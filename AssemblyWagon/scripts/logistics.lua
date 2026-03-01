local Logistics = {}
local log_debug = function(_) end

function Logistics.init(deps)
    if deps and deps.log_debug then
        log_debug = deps.log_debug
    end
end

-- 物流循环间隔（tick）
local NTH_TICK = 10
-- 每次 on_nth_tick 处理的绑定对预算（分片核心参数）
local MAX_PAIRS_PER_STEP = 80
-- 每个绑定对单轮最多执行的搬运操作次数（防止单个车厢独占预算）
local MAX_OPS_PER_PAIR = 4
-- 清仓模式下每个绑定对单轮最多执行的搬运操作次数（提高切配方清仓收敛速度）
local MAX_DRAIN_OPS_PER_PAIR = 8

---初始化物流状态存储
function Logistics.on_init()
    storage.aw_logistics = storage.aw_logistics or {}
    storage.aw_logistics.recipe_cache = storage.aw_logistics.recipe_cache or {}
    storage.aw_logistics.sleep_until = storage.aw_logistics.sleep_until or {}
    storage.aw_logistics.drain_mode = storage.aw_logistics.drain_mode or {}
    storage.aw_logistics.drain_full_warn_until = storage.aw_logistics.drain_full_warn_until or {}
    storage.aw_logistics.cursor = storage.aw_logistics.cursor or 1

    -- 初版路径：直接初始化活跃列表结构，不做旧存档重建
    storage.aw_active_wagons = storage.aw_active_wagons or {}
    storage.aw_active_index = storage.aw_active_index or {}
end

-- 从活跃列表移除车厢（本地兜底，防止失效绑定残留）
-- @param wagon_unit 车厢 unit_number
local function remove_active_wagon(wagon_unit)
    if not (wagon_unit and storage.aw_active_wagons and storage.aw_active_index) then
        return
    end

    local list = storage.aw_active_wagons
    local index_map = storage.aw_active_index
    local idx = index_map[wagon_unit]
    if not idx then
        return
    end

    local last_idx = #list
    local last_unit = list[last_idx]

    list[idx] = last_unit
    list[last_idx] = nil
    index_map[wagon_unit] = nil

    if last_unit and last_unit ~= wagon_unit then
        index_map[last_unit] = idx
    end
end

---获取货运车厢库存
-- @param wagon 车厢实体
-- @return 车厢库存
local function get_wagon_inventory(wagon)
    if not (wagon and wagon.valid) then
        return nil
    end
    return wagon.get_inventory(defines.inventory.cargo_wagon)
end

---获取组装机输入库存
-- @param assembler 组装机实体
-- @return 组装机输入库存
local function get_assembler_input(assembler)
    if not (assembler and assembler.valid) then
        return nil
    end
    return assembler.get_inventory(defines.inventory.crafter_input)
end

---获取组装机输出库存
-- @param assembler 组装机实体
-- @return 组装机输出库存
local function get_assembler_output(assembler)
    if not (assembler and assembler.valid) then
        return nil
    end
    return assembler.get_inventory(defines.inventory.crafter_output)
end

---获取组装机垃圾库存
-- @param assembler 组装机实体
-- @return 组装机垃圾库存
local function get_assembler_trash(assembler)
    if not (assembler and assembler.valid) then
        return nil
    end
    return assembler.get_inventory(defines.inventory.crafter_trash)
end

---获取组装机弹出库存（配方切换等场景）
-- @param assembler 组装机实体
-- @return 组装机弹出库存
local function get_assembler_dump(assembler)
    if not (assembler and assembler.valid) then
        return nil
    end
    return assembler.get_inventory(defines.inventory.assembling_machine_dump)
end

---获取当前配方（兼容不同 API 读取方式）
-- @param assembler 组装机实体
-- @return 当前配方
local function get_current_recipe(assembler)
    if not (assembler and assembler.valid) then
        return nil
    end

    if assembler.get_recipe then
        return assembler.get_recipe()
    end

    return assembler.recipe
end

local function move_outputs_to_wagon(output_inv, wagon_inv, max_ops)
    local moved_ops = 0
    local blocked = false

    -- 改为按槽位读取，避免 get_contents 在品质场景下结构差异导致 remove 失败
    for slot_index = 1, #output_inv do
        if moved_ops >= max_ops then
            break
        end

        local stack = output_inv[slot_index]
        if stack and stack.valid_for_read then
            local stack_name = stack.name
            local stack_quality = stack.quality
            local move_count = math.min(stack.count, 100)

            local removed = output_inv.remove({
                name = stack_name,
                count = move_count,
                quality = stack_quality,
            })

            if removed > 0 then
                local inserted = wagon_inv.insert({
                    name = stack_name,
                    count = removed,
                    quality = stack_quality,
                })

                if inserted < removed then
                    output_inv.insert({
                        name = stack_name,
                        count = (removed - inserted),
                        quality = stack_quality,
                    })
                    if inserted == 0 then
                        blocked = true
                    end
                end

                moved_ops = moved_ops + 1
            end
        end
    end

    return moved_ops, blocked
end

-- 将组装机输入槽中的物品退回车厢（用于切配方后的旧料清仓）
-- @param input_inv 组装机输入库存
-- @param wagon_inv 车厢库存
-- @param max_ops 本轮最多搬运次数
-- @return moved_ops 实际执行的搬运次数
local function move_inventory_to_wagon(source_inv, wagon_inv, max_ops)
    local moved_ops = 0
    local blocked = false

    if not source_inv then
        return moved_ops, blocked
    end

    for slot_index = 1, #source_inv do
        if moved_ops >= max_ops then
            break
        end

        local stack = source_inv[slot_index]
        if stack and stack.valid_for_read then
            local stack_name = stack.name
            local stack_quality = stack.quality
            local move_count = math.min(stack.count, 100)

            local removed = source_inv.remove({
                name = stack_name,
                count = move_count,
                quality = stack_quality,
            })

            if removed > 0 then
                local inserted = wagon_inv.insert({
                    name = stack_name,
                    count = removed,
                    quality = stack_quality,
                })

                if inserted < removed then
                    source_inv.insert({
                        name = stack_name,
                        count = (removed - inserted),
                        quality = stack_quality,
                    })
                    if inserted == 0 then
                        blocked = true
                    end
                end

                moved_ops = moved_ops + 1
            end
        end
    end

    return moved_ops, blocked
end

local function move_inputs_to_wagon(input_inv, wagon_inv, max_ops)
    return move_inventory_to_wagon(input_inv, wagon_inv, max_ops)
end

local function move_trash_to_wagon(trash_inv, wagon_inv, max_ops)
    return move_inventory_to_wagon(trash_inv, wagon_inv, max_ops)
end

local function move_dump_to_wagon(dump_inv, wagon_inv, max_ops)
    return move_inventory_to_wagon(dump_inv, wagon_inv, max_ops)
end

local function inventory_has_items(inv)
    if not inv then
        return false
    end
    return next(inv.get_contents()) ~= nil
end

local function get_wagon_gps(wagon)
    if not (wagon and wagon.valid and wagon.position and wagon.surface and wagon.surface.name) then
        return ""
    end

    local x = math.floor((wagon.position.x or 0) + 0.5)
    local y = math.floor((wagon.position.y or 0) + 0.5)
    return "[gps=" .. tostring(x) .. "," .. tostring(y) .. "," .. wagon.surface.name .. "]"
end

local function print_drain_full_warning(tick, wagon_unit, wagon)
    local warn_until = storage.aw_logistics.drain_full_warn_until[wagon_unit] or 0
    if tick < warn_until then
        return
    end

    if game then
        game.print({ "messages.aw-wagon-full-cannot-return-gps", get_wagon_gps(wagon) })
    end
    storage.aw_logistics.drain_full_warn_until[wagon_unit] = tick + 300
end

---按配方需求从车厢投喂原料到组装机输入
-- @param recipe 当前配方
-- @param wagon_inv 车厢库存
-- @param input_inv 组装机输入库存
-- @param max_ops 本轮最多投喂次数
-- @return moved_ops 实际执行的投喂次数
local function feed_ingredients(recipe, wagon_inv, input_inv, max_ops)
    local moved_ops = 0

    for _, ingredient in pairs(recipe.ingredients) do
        if moved_ops >= max_ops then
            break
        end

        -- 仅处理固体物品，流体配方在 MVP 阶段跳过
        if (ingredient.type == nil or ingredient.type == "item") and ingredient.name and ingredient.amount then
            local current_count = input_inv.get_item_count(ingredient.name)
            local desired_count = math.max(math.ceil(ingredient.amount * 2), ingredient.amount)
            local need_count = desired_count - current_count

            if need_count > 0 then
                local removed = wagon_inv.remove({ name = ingredient.name, count = need_count })
                if removed > 0 then
                    local inserted = input_inv.insert({ name = ingredient.name, count = removed })
                    if inserted < removed then
                        wagon_inv.insert({ name = ingredient.name, count = (removed - inserted) })
                    end
                    moved_ops = moved_ops + 1
                end
            end
        end
    end

    return moved_ops
end

---处理单个“车厢-组装机”绑定对
-- @param wagon_unit 车厢 unit_number
-- @param wagon 车厢实体
-- @param assembler 组装机实体
-- @param tick 当前 tick
local function process_pair(wagon_unit, wagon, assembler, tick)
    if not (wagon and wagon.valid and assembler and assembler.valid) then
        storage.wagon_to_assembler[wagon_unit] = nil
        storage.aw_logistics.recipe_cache[wagon_unit] = nil
        storage.aw_logistics.sleep_until[wagon_unit] = nil
        storage.aw_logistics.drain_mode[wagon_unit] = nil
        storage.aw_logistics.drain_full_warn_until[wagon_unit] = nil
        remove_active_wagon(wagon_unit)
        return
    end

    -- 睡眠中的绑定对暂不处理
    local sleep_until = storage.aw_logistics.sleep_until[wagon_unit]
    if sleep_until and tick < sleep_until then
        return
    end

    local wagon_inv = get_wagon_inventory(wagon)
    local input_inv = get_assembler_input(assembler)
    local output_inv = get_assembler_output(assembler)
    local trash_inv = get_assembler_trash(assembler)
    local dump_inv = get_assembler_dump(assembler)
    if not (wagon_inv and input_inv and output_inv) then
        return
    end

    local recipe = get_current_recipe(assembler)
    local recipe_name = recipe and recipe.name or nil
    local cached_recipe = storage.aw_logistics.recipe_cache[wagon_unit]
    local recipe_changed = (cached_recipe ~= recipe_name)

    if recipe_changed then
        storage.aw_logistics.recipe_cache[wagon_unit] = recipe_name
        storage.aw_logistics.drain_mode[wagon_unit] = true
        storage.aw_logistics.sleep_until[wagon_unit] = nil

        if AssemblyWagon.DEBUG_MODE_ENABLED then
            log_debug("物流: 检测到配方切换，进入清仓模式 wagon=" .. tostring(wagon_unit) .. ", old=" .. tostring(cached_recipe) .. ", new=" .. tostring(recipe_name))
        end
    end

    -- 清仓模式：切配方后优先把组装机内所有可访问物品（输出+输入+垃圾+弹出）退回车厢
    if storage.aw_logistics.drain_mode[wagon_unit] then
        local moved_ops = 0
        local moved_out_ops, out_blocked = move_outputs_to_wagon(output_inv, wagon_inv, MAX_DRAIN_OPS_PER_PAIR)
        moved_ops = moved_ops + moved_out_ops

        local remain_ops = MAX_DRAIN_OPS_PER_PAIR - moved_ops
        local moved_in_ops = 0
        local in_blocked = false
        if remain_ops > 0 then
            moved_in_ops, in_blocked = move_inputs_to_wagon(input_inv, wagon_inv, remain_ops)
            moved_ops = moved_ops + moved_in_ops
        end

        remain_ops = MAX_DRAIN_OPS_PER_PAIR - moved_ops
        local moved_trash_ops = 0
        local trash_blocked = false
        if remain_ops > 0 then
            moved_trash_ops, trash_blocked = move_trash_to_wagon(trash_inv, wagon_inv, remain_ops)
            moved_ops = moved_ops + moved_trash_ops
        end

        remain_ops = MAX_DRAIN_OPS_PER_PAIR - moved_ops
        local moved_dump_ops = 0
        local dump_blocked = false
        if remain_ops > 0 then
            moved_dump_ops, dump_blocked = move_dump_to_wagon(dump_inv, wagon_inv, remain_ops)
            moved_ops = moved_ops + moved_dump_ops
        end

        local has_output = inventory_has_items(output_inv)
        local has_input = inventory_has_items(input_inv)
        local has_trash = inventory_has_items(trash_inv)
        local has_dump = inventory_has_items(dump_inv)

        if out_blocked or in_blocked or trash_blocked or dump_blocked then
            print_drain_full_warning(tick, wagon_unit, wagon)
        end

        if AssemblyWagon.DEBUG_MODE_ENABLED then
            if moved_ops > 0 then
                log_debug("物流: 清仓退料 wagon=" .. tostring(wagon_unit) .. ", out_ops=" .. tostring(moved_out_ops) .. ", in_ops=" .. tostring(moved_in_ops) .. ", trash_ops=" .. tostring(moved_trash_ops) .. ", dump_ops=" .. tostring(moved_dump_ops))
            end
            if has_output or has_input or has_trash or has_dump then
                log_debug("物流: 清仓未完成 wagon=" .. tostring(wagon_unit) .. ", has_output=" .. tostring(has_output) .. ", has_input=" .. tostring(has_input) .. ", has_trash=" .. tostring(has_trash) .. ", has_dump=" .. tostring(has_dump))
            end
        end

        if has_output or has_input or has_trash or has_dump then
            storage.aw_logistics.sleep_until[wagon_unit] = tick + 20
            return
        end

        storage.aw_logistics.drain_mode[wagon_unit] = nil
        storage.aw_logistics.drain_full_warn_until[wagon_unit] = nil
        if AssemblyWagon.DEBUG_MODE_ENABLED then
            log_debug("物流: 清仓完成 wagon=" .. tostring(wagon_unit))
        end
    end

    -- 无配方：长睡眠，降低空转（清仓流程已在前面执行）
    if not recipe then
        storage.aw_logistics.sleep_until[wagon_unit] = tick + 300
        return
    end

    -- 第 1 阶段：先清输出，避免产物堆积
    local moved_out_ops, blocked = move_outputs_to_wagon(output_inv, wagon_inv, MAX_OPS_PER_PAIR)

    if AssemblyWagon.DEBUG_MODE_ENABLED then
        local output_contents = output_inv.get_contents()
        if moved_out_ops > 0 then
            log_debug("物流: 成品已回仓 wagon=" .. tostring(wagon_unit) .. ", ops=" .. tostring(moved_out_ops))
        elseif next(output_contents) ~= nil then
            log_debug("物流: 检测到输出库存有物品但本轮未搬运 wagon=" .. tostring(wagon_unit))
        end
    end

    -- 输出阻塞：短睡眠，等待车厢腾挪
    if blocked then
        storage.aw_logistics.sleep_until[wagon_unit] = tick + 60
        return
    end

    -- 第 2 阶段：按需投喂（剩余预算）
    local remain_ops = MAX_OPS_PER_PAIR - moved_out_ops
    if remain_ops > 0 then
        local moved_in_ops = feed_ingredients(recipe, wagon_inv, input_inv, remain_ops)
        if moved_in_ops == 0 and moved_out_ops == 0 then
            -- 本轮无任何搬运行为，短睡眠避免空转
            storage.aw_logistics.sleep_until[wagon_unit] = tick + 30
        else
            storage.aw_logistics.sleep_until[wagon_unit] = nil
        end
    end
end

---物流主循环（on_nth_tick）
-- @param event on_nth_tick 事件数据
function Logistics.on_nth_tick(event)
    if not (storage and storage.wagon_to_assembler and storage.aw_logistics and storage.aw_active_wagons) then
        return
    end

    local tick = event.tick or game.tick

    local active_units = storage.aw_active_wagons
    local total = #active_units
    if total == 0 then
        storage.aw_logistics.cursor = 1
        return
    end

    local cursor = storage.aw_logistics.cursor or 1
    if cursor > total then
        cursor = 1
    end

    local processed = 0
    local scan_limit = MAX_PAIRS_PER_STEP * 3
    local scanned = 0

    while processed < MAX_PAIRS_PER_STEP and #active_units > 0 and scanned < scan_limit do
        scanned = scanned + 1

        local size = #active_units
        if size == 0 then
            break
        end

        if cursor > size then
            cursor = 1
        end

        local wagon_unit = active_units[cursor]
        local assembler = wagon_unit and storage.wagon_to_assembler[wagon_unit] or nil

        if not (wagon_unit and assembler and assembler.valid) then
            if wagon_unit then
                storage.wagon_to_assembler[wagon_unit] = nil
                storage.aw_logistics.recipe_cache[wagon_unit] = nil
                storage.aw_logistics.sleep_until[wagon_unit] = nil
                storage.aw_logistics.drain_mode[wagon_unit] = nil
                storage.aw_logistics.drain_full_warn_until[wagon_unit] = nil
                remove_active_wagon(wagon_unit)
            else
                cursor = cursor + 1
            end
        else
            local wagon = storage.assembler_to_wagon and storage.assembler_to_wagon[assembler.unit_number] or nil
            process_pair(wagon_unit, wagon, assembler, tick)
            processed = processed + 1
            cursor = cursor + 1
        end
    end

    if cursor > #active_units and #active_units > 0 then
        cursor = 1
    end
    storage.aw_logistics.cursor = cursor
end

---对外暴露 tick 间隔，供 control.lua 注册
-- @return 物流循环间隔 tick 数
function Logistics.get_nth_tick()
    return NTH_TICK
end

return Logistics

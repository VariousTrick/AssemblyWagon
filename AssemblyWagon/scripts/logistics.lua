local Logistics = {}

-- 物流循环间隔（tick）
local NTH_TICK = 10
-- 每次 on_nth_tick 处理的绑定对预算（分片核心参数）
local MAX_PAIRS_PER_STEP = 80
-- 每个绑定对单轮最多执行的搬运操作次数（防止单个车厢独占预算）
local MAX_OPS_PER_PAIR = 4

---初始化物流状态存储
function Logistics.on_init()
    storage.aw_logistics = storage.aw_logistics or {}
    storage.aw_logistics.recipe_cache = storage.aw_logistics.recipe_cache or {}
    storage.aw_logistics.sleep_until = storage.aw_logistics.sleep_until or {}
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
    return assembler.get_inventory(defines.inventory.assembling_machine_input)
end

---获取组装机输出库存
-- @param assembler 组装机实体
-- @return 组装机输出库存
local function get_assembler_output(assembler)
    if not (assembler and assembler.valid) then
        return nil
    end
    return assembler.get_inventory(defines.inventory.assembling_machine_output)
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

---将组装机输出尽量搬到车厢
-- @param output_inv 组装机输出库存
-- @param wagon_inv 车厢库存
-- @param max_ops 本轮最多搬运次数
-- @return moved_ops 实际执行的搬运次数
-- @return blocked 是否出现“有产物但无法塞入车厢”的阻塞
local function move_single_output_entry(output_inv, wagon_inv, item_key, quality_key, raw_count)
    local name = nil
    local quality = nil

    if type(item_key) == "string" then
        name = item_key
    elseif type(item_key) == "table" then
        name = item_key.name
        quality = item_key.quality
    end

    if type(quality_key) == "string" then
        quality = quality_key
    end

    if not (name and type(raw_count) == "number" and raw_count > 0) then
        return 0, false
    end

    local request = {
        name = name,
        count = math.min(raw_count, 100),
    }
    if quality then
        request.quality = quality
    end

    local removed = output_inv.remove(request)
    if removed <= 0 then
        return 0, false
    end

    local inserted = wagon_inv.insert({
        name = name,
        count = removed,
        quality = quality,
    })

    if inserted < removed then
        output_inv.insert({
            name = name,
            count = (removed - inserted),
            quality = quality,
        })
    end

    return 1, inserted == 0
end

local function move_outputs_to_wagon(output_inv, wagon_inv, max_ops)
    local moved_ops = 0
    local blocked = false

    local contents = output_inv.get_contents()
    for item_key, item_count in pairs(contents) do
        if moved_ops >= max_ops then
            break
        end

        if type(item_count) == "number" then
            local op_used, is_blocked = move_single_output_entry(output_inv, wagon_inv, item_key, nil, item_count)
            moved_ops = moved_ops + op_used
            blocked = blocked or is_blocked
        elseif type(item_count) == "table" then
            -- 兼容品质分层统计：value 可能是 { normal = n1, uncommon = n2, ... }
            for quality_key, quality_count in pairs(item_count) do
                if moved_ops >= max_ops then
                    break
                end

                local op_used, is_blocked = move_single_output_entry(output_inv, wagon_inv, item_key, quality_key, quality_count)
                moved_ops = moved_ops + op_used
                blocked = blocked or is_blocked
            end
        end
    end

    return moved_ops, blocked
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
    if not (wagon_inv and input_inv and output_inv) then
        return
    end

    -- 第 1 阶段：先清输出，避免产物堆积
    local moved_out_ops, blocked = move_outputs_to_wagon(output_inv, wagon_inv, MAX_OPS_PER_PAIR)

    local recipe = get_current_recipe(assembler)
    local recipe_name = recipe and recipe.name or nil
    local cached_recipe = storage.aw_logistics.recipe_cache[wagon_unit]

    if cached_recipe ~= recipe_name then
        -- 配方变化时重置睡眠并刷新缓存
        storage.aw_logistics.recipe_cache[wagon_unit] = recipe_name
        storage.aw_logistics.sleep_until[wagon_unit] = nil
    end

    -- 无配方：长睡眠，降低空转
    if not recipe then
        storage.aw_logistics.sleep_until[wagon_unit] = tick + 300
        return
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

local builder = {}
local VoidPool = require("scripts.void_pool")

-- 1. 初始化数据存储，准备一个字典用来记录【车厢】和【组装机】的一一对应关系
function builder.on_init()
    storage.wagon_to_assembler = storage.wagon_to_assembler or {}
    -- 反向字典，方便通过组装机找车厢
    storage.assembler_to_wagon = storage.assembler_to_wagon or {}
    storage.wagon_to_slot = storage.wagon_to_slot or {}
    VoidPool.on_init()
end

-- 2. 建造事件处理逻辑
function builder.on_entity_created(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid) then return end

    -- 如果建出来的是我们的“组装车厢”
    if entity.name == "assembly-wagon" then
        local slot_id, surface, position = VoidPool.allocate_slot()

        -- 在虚空地表的专属槽位创建伴生组装机
        local assembler = surface.create_entity({
            name = "wagon-assembler",
            position = position,
            force = entity.force,
            create_build_effect_smoke = false -- 不产生建造烟雾
        })

        if assembler then
            -- 绑定死契：把组装机存入字典，钥匙是车厢的物理身份证 (unit_number)
            storage.wagon_to_assembler[entity.unit_number] = assembler
            -- 记录反向绑定
            storage.assembler_to_wagon[assembler.unit_number] = entity
            -- 记录槽位绑定，用于回收
            storage.wagon_to_slot[entity.unit_number] = slot_id
        else
            -- 创建失败时立即归还槽位
            VoidPool.release_slot(slot_id)
        end
    end
end

-- 3. 拆除/死亡事件处理逻辑
function builder.on_entity_destroyed(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end

    if entity.name == "assembly-wagon" then
        local assembler = storage.wagon_to_assembler[entity.unit_number]

        -- 如果它的伴生组装机还活着，就把它干掉
        if assembler and assembler.valid then
            -- 擦除反向记录
            storage.assembler_to_wagon[assembler.unit_number] = nil
            assembler.destroy()
        end

        -- 从字典里擦除这条记录，防止内存泄漏
        storage.wagon_to_assembler[entity.unit_number] = nil
        local slot_id = storage.wagon_to_slot[entity.unit_number]
        storage.wagon_to_slot[entity.unit_number] = nil
        VoidPool.release_slot(slot_id)
    elseif entity.name == "wagon-assembler" then
        local wagon = storage.assembler_to_wagon[entity.unit_number]
        if wagon and wagon.valid and wagon.unit_number then
            storage.wagon_to_assembler[wagon.unit_number] = nil
            local slot_id = storage.wagon_to_slot[wagon.unit_number]
            storage.wagon_to_slot[wagon.unit_number] = nil
            VoidPool.release_slot(slot_id)
        end

        storage.assembler_to_wagon[entity.unit_number] = nil
    end
end

-- 4. 兼容接口：当外部模组替换车厢实体时，转移绑定关系
-- 参数必须是有效的 assembly-wagon 实体
function builder.transfer_binding(old_wagon, new_wagon)
    if not (old_wagon and old_wagon.valid and new_wagon and new_wagon.valid) then
        return false
    end

    if old_wagon.name ~= "assembly-wagon" or new_wagon.name ~= "assembly-wagon" then
        return false
    end

    local old_unit = old_wagon.unit_number
    local new_unit = new_wagon.unit_number
    if not (old_unit and new_unit) then
        return false
    end

    local assembler = storage.wagon_to_assembler[old_unit]
    local slot_id = storage.wagon_to_slot[old_unit]

    -- 先清理旧键，避免并存
    storage.wagon_to_assembler[old_unit] = nil
    storage.wagon_to_slot[old_unit] = nil

    if assembler and assembler.valid then
        storage.wagon_to_assembler[new_unit] = assembler
        storage.assembler_to_wagon[assembler.unit_number] = new_wagon
    end

    if slot_id then
        storage.wagon_to_slot[new_unit] = slot_id
    end

    return true
end

return builder
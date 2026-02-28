local lifecycle = {}

-- 1. 初始化数据存储，准备一个字典用来记录【车厢】和【组装机】的一一对应关系
function lifecycle.on_init()
    storage.wagon_to_assembler = storage.wagon_to_assembler or {}
    -- 反向字典，方便通过组装机找车厢
    storage.assembler_to_wagon = storage.assembler_to_wagon or {}
end

-- 2. 建造事件处理逻辑
function lifecycle.on_entity_created(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid) then return end

    -- 如果建出来的是我们的“组装车厢”
    if entity.name == "assembly-wagon" then
        local surface = entity.surface
        local pos = entity.position

        -- 在它的正上方 20 格，硬刷出一个组装机
        local assembler = surface.create_entity({
            name = "wagon-assembler",
            position = { x = pos.x, y = pos.y - 20 },
            force = entity.force,
            create_build_effect_smoke = false -- 不产生建造烟雾
        })

        if assembler then
            -- 绑定死契：把组装机存入字典，钥匙是车厢的物理身份证 (unit_number)
            storage.wagon_to_assembler[entity.unit_number] = assembler
            -- 记录反向绑定
            storage.assembler_to_wagon[assembler.unit_number] = entity
        end
    end
end

-- 3. 拆除/死亡事件处理逻辑
function lifecycle.on_entity_destroyed(event)
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
    end
end

return lifecycle
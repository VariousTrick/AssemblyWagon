local entity = table.deepcopy(data.raw["assembling-machine"]["assembling-machine-3"])

entity.name = "wagon-assembler"
-- 移除掉落物，防止玩家挖掉它获取免费的组装机
entity.minable = nil 

-- 让实体变成无敌状态（不会被虫子咬爆）
entity.destructible = false

-- 让它不需要接电线就能全速运转
entity.energy_source = { type = "void" }

-- Factorio 2.0 标准的模块彻底阉割法
entity.module_slots = 0                     -- 基础槽位直接设为 0（2.0新版属性名）
entity.allowed_effects = nil                -- 禁用所有模块效果
entity.quality_affects_module_slots = false -- 禁止品质系统为它凭空增加槽位！


data:extend({entity})
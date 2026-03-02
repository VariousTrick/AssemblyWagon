local entity = table.deepcopy(data.raw["cargo-wagon"]["cargo-wagon"])

entity.name = "assembly-wagon"
entity.minable.result = "assembly-wagon" -- 挖掉后掉落我们自定义的物品
entity.inventory_size = 200 -- 基础品质库存为 200（传奇按 2.5x 自动到 500）
entity.quality_affects_inventory_size = true -- 启用品质对库存容量的影响

data:extend({entity})
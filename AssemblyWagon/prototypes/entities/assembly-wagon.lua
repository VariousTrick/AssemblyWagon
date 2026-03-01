local entity = table.deepcopy(data.raw["cargo-wagon"]["cargo-wagon"])

entity.name = "assembly-wagon"
entity.minable.result = "assembly-wagon" -- 挖掉后掉落我们自定义的物品
entity.inventory_size = 500 -- 车厢库存固定扩展为 500 格

data:extend({entity})
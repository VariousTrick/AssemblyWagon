local item = table.deepcopy(data.raw["item-with-entity-data"]["cargo-wagon"])

item.name = "assembly-wagon"
item.place_result = "assembly-wagon"
item.order = "a[train-system]-c[assembly-wagon]" -- 放在原版货车厢的旁边
-- item.icon 暂时沿用原版的，不做修改

data:extend({item})
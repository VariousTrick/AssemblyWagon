local recipe = table.deepcopy(data.raw["recipe"]["cargo-wagon"])

recipe.name = "assembly-wagon"
recipe.results = {{type = "item", name = "assembly-wagon", amount = 1}}
-- 制造材料：1个货车厢 + 1个组装机3型
recipe.ingredients = {
    {type = "item", name = "cargo-wagon", amount = 1},
    {type = "item", name = "assembling-machine-3", amount = 1}
}

data:extend({recipe})
-- =================================================================================================
-- Assembly Wagon - control.lua
-- =================================================================================================

local builder = require("scripts.builder")
local gui = require("scripts.gui")
local aw_remote = require("scripts.remote")

-- 注册对外 remote 接口（供其他模组调用）
aw_remote.init({
    Builder = builder,
})

-- 初始化
script.on_init(function()
    builder.on_init()
    gui.on_init()
end)

script.on_configuration_changed(function()
    builder.on_init()
    gui.on_init()
end)

-- 实体过滤器：只监听本模组相关实体
local aw_filters = {
    { filter = "name", name = "assembly-wagon" },
    { filter = "name", name = "wagon-assembler" },
}

-- 生命周期事件（按事件类型拆分，兼容过滤器限制）
script.on_event(defines.events.on_built_entity, builder.on_entity_created, aw_filters)
script.on_event(defines.events.on_robot_built_entity, builder.on_entity_created, aw_filters)
script.on_event({ defines.events.script_raised_built, defines.events.script_raised_revive }, builder.on_entity_created)

script.on_event(defines.events.on_player_mined_entity, builder.on_entity_destroyed, aw_filters)
script.on_event(defines.events.on_robot_mined_entity, builder.on_entity_destroyed, aw_filters)
script.on_event(defines.events.on_entity_died, builder.on_entity_destroyed, aw_filters)
script.on_event(defines.events.script_raised_destroy, builder.on_entity_destroyed)

-- GUI 事件
script.on_event(defines.events.on_player_created, gui.on_player_created)
script.on_event(defines.events.on_gui_opened, gui.on_gui_opened)
script.on_event(defines.events.on_gui_click, gui.on_gui_click)
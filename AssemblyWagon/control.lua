-- =================================================================================================
-- Assembly Wagon - control.lua
-- =================================================================================================

local lifecycle = require("scripts.lifecycle")
local gui = require("scripts.gui")

-- 初始化
script.on_init(function()
    lifecycle.on_init()
    gui.on_init()
end)

script.on_configuration_changed(function()
    lifecycle.on_init()
    gui.on_init()
end)

-- 生命周期事件
local build_events = { defines.events.on_built_entity, defines.events.on_robot_built_entity, defines.events.script_raised_built, defines.events.script_raised_revive }
script.on_event(build_events, lifecycle.on_entity_created)

local destroy_events = { defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity, defines.events.on_entity_died, defines.events.script_raised_destroy }
script.on_event(destroy_events, lifecycle.on_entity_destroyed)

-- GUI 事件
script.on_event(defines.events.on_player_created, gui.on_player_created)
script.on_event(defines.events.on_gui_opened, gui.on_gui_opened)
script.on_event(defines.events.on_gui_click, gui.on_gui_click)
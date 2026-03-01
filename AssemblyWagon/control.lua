-- =================================================================================================
-- Assembly Wagon - control.lua
-- =================================================================================================

local builder = require("scripts.builder")
local gui = require("scripts.gui")
local aw_remote = require("scripts.remote")
local logistics = require("scripts.logistics")

-- 将调试开关挂载到全局表上（与 RiftRail 风格一致）
AssemblyWagon = AssemblyWagon or {}

local function refresh_debug_flag()
    AssemblyWagon.DEBUG_MODE_ENABLED = settings.global["assemblywagon-debug-mode"].value
end

-- 定义纯日志函数：只有开启调试时才输出
local function log_debug(msg)
    if not AssemblyWagon.DEBUG_MODE_ENABLED then
        return
    end
    log("[AssemblyWagon] " .. msg)
    if game then
        game.print("[AssemblyWagon] " .. msg)
    end
end

refresh_debug_flag()

if builder.init then
    builder.init({
        log_debug = log_debug,
    })
end

if logistics.init then
    logistics.init({
        log_debug = log_debug,
    })
end

-- 注册对外 remote 接口（供其他模组调用）
aw_remote.init({
    Builder = builder,
    log_debug = log_debug,
})

-- 初始化
script.on_init(function()
    refresh_debug_flag()
    builder.on_init()
    gui.on_init()
    logistics.on_init()
end)

script.on_configuration_changed(function()
    refresh_debug_flag()
    builder.on_init()
    gui.on_init()
    logistics.on_init()
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
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event and event.setting == "assemblywagon-debug-mode" then
        refresh_debug_flag()
    end
end)

-- 物流循环（按固定间隔执行）
script.on_nth_tick(logistics.get_nth_tick(), logistics.on_nth_tick)
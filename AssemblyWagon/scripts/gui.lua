local gui = {}

-- 为玩家创建两个静默挂载的“相对 GUI”面板
local function setup_player_guis(player)
    -- 1. 挂载在【我们的组装机】上方的按钮
    if not player.gui.relative["aw_btn_to_wagon"] then
        local frame_wagon = player.gui.relative.add{
            type = "frame",
            name = "aw_btn_to_wagon",
            -- 魔法：设为 top，按钮会完美贴合在原生界面的正上方！
            anchor = {
                gui = defines.relative_gui_type.assembling_machine_gui,
                position = defines.relative_gui_position.top,
                name = "wagon-assembler" 
            }
        }
        -- 正确的嵌套添加方式
        frame_wagon.add{
            type = "button", 
            name = "aw_action_to_wagon", 
            caption = {"gui.aw-open-wagon"},
        }
    end

    -- 2. 挂载在【我们的车厢】上方的按钮
    if not player.gui.relative["aw_btn_to_assembler"] then
        local frame_assembler = player.gui.relative.add{
            type = "frame",
            name = "aw_btn_to_assembler",
            anchor = {
                -- 车厢界面在底层就是一个带轮子的箱子！
                gui = defines.relative_gui_type.container_gui, 
                position = defines.relative_gui_position.top,
                name = "assembly-wagon"
            }
        }
        -- 正确的嵌套添加方式
        frame_assembler.add{
            type = "button", 
            name = "aw_action_to_assembler", 
            caption = {"gui.aw-open-assembler"},
        }
    end
end

-- 初始化时给所有已存在玩家发按钮（只发一次，受用终身）
function gui.on_init()
    for _, player in pairs(game.players) do
        setup_player_guis(player)
    end
end

-- 新玩家加入服务器时，给萌新发按钮
function gui.on_player_created(event)
    setup_player_guis(game.get_player(event.player_index))
end

--[[ -- 【核心】：狸猫换太子 & 通行证检查
function gui.on_gui_opened(event)
    local player = game.get_player(event.player_index)
    local entity = event.entity

    if not (entity and entity.valid) then return end

    if entity.name == "assembly-wagon" then
        if storage.allow_wagon_open[player.index] then
            -- 玩家有通行证（点了切换按钮），放行！并销毁通行证
            storage.allow_wagon_open[player.index] = nil
        else
            -- 玩家直接在地图上点的！强行拦截，转交焦点到组装机
            local assembler = storage.wagon_to_assembler[entity.unit_number]
            if assembler and assembler.valid then
                player.opened = assembler
            end
        end
    end
end ]]

-- 监听按钮点击事件
function gui.on_gui_click(event)
    local player = game.get_player(event.player_index)
    local element = event.element
    if not element then return end

    -- 情况 A：在组装机界面，点击了“打开车厢库存”
    if element.name == "aw_action_to_wagon" then
        local opened_entity = player.opened
        if opened_entity and opened_entity.name == "wagon-assembler" then
            local wagon = storage.assembler_to_wagon[opened_entity.unit_number]
            if wagon and wagon.valid then
                player.opened = wagon -- 直接切，毫无顾忌！
            end
        end
    end

    -- 情况 B：在车厢界面，点击了“打开生产面板”
    if element.name == "aw_action_to_assembler" then
        local opened_entity = player.opened
        if opened_entity and opened_entity.name == "assembly-wagon" then
            local assembler = storage.wagon_to_assembler[opened_entity.unit_number]
            if assembler and assembler.valid then
                player.opened = assembler -- 直接切，毫无顾忌！
            end
        end
    end
end

return gui
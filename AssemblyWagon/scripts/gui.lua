local gui = {}

local function open_entity_gui(player, target)
	if not (player and player.valid and target and target.valid) then
		return
	end

	-- 先清空再打开，避免某些情况下同 tick 切换界面不刷新
	player.opened = nil
	player.opened = target
end

local function ensure_remote_view_near(player, anchor_entity)
	if not (player and player.valid and anchor_entity and anchor_entity.valid) then
		return
	end

	player.opened = nil
	player.set_controller({
		type = defines.controllers.remote,
		position = anchor_entity.position,
		surface = anchor_entity.surface,
		zoom = player.zoom,
	})
end

-- 为玩家创建两个静默挂载的“相对 GUI”面板
local function setup_player_guis(player)
	-- 1. 挂载在【我们的组装机】上方的按钮
	if not player.gui.relative["aw_btn_to_wagon"] then
		local frame_wagon = player.gui.relative.add({
			type = "frame",
			name = "aw_btn_to_wagon",
			-- 魔法：设为 top，按钮会完美贴合在原生界面的正上方！
			anchor = {
				gui = defines.relative_gui_type.assembling_machine_gui,
				position = defines.relative_gui_position.top,
				name = "wagon-assembler",
			},
		})
		-- 正确的嵌套添加方式
		frame_wagon.add({
			type = "button",
			name = "aw_action_to_wagon",
			caption = { "gui.aw-open-wagon" },
		})
	end

	-- 2. 挂载在【我们的车厢】上方的按钮
	if not player.gui.relative["aw_btn_to_assembler"] then
		local frame_assembler = player.gui.relative.add({
			type = "frame",
			name = "aw_btn_to_assembler",
			anchor = {
				-- 车厢界面在底层就是一个带轮子的箱子！
				gui = defines.relative_gui_type.container_gui,
				position = defines.relative_gui_position.top,
				name = "assembly-wagon",
			},
		})
		-- 正确的嵌套添加方式
		frame_assembler.add({
			type = "button",
			name = "aw_action_to_assembler",
			caption = { "gui.aw-open-assembler" },
		})
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

-- 监听按钮点击事件
function gui.on_gui_click(event)
	local player = game.get_player(event.player_index)
	local element = event.element
	if not element then
		return
	end

	-- 情况 A：在组装机界面，点击了“打开车厢库存”
	if element.name == "aw_action_to_wagon" then
		local opened_entity = player.opened
		if opened_entity and opened_entity.name == "wagon-assembler" then
			local wagon = storage.assembler_to_wagon[opened_entity.unit_number]
			open_entity_gui(player, wagon)
		end
	end

	-- 情况 B：在车厢界面，点击了“打开生产面板”
	if element.name == "aw_action_to_assembler" then
		local opened_entity = player.opened
		if opened_entity and opened_entity.name == "assembly-wagon" then
			local assembler = storage.wagon_to_assembler[opened_entity.unit_number]
			ensure_remote_view_near(player, assembler)
			open_entity_gui(player, assembler)
		end
	end
end

return gui

# AssemblyWagon 开发变更记录

> 说明：模组未发布阶段使用本文件记录每一次改动。
> 规则：新改动统一追加到最上方（时间倒序），每次包含日期、改动文件、改动内容。

## 2026-03-01（remote注册风格与RiftRail统一）

### 改动摘要
- 将 AW 的 remote 模块从 `setup_interface` 防御式注册，调整为与 RiftRail 一致的 `init + 依赖注入 + add_interface` 风格。

### 具体改动
- `scripts/remote.lua`
  - `Remote.setup_interface()` 改为 `Remote.init(params)`。
  - `Builder` 改为通过 `params.Builder` 注入。
  - 保留 `remote.add_interface("AssemblyWagon", ...)` 接口定义不变。

- `control.lua`
  - 启动注册改为：
    - `aw_remote.init({ Builder = builder })`

### 备注
- 当前调用时机仍为脚本加载阶段，不在传送热路径上执行。

## 2026-03-01（新增AW远程接口 transfer_binding）

### 改动摘要
- 新增 `scripts/remote.lua`，对外提供 `AssemblyWagon.transfer_binding` 远程接口。
- 在 `builder` 中新增绑定迁移逻辑，用于旧车厢替换为新车厢时保持伴生组装机与槽位绑定。
- `control.lua` 启动时注册 remote 接口。

### 具体改动
- `scripts/remote.lua`（新文件）
  - 新增 `Remote.setup_interface()`：
    - 若已有同名接口先移除再重注册。
    - 注册 `remote.add_interface("AssemblyWagon", { transfer_binding = ... })`。
  - `transfer_binding(old_wagon, new_wagon)` 内部委托 `builder.transfer_binding(...)`。

- `scripts/builder.lua`
  - 新增 `builder.transfer_binding(old_wagon, new_wagon)`：
    - 校验两者均为有效 `assembly-wagon`。
    - 转移 `storage.wagon_to_assembler` 键：`old_unit -> new_unit`。
    - 转移 `storage.wagon_to_slot` 键：`old_unit -> new_unit`。
    - 更新 `storage.assembler_to_wagon[assembler_unit] = new_wagon`。

- `control.lua`
  - 新增 `local aw_remote = require("scripts.remote")`。
  - 新增 `aw_remote.setup_interface()`，启动时注册接口。

### 备注
- 该接口为跨模组兼容准备，当前目标是配合 RiftRail 传送替换流程。

## 2026-03-01（虚空地表创建即隐藏）

### 改动摘要
- `aw_void` 地表在创建/获取时立即对所有 force 设为隐藏。

### 具体改动
- `scripts/void_pool.lua`
  - 新增 `hide_surface_for_all_forces(surface)`。
  - 在 `VoidPool.get_or_create_surface()` 中调用 `force.set_surface_hidden(surface, true)`（遍历 `game.forces`）。

### 备注
- 按当前开发阶段策略，不补迁移脚本。

## 2026-03-01（虚空槽位间距调整为 16）

### 改动摘要
- 将虚空地表槽位间距从 8 调整为 16，以提高不同工厂类型扩展时的安全缓冲。

### 具体改动
- `scripts/void_pool.lua`
  - `DEFAULT_PITCH` 从 `8` 调整为 `16`。

### 备注
- 当前模组尚未发布，无需迁移脚本。

## 2026-03-01（虚空地表 + 组装机槽位池）

### 改动摘要
- 新增独立 `void_pool` 模块，为组装机车厢提供虚空地表部署与槽位回收机制。
- 伴生组装机从“同地表偏移生成”改为“虚空地表按槽位生成”。
- 按钮打开组装机时，远程视图锚点切到组装机实体，兼容跨地表。

### 具体改动
- `scripts/void_pool.lua`（新文件）
  - 新增虚空池模块，固定地表名 `aw_void`。
  - 提供 `on_init()` / `allocate_slot()` / `release_slot()`。
  - 槽位参数：`pitch=8`，`columns=128`。
  - 坐标映射：`x=(slot_id % columns) * pitch`，`y=math.floor(slot_id / columns) * pitch`。
  - 维护 `storage.aw_void_pool`：`next_slot_id`、`freed_slots`、`used_slots`。

- `scripts/builder.lua`
  - 引入 `scripts.void_pool`。
  - `on_init()` 中初始化 `storage.wagon_to_slot` 并调用 `VoidPool.on_init()`。
  - 建造车厢时：
    - 通过 `VoidPool.allocate_slot()` 分配槽位与坐标。
    - 在 `aw_void` 地表创建 `wagon-assembler`。
    - 记录 `storage.wagon_to_slot[wagon_unit] = slot_id`。
    - 若创建失败，立即 `VoidPool.release_slot(slot_id)`。
  - 拆除车厢时：
    - 销毁伴生组装机后释放槽位。
  - 补充 `wagon-assembler` 销毁分支：
    - 清理双向映射，并尝试回收对应槽位。

- `scripts/gui.lua`
  - `aw_action_to_assembler` 分支中远程视图锚点改为 `assembler`，不再使用车厢实体作为锚点。

### 备注
- 当前仅接入“组装机车厢”路径；后续电磁/低温/铸造可在 `void_pool` 基础上扩展多池策略。

## 2026-03-01（按钮触发远程视图后打开组装机）

### 改动摘要
- 按你的决策，仅在“点击打开生产面板按钮”时进入远程视图，再打开真实组装机 GUI。
- 不修改交互距离，不增加回退机制。

### 具体改动
- `scripts/gui.lua`
  - 新增 `ensure_remote_view_near(player, anchor_entity)`：
    - 调用 `player.set_controller({ type = defines.controllers.remote, position = anchor_entity.position, surface = anchor_entity.surface, zoom = player.zoom })`。
    - 进入远程视图前先 `player.opened = nil`。
  - 在 `aw_action_to_assembler` 分支中：
    - 先对当前车厢调用 `ensure_remote_view_near`。
    - 再调用 `open_entity_gui(player, assembler)` 打开真实组装机界面。

### 备注
- `aw_action_to_wagon` 保持原逻辑，仅做界面重定向，不强制切换 controller。

## 2026-03-01（按钮重定向验证：不改交互距离）

### 改动摘要
- 仅调整按钮逻辑，验证在不修改交互距离的前提下，通过脚本重定向打开真实组装机 GUI。

### 具体改动
- `scripts/gui.lua`
  - 新增 `open_entity_gui(player, target)` 辅助函数：
    - 保留 `player/target.valid` 安全检查。
    - 采用 `player.opened = nil` 后再 `player.opened = target` 的切换方式，减少同 tick 界面不刷新的概率。
  - 按钮事件改用统一入口：
    - `aw_action_to_wagon`：从组装机界面切回车厢界面时调用 `open_entity_gui`。
    - `aw_action_to_assembler`：从车厢界面切到真实组装机界面时调用 `open_entity_gui`。

### 备注
- 本次未修改交互距离、未引入虚空地表，仅用于验证“脚本强制重定向 GUI”路径是否满足需求。

## 2026-03-01

### 改动摘要
- 在运行时事件注册中加入实体过滤器，降低无关事件触发。
- 将脚本命名从 `lifecycle` 调整为更贴近职责的 `builder`。

### 具体改动
- `control.lua`
  - `require("scripts.lifecycle")` 改为 `require("scripts.builder")`。
  - 初始化调用从 `lifecycle.on_init()` 改为 `builder.on_init()`。
  - 新增 `aw_filters`：
    - `{ filter = "name", name = "assembly-wagon" }`
    - `{ filter = "name", name = "wagon-assembler" }`
  - 事件注册改为拆分模式：
    - 支持过滤器的事件（玩家/机器人建造、玩家/机器人挖掘、实体死亡）单独注册并传入 `aw_filters`。
    - 不支持过滤器的脚本事件（`script_raised_built`/`script_raised_revive`/`script_raised_destroy`）单独注册，不传过滤器。

- `scripts/builder.lua`
  - 新建文件，内容由原 `scripts/lifecycle.lua` 迁移。
  - 模块名由 `lifecycle` 改为 `builder`，导出 `return builder`。

- `scripts/lifecycle.lua`
  - 删除（已被 `scripts/builder.lua` 替代）。

### 备注
- 本次为重构与性能优化改动，不涉及对外发布版本号与正式 `changelog`。

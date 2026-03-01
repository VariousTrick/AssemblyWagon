# AssemblyWagon 开发变更记录

> 说明：模组未发布阶段使用本文件记录每一次改动。
> 规则：新改动统一追加到最上方（时间倒序），每次包含日期、改动文件、改动内容。

## 2026-03-01（清仓扩展到 trash/dump）

### 改动摘要
- 清仓模式从“输出+输入”扩展为“输出+输入+垃圾+弹出”四库存全扫，避免切配方后残留滞留在 `trash/dump`。

### 具体改动
- `AssemblyWagon/scripts/logistics.lua`
  - 新增库存读取：`crafter_trash`、`assembling_machine_dump`。
  - 新增通用搬运函数 `move_inventory_to_wagon(...)`，并用于输入/垃圾/弹出库存回退。
  - 清仓分支新增 `trash/dump` 搬运与剩余检测；仅全部清空后退出清仓模式。
  - 调试日志增加 `trash_ops/dump_ops` 与 `has_trash/has_dump` 字段。

## 2026-03-01（切配方强制清仓 + GPS 满仓告警）

### 改动摘要
- 切配方后清仓逻辑改为“强制优先清仓”：先退回组装机内可访问的输出与输入物品，再恢复正常投喂。
- 清仓失败（车厢满）时提示改为携带车厢 GPS 的本地化消息；成品回仓失败仍保持静默。

### 具体改动
- `AssemblyWagon/scripts/logistics.lua`
  - 新增 `MAX_DRAIN_OPS_PER_PAIR = 8`，提高清仓阶段每轮搬运预算。
  - 新增 `inventory_has_items(...)`、`get_wagon_gps(...)`、`print_drain_full_warning(...)` 辅助函数。
  - 在 `process_pair(...)` 中将“配方变化检测 + 清仓模式”前置：
    - 配方切换后立即进入清仓模式；
    - 清仓模式下优先搬运输出库存，再搬运输入库存；
    - 清仓未完成则短睡眠重试；清仓完成后退出清仓模式。
  - 仅在清仓阶段回退失败时提示满仓，不对常规成品回仓阻塞进行 `game.print`。

- `AssemblyWagon/locale/zh-CN/locale.cfg`
  - 新增 `messages.aw-wagon-full-cannot-return-gps`（含 GPS 占位符 `__1__`）。

- `AssemblyWagon/locale/en/locale.cfg`
  - 新增 `messages.aw-wagon-full-cannot-return-gps`（含 GPS 占位符 `__1__`）。

## 2026-03-01（清仓退料失败提示：仅车厢满时提示）

### 改动摘要
- 清仓阶段若旧料因车厢已满无法退回，新增本地化 `game.print` 提示。
- 成品回仓失败保持静默，不提示。

### 具体改动
- `AssemblyWagon/scripts/logistics.lua`
  - `move_inputs_to_wagon(...)` 增加 `blocked` 返回值。
  - 清仓模式下当 `drain_blocked` 为真时触发提示：
    - `game.print({ "messages.aw-wagon-full-cannot-return" })`
  - 新增节流表 `storage.aw_logistics.drain_full_warn_until`，同一车厢每 300 tick 最多提示一次。
  - 在绑定清理/清仓完成时清除对应节流状态。

- `AssemblyWagon/locale/zh-CN/locale.cfg`
  - 新增 `messages.aw-wagon-full-cannot-return` 中文文案。

- `AssemblyWagon/locale/en/locale.cfg`
  - 新增 `messages.aw-wagon-full-cannot-return` 英文文案。

### 备注
- 按当前需求，成品回仓阻塞不做任何提示。

## 2026-03-01（切配方后旧料退回车厢）

### 改动摘要
- 新增“清仓模式”：当配方切换时，先将组装机输入槽旧原料退回车厢，再恢复新配方投喂。

### 具体改动
- `AssemblyWagon/scripts/logistics.lua`
  - `storage.aw_logistics` 新增 `drain_mode`。
  - 新增 `move_inputs_to_wagon(...)`：按输入槽位逐格回退旧料到车厢。
  - 在 `process_pair(...)` 中：
    - 检测到 `recipe` 变化后置 `drain_mode[wagon_unit] = true`。
    - 清仓模式下优先退回输入槽旧料，未清空则短睡眠重试。
    - 输入槽清空后退出清仓模式，再进入正常投喂。

### 备注
- 该逻辑直接解决“切配方后旧原料长期滞留在组装机槽位”的问题。

## 2026-03-01（修复输出搬运中的 LuaItemStack 失效读取）

### 改动摘要
- 修复 `on_nth_tick(10)` 输出搬运时因 `remove` 后槽位失效导致的 `LuaItemStack invalid for read` 报错。

### 具体改动
- `AssemblyWagon/scripts/logistics.lua`
  - 在按槽位搬运逻辑中，先缓存 `stack.name` 与 `stack.quality`。
  - 后续 `remove/insert` 全部使用缓存变量，避免在槽位被清空后继续读取 `stack` 字段。

### 备注
- 报错栈：`LuaItemStack API call when LuaItemStack was invalid for read`（line 121）。

## 2026-03-01（修复“输出有货但不回仓”）

### 改动摘要
- 将成品回仓逻辑从 `get_contents` 解析改为“按输出槽位逐格搬运”，修复输出栏满但不搬运的问题。

### 具体改动
- `AssemblyWagon/scripts/logistics.lua`
  - 删除基于 `get_contents()` 的成品提取路径。
  - `move_outputs_to_wagon(...)` 改为按 `output_inv[slot_index]` 逐格读取并搬运：
    - 每格最多搬 `100`。
    - 失败时回插到输出库存。
    - `inserted == 0` 标记为阻塞。

### 备注
- 该改动用于规避品质/统计结构差异导致的 `remove` 拿不到物品问题。

## 2026-03-01（日志判断简化 + 物流回仓诊断日志）

### 改动摘要
- 按讨论将日志判断简化为 `if AssemblyWagon.DEBUG_MODE_ENABLED then`，移除冗余 `if AssemblyWagon` 判断。
- 在物流模块加入“成品回仓”关键诊断日志，便于直接定位“为什么没回车厢”。

### 具体改动
- `AssemblyWagon/scripts/builder.lua`
  - 所有日志判断统一为 `if AssemblyWagon.DEBUG_MODE_ENABLED then`。

- `AssemblyWagon/scripts/remote.lua`
  - 所有日志判断统一为 `if AssemblyWagon.DEBUG_MODE_ENABLED then`。

- `AssemblyWagon/scripts/logistics.lua`
  - 新增 `Logistics.init(deps)` 接收 `log_debug` 注入。
  - 在输出搬运后新增诊断日志：
    - 成功回仓（`moved_out_ops > 0`）
    - 回仓阻塞（`blocked == true`）
    - 输出有货但未搬运（`next(output_contents) ~= nil` 且 `moved_out_ops == 0`）

- `AssemblyWagon/control.lua`
  - 新增 `logistics.init({ log_debug = log_debug })` 注入。

## 2026-03-01（日志系统改为 RiftRail 同风格）

### 改动摘要
- 按你的要求，将日志体系从“惰性回调构造”改为 RiftRail 同款：
  - `control.lua` 挂全局开关 `AssemblyWagon.DEBUG_MODE_ENABLED`
  - 提供 `log_debug(msg)`
  - 业务模块通过依赖注入拿到 `log_debug`
  - 字符串拼接统一放在 `if DEBUG then` 语句块内

### 具体改动
- `AssemblyWagon/control.lua`
  - 新增 `AssemblyWagon.DEBUG_MODE_ENABLED` 刷新逻辑。
  - 新增 `log_debug(msg)`。
  - `builder.init(...)` 与 `remote.init(...)` 注入 `log_debug`。
  - 运行时设置变更时刷新全局调试开关。

- `AssemblyWagon/scripts/builder.lua`
  - 新增 `builder.init(deps)` 接收 `log_debug`。
  - 所有日志改为 `if AssemblyWagon.DEBUG_MODE_ENABLED then ... end` 包裹。

- `AssemblyWagon/scripts/remote.lua`
  - `Remote.init(params)` 接收 `log_debug`。
  - 日志改为显式 `if DEBUG then` 包裹。

- `AssemblyWagon/scripts/logger.lua`
  - 删除（不再使用惰性回调日志器）。

### 备注
- 当前实现与 RiftRail 日志风格一致，便于跨模组维护。

## 2026-03-01（新增可开关调试日志系统）

### 改动摘要
- 新增类似 RiftRail 风格的可开关调试日志系统。
- 日志统一走惰性消息构造，关闭开关时不进行字符串拼接。

### 具体改动
- `AssemblyWagon/settings.lua`（新文件）
  - 新增运行时全局设置：`assemblywagon-debug-mode`（默认 `false`）。

- `AssemblyWagon/scripts/logger.lua`（新文件）
  - 新增 `Logger.init()`：读取调试开关状态。
  - 新增 `Logger.debug(message_or_builder)`：
    - 仅在开关开启时输出。
    - 支持函数回调惰性构造消息，避免关闭时字符串拼接。

- `AssemblyWagon/control.lua`
  - 启动与配置变更时调用 `logger.init()`。
  - 监听 `on_runtime_mod_setting_changed`，当 `assemblywagon-debug-mode` 改变时热更新日志开关。

- `AssemblyWagon/scripts/builder.lua`
  - 在初始化、创建绑定、销毁解绑、跨模组转移绑定等关键路径加入调试日志（均为惰性消息构造）。

- `AssemblyWagon/scripts/remote.lua`
  - 在 remote 接口注册和 `transfer_binding` 调用处加入调试日志（惰性消息构造）。

- `AssemblyWagon/locale/zh-CN/locale.cfg`
  - 新增调试设置中文名称与说明。

- `AssemblyWagon/locale/en/locale.cfg`（新文件）
  - 新增调试设置英文名称与说明。

### 备注
- 当前日志系统已具备“零开销消息拼接”特性，后续新增日志应统一通过 `Logger.debug(function() ... end)` 形式写入。

## 2026-03-01（组装车厢库存扩展到500格）

### 改动摘要
- 按当前讨论先行扩大模组车厢容量，便于验证物流循环阶段的吞吐与阻塞行为。

### 具体改动
- `AssemblyWagon/prototypes/entities/assembly-wagon.lua`
  - 新增 `entity.inventory_size = 500`。

### 备注
- 本次只调整车厢容量，不改成品回收逻辑。

## 2026-03-01（修复输出搬运在品质场景下的类型报错）

### 改动摘要
- 修复 `on_nth_tick(10)` 中输出搬运逻辑对 `get_contents()` 返回结构假设过窄导致的运行时报错。

### 具体改动
- `AssemblyWagon/scripts/logistics.lua`
  - 新增 `move_single_output_entry(...)`，统一处理单条输出搬运。
  - `move_outputs_to_wagon(...)` 改为兼容两种结构：
    - 普通计数：`item -> number`
    - 品质分层计数：`item -> { quality -> number }`
  - 避免 `math.min(table, 100)` 类型错误。

### 备注
- 报错栈：`bad argument #1 of 3 to 'min' (number expected, got table)`。

## 2026-03-01（移除旧存档重建分支）

### 改动摘要
- 按“初版开发”策略，删除物流初始化中的旧存档兼容重建逻辑。

### 具体改动
- `AssemblyWagon/scripts/logistics.lua`
  - 在 `Logistics.on_init()` 中移除：
    - 当活跃列表为空时，从 `storage.wagon_to_assembler` 重建 `aw_active_wagons/aw_active_index` 的分支。
  - 保留纯初始化路径：只创建空结构，不做历史数据推断。

### 备注
- 当前阶段不考虑已发布版本的存档兼容，不新增迁移逻辑。

## 2026-03-01（物流循环实行分片轮询）

### 改动摘要
- 物流引擎从“全量扫描绑定表”升级为“活跃列表 + 游标 + 固定预算”的分片轮询。
- 每次 `on_nth_tick` 仅处理部分绑定对，降低大规模存档下的帧时间抖动。

### 具体改动
- `AssemblyWagon/scripts/builder.lua`
  - 新增活跃列表维护：`storage.aw_active_wagons`、`storage.aw_active_index`。
  - 新增局部函数：`add_active_wagon(unit_number)`、`remove_active_wagon(unit_number)`（swap-remove）。
  - 在建造/拆除/兼容迁移路径中同步维护活跃列表。

- `AssemblyWagon/scripts/logistics.lua`
  - 新增分片参数：`MAX_PAIRS_PER_STEP = 80`。
  - 新增游标：`storage.aw_logistics.cursor`。
  - `on_nth_tick` 改为：
    - 从活跃列表按游标轮询。
    - 每轮最多处理固定预算绑定对。
    - 对失效绑定执行惰性清理并从活跃列表剔除。
  - `on_init` 增加旧存档兼容：可从 `wagon_to_assembler` 重建活跃列表。

### 备注
- 当前分片参数为保守默认值，后续可按实测 UPS 再调优。

## 2026-03-01（新增物流搬运引擎 MVP）

### 改动摘要
- 新增独立物流模块 `scripts/logistics.lua`，以 `on_nth_tick` 驱动车厢与组装机间的物品搬运。
- 采用“两阶段搬运”策略：先拉成品，再按需喂料。
- 加入配方缓存与睡眠机制，降低空转开销。

### 具体改动
- `AssemblyWagon/scripts/logistics.lua`（新文件）
  - 新增 `Logistics.on_init()`：初始化 `storage.aw_logistics`（`recipe_cache`、`sleep_until`）。
  - 新增 `Logistics.on_nth_tick(event)`：遍历绑定对，执行单对处理流程。
  - 新增 `process_pair(...)`：
    - 先执行输出搬运（组装机 -> 车厢）。
    - 再执行输入投喂（车厢 -> 组装机）。
    - 处理无配方、输出阻塞、空转睡眠等状态。
  - 新增 `Logistics.get_nth_tick()`：返回循环间隔（当前 `10` tick）。
  - 全文件补充中文注释和 `---@param` 类型提示。

- `AssemblyWagon/control.lua`
  - 新增 `local logistics = require("scripts.logistics")`。
  - 在 `on_init/on_configuration_changed` 中调用 `logistics.on_init()`。
  - 新增 `script.on_nth_tick(logistics.get_nth_tick(), logistics.on_nth_tick)`。

### 备注
- 当前为 MVP：仅处理固体物品配方，流体配方默认跳过。
- 目标是先确保稳定与不吞物，后续再做分片预算与更细粒度性能优化。

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

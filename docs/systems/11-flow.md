# 11 · 流程管理系统

- 上游：`../core-design.md`（**v0.27**：新增第 11 个系统，§16.22）
- 依赖系统：无（**它不读任何游戏数据**）；被依赖：**全部入口**（08 的菜单按钮、09 的演出结束、10 的读档完成都通过它切节点）
- 定位：**全游戏的"现在在哪"只有这一份答案**。它是一个**极小的状态机 + 唯一的换场景入口**，不承担业务。

## 1. 这个系统负责什么

1. **流程节点（3 个，逐字）**：**游戏菜单 `menu`**、**游戏场景 `game`**、**设置 `settings`**（用户裁决；早期口误的"四个场景"已裁决为 3 个）。
2. **唯一事实来源**：`FlowService.current`。**任何面板 / 场景不得自己记"我在哪"**。
3. **转换白名单**：合法边只有 `menu ↔ game`、`menu ↔ settings`、`game ↔ settings`；**禁止原地切换**、**禁止跳到未知节点**。
4. **设置的"来源记忆"**：`settings_return_to`——**从哪个节点进设置，关掉就回哪个**（用户裁决：设置可从任意场景进入）。没有来源 ⇒ 回菜单。
5. **唯一换场景入口**：`FlowService.apply_scene()` 是全库**唯一**可以 `change_scene_to_file` 的地方。
6. **场景清单**：`menu_screen.tscn`（四按钮）/ `settings_screen.tscn`（空壳）/ `game_screen.tscn`（**只做 tab 骨架**）＋ 两个**页场景**：`warehouse_page.tscn`（仓库）/ **`wish_machine.tscn`（许愿机）**。★ **v0.29 用户裁决：「许愿机」就是设备的名字**（`dev_basic_q1.tres` 的 `display_name` 已改为「许愿机」），**它的整页内容是一个独立场景**：设备名 / 描述 / 等级 / 本级两条效果（可开套系品质上限、开盒折扣）/ 升级价 + 升级按钮 / 原石余额 / 盲盒下拉 + 开一次 + 结果。**页面内容归 08 的视觉规格，行为入口归 01/04**（本系统只负责把场景放进 tab）。
7. **★ 会话容器 `GameSession`（v0.28）**：**"这一局是哪个 `GameState`"只此一份**。`FlowService` 只转场、**不持游戏数据**；切场景之后新场景还拿得到这一局，靠的就是 `GameSession.state`。
   - 菜单「**新游戏**」→ `GameSession.start_new_game()`（内部 `GameState.new_game()`，**开局 = 设备 + 原石 + 金币**）→ 再 `transition(game)`；
   - 菜单「**继续**」→ `GameSession.load()`——**读档归 10**，本版是**占位实现（恒 false）** ⇒ 无档时**明确拒绝**（置灰 + `continue_unavailable`），**不装作能继续**；
   - 游戏场景 `_ready()`：`state == null` 时从 `GameSession.state` 取 —— **一局只能有一个 `GameState`**（两个场景各建一份，玩家的东西就分家了）；
   - **本系统仍不解释存档格式**：`has_save()` / `load()` 是留给 10 的两个空槽。

## 2. 不负责什么（边界）

| 不归本系统 | 归属 |
|---|---|
| 面板布局、按钮、菜单长什么样 | `08-ui-panels.md` |
| 读档 / 存档 / 迁移（**进入游戏场景前要不要读档**是 10 的事） | `10-progression.md` |
| 开箱演出、结算动画 | `09-presentation.md` |
| 游戏循环、任务交付、开盒逻辑 | `01` / `03` / `04` |
| 暂停、音量、按键绑定等"设置项本身" | 未裁决（见 §7） |

## 3. 数据结构

```gdscript
# res://src/flow/flow_service.gd —— autoload 单例（名字就是 FlowService，不额外写 class_name）
const NODE_MENU := &"menu"
const NODE_GAME := &"game"
const NODE_SETTINGS := &"settings"
const NODE_SCENES := { menu: "res://src/flow/scenes/menu_screen.tscn", ... }   # 路径只有这一份
const ALLOWED := { menu: [game, settings], game: [menu, settings], settings: [menu, game] }

var current: StringName = NODE_MENU      # 唯一事实来源
var settings_return_to: StringName = &"" # 设置来源（一次性记忆）

signal flow_changed(from, to)            # 只在真转换时发
```

## 4. 规则（写死）

- **R11-1 白名单**：`can_transition(to)` = `to ∈ ALLOWED[current]` 且 `to != current`。**被拒时状态一点不变、信号不发**。
- **R11-2 设置覆盖层**：`open_settings()` 记下来源后进入；`close_settings()` 回来源（无来源 ⇒ 菜单）；**离开设置即清空记忆**（它只服务一次返回）。
- **R11-3 状态与画面同源**：`transition(to, scene_change := true)` 是唯一同时改状态与换场景的入口；**别处不得直接换场景**（否则"状态说在游戏、画面在菜单"）。
- **R11-4 不碰游戏数据**：本系统**不读档、不写档、不改 `GameState` / `ItemService`**。
- **R11-5 自动换场景可关**：`auto_scene_change`（默认 `true`）。为 `false` 时 `transition()` **只改状态、不真换场景** —— **无头测试必须关掉它**（真换场景会销毁测试自身的场景，断言全落在已释放实例上）；运行时也可以用它做"启动早期先不切场景"。

## 5. 接口

| 方向 | 接口 | 说明 |
|---|---|---|
| 任意 → 11 | `transition(node, scene_change := true) -> bool` | 按白名单切换；返回是否真的切了 |
| 任意 → 11 | `open_settings()` / `close_settings()` | 设置往返（记住来源） |
| 11 → 全库 | `flow_changed(from, to)` 信号 | 08 / 09 / 10 订阅它做"进入游戏时刷新""回菜单时停演出"这类动作 |
| 11 → 10 | **无**（**故意不耦合**） | "进入游戏场景要不要读档"由 10 自己订阅 `flow_changed` 决定 |

## 6. 测试点（v0.29：两个场景，共 **111 条断言**全绿）

1. 初始节点 = 菜单；`menu→game` / `menu→settings` 允许；`menu→menu` 与未知节点**禁止**。
2. **非法流转状态不变**（`transition(&"no_such_node")` ⇒ false、`current` 不动）。
3. **设置往返**：菜单→设置→菜单；**游戏→设置→游戏**（用户裁决的核心用例）。
4. **边界**：设置里再开设置 ⇒ 拒绝；不在设置里关设置 ⇒ 拒绝；**无来源记忆**时关设置 ⇒ 回菜单。
5. **信号只发真转换**（被拒的不发，`from` / `to` 正确）。
6. **三个节点的场景文件都必须存在**（`ResourceLoader.exists`）。
7. **菜单内容**（`test_flow_service.gd`）：游戏名称 + 四个按钮（**顺序 = 继续 → 新游戏 → 存档 → 设置**）、各自去向；**无档时「继续」不切节点并转发 `continue_unavailable`**（v0.28 语义：读档归 10）。
8. **游戏场景**（`test_game_screen.gd`，49 条）：两个 tab **都是场景实例**（`warehouse_page` / `wish_machine`）、`refresh()` **不重建页**（页引用保持有效）；仓库页占用/分组/盲盒数；许愿机页设备名「许愿机」/等级/两条效果/升级真扣原石/余额不足置灰/开盒真产出/下拉只列仓库盒子。
9. **旁路写盘**：本机 runner 拿不到 Godot 的 stdout，两个 flow 测试都会另写 `user://test_*.txt`（正常环境只是一次无害的额外写盘）。

## 7. 待定项

| # | 待定项 | 现状与影响 |
|---|---|---|
| **F0** | **菜单的四个按钮与它们去哪**（★ 已裁决 = 用户要求） | **游戏名称 `Open Box` + 四个按钮，顺序 = 继续 → 新游戏 → 存档 → 设置**（用户裁决；设置挂在最后，不参与"开始游戏"的主流程）：`新游戏`、`继续` ⇒ `game`（**有没有档可继续由 10 判**，本层只转发；不可继续时置灰并转发 `continue_unavailable`）；`设置` ⇒ `open_settings()`（来源 = 菜单，关掉回菜单）；`存档` ⇒ **发 `save_requested` 信号**，**存档读写归 10**（本系统不碰存档）。**长什么样（排版 / 字体 / 动效）归 08** |
| **F1** | **设置项本身有哪些**（音量 / 按键 / 语言 / 画质） | **未裁决**：本版只做"进出设置"的流程，**不实现任何设置项**。加设置项不改变本系统的状态机（它们属于 08 的面板内容） |
| **F2** | **"开始新游戏 / 继续存档"要不要在流程里显式建模** | 当前**不建模**：菜单 → 游戏只有一条边，"新档还是继续"由 10 在进入游戏时自行判断（本系统不持有档位）。若将来需要"主菜单 → 选档界面"，那是**加一个节点**（`ALLOWED` 加两条边），不改结构 |
| **F3** | 是否需要"加载 / 过渡"节点 | 用户已裁决 **三个节点**；转场动画归 09（演出层），**不新增流程节点** |

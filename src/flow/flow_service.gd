## 流程管理系统（★ v0.27 新增；归属第 11 个系统，`11-flow.md`）。
##
## **它只负责一件事：现在在哪个"流程节点"、以及能不能去下一个。**
## 当前流程有三个节点（用户裁决）：**游戏菜单 `menu` / 游戏场景 `game` / 设置 `settings`**。
##
## 三条纪律（与全库"单一事实来源"同一精神）：
##   1. **流程状态只有一份**（`current`），就在本类里。任何面板 / 场景**不得自己记"我在哪"**。
##   2. **转换必须过白名单**（`can_transition()`）：非法流转**拒绝并返回 false**，
##      状态**一点都不变**（不半途切换，不发信号）。
##   3. **设置是"覆盖层"型节点**：可以从菜单或游戏**进入**，并用 `settings_return_to`
##      记住"我该回哪去"；`close_settings()` 回到那个来源（没有来源 ⇒ 回菜单）。
##      **设置不是第四个独立场景**——它是"从任意节点进入、返回来源"的那一个（用户裁决）。
##
## **本类不碰游戏数据**：不读档、不写档、不改 `GameState` / `ItemService`。
## 存档归 10，场景内容归各自系统；本类只**切节点**（`apply_scene()` 是唯一真正换场景的地方）。
extends Node

## 节点 id（逐字；存档 / 日志 / UI 都用这三个字符串）
const NODE_MENU := &"menu"
const NODE_GAME := &"game"
const NODE_SETTINGS := &"settings"

const ALL_NODES: Array[StringName] = [NODE_MENU, NODE_GAME, NODE_SETTINGS]

## 节点 → 场景文件。**只在这里维护一份映射**（场景路径不散落在各处）。
const NODE_SCENES := {
	NODE_MENU: "res://src/flow/scenes/menu_screen.tscn",
	NODE_GAME: "res://src/flow/scenes/game_screen.tscn",
	NODE_SETTINGS: "res://src/flow/scenes/settings_screen.tscn",
}

## 合法流转白名单（**只允许这些**；`settings` 的边由 `open_settings()` / `close_settings()`
## 动态决定"回到哪"，所以这里只登记"能不能从 A 到 B"这件事本身）。
const ALLOWED := {
	NODE_MENU: [NODE_GAME, NODE_SETTINGS],
	NODE_GAME: [NODE_MENU, NODE_SETTINGS],
	NODE_SETTINGS: [NODE_MENU, NODE_GAME],
}

## ★ **自动换场景开关**（默认开）。为 `false` 时 `transition()` **只改状态、不真换场景**。
##
## 为什么需要它：**无头测试不能真的换场景**——换掉当前场景会销毁测试自身（以及它正在
## 操作的那些节点），断言会落在已释放的实例上。生产环境保持 `true`；
## 也可以在"启动早期不想被切走"的场合临时关掉。
var auto_scene_change: bool = true

## 当前节点。**唯一事实来源**（初始 = 菜单）。
var current: StringName = NODE_MENU
## 从哪个节点进的设置（空 = 没有来源，`close_settings()` 回菜单）。
var settings_return_to: StringName = &""

## 节点变化信号：`(from, to)`。**只在真正发生转换时发**（被拒绝时不发）。
signal flow_changed(from: StringName, to: StringName)


func is_known(node: StringName) -> bool:
	return ALL_NODES.has(node)


## 能不能从**当前节点**走到 `to`？
## **不允许"原地切换"**（`to == current` ⇒ false）：那是无意义的转换，会让信号与快照语义变糊。
func can_transition(to: StringName) -> bool:
	if not is_known(to) or to == current:
		return false
	var outs: Array = ALLOWED.get(current, [])
	return outs.has(to)


## 真正切换节点（白名单外的请求**一律拒绝**：返回 false、状态不变、不发信号）。
## `scene_change == true` 时顺带换场景（游戏运行时用；无头测试传 false 只验状态机）。
func transition(to: StringName, scene_change: bool = true) -> bool:
	if not can_transition(to):
		return false
	var from := current
	if current == NODE_SETTINGS:
		# 离开设置后"来源记忆"失效（它只服务一次返回）
		settings_return_to = &""
	current = to
	if scene_change and auto_scene_change:
		apply_scene()
	flow_changed.emit(from, to)
	return true


## 进入设置（**从任何节点都可以**）；记住"从哪来"，好让 `close_settings()` 回得去。
func open_settings(scene_change: bool = true) -> bool:
	if current == NODE_SETTINGS:
		return false
	if not can_transition(NODE_SETTINGS):
		return false
	settings_return_to = current
	return transition(NODE_SETTINGS, scene_change)


## 离开设置：回到来源节点（没有来源 ⇒ 菜单）。**只回一次**。
func close_settings(scene_change: bool = true) -> bool:
	if current != NODE_SETTINGS:
		return false
	var back := settings_return_to
	if back == &"" or back == NODE_SETTINGS:
		back = NODE_MENU
	return transition(back, scene_change)


## 回到初始态（测试 / 重开游戏用）。**不换场景**。
func reset_flow() -> void:
	current = NODE_MENU
	settings_return_to = &""


func node_scene_path(node: StringName) -> String:
	return String(NODE_SCENES.get(node, ""))


## **唯一真正换场景的地方**（`FlowService` 之外不得直接 `change_scene_to_file`——
## 否则"流程状态"与"屏幕上是什么"会各说各话）。
func apply_scene() -> void:
	if not auto_scene_change:
		return
	var path := node_scene_path(current)
	if path == "" or not ResourceLoader.exists(path):
		push_warning("FlowService: 节点 `%s` 的场景不存在（`%s`）" % [current, path])
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.change_scene_to_file(path)

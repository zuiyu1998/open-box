## 流程管理系统测试（★ v0.27；`docs/systems/11-flow.md` §10）。
##
## 断的是**状态机本身**（不换场景，`scene_change = false`）：白名单、设置来源记忆、
## 信号只发真转换、以及"三个场景文件都真的存在"。
extends Node

var _pass := 0
var _fail := 0
## 旁路：本机 runner 拿不到 stdout，结果另写 user://test_flow_service.txt。
var _lines: Array[String] = []
var _events: Array = []


func _ready() -> void:
	print("=== 流程管理系统测试（11-flow.md §10）===\n")
	# ★ 无头测试**不能真换场景**（会销毁测试自身）⇒ 关掉自动换场景，只验状态机与节点内容
	FlowService.auto_scene_change = false
	FlowService.flow_changed.connect(_on_flow)
	_test_initial_and_whitelist()
	_test_settings_roundtrip()
	_test_signal_only_on_real_change()
	_test_scene_paths_exist()
	await _test_menu_scene_content()
	FlowService.auto_scene_change = true
	FlowService.reset_flow()
	var summary := "=== 结果：%d 通过 / %d 失败 ===" % [_pass, _fail]
	print("\n" + summary)
	_lines.append(summary)
	var f := FileAccess.open("user://test_flow_service.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit(1 if _fail > 0 else 0)


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [PASS] " + what)
		_lines.append("PASS " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)
		_lines.append("FAIL " + what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s  期望=%s 实际=%s" % [what, str(b), str(a)])


func _on_flow(from: StringName, to: StringName) -> void:
	_events.append([from, to])


func _test_initial_and_whitelist() -> void:
	print("— §5.1 初始节点与白名单")
	FlowService.reset_flow()
	eq(FlowService.current, FlowService.NODE_MENU, "初始节点 = 菜单")
	ok(FlowService.can_transition(FlowService.NODE_GAME), "菜单 → 游戏：允许")
	ok(FlowService.can_transition(FlowService.NODE_SETTINGS), "菜单 → 设置：允许")
	ok(not FlowService.can_transition(FlowService.NODE_MENU), "菜单 → 菜单：禁止（原地切换无意义）")
	ok(not FlowService.can_transition(&"no_such_node"), "未知节点：禁止")
	FlowService.reset_flow()

	print("— §5.1 非法流转被拒且状态不变")
	var before := FlowService.current
	eq(FlowService.transition(&"no_such_node", false), false, "未知节点 ⇒ false")
	eq(FlowService.current, before, "状态不变")

	print("— §5.2 菜单 ↔ 游戏")
	eq(FlowService.transition(FlowService.NODE_GAME, false), true, "菜单 → 游戏：成功")
	eq(FlowService.current, FlowService.NODE_GAME, "当前 = 游戏")
	eq(FlowService.transition(FlowService.NODE_MENU, false), true, "游戏 → 菜单：成功")
	eq(FlowService.current, FlowService.NODE_MENU, "当前 = 菜单")


func _test_settings_roundtrip() -> void:
	print("— §5.3 设置：从菜单进，回菜单")
	FlowService.reset_flow()
	eq(FlowService.open_settings(false), true, "菜单 → 设置：成功")
	eq(FlowService.current, FlowService.NODE_SETTINGS, "当前 = 设置")
	eq(FlowService.settings_return_to, FlowService.NODE_MENU, "来源记忆 = 菜单")
	eq(FlowService.close_settings(false), true, "关设置：成功")
	eq(FlowService.current, FlowService.NODE_MENU, "回到菜单")
	eq(FlowService.settings_return_to, &"", "离开设置后来源记忆清空")

	print("— §5.3 设置：从游戏进，回游戏（用户裁决：任意节点可进、返回来源）")
	FlowService.reset_flow()
	FlowService.transition(FlowService.NODE_GAME, false)
	eq(FlowService.open_settings(false), true, "游戏 → 设置：成功")
	eq(FlowService.settings_return_to, FlowService.NODE_GAME, "来源记忆 = 游戏")
	eq(FlowService.close_settings(false), true, "关设置：成功")
	eq(FlowService.current, FlowService.NODE_GAME, "**回到游戏**（不是回菜单）")

	print("— §5.3 边界：设置里再开设置 / 直接关已关闭的设置")
	eq(FlowService.open_settings(false), true, "再进设置")
	eq(FlowService.open_settings(false), false, "设置里再开设置 ⇒ 拒绝")
	eq(FlowService.close_settings(false), true, "关设置")
	eq(FlowService.close_settings(false), false, "不在设置里关设置 ⇒ 拒绝")
	eq(FlowService.current, FlowService.NODE_GAME, "状态未被第二次关闭影响")

	print("— §5.3 边界：没有来源记忆时回菜单")
	FlowService.reset_flow()
	FlowService.current = FlowService.NODE_SETTINGS       # 人为构造"无来源"状态
	FlowService.settings_return_to = &""
	eq(FlowService.close_settings(false), true, "无来源 ⇒ 仍可关闭")
	eq(FlowService.current, FlowService.NODE_MENU, "回退到菜单")


func _test_signal_only_on_real_change() -> void:
	print("— §5.4 信号只发真转换")
	FlowService.reset_flow()
	_events.clear()
	FlowService.transition(FlowService.NODE_GAME, false)
	FlowService.transition(FlowService.NODE_GAME, false)      # 原地：被拒
	FlowService.transition(&"no_such_node", false)            # 未知：被拒
	eq(_events.size(), 1, "只发 1 次信号（被拒的不发）")
	eq(_events[0][0], FlowService.NODE_MENU, "from = 菜单")
	eq(_events[0][1], FlowService.NODE_GAME, "to = 游戏")


func _test_scene_paths_exist() -> void:
	print("— §6 三个节点的场景文件都必须存在")
	for node in FlowService.ALL_NODES:
		var path := FlowService.node_scene_path(node)
		ok(path != "", "节点 `%s` 配了场景路径" % node)
		ok(ResourceLoader.exists(path), "场景存在：%s" % path)
	FlowService.reset_flow()


func _test_menu_scene_content() -> void:
	print("— §7 菜单场景内容（★ v0.27：游戏名称 + 新游戏 / 继续 / 设置 / 存档 四个按钮）")
	var packed: PackedScene = load(FlowService.node_scene_path(FlowService.NODE_MENU))
	ok(packed != null, "菜单场景能载入")
	if packed == null:
		return
	var menu = packed.instantiate()
	add_child(menu)
	await get_tree().process_frame          # 等 _ready 与 @onready 就位

	var title: Label = menu.get_node("Title")
	eq(title.text, "Open Box", "游戏名称显示为 `Open Box`")

	var box: VBoxContainer = menu.get_node("Buttons")
	eq(box.get_child_count(), 4, "四个按钮（继续 / 新游戏 / 存档 / 设置）")
	# ★ 用户裁决（v0.27）：**顺序 = 继续 → 新游戏 → 存档 → 设置**（设置挂在最后，不参与"开始游戏"的主流程）
	var names := ["Continue", "NewGame", "Save", "Settings"]
	var texts := ["继续", "新游戏", "存档", "设置"]
	for i in names.size():
		var b: Button = box.get_node(names[i])
		ok(b != null, "按钮 `%s` 存在" % names[i])
		if b == null:
			continue
		eq(b.text, texts[i], "按钮 `%s` 文案 = %s" % [names[i], texts[i]])
		ok(not b.disabled, "按钮 `%s` 可点" % names[i])

	print("— 按钮去向：新游戏 / 继续 → game；设置 → settings；存档 → 信号（归 10）")
	FlowService.reset_flow()
	menu.get_node("Buttons/NewGame").pressed.emit()
	eq(FlowService.current, FlowService.NODE_GAME, "**新游戏 ⇒ 进游戏场景**")

	# ★ v0.28 改语义：**继续**要经过 `GameSession.load()`（读档归 10，本版占位恒 false）
	#   ⇒ 无档时**明确拒绝**（不切节点 + 发 continue_unavailable），绝不"装作能继续"。
	FlowService.reset_flow()
	var unavailable := []
	menu.continue_unavailable.connect(func(): unavailable.append(1))
	menu.get_node("Buttons/Continue").pressed.emit()
	eq(FlowService.current, FlowService.NODE_MENU, "**无档时「继续」不切节点**（读档归 10）")
	eq(unavailable.size(), 1, "无档时「继续」⇒ 发 continue_unavailable")

	FlowService.reset_flow()
	menu.get_node("Buttons/Settings").pressed.emit()
	eq(FlowService.current, FlowService.NODE_SETTINGS, "**设置 ⇒ 进设置**")
	eq(FlowService.settings_return_to, FlowService.NODE_MENU, "设置来源 = 菜单（关掉回菜单）")

	var got_save := []
	menu.save_requested.connect(func(): got_save.append(true))
	FlowService.reset_flow()
	menu.get_node("Buttons/Save").pressed.emit()
	eq(got_save.size(), 1, "**存档 ⇒ 发 `save_requested` 信号**（存档本身归 10）")
	eq(FlowService.current, FlowService.NODE_MENU, "存档不改变流程节点")

	print("— 「继续」不可用时：置灰 + 发 `continue_unavailable`，且不切节点")
	var got_unavail := []
	menu.continue_unavailable.connect(func(): got_unavail.append(true))
	menu.refresh(false)
	ok(menu.get_node("Buttons/Continue").disabled, "无档可继续 ⇒ 按钮置灰")
	FlowService.reset_flow()
	menu.get_node("Buttons/Continue").pressed.emit()
	eq(got_unavail.size(), 1, "发 `continue_unavailable`")
	eq(FlowService.current, FlowService.NODE_MENU, "**不切节点**（灰按钮不会真的进游戏）")
	menu.queue_free()
	FlowService.reset_flow()
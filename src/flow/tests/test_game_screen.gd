## 游戏场景测试（★ v0.29：两个 tab 各自是一个**独立场景**）。
##
## 断的是"**这套东西真的能用**"：
##   ① **tab 骨架**：两个 tab（仓库 / 许愿机）都是**场景实例**，可切换；
##   ② **仓库页**（`warehouse_page.tscn`）：只读口径——占用（含盲盒占位）/ 按类别分组的物品聚合 / 盲盒仓库与邮件数；
##   ③ **许愿机页**（`wish_machine.tscn`）：**许愿机 = 设备的名字** —— 设备名 / 等级 / 本级两条效果 /
##      升级价 + 升级（走 04，真扣原石）/ 原石余额 / 盲盒开盒（走 04）/ 结果文案；
##   ④ 降级：没状态时显示「尚未开局」，没盒子时「开一次」置灰。
extends Node

var _pass := 0
var _fail := 0
## ★ 同时把结果写进 user://test_game_screen.txt：本机 runner 环境拿不到 Godot 的 stdout，
## 这条文件路径是一个可靠的旁路（正常 runner 下也只是一次无害的额外写盘）。
var _lines: Array[String] = []


func _ready() -> void:
	var banner := "=== 游戏场景测试（11-flow.md §3 / v0.29）==="
	print(banner + "\n")
	_lines.append(banner)
	FlowService.auto_scene_change = false
	GameSession.clear()
	_reset_world()
	await _test_structure()
	_reset_world()
	await _test_warehouse_page()
	_reset_world()
	await _test_wish_machine_device()
	_reset_world()
	await _test_wish_machine_open()
	FlowService.auto_scene_change = true
	var summary := "=== 结果：%d 通过 / %d 失败 ===" % [_pass, _fail]
	print("\n" + summary)
	_lines.append(summary)
	var f := FileAccess.open("user://test_game_screen.txt", FileAccess.WRITE)
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


## 每个用例都从干净的世界开始（盲盒占位/货币余额会跨用例串账，见 v0.26 的测试教训）。
func _reset_world() -> void:
	GameSession.clear()
	ItemService.reset()
	ItemService.warehouse_capacity = 100


func _make_screen():
	var packed: PackedScene = load("res://src/flow/scenes/game_screen.tscn")
	ok(packed != null, "游戏场景能载入")
	if packed == null:
		return null
	var scr = packed.instantiate()
	add_child(scr)
	await get_tree().process_frame
	return scr


# ══════════════════════════════════════════════════════════════════════════════
#  ① tab 骨架
# ══════════════════════════════════════════════════════════════════════════════

func _test_structure() -> void:
	print("— §3.0 顶层 tab：仓库 / 许愿机")
	var scr = await _make_screen()
	if scr == null:
		return
	var titles: Array = scr.tab_titles()
	eq(titles.size(), 2, "两个 tab")
	eq(titles[0], "仓库", "第 1 个 tab = 仓库")
	eq(titles[1], "许愿机", "第 2 个 tab = 许愿机")

	# ★ v0.29：两个 tab 的内容都是**独立场景实例**（不是代码拼的节点）
	var wh: Node = scr.page_node("WarehousePage")
	var wish: Node = scr.page_node("WishPage")
	ok(wh != null, "仓库页存在")
	ok(wish != null, "许愿机页存在")
	if wh != null:
		ok(String(wh.get_script().resource_path).ends_with("warehouse_page.gd"),
			"仓库页 = warehouse_page 场景实例（%s）" % wh.get_script().resource_path)
		ok(wh.has_method("snapshot"), "仓库页有只读快照接口")
	if wish != null:
		ok(String(wish.get_script().resource_path).ends_with("wish_machine.gd"),
			"许愿机页 = wish_machine 场景实例（%s）" % wish.get_script().resource_path)
		ok(wish.has_method("snapshot"), "许愿机页有只读快照接口")

	var tabs: TabContainer = scr.get_node("Tabs")
	tabs.current_tab = 1
	eq(tabs.current_tab, 1, "可以切到「许愿机」")
	tabs.current_tab = 0
	eq(tabs.current_tab, 0, "可以切回「仓库」")

	# ★ refresh() 多次调用不得重建页（否则外部持有的页引用会变成已释放实例）
	var wish_ref: Node = scr.page_node("WishPage")
	scr.refresh()
	await get_tree().process_frame
	ok(is_instance_valid(wish_ref) and scr.page_node("WishPage") == wish_ref,
		"refresh() 不会重建页（页引用保持有效）")
	scr.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════════
#  ② 仓库页
# ══════════════════════════════════════════════════════════════════════════════

func _test_warehouse_page() -> void:
	print("— §3.1 仓库页：没状态时降级")
	var scr = await _make_screen()
	if scr == null:
		return
	var wh: Node = scr.page_node("WarehousePage")
	var s0: Dictionary = wh.snapshot()
	eq(s0["boxes"], "尚未开局", "未注入状态 ⇒ 盲盒行显示「尚未开局」")

	print("— §3.1 仓库页：注入状态后读真实数据")
	var st := GameState.new_game()
	var boxes := GachaService.grant_box(st, &"series_01", 1, &"test")
	eq(boxes.size(), 1, "夹具：发 1 个盒子")
	scr.bind_state(st)
	await get_tree().process_frame
	var s1: Dictionary = wh.snapshot()
	ok(String(s1["usage"]).find("仓库占用") >= 0, "显示仓库占用（%s）" % s1["usage"])
	ok(String(s1["usage"]).find("%") >= 0, "占用用百分比表达（P6：不让玩家做除法）")
	ok(String(s1["items"]).find("还没有物品") >= 0, "空仓库时明说「还没有物品」")
	ok(String(s1["boxes"]).find("仓库 1 个") >= 0, "盲盒行：仓库 1 个（%s）" % s1["boxes"])
	ok(String(s1["boxes"]).find("邮件 0 个") >= 0, "盲盒行：邮件 0 个")

	# 物品进仓库后应当按类别分组出现
	ItemService.grant(&"home_q1", {"kind": ItemConstants.KIND_UNLOCK})
	scr.refresh()
	await get_tree().process_frame
	var s2: Dictionary = wh.snapshot()
	ok(String(s2["items"]).find("家居物品") >= 0, "物品聚合按类别分组（%s）" % s2["items"])
	ok(String(s2["items"]).find("白×1") >= 0, "同一行的档位计数（%s）" % s2["items"])
	scr.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════════
#  ③ 许愿机页（= 设备面板）
# ══════════════════════════════════════════════════════════════════════════════

func _test_wish_machine_device() -> void:
	print("— §3.2 许愿机 = 设备的名字：显示与升级")
	var st := GameState.new_game()
	var scr = await _make_screen()
	scr.bind_state(st)
	await get_tree().process_frame
	var wish: Node = scr.page_node("WishPage")
	var s: Dictionary = wish.snapshot()

	eq(s["device_name"], "许愿机", "★ 设备名就是「许愿机」")
	ok(String(s["level"]).find("Lv.1 / Lv.3") >= 0, "等级行（%s）" % s["level"])
	ok(String(s["effect"]).find("可开套系品质") >= 0, "显示本级效果：可开套系品质上限（%s）" % s["effect"])
	ok(String(s["effect"]).find("开盒成本") >= 0, "显示本级效果：开盒折扣（%s）" % s["effect"])
	eq(s["gem"], "原石 60", "显示原石余额")
	ok(String(s["upgrade_text"]).find("升级（40 原石）") >= 0, "升级价取自 04（%s）" % s["upgrade_text"])
	eq(s["upgrade_disabled"], false, "原石够 ⇒ 升级可点")
	eq(s["open_disabled"], true, "没有盒子 ⇒ 开一次置灰")

	print("— §3.2 升级：真扣原石、真升等级、面板跟着刷新")
	var gem_before := ItemService.currency_balance(ItemConstants.CURRENCY_GEM)
	var lv_before: int = DeviceService.primary_device(st).level
	var btn: Button = wish.get_node("UpgradeButton")
	btn.pressed.emit()
	await get_tree().process_frame
	eq(DeviceService.primary_device(st).level, lv_before + 1, "等级 +1")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GEM), gem_before - 40, "原石 −40")
	var s2: Dictionary = wish.snapshot()
	ok(String(s2["level"]).find("Lv.2 / Lv.3") >= 0, "面板等级行刷新（%s）" % s2["level"])
	eq(s2["gem"], "原石 20", "面板余额刷新")
	ok(String(s2["result"]).find("升级成功") >= 0, "结果行报告升级成功（%s）" % s2["result"])

	print("— §3.2 原石不够 ⇒ 升级置灰（本层只读余额，不自己判门槛）")
	ItemService.currencies.clear()
	ItemService.grant_currency(ItemConstants.CURRENCY_GEM, 0, ItemConstants.CURRENCY_SOURCE_INIT)
	scr.refresh()
	await get_tree().process_frame
	var s3: Dictionary = wish.snapshot()
	eq(s3["upgrade_disabled"], true, "原石 0 ⇒ 升级置灰")
	scr.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════════
#  ④ 许愿机页：开盒
# ══════════════════════════════════════════════════════════════════════════════

func _test_wish_machine_open() -> void:
	print("— §3.2 开盒：走 04 的入口，结果与消耗都对")
	var st := GameState.new_game()
	var boxes := GachaService.grant_box(st, &"series_01", 1, &"test")
	var bx: Box = boxes[0]
	var uses_before := bx.uses_remaining
	var inst_before := ItemService.instances.size()

	var scr = await _make_screen()
	scr.bind_state(st)
	await get_tree().process_frame
	var wish: Node = scr.page_node("WishPage")
	var s: Dictionary = wish.snapshot()
	eq(s["box_count"], 1, "下拉里出现 1 个仓库盒子")
	eq(s["open_disabled"], false, "有盒子 ⇒ 开一次可点")

	var btn: Button = wish.get_node("OpenButton")
	btn.pressed.emit()
	await get_tree().process_frame
	var s2: Dictionary = wish.snapshot()
	ok(String(s2["result"]).find("许愿机") == 0, "结果文案以「许愿机」开头（%s）" % s2["result"])
	ok(String(s2["result"]).find("许愿机开出：") >= 0 or String(s2["result"]).find("什么都没有") >= 0,
		"结果要么是物品名、要么是 void 文案（%s）" % s2["result"])
	eq(bx.uses_remaining, uses_before - 1, "寿命 −1")
	ok(ItemService.instances.size() >= inst_before, "非 void ⇒ 至少多一个实例")
	scr.queue_free()
	await get_tree().process_frame

	print("— §3.2 邮件里的盒子不可开（v0.26 的纪律在 UI 上也要成立）")
	_reset_world()
	ItemService.warehouse_capacity = 1
	var st2 := GameState.new_game()
	var b1 := GachaService.grant_box(st2, &"series_01", 2, &"test")
	eq(b1[0].location, ItemConstants.LOC_WAREHOUSE, "第一个盒子落仓库")
	eq(b1[1].location, ItemConstants.LOC_MAIL, "仓库满 ⇒ 第二个进邮件")
	var scr2 = await _make_screen()
	scr2.bind_state(st2)
	await get_tree().process_frame
	var wish2: Node = scr2.page_node("WishPage")
	eq(wish2.snapshot()["box_count"], 1, "下拉**只列仓库里的盒子**（不含邮件那个）")
	scr2.queue_free()
	await get_tree().process_frame

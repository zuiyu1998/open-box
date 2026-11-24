## 游戏场景测试（★ v0.29：两个 tab 各自是一个**独立场景**）。
##
## 断的是"**这套东西真的能用**"：
##   ① **tab 骨架**：两个 tab（仓库 / 许愿机）都是**场景实例**，可切换；
##   ② **仓库页**（`src/warehouse/scenes/warehouse_page.tscn`，★ v0.36 已从 `src/flow/scenes/` 迁出）：
##      只读口径——占用（含盲盒占位）/ 按类别分组的物品聚合 / 盲盒仓库与邮件数；
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
	await _test_tab_style_survives_first_layout()
	_reset_world()
	await _test_top_bar_currency()
	_reset_world()
	await _test_warehouse_page()
	_reset_world()
	await _test_wish_machine_device()
	_reset_world()
	await _test_wish_machine_open()
	_reset_world()
	await _test_wish_machine_layout()
	_reset_world()
	await _test_pool_editor()
	_reset_world()
	await _test_pool_overlay()
	_reset_world()
	await _test_market_page()
	_reset_world()
	await _test_tab_switch_refreshes()
	_reset_world()
	await _test_company_page()
	_reset_world()
	await _test_operator_page()
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


## 浮点近似（期望 / 概率这类数不能用 `==` 断言）。
func near(a: float, b: float, eps: float, what: String) -> void:
	ok(absf(a - b) <= eps, "%s  期望≈%.4f 实际=%.4f" % [what, b, a])


## 每个用例都从干净的世界开始（盲盒占位/货币余额会跨用例串账，见 v0.26 的测试教训）。
func _reset_world() -> void:
	GameSession.clear()
	ItemService.reset()
	ItemService.warehouse_capacity = 100
	CompanyService.reset()
	MarketService.reset()
	OperatorService.reset()


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
	print("— §3.0 顶层 tab：仓库 / 许愿机 / 市场 / 公司 / 干员")
	var scr = await _make_screen()
	if scr == null:
		return
	var titles: Array = scr.tab_titles()
	eq(titles.size(), 5, "五个 tab")
	# ★ v0.54：许愿机是第一项（核心循环先给玩家看）
	eq(titles[0], "许愿机", "第 1 个 tab = 许愿机（★ v0.54）")
	eq(titles[1], "仓库", "第 2 个 tab = 仓库")
	eq(titles[2], "市场", "第 3 个 tab = 市场（★ v0.38）")
	eq(titles[3], "公司", "第 4 个 tab = 公司（★ v0.39）")
	eq(titles[4], "干员", "第 5 个 tab = 干员（★ v0.40）")

	# ★ v0.30：tab 的内容都是**独立场景实例**（MVC：页 = View + 子节点 Controller）
	var wh: Node = scr.page_node("WarehousePage")
	var wish: Node = scr.page_node("WishPage")
	var mkt: Node = scr.page_node("MarketPage")
	var cmp: Node = scr.page_node("CompanyPage")
	var opr: Node = scr.page_node("OperatorPage")
	ok(wh != null, "仓库页存在")
	ok(wish != null, "许愿机页存在")
	ok(mkt != null, "市场页存在")
	ok(cmp != null, "公司页存在")
	ok(opr != null, "干员页存在")
	if wh != null:
		ok(String(wh.get_script().resource_path).ends_with("warehouse_view.gd"),
			"仓库页根 = warehouse_view（View）（%s）" % wh.get_script().resource_path)
		var wh_ctrl: Node = wh.get_node_or_null("Controller")
		ok(wh_ctrl != null and String(wh_ctrl.get_script().resource_path).ends_with("warehouse_controller.gd"), "仓库页有 Controller 子节点（%s）" % (wh_ctrl.get_script().resource_path if wh_ctrl else "nil"))
	if wish != null:
		ok(String(wish.get_script().resource_path).ends_with("wish_machine_view.gd"),
			"许愿机页根 = wish_machine_view（View）（%s）" % wish.get_script().resource_path)
		var ctrl: Node = wish.get_node_or_null("Controller")
		ok(ctrl != null and String(ctrl.get_script().resource_path).ends_with("wish_machine_controller.gd"),
			"许愿机页有 Controller 子节点（%s）" % (ctrl.get_script().resource_path if ctrl else "nil"))
	if mkt != null:
		ok(String(mkt.get_script().resource_path).ends_with("market_view.gd"),
			"市场页根 = market_view（View）（%s）" % mkt.get_script().resource_path)
		var mkt_ctrl: Node = mkt.get_node_or_null("Controller")
		ok(mkt_ctrl != null and String(mkt_ctrl.get_script().resource_path).ends_with("market_controller.gd"),
			"市场页有 Controller 子节点（%s）" % (mkt_ctrl.get_script().resource_path if mkt_ctrl else "nil"))
	if cmp != null:
		ok(String(cmp.get_script().resource_path).ends_with("company_view.gd"),
			"公司页根 = company_view（View）（%s）" % cmp.get_script().resource_path)
		var cmp_ctrl: Node = cmp.get_node_or_null("Controller")
		ok(cmp_ctrl != null and String(cmp_ctrl.get_script().resource_path).ends_with("company_controller.gd"),
			"公司页有 Controller 子节点（%s）" % (cmp_ctrl.get_script().resource_path if cmp_ctrl else "nil"))
	if opr != null:
		ok(String(opr.get_script().resource_path).ends_with("operator_view.gd"),
			"干员页根 = operator_view（View）（%s）" % opr.get_script().resource_path)
		var opr_ctrl: Node = opr.get_node_or_null("Controller")
		ok(opr_ctrl != null and String(opr_ctrl.get_script().resource_path).ends_with("operator_controller.gd"),
			"干员页有 Controller 子节点（%s）" % (opr_ctrl.get_script().resource_path if opr_ctrl else "nil"))

	var tabs: TabContainer = scr.get_node("Tabs")
	eq(tabs.current_tab, 0, "默认落在「许愿机」（第一个 tab）")
	tabs.current_tab = 1
	eq(tabs.current_tab, 1, "可以切到「仓库」")
	tabs.current_tab = 2
	eq(tabs.current_tab, 2, "可以切到「市场」")
	tabs.current_tab = 3
	eq(tabs.current_tab, 3, "可以切到「公司」")
	tabs.current_tab = 4
	eq(tabs.current_tab, 4, "可以切到「干员」")
	tabs.current_tab = 0
	eq(tabs.current_tab, 0, "可以切回「许愿机」")

	# ★ refresh() 多次调用不得重建页（否则外部持有的页引用会变成已释放实例）
	var wish_ref: Node = scr.page_node("WishPage")
	scr.refresh()
	await get_tree().process_frame
	ok(is_instance_valid(wish_ref) and scr.page_node("WishPage") == wish_ref,
		"refresh() 不会重建页（页引用保持有效）")

	# ★ v0.43：tab 头被加大了（默认 16px / 窄内边距在 1920×1080 上小到看不清）
	var bar: TabBar = tabs.get_tab_bar()
	ok(bar != null, "能拿到内部 TabBar（主题覆盖必须打在它身上）")
	if bar != null:
		eq(bar.get_theme_font_size("font_size"), scr.TAB_FONT_SIZE,
			"tab 字体 = %d（默认 16）" % scr.TAB_FONT_SIZE)
		var rect := bar.get_tab_rect(0)
		ok(rect.size.y >= 40.0, "tab 高度 ≥ 40px（实际 %.0f）" % rect.size.y)
		ok(rect.size.x >= 90.0, "tab 宽度 ≥ 90px（实际 %.0f）" % rect.size.x)

	# ★ v0.43：右上角有金币 / 原石读数（这是"钱够不够"的唯一常驻入口）
	ok(scr.get_node_or_null("TopBar/Gold") != null, "右上角有金币标签")
	ok(scr.get_node_or_null("TopBar/Gem") != null, "右上角有原石标签")
	scr.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════════
#  ①b 右上角：金币 / 原石（★ v0.43）
# ══════════════════════════════════════════════════════════════════════════════

func _test_top_bar_currency() -> void:
	print("— §3.0b 右上角读数：金币 / 原石")
	_reset_world()
	var st := GameState.new_game()
	var scr = await _make_screen()
	scr.bind_state(st)
	await get_tree().process_frame

	var gold: Label = scr.get_node("TopBar/Gold")
	var gem: Label = scr.get_node("TopBar/Gem")
	eq(gold.text, "金币 10000", "开局金币 10000（读 02 的余额）")
	eq(gem.text, "原石 10000", "开局原石 10000（读 02 的余额）")
	eq(gold.mouse_filter, Control.MOUSE_FILTER_IGNORE, "金币标签不吃鼠标（不挡 tab 点击）")
	eq(gem.mouse_filter, Control.MOUSE_FILTER_IGNORE, "原石标签不吃鼠标（不挡 tab 点击）")

	print("— §3.0b 余额变了 ⇒ refresh 后读数跟着变（本层不缓存）")
	ItemService.grant_currency(ItemConstants.CURRENCY_GOLD, 250,
		ItemConstants.CURRENCY_SOURCE_TASK)
	ItemService.transact([{"op": ItemConstants.OP_CURRENCY,
		"kind": ItemConstants.CURRENCY_GEM, "delta": -400}])
	scr.refresh()
	await get_tree().process_frame
	eq(gold.text, "金币 10250", "金币 +250 后刷新")
	eq(gem.text, "原石 9600", "原石 −400 后刷新")

	print("— §3.0b 无状态时也不崩（读数显示 0）")
	_reset_world()
	ItemService.currencies.clear()
	var scr2 = await _make_screen()
	await get_tree().process_frame
	eq(scr2.get_node("TopBar/Gold").text, "金币 0", "空余额 ⇒ 金币 0")
	eq(scr2.get_node("TopBar/Gem").text, "原石 0", "空余额 ⇒ 原石 0")
	scr.queue_free()
	scr2.queue_free()
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
	var s0: Dictionary = wh.get_node("Controller").snapshot()
	eq(s0["boxes"], "尚未开局", "未注入状态 ⇒ 盲盒行显示「尚未开局」")

	print("— §3.1 仓库页：注入状态后读真实数据")
	var st := GameState.new_game()
	var boxes := GachaService.grant_box(st, &"series_01", 1, &"test")
	eq(boxes.size(), 1, "夹具：发 1 个盒子")
	scr.bind_state(st)
	await get_tree().process_frame
	var s1: Dictionary = wh.get_node("Controller").snapshot()
	ok(String(s1["usage"]).find("仓库占用") >= 0, "显示仓库占用（%s）" % s1["usage"])
	ok(String(s1["usage"]).find("%") >= 0, "占用用百分比表达（P6：不让玩家做除法）")
	ok(String(s1["items"]).find("还没有物品") >= 0, "空仓库时明说「还没有物品」")
	ok(String(s1["boxes"]).find("仓库 1 个") >= 0, "盲盒行：仓库 1 个（%s）" % s1["boxes"])
	ok(String(s1["boxes"]).find("邮件 0 个") >= 0, "盲盒行：邮件 0 个")

	# 物品进仓库后应当按类别分组出现
	ItemService.grant(&"home_q1", {"kind": ItemConstants.KIND_UNLOCK})
	scr.refresh()
	await get_tree().process_frame
	var s2: Dictionary = wh.get_node("Controller").snapshot()
	ok(String(s2["items"]).find("家居物品") >= 0, "物品聚合按类别分组（%s）" % s2["items"])
	ok(String(s2["items"]).find("白×1") >= 0, "同一行的档位计数（%s）" % s2["items"])

	# ★ v0.37：网格真的接进了页面（模型算得出 ≠ 页面画得出）
	var gv = wh.grid_view()
	ok(gv != null, "仓库页有网格控件（Scroll/Grid）")
	if gv != null:
		ok(gv.has_layout(), "refresh 后网格拿到布局")
		var g: Dictionary = s2["grid"]
		eq(g["cell_size"], 128, "格子边长 128")
		# 夹具此时 = 1 个盲盒（1×1）+ 1 件物品（1×1）⇒ 2 个块
		var placed: Array = g["placed"]
		var n_item := 0
		var n_box := 0
		for p in placed:
			if String(p["kind"]) == "item":
				n_item += 1
			elif String(p["kind"]) == "box":
				n_box += 1
		eq(gv.placed_count(), placed.size(), "网格控件画出的块数 == 模型的块数")
		eq(n_item, 1, "1 件物品 ⇒ 1 个物品块")
		eq(n_box, 1, "1 个盲盒 ⇒ 1 个盲盒块（也占格）")
		eq(
			gv.custom_minimum_size,
			Vector2(int(g["columns"]) * 128, int(g["rows"]) * 128),
			"网格尺寸 = 列数 × 行数 × 128（画满容量格）"
		)
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
	var ctrl: Node = wish.get_node("Controller")
	var s: Dictionary = ctrl.snapshot()

	eq(s["device_name"], "许愿机", "★ 设备名就是「许愿机」")
	ok(String(s["level"]).find("Lv.1 / Lv.3") >= 0, "等级行（%s）" % s["level"])
	ok(String(s["effect"]).find("可开套系品质") >= 0, "显示本级效果：可开套系品质上限（%s）" % s["effect"])
	ok(String(s["effect"]).find("开盒成本") >= 0, "显示本级效果：开盒折扣（%s）" % s["effect"])
	eq(s["gem"], "原石 10000", "显示原石余额（开局 10000）")
	ok(String(s["upgrade_text"]).find("升级（40 原石）") >= 0, "升级价取自 04（%s）" % s["upgrade_text"])
	eq(s["upgrade_disabled"], false, "原石够 ⇒ 升级可点")
	eq(s["open_disabled"], true, "没有盒子 ⇒ 两个开盒按钮都置灰")

	print("— §3.2 升级：真扣原石、真升等级、面板跟着刷新")
	var gem_before := ItemService.currency_balance(ItemConstants.CURRENCY_GEM)
	var lv_before: int = DeviceService.primary_device(st).level
	var btn: Button = wish.get_node("Header/UpgradeButton")
	btn.pressed.emit()
	await get_tree().process_frame
	eq(DeviceService.primary_device(st).level, lv_before + 1, "等级 +1")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GEM), gem_before - 40, "原石 −40")
	var s2: Dictionary = ctrl.snapshot()
	ok(String(s2["level"]).find("Lv.2 / Lv.3") >= 0, "面板等级行刷新（%s）" % s2["level"])
	eq(s2["gem"], "原石 9960", "面板余额刷新（10000 − 40）")
	ok(String(s2["result"]).find("升级成功") >= 0, "结果行报告升级成功（%s）" % s2["result"])

	print("— §3.2 原石不够 ⇒ 升级置灰（本层只读余额，不自己判门槛）")
	ItemService.currencies.clear()
	ItemService.grant_currency(ItemConstants.CURRENCY_GEM, 0, ItemConstants.CURRENCY_SOURCE_INIT)
	scr.refresh()
	await get_tree().process_frame
	var s3: Dictionary = ctrl.snapshot()
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
	var ctrl: Node = wish.get_node("Controller")
	var s: Dictionary = ctrl.snapshot()
	eq(s["box_options"].size(), 1, "下拉里出现 1 个仓库盒子")
	eq(s["open_disabled"], false, "有盒子 ⇒ 两个开盒按钮可点")

	var one: Button = wish.get_node("Columns/Right/OpenButtons/OpenOne")
	var ten: Button = wish.get_node("Columns/Right/OpenButtons/OpenTen")
	var all_btn: Button = wish.get_node("Columns/Right/OpenButtons/OpenAll")
	ok(one != null and ten != null and all_btn != null, "三个开启按钮都存在")
	eq(one.text, "开启一次", "按钮文案 = 开启一次")
	eq(ten.text, "开启 10 次", "按钮文案 = 开启 10 次")
	eq(all_btn.text, "开启全部", "按钮文案 = 开启全部")
	one.pressed.emit()
	await get_tree().process_frame
	var s2: Dictionary = ctrl.snapshot()
	ok(String(s2["result"]).find("开出：") >= 0 or String(s2["result"]).find("什么都没有") >= 0,
		"结果要么是物品名、要么是 void 文案（%s）" % s2["result"])
	eq(bx.uses_remaining, uses_before - 1, "寿命 −1")
	ok(ItemService.instances.size() >= inst_before, "非 void ⇒ 至少多一个实例")

	print("— §3.2 开启全部：把该盒剩余次数一次开完（寿命归零 ⇒ 盒子被摧毁）")
	var remaining := bx.uses_remaining
	eq(remaining > 0, true, "前置：还有剩余次数（%d）" % remaining)
	ItemService.grant_currency(ItemConstants.CURRENCY_GEM, 1000000,
		ItemConstants.CURRENCY_SOURCE_INIT)   # 给足原石，避免中途因余额不足停下
	scr.refresh()
	await get_tree().process_frame
	all_btn.pressed.emit()
	await get_tree().process_frame
	eq(st.box_count(), 0, "全部开完 ⇒ 盒子寿命归零、已从清单移除")
	ok(ItemService.instances.size() >= inst_before, "产出仍在（不因盒子摧毁而丢失）")
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
	eq(wish2.get_node("Controller").snapshot()["box_options"].size(), 1, "下拉**只列仓库里的盒子**（不含邮件那个）")
	scr2.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════════
#  ④b 许愿机页：三栏布局（★ v0.41）
# ══════════════════════════════════════════════════════════════════════════════

func _test_wish_machine_layout() -> void:
	print("— §3.2b 许愿机三栏：左=盲盒/模块/产出，中=干员，右=信息/三按钮")
	_reset_world()
	OperatorService.reset()
	var st := GameState.new_game()
	var boxes := GachaService.grant_box(st, &"series_01", 1, &"test")
	var bx: Box = boxes[0]
	var scr = await _make_screen()
	scr.bind_state(st)
	await get_tree().process_frame
	var wish: Node = scr.page_node("WishPage")

	# ── 三栏骨架 ──────────────────────────────────────────────────────────────
	var left: Node = wish.get_node_or_null("Columns/Left")
	var middle: Node = wish.get_node_or_null("Columns/Middle")
	var right: Node = wish.get_node_or_null("Columns/Right")
	ok(left != null and middle != null and right != null, "从左至右三栏都存在（Left / Middle / Right）")
	# 左栏三段（顶层盲盒选择 / 中层模块镶嵌 / 下层生成物品）
	ok(left.get_node_or_null("BoxSection/BoxPicker") != null, "左栏顶层 = 盲盒选择")
	ok(left.get_node_or_null("ModuleSection/ModulePicker") != null, "左栏中层 = 模块镶嵌")
	ok(left.get_node_or_null("ResultSection/ResultLine") != null, "左栏下层 = 生成物品显示")
	# 中栏 = 干员
	ok(middle.get_node_or_null("OperatorToggle") != null, "中栏 = 干员（含出战切换）")
	# 右栏上层信息 / 下层三按钮
	ok(right.get_node_or_null("InfoSection/BoxUses") != null, "右栏上层 = 盲盒信息（使用次数）")
	ok(right.get_node_or_null("InfoSection/BoxExpectation") != null, "右栏上层 = 盲盒信息（数学期望）")
	eq(right.get_node("OpenButtons").get_child_count(), 3, "右栏下层 = 3 个开启按钮")

	# ── 右栏信息读真实值 ──────────────────────────────────────────────────────
	var ctrl: Node = wish.get_node("Controller")
	var s: Dictionary = ctrl.snapshot()
	ok(String(s["box_uses"]).find("剩余开盒次数") >= 0, "使用次数读得到（%s）" % s["box_uses"])
	# ★ v0.47：期望改成**金币口径**，且扣掉模块成本
	ok(String(s["box_expectation"]).find("单次毛期望") >= 0, "单次毛期望读得到（%s）" % s["box_expectation"])
	ok(String(s["box_expectation"]).find("金币") >= 0, "用金币作单位（不再是 TVU）")
	ok(String(s["box_expectation"]).find("净期望") >= 0, "净期望读得到")
	ok(float(s["expectation_gold_per_open"]) > 0.0, "单次毛期望 > 0（%.2f）" % s["expectation_gold_per_open"])
	eq(int(s["expectation_module_cost"]), 0, "新盒子没镶模块 ⇒ 模块成本 0")
	near(
		float(s["expectation_net"]),
		float(s["expectation_gold_per_open"]) * float(bx.uses_remaining),
		1e-6, "净期望 == 单次毛期望 × 剩余次数（无模块成本时）"
	)

	# ── 左栏中段：模块镶嵌（真镶嵌、真扣金币、真进位子）─────────────────────────
	print("— §3.2b 模块镶嵌：位子按 socket_count 渲染，镶嵌真扣金币")
	eq((s["slot_options"] as Array).size(), bx.modules.size(), "位子数 == 该盒 socket_count")
	# ⚠️ `"%s" % 数组` 会被 GDScript 当成**参数列表**展开（元素多于一就报
	#    "not all arguments converted"）⇒ 打印数组必须先 `str()`。
	ok((s["module_options"] as Array).size() > 0, "有可镶嵌的模块（%s）" % str(s["module_options"]))
	eq(left.get_node_or_null("ModuleSection/ModuleButtons/UnsocketButton"), null,
		"★ v0.44：**「拆卸」按钮已从场景里删除**")

	var gold_before := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var rev_before := bx.item_pool.revision
	var socket_btn: Button = left.get_node("ModuleSection/ModuleButtons/SocketButton")
	socket_btn.pressed.emit()
	await get_tree().process_frame
	var s2: Dictionary = ctrl.snapshot()
	ok(String(s2["result"]).find("镶嵌成功") >= 0, "镶嵌成功（%s）" % s2["result"])
	ok(bx.modules[0] != null, "第 1 位真的装上了模块")
	eq(bx.item_pool.revision, rev_before + 1, "revision +1（池子编辑的唯一失效依据）")
	ok(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD) < gold_before, "金币真扣")

	# ★ v0.47：镶了模块 ⇒ 模块成本 C 进读数，净期望 = 毛期望 × 剩余次数 − C
	eq(int(s2["expectation_module_cost"]), 20, "模块成本 = 该模块的 gold_cost（20）")
	near(
		float(s2["expectation_net"]),
		float(s2["expectation_gold_per_open"]) * float(bx.uses_remaining) - 20.0,
		1e-6, "净期望 = 单次毛期望 × 剩余次数 − 20（一次性全额扣，不摊）"
	)
	eq(bx.modules[0].module_id, &"mod_ban_home_q1", "装的是 20 金币的那个模块")

	print("— §3.2b 占用位终局：镶上即锁定，UI 不再提供任何取下入口")
	# 选中的仍是第 0 位（已占用）⇒ 镶嵌按钮必须置灰
	scr.refresh()
	await get_tree().process_frame
	var s3: Dictionary = ctrl.snapshot()
	eq(s3["socket_disabled"], true, "选中已占用的位子 ⇒ 镶嵌置灰（没有替换）")
	eq(bx.modules[0].module_id, &"mod_ban_home_q1", "原位子的模块名 = mod_ban_home_q1（原封不动）")

	# ── 中栏：干员出战切换（免费、即时影响排除）───────────────────────────────
	print("— §3.2b 中栏干员：出战切换影响排除目标")
	var op0: Dictionary = ctrl.snapshot()["operator"]
	eq(op0["active"], true, "默认出战")
	ok(String(op0["bans"]).find("排除：") >= 0, "显示排除目标（%s）" % op0["bans"])
	ok(String(op0["bans"]).find("无") < 0, "出战时排除目标非空")
	var toggle: Button = middle.get_node("OperatorToggle")
	toggle.pressed.emit()
	await get_tree().process_frame
	var op1: Dictionary = ctrl.snapshot()["operator"]
	eq(op1["active"], false, "点击后撤回")
	ok(String(op1["bans"]).find("无") >= 0, "未出战 ⇒ 排除目标清空（%s）" % op1["bans"])
	scr.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════════
#  ④c 许愿机页：池子（显示 / 隐藏 / 禁用 + 添加）★ v0.45
# ══════════════════════════════════════════════════════════════════════════════

func _test_pool_editor() -> void:
	print("— §3.2c 池子：三态轮转真改池子，摘要跟着更新")
	_reset_world()
	OperatorService.reset()
	var st := GameState.new_game()
	var boxes := GachaService.grant_box(st, &"series_01", 1, &"test")
	var bx: Box = boxes[0]
	var scr = await _make_screen()
	scr.bind_state(st)
	await get_tree().process_frame
	var wish: Node = scr.page_node("WishPage")
	var ctrl: Node = wish.get_node("Controller")
	var left: Node = wish.get_node("Columns/Left")

	ok(left.get_node_or_null("PoolSection/PoolPicker") != null, "左栏有「池子」段")

	var s: Dictionary = ctrl.snapshot()
	var n0: int = (s["pool_options"] as Array).size()
	eq(n0, bx.item_pool.base_items.size(), "池子列表 = 池内件数（%d）" % n0)
	ok(String(s["pool_summary"]).find("池子 %d 件" % n0) >= 0, "摘要报出件数（%s）" % s["pool_summary"])

	var reveal_btn: Button = left.get_node("PoolSection/PoolButtons/RevealButton")
	var disable_btn: Button = left.get_node("PoolSection/PoolButtons/DisableButton")
	var first_id: StringName = bx.item_pool.base_items[0].item_id

	print("— §3.2c 禁用：只有显示能禁用；禁用后退出分布且终局")
	eq(reveal_btn.disabled, true, "显示态的物件 ⇒「揭示」置灰（没什么可揭示的）")
	eq(disable_btn.disabled, false, "显示态 ⇒「禁用」可点")
	disable_btn.pressed.emit()
	await get_tree().process_frame
	var s1: Dictionary = ctrl.snapshot()
	eq(bx.item_pool.state_of(first_id), ItemPool.ItemState.DISABLED, "第 1 件变成禁用")
	ok(String(s1["pool_summary"]).find("禁用 1") >= 0, "摘要：禁用 1（%s）" % s1["pool_summary"])
	ok(String(s1["pool_state_text"]).find("禁用") >= 0, "状态行说明是禁用（%s）" % s1["pool_state_text"])
	eq(reveal_btn.disabled, true, "禁用后 ⇒「揭示」置灰（终局不可逆）")
	eq(disable_btn.disabled, true, "禁用后 ⇒「禁用」也置灰")
	var ps := PoolService.get_pool_state(st, bx.box_id)
	eq(ps.weights_bp.has(first_id), false, "禁用项已退出 weights_bp")
	ok(ps.is_zero_sum(), "其余物品重新归一，Σ == 10000")

	print("— §3.2c 揭示：隐藏态才能揭示；隐藏的不能直接禁用")
	# 隐藏态由数据层构造（玩家没有"显示→隐藏"这个动作）
	var second_id: StringName = bx.item_pool.base_items[1].item_id
	bx.item_pool.set_state(second_id, ItemPool.ItemState.HIDDEN)
	bx.item_pool.revision += 1
	# 在池子下拉里**选中那一件**再看按钮（按钮的可用性跟着选中项走）
	var pool_picker: OptionButton = left.get_node("PoolSection/PoolPicker")
	pool_picker.select(1)
	scr.refresh()
	await get_tree().process_frame
	var s2: Dictionary = ctrl.snapshot()
	eq(reveal_btn.disabled, false, "隐藏态 ⇒「揭示」可点")
	eq(disable_btn.disabled, true, "隐藏态 ⇒「禁用」置灰（还没揭示）")
	ok(String(s2["pool_summary"]).find("隐藏 1") >= 0, "摘要：隐藏 1（%s）" % s2["pool_summary"])
	# 直接调模型：隐藏的禁用必须被拒，并给出人能看懂的理由
	ctrl.model.disable_pool_item(1, 1)
	var s2b: Dictionary = ctrl.snapshot()
	ok(String(s2b["result"]).find("必须先揭示") >= 0, "隐藏的禁用 ⇒ 提示「必须先揭示」（%s）" % s2b["result"])
	eq(bx.item_pool.state_of(second_id), ItemPool.ItemState.HIDDEN, "状态没变")
	reveal_btn.pressed.emit()
	await get_tree().process_frame
	var s2c: Dictionary = ctrl.snapshot()
	eq(bx.item_pool.state_of(second_id), ItemPool.ItemState.SHOWN, "揭示后变成显示")
	ok(String(s2c["pool_summary"]).find("隐藏 0") >= 0, "摘要：隐藏 0（%s）" % s2c["pool_summary"])
	eq(reveal_btn.disabled, true, "揭示后 ⇒「揭示」又置灰（已是显示）")
	eq(disable_btn.disabled, false, "揭示后 ⇒「禁用」可点（它现在是显示）")

	print("— §3.2c 添加：把池外物品加进池子")
	var add_n: int = (s2c["add_options"] as Array).size()
	ok(add_n > 0, "有可添加的候选（%d 件池外物品）" % add_n)
	var add_btn: Button = left.get_node("PoolSection/AddRow/AddButton")
	add_btn.pressed.emit()
	await get_tree().process_frame
	var s4: Dictionary = ctrl.snapshot()
	eq((s4["pool_options"] as Array).size(), n0 + 1, "池子 +1 件")
	eq(bx.item_pool.base_items.size(), n0 + 1, "ItemPool 真的多了一件")
	eq(bx.item_pool.extra_item_ids.size(), 1, "记进 extra_item_ids（要落盘）")
	ok(String(s4["result"]).find("已加入池子") >= 0, "结果行报告加入成功（%s）" % s4["result"])
	ok((s4["add_options"] as Array).size() < add_n, "候选列表少了一件（它已经在池里）")
	scr.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════════
#  ⑤ 市场页
# ══════════════════════════════════════════════════════════════════════════════

func _test_market_page() -> void:
	print("— §3.3 市场页：显示金币 / 刷新倒计时 / 上架清单")
	_reset_world()
	MarketService.reset()
	var st := GameState.new_game()
	var scr = await _make_screen()
	scr.bind_state(st)
	await get_tree().process_frame
	var mkt: Node = scr.page_node("MarketPage")
	var ctrl: Node = mkt.get_node("Controller")
	var s: Dictionary = ctrl.snapshot()

	ok(String(s["gold"]).find("金币") >= 0, "显示金币余额（%s）" % s["gold"])
	ok(String(s["refresh"]).find("距刷新") >= 0, "显示刷新倒计时（%s）" % s["refresh"])
	eq((s["listing_lines"] as Array).size(), MarketService.SLOT_COUNT,
		"上架清单 = SLOT_COUNT 格")
	eq((s["buy_options"] as Array).size(), MarketService.SLOT_COUNT,
		"买入下拉选项数 == 上架格数")
	eq(s["buy_disabled"], false, "有货 ⇒ 买按钮可点")
	eq(s["sell_disabled"], true, "仓库无可售实例 ⇒ 卖按钮置灰")

	print("— §3.3 市场页：买入真扣金币、真发实例")
	# 发一笔金币足够买任意一件上架品
	ItemService.grant_currency(ItemConstants.CURRENCY_GOLD, 100000,
		ItemConstants.CURRENCY_SOURCE_INIT)
	scr.refresh()
	await get_tree().process_frame
	var gold_before := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var inst_before := ItemService.instances.size()
	var buy_btn: Button = mkt.get_node("BuyRow/BuyButton")
	buy_btn.pressed.emit()
	await get_tree().process_frame
	var s2: Dictionary = ctrl.snapshot()
	ok(String(s2["result"]).find("买入成功") >= 0, "买入成功（%s）" % s2["result"])
	ok(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD) < gold_before, "金币真扣")
	ok(ItemService.instances.size() > inst_before, "真发了一个实例")

	print("— §3.3 市场页：卖出真发金币、实例消失")
	# 现在仓库里至少有刚才买入的那一件（可售），卖按钮应可点
	var s3: Dictionary = ctrl.snapshot()
	eq(s3["sell_disabled"], false, "有可售实例 ⇒ 卖按钮可点")
	var sell_btn: Button = mkt.get_node("SellRow/SellButton")
	var gold_before_sell := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var inst_before_sell := ItemService.instances.size()
	sell_btn.pressed.emit()
	await get_tree().process_frame
	var s4: Dictionary = ctrl.snapshot()
	ok(String(s4["result"]).find("卖出成功") >= 0, "卖出成功（%s）" % s4["result"])
	ok(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD) > gold_before_sell, "金币真增")
	ok(ItemService.instances.size() < inst_before_sell, "实例被销毁")
	scr.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════════
#  ⑥ 切 tab 刷新（★ v0.38：修复"仓库页不显示新物品"）
# ══════════════════════════════════════════════════════════════════════════════

func _test_tab_switch_refreshes() -> void:
	print("— §3.4 切 tab 刷新：别处加物品后切回仓库页能看到")
	_reset_world()
	var st := GameState.new_game()
	var scr = await _make_screen()
	scr.bind_state(st)
	await get_tree().process_frame
	var wh: Node = scr.page_node("WarehousePage")
	var items_lbl: Label = wh.get_node("Items")

	ok(String(items_lbl.text).find("还没有物品") >= 0, "前置：开局仓库无物品（View 已渲染）")

	# 直接 grant 一件物品（不经过 scr.refresh()）——模拟在别的页开盒 / 买进物品
	ItemService.grant(&"home_q1", {"kind": ItemConstants.KIND_UNLOCK})
	# ★ View 的 Label 文本是上次 render 写的，未切 tab 不更新
	ok(String(items_lbl.text).find("还没有物品") >= 0, "未切 tab ⇒ View 仍是旧值（尚未刷新）")

	# ★ v0.54：默认落在许愿机（0）⇒ 切到仓库页（1）就会触发 `tab_changed` ⇒ 重新渲染出新物品
	var tabs: TabContainer = scr.get_node("Tabs")
	eq(tabs.current_tab, 0, "前置：默认在许愿机（第一个 tab）")
	tabs.current_tab = 1          # 切到仓库页
	await get_tree().process_frame
	ok(String(items_lbl.text).find("家居物品") >= 0, "切到仓库页 ⇒ View 显示新物品")
	ok(String(items_lbl.text).find("白×1") >= 0, "档位计数也更新")
	scr.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════════
#  ⑦ 公司页
# ══════════════════════════════════════════════════════════════════════════════

func _test_company_page() -> void:
	print("— §3.5 公司页：显示等级 / 路线 / 升级配方 / 产出 / 库存 / 金币")
	_reset_world()
	CompanyService.reset()
	var st := GameState.new_game()
	var scr = await _make_screen()
	scr.bind_state(st)
	await get_tree().process_frame
	var cmp: Node = scr.page_node("CompanyPage")
	var ctrl: Node = cmp.get_node("Controller")
	var s: Dictionary = ctrl.snapshot()

	ok(String(s["level"]).find("Lv.1 / Lv.5") >= 0, "显示公司等级（%s）" % s["level"])
	ok(String(s["route"]).find("标准线") >= 0, "显示培养路线（%s）" % s["route"])
	ok(String(s["upgrade_text"]).find("升级") >= 0, "显示升级按钮文案（%s）" % s["upgrade_text"])
	ok(String(s["gold"]).find("金币") >= 0, "显示金币余额（%s）" % s["gold"])

	print("— §3.5 公司页：升级真提交物品")
	# 开局仓库无物品 ⇒ 升级置灰（配方物品不足）
	eq(s["upgrade_disabled"], true, "配方物品不足 ⇒ 升级置灰")
	# 提交配方物品（home_q1 ×1）
	ItemService.grant(&"home_q1", {"kind": ItemConstants.KIND_UNLOCK})
	scr.refresh()
	await get_tree().process_frame
	var s2: Dictionary = ctrl.snapshot()
	eq(s2["upgrade_disabled"], false, "配方物品够 ⇒ 升级可点")
	var up_btn: Button = cmp.get_node("UpgradeButton")
	up_btn.pressed.emit()
	await get_tree().process_frame
	var s3: Dictionary = ctrl.snapshot()
	ok(String(s3["result"]).find("升级成功") >= 0, "升级成功（%s）" % s3["result"])
	ok(String(s3["level"]).find("Lv.2") >= 0, "面板等级刷新（%s）" % s3["level"])

	print("— §3.5 公司页：买盲盒真扣金币发盒")
	# 产出库存 + 给金币
	CompanyService.ensure_produced(1000)
	ItemService.grant_currency(ItemConstants.CURRENCY_GOLD, 100000,
		ItemConstants.CURRENCY_SOURCE_INIT)
	scr.refresh()
	await get_tree().process_frame
	var s4: Dictionary = ctrl.snapshot()
	eq(s4["buy_disabled"], false, "有库存 + 金币够 ⇒ 买盲盒可点")
	var box_before := st.box_count()
	var buy_btn: Button = cmp.get_node("BuyButton")
	buy_btn.pressed.emit()
	await get_tree().process_frame
	var s5: Dictionary = ctrl.snapshot()
	ok(String(s5["result"]).find("买入成功") >= 0, "买盲盒成功（%s）" % s5["result"])
	eq(st.box_count(), box_before + 1, "盲盒 +1（发进清单）")
	scr.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════════
#  ⑧ 干员页
# ══════════════════════════════════════════════════════════════════════════════

func _test_operator_page() -> void:
	print("— §3.6 干员页：显示等级 / 路线 / 排除目标 / 出战状态")
	_reset_world()
	OperatorService.reset()
	var st := GameState.new_game()
	var scr = await _make_screen()
	scr.bind_state(st)
	await get_tree().process_frame
	var opr: Node = scr.page_node("OperatorPage")
	var ctrl: Node = opr.get_node("Controller")
	var s: Dictionary = ctrl.snapshot()

	ok(String(s["level"]).find("Lv.1 / Lv.5") >= 0, "显示干员等级（%s）" % s["level"])
	ok(String(s["route"]).find("精准线") >= 0, "显示养成路线（%s）" % s["route"])
	ok(String(s["bans"]).find("排除") >= 0, "显示排除目标（%s）" % s["bans"])
	eq(s["toggle_active"], true, "默认出战（active == true）")
	ok(String(s["toggle_text"]).find("出战中") >= 0, "出战按钮文案（%s）" % s["toggle_text"])

	print("— §3.6 干员页：出战切换（无代价，即时生效）")
	var toggle_btn: Button = opr.get_node("ToggleButton")
	toggle_btn.pressed.emit()
	await get_tree().process_frame
	var s2: Dictionary = ctrl.snapshot()
	eq(s2["toggle_active"], false, "点击后未出战")
	ok(String(s2["bans"]).find("无排除") >= 0, "未出战 ⇒ 排除目标清空（%s）" % s2["bans"])
	toggle_btn.pressed.emit()
	await get_tree().process_frame
	var s3: Dictionary = ctrl.snapshot()
	eq(s3["toggle_active"], true, "再点恢复出战")

	print("— §3.6 干员页：升级真提交物品")
	eq(s3["upgrade_disabled"], true, "配方物品不足 ⇒ 升级置灰")
	ItemService.grant(&"home_q1", {"kind": ItemConstants.KIND_UNLOCK})
	scr.refresh()
	await get_tree().process_frame
	var s4: Dictionary = ctrl.snapshot()
	eq(s4["upgrade_disabled"], false, "配方物品够 ⇒ 升级可点")
	var up_btn: Button = opr.get_node("UpgradeButton")
	up_btn.pressed.emit()
	await get_tree().process_frame
	var s5: Dictionary = ctrl.snapshot()
	ok(String(s5["result"]).find("升级成功") >= 0, "升级成功（%s）" % s5["result"])
	ok(String(s5["level"]).find("Lv.2") >= 0, "面板等级刷新（%s）" % s5["level"])
	scr.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════════════════════
#  ④d 池子数据浮层（★ v0.50：按钮在许愿机页，浮层列池子数据）
# ══════════════════════════════════════════════════════════════════════════════

func _test_pool_overlay() -> void:
	print("— §3.2d 池子数据浮层：按钮在页面上，浮层列数据、隐藏项不列")
	_reset_world()
	OperatorService.reset()
	var st := GameState.new_game()
	var boxes := GachaService.grant_box(st, &"series_01", 1, &"test")
	var bx: Box = boxes[0]
	var scr = await _make_screen()
	scr.bind_state(st)
	await get_tree().process_frame
	var wish: Node = scr.page_node("WishPage")
	var left: Node = wish.get_node("Columns/Left")
	var overlay: Control = wish.get_node("PoolOverlayLayer/PoolOverlay")
	var rows: VBoxContainer = wish.get_node("PoolOverlayLayer/PoolOverlay/Frame/Body/Scroll/Rows")
	var note: Label = wish.get_node("PoolOverlayLayer/PoolOverlay/Frame/Body/Note")
	var totals: Label = wish.get_node("PoolOverlayLayer/PoolOverlay/Frame/Body/Totals")
	var close_btn: Button = wish.get_node("PoolOverlayLayer/PoolOverlay/Frame/Body/CloseButton")

	var data_btn: Button = left.get_node("PoolSection/PoolButtons/PoolDataButton")
	ok(data_btn != null, "许愿机页有「池子数据」按钮")
	eq(overlay.visible, false, "默认不显示浮层")

	# 基础表格：8 件全显示 ⇒ 8 行
	eq(rows.get_child_count(), bx.item_pool.base_items.size(),
		"浮层列出 %d 行（= 池内件数）" % bx.item_pool.base_items.size())
	ok(String(totals.text).find("100.00%") >= 0, "合计行给出 Σ概率 + void = 100.00%（%s）" % totals.text)
	ok(String(totals.text).find("金币") >= 0, "合计行给出金币期望")
	ok(String(note.text).find("未揭示") < 0, "没有隐藏项 ⇒ 不提示未揭示")

	print("— §3.2d 点按钮开浮层；隐藏项不列但计数提示")
	data_btn.pressed.emit()
	await get_tree().process_frame
	eq(overlay.visible, true, "点击后浮层可见")
	close_btn.pressed.emit()
	await get_tree().process_frame
	eq(overlay.visible, false, "「关闭」把它收起来")

	# 造一个隐藏项 + 一个禁用项，再刷新
	var hidden_id: StringName = bx.item_pool.base_items[0].item_id
	bx.item_pool.set_state(hidden_id, ItemPool.ItemState.HIDDEN)
	var disabled_id: StringName = bx.item_pool.base_items[1].item_id
	PoolBuff.disable(st, bx.box_id, disabled_id)
	bx.item_pool.revision += 1
	scr.refresh()
	await get_tree().process_frame
	eq(rows.get_child_count(), bx.item_pool.base_items.size() - 1,
		"隐藏项被排除 ⇒ 少一行（禁用项仍在表里）")
	ok(String(note.text).find("另有 1 件未揭示") >= 0, "提示里说明有 1 件未揭示（%s）" % note.text)
	# 禁用行：概率与权重都是 0
	var found_disabled := false
	for ch in rows.get_children():
		if ch is HBoxContainer and ch.get_child_count() >= 4:
			if String((ch.get_child(2) as Label).text) == "0":
				found_disabled = true
				eq((ch.get_child(3) as Label).text, "0.00%", "禁用行概率显示 0.00%")
	ok(found_disabled, "禁用行确实在表里（权重 0）")

	print("— §3.2d 排序：概率↓ / 价值↓ 真的换顺序（且不动数据）")
	var sort_picker: OptionButton = wish.get_node("PoolOverlayLayer/PoolOverlay/Frame/Body/SortRow/SortPicker")
	eq(sort_picker.item_count, WishMachineModel.SORT_MODES.size(), "排序下拉有 3 个选项（★ v0.52：售价并入价值）")
	eq(sort_picker.selected, 0, "默认 = 池内顺序")

	var rev_before := bx.item_pool.revision
	var weights_before := PoolService.get_pool_state(st, bx.box_id).weights_bp.duplicate()

	# 价值 ↓：首行价值必须是全表最大（★ v0.52：表只有 5 列，价值的列号 = 4）
	sort_picker.select(2)
	sort_picker.item_selected.emit(2)
	await get_tree().process_frame
	var first_val := 0
	var max_val := -1
	for ch in rows.get_children():
		if ch is HBoxContainer and ch.get_child_count() >= 5:
			max_val = maxi(max_val, int(String((ch.get_child(4) as Label).text).split(" ")[0]))
	if rows.get_child_count() > 0:
		first_val = int(String((rows.get_child(0).get_child(4) as Label).text).split(" ")[0])
	eq(first_val, max_val, "价值 ↓：首行价值 == 全表最大值（%d）" % max_val)

	# 概率 ↓
	sort_picker.select(1)
	sort_picker.item_selected.emit(1)
	await get_tree().process_frame
	var first_prob := String((rows.get_child(0).get_child(3) as Label).text)
	var max_prob := 0.0
	for ch in rows.get_children():
		if ch is HBoxContainer and ch.get_child_count() >= 6:
			max_prob = maxf(max_prob, String((ch.get_child(3) as Label).text).trim_suffix("%").to_float())
	eq(String(first_prob).trim_suffix("%").to_float(), max_prob, "概率 ↓：首行概率 == 全表最大值")

	# 排序不碰数据
	eq(bx.item_pool.revision, rev_before, "排序不推进 revision（不是写入）")
	eq(PoolService.get_pool_state(st, bx.box_id).weights_bp, weights_before, "排序不改分布")

	# 回到池内顺序
	sort_picker.select(0)
	sort_picker.item_selected.emit(0)
	await get_tree().process_frame
	eq(first_val >= 0, true, "回到池内顺序也能正常渲染")
	ok(String(note.text).find("池内顺序") >= 0, "说明行标明当前排序（%s）" % note.text)

	print("— §3.2d ★ v0.52b 打开浮层会先取最新数据（外部改动也算）")
	# 数据层直接改池子（模拟"别的系统动了池子，而本页没刷新"），不调 scr.refresh()
	var tail_id: StringName = bx.item_pool.base_items[bx.item_pool.base_items.size() - 1].item_id
	bx.item_pool.set_state(tail_id, ItemPool.ItemState.DISABLED)
	bx.item_pool.revision += 1
	# 此时浮层里还是旧数据（未渲染）
	overlay.visible = false
	data_btn.pressed.emit()
	await get_tree().process_frame
	eq(overlay.visible, true, "按钮把浮层打开了")
	var found_tail := false
	for ch in rows.get_children():
		if ch is HBoxContainer and ch.get_child_count() >= 5:
			var state_txt := String((ch.get_child(1) as Label).text)
			var weight_txt := String((ch.get_child(2) as Label).text)
			if state_txt.find("禁用") >= 0 and weight_txt == "0":
				found_tail = true
	ok(found_tail, "打开时重新取数 ⇒ 外部改的禁用项立刻反映在表里（权重 0）")

	print("— §3.2d ★ v0.52c 浮层开着时也始终最新（订阅 pool_changed）")
	# 浮层开着，直接用 buff 改池子（会发 pool_changed），**不调 refresh**
	eq(overlay.visible, true, "前置：浮层是开着的")
	var rows_before := rows.get_child_count()
	# 挑一件**当前是显示**的（隐藏的不能直接禁用，v0.48）
	var victim: StringName = &""
	for d in bx.item_pool.base_items:
		if d != null and bx.item_pool.state_of(d.item_id) == ItemPool.ItemState.SHOWN:
			victim = d.item_id
			break
	ok(victim != &"", "前置：找到一件显示态的物件（%s）" % victim)
	ok(PoolBuff.disable(st, bx.box_id, victim)["ok"], "用 buff 禁用（发出 pool_changed）")
	await get_tree().process_frame
	eq(rows.get_child_count(), rows_before, "行数不变（禁用不删行）")
	var live_ok := false
	for ch in rows.get_children():
		if ch is HBoxContainer and ch.get_child_count() >= 5:
			var st_txt := String((ch.get_child(1) as Label).text)
			var w_txt := String((ch.get_child(2) as Label).text)
			if st_txt.find("禁用") >= 0 and w_txt == "0":
				live_ok = true
	ok(live_ok, "**没有手动 refresh，浮层也立刻反映这次禁用**（订阅生效）")
	scr.queue_free()
	await get_tree().process_frame

# ══════════════════════════════════════════════════════════════════════════════
#  ①c tab 样式必须在"真实进入流程"里就位（★ v0.53）
# ══════════════════════════════════════════════════════════════════════════════

## 复现真实流程：**只把场景加进树、让它自己 `_ready`**，不调 `bind_state` / `refresh`。
##
## 这条测试是为了钉住一个真实缺陷：`_ready` 里打的 tab 覆盖会在**首次布局后被清掉**，
## 而之后直到玩家点 tab 才有下一次 `refresh()` ⇒ **一进游戏 tab 还是小的**。
## 所以这里刻意"什么都不额外调用"，只等布局完成。
func _test_tab_style_survives_first_layout() -> void:
	print("— §3.0c tab 样式在首次布局后仍生效（真实进入路径：只 _ready + 布局）")
	_reset_world()
	var st := GameState.new_game()
	GameSession.state = st
	var packed: PackedScene = load("res://src/flow/scenes/game_screen.tscn")
	var scr: Node = packed.instantiate()
	add_child(scr)                       # 不加 bind_state、不调 refresh
	await get_tree().process_frame
	await get_tree().process_frame
	var tabs: TabContainer = scr.get_node("Tabs")
	var bar: TabBar = tabs.get_tab_bar()
	eq(bar.get_theme_font_size("font_size"), scr.TAB_FONT_SIZE,
		"布局结束后字体仍是 %d（没被清回 16）" % scr.TAB_FONT_SIZE)
	var rect := bar.get_tab_rect(0)
	ok(rect.size.y >= 40.0, "布局结束后 tab 高度仍 ≥ 40px（实际 %.0f）" % rect.size.y)
	ok(rect.size.x >= 90.0, "布局结束后 tab 宽度仍 ≥ 90px（实际 %.0f）" % rect.size.x)
	scr.queue_free()
	await get_tree().process_frame
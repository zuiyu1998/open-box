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
	await _test_warehouse_page()
	_reset_world()
	await _test_wish_machine_device()
	_reset_world()
	await _test_wish_machine_open()
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
	eq(titles[0], "仓库", "第 1 个 tab = 仓库")
	eq(titles[1], "许愿机", "第 2 个 tab = 许愿机")
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
	tabs.current_tab = 1
	eq(tabs.current_tab, 1, "可以切到「许愿机」")
	tabs.current_tab = 2
	eq(tabs.current_tab, 2, "可以切到「市场」")
	tabs.current_tab = 3
	eq(tabs.current_tab, 3, "可以切到「公司」")
	tabs.current_tab = 4
	eq(tabs.current_tab, 4, "可以切到「干员」")
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
	var btn: Button = wish.get_node("UpgradeButton")
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

	var one: Button = wish.get_node("OpenButtons/OpenOne")
	var ten: Button = wish.get_node("OpenButtons/OpenTen")
	ok(one != null and ten != null, "两个开盒按钮存在")
	eq(one.text, "开一次", "按钮文案 = 开一次")
	eq(ten.text, "开 10 次", "按钮文案 = 开 10 次")
	one.pressed.emit()
	await get_tree().process_frame
	var s2: Dictionary = ctrl.snapshot()
	ok(String(s2["result"]).find("开出：") >= 0 or String(s2["result"]).find("什么都没有") >= 0,
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
	eq(wish2.get_node("Controller").snapshot()["box_options"].size(), 1, "下拉**只列仓库里的盒子**（不含邮件那个）")
	scr2.queue_free()
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

	# 切到许愿机再切回仓库 ⇒ tab_changed 触发 refresh ⇒ View 重新渲染出新物品
	var tabs: TabContainer = scr.get_node("Tabs")
	tabs.current_tab = 1
	await get_tree().process_frame
	tabs.current_tab = 0
	await get_tree().process_frame
	ok(String(items_lbl.text).find("家居物品") >= 0, "切回仓库页 ⇒ View 显示新物品")
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

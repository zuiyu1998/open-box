## 公司系统测试（14-company.md §6 的测试点）。
##
## 无头运行：
##   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
## 或直接：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . res://src/company/tests/test_company_service.tscn
##
## 退出码 0 = 全绿，1 = 有失败。
extends Node

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== 公司系统测试（14-company.md §6）===\n")

	_test_level_and_upgrade()
	_test_upgrade_atomic_on_missing_items()
	_test_upgrade_max_level()
	_test_route_mutually_exclusive()
	_test_produce_on_interval()
	_test_produce_respects_stock_cap()
	_test_buy_grants_box_and_charges()
	_test_buy_atomic_on_insufficient_gold()
	_test_buy_out_of_stock()
	_test_save_roundtrip_shape()

	print("\n=== 结果：%d 通过 / %d 失败 ===" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ══════════════════════════════════════════════════════════════════════════════
#  断言助手
# ══════════════════════════════════════════════════════════════════════════════

func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s" % what)
	else:
		_fail += 1
		print("  [FAIL] %s" % what)


func eq(a, b, what: String) -> void:
	if a == b:
		_pass += 1
		print("  [PASS] %s" % what)
	else:
		_fail += 1
		print("  [FAIL] %s  期望=%s 实际=%s" % [what, b, a])


# ══════════════════════════════════════════════════════════════════════════════
#  夹具
# ══════════════════════════════════════════════════════════════════════════════

func _setup() -> void:
	ItemCatalog.clear()
	var c := ItemCategoryDef.new()
	c.category_id = &"home"
	c.display_name = "家居"
	ItemCatalog.register_category(c)
	for kind in ItemConstants.ALL_CURRENCIES:
		var cur := CurrencyDef.new()
		cur.id = kind
		cur.display_name = String(kind)
		cur.description = "夹具"
		ItemCatalog.register_currency(cur)
	# 升级配方需要的 home_q1..q4
	for q in [1, 2, 3, 4]:
		var d := ItemDef.new()
		d.item_id = StringName("home_q%d" % q)
		d.display_name = "家居 %d" % q
		d.category = &"home"
		d.quality = q
		d.value = q
		d.size = Vector2i(1, 1)
		d.rarity = 10
		d.sell_gold = q * 2
		ItemCatalog.register(d)


func _reset() -> void:
	_setup()
	ItemService.reset()
	ItemService.warehouse_capacity = 1000
	CompanyService.reset()


func _give_items(item_id: StringName, n: int) -> void:
	for _i in n:
		ItemService.grant(item_id, {"kind": ItemConstants.KIND_UNLOCK})


func _give_gold(amount: int) -> void:
	ItemService.grant_currency(ItemConstants.CURRENCY_GOLD, amount,
		ItemConstants.CURRENCY_SOURCE_INIT)


# ══════════════════════════════════════════════════════════════════════════════
#  测试
# ══════════════════════════════════════════════════════════════════════════════

func _test_level_and_upgrade() -> void:
	_reset()
	eq(CompanyService.level, 1, "初始等级 = 1")
	var req: Dictionary = CompanyService.upgrade_requirement()
	eq(req, {&"home_q1": 1}, "1 级配方 = home_q1 ×1")

	# 没有配方物品 ⇒ 升级失败、不消耗
	var r0 := CompanyService.upgrade(null)
	ok(not r0["ok"], "无配方物品 ⇒ 升级失败")
	eq(r0["reason"], &"missing_items", "原因 = missing_items")

	# 提交 1 个 home_q1 ⇒ 升到 2 级
	_give_items(&"home_q1", 1)
	var before := ItemService.instances.size()
	var r1 := CompanyService.upgrade(null)
	ok(r1["ok"], "升级成功")
	eq(CompanyService.level, 2, "等级 1 → 2")
	eq(ItemService.instances.size(), before - 1, "配方物品被消耗（-1）")


func _test_upgrade_atomic_on_missing_items() -> void:
	_reset()
	_give_items(&"home_q1", 1)   # 只给 1 个，但 2 级配方要 home_q2 ×2
	# 先升到 2 级
	ok(CompanyService.upgrade(null)["ok"], "升到 2 级")
	var snap_before := _inst_count()
	# 2 级配方 home_q2 ×2，但一个都没有 ⇒ 失败、不消耗任何东西
	var r := CompanyService.upgrade(null)
	ok(not r["ok"], "缺配方物品 ⇒ 升级失败")
	eq(r["reason"], &"missing_items", "原因 = missing_items")
	eq(_inst_count(), snap_before, "什么都不消耗（原子）")


func _test_upgrade_max_level() -> void:
	_reset()
	# 一路喂满配方，升到 MAX_LEVEL
	for _i in CompanyService.MAX_LEVEL:
		var req: Dictionary = CompanyService.upgrade_requirement()
		for k in req.keys():
			_give_items(StringName(k), int(req[k]))
		CompanyService.upgrade(null)
	eq(CompanyService.level, CompanyService.MAX_LEVEL, "升到 MAX_LEVEL")
	var r := CompanyService.upgrade(null)
	ok(not r["ok"], "满级 ⇒ 升级失败")
	eq(r["reason"], &"max_level", "原因 = max_level")


func _test_route_mutually_exclusive() -> void:
	_reset()
	eq(CompanyService.route_id, &"standard", "默认路线 = standard")
	var r := CompanyService.current_route()
	ok(not r.is_empty(), "当前路线存在")
	ok((r.get("series", []) as Array).has(&"series_01"), "路线产出 series_01")

	# 不存在的路线 ⇒ 拒绝、状态不变
	ok(not CompanyService.select_route(&"nope"), "未知路线 ⇒ 拒绝")
	eq(CompanyService.route_id, &"standard", "路线不变")

	# 选回自己 ⇒ 幂等成功
	ok(CompanyService.select_route(&"standard"), "选已选路线 ⇒ 成功（幂等）")


func _test_produce_on_interval() -> void:
	_reset()
	eq(CompanyService.stock.size(), 0, "初始库存 0")

	# 首次 ensure_produced ⇒ 立即产一批
	CompanyService.ensure_produced(1000)
	eq(CompanyService.stock.size(), CompanyService.PRODUCTION_BATCH, "首次产出 = PRODUCTION_BATCH 盒")
	eq(StringName(CompanyService.stock[0]["series_id"]), &"series_01", "产出的是路线的 series_01")

	# 未到 1 小时 ⇒ 不再产
	CompanyService.ensure_produced(1000 + CompanyService.PRODUCTION_INTERVAL - 1)
	eq(CompanyService.stock.size(), CompanyService.PRODUCTION_BATCH, "未到周期 ⇒ 不再产")

	# 到 1 小时 ⇒ 再产一批
	CompanyService.ensure_produced(1000 + CompanyService.PRODUCTION_INTERVAL)
	eq(CompanyService.stock.size(), CompanyService.PRODUCTION_BATCH * 2, "到周期 ⇒ 再产一批")


func _test_produce_respects_stock_cap() -> void:
	_reset()
	var t := 1000
	for _i in CompanyService.STOCK_CAP + 2:
		CompanyService.ensure_produced(t)
		t += CompanyService.PRODUCTION_INTERVAL
	eq(CompanyService.stock.size(), CompanyService.STOCK_CAP, "库存封顶 = STOCK_CAP")


func _test_buy_grants_box_and_charges() -> void:
	_reset()
	CompanyService.ensure_produced(1000)
	var price: int = CompanyService.buy_price(&"series_01")
	ok(price > 0, "买价 > 0")
	_give_gold(price)

	var st := GameState.new_game()
	var gold_before := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var box_before := st.box_count()
	var stock_before := CompanyService.stock_of(&"series_01")

	var r := CompanyService.buy(&"series_01", st)
	ok(r["ok"], "买入成功")
	eq(int(r["paid"]), price, "付款 = 买价")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), gold_before - price, "金币 −买价")
	eq(st.box_count(), box_before + 1, "盲盒 +1（落仓库/邮件由 place_box 决定）")
	eq(CompanyService.stock_of(&"series_01"), stock_before - 1, "库存 −1")


func _test_buy_atomic_on_insufficient_gold() -> void:
	_reset()
	CompanyService.ensure_produced(1000)
	var st := GameState.new_game()
	# ★ new_game() 会自动发开局 10000 金币 ⇒ 显式清空，构造"金币不足"
	ItemService.currencies.clear()
	var stock_before := CompanyService.stock_of(&"series_01")
	var box_before := st.box_count()
	var r := CompanyService.buy(&"series_01", st)
	ok(not r["ok"], "金币不足 ⇒ 买入失败")
	eq(r["reason"], ItemConstants.REASON_CURRENCY_INSUFFICIENT, "原因 = currency_insufficient")
	eq(CompanyService.stock_of(&"series_01"), stock_before, "库存不减（原子）")
	eq(st.box_count(), box_before, "无新盲盒（原子）")


func _test_buy_out_of_stock() -> void:
	_reset()
	# 库存为空 ⇒ 买不到
	var st := GameState.new_game()
	_give_gold(100000)
	var r := CompanyService.buy(&"series_01", st)
	ok(not r["ok"], "无库存 ⇒ 买入失败")
	eq(r["reason"], &"out_of_stock", "原因 = out_of_stock")


func _test_save_roundtrip_shape() -> void:
	_reset()
	CompanyService.ensure_produced(1000)
	var d := CompanyService.to_save_dict()
	ok(d.has("level") and d.has("route_id") and d.has("stock") and d.has("last_production_unix"),
		"to_save_dict 含四个键")
	CompanyService.from_save_dict(d)
	var d2 := CompanyService.to_save_dict()
	eq(d2, d, "存档形状往返一致")
	# 空段 ⇒ 默认等级 1 / 默认路线 / 空库存
	CompanyService.from_save_dict({})
	eq(CompanyService.level, 1, "缺段 ⇒ 等级 1")
	eq(CompanyService.route_id, &"standard", "缺段 ⇒ 默认路线")
	eq(CompanyService.stock.size(), 0, "缺段 ⇒ 空库存")


func _inst_count() -> int:
	return ItemService.instances.size()

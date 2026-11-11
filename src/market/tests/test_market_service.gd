## 市场系统测试（13-market.md §6 的测试点）。
##
## 无头运行：
##   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
## 或直接：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . res://src/market/tests/test_market_service.tscn
##
## 退出码 0 = 全绿，1 = 有失败。
extends Node

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== 市场系统测试（13-market.md §6）===\n")

	_test_refresh_draws_tradeable_items()
	_test_refresh_is_deterministic_with_seed()
	_test_refresh_excludes_untradeable()
	_test_lazy_refresh_after_six_hours()
	_test_buy_grants_and_charges()
	_test_buy_atomic_on_insufficient_gold()
	_test_buy_no_space_rejected()
	_test_buy_sold_out()
	_test_sell_forwards_to_item_service()
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

## 注册类别 + 金币 + 一组物品（含可交易 sell_gold>0 与不可交易 sell_gold==0）。
func _setup() -> void:
	ItemCatalog.clear()
	var c := ItemCategoryDef.new()
	c.category_id = &"stardust"
	c.display_name = "星尘"
	ItemCatalog.register_category(c)
	for kind in ItemConstants.ALL_CURRENCIES:
		var cur := CurrencyDef.new()
		cur.id = kind
		cur.display_name = String(kind)
		cur.description = "夹具"
		ItemCatalog.register_currency(cur)
	# 7 个可交易物品 + 1 个不可交易物品（sell_gold = 0 不该上架）——可交易数 ≥ SLOT_COUNT
	for i in 8:
		var d := ItemDef.new()
		d.item_id = StringName("stardust_q%d" % (i + 1))
		d.display_name = "物品 %d" % (i + 1)
		d.category = &"stardust"
		d.quality = 1 + (i % 6)   # 品质 1..6 循环（不重复用同一个 (category,quality) 键，避免 V1 冲突）
		d.value = 1
		d.size = Vector2i(1, 1)
		d.rarity = 10
		# 第 8 个 sell_gold = 0（不可交易）；其余 2/4/6/8/10/12/14（买价 = ×2）
		d.sell_gold = 0 if i == 7 else (i + 1) * 2
		ItemCatalog.register(d)


func _reset() -> void:
	_setup()
	ItemService.reset()
	ItemService.warehouse_capacity = 1000
	MarketService.reset()


## 给玩家一笔金币（走 02 的唯一发放入口）。
func _give_gold(amount: int) -> void:
	ItemService.grant_currency(ItemConstants.CURRENCY_GOLD, amount,
		ItemConstants.CURRENCY_SOURCE_INIT)


# ══════════════════════════════════════════════════════════════════════════════
#  测试
# ══════════════════════════════════════════════════════════════════════════════

func _test_refresh_draws_tradeable_items() -> void:
	_reset()
	MarketService.refresh(1)
	var ls := MarketService.listings_snapshot()
	eq(ls.size(), MarketService.SLOT_COUNT, "上架格数 = SLOT_COUNT（6）")
	# 全部来自可交易物品，且互不相同
	var ids := {}
	for l in ls:
		ids[String(l["item_id"])] = true
	eq(ids.size(), ls.size(), "上架物品互不相同（不放回抽样）")
	eq(MarketService.listings_snapshot().size(), ls.size(), "快照返回副本（再次读不改状态）")


func _test_refresh_is_deterministic_with_seed() -> void:
	_reset()
	MarketService.refresh(42)
	var a := MarketService.listings_snapshot()
	MarketService.refresh(42)
	var b := MarketService.listings_snapshot()
	eq(a, b, "同 seed 两次刷新结果逐项相同（确定性）")
	MarketService.refresh(43)
	var c := MarketService.listings_snapshot()
	ok(a != c, "不同 seed ⇒ 大概率不同（覆盖不同上架）")


func _test_refresh_excludes_untradeable() -> void:
	_reset()
	# 反复多 seed 刷新：sell_gold == 0 的物品（stardust_q6）永远不上架
	for s in 20:
		MarketService.refresh(s)
		for l in MarketService.listings_snapshot():
			var id: StringName = l["item_id"]
			var def := ItemCatalog.get_def(id)
			ok(def != null and def.sell_gold > 0, "上架物品都可交易（sell_gold > 0）")
			ok(String(id) != "stardust_q8", "不可交易物品（q8）不上架")
	# 买价 = sell_gold × 2
	var found := false
	for l in MarketService.listings_snapshot():
		var def := ItemCatalog.get_def(l["item_id"])
		eq(int(l["price"]), def.sell_gold * MarketService.BUY_PRICE_MULTIPLIER,
			"买价 = sell_gold × %d" % MarketService.BUY_PRICE_MULTIPLIER)
		found = true
	ok(found, "至少有一格上架（断言了买价公式）")


func _test_lazy_refresh_after_six_hours() -> void:
	_reset()
	MarketService.refresh(1, 1000)   # 注入时间戳：上架于 t=1000
	eq(MarketService.seconds_until_refresh(1000), MarketService.REFRESH_SECONDS,
		"刚刷新 ⇒ 剩余 6 小时")

	# 还没到 6 小时：不刷新（时间戳不变）
	MarketService.ensure_fresh(1000 + MarketService.REFRESH_SECONDS - 1)
	eq(MarketService.refreshed_at_unix, 1000, "未到点 ⇒ 不刷新（时间戳不变）")

	# 恰好到 6 小时：触发自动刷新（时间戳推进到当前时刻）
	MarketService.ensure_fresh(1000 + MarketService.REFRESH_SECONDS)
	eq(MarketService.refreshed_at_unix, 1000 + MarketService.REFRESH_SECONDS,
		"到点 ⇒ 自动刷新（时间戳推进到 now）")
	eq(MarketService.seconds_until_refresh(1000 + MarketService.REFRESH_SECONDS),
		MarketService.REFRESH_SECONDS, "刷新后剩余时间重新回到 6 小时")


func _test_buy_grants_and_charges() -> void:
	_reset()
	MarketService.refresh(1)
	var ls := MarketService.listings_snapshot()
	var first: Dictionary = ls[0]
	var item_id: StringName = first["item_id"]
	var price: int = first["price"]

	_give_gold(price)
	var gold_before := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var inst_before := ItemService.instances.size()
	var stock_before := MarketService.stock_of(item_id)

	var res := MarketService.buy(item_id, 1)
	ok(res["ok"], "买入成功")
	eq(int(res["bought"]), 1, "买 1 件")
	eq(int(res["paid"]), price, "付款 = 买价")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), gold_before - price,
		"金币余额 −买价")
	eq(ItemService.instances.size(), inst_before + 1, "新实例 +1")
	eq(MarketService.stock_of(item_id), stock_before - 1, "库存 −1")

	# 新实例的来源 = market（主动 kind）
	var inst: ItemInstance = ItemService.instances[ItemService.instances.size() - 1]
	eq(inst.source.get("kind"), ItemConstants.KIND_MARKET, "买入产出的 source.kind = market")


func _test_buy_atomic_on_insufficient_gold() -> void:
	_reset()
	MarketService.refresh(1)
	var ls := MarketService.listings_snapshot()
	var first: Dictionary = ls[0]
	var item_id: StringName = first["item_id"]
	# 不给金币（余额 0）
	var stock_before := MarketService.stock_of(item_id)
	var inst_before := ItemService.instances.size()

	var res := MarketService.buy(item_id, 1)
	ok(not res["ok"], "金币不足 ⇒ 买入失败")
	eq(res["reason"], ItemConstants.REASON_CURRENCY_INSUFFICIENT, "原因 = currency_insufficient")
	eq(MarketService.stock_of(item_id), stock_before, "库存不减（原子）")
	eq(ItemService.instances.size(), inst_before, "无新实例（原子）")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), 0, "金币分文不动")


func _test_buy_no_space_rejected() -> void:
	_reset()
	ItemService.warehouse_capacity = 1
	# 先占满唯一 1 格
	ItemService.grant(&"stardust_q1", {"kind": ItemConstants.KIND_UNLOCK})
	MarketService.refresh(1)
	# 找一件上架且不等于已占物品的物品（任意一件上架物，价格无所谓）
	_give_gold(100000)
	var ls := MarketService.listings_snapshot()
	var target: StringName = ls[0]["item_id"]
	var inst_before := ItemService.instances.size()
	var gold_before := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)

	var res := MarketService.buy(target, 1)
	# 主动 kind ⇒ 放不下整笔拒绝（除非 target 恰好占 1 格也放得下——容量已满，必拒）
	ok(not res["ok"], "仓库满 ⇒ 买入被拒（主动操作不落邮件）")
	eq(ItemService.instances.size(), inst_before, "无新实例")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), gold_before, "金币分文不动")


func _test_buy_sold_out() -> void:
	_reset()
	MarketService.refresh(1)
	var ls := MarketService.listings_snapshot()
	var first: Dictionary = ls[0]
	var item_id: StringName = first["item_id"]
	_give_gold(100000)
	# 库存 = STOCK_PER_SLOT = 1 ⇒ 买 1 件后售罄
	ok(MarketService.buy(item_id, 1)["ok"], "第一次买入成功")
	eq(MarketService.stock_of(item_id), 0, "库存归零")
	var res2 := MarketService.buy(item_id, 1)
	ok(not res2["ok"], "售罄 ⇒ 再买失败")
	eq(res2["reason"], &"sold_out", "原因 = sold_out")


func _test_sell_forwards_to_item_service() -> void:
	_reset()
	var inst := ItemService.grant(&"stardust_q1", {"kind": ItemConstants.KIND_UNLOCK})
	ItemService.currencies.clear()
	var gold_before := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var res := MarketService.sell([inst.instance_id])
	ok(res["ok"], "市场卖出成功（转发 02）")
	eq(int(res["gold"]), ItemCatalog.get_def(&"stardust_q1").sell_gold,
		"卖得金币 = sell_gold（市场不另定卖价）")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), gold_before + int(res["gold"]),
		"金币余额 +卖得")


func _test_save_roundtrip_shape() -> void:
	_reset()
	MarketService.refresh(7)
	var d := MarketService.to_save_dict()
	ok(d.has("listings"), "to_save_dict 含 listings 段")
	ok(d.has("refreshed_at_unix"), "to_save_dict 含 refreshed_at_unix")
	# 往返
	MarketService.from_save_dict(d)
	var d2 := MarketService.to_save_dict()
	eq(d2, d, "存档形状往返一致（listings + 时间戳）")
	# 空段（旧档缺段）⇒ 空上架，下次 ensure_fresh 会立即刷
	MarketService.from_save_dict({})
	eq(MarketService.listings.size(), 0, "缺段 ⇒ 空上架")

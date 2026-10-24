## 套系内容测试（★ v0.26）：用**现有的物品资源**拼出来的盲盒套系能不能真的用起来。
##
## 断的是三件事：①内容真的被注册（`GachaCatalog._ready()` 自动载入）；
## ②`regular_items` 引用的是**真实物品资源**（在 `ItemCatalog` 里查得到、不重复）；
## ③拿这个套系能**发一个真盒子**（落仓库、占 1 单位、8 件物品 / 3 位 / 15 次），并且能开一次。
extends Node

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== 套系内容测试（01-gacha.md §4.1 / §5.10）===\n")
	_test_series_01_content()
	print("\n=== 结果：%d 通过 / %d 失败 ===" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [PASS] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


func eq(a, b, what: String) -> void:
	ok(a == b, "%s  期望=%s 实际=%s" % [what, str(b), str(a)])


func _test_series_01_content() -> void:
	print("— §4.1 内容：`series_01` = 现有物品资源拼出来的品质 2 套系")
	var n := GachaCatalog.load_series_content()
	ok(n >= 1, "内容目录至少载入 1 个 SeriesDef（实际 %d）" % n)
	var s := GachaCatalog.get_series(&"series_01")
	ok(s != null, "`series_01` 已注册")
	if s == null:
		return

	eq(s.series_quality, 2, "套系品质 = 2（精良）")
	eq(s.regular_count, 8, "常规物品数 = 8（品质 1–2 的曲线）")
	eq(s.regular_items.size(), 8, "`regular_items` 长度 == `regular_count`")
	eq(s.socket_count, 3, "镶嵌位 = 3（品质 2 的曲线）")
	eq(s.uses_per_box, 15, "寿命预算 = 15（`USES_PER_SOCKET` × 位数）")
	ok(s.validate().is_empty(), "套系自身校验通过（%s）" % str(s.validate()))

	print("— 引用的必须是**真实物品资源**（不是新造的空 ItemDef）")
	var ids := {}
	for d in s.regular_items:
		ok(d != null, "没有 null 物品")
		if d == null:
			continue
		ok(ItemCatalog.get_def(d.item_id) != null,
			"`%s` 在 ItemCatalog 里查得到（物品内容已载入）" % d.item_id)
		ok(not ids.has(d.item_id), "`%s` 不重复" % d.item_id)
		ids[d.item_id] = true
	eq(ids.size(), 8, "8 个不同 `item_id`")
	ok(GachaCatalog.validate()["ok"], "注册表整体校验通过（%s）" % str(GachaCatalog.validate()["errors"]))
	# 引用的是**同一份**定义：价值与权重来自物品内容（60 / 30 的白绿档）
	var first: ItemDef = s.regular_items[0]
	eq(first.value, ItemConstants.quality_value(first.quality), "物品价值取自内容阶梯")
	eq(first.rarity, ItemConstants.quality_rarity(first.quality), "物品权重取自内容阶梯")

	print("— §5.10 / v0.26：拿这个套系发一个**真盒子**（落仓库、占 1 单位）")
	ItemService.reset()
	ItemService.warehouse_capacity = 100
	var st := GameState.new_game()
	var boxes := GachaService.grant_box(st, &"series_01", 1, &"test")
	eq(boxes.size(), 1, "发出 1 个盒子")
	var b: Box = boxes[0]
	eq(b.location, ItemConstants.LOC_WAREHOUSE, "落仓库（容量够）")
	eq(b.size, 1, "占 1 单位容量")
	eq(b.uses_remaining, 15, "初始寿命 = 15")
	eq(b.item_pool.regular_count, 8, "该盒的池子有 8 件")
	eq(b.modules.size(), 3, "3 个空位（定长）")
	eq(ItemService.warehouse_usage()["used"], 1, "仓库已用 = 1（盒子自己占的）")

	print("— 能真的开一次（void 也算成功）")
	var r := GachaService.redeem(st, b, 0)
	ok(r.ok, "开盒成功（reason=%s）" % String(r.error))
	if r.ok and not r.is_void:
		ok(ItemCatalog.get_def(r.item_id) != null, "开出的物品 `%s` 来自该套系的池子" % r.item_id)
		ok(r.item_id in s.item_ids(), "`%s` 在本套系的物品清单里" % r.item_id)
	eq(b.uses_remaining, 14, "寿命 −1（开盒也会扣）")

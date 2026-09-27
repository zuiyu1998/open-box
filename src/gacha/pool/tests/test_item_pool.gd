## 物品池的产生概率测试（01-gacha.md 的池子部分 / 核心 §4.1）。
##
## 无头运行：
##   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
## 或直接：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . res://src/gacha/pool/tests/test_item_pool.tscn
##
## 退出码 0 = 全绿，1 = 有失败。
##
## v0.13：隐藏款设定已整体删除 ⇒ 全部物品共分 100%，红线 C3 随之作废。
extends Node

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== 物品池概率测试（池子部分 / 核心 §4.1）===\n")

	_test_formula_basic()
	_test_equal_rarity_is_uniform()
	_test_sum_is_exactly_10000()
	_test_probability_view_is_derived_from_bp()
	_test_output_order()
	_test_single_item()
	_test_monotonic_in_rarity()
	_test_deterministic()
	_test_twelve_items()
	_test_invalid_pools()
	_test_tiny_rarity_rounds_to_zero()

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


func near(a: float, b: float, eps: float, what: String) -> void:
	if absf(a - b) <= eps:
		_pass += 1
		print("  [PASS] %s" % what)
	else:
		_fail += 1
		print("  [FAIL] %s  期望≈%f(±%f) 实际=%f" % [what, b, eps, a])


# ══════════════════════════════════════════════════════════════════════════════
#  夹具
# ══════════════════════════════════════════════════════════════════════════════

func _mk(item_id: String, rarity: int) -> ItemDef:
	var d := ItemDef.new()
	d.item_id = StringName(item_id)
	d.display_name = item_id
	d.category = &"stardust"
	d.quality = 2
	d.value = 3
	d.size = 2
	d.rarity = rarity
	return d


## 造一个池子：`rarities` 是各物品的 rarity（v0.13：不再有隐藏款）。
func _pool(rarities: Array) -> ItemPool:
	var p := ItemPool.new()
	p.box_id = "b1"
	p.series_id = &"series_01"
	p.regular_count = rarities.size()
	p.socket_count = 3
	var i := 0
	for r in rarities:
		i += 1
		p.base_items.append(_mk("s01_%02d" % i, r))
	return p


func _sum_bp(bp: PackedInt32Array) -> int:
	var t := 0
	for v in bp:
		t += v
	return t


## 逐元素比较（不依赖 PackedInt32Array 的 == 语义）。
func _same_bp(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


# ══════════════════════════════════════════════════════════════════════════════
#  测试
# ══════════════════════════════════════════════════════════════════════════════

func _test_formula_basic() -> void:
	print("— 公式：p_i = rarity_i / Σ rarity（全部物品共分 100%）")
	var p := _pool([1, 2, 3])                 # Σ rarity = 6
	var bp := p.compute_weights_bp()
	eq(bp.size(), 3, "产出条目数 = 物品数（v0.13：没有隐藏款那一项）")
	# 精确值：10000×1/6=1666.67→1666、×2/6=3333.33→3333、×3/6=5000.00→5000
	# 取整后 Σ=9999，差 1 补给余数最大者（0.667 > 0.333 > 0）⇒ 第 1 项 +1
	eq(bp[0], 1667, "物品 1：10000×1/6 取整 + 最大余数补 1")
	eq(bp[1], 3333, "物品 2：10000×2/6 取整")
	eq(bp[2], 5000, "物品 3：10000×3/6 恰好整除")
	eq(_sum_bp(bp), 10000, "Σ == 10000（C1 零和）")

	var probs := p.compute_probabilities()
	near(probs[&"s01_01"], 0.1667, 0.00005, "概率 1 ≈ 0.1667")
	near(probs[&"s01_02"], 0.3333, 0.00005, "概率 2 ≈ 0.3333")
	near(probs[&"s01_03"], 0.5000, 0.00005, "概率 3 ≈ 0.5000")
	var total := 0.0
	for k in probs:
		total += probs[k]
	near(total, 1.0, 0.0000001, "概率之和 == 1.0")

	# 比例关系（公式的本意）：rarity 翻倍 ⇒ 概率翻倍
	near(float(bp[1]), 2.0 * float(bp[0]), 3.0, "rarity 2× ⇒ bp 约 2×")
	near(float(bp[2]), 3.0 * float(bp[0]), 3.0, "rarity 3× ⇒ bp 约 3×")


func _test_equal_rarity_is_uniform() -> void:
	print("— 退化情形：rarity 全相等 ⇒ 全部物品均等（v0.11 均等规则的推广）")
	var p := _pool([1, 1, 1])
	var bp := p.compute_weights_bp()
	eq(_sum_bp(bp), 10000, "Σ == 10000")
	# 10000/3 = 3333.33 → 3333×3 = 9999，差 1 补给余数最大者（三者同余数 ⇒ 取下标靠前者）
	eq(bp[0], 3334, "第 1 项 3334")
	eq(bp[1], 3333, "第 2 项 3333（同余数取下标靠前者）")
	eq(bp[2], 3333, "第 3 项 3333")
	var probs := p.compute_probabilities()
	near(probs[&"s01_01"], 1.0 / 3.0, 0.0001, "均等 ≈ 1/3（不再是被 2% 隐藏款挤过的 0.98/3）")
	near(probs[&"s01_01"] + probs[&"s01_02"] + probs[&"s01_03"], 1.0, 0.0000001, "三件合计 == 1.0")


func _test_sum_is_exactly_10000() -> void:
	print("— 红线 C1：任何合法配置下 Σ bp 精确 == 10000")
	var configs := [
		[1], [1, 1], [1, 1, 1], [1, 2, 3], [7, 11, 13], [1, 2, 3, 4, 5, 6, 7, 8],
		[3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
		[999, 1, 1], [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	]
	for cfg in configs:
		var bp := _pool(cfg).compute_weights_bp()
		eq(_sum_bp(bp), 10000, "配置 %s：Σ == 10000" % [cfg.size()])


func _test_probability_view_is_derived_from_bp() -> void:
	print("— 浮点视图由规范整数形态派生（不成为第二个事实来源）")
	var p := _pool([1, 2, 3, 4, 5])
	var bp := p.compute_weights_bp()
	var probs := p.compute_probabilities()
	var ids := p.item_ids()
	var all_match := true
	for i in bp.size():
		if absf(float(probs[ids[i]]) - float(bp[i]) / 10000.0) > 0.0:
			all_match = false
	ok(all_match, "每个物品：prob == bp / 10000（逐位相等，无第二次舍入）")


func _test_output_order() -> void:
	print("— 产出顺序：按 base_items 顺序（不再有隐藏物品排在最后）")
	var p := _pool([1, 2, 3])
	var ids := p.item_ids()
	eq(ids.size(), 3, "item_ids 长度 = 3")
	eq(ids[0], &"s01_01", "第 1 个是第 1 件物品")
	eq(ids[2], &"s01_03", "第 3 个是第 3 件物品")
	var probs := p.compute_probabilities()
	eq(probs.size(), 3, "概率字典与 item_ids 同长")
	eq(probs.has(&"s01_hidden"), false, "v0.13：字典里不存在任何 hidden 条目")


func _test_single_item() -> void:
	print("— 只有 1 件物品")
	var p := _pool([7])
	var bp := p.compute_weights_bp()
	eq(bp.size(), 1, "只有一项")
	eq(bp[0], 10000, "唯一物品拿走全部 100%")
	eq(_sum_bp(bp), 10000, "Σ == 10000")
	near(p.probability_of(&"s01_01"), 1.0, 0.0000001, "它的概率 == 1.0")


func _test_monotonic_in_rarity() -> void:
	print("— 单调性：rarity 更大 ⇒ 概率不会更小")
	var bp := _pool([1, 5, 20, 100]).compute_weights_bp()
	var monotonic := bp[0] <= bp[1] and bp[1] <= bp[2] and bp[2] <= bp[3]
	ok(monotonic, "bp 随 rarity 单调不减（1 < 5 < 20 < 100）")


func _test_deterministic() -> void:
	print("— 同一配置反复计算结果一致（最大余数法的同余数按下标定序）")
	var p := _pool([1, 1, 1, 1, 1, 1, 1])
	var first := p.compute_weights_bp()
	for _i in 5:
		if not _same_bp(p.compute_weights_bp(), first):
			ok(false, "多次调用结果一致")
			return
	ok(true, "多次调用结果一致")


func _test_twelve_items() -> void:
	print("— 品质 3/4 套系的 12 件物品")
	var cfg := []
	for i in 12:
		cfg.append(i + 1)                     # Σ = 78
	var p := _pool(cfg)
	eq(p.regular_count, 12, "物品数 == 12")
	eq(_sum_bp(p.compute_weights_bp()), 10000, "12 件时 Σ 仍精确 == 10000")
	ok(p.validate().is_empty(), "12 件的池子校验通过")
	var bp := p.compute_weights_bp()
	var monotonic := true
	for i in 11:
		if bp[i] > bp[i + 1]:
			monotonic = false
	ok(monotonic, "12 件时概率随 rarity 递增")


func _test_invalid_pools() -> void:
	print("— 非法池子：返回空结果 + 可读原因（不给『看起来像概率』的假数据）")
	var empty := ItemPool.new()
	ok(not empty.validate().is_empty(), "没有物品 ⇒ 校验失败")
	eq(empty.compute_weights_bp().size(), 0, "没有物品 ⇒ bp 为空数组")
	eq(empty.compute_probabilities().size(), 0, "没有物品 ⇒ 概率为空字典")

	var zero := _pool([0, 0])
	ok(not zero.validate().is_empty(), "rarity 全 0 ⇒ 校验失败（无法归一化）")
	eq(zero.compute_weights_bp().size(), 0, "rarity 全 0 ⇒ bp 为空数组")

	var one_zero := _pool([0, 1])
	ok(not one_zero.validate().is_empty(), "单件 rarity < 1 ⇒ 校验失败（0 表示永不产出）")

	# v0.13：不再有"缺隐藏物品""hidden_flag"这两条校验
	var two := _pool([1, 1])
	var reasons := ""
	for r in two.validate():
		reasons += r
	ok(not reasons.contains("hidden"), "校验原因里不再出现任何 hidden 相关条目")


func _test_tiny_rarity_rounds_to_zero() -> void:
	print("— 已记录的边界：极端 rarity 差距会把小的一件取整成 0 bp（概率 0 ⇒ 永不产出）")
	var p := _pool([1, 200000])
	var bp := p.compute_weights_bp()
	eq(bp[0], 0, "rarity=1 的那件被取整成 0 bp（0.05 bp → 0）")
	eq(bp[1], 10000, "其余全部质量归另一件")
	eq(_sum_bp(bp), 10000, "Σ 仍精确 == 10000（C1 不受影响）")
	eq(p.probability_of(&"s01_01"), 0.0, "它的概率就是 0.0")
	var zero_items := p.zero_bp_items()
	eq(zero_items.size(), 1, "zero_bp_items() 报出 1 件")
	eq(zero_items[0], &"s01_01", "报出的正是那一件")
	ok(p.validate().is_empty(), "注意：这种配置**能过** validate()——它是配置质量问题，不是结构非法")

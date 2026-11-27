## 抽取服务测试（01-gacha.md §4.4 / §5.5 / §5.6 / §7 B / §10.1–§10.2）。
##
## 无头运行：
##   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
## 或直接：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . res://src/gacha/tests/test_gacha_service.tscn
extends Node

const N := 8
const SAMPLE := 50000            # 分布抽样次数（±0.7% 容差 ≈ 4.5σ）

var _pass := 0
var _fail := 0
var _defs: Array[ItemDef] = []
## ★ v0.61：均等池（×1.5 比值断言用）
var _u_defs: Array[ItemDef] = []


func _ready() -> void:
	print("=== 抽取服务测试（01 §4.4 / §5.5 / §5.6 / §7 B）===\n")

	_test_grant_box_shape()
	_test_roll_is_deterministic()
	_test_roll_covers_void_and_matches_distribution()
	_test_roll_has_no_side_effects()
	_test_gacha_service_has_no_uuid_or_serial_math()
	_test_evaluation_invariants_and_headline()
	_test_gold_expectation_and_pool_extras()
	_test_x1_5_uses_collected_only()
	_test_redeem_consumes_box_and_grants_exactly_once()
	_test_redeem_overflow_goes_to_mail()
	_test_redeem_void_consumes_box_without_item()
	_test_generate_box()
	_test_generated_box_open_cost()
	_test_sell_price_and_sell_box()
	_test_redeem_rejects_unregistered_series()
	_test_batch_redeem_is_ordered_and_contiguous()

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

func _setup() -> void:
	ItemCatalog.clear()
	GachaCatalog.clear()
	ItemService.reset()
	ItemService.warehouse_capacity = 1000
	PoolService.drop_all_cached_states()
	EvalService.is_collected_provider = Callable()
	_defs = []
	var cats: Array[StringName] = [&"stardust", &"stardust", &"stardust", &"stardust",
		&"stardust", &"crystal", &"crystal", &"crystal"]
	var quals: Array[int] = [1, 2, 3, 4, 5, 1, 2, 3]
	var values: Array[int] = [1, 1, 3, 3, 9, 1, 3, 9]
	var rarities: Array[int] = [12, 12, 12, 11, 20, 11, 11, 11]
	for i in N:
		var d := ItemDef.new()
		d.item_id = StringName("s01_%02d" % (i + 1))
		d.display_name = "物品 %d" % (i + 1)
		d.category = cats[i]
		d.quality = quals[i]
		d.value = values[i]
		d.size = Vector2i(2, 1)   # ★ v0.37：二维尺寸（占 2 格）
		d.rarity = rarities[i]
		# ★ v0.52：价值即售价（`sell_gold` 已删除）——夹具只需要一个 `value`。
		ItemCatalog.register(d)
		_defs.append(d)

	# ★ v0.61：没有套系了 —— 夹具只造物品，盒子在 `_new_state()` 里用 `BoxTestKit` 确定性构造。
	# 均等池（用于 ×1.5 的比值断言：等 rarity 时比例才好读）
	_u_defs = []
	for i in N:
		var d2 := ItemDef.new()
		d2.item_id = StringName("u_%02d" % (i + 1))
		d2.display_name = "均等物品 %d" % (i + 1)
		d2.category = &"stardust" if i < 4 else &"crystal"
		d2.quality = (i % 4) + 1
		d2.value = 3
		d2.size = Vector2i(2, 1)
		d2.rarity = 10
		ItemCatalog.register(d2)
		_u_defs.append(d2)
	var ban := ModuleDef.new()
	ban.id = &"mod_ban_05"
	ban.quality = 2
	ban.op_type = ModuleDef.OpType.BAN
	ban.targets.append(&"s01_05")
	GachaCatalog.register_module(ban)


## 造 `n` 个盒子（池子 = `_defs` 8 件；品质 2 / 位子 3 / 寿命 15）。
## `uniform = true` ⇒ 用均等池（×1.5 比值断言用）。
func _new_state(n: int = 1, uniform: bool = false) -> Dictionary:
	_setup()
	var st := GameState.new_game()   # v0.14：走两个消耗入口的档必须有设备（开局送一台）
	var items: Array = _u_defs if uniform else _defs
	var boxes := BoxTestKit.grant(st, n, 2, items, 3, ItemConstants.box_uses(2))
	return {"state": st, "boxes": boxes}


func _eval_of(st: GameState, box: Box) -> EvalService.PoolEvaluation:
	return EvalService.evaluate_pool(PoolService.get_pool_state(st, box.box_id))


# ══════════════════════════════════════════════════════════════════════════════
#  测试
# ══════════════════════════════════════════════════════════════════════════════

func _test_grant_box_shape() -> void:
	print("— 发盒（§5.5）：未配置态 = 基础池副本 + 定长空位")
	var f := _new_state(2)
	var st: GameState = f["state"]
	var a: Box = f["boxes"][0]
	var b: Box = f["boxes"][1]
	eq(st.box_count(), 2, "囤积清单里有 2 个盒子")
	eq(a.uses_remaining, 15, "v0.14：品质 2 ⇒ 初始寿命预算 15（新曲线 10/15/20/25）")
	eq(b.uses_remaining, 15, "两个盒子各自持有自己的次数（不是共享的计数器）")
	eq(a.modules.size(), 3, "modules 定长 == socket_count")
	eq(a.item_pool.regular_count, 8, "item_pool 是基础池副本（8 件）")
	ok(a.item_pool != b.item_pool, "两盒各持一份 item_pool（**不是同一个对象**）")
	eq(a.source, &"test", "来源被记录")
	ok(b.acquired_tick >= 0, "acquired_tick 已记录")
	ok(a.item_pool.revision == 0 and b.item_pool.revision == 0, "revision 均为 0")


func _test_roll_is_deterministic() -> void:
	print("— 无状态抽取（§5.6）：同 (evaluation, seed) ⇒ 逐项相同的输出")
	var f := _new_state()
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var ev := _eval_of(st, bx)
	var first := GachaService.roll(ev, 12345)
	var same := true
	for _i in 1000:
		var r := GachaService.roll(ev, 12345)
		if r.item_id != first.item_id or r.is_void != first.is_void or r.probability != first.probability:
			same = false
	ok(same, "同一 seed 跑 1000 次结果完全相同（纯函数、无隐式状态）")
	var distinct := {}
	for s in 200:
		var r := GachaService.roll(ev, s)
		distinct[r.item_id] = true
	ok(distinct.size() >= 3, "不同 seed 会取到不同结果（200 个种子覆盖 ≥ 3 种）")
	ok(not "pity" in GachaService.roll(ev, 1).to_source().keys(), "结果里没有任何保底状态")


func _test_roll_covers_void_and_matches_distribution() -> void:
	print("— 抽样空间 = 全部物品 + **void 段（固定在末尾）**；频率与公布分布一致（§5.6）")
	var f := _new_state()
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	ok(PoolBuff.apply_module(st, bx.box_id, &"mod_ban_05", 0)["ok"], "先造出 void（排除 s01_05 ⇒ 800 bp）")
	var ev := _eval_of(st, bx)
	near(ev.void_prob, 0.08, 1e-6, "void_prob == 800 / 10000 == 0.08")

	var counts: Dictionary = {}
	var voids := 0
	var first_void_checked := false
	for i in SAMPLE:
		var r := GachaService.roll(ev, i)
		if r.is_void:
			voids += 1
			if not first_void_checked:
				first_void_checked = true
				eq(r.item_id, &"", "void 的 item_id 是空串哨兵")
				eq(r.quality, 0, "void 的 quality == 0")
				ok(not r.is_new, "void 的 is_new 恒 false")
		else:
			counts[r.item_id] = int(counts.get(r.item_id, 0)) + 1
	near(float(voids) / float(SAMPLE), 0.08, 0.007, "void 频率 ≈ 0.08（±0.7%）")
	for i in ev.probs.size():
		var id := ev.item_ids[i]
		var freq := float(int(counts.get(id, 0))) / float(SAMPLE)
		near(freq, float(ev.probs[i]), 0.007, "物品 %s 的频率 ≈ 公布概率 %.4f" % [id, ev.probs[i]])
	eq(int(counts.get(&"s01_05", 0)), 0, "被排除的物品一次都没出现（零概率就是零概率）")


func _test_roll_has_no_side_effects() -> void:
	print("— I2 抽取侧无实例化：**roll() 前后实例列表逐字段不变、grant 一次都不被调用**（§10.2）")
	var f := _new_state()
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var ev := _eval_of(st, bx)
	var size_before := ItemService.instances.size()
	var granted_before := ItemService.total_granted
	var consumed_before := ItemService.total_consumed
	var snapshot := ItemService.snapshot()
	for s in 500:
		GachaService.roll(ev, s)
	eq(ItemService.instances.size(), size_before, "实例数不变")
	eq(ItemService.total_granted, granted_before, "total_granted 不变（没有 grant）")
	eq(ItemService.total_consumed, consumed_before, "total_consumed 不变")
	var identical := true
	for i in snapshot.size():
		if snapshot[i].instance_id != ItemService.instances[i].instance_id:
			identical = false
	ok(identical, "实例列表逐项相等")
	eq(st.box_count(), 1, "roll() 不消耗盒子（消耗是 redeem 的事）")


func _test_gacha_service_has_no_uuid_or_serial_math() -> void:
	print("— 静态检查（§10.2）：抽取侧不得出现 UUID 生成 / serial 计算")
	var f := FileAccess.open("res://src/gacha/gacha_service.gd", FileAccess.READ)
	if f == null:
		ok(false, "能打开 gacha_service.gd")
		return
	var text := f.get_as_text()
	f.close()
	# ★ 01 §1 第 2 条要求 `grant_box` 用 `IUuid.v4()` 生成 **box_id**（盒子身份）；
	#   §10.2 的静态检查针对的是**抽取侧**：`roll()` / `redeem()` 不得生成实例 UUID、不得算 serial。
	#   因此这里断言的是"`IUuid.v4` 只出现在 box_id 那一行"，而不是"文件里没有这个词"。
	var uuid_lines: Array[String] = []
	for line in text.split("\n"):
		if String(line).contains("IUuid.v4"):
			uuid_lines.append(String(line))
	# ★ v0.55：多了"生成盲盒"一处（同样在建盒路径上）⇒ 允许 **2 处**，且都必须是 box_id
	# ★ v0.61：造盒统一走 `Box.make()` ⇒ 建盒身份在 box.gd 里生成，本文件不再出现 UUID
	eq(uuid_lines.size(), 0, "已抽离：`gacha_service.gd` 不再直接生成 UUID（归 `Box.make()`）")
	var bf := FileAccess.open("res://src/gacha/defs/box.gd", FileAccess.READ)
	if bf != null:
		var btext := bf.get_as_text()
		bf.close()
		ok(btext.contains("b.box_id = IUuid.v4()"), "`box.gd` 用 IUuid 生成**盒子身份**")
	ok(not text.contains("serial ="), "文件里没有对 `serial` 赋值")
	ok(not text.contains("instance_id ="), "文件里没有对 `instance_id` 赋值（实例身份归 02 的 grant）")


func _test_evaluation_invariants_and_headline() -> void:
	print("— C1 / m̄ / headline：Σprobs + void_prob 恒为 1.0；headline 取**仍可产出**的最高价值物品")
	var f := _new_state()
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var ev := _eval_of(st, bx)
	var total := ev.void_prob
	for p in ev.probs:
		total += float(p)
	near(total, 1.0, 1e-6, "未编辑池：Σprobs + void_prob == 1.0（C1）")
	ok(ev.is_normalized, "is_normalized == true")
	near(EvalService.m_bar(ev), 4.16, 1e-4,
		"m̄ == 4.16 TVU = Σ(pᵢ × vᵢ)（void 的 v = 0，不贡献）")
	var hl := EvalService.headline(ev)
	eq(hl["best_item_id"], &"s01_05", "头奖 = 价值 9 的那件（s01_05）")
	near(hl["best_item_prob"], 0.2, 1e-6, "它的概率 0.2")
	ok(PoolBuff.apply_module(st, bx.box_id, &"mod_ban_05", 0)["ok"], "把头奖排除掉")
	var ev2 := _eval_of(st, bx)
	var hl2 := EvalService.headline(ev2)
	ok(hl2["best_item_id"] != &"s01_05", "排除后 headline 换人（候选集 = 仍可产出的物品）")
	eq(hl2["best_item_id"], &"s01_08", "换成价值同为 9 的另一件（s01_08）")
	var total2 := ev2.void_prob
	for p in ev2.probs:
		total2 += float(p)
	near(total2, 1.0, 1e-6, "编辑后 C1 仍成立（Σprobs + void_prob == 1.0）")


## ★ v0.47：**金币口径的期望** + 池子追加物品后求值链仍自洽。
##
## 后者是这条测试真正的价值：v0.45 加了"往池子加物品"，而 `evaluate_pool` 当时仍以
## `series.item_ids()` 取范围 ⇒ 追加物品整个漏出分布 ⇒ `Σp < 1` ⇒ `is_normalized == false`
## ⇒ **`roll()` 直接拒开**（`bad_evaluation`）。这里把它钉死。
func _test_gold_expectation_and_pool_extras() -> void:
	print("— ★ v0.47/v0.52 金币期望：m_bar_gold = Σ(pᵢ × valueᵢ)；模块成本 = Σ gold_cost")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var ev := _eval_of(st, bx)

	# ① 金币期望：按同一组概率自己再算一遍，必须与 07 的实现相等
	var manual := 0.0
	for i in ev.item_ids.size():
		var d := ItemCatalog.get_def(ev.item_ids[i])
		manual += float(ev.probs[i]) * float(d.value)
	near(EvalService.m_bar_gold(ev), manual, 1e-6, "m_bar_gold == Σ(pᵢ × sell_goldᵢ)")
	ok(EvalService.m_bar_gold(ev) > 0.0, "金币期望 > 0（%.3f）" % EvalService.m_bar_gold(ev))
	# TVU 口径仍在（07 的 ρ 用），两者不是一回事
	near(EvalService.m_bar(ev), 4.16, 1e-4, "TVU 口径的 m̄ 仍是 4.16（没被改动）")
	# ★ v0.52：合并后两者**必须相等**（TVU 概念已退场，value 直接是金币）
	near(EvalService.m_bar(ev), EvalService.m_bar_gold(ev), 1e-9,
		"m_bar 与 m_bar_gold 现在是同一个口径（价值即金币）")

	# ② 模块成本
	eq(EvalService.module_gold_cost(bx), 0, "未镶模块 ⇒ C = 0")
	ok(PoolBuff.apply_module(st, bx.box_id, &"mod_ban_05", 0)["ok"], "镶一个模块")
	var mod := GachaCatalog.get_module(&"mod_ban_05")
	eq(EvalService.module_gold_cost(bx), mod.gold_cost, "C == 该模块的 gold_cost（%d）" % mod.gold_cost)

	# ③ ★ 回归：往池子加一件物品后，分布仍自洽、仍能开盒
	var extra := ItemDef.new()
	extra.item_id = &"extra_q1"
	extra.display_name = "池外物品"
	extra.category = &"stardust"
	extra.quality = 1
	extra.value = 50          # ★ v0.52：价值即售价，只有一个字段
	extra.size = Vector2i(1, 1)
	extra.rarity = 10
	ItemCatalog.register(extra)
	ok(PoolBuff.add_item(st, bx.box_id, &"extra_q1")["ok"], "把池外物品加进池子")

	var ev2 := _eval_of(st, bx)
	var sum := ev2.void_prob
	for p in ev2.probs:
		sum += float(p)
	near(sum, 1.0, 1e-6, "**加物品后 Σp + void 仍 == 1（C1）**")
	ok(ev2.is_normalized, "**is_normalized == true**（旧实现这里是 false）")
	eq(ev2.item_ids.size(), ev.item_ids.size() + 1, "分布范围含新物品（多一件）")
	ok(ev2.item_ids.has(&"extra_q1"), "新物品在 `item_ids` 里")
	var r := GachaService.roll(ev2, 3)
	ok(r.ok, "**加物品后仍开得动盒子**（旧实现返回 bad_evaluation）")
	ok(EvalService.m_bar_gold(ev2) > EvalService.m_bar_gold(ev), "金币期望随新物品上升")
	# 池子禁用一件后，求值范围也要跟着缩
	var target: StringName = ev2.item_ids[0]
	ok(PoolBuff.disable(st, bx.box_id, target)["ok"], "禁用一件")
	var ev3 := _eval_of(st, bx)
	ok(not ev3.item_ids.has(target), "禁用项已退出求值范围")
	var sum3 := ev3.void_prob
	for p3 in ev3.probs:
		sum3 += float(p3)
	near(sum3, 1.0, 1e-6, "禁用后 C1 仍成立（其余物品重新归一）")


func _test_x1_5_uses_collected_only() -> void:
	print("— ×1.5 的判定源 = **收藏口径**（守护裁决 11 / §5.2.1）：只认 collected，不认仓库")
	var f := _new_state(1, true)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var ev0 := EvalService.evaluate_pool(PoolService.get_pool_state(st, bx.box_id))
	near(float(ev0.probs[0]), 0.125, 1e-6, "未注入提供者 ⇒ 无加成（8 件均等 = 0.125）")

	# 全部"未拥有" ⇒ 等比放大后再归一化 ⇒ 分布不变（这是一个可断言的性质）
	EvalService.is_collected_provider = func(_id): return false
	var ev_all := EvalService.evaluate_pool(PoolService.get_pool_state(st, bx.box_id))
	near(float(ev_all.probs[0]), 0.125, 1e-6, "全部未拥有 ⇒ 等比 ×1.5 后归一化 ⇒ 分布不变")

	# 只有 1 件未拥有 ⇒ 它相对其他项获得 1.5 倍
	var target := &"u_01"
	EvalService.is_collected_provider = func(id): return StringName(id) != target
	var ev_one := EvalService.evaluate_pool(PoolService.get_pool_state(st, bx.box_id))
	var p_t := 0.0
	var p_o := 0.0
	for i in ev_one.probs.size():
		if ev_one.item_ids[i] == target:
			p_t = float(ev_one.probs[i])
		elif ev_one.item_ids[i] == &"u_02":
			p_o = float(ev_one.probs[i])
	near(p_t / p_o, 1.5, 0.02, "未拥有那一件 vs 已拥有那件 = 1.5 : 1")
	near(p_t, 1.5 / 8.5, 0.01, "未拥有那一件 ≈ 1.5 / 8.5（归一化后）")

	# **仓库口径不得被使用**：让该物品在仓库里有实例，但收藏口径仍说"已拥有" ⇒ 没有加成
	ItemService.grant(target, {"kind": ItemConstants.KIND_UNLOCK})
	EvalService.is_collected_provider = func(_id): return true
	var ev_none := EvalService.evaluate_pool(PoolService.get_pool_state(st, bx.box_id))
	near(float(ev_none.probs[0]), 0.125, 1e-6, "全部已拥有 ⇒ 无加成（仓库里有实例也不影响收藏口径）")


func _test_redeem_consumes_box_and_grants_exactly_once() -> void:
	print("— 兑现（§7 B / §10.2）：恰好一次 grant、消耗盒子、draw_index 全局递增")
	var f := _new_state()
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var ev := _eval_of(st, bx)
	var seed := _find_seed(ev, false)
	ok(seed >= 0, "找到一个会出物品的 seed")
	var size_before := ItemService.instances.size()
	var r := GachaService.redeem(st, bx, 0, seed)
	ok(r.ok, "兑现成功")
	ok(not r.is_void, "本次不是 void")
	eq(ItemService.instances.size(), size_before + 1, "**恰好产生一个新实例**")
	eq(st.box_count(), 1, "**盒子仍在清单里**（v0.14：一次兑现只消耗一次使用，不消耗盒子）")
	eq(bx.uses_remaining, 14, "使用次数 15 → 14（品质 2 的预算 15，兑现 −1）")
	eq(r.draw_index, 1, "draw_index == 1（全局计数器）")
	eq(st.draw_index, 1, "状态里的计数器同步")
	eq(r.box_id, bx.box_id, "结果记住了盒子身份")
	eq(r.item_id != &"", true, "结果记住了 item_id")
	eq(r.seed, seed, "结果记录了本次 seed")
	var inst: ItemInstance = ItemService.instances[ItemService.instances.size() - 1]
	eq(inst.item_id, r.item_id, "实例的 item_id == 结果的 item_id")
	eq(inst.source.get("kind"), ItemConstants.KIND_GACHA, "source.kind == gacha")
	eq(int(inst.source.get("quality", 0)) >= 1, true, "source 含 quality")
	eq(int(inst.source.get("box_seed")), seed, "source 含 box_seed（= 本次 seed）")
	eq(int(inst.source.get("draw_index")), 1, "source 含 draw_index")
	eq(inst.serial, 1, "开盒来源的 serial 从 1 开始（02 内部赋值）")
	eq(WarehouseService.location_of(inst.instance_id), ItemConstants.LOC_WAREHOUSE, "放得下 ⇒ 进仓库")
	eq(r.mailed, false, "★ v0.38：放得下 ⇒ r.mailed == false")
	ok(r.probability > 0.0, "结果带有本次所用分布中该结果的概率（显示与抽取同源）")


func _test_redeem_overflow_goes_to_mail() -> void:
	print("— ★ v0.38 落位可感知：仓库满 ⇒ 产出进邮件、r.mailed == true")
	var f := _new_state()
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	# 把仓库容量压到 1：q1 物品 size 1（夹具）→ 第一件占满，后续进邮件
	ItemService.warehouse_capacity = 1
	var ev := _eval_of(st, bx)
	var seed := _find_seed(ev, false)
	ok(seed >= 0, "找到一个会出物品的 seed")
	var r := GachaService.redeem(st, bx, 0, seed)
	ok(r.ok, "兑现成功")
	ok(not r.is_void, "本次不是 void")
	eq(r.mailed, true, "仓库放不下 ⇒ r.mailed == true（产出进邮件）")
	var inst: ItemInstance = ItemService.instances[ItemService.instances.size() - 1]
	eq(WarehouseService.location_of(inst.instance_id), ItemConstants.LOC_MAIL,
		"实例确实落在邮件（不是仓库）")
	eq(ItemService.instances.size(), 1, "产出不丢失（P5）：仍创建了实例")
	# 第二次也进邮件（持续超出）
	var r2 := GachaService.redeem(st, bx, 0, _find_seed(ev, false))
	eq(r2.mailed, true, "持续超出 ⇒ 仍进邮件")


func _test_redeem_void_consumes_box_without_item() -> void:
	print("— void 的兑现：**不产出任何东西，但仍消耗一次使用**（§5.6 + v0.14）")
	var f := _new_state()
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	ok(PoolBuff.apply_module(st, bx.box_id, &"mod_ban_05", 0)["ok"], "造出 void 段")
	var ev := _eval_of(st, bx)
	var seed := _find_seed(ev, true)
	ok(seed >= 0, "找到一个会出 void 的 seed")
	var size_before := ItemService.instances.size()
	var granted_before := ItemService.total_granted
	var r := GachaService.redeem(st, bx, 0, seed)
	ok(r.ok, "兑现成功（void 不是失败）")
	ok(r.is_void, "结果是 void")
	eq(r.item_id, &"", "item_id 为空串")
	eq(r.quality, 0, "quality == 0")
	eq(ItemService.instances.size(), size_before, "**没有产生任何实例**")
	eq(ItemService.total_granted, granted_before, "grant 一次都没被调用")
	eq(st.box_count(), 1, "v0.14：盒子**仍在清单里**（void 消耗的是一次使用，不是盒子）")
	eq(bx.uses_remaining, 13, "void 照样扣一次使用：装模块 −1、本次兑现 −1 ⇒ 15 → 13")
	eq(r.draw_index, 1, "draw_index 照常推进（它不是概率状态）")


func _test_redeem_rejects_unregistered_series() -> void:
	print("— ★ v0.61：套系删除后，这条用例改测「盒子用尽 / 原石不足」的拒绝分支不消耗物品")
	var f := _new_state()
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	# 原石不足 ⇒ 拒绝、且不发实例、不扣寿命
	var gems_before := ItemService.currency_balance(ItemConstants.CURRENCY_GEM)
	ItemService.grant_currency(ItemConstants.CURRENCY_GEM, -gems_before,
		ItemConstants.CURRENCY_SOURCE_INIT)
	var size_before := ItemService.instances.size()
	var uses_before := bx.uses_remaining
	var cost := DeviceService.open_cost(st, bx)
	var r := GachaService.redeem(st, bx, cost)
	ok(not r.ok, "原石不足 ⇒ 失败")
	eq(r.error, GachaService.R_CURRENCY_INSUFFICIENT, "错误码 = currency_insufficient")
	eq(ItemService.instances.size(), size_before, "没有产生实例")
	eq(bx.uses_remaining, uses_before, "**校验失败不消耗使用次数**")
	ItemService.grant_currency(ItemConstants.CURRENCY_GEM, gems_before,
		ItemConstants.CURRENCY_SOURCE_INIT)

func _test_batch_redeem_is_ordered_and_contiguous() -> void:
	print("— 批量兑现：顺序确定、`draw_index` 全局递增且连续（§10.2）")
	var f := _new_state(3)
	var st: GameState = f["state"]
	var boxes: Array = f["boxes"]
	var seeds := [11, 22, 33]
	# v0.14：第 3 个参数是**本次结算的使用次数 k**（不再是盒子数）
	var results := GachaService.redeem_batch(st, boxes, [], 3, seeds)
	eq(results.size(), 3, "返回 3 个结果（k == 3 次使用）")
	var all_ok := true
	for r in results:
		if not r.ok:
			all_ok = false
	ok(all_ok, "三个都成功")
	eq(st.box_count(), 3, "3 次结算落在第 1 个盒子上；预算 15 未耗尽 ⇒ **三个盒子都还在**")
	eq(boxes[0].uses_remaining, 15 - 3, "第 1 个盒子被扣 3 次（15 → 12；新曲线下 3 次烧不光它）")
	eq(boxes[1].uses_remaining, 15, "第 2 个盒子一次都没被碰")
	eq(results[0].draw_index, 1, "第 1 个 draw_index = 1")
	eq(results[1].draw_index, 2, "第 2 个 draw_index = 2（连续）")
	eq(results[2].draw_index, 3, "第 3 个 draw_index = 3（连续）")
	eq(st.draw_index, 3, "全局计数器 == 3")
	var non_void := 0
	for r in results:
		if not r.is_void:
			non_void += 1
	eq(ItemService.instances.size(), non_void, "实例数 == 非 void 的结果数（void 不产出）")


# ══════════════════════════════════════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════════════════════════════════════

## 扫种子找一个"会出物品 / 会出 void"的确定性种子（最多扫 20000 个）。
func _find_seed(ev: EvalService.PoolEvaluation, want_void: bool) -> int:
	for s in 20000:
		var r := GachaService.roll(ev, s)
		if r.is_void == want_void:
			return s
	return -1


# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.55：盲盒生成 / 出售
# ══════════════════════════════════════════════════════════════════════════════

func _test_generate_box() -> void:
	print("— ★ v0.55 生成：物品进池、其余随机取更低品质、品质映射、售价 = ⌈M̄ × 倍率⌉")
	var f := _new_state()
	_gen_catalog()                       # 自建目录（品质 1–6 各若干件 + 四个品质档的套系）
	var st: GameState = f["state"]

	# 品质映射（两档并一档）
	eq(GachaService.box_quality_of_item(1), 1, "物品品质 1 → 盲盒 1")
	eq(GachaService.box_quality_of_item(2), 1, "物品品质 2 → 盲盒 1")
	eq(GachaService.box_quality_of_item(3), 2, "物品品质 3 → 盲盒 2")
	eq(GachaService.box_quality_of_item(4), 2, "物品品质 4 → 盲盒 2")
	eq(GachaService.box_quality_of_item(5), 3, "物品品质 5 → 盲盒 3")
	eq(GachaService.box_quality_of_item(6), 4, "物品品质 6 → 盲盒 4")

	# 用一件品质 3 的物品生成 6 件池子
	var src := ItemCatalog.get_def(&"gen_q3_0")
	ok(src != null, "夹具里有品质 3 的物品（gen_q3_0）")
	var r := GachaService.generate_box(st, &"gen_q3_0", 6, 12345)
	ok(r["ok"], "生成成功（%s）" % String(r.get("reason", "")))
	var b: Box = r["box"]
	ok(b != null, "拿到盒子")
	eq(b.item_pool.base_items.size(), 6, "池子 6 件（件数由参数决定）")
	eq(b.item_pool.base_items[0].item_id, &"gen_q3_0", "**传入的物品是第一件**（不会被消耗）")
	eq(st.has_box(b.box_id), true, "盒子进了清单")
	eq(b.source, &"generated", "source = generated")
	eq(b.gem_cost, int(r["price"]), "返回的 price 与盒子的开盒原石价一致")
	ok(b.gem_cost >= 1, "开盒原石价 ≥ 1（%d 原石/次）" % b.gem_cost)

	# ★ v0.64：传入的物品显示，其余默认隐藏（隐藏 ≠ 禁用：照样参与抽取）
	eq(b.item_pool.state_of(&"gen_q3_0"), ItemPool.ItemState.SHOWN, "传入的物品 = 显示")
	var hidden_n := 0
	for i in range(1, b.item_pool.base_items.size()):
		if b.item_pool.state_of(b.item_pool.base_items[i].item_id) == ItemPool.ItemState.HIDDEN:
			hidden_n += 1
	eq(hidden_n, b.item_pool.base_items.size() - 1, "其余 %d 件全部**隐藏**" % (b.item_pool.base_items.size() - 1))
	eq(b.item_pool.hidden_ids().size(), b.item_pool.base_items.size() - 1, "hidden_ids 同步")
	eq(b.item_pool.enabled_items().size(), b.item_pool.base_items.size(), "**隐藏不等于禁用**：可产出数不变")
	var ps_hidden := PoolService.get_pool_state(st, b.box_id)
	eq(ps_hidden.weights_bp.size(), b.item_pool.base_items.size(), "隐藏项仍在分布里")
	ok(ps_hidden.is_zero_sum(), "Σ == 10000（隐藏不影响零和）")

	# 其余物品：品质必须 **低于** 品质 3（用户裁决）
	var all_lower := true
	for i in range(1, b.item_pool.base_items.size()):
		if b.item_pool.base_items[i].quality >= src.quality:
			all_lower = false
	ok(all_lower, "其余 %d 件的品质都低于 %d" % [b.item_pool.base_items.size() - 1, src.quality])

	# 售价 = ⌈M̄ × 1.45⌉（盲盒品质 2 ⇒ 1.25？不对：品质 3 物品 → 盲盒品质 2 ⇒ 1.25）
	var ev := EvalService.evaluate_pool(PoolService.get_pool_state(st, b.box_id))
	var q_box := GachaService.box_quality_of_item(src.quality)
	eq(q_box, 2, "盲盒品质 = 2")
	# ★ v0.56：原石价 = ⌈M̄_gold × 1.25 ÷ 10⌉（10 金币 = 1 原石），至少 1
	var expect_price := maxi(1, int(ceil(EvalService.m_bar_gold(ev) * 1.25 / 10.0)))
	eq(b.gem_cost, expect_price,
		"开盒价 = ⌈M̄ %.3f × 1.25 ÷ 10⌉ = %d 原石/次" % [EvalService.m_bar_gold(ev), expect_price])

	# 同一 seed ⇒ 同一池子（可复现）
	var f2 := _new_state()
	_gen_catalog()
	var r2 := GachaService.generate_box(f2["state"], &"gen_q3_0", 6, 12345)
	ok(r2["ok"], "第二次生成成功")
	eq((r2["box"] as Box).item_pool.item_ids(), b.item_pool.item_ids(), "同 seed ⇒ 池子逐项相同")

	# 件数 < 3 ⇒ 拒绝（C6）
	eq(GachaService.generate_box(st, &"gen_q3_0", 2, 1)["reason"], PoolService.R_BELOW_C6,
		"件数 2 ⇒ below_c6_floor（池子开不了）")
	# 未注册物品 ⇒ 拒绝
	eq(GachaService.generate_box(st, &"nope", 6, 1)["reason"], GachaService.R_ITEM_NOT_REGISTERED,
		"未注册物品 ⇒ item_not_registered")

	print("— ★ v0.55 生成：品质 1 的物品没有更低品质可抽 ⇒ 用同品质补齐（不拒绝）")
	var f3 := _new_state()
	_gen_catalog()
	var r3 := GachaService.generate_box(f3["state"], &"gen_q1_0", 6, 999)
	ok(r3["ok"], "品质 1 也能生成（同品质补齐）")
	var b3: Box = r3["box"]
	eq(b3.item_pool.base_items.size(), 6, "仍是 6 件")
	var all_q1 := true
	for d in b3.item_pool.base_items:
		if d.quality != 1:
			all_q1 = false
	ok(all_q1, "全部是品质 1（没有更低的可用）")
	var ids := b3.item_pool.item_ids()
	var uniq := {}
	for id in ids:
		uniq[id] = true
	eq(uniq.size(), 6, "6 件互不重复")


## ★ v0.55：给"生成 / 出售"用例自建的目录——品质 1–6 各若干件 + 四个品质档的套系。
## （`_setup()` 的夹具只有 8 件、且没有品质 1 / 3 / 4 档套系，凑不出可验证的样本。）
## 生成/出售用例的确定性物品列表（前 4 件，够 C6）。
func _gen_items() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for i in 4:
		out.append(ItemCatalog.get_def(&"gen_q%d_0" % (i + 1)))
	return out


func _gen_catalog() -> void:
	ItemCatalog.clear()
	GachaCatalog.clear()
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
	# 每个品质 8 件（够 6 件池子，也够"同品质补齐"）
	for q in range(1, 7):
		for i in 8:
			var d := ItemDef.new()
			d.item_id = StringName("gen_q%d_%d" % [q, i])
			d.display_name = "品质%d-%d" % [q, i]
			d.category = &"stardust"
			d.quality = q
			d.value = q * 2
			d.size = Vector2i(1, 1)
			d.rarity = 10
			ItemCatalog.register(d)


## ★ v0.56：**生成盒的原石价真的用于开盒扣费**（取代套系价；0 才回退）。
func _test_generated_box_open_cost() -> void:
	print("— ★ v0.56 开盒原石价：生成的盒子按自己的价扣、牌库盒回退到套系价")
	var f := _new_state()
	_gen_catalog()
	var st: GameState = f["state"]
	ItemService.grant_currency(ItemConstants.CURRENCY_GEM, 100,
		ItemConstants.CURRENCY_SOURCE_INIT)
	var r := GachaService.generate_box(st, &"gen_q3_0", 6, 4242)
	ok(r["ok"], "先生成一个盒子")
	var b: Box = r["box"]
	ok(b.gem_cost >= 1, "盒子带自己的原石价（%d）" % b.gem_cost)

	# 等级 1 的设备 open_cost_bp = 10000 ⇒ 实付 == 盒子自己写的价
	eq(DeviceService.open_cost(st, b), b.gem_cost,
		"开盒价 = 盒子自己的 gem_cost（设备 1 级 bp=10000）")

	# 真开一次：原石按这个价扣
	var gems_before := ItemService.currency_balance(ItemConstants.CURRENCY_GEM)
	var uses_before := b.uses_remaining
	var gr := DeviceService.redeem(st, b)
	ok(gr.ok, "开盒成功（error=%s）" % String(gr.error))
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GEM), gems_before - b.gem_cost,
		"**原石按盒子的价扣掉了 %d**" % b.gem_cost)
	eq(b.uses_remaining, uses_before - 1, "寿命 −1")

	# 牌库发的盒子：开盒价 = **该品质的默认价**（v0.61：盒子自己存）
	var granted := BoxTestKit.grant(st, 1, 2, _gen_items(), 3)[0]
	eq(int(granted.gem_cost), ItemConstants.box_gem_cost(2), "牌库盒子按品质默认价")
	eq(DeviceService.open_cost(st, granted), granted.gem_cost,
		"开盒价 = 盒子自己的 gem_cost（%d）" % granted.gem_cost)

## ★ v0.59：盲盒的**售出价格**（按品质固定表）+ 卖盒入口。
func _test_sell_price_and_sell_box() -> void:
	print("— ★ v0.59 卖价表：品质 1–4 → 20 / 50 / 120 / 300 金币；牌库盒也能卖")
	var f := _new_state()
	_gen_catalog()
	var st: GameState = f["state"]

	# 盲盒品质 1..4 各造一个（材料要选映射到该档的：1–2→1、3–4→2、5→3、6→4）
	var expect := {1: 20, 2: 50, 3: 120, 4: 300}
	var src_for := {1: &"gen_q1_0", 2: &"gen_q3_0", 3: &"gen_q5_0", 4: &"gen_q6_0"}
	for q in range(1, 5):
		var made := GachaService.generate_box(st, src_for[q], 4, 100 + q)
		ok(made["ok"], "用材料 %s 生成盲盒品质 %d" % [String(src_for[q]), q])
		eq(GachaService.box_quality_of_item(ItemCatalog.get_def(src_for[q]).quality), q,
			"材料品质映射到盲盒品质 %d" % q)
		eq(GachaService.sell_price_gold(made["box"]), expect[q],
			"盲盒品质 %d ⇒ 卖价 %d 金币" % [q, expect[q]])

	# 牌库发的盒子也有保底卖价（用户裁决）
	var granted := BoxTestKit.grant(st, 1, 3, _gen_items(), 4)[0]
	eq(GachaService.sell_price_gold(granted), 120, "牌库发的品质 3 盒也能卖 120 金币")

	# 真卖：金币到账、盒子消失
	var gold_before := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var sold := GachaService.sell_box(st, granted.box_id)
	ok(sold["ok"], "卖出成功")
	eq(int(sold["gold"]), 120, "卖得 120 金币")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), gold_before + 120, "金币余额 +120")
	eq(st.has_box(granted.box_id), false, "盒子已销毁")
	eq(String(GachaService.sell_box(st, granted.box_id)["reason"]), "box_not_found",
		"再卖同一盒 ⇒ box_not_found")

	# 邮件里的盒子不可卖
	var mailed := BoxTestKit.grant(st, 1, 1, _gen_items(), 2)[0]
	mailed.location = ItemConstants.LOC_MAIL
	eq(GachaService.sell_box(st, mailed.box_id)["reason"], ItemConstants.REASON_BOX_IN_MAIL,
		"邮件里的盒子 ⇒ box_in_mail")
	eq(st.has_box(mailed.box_id), true, "拒卖时盒子还在")
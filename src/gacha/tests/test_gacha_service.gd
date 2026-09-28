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


func _ready() -> void:
	print("=== 抽取服务测试（01 §4.4 / §5.5 / §5.6 / §7 B）===\n")

	_test_grant_box_shape()
	_test_roll_is_deterministic()
	_test_roll_covers_void_and_matches_distribution()
	_test_roll_has_no_side_effects()
	_test_gacha_service_has_no_uuid_or_serial_math()
	_test_evaluation_invariants_and_headline()
	_test_x1_5_uses_collected_only()
	_test_redeem_consumes_box_and_grants_exactly_once()
	_test_redeem_void_consumes_box_without_item()
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
		d.size = 2
		d.rarity = rarities[i]
		ItemCatalog.register(d)
		_defs.append(d)

	var graded := SeriesDef.new()
	graded.series_id = &"series_01"
	graded.series_quality = 2
	graded.regular_count = N
	graded.socket_count = 3
	graded.regular_items = _defs.duplicate()
	GachaCatalog.register_series(graded)

	# 均等池（用于 ×1.5 的比值断言：等 rarity 时比例才好读）
	var uniform := SeriesDef.new()
	uniform.series_id = &"series_uniform"
	uniform.series_quality = 2
	uniform.regular_count = N
	uniform.socket_count = 3
	var u_defs: Array[ItemDef] = []
	for i in N:
		var d2 := ItemDef.new()
		d2.item_id = StringName("u_%02d" % (i + 1))
		d2.display_name = "均等物品 %d" % (i + 1)
		d2.category = &"stardust" if i < 4 else &"crystal"
		d2.quality = (i % 4) + 1
		d2.value = 3
		d2.size = 2
		d2.rarity = 10
		ItemCatalog.register(d2)
		u_defs.append(d2)
	uniform.regular_items = u_defs
	GachaCatalog.register_series(uniform)

	var ban := ModuleDef.new()
	ban.id = &"mod_ban_05"
	ban.quality = 2
	ban.op_type = ModuleDef.OpType.BAN
	ban.targets.append(&"s01_05")
	GachaCatalog.register_module(ban)


func _new_state(sid: StringName = &"series_01", n: int = 1) -> Dictionary:
	_setup()
	var st := GameState.new_game()   # v0.14：走两个消耗入口的档必须有设备（开局送一台）
	var boxes := GachaService.grant_box(st, sid, n, &"test")
	return {"state": st, "boxes": boxes}


func _eval_of(st: GameState, box: Box) -> EvalService.PoolEvaluation:
	var series := GachaCatalog.get_series(box.series_id)
	return EvalService.evaluate_pool(PoolService.get_pool_state(st, box.box_id), series)


# ══════════════════════════════════════════════════════════════════════════════
#  测试
# ══════════════════════════════════════════════════════════════════════════════

func _test_grant_box_shape() -> void:
	print("— 发盒（§5.5）：未配置态 = 基础池副本 + 定长空位")
	var f := _new_state(&"series_01", 2)
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
	ok(PoolService.socket(st, bx.box_id, &"mod_ban_05", 0)["ok"], "先造出 void（排除 s01_05 ⇒ 800 bp）")
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
	# ★ 01 §1 第 2 条要求 `grant_box` 用 `Uuid.v4()` 生成 **box_id**（盒子身份）；
	#   §10.2 的静态检查针对的是**抽取侧**：`roll()` / `redeem()` 不得生成实例 UUID、不得算 serial。
	#   因此这里断言的是"`Uuid.v4` 只出现在 box_id 那一行"，而不是"文件里没有这个词"。
	var uuid_lines: Array[String] = []
	for line in text.split("\n"):
		if String(line).contains("Uuid.v4"):
			uuid_lines.append(String(line))
	eq(uuid_lines.size(), 1, "`Uuid.v4` 只出现 1 次")
	ok(uuid_lines.size() == 1 and uuid_lines[0].contains("box_id"),
		"那一次是盒子身份（box_id），不是实例身份")
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
	near(EvalService.m_bar(ev, GachaCatalog.get_series(&"series_01")), 4.16, 1e-4,
		"m̄ == 4.16 TVU = Σ(pᵢ × vᵢ)（void 的 v = 0，不贡献）")
	var hl := EvalService.headline(ev, GachaCatalog.get_series(&"series_01"))
	eq(hl["best_item_id"], &"s01_05", "头奖 = 价值 9 的那件（s01_05）")
	near(hl["best_item_prob"], 0.2, 1e-6, "它的概率 0.2")
	ok(PoolService.socket(st, bx.box_id, &"mod_ban_05", 0)["ok"], "把头奖排除掉")
	var ev2 := _eval_of(st, bx)
	var hl2 := EvalService.headline(ev2, GachaCatalog.get_series(&"series_01"))
	ok(hl2["best_item_id"] != &"s01_05", "排除后 headline 换人（候选集 = 仍可产出的物品）")
	eq(hl2["best_item_id"], &"s01_08", "换成价值同为 9 的另一件（s01_08）")
	var total2 := ev2.void_prob
	for p in ev2.probs:
		total2 += float(p)
	near(total2, 1.0, 1e-6, "编辑后 C1 仍成立（Σprobs + void_prob == 1.0）")


func _test_x1_5_uses_collected_only() -> void:
	print("— ×1.5 的判定源 = **收藏口径**（守护裁决 11 / §5.2.1）：只认 collected，不认仓库")
	var f := _new_state(&"series_uniform", 1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var series := GachaCatalog.get_series(&"series_uniform")
	var ev0 := EvalService.evaluate_pool(PoolService.get_pool_state(st, bx.box_id), series)
	near(float(ev0.probs[0]), 0.125, 1e-6, "未注入提供者 ⇒ 无加成（8 件均等 = 0.125）")

	# 全部"未拥有" ⇒ 等比放大后再归一化 ⇒ 分布不变（这是一个可断言的性质）
	EvalService.is_collected_provider = func(_id): return false
	var ev_all := EvalService.evaluate_pool(PoolService.get_pool_state(st, bx.box_id), series)
	near(float(ev_all.probs[0]), 0.125, 1e-6, "全部未拥有 ⇒ 等比 ×1.5 后归一化 ⇒ 分布不变")

	# 只有 1 件未拥有 ⇒ 它相对其他项获得 1.5 倍
	var target := &"u_01"
	EvalService.is_collected_provider = func(id): return StringName(id) != target
	var ev_one := EvalService.evaluate_pool(PoolService.get_pool_state(st, bx.box_id), series)
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
	var ev_none := EvalService.evaluate_pool(PoolService.get_pool_state(st, bx.box_id), series)
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
	var r := GachaService.redeem(st, bx, seed)
	ok(r.ok, "兑现成功")
	ok(not r.is_void, "本次不是 void")
	eq(ItemService.instances.size(), size_before + 1, "**恰好产生一个新实例**")
	eq(st.box_count(), 1, "**盒子仍在清单里**（v0.14：一次兑现只消耗一次使用，不消耗盒子）")
	eq(bx.uses_remaining, 14, "使用次数 15 → 14（品质 2 的预算 15，兑现 −1）")
	eq(r.draw_index, 1, "draw_index == 1（全局计数器）")
	eq(st.draw_index, 1, "状态里的计数器同步")
	eq(r.box_id, bx.box_id, "结果记住了盒子身份")
	eq(r.series_id, &"series_01", "结果记住了套系")
	eq(r.seed, seed, "结果记录了本次 seed")
	var inst: ItemInstance = ItemService.instances[ItemService.instances.size() - 1]
	eq(inst.item_id, r.item_id, "实例的 item_id == 结果的 item_id")
	eq(inst.source.get("kind"), ItemConstants.KIND_GACHA, "source.kind == gacha")
	eq(inst.source.get("series_id"), "series_01", "source 含 series_id")
	eq(int(inst.source.get("box_seed")), seed, "source 含 box_seed（= 本次 seed）")
	eq(int(inst.source.get("draw_index")), 1, "source 含 draw_index")
	eq(inst.serial, 1, "开盒来源的 serial 从 1 开始（02 内部赋值）")
	eq(inst.location, ItemConstants.LOC_WAREHOUSE, "放得下 ⇒ 进仓库")
	ok(r.probability > 0.0, "结果带有本次所用分布中该结果的概率（显示与抽取同源）")


func _test_redeem_void_consumes_box_without_item() -> void:
	print("— void 的兑现：**不产出任何东西，但仍消耗一次使用**（§5.6 + v0.14）")
	var f := _new_state()
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	ok(PoolService.socket(st, bx.box_id, &"mod_ban_05", 0)["ok"], "造出 void 段")
	var ev := _eval_of(st, bx)
	var seed := _find_seed(ev, true)
	ok(seed >= 0, "找到一个会出 void 的 seed")
	var size_before := ItemService.instances.size()
	var granted_before := ItemService.total_granted
	var r := GachaService.redeem(st, bx, seed)
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
	print("— 校验失败 ⇒ **盲盒不消耗、不发物品**（§7 B 的拒绝分支）")
	var f := _new_state()
	var st: GameState = f["state"]
	var tmp := Box.new()
	tmp.box_id = Uuid.v4()
	tmp.series_id = &"series_offline"
	tmp.item_pool = PoolService.init_pool(st, tmp.box_id, &"series_01")
	tmp.modules = PoolService.empty_slots(3)
	tmp.uses_remaining = 3        # v0.14：真实发放的盒子必然 > 0（默认 0 现在表示"已用尽"）
	st.add_box(tmp)
	var count_before := st.box_count()
	var size_before := ItemService.instances.size()
	var uses_before: Array[int] = []
	for b in st.pending_boxes:
		uses_before.append(b.uses_remaining)
	var r := GachaService.redeem(st, tmp)
	ok(not r.ok, "未注册的套系 ⇒ 失败")
	eq(r.error, GachaService.R_BAD_SERIES, "错误码 = bad_series")
	eq(st.box_count(), count_before, "**盒子还在清单里**（校验失败不消耗盲盒）")
	eq(ItemService.instances.size(), size_before, "没有产生实例")
	eq(st.draw_index, 0, "draw_index 没有推进")
	var uses_intact := true
	for i in st.pending_boxes.size():
		if st.pending_boxes[i].uses_remaining != uses_before[i]:
			uses_intact = false
	ok(uses_intact, "v0.14：**校验失败不消耗任何一次使用**（逐盒逐项不变）")
	eq(tmp.uses_remaining, 3, "那个盒子自己的次数也没被动（仍是 3）")


func _test_batch_redeem_is_ordered_and_contiguous() -> void:
	print("— 批量兑现：顺序确定、`draw_index` 全局递增且连续（§10.2）")
	var f := _new_state(&"series_01", 3)
	var st: GameState = f["state"]
	var boxes: Array = f["boxes"]
	var seeds := [11, 22, 33]
	# v0.14：第 3 个参数是**本次结算的使用次数 k**（不再是盒子数）
	var results := GachaService.redeem_batch(st, boxes, 3, seeds)
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

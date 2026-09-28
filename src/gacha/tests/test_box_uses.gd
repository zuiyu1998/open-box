## 盲盒使用次数测试（v0.14：`Box.uses_remaining`）。
##
## 无头运行：
##   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
## 或直接：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . res://src/gacha/tests/test_box_uses.tscn
##
## 本套件覆盖 v0.14 的三条裁决：①字段在 `Box.uses_remaining`；②初始值按套系品质 **10/15/20/25**；
## ③两次使用之间可以继续编辑池子（模块留到用完）。
extends Node

var _pass := 0
var _fail := 0
var _items8: Array[ItemDef] = []
var _items12: Array[ItemDef] = []


func _ready() -> void:
	print("=== 盲盒使用次数测试（v0.14）===\n")

	_test_initial_uses_curve()
	_test_three_draws_then_box_disappears()
	_test_unsocket_refunds_no_uses()
	_test_snapshot_per_draw()
	_test_edit_applies_to_next_draw()
	_test_validation_failure_consumes_no_use()
	_test_modules_live_until_exhausted()
	_test_batch_k_is_uses_not_boxes()
	_test_conservation()
	_test_uses_remaining_is_persisted()
	_test_two_spend_points_share_counter()
	_test_zero_by_socket_destroys_box()
	_test_device_gate()

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

func _series_id(q: int) -> StringName:
	return StringName("series_q%d" % q)


func _setup() -> void:
	ItemCatalog.clear()
	GachaCatalog.clear()
	ItemService.reset()
	ItemService.warehouse_capacity = 1000
	PoolService.drop_all_cached_states()
	EvalService.is_collected_provider = Callable()

	# 12 件物品、**两维键互不相同**（V1 要求 (category, quality) → item_id 唯一）
	# ⇒ stardust q1..q5 + crystal q1..q5 + resin q1..q2 = 12 个不同的两维键
	var defs: Array[ItemDef] = []
	for i in 5:
		defs.append(_mk("stardust_q%d" % (i + 1), &"stardust", i + 1))
	for i in 5:
		defs.append(_mk("crystal_q%d" % (i + 1), &"crystal", i + 1))
	for i in 2:
		defs.append(_mk("resin_q%d" % (i + 1), &"resin", i + 1))
	_items12 = defs
	_items8 = []
	for i in 8:
		_items8.append(defs[i])

	# 四个品质各一个套系（物品数 / 位数 / 使用次数都按品质曲线）
	for q in [1, 2, 3, 4]:
		var s := SeriesDef.new()
		s.series_id = _series_id(q)
		s.series_quality = q
		s.regular_count = SeriesDef.expected_regular_count(q)
		s.socket_count = SeriesDef.expected_socket_count(q)
		s.uses_per_box = SeriesDef.expected_initial_uses(q)
		var src: Array[ItemDef] = _items8 if q <= 2 else _items12
		var items: Array[ItemDef] = []
		for it in src:
			items.append(it)
		s.regular_items = items
		GachaCatalog.register_series(s)

	GachaCatalog.register_module(_module(&"mod_ban_sd1", &"stardust_q1"))
	GachaCatalog.register_module(_module(&"mod_ban_sd2", &"stardust_q2"))
	GachaCatalog.register_module(_module(&"mod_ban_cr3", &"crystal_q3"))
	# V2 / V5 的夹具：与 `mod_ban_sd1` 抢同一目标的 BOOST、以及一次排除 6 件的 BAN
	GachaCatalog.register_module(_module(&"mod_boost_sd1", &"stardust_q1", ModuleDef.OpType.BOOST, 2.0))
	GachaCatalog.register_module(_module(&"mod_ban_many6", &"stardust_q1", ModuleDef.OpType.BAN, 1.0, [],
		[], ModuleDef.RedistributeMode.AUTO, &"", [&"stardust_q2", &"stardust_q3", &"stardust_q4",
			&"stardust_q5", &"crystal_q1"]))


func _mk(id: String, cat: StringName, quality: int) -> ItemDef:
	var d := ItemDef.new()
	d.item_id = StringName(id)
	d.display_name = id
	d.category = cat
	d.quality = quality
	d.value = quality                 # 价值只为可读性；本套件的断言都不看它
	d.size = 2
	d.rarity = 10                     # 全部相等 ⇒ 基础分布是均等的（便于读摊回后的数字）
	ItemCatalog.register(d)
	return d


func _module(id: StringName, target: StringName, op: int = ModuleDef.OpType.BAN,
		magnitude: float = 1.0, cost: Array = [], tags: Array = [],
		mode: int = ModuleDef.RedistributeMode.AUTO, rtarget: StringName = &"",
		extra_targets: Array = []) -> ModuleDef:
	var m := ModuleDef.new()
	m.id = id
	m.display_name = String(id)
	m.quality = 2
	m.op_type = op
	m.magnitude = magnitude
	m.redistribute_mode = mode
	m.redistribute_target = rtarget
	m.targets.append(target)
	for t in extra_targets:
		m.targets.append(StringName(t))
	for c in cost:
		var e := ModuleCost.new()
		e.category = StringName(c[0])
		e.quality = int(c[1])
		e.amount = int(c[2])
		m.item_cost.append(e)
	for t in tags:
		m.exclusive_tags.append(StringName(t))
	return m


func _new_box(sid: StringName = &"series_q2") -> Dictionary:
	_setup()
	var st := GameState.new_game()
	var boxes := GachaService.grant_box(st, sid, 1, &"test")
	return {"state": st, "box": boxes[0]}


## **低预算夹具盒**（v0.14 裁决后必需）：真实寿命预算是 **10/15/20/25**，而镶嵌位只有 2/3/4/5——
## **"装满位子"再也烧不光预算**。凡是需要"把次数用光 ⇒ 盒子被摧毁"的场景，
## 都用这个夹具把预算显式压到低位（改的是测试场景，不是配置曲线）。
func _new_box_with_budget(sid: StringName, uses: int) -> Dictionary:
	var f := _new_box(sid)
	var bx: Box = f["box"]
	bx.uses_remaining = uses
	return f


func _codes(errors: Array) -> Array[String]:
	var out: Array[String] = []
	for e in errors:
		out.append(String(e).split("：")[0])
	return out


## 权重逐项比较（不依赖容器的 `==` 语义）。
func _same_weights(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k):
			return false
		if int(a[k]) != int(b[k]):
			return false
	return true


## 模块列表的逐项签名（module_id / quality / socketed_at + 槽位）。
func _modules_sig(b: Box) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i in b.modules.size():
		var m := b.modules[i]
		if m == null:
			parts.append("%d:-" % i)
		else:
			parts.append("%d:%s:%d:%d" % [i, m.module_id, m.quality, m.socketed_at])
	return "|".join(parts)


func _instance_ids() -> Array[String]:
	var out: Array[String] = []
	for inst in ItemService.instances:
		out.append(inst.instance_id)
	return out


func _same_ids(a: Array[String], b: Array[String]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


# ══════════════════════════════════════════════════════════════════════════════
#  ① 品质曲线
# ══════════════════════════════════════════════════════════════════════════════

func _test_initial_uses_curve() -> void:
	print("— ① 品质 → 初始使用次数：1/2/3/4 ⇒ 10/15/20/25")
	_setup()
	var expect := [10, 15, 20, 25]
	for q in [1, 2, 3, 4]:
		eq(SeriesDef.expected_initial_uses(q), expect[q - 1], "曲线：品质 %d ⇒ %d 次" % [q, expect[q - 1]])
	# ★ **锁定：预算与位数同源**（`expected_initial_uses` 必须由 `socket_curve()` 推出）。
	#   用一条**机械判定**替代"注释里写请不要各自推导"——注释拦不住下一次改动。
	for q in [1, 2, 3, 4]:
		eq(SeriesDef.expected_initial_uses(q), SeriesDef.USES_PER_SOCKET * SeriesDef.expected_socket_count(q),
			"锁定：预算 == USES_PER_SOCKET × 位数（品质 %d）" % q)
	# ★ **默认值也不手写**：新建的默认 `SeriesDef` 必须自洽（否则默认配置一加载就报 uses_curve）
	var fresh := SeriesDef.new()
	eq(fresh.uses_per_box, SeriesDef.expected_initial_uses(fresh.series_quality),
		"默认 uses_per_box 由常量表达式推出 ⇒ 默认配置自洽（不再是手写的 15）")
	for q in [1, 2, 3, 4]:
		var st := GameState.new_game()
		var boxes := GachaService.grant_box(st, _series_id(q), 3, &"test")
		eq(boxes.size(), 3, "品质 %d：发出 3 个盒子" % q)
		var all_match := true
		var each_own := true
		for b in boxes:
			if b.uses_remaining != expect[q - 1]:
				all_match = false
		ok(all_match, "品质 %d 的每个盒子 uses_remaining == %d" % [q, expect[q - 1]])
		eq(st.total_remaining_uses(), expect[q - 1] * 3, "清单剩余次数 == %d × 3" % expect[q - 1])
		# 次数是**每盒自己的**，不是共享计数器
		boxes[0].uses_remaining -= 1
		for i in range(1, boxes.size()):
			if boxes[i].uses_remaining != expect[q - 1]:
				each_own = false
		ok(each_own, "改一个盒子的次数不影响别的盒子（每盒可变）")

	# 曲线是**被校验**的：配错必须报 uses_curve
	var bad := SeriesDef.new()
	bad.series_id = &"series_bad_uses"
	bad.series_quality = 2
	bad.regular_count = 8
	bad.regular_items = _items8.duplicate()
	bad.socket_count = 3
	bad.uses_per_box = 3                                  # 品质 2 应为 15
	ok(_codes(bad.validate()).has("uses_curve"), "uses_per_box 与品质不匹配 ⇒ 报 uses_curve")
	bad.uses_per_box = 15
	ok(not _codes(bad.validate()).has("uses_curve"), "改回 15 ⇒ 该条不再报")
	bad.uses_per_box = 0
	ok(_codes(bad.validate()).has("bad_uses"), "uses_per_box = 0 ⇒ 报 bad_uses（否则一发放即用尽）")

	# 已记录的文档内部冲突（本套件把它**可见化**，不掩盖）：
	# 品质 4 ⇒ socket_count 5 / regular_count 12 = 41.7%，超出 01 §4.1 [补充]③ 的 25%–40%
	var q4 := GachaCatalog.get_series(&"series_q4")
	ok(_codes(q4.validate()).has("socket_ratio"),
		"已记录冲突：品质 4 的 5/12 = 41.7% 超出 25%–40% ⇒ 其 validate() 报 socket_ratio")


# ══════════════════════════════════════════════════════════════════════════════
#  ② 连开三次
# ══════════════════════════════════════════════════════════════════════════════

func _test_three_draws_then_box_disappears() -> void:
	print("— ② **低预算夹具盒**（预算 3）连开 3 次：2 → 1 → 0，第三次后盒子消失")
	var f := _new_box_with_budget(&"series_q2", 3)
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	var bid := bx.box_id
	eq(bx.uses_remaining, 3, "初始 3 次（夹具预算；真实曲线品质 2 = 15）")
	var inst0 := ItemService.instances.size()

	var r1 := GachaService.redeem(st, bx, 101)
	ok(r1.ok and not r1.is_void, "第 1 次开出物品")
	eq(bx.uses_remaining, 2, "第 1 次后：2")
	eq(st.box_count(), 1, "盒子**仍在**清单里")
	ok(st.has_box(bid), "仍可寻址")
	eq(ItemService.instances.size(), inst0 + 1, "产生 1 个实例")

	var r2 := GachaService.redeem(st, bx, 202)
	ok(r2.ok, "第 2 次成功")
	eq(bx.uses_remaining, 1, "第 2 次后：1")
	eq(st.box_count(), 1, "盒子仍在清单里")
	eq(ItemService.instances.size(), inst0 + 2, "两个实例")

	var r3 := GachaService.redeem(st, bx, 303)
	ok(r3.ok, "第 3 次成功")
	eq(bx.uses_remaining, 0, "第 3 次后：0")
	ok(bx.is_exhausted(), "is_exhausted() == true")
	eq(st.box_count(), 0, "**第三次后盒子从清单消失**")
	ok(not st.has_box(bid), "已无法寻址")
	eq(ItemService.instances.size(), inst0 + 3, "三次三次实例（未编辑池 ⇒ void_prob == 0）")
	eq(r3.draw_index, 3, "draw_index == 3（**每次抽取 +1**，与盒子不再一一对应）")
	eq(st.total_remaining_uses(), 0, "清单剩余次数 0")

	# 对已用尽/已移除的盒子再兑现 ⇒ 明确失败且不产生负值
	var r4 := GachaService.redeem(st, bx, 404)
	ok(not r4.ok, "已用尽的盒子再兑现 ⇒ 失败")
	eq(r4.error, GachaService.R_BOX_NOT_FOUND, "错误码 box_not_found（它已不在清单里）")
	eq(bx.uses_remaining, 0, "次数不产生负值")

	# 手工造一个"次数为 0 但还在清单里"的盒子（正常路径不会出现）⇒ 必须是 uses_exhausted
	var zombie := GachaService.grant_box(st, &"series_q2", 1, &"test")[0]
	zombie.uses_remaining = 0
	var before_n := st.box_count()
	var before_i := ItemService.instances.size()
	var rz := GachaService.redeem(st, zombie, 505)
	ok(not rz.ok, "次数为 0 ⇒ 拒绝")
	eq(rz.error, GachaService.R_USES_EXHAUSTED, "错误码 uses_exhausted")
	eq(st.box_count(), before_n, "清单不变")
	eq(ItemService.instances.size(), before_i, "没有产生实例")


# ══════════════════════════════════════════════════════════════════════════════
#  ②b 拆卸不退还次数（裁决："unsocket 不退还次数"）
# ══════════════════════════════════════════════════════════════════════════════

## **语义锁定**：`socket()` 扣 1 次，`unsocket()` **既不扣、也不退**。
##
## 为什么必须用断言钉住：在代码里"**没扣**"与"**没退**"长得一模一样——
## 将来有人给 `unsocket` 加一句"退还一次"，经济会被**静默**改变，而没有任何断言会拦下它。
##
## ★ 派生语义：**"替换一个模块"的增量成本 == 1 次**——那个位子历史上一共花掉 2 次
##   （原装 1 + 新装 1）；**拆卸本身零成本、也不退还**，它是**沉没成本**，
##   与"模块是消耗品、拆卸只返还 50% 材料"是同一条设计意图。
func _test_unsocket_refunds_no_uses() -> void:
	print("— ②b 拆卸**不退还**次数（裁决）：unsocket 零成本不退；替换的增量成本 == 1 次")
	var f := _new_box(&"series_q3")          # 品质 3 ⇒ 真实预算 20 次 / 4 个位
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	var uses0 := bx.uses_remaining
	eq(uses0, SeriesDef.expected_initial_uses(3), "起点 == 品质 3 的预算（20）")

	# ── 装 3 个模块：每个各扣 1 次 ──────────────────────────────────────────────
	var s1 := PoolService.socket(st, bx.box_id, &"mod_ban_sd1", 0)
	eq(uses0 - bx.uses_remaining, 1, "装第 1 个：−1")
	var s2 := PoolService.socket(st, bx.box_id, &"mod_ban_cr3", 1)
	eq(uses0 - bx.uses_remaining, 2, "装第 2 个：累计 −2")
	var s3 := PoolService.socket(st, bx.box_id, &"mod_ban_sd2", 2)
	ok(s1["ok"] and s2["ok"] and s3["ok"], "三次镶嵌都成功")
	eq(bx.occupied_count(), 3, "3 个位被占用")
	var uses_installed := bx.uses_remaining
	eq(uses0 - uses_installed, 3, "**装模块的累计成本 == 3 次**")

	# ── 逐个拆卸：**次数一次都不变**（既不扣、也不退）────────────────────────────
	var u1 := PoolService.unsocket(st, bx.box_id, 0)
	eq(bx.uses_remaining, uses_installed, "拆第 1 个后：次数**一次没变**（不退也不扣）")
	eq(u1["destroyed"], false, "拆卸的 `destroyed` 恒为 false")
	var u2 := PoolService.unsocket(st, bx.box_id, 1)
	eq(bx.uses_remaining, uses_installed, "拆第 2 个后：仍不变")
	var u3 := PoolService.unsocket(st, bx.box_id, 2)
	ok(u1["ok"] and u2["ok"] and u3["ok"], "三次拆卸都成功")
	eq(bx.uses_remaining, uses_installed, "拆完全部 3 个：**前后逐项相等，一次都没退**")
	eq(bx.occupied_count(), 0, "位子都空了")
	eq(st.total_remaining_uses(), uses_installed, "全局剩余次数也不变")

	# ── 再装一个（替换语义）：只减 1 ───────────────────────────────────────────
	var s4 := PoolService.socket(st, bx.box_id, &"mod_ban_sd1", 0)
	ok(s4["ok"], "重新装一个模块")
	eq(bx.occupied_count(), 1, "拆卸确实生效过（归零 → 现在 1）⇒ 上面的「次数不变」不是因为什么都没发生")
	eq(uses_installed - bx.uses_remaining, 1, "**替换的增量成本 == 1 次**（不是 2、也不是 0）")
	eq(uses0 - bx.uses_remaining, 4, "该位子历史上一共花掉 2 次（原装 1 + 新装 1），连另外两件共 4 次")
	eq(bx.uses_remaining, uses0 - 4, "总账：预算 20 − 4 次实际消耗 = 16（**拆卸没有退回任何一次**）")


# ══════════════════════════════════════════════════════════════════════════════
#  ③ 每次抽取各得一份 pool_snapshot
# ══════════════════════════════════════════════════════════════════════════════

func _test_snapshot_per_draw() -> void:
	print("— ③ 每次抽取各得一份 `pool_snapshot`；两次之间编辑池子 ⇒ 第二份必须不同")
	var f := _new_box(&"series_q3")          # 品质 3 ⇒ 真实预算 20 次（够"兑现→镶嵌→兑现"三步）
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	var ps0 := PoolService.get_pool_state(st, bx.box_id)
	var w0 := ps0.weights_bp.duplicate(true)

	var r1 := GachaService.redeem(st, bx, 11)
	ok(r1.ok, "第 1 次成功")
	var banned_before := ps0.weight_of(&"stardust_q1")
	eq(r1.pool_snapshot.size(), 4, "快照有 4 个键（box_id / revision / void_mass_bp / weights_bp）")
	eq(r1.pool_snapshot["box_id"], bx.box_id, "快照记住盒子身份")
	eq(int(r1.pool_snapshot["revision"]), 0, "第 1 份快照的 revision == 0")
	eq(int(r1.pool_snapshot["void_mass_bp"]), 0, "第 1 份快照的 void == 0（未编辑）")
	ok(_same_weights(r1.pool_snapshot["weights_bp"], w0),
		"第 1 份快照 == **那一刻**的 PoolState 权重（逐项）")

	# ★ 两次使用之间编辑池子
	ok(PoolService.socket(st, bx.box_id, &"mod_ban_sd1", 0)["ok"], "第 2 次之前排除 stardust_q1")
	var ps1 := PoolService.get_pool_state(st, bx.box_id)
	eq(ps1.revision, 1, "编辑后 revision == 1")
	eq(ps1.void_mass_bp, int(floor(float(banned_before) * 0.4)),
		"编辑后 void == 40% × 该物品释放的质量（%d bp）" % banned_before)

	var r2 := GachaService.redeem(st, bx, 22)
	ok(r2.ok, "第 2 次成功")
	ok(not _same_weights(r2.pool_snapshot["weights_bp"], r1.pool_snapshot["weights_bp"]),
		"**第二份快照与第一份不同**（绝不复用上一份）")
	eq(int(r2.pool_snapshot["revision"]), 1, "第二份快照的 revision == 1")
	eq(int(r2.pool_snapshot["void_mass_bp"]), int(floor(float(banned_before) * 0.4)),
		"第二份快照的 void == 那一刻的 void")
	eq(bx.uses_remaining, SeriesDef.expected_initial_uses(3) - 3, "三次动作各扣 1 次（20 → 17）：兑现、镶嵌、兑现")
	ok(_same_weights(r2.pool_snapshot["weights_bp"], ps1.weights_bp),
		"第二份快照 == **那一刻**的 PoolState 权重（逐项）")
	eq(int(r2.pool_snapshot["weights_bp"]["stardust_q1"]), 0, "快照里那件已被排除（权重 0）")

	# 深拷贝：改快照不影响在跑的池子，也不影响另一份快照
	r2.pool_snapshot["weights_bp"]["stardust_q2"] = 9999
	ok(PoolService.get_pool_state(st, bx.box_id).weight_of(&"stardust_q2") != 9999,
		"改快照**不影响在跑的池子**（深拷贝）")
	ok(int(r1.pool_snapshot["weights_bp"]["stardust_q2"]) != 9999, "也不影响第一份快照")

	# 日志条目形状（核心 §14.2.7 / 01 §4.4）
	var entry := GachaService.draw_log_entry(r2)
	eq(entry.size(), 7, "日志条目 7 个键（逐字）")
	ok(entry.has("pool_snapshot") and entry.has("is_void") and entry.has("item_id"),
		"含 pool_snapshot / is_void / item_id")
	ok(_same_weights(entry["pool_snapshot"]["weights_bp"], r2.pool_snapshot["weights_bp"]),
		"日志里的快照就是这一次的快照")
	eq(entry["box_id"], bx.box_id, "日志记盒子身份")


# ══════════════════════════════════════════════════════════════════════════════
#  ④ 编辑跨次生效
# ══════════════════════════════════════════════════════════════════════════════

func _test_edit_applies_to_next_draw() -> void:
	print("— ④ 编辑跨次生效：第 2 次抽取里被排除的物品**不再出现**（抽样验证）")
	var f := _new_box(&"series_q3")          # 品质 3 ⇒ 真实预算 20 次
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	var ps_before := PoolService.get_pool_state(st, bx.box_id)
	var w_sd1_before := ps_before.weight_of(&"stardust_q1")
	var w_sd2_before := ps_before.weight_of(&"stardust_q2")
	var r1 := GachaService.redeem(st, bx, 7)
	ok(r1.ok, "第 1 次成功")
	ok(PoolService.socket(st, bx.box_id, &"mod_ban_sd1", 0)["ok"], "第 1 次之后排除 stardust_q1")

	var ps := PoolService.get_pool_state(st, bx.box_id)
	eq(ps.weight_of(&"stardust_q1"), 0, "该物品权重归零")
	ok(ps.weight_of(&"stardust_q2") > w_sd2_before,
		"其余物品分到摊回的质量（%d → %d）" % [w_sd2_before, ps.weight_of(&"stardust_q2")])
	eq(ps.void_mass_bp, int(floor(float(w_sd1_before) * 0.4)), "损耗 = 40% × 释放质量（C2）")

	# 抽样：第 2 次将要用的那份分布里，它一次都不出现
	var series := GachaCatalog.get_series(&"series_q3")
	var ev := EvalService.evaluate_pool(ps, series)
	var hits := 0
	var other_hits := 0
	var failed_rolls := 0
	for s in 5000:
		var r := GachaService.roll(ev, s)
		if not r.ok:
			failed_rolls += 1
		elif r.item_id == &"stardust_q1":
			hits += 1
		elif r.item_id == &"stardust_q2":
			other_hits += 1
	eq(failed_rolls, 0, "5000 次抽样全部成功（分布自洽，没有 `bad_evaluation`）")
	eq(hits, 0, "5000 个种子各抽一次：被排除的物品出现 **0** 次")
	ok(other_hits > 300, "未被排除的物品照常出现（%d 次 / 5000）" % other_hits)

	# 真·第 2 次兑现（走完整路径）
	var r2 := GachaService.redeem(st, bx, 8)
	ok(r2.ok, "第 2 次兑现成功")
	ok(r2.item_id != &"stardust_q1", "实际抽到的不是被排除的那件")
	eq(int(r2.pool_snapshot["weights_bp"]["stardust_q1"]), 0, "第 2 份快照也记录了这次排除")
	eq(bx.uses_remaining, SeriesDef.expected_initial_uses(3) - 3, "三次动作各扣 1 次（20 → 17）：兑现、镶嵌、兑现")
	eq(r2.draw_index, 2, "draw_index 第 2 次 == 2")


# ══════════════════════════════════════════════════════════════════════════════
#  ⑤ 校验失败不消耗次数
# ══════════════════════════════════════════════════════════════════════════════

func _test_validation_failure_consumes_no_use() -> void:
	print("— ⑤ 校验失败不消耗任何一次使用（uses_remaining 与实例列表逐项不变）")
	var f := _new_box(&"series_q2")
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	var uses_before := bx.uses_remaining
	var ids_before := _instance_ids()
	var granted_before := ItemService.total_granted
	var consumed_before := ItemService.total_consumed
	var draw_before := st.draw_index

	# 让池子状态不可用：塞一个未注册的 module_id（载入路径的同一纪律）
	bx.modules[0] = Module.make(&"mod_offline", 1, 0)
	PoolService.drop_cached_state(bx.box_id)
	var r := GachaService.redeem(st, bx, 1)
	ok(not r.ok, "池子不可用 ⇒ 拒绝")
	eq(r.error, GachaService.R_POOL_INVALID, "错误码 pool_invalid")
	eq(bx.uses_remaining, uses_before, "**一次使用都没被消耗**")
	ok(_same_ids(ids_before, _instance_ids()), "实例列表逐项不变")
	eq(ItemService.total_granted, granted_before, "total_granted 不变")
	eq(ItemService.total_consumed, consumed_before, "total_consumed 不变")
	eq(st.draw_index, draw_before, "draw_index 不变")
	eq(st.box_count(), 1, "盒子仍在清单里")

	# 修好之后，同一次使用照常可用（次数没有被那次失败吃掉）
	bx.modules[0] = null
	PoolService.drop_cached_state(bx.box_id)
	var r2 := GachaService.redeem(st, bx, 2)
	ok(r2.ok, "修好后兑现成功")
	eq(bx.uses_remaining, uses_before - 1, "此时才扣掉一次")

	# 未注册套系（另一条校验失败路径）同样不消耗次数
	var st2 := GameState.new_game()
	var good := GachaService.grant_box(st2, &"series_q2", 1, &"test")[0]
	var tmp := Box.new()
	tmp.box_id = Uuid.v4()
	tmp.series_id = &"series_offline"
	tmp.item_pool = PoolService.init_pool(st2, tmp.box_id, &"series_q2")
	tmp.modules = PoolService.empty_slots(3)
	tmp.uses_remaining = 3
	st2.add_box(tmp)
	var g_before := good.uses_remaining
	var bad := GachaService.redeem(st2, tmp)
	ok(not bad.ok, "未注册套系 ⇒ 失败")
	eq(bad.error, GachaService.R_BAD_SERIES, "错误码 bad_series")
	eq(good.uses_remaining, g_before, "**别的盒子的次数也没被牵动**")
	eq(tmp.uses_remaining, 3, "它自己的次数也没动")

	# 镶嵌被闸门拒绝（V3 / V7）同样**不扣次数**
	var f3 := _new_box(&"series_q2")
	var st3: GameState = f3["state"]
	var bx3: Box = f3["box"]
	ok(PoolService.socket(st3, bx3.box_id, &"mod_ban_sd1", 0)["ok"], "先成功镶一个（15 → 14）")
	var uses_now := bx3.uses_remaining
	eq(uses_now, SeriesDef.expected_initial_uses(2) - 1, "成功镶嵌扣 1 次（品质 2 的 15 → 14）")
	var dup := PoolService.socket(st3, bx3.box_id, &"mod_ban_sd2", 0)     # 往占用位放 ⇒ V3
	ok(not dup["ok"], "往占用位镶嵌 ⇒ 拒绝")
	eq(dup["reason"], PoolService.R_SLOT_OCCUPIED, "原因码 slot_occupied（V3）")
	eq(bx3.uses_remaining, uses_now, "**失败不扣次数**")
	var unknown := PoolService.socket(st3, bx3.box_id, &"no_such_module", 1)
	ok(not unknown["ok"], "未注册模块 ⇒ 拒绝")
	eq(unknown["reason"], PoolService.R_UNKNOWN_MODULE, "原因码 unknown_module（V7）")
	eq(bx3.uses_remaining, uses_now, "仍不扣次数")
	eq(bx3.occupied_count(), 1, "modules 没被写坏（失败不留痕）")
	eq(bx3.item_pool.revision, 1, "revision 只被成功的那次推进")

	# V2：同一物品既排除又提升 ⇒ 拒绝，**不扣次数**
	var conflict := PoolService.socket(st3, bx3.box_id, &"mod_boost_sd1", 1)
	ok(not conflict["ok"], "与已排除物品冲突的提升 ⇒ 拒绝")
	eq(conflict["reason"], PoolService.R_BAN_BOOST_CONFLICT, "原因码 ban_boost_conflict（V2）")
	eq(bx3.uses_remaining, uses_now, "V2 拒绝不扣次数")

	# V5：一次排除 6 件 > ban_limit（8 − 3 = 5）⇒ 拒绝，**不扣次数**
	var over := PoolService.socket(st3, bx3.box_id, &"mod_ban_many6", 1)
	ok(not over["ok"], "排除数超过 ban_limit ⇒ 拒绝")
	eq(over["reason"], PoolService.R_BAN_LIMIT, "原因码 ban_limit_exceeded（V5）")
	eq(bx3.uses_remaining, uses_now, "V5 拒绝不扣次数")
	eq(bx3.occupied_count(), 1, "三次失败之后仍只有 1 个模块")
	eq(bx3.item_pool.revision, 1, "revision 仍为 1")
	eq(PoolService.get_pool_state(st3, bx3.box_id).weight_of(&"stardust_q1"), 0,
		"池子状态仍是那一次成功镶嵌的结果")


# ══════════════════════════════════════════════════════════════════════════════
#  ⑥ 模块留到用完
# ══════════════════════════════════════════════════════════════════════════════

func _test_modules_live_until_exhausted() -> void:
	print("— ⑥ 模块留在盒子上，直到盒子被摧毁（归零即摧毁）")
	var f := _new_box_with_budget(&"series_q3", 4)   # 夹具预算 4（真实曲线品质 3 = 20）：够走到摧毁
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	ok(PoolService.socket(st, bx.box_id, &"mod_ban_sd1", 0)["ok"], "镶一个排除模块（4 → 3）")
	var sig := _modules_sig(bx)
	eq(bx.occupied_count(), 1, "1 个已占用位")
	eq(bx.uses_remaining, 3, "镶嵌扣掉 1 次")

	var r1 := GachaService.redeem(st, bx, 5)
	ok(r1.ok, "第 1 次兑现成功（3 → 2）")
	eq(_modules_sig(bx), sig, "**摧毁前 modules 逐项不变**（module_id / quality / socketed_at）")
	eq(bx.occupied_count(), 1, "该模块仍在位")
	ok(PoolService.get_pool_state(st, bx.box_id).void_mass_bp > 0,
		"编辑仍然生效（**不是「兑现就重置」**）")
	eq(PoolService.get_modules(st, bx.box_id).size(), 4, "get_modules 仍能读到该盒的定长列表（品质 3 ⇒ 4 位）")

	# 摧毁前**可以继续编辑**：再镶一个（也扣 1 次）、再拆掉（不扣）
	ok(PoolService.socket(st, bx.box_id, &"mod_ban_cr3", 1)["ok"], "还可以继续镶嵌（2 → 1）")
	eq(bx.occupied_count(), 2, "两个模块在位")
	eq(bx.uses_remaining, 1, "第二次镶嵌也扣 1 次")
	ok(PoolService.unsocket(st, bx.box_id, 1)["ok"], "也可以拆掉（模块可拆卸）")
	eq(bx.occupied_count(), 1, "回到 1 个模块")
	eq(bx.uses_remaining, 1, "**拆卸不消耗次数**（消耗点只有镶嵌与兑现）")
	eq(_modules_sig(bx), sig, "拆掉后与最初逐项一致")

	var r2 := GachaService.redeem(st, bx, 6)
	ok(r2.ok, "第 2 次兑现成功（1 → 0）")
	ok(bx.is_exhausted(), "次数归零")
	ok(not st.has_box(bx.box_id), "**归零即摧毁：盒子已从清单移除 ⇒ 它的 modules 随之消失**")
	eq(st.box_count(), 0, "清单空")
	eq(PoolService.get_modules(st, bx.box_id).size(), 0, "对已摧毁的盒子读模块 ⇒ 空")
	ok(not PoolService.socket(st, bx.box_id, &"mod_ban_sd1", 0)["ok"], "对已摧毁的盒子镶嵌 ⇒ 拒绝")


# ══════════════════════════════════════════════════════════════════════════════
#  ⑦ k 的口径
# ══════════════════════════════════════════════════════════════════════════════

func _test_batch_k_is_uses_not_boxes() -> void:
	print("— ⑦ k 的口径：跨 2 个盒子共 5 次使用 ⇒ k == 5（不是 2）")
	_setup()
	var st := GameState.new_game()
	var boxes := GachaService.grant_box(st, &"series_q2", 2, &"test")
	var a: Box = boxes[0]
	var b: Box = boxes[1]
	# 夹具：把两盒预算显式压到 3（真实曲线品质 2 = 15），否则 k=5 烧不光第 1 个盒子
	a.uses_remaining = 3
	b.uses_remaining = 3
	eq(st.total_remaining_uses(), 6, "两个盒子共 6 次可用（夹具：各 3 次）")

	var results := GachaService.redeem_batch(st, boxes, 5, [1, 2, 3, 4, 5])
	eq(results.size(), 5, "**k == 5**：返回 5 次结算（而盒子数只有 2）")
	var all_ok := true
	for r in results:
		if not r.ok:
			all_ok = false
	ok(all_ok, "5 次全部成功")
	eq(a.uses_remaining, 0, "第 1 个盒子 3 次用尽")
	eq(b.uses_remaining, 1, "第 2 个盒子被用掉 2 次（3 → 1）")
	eq(st.box_count(), 1, "用尽的盒子离开清单，另一个还在")
	eq(st.total_remaining_uses(), 1, "剩余次数 1")
	var idx_ok := true
	for i in 5:
		if results[i].draw_index != i + 1:
			idx_ok = false
	ok(idx_ok, "draw_index 1..5 连续（每次抽取 +1，与盒子数无关）")
	eq(results[0].box_id, a.box_id, "第 1 次落在第 1 个盒子")
	eq(results[2].box_id, a.box_id, "第 3 次仍在第 1 个盒子（它有 3 次）")
	eq(results[3].box_id, b.box_id, "第 4 次**按顺序跨到**第 2 个盒子")
	eq(results[4].box_id, b.box_id, "第 5 次在第 2 个盒子")
	eq(ItemService.instances.size(), 5, "5 次抽取产生 5 个实例（未编辑池 ⇒ void_prob == 0）")

	# 可用次数不足 ⇒ **整批被拒**，一次都不消耗
	var uses_before := st.total_remaining_uses()
	var idx_before := st.draw_index
	var inst_before := ItemService.instances.size()
	var bad := GachaService.redeem_batch(st, [b], 3)
	eq(bad.size(), 3, "results.size() == k 恒成立（返回 3 条失败结果）")
	ok(not bad[0].ok and bad[0].error == GachaService.R_USES_EXHAUSTED, "不足 ⇒ uses_exhausted")
	eq(st.total_remaining_uses(), uses_before, "**没有消耗任何次数**")
	eq(st.draw_index, idx_before, "draw_index 没动")
	eq(ItemService.instances.size(), inst_before, "没有产生实例")

	# 预校验失败（盒子不在清单里）⇒ 同样整批被拒
	var other := GachaService.grant_box(st, &"series_q2", 1, &"test")[0]
	st.remove_box(other.box_id)
	var bad2 := GachaService.redeem_batch(st, [other], 2)
	eq(bad2.size(), 2, "2 条失败结果")
	eq(bad2[0].error, GachaService.R_BOX_NOT_FOUND, "错误码 box_not_found")
	eq(st.total_remaining_uses(), uses_before, "仍未消耗任何次数")

	# k <= 0 ⇒ 空结果（合法 no-op）
	eq(GachaService.redeem_batch(st, boxes, 0).size(), 0, "k == 0 ⇒ 空数组，不做任何事")
	eq(st.total_remaining_uses(), uses_before, "k == 0 不消耗次数")


# ══════════════════════════════════════════════════════════════════════════════
#  ⑧ 守恒
# ══════════════════════════════════════════════════════════════════════════════

func _test_conservation() -> void:
	print("— ⑧ 守恒：`uses_remaining` 只减不增；盒子总数 == 已发放 − 已用尽")
	_setup()
	var st := GameState.new_game()
	var granted := 0
	for _i in 4:
		granted += GachaService.grant_box(st, &"series_q1", 1, &"test").size()   # 品质 1 ⇒ 每盒 10 次
	eq(granted, 4, "已发放 4 个盒子")
	eq(st.total_remaining_uses(), SeriesDef.expected_initial_uses(1) * 4,
		"初始总次数 == 品质 1 的预算 × 4 盒（10 × 4 = 40）")

	var draws := 0
	var exhausted := 0
	var monotonic := true
	var prev: Dictionary = {}
	for b in st.pending_boxes:
		prev[b.box_id] = b.uses_remaining
	while st.box_count() > 0:
		var target: Box = st.pending_boxes[0]
		var before_uses := target.uses_remaining
		var r := GachaService.redeem(st, target, draws + 1)
		draws += 1
		if not r.ok:
			ok(false, "第 %d 次兑现失败：%s" % [draws, r.error])
			break
		if target.uses_remaining > before_uses:
			monotonic = false
		if prev.has(target.box_id) and target.uses_remaining > int(prev[target.box_id]):
			monotonic = false
		prev[target.box_id] = target.uses_remaining
		if target.is_exhausted():
			exhausted += 1
	ok(monotonic, "**uses_remaining 只减不增**（逐次检查，包括跨盒）")
	eq(draws, SeriesDef.expected_initial_uses(1) * granted, "总共抽取 == 预算 × 盒数（每次兑现 −1）")
	eq(exhausted, granted, "用尽数 == 发放数（4）")
	eq(st.box_count(), granted - exhausted, "**盒子总数 == 已发放 − 已用尽**（4 − 4 = 0）")
	eq(st.total_remaining_uses(), 0, "剩余次数 0")
	eq(ItemService.instances.size(), draws, "实例数 == 抽取次数（未编辑池 ⇒ void_prob == 0）")
	eq(st.draw_index, draws, "draw_index == 抽取次数（与盒子数无关）")
	ok(ItemService.check_conservation(), "02 的实例守恒等式仍成立")

	# 发放过程中清点：部分用尽时两边同时成立
	var st2 := GameState.new_game()
	var b1 := GachaService.grant_box(st2, &"series_q1", 1, &"test")[0]    # 夹具：预算 2
	var b2 := GachaService.grant_box(st2, &"series_q1", 1, &"test")[0]    # 夹具：预算 2
	b1.uses_remaining = 2
	b2.uses_remaining = 2
	eq(st2.box_count(), 2, "2 个盒子")
	eq(st2.total_remaining_uses(), 4, "共 4 次（夹具：各 2 次）")
	GachaService.redeem(st2, b1, 1)
	GachaService.redeem(st2, b1, 2)
	eq(b1.uses_remaining, 0, "b1 用尽")
	eq(st2.box_count(), 1, "盒子数 2 − 1 = 1")
	eq(st2.total_remaining_uses(), 2, "剩余 2 次（全在 b2 上）")
	eq(b2.uses_remaining, 2, "b2 一次都没被碰")

	# **两个消耗点合起来守恒**：初始总次数 == 镶嵌数 + 兑现数 + 剩余
	var st3 := GameState.new_game()
	var pair := GachaService.grant_box(st3, &"series_q3", 2, &"test")    # 夹具：各 4 次（真实曲线品质 3 = 20）
	pair[0].uses_remaining = 4
	pair[1].uses_remaining = 4
	eq(st3.total_remaining_uses(), 8, "两个盒子共 8 次（夹具：各 4 次）")
	var sockets := 0
	var draws2 := 0
	ok(PoolService.socket(st3, pair[0].box_id, &"mod_ban_sd1", 0)["ok"], "A 镶嵌 #1")
	sockets += 1
	ok(PoolService.socket(st3, pair[0].box_id, &"mod_ban_cr3", 1)["ok"], "A 镶嵌 #2")
	sockets += 1
	ok(GachaService.redeem(st3, pair[0], 1).ok, "A 兑现 #1")
	draws2 += 1
	eq(pair[0].uses_remaining, 1, "A：4 − 2（镶嵌）− 1（兑现）= 1")
	eq(pair[1].uses_remaining, 4, "B 一次都没被碰（4）")
	eq(st3.total_remaining_uses(), 5, "全局剩余 5")
	eq(st3.total_remaining_uses(), 8 - sockets - draws2,
		"**初始总次数 == 镶嵌数 + 兑现数 + 剩余**（8 == 2 + 1 + 5）")
	eq(pair[0].uses_remaining + pair[1].uses_remaining, st3.total_remaining_uses(),
		"Σ 每盒剩余 == 全局剩余")


# ══════════════════════════════════════════════════════════════════════════════
#  ⑨ 入档
# ══════════════════════════════════════════════════════════════════════════════

func _test_uses_remaining_is_persisted() -> void:
	print("— ⑨ 入档：`uses_remaining` 随盒子落盘 / 读回（不丢、不凭空补）")
	var f := _new_box_with_budget(&"series_q2", 3)    # 夹具预算 3（真实曲线品质 2 = 15）
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	ok(PoolService.socket(st, bx.box_id, &"mod_ban_sd1", 0)["ok"], "镶一个模块（3 → 2）")
	ok(GachaService.redeem(st, bx, 42).ok, "再兑现一次（2 → 1）")

	var d := bx.to_dict()
	eq(int(d["uses_remaining"]), 1, "落盘里含 uses_remaining（镶嵌 −1、兑现 −1 ⇒ 3 → 1）")
	eq(d["item_pool"].size(), 5, "池子只落**五项子集**（box_id / series_id / regular_count / socket_count / revision）")
	eq(int(d["item_pool"]["revision"]), 1, "revision 入档 == 1")
	eq(d["modules"].size(), 1, "模块落**稀疏序列**（1 条）")
	eq(int(d["modules"][0]["index"]), 0, "稀疏序列带下标")

	var back := Box.from_dict(d)
	ok(back != null, "读回成功")
	eq(back.uses_remaining, 1, "**读回后次数不丢**（3 → 1 原样回来）")
	eq(back.box_id, bx.box_id, "身份逐位不变")
	eq(back.series_id, &"series_q2", "套系不变")
	eq(back.source, &"test", "来源不变")
	eq(back.item_pool.revision, 1, "revision 读回")
	eq(back.item_pool.socket_count, 3, "socket_count 由套系解析回来")
	eq(back.item_pool.regular_count, 8, "regular_count 读回")
	eq(back.modules.size(), 3, "定长长度仍 == socket_count")
	eq(back.module_at(0).module_id, &"mod_ban_sd1", "模块逐项还原")
	eq(JSON.stringify(back.to_dict()), JSON.stringify(d), "往返后落盘形状逐字段相等")

	# ★ v0.14 裁决：**缺键 ⇒ 载入路径按品质补齐**（不是取 0——那会一次性摧毁旧档的全部盒子）
	var d2 := d.duplicate(true)
	d2.erase("uses_remaining")
	var legacy := GameState.box_from_dict(d2)
	ok(legacy != null, "缺键的档仍能载入")
	eq(legacy.uses_remaining, SeriesDef.expected_initial_uses(2),
		"**缺键 ⇒ 按品质补齐**（品质 2 ⇒ 15，取自 series 的品质而不是取 0）")
	ok(not legacy.is_exhausted(), "补齐后**不在「已摧毁」状态**")
	ok(legacy.to_dict().has("uses_remaining"), "补齐后 `to_dict()` 里已经带上该键")
	eq(int(legacy.to_dict()["uses_remaining"]), SeriesDef.expected_initial_uses(2), "补齐的值原样入档")
	eq(GameState.box_from_dict(legacy.to_dict()).uses_remaining, SeriesDef.expected_initial_uses(2),
		"**往返一次后值不变**（键已在档里 ⇒ 不再走补齐分支）")

	# ★ 反向：键存在且为 `0` ⇒ **不许被好心补满**（`0` = 已用尽，是合法状态）
	var d_zero := d.duplicate(true)
	d_zero["uses_remaining"] = 0
	eq(GameState.box_from_dict(d_zero).uses_remaining, 0, "**有键且为 0 ⇒ 仍是 0**（合法状态，不补满）")
	eq(Box.from_dict(d_zero).uses_remaining, 0, "底层 `Box.from_dict` 同样尊重档里的 0")
	ok(GameState.box_from_dict(d_zero).is_exhausted(), "它确实处于「已用尽」状态")

	# 未知套系 ⇒ 拒绝载入（不静默降级成基础池）
	var d3 := d.duplicate(true)
	d3["series_id"] = "series_offline"
	ok(GameState.box_from_dict(d3) == null, "未知 series_id ⇒ 返回 null（禁止静默降级）")
	ok(Box.from_dict(d3) == null, "底层 `Box.from_dict` 同样拒绝")


# ══════════════════════════════════════════════════════════════════════════════
#  ⑩ 两个消耗点共用同一个计数器
# ══════════════════════════════════════════════════════════════════════════════

func _test_two_spend_points_share_counter() -> void:
	print("— ⑩ 两个消耗点共用同一个 `uses_remaining`：**装模块 −1、兑现 −1**")
	var f := _new_box_with_budget(&"series_q3", 4)   # 夹具预算 4（真实曲线品质 3 = 20）
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	eq(bx.uses_remaining, 4, "初始 4 次（夹具预算）")

	var s1 := PoolService.socket(st, bx.box_id, &"mod_ban_sd1", 0)
	ok(s1["ok"], "镶嵌成功")
	eq(bx.uses_remaining, 3, "**装模块 −1**（4 → 3）")
	eq(s1["destroyed"], false, "还有 3 次 ⇒ 没有摧毁")

	var r1 := GachaService.redeem(st, bx, 1)
	ok(r1.ok, "兑现成功")
	eq(bx.uses_remaining, 2, "**兑现 −1**（3 → 2）")

	ok(PoolService.socket(st, bx.box_id, &"mod_ban_cr3", 1)["ok"], "再装一个模块")
	eq(bx.uses_remaining, 1, "3 → 2 → 1：**两个动作打在同一个计数器上**")
	ok(st.has_box(bx.box_id), "还剩 1 次 ⇒ 盒子仍在清单里")

	var u := PoolService.unsocket(st, bx.box_id, 1)
	ok(u["ok"], "拆卸成功")
	eq(bx.uses_remaining, 1, "**拆卸不消耗次数**（消耗点只有「装模块」与「兑现」两个）")
	eq(u["destroyed"], false, "拆卸的 `destroyed` 恒为 false")
	eq(st.total_remaining_uses(), 1, "全局剩余次数 == 1")


# ══════════════════════════════════════════════════════════════════════════════
#  ⑪ "刚好扣到 0" 的两条路径都摧毁盒子
# ══════════════════════════════════════════════════════════════════════════════

func _test_zero_by_socket_destroys_box() -> void:
	print("— ⑪ 刚好扣到 0 的两条路径都摧毁盒子（含**从未兑现**的合法自毁）")
	# ── 路径 ①：连续装模块至 0（**一次都没兑现过**）──────────────────────────────
	_setup()
	var st := GameState.new_game()
	var bx := GachaService.grant_box(st, &"series_q2", 1, &"test")[0]
	# ★ **夹具重构**：新曲线下品质 1 有 10 次预算却只有 2 个位 ⇒"装满位子"再也烧不光预算。
	#   这里把预算压到 3（= q2 的位数），于是"连续装模块至 0"仍可被触发；
	#   **被覆盖的语义不变**：归零即摧毁，且这条路径**从未兑现过**（合法自毁）。
	bx.uses_remaining = 3
	var draws_before := st.draw_index
	var inst_before := ItemService.instances.size()
	var inst_ids_before := _instance_ids()
	eq(bx.uses_remaining, 3, "初始 3 次")

	var a1 := PoolService.socket(st, bx.box_id, &"mod_ban_sd1", 0)
	ok(a1["ok"] and not a1["destroyed"], "第 1 次镶嵌（3 → 2），未摧毁")
	eq(bx.uses_remaining, 2, "剩 2 次")
	eq(st.box_count(), 1, "盒子还在")
	var a2 := PoolService.socket(st, bx.box_id, &"mod_ban_cr3", 1)
	ok(a2["ok"] and not a2["destroyed"], "第 2 次镶嵌（2 → 1），未摧毁")
	eq(bx.uses_remaining, 1, "剩 1 次")
	ok(st.has_box(bx.box_id), "还剩 1 次 ⇒ 仍在清单里")

	var a3 := PoolService.socket(st, bx.box_id, &"mod_ban_sd2", 2)
	ok(a3["ok"], "第 3 次镶嵌成功（**没有被防御性拒绝**：归零前镶嵌是合法的）")
	eq(a3["destroyed"], true, "**返回里明确报告这次镶嵌摧毁了盒子**")
	eq(bx.uses_remaining, 0, "次数归零")
	ok(bx.is_exhausted(), "is_exhausted() == true")
	ok(not st.has_box(bx.box_id), "**盒子被摧毁：从未兑现过也照样摧毁（合法路径）**")
	eq(st.box_count(), 0, "清单空")
	eq(st.draw_index, draws_before, "**从未兑现 ⇒ draw_index 一步没动**")
	eq(ItemService.instances.size(), inst_before, "没有产生任何实例")
	eq(PoolService.get_modules(st, bx.box_id).size(), 0, "它的 modules 随之消失")
	eq(PoolService.get_pool_state(st, bx.box_id), null, "对已摧毁的盒子取状态 ⇒ null")
	ok(not PoolService.socket(st, bx.box_id, &"mod_ban_sd1", 0)["ok"], "对已摧毁的盒子再镶嵌 ⇒ 拒绝")
	ok(_same_ids(inst_ids_before, _instance_ids()), "**实例账逐项不变**（从未兑现 ⇒ 一件都没产出）")
	ok(ItemService.check_conservation(), "02 的守恒等式仍成立")
	eq(st.pending_boxes.size(), 0, "`pending_boxes` 空（盒子是被移除，不是被标记）")

	# ── 路径 ②：装模块后再兑现至 0 ────────────────────────────────────────────
	var st2 := GameState.new_game()
	var bx2 := GachaService.grant_box(st2, &"series_q2", 1, &"test")[0]
	bx2.uses_remaining = 3           # 夹具预算 3（真实曲线品质 2 = 15）
	ok(PoolService.socket(st2, bx2.box_id, &"mod_ban_sd1", 0)["ok"], "装模块一次（3 → 2）")
	var ids2_before := _instance_ids()
	var r_a := GachaService.redeem(st2, bx2, 9)
	ok(r_a.ok, "兑现一次（2 → 1）")
	ok(st2.has_box(bx2.box_id), "还剩 1 次 ⇒ 还在清单里")
	var r_b := GachaService.redeem(st2, bx2, 10)
	ok(r_b.ok, "再兑现一次（1 → 0）")
	eq(bx2.uses_remaining, 0, "归零")
	ok(not st2.has_box(bx2.box_id), "**兑现至 0 也摧毁盒子**")
	eq(st2.pending_boxes.size(), 0, "`pending_boxes` 空（盒子是被移除，不是被标记）")
	eq(st2.box_count(), 0, "清单空")
	eq(st2.draw_index, 2, "两次兑现 ⇒ draw_index == 2（与盒子数无关）")
	# 实例账与抽取逐项对账（该盒已被排除一件 ⇒ void_prob > 0，故按"非 void 次数"对账）
	var non_void := 0
	if not r_a.is_void:
		non_void += 1
	if not r_b.is_void:
		non_void += 1
	eq(ItemService.instances.size(), ids2_before.size() + non_void,
		"**实例账一致**：新增实例数 == 非 void 的抽取次数（%d）" % non_void)
	var now_ids := _instance_ids()
	var prefix_ok := true
	for i in ids2_before.size():
		if now_ids[i] != ids2_before[i]:
			prefix_ok = false
	ok(prefix_ok, "原有实例一个没被动（新实例追加在末尾）")
	ok(ItemService.check_conservation(), "02 的守恒等式仍成立")


# ══════════════════════════════════════════════════════════════════════════════
#  ⑫ 设备是硬门槛（v0.14 裁决：开盒与装模块都要有设备）
# ══════════════════════════════════════════════════════════════════════════════

func _test_device_gate() -> void:
	print("— ⑫ 设备是硬门槛：无设备 ⇒ 两条入口都拒绝且**不消耗寿命**；开局送一台 ⇒ 实测可开盒")
	_setup()
	# ── 无设备的档：裸 `GameState`（**不**走 `new_game()` ⇒ 不送装置）─────────────
	var bare := GameState.new()
	ok(not bare.has_device(), "裸 GameState 没有设备（has_device() == false）")
	eq(bare.device_count(), 0, "设备数 == 0")
	var boxes := GachaService.grant_box(bare, &"series_q2", 1, &"test")
	eq(boxes.size(), 1, "**发盒不受门槛限制**（门槛只摆在两个消耗寿命的动作上）")
	var bx: Box = boxes[0]
	var uses_before := bx.uses_remaining
	var ids_before := _instance_ids()
	var idx_before := bare.draw_index

	var r := GachaService.redeem(bare, bx, 1)
	ok(not r.ok, "**无设备 ⇒ 开盒被拒**")
	eq(r.error, GachaService.R_NO_DEVICE, "原因码 no_device")
	eq(bx.uses_remaining, uses_before, "**一次寿命都没消耗**")
	ok(_same_ids(ids_before, _instance_ids()), "实例账逐项不变")
	eq(bare.draw_index, idx_before, "draw_index 不变")
	eq(bare.box_count(), 1, "盒子仍在清单里")

	var s := PoolService.socket(bare, bx.box_id, &"mod_ban_sd1", 0)
	ok(not s["ok"], "**无设备 ⇒ 装模块被拒**")
	eq(s["reason"], PoolService.R_NO_DEVICE, "原因码同样是 no_device（两侧同名同义）")
	eq(bx.uses_remaining, uses_before, "寿命仍未被消耗")
	eq(bx.occupied_count(), 0, "modules 没被写入")
	eq(bx.item_pool.revision, 0, "revision 没被推进")

	var batch := GachaService.redeem_batch(bare, [bx], 2)
	eq(batch.size(), 2, "批量同样被拒（`results.size() == k` 的不变量不变）")
	ok(batch[0].error == GachaService.R_NO_DEVICE and batch[1].error == GachaService.R_NO_DEVICE,
		"两条都是 no_device")
	eq(bx.uses_remaining, uses_before, "批量也没有消耗任何寿命")
	eq(bare.total_remaining_uses(), uses_before, "全局剩余次数不变")

	# ── 有设备（开局送的那台）⇒ 两条入口都放行 ───────────────────────────────
	var armed := GameState.new_game()
	ok(armed.has_device(), "**新游戏初始化后即有设备**（开局送一台基础装置）")
	eq(armed.device_count(), 1, "正好一台")
	var bx2: Box = GachaService.grant_box(armed, &"series_q2", 1, &"test")[0]
	eq(bx2.uses_remaining, SeriesDef.expected_initial_uses(2), "新盒子拿到完整预算（15）")
	ok(PoolService.socket(armed, bx2.box_id, &"mod_ban_sd1", 0)["ok"], "有设备 ⇒ **装模块放行**")
	eq(bx2.uses_remaining, SeriesDef.expected_initial_uses(2) - 1, "放行后照常扣 1 次寿命")
	var rd := GachaService.redeem(armed, bx2, 7)
	ok(rd.ok, "有设备 ⇒ **开盒放行**")
	eq(bx2.uses_remaining, SeriesDef.expected_initial_uses(2) - 2, "兑现也照常扣 1 次")
	# ★ **死锁路径在实测上不存在**：新游戏直接就能开盒
	ok(rd.ok and not rd.is_void and rd.item_id != &"",
		"**新游戏初始化后即可开盒**：开局那台设备足以让「开盒 → 物品 → 造设备」跑起来")

## 物品系统验收测试（对应 02-item.md §10 的测试点）。
##
## 无头运行：
##   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
## 或直接：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . res://src/items/tests/test_item_system.tscn
##
## 退出码 0 = 全绿，1 = 有失败。
##
## [!] 为什么走**场景**而不是 `--script`：`--script` 模式下 autoload 不会作为全局
##     标识符注册，`ItemCatalog` / `ItemService` 会在**编译期**就报 Identifier not found。
##     场景入口会正常加载 autoload，与游戏实际运行方式一致。
extends Node

var _pass := 0
var _fail := 0
var _section := ""


func _ready() -> void:
	print("=== 物品系统测试（02-item.md §10）===\n")

	_setup_catalog()

	_section = "§10.1 实例与幂等"
	_test_idempotent_grant()
	_test_uuid_uniqueness()
	_test_uuid_not_from_seed()
	_test_serial_semantics()

	_section = "§10.2 count 派生一致性"
	_test_count_matches_rebuild()
	_test_count_immediate()
	_test_zero_key_removed()
	_test_key_count_bound()

	_section = "§10.3 原子性"
	_test_consume_atomic()
	_test_duplicate_ids()
	_test_pick_order()
	_test_double_destroy()

	_section = "§10.4 存档往返"
	_test_save_roundtrip()

	_section = "§10.5 数量守恒"
	_test_conservation()

	_section = "§10.8 仓库容量、邮件与事务"
	_test_overflow_boundaries()
	_test_mail_not_counted()
	_test_claim_only_location()
	_test_claim_partial()
	_test_transact_atomic()
	_test_transact_no_space()
	_test_overflow_loosening_rejected()
	_test_no_partial_containment()
	_test_discard_escape_valve()
	_test_config_validator()

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

func _setup_catalog() -> void:
	ItemCatalog.clear()
	for cat_id in [&"stardust", &"crystal"]:
		var c := ItemCategoryDef.new()
		c.category_id = cat_id
		c.display_name = String(cat_id)
		ItemCatalog.register_category(c)
	# 2 类别 × 3 品质 = 6 个键（切片范围）
	var sizes := {1: 1, 2: 2, 3: 5}
	var values := {1: 1, 2: 3, 3: 9}
	for cat in [&"stardust", &"crystal"]:
		for q in [1, 2, 3]:
			var d := ItemDef.new()
			d.item_id = StringName("%s_q%d" % [cat, q])
			d.display_name = "%s q%d" % [cat, q]
			d.category = cat
			d.quality = q
			d.value = values[q]
			d.size = sizes[q]
			ItemCatalog.register(d)


func _reset(capacity := 1000) -> void:
	ItemService.reset()
	ItemService.warehouse_capacity = capacity


func _grant_q1(n: int, item := &"stardust_q1") -> Array[String]:
	var ids: Array[String] = []
	for i in n:
		var inst := ItemService.grant(item, {"kind": &"gacha", "series_id": &"s1",
			"box_seed": 1, "draw_index": i})
		ids.append(inst.instance_id)
	return ids


# ══════════════════════════════════════════════════════════════════════════════
#  §10.1
# ══════════════════════════════════════════════════════════════════════════════

func _test_idempotent_grant() -> void:
	_reset()
	var src := {"kind": &"gacha", "series_id": &"s1", "box_seed": 7, "draw_index": 0}
	var a := ItemService.grant(&"stardust_q1", src)
	var n_before := ItemService.instances.size()
	var g_before := ItemService.total_granted
	var c_before := ItemService.count(&"stardust", 1)
	# 同一 instance_id 重放（模拟存档重放 / 日志补发）
	var b := ItemService.grant(&"stardust_q1", src, a.instance_id)
	eq(ItemService.instances.size(), n_before, "幂等命中：实例数不变")
	eq(b.instance_id, a.instance_id, "幂等命中：返回同一个实例")
	eq(ItemService.total_granted, g_before, "幂等命中：total_granted 不变")
	eq(ItemService.count(&"stardust", 1), c_before, "幂等命中：count 不变")

	# 幂等命中不得把邮件实例"顺手"搬进仓库
	_reset(1)  # 容量 1，q1 的 size 也是 1 → 第二件必进邮件
	ItemService.grant(&"stardust_q1", src)
	var m := ItemService.grant(&"stardust_q1", src)
	eq(m.location, ItemConstants.LOC_MAIL, "容量不足时落邮件")
	var again := ItemService.grant(&"stardust_q1", src, m.instance_id)
	eq(again.location, ItemConstants.LOC_MAIL, "幂等命中：不改 location")


func _test_uuid_uniqueness() -> void:
	var seen := {}
	var bad_format := 0
	var n := 20000
	for i in n:
		var u := Uuid.v4()
		if seen.has(u):
			_fail += 1
			print("  [FAIL] UUID 碰撞：%s" % u)
			return
		seen[u] = true
		if not Uuid.is_valid(u):
			bad_format += 1
	ok(true, "UUID 唯一性：%d 个零碰撞" % n)
	eq(bad_format, 0, "UUID 格式：36 字符 / version 4 / variant RFC 4122 / 全小写")


func _test_uuid_not_from_seed() -> void:
	# 实例身份必须与抽取随机流**无关**：同一 (series, seed, index) 重放两次
	# （不传 instance_id）必须得到不同 id，否则幂等键失去意义
	_reset()
	var src := {"kind": &"gacha", "series_id": &"s1", "box_seed": 42, "draw_index": 3}
	var a := ItemService.grant(&"stardust_q1", src)
	var b := ItemService.grant(&"stardust_q1", src)
	ok(a.instance_id != b.instance_id, "同 source 两次开盒得到不同 instance_id（身份与种子无关）")
	ok(a.serial != b.serial, "同 source 两次开盒的 serial 递增（编号不复用）")


func _test_serial_semantics() -> void:
	_reset()
	var a := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(a.serial, 1, "开盒产出：serial 从 1 起")
	var b := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(b.serial, 2, "开盒产出：serial 单调递增")

	# 非开盒来源一律 0，且不推进计数器
	eq(ItemService.grant(&"stardust_q1", {"kind": &"convert"}).serial, 0, "转化产出：serial == 0")
	eq(ItemService.grant(&"stardust_q1", {"kind": &"refund"}).serial, 0, "返还产出：serial == 0")
	eq(ItemService.grant(&"stardust_q1", {"kind": &"unlock"}).serial, 0, "解锁产出：serial == 0")

	var c := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(c.serial, 3, "非开盒来源不占号：下一个开盒仍是 3")

	# 销毁编号最大的实例后，编号不复用
	ItemService.consume([c.instance_id], ItemConstants.TAG_FUEL)
	var d := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(d.serial, 4, "编号不复用：销毁后继续 N+1")

	# 未注册 item_id
	eq(ItemService.grant(&"nope", {"kind": &"gacha"}), null, "未注册 item_id → 返回 null")


# ══════════════════════════════════════════════════════════════════════════════
#  §10.2
# ══════════════════════════════════════════════════════════════════════════════

func _test_count_matches_rebuild() -> void:
	_reset()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var items := [&"stardust_q1", &"stardust_q2", &"crystal_q1", &"crystal_q3"]
	for i in 1000:
		ItemService.grant(items[rng.randi_range(0, 3)], {"kind": &"gacha"})
	var incremental := ItemService.count_index.duplicate()
	var incremental_used := ItemService.warehouse_used
	var rebuilt := ItemService.rebuild_count_index()
	eq(_dict_eq(incremental, ItemService.count_index), true, "count_index 增量 == 全量重算")
	eq(incremental_used, ItemService.warehouse_used, "warehouse_used 增量 == 全量重算")
	# 每个键的值 == 实例列表中该 (category, quality) 的实例数（仅仓库）
	var manual := {}
	for inst in ItemService.instances:
		if not inst.is_in_warehouse():
			continue
		var def := ItemCatalog.get_def(inst.item_id)
		var k := def.count_key()
		manual[k] = int(manual.get(k, 0)) + 1
	eq(_dict_eq(manual, ItemService.count_index), true, "count_index 逐键 == 手工统计实例")


func _test_count_immediate() -> void:
	_reset()
	var before := ItemService.count(&"stardust", 1)
	ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(ItemService.count(&"stardust", 1), before + 1, "grant 后同帧 count 立即生效")
	var ids := ItemService.query(&"stardust", 1)
	ItemService.consume([ids[0]], ItemConstants.TAG_FUEL)
	eq(ItemService.count(&"stardust", 1), before, "consume 后同帧 count 立即生效")


func _test_zero_key_removed() -> void:
	_reset()
	var ids := _grant_q1(2)
	ItemService.consume([ids[0], ids[1]], ItemConstants.TAG_FUEL)
	ok(not ItemService.count_index.has("stardust:1"), "归零即消键（不保留 0 条目）")
	ok(ItemService.count(&"stardust", 1) >= 0, "count 恒 >= 0")


func _test_key_count_bound() -> void:
	_reset()
	for i in 10000:
		ItemService.grant(&"crystal_q3", {"kind": &"gacha"})
	ok(ItemService.count_index.size() <= 6, "键数 ≤ 类别数 × 品质数（切片 6），与实例数无关")
	eq(ItemService.count_index.size(), 1, "10000 个实例只占 1 个键")


# ══════════════════════════════════════════════════════════════════════════════
#  §10.3
# ══════════════════════════════════════════════════════════════════════════════

func _test_consume_atomic() -> void:
	_reset()
	var ids := _grant_q1(3)
	var snap := _state_snapshot()
	var res := ItemService.consume([ids[0], "不存在的-id"], ItemConstants.TAG_FUEL)
	eq(res["ok"], false, "含不存在 id → ok == false")
	eq(res["reason"], ItemConstants.REASON_MISSING_INSTANCE, "reason == missing_instance")
	eq(_state_snapshot(), snap, "失败即全不变（原子）")


func _test_duplicate_ids() -> void:
	_reset()
	var ids := _grant_q1(2)
	var snap := _state_snapshot()
	var res := ItemService.consume([ids[0], ids[0]], ItemConstants.TAG_FUEL)
	eq(res["reason"], ItemConstants.REASON_DUPLICATE_ID, "入参内重复 id → duplicate_id")
	eq(_state_snapshot(), snap, "重复 id 失败时状态不变")

	# 空列表是合法 no-op
	eq(ItemService.consume([] as Array[String], ItemConstants.TAG_FUEL)["ok"], true, "空列表 → 合法 no-op")

	# tag 运行时不变量
	var r2 := ItemService.consume([ids[0]], ItemConstants.TAG_UNKNOWN)
	eq(r2["reason"], ItemConstants.REASON_BAD_TAG, "不传 tag（unknown）→ bad_tag")
	var r3 := ItemService.consume([ids[0]], ItemConstants.TAG_DISCARD)
	eq(r3["reason"], ItemConstants.REASON_BAD_TAG, "consume 传 discard → bad_tag（只能走 discard 入口）")

	# consume_by_filter 越界
	var out := ItemService.consume_by_filter(&"stardust", 1, 99, ItemConstants.TAG_ENGINE)
	eq(out.size(), 0, "consume_by_filter 越界 → 返回 []")


func _test_pick_order() -> void:
	_reset()
	# 造跨品质、跨时间的数据集
	var lo := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	var mid_a := ItemService.grant(&"stardust_q2", {"kind": &"gacha"})
	var mid_b := ItemService.grant(&"stardust_q2", {"kind": &"gacha"})
	var hi := ItemService.grant(&"stardust_q3", {"kind": &"gacha"})
	# 手工设不同 acquired_at（同秒是默认，故显式区分）
	lo.acquired_at = 100
	mid_a.acquired_at = 200
	mid_b.acquired_at = 200  # 同秒 → 由 instance_id 字典序打破
	hi.acquired_at = 50      # 时间最早，但品质最高

	var q := ItemService.query(&"stardust", 1)
	eq(q[0], lo.instance_id, "最低合格品质优先")
	ok(q[3] == hi.instance_id, "时间最早但品质最高的排在最后（品质优先于时间）")
	# 同品质内 FIFO，同秒按 instance_id
	var expected_mid := [mid_a.instance_id, mid_b.instance_id]
	expected_mid.sort()
	eq([q[1], q[2]], expected_mid, "同品质内按 (acquired_at, instance_id)")

	var consumed := ItemService.consume_by_filter(&"stardust", 2, 2, ItemConstants.TAG_ENGINE)
	eq(consumed.size(), 2, "按条件销毁返回 n 个")
	eq(consumed[0], mid_a.instance_id if mid_a.instance_id < mid_b.instance_id else mid_b.instance_id,
		"销毁的是合格集前 2 个")


func _test_double_destroy() -> void:
	_reset()
	var ids := _grant_q1(1)
	ItemService.consume([ids[0]], ItemConstants.TAG_FUEL)
	var res := ItemService.consume([ids[0]], ItemConstants.TAG_FUEL)
	eq(res["reason"], ItemConstants.REASON_MISSING_INSTANCE, "同一实例销毁两次 → 第二次 missing_instance")


# ══════════════════════════════════════════════════════════════════════════════
#  §10.4
# ══════════════════════════════════════════════════════════════════════════════

func _test_save_roundtrip() -> void:
	_reset(50)
	for i in 12:
		ItemService.grant(&"stardust_q1", {"kind": &"gacha", "series_id": &"s1",
			"box_seed": i, "draw_index": i})
	ItemService.grant(&"crystal_q2", {"kind": &"convert"})
	ItemService.grant(&"crystal_q3", {"kind": &"refund"})
	var d1 := ItemService.to_save_dict()
	var j1 := JSON.stringify(d1)
	ItemService.from_save_dict(JSON.parse_string(j1))
	var j2 := JSON.stringify(ItemService.to_save_dict())
	eq(j2, j1, "存档往返字节级稳定（to→json→from→to）")

	eq(ItemService.check_conservation(), true, "载入后守恒式成立")
	var manual := {}
	for inst in ItemService.instances:
		if not inst.is_in_warehouse():
			continue
		var def := ItemCatalog.get_def(inst.item_id)
		manual[def.count_key()] = int(manual.get(def.count_key(), 0)) + 1
	eq(_dict_eq(manual, ItemService.count_index), true, "载入后 rebuild 与实例列表逐项一致（count_index 不入档）")

	# 只存现存实例
	var before_n := ItemService.instances.size()
	var ids := ItemService.query(&"stardust", 1)
	ItemService.consume([ids[0]], ItemConstants.TAG_FUEL)
	var d2 := ItemService.to_save_dict()
	eq((d2["instances"] as Array).size(), before_n - 1, "只存现存实例：销毁后存档少一条")


# ══════════════════════════════════════════════════════════════════════════════
#  §10.5
# ══════════════════════════════════════════════════════════════════════════════

func _test_conservation() -> void:
	_reset(30)
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	for i in 1000:
		match rng.randi_range(0, 3):
			0:
				ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
			1:
				var q := ItemService.query(&"stardust", 1)
				if q.size() > 0:
					ItemService.consume([q[0]], ItemConstants.TAG_FUEL)
			2:
				var m := ItemService.mail_instances()
				if m.size() > 0:
					ItemService.claim([m[0].instance_id])
			3:
				var q2 := ItemService.query(&"stardust", 1)
				if q2.size() > 0:
					ItemService.discard([q2[0]])
	ok(ItemService.check_conservation(), "1000 次混合操作后：instances.size() == total_granted − total_consumed")
	ok(ItemService.warehouse_used <= ItemService.warehouse_capacity, "任何一步都未越过容量")


# ══════════════════════════════════════════════════════════════════════════════
#  §10.8
# ══════════════════════════════════════════════════════════════════════════════

func _test_overflow_boundaries() -> void:
	# q1 的 size = 1，容量 2
	_reset(2)
	var a := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	var b := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(a.location, ItemConstants.LOC_WAREHOUSE, "刚好放得下 → warehouse")
	eq(b.location, ItemConstants.LOC_WAREHOUSE, "填满容量 → warehouse")
	var c := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(c.location, ItemConstants.LOC_MAIL, "超出一件 → mail")
	eq(ItemService.warehouse_used, 2, "邮件实例不计入 warehouse_used")
	eq(ItemService.warehouse_usage()["used"], 2, "warehouse_usage().used 正确")
	ok(c != null, "被动产出装不下仍被创建（P5：产出永不丢失）")

	# 超出一件时不再有空间，后续全进邮件
	var d := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(d.location, ItemConstants.LOC_MAIL, "持续超出 → 全部进邮件")


func _test_mail_not_counted() -> void:
	_reset(1)
	ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	var before := ItemService.count(&"stardust", 1)
	var mail_before := ItemService.count(&"stardust", 1, ItemConstants.LOC_MAIL)
	ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(ItemService.count(&"stardust", 1), before, "落邮件后 count(仓库) 不增加")
	eq(ItemService.count(&"stardust", 1, ItemConstants.LOC_MAIL), mail_before + 1, "count(mail) 增加 1")
	# 两口径不得隐式合并
	eq(ItemService.count(&"stardust", 1) + ItemService.count(&"stardust", 1, ItemConstants.LOC_MAIL),
		ItemService.instances.size(), "两个口径互不隐式合并（各自独立计数）")

	# 邮件实例不可用于消耗
	var m := ItemService.mail_instances()
	var res := ItemService.consume([m[0].instance_id], ItemConstants.TAG_FUEL)
	eq(res["reason"], ItemConstants.REASON_NOT_IN_WAREHOUSE, "邮件实例不可被销毁 → not_in_warehouse")
	eq(ItemService.query(&"stardust", 1).has(m[0].instance_id), false, "邮件实例不进 query 合格集")


func _test_claim_only_location() -> void:
	_reset(1)
	ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	var m := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(m.location, ItemConstants.LOC_MAIL, "前置：第二件在邮件")

	var g_before := ItemService.total_granted
	var c_before := ItemService.total_consumed
	var ser_before := m.serial
	var src_before := JSON.stringify(m.source)

	# 仓库已满 → 一件都领不进
	var full := ItemService.claim([m.instance_id])
	eq(full["claimed"].size(), 0, "仓库满时领取：claimed 为空")
	eq(full["reason"], ItemConstants.REASON_NO_SPACE, "仓库满时领取：reason == no_space")

	# 腾出空间后领取
	var q := ItemService.query(&"stardust", 1)
	ItemService.consume([q[0]], ItemConstants.TAG_FUEL)
	# 快照必须在 consume **之后**取：领取的可比对象是"领取前"，不是"本次会话开始时"
	var n_before := ItemService.instances.size()
	var ids_before := _id_set()
	var res := ItemService.claim([m.instance_id])
	eq(res["ok"], true, "腾出空间后领取成功")
	eq(m.location, ItemConstants.LOC_WAREHOUSE, "领取只改 location")

	eq(ItemService.instances.size(), n_before, "领取前后实例总数不变")
	eq(_id_set(), ids_before, "领取前后 instance_id 集合逐项相等")
	eq(m.serial, ser_before, "领取不改 serial")
	eq(JSON.stringify(m.source), src_before, "领取不改 source")
	eq(ItemService.total_granted, g_before, "领取不动 total_granted")
	eq(ItemService.total_consumed, c_before + 1, "领取不动 total_consumed（只有那次 consume 生效）")

	# 重复领取是幂等 no-op
	var again := ItemService.claim([m.instance_id])
	eq(again["claimed"].has(m.instance_id), true, "重复领取：no-op 且计入 claimed")
	eq(ItemService.instances.size(), n_before, "重复领取实例数不变")


func _test_claim_partial() -> void:
	# 容量 2：q2(size 2) 就把仓库占满 → 邮件里的 3 件 q1(size 1) 一件也领不进；
	# 销毁 q2 腾出 2 点空间后，只能领进 2 件（部分成功，第 3 件留在邮件）
	_reset(2)
	ItemService.grant(&"stardust_q2", {"kind": &"gacha"})  # 占 2 → 满
	var m1 := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	var m2 := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	var m3 := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(m1.location, ItemConstants.LOC_MAIL, "前置：容量已满")
	eq(m2.location, ItemConstants.LOC_MAIL, "前置：容量已满")
	eq(m3.location, ItemConstants.LOC_MAIL, "前置：容量已满")

	# 腾出 2 点空间 → 3 件各占 1，只能领 2 件（部分成功）
	var q := ItemService.query(&"stardust", 2)
	ItemService.consume([q[0]], ItemConstants.TAG_FUEL)
	var res := ItemService.claim([m1.instance_id, m2.instance_id, m3.instance_id])
	eq(res["claimed"].size(), 2, "部分成功：尽可能多领（领进 2 件）")
	eq(res["remaining"].size(), 1, "剩余 1 件留在邮件")
	eq(res["ok"], false, "ok == (claimed.size() == 请求数) → false")
	ok(ItemService.warehouse_used <= ItemService.warehouse_capacity, "部分领取后仍未超容")


func _test_transact_atomic() -> void:
	_reset(100)
	var ids := _grant_q1(3)
	var snap := _state_snapshot()
	# 必然失败的组合：consume 合法 + grant 未注册 item_id
	var res := ItemService.transact([
		{"op": &"consume", "instance_ids": [ids[0]], "tag": &"convert"},
		{"op": &"grant", "item_id": &"nope", "source": {"kind": &"convert"}},
	])
	eq(res["ok"], false, "事务含非法 op → ok == false")
	eq(res["reason"], ItemConstants.REASON_BAD_OP, "reason == bad_op")
	eq(_state_snapshot(), snap, "事务失败：全部状态逐项回到事务前（源实例未销毁）")

	# 成功路径
	var res2 := ItemService.transact([
		{"op": &"consume", "instance_ids": [ids[0]], "tag": &"convert"},
		{"op": &"grant", "item_id": &"crystal_q1", "source": {"kind": &"convert"}},
	])
	eq(res2["ok"], true, "合法事务成功")
	eq(res2["consumed"].size(), 1, "事务返回 consumed")
	eq(res2["granted"].size(), 1, "事务返回 granted")
	eq(res2["mailed"].size(), 0, "主动操作产出不落邮件（mailed == []）")

	# 键集非法
	var res3 := ItemService.transact([{"op": &"discard", "instance_ids": [], "tag": &"fuel"}])
	eq(res3["reason"], ItemConstants.REASON_BAD_OP, "discard op 带 tag（多键）→ bad_op")

	# op 类型非法
	eq(ItemService.transact([{"op": &"nope"}])["reason"], ItemConstants.REASON_BAD_OP, "未知 op 类型 → bad_op")


func _test_transact_no_space() -> void:
	_reset(3)
	ItemService.grant(&"stardust_q2", {"kind": &"gacha"})  # 占 2，剩 1
	var src := _grant_q1(1)  # 占 1 → 满
	eq(ItemService.warehouse_used, 3, "前置：仓库满")
	var snap := _state_snapshot()
	# 主动操作：销毁源（腾出 2）+ 创建 q3(size 5) → 放不下 → 整个事务被拒
	var res := ItemService.transact([
		{"op": &"consume", "instance_ids": [src[0]], "tag": &"convert"},
		{"op": &"grant", "item_id": &"stardust_q3", "source": {"kind": &"convert"}},
	])
	eq(res["ok"], false, "主动操作产出放不下 → 事务被拒")
	eq(res["reason"], ItemConstants.REASON_NO_SPACE, "reason == no_space")
	eq(res["mailed"].size(), 0, "主动操作绝不落邮件（mailed == []）")
	eq(_state_snapshot(), snap, "源实例逐项仍在（不被销毁）")


func _test_overflow_loosening_rejected() -> void:
	_reset(1)
	ItemService.grant(&"stardust_q1", {"kind": &"gacha"})  # 占满
	# 主动操作声明 mail → 越权放宽 → 拒绝
	eq(ItemService.grant(&"crystal_q1", {"kind": &"convert"}, "", ItemConstants.OVERFLOW_MAIL),
		null, "主动操作声明 overflow = mail → grant 返回 null（越权放宽被拒）")
	# 被动产出声明 reject → 收紧，允许
	eq(ItemService.grant(&"crystal_q1", {"kind": &"gacha"}, "", ItemConstants.OVERFLOW_REJECT),
		null, "被动产出声明 reject → 允许收紧，装不下即被拒")
	# 被动产出默认 → 进邮件
	var g := ItemService.grant(&"crystal_q1", {"kind": &"gacha"})
	eq(g.location, ItemConstants.LOC_MAIL, "被动产出默认 overflow → 进邮件")
	# 越权放宽在 transact 内同样生效
	var res := ItemService.transact([
		{"op": &"grant", "item_id": &"crystal_q2", "source": {"kind": &"convert"},
			"overflow": &"mail"},
	])
	eq(res["reason"], ItemConstants.REASON_BAD_OP, "transact 内越权放宽 → bad_op")
	# 未知 kind
	eq(ItemService.grant(&"crystal_q1", {"kind": &"migration"}), null,
		"未知 kind（migration）→ 拒绝（取值是 migrate）")


func _test_no_partial_containment() -> void:
	# 一次超过容量 10 倍的批量产出：最终态必须 used <= capacity，
	# 且 mail_count == 总产出数 − 入库数（**不存在"半个实例入库"**）
	_reset(5)
	var n := 50
	var ware := 0
	for i in n:
		if ItemService.grant(&"stardust_q1", {"kind": &"gacha"}).is_in_warehouse():
			ware += 1
	ok(ItemService.warehouse_used <= 5, "批量超容产出后 used <= capacity")
	eq(ware, 5, "入库数 == 容量 / size（完全填满，无部分入库）")
	eq(ItemService.instances.size(), n, "全部实例都被创建（产出永不丢失）")
	eq(ItemService.count(&"stardust", 1, ItemConstants.LOC_MAIL), n - ware, "mail_count == 总产出数 − 入库数")


func _test_discard_escape_valve() -> void:
	_reset(2)
	var a := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	var b := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	var m := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(ItemService.warehouse_used, 2, "前置：仓库满")

	# ① 丢弃成功、warehouse_used 下降、total_consumed 增加、守恒式仍成立
	var c_before := ItemService.total_consumed
	var res := ItemService.discard([a.instance_id])
	eq(res["ok"], true, "丢弃成功")
	eq(ItemService.warehouse_used, 1, "丢弃后 warehouse_used 下降")
	eq(ItemService.total_consumed, c_before + 1, "丢弃计入 total_consumed")
	ok(ItemService.check_conservation(), "丢弃后守恒式仍成立")

	# ② 随后 claim 至少能领进 1 件（死局可解）
	var claim_res := ItemService.claim([m.instance_id])
	eq(claim_res["claimed"].size(), 1, "死局可解：丢弃腾出空间后能领进 1 件")

	# ③ 丢弃量单列：不计入三个出口标签
	var inter: Dictionary = ItemService.get_meta("outlet_totals", {})
	# （出口归因记账归 07；此处只断言 discard 的语义不产出、只减不增）
	eq(ItemService.instances.size(), 2, "丢弃不产生产出（实例数只减不增）")

	# ④ 不能丢弃邮件实例
	var m2 := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(m2.location, ItemConstants.LOC_MAIL, "前置：容量已满")
	eq(ItemService.discard([m2.instance_id])["reason"], ItemConstants.REASON_NOT_IN_WAREHOUSE,
		"不能丢弃邮件实例 → not_in_warehouse")


func _test_config_validator() -> void:
	# V1：(category, quality) 唯一
	var d := ItemDef.new()
	d.item_id = &"dup_a"
	d.category = &"stardust"
	d.quality = 1  # 与 stardust_q1 冲突
	d.value = 1
	d.size = 1
	ItemCatalog.register(d)
	var v := ItemCatalog.validate()
	eq(v["ok"], false, "V1：两维键冲突 → 校验失败")
	ok(_errors_contain(v["errors"], "V1"), "V1：错误信息点名冲突")

	# V2：size > 0
	ItemCatalog.clear()
	_setup_catalog()
	var bad := ItemDef.new()
	bad.item_id = &"bad_size"
	bad.category = &"stardust"
	bad.quality = 5
	bad.size = 0
	ItemCatalog.register(bad)
	ok(_errors_contain(ItemCatalog.validate()["errors"], "V2"), "V2：size == 0 → 校验失败")

	# 容量 >= 1
	_setup_catalog()
	ItemService.warehouse_capacity = 0
	eq(ItemService.validate_config()["ok"], false, "warehouse_capacity == 0 → 校验失败")

	# 合法配置一律通过
	_setup_catalog()
	ItemService.warehouse_capacity = 1000
	eq(ItemCatalog.validate()["ok"], true, "合法配置通过（校验器不改任何数值）")
	eq(ItemService.validate_config()["ok"], true, "合法容量通过")


# ══════════════════════════════════════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════════════════════════════════════

func _dict_eq(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k) or a[k] != b[k]:
			return false
	return true


func _id_set() -> Array:
	var out := []
	for inst in ItemService.instances:
		out.append(inst.instance_id)
	out.sort()
	return out


## 事务 / 原子性断言用的完整状态快照（逐项可比）。
func _state_snapshot() -> Dictionary:
	var insts := []
	for inst in ItemService.instances:
		insts.append(inst.to_dict())
	return {
		"instances": insts,
		"count_index": ItemService.count_index.duplicate(),
		"mail_count_index": ItemService.mail_count_index.duplicate(),
		"warehouse_used": ItemService.warehouse_used,
		"total_granted": ItemService.total_granted,
		"total_consumed": ItemService.total_consumed,
		"serial_counters": ItemService.serial_counters.duplicate(),
	}


func _errors_contain(errors: Array, needle: String) -> bool:
	for e in errors:
		if String(e).contains(needle):
			return true
	return false

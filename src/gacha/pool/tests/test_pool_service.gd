## 池子编辑服务测试（01-gacha.md §4.5 / §5.1 / §5.2 / §5.2.3 / §5.8 / §10.1）。
##
## 无头运行：
##   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
## 或直接：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . res://src/gacha/pool/tests/test_pool_service.tscn
##
## 退出码 0 = 全绿，1 = 有失败。
extends Node

const N := 8

var _pass := 0
var _fail := 0
var _defs: Array[ItemDef] = []
var _series: SeriesDef


func _ready() -> void:
	print("=== 池子编辑服务测试（01 §4.5 / §5.1 / §5.2 / §5.2.3 / §5.8）===\n")

	_test_box_creation()
	_test_base_state_is_the_pool_distribution()
	_test_ban_matches_the_documented_example()
	_test_boost_is_zero_sum()
	_test_plan_gates()
	_test_per_box_independence()
	_test_preview_is_read_only()
	_test_unsocket_refund_and_reversibility()
	_test_cost_insufficient_consumes_nothing()
	_test_unsocket_no_space_rejects_whole_operation()
	_test_explicit_replace_path()
	_test_broken_modules_are_reported()

	print("\n=== 结果：%d 通过 / %d 失败 ===" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ══════════════════════════════════════════════════════════════════════════════
#  断言助手（与 test_item_pool.gd 同一套）
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

## 8 件物品、**两维键互不相同**（V1 要求 `(category, quality)` 唯一）。
## `rarity` 取 10 的示例值：`s01_05` = 20、`s01_01..03` = 12、`s01_04/06/07/08` = 11。
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

	_series = SeriesDef.new()
	_series.series_id = &"series_01"
	_series.series_quality = 2                    # 品质 2 ⇒ 8 物品 / 3 位（核心 §4.1.1）
	_series.regular_count = N
	_series.socket_count = 3
	_series.regular_items = _defs.duplicate()
	GachaCatalog.register_series(_series)

	GachaCatalog.register_module(_module(&"mod_ban_05", ModuleDef.OpType.BAN, [&"s01_05"]))
	GachaCatalog.register_module(_module(&"mod_ban_08", ModuleDef.OpType.BAN, [&"s01_08"]))
	GachaCatalog.register_module(_module(&"mod_boost_05", ModuleDef.OpType.BOOST, [&"s01_05"], 3.0))
	GachaCatalog.register_module(_module(&"mod_boost_over", ModuleDef.OpType.BOOST, [&"s01_05"], 3.5))
	GachaCatalog.register_module(_module(&"mod_recover", ModuleDef.OpType.RECOVER, [&"s01_05"]))
	GachaCatalog.register_module(_module(&"mod_ban_many", ModuleDef.OpType.BAN,
		[&"s01_01", &"s01_02", &"s01_03", &"s01_04", &"s01_05", &"s01_06"]))
	# 有物品成本的模块：需求向量 = (stardust, 品质下限 2, 4 件)
	GachaCatalog.register_module(_module(&"mod_ban_costly", ModuleDef.OpType.BAN, [&"s01_05"], 1.0,
		[[&"stardust", 2, 4]]))
	# 互斥标记（V6）
	GachaCatalog.register_module(_module(&"mod_tag_a", ModuleDef.OpType.BAN, [&"s01_04"], 1.0, [],
		[&"exclusive_x"]))
	GachaCatalog.register_module(_module(&"mod_tag_b", ModuleDef.OpType.BAN, [&"s01_06"], 1.0, [],
		[&"exclusive_x"]))


func _module(
	id: StringName,
	op: int,
	targets: Array,
	magnitude: float = 1.0,
	cost: Array = [],
	tags: Array = [],
	mode: int = ModuleDef.RedistributeMode.AUTO,
	rtarget: StringName = &""
) -> ModuleDef:
	var m := ModuleDef.new()
	m.id = id
	m.display_name = String(id)
	m.quality = 2
	m.op_type = op
	m.magnitude = magnitude
	m.redistribute_mode = mode
	m.redistribute_target = rtarget
	for t in targets:
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


## 新档 + 发 `n` 个盒子。
func _new_state(n: int = 1) -> Dictionary:
	_setup()
	var st := GameState.new_game()   # v0.14：镶嵌需要设备（开局送一台基础装置）
	var boxes := GachaService.grant_box(st, &"series_01", n, &"test")
	return {"state": st, "boxes": boxes}


func _codes(errors: Array) -> Array[String]:
	var out: Array[String] = []
	for e in errors:
		out.append(String(e).split("：")[0])
	return out


# ══════════════════════════════════════════════════════════════════════════════
#  测试
# ══════════════════════════════════════════════════════════════════════════════

func _test_box_creation() -> void:
	print("— 发盒：box_id / 基础池副本 / 定长空位（01 §1 第 2 条 · §5.5）")
	var f := _new_state(2)
	var st: GameState = f["state"]
	var boxes: Array = f["boxes"]
	eq(boxes.size(), 2, "发出 2 个盒子")
	var a: Box = boxes[0]
	var b: Box = boxes[1]
	eq(a.item_pool.socket_count, 3, "池子冻结了 socket_count = 3（C4）")
	eq(a.item_pool.regular_count, 8, "池子冻结了 regular_count = 8（C6 的依据）")
	eq(a.modules.size(), 3, "modules 是定长数组，长度 == socket_count")
	ok(a.modules[0] == null and a.modules[2] == null, "空位为空项（不是缺字段、不是 []）")
	eq(a.item_pool.revision, 0, "新盒子 revision = 0")
	ok(a.item_pool != b.item_pool, "**同套系两盒的 item_pool 不是同一个对象**（池子随盒子走）")
	eq(a.box_id.length(), 36, "box_id 是 UUIDv4（36 字符）")
	ok(a.box_id != b.box_id, "两个盒子的 box_id 不同")
	eq(st.box_count(), 2, "两个盒子都进了囤积清单")


func _test_base_state_is_the_pool_distribution() -> void:
	print("— 未配置盒：派生状态 == 基础分布，void == 0（§5.2 第 0–9 步）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var ps := PoolService.get_pool_state(st, bx.box_id)
	eq(ps.weight_of(&"s01_05"), 2000, "rarity 20 ⇒ 2000 bp")
	eq(ps.weight_of(&"s01_01"), 1200, "rarity 12 ⇒ 1200 bp")
	eq(ps.weight_of(&"s01_04"), 1100, "rarity 11 ⇒ 1100 bp")
	eq(ps.void_mass_bp, 0, "未编辑池没有 void")
	ok(ps.is_zero_sum(), "Σ weights_bp + void_mass_bp == 10000（C1 整数口径）")
	eq(ps.producible_count(), 8, "8 件都可产出")
	ok(ps.box_id == bx.box_id, "派生状态记住了它属于哪个盒子")
	ok(ps.revision == 0, "revision 与 item_pool 同步")


func _test_ban_matches_the_documented_example() -> void:
	print("— 排除（BAN）：与 10-progression.md 的示例算术逐位一致（40% 蒸发 + 60% 按基础权重摊回）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var r := PoolService.socket(st, bx.box_id, &"mod_ban_05", 0)
	ok(r["ok"], "镶嵌排除模块成功")
	var ps: PoolState = r["state"]
	eq(ps.weight_of(&"s01_05"), 0, "被排除物品权重归零")
	eq(ps.weight_of(&"s01_01"), 1380, "rarity 12 的三项：1200 → 1380（+15%）")
	eq(ps.weight_of(&"s01_02"), 1380, "同上（第 2 项）")
	eq(ps.weight_of(&"s01_03"), 1380, "同上（第 3 项）")
	eq(ps.weight_of(&"s01_04"), 1265, "rarity 11 的四项：1100 → 1265（+15%）")
	eq(ps.weight_of(&"s01_08"), 1265, "同上（第 4 项）")
	eq(ps.void_mass_bp, 800, "释放的 2000 bp 里 40% 蒸发为 void（C2）")
	ok(ps.is_zero_sum(), "Σ 物品 9200 + void 800 == 10000（C1）")
	eq(ps.producible_count(), 7, "可产出物品 7 件（C6 下限 3 仍满足）")
	eq(bx.item_pool.revision, 1, "写入后 revision +1")
	eq(bx.occupied_count(), 1, "已占用位数 == 1（模块进入了这个盒子的 modules）")
	eq(bx.modules[0].module_id, &"mod_ban_05", "第 0 位装的是它（槽位 = 数组下标）")


func _test_boost_is_zero_sum() -> void:
	print("— 提升（BOOST）：目标 ×N，**增量从其他物品按比例扣除**（零和）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var before := PoolService.get_pool_state(st, bx.box_id)
	var r := PoolService.socket(st, bx.box_id, &"mod_boost_05", 0)
	ok(r["ok"], "镶嵌提升模块成功")
	var ps: PoolState = r["state"]
	eq(ps.weight_of(&"s01_05"), 6000, "目标 2000 → 6000（×3）")
	eq(ps.weight_of(&"s01_01"), 600, "其余项等比缩水：1200 → 600")
	eq(ps.weight_of(&"s01_04"), 550, "其余项等比缩水：1100 → 550")
	eq(ps.item_mass_bp(), before.item_mass_bp(), "物品质量总量恒定（零和：提升不是凭空加概率）")
	eq(ps.void_mass_bp, 0, "提升不产生 void")
	ok(ps.is_zero_sum(), "Σ == 10000（C1）")


func _test_plan_gates() -> void:
	print("— 合法性闸门（§5.2.3 V2–V7 / C6）：非法计划必须**响亮拒绝**且不产生任何消耗")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]

	var r1 := PoolService.socket(st, bx.box_id, &"mod_ban_05", 1)
	ok(r1["ok"], "先装一个排除模块（目标 s01_05）")
	var r2 := PoolService.socket(st, bx.box_id, &"mod_boost_05", 2)
	ok(not r2["ok"], "同一物品既排除又提升 ⇒ 拒绝")
	eq(r2["reason"], PoolService.R_BAN_BOOST_CONFLICT, "原因码 = ban_boost_conflict（V2）")

	var r3 := PoolService.socket(st, bx.box_id, &"mod_ban_08", 1)
	ok(not r3["ok"], "往**占用位**放 ⇒ 拒绝")
	eq(r3["reason"], PoolService.R_SLOT_OCCUPIED, "原因码 = slot_occupied（必须显式替换，不做隐式覆盖）")

	var r4 := PoolService.socket(st, bx.box_id, &"mod_boost_over", 0)
	ok(not r4["ok"], "提升倍数 3.5× ⇒ 拒绝")
	eq(r4["reason"], PoolService.R_BOOST_OVER_CAP, "原因码 = boost_over_cap（V4 / 核心 D7）")

	var r5 := PoolService.socket(st, bx.box_id, &"mod_recover", 0)
	ok(not r5["ok"], "RECOVER 模块 ⇒ 拒绝（第二切片，本版仅定义接口）")
	eq(r5["reason"], PoolService.R_RECOVER_UNSUPPORTED, "原因码 = recover_unsupported")

	var r6 := PoolService.socket(st, bx.box_id, &"mod_ban_many", 0)
	ok(not r6["ok"], "一次排除 6 件 ⇒ 拒绝")
	eq(r6["reason"], PoolService.R_BAN_LIMIT, "原因码 = ban_limit_exceeded（V5：ban_limit = 8 − 3 = 5）")

	var r7 := PoolService.socket(st, bx.box_id, &"no_such_module", 0)
	ok(not r7["ok"], "未注册的 module_id ⇒ 拒绝")
	eq(r7["reason"], PoolService.R_UNKNOWN_MODULE, "原因码 = unknown_module（V7：非空项良构）")

	var r8 := PoolService.socket(st, bx.box_id, &"mod_ban_05", 9)
	ok(not r8["ok"], "slot 越界 ⇒ 拒绝")
	eq(r8["reason"], PoolService.R_BAD_SLOT, "原因码 = bad_slot")

	var r9 := PoolService.socket(st, bx.box_id, &"mod_tag_a", 0)
	ok(r9["ok"], "装一个带互斥标记的模块")
	var r10 := PoolService.socket(st, bx.box_id, &"mod_tag_b", 2)
	ok(not r10["ok"], "共享互斥标记的两个模块 ⇒ 拒绝共存")
	eq(r10["reason"], PoolService.R_TAG_CONFLICT, "原因码 = exclusive_tag_conflict（V6）")

	eq(bx.occupied_count(), 2, "上述失败**一个都没写进 modules**（只有成功的 2 个）")
	eq(bx.item_pool.revision, 2, "revision 只在成功写入时推进（0 → 2）")


func _test_per_box_independence() -> void:
	print("— 池子随盒子走（§2 三条不得越界 / §10.1 T12）：编辑 A 不得影响 B 的一个字节")
	var f := _new_state(2)
	var st: GameState = f["state"]
	var a: Box = f["boxes"][0]
	var b: Box = f["boxes"][1]
	var b_before := PoolService.get_pool_state(st, b.box_id)
	var b_weights_before := b_before.weights_bp.duplicate()
	ok(PoolService.socket(st, a.box_id, &"mod_ban_05", 0)["ok"], "编辑盒子 A")
	var a_after := PoolService.get_pool_state(st, a.box_id)
	var b_after := PoolService.get_pool_state(st, b.box_id)
	eq(a_after.weight_of(&"s01_05"), 0, "A 的 s01_05 被排除")
	eq(b_after.weight_of(&"s01_05"), 2000, "**B 的 s01_05 一点没变**")
	var same := true
	for k in b_weights_before.keys():
		if int(b_weights_before[k]) != b_after.weight_of(StringName(k)):
			same = false
	ok(same, "B 的全部权重逐项等于编辑前")
	eq(b_after.void_mass_bp, 0, "B 的 void 仍为 0（A 的损耗没有渗过去）")
	eq(b.item_pool.revision, 0, "B 的 revision 没动")
	eq(a.item_pool.revision, 1, "A 的 revision = 1")
	ok(a_after.weight_of(&"s01_01") != b_after.weight_of(&"s01_01"), "A ≠ B 是正确行为（不是需要抹平的差异）")


func _test_preview_is_read_only() -> void:
	print("— 试算 preview_socket：**只读沙盒**（不写状态 / 不推进 revision / 不动实例）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var inst_before := ItemService.instances.size()
	var ps := PoolService.preview_socket(st, bx.box_id, 0, &"mod_boost_05")
	ok(ps != null, "试算返回候选状态")
	eq(ps.weight_of(&"s01_05"), 6000, "候选状态反映提升后的分布")
	eq(bx.item_pool.revision, 0, "**revision 没有被推进**")
	eq(bx.occupied_count(), 0, "**modules 没有被写入**")
	eq(ItemService.instances.size(), inst_before, "没有实例被消耗")
	var real := PoolService.get_pool_state(st, bx.box_id)
	eq(real.weight_of(&"s01_05"), 2000, "真实状态仍是基础分布（试算没有渗进去）")
	ok(ps != real, "候选状态与真实状态是两个对象")


func _test_unsocket_refund_and_reversibility() -> void:
	print("— 拆卸（§5.8 / §10.1 T6）：返还 floor(cost × 0.5) 的**新实例**，池子回到基础态")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	# 备好制造成本：需求向量 (stardust, 品质下限 2, 4 件) ⇒ 4 件 `s01_02`（category stardust / quality 2 / size 2）
	var made: Array[String] = []
	for _i in 4:
		var inst := ItemService.grant(&"s01_02", {"kind": ItemConstants.KIND_UNLOCK})
		made.append(inst.instance_id)
	eq(ItemService.count(&"stardust", 2), 4, "仓库里有 4 件满足需求的实例")
	eq(ItemService.warehouse_usage()["used"], 8, "占 4 × size 2 = 8")

	var r := PoolService.socket(st, bx.box_id, &"mod_ban_costly", 0)
	ok(r["ok"], "镶嵌成功（制造消耗在同一事务里原子完成）")
	eq(ItemService.count(&"stardust", 2), 0, "4 件成本被销毁")
	var ps_socketed: PoolState = r["state"]
	eq(ps_socketed.void_mass_bp, 800, "已生效：void 800")

	var u := PoolService.unsocket(st, bx.box_id, 0)
	ok(u["ok"], "拆卸成功")
	eq(ItemService.count(&"stardust", 2), 2, "返还 floor(4 × 0.5) = 2 件")
	ok(ItemService.check_conservation(), "守恒等式仍成立（total_granted − total_consumed == 实例数）")
	var ps_after: PoolState = u["state"]
	eq(ps_after.void_mass_bp, 0, "**PoolState 回到基础态且 void == 0**（T6 ①）")
	eq(ps_after.weight_of(&"s01_05"), 2000, "被排除项回到基础权重")
	ok(ps_after.is_zero_sum(), "Σ == 10000")
	eq(bx.occupied_count(), 0, "该位被置空")
	eq(bx.modules.size(), 3, "**定长长度不变**")
	eq(bx.item_pool.revision, 2, "revision = 2（镶嵌 +1、拆卸 +1）")
	# 返还的是**新实例**：UUID 与制造时被销毁的那批不相交（T6 ③）
	var new_ids: Array[String] = []
	for inst in ItemService.instances:
		if inst.item_id == &"s01_02":
			new_ids.append(inst.instance_id)
	eq(new_ids.size(), 2, "仓库里恰好 2 件返还实例")
	var disjoint := true
	for id in new_ids:
		if made.has(id):
			disjoint = false
	ok(disjoint, "返还实例的 UUID 与制造时销毁的**交集为空**（可逆说的是数量与状态，不是实例身份）")
	var serial_zero := true
	for inst in ItemService.instances:
		if inst.item_id == &"s01_02" and inst.serial != 0:
			serial_zero = false
	ok(serial_zero, "返还实例的 serial == 0（非开盒来源，02 内部置位）")


func _test_cost_insufficient_consumes_nothing() -> void:
	print("— 制造成本不足 ⇒ **整体失败**，且一个实例都不消耗（§5.8 原子性）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	for _i in 2:
		ItemService.grant(&"s01_02", {"kind": ItemConstants.KIND_UNLOCK})
	var granted_before := ItemService.total_granted
	var consumed_before := ItemService.total_consumed
	var r := PoolService.socket(st, bx.box_id, &"mod_ban_costly", 0)
	ok(not r["ok"], "只备了 2 件、需求 4 件 ⇒ 拒绝")
	eq(r["reason"], PoolService.R_COST_INSUFFICIENT, "原因码 = cost_insufficient")
	eq(ItemService.count(&"stardust", 2), 2, "**一件都没被销毁**")
	eq(ItemService.total_granted, granted_before, "total_granted 不变")
	eq(ItemService.total_consumed, consumed_before, "total_consumed 不变")
	eq(bx.occupied_count(), 0, "modules 没被写入")
	eq(bx.item_pool.revision, 0, "revision 没被推进")


func _test_unsocket_no_space_rejects_whole_operation() -> void:
	print("— 返还装不下 ⇒ **拒绝整个拆卸**（裁决 17：主动操作不产生净损失）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	ItemService.warehouse_capacity = 10
	for _i in 4:
		ItemService.grant(&"s01_02", {"kind": ItemConstants.KIND_UNLOCK})
	ok(PoolService.socket(st, bx.box_id, &"mod_ban_costly", 0)["ok"], "先镶嵌（消耗 4 件，腾空仓库）")
	for _i in 5:
		ItemService.grant(&"s01_02", {"kind": ItemConstants.KIND_UNLOCK})
	eq(ItemService.warehouse_usage()["used"], 10, "仓库恰好占满（5 件 × size 2）")
	var inst_before := ItemService.instances.size()
	var ps_before := PoolService.get_pool_state(st, bx.box_id)
	var ps_weights_before := ps_before.weights_bp.duplicate()

	var u := PoolService.unsocket(st, bx.box_id, 0)
	ok(not u["ok"], "返还 2 件 × size 2 = 4 装不下 ⇒ 拒绝")
	eq(u["reason"], PoolService.R_NO_SPACE, "原因码 = no_space")
	eq(bx.occupied_count(), 1, "**该位仍含那一项**（没有先拆再补救）")
	eq(ItemService.instances.size(), inst_before, "实例列表逐项不变")
	var same := true
	for k in ps_weights_before.keys():
		if int(ps_weights_before[k]) != PoolService.get_pool_state(st, bx.box_id).weight_of(StringName(k)):
			same = false
	ok(same, "PoolState 逐项不变")
	eq(bx.item_pool.revision, 1, "revision 没有推进")


func _test_explicit_replace_path() -> void:
	print("— 替换的唯一路径：显式 unsocket 后再 socket（不做隐式覆盖）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	ok(PoolService.socket(st, bx.box_id, &"mod_ban_05", 0)["ok"], "第 0 位装上排除模块")
	ok(not PoolService.socket(st, bx.box_id, &"mod_ban_08", 0)["ok"], "往占用位放 ⇒ 拒绝")
	ok(PoolService.unsocket(st, bx.box_id, 0)["ok"], "显式拆卸第 0 位（该模块无成本 ⇒ 无返还）")
	ok(PoolService.socket(st, bx.box_id, &"mod_ban_08", 0)["ok"], "现在可以装另一个模块")
	var ps := PoolService.get_pool_state(st, bx.box_id)
	eq(ps.weight_of(&"s01_08"), 0, "新模块生效（s01_08 被排除）")
	ok(ps.weight_of(&"s01_05") > 2000, "旧模块的排除已被撤销：s01_05 拿回并分到摊回的质量（> 2000 bp）")
	eq(ps.void_mass_bp, 440, "此时生效的是 s01_08 的 40% 损耗（1100 × 0.4 = 440）")


func _test_broken_modules_are_reported() -> void:
	print("— 载入路径的失败必须**报错**，不得静默降级成基础池（§10.1 T24 ④）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	bx.modules[0] = Module.make(&"mod_offline", 1, 0)     # 已下线的 module_id
	PoolService.drop_cached_state(bx.box_id)
	var ps := PoolService.get_pool_state(st, bx.box_id)
	ok(ps == null, "引用未注册 module_id ⇒ 重建返回 null（不静默给基础池）")
	var errs := PoolService.validate_box(bx, _series)
	ok(_codes(errs).has("unknown_module"), "validate_box 报出 unknown_module")
	bx.modules[0] = null
	var shape := PoolService.validate_box(bx, _series)
	ok(shape.is_empty(), "修好后校验通过")
	# 定长形状（V7）：长度不等于 socket_count 必须被报出来
	var saved := bx.modules.duplicate()
	var empty_modules: Array[Module] = []
	bx.modules = empty_modules
	var errs2 := PoolService.validate_box(bx, _series)
	ok(_codes(errs2).has("modules_shape"), "抓长度 ≠ socket_count（V7 / C4 第①条）")
	bx.modules = saved
	ok(PoolService.validate_box(bx, _series).is_empty(), "恢复后校验通过")
	ok(PoolService.get_pool_state(st, bx.box_id) != null, "缓存重建后可用")

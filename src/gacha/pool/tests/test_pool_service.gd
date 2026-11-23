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
	_test_socket_gold_cost_and_permanent_lock()
	_test_gold_insufficient_consumes_nothing()
	_test_socket_works_when_warehouse_full()
	_test_occupied_slot_is_terminal()
	_test_broken_modules_are_reported()
	_test_add_pool_item()
	_test_item_state_writes()
	_test_item_state_roundtrip()

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

	# ★ v0.18 / v0.19：资源（货币类）必须先注册（V6：缺 gold 就装不了模块）
	for kind in ItemConstants.ALL_CURRENCIES:
		var cur := CurrencyDef.new()
		cur.id = kind
		cur.display_name = String(kind)
		cur.description = "夹具"
		ItemCatalog.register_currency(cur)

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
	# 有金币成本的模块（★ v0.19：模块的成本 = 金币，写在 `ModuleDef.gold_cost` 上）
	GachaCatalog.register_module(_module(&"mod_ban_costly", ModuleDef.OpType.BAN, [&"s01_05"], 1.0,
		25))
	# 互斥标记（V6）
	GachaCatalog.register_module(_module(&"mod_tag_a", ModuleDef.OpType.BAN, [&"s01_04"], 1.0, 0,
		[&"exclusive_x"]))
	GachaCatalog.register_module(_module(&"mod_tag_b", ModuleDef.OpType.BAN, [&"s01_06"], 1.0, 0,
		[&"exclusive_x"]))


func _module(
	id: StringName,
	op: int,
	targets: Array,
	magnitude: float = 1.0,
	gold_cost: int = 0,
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
	# ★ v0.19：成本 = 金币（`ModuleCost` 物品需求向量已整族删除）
	m.gold_cost = gold_cost
	for t in targets:
		m.targets.append(StringName(t))
	for t in tags:
		m.exclusive_tags.append(StringName(t))
	return m


## 新档 + 发 `n` 个盒子。
## ★ 开局给足金币（成本测试自己会把余额压到阈值两侧）。
func _new_state(n: int = 1) -> Dictionary:
	_setup()
	var st := GameState.new_game()   # v0.14：镶嵌需要设备（开局送一台基础装置）
	ItemService.grant_currency(
		ItemConstants.CURRENCY_GOLD, 1000, ItemConstants.CURRENCY_SOURCE_INIT
	)
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
	ok(IUuid.is_valid(a.box_id), "box_id 是插件产出的 id（8-4-4-12 / 31 字符，★ v0.25 起不再是 36 字符 UUIDv4）")
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
	var r := PoolBuff.apply_module(st, bx.box_id, &"mod_ban_05", 0)
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
	var r := PoolBuff.apply_module(st, bx.box_id, &"mod_boost_05", 0)
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

	var r1 := PoolBuff.apply_module(st, bx.box_id, &"mod_ban_05", 1)
	ok(r1["ok"], "先装一个排除模块（目标 s01_05）")
	var r2 := PoolBuff.apply_module(st, bx.box_id, &"mod_boost_05", 2)
	ok(not r2["ok"], "同一物品既排除又提升 ⇒ 拒绝")
	eq(r2["reason"], PoolService.R_BAN_BOOST_CONFLICT, "原因码 = ban_boost_conflict（V2）")

	var r3 := PoolBuff.apply_module(st, bx.box_id, &"mod_ban_08", 1)
	ok(not r3["ok"], "往**占用位**放 ⇒ 拒绝")
	eq(r3["reason"], PoolService.R_SLOT_OCCUPIED, "原因码 = slot_occupied（必须显式替换，不做隐式覆盖）")

	var r4 := PoolBuff.apply_module(st, bx.box_id, &"mod_boost_over", 0)
	ok(not r4["ok"], "提升倍数 3.5× ⇒ 拒绝")
	eq(r4["reason"], PoolService.R_BOOST_OVER_CAP, "原因码 = boost_over_cap（V4 / 核心 D7）")

	var r5 := PoolBuff.apply_module(st, bx.box_id, &"mod_recover", 0)
	ok(not r5["ok"], "RECOVER 模块 ⇒ 拒绝（第二切片，本版仅定义接口）")
	eq(r5["reason"], PoolService.R_RECOVER_UNSUPPORTED, "原因码 = recover_unsupported")

	var r6 := PoolBuff.apply_module(st, bx.box_id, &"mod_ban_many", 0)
	ok(not r6["ok"], "一次排除 6 件 ⇒ 拒绝")
	eq(r6["reason"], PoolService.R_BAN_LIMIT, "原因码 = ban_limit_exceeded（V5：ban_limit = 8 − 3 = 5）")

	var r7 := PoolBuff.apply_module(st, bx.box_id, &"no_such_module", 0)
	ok(not r7["ok"], "未注册的 module_id ⇒ 拒绝")
	eq(r7["reason"], PoolService.R_UNKNOWN_MODULE, "原因码 = unknown_module（V7：非空项良构）")

	var r8 := PoolBuff.apply_module(st, bx.box_id, &"mod_ban_05", 9)
	ok(not r8["ok"], "slot 越界 ⇒ 拒绝")
	eq(r8["reason"], PoolService.R_BAD_SLOT, "原因码 = bad_slot")

	var r9 := PoolBuff.apply_module(st, bx.box_id, &"mod_tag_a", 0)
	ok(r9["ok"], "装一个带互斥标记的模块")
	var r10 := PoolBuff.apply_module(st, bx.box_id, &"mod_tag_b", 2)
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
	ok(PoolBuff.apply_module(st, a.box_id, &"mod_ban_05", 0)["ok"], "编辑盒子 A")
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


func _test_socket_gold_cost_and_permanent_lock() -> void:
	print("— ★ v0.44：镶嵌的成本 = 该模块的金币；**模块镶上即永久锁定**（拆卸已删除）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var gold_before := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var inst_before := ItemService.instances.size()

	var r := PoolBuff.apply_module(st, bx.box_id, &"mod_ban_costly", 0)
	ok(r["ok"], "镶嵌成功（成本在同一次 02 事务里扣掉）")
	eq(
		ItemService.currency_balance(ItemConstants.CURRENCY_GOLD),
		gold_before - 25,
		"**金币恰好减少该模块的 `gold_cost`（25）**"
	)
	eq(ItemService.instances.size(), inst_before, "**一件物品都没有被消耗**（模块不再吃物品）")
	var ps_socketed: PoolState = r["state"]
	eq(ps_socketed.void_mass_bp, 800, "已生效：void 800")

	# ★ v0.44：再往同一个位子镶 ⇒ 终局拒绝；没有任何"取下"的路径
	var rev := bx.item_pool.revision
	var gold_mid := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var again := PoolBuff.apply_module(st, bx.box_id, &"mod_ban_08", 0)
	ok(not again["ok"], "**往已占用位再镶 ⇒ 拒绝**（没有替换）")
	eq(again["reason"], PoolService.R_SLOT_OCCUPIED, "原因码 = slot_occupied（终局：不是「请先拆」）")
	eq(bx.item_pool.revision, rev, "revision 未推进")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), gold_mid, "金币未扣")
	eq(bx.modules[0].module_id, &"mod_ban_costly", "原位子的模块原封不动（永久锁定）")
	eq(bx.occupied_count(), 1, "占用数不变")
	eq(bx.modules.size(), 3, "**定长长度不变**")
	ok(PoolService.get_pool_state(st, bx.box_id).is_zero_sum(), "Σ == 10000（状态仍自洽）")


func _test_gold_insufficient_consumes_nothing() -> void:
	print("— 金币不足 ⇒ **整体拒绝**，且什么都不改（§5.3 / 核心 §16.14）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	# 把余额压到"差 1 点"：模块价 25
	ItemService.currencies.clear()
	ItemService.grant_currency(
		ItemConstants.CURRENCY_GOLD, 24, ItemConstants.CURRENCY_SOURCE_INIT
	)
	var inst_before := ItemService.instances.size()
	var r := PoolBuff.apply_module(st, bx.box_id, &"mod_ban_costly", 0)
	ok(not r["ok"], "余额 24 < 25 ⇒ 拒绝")
	eq(r["reason"], PoolService.R_CURRENCY_INSUFFICIENT, "原因码 = currency_insufficient")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), 24, "**一分钱都没扣**")
	eq(ItemService.instances.size(), inst_before, "实例列表逐项不变")
	eq(bx.occupied_count(), 0, "modules 没被写入")
	eq(bx.item_pool.revision, 0, "revision 没被推进")


func _test_socket_works_when_warehouse_full() -> void:
	print("— 仓库满时**镶嵌照样成功**（它只花钱、不产出 ⇒ 没有『放不下』这回事）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	ItemService.warehouse_capacity = 11
	ok(PoolBuff.apply_module(st, bx.box_id, &"mod_ban_costly", 0)["ok"], "先镶嵌（金币扣款）")
	for _i in 5:
		ItemService.grant(&"s01_02", {"kind": ItemConstants.KIND_UNLOCK})
	eq(ItemService.warehouse_usage()["used"], 11, "仓库恰好占满（5 件 × size 2 + 盲盒 1 单位）")
	var inst_before := ItemService.instances.size()
	var gold_before := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)

	# 换一个空位继续镶（`mod_ban_08` 无金币成本 ⇒ 金额断言只看"不扣多于应扣"，见下）
	var r2 := PoolBuff.apply_module(st, bx.box_id, &"mod_ban_08", 1)
	ok(r2["ok"], "**仓库满也能镶嵌**（镶嵌不产出任何实例 ⇒ 没有空间问题）")
	eq(bx.occupied_count(), 2, "第 2 位也装上了")
	eq(ItemService.instances.size(), inst_before, "实例列表逐项不变（不产出、不返还）")
	eq(ItemService.warehouse_usage()["used"], 11, "占用不变")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), gold_before,
		"该模块 `gold_cost = 0` ⇒ 余额不变（成本精确来自模块字段）")
	eq(bx.item_pool.revision, 2, "revision = 2（两次镶嵌各 +1）")


func _test_occupied_slot_is_terminal() -> void:
	print("— ★ v0.44：占用位终局化——不能覆盖、不能取下，别的空位仍可镶")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	ok(PoolBuff.apply_module(st, bx.box_id, &"mod_ban_05", 0)["ok"], "第 0 位装上排除模块")
	var rev := bx.item_pool.revision
	ok(not PoolBuff.apply_module(st, bx.box_id, &"mod_ban_08", 0)["ok"], "往占用位放 ⇒ 拒绝")
	eq(bx.item_pool.revision, rev, "被拒时 revision 不推进")
	ok(PoolBuff.apply_module(st, bx.box_id, &"mod_ban_08", 1)["ok"], "换到第 1 位（空位）⇒ 成功")
	var ps := PoolService.get_pool_state(st, bx.box_id)
	eq(ps.weight_of(&"s01_08"), 0, "新模块生效（s01_08 被排除）")
	eq(ps.weight_of(&"s01_05"), 0, "旧模块也仍然生效（它取不下来）")
	ok(ps.is_zero_sum(), "Σ == 10000（两个排除叠加后仍自洽）")


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


# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.45：池子成员与物品三态（可编辑字段，不走模块）
# ══════════════════════════════════════════════════════════════════════════════

func _test_add_pool_item() -> void:
	print("— ★ v0.45 添加物品：真进池子、真改分布、revision +1、发信号")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var size0 := bx.item_pool.base_items.size()
	var rev0 := bx.item_pool.revision

	# 造一件"已注册但不在池里"的物品（池子只含 s01_XX）
	var extra := ItemDef.new()
	extra.item_id = &"extra_q1"
	extra.display_name = "池外物品"
	extra.category = &"stardust"
	extra.quality = 1
	extra.value = 1
	extra.size = Vector2i(1, 1)
	extra.rarity = 50
	ItemCatalog.register(extra)

	var hits: Array = []
	var cb := func(bid: String, rev: int) -> void: hits.append([bid, rev])
	PoolService.bus.pool_changed.connect(cb)

	var r := PoolBuff.add_item(st, bx.box_id, &"extra_q1")
	PoolService.bus.pool_changed.disconnect(cb)

	ok(r["ok"], "加入成功")
	eq(bx.item_pool.base_items.size(), size0 + 1, "池子 +1 件")
	eq(bx.item_pool.regular_count, size0 + 1, "regular_count 同步（C6 / V5 口径跟着池子走）")
	eq(bx.item_pool.extra_item_ids, [&"extra_q1"] as Array[StringName], "记进 extra_item_ids（要落盘）")
	eq(bx.item_pool.revision, rev0 + 1, "revision +1（07 的缓存键失效）")
	eq(hits.size(), 1, "发出 1 次 pool_changed")
	if hits.size() == 1:
		eq(hits[0][0], bx.box_id, "信号带对的 box_id")
		eq(hits[0][1], rev0 + 1, "信号带新的 revision")
	var ps := PoolService.get_pool_state(st, bx.box_id)
	ok(ps.weight_of(&"extra_q1") > 0, "新物品真的进了分布（权重 > 0）")
	ok(ps.is_zero_sum(), "Σ == 10000（C1）")

	# 拒绝路径
	eq(PoolBuff.add_item(st, bx.box_id, &"extra_q1")["reason"],
		PoolService.R_ITEM_ALREADY_IN_POOL, "重复添加 ⇒ item_already_in_pool")
	eq(PoolBuff.add_item(st, bx.box_id, &"nope")["reason"],
		PoolService.R_UNKNOWN_ITEM, "未注册物品 ⇒ unknown_item")


func _test_item_state_writes() -> void:
	print("— ★ v0.48 状态机：添加→显示、隐藏→(揭示)→显示、显示→(禁用)→禁用；禁用终局")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]
	var ids := bx.item_pool.item_ids()
	var first: StringName = ids[0]

	var before := PoolService.get_pool_state(st, bx.box_id).weights_bp.duplicate()

	# ① 隐藏是"物品的基础状态"（由内容/读档决定），玩家没有把显示压成隐藏的动作。
	#    这里用数据层直接构造一个隐藏项，再用 buff 的 reveal 揭示它。
	ok(bx.item_pool.set_state(first, ItemPool.ItemState.HIDDEN), "夹具：把第 1 件置为隐藏")
	bx.item_pool.revision += 1          # 绕过 buff 的夹具改动要自己推进 revision，否则读到缓存
	var ps_hidden := PoolService.get_pool_state(st, bx.box_id)
	eq(ps_hidden.weights_bp, before, "**隐藏不改变任何权重**（仍参与抽取）")
	eq(ps_hidden.hidden_ids.has(first), true, "PoolState 报出该隐藏项")

	# ② 隐藏的物品**不能直接禁用**（必须先揭示）
	var bad := PoolBuff.disable(st, bx.box_id, first)
	ok(not bad["ok"], "禁用一件隐藏物品 ⇒ 拒绝")
	eq(bad["reason"], PoolService.R_NOT_REVEALED, "原因码 = not_revealed")
	eq(bx.item_pool.state_of(first), ItemPool.ItemState.HIDDEN, "状态没变")

	# ③ 揭示：隐藏 → 显示
	var rev0 := bx.item_pool.revision
	var rev_h := PoolBuff.reveal(st, bx.box_id, first)
	ok(rev_h["ok"], "揭示成功")
	eq(bx.item_pool.state_of(first), ItemPool.ItemState.SHOWN, "变成显示")
	eq(bx.item_pool.revision, rev0 + 1, "revision +1")
	eq(PoolService.get_pool_state(st, bx.box_id).weights_bp, before, "揭示也不改分布")

	# ④ 禁用：显示 → 禁用，退出分布、其余重新归一
	var r2 := PoolBuff.disable(st, bx.box_id, first)
	ok(r2["ok"], "禁用成功")
	var ps2 := PoolService.get_pool_state(st, bx.box_id)
	eq(ps2.weights_bp.has(first), false, "**禁用项不在 weights_bp 里**（出候选集，不是 0 权重）")
	eq(ps2.weight_of(first), 0, "查询它的权重为 0")
	ok(ps2.is_zero_sum(), "Σ == 10000（其余物品重新归一）")
	eq(ps2.disabled_ids.has(first), true, "PoolState 报出该禁用项")
	eq(ps2.banned_ids().has(first), false, "**禁用不被误报成「被 BAN」**")

	# ⑤ 禁用是**终局**：揭示 / 再禁用都拒绝，状态不变
	var rev_term := bx.item_pool.revision
	eq(PoolBuff.reveal(st, bx.box_id, first)["reason"], PoolService.R_STATE_TERMINAL,
		"禁用后不能揭示 ⇒ state_terminal")
	eq(PoolBuff.disable(st, bx.box_id, first)["ok"], true, "再禁用 ⇒ 幂等成功（已是该状态）")
	eq(bx.item_pool.revision, rev_term, "幂等不推进 revision")
	eq(bx.item_pool.state_of(first), ItemPool.ItemState.DISABLED, "状态仍是禁用")

	# ⑥ 没有"显示 → 隐藏"这个公开动作：buff 上不存在能直接设隐藏的入口
	ok(not _has_buff_method("set_state"), "buff 不再暴露万能 set_state")
	#    内部写入确实拦住了降级（打开闸门直接调，验证护栏本身）
	PoolService._open_write_gate()
	var down := PoolService._write_set_state(st, bx.box_id, ids[1], ItemPool.ItemState.HIDDEN)
	PoolService._close_write_gate()
	eq(down["reason"], PoolService.R_NO_DOWNGRADE, "显示 → 隐藏 ⇒ no_downgrade（护栏在位）")

	# ⑦ C6 下限：把可产出压到 3 之后，再禁用一件 ⇒ 拒绝且状态不变
	while bx.item_pool.enabled_count() > 3:
		var target := &""
		for id in bx.item_pool.item_ids():
			if bx.item_pool.state_of(id) == ItemPool.ItemState.SHOWN:
				target = id
				break
		if target == &"":
			break
		ok(PoolBuff.disable(st, bx.box_id, target)["ok"],
			"禁用一件（可产出 → %d）" % (bx.item_pool.enabled_count() - 1))
	eq(bx.item_pool.enabled_count(), 3, "前置：可产出压到 3")
	var last_id := &""
	for id in bx.item_pool.item_ids():
		if bx.item_pool.state_of(id) == ItemPool.ItemState.SHOWN:
			last_id = id
			break
	var rev_before := bx.item_pool.revision
	var r3 := PoolBuff.disable(st, bx.box_id, last_id)
	ok(not r3["ok"], "再禁用一件 ⇒ 拒绝（C6 ≥ 3）")
	eq(r3["reason"], PoolService.R_BELOW_C6, "原因码 = below_c6_floor")
	eq(bx.item_pool.revision, rev_before, "被拒时 revision 不动")
	eq(bx.item_pool.enabled_count(), 3, "可产出仍是 3")

	# ⑧ 其它拒绝路径
	eq(PoolBuff.disable(st, bx.box_id, &"nope")["reason"],
		PoolService.R_ITEM_NOT_IN_POOL, "不在池中 ⇒ item_not_in_pool")


## buff 脚本里是否还有某个静态方法（用于"旧接口已删除"的断言）。
func _has_buff_method(method_name: String) -> bool:
	var scr := load("res://src/gacha/pool/pool_buff.gd") as Script
	if scr == null:
		return false
	for m in scr.get_script_method_list():
		if String(m.get("name", "")) == method_name:
			return true
	return false


func _test_item_state_roundtrip() -> void:
	print("— ★ v0.45 落盘：追加物品与三态随盒子往返（读档不丢编辑）")
	var f := _new_state(1)
	var st: GameState = f["state"]
	var bx: Box = f["boxes"][0]

	var extra := ItemDef.new()
	extra.item_id = &"extra_q2"
	extra.display_name = "池外物品 2"
	extra.category = &"stardust"
	extra.quality = 2
	extra.value = 3
	extra.size = Vector2i(1, 1)
	extra.rarity = 40
	ItemCatalog.register(extra)

	ok(PoolBuff.add_item(st, bx.box_id, &"extra_q2")["ok"], "先加一件（落为显示）")
	eq(bx.item_pool.state_of(&"extra_q2"), ItemPool.ItemState.SHOWN, "新物品是显示（v0.48）")
	ok(PoolBuff.disable(st, bx.box_id, &"extra_q2")["ok"], "再把它禁用")
	# 隐藏态只能由数据层构造（玩家没有这个动作）——落盘仍要能往返
	var first: StringName = bx.item_pool.item_ids()[0]
	ok(bx.item_pool.set_state(first, ItemPool.ItemState.HIDDEN), "夹具：第一件置为隐藏")

	var d := bx.to_dict()
	var back := Box.from_dict(d, 0)
	ok(back != null, "能读回来")
	eq(back.item_pool.extra_item_ids, [&"extra_q2"] as Array[StringName], "追加物品读回来了")
	eq(back.item_pool.state_of(&"extra_q2"), ItemPool.ItemState.DISABLED, "禁用状态读回来了")
	eq(back.item_pool.state_of(first), ItemPool.ItemState.HIDDEN, "隐藏状态读回来了")
	eq(back.item_pool.base_items.size(), bx.item_pool.base_items.size(), "池子件数一致")
	eq(back.to_dict(), d, "往返后 to_dict 逐项一致（字节级稳定）")

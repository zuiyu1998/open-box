## 设备系统测试（04-device.md §10 的 T9 / T11 / T13 / T14 / T15 / T16）。
##
## 无头运行：
##   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
## 或直接：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . res://src/devices/tests/test_device_service.tscn
##
## 退出码 0 = 全绿，1 = 有失败。
extends Node

## 夹具套系：品质 2 ⇒ 8 物品 / 3 位 / 寿命 15；开盒基准价 = `GEM_BASE`
const N := 8
const GEM_BASE := 30
const MOD_GOLD := 20        # 夹具模块的金币价
const UPGRADE_L2 := 40      # 夹具曲线：升到 2 级的价格

var _pass := 0
var _fail := 0
var _defs: Array[ItemDef] = []
var _series: SeriesDef


func _ready() -> void:
	print("=== 设备系统测试（04-device.md §10）===\n")

	_test_content_and_catalog()
	_test_no_device_gate()
	_test_open_cost_formula()
	_test_redeem_atomicity_and_insufficient()
	_test_batch_precheck()
	_test_upgrade()
	_test_level_gate_only_for_opening()
	_test_socket_gold_and_replace()
	_test_starting_state_has_no_deadlock()

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

## 8 件物品 / 1 个品质 2 的套系 / 1 个金币价 20 的模块 / 一台 3 级的装置。
func _setup() -> void:
	ItemCatalog.clear()
	GachaCatalog.clear()
	DeviceCatalog.clear()
	ItemService.reset()
	ItemService.warehouse_capacity = 1000
	PoolService.drop_all_cached_states()
	EvalService.is_collected_provider = Callable()

	# 资源（切片两种：原石 / 金币）
	for kind in ItemConstants.ALL_CURRENCIES:
		var c := CurrencyDef.new()
		c.id = kind
		c.display_name = String(kind)
		c.description = "夹具"
		ItemCatalog.register_currency(c)

	_defs = []
	var cats: Array[StringName] = [&"stardust", &"stardust", &"stardust", &"stardust",
		&"stardust", &"crystal", &"crystal", &"crystal"]
	var quals: Array[int] = [1, 2, 3, 4, 5, 1, 2, 3]
	for i in N:
		var d := ItemDef.new()
		d.item_id = StringName("s01_%02d" % (i + 1))
		d.display_name = "物品 %d" % (i + 1)
		d.category = cats[i]
		d.quality = quals[i]
		d.value = 1 + quals[i]
		d.size = 2
		d.rarity = 10
		ItemCatalog.register(d)
		_defs.append(d)

	_series = SeriesDef.new()
	_series.series_id = &"series_01"
	_series.series_quality = 2
	_series.regular_count = N
	_series.socket_count = 3
	_series.uses_per_box = SeriesDef.expected_initial_uses(2)
	_series.gem_cost = GEM_BASE
	_series.regular_items = _defs.duplicate()
	GachaCatalog.register_series(_series)

	var m := ModuleDef.new()
	m.id = &"mod_ban_sd5"
	m.display_name = "排除 5 号"
	m.quality = 2
	m.op_type = ModuleDef.OpType.BAN
	m.targets.append(&"s01_05")
	m.gold_cost = MOD_GOLD
	GachaCatalog.register_module(m)

	DeviceCatalog.register(_device_def())


## 一台 3 级的装置：等级 1 能开品质 ≤2、原价；等级 2 能开 ≤3、6 折；等级 3 能开 ≤4、2 折。
func _device_def() -> DeviceDef:
	var def := DeviceDef.new()
	def.id = &"dev_test"
	def.display_name = "测试装置"
	def.description = "夹具"
	var rows := [[1, 2, 10000, 0], [2, 3, 6000, UPGRADE_L2], [3, 4, 2000, 120]]
	var levels: Array[DeviceLevelSpec] = []
	for r in rows:
		var spec := DeviceLevelSpec.new()
		spec.level = int(r[0])
		spec.unlock_series_quality_max = int(r[1])
		spec.open_cost_bp = int(r[2])
		spec.upgrade_cost_gems = int(r[3])
		levels.append(spec)
	def.levels = levels
	return def


## 新档（开局一台装置 + INIT_GEM / INIT_GOLD）+ 1 个盒子。
func _new_state(gems: int = -1, gold: int = -1, lv: int = 1) -> Dictionary:
	_setup()
	var st := GameState.new()
	st.grant_device(&"dev_test", lv)
	ItemService.grant_currency(
		ItemConstants.CURRENCY_GEM,
		ItemConstants.INIT_GEM if gems < 0 else gems,
		ItemConstants.CURRENCY_SOURCE_INIT
	)
	ItemService.grant_currency(
		ItemConstants.CURRENCY_GOLD,
		ItemConstants.INIT_GOLD if gold < 0 else gold,
		ItemConstants.CURRENCY_SOURCE_INIT
	)
	var boxes := GachaService.grant_box(st, &"series_01", 1, &"test")
	return {"state": st, "box": boxes[0]}


# ══════════════════════════════════════════════════════════════════════════════
#  测试
# ══════════════════════════════════════════════════════════════════════════════

func _test_content_and_catalog() -> void:
	print("— 内容与注册表：开局那台是纯配置（`.tres`），等级曲线可校验（§1.1 / §4）")
	DeviceCatalog.clear()
	DeviceCatalog.ensure_default_content()
	var start := DeviceCatalog.get_device(DeviceConstants.STARTING_DEVICE_ID)
	ok(start != null, "开局装置已注册（缺它 ⇒ 永远是 0 台）")
	if start != null:
		eq(start.levels.size(), 3, "内容配置载入成功：3 档等级（`.tres` 有效）")
		eq(start.unlock_series_quality_max(1), 2, "等级 1 能开品质 ≤ 2 的套系（切片不死锁）")
		eq(start.upgrade_cost_to_next(1), 40, "升到 2 级的价格 = 40 原石")
		eq(start.upgrade_cost_to_next(3), -1, "满级 ⇒ 无下一级（-1）")
		ok(start.validate().is_empty(), "内容定义本身通过校验")
	ok(DeviceCatalog.validate()["ok"], "注册表校验通过")

	# 负测试：等级空洞 / 升级把准入变小 ⇒ 必须报出来
	var broken := _device_def()
	broken.levels[1].level = 5
	var probs := broken.validate()
	ok(not probs.is_empty(), "等级不连续 ⇒ 校验报错（不得静默当连续）")
	var shrink := _device_def()
	shrink.levels[2].unlock_series_quality_max = 1
	ok(not shrink.validate().is_empty(), "升级把准入变小 ⇒ 校验报错（升级不许变成惩罚）")
	DeviceCatalog.clear()
	DeviceCatalog.register(_device_def())


func _test_no_device_gate() -> void:
	print("— T9：没有设备 ⇒ 三个入口都拒绝，且**不消耗任何东西**（§5.7）")
	var f := _new_state()
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	st.devices.clear()
	var gems := ItemService.currency_balance(ItemConstants.CURRENCY_GEM)
	var gold := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var uses := bx.uses_remaining
	var insts := ItemService.instances.size()

	eq(DeviceService.redeem(st, bx, 1).error, DeviceService.R_NO_DEVICE, "开盒 ⇒ no_device")
	eq(DeviceService.socket(st, bx.box_id, &"mod_ban_sd5", 0)["reason"], DeviceService.R_NO_DEVICE,
		"镶嵌 ⇒ no_device")
	eq(DeviceService.upgrade_device(st, &"dev_test")["reason"], DeviceService.R_NO_DEVICE,
		"升级 ⇒ no_device")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GEM), gems, "原石一分未扣")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), gold, "金币一分未扣")
	eq(bx.uses_remaining, uses, "寿命一次未扣")
	eq(ItemService.instances.size(), insts, "实例列表逐项不变")
	eq(bx.occupied_count(), 0, "modules 没被写入")
	ok(not DeviceService.has_device(st), "has_device() 为 false")

	# 拆卸不受门槛约束（01 侧入口，核心 §4.4 裁定⑪）
	var u := PoolService.unsocket(st, bx.box_id, 0)
	eq(u["reason"], PoolService.R_SLOT_EMPTY, "拆卸不看设备（报的是 slot_empty，不是 no_device）")


func _test_open_cost_formula() -> void:
	print("— T13 ①：`floori(gem_cost × bp / 10000)`；折扣随等级下降（§5.2）")
	var f := _new_state(-1, -1, 1)
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	eq(DeviceService.open_cost(st, bx), GEM_BASE, "等级 1（bp 10000）⇒ 30")
	var d := DeviceService.find_device(st, &"dev_test")
	d.level = 2
	eq(DeviceService.open_cost(st, bx), 18, "等级 2（bp 6000）⇒ floori(18.0) = 18")
	d.level = 3
	eq(DeviceService.open_cost(st, bx), 6, "等级 3（bp 2000）⇒ 6")
	d.level = 2
	# 取整一律向下：30 × 3333 / 10000 = 9.999 ⇒ 9
	var def := DeviceCatalog.get_device(&"dev_test")
	def.levels[1].open_cost_bp = 3333
	eq(DeviceService.open_cost(st, bx), 9, "取整一律 floori（9.999 ⇒ 9）")
	def.levels[1].open_cost_bp = 6000
	# 无设备 / 等级不足 ⇒ -1（**不得**当成 0 用）
	st.devices.clear()
	eq(DeviceService.open_cost(st, bx), -1, "无设备 ⇒ 计价返回 -1（不是 0）")


func _test_redeem_atomicity_and_insufficient() -> void:
	print("— T13 ②③：一次事务（扣原石 + 产实例）；不足 ⇒ 链首拒绝（§5.1 / §5.2）")
	var f := _new_state(GEM_BASE)
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GEM), GEM_BASE, "原石 = 恰好一次开盒的量")
	var insts := ItemService.instances.size()
	var r := DeviceService.redeem(st, bx, 7)
	ok(r.ok, "开盒成功")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GEM), 0, "**原石恰好减少 `gem_cost`**")
	if not r.is_void:
		eq(ItemService.instances.size(), insts + 1, "非 void ⇒ 恰好一个新实例")
	eq(bx.uses_remaining, SeriesDef.expected_initial_uses(2) - 1, "寿命恰好 −1")
	ok(ItemService.check_conservation(), "守恒等式仍成立")

	# 不足：余额 = cost − 1 ⇒ 链首拒绝，什么都不动
	var f2 := _new_state(GEM_BASE - 1)
	var st2: GameState = f2["state"]
	var bx2: Box = f2["box"]
	var uses2 := bx2.uses_remaining
	var di2 := st2.draw_index
	var r2 := DeviceService.redeem(st2, bx2, 3)
	eq(r2.error, DeviceService.R_CURRENCY_INSUFFICIENT, "余额差 1 ⇒ currency_insufficient")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GEM), GEM_BASE - 1, "原石一分未扣")
	eq(bx2.uses_remaining, uses2, "寿命未扣")
	eq(st2.draw_index, di2, "`draw_index` 未推进")
	eq(ItemService.instances.size(), 0, "没有实例产出")


func _test_batch_precheck() -> void:
	print("— T13 ④：整批预检按**整批总成本**判定（§5.1 / §5.8）")
	var f := _new_state(GEM_BASE * 2 - 1)
	var st: GameState = f["state"]
	var boxes := GachaService.grant_box(st, &"series_01", 2, &"test")
	var gems_before := ItemService.currency_balance(ItemConstants.CURRENCY_GEM)
	var uses_before := boxes[0].uses_remaining + boxes[1].uses_remaining
	var res := DeviceService.redeem_batch(st, boxes, 2, [1, 2])
	eq(res.size(), 2, "返回 k 条结果（对账不变式）")
	eq(res[0].error, DeviceService.R_CURRENCY_INSUFFICIENT, "整批拒绝（差 1 点也不放行）")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GEM), gems_before, "原石未扣")
	eq(boxes[0].uses_remaining + boxes[1].uses_remaining, uses_before, "寿命一次未扣")

	# 够 ⇒ 全部成功
	var f2 := _new_state(GEM_BASE * 2)
	var st2: GameState = f2["state"]
	var boxes2 := GachaService.grant_box(st2, &"series_01", 2, &"test")
	var res2 := DeviceService.redeem_batch(st2, boxes2, 2, [1, 2])
	eq(res2.size(), 2, "k = 2")
	ok(res2[0].ok and res2[1].ok, "整批成功")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GEM), 0, "总成本恰好吃掉余额")


func _test_upgrade() -> void:
	print("— T14：升级花原石、等级 +1、立刻生效、不消耗本体、不碰功率面（§5.4）")
	var f := _new_state(UPGRADE_L2 + 100, -1, 1)
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	var gems := ItemService.currency_balance(ItemConstants.CURRENCY_GEM)
	var count := st.devices.size()
	var id := st.devices[0].device_id

	var up := DeviceService.upgrade_device(st, &"dev_test")
	ok(up["ok"], "升级成功")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GEM), gems - UPGRADE_L2,
		"**原石恰好减少升级价（40）**")
	eq(st.devices[0].level, 2, "等级 +1")
	eq(st.devices.size(), count, "**不消耗本体**：持有台数不变")
	eq(st.devices[0].device_id, id, "设备 id 不变（升级不是换一台）")
	eq(DeviceService.open_cost(st, bx), 18, "**立刻生效**：开盒成本降到 18")
	eq(bx.item_pool.socket_count, 3, "**功率面不动**：镶嵌位数仍是 3")
	eq(bx.uses_remaining, SeriesDef.expected_initial_uses(2), "寿命预算口径不动")
	eq(ItemService.instances.size(), 0, "升级不产生任何实例")

	# 原石不足
	var f2 := _new_state(UPGRADE_L2 - 1, -1, 1)
	var st2: GameState = f2["state"]
	eq(DeviceService.upgrade_device(st2, &"dev_test")["reason"],
		DeviceService.R_CURRENCY_INSUFFICIENT, "原石不足 ⇒ currency_insufficient")
	eq(st2.devices[0].level, 1, "失败时等级不变")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GEM), UPGRADE_L2 - 1, "失败时原石不变")

	# 满级
	var f3 := _new_state(1000, -1, 3)
	var st3: GameState = f3["state"]
	eq(DeviceService.upgrade_device(st3, &"dev_test")["reason"], DeviceService.R_DEVICE_MAX_LEVEL,
		"满级 ⇒ device_max_level")

	# 未注册 / 不存在的设备
	var f4 := _new_state(1000)
	var st4: GameState = f4["state"]
	eq(DeviceService.upgrade_device(st4, &"dev_nope")["reason"], DeviceService.R_UNKNOWN_DEVICE,
		"不持有的设备 ⇒ unknown_device")


func _test_level_gate_only_for_opening() -> void:
	print("— T15：等级门控（准入轴）只作用于开盒；镶嵌不受影响（§5.6 / §5.8）")
	var f := _new_state(1000, 1000, 1)
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	ok(DeviceService.can_open(st, bx), "品质 2 的套系 vs 等级 1（上限 2）⇒ 可开")
	# 换一个品质 3 的套系（夹具里临时加一个）
	var s3 := SeriesDef.new()
	s3.series_id = &"series_q3"
	s3.series_quality = 3
	s3.regular_count = 12
	s3.socket_count = 4
	s3.uses_per_box = SeriesDef.expected_initial_uses(3)
	s3.gem_cost = GEM_BASE
	var defs3: Array[ItemDef] = _defs.duplicate()
	for i in 4:
		var d := ItemDef.new()
		d.item_id = StringName("s03_%02d" % (i + 1))
		d.display_name = "补充 %d" % i
		d.category = &"crystal"
		d.quality = 1 + (i % 3)
		d.value = 2
		d.size = 2
		d.rarity = 10
		ItemCatalog.register(d)
		defs3.append(d)
	s3.regular_items = defs3
	GachaCatalog.register_series(s3)
	var bx3: Box = GachaService.grant_box(st, &"series_q3", 1, &"test")[0]

	ok(not DeviceService.can_open(st, bx3), "品质 3 的套系 vs 等级 1 ⇒ 不可开")
	eq(DeviceService.redeem(st, bx3, 1).error, DeviceService.R_DEVICE_LEVEL_LOW,
		"开盒 ⇒ device_level_low")
	var gems := ItemService.currency_balance(ItemConstants.CURRENCY_GEM)
	eq(gems, 1000, "被拒绝的开盒不扣原石")
	# **镶嵌不看等级**：等级 1 也能镶嵌品质 3 盒子上的模块
	eq(st.devices[0].level, 1, "仍是等级 1")
	ok(DeviceService.socket(st, bx3.box_id, &"mod_ban_sd5", 0)["ok"], "**镶嵌不受等级门控**（只作用于开盒）")
	# 升级到 2 级 ⇒ 立刻能开品质 3
	ok(DeviceService.upgrade_device(st, &"dev_test")["ok"], "升级到 2 级")
	ok(DeviceService.can_open(st, bx3), "等级 2（上限 3）⇒ 品质 3 可开")


func _test_socket_gold_and_replace() -> void:
	print("— T16：镶嵌的金币成本来自模块字段；替换再付一次；拆卸零返还（§5.3）")
	var f := _new_state(1000, MOD_GOLD * 2, 1)
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	var gold := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var insts := ItemService.instances.size()

	ok(DeviceService.socket(st, bx.box_id, &"mod_ban_sd5", 0)["ok"], "镶嵌成功")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), gold - MOD_GOLD,
		"**金币恰好减少模块的 `gold_cost`（20）**")
	eq(ItemService.instances.size(), insts, "**不消耗任何物品**")

	# 替换 = 拆 + 装 ⇒ 再付一次，且旧模块什么都不返还
	var before := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	ok(DeviceService.replace(st, bx.box_id, &"mod_ban_sd5", 0)["ok"], "替换成功")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), before - MOD_GOLD,
		"替换**再付一次**新模块的金币（旧模块不返还）")
	eq(
		bx.uses_remaining,
		SeriesDef.expected_initial_uses(2) - 2,
		"两次镶嵌共扣 2 次寿命（原装 1 + 新装 1；拆卸不退还那一次）"
	)

	# 金币不足 ⇒ 链首拒绝
	var f2 := _new_state(1000, MOD_GOLD - 1, 1)
	var st2: GameState = f2["state"]
	var bx2: Box = f2["box"]
	eq(DeviceService.socket(st2, bx2.box_id, &"mod_ban_sd5", 0)["reason"],
		DeviceService.R_CURRENCY_INSUFFICIENT, "金币差 1 ⇒ currency_insufficient")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), MOD_GOLD - 1, "金币未扣")
	eq(bx2.occupied_count(), 0, "modules 未写入")
	eq(bx2.uses_remaining, SeriesDef.expected_initial_uses(2), "寿命未扣")

	# 拆卸零返还 + 仓库满也成功
	var full := _new_state(1000, MOD_GOLD, 1)
	var st3: GameState = full["state"]
	var bx3: Box = full["box"]
	ItemService.warehouse_capacity = 5
	ok(DeviceService.socket(st3, bx3.box_id, &"mod_ban_sd5", 0)["ok"], "先镶嵌")
	for _i in 2:
		ItemService.grant(&"s01_01", {"kind": ItemConstants.KIND_UNLOCK})
	eq(ItemService.warehouse_usage()["used"], 5, "仓库占满（2 件 × size 2 + 盲盒 1 单位）")
	var gold3 := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var n3 := ItemService.instances.size()
	ok(PoolService.unsocket(st3, bx3.box_id, 0)["ok"], "**仓库满也能拆卸**（零返还 ⇒ 无空间问题）")
	eq(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), gold3, "拆卸不返还金币")
	eq(ItemService.instances.size(), n3, "拆卸不产生实例")


func _test_starting_state_has_no_deadlock() -> void:
	print("— T13 ③ / T15 ③：开局（装置 + 原石 + 金币）⇒ 开第一个盒子、装第一个模块都不会被闸门挡住")
	_setup()                       # ★ v0.26：先清账（盲盒占位会跨用例累积，不重置会串账）
	ItemService.warehouse_capacity = 1000
	var st := GameState.new_game()
	ok(st.has_device(), "开局有一台装置")
	ok(DeviceService.has_device(st), "DeviceService.has_device() = true")
	var boxes := GachaService.grant_box(st, &"series_01", 1, &"test")
	var bx: Box = boxes[0]
	ok(DeviceService.can_open(st, bx), "开局那台（等级 1）能开切片品质 2 的套系")
	var cost := DeviceService.open_cost(st, bx)
	ok(
		ItemService.currency_balance(ItemConstants.CURRENCY_GEM) >= cost,
		"**开局原石 ≥ 第一个盒子的开盒成本**（%d ≥ %d）"
		% [ItemService.currency_balance(ItemConstants.CURRENCY_GEM), cost]
	)
	var module := ModuleDef.new()
	module.id = &"mod_start_probe"
	module.display_name = "探针"
	module.quality = 1
	module.op_type = ModuleDef.OpType.BAN
	module.targets.append(&"s01_05")
	module.gold_cost = MOD_GOLD
	GachaCatalog.register_module(module)
	ok(
		ItemService.currency_balance(ItemConstants.CURRENCY_GOLD) >= MOD_GOLD,
		"**开局金币 ≥ 装第一个模块所需**（%d ≥ %d）"
		% [ItemService.currency_balance(ItemConstants.CURRENCY_GOLD), MOD_GOLD]
	)
	ok(DeviceService.socket(st, bx.box_id, &"mod_start_probe", 0)["ok"], "开局就能装第一个模块")
	ok(DeviceService.redeem(st, bx, 11).ok, "开局就能开盒（经设备入口）")

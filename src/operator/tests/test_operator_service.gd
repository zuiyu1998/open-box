## 干员系统测试（15-operator.md §6 的测试点）。
##
## 无头运行：
##   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
## 或直接：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . res://src/operator/tests/test_operator_service.tscn
##
## 退出码 0 = 全绿，1 = 有失败。
extends Node

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== 干员系统测试（15-operator.md §6）===\n")

	_test_level_and_upgrade()
	_test_route_mutually_exclusive()
	_test_active_toggles_bans()
	_test_ban_affects_pool_state()

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

## 建一个含 home_q1..q6 的系列（rarity 全等，便于 BAN 效果的零和断言）。
func _setup_pool() -> GameState:
	ItemCatalog.clear()
	GachaCatalog.clear()
	ItemService.reset()
	ItemService.warehouse_capacity = 1000
	PoolService.drop_all_cached_states()

	var c := ItemCategoryDef.new()
	c.category_id = &"home"
	c.display_name = "家居"
	ItemCatalog.register_category(c)
	for kind in ItemConstants.ALL_CURRENCIES:
		var cur := CurrencyDef.new()
		cur.id = kind
		cur.display_name = String(kind)
		cur.description = "夹具"
		ItemCatalog.register_currency(cur)

	var defs: Array[ItemDef] = []
	for q in [1, 2, 3, 4, 5, 6]:
		var d := ItemDef.new()
		d.item_id = StringName("home_q%d" % q)
		d.display_name = "家居 %d" % q
		d.category = &"home"
		d.quality = q
		d.value = q
		d.size = Vector2i(1, 1)
		d.rarity = 100   # 全等 ⇒ 基础权重均分，BAN 效果可精确读
		d.sell_gold = q * 2
		ItemCatalog.register(d)
		defs.append(d)

	var series := SeriesDef.new()
	series.series_id = &"series_op"
	series.series_quality = 2
	series.regular_count = 6
	series.socket_count = 3
	series.regular_items = defs
	GachaCatalog.register_series(series)

	var st := GameState.new_game()
	GachaService.grant_box(st, &"series_op", 1, &"test")
	return st


## 求当前盒子的 weights_bp / void_mass_bp（干员 BAN 已由 provider 注入求值）。
func _weights(st: GameState) -> Dictionary:
	var box: Box = st.pending_boxes[0]
	var ps := PoolService.get_pool_state(st, box.box_id)
	return {"weights_bp": ps.weights_bp, "void_mass_bp": ps.void_mass_bp}


func _sum_bp(d: Dictionary) -> int:
	var s := 0
	for k in d.keys():
		s += int(d[k])
	return s


func _give_items(item_id: StringName, n: int) -> void:
	for _i in n:
		ItemService.grant(item_id, {"kind": ItemConstants.KIND_UNLOCK})


# ══════════════════════════════════════════════════════════════════════════════
#  测试
# ══════════════════════════════════════════════════════════════════════════════

func _test_level_and_upgrade() -> void:
	_setup_pool()
	OperatorService.reset()
	eq(OperatorService.level, 1, "初始等级 = 1")
	var req: Dictionary = OperatorService.upgrade_requirement()
	eq(req, {&"home_q1": 1}, "1 级配方 = home_q1 ×1")

	# 无配方物品 ⇒ 失败不消耗
	ok(not OperatorService.upgrade(null)["ok"], "无配方物品 ⇒ 升级失败")
	# 提交 1 个 home_q1 ⇒ 升 2 级
	_give_items(&"home_q1", 1)
	var before := ItemService.instances.size()
	ok(OperatorService.upgrade(null)["ok"], "升级成功")
	eq(OperatorService.level, 2, "等级 1 → 2")
	eq(ItemService.instances.size(), before - 1, "配方物品被消耗")


func _test_route_mutually_exclusive() -> void:
	_setup_pool()
	OperatorService.reset()
	eq(OperatorService.route_id, &"precision", "默认路线 = precision")
	ok(not OperatorService.select_route(&"nope"), "未知路线 ⇒ 拒绝")
	eq(OperatorService.route_id, &"precision", "路线不变")
	ok(OperatorService.select_route(&"precision"), "选已选路线 ⇒ 幂等成功")


func _test_active_toggles_bans() -> void:
	_setup_pool()
	OperatorService.reset()
	OperatorService.select_route(&"precision")
	# 出战（默认 active=true）⇒ 返回 ban_targets
	var bans := OperatorService.active_bans()
	eq(bans.size(), 1, "出战 ⇒ 1 个排除目标")
	eq(bans[0], &"home_q6", "排除目标 = home_q6（精准线）")
	# 未出战 ⇒ 空
	OperatorService.set_active(false)
	eq(OperatorService.active_bans().size(), 0, "未出战 ⇒ 无排除")
	OperatorService.set_active(true)
	eq(OperatorService.active_bans().size(), 1, "重新出战 ⇒ 恢复排除")


func _test_ban_affects_pool_state() -> void:
	var st := _setup_pool()
	OperatorService.reset()
	OperatorService.select_route(&"precision")

	# ── 未出战：home_q6 有基础权重 ──────────────────────────────────────────
	OperatorService.set_active(false)
	PoolService.drop_all_cached_states()
	var off := _weights(st)
	ok(int(off["weights_bp"].get(&"home_q6", 0)) > 0, "未出战 ⇒ home_q6 有基础权重")

	# ── 出战：home_q6 权重归零，void 增加（40% 蒸发），其余摊回（60%）──────────
	OperatorService.set_active(true)
	PoolService.drop_all_cached_states()
	var on := _weights(st)
	eq(int(on["weights_bp"].get(&"home_q6", -1)), 0, "出战 ⇒ home_q6 权重 == 0（被排除）")
	ok(int(on["void_mass_bp"]) > int(off["void_mass_bp"]), "出战 ⇒ void 增加（40% 蒸发）")
	# C1 零和：出战前后 Σ weights + void 恒 == 10000
	eq(_sum_bp(on["weights_bp"]) + int(on["void_mass_bp"]), 10000,
		"出战 ⇒ Σ weights_bp + void_mass_bp == 10000（C1 零和）")
	eq(_sum_bp(off["weights_bp"]) + int(off["void_mass_bp"]), 10000,
		"未出战 ⇒ 零和同样成立")

## 物品池 buff 测试（★ v0.46：**唯一对物品池数据做写入的接口**）。
##
## 无头运行：
##   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
## 或直接：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . res://src/gacha/pool/tests/test_pool_buff.tscn
##
## 退出码 0 = 全绿，1 = 有失败。
extends Node

const N := 8

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== 物品池 buff 测试（v0.46：唯一写入门面）===\n")

	_test_apply_dispatch()
	_test_gate_denies_bypass()
	_test_public_write_names_are_gone()
	_test_device_entry_still_works()
	_test_operator_bans_go_through_buff()

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

func _setup() -> Dictionary:
	ItemCatalog.clear()
	GachaCatalog.clear()
	ItemService.reset()
	ItemService.warehouse_capacity = 1000
	PoolService.drop_all_cached_states()

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

	var defs: Array[ItemDef] = []
	for i in N:
		var d := ItemDef.new()
		d.item_id = StringName("s01_%02d" % (i + 1))
		d.display_name = "物品 %d" % (i + 1)
		d.category = &"stardust"
		d.quality = 2
		d.value = 3
		d.size = Vector2i(2, 1)
		d.rarity = 10
		ItemCatalog.register(d)
		defs.append(d)

	# 一件"池外"物品（用来测 add_item）
	var extra := ItemDef.new()
	extra.item_id = &"extra_q1"
	extra.display_name = "池外物品"
	extra.category = &"stardust"
	extra.quality = 1
	extra.value = 1
	extra.size = Vector2i(1, 1)
	extra.rarity = 10
	ItemCatalog.register(extra)

	# ★ v0.61：套系删除 ⇒ 盒子用 `BoxTestKit` 按品质造（池子 = 上面那些物品）
	var bx_items: Array[ItemDef] = defs.duplicate()
	# 夹具模块（BAN，目标在池内）
	var mod := ModuleDef.new()
	mod.id = &"mod_ban_sd1"
	mod.display_name = "排除 物品 1"
	mod.quality = 1
	mod.op_type = ModuleDef.OpType.BAN
	mod.targets = [&"s01_01"]
	GachaCatalog.register_module(mod)

	var st := GameState.new_game()
	ItemService.grant_currency(ItemConstants.CURRENCY_GOLD, 500, ItemConstants.CURRENCY_SOURCE_INIT)
	var boxes := BoxTestKit.grant(st, 1, 2, bx_items)
	return {"state": st, "box": boxes[0]}


# ══════════════════════════════════════════════════════════════════════════════
#  测试
# ══════════════════════════════════════════════════════════════════════════════

func _test_apply_dispatch() -> void:
	print("— 三个动作都能经 buff 落到池子数据上；apply() 是分发器")
	var f := _setup()
	var st: GameState = f["state"]
	var bx: Box = f["box"]

	# ① add_item（直接调用与 apply() 等价）
	var r1 := PoolBuff.add_item(st, bx.box_id, &"extra_q1")
	ok(r1["ok"], "add_item 成功")
	ok(bx.item_pool.has_item(&"extra_q1"), "物品真的进了池子")
	eq(bx.item_pool.extra_item_ids.has(&"extra_q1"), true, "记进 extra_item_ids（要落盘）")

	# ② set_state
	var r2 := PoolBuff.disable(st, bx.box_id, &"extra_q1")
	ok(r2["ok"], "set_state 成功")
	eq(bx.item_pool.state_of(&"extra_q1"), ItemPool.ItemState.DISABLED, "状态已改为禁用")
	var ps := PoolService.get_pool_state(st, bx.box_id)
	eq(ps.weights_bp.has(&"extra_q1"), false, "禁用项退出分布（buff 与池子口径一致）")
	ok(ps.is_zero_sum(), "Σ == 10000")

	# ③ apply_module
	var rev := bx.item_pool.revision
	var r3 := PoolBuff.apply_module(st, bx.box_id, &"mod_ban_sd1", 0)
	ok(r3["ok"], "apply_module 成功")
	eq(bx.modules[0].module_id, &"mod_ban_sd1", "模块进了第 0 位")
	eq(bx.item_pool.revision, rev + 1, "revision +1")

	# ④ apply() 分发：v0.48 的三个 kind 都认（添加 / 揭示 / 禁用）
	#    先造一个隐藏项（隐藏只能由数据层构造），再用 apply(KIND_REVEAL) 揭示它
	ok(bx.item_pool.set_state(&"s01_02", ItemPool.ItemState.HIDDEN), "夹具：s01_02 置为隐藏")
	var r4 := PoolBuff.apply(st, bx.box_id, {
		"kind": PoolBuff.KIND_REVEAL, "item_id": &"s01_02",
	})
	ok(r4["ok"], "apply(KIND_REVEAL) 成功")
	eq(bx.item_pool.state_of(&"s01_02"), ItemPool.ItemState.SHOWN, "分发到了 reveal")
	var r5b := PoolBuff.apply(st, bx.box_id, {
		"kind": PoolBuff.KIND_DISABLE, "item_id": &"s01_02",
	})
	ok(r5b["ok"], "apply(KIND_DISABLE) 成功")
	eq(bx.item_pool.state_of(&"s01_02"), ItemPool.ItemState.DISABLED, "分发到了 disable")

	# ⑤ 未知 kind ⇒ bad_op（不猜、不静默降级）
	var r_unknown := PoolBuff.apply(st, bx.box_id, {"kind": &"nope"})
	ok(not r_unknown["ok"], "未知 kind ⇒ 失败")
	eq(r_unknown["reason"], ItemConstants.REASON_BAD_OP, "原因码 = bad_op")


func _test_gate_denies_bypass() -> void:
	print("— 闸门：不走 buff 直接调 PoolService 的内部写入 ⇒ write_denied")
	var f := _setup()
	var st: GameState = f["state"]
	var bx: Box = f["box"]

	var a := PoolService._write_add_item(st, bx.box_id, &"extra_q1")
	ok(not a["ok"], "直接 _write_add_item ⇒ 拒绝")
	eq(a["reason"], PoolService.R_WRITE_DENIED, "原因码 = write_denied")

	var b := PoolService._write_set_state(st, bx.box_id, &"s01_01", ItemPool.ItemState.HIDDEN)
	eq(b["reason"], PoolService.R_WRITE_DENIED, "_write_set_state 同样被拒")

	var c := PoolService._write_module(st, bx.box_id, &"mod_ban_sd1", 0)
	eq(c["reason"], PoolService.R_WRITE_DENIED, "_write_module 同样被拒")

	# 被拒时什么都没改
	eq(bx.item_pool.has_item(&"extra_q1"), false, "池子没被改动")
	eq(bx.modules[0], null, "位子仍空着")
	eq(bx.item_pool.revision, 0, "revision 没被推进")
	# 闸门用完必须关回去（不然下一次外部调用会被放行）
	ok(not PoolService._write_gate, "闸门在 buff 返回后是关的")


func _test_public_write_names_are_gone() -> void:
	print("— 旧的公开写入口已不存在（改名成内部实现 ⇒ 编译期就绕不过去）")
	# 不能用 `PoolService.has_method()`：那是**实例方法**探测，且不能点在类上；
	# 这里要查的是**静态方法**，走脚本反射。
	ok(not _has_method("res://src/gacha/pool/pool_service.gd", "socket"), "PoolService 不再有 socket()")
	ok(not _has_method("res://src/gacha/pool/pool_service.gd", "add_pool_item"), "PoolService 不再有 add_pool_item()")
	ok(not _has_method("res://src/gacha/pool/pool_service.gd", "set_item_state"), "PoolService 不再有 set_item_state()")
	ok(_has_method("res://src/gacha/pool/pool_buff.gd", "apply"), "PoolBuff.apply() 存在")
	ok(_has_method("res://src/gacha/pool/pool_buff.gd", "add_item"), "PoolBuff.add_item() 存在")
	ok(_has_method("res://src/gacha/pool/pool_buff.gd", "reveal"), "PoolBuff.reveal() 存在")
	ok(_has_method("res://src/gacha/pool/pool_buff.gd", "disable"), "PoolBuff.disable() 存在")
	ok(not _has_method("res://src/gacha/pool/pool_buff.gd", "set_state"), "没有万能 set_state（三件事各有入口）")
	ok(_has_method("res://src/gacha/pool/pool_buff.gd", "apply_module"), "PoolBuff.apply_module() 存在")


## 脚本里是否有这个名字的方法（**含静态**）。
func _has_method(script_path: String, method_name: String) -> bool:
	var scr := load(script_path) as Script
	if scr == null:
		return false
	for m in scr.get_script_method_list():
		if String(m.get("name", "")) == method_name:
			return true
	return false


func _test_device_entry_still_works() -> void:
	print("— 04 的入口仍是 DeviceService.socket()：门槛/金币在它那儿，落库经 buff")
	var f := _setup()
	var st: GameState = f["state"]
	var bx: Box = f["box"]
	var gold_before := ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var r := DeviceService.socket(st, bx.box_id, &"mod_ban_sd1", 0)
	ok(r["ok"], "DeviceService.socket 成功（内部走 PoolBuff.apply_module）")
	eq(bx.modules[0].module_id, &"mod_ban_sd1", "模块已装")
	ok(ItemService.currency_balance(ItemConstants.CURRENCY_GOLD) <= gold_before, "金币按模块成本扣除")
	# 占用位再镶 ⇒ 终局拒绝（v0.44）
	eq(DeviceService.socket(st, bx.box_id, &"mod_ban_sd1", 0)["reason"],
		PoolService.R_SLOT_OCCUPIED, "占用位仍终局拒绝")

## ★ v0.49：**干员的额外排除也经 buff**（原来是从 OperatorService 直接塞给 PoolService 的旁路）。
##
## 钉住两件事：① `PoolBuff.operator_bans()` 是唯一读取入口；② 它真的改变分布
## （与模块 BAN 同一条 40% 蒸发 / 60% 摊回路径）。
func _test_operator_bans_go_through_buff() -> void:
	print("— ★ v0.49 干员排除经 buff：设置 → 分布变化；清空 → 回到基线")
	var f := _setup()
	var st: GameState = f["state"]
	var bx: Box = f["box"]

	PoolBuff.clear_operator_ban_provider()
	eq(PoolBuff.operator_bans().size(), 0, "未注入 ⇒ 空（不施加任何额外排除）")
	var base := PoolService.get_pool_state(st, bx.box_id)
	var base_w := base.weight_of(&"s01_01")
	ok(base_w > 0, "基线：s01_01 可产出（%d bp）" % base_w)
	eq(base.void_mass_bp, 0, "基线：没有 void")

	# 注入一条排除：s01_01
	PoolBuff.set_operator_ban_provider(func() -> Array: return [&"s01_01"])
	eq(PoolBuff.operator_bans(), [&"s01_01"] as Array[StringName], "buff 报出该排除")
	# 分布缓存按 revision 命中，这里强制重算：直接让缓存失效
	PoolService.drop_all_cached_states()
	var after := PoolService.get_pool_state(st, bx.box_id)
	eq(after.weight_of(&"s01_01"), 0, "被排除项权重归 0")
	eq(after.void_mass_bp, int(floor(float(base_w) * 0.4)),
		"40%% 蒸发到 void（%d → %d）" % [base_w, after.void_mass_bp])
	ok(after.is_zero_sum(), "Σ == 10000（C1 仍成立）")

	# 清空 ⇒ 回到基线
	PoolBuff.clear_operator_ban_provider()
	PoolService.drop_all_cached_states()
	var back := PoolService.get_pool_state(st, bx.box_id)
	eq(back.weight_of(&"s01_01"), base_w, "清空后权重逐项回到基线")
	eq(back.void_mass_bp, 0, "void 归 0")
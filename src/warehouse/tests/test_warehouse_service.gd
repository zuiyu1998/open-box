## 仓库系统测试（12-warehouse.md §6 的测试点；★ v0.36 B 重构验收）。
##
## 无头运行：
##   powershell -NoProfile -ExecutionPolicy Bypass -File src/tests/run_tests.ps1
## 或直接：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . res://src/warehouse/tests/test_warehouse_service.tscn
##
## 退出码 0 = 全绿，1 = 有失败。
##
## 覆盖的 B 步骤：
##   B1 `WarehouseService.locations` 的位置账接口（默认值 / 读写 / 移除 / 清空）；
##   B2 `ItemInstance` 不再携带 `location`（序列化也无该键）；
##   B3 `ItemService` 的位置读写经 12（落位 / 领取 / 销毁清账 / count_index 同步）；
##   B4 `to_save_dict` 带 `locations` 独立段，往返字节级稳定，旧档可载入；
##   B5 事务失败 ⇒ 位置零变化（`_state_snapshot` 含 `locations`）。
##
## ★ v0.37 追加：**仓库网格布局**（`WarehouseModel.grid()`）——
##   格子 128×128、画满 `capacity` 格、物品按 `size` 的二维尺寸占块、邮件块标记 locked。
extends Node

const LOC_W := ItemConstants.LOC_WAREHOUSE
const LOC_M := ItemConstants.LOC_MAIL

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== 仓库系统测试（12-warehouse.md §6 / v0.36 B 重构 / v0.37 网格）===\n")

	_test_locations_basic()
	_test_location_default()
	_test_remove_and_reset()
	_test_instance_has_no_location()
	_test_grant_and_claim_via_warehouse()
	_test_destroy_clears_location()
	_test_save_roundtrip_with_locations()
	_test_legacy_save_backfills_warehouse()
	_test_transact_failure_keeps_locations()
	_test_capacity_checkbox_still_single_point()

	_test_grid_cell_size_and_shape()
	_test_grid_places_by_size()
	_test_grid_mail_is_locked()
	_test_grid_boxes_are_one_cell()
	_test_grid_is_deterministic()

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
	for kind in ItemConstants.ALL_CURRENCIES:
		var cur := CurrencyDef.new()
		cur.id = kind
		cur.display_name = String(kind)
		cur.description = "夹具"
		ItemCatalog.register_currency(cur)
	# ★ v0.37：尺寸是二维向量；夹具保留"面积 1 / 2 / 5"以维持容量语义
	var sizes := {1: Vector2i(1, 1), 2: Vector2i(2, 1), 3: Vector2i(5, 1)}
	var values := {1: 1, 2: 3, 3: 9}
	var rarities := {1: 60, 2: 30, 3: 10}
	for cat in [&"stardust", &"crystal"]:
		for q in [1, 2, 3]:
			var d := ItemDef.new()
			d.item_id = StringName("%s_q%d" % [cat, q])
			d.display_name = "%s q%d" % [cat, q]
			d.category = cat
			d.quality = q
			d.value = values[q]
			d.size = sizes[q]
			d.rarity = rarities[q]
			d.sell_gold = q * 2
			ItemCatalog.register(d)


func _reset(capacity := 1000) -> void:
	_setup_catalog()
	ItemService.reset()
	ItemService.warehouse_capacity = capacity


# ══════════════════════════════════════════════════════════════════════════════
#  B1：位置账接口
# ══════════════════════════════════════════════════════════════════════════════

func _test_locations_basic() -> void:
	_reset()
	WarehouseService.reset_locations()
	WarehouseService.set_location("id-a", LOC_M)
	eq(WarehouseService.location_of("id-a"), LOC_M, "set_location / location_of 往返")
	ok(WarehouseService.is_mail("id-a"), "is_mail 认邮件位置")
	ok(not WarehouseService.is_warehouse("id-a"), "is_warehouse 对邮件位置为假")
	WarehouseService.set_location("id-a", LOC_W)
	ok(WarehouseService.is_warehouse("id-a"), "同一 id 可改写为仓库位置")
	eq(WarehouseService.locations.size(), 1, "同一 id 只占一条（不是追加）")


func _test_location_default() -> void:
	_reset()
	WarehouseService.reset_locations()
	# 缺键 ⇒ 默认 warehouse（与旧 `ItemInstance.location` 默认值一致）
	eq(WarehouseService.location_of("never-seen"), LOC_W, "缺键默认 warehouse")
	ok(WarehouseService.is_warehouse("never-seen"), "缺键 ⇒ is_warehouse 为真")
	ok(not WarehouseService.is_mail("never-seen"), "缺键 ⇒ is_mail 为假")
	eq(WarehouseService.locations.size(), 0, "只读查询不写入映射（不产生副作用）")


func _test_remove_and_reset() -> void:
	_reset()
	WarehouseService.reset_locations()
	WarehouseService.set_location("x", LOC_M)
	WarehouseService.set_location("y", LOC_M)
	eq(WarehouseService.locations.size(), 2, "前置：两条位置记录")
	WarehouseService.remove_location("x")
	eq(WarehouseService.locations.size(), 1, "remove_location 移除一条")
	eq(WarehouseService.location_of("x"), LOC_W, "移除后回落到默认 warehouse")
	WarehouseService.reset_locations()
	eq(WarehouseService.locations.size(), 0, "reset_locations 清空全部")
	eq(WarehouseService.location_of("y"), LOC_W, "清空后也回落到默认")


# ══════════════════════════════════════════════════════════════════════════════
#  B2：实例不再携带 location
# ══════════════════════════════════════════════════════════════════════════════

func _test_instance_has_no_location() -> void:
	_reset()
	var inst := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	var d := inst.to_dict()
	ok(not d.has("location"), "实例序列化不含 location 键（B2）")
	ok(not ("location" in inst), "ItemInstance 没有 location 属性（B2）")
	# 位置仍然可查——但答案来自 12
	eq(WarehouseService.location_of(inst.instance_id), LOC_W, "位置改由 WarehouseService 回答")
	# 从落盘字典还原的实例同样没有 location
	var back := ItemInstance.from_dict(d)
	ok(not ("location" in back), "from_dict 还原的实例也没有 location 属性")


# ══════════════════════════════════════════════════════════════════════════════
#  B3：落位 / 领取 / 销毁清账
# ══════════════════════════════════════════════════════════════════════════════

func _test_grant_and_claim_via_warehouse() -> void:
	# 容量 1：第一件进仓库，第二件进邮件
	_reset(1)
	var a := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	var b := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(WarehouseService.location_of(a.instance_id), LOC_W, "放得下 ⇒ 仓库")
	eq(WarehouseService.location_of(b.instance_id), LOC_M, "装不下 ⇒ 邮件")
	eq(ItemService.count(&"stardust", 1, LOC_W), 1, "count(仓库) == 1（位置口径与 12 一致）")
	eq(ItemService.count(&"stardust", 1, LOC_M), 1, "count(邮件) == 1")
	eq(ItemService.mail_instances().size(), 1, "mail_instances 与 12 的位置一致")

	# 腾出空间后领取：位置由 12 改写，实例身份逐项不变
	var id_before := b.instance_id
	var serial_before := b.serial
	var src_before := JSON.stringify(b.source)
	ItemService.consume([a.instance_id], ItemConstants.TAG_FUEL)
	var res := ItemService.claim([b.instance_id])
	eq(res["claimed"].size(), 1, "领取成功")
	eq(WarehouseService.location_of(b.instance_id), LOC_W, "领取只改 12 的位置账")
	eq(b.instance_id, id_before, "领取不改 instance_id")
	eq(b.serial, serial_before, "领取不改 serial")
	eq(JSON.stringify(b.source), src_before, "领取不改 source")
	eq(ItemService.count(&"stardust", 1, LOC_W), 1, "领取后 count(仓库) == 1")
	eq(ItemService.count(&"stardust", 1, LOC_M), 0, "领取后 count(邮件) == 0")


func _test_destroy_clears_location() -> void:
	_reset()
	var inst := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	ok(WarehouseService.locations.has(inst.instance_id), "前置：位置记录存在")
	ItemService.consume([inst.instance_id], ItemConstants.TAG_FUEL)
	ok(not WarehouseService.locations.has(inst.instance_id),
		"销毁后位置记录被清除（映射不泄漏）")
	eq(WarehouseService.location_of(inst.instance_id), LOC_W, "清除后查询回落到默认")


func _test_capacity_checkbox_still_single_point() -> void:
	# 容量判定仍只有一处（02 的 `_fits` 读 02 物品占位 + 12 的盒占位），B 重构不动它
	_reset(3)
	WarehouseService.reset_box_usage()
	eq(WarehouseService.box_fits(3), true, "空仓可放 3 单位盒子")
	WarehouseService.place_box(2)
	eq(WarehouseService.box_used, 2, "place_box 记账")
	eq(WarehouseService.box_fits(2), false, "剩余 1 单位时放不下 2")
	WarehouseService.release_box(2)
	eq(WarehouseService.box_used, 0, "release_box 释放")


# ══════════════════════════════════════════════════════════════════════════════
#  B4：存档位置段
# ══════════════════════════════════════════════════════════════════════════════

func _test_save_roundtrip_with_locations() -> void:
	_reset(2)
	for i in 5:
		ItemService.grant(&"stardust_q1", {"kind": &"gacha", "series_id": &"s1",
			"box_seed": i, "draw_index": i})
	var d := ItemService.to_save_dict()
	ok(d.has("locations"), "to_save_dict 带 locations 段（B4）")
	var locs: Dictionary = d["locations"]
	eq(locs.size(), 5, "5 个实例各一条位置记录")
	var warehouse_n := 0
	var mail_n := 0
	for k in locs.keys():
		if String(locs[k]) == String(LOC_W):
			warehouse_n += 1
		elif String(locs[k]) == String(LOC_M):
			mail_n += 1
	eq(warehouse_n, 2, "容量 2 ⇒ 仓库侧 2 条")
	eq(mail_n, 3, "溢出 3 条进邮件")

	# 往返字节级稳定
	var j1 := JSON.stringify(d)
	ItemService.from_save_dict(JSON.parse_string(j1))
	var j2 := JSON.stringify(ItemService.to_save_dict())
	eq(j2, j1, "含 positions 段的位置往返字节级稳定")
	# 位置确实被还原（不是默认值）
	eq(ItemService.count(&"stardust", 1, LOC_M), 3, "载入后邮件侧计数 == 3")
	eq(ItemService.count(&"stardust", 1, LOC_W), 2, "载入后仓库侧计数 == 2")
	ok(ItemService.check_conservation(), "载入后守恒式成立")


func _test_legacy_save_backfills_warehouse() -> void:
	_reset(1000)
	var inst := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	# 造一份"旧档"：实例条目里带 location 键，但整体没有 locations 段
	var legacy := ItemService.to_save_dict()
	legacy.erase("locations")
	var arr: Array = legacy["instances"]
	(arr[0] as Dictionary)["location"] = "mail"   # 旧档的逐实例 location（应被忽略）
	ItemService.from_save_dict(legacy)
	eq(ItemService.instances.size(), 1, "旧档载入：实例数不变（不丢东西）")
	eq(WarehouseService.location_of(inst.instance_id), LOC_W,
		"缺 locations 段的旧档 ⇒ 全部回填默认 warehouse（不静默搬进邮件）")
	eq(ItemService.count(&"stardust", 1, LOC_W), 1, "仓库口径计数正确")


# ══════════════════════════════════════════════════════════════════════════════
#  B5：事务失败 ⇒ 位置零变化
# ══════════════════════════════════════════════════════════════════════════════

func _test_transact_failure_keeps_locations() -> void:
	_reset(100)
	var ids: Array[String] = []
	for i in 3:
		ids.append(ItemService.grant(&"stardust_q1", {"kind": &"gacha"}).instance_id)
	var locs_before := WarehouseService.locations_to_dict()
	var idx_before := ItemService.count_index.duplicate()
	var used_before := ItemService.warehouse_used
	# 必然失败的组合（第二个 op 的 item_id 未注册）
	var res := ItemService.transact([
		{"op": &"consume", "instance_ids": [ids[0]], "tag": &"convert"},
		{"op": &"grant", "item_id": &"nope", "source": {"kind": &"convert"}},
	])
	eq(res["ok"], false, "事务失败")
	eq(WarehouseService.locations_to_dict(), locs_before, "失败事务：位置账逐项不变（B5）")
	eq(ItemService.count_index.duplicate(), idx_before, "失败事务：count_index 不变")
	eq(ItemService.warehouse_used, used_before, "失败事务：warehouse_used 不变")


# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.37：仓库网格布局
# ══════════════════════════════════════════════════════════════════════════════

## 造一个只有网格、没有盒子的模型（盒子归 01，网格测试不需要它）。
func _model(capacity: int) -> WarehouseModel:
	_reset(capacity)
	var m := WarehouseModel.new()
	m.bind(null)   # 没有 GameState ⇒ 盒数为 0（"尚未开局"），网格只画物品
	return m


func _test_grid_cell_size_and_shape() -> void:
	var m := _model(1000)
	var g := m.grid()
	eq(g["cell_size"], 128, "格子边长 = 128（用户裁决）")
	eq(g["capacity"], 1000, "画出的仓库空间 = 容量（1000 格）")
	eq(g["columns"], 12, "列数固定 = 12（用户裁决）")
	eq(g["rows"], 84, "行数 = ceil(1000 / 12) = 84（12×84 = 1008 ≥ 1000）")
	eq((g["placed"] as Array).size(), 0, "空仓库 ⇒ 没有块")
	eq((g["unplaced"] as Array).size(), 0, "空仓库 ⇒ 没有放不下的块")

	# 小容量也成立：列数仍是 12，行数按 ceil(capacity/12)
	var m2 := _model(1)
	var g2 := m2.grid()
	eq(g2["columns"], 12, "容量 1 ⇒ 列数仍是 12（固定）")
	eq(g2["rows"], 1, "容量 1 ⇒ 行数 = ceil(1/12) = 1")


func _test_grid_places_by_size() -> void:
	# q1 = 1×1、q2 = 2×1、q3 = 5×1（夹具的面积语义仍保留）
	var m := _model(100)
	var a := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})   # 1×1
	var b := ItemService.grant(&"stardust_q2", {"kind": &"gacha"})   # 2×1
	var c := ItemService.grant(&"stardust_q3", {"kind": &"gacha"})   # 5×1
	var g := m.grid()
	var placed: Array = g["placed"]
	eq(placed.size(), 3, "3 件物品 ⇒ 3 个块")

	var pa: Dictionary = placed[0]
	eq(pa["x"], 0, "第一件从 (0,0) 开始")
	eq(pa["y"], 0, "第一件在第一行")
	eq([pa["w"], pa["h"]], [1, 1], "q1 的块 = 1×1")
	eq(pa["instance_id"], a.instance_id, "块指回实例身份")
	eq(pa["locked"], false, "仓库物品不锁定")

	var pb: Dictionary = placed[1]
	eq(pb["instance_id"], b.instance_id, "第二个块是 q2（按入库顺序）")
	eq([pb["w"], pb["h"]], [2, 1], "q2 的块 = 2×1（宽 2 格）")
	eq([pb["x"], pb["y"]], [1, 0], "1×1 用掉 (0,0) 后，2×1 从 (1,0) 开始")

	var pc: Dictionary = placed[2]
	eq(pc["instance_id"], c.instance_id, "第三个块是 q3")
	eq([pc["w"], pc["h"]], [5, 1], "q3 的块 = 5×1")

	# 块占的格数之和 == 仓库已用（容量账与网格必须说同一件事）
	var area := 0
	for p in placed:
		area += int(p["w"]) * int(p["h"])
	eq(area, ItemService.warehouse_used, "块面积之和 == warehouse_used（网格与容量账同源）")
	ok(area <= int(g["capacity"]), "仓库侧块面积不超过容量")


func _test_grid_mail_is_locked() -> void:
	# 容量 1：第一件进仓库、第二件进邮件 ⇒ 两块都在网格里，但邮件块 locked
	var m := _model(1)
	var a := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	var b := ItemService.grant(&"stardust_q1", {"kind": &"gacha"})
	eq(WarehouseService.location_of(b.instance_id), LOC_M, "前置：第二件在邮件")
	var g := m.grid()
	var placed: Array = g["placed"]
	eq(placed.size(), 2, "**邮件物品也进网格**（用户裁决）")

	var pa: Dictionary = placed[0]
	eq(pa["instance_id"], a.instance_id, "仓库物品排在前面")
	eq(pa["locked"], false, "仓库物品不锁定")

	var pb: Dictionary = placed[1]
	eq(pb["instance_id"], b.instance_id, "邮件物品排在后面")
	eq(pb["locked"], true, "**邮件物品标记 locked**（不可用）")

	# 邮件块不计入仓库侧面积：仓库已用只算仓库那一件
	eq(ItemService.warehouse_used, 1, "邮件物品不占仓库容量")
	ok(int(g["rows"]) * int(g["columns"]) >= int(g["capacity"]),
		"邮件块越过容量后网格会扩容，不再有放不下的块")


func _test_grid_boxes_are_one_cell() -> void:
	# 盲盒固定 1×1（Box.size = 1，与容量账同一口径）
	var st := GameState.new()
	_reset(100)
	var m := WarehouseModel.new()
	m.bind(st)
	# 直接造一个 1×1 的盒子（不依赖 01 的内容配置）
	var box := Box.new()
	box.box_id = "box-1"
	box.size = 1
	box.location = LOC_W
	st.add_box(box)

	var g := m.grid()
	var placed: Array = g["placed"]
	eq(placed.size(), 1, "1 个盲盒 ⇒ 1 个块")
	var p: Dictionary = placed[0]
	eq(p["kind"], "box", "块类型 = box")
	eq([p["w"], p["h"]], [1, 1], "盲盒固定 1×1")
	eq(p["locked"], false, "仓库里的盲盒不锁定")


func _test_grid_is_deterministic() -> void:
	var m := _model(50)
	for i in 5:
		ItemService.grant(&"stardust_q2", {"kind": &"gacha"})
	var g1 := m.grid()
	var g2 := m.grid()
	eq(g1["placed"], g2["placed"], "同一状态下两次布局逐项相同（确定性）")
	eq(g1["rows"], g2["rows"], "行数也相同")
	# 所有块互不重叠（锚点两两不同，且按行主序推进）
	var seen := {}
	var overlap := false
	for p in (g1["placed"] as Array):
		for dy in int(p["h"]):
			for dx in int(p["w"]):
				var key := "%d,%d" % [int(p["x"]) + dx, int(p["y"]) + dy]
				if seen.has(key):
					overlap = true
				seen[key] = true
	ok(not overlap, "块之间没有重叠")

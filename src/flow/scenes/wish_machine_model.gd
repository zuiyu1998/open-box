## 许愿机 —— Model（★ v0.30 MVC；★ v0.41 三栏重构）。
##
## **纯数据与业务，不碰任何 UI**（不知道 Button / Label 的存在）。
## 它只回答四类问题，全部通过既有系统的入口（本类不自己算数）：
##   1. 这台"许愿机"（= 设备）长什么样：名字 / 等级 / 本级两条效果 / 原石 / 升级价；
##   2. 升级：走 `DeviceService.upgrade_device()`（价格问 `upgrade_cost()`）；
##   3. 开盒（**单次 / 10 连 / 全部**）：走 `DeviceService.redeem()`，逐次累计结果；
##   4. 模块镶嵌（★ v0.41）：位子展示走 `PoolService.get_modules()`，镶嵌走
##      `DeviceService.socket()`（**本类不写池子数据**）。
##      ★ v0.44：**拆卸已删除**——模块镶上即永久锁定，本类不再有"取下"的入口。
##
## ★ v0.41：界面扩成三栏（左=盲盒/模块/产出，中=干员，右=信息/开启），
##   因此快照额外提供 `slots` / `slot_options` / `module_options` / `operator` 等键；
##   **既有键（`device_name` / `level` / `box_options` / `open_disabled` / `result` /
##   `box_uses` / `box_expectation` …）一律保留**，避免上层与测试断链。
##
## 纪律：不读档、不写档、不改 `GameState` / `ItemService` 的写入（`11-flow.md` §2）。
class_name WishMachineModel
extends RefCounted

var state: GameState = null

## 开盒 / 镶嵌 / 升级共用的结果行（一次操作覆盖上一次）。
var open_result: String = ""

## ★ v0.51：**浮层表格的排序**。0 = 池内顺序，1 = 概率降序，2 = 价值降序，3 = 售价降序。
## 存在 Model 而不是 View：它是**表格数据的口径**（同一份数据的不同呈现顺序），
## 放 View 会让"渲染"承担业务排序；放这里也能被测试直接断言。
const SORT_MODES: Array[String] = ["池内顺序", "概率 ↓", "价值 ↓"]
var pool_sort_mode: int = 0


## 设排序（越界 ⇒ 回落到池内顺序）。**不改任何池子数据**，只是下一次 snapshot 的顺序变了。
func set_pool_sort(mode: int) -> void:
	pool_sort_mode = clampi(mode, 0, SORT_MODES.size() - 1)


## 绑定这一局。View 用 `snapshot()` 拉取展示数据。
func bind(s: GameState) -> void:
	state = s


## 只读快照：**View 唯一的数据来源**（Model 算好，View 只渲染）。
##
## `box_index` / `slot_index` / `module_index` 都是 **View 的选中项下标**（-1 = 未选）。
##
## ★ **未选即取第 0 项**（`_norm_box` / `_norm_slot`）：首次 `render` 时下拉还是空的，
##   View 报的是 -1；若照 -1 算，位子与模块列表都会是空表，而**程序设置 `selected`
##   不会发 `item_selected`** ⇒ 页面永远停在"空"上（实测踩过）。归一化后首帧就自洽。
func snapshot(
	box_index: int = -1, slot_index: int = -1, module_index: int = -1
) -> Dictionary:
	var dev: Device = null if state == null else DeviceService.primary_device(state)
	var boxes := _boxes()
	box_index = _norm_box(box_index, boxes)
	slot_index = _norm_slot(slot_index, _selected_box(box_index, boxes))

	if dev == null:
		return {
			"device_name": "还没有许愿机",
			"description": "开局应当发一台；若这里是空的，说明这一局没有建档",
			"level": "", "effect": "", "gem": "原石 0",
			"upgrade_text": "升级", "upgrade_disabled": true,
			"box_options": [] as Array[String],
			"open_disabled": true, "open_all_disabled": true,
			"result": open_result,
			"box_uses": "剩余开盒次数 —", "box_expectation": "期望 —",
			"expectation_gold_per_open": 0.0, "expectation_module_cost": 0,
			"expectation_net": 0.0,
			"slot_options": [] as Array[String], "slot_detail": "—",
			"module_options": [] as Array[String],
			"socket_disabled": true,
			"pool_table_rows": [] as Array,
			"pool_table_note": "", "pool_table_totals": "", "pool_table_sort_mode": 0,
			"operator": _operator_block(),
		}

	var def: DeviceDef = DeviceCatalog.get_device(dev.device_id)
	var name := String(dev.device_id)
	var desc := ""
	if def != null:
		name = def.display_name
		desc = def.description

	var max_lv: int = def.max_level() if def != null else dev.level
	var level_text := "等级 Lv.%d / Lv.%d" % [dev.level, max_lv]

	var effect := ""
	if def != null:
		var spec: DeviceLevelSpec = def.spec_for_level(dev.level)
		effect = "可开盲盒品质 ≤ %d · 开盒成本 %d%%" % [
			spec.unlock_quality_max if spec != null else 0,
			int(round((spec.open_cost_bp if spec != null else 10000) / 100.0)),
		]

	var cost: int = DeviceService.upgrade_cost(state, dev.device_id)
	var upgrade_text := "升级"
	var upgrade_disabled := true
	if dev.level >= max_lv:
		upgrade_text = "已满级"
	elif cost < 0:
		upgrade_text = "升级"
	else:
		upgrade_text = "升级（%d 原石）" % cost
		upgrade_disabled = cost > ItemService.currency_balance(ItemConstants.CURRENCY_GEM)

	var gem := "原石 %d" % ItemService.currency_balance(ItemConstants.CURRENCY_GEM)

	var opts: Array[String] = []
	for b in boxes:
		# ★ v0.61：套系删除后没有"套系名"可显示 ⇒ 用**品质 + 剩余寿命**（比 id 可读）
		opts.append("品质 %d · 剩余 %d 次" % [b.quality, b.uses_remaining])

	var stats := _box_stats(box_index, boxes)
	var slots := _slots_block(box_index, boxes, slot_index)
	var mods := _modules_block(box_index, boxes, slot_index)

	var table := _pool_table_block(box_index, boxes)

	return {
		"device_name": name, "description": desc,
		"level": level_text, "effect": effect, "gem": gem,
		"upgrade_text": upgrade_text, "upgrade_disabled": upgrade_disabled,
		"box_options": opts,
		"open_disabled": boxes.size() == 0, "open_all_disabled": boxes.size() == 0,
		"result": open_result,
		"box_uses": stats["uses"], "box_expectation": stats["expectation"],
		"expectation_gold_per_open": stats.get("expectation_gold_per_open", 0.0),
		"expectation_module_cost": stats.get("expectation_module_cost", 0),
		"expectation_net": stats.get("expectation_net", 0.0),
		"slot_options": slots["options"], "slot_detail": slots["detail"],
		"module_options": mods["options"],
		"socket_disabled": mods["socket_disabled"],
		"pool_table_rows": table["rows"],
		"pool_table_note": table["note"],
		"pool_table_totals": table["totals"],
		"pool_table_sort_mode": table.get("sort_mode", 0),
		"operator": _operator_block(),
	}


# ══════════════════════════════════════════════════════════════════════════════
#  左栏 · 盲盒 / 模块 / 产出
# ══════════════════════════════════════════════════════════════════════════════

## 仓库里可用的盒子（邮件里的不可配置 / 不可开，v0.26）。
func _boxes() -> Array:
	return [] if state == null else state.boxes_in(ItemConstants.LOC_WAREHOUSE)


func _selected_box(box_index: int, boxes: Array) -> Box:
	if box_index < 0 or box_index >= boxes.size():
		return null
	return boxes[box_index]


## 盲盒下标归一化：**未选（-1）/ 越界 ⇒ 取第 0 项**（空清单 ⇒ -1）。
func _norm_box(box_index: int, boxes: Array) -> int:
	if boxes.is_empty():
		return -1
	if box_index < 0 or box_index >= boxes.size():
		return 0
	return box_index


## 位子下标归一化：**未选（-1）/ 越界 ⇒ 取第 0 位**（该盒没有位子 ⇒ -1）。
func _norm_slot(slot_index: int, box: Box) -> int:
	if box == null or box.modules.is_empty():
		return -1
	if slot_index < 0 or slot_index >= box.modules.size():
		return 0
	return slot_index


## ★ v0.48：池内物品下标归一化——**未选 / 越界 ⇒ 取第 0 项**（与 `_norm_box` / `_norm_slot` 同一惯例）。
## 空池子 ⇒ -1。
func _box_stats(box_index: int, boxes: Array) -> Dictionary:
	var empty := {"uses": "剩余开盒次数 —", "expectation": "期望 —"}
	var b := _selected_box(box_index, boxes)
	if b == null:
		return empty

	var ps := PoolService.get_pool_state(state, b.box_id)
	var ev := EvalService.evaluate_pool(ps)
	var per_open := EvalService.m_bar_gold(ev)
	var module_cost := EvalService.module_gold_cost(b)
	var remaining := maxi(b.uses_remaining, 0)
	var net := per_open * float(remaining) - float(module_cost)

	var text := "单次毛期望 ≈ %.1f 金币" % per_open
	if remaining <= 0:
		text += "\n净期望 —（这个盒子已经没有开盒次数）"
	else:
		text += "\n净期望 ≈ %.0f 金币（剩余 %d 次全开完，已扣模块 %d 金币）" % [
			net, remaining, module_cost,
		]
	return {
		"uses": "剩余开盒次数 %d" % b.uses_remaining,
		"expectation": text,
		# 结构化数值（测试 / 将来别处复用；不要让下游再解析字符串）
		"expectation_gold_per_open": per_open,
		"expectation_module_cost": module_cost,
		"expectation_net": net,
	}


## 该盒的**定长位子**展示（空位 / 已装），以及所有位子的文案供 `SlotPicker` 用。
func _slots_block(box_index: int, boxes: Array, slot_index: int) -> Dictionary:
	var b := _selected_box(box_index, boxes)
	if b == null:
		return {"options": [] as Array[String], "detail": "先选一个盲盒"}
	var options: Array[String] = []
	for i in b.modules.size():
		var m: Module = b.modules[i]
		if m == null:
			options.append("位 %d：空" % (i + 1))
		else:
			options.append("位 %d：%s" % [i + 1, _module_name(m.module_id)])
	var detail := "共 %d 位 · 已占 %d" % [b.modules.size(), b.occupied_count()]
	if slot_index >= 0 and slot_index < options.size():
		detail += " · 选中 %s" % options[slot_index]
	return {"options": options, "detail": detail}


## **可镶嵌的模块**：只列"目标全部在该盒池内"的模块——否则必然被 `unknown_target` 拒。
## 返回 `{options, socket_disabled}`。
##
## ★ v0.44：**位子被占用 ⇒ 不能再镶**（模块永久锁定）。这不是"提示先拆"，而是终局状态。
func _modules_block(box_index: int, boxes: Array, slot_index: int) -> Dictionary:
	var b := _selected_box(box_index, boxes)
	if b == null or b.item_pool == null:
		return {"options": [] as Array[String], "socket_disabled": true}

	var pool_ids := b.item_pool.item_ids()
	var options: Array[String] = []
	for mid in GachaCatalog.all_module_ids():
		var mdef := GachaCatalog.get_module(mid)
		if mdef == null:
			continue
		if not _targets_in_pool(mdef, pool_ids):
			continue
		options.append("%s（%d 金币）" % [mdef.display_name if mdef.display_name != "" else String(mid), mdef.gold_cost])

	var slot_ok := slot_index >= 0 and slot_index < b.modules.size()
	var slot_empty := slot_ok and b.modules[slot_index] == null
	return {
		"options": options,
		"socket_disabled": options.is_empty() or not slot_empty,
	}


# ══════════════════════════════════════════════════════════════════════════════
#  左栏 · 池子（★ v0.45：成员与三态 = 池子上的可编辑字段，不走模块）
# ══════════════════════════════════════════════════════════════════════════════

func _pool_table_block(box_index: int, boxes: Array) -> Dictionary:
	var b := _selected_box(box_index, boxes)
	if b == null or b.item_pool == null:
		return {"rows": [] as Array, "note": "先选一个盲盒", "totals": ""}
	var ps := PoolService.get_pool_state(state, b.box_id)
	if ps == null:
		return {"rows": [] as Array, "note": "池子不可用", "totals": ""}

	var ev := EvalService.evaluate_pool(ps)
	var prob_of: Dictionary = {}
	if ev != null:
		for i in ev.item_ids.size():
			prob_of[ev.item_ids[i]] = float(ev.probs[i])

	# ★ v0.66（用户裁决）：**隐藏项也出行**，只是**这一行不显示任何信息**（名称/权重/概率/价值全部打码）。
	#   统计口径仍按**全池**算（隐藏项权重照旧参与，零和不变）。
	var rows: Array = []
	var hidden := 0
	var prob_sum := 0.0
	for d in b.item_pool.base_items:
		if d == null:
			continue
		var st := b.item_pool.state_of(d.item_id)
		var p := float(prob_of.get(d.item_id, 0.0))
		prob_sum += p
		if st == ItemPool.ItemState.HIDDEN:
			hidden += 1
			rows.append({
				"name": "？？？",
				"state": "隐藏（信息不展示）",
				"weight_bp": 0,
				"prob": 0.0,
				"value": 0,
				"masked": true,
			})
			continue
		rows.append({
			"name": d.display_name if d.display_name != "" else String(d.item_id),
			"state": _state_name(st),
			"weight_bp": ps.weight_of(d.item_id),
			"prob": p,
			"value": d.value,
			"masked": false,
		})

	# ★ v0.51：排序。**只在"呈现顺序"上动**——`rows` 是副本，池子数据与分布一概不变。
	#   同值时的并列按池内顺序（下标）稳定，避免每次刷新顺序抖动。
	if pool_sort_mode > 0:
		var key := "prob" if pool_sort_mode == 1 else "value"
		var order: Dictionary = {}      # name -> 池内下标（稳定并列用）
		for i in rows.size():
			order[rows[i]["name"]] = i
		rows.sort_custom(func(a, b) -> bool:
			# ★ v0.66：打码行（隐藏）没有可比值 ⇒ 一律沉底，避免混进排名里泄露"它大概值多少"
			var ma := bool(a.get("masked", false))
			var mb := bool(b.get("masked", false))
			if ma != mb:
				return mb
			var va := float(a[key])
			var vb := float(b[key])
			if va != vb:
				return va > vb
			return int(order[a["name"]]) < int(order[b["name"]])
		)

	var note := "共 %d 件" % rows.size()
	note += "　｜　排序：%s" % SORT_MODES[pool_sort_mode]
	if hidden > 0:
		note += "；其中 **%d 件隐藏（行在，信息不展示）**" % hidden
	var totals := "Σ概率 %.2f%%　+　void %.2f%%　=　100.00%%　｜　单次毛期望 ≈ %.1f 金币" % [
		prob_sum * 100.0, float(ps.void_mass_bp) / 100.0, EvalService.m_bar_gold(ev),
	]
	return {"rows": rows, "note": note, "totals": totals, "sort_mode": pool_sort_mode}


func _state_name(st: int) -> String:
	match st:
		ItemPool.ItemState.HIDDEN:
			return "隐藏（仍会抽出，只是不陈列）"
		ItemPool.ItemState.DISABLED:
			return "禁用（不会抽出）"
		_:
			return "显示"


## ★ v0.48：**揭示**选中的池内物品（隐藏 → 显示）。
## 用户裁决的三态是一条**单向链**：添加→显示、隐藏→(揭示)→显示、显示→(禁用)→禁用；
## 没有"显示 → 隐藏"，也没有"禁用 → 显示"（终局）。所以 UI 是**两个按钮**，不是一个循环。
func _targets_in_pool(mdef: ModuleDef, pool_ids: Array) -> bool:
	if mdef.targets.is_empty():
		return false
	for t in mdef.targets:
		if not pool_ids.has(t):
			return false
	return true


# ══════════════════════════════════════════════════════════════════════════════
#  中栏 · 干员
# ══════════════════════════════════════════════════════════════════════════════

## 干员块（读 15；本类只展示，不改它的规则）。
func _operator_block() -> Dictionary:
	var route := OperatorService.current_route()
	var bans := OperatorService.active_bans()
	var names: PackedStringArray = PackedStringArray()
	for id in bans:
		var d := ItemCatalog.get_def(id)
		names.append(d.display_name if d != null else String(id))
	return {
		"name": "干员",
		"level": "Lv.%d / Lv.%d" % [OperatorService.level, OperatorService.MAX_LEVEL],
		"route": String(route.get("name", "未选择")),
		"bans": "排除：%s" % "、".join(names) if names.size() > 0 else "排除：无",
		"active": OperatorService.active,
		"toggle_text": "出战中（点击撤回）" if OperatorService.active else "未出战（点击出战）",
	}


## 出战 / 撤回（无代价，即时生效；`OperatorService` 会负责丢池子缓存）。
func toggle_operator() -> void:
	OperatorService.toggle_active()
	open_result = "干员已出战" if OperatorService.active else "干员已撤回（未出战）"


# ══════════════════════════════════════════════════════════════════════════════
#  行为入口
# ══════════════════════════════════════════════════════════════════════════════

## 升级：走 04；结果写进 `open_result`（与开盒共用一条结果行）。
func upgrade() -> void:
	var dev: Device = null if state == null else DeviceService.primary_device(state)
	if dev == null:
		open_result = "升级失败：没有许愿机"
		return
	var r := DeviceService.upgrade_device(state, dev.device_id)
	if r["ok"]:
		open_result = "升级成功：Lv.%d" % DeviceService.primary_device(state).level
	else:
		open_result = "升级失败：%s" % String(r["reason"])


## 开盒：`times` 连开（同一选中盒子）。`box_index` 是 View 的选中项下标。
## **`times <= 0` = 把该盒剩余次数全部开完**（右栏「开启全部」）。
func open(times: int, box_index: int) -> void:
	if state == null:
		open_result = "尚未开局"
		return
	var boxes := _boxes()
	box_index = _norm_box(box_index, boxes)
	var box := _selected_box(box_index, boxes)
	if box == null:
		open_result = "请先选择要开的盲盒"
		return

	var wanted := times
	if wanted <= 0:
		wanted = maxi(box.uses_remaining, 0)
		if wanted <= 0:
			open_result = "这个盒子已经没有开盒次数了"
			return

	var hit: Array[String] = []
	var voids := 0
	var mailed := 0
	var opened := 0
	for _i in wanted:
		var r := DeviceService.redeem(state, box)
		if not r.ok:
			if opened > 0:
				open_result = "%d 连开到第 %d 次失败：%s（已开 %d 次%s）" % [
					wanted, opened + 1, String(r.error), opened,
					"、void %d" % voids if voids > 0 else "",
				]
			else:
				open_result = "开盒失败：%s" % String(r.error)
			return
		opened += 1
		if r.is_void:
			voids += 1
		else:
			var d := ItemCatalog.get_def(r.item_id)
			var iname := "%s（%s）" % [
				d.display_name if d != null else String(r.item_id),
				ItemConstants.quality_name(d.quality if d != null else 1),
			]
			# ★ v0.38：**落位可感知**——仓库放不下 ⇒ 进邮件。文案要说得出来（P5：产出永不丢失，
			#   但玩家得知道它去哪了，否则"东西凭空消失"的错觉比真丢还糟）。
			if r.mailed:
				mailed += 1
				hit.append("%s → 邮件" % iname)
			else:
				hit.append(iname)

	var head := "开出：" if opened == 1 else "%d 连开出 %d 件：" % [opened, hit.size()]
	var tail := "" if voids == 0 else "、void %d 次" % voids
	if mailed > 0:
		tail += "、%d 件存入邮件" % mailed
	open_result = head + ("、".join(hit) if hit.size() > 0 else "什么都没有") + tail


## 镶嵌：把第 `module_index` 个候选模块装进第 `slot_index` 位。
## 走 `DeviceService.socket()`（校验 + 计价 + 转发）；**本类不写 `Box.modules`**。
func socket_module(box_index: int, slot_index: int, module_index: int) -> void:
	var boxes := _boxes()
	box_index = _norm_box(box_index, boxes)
	var box := _selected_box(box_index, boxes)
	if box == null:
		open_result = "镶嵌失败：请先选择盲盒"
		return
	slot_index = _norm_slot(slot_index, box)
	var mids := _socketable_ids(box)
	if module_index < 0 or module_index >= mids.size():
		open_result = "镶嵌失败：请先选择模块"
		return
	var r := DeviceService.socket(state, box.box_id, mids[module_index], slot_index)
	if r["ok"]:
		if bool(r.get("destroyed", false)):
			open_result = "镶嵌成功，但该盒寿命归零 ⇒ 盒子已被摧毁"
		else:
			open_result = "镶嵌成功：%s → 位 %d" % [_module_name(mids[module_index]), slot_index + 1]
	else:
		open_result = "镶嵌失败：%s" % String(r["reason"])


## ── 墓碑：`unsocket_module()` 已于 **v0.44 删除**（用户裁决）─────────────────────────
##
## 许愿机页原有一个「拆卸」按钮（把位子置空、零返还）。**拆卸与替换一起取消**后，
## 这个入口没有任何可用语义了：**模块一旦镶上就永久锁定，直到盒子被摧毁**。
## 不要把它加回来——理由与 `PoolService.unsocket()` 的墓碑一致（防"能取下来"的后门）。


## 可镶嵌模块的 id 列表（**与 `_modules_block()` 的 options 同序**）。
func _socketable_ids(b: Box) -> Array[StringName]:
	var out: Array[StringName] = []
	if b == null or b.item_pool == null:
		return out
	var pool_ids := b.item_pool.item_ids()
	for mid in GachaCatalog.all_module_ids():
		var mdef := GachaCatalog.get_module(mid)
		if mdef == null:
			continue
		if _targets_in_pool(mdef, pool_ids):
			out.append(mid)
	return out


func _module_name(mid: StringName) -> String:
	var mdef := GachaCatalog.get_module(mid)
	if mdef == null:
		return String(mid)
	return mdef.display_name if mdef.display_name != "" else String(mid)

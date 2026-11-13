## 许愿机 —— Model（★ v0.30 MVC 重构）。
##
## **纯数据与业务，不碰任何 UI**（不知道 Button / Label 的存在）。
## 它只回答三类问题，全部通过既有系统的入口（本类不自己算数）：
##   1. 这台"许愿机"（= 设备）长什么样：名字 / 等级 / 本级两条效果 / 原石 / 升级价；
##   2. 升级：走 `DeviceService.upgrade_device()`（价格问 `upgrade_cost()`，扣费与门槛都在 04）；
##   3. 开盒（**单次 / N 连**）：走 `DeviceService.redeem()`，逐次累计结果。
##
## 纪律：不读档、不写档、不改 `GameState` / `ItemService` 的写入（`11-flow.md` §2）。
class_name WishMachineModel
extends RefCounted

var state: GameState = null

## 开 N 连时，若中途失败（寿命耗尽 / 原石不足 / 盒子进邮件），停止并记下原因。
var open_result: String = ""


## 绑定这一局。View 用 `snapshot()` 拉取展示数据。
func bind(s: GameState) -> void:
	state = s


## 只读快照：**View 唯一的数据来源**（Model 算好，View 只渲染）。
## ★ v0.31：`box_index` 是当前选中的盒子下标；有效时额外给"剩余开盒次数"与"数学期望 M̄"。
func snapshot(box_index: int = -1) -> Dictionary:
	var dev: Device = null if state == null else DeviceService.primary_device(state)
	var boxes: Array = [] if state == null else state.boxes_in(ItemConstants.LOC_WAREHOUSE)

	if dev == null:
		return {
			"device_name": "还没有许愿机",
			"description": "开局应当发一台；若这里是空的，说明这一局没有建档",
			"level": "", "effect": "", "gem": "原石 0",
			"upgrade_text": "升级", "upgrade_disabled": true,
			"box_options": [] as Array[String],
			"open_disabled": true, "result": open_result,
			"box_uses": "剩余开盒次数 —", "box_expectation": "数学期望 M̄ —",
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
		effect = "可开套系品质 ≤ %d · 开盒成本 %d%%" % [
			spec.unlock_series_quality_max if spec != null else 0,
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
		opts.append("%s（寿命 %d）" % [String(b.box_id).substr(0, 8), b.uses_remaining])

	var stats := _box_stats(box_index, boxes)

	return {
		"device_name": name, "description": desc,
		"level": level_text, "effect": effect, "gem": gem,
		"upgrade_text": upgrade_text, "upgrade_disabled": upgrade_disabled,
		"box_options": opts, "open_disabled": boxes.size() == 0,
		"result": open_result,
		"box_uses": stats["uses"], "box_expectation": stats["expectation"],
	}


## ★ v0.31：选中盒子的"剩余开盒次数"与"数学期望 M̄"。
## 期望走 07 的 `EvalService`（**本类不自己算概率 / 求和**）：池子当前状态 → 求值 → `m_bar`。
func _box_stats(box_index: int, boxes: Array) -> Dictionary:
	var empty := {"uses": "剩余开盒次数 —", "expectation": "数学期望 M̄ —"}
	if box_index < 0 or box_index >= boxes.size():
		return empty
	var b: Box = boxes[box_index]
	var series := GachaCatalog.get_series(b.series_id)
	if series == null:
		return {"uses": "剩余开盒次数 %d" % b.uses_remaining, "expectation": "数学期望 M̄ —"}
	var ps := PoolService.get_pool_state(state, b.box_id)
	var ev := EvalService.evaluate_pool(ps, series)
	var m := EvalService.m_bar(ev, series)
	return {
		"uses": "剩余开盒次数 %d" % b.uses_remaining,
		"expectation": "数学期望 M̄ ≈ %.2f" % m,
	}


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
## 逐次走 04 的入口；中途失败即停，并把已开出 / void 的计数汇总成一句话。
func open(times: int, box_index: int) -> void:
	if state == null:
		open_result = "尚未开局"
		return
	var boxes: Array = state.boxes_in(ItemConstants.LOC_WAREHOUSE)
	if box_index < 0 or box_index >= boxes.size():
		open_result = "请先选择要开的盲盒"
		return
	var box: Box = boxes[box_index]

	var hit: Array[String] = []
	var voids := 0
	var mailed := 0
	var opened := 0
	for _i in times:
		var r := DeviceService.redeem(state, box)
		if not r.ok:
			if opened > 0:
				open_result = "%d 连开到第 %d 次失败：%s（已开 %d 次%s）" % [
					times, opened + 1, String(r.error), opened,
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
			var name := "%s（%s）" % [
				d.display_name if d != null else String(r.item_id),
				ItemConstants.quality_name(d.quality if d != null else 1),
			]
			# ★ v0.38：**落位可感知**——仓库放不下 ⇒ 进邮件。文案要说得出来（P5：产出永不丢失，
			#   但玩家得知道它去哪了，否则"东西凭空消失"的错觉比真丢还糟）。
			if r.mailed:
				mailed += 1
				hit.append("%s → 邮件" % name)
			else:
				hit.append(name)

	var head := "开出：" if times == 1 else "%d 连开出 %d 件：" % [times, hit.size()]
	var tail := "" if voids == 0 else "、void %d 次" % voids
	if mailed > 0:
		tail += "、%d 件存入邮件" % mailed
	open_result = head + ("、".join(hit) if hit.size() > 0 else "什么都没有") + tail

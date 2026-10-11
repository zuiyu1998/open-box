## 设备系统的薄入口（04-device.md §1 / §5 / §8；核心 §4.4 / §15 D23）。
##
## ★ **设备负责三件事**：**① 开启盲盒（该盒 1 次寿命 ＋ 原石）② 镶嵌模块（该盒 1 次寿命 ＋ 该模块的金币）
##   ③ 设备升级（原石）**。本类**是前两件事的入口发起方**，第三件事只有本类做。
##
## ★ **本层只做"校验 + 计价 + 转发"**：
##   · **不写池子数据**（`PoolService` 是唯一写入方）；
##   · **不写资源余额**（`ItemService` 是唯一写入方）——本类只**读余额做预检**、只**发起**扣除；
##   · **不写实例列表、不改寿命**（寿命归 `01` / `GameState.spend_use`）；
##   · **不构造求值、不调 `roll()`**。
##
## ★ **两份判定、同一份数据**（核心 §5.3 / D21 的回滚点）：
##   `has_device(state)`（无参，**镶嵌侧**）与 `can_open(state, box)`（带盒子，**开盒侧**，含等级门控）。
##   **实现只有一处**（本类），`01` 侧的两条入口调同一个事实做兜底。
##
## ★ **门槛与门控都不得加宽**：等级门控**只作用于开盒**——镶嵌不看等级，拆卸（`01` 侧）
##   既不看等级也不看设备（核心 §4.4 的裁定⑪）。
##
## ★ 本类是**静态类**（与 `GachaService` / `PoolService` 同型）：它不持有任何状态，
##   全部事实来自 `GameState` / `DeviceCatalog` / `ItemService`。故**不需要注册 autoload**。
class_name DeviceService
extends RefCounted

# ── 拒绝原因码（与 02 / 01 的同一枚码同名同义）────────────────────────────────────
const R_OK := &""
const R_NO_DEVICE := &"no_device"
## 该设备等级开不了这个套系（准入）
const R_DEVICE_LEVEL_LOW := &"device_level_low"
## 资源不足（开盒 / 升级 ⇒ 原石；镶嵌 ⇒ 金币）——**一枚码，币种由动作决定**
const R_CURRENCY_INSUFFICIENT := &"currency_insufficient"
const R_DEVICE_MAX_LEVEL := &"device_max_level"
const R_UNKNOWN_DEVICE := &"unknown_device"
const R_UNKNOWN_MODULE := &"unknown_module"
const R_BOX_NOT_FOUND := &"box_not_found"
const R_NO_DEVICE_DEF := &"no_device_def"


# ══════════════════════════════════════════════════════════════════════════════
#  两份判定（核心 §4.4；D21 的可回滚默认在此被"等级门控"触发）
# ══════════════════════════════════════════════════════════════════════════════

## **镶嵌侧**的判定：**"持有至少一台设备"**（无参，D21 的语义原样保留）。
## ★ 本函数**不**要求等级、**不**看盒子——镶嵌与设备绑定的唯一事实就是"有没有"。
static func has_device(state: GameState) -> bool:
	return state != null and not state.devices.is_empty()


## **开盒侧**的判定：**"有一台设备的等级能开这个盒子"**。
##
## 比较对象 = **该盒所属套系的品质**（`series_quality`）vs **设备等级的准入上限**。
## ★ 这一条就是 D21 预写的回滚点：判定从此**必须知道"是哪个盒子"**（故签名带 `box`）。
static func can_open(state: GameState, box: Box) -> bool:
	return _device_for_open(state, box) != null


## 选定**用来开这个盒子的那一台**（判定与计价的唯一实现，避免两处各挑一次）。
##
## 规则（`[补充]`，核心只写"存在一台满足条件的"）：
##   · 只考虑**该盒套系品质 ≤ 该级准入上限**的设备；
##   · 多台都满足时取**开盒折扣最优（`open_cost_bp` 最小）**的那一台，**同价则取 `level` 最高**、
##     再同则取**持有顺序在前**的——**确定性**，不依赖字典 / 容器遍历顺序。
##   · 没有任何一台满足 ⇒ 返回 null（调用方据此报 `no_device` / `device_level_low`）。
static func _device_for_open(state: GameState, box: Box) -> Device:
	if state == null or box == null:
		return null
	var q := series_quality_of(box)
	if q <= 0:
		return null
	var best: Device = null
	var best_bp := 0
	for d in state.devices:
		if d == null:
			continue
		var def := DeviceCatalog.get_device(d.device_id)
		if def == null:
			continue
		if def.unlock_series_quality_max(d.level) < q:
			continue
		var bp := def.open_cost_bp(d.level)
		if best == null or bp < best_bp or (bp == best_bp and d.level > best.level):
			best = d
			best_bp = bp
	return best


## 该盒所属套系的品质（0 = 套系解析不到 ⇒ 一律拒绝，不猜）。
static func series_quality_of(box: Box) -> int:
	if box == null:
		return 0
	var series := GachaCatalog.get_series(box.series_id)
	return series.series_quality if series != null else 0


# ══════════════════════════════════════════════════════════════════════════════
#  职责一：开启盲盒（校验 + 计价 + 转发；核心 §4.4 / §4.8）
# ══════════════════════════════════════════════════════════════════════════════

## **本次开盒要花的原石**（唯一计价口径，整数）：
##
##     gem_cost = floori( SeriesDef.gem_cost × open_cost_bp(设备等级) / 10000 )
##
## · **基准归 01 的内容配置**（`SeriesDef.gem_cost`）、**折扣归 04 的等级曲线**；
## · **一律 `floori`**（与 02 / 06 的取整纪律一致）；结果恒 ≥ 0（`bp = 0` ⇒ 免费）；
## · **无设备 / 等级不足 / 套系解析不到 ⇒ 返回 -1**（调用方先看 `can_open`，
##   这个 -1 只是"不该被用来计价"的响亮信号，**不得**当成 0 用）。
static func open_cost(state: GameState, box: Box) -> int:
	var d := _device_for_open(state, box)
	if d == null:
		return -1
	var series := GachaCatalog.get_series(box.series_id)
	if series == null:
		return -1
	var def := DeviceCatalog.get_device(d.device_id)
	if def == null:
		return -1
	return floori(float(series.gem_cost) * float(def.open_cost_bp(d.level)) / 10000.0)


## **开盒入口**：链首校验（有设备 / 等级够 / 原石够）⇒ 把成本交给 `01` 执行。
##
## ★ 校验顺序**写死**（全部在事务之前），任一失败 ⇒ 响亮拒绝、**逐项不变**
##   （不扣原石、不扣寿命、不推进 `draw_index`）：
##   ① 盒子存在（`box_not_found`）② 有设备（`no_device`）③ 等级够（`device_level_low`）
##   ④ 原石够（`currency_insufficient`）。
static func redeem(state: GameState, box: Box, seed_override: int = -1) -> GachaResult:
	if state == null or box == null or not state.has_box(box.box_id):
		return GachaResult.failure(R_BOX_NOT_FOUND)
	if not has_device(state):
		return GachaResult.failure(R_NO_DEVICE)
	if not can_open(state, box):
		# 有设备但等级不够 / 套系解析不到：两种情形分开报，便于 UI 给"直达升级"的下一跳
		var q := series_quality_of(box)
		if q > 0:
			return GachaResult.failure(R_DEVICE_LEVEL_LOW)
		return GachaResult.failure(R_NO_DEVICE_DEF)
	var cost := open_cost(state, box)
	if cost < 0:
		return GachaResult.failure(R_DEVICE_LEVEL_LOW)
	if ItemService.currency_balance(ItemConstants.CURRENCY_GEM) < cost:
		return GachaResult.failure(R_CURRENCY_INSUFFICIENT)
	# 转发：成本由本类算好，`01` 只负责"扣 + 抽 + 产 + 扣寿命"（一次事务）
	return GachaService.redeem(state, box, cost, seed_override)


## **批量开盒入口**：逐盒计价（等级按各自盒子的套系判定），整批预检后转发。
static func redeem_batch(
	state: GameState,
	boxes: Array,
	k: int,
	seed_overrides: Array = []
) -> Array[GachaResult]:
	if state == null:
		var bad: Array[GachaResult] = []
		for _i in maxi(k, 0):
			bad.append(GachaResult.failure(R_BOX_NOT_FOUND))
		return bad
	if k <= 0:
		return [] as Array[GachaResult]
	if not has_device(state):
		return _batch_failure(k, R_NO_DEVICE)
	# ① 逐盒判等级（任一盒不合格 ⇒ 整批拒绝，不消耗任何东西）
	var costs: Array = []
	for i in boxes.size():
		var b := boxes[i] as Box
		if b == null or not state.has_box(b.box_id):
			return _batch_failure(k, R_BOX_NOT_FOUND)
		if not can_open(state, b):
			return _batch_failure(k, R_DEVICE_LEVEL_LOW)
		costs.append(open_cost(state, b))
	# ② 整批总成本（按提交顺序复刻"逐盒消耗、用尽接下一盒"）
	var total := 0
	var left := k
	for i in boxes.size():
		if left <= 0:
			break
		var b2 := boxes[i] as Box
		var take := mini(maxi(b2.uses_remaining, 0), left)
		if take <= 0:
			continue
		total += maxi(int(costs[i]), 0) * take
		left -= take
	if ItemService.currency_balance(ItemConstants.CURRENCY_GEM) < total:
		return _batch_failure(k, R_CURRENCY_INSUFFICIENT)
	# ③ 转发（逐次调用都走本类的单次入口，因此每一笔单独成事务）
	return GachaService.redeem_batch(state, boxes, costs, k, seed_overrides)


static func _batch_failure(k: int, reason: StringName) -> Array[GachaResult]:
	var out: Array[GachaResult] = []
	for _i in k:
		out.append(GachaResult.failure(reason))
	return out


# ══════════════════════════════════════════════════════════════════════════════
#  职责二：镶嵌模块（核心 §4.5；成本 = 该模块的金币）
# ══════════════════════════════════════════════════════════════════════════════

## **镶嵌入口**（空位）：校验"有设备" ＋ "金币够" ⇒ 转发 `PoolService.socket()`。
##
## ★ **成本 = 该模块的 `ModuleDef.gold_cost`**（数额完全由模块字段决定；`01` / `02` 在那里扣）。
## ★ **镶嵌不看设备等级、也不花原石**（等级门控只作用于开盒）。
## ★ **替换请用 `replace()`**——`socket()` 遇到占用位一律 `slot_occupied`（不做隐式覆盖）。
static func socket(
	state: GameState,
	box_id: String,
	module_id: StringName,
	slot: int
) -> Dictionary:
	var gate := _module_gate(state, module_id)
	if gate["ok"] != true:
		return gate
	return PoolService.socket(state, box_id, module_id, slot)


## **替换入口**：**替换 = 拆卸 + 重新镶嵌**（本文件与核心 §3.3 的唯一定义）。
##
## · 语义上由**本类编排**（先 `unsocket` 再 `socket`），两次都是 `01` 的入口；
## · **拆卸什么都不返还**（金币不退、也没有物品可退，核心 §15 D8）⇒ 玩家**再付一次新模块的金币**
##   且**再扣 1 次寿命**（`m` 是历史累计）；
## · 任一步失败 ⇒ 立刻返回该步的失败（**不做"回滚半个替换"**：`unsocket` 成功而 `socket` 失败时，
##   盘面是"位子被拆空"——这与"拆卸是一个独立合法动作"一致，UI 必须先确认再调用）。
static func replace(
	state: GameState,
	box_id: String,
	module_id: StringName,
	slot: int
) -> Dictionary:
	var gate := _module_gate(state, module_id)
	if gate["ok"] != true:
		return gate
	var off := PoolService.unsocket(state, box_id, slot)
	if off["ok"] != true:
		return off
	return PoolService.socket(state, box_id, module_id, slot)


## 镶嵌侧的共同前置：**有设备 ／ 模块已注册 ／ 金币够**（三条都在任何写入之前）。
static func _module_gate(state: GameState, module_id: StringName) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": R_BOX_NOT_FOUND, "state": null, "errors": [] as Array[String]}
	if not has_device(state):
		return {"ok": false, "reason": R_NO_DEVICE, "state": null, "errors": [] as Array[String]}
	var mdef := GachaCatalog.get_module(module_id)
	if mdef == null:
		return {"ok": false, "reason": R_UNKNOWN_MODULE, "state": null, "errors": [] as Array[String]}
	if ItemService.currency_balance(ItemConstants.CURRENCY_GOLD) < mdef.gold_cost:
		return {
			"ok": false, "reason": R_CURRENCY_INSUFFICIENT,
			"state": null, "errors": [] as Array[String],
		}
	return {"ok": true, "reason": R_OK, "state": null, "errors": [] as Array[String]}


# ══════════════════════════════════════════════════════════════════════════════
#  职责三：设备升级（核心 §4.4 / §15 D24；消耗原石）
# ══════════════════════════════════════════════════════════════════════════════

## **升级价格**（原石）：满级 / 未知名设备 ⇒ -1。
static func upgrade_cost(state: GameState, device_id: StringName) -> int:
	var d := find_device(state, device_id)
	if d == null:
		return -1
	var def := DeviceCatalog.get_device(d.device_id)
	if def == null:
		return -1
	return def.upgrade_cost_to_next(d.level)


## **升级入口**：消耗原石、等级 +1、上限 = `levels.size()`。
##
## ★ **升级不消耗设备本体**（D21 不变）：只改 `level` 一个整数 ⇒ `devices` 集合不变、id 不变；
## ★ **升级不产生任何实例 / 池子 / 寿命变更**——它是"资源 → 准入 + 效率"的兑换；
## ★ **升级不受等级门控**（否则会形成"升不上去也开不了"的死结）：只看原石够不够 + 是否满级；
## ★ **新档立刻生效**：下一次开盒即用新的折扣与准入。
static func upgrade_device(state: GameState, device_id: StringName) -> Dictionary:
	if state == null:
		return _result(false, R_UNKNOWN_DEVICE)
	# ★ 链首：**先看"有没有设备"**（与开盒 / 镶嵌同一顺序，§5.7）——
	#   否则"没有设备"会被报成"没有这台设备"，而两者对 UI 的下一跳完全不同。
	if not has_device(state):
		return _result(false, R_NO_DEVICE)
	var d := find_device(state, device_id)
	if d == null:
		return _result(false, R_UNKNOWN_DEVICE)
	var def := DeviceCatalog.get_device(d.device_id)
	if def == null:
		return _result(false, R_NO_DEVICE_DEF)
	var price := def.upgrade_cost_to_next(d.level)
	if price < 0:
		return _result(false, R_DEVICE_MAX_LEVEL)
	if ItemService.currency_balance(ItemConstants.CURRENCY_GEM) < price:
		return _result(false, R_CURRENCY_INSUFFICIENT)
	if price > 0:
		# 资源侧的唯一写入方是 02：本类只发起这一次事务
		var pay := ItemService.transact([
			{
				"op": ItemConstants.OP_CURRENCY,
				"kind": ItemConstants.CURRENCY_GEM,
				"delta": -price,
			},
		])
		if not pay["ok"]:
			return _result(false, StringName(pay["reason"]))
	d.level += 1
	return _result(true, R_OK)


## 按 id 找持有中的那一台（找不到 ⇒ null）。
static func find_device(state: GameState, device_id: StringName) -> Device:
	if state == null or device_id == &"":
		return null
	for d in state.devices:
		if d != null and d.device_id == device_id:
			return d
	return null


## 持有中的第一台（UI 的默认展示对象；`[补充]`——判定本身是"至少一台"，不依赖顺序）。
static func primary_device(state: GameState) -> Device:
	if state == null:
		return null
	for d in state.devices:
		if d != null:
			return d
	return null


static func _result(ok: bool, reason: StringName) -> Dictionary:
	return {"ok": ok, "reason": reason}

## 抽取服务（01-gacha.md §1 / §4.4 / §5.5 / §5.6 / §7 B）——**盲盒系统的抽取侧**。
##
## ★ `roll()` 是**纯函数**：给定同一 `evaluation` 与 `seed`，输出永远相同，
##   **不存在任何跨次累计的状态**（v0.11：入参里没有保底计数器——保底已删除）。
##   它**不产生实例、不消耗使用次数**：那是 `redeem()` 的事（§10.2 的 I2：
##   "抽取侧无实例化"——`roll()` 前后实例列表逐字段不变、`grant` 一次都不被调用）。
##
## ★ **`roll()` 中没有 UUID 生成、没有 `serial` 计算**：
##   两者都只在 02 的 `grant` 内部发生，本文件只**发起请求**。
##
## ★ **v0.14：一次兑现 = 消耗一次使用（`Box.uses_remaining`），不是消耗整个盒子。**
##   · 只有 `uses_remaining` 归 0 时，盒子才连同它的 `modules` 从囤积清单消失；
##   · 两次使用之间**可以继续编辑池子**，编辑只影响**之后**的抽取
##     ⇒ `pool_snapshot` **每次抽取各取一份**（绝不复用上一份）；
##   · `draw_index` 每次抽取 +1（它现在**与盒子不再一一对应**）。
class_name GachaService
extends RefCounted

const R_OK := &""
const R_BOX_NOT_FOUND := &"box_not_found"
const R_BAD_SERIES := &"bad_series"
const R_POOL_INVALID := &"pool_invalid"
const R_EVAL_FAILED := &"eval_failed"
const R_BAD_EVALUATION := &"bad_evaluation"
const R_ITEM_NOT_REGISTERED := &"item_not_registered"
const R_GRANT_FAILED := &"grant_failed"
## v0.14：该盒（或本批盒子）的可开次数不足以完成这次结算
const R_USES_EXHAUSTED := &"uses_exhausted"
## v0.14 裁决：**没有设备就不能开盒**（设备是硬门槛；与 01 的装配侧同一个码）
const R_NO_DEVICE := &"no_device"

## 兑现种子的发生器。**seed 在兑现时刻生成并记录**（不预生成于盒子获得时：
## "盒子先拿到手、池子之后才配置"要求 seed 与**兑现那一刻的池子快照**成对生成）。
## 测试用 `redeem(..., seed_override)` 注入确定值。
static var _seed_rng: RandomNumberGenerator = null


# ══════════════════════════════════════════════════════════════════════════════
#  盒子的获得
# ══════════════════════════════════════════════════════════════════════════════

## 发放盲盒（01 §1 第 2 条 / §5.5）：生成 `box_id`、复制基础池为 `item_pool`、
## 把 `modules` 填成**定长的空位数组**、按套系品质给出**初始使用次数**，并追加进囤积清单。
##
## **奖励发的盒子是「未配置」态**：`item_pool` = 该套系基础池的副本（**每个盒子各一份**）、
## `modules` = 全空位——**不是 null、不是"字段不存在"**（03 §5.5 的定义）。
##
## v0.14：`uses_remaining = SeriesDef.uses_per_box`（品质 1/2/3/4 → **10/15/20/25**，
## 即 `USES_PER_SOCKET ×` 镶嵌位数；该常量由 `SeriesDef.validate()` 与品质曲线对齐）。
## ★ v0.16 数值裁决：寿命预算**远远超过**镶嵌次数 ⇒ 预算**不等于位数**（位数仍是 2/3/4/5；
## 旧曲线 2/3/4/5 已作废）——**"装满位子即烧光预算"不再是可发生路径**。
static func grant_box(
	state: GameState,
	series_id: StringName,
	count: int,
	source: StringName = &""
) -> Array[Box]:
	var out: Array[Box] = []
	if state == null:
		return out
	var series := GachaCatalog.get_series(series_id)
	if series == null:
		push_error("GachaService.grant_box: 未知 series_id `%s`" % series_id)
		return out
	for _i in maxi(count, 0):
		var b := Box.new()
		b.box_id = Uuid.v4()                      # 身份：Uuid.v4()，String，与 instance_id 同类型
		b.series_id = series_id
		b.item_pool = PoolService.init_pool(state, b.box_id, series_id)
		if b.item_pool == null:
			push_error("GachaService.grant_box: init_pool 失败，停止发放")
			break
		b.modules = PoolService.empty_slots(series.socket_count)
		b.uses_remaining = series.uses_per_box    # ★ v0.14：初始使用次数（按套系品质）
		b.source = source
		b.acquired_tick = int(Time.get_ticks_msec())
		state.add_box(b)
		out.append(b)
	return out


# ══════════════════════════════════════════════════════════════════════════════
#  抽取（纯函数）
# ══════════════════════════════════════════════════════════════════════════════

## 抽取判定（01 §5.6）。**纯函数**：只读出结果，不产生任何副作用。
##
## 抽样规格（§5.6 的 `[补充]`，逐条照做）：
## · 抽样空间 = `evaluation.probs`（**全部物品**）**加上 `void_prob`**，总和恒为 1.0；
## · **物品序 = 全部物品的固定数组顺序**（`SeriesDef.regular_items`；v0.13 起其后不再接隐藏物品）
##   → **再接 `void`**（`void` 段区间位置固定，置于物品序末尾）；
## · **禁用字典遍历顺序**；`RandomNumberGenerator` **必须显式赋 `seed`**，
##   **禁用全局 `randi()` / `randf()`**；
## · 算法 = 累计概率 + 线性查找（固定顺序 ⇒ 跨平台可复现）。
##
## 抽中 `void`：`is_void = true`、`item_id = &""`、`quality = 0`、`is_new = false`、
## **不产生任何物品与实例**，但**仍消耗一次使用**（v0.14；v0.13 及以前是消耗一个盒子）、
## **不推进任何计数器**——因此 `void` 也没有落点（不入库、不进邮件）。
static func roll(evaluation: EvalService.PoolEvaluation, seed: int) -> GachaResult:
	if evaluation == null:
		return GachaResult.failure(R_BAD_EVALUATION)
	if evaluation.probs.size() == 0 or evaluation.probs.size() != evaluation.item_ids.size():
		return GachaResult.failure(R_BAD_EVALUATION)
	if not evaluation.is_normalized:
		# 分布不自洽（C1 不成立）⇒ 响亮拒绝，不抽一个"看起来合理"的结果
		return GachaResult.failure(R_BAD_EVALUATION)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var u := rng.randf()                          # [0.0, 1.0)

	var acc := 0.0
	for i in evaluation.probs.size():
		acc += evaluation.probs[i]
		if u < acc:
			var item_id := evaluation.item_ids[i]
			var def := ItemCatalog.get_def(item_id)
			if def == null:
				return GachaResult.failure(R_ITEM_NOT_REGISTERED)
			var r := GachaResult.new()
			r.item_id = item_id
			r.quality = def.quality
			r.is_void = false
			r.probability = evaluation.probs[i]
			r.seed = seed
			return r

	# void 段：固定在物品序末尾
	acc += evaluation.void_prob
	if u < acc:
		return GachaResult.make_void(seed, 0, evaluation.void_prob)

	# 浮点兜底（理论上不可达）：`void_prob == 0` 时落回最后一个**可产出**物品。
	for i in range(evaluation.probs.size() - 1, -1, -1):
		if evaluation.probs[i] > 0.0:
			var def2 := ItemCatalog.get_def(evaluation.item_ids[i])
			if def2 == null:
				return GachaResult.failure(R_ITEM_NOT_REGISTERED)
			var r2 := GachaResult.new()
			r2.item_id = evaluation.item_ids[i]
			r2.quality = def2.quality
			r2.probability = evaluation.probs[i]
			r2.seed = seed
			return r2
	return GachaResult.failure(R_BAD_EVALUATION)


# ══════════════════════════════════════════════════════════════════════════════
#  兑现（v0.14：消耗一次使用 + 产生实例）
# ══════════════════════════════════════════════════════════════════════════════

## 兑现**一次使用**：求该盒当前状态 → 07 求值 → `roll()` → 产出实例 → 扣一次 `uses_remaining`。
##
## · **★ v0.14 裁决：设备是硬门槛**——`state.has_device() == false` ⇒ 拒绝 `no_device`，
##   **不消耗任何一次寿命、不推进 `draw_index`**；
## · **每次调用只扣 1 次使用**（v0.14：与"装模块"**共用同一个计数器**）；
##   `uses_remaining` 归 0 ⇒ **归零即摧毁**（盒子连同 `modules` 一起从 `pending_boxes` 移除，
##   **不存在"用尽才消耗"的缓冲**）；
## · **校验失败 ⇒ 一次使用都不消耗、不发物品**（§7 B 的拒绝分支，v0.14 沿用同一条纪律）；
## · `pool_snapshot` **每次抽取各取一份**（两次之间池子可能已被编辑，绝不复用上一份）；
## · `seed` 在**兑现时刻**生成（或用 `seed_override` 注入）；
## · `draw_index` 每次抽取 +1（**与盒子不再一一对应**：一个盒子可以贡献多次抽取）；
## · 抽中 `void` 仍然消耗一次使用，只是不产生任何实例。
##
## `[补充]` `seed_override`：文档没有这个参数，是测试与重放需要的确定性入口（`-1` = 自行生成）。
## `[补充]` 提交阶段若 `grant` 意外失败（正常路径不可能），`draw_index` 已经推进且不回退——
## 序号**不复用**（与 02 的 `serial` 同一纪律：宁可跳号，不可复用）。
static func redeem(state: GameState, box: Box, seed_override: int = -1) -> GachaResult:
	# ── 校验阶段：任何失败都**不得消耗使用次数、不得推进 draw_index** ──────────────
	if state == null or box == null:
		return GachaResult.failure(R_BOX_NOT_FOUND)
	if not state.has_box(box.box_id):
		return GachaResult.failure(R_BOX_NOT_FOUND)
	if not state.has_device():
		# ★ v0.14 裁决：**设备是硬门槛**——没有设备就不能开盒（也不消耗任何一次寿命）
		return GachaResult.failure(R_NO_DEVICE)
	if box.uses_remaining <= 0:
		return GachaResult.failure(R_USES_EXHAUSTED)
	var series := GachaCatalog.get_series(box.series_id)
	if series == null:
		return GachaResult.failure(R_BAD_SERIES)
	var ps := PoolService.get_pool_state(state, box.box_id)
	if ps == null:
		return GachaResult.failure(R_POOL_INVALID)
	var ev := EvalService.evaluate_pool(ps, series)
	if ev == null:
		return GachaResult.failure(R_EVAL_FAILED)

	var seed := seed_override if seed_override >= 0 else _new_seed()
	var r := roll(ev, seed)
	if not r.ok:
		return r
	if not r.is_void and ItemCatalog.get_def(r.item_id) == null:
		# 配置错误不该吃掉玩家的一次使用
		return GachaResult.failure(R_ITEM_NOT_REGISTERED)

	# ── 提交阶段 ────────────────────────────────────────────────────────────────
	r.series_id = box.series_id
	r.box_id = box.box_id
	r.seed = seed
	r.draw_index = state.next_draw_index()
	# ★ 快照取自**这一次**的池子状态（两次之间可能已被编辑 ⇒ 每次各一份）
	r.pool_snapshot = snapshot_of(ps)

	if not r.is_void:
		# `is_new` = 收藏口径（**不驱动任何计数器**）
		r.is_new = not EvalService.is_collected(r.item_id)
		# 产出实例：**恰好一次** `grant`；`kind = &"gacha"` ⇒ 被动产出 ⇒ 放不下进邮件
		var src := r.to_source()
		src["kind"] = ItemConstants.KIND_GACHA    # 02 §5.2：source.kind 必填（01 §10.2 断言这条形状）
		var inst := ItemService.grant(r.item_id, src)
		if inst == null:
			return GachaResult.failure(R_GRANT_FAILED)

	# ★ v0.14：**成功兑现消耗一次使用**（与装模块**共用同一个计数器**）；**归零即摧毁盒子**
	var destroyed := state.spend_use(box)
	if destroyed:
		PoolService.drop_cached_state(box.box_id)   # 盒子没了：清掉它的派生状态缓存
	return r


## 批量兑现（v0.14：**`k` = 本次结算的使用次数**，不再是盒子数）。
##
## 盒子按给定顺序逐个消耗：一个盒子的次数用尽后自动接到下一个盒子，
## 因此**一次批量兑现可以跨多个盒子**（`k == 5` 完全可能是 2 个盒子）。
##
## `[补充]` **全部预校验后再逐个提交**（03 §5.2 的同一纪律：不做"半批已开、后面失败"）：
## 预校验不通过（**无设备** / 盒子不在清单 / 套系不可解析 / **可用次数 < k**）⇒ 返回 **k 条失败结果**，
## **不消耗任何次数、不推进 `draw_index`**。`results.size() == k` 恒成立，便于对账。
static func redeem_batch(state: GameState, boxes: Array, k: int, seed_overrides: Array = []) -> Array[GachaResult]:
	var out: Array[GachaResult] = []
	if k <= 0:
		return out
	var reason := R_OK
	if state == null:
		reason = R_BOX_NOT_FOUND
	elif not state.has_device():
		# ★ v0.14 裁决：无设备 ⇒ **整批被拒**（不消耗任何一次寿命、不推进 draw_index）
		reason = R_NO_DEVICE
	else:
		var available := 0
		for b in boxes:
			var bx := b as Box
			if bx == null or not state.has_box(bx.box_id):
				reason = R_BOX_NOT_FOUND
			elif GachaCatalog.get_series(bx.series_id) == null:
				reason = R_BAD_SERIES
			else:
				available += maxi(bx.uses_remaining, 0)
		if reason == R_OK and available < k:
			reason = R_USES_EXHAUSTED
	if reason != R_OK:
		for _i in k:
			out.append(GachaResult.failure(reason))
		return out

	# 提交：按盒子顺序逐次消耗，直到结算完 k 次
	var remaining := k
	var i := 0
	for b in boxes:
		if remaining <= 0:
			break
		var bx := b as Box
		while remaining > 0 and bx.uses_remaining > 0:
			var override := -1
			if i < seed_overrides.size():
				override = int(seed_overrides[i])
			var r := redeem(state, bx, override)
			out.append(r)
			i += 1
			remaining -= 1
			if not r.ok:
				remaining = 0        # 提交阶段失败：立刻停，不吞错、不再继续消耗
				break
	# 提交阶段意外中断 ⇒ 补齐失败结果，保持 results.size() == k 的对账不变量
	while out.size() < k:
		out.append(GachaResult.failure(R_USES_EXHAUSTED))
	return out


# ══════════════════════════════════════════════════════════════════════════════
#  快照与日志
# ══════════════════════════════════════════════════════════════════════════════

## 池子快照（v0.14）：**每次抽取各取一份**。
##
## 内容 = 该次抽取所用的**整数权重** + `void_mass_bp` + 身份 / 修订号。
## 存整数权重而不是浮点 `probs`：概率是派生值，快照留规范形态才不产生第二份事实来源。
## `weights_bp` 是**深拷贝**——改这份快照不得影响在跑的池子（反之亦然）。
static func snapshot_of(ps: PoolState) -> Dictionary:
	if ps == null:
		return {}
	return {
		"box_id": ps.box_id,
		"revision": ps.revision,
		"void_mass_bp": ps.void_mass_bp,
		"weights_bp": ps.weights_bp.duplicate(true),
	}


## 开箱日志条目（核心 §14.2.7 / 01 §4.4）。**键集逐字**：
## `{box_id, seed, series_id, pool_snapshot, item_id, quality, is_void}`。
##
## `[补充]` **持久化归 10**（存档格式、日志落盘时机）；本方法只保证形状与内容——
## `void` 以 `is_void = true` + 空 `item_id` 落盘，使"抽到空洞"可复现、可对账。
static func draw_log_entry(r: GachaResult) -> Dictionary:
	if r == null:
		return {}
	return {
		"box_id": r.box_id,
		"seed": r.seed,
		"series_id": String(r.series_id),
		"pool_snapshot": r.pool_snapshot.duplicate(true),
		"item_id": String(r.item_id),
		"quality": r.quality,
		"is_void": r.is_void,
	}


# ══════════════════════════════════════════════════════════════════════════════
#  小工具
# ══════════════════════════════════════════════════════════════════════════════

static func _new_seed() -> int:
	if _seed_rng == null:
		_seed_rng = RandomNumberGenerator.new()
		_seed_rng.randomize()
	return _seed_rng.randi()

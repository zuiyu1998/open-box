## 抽取服务（01-gacha.md §1 / §4.4 / §5.5 / §5.6 / §7 B）——**盲盒系统的抽取侧**。
##
## ★ `roll()` 是**纯函数**：给定同一 `evaluation` 与 `seed`，输出永远相同，
##   **不存在任何跨次累计的状态**（v0.11：入参里没有保底计数器——保底已删除）。
##   它**不产生实例、不消耗盒子**：那是 `redeem()` 的事（§10.2 的 I2：
##   "抽取侧无实例化"——`roll()` 前后实例列表逐字段不变、`grant` 一次都不被调用）。
##
## ★ **`roll()` 中没有 UUID 生成、没有 `serial` 计算**：
##   两者都只在 02 的 `grant` 内部发生，本文件只**发起请求**。
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

## 兑现种子的发生器。**seed 在兑现时刻生成并记录**（不预生成于盒子获得时：
## "盒子先拿到手、池子之后才配置"要求 seed 与**兑现那一刻的池子快照**成对生成）。
## 测试用 `redeem(..., seed_override)` 注入确定值。
static var _seed_rng: RandomNumberGenerator = null


# ══════════════════════════════════════════════════════════════════════════════
#  盒子的获得
# ══════════════════════════════════════════════════════════════════════════════

## 发放盲盒（01 §1 第 2 条 / §5.5）：生成 `box_id`、复制基础池为 `item_pool`、
## 把 `modules` 填成**定长的空位数组**，并追加进囤积清单。
##
## **奖励发的盒子是「未配置」态**：`item_pool` = 该套系基础池的副本（**每个盒子各一份**）、
## `modules` = 全空位——**不是 null、不是"字段不存在"**（03 §5.5 的定义）。
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
## **不产生任何物品与实例**，但**仍消耗一个 `Box`**、**不推进任何计数器**——
## 因此 `void` 也没有落点（不入库、不进邮件）。
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
#  兑现（消耗一个盒子 + 产生实例）
# ══════════════════════════════════════════════════════════════════════════════

## 兑现一个盲盒（01 §7 B）：求该盒当前状态 → 07 求值 → `roll()` → 产出实例 → 消耗盒子。
##
## · **校验失败 ⇒ 盲盒不消耗、不发物品**（§7 B 的拒绝分支）；
## · `seed` 由本方法在**兑现时刻**生成（或用 `seed_override` 注入）并记入结果与日志；
## · `draw_index` 取自**全局**计数器（跨批次 / 跨套系 / 跨载入不重置）；
## · 抽中 `void` 仍然**消耗这个盒子**，只是不产生任何实例。
##
## `[补充]` `seed_override`：文档没有这个参数。它是**测试与重放**需要的确定性入口
## （"存档载入后以同一 `seed` + 快照重放结果一致"这条验收项需要它）；`-1` = 按文档自行生成。
static func redeem(state: GameState, box: Box, seed_override: int = -1) -> GachaResult:
	if state == null or box == null:
		return GachaResult.failure(R_BOX_NOT_FOUND)
	if not state.has_box(box.box_id):
		return GachaResult.failure(R_BOX_NOT_FOUND)
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

	r.series_id = box.series_id
	r.box_id = box.box_id
	r.seed = seed
	r.draw_index = state.next_draw_index()

	if not r.is_void:
		# 先确认物品已注册（否则不消耗盒子——配置错误不该吃掉玩家的盲盒）
		if ItemCatalog.get_def(r.item_id) == null:
			return GachaResult.failure(R_ITEM_NOT_REGISTERED)
		# `is_new` = 收藏口径（**不驱动任何计数器**）
		r.is_new = not EvalService.is_collected(r.item_id)
		# 产出实例：**恰好一次** `grant`；`kind = &"gacha"` ⇒ 被动产出 ⇒ 放不下进邮件
		var src := r.to_source()
		src["kind"] = ItemConstants.KIND_GACHA    # 02 §5.2：source.kind 必填（01 §10.2 断言这条形状）
		var inst := ItemService.grant(r.item_id, src)
		if inst == null:
			return GachaResult.failure(R_GRANT_FAILED)

	state.remove_box(box.box_id)                  # 兑现 = 消费这个盒子（连同 item_pool 与 modules）
	return r


## 批量兑现（顺序确定；每个盒子各自生成 seed / 各自递增 `draw_index`）。
## `[补充]` **全部预校验后再逐个提交**（03 §5.2 的同一纪律：不做"半批已开、后面失败"）。
static func redeem_batch(state: GameState, boxes: Array, seed_overrides: Array = []) -> Array[GachaResult]:
	# 阶段一：全部预校验（不做"半批已开、后面失败"）
	var pre: Array[StringName] = []
	for b in boxes:
		if b == null or not state.has_box(b.box_id):
			pre.append(R_BOX_NOT_FOUND)
		elif GachaCatalog.get_series(b.series_id) == null:
			pre.append(R_BAD_SERIES)
		else:
			pre.append(R_OK)
	# 阶段二：逐个提交（顺序确定；每个盒子各自生成 seed、各自递增 draw_index）
	var out: Array[GachaResult] = []
	for i in boxes.size():
		if pre[i] != R_OK:
			out.append(GachaResult.failure(pre[i]))
			continue
		var override := -1
		if i < seed_overrides.size():
			override = int(seed_overrides[i])
		out.append(redeem(state, boxes[i], override))
	return out


# ══════════════════════════════════════════════════════════════════════════════
#  小工具
# ══════════════════════════════════════════════════════════════════════════════

static func _new_seed() -> int:
	if _seed_rng == null:
		_seed_rng = RandomNumberGenerator.new()
		_seed_rng.randomize()
	return _seed_rng.randi()

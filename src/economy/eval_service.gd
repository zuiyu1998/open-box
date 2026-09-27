## 求值服务（07-economy-rho.md §4 / §5.1）——**唯一求值方**。
##
## 职责边界（07 §2）：本系统**只做「归一化 + 统计量」**——从 05 的 `weights_bp` 出发，
## **绝不重新应用一次排除 / 提升 / 损耗**（那会双重应用，且结果是"静默错"：
## 算出来仍然看起来合理）。**本系统不读 `Box.modules`、不做编辑算术。**
##
## [!] **本轮只落地 01（盲盒系统）依赖的最小契约**：`evaluate_pool()` + `m_bar()` + `headline()`。
##     **ρ / σ / 归因（`attribution`）/ `d̄` / `b` 尚未实现**——它们依赖 03 的任务结构
##     （`d̄` 是任务需求向量的 TVU 折算、`b` 是任务奖励盒数），不在本轮范围内。
##     因此 `EvalResult` / `Headline` / `AttributionEntry` 暂不提供。
class_name EvalService
extends RefCounted

## 单池求值结果——`EvalService` 与 `GachaService` 共用的**唯一数据契约**（07 §4）。
class PoolEvaluation:
	extends RefCounted
	var probs: PackedFloat32Array = PackedFloat32Array()
	var void_prob: float = 0.0
	var is_normalized: bool = false
	var box_id: String = ""                        # 这份求值属于哪个盒子（类型 String，同 Box.box_id）
	var revision: int = 0                          # 求值时的 pool_state.revision（缓存校验用）
	var series_id: StringName = &""
	## `[补充-实现必需]` **物品 id 顺序**。
	##
	## 07 §4 原文的 `PoolEvaluation` 只有 `probs: PackedFloat32Array`，而
	## `GachaService.roll(evaluation, seed)` 的入参里**既没有 series 也没有 box**（§5.6 明文禁止），
	## 于是"下标 → `item_id`"的翻译无处可取。07 §5.1 已写明 `evaluate_pool(pool_state, series)`
	## 的 `series` **只用于物品清单（`probs` 的长度与顺序）的对齐**——把对齐结果随求值一起
	## 交出来，是让既有签名成立的最小改动。**该字段是否需要入文档、归宿在哪，请 07 的拥有者裁决。**
	var item_ids: Array[StringName] = []


## 收藏口径提供者：`Callable(item_id: StringName) -> bool`，由 **10**（`collected` 的拥有者）注入。
##
## **必须在求值时询问**（"未拥有"随进度变，不能烘进权重）；且**只认收藏口径**——
## 绝不能用仓库口径（玩家可以把实例压在邮件里，让同一物品永远算"未拥有"而刷到永久加成，
## 守护裁决 11 / 01 §5.2.1）。未注入时**按"全部已拥有"处理**（即不施加 ×1.5），
## 这是唯一安全的默认值：缺席不该被解释成"白送加成"。
static var is_collected_provider: Callable = Callable()

const TOTAL_BP := ItemPool.TOTAL_BP              # 10000：全部质量（含 void）


## 唯一的求值路径（07 §5.1 的 1 → 4 步）。**01 / 07 都必须调它**。
##
## ```
## 1. w[i] = pool_state.weights_bp[i]     # 输入是 05 已推出的当前权重；禁止在此重算
## 2. 未拥有物品 w[i] *= 1.5               # 规则归 01；判定源 = 收藏口径 collected
##    随后把物品按比例归一化回原总质量（★ 在**整数**上做，浮点只出现一次）
## 3. probs = w / 10000                    # ★ 全流程唯一的浮点入口
## 4. void_prob = pool_state.void_mass_bp / 10000
## ```
##
## ★ **第 3 步的分母口径**：07 §5.1 的原文写作 `probs = w / Σw`。本实现取
##   **分母 = 全部质量（`TOTAL_BP`，含 `void`）**，因为红线 C1 要求
##   "物品概率之和 + `void_prob` **恒为 100%**"——若按"物品自身之和"归一化，
##   `Σprobs` 会是 1.0 而 `void_prob` 另加，合计必然 **> 1**，C1 当场不成立
##   （`10-progression.md` 的 T5 与 01 的 T2 都按 `≤ 1.0` 断言）。
##   这也正是 §5.1 那句"**全部物品一起归一化**、不再有独立占 2% 不参与归一化的那一项"的读法。
##   **该读法需要 07 的拥有者确认**（原文措辞可两解）。
static func evaluate_pool(pool_state: PoolState, series: SeriesDef) -> PoolEvaluation:
	if pool_state == null or series == null:
		return null
	var ids := series.item_ids()
	if ids.is_empty():
		return null
	var ev := PoolEvaluation.new()
	ev.box_id = pool_state.box_id
	ev.revision = pool_state.revision
	ev.series_id = pool_state.series_id
	ev.item_ids = ids
	ev.void_prob = float(pool_state.void_mass_bp) / float(TOTAL_BP)

	# 1. 读权重（**不重算编辑算术**）
	var w: Dictionary = {}
	for id in ids:
		w[id] = pool_state.weight_of(id)

	# 2. 未拥有 ×1.5，然后按比例归一回原总质量
	var mass := BpAlloc.sum_of(w)
	var mult := series.unowned_weight_mult
	if is_collected_provider.is_valid() and mass > 0 and not is_equal_approx(mult, 1.0):
		var scaled: Dictionary = {}
		for id in ids:
			var factor := 1.0 if is_collected(id) else mult
			scaled[id] = roundi(float(w[id]) * factor)
		w = BpAlloc.allocate(scaled, ids, scaled, ids, mass)

	# 3 + 4. 唯一的浮点入口：probs = w / 全部质量（含 void）
	var probs := PackedFloat32Array()
	var s := 0.0
	for id in ids:
		var p := float(w[id]) / float(TOTAL_BP)
		probs.append(p)
		s += p
	ev.probs = probs
	ev.is_normalized = absf(s + ev.void_prob - 1.0) <= 1e-6
	return ev


## 「未拥有」判定（收藏口径）。未注入提供者 ⇒ 视为已拥有（不施加 ×1.5）。
static func is_collected(item_id: StringName) -> bool:
	if not is_collected_provider.is_valid():
		return true
	return bool(is_collected_provider.call(item_id))


## `m̄ = Σ (probs[i] × v_i)`（07 §5.2）——**void 的 `v = 0`，不贡献**。
## 求和范围是**概率分布**，与持有形态 / 位置无关（v0.8 / v0.9 的同一不变量）。
static func m_bar(ev: PoolEvaluation, series: SeriesDef) -> float:
	if ev == null or series == null:
		return 0.0
	var total := 0.0
	var defs := series.regular_items
	for i in mini(ev.probs.size(), defs.size()):
		var d := defs[i]
		if d == null:
			continue
		total += float(ev.probs[i]) * float(d.value)
	return total


## `headline` 的两个数字（01 §6 / 07 §4 的 `Headline`）。
## **候选集 = 该盒池中仍可产出的全部物品**（被排除项不算）——v0.13 无隐藏款；
## 同一套系的两个盒子可以有不同 `best_item`（某盒排除了原本的头奖）。
## 只返回这两个数字 + `ev`；`Headline` 类型的其余字段归 07 的后续落地。
static func headline(ev: PoolEvaluation, series: SeriesDef) -> Dictionary:
	var out := {"best_item_id": &"", "best_item_prob": 0.0, "ev": 0.0}
	if ev == null or series == null:
		return out
	var best_v := -1
	var best_i := -1
	var defs := series.regular_items
	for i in mini(ev.probs.size(), defs.size()):
		if ev.probs[i] <= 0.0:
			continue
		var d := defs[i]
		if d == null:
			continue
		if d.value > best_v:
			best_v = d.value
			best_i = i
	if best_i >= 0:
		out["best_item_id"] = defs[best_i].item_id
		out["best_item_prob"] = ev.probs[best_i]
	out["ev"] = m_bar(ev, series)
	return out

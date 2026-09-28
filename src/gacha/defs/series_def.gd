## 套系 / 基础池模板（01-gacha.md §4.1）。
##
## 每个 `Box` 从它**复制一份** `ItemPool`（`PoolService.init_pool`），此后该盒的池子
## 与这份模板再无写入关系——**模板是模板，池子是那个盒子自己的属性**（核心 §4.1.2）。
##
## ★ v0.13：池中**全部物品都是常规物品**（`hidden_item` / `HIDDEN_COUNT` 已删除），
##   红线 C3 随之作废。★ v0.12：**没有"基础权重表"字段**——权重由各 `ItemDef.rarity`
##   归一化**派生**（消灭第二份事实来源）。
@tool
class_name SeriesDef
extends Resource

## 默认套系品质（`series_quality` 的默认值）。
## v0.14：`uses_per_box` 的默认值**由它 + `USES_PER_SOCKET` 推出**，**不手写数字**。
const DEFAULT_SERIES_QUALITY := 2

## **寿命预算 ÷ 镶嵌位数**（预算 = 本值 × 位数）。
##
## ★ **它是平衡旋钮，不是实现细节**：预算正比于它 ⇒ `d = 预算 − 装模块数` 正比于它，
##   而"每次抽取摊到的模块成本" `C/d` **反比于它**。
##   ⇒ 改本值就等于**改 D17 的标定基线**（D17 是 P7 唯一的跨池锚点）。
const USES_PER_SOCKET := 5

@export var series_id: StringName = &""
@export var series_quality: int = DEFAULT_SERIES_QUALITY   # 套系品质 1..4（≠ 物品品质 quality）
@export var regular_count: int = 8               # 物品数：品质 1–2 → 8；品质 3–4 → 12
@export var regular_items: Array[ItemDef] = []   # 引用 02 的 ItemDef（含 rarity/value）；长度必须 == regular_count
@export var socket_count: int = 3                # 该套系的常量（C4）：品质 1–4 → 2/3/4/5
## **v0.14：每盒初始使用次数（寿命预算）**（品质 1/2/3/4 → **10/15/20/25**）。
##
## 与 `socket_count` **同一套品质曲线校验**：它是套系常量，
## 由品质唯一决定；单独配置会产生"品质与次数不匹配"的非法组合。
##
## ★ **数值裁决**：寿命预算**远远超过**镶嵌次数（"盲盒的使用次数远远超过镶嵌的次数"）⇒
##   预算**不再等于位数**（位数仍是 2/3/4/5；旧曲线 2/3/4/5 已作废）。
@export var uses_per_box: int = USES_PER_SOCKET * socket_curve(DEFAULT_SERIES_QUALITY)
## ↑ 默认值 = `USES_PER_SOCKET × socket_curve(DEFAULT_SERIES_QUALITY)`——**常量表达式，不手写 15**。
##   手写的那个 15 是同一个数的**第二份副本**：D3 曲线一改，默认 `SeriesDef` 一加载就报 `uses_curve`；
##   更坏的是有人为了让它通过而把默认值随手改成新数 ⇒ **曲线与默认值各说各话**。
@export var unowned_weight_mult: float = 1.5     # 未拥有物品权重倍率（判定源 = 收藏口径 collected）

## 前 4 位 = 前 2 项「位子/物品」比例必须落在核心 §4.1 / P7 的 25%–40% 区间，
## 否则高品质套系会被收敛（R2 从后门回来）；C6 的 ≥3 断言也将无从保证。
const SOCKET_RATIO_MIN := 0.25
const SOCKET_RATIO_MAX := 0.40


## 核心 §4.1.1 的套系品质表（01 §11 G7 逐档抄录）。品质 1–4 → 物品数。
static func expected_regular_count(p_series_quality: int) -> int:
	return 8 if p_series_quality <= 2 else 12


## **镶嵌位曲线（唯一权威实现）**：品质 1–4 → 2/3/4/5（核心 §4.1.1）。
##
## ★ 曲线**只在这一个地方推导**：`expected_socket_count()` 与 `expected_initial_uses()`
## 都从它取数，`SeriesDef.socket_count`（字段）由前者校验。
## 以此消灭"同一事实存两份"——否则 D3 那条曲线（本来就标着"待手感验证"）一改形状，
## 两处会**静默不一致**：`uses_curve` 校验照样通过，而位数与预算的关系已经错了。
static func socket_curve(p_series_quality: int) -> int:
	return clampi(p_series_quality + 1, 2, 5)


## 核心 §4.1.1：品质 1–4 → 镶嵌位数 2/3/4/5（= `socket_curve()`，不再各自推导）。
static func expected_socket_count(p_series_quality: int) -> int:
	return socket_curve(p_series_quality)


## **v0.14：品质 1–4 → 每盒初始使用次数（寿命预算）10/15/20/25**。
##
## ★ 数值裁决：寿命预算**远远大于**镶嵌次数 ⇒ 预算 = `USES_PER_SOCKET ×` 位数，
##   与镶嵌位曲线**同源**（都出自 `socket_curve()`），**不重推一遍曲线**。
##
## ★★ **D17 提醒（必须按这条新基线重新标定）**：预算就是"每次抽取摊模块成本"的分母来源——
##   设 `d = 预算 − 装模块数`，则 `d` 现在落在 **8–20**（品质 1：10 − 2；品质 4：25 − 5，
##   按"装模块数 = 位数"的上限计），而**不是**"预算 = 位数"情形下的 2–5。
##   ⇒ 摊到的模块成本 `C/d` 相比那一情形又降了约 `USES_PER_SOCKET` 倍。
##   D17（单个模块的物品成本）是 **P7 唯一的跨池锚点**：不按新基线重标，
##   跨池复制就会实质免费，**P7 名存实亡**。
static func expected_initial_uses(p_series_quality: int) -> int:
	return USES_PER_SOCKET * socket_curve(p_series_quality)


## C6：排除上限 = 常规物品数 − 3（`ban_limit = regular_count − 3`；品质 2 即 5）。
func ban_limit() -> int:
	return regular_count - 3


func item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for d in regular_items:
		if d != null:
			out.append(d.item_id)
	return out


## 配置校验（01 §4.1 的 `[补充]`，加载时执行）。返回空数组 = 合法。
##
## ① `regular_items.size() == regular_count`；② 每件物品 `rarity >= 1`；
## ③ `socket_count` / `regular_count` 与品质表一致，且 `socket_count / regular_count ∈ 25%–40%`。
##
## ★ v0.15：**不再有 `device_slot_count`**——装置是"往盒子里装模块 / 开盒的工具"，
##   既不带修正、也不绑定套系、也不限次（核心 §16.10 的 D4 行）⇒ **槽位没有任何对象**。
func validate() -> Array[String]:
	var problems: Array[String] = []
	if series_id == &"":
		problems.append("bad_series_id：series_id 为空")
	if series_quality < 1 or series_quality > 4:
		problems.append("bad_quality：series_quality = %d，必须落在 1..4" % series_quality)
	if regular_items.size() != regular_count:
		problems.append(
			"count_mismatch：regular_items 有 %d 项，regular_count = %d"
			% [regular_items.size(), regular_count]
		)
	if regular_count != expected_regular_count(series_quality):
		problems.append(
			"quality_curve：品质 %d 的物品数应为 %d，实配 %d（核心 §4.1.1）"
			% [series_quality, expected_regular_count(series_quality), regular_count]
		)
	if socket_count != expected_socket_count(series_quality):
		problems.append(
			"quality_curve：品质 %d 的镶嵌位数应为 %d，实配 %d（核心 §4.1.1）"
			% [series_quality, expected_socket_count(series_quality), socket_count]
		)
	# v0.14：使用次数也走同一套品质曲线校验（与 socket_count 同一处理）
	if uses_per_box != expected_initial_uses(series_quality):
		problems.append(
			"uses_curve：品质 %d 的初始使用次数应为 %d，实配 %d"
			% [series_quality, expected_initial_uses(series_quality), uses_per_box]
		)
	if uses_per_box <= 0:
		problems.append("bad_uses：uses_per_box 必须 >= 1（0 会让盒子一发放就被判定用尽）")
	var seen := {}
	for d in regular_items:
		if d == null:
			problems.append("null_item：regular_items 里存在 null")
			continue
		if d.rarity < 1:
			problems.append("bad_rarity：%s 的 rarity < 1（0 表示永不产出，是配置错误）" % d.item_id)
		if seen.has(d.item_id):
			problems.append("duplicate_item：%s 在同一套系里出现了两次" % d.item_id)
		seen[d.item_id] = true
	if regular_count > 0:
		var ratio := float(socket_count) / float(regular_count)
		if ratio < SOCKET_RATIO_MIN or ratio > SOCKET_RATIO_MAX:
			problems.append(
				"socket_ratio：socket_count/regular_count = %.3f，必须落在 %.2f–%.2f（P7 / R2）"
				% [ratio, SOCKET_RATIO_MIN, SOCKET_RATIO_MAX]
			)
	return problems

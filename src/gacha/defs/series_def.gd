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

@export var series_id: StringName = &""
@export var series_quality: int = 2              # 套系品质 1..4（≠ 物品品质 quality）
@export var regular_count: int = 8               # 物品数：品质 1–2 → 8；品质 3–4 → 12
@export var regular_items: Array[ItemDef] = []   # 引用 02 的 ItemDef（含 rarity/value）；长度必须 == regular_count
@export var socket_count: int = 3                # 该套系的常量（C4）：品质 1–4 → 2/3/4/5
@export var device_slot_count: int = 4           # 该套系的常量（核心 D4）：只被 04 读取
@export var unowned_weight_mult: float = 1.5     # 未拥有物品权重倍率（判定源 = 收藏口径 collected）

## 前 4 位 = 前 2 项「位子/物品」比例必须落在核心 §4.1 / P7 的 25%–40% 区间，
## 否则高品质套系会被收敛（R2 从后门回来）；C6 的 ≥3 断言也将无从保证。
const SOCKET_RATIO_MIN := 0.25
const SOCKET_RATIO_MAX := 0.40


## 核心 §4.1.1 的套系品质表（01 §11 G7 逐档抄录）。品质 1–4 → 物品数。
static func expected_regular_count(p_series_quality: int) -> int:
	return 8 if p_series_quality <= 2 else 12


## 核心 §4.1.1：品质 1–4 → 镶嵌位数 2/3/4/5。
static func expected_socket_count(p_series_quality: int) -> int:
	return clampi(p_series_quality + 1, 2, 5)


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
## [!] `device_slot_count` 的**逐档数值**未在本仓库文档中给出（01 §4.1 只有示例值 4，
##     表在核心 D4），因此这里只校验它 > 0 —— 不替核心补一张它没有给的表。
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
	if device_slot_count <= 0:
		problems.append("bad_device_slots：device_slot_count 必须 > 0")
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

## 制造成本的一条**需求向量**（01-gacha.md §4.3；v0.9 与 04 的 `DeviceCost` 统一为同一结构）。
##
## ★ 形状 = `(category, quality, amount)`，**不是** `item_id → count` 字典。
##   理由（裁决 5）：盲盒产出随机，`item_id` 级要求会让玩家卡在
##   "我需要星尘但只开出晶核"。
##
## [!] **`quality` 的语义按"品质下限"落地**（与 02 的 `consume_by_filter(category, quality_floor, n)`
##     和 03 的任务需求向量一致）。核心与本仓库文档没有逐字规定这一点，
##     这里取"与既有实现同义"的最小选择，**该口径需由 01/05 的拥有者确认**。
@tool
class_name ModuleCost
extends Resource

@export var category: StringName = &""
@export var quality: int = 1                             # 品质下限（见上）
@export_range(1, 99, 1) var amount: int = 1


func to_dict() -> Dictionary:
	return {"category": String(category), "quality": quality, "amount": amount}

## 一次抽取的结果（01-gacha.md §4.4）。**本系统拥有**。
##
## 以 Resource 承载，便于按核心 §14.2.7 写入开箱日志。
## `roll()` 是**纯函数**：它只产出这个对象，不产生实例、不消耗盒子（那是 `redeem()` 的事）。
class_name GachaResult
extends Resource

@export var ok: bool = true
@export var error: StringName = &""       # [补充] 纯函数不崩溃，用错误码返回
@export var series_id: StringName = &""
@export var box_id: String = ""           # 本次兑现的盒子身份（= Box.box_id，同类型、无转换）
@export var item_id: StringName = &""     # 抽中 void 时为空串哨兵（不产出任何物品）
@export var quality: int = 1              # 物品品质 1..5；void 时为 0
@export var is_void: bool = false         # 本次抽中空洞：仍消耗一个 Box
@export var is_new: bool = false          # 是否新物品（收藏口径 collected）；void 时恒 false
@export var probability: float = 0.0      # 本次所用分布中该结果的概率（void 时为 void_prob）
@export var seed: int = 0                 # 本次兑现的种子；即 source.box_seed
@export var draw_index: int = 0           # **全局单调递增**的兑现序号（不是"批次内序号"）
## **v0.14：本次抽取所用的池子快照**（`{box_id, revision, void_mass_bp, weights_bp}`）。
##
## **每次抽取各取一份**——两次使用之间池子可能已被编辑，**绝不能复用上一份快照**：
## 否则日志里"这一抽用的分布"与实际抽样用的分布不一致，P1（可核对）与 P2（可归因）当场失效。
##
## 存的是**整数权重**（`weights_bp`）而不是浮点 `probs`：概率是派生值，
## 快照留规范形态才不会变成"第二份事实来源"（07 §5.1 的整数口径）。
## 值是**深拷贝**——改这份快照不影响在跑的池子。
@export var pool_snapshot: Dictionary = {}


## 交付 02 的溯源三元组（核心 §4.2.1）：**只提供，不创建实例**。
func to_source() -> Dictionary:
	return {"series_id": series_id, "box_seed": seed, "draw_index": draw_index}


## 错误结果（`ok == false`）。**非法输入一律返回它，不崩溃、不产出半个 GachaResult**。
static func failure(err: StringName) -> GachaResult:
	var r := GachaResult.new()
	r.ok = false
	r.error = err
	return r


## `void` 结果（01 §5.6 的抽样规格）：空 item_id、quality = 0、is_new = false。
static func make_void(seed_arg: int, draw_index_arg: int, void_prob: float) -> GachaResult:
	var r := GachaResult.new()
	r.item_id = &""
	r.quality = 0
	r.is_void = true
	r.is_new = false
	r.probability = void_prob
	r.seed = seed_arg
	r.draw_index = draw_index_arg
	return r

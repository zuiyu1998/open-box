## 模块定义 / 编辑规则蓝图（01-gacha.md §4.3；原 05 的模块子系统已并入 01）。
##
## 一条模块 = 一条作用在**开盒端**的池子编辑规则：排除（BAN）/ 提升（BOOST）/ 回收（RECOVER）。
## **模块定义是"蓝图"，`Module` 是"某个盒子里已镶嵌的那一份实例"**——两者是两回事。
@tool
class_name ModuleDef
extends Resource

enum OpType { BAN, BOOST, RECOVER }

## 分配模式：AUTO = 按基础权重摊给其余未排除物品；TARGETED = 全给 `redistribute_target`。
enum RedistributeMode { AUTO, TARGETED }

@export var id: StringName = &""
@export var display_name: String = ""
@export var quality: int = 1                             # 模块品质梯度（核心 D13；第三条独立轴）
@export var op_type: OpType = OpType.BAN
@export var targets: Array[StringName] = []              # 多目标；**必须指向池内物品**（v0.13：池中全是常规物品）
@export var magnitude: float = 1.0                       # BOOST 的倍数；BAN / RECOVER 忽略
@export var redistribute_mode: RedistributeMode = RedistributeMode.AUTO
@export var redistribute_target: StringName = &""        # TARGETED 时的目标物品
@export var item_cost: Array[ModuleCost] = []            # 制造消耗（需求向量）
@export var exclusive_tags: Array[StringName] = []       # 互斥标记（V6）

const BOOST_CAP := 3.0                                   # 核心 D7 / 01 §5.2.3 V4：提升倍数上限 ×3


func op_name() -> String:
	match op_type:
		OpType.BAN:
			return "ban"
		OpType.BOOST:
			return "boost"
		_:
			return "recover"


## 定义级校验（加载时）。返回空数组 = 合法。
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("bad_module_id：ModuleDef.id 为空")
	if quality < 1:
		problems.append("bad_quality：%s.quality = %d，必须 >= 1" % [id, quality])
	if targets.is_empty():
		problems.append("no_targets：%s 没有目标物品（BAN / BOOST 都必须指明对象）" % id)
	if op_type == OpType.BOOST and magnitude > BOOST_CAP:
		problems.append(
			"boost_over_cap：%s.magnitude = %.2f 超过 boost_cap = %.2f（V4 / 核心 D7）"
			% [id, magnitude, BOOST_CAP]
		)
	if op_type == OpType.BOOST and magnitude < 1.0:
		problems.append("bad_magnitude：%s.magnitude = %.2f，提升必须 >= 1.0" % [id, magnitude])
	if op_type == OpType.RECOVER:
		problems.append(
			"recover_not_implemented：%s 是 RECOVER 模块——01 §5.1 规定「回收」为第二切片、本版仅定义接口"
			% id
		)
	if redistribute_mode == RedistributeMode.TARGETED and redistribute_target == &"":
		problems.append("no_redistribute_target：%s 选了 TARGETED 却没给 redistribute_target" % id)
	return problems

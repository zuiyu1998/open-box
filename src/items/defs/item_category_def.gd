## 物品类别注册表条目（02-item.md §4.1 的 [补充]）。
##
## 为什么类别用 StringName 引用注册表、而不是 enum：
## 核心 §14.3 / R11 要求"新物品类别可**纯配置产出**、不改代码"。
## 用 enum 的话每加一类都要改代码并承担存档兼容问题。
@tool
class_name ItemCategoryDef
extends Resource

@export var category_id: StringName = &""   # 唯一 id，被 ItemDef.category 引用
@export var display_name: String = ""       # 展示名，如"家居物品"
@export var description: String = ""        # ★ v0.21：一句话说明（内容文案；UI 的悬浮提示用）
@export var icon: Texture2D                 # 类别图标（形状区分，不得只靠颜色）
@export var sort_order: int = 0             # 面板内排序（**同一内容包里必须唯一**，见 validate）


## 定义级校验（加载时）。返回空数组 = 合法。
## **id 与 display_name 不能空**（前者是引用键、后者是 UI 必显示项）；
## `sort_order` 可选（0 = 不参与排序），但同一批内容里**重复的排序值是无意义的**，由注册表交叉校验。
func validate() -> Array[String]:
	var problems: Array[String] = []
	if category_id == &"":
		problems.append("bad_category_id：ItemCategoryDef.category_id 为空")
	if display_name == "":
		problems.append("bad_category_name：%s.display_name 为空（UI 要显示它）" % category_id)
	if sort_order < 0:
		problems.append("bad_sort_order：%s.sort_order = %d，不能为负" % [category_id, sort_order])
	return problems

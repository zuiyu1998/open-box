## 物品类别注册表条目（02-item.md §4.1 的 [补充]）。
##
## 为什么类别用 StringName 引用注册表、而不是 enum：
## 核心 §14.3 / R11 要求"新物品类别可**纯配置产出**、不改代码"。
## 用 enum 的话每加一类都要改代码并承担存档兼容问题。
@tool
class_name ItemCategoryDef
extends Resource

@export var category_id: StringName = &""   # 唯一 id，被 ItemDef.category 引用
@export var display_name: String = ""       # 展示名，如"星尘"
@export var icon: Texture2D                 # 类别图标（形状区分，不得只靠颜色）
@export var sort_order: int = 0             # 面板内排序

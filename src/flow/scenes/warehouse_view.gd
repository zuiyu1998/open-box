## 仓库页 —— View（★ v0.32 MVC 重构）。
##
## **只渲染**：`render(snapshot)` 把 Model 算好的 `Dictionary` 画到控件上。
## 时序问题同许愿机（方案 1）：Controller 用 `call_deferred("refresh")`，所以本类 `@onready` 一定就绪。
class_name WarehouseView
extends VBoxContainer

@onready var _usage_lbl: Label = $Usage
@onready var _items_lbl: Label = $Items
@onready var _boxes_lbl: Label = $Boxes


func render(s: Dictionary) -> void:
	_usage_lbl.text = String(s.get("usage", ""))
	_items_lbl.text = String(s.get("items", ""))
	_boxes_lbl.text = String(s.get("boxes", ""))

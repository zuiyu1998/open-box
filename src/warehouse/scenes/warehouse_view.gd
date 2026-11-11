## 仓库页 —— View（★ v0.32 MVC 重构；★ v0.37 网格）。
##
## **只渲染**：`render(snapshot)` 把 Model 算好的 `Dictionary` 画到控件上。
## 时序问题同许愿机（方案 1）：Controller 用 `call_deferred("refresh")`，所以本类 `@onready` 一定就绪。
##
## ★ v0.37：新增**仓库网格**——`ScrollContainer/Grid`（`warehouse_grid.gd`）负责按 `cell_size`
## 把每个物品画成 `w × h` 的块；本类只把 Model 的 `grid` 字典转交给它。
class_name WarehouseView
extends VBoxContainer

@onready var _usage_lbl: Label = $Usage
@onready var _items_lbl: Label = $Items
@onready var _boxes_lbl: Label = $Boxes
@onready var _grid: WarehouseGrid = $Scroll/Grid


func render(s: Dictionary) -> void:
	_usage_lbl.text = String(s.get("usage", ""))
	_items_lbl.text = String(s.get("items", ""))
	_boxes_lbl.text = String(s.get("boxes", ""))
	if _grid != null:
		_grid.set_layout(s.get("grid", {}))


## 测试用：拿到网格控件本身（验证格子尺寸 / 块数）。
func grid_view() -> WarehouseGrid:
	return _grid

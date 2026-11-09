## 仓库页 —— Controller（★ v0.32 MVC 重构）。
##
## **唯一把 Model 与 View 连起来的地方**。本节点是场景里的一个**子节点**，
## `view` = 父节点（场景根 `WarehousePage`，挂 `warehouse_view.gd`）。
## 首次 render 用 `call_deferred`（与许愿机同一方案 1：子先于父 ready）。
class_name WarehouseController
extends Node

var model: WarehouseModel = WarehouseModel.new()

@onready var view: WarehouseView = get_parent()


func _ready() -> void:
	if model.state == null:
		model.bind(GameSession.state)
	call_deferred("refresh")


func bind_state(s: GameState) -> void:
	model.bind(s)
	refresh()


func refresh() -> void:
	view.render(model.snapshot())


## 透传给外部 / 测试的只读快照。
func snapshot() -> Dictionary:
	return model.snapshot()

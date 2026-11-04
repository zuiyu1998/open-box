## 许愿机 —— Controller（★ v0.30 MVC 重构；v0.30.1 方案 1 修复 ready 时序）。
##
## **唯一把 Model 与 View 连起来的地方**：
##   · `bind_state()`：Model 绑状态 → View 渲染；
##   · 订阅 View 的两个信号 → 调 Model 对应方法 → 再 View 渲染。
##
## ★ **v0.30.1（方案 1）**：`_ready` 里**不直接 refresh**，而是 `call_deferred("refresh")`。
##   Godot 的 `_ready` 自底向上（子先于父）⇒ 本类（子）的 `_ready` 跑在 View（父）之前，
##   那一刻 View 的 `@onready` 还没赋值。推迟到本帧所有 `_ready` 结束后，View 一定已就绪，
##   `render()` 才能安全地直接用 `@onready`。
##
## 输入（按钮）→ Controller → Model（业务）→ View（渲染）。
class_name WishMachineController
extends Node

var model: WishMachineModel = WishMachineModel.new()

@onready var view: WishMachineView = get_parent()


func _ready() -> void:
	if model.state == null:
		model.bind(GameSession.state)
	view.upgrade_requested.connect(_on_upgrade)
	view.open_requested.connect(_on_open)
	call_deferred("refresh")   # ★ 首次 render 推迟到 View 的 @onready 就绪之后


func bind_state(s: GameState) -> void:
	model.bind(s)
	refresh()


func refresh() -> void:
	view.render(model.snapshot(view.selected_index))


## 透传给外部 / 测试的只读快照（View 不提供，Model 才有）。
func snapshot() -> Dictionary:
	return model.snapshot(view.selected_index)


func _on_upgrade() -> void:
	model.upgrade()
	refresh()


func _on_open(times: int) -> void:
	model.open(times, view.selected_index)
	refresh()

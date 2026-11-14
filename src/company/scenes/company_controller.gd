## 公司页 —— Controller（★ v0.39 MVC）。
##
## **唯一把 Model 与 View 连起来的地方**：
##   · `bind_state()`：Model 绑状态 → View 渲染；
##   · 订阅 View 的两个信号 → 调 Model 对应方法 → 再 View 渲染。
##
## 时序同许愿机（方案 1）：`_ready` 里 `call_deferred("refresh")`，保证 View 的 `@onready` 就绪。
class_name CompanyController
extends Node

var model: CompanyModel = CompanyModel.new()

@onready var view: CompanyView = get_parent()


func _ready() -> void:
	if model.state == null:
		model.bind(GameSession.state)
	view.upgrade_requested.connect(_on_upgrade)
	view.buy_requested.connect(_on_buy)
	call_deferred("refresh")   # ★ 首次 render 推迟到 View 的 @onready 就绪之后


func bind_state(s: GameState) -> void:
	model.bind(s)
	refresh()


func refresh() -> void:
	view.render(model.snapshot())


## 透传给外部 / 测试的只读快照。
func snapshot() -> Dictionary:
	return model.snapshot()


func _on_upgrade() -> void:
	model.upgrade()
	refresh()


func _on_buy() -> void:
	model.buy()
	refresh()

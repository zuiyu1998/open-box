## 市场页 —— Controller（★ v0.38 MVC）。
##
## **唯一把 Model 与 View 连起来的地方**：
##   · `refresh()`：Model 取快照 → View 渲染；
##   · 订阅 View 的两个信号 → 调 Model 对应方法 → 再 View 渲染。
##
## 时序同许愿机（方案 1）：`_ready` 里 `call_deferred("refresh")`，保证 View 的 `@onready` 就绪。
class_name MarketController
extends Node

var model: MarketModel = MarketModel.new()

@onready var view: MarketView = get_parent()


func _ready() -> void:
	view.buy_requested.connect(_on_buy)
	view.sell_requested.connect(_on_sell)
	call_deferred("refresh")   # ★ 首次 render 推迟到 View 的 @onready 就绪之后


func refresh() -> void:
	view.render(model.snapshot())


## 透传给外部 / 测试的只读快照。
func snapshot() -> Dictionary:
	return model.snapshot()


func _on_buy() -> void:
	model.buy(view.buy_index)
	refresh()


func _on_sell() -> void:
	model.sell(view.sell_index)
	refresh()

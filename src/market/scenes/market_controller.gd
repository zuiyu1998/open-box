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
	view.buy_item_requested.connect(_on_buy_item)
	view.buy_box_requested.connect(_on_buy_box)
	call_deferred("refresh")   # ★ 首次 render 推迟到 View 的 @onready 就绪之后


## ★ v0.57：与其它页同形——顶层 `GameScreen.refresh()` 会经 `bind_state` 重渲染本页。
## 没有它的话，**切 tab 回来市场页不会重画**（金币 / 库存 / 生成候选项都可能是旧的）。
func bind_state(_state: GameState) -> void:
	refresh()


func refresh() -> void:
	view.render(model.snapshot())


## 透传给外部 / 测试的只读快照。
func snapshot() -> Dictionary:
	return model.snapshot()


## ★ v0.60：买盲盒（卡片直接带 box_id）
func _on_buy_box(box_id: String) -> void:
	model.buy_box(box_id)
	refresh()


## ★ v0.58：卡片上的购买按钮直接带 item_id（不再有"选中项"这一层）
func _on_buy_item(item_id: StringName) -> void:
	model.buy_item(item_id)
	refresh()

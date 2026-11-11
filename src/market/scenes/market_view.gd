## 市场页 —— View（★ v0.38 MVC）。
##
## **只渲染 + 只转发输入**：`render(snapshot)` 画 Model 算好的 `Dictionary`；
## 按钮 `pressed` 只 `emit` 信号（`buy_requested` / `sell_requested`），不做任何业务。
##
## 时序同许愿机（方案 1）：Controller 用 `call_deferred("refresh")`，所以本类 `@onready` 一定就绪。
class_name MarketView
extends VBoxContainer

signal buy_requested
signal sell_requested

@onready var _gold_lbl: Label = $Gold
@onready var _refresh_lbl: Label = $Refresh
@onready var _listing_lbl: Label = $Listings
@onready var _buy_picker: OptionButton = $BuyRow/BuyPicker
@onready var _buy_btn: Button = $BuyRow/BuyButton
@onready var _sell_picker: OptionButton = $SellRow/SellPicker
@onready var _sell_btn: Button = $SellRow/SellButton
@onready var _result_lbl: Label = $Result


func _ready() -> void:
	_buy_btn.pressed.connect(func() -> void: buy_requested.emit())
	_sell_btn.pressed.connect(func() -> void: sell_requested.emit())


## 选中项下标（Controller 读它，转成 Model.buy / Model.sell 的下标）。
var buy_index: int:
	get:
		return _buy_picker.selected

var sell_index: int:
	get:
		return _sell_picker.selected


## 用 Model 的快照渲染（调用方保证 @onready 已就绪）。
func render(s: Dictionary) -> void:
	_gold_lbl.text = String(s.get("gold", ""))
	_refresh_lbl.text = String(s.get("refresh", ""))

	# 上架清单（多行文本）
	var lines: Array = s.get("listing_lines", [])
	_listing_lbl.text = "\n".join(lines) if lines.size() > 0 else "市场暂无可购买的物品"

	# 买入下拉 + 按钮
	var buy_opts: Array = s.get("buy_options", [])
	_refill(_buy_picker, buy_opts)
	_buy_btn.disabled = bool(s.get("buy_disabled", true))

	# 卖出下拉 + 按钮
	var sell_opts: Array = s.get("sell_options", [])
	_refill(_sell_picker, sell_opts)
	_sell_btn.disabled = bool(s.get("sell_disabled", true))

	_result_lbl.text = String(s.get("result", ""))


## 重填一个 OptionButton（保留原选中下标，越界则归 0）。
func _refill(picker: OptionButton, opts: Array) -> void:
	var prev := picker.selected
	picker.clear()
	for o in opts:
		picker.add_item(String(o))
	if prev >= 0 and prev < opts.size():
		picker.selected = prev

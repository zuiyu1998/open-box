## 公司页 —— View（★ v0.39 MVC）。
##
## **只渲染 + 只转发输入**：`render(snapshot)` 画 Model 算好的 `Dictionary`；
## 按钮 `pressed` 只 `emit` 信号（`upgrade_requested` / `buy_requested`），不做任何业务。
##
## 时序同许愿机（方案 1）：Controller 用 `call_deferred("refresh")`，所以本类 `@onready` 一定就绪。
class_name CompanyView
extends VBoxContainer

signal upgrade_requested
signal buy_requested

@onready var _level_lbl: Label = $Level
@onready var _route_lbl: Label = $Route
@onready var _countdown_lbl: Label = $Countdown
@onready var _stock_lbl: Label = $Stock
@onready var _gold_lbl: Label = $Gold
@onready var _upgrade_btn: Button = $UpgradeButton
@onready var _buy_btn: Button = $BuyButton
@onready var _result_lbl: Label = $Result


func _ready() -> void:
	_upgrade_btn.pressed.connect(func() -> void: upgrade_requested.emit())
	_buy_btn.pressed.connect(func() -> void: buy_requested.emit())


## 用 Model 的快照渲染（调用方保证 @onready 已就绪）。
func render(s: Dictionary) -> void:
	_level_lbl.text = String(s.get("level", ""))
	_route_lbl.text = String(s.get("route", ""))
	_countdown_lbl.text = String(s.get("countdown", ""))
	_stock_lbl.text = String(s.get("stock", ""))
	_gold_lbl.text = String(s.get("gold", ""))

	_upgrade_btn.text = String(s.get("upgrade_text", "升级"))
	_upgrade_btn.disabled = bool(s.get("upgrade_disabled", true))
	_buy_btn.text = String(s.get("buy_text", "买一盒"))
	_buy_btn.disabled = bool(s.get("buy_disabled", true))

	_result_lbl.text = String(s.get("result", ""))

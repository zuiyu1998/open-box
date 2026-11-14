## 干员页 —— View（★ v0.40 MVC）。
##
## **只渲染 + 只转发输入**：`render(snapshot)` 画 Model 算好的 `Dictionary`；
## 按钮 `pressed` 只 `emit` 信号（`toggle_requested` / `upgrade_requested`），不做任何业务。
##
## 时序同许愿机（方案 1）：Controller 用 `call_deferred("refresh")`，所以本类 `@onready` 一定就绪。
class_name OperatorView
extends VBoxContainer

signal toggle_requested
signal upgrade_requested

@onready var _level_lbl: Label = $Level
@onready var _route_lbl: Label = $Route
@onready var _bans_lbl: Label = $Bans
@onready var _toggle_btn: Button = $ToggleButton
@onready var _upgrade_btn: Button = $UpgradeButton
@onready var _result_lbl: Label = $Result


func _ready() -> void:
	_toggle_btn.pressed.connect(func() -> void: toggle_requested.emit())
	_upgrade_btn.pressed.connect(func() -> void: upgrade_requested.emit())


## 用 Model 的快照渲染（调用方保证 @onready 已就绪）。
func render(s: Dictionary) -> void:
	_level_lbl.text = String(s.get("level", ""))
	_route_lbl.text = String(s.get("route", ""))
	_bans_lbl.text = String(s.get("bans", ""))

	_toggle_btn.text = String(s.get("toggle_text", "出战"))
	_upgrade_btn.text = String(s.get("upgrade_text", "升级"))
	_upgrade_btn.disabled = bool(s.get("upgrade_disabled", true))

	_result_lbl.text = String(s.get("result", ""))

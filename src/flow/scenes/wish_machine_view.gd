## 许愿机 —— View（★ v0.30 MVC 重构；v0.30.1 方案 1 修复 ready 时序）。
##
## **只渲染 + 只转发输入**：
##   · `render(snapshot)` 把 Model 算好的 `Dictionary` 画到控件上（**View 不自己算任何数**）；
##   · 按钮 `pressed` 只 `emit` 信号（`upgrade_requested` / `open_requested(times)`）；
##   · `selected_index` 是 `BoxPicker` 的选中项，由 Controller 读走。
##
## ★ **v0.30.1（方案 1）**：恢复 `@onready`（Godot 惯用、静态类型）。
##   时序问题不在 View 解决，而在 Controller —— 它用 `call_deferred("refresh")` 把首次
##   `render` 推迟到**本帧所有 `_ready` 都跑完**之后；因此本类的 `@onready` 一定已就绪，
##   `render()` 可以放心直接用它们。
class_name WishMachineView
extends VBoxContainer

signal upgrade_requested
signal open_requested(times: int)

@onready var _name_lbl: Label = $DeviceName
@onready var _desc_lbl: Label = $DeviceDesc
@onready var _level_lbl: Label = $LevelLine
@onready var _effect_lbl: Label = $EffectLine
@onready var _gem_lbl: Label = $GemLine
@onready var _upgrade_btn: Button = $UpgradeButton
@onready var _picker: OptionButton = $BoxPicker
@onready var _uses_lbl: Label = $BoxUses
@onready var _expect_lbl: Label = $BoxExpectation
@onready var _open_one: Button = $OpenButtons/OpenOne
@onready var _open_ten: Button = $OpenButtons/OpenTen
@onready var _result_lbl: Label = $ResultLine


func _ready() -> void:
	_upgrade_btn.pressed.connect(func() -> void: upgrade_requested.emit())
	_open_one.pressed.connect(func() -> void: open_requested.emit(1))
	_open_ten.pressed.connect(func() -> void: open_requested.emit(10))


## 选中项下标（Controller 读它，转成 Model.open 的 `box_index`）。
var selected_index: int:
	get:
		return _picker.selected


## 用 Model 的快照渲染（调用方保证 @onready 已就绪——见 Controller 的 call_deferred）。
func render(s: Dictionary) -> void:
	_name_lbl.text = String(s.get("device_name", ""))
	_desc_lbl.text = String(s.get("description", ""))
	_level_lbl.text = String(s.get("level", ""))
	_effect_lbl.text = String(s.get("effect", ""))
	_gem_lbl.text = String(s.get("gem", ""))

	_upgrade_btn.text = String(s.get("upgrade_text", "升级"))
	_upgrade_btn.disabled = bool(s.get("upgrade_disabled", true))

	_uses_lbl.text = String(s.get("box_uses", "剩余开盒次数 —"))
	_expect_lbl.text = String(s.get("box_expectation", "数学期望 M̄ —"))

	var opts: Array = s.get("box_options", [])
	var prev := _picker.selected
	_picker.clear()
	for o in opts:
		_picker.add_item(String(o))
	if prev >= 0 and prev < opts.size():
		_picker.selected = prev

	var disabled := bool(s.get("open_disabled", true))
	_open_one.disabled = disabled
	_open_ten.disabled = disabled

	_result_lbl.text = String(s.get("result", ""))

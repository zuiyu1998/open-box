## 许愿机 —— View（★ v0.30 MVC；★ v0.41 三栏重构）。
##
## **只渲染 + 只转发输入**：
##   · `render(snapshot)` 把 Model 算好的 `Dictionary` 画到控件上（**View 不自己算任何数**）；
##   · 控件的输入只 `emit` 信号，业务一律由 Controller → Model 处理。
##
## **★ v0.41 布局（从左至右三栏）**：
##   · **左栏** = 许愿机的操作部分：顶层**盲盒选择** / 中层**模块镶嵌** / 下层**生成物品显示**；
##   · **中栏** = **干员**（出战切换 + 等级 / 路线 / 排除目标）；
##   · **右栏** = 上层**盲盒信息**（使用次数 + 数学期望）/ 下层**三个开启按钮**
##     （开启一次 / 开启 10 次 / 开启全部）。
##   设备身份（名字 / 等级 / 效果 / 原石 / 升级）在顶部 `Header` 横条，**不占三栏**。
##
## ★ **v0.30.1（方案 1）**：Controller 用 `call_deferred("refresh")` 把首次 `render` 推迟到
##   **本帧所有 `_ready` 都跑完**之后 ⇒ 本类的 `@onready` 一定已就绪。
class_name WishMachineView
extends VBoxContainer

signal upgrade_requested
## `times`：1 / 10；**0 = 开启全部**（由 Model 解释成"该盒剩余次数"）。
signal open_requested(times: int)
signal socket_requested
## ★ v0.44：`unsocket_requested` 已随"拆卸"一起删除——**模块镶上即永久锁定**。
## ★ v0.45：池子成员与三态（可编辑字段，不走模块）
signal pool_cycle_requested
signal pool_add_requested
signal operator_toggle_requested
## 选中的盲盒变了（右栏信息 / 中栏位子都要跟着重算）。
signal box_changed

@onready var _name_lbl: Label = $Header/DeviceName
@onready var _desc_lbl: Label = $Header/DeviceDesc
@onready var _level_lbl: Label = $Header/LevelLine
@onready var _effect_lbl: Label = $Header/EffectLine
@onready var _gem_lbl: Label = $Header/GemLine
@onready var _upgrade_btn: Button = $Header/UpgradeButton

@onready var _picker: OptionButton = $Columns/Left/BoxSection/BoxPicker
@onready var _slot_detail: Label = $Columns/Left/ModuleSection/SlotDetail
@onready var _slot_picker: OptionButton = $Columns/Left/ModuleSection/SlotPicker
@onready var _module_picker: OptionButton = $Columns/Left/ModuleSection/ModulePicker
@onready var _socket_btn: Button = $Columns/Left/ModuleSection/ModuleButtons/SocketButton
@onready var _pool_summary: Label = $Columns/Left/PoolSection/PoolSummary
@onready var _pool_picker: OptionButton = $Columns/Left/PoolSection/PoolPicker
@onready var _pool_state: Label = $Columns/Left/PoolSection/PoolState
@onready var _pool_cycle_btn: Button = $Columns/Left/PoolSection/PoolButtons/PoolCycleButton
@onready var _add_picker: OptionButton = $Columns/Left/PoolSection/AddRow/AddPicker
@onready var _add_btn: Button = $Columns/Left/PoolSection/AddRow/AddButton
@onready var _result_lbl: Label = $Columns/Left/ResultSection/ResultLine

@onready var _op_level: Label = $Columns/Middle/OperatorLevel
@onready var _op_route: Label = $Columns/Middle/OperatorRoute
@onready var _op_bans: Label = $Columns/Middle/OperatorBans
@onready var _op_toggle: Button = $Columns/Middle/OperatorToggle

@onready var _uses_lbl: Label = $Columns/Right/InfoSection/BoxUses
@onready var _expect_lbl: Label = $Columns/Right/InfoSection/BoxExpectation
@onready var _open_one: Button = $Columns/Right/OpenButtons/OpenOne
@onready var _open_ten: Button = $Columns/Right/OpenButtons/OpenTen
@onready var _open_all: Button = $Columns/Right/OpenButtons/OpenAll


func _ready() -> void:
	_upgrade_btn.pressed.connect(func() -> void: upgrade_requested.emit())
	_open_one.pressed.connect(func() -> void: open_requested.emit(1))
	_open_ten.pressed.connect(func() -> void: open_requested.emit(10))
	_open_all.pressed.connect(func() -> void: open_requested.emit(0))
	_socket_btn.pressed.connect(func() -> void: socket_requested.emit())
	_pool_cycle_btn.pressed.connect(func() -> void: pool_cycle_requested.emit())
	_add_btn.pressed.connect(func() -> void: pool_add_requested.emit())
	_op_toggle.pressed.connect(func() -> void: operator_toggle_requested.emit())
	_picker.item_selected.connect(func(_i: int) -> void: box_changed.emit())


## 选中项下标（Controller 读走，转成 Model 的下标参数）。
var selected_index: int:
	get:
		return _picker.selected

var slot_index: int:
	get:
		return _slot_picker.selected

var module_index: int:
	get:
		return _module_picker.selected

## ★ v0.45：池内物品下标 / 可添加物品下标。
var pool_index: int:
	get:
		return _pool_picker.selected

var add_index: int:
	get:
		return _add_picker.selected


## 用 Model 的快照渲染（调用方保证 @onready 已就绪——见 Controller 的 call_deferred）。
func render(s: Dictionary) -> void:
	# ── 顶部：设备身份 ────────────────────────────────────────────────────────
	_name_lbl.text = String(s.get("device_name", ""))
	_desc_lbl.text = String(s.get("description", ""))
	_level_lbl.text = String(s.get("level", ""))
	_effect_lbl.text = String(s.get("effect", ""))
	_gem_lbl.text = String(s.get("gem", ""))
	_upgrade_btn.text = String(s.get("upgrade_text", "升级"))
	_upgrade_btn.disabled = bool(s.get("upgrade_disabled", true))

	# ── 左栏 · 顶：盲盒选择 ───────────────────────────────────────────────────
	_refill(_picker, s.get("box_options", []))

	# ── 左栏 · 中：模块镶嵌 ───────────────────────────────────────────────────
	_slot_detail.text = String(s.get("slot_detail", "—"))
	_refill(_slot_picker, s.get("slot_options", []))
	_refill(_module_picker, s.get("module_options", []))
	_socket_btn.disabled = bool(s.get("socket_disabled", true))

	# ── 左栏 · 池子（★ v0.45）─────────────────────────────────────────────────
	_pool_summary.text = String(s.get("pool_summary", ""))
	_pool_state.text = String(s.get("pool_state_text", ""))
	_refill(_pool_picker, s.get("pool_options", []))
	_refill(_add_picker, s.get("add_options", []))
	_pool_cycle_btn.disabled = bool(s.get("pool_cycle_disabled", true))
	_add_btn.disabled = bool(s.get("pool_add_disabled", true))

	# ── 左栏 · 下：生成物品 ───────────────────────────────────────────────────
	_result_lbl.text = String(s.get("result", ""))

	# ── 中栏：干员 ────────────────────────────────────────────────────────────
	var op: Dictionary = s.get("operator", {})
	_op_level.text = "干员 %s" % String(op.get("level", ""))
	_op_route.text = "路线：%s" % String(op.get("route", "—"))
	_op_bans.text = String(op.get("bans", "排除：无"))
	_op_toggle.text = String(op.get("toggle_text", "出战"))

	# ── 右栏 · 上：盲盒信息；下：三个开启按钮 ─────────────────────────────────
	_uses_lbl.text = String(s.get("box_uses", "剩余开盒次数 —"))
	_expect_lbl.text = String(s.get("box_expectation", "数学期望 M̄ —"))
	var disabled := bool(s.get("open_disabled", true))
	_open_one.disabled = disabled
	_open_ten.disabled = disabled
	_open_all.disabled = bool(s.get("open_all_disabled", disabled))


## 重填一个 OptionButton（保留原选中下标；越界则归 0，空表则 -1）。
func _refill(picker: OptionButton, opts) -> void:
	var prev := picker.selected
	picker.clear()
	var arr: Array = opts if opts is Array else []
	for o in arr:
		picker.add_item(String(o))
	if arr.is_empty():
		picker.selected = -1
	elif prev >= 0 and prev < arr.size():
		picker.selected = prev
	else:
		picker.selected = 0

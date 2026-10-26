## 许愿机（★ v0.29）——**01/04 的"设备"在界面上的名字就是「许愿机」**（用户裁决）。
##
## 它是**游戏场景里的一个 tab 页的完整内容**，被 `game_screen.tscn` 实例化后放进第二个 tab：
##   `game_screen.gd` 只负责 tab 骨架，**许愿机的界面与行为全部在这个场景里**。
##
## 本页做四件事（全部走各自系统的既有入口，**本脚本不自己算数**）：
##   1. **显示设备**：名字 / 描述 / 等级（`DeviceService.primary_device()` + `DeviceCatalog`）；
##   2. **显示本级效果**：可开套系品质上限、开盒折扣（`DeviceDef.spec_for_level()`）；
##   3. **升级**：价格取 `DeviceService.upgrade_cost()`，扣费与生效走 `DeviceService.upgrade_device()`
##      （**本脚本不碰原石余额**）；原石不够 / 已满级 ⇒ 按钮置灰并写明原因；
##   4. **开盒**：选一个**仓库里**的盲盒，走 `DeviceService.redeem()`，结果显示开出什么 / `void` / 原因码。
##
## 纪律：不读档、不写档、不改 `GameState` / `ItemService`（`11-flow.md` §2 的边界）。
extends VBoxContainer

## 由外部注入（`game_screen` 注入 `GameSession.state`；测试也可直接注入）。
var state: GameState = null

@onready var _name_lbl: Label = $DeviceName
@onready var _desc_lbl: Label = $DeviceDesc
@onready var _level_lbl: Label = $LevelLine
@onready var _effect_lbl: Label = $EffectLine
@onready var _upgrade_btn: Button = $UpgradeButton
@onready var _gem_lbl: Label = $GemLine
@onready var _picker: OptionButton = $BoxPicker
@onready var _open_btn: Button = $OpenButton
@onready var _result_lbl: Label = $ResultLine

var _last_result := ""


func _ready() -> void:
	if state == null:
		state = GameSession.state
	_upgrade_btn.pressed.connect(_on_upgrade)
	_open_btn.pressed.connect(_on_open)
	refresh()


func bind_state(s: GameState) -> void:
	state = s
	refresh()


func refresh() -> void:
	var dev: Device = null if state == null else DeviceService.primary_device(state)
	if dev == null:
		_name_lbl.text = "还没有许愿机"
		_desc_lbl.text = "开局应当发一台；若这里是空的，说明这一局没有建档"
		_level_lbl.text = ""
		_effect_lbl.text = ""
		_upgrade_btn.text = "升级"
		_upgrade_btn.disabled = true
		_gem_lbl.text = "原石 0"
		_picker.clear()
		_open_btn.disabled = true
		_result_lbl.text = _last_result
		return

	var def: DeviceDef = DeviceCatalog.get_device(dev.device_id)
	if def == null:
		_name_lbl.text = String(dev.device_id)
		_desc_lbl.text = "（设备注册表里查不到这台，配置错误）"
	else:
		_name_lbl.text = def.display_name
		_desc_lbl.text = def.description

	var max_lv: int = def.max_level() if def != null else dev.level
	_level_lbl.text = "等级 Lv.%d / Lv.%d" % [dev.level, max_lv]

	if def != null:
		var spec: DeviceLevelSpec = def.spec_for_level(dev.level)
		var unlock := spec.unlock_series_quality_max if spec != null else 0
		var bp := spec.open_cost_bp if spec != null else 10000
		_effect_lbl.text = "可开套系品质 ≤ %d · 开盒成本 %d%%" % [unlock, int(round(bp / 100.0))]

	# 升级：价格问 04；钱够不够也只问 02 的余额（本页不算折扣）
	var cost: int = DeviceService.upgrade_cost(state, dev.device_id)
	if dev.level >= max_lv:
		_upgrade_btn.text = "已满级"
		_upgrade_btn.disabled = true
	elif cost < 0:
		_upgrade_btn.text = "升级"
		_upgrade_btn.disabled = true
	else:
		_upgrade_btn.text = "升级（%d 原石）" % cost
		_upgrade_btn.disabled = cost > ItemService.currency_balance(ItemConstants.CURRENCY_GEM)

	_gem_lbl.text = "原石 %d" % ItemService.currency_balance(ItemConstants.CURRENCY_GEM)

	# 开盒：只列**仓库里**的盒子（邮件里的不可兑现，v0.26）
	var boxes: Array = [] if state == null else state.boxes_in(ItemConstants.LOC_WAREHOUSE)
	var prev := _picker.selected
	_picker.clear()
	for b in boxes:
		_picker.add_item("%s（寿命 %d）" % [String(b.box_id).substr(0, 8), b.uses_remaining])
	if prev >= 0 and prev < boxes.size():
		_picker.selected = prev
	_open_btn.disabled = boxes.size() == 0
	_result_lbl.text = _last_result


func _on_upgrade() -> void:
	if state == null:
		return
	var dev: Device = DeviceService.primary_device(state)
	if dev == null:
		return
	var r := DeviceService.upgrade_device(state, dev.device_id)
	if r["ok"]:
		_last_result = "升级成功：Lv.%d" % DeviceService.primary_device(state).level
	else:
		_last_result = "升级失败：%s" % String(r["reason"])
	refresh()


func _on_open() -> void:
	if state == null:
		return
	var boxes := state.boxes_in(ItemConstants.LOC_WAREHOUSE)
	if _picker.selected < 0 or _picker.selected >= boxes.size():
		_last_result = "请先选择要开的盲盒"
		refresh()
		return
	var box: Box = boxes[_picker.selected]
	var r := DeviceService.redeem(state, box)
	if r.ok:
		if r.is_void:
			_last_result = "许愿机：这次什么都没有（消耗 1 次寿命）"
		else:
			var d := ItemCatalog.get_def(r.item_id)
			_last_result = "许愿机开出：%s（%s）" % [
				d.display_name if d != null else String(r.item_id),
				ItemConstants.quality_name(d.quality if d != null else 1),
			]
	else:
		_last_result = "开盒失败：%s" % String(r.error)
	refresh()


## 供测试读取的只读快照（不参与业务）。
func snapshot() -> Dictionary:
	return {
		"device_name": _name_lbl.text,
		"level": _level_lbl.text,
		"effect": _effect_lbl.text,
		"upgrade_text": _upgrade_btn.text,
		"upgrade_disabled": _upgrade_btn.disabled,
		"gem": _gem_lbl.text,
		"box_count": _picker.item_count,
		"open_disabled": _open_btn.disabled,
		"result": _result_lbl.text,
	}

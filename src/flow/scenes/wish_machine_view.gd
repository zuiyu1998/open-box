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
signal slot_clicked(slot: int)
## ★ v0.78：在浮层里选中某个模块 ⇒ 镶进"刚才点的那个空位"
signal module_picked(module_id: StringName)
## ★ v0.44：`unsocket_requested` 已随"拆卸"一起删除——**模块镶上即永久锁定**。
## ★ v0.45：池子成员与三态（可编辑字段，不走模块）
## ★ v0.51：浮层的排序变了（0 池内顺序 / 1 概率 / 2 价值 / 3 售价）
signal pool_sort_requested(mode: int)
## ★ v0.52b：请求打开池子数据浮层——**先 refresh 再开**，保证打开时看到的是当前数据
signal pool_data_requested
signal operator_toggle_requested
## 选中的盲盒变了（右栏信息 / 中栏位子都要跟着重算）。
signal box_button_clicked
## ★ v0.79：在浮层里选中某个盒子
signal box_chosen(index: int)
signal box_changed

@onready var _name_lbl: Label = $Header/DeviceName
@onready var _desc_lbl: Label = $Header/DeviceDesc
@onready var _level_lbl: Label = $Header/LevelLine
@onready var _effect_lbl: Label = $Header/EffectLine
@onready var _gem_lbl: Label = $Header/GemLine
@onready var _upgrade_btn: Button = $Header/UpgradeButton

@onready var _box_btn: Button = $Columns/Middle/BoxSection/BoxButton
@onready var _box_icon: BoxIcon = $Columns/Middle/BoxSection/BoxButton/BoxIcon
## ★ v0.79：当前选中的盒子下标（View 自己持有——浮层选完由它记）
var _selected_box: int = 0
# ★ v0.79：盲盒选择浮层
@onready var _box_overlay: Control = $BoxOverlayLayer/BoxOverlay
@onready var _box_note: Label = $BoxOverlayLayer/BoxOverlay/Frame/Body/Note
@onready var _box_rows: VBoxContainer = $BoxOverlayLayer/BoxOverlay/Frame/Body/Scroll/Rows
@onready var _box_close: Button = $BoxOverlayLayer/BoxOverlay/Frame/Body/CloseButton
@onready var _slot_detail: Label = $Columns/Middle/ModuleSection/SlotDetail
@onready var _slot_row: HBoxContainer = $Columns/Middle/ModuleSection/SlotRow
## ★ v0.50：池子数据浮层（用 `CanvasLayer` 承载，容器的排版不会碰到它）
@onready var _pool_data_btn: Button = $Columns/Middle/ModuleSection/ModuleButtons/PoolDataButton
@onready var _overlay: Control = $PoolOverlayLayer/PoolOverlay
@onready var _res_overlay: Control = $ResultOverlayLayer/ResultOverlay
@onready var _res_note: Label = $ResultOverlayLayer/ResultOverlay/Frame/Body/Note
@onready var _res_rows: VBoxContainer = $ResultOverlayLayer/ResultOverlay/Frame/Body/Scroll/Rows
@onready var _res_foot: Label = $ResultOverlayLayer/ResultOverlay/Frame/Body/Foot
@onready var _res_close: Button = $ResultOverlayLayer/ResultOverlay/Frame/Body/CloseButton
# ★ v0.78：模块选择浮层（点空位后弹出）
@onready var _mod_overlay: Control = $ModuleOverlayLayer/ModuleOverlay
@onready var _mod_note: Label = $ModuleOverlayLayer/ModuleOverlay/Frame/Body/Note
@onready var _mod_rows: VBoxContainer = $ModuleOverlayLayer/ModuleOverlay/Frame/Body/Scroll/Rows
@onready var _mod_close: Button = $ModuleOverlayLayer/ModuleOverlay/Frame/Body/CloseButton
@onready var _ov_note: Label = $PoolOverlayLayer/PoolOverlay/Frame/Body/Note
@onready var _ov_rows: VBoxContainer = $PoolOverlayLayer/PoolOverlay/Frame/Body/Scroll/Rows
@onready var _ov_totals: Label = $PoolOverlayLayer/PoolOverlay/Frame/Body/Totals
@onready var _ov_close: Button = $PoolOverlayLayer/PoolOverlay/Frame/Body/CloseButton
## ★ v0.51：浮层排序
@onready var _ov_sort: OptionButton = $PoolOverlayLayer/PoolOverlay/Frame/Body/SortRow/SortPicker
@onready var _result_lbl: Label = $Columns/Middle/StatusLine

@onready var _op_level: Label = $Columns/Left/OperatorLevel
@onready var _op_route: Label = $Columns/Left/OperatorRoute
@onready var _op_bans: Label = $Columns/Left/OperatorBans
@onready var _op_toggle: Button = $Columns/Left/OperatorToggle

@onready var _uses_lbl: Label = $Columns/Right/BoxUses
@onready var _expect_lbl: Label = $Columns/Right/BoxExpectation
@onready var _open_one: Button = $Columns/Middle/OpenButtons/OpenOne
@onready var _open_ten: Button = $Columns/Middle/OpenButtons/OpenTen
@onready var _open_all: Button = $Columns/Middle/OpenButtons/OpenAll


func _ready() -> void:
	if _res_close != null:
		_res_close.pressed.connect(func() -> void: hide_result_overlay())
	if _mod_close != null:
		_mod_close.pressed.connect(func() -> void: hide_module_overlay())
	_upgrade_btn.pressed.connect(func() -> void: upgrade_requested.emit())
	_open_one.pressed.connect(func() -> void: open_requested.emit(1))
	_open_ten.pressed.connect(func() -> void: open_requested.emit(10))
	_open_all.pressed.connect(func() -> void: open_requested.emit(0))
	# ★ v0.50：浮层的开 / 关**完全在 View 内部**——它不改任何数据，不需要绕 Model / Controller
	_pool_data_btn.pressed.connect(func() -> void: pool_data_requested.emit())
	_ov_sort.item_selected.connect(func(i: int) -> void: pool_sort_requested.emit(i))
	_ov_close.pressed.connect(func() -> void: _overlay.visible = false)
	_op_toggle.pressed.connect(func() -> void: operator_toggle_requested.emit())
	_box_btn.pressed.connect(func() -> void: box_button_clicked.emit())
	if _box_close != null:
		_box_close.pressed.connect(func() -> void: hide_box_overlay())


## 选中项下标（Controller 读走，转成 Model 的下标参数）。
var selected_index: int:
	get:
		return _selected_box


## ★ v0.79：浮层选中后由 Controller 调用（越界夹到 0）。
func set_selected_box(index: int) -> void:
	_selected_box = maxi(index, 0)
	box_changed.emit()

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
	# ★ v0.79：盲盒按钮 = 图标 + 一句话（点它开浮层选盒）
	var items: Array = s.get("box_items", [])
	if items.is_empty():
		_box_btn.text = "          还没有盲盒"
		if _box_icon != null:
			_box_icon.empty = true
	else:
		var cur: Dictionary = items[clampi(_selected_box, 0, items.size() - 1)]
		_box_btn.text = "          " + String(cur.get("label", ""))
		if _box_icon != null:
			_box_icon.empty = false
			_box_icon.quality = int(cur.get("quality", 1))

	# ── 左栏 · 中：模块镶嵌 ───────────────────────────────────────────────────
	_slot_detail.text = String(s.get("slot_detail", "—"))
	# ★ v0.78：**逐位暴露**——每位一个按钮；空位可点（点了弹模块浮层）
	_render_slot_buttons(s.get("slot_items", []))

	# ── 左栏 · 池子（★ v0.45）─────────────────────────────────────────────────

	# ── 池子数据浮层（★ v0.50）───────────────────────────────────────────────
	_ov_note.text = String(s.get("pool_table_note", ""))
	_ov_totals.text = String(s.get("pool_table_totals", ""))
	if _ov_sort.item_count == 0:
		for m in WishMachineModel.SORT_MODES:
			_ov_sort.add_item(m)
	_ov_sort.select(int(s.get("pool_table_sort_mode", 0)))
	_render_pool_table(s.get("pool_table_rows", []))

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


## ★ v0.50：把浮层的表格行**重建一遍**（每次 render 都重建 ⇒ 数据永远跟当前池子一致）。
##
## 为什么用代码建行而不是在场景里铺 N 个 Label：池子件数由套系品质与"添加物品"决定（8–12+），
## 静态节点会在增删物品后对不上；这里清空重填，逻辑与 `_refill` 同一套路子。
## ★ v0.52b：显示 / 隐藏浮层（由 Controller 在 refresh 之后调用，保证数据是新取的）。
func show_pool_overlay() -> void:
	_overlay.visible = true


func hide_pool_overlay() -> void:
	_overlay.visible = false


func is_pool_overlay_visible() -> bool:
	return _overlay.visible


func _render_pool_table(rows) -> void:
	for ch in _ov_rows.get_children():
		_ov_rows.remove_child(ch)
		ch.queue_free()
	var arr: Array = rows if rows is Array else []
	if arr.is_empty():
		var empty := Label.new()
		empty.text = "（这个池子还没有可陈列的物品）"
		_ov_rows.add_child(empty)
		return
	for r in arr:
		var masked := bool(r.get("masked", false))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_lbl := Label.new()
		name_lbl.text = String(r.get("name", ""))
		name_lbl.custom_minimum_size = Vector2(260, 0)
		row.add_child(name_lbl)
		var state_lbl := Label.new()
		state_lbl.text = String(r.get("state", ""))
		state_lbl.custom_minimum_size = Vector2(160, 0)
		row.add_child(state_lbl)
		var w_lbl := Label.new()
		w_lbl.text = "—" if masked else "%d" % int(r.get("weight_bp", 0))
		w_lbl.custom_minimum_size = Vector2(90, 0)
		w_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(w_lbl)
		var p_lbl := Label.new()
		p_lbl.text = "—" if masked else "%.2f%%" % (float(r.get("prob", 0.0)) * 100.0)
		p_lbl.custom_minimum_size = Vector2(90, 0)
		p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(p_lbl)
		var v_lbl := Label.new()
		v_lbl.text = "—" if masked else "%d 金币" % int(r.get("value", 0))
		v_lbl.custom_minimum_size = Vector2(90, 0)
		v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(v_lbl)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(spacer)
		_ov_rows.add_child(row)

# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.70：开盒结果浮层（用户裁决：结果不再占版面，改用浮层）
# ══════════════════════════════════════════════════════════════════════════════

## 打开结果浮层。`items` = `[{name, quality, count, mailed}, …]`，`foot` = 合计行。
func show_result_overlay(items, note: String, foot: String) -> void:
	_res_note.text = note
	_res_foot.text = foot
	for ch in _res_rows.get_children():
		_res_rows.remove_child(ch)
		ch.queue_free()
	var arr: Array = items if items is Array else []
	if arr.is_empty():
		var empty := Label.new()
		empty.text = "（这一轮没有开出物品）"
		_res_rows.add_child(empty)
	else:
		for it in arr:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var nm := Label.new()
			nm.text = String(it.get("name", ""))
			nm.custom_minimum_size = Vector2(300, 0)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nm)
			var q := Label.new()
			q.text = String(it.get("quality", ""))
			q.custom_minimum_size = Vector2(70, 0)
			row.add_child(q)
			var cnt := Label.new()
			cnt.text = "×%d%s" % [int(it.get("count", 1)), "（邮件）" if bool(it.get("mailed", false)) else ""]
			cnt.custom_minimum_size = Vector2(110, 0)
			cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(cnt)
			_res_rows.add_child(row)
	_res_overlay.visible = true


func hide_result_overlay() -> void:
	_res_overlay.visible = false


func is_result_overlay_visible() -> bool:
	return _res_overlay.visible

## ★ v0.78：把每个位子渲染成一个按钮（空位可点 ⇒ 发 `slot_clicked(slot)`）。
func _render_slot_buttons(items) -> void:
	for ch in _slot_row.get_children():
		_slot_row.remove_child(ch)
		ch.queue_free()
	var arr: Array = items if items is Array else []
	if arr.is_empty():
		var empty := Label.new()
		empty.text = "先选一个盲盒"
		_slot_row.add_child(empty)
		return
	for it in arr:
		var btn := Button.new()
		btn.text = String(it.get("label", ""))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# ★ v0.80：**位子按钮不参与"最小宽度"**——否则切到位数更多的盒子时，
		#   这一行会把中栏撑宽、三栏重新分配 ⇒ 整页布局跳动。
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.custom_minimum_size = Vector2(0, 0)
		var idx := int(it.get("index", 0))
		var occupied := bool(it.get("occupied", false))
		btn.disabled = occupied          # ★ v0.44：已镶的位子永久锁定，不可点
		if not occupied:
			btn.pressed.connect(func() -> void: slot_clicked.emit(idx))
		_slot_row.add_child(btn)


# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.78：模块选择浮层（点空位 ⇒ 列出仓库里的模块 ⇒ 点一项直接镶）
# ══════════════════════════════════════════════════════════════════════════════

func show_module_overlay(options, note: String) -> void:
	_mod_note.text = note
	for ch in _mod_rows.get_children():
		_mod_rows.remove_child(ch)
		ch.queue_free()
	var arr: Array = options if options is Array else []
	if arr.is_empty():
		var empty := Label.new()
		empty.text = "仓库里没有可用的模块（去市场买）"
		_mod_rows.add_child(empty)
	else:
		for o in arr:
			var btn := Button.new()
			btn.text = "%s · 品质 %d · 镶嵌 %d 金币 · 持有 %d" % [
				String(o.get("name", "")), int(o.get("quality", 1)),
				int(o.get("cost", 0)), int(o.get("owned", 0)),
			]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var mid := StringName(o.get("module_id", ""))
			btn.pressed.connect(func() -> void: module_picked.emit(mid))
			_mod_rows.add_child(btn)
	_mod_overlay.visible = true


func hide_module_overlay() -> void:
	_mod_overlay.visible = false


func is_module_overlay_visible() -> bool:
	return _mod_overlay.visible

# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.79：盲盒选择浮层（点图标按钮 ⇒ 列仓库里的盲盒 ⇒ 点一项切换）
# ══════════════════════════════════════════════════════════════════════════════

func show_box_overlay(items, note: String) -> void:
	_box_note.text = note
	for ch in _box_rows.get_children():
		_box_rows.remove_child(ch)
		ch.queue_free()
	var arr: Array = items if items is Array else []
	if arr.is_empty():
		var empty := Label.new()
		empty.text = "仓库里还没有盲盒（去市场买）"
		_box_rows.add_child(empty)
	else:
		for it in arr:
			# 每行 = 小图标 + 文案；整行是一个按钮
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 48)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var idx := int(it.get("index", 0))
			var cur := bool(it.get("current", false))
			btn.text = "        %s%s" % [String(it.get("label", "")), "（当前）" if cur else ""]
			var icon := BoxIcon.new()
			icon.quality = int(it.get("quality", 1))
			icon.size = Vector2(32, 32)
			icon.position = Vector2(8, 8)
			btn.add_child(icon)
			btn.pressed.connect(func() -> void: box_chosen.emit(idx))
			_box_rows.add_child(btn)
	_box_overlay.visible = true


func hide_box_overlay() -> void:
	_box_overlay.visible = false


func is_box_overlay_visible() -> bool:
	return _box_overlay.visible
## 市场页 —— View（★ v0.38 MVC）。
##
## **只渲染 + 只转发输入**：`render(snapshot)` 画 Model 算好的 `Dictionary`；
## 按钮 `pressed` 只 `emit` 信号（`buy_*`），不做任何业务。★ v0.63：**卖出入口已从市场页移除**。
##
## 时序同许愿机（方案 1）：Controller 用 `call_deferred("refresh")`，所以本类 `@onready` 一定就绪。
class_name MarketView
extends VBoxContainer

signal buy_item_requested(item_id: StringName)
## ★ v0.60：买盲盒（`box_id` 来自卡片按钮）
signal buy_box_requested(box_id: String)
## ★ v0.77：买模块（`module_id` 来自卡片按钮）
signal buy_module_requested(module_id: StringName)

@onready var _gold_lbl: Label = $Gold
@onready var _refresh_lbl: Label = $Refresh
@onready var _grid: GridContainer = $Scroll/Grid
@onready var _box_grid: GridContainer = $BoxScroll/BoxGrid
@onready var _mod_grid: GridContainer = $ModScroll/ModGrid
@onready var _result_lbl: Label = $Result


## ★ v0.63：`_ready()` 已删除——市场页的按钮都是**代码建的卡片按钮**（在 `_render_*` 里连接），
## 场景里不再有静态按钮需要在这里接线。


## ★ v0.60：**两列网格**铺"待售盲盒"，**每个盲盒一个购买按钮**。
func _render_box_cards(cards) -> void:
	for ch in _box_grid.get_children():
		_box_grid.remove_child(ch)
		ch.queue_free()
	var arr: Array = cards if cards is Array else []
	if arr.is_empty():
		var empty := Label.new()
		empty.text = "本次刷新没有可售盲盒（内容不足）"
		_box_grid.add_child(empty)
		return
	for c in arr:
		# 紧凑：左边两行文字、右边按钮 —— 8 张要能一屏放下（4 行 × 2 列）
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)

		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 2)
		row.add_child(body)

		var title := Label.new()
		title.text = "盲盒 · 品质 %d" % int(c.get("quality", 0))
		body.add_child(title)

		var info := Label.new()
		info.text = "%d 件 · 开盒 %d 原石 · 买价 %d 金币" % [
			int(c.get("size", 0)), int(c.get("gem_cost", 0)), int(c.get("price", 0)),
		]
		body.add_child(info)

		var buy := Button.new()
		buy.text = "购买盲盒"
		buy.pressed.connect(func() -> void: buy_box_requested.emit(String(c.get("box_id", ""))))
		row.add_child(buy)
		_box_grid.add_child(card)

## ★ v0.58：**两列网格**铺上架物品，**每件一个购买按钮**。
##
## 卡片是代码建的（件数 = `MarketService.SLOT_COUNT`，且随时刷新可能变）——
## 静态节点会在刷新后对不上，逻辑与许愿机页的"池子表格"同一套路子。
func _render_listing_cards(cards) -> void:
	for ch in _grid.get_children():
		_grid.remove_child(ch)
		ch.queue_free()
	var arr: Array = cards if cards is Array else []
	if arr.is_empty():
		var empty := Label.new()
		empty.text = "市场暂无可购买的物品"
		_grid.add_child(empty)
		return
	for c in arr:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 4)
		card.add_child(body)

		var name_lbl := Label.new()
		name_lbl.text = "%s（%s）" % [String(c.get("name", "")), String(c.get("quality", ""))]
		body.add_child(name_lbl)

		var price_lbl := Label.new()
		price_lbl.text = "%d 金币 · 剩 %d 件" % [int(c.get("price", 0)), int(c.get("qty", 0))]
		body.add_child(price_lbl)

		var buy := Button.new()
		buy.text = "购买"
		buy.pressed.connect(func() -> void: buy_item_requested.emit(StringName(c.get("item_id", ""))))
		body.add_child(buy)
		_grid.add_child(card)


## 用 Model 的快照渲染（调用方保证 @onready 已就绪）。
func render(s: Dictionary) -> void:
	_gold_lbl.text = String(s.get("gold", ""))
	_refresh_lbl.text = String(s.get("refresh", ""))

	# ★ v0.58：上架清单 = **两列网格，每件自带购买按钮**
	_render_listing_cards(s.get("listing_cards", []))
	_render_box_cards(s.get("box_cards", []))
	_render_module_cards(s.get("module_cards", []))

	_result_lbl.text = String(s.get("result", ""))


## 重填一个 OptionButton（保留原选中下标，越界则归 0）。
func _refill(picker: OptionButton, opts: Array) -> void:
	var prev := picker.selected
	picker.clear()
	for o in opts:
		picker.add_item(String(o))
	if prev >= 0 and prev < opts.size():
		picker.selected = prev

## ★ v0.77：**两列网格**铺"模块"，每张卡一个购买按钮（买了才有一件实体）。
func _render_module_cards(cards) -> void:
	for ch in _mod_grid.get_children():
		_mod_grid.remove_child(ch)
		ch.queue_free()
	var arr: Array = cards if cards is Array else []
	if arr.is_empty():
		var empty := Label.new()
		empty.text = "本次刷新没有可买模块"
		_mod_grid.add_child(empty)
		return
	for c in arr:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 2)
		row.add_child(body)
		var title := Label.new()
		title.text = String(c.get("name", ""))
		body.add_child(title)
		var info := Label.new()
		info.text = "品质 %d · 买价 %d 金币" % [int(c.get("quality", 1)), int(c.get("price", 0))]
		body.add_child(info)
		var buy := Button.new()
		buy.text = "购买模块"
		buy.pressed.connect(func() -> void:
			buy_module_requested.emit(StringName(c.get("module_id", ""))))
		row.add_child(buy)
		_mod_grid.add_child(card)
## 仓库页（★ v0.29）——游戏场景里第一个 tab 的完整内容，**独立场景**。
##
## 只做呈现，**只读**：
##   · 占用：只读 `ItemService.warehouse_usage()`（已含盲盒占位，v0.26），不自己求和、不做除法（P6）；
##   · 物品聚合：按 `(category, quality)` **一行一类**（7 类 × 6 档，只列有持有的档）；
##   · 盲盒：仓库 / 邮件分开列（v0.26：邮件里的盒子不可用）。
extends VBoxContainer

var state: GameState = null

@onready var _usage_lbl: Label = $Usage
@onready var _items_lbl: Label = $Items
@onready var _boxes_lbl: Label = $Boxes


func _ready() -> void:
	if state == null:
		state = GameSession.state
	refresh()


func bind_state(s: GameState) -> void:
	state = s
	refresh()


func refresh() -> void:
	var u := ItemService.warehouse_usage()
	_usage_lbl.text = "仓库占用 %d%%（%d / %d）" % [
		int(round(float(u["ratio"]) * 100.0)), int(u["used"]), int(u["capacity"]),
	]
	_items_lbl.text = _items_text()
	if state == null:
		_boxes_lbl.text = "尚未开局"
	else:
		var in_wh := state.boxes_in(ItemConstants.LOC_WAREHOUSE).size()
		var in_mail := state.boxes_in(ItemConstants.LOC_MAIL).size()
		_boxes_lbl.text = "盲盒：仓库 %d 个 / 邮件 %d 个" % [in_wh, in_mail]


## 物品聚合：**一行一类**（R5 / 08 R-31 的分组呈现），只列有持有的档。
func _items_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for cat in ItemCatalog.all_categories():
		var cells: PackedStringArray = PackedStringArray()
		for q in range(ItemConstants.QUALITY_MIN, ItemConstants.QUALITY_MAX + 1):
			var n := ItemService.count(StringName(cat.category_id), q)
			if n > 0:
				cells.append("%s×%d" % [ItemConstants.quality_name(q), n])
		if cells.size() > 0:
			lines.append("%s：%s" % [cat.display_name, "、".join(cells)])
	if lines.size() == 0:
		return "仓库里还没有物品"
	return "\n".join(lines)


## 供测试读取的只读快照。
func snapshot() -> Dictionary:
	return {"usage": _usage_lbl.text, "items": _items_lbl.text, "boxes": _boxes_lbl.text}

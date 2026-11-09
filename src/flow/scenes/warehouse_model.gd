## 仓库页 —— Model（★ v0.32 MVC 重构）。
##
## **纯数据与业务，不碰 UI**。只读口径（`11-flow.md` §2 边界）：
##   · 占用：只读 `ItemService.warehouse_usage()`（已含盲盒占位，v0.26），不自己求和、不做除法（P6）；
##   · 物品聚合：按 `(category, quality)` **一行一类**（7 类 × 6 档，只列有持有的档）；
##   · 盲盒：仓库 / 邮件分开列（v0.26：邮件里的盒子不可用）。
class_name WarehouseModel
extends RefCounted

var state: GameState = null


func bind(s: GameState) -> void:
	state = s


## 只读快照：View 唯一的数据来源。
func snapshot() -> Dictionary:
	var u := ItemService.warehouse_usage()
	var usage := "仓库占用 %d%%（%d / %d）" % [
		int(round(float(u["ratio"]) * 100.0)), int(u["used"]), int(u["capacity"]),
	]
	var boxes := "尚未开局"
	if state != null:
		var in_wh := state.boxes_in(ItemConstants.LOC_WAREHOUSE).size()
		var in_mail := state.boxes_in(ItemConstants.LOC_MAIL).size()
		boxes = "盲盒：仓库 %d 个 / 邮件 %d 个" % [in_wh, in_mail]
	return {"usage": usage, "items": items_text(), "boxes": boxes}


## 物品聚合：**一行一类**（R5 / 08 R-31 的分组呈现），只列有持有的档。
func items_text() -> String:
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

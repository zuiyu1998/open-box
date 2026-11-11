## 仓库页 —— Model（★ v0.32 MVC 重构；★ v0.37 网格布局）。
##
## **纯数据与业务，不碰 UI**。只读口径（`11-flow.md` §2 边界）：
##   · 占用：只读 `ItemService.warehouse_usage()`（已含盲盒占位），不自己求和、不做除法（P6）；
##   · 物品聚合：按 `(category, quality)` **一行一类**（R-31 的分组呈现），只列有持有的档；
##   · 盲盒：仓库 / 邮件分开列（v0.26：邮件里的盒子不可用）；
##   · **★ v0.37 网格布局**：把持有物排进"每格 128×128、共 `capacity` 格"的仓库网格。
##     **占格数 = `size.x * size.y`**；邮件物品也进网格，但标记 `locked`（不可用）。
class_name WarehouseModel
extends RefCounted

## ★ v0.37：**每格边长（像素）**——用户裁决"当前格子大小为 128×128"。
## 这是**唯一**的格子尺寸定义：`warehouse_grid.gd` 直接读本常量来画，别处不得另写一个数。
const CELL_SIZE := 128

## ★ v0.37：**网格列数固定为 12**（用户裁决）。
## 行数 = `ceil(占格总数 / 12)`；`128×12 = 1536 px` 宽。
## 注意：**任何物品的 `size.x` 都不得 > 12**，否则该物品永远放不进这一行（会落入 `unplaced`）；
## 当前全部物品 1×1，无此风险；将来做宽物品时须一起重审列数。
const GRID_COLUMNS := 12

## 一块块上的标签最多显示几个字（超出截断，避免画出格子）。
const LABEL_MAX_CHARS := 8

var state: GameState = null


func bind(s: GameState) -> void:
	state = s


## 只读快照：View 唯一的数据来源。
func snapshot() -> Dictionary:
	var u := ItemService.warehouse_usage()
	var usage := "仓库占用 %d%%（%d / %d 格）" % [
		int(round(float(u["ratio"]) * 100.0)), int(u["used"]), int(u["capacity"]),
	]
	var boxes := "尚未开局"
	if state != null:
		var in_wh := state.boxes_in(ItemConstants.LOC_WAREHOUSE).size()
		var in_mail := state.boxes_in(ItemConstants.LOC_MAIL).size()
		boxes = "盲盒：仓库 %d 个 / 邮件 %d 个" % [in_wh, in_mail]
	return {
		"usage": usage,
		"items": items_text(),
		"boxes": boxes,
		"grid": grid(),
	}


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


# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.37：仓库网格布局
# ══════════════════════════════════════════════════════════════════════════════

## 网格布局（**单位是"格"，不是像素**——像素由 View 乘 `CELL_SIZE`）。
##
## 返回：
##   `cell_size`      每格边长（px，= `CELL_SIZE`）
##   `capacity`       仓库容量（格数）——**画出的"仓库空间"就是它**
##   `columns`/`rows` 网格行列数（`rows * columns >= capacity`）
##   `placed`         已放置的块：`{x, y, w, h, label, color, locked, kind, …}`
##   `unplaced`       放不下的块（矩形装箱碎片化时的兜底，正常应为空）
##
## **放置顺序**（确定性，便于测试与复现）：仓库物品 → 仓库盲盒 → 邮件物品 → 邮件盲盒。
## 仓库侧一定落在 `capacity` 之内（容量记账保证 `Σ 格数 <= capacity`）；
## **邮件侧不计入容量**，因此允许越过 `capacity` 继续往后排（它本来就不占仓库空间）。
func grid() -> Dictionary:
	var capacity := maxi(ItemService.warehouse_capacity, 1)
	# ★ v0.37：**列数固定 12**（用户裁决）——不再按容量/物品宽度自适应。
	var columns := GRID_COLUMNS
	# 占位表按行主序展开：`index = row * columns + col`；按需扩容（邮件侧会越过 capacity）
	var occupied := PackedByteArray()
	occupied.resize(capacity)

	var placed: Array = []
	var unplaced: Array = []

	# ── 分组：仓库侧在前，邮件侧在后（视觉上"能用的先排、锁着的排后面"）──────────
	var wh_items: Array = []
	var mail_items: Array = []
	for inst in ItemService.instances:
		if WarehouseService.is_warehouse(inst.instance_id):
			wh_items.append(inst)
		else:
			mail_items.append(inst)

	var wh_boxes: Array = []
	var mail_boxes: Array = []
	if state != null:
		wh_boxes = state.boxes_in(ItemConstants.LOC_WAREHOUSE)
		mail_boxes = state.boxes_in(ItemConstants.LOC_MAIL)

	for inst in wh_items:
		_try_place_item(inst, false, occupied, columns, placed, unplaced)
	for b in wh_boxes:
		_try_place_box(b, false, occupied, columns, placed, unplaced)
	for inst in mail_items:
		_try_place_item(inst, true, occupied, columns, placed, unplaced)
	for b in mail_boxes:
		_try_place_box(b, true, occupied, columns, placed, unplaced)

	# 画出的格数 = max(容量, 已用到的最后一格 + 1)
	var rows := maxi(int(ceil(float(occupied.size()) / float(columns))), 1)
	return {
		"cell_size": CELL_SIZE,
		"capacity": capacity,
		"columns": columns,
		"rows": rows,
		"placed": placed,
		"unplaced": unplaced,
	}


## 尝试把一件物品放进网格（**首次适配**：行主序找第一个能放下的锚点）。
func _try_place_item(
	inst: ItemInstance,
	locked: bool,
	occupied: PackedByteArray,
	columns: int,
	placed: Array,
	unplaced: Array
) -> void:
	var def := ItemCatalog.get_def(inst.item_id)
	if def == null:
		return
	var w := maxi(def.size.x, 1)
	var h := maxi(def.size.y, 1)
	var anchor := _find_anchor(occupied, columns, w, h)
	if anchor.x < 0:
		unplaced.append({
			"instance_id": inst.instance_id, "item_id": String(inst.item_id),
			"w": w, "h": h, "locked": locked,
		})
		return
	_mark(occupied, columns, anchor, w, h)
	placed.append({
		"x": anchor.x, "y": anchor.y, "w": w, "h": h,
		"label": _item_label(def, inst),
		"color": ItemConstants.quality_color(def.quality),
		"locked": locked,
		"kind": "item",
		"instance_id": inst.instance_id,
	})


## 盲盒：**固定 1×1**（`Box.size` 与容量账同口径）。
func _try_place_box(
	b: Box,
	locked: bool,
	occupied: PackedByteArray,
	columns: int,
	placed: Array,
	unplaced: Array
) -> void:
	var anchor := _find_anchor(occupied, columns, 1, 1)
	if anchor.x < 0:
		unplaced.append({"box_id": b.box_id, "w": 1, "h": 1, "locked": locked})
		return
	_mark(occupied, columns, anchor, 1, 1)
	placed.append({
		"x": anchor.x, "y": anchor.y, "w": 1, "h": 1,
		"label": "盲盒",
		"color": Color("#7A5CF0"),   # 盲盒用固定色（它没有物品品质）
		"locked": locked,
		"kind": "box",
		"box_id": b.box_id,
	})


## 行主序首次适配：返回锚点（左上角格坐标）；放不下返回 `(-1, -1)`。
##
## **允许越过现有占位范围继续往后排**——邮件侧不计入容量，网格按需向下增长。
## 扫描行数上界 = `(现有格数 + 本块面积) / 列数 + 块高 + 1`（最坏情况也够用）。
func _find_anchor(occupied: PackedByteArray, columns: int, w: int, h: int) -> Vector2i:
	var limit_rows := int(ceil(float(occupied.size() + w * h) / float(columns))) + h + 1
	for row in limit_rows:
		for col in columns:
			if _fits_at(occupied, columns, col, row, w, h):
				return Vector2i(col, row)
	return Vector2i(-1, -1)


## 指定锚点能否放下 `w × h`（逐格检查；超出现有占位表即视为空闲，`_mark` 时再扩容）。
func _fits_at(occupied: PackedByteArray, columns: int, col: int, row: int, w: int, h: int) -> bool:
	for dy in h:
		for dx in w:
			var idx := (row + dy) * columns + (col + dx)
			if idx < occupied.size() and occupied[idx] != 0:
				return false
	return true


## 标记占用（必要时扩容占位表——邮件侧会排在 `capacity` 之后）。
func _mark(occupied: PackedByteArray, columns: int, anchor: Vector2i, w: int, h: int) -> void:
	for dy in h:
		for dx in w:
			var idx := (anchor.y + dy) * columns + (anchor.x + dx)
			while idx >= occupied.size():
				occupied.resize(occupied.size() + columns)
			occupied[idx] = 1


## 块上的短标签：物品名（过长截断）+ 收藏编号（若有）。
func _item_label(def: ItemDef, inst: ItemInstance) -> String:
	var base := def.display_name if def.display_name != "" else String(def.item_id)
	if inst.serial > 0:
		base = "%s #%d" % [base, inst.serial]
	if base.length() > LABEL_MAX_CHARS:
		base = base.substr(0, LABEL_MAX_CHARS)
	return base

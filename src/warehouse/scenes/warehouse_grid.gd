## 仓库网格 —— View 的绘制层（★ v0.37）。
##
## **只画**：一个由 `capacity` 个方格组成的仓库，以及落在格子上的物品块。
## 数据全部来自 `WarehouseModel.grid()`（本类**不查任何服务、不做任何业务判断**）。
##
## 为什么自绘而不是 1000 个 ColorRect 节点：
##   · 1000 个格子 × 上千实例的块 = 数千个 Control，光树结构就吃掉帧预算；
##   · 网格与块都是"矩形 + 文本"，`_draw()` 一次画完更省，且尺寸变化时只 `queue_redraw()`。
##
## 坐标约定：模型给的是**格坐标**（x / y / w / h），本类乘 `cell_size` 换成像素。
class_name WarehouseGrid
extends Control

## 空格子的底色（仓库地面）。
const COLOR_EMPTY := Color("#1B1E27")
## 网格线。
const COLOR_GRID_LINE := Color("#33FFFFFF")
## 容量边界的强调线（`capacity` 之后是"邮件区"，不属于仓库空间）。
const COLOR_CAPACITY_EDGE := Color("#FFF2B01E")
## 占位块的内边距（像素，视觉上让块之间留缝）。
const BLOCK_INSET := 3.0
## 锁定块（邮件物品）的遮罩透明度。
const COLOR_LOCKED_VEIL := Color(0.0, 0.0, 0.0, 0.55)
## 文本颜色。
const COLOR_LABEL := Color("#FFFFFF")

var _layout: Dictionary = {}


## 接收布局（`WarehouseModel.grid()` 的返回值）并按需要调整自身尺寸。
func set_layout(layout: Dictionary) -> void:
	_layout = layout
	var cell := int(layout.get("cell_size", 128))
	var cols := maxi(int(layout.get("columns", 1)), 1)
	var rows := maxi(int(layout.get("rows", 1)), 1)
	custom_minimum_size = Vector2(cols * cell, rows * cell)
	queue_redraw()


## 当前是否已绑定布局（测试用）。
func has_layout() -> bool:
	return not _layout.is_empty()


## 已放置的块数（测试用）。
func placed_count() -> int:
	return (_layout.get("placed", []) as Array).size()


func _draw() -> void:
	if _layout.is_empty():
		return
	var cell := int(_layout.get("cell_size", 128))
	var cols := maxi(int(_layout.get("columns", 1)), 1)
	var rows := maxi(int(_layout.get("rows", 1)), 1)
	var capacity := int(_layout.get("capacity", cols * rows))
	var total := Vector2(cols * cell, rows * cell)

	# ── ① 仓库地面（空格子）──────────────────────────────────────────────────
	draw_rect(Rect2(Vector2.ZERO, total), COLOR_EMPTY, true)

	# ── ② 网格线 ─────────────────────────────────────────────────────────────
	for c in range(cols + 1):
		var x := float(c * cell)
		draw_line(Vector2(x, 0.0), Vector2(x, total.y), COLOR_GRID_LINE, 1.0)
	for r in range(rows + 1):
		var y := float(r * cell)
		draw_line(Vector2(0.0, y), Vector2(total.x, y), COLOR_GRID_LINE, 1.0)

	# ── ③ 容量边界（第 capacity 格之后属于"邮件区"，画一条强调线）──────────────
	if capacity < cols * rows:
		var edge_row := capacity / cols
		var edge_col := capacity % cols
		var edge := Vector2(float(edge_col * cell), float(edge_row * cell))
		if edge_col == 0:
			draw_line(Vector2(0.0, edge.y), Vector2(total.x, edge.y), COLOR_CAPACITY_EDGE, 3.0)
		else:
			draw_line(edge, Vector2(total.x, edge.y), COLOR_CAPACITY_EDGE, 3.0)

	# ── ④ 物品块 ─────────────────────────────────────────────────────────────
	var font := ThemeDB.fallback_font
	var font_size := int(maxi(int(float(cell) * 0.16), 10))
	for raw in (_layout.get("placed", []) as Array):
		if not (raw is Dictionary):
			continue
		var p: Dictionary = raw
		var rect := Rect2(
			Vector2(float(int(p["x"]) * cell), float(int(p["y"]) * cell)) + Vector2(BLOCK_INSET, BLOCK_INSET),
			Vector2(float(int(p["w"]) * cell), float(int(p["h"]) * cell)) - Vector2(BLOCK_INSET, BLOCK_INSET) * 2.0
		)
		var color: Color = p.get("color", Color.WHITE)
		# 块体
		draw_rect(rect, Color(color.r, color.g, color.b, 0.82), true)
		# 边框（锁定态用虚线感的深色边，与可用的块区分）
		var border := Color(0.0, 0.0, 0.0, 0.9) if bool(p.get("locked", false)) else color.lightened(0.35)
		draw_rect(rect, border, false, 2.0)
		# 邮件里的东西：整块压暗 + 一个锁记号（不靠颜色单独表达，避免只靠色相辨别）
		if bool(p.get("locked", false)):
			draw_rect(rect, COLOR_LOCKED_VEIL, true)
			var lock := "🔒" if font != null else "L"
			if font != null:
				draw_string(font, rect.position + Vector2(4.0, float(font_size) + 2.0), lock,
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, COLOR_LABEL)
		# 标签
		if font != null and rect.size.x > float(font_size) * 2.0:
			var label := String(p.get("label", ""))
			draw_string(font, rect.position + Vector2(4.0, rect.size.y - 6.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, font_size, COLOR_LABEL)

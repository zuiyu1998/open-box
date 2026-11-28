## 盲盒图标（★ v0.79）：**代码绘制**，不依赖贴图资源。
##
## 为什么画而不是用图片：仓库里一张图标资源都没有（只有项目图 `icon.svg`），
## 而"盲盒图标"需要**按品质换颜色**（4 档）——画出来只要十几行，且随容器缩放不糊。
##
## 画的是最简的"箱子"语汇：**箱体 + 盖沿 + 中间捆带**。
class_name BoxIcon
extends Control

## 1–4；决定主色。
var quality: int = 1:
	set(v):
		quality = clampi(v, 1, 4)
		queue_redraw()

## 空盒（没有盒子时）用灰调。
var empty: bool = false:
	set(v):
		empty = v
		queue_redraw()

## 品质色（与物品品质配色口径一致：白 / 绿 / 蓝 / 紫）。
const QUALITY_COLOR := {
	1: Color(0.78, 0.78, 0.80),   # 白
	2: Color(0.42, 0.78, 0.44),   # 绿
	3: Color(0.40, 0.66, 0.95),   # 蓝
	4: Color(0.72, 0.50, 0.95),   # 紫
}


func _init() -> void:
	custom_minimum_size = Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 让点击穿透给外层按钮


func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var base: Color = Color(0.45, 0.45, 0.48) if empty else (QUALITY_COLOR.get(quality, QUALITY_COLOR[1]) as Color)
	var body := Rect2(Vector2(s.x * 0.12, s.y * 0.34), Vector2(s.x * 0.76, s.y * 0.54))
	# 箱体
	draw_rect(body, base.darkened(0.35), true)
	draw_rect(body, base, false, maxf(1.0, s.x * 0.05))
	# 盖沿（比箱体宽一点、略高）
	var lid := Rect2(Vector2(s.x * 0.06, s.y * 0.20), Vector2(s.x * 0.88, s.y * 0.16))
	draw_rect(lid, base.darkened(0.15), true)
	draw_rect(lid, base.lightened(0.15), false, maxf(1.0, s.x * 0.05))
	# 中间捆带
	var band := Rect2(Vector2(s.x * 0.44, s.y * 0.20), Vector2(s.x * 0.12, s.y * 0.68))
	draw_rect(band, base.lightened(0.25), true)

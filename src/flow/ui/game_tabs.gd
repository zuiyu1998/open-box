## 游戏顶栏的 TabContainer（★ v0.53）。
##
## **规格的唯一来源**：字体 / 横向内边距 / 高度都只在这里定义，`GameScreen` 只做校验。
##
## 三条实测结论（别改回去）：
##   1. **`Theme` 进不去内部 `TabBar`**——赋给 TabContainer 的 `theme` 不行，
##      `project.godot` 的 `gui/theme/custom` 也不行（按 `TabBar` 类型显式查仍是 16）。
##      ⇒ 只有**直接对实例 `add_theme_*_override`** 有效。
##   2. **主题覆盖在本节点 `_ready` 里打会被丢弃**（同一实例上 `custom_minimum_size` 却留得住）——
##      所以覆盖要**推迟一帧**再打；**高度必须早设**，因为首次布局只认当时的最小尺寸。
##   3. **`TabContainer` 的页面偏移只算一次**（按首次布局时的 tab 高度），之后 bar 变高也**不回填**。
##      ⇒ 页面下移由 `GameScreen._fix_page_offset()` 显式负责（见那边的注释）。
class_name GameTabs
extends TabContainer

## tab 头的尺寸——**唯一定义在这里**。
const FONT_SIZE := 21
const MARGIN_H := 24.0
const HEIGHT := 62.0


func _ready() -> void:
	# ① 高度：**必须早设**（首次布局按它给页面定位）
	var bar := get_tab_bar()
	if bar != null:
		bar.custom_minimum_size = Vector2(0.0, HEIGHT)
	# ② 字体与内边距：推迟一帧，否则会被本节点的初始化流程丢掉
	_apply_theme_overrides.call_deferred()


func _apply_theme_overrides() -> void:
	var bar := get_tab_bar()
	if bar == null:
		return
	if bar.get_theme_font_size("font_size") == FONT_SIZE:
		return                                  # 已打过（幂等，避免重复加内边距）
	bar.add_theme_font_size_override("font_size", FONT_SIZE)
	for sb_name in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled", "tab_focus"]:
		var base := bar.get_theme_stylebox(sb_name)
		if base == null:
			continue
		var sb := base.duplicate() as StyleBox
		if sb == null:
			continue
		sb.content_margin_left = maxf(sb.content_margin_left, 0.0) + MARGIN_H
		sb.content_margin_right = maxf(sb.content_margin_right, 0.0) + MARGIN_H
		bar.add_theme_stylebox_override(sb_name, sb)

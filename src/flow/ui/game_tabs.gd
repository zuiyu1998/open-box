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

## ★ v0.74：**页面顶部要留的间距**（页面从 `HEIGHT + GAP` 开始）。
##
## 为什么需要：**选中的那个 tab 的背景比其它 tab 高约 10px**（`tab_selected` 的
## content margin 不同），它会盖住页面的第一行——实测"许愿机"标题的上沿被压掉。
## 间距放在这里而不是页面里，是因为它属于"tab 条占多高"这件事。
const PAGE_TOP_GAP := 10.0

## ★ v0.76：tab 的上下内容边距（**五个状态统一**，否则选中态更高、会盖住页面第一行）。
const V_PAD := 12.0


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
		# ★ v0.76：**五个状态的上下边距必须一致**——默认主题里 `tab_selected` 的下边距更大，
		#   于是"选中的那个 tab 比其它高约 10px"，它的背景会盖住页面第一行（实测就是它）。
		#   统一成 `V_PAD` 后所有 tab 等高，重叠从根上消失。
		sb.content_margin_top = V_PAD
		sb.content_margin_bottom = V_PAD
		bar.add_theme_stylebox_override(sb_name, sb)

# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.75：**页面偏移归本类**（每次排序后自动重打，切 tab 不会被覆盖）
# ══════════════════════════════════════════════════════════════════════════════

## `TabContainer` 在 `NOTIFICATION_SORT_CHILDREN` 里把每个页面摆到 `bar` 正下方——
## **切 tab / 改尺寸 / 增减页都会重跑它**，于是 `+PAGE_TOP_GAP` 会被覆盖回 0。
## 这里在**同一通知之后**（deferred）再打一次，覆盖顺序就稳定了。
func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		apply_page_offset.call_deferred()


## 把每个页面下移 `HEIGHT + PAGE_TOP_GAP`，高度相应减去（幂等）。
func apply_page_offset() -> void:
	var h := HEIGHT + PAGE_TOP_GAP
	for i in get_tab_count():
		var pg := get_child(i)
		if pg is Control:
			var c := pg as Control
			c.position.y = h
			c.size = Vector2(size.x, maxf(size.y - h, 0.0))
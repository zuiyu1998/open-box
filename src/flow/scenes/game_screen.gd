## 游戏场景（★ v0.27 / v0.29：顶层 `TabContainer` 分页；★ v0.38「市场」、v0.39「公司」、v0.40「干员」）。
##
## **本脚本只管 tab 骨架**（各页的内容都在自己的场景里）：
##   · **仓库 tab** → `src/warehouse/scenes/warehouse_page.tscn`（★ 仓库页归 12）
##   · **许愿机 tab** → `src/flow/scenes/wish_machine.tscn`（★ 设备的名字，v0.29）
##   · **市场 tab** → `src/market/scenes/market_page.tscn`（★ v0.38 归 13）
##   · **公司 tab** → `src/company/scenes/company_page.tscn`（★ v0.39 归 14）
##   · **干员 tab** → `src/operator/scenes/operator_page.tscn`（★ v0.40 归 15）
##
## 纪律：只读为主；开盒 / 升级 / 买卖 / 出战切换的写入都在 01/04/13/14/15 的入口里；
## 本层不改 `GameState` / `ItemService` 的数据。
## `state` 由外部注入（`bind_state()`），未注入时从 `GameSession.state` 取（v0.28 的流程接入）。
extends Control

const TAB_WAREHOUSE := "仓库"
const TAB_WISH := "许愿机"
const TAB_MARKET := "市场"
const TAB_COMPANY := "公司"
const TAB_OPERATOR := "干员"
## ★ v0.36：仓库页已迁到 `src/warehouse/scenes/`（内容归 12，本系统只把场景放进 tab）。
const WAREHOUSE_SCENE := "res://src/warehouse/scenes/warehouse_page.tscn"
const WISH_SCENE := "res://src/flow/scenes/wish_machine.tscn"
## ★ v0.38：市场页归 13。
const MARKET_SCENE := "res://src/market/scenes/market_page.tscn"
## ★ v0.39：公司页归 14。
const COMPANY_SCENE := "res://src/company/scenes/company_page.tscn"
## ★ v0.40：干员页归 15。
const OPERATOR_SCENE := "res://src/operator/scenes/operator_page.tscn"

## 由外部注入的运行时状态（测试 / 读档完成后注入）。
var state: GameState = null

## ★ v0.43：tab 头的尺寸。默认（16px 字体 + 窄内边距）在 1920×1080 上小到看不清，
## 点起来也费劲。这几个常量是 tab 条的**唯一尺寸来源**，别在场景里另写一套。
##
## ★ v0.53：**高度改用 `custom_minimum_size.y` 定死**，不再靠上下 content_margin 撑。
##   原因：`TabContainer` 是按**内部 `TabBar` 的最小尺寸**给页面定位的。只改 StyleBox 的内边距时，
##   容器未必重排（实测页面仍按 31px 定位 ⇒ 顶部一条被压在 tab 条下面）；
##   而**最小尺寸变化会让父容器自动重排**，所以把 height 交给 `custom_minimum_size` 最稳。
# ★ v0.53：**规格的唯一来源是 `GameTabs`**（挂在 Tabs 节点上的脚本，在首次布局前落到内部 TabBar）。
const TAB_FONT_SIZE := GameTabs.FONT_SIZE

@onready var _tabs: TabContainer = $Tabs
@onready var _gold_lbl: Label = $TopBar/Gold
@onready var _gem_lbl: Label = $TopBar/Gem


func _ready() -> void:
	if state == null:
		state = GameSession.state
	_ensure_tabs()
	# ★ v0.38：**切 tab 时刷新**——玩家在别的页开盒 / 买进物品后，切回仓库页必须看到最新持有。
	#   各页的 `refresh()` 是纯重算（读 ItemService / MarketService 当前态），不产生副作用。
	_tabs.tab_changed.connect(func(_idx: int) -> void: refresh())
	# ★ v0.53：**布局结束后再打一次 tab 样式**。
	#   实测（真实流程：菜单 →「新游戏」→ 本场景）：`_ready` 里打的覆盖**在首次布局后被清掉**，
	#   而那时之后没有任何 `refresh()`（`tab_changed` 要等玩家点 tab），于是**一进游戏 tab 还是小的**，
	#   直到玩家切一次 tab 才变大。`resized` 在首次布局完成时触发 ⇒ 在这里补一次（幂等，不会叠加边距）。
	_tabs.resized.connect(_style_tabs)
	_tabs.resized.connect(_queue_fix_page_offset)
	call_deferred("_style_tabs")
	call_deferred("_queue_fix_page_offset")
	refresh()


## ★ v0.43：**加大 tab 头**。
##
## 两条实测结论（见 `_rt/probe.gd` 的探针）：
##   · **`Theme` 继承不到内部 `TabBar`**：把 `TabBar` 条目塞进 `Theme` 赋给 `Tabs`，
##     字体仍是 16（TabContainer 的内部子节点不吃祖先 theme 的 `TabBar` 类型条目）。
##   · **直接对 `get_tab_bar()` 加覆盖有效**，但**必须在 tab 建好之后**打
##     （在 `_ready` 里、`_ensure_tabs()` 之前打会丢）。
## 因此：`refresh()` 里、`_ensure_tabs()` 之后调用本方法；用**字体已是目标值**做幂等判据，
## 这样 TabBar 若被重建（新实例、字体回到 16）会**自动重装**，而已装好时不会把内边距叠加变大。
func _style_tabs() -> void:
	# ★ v0.53：**规格已交给项目默认主题**（`project.godot` 的 `gui/theme/custom` →
	#   `assets/ui/game_tab_theme.tres`，由 `tools/gen_tab_theme.gd` 生成）。
	#
	# 为什么不在运行时改内部 TabBar：`TabContainer` 只在**首次布局**时按内部 `TabBar` 的最小高度
	# 给页面定位；之后再改 Bar 的字体 / 尺寸，**页面偏移不会回填** ⇒ 顶部一条被压在 tab 条底下
	# （实测：bar 62px、页面仍停在 31px）。主题是声明式的，布局一开始就对。
	#
	# 本函数现在只做一件事：**校验主题真的生效了**（没生效时报一条错，而不是静默变回小 tab）。
	var bar := _tabs.get_tab_bar()
	if bar == null:
		return
	_fix_page_offset()
	var fs := bar.get_theme_font_size("font_size")
	if fs != TAB_FONT_SIZE:
		push_warning(
			"tab 样式未生效：font_size=%d，期望 %d —— 检查 Tabs 节点的 GameTabs 脚本（src/flow/ui/game_tabs.gd）" % [fs, TAB_FONT_SIZE]
		)

func bind_state(s: GameState) -> void:
	state = s
	refresh()


## 顶层 tabs 的标题（**唯一来源就是 TabContainer 自己**，不另存一张表）。
func tab_titles() -> Array[String]:
	var out: Array[String] = []
	for i in _tabs.get_tab_count():
		out.append(_tabs.get_tab_title(i))
	return out


## 取某个 tab 的内容节点（测试与外部联动用）。
func page_node(node_name: String) -> Node:
	return _tabs.get_node_or_null(node_name)


func refresh() -> void:
	_ensure_tabs()
	_style_tabs()   # ★ v0.43：必须在 tab 建好之后（见该函数的注释）
	for page_name in ["WarehousePage", "WishPage", "MarketPage", "CompanyPage", "OperatorPage"]:
		var page := page_node(page_name)
		if page == null:
			continue
		# ★ MVC 页的 bind_state 在子节点 `Controller` 上
		var target := page
		var ctrl := page.get_node_or_null("Controller")
		if ctrl != null and ctrl.has_method("bind_state"):
			target = ctrl
		if target.has_method("bind_state"):
			target.bind_state(state)
	_refresh_currency()


## ★ v0.43：右上角的**金币 / 原石**读数。
##
## 只读 `ItemService.currency_balance()`——02 是资源余额的唯一写入方，
## 本层**不缓存、不做加减**（与 04 / 13 / 14 对 02 的同一纪律）。
## 每次 `refresh()`（切 tab / 换局）都会重取，因此开盒、买盲盒、升级后切一次 tab 就是最新值。
func _refresh_currency() -> void:
	if _gold_lbl != null:
		_gold_lbl.text = "金币 %d" % ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	if _gem_lbl != null:
		_gem_lbl.text = "原石 %d" % ItemService.currency_balance(ItemConstants.CURRENCY_GEM)


# ══════════════════════════════════════════════════════════════════════════════
#  tab 骨架
# ══════════════════════════════════════════════════════════════════════════════

func _ensure_tabs() -> void:
	# ★ **只在缺失时建**（v0.29）：`refresh()` 会反复调用本方法，若每次都重建，
	#   外部持有的页引用会变成"已释放实例"。
	if _tabs.get_tab_count() == 5 \
			and page_node("WarehousePage") != null \
			and page_node("WishPage") != null \
			and page_node("MarketPage") != null \
			and page_node("CompanyPage") != null \
			and page_node("OperatorPage") != null:
		return
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	# ★ v0.54（用户裁决）：**许愿机是第一个 tab**（它是核心循环，进游戏先看到它）。
	#   其余四页保持原相对顺序：许愿机 / 仓库 / 市场 / 公司 / 干员。
	var wish := _load_page(WISH_SCENE, "WishPage")
	# ★ 子节点名决定 TabContainer 的 key：统一成 `WishPage`，外部按名字取页才稳定
	#   （场景根自己的名字 `WishMachine` 只用于那页场景单独使用时的语义）
	wish.name = "WishPage"
	_tabs.add_child(wish)
	var wh := _load_page(WAREHOUSE_SCENE, "WarehousePage")
	wh.name = "WarehousePage"
	_tabs.add_child(wh)
	var mkt := _load_page(MARKET_SCENE, "MarketPage")
	mkt.name = "MarketPage"
	_tabs.add_child(mkt)
	var cmp := _load_page(COMPANY_SCENE, "CompanyPage")
	cmp.name = "CompanyPage"
	_tabs.add_child(cmp)
	var opr := _load_page(OPERATOR_SCENE, "OperatorPage")
	opr.name = "OperatorPage"
	_tabs.add_child(opr)
	_tabs.set_tab_title(0, TAB_WISH)
	_tabs.set_tab_title(1, TAB_WAREHOUSE)
	_tabs.set_tab_title(2, TAB_MARKET)
	_tabs.set_tab_title(3, TAB_COMPANY)
	_tabs.set_tab_title(4, TAB_OPERATOR)
	_tabs.current_tab = 0


## 载入一页；场景缺失时退化为一个空 `VBoxContainer`（**不崩**，但仍会报错提示）。
func _load_page(path: String, node_name: String) -> Node:
	if ResourceLoader.exists(path):
		var page = (load(path) as PackedScene).instantiate()
		if page != null:
			return page
	push_error("GameScreen: 页面场景不存在 `%s`" % path)
	var fallback := VBoxContainer.new()
	fallback.name = node_name
	var lbl := Label.new()
	lbl.name = "MissingHint"
	lbl.text = "页面场景缺失：%s" % path
	fallback.add_child(lbl)
	return fallback


## ★ v0.53：**把页面下移到 tab 条之下**。
##
## 为什么必须自己算：`TabContainer` 的页面偏移来自**首次布局时**的 tab 高度（31px），
## 之后 tab 条变高（62px）它**不回填** —— 结果页面顶部第一条被压在 tab 条底下
## （真实截图：仓库页"仓库占用 0%"那行被 tab 压住）。
## 这里在**样式就位之后**显式把每个页面放到 `GameTabs.HEIGHT` 之下，并在窗口尺寸变化后重做一次。
func _fix_page_offset() -> void:
	var h := GameTabs.HEIGHT
	for i in _tabs.get_tab_count():
		var pg := _tabs.get_child(i)
		if pg is Control:
			var c := pg as Control
			c.position.y = h
			c.size = Vector2(_tabs.size.x, maxf(_tabs.size.y - h, 0.0))


func _queue_fix_page_offset() -> void:
	# 延后一帧：等 `TabContainer` 自己这一轮的排序跑完，否则会被它覆盖回旧偏移
	_fix_page_offset.call_deferred()
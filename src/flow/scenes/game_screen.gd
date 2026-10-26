## 游戏场景（★ v0.27 / v0.29：顶层 `TabContainer` 分页，两个 tab）。
##
## **本脚本只管 tab 骨架**（各页的内容都在自己的场景里）：
##   · **仓库 tab** → `src/flow/scenes/warehouse_page.tscn`（占用 + 按类别分组的物品聚合 + 盲盒数）
##   · **许愿机 tab** → `src/flow/scenes/wish_machine.tscn`
##     （★ v0.29 用户裁决：**许愿机就是设备的名字**，把它整个 tabitem 的内容做成一个场景）
##
## 纪律：只读为主；开盒 / 升级的写入都在 01/04 的入口里；本层不改 `GameState` / `ItemService` 的数据。
## `state` 由外部注入（`bind_state()`），未注入时从 `GameSession.state` 取（v0.28 的流程接入）。
extends Control

const TAB_WAREHOUSE := "仓库"
const TAB_WISH := "许愿机"
const WAREHOUSE_SCENE := "res://src/flow/scenes/warehouse_page.tscn"
const WISH_SCENE := "res://src/flow/scenes/wish_machine.tscn"

## 由外部注入的运行时状态（测试 / 读档完成后注入）。
var state: GameState = null

@onready var _tabs: TabContainer = $Tabs


func _ready() -> void:
	if state == null:
		state = GameSession.state
	_ensure_tabs()
	refresh()


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
	for page_name in ["WarehousePage", "WishPage"]:
		var page := page_node(page_name)
		if page != null and page.has_method("bind_state"):
			page.bind_state(state)


# ══════════════════════════════════════════════════════════════════════════════
#  tab 骨架
# ══════════════════════════════════════════════════════════════════════════════

func _ensure_tabs() -> void:
	# ★ **只在缺失时建**（v0.29）：`refresh()` 会反复调用本方法，若每次都重建，
	#   外部持有的页引用会变成"已释放实例"。
	if _tabs.get_tab_count() == 2 and page_node("WarehousePage") != null and page_node("WishPage") != null:
		return
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	var wh := _load_page(WAREHOUSE_SCENE, "WarehousePage")
	wh.name = "WarehousePage"
	_tabs.add_child(wh)
	var wish := _load_page(WISH_SCENE, "WishPage")
	# ★ 子节点名决定 TabContainer 的 key：统一成 `WishPage`，外部按名字取页才稳定
	#   （场景根自己的名字 `WishMachine` 只用于那页场景单独使用时的语义）
	wish.name = "WishPage"
	_tabs.add_child(wish)
	_tabs.set_tab_title(0, TAB_WAREHOUSE)
	_tabs.set_tab_title(1, TAB_WISH)


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

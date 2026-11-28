## 许愿机 —— Controller（★ v0.30 MVC；★ v0.41 三栏重构）。
##
## **唯一把 Model 与 View 连起来的地方**：
##   · `bind_state()`：Model 绑状态 → View 渲染；
##   · 订阅 View 的信号 → 调 Model 对应方法 → 再 View 渲染。
##
## ★ **v0.30.1（方案 1）**：`_ready` 里**不直接 refresh**，而是 `call_deferred("refresh")`。
##   Godot 的 `_ready` 自底向上（子先于父）⇒ 本类（子）的 `_ready` 跑在 View（父）之前，
##   那一刻 View 的 `@onready` 还没赋值。推迟到本帧所有 `_ready` 结束后，View 一定已就绪。
##
## ★ v0.41：三栏各自的选中项（盲盒 / 位子 / 模块）由 View 持有，Controller 每次 refresh
##   把三个下标一起交给 Model 算快照——**Model 不持有任何 UI 选择状态**。
class_name WishMachineController
extends Node

var model: WishMachineModel = WishMachineModel.new()

@onready var view: WishMachineView = get_parent()


func _ready() -> void:
	if model.state == null:
		model.bind(GameSession.state)
	view.upgrade_requested.connect(_on_upgrade)
	view.open_requested.connect(_on_open)
	# ★ v0.78：点空位 ⇒ 弹模块浮层；在浮层里点模块 ⇒ 直接镶进那个位子
	view.slot_clicked.connect(_on_slot_clicked)
	view.module_picked.connect(_on_module_picked)
	view.pool_sort_requested.connect(_on_pool_sort)
	view.pool_data_requested.connect(_on_pool_data)
	view.operator_toggle_requested.connect(_on_operator_toggle)
	# ★ v0.79：点盲盒图标 ⇒ 弹浮层；浮层里选一项 ⇒ 切换当前盒
	view.box_button_clicked.connect(_on_box_button_clicked)
	view.box_chosen.connect(_on_box_chosen)
	view.box_changed.connect(refresh)
	# ★ v0.52c：**池子一变就重算**——浮层开着的时候也必须跟着变（不是"打开即最新"，而是"始终保持最新"）。
	#   订阅 `PoolService.bus.pool_changed`（唯一写入方在每次写入后发出），
	#   用**对象方法**（不是 lambda）连接 ⇒ 节点被释放时 Godot 会自动断开，不会留下悬空回调。
	PoolService.bus.pool_changed.connect(_on_pool_changed)
	call_deferred("refresh")   # ★ 首次 render 推迟到 View 的 @onready 就绪之后


## ★ v0.52c：池子被写入了（任何来源：本页按钮 / 数据层 / 别的系统）⇒ 重算并重渲染。
##
## **只在两种情况下真的去 refresh**：
##   · 浮层正开着（用户在看数据，必须立刻跟）；
##   · 页面在可见的那个 tab 上（否则白算一遍，切回来时 `tab_changed` 还会再刷）。
## 其余情况什么都不做——**本类的 refresh 是纯读**，但没必要给不可见的页面做无用功。
func _on_pool_changed(_box_id: String, _revision: int) -> void:
	if view == null or not is_instance_valid(view):
		return
	if view.is_pool_overlay_visible() or view.is_visible_in_tree():
		refresh()


func bind_state(s: GameState) -> void:
	model.bind(s)
	refresh()


func refresh() -> void:
	view.render(model.snapshot(view.selected_index))


## 透传给外部 / 测试的只读快照（View 不提供，Model 才有）。
func snapshot() -> Dictionary:
	return model.snapshot(view.selected_index)


func _on_upgrade() -> void:
	model.upgrade()
	refresh()


func _on_open(times: int) -> void:
	model.open(times, view.selected_index)
	refresh()
	# ★ v0.70：**结果改用浮层**（版面里不再有"生成物品"段）
	if not model.open_items.is_empty() or String(model.open_note) != "":
		view.show_result_overlay(model.open_items, model.open_note, model.open_foot)


var _pending_slot: int = -1          # ★ v0.78：刚才点的那个空位


## 点空位：把"可镶的模块（仓库里真有货）"列进浮层。
## ★ v0.79：点图标 ⇒ 列仓库里的盲盒
func _on_box_button_clicked() -> void:
	var items: Array = model.snapshot(view.selected_index).get("box_items", [])
	view.show_box_overlay(items, "共 %d 个盲盒（点击切换）" % items.size())


func _on_box_chosen(index: int) -> void:
	view.set_selected_box(index)
	view.hide_box_overlay()
	refresh()


func _on_slot_clicked(slot: int) -> void:
	_pending_slot = slot
	var opts: Array = model.socketable_modules(view.selected_index, model.boxes())
	if opts.is_empty():
		view.show_module_overlay([], "位 %d：仓库里没有可用模块" % (slot + 1))
		return
	view.show_module_overlay(opts, "位 %d：选择要镶入的模块（会消耗一件实物）" % (slot + 1))


## 浮层里选了模块 ⇒ 镶进刚才那个位子。
func _on_module_picked(module_id: StringName) -> void:
	if _pending_slot < 0:
		return
	model.socket_module_into(view.selected_index, _pending_slot, module_id)
	_pending_slot = -1
	view.hide_module_overlay()
	refresh()


func _on_pool_data() -> void:
	refresh()
	view.show_pool_overlay()


func _on_pool_sort(mode: int) -> void:
	model.set_pool_sort(mode)
	refresh()


func _on_operator_toggle() -> void:
	model.toggle_operator()
	refresh()

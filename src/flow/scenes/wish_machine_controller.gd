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
	view.socket_requested.connect(_on_socket)
	view.pool_reveal_requested.connect(_on_pool_reveal)
	view.pool_disable_requested.connect(_on_pool_disable)
	view.pool_add_requested.connect(_on_pool_add)
	view.pool_sort_requested.connect(_on_pool_sort)
	view.pool_data_requested.connect(_on_pool_data)
	view.operator_toggle_requested.connect(_on_operator_toggle)
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
	view.render(model.snapshot(
		view.selected_index, view.slot_index, view.module_index,
		view.pool_index, view.add_index
	))


## 透传给外部 / 测试的只读快照（View 不提供，Model 才有）。
func snapshot() -> Dictionary:
	return model.snapshot(
		view.selected_index, view.slot_index, view.module_index,
		view.pool_index, view.add_index
	)


func _on_upgrade() -> void:
	model.upgrade()
	refresh()


func _on_open(times: int) -> void:
	model.open(times, view.selected_index)
	refresh()


func _on_socket() -> void:
	model.socket_module(view.selected_index, view.slot_index, view.module_index)
	refresh()


func _on_pool_reveal() -> void:
	model.reveal_pool_item(view.selected_index, view.pool_index)
	refresh()


func _on_pool_disable() -> void:
	model.disable_pool_item(view.selected_index, view.pool_index)
	refresh()


## ★ v0.51：浮层排序（只改呈现顺序，不动池子数据）
## ★ v0.52b：打开浮层**前先刷新**——按钮只负责"要开"，数据由这次 refresh 现取。
## 如果池子在别处（数据层 / 其它系统）被改过而本页没刷新，这里能兜住。
func _on_pool_data() -> void:
	refresh()
	view.show_pool_overlay()


func _on_pool_sort(mode: int) -> void:
	model.set_pool_sort(mode)
	refresh()


func _on_pool_add() -> void:
	model.add_pool_item(view.selected_index, view.add_index)
	refresh()


func _on_operator_toggle() -> void:
	model.toggle_operator()
	refresh()

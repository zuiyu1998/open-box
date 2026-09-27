## 盲盒（01-gacha.md §4.3）。
##
## ★ **两个并列数据**：`item_pool`（该盒的池子，生成数据的凭证）+ `modules`（**定长**模块数组）。
##   池子的"当前状态"是二者的函数（`PoolState`）——**派生值、不入档、载入时逐盒重建**。
##   **模块不折进池子**：不得在 `PoolState` 或 `item_pool` 里再放一份模块字段
##   （核心已否决 `PoolState.socketed` 这种形状）。
##
## ★ `box_id` 是**身份、不是输入**：不参与权重与抽样；**稳定性来自持久化**，不来自派生。
##   `Uuid.v4()` 生成（`String`，与 `instance_id` 同源同类型，**无转换点**）。
##
## ★ `modules` 是**定长**数组（长度恒 == `item_pool.socket_count`，**空位为空项**）；
##   **槽位号 = 数组下标**（**不另设 `slot` 字段**）。
@tool
class_name Box
extends Resource

@export var box_id: String = ""                          # Uuid.v4()；与 instance_id 同类型、无转换
@export var series_id: StringName = &""
@export var item_pool: ItemPool                          # 【生成数据的凭证】——roll() 消费它
@export var modules: Array[Module] = []                  # 定长，长度恒 == item_pool.socket_count，空位为空项
@export var source: StringName = &""                     # 来源任务 id（归因，见 03）
@export var acquired_tick: int = 0


## 该盒的位数（冻结在 item_pool 上；C4：同一池内恒定、运行时不可变）。
func socket_count() -> int:
	return item_pool.socket_count if item_pool != null else 0


## 已占用位数（非空项数）。→ C4 真正要守的是"已占用位数 ≤ socket_count"
## （"长度恒等于 socket_count"是结构上恒真的，见 01 §10.1 T6/C4 与 §5.2 第 7 步）。
func occupied_count() -> int:
	var n := 0
	for m in modules:
		if m != null:
			n += 1
	return n


## 第 slot 位（越界返回 null；空位本身就是 null）。
func module_at(slot: int) -> Module:
	if slot < 0 or slot >= modules.size():
		return null
	return modules[slot]


## 落盘 = 由下标生成的**稀疏序列**（空位不写）：`{index, module_id, quality, socketed_at}`。
## 存档格式归 10（01 §4.3 / 10 的示例）；这里只提供形状，**不改动实例本身**。
func modules_to_sparse_array() -> Array:
	var out: Array = []
	for i in modules.size():
		var m := modules[i]
		if m == null:
			continue
		out.append({
			"index": i,
			"module_id": String(m.module_id),
			"quality": m.quality,
			"socketed_at": m.socketed_at,
		})
	return out


## 从稀疏序列还原**定长**数组（长度取自 `socket_count_arg`）。
## **长度由调用方给定**（= `item_pool.socket_count`），不由序列长度推导——
## 否则"定长"会随"镶了几个"变化，C4 的第①条断言当场失效。
static func modules_from_sparse_array(items: Array, socket_count_arg: int) -> Array[Module]:
	var out: Array[Module] = []
	for _i in socket_count_arg:
		out.append(null)
	for raw in items:
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		var idx := int(d.get("index", -1))
		if idx < 0 or idx >= socket_count_arg:
			continue
		var m := Module.new()
		m.module_id = StringName(d.get("module_id", ""))
		m.quality = int(d.get("quality", 1))
		m.socketed_at = int(d.get("socketed_at", 0))
		out[idx] = m
	return out

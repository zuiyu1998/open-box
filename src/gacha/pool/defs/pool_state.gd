## 池子的**当前状态**（01-gacha.md §4.3；07-economy-rho.md §4）。
##
## ★ **派生值**：= f(该盒 `item_pool` 的基础分布, 该盒 `modules`)。**不是存储数据、不入档**——
##   载入时由 `PoolService` **逐盒重建**。存下来就等于把结果当成第二个事实来源
##   （与"派生状态不入档"是同一条纪律，核心 §4.1.2）。
##
## ★ 字段集**仅此**（+ box_id / 规模副本）：**不含 `socketed`**——"模块在池子里"的形状
##   已被核心否决；**模块列表只在 `Box.modules`**。
##
## ★ 规范表示是**整数万分比**：`Σ weights_bp + void_mass_bp == 10000`（C1 的零和等式
##   因此在**整数**上精确成立，存档往返也字节级稳定）。
class_name PoolState
extends RefCounted

var box_id: String = ""                  # 本状态属于哪一个盒子（缓存键的一半）
var series_id: StringName = &""
var revision: int = 0                    # 镜像 ItemPool.revision（07 的缓存键 = (box_id, revision)）
var socket_count: int = 0                # 从该盒 item_pool 冻结（C4）
var regular_count: int = 0               # 从该盒 item_pool 冻结（C6 的依据）
var weights_bp: Dictionary = {}          # item_id -> **当前**权重（整数万分比；被排除项为 0，仍在表内）
var void_mass_bp: int = 0                # 当前不可回收质量（同单位同精度；**每个池子各自累积**）


func item_mass_bp() -> int:
	var t := 0
	for v in weights_bp.values():
		t += int(v)
	return t


## C1 的**整数**零和等式（唯一可以精确断言的形式）。
func is_zero_sum() -> bool:
	return item_mass_bp() + void_mass_bp == ItemPool.TOTAL_BP


func weight_of(item_id: StringName) -> int:
	return int(weights_bp.get(item_id, 0))


## **可产出物品数**（权重 > 0 的物品）。C6 的下限（≥ 3）判的就是它。
func producible_count() -> int:
	var n := 0
	for v in weights_bp.values():
		if int(v) > 0:
			n += 1
	return n


## 被排除的物品（权重 0）。注意：`weights_bp` 里**仍然保留这些条目**（值为 0），
## 因为"被排除"与"池子里没这件物品"是两件事——候选集仍出自 `item_pool`。
func banned_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in weights_bp.keys():
		if int(weights_bp[k]) == 0:
			out.append(StringName(k))
	return out


func clone() -> PoolState:
	var s := PoolState.new()
	s.box_id = box_id
	s.series_id = series_id
	s.revision = revision
	s.socket_count = socket_count
	s.regular_count = regular_count
	s.weights_bp = weights_bp.duplicate()
	s.void_mass_bp = void_mass_bp
	return s

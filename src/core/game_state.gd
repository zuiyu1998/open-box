## 全局游戏状态（01-gacha.md §4.3 / §4.4）。
##
## 本类目前**只承载 01 拥有的两项**，与 02 的账本（`ItemService` 是 autoload 单例）分开：
##   · `pending_boxes` —— 已获得、未兑现的盲盒清单（**每个盒子各带自己的 `item_pool` 与 `modules`**）
##   · `draw_index`    —— **全局单调递增**的兑现序号
##
## ★ `draw_index` **必须全局递增**（跨批次 / 跨套系 / 跨存档载入均不重置）：若每批从 0 开始，
##   两批不同盒子的实例会拿到相同 `draw_index`，溯源与回放就会串。
##   **它与已删除的保底计数器毫无关系**——它不是概率状态，只是**兑现序号 / 幂等锚点**。
##
## [!] **存档格式归 10**（`10-progression.md`）：本类只提供 `snapshot()` / `restore()` 两个
##     最小心跳接口供测试与将来的存档层调用，**不定义 save.json 的封装**。
class_name GameState
extends RefCounted

var pending_boxes: Array[Box] = []
var draw_index: int = 0


func add_box(box: Box) -> void:
	if box != null:
		pending_boxes.append(box)


func find_box(box_id: String) -> Box:
	for b in pending_boxes:
		if b.box_id == box_id:
			return b
	return null


func has_box(box_id: String) -> bool:
	return find_box(box_id) != null


## 兑现 = **消费一个盒子**：它连同 `item_pool` 与 `modules` 一起从清单移除、**不再存在**
## （01 §10.1 T14）。这是"模块是消耗品"的落点——兑现后没有任何拆卸路径。
func remove_box(box_id: String) -> bool:
	for i in pending_boxes.size():
		if pending_boxes[i].box_id == box_id:
			pending_boxes.remove_at(i)
			return true
	return false


## 下一枚兑现序号（**先自增、再使用**，从 1 开始）。
func next_draw_index() -> int:
	draw_index += 1
	return draw_index


func box_count() -> int:
	return pending_boxes.size()

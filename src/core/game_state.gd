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

## **v0.14：玩家持有的设备**（裁决：设备是**开盒**与**装模块**的硬门槛）。
##
## `[补充]` 现在只存 **id 列表**——**不实现** `DeviceDef` / 槽位 / 占用 / 装配（那是 04 的活）。
## ★★ **必须入档**（归档格式归 10）：读档若把设备丢了，玩家会被**永久锁死**——
##   两条消耗入口（`GachaService.redeem()` / `PoolService.socket()`）会全部拒绝。
var devices: Array[StringName] = []


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


## **v0.14：归零即移除（含镶嵌导致）——盒子离开清单的唯一原因就是"使用次数归零"。**
## 本方法把盒子连同它的 `item_pool` 与 `modules` 一起移除、**不再存在**。
## 两条导致归零的路径**共用** `spend_use()`：**装模块**（`PoolService.socket()`）与**兑现**
## （`GachaService.redeem()`）。**不存在"用尽才消耗"的缓冲**：镶嵌把次数扣到 0 时立即移除，
## 哪怕这个盒子从未被兑现过（那是**合法路径**，不做防御性拦截）。
func remove_box(box_id: String) -> bool:
	for i in pending_boxes.size():
		if pending_boxes[i].box_id == box_id:
			pending_boxes.remove_at(i)
			return true
	return false


## **v0.14：消耗一次使用 + 归零即摧毁。**
##
## 两个消耗点**共用同一个计数器**：`PoolService.socket()`（装模块）与 `GachaService.redeem()`（兑现）。
## 返回**是否因此被摧毁**（`uses_remaining` 归零 ⇒ 从 `pending_boxes` 移除，连同该盒自己的
## `item_pool` 与 `modules`）。
##
## ★ **摧毁是合法路径**：哪怕一次都没兑现过，装模块把次数扣到 0 也照样摧毁——
##   这里**不做**任何防御性拦截（不要求"先兑现"、不在归零前拒绝镶嵌）。
## ★ 调用方必须保证：**只有在这一步之前的全部失败路径都已排除**之后才调用它
##   （"失败一律不扣次数"）。
func spend_use(box: Box) -> bool:
	if box == null:
		return false
	if not box.consume_one_use():
		return false
	if box.is_exhausted():
		remove_box(box.box_id)
		return true
	return false


## 下一枚兑现序号（**先自增、再使用**，从 1 开始）。
func next_draw_index() -> int:
	draw_index += 1
	return draw_index


func box_count() -> int:
	return pending_boxes.size()


## **v0.14：清单里还剩多少次使用**（Σ `uses_remaining`）。
## 它才是"还能开几次"的那个数——**盒子数不再等于可开次数**（一次兑现 = 一次使用）。
func total_remaining_uses() -> int:
	var t := 0
	for b in pending_boxes:
		t += maxi(b.uses_remaining, 0)
	return t


# ══════════════════════════════════════════════════════════════════════════════
#  设备（v0.14 裁决：开盒与装模块的硬门槛）
# ══════════════════════════════════════════════════════════════════════════════

## **新游戏初始化**：**开局送一台基础装置**（id 取自 `DeviceConstants`，**不硬编码字面量**）。
##
## 为什么要送：设备是开盒与装模块的硬门槛，而设备由物品造、物品来自开盒——
## 不送一台就**死锁**（"开盒需要设备 → 设备需要开盒"）。
static func new_game() -> GameState:
	var st := GameState.new()
	st.grant_device(DeviceConstants.STARTING_DEVICE_ID)
	return st


## 发放一台设备（初始化与将来的内容释放都走这里；**不是**"设备库存"的意思——
## 设备**不会被消耗、也不会损耗**（已裁决），因此这个列表只增不减；持有与判定的完整口径见 `has_device()`）。
func grant_device(device_id: StringName) -> void:
	if device_id != &"":
		devices.append(device_id)


func device_count() -> int:
	return devices.size()


## **"是否有设备"的唯一判定入口**（v0.14 裁决：**没有设备 ⇒ 既不能开盒也不能装模块**）。
##
## **② 已裁决：设备不会被消耗、也不会损耗。**（用户原话"设备不会被消耗"）
##   ⇒ 本函数是**纯只读**判定；"扣设备"这件事**不存在**，因此它也不需要进 `spend_use()` 的事务。
##   ★ **为什么这条要紧**：如果设备会被消耗，**开局送的那一台用完就会回到同一个死锁**
##     （无设备 ⇒ 两条入口全拒）——所以"**设备耐用**"是"**开局送一台**"这个解法的
##     **前提条件**，不是附加细节。
##
## **① 最简默认（★ 可回滚）**：**一台设备是通用耐用工具——不绑定盒子、不限制次数**。
##   理由：既然设备不会被消耗，"通用"就是最小假设。
##   ⇒ `has_device()` 因此**保持无参**。
##   ★ **将来若要改成"设备绑定盒子"，唯一要动的地方就是本函数**：改成 `has_device(box_id)`，
##     并让 `redeem()` / `socket()` 把 `box_id` 传进来即可——这正是当初把判定**集中到一处**的目的。
##     **现在不实现绑定。**
func has_device() -> bool:
	return not devices.is_empty()


# ══════════════════════════════════════════════════════════════════════════════
#  载入路径（v0.14「缺键补齐」的唯一落点）
# ══════════════════════════════════════════════════════════════════════════════

## 从落盘字典载入一个盒子 —— **v0.14「缺 `uses_remaining` 键 ⇒ 按品质补齐」的唯一落点**。
##
## ★ **为什么补齐放在这一层**：补齐需要"该盒所属套系的品质"（`SeriesDef.series_quality`），
##   而 `Box` 只带 `series_id`；要拿品质就必须能问注册表（`GachaCatalog`）——
##   那是**载入层**的能力。**`Box` 不该依赖注册表**，所以策略在这里、`Box.from_dict()`
##   只接受一个"缺键时用几"的值。
##
## ★ **只有缺键才补**：字典里**没有** `uses_remaining` ⇒ 取
##   `SeriesDef.expected_initial_uses(series.series_quality)`（品质 1–4 → 10/15/20/25）。
##   **不是取 0**：`0` 在新语义下等于"归零 ⇒ 摧毁"，取 0 会让一份 v0.14 之前的存档
##   **把所有盒子一次性摧毁**。
## ★ **键存在时一律用档里的值**（哪怕它是 `0`——那是"这个盒子已经用尽"，是合法状态）。
## ★ `schema_version` **不动**（仍是 v5）：这是"新增字段 + 载入补齐"，不是格式变更。
static func box_from_dict(d: Dictionary) -> Box:
	var backfill := 0
	if not d.has("uses_remaining"):
		var series := GachaCatalog.get_series(StringName(d.get("series_id", "")))
		if series != null:
			backfill = SeriesDef.expected_initial_uses(series.series_quality)
	# 套系解析不到时 `Box.from_dict` 自己会返回 null（不静默降级），补不补都无所谓
	return Box.from_dict(d, backfill)

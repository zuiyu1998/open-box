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

## **v0.14 立、v0.18 改形态：玩家持有的设备**（设备是**开盒**与**装模块**的硬门槛）。
##
## ★★ **v0.18 / v0.19：每台 = `Device { device_id, level }`**（设备带**等级**）。
##   **存档条目形态随之变化** ⇒ v5 → v6 迁移（旧字符串条目回填 `level = 1`），
##   见 `10-progression.md` §7.4 第 11 条。**必须入档**：读档若把设备丢了，
##   玩家会被永久锁死（两条消耗入口会全部拒绝）。
## ★ **本类只持有事实**；**判定与计价都在 `DeviceService`**
##   （`has_device()` 镶嵌侧 / `can_open(state, box)` 开盒侧）——**不在这里做第二套判断**。
var devices: Array[Device] = []


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
#  设备（v0.14 硬门槛；v0.17 三个动作的入口归 04；v0.18 带等级与资源；v0.19 镶嵌花金币）
# ══════════════════════════════════════════════════════════════════════════════

## **新游戏初始化**：**开局送一台基础装置（等级 1）＋ 一笔原石 ＋ 一笔金币**。
##
## ★ 为什么三样都必须发（`04-device.md` §1.1 / §1.2；核心 §16.13 / §16.14）：
##   · **设备**：它是硬门槛，而**装置没有第二个来源**（制造已删除）⇒ 不发就**永远是 0 台**；
##   · **原石**：开盒要付它，而它的来源是任务（任务又要先开盒产出物品）⇒ 不发就**开不了第一个盒子**；
##   · **金币**：镶嵌要付它 ⇒ 不发就**装不了第一个模块**（中心机制的第一次体验被闸门挡住）。
##
## ★ **数额来自内容配置的同一处来源**（`ItemConstants.INIT_*`）——**迁移回填也必须读它**
##   （`10-progression.md` §7.4 第 11 条），**不得在两处各写一个数**。
static func new_game() -> GameState:
	var st := GameState.new()
	DeviceCatalog.ensure_default_content()
	st.grant_device(DeviceConstants.STARTING_DEVICE_ID)
	ItemService.grant_currency(
		ItemConstants.CURRENCY_GEM, ItemConstants.INIT_GEM, ItemConstants.CURRENCY_SOURCE_INIT
	)
	ItemService.grant_currency(
		ItemConstants.CURRENCY_GOLD, ItemConstants.INIT_GOLD, ItemConstants.CURRENCY_SOURCE_INIT
	)
	return st


## 发放一台设备（**只有"初始化 / 缺键补发"这一个调用方**——不是"设备库存"的意思）。
## 设备**不会被消耗、也不会损耗**（D21 已裁决）⇒ 这个列表**只增不减**。
func grant_device(device_id: StringName, level: int = 1) -> void:
	if device_id != &"":
		devices.append(Device.make(device_id, level))


func device_count() -> int:
	return devices.size()


## **"是否有设备"的判定**（v0.14 裁决：**没有设备 ⇒ 既不能开盒也不能装模块**）。
##
## **② 已裁决：设备不会被消耗、也不会损耗。**（用户原话"设备不会被消耗"）
##   ⇒ 本函数是**纯只读**判定；"扣设备"这件事**不存在**，因此它也不需要进 `spend_use()` 的事务。
##   ★ **为什么这条要紧**：如果设备会被消耗，**开局送的那一台用完就会回到"永远 0 台"**
##     （无设备 ⇒ 两条入口全拒）——所以"**设备耐用**"是"**开局送一台**"这个解法的
##     **前提条件**，不是附加细节。
##
## **① 最简默认（★ 可回滚）**：**一台设备是通用耐用工具——不绑定盒子、不限制次数**。
##   ⇒ 本函数**无参**。
##   ★ **v0.18：开盒侧还需要"等级够不够"** ⇒ 那一份判定是 **`DeviceService.can_open(state, box)`**
##     （**带盒子**——D21 预写的回滚点被"等级门控"触发）。**两份判定同一份数据、同一处实现**
##     （`DeviceService`），本函数只是它下面的**同一份事实**（"持有集合非空"），
##     `01` 的两条入口调它做兜底。
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

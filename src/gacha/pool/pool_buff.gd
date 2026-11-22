## 物品池 buff —— ★ v0.46：**唯一对物品池数据做写入的接口**（用户裁决）。
##
## 用户原话："**添加一个物品池buff，这个是唯一对物品池数据操作的接口**"。
## 追问确认：**buff 就是统一写入门面**（不引入寿命/叠加，也不是与模块并列的第三种修饰）、
## **覆盖全部池子数据写入（含模块效果）**、**免费且可逆**。
##
## 三条它必须承担的事：
##   1. **单一入口**：池子数据的写入只有这一个类。`PoolService` 里对应的三个实现已降级为
##      `_write_*`（下划线 = 内部），并带**运行时闸门**：不经本类直接调用会被拒
##      （`write_denied`）——所以"唯一接口"不是靠约定，而是**跑起来就成立**。
##   2. **统一的结果形状**：三个动作都返回 `{ok, reason, state, errors, destroyed}`，
##      上层（UI / 04 / 测试）只认这一种回执，不必按动作分支。
##   3. **不收代价、可逆**：buff 不花金币、不占盒子位子、不扣寿命（与模块镶嵌不同）；
##      唯一需要"永久"的是**模块本身**（v0.44 起镶上即锁定）——那是模块的规则，不是 buff 的。
##
## **不属于池子数据的写操作**（因此**不**走本类）：`PoolService.init_pool()`（建池，归发盒流程）
## 与 `Box.from_dict()`（读档重建）。它们是"创建 / 复原"，不是"改"。
##
## 使用方式（两种等价写法，`apply()` 只是分发器）：
## ```gdscript
## PoolBuff.add_item(state, box_id, &"home_q3")
## PoolBuff.set_state(state, box_id, &"home_q1", ItemPool.ItemState.HIDDEN)
## PoolBuff.apply_module(state, box_id, &"mod_ban_home_q1", 0)
## PoolBuff.apply(state, box_id, {"kind": PoolBuff.KIND_SET_STATE, "item_id": &"home_q1", "new_state": 1})
## ```
class_name PoolBuff
extends RefCounted

## `apply()` 的动作名（逐字；与 `PoolService` 的三个内部写入一一对应）。
const KIND_ADD_ITEM := &"add_item"          # 把一件已注册物品加进池子
const KIND_SET_STATE := &"set_state"        # 改一件池内物品的三态（显示/隐藏/禁用）
const KIND_APPLY_MODULE := &"apply_module"  # 把模块镶进某个位子（模块效果 = 池子数据的写入）
const ALL_KINDS: Array[StringName] = [KIND_ADD_ITEM, KIND_SET_STATE, KIND_APPLY_MODULE]


## 统一分发：`op` 形如 `{kind, ...}`。
## **未知 kind / 缺字段 ⇒ `bad_op`**（不猜、不静默降级）。
static func apply(state: GameState, box_id: String, op: Dictionary) -> Dictionary:
	var kind := StringName(op.get("kind", &""))
	match kind:
		KIND_ADD_ITEM:
			return add_item(state, box_id, StringName(op.get("item_id", &"")))
		KIND_SET_STATE:
			return set_state(
				state, box_id, StringName(op.get("item_id", &"")), int(op.get("new_state", -1))
			)
		KIND_APPLY_MODULE:
			return apply_module(
				state, box_id, StringName(op.get("module_id", &"")), int(op.get("slot", -1))
			)
		_:
			return _bad_op()


## 把一件**已注册**物品加进该盒池子。免费、可逆（用 `set_state(DISABLED)` 让它抽不到）。
static func add_item(state: GameState, box_id: String, item_id: StringName) -> Dictionary:
	return _through_gate(func() -> Dictionary:
		return PoolService._write_add_item(state, box_id, item_id))


## 改一件池内物品的三态。免费、可逆、幂等（设成当前态 ⇒ 成功但不动 `revision`）。
static func set_state(
	state: GameState, box_id: String, item_id: StringName, new_state: int
) -> Dictionary:
	return _through_gate(func() -> Dictionary:
		return PoolService._write_set_state(state, box_id, item_id, new_state))


## 把 `module_id` 镶进该盒第 `slot` 位（**模块效果就是池子数据的一次写入**）。
## ★ 注意：**设备门槛 / 金币成本仍由 `DeviceService.socket()` 负责**——它是"能不能镶"的入口，
##   本方法是"把这次镶嵌落到池子数据上"的那一步。UI 请优先走 `DeviceService.socket()`。
static func apply_module(
	state: GameState, box_id: String, module_id: StringName, slot: int
) -> Dictionary:
	return _through_gate(func() -> Dictionary:
		return PoolService._write_module(state, box_id, module_id, slot))


# ══════════════════════════════════════════════════════════════════════════════
#  内部
# ══════════════════════════════════════════════════════════════════════════════

## 进出闸门：`PoolService` 的内部写入只在"本类正拿着闸门"时放行。
## 用一个闭包而不是 try/finally（GDScript 没有 finally），写入实现本身**不会中途抛异常**
## （全部走返回值），所以"开门 → 调用 → 关门"是安全的。
static func _through_gate(body: Callable) -> Dictionary:
	PoolService._open_write_gate()
	var r: Dictionary = body.call()
	PoolService._close_write_gate()
	return r


static func _bad_op() -> Dictionary:
	return {
		"ok": false, "reason": ItemConstants.REASON_BAD_OP, "state": null,
		"errors": [] as Array[String], "destroyed": false,
	}

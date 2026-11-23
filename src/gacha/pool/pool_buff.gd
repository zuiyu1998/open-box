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
## PoolBuff.reveal(state, box_id, &"home_q1")      # 隐藏 → 显示
## PoolBuff.apply_module(state, box_id, &"mod_ban_home_q1", 0)
## PoolBuff.disable(state, box_id, &"home_q1")     # 显示 → 禁用（隐藏的不行）
## PoolBuff.apply(state, box_id, {"kind": PoolBuff.KIND_REVEAL, "item_id": &"home_q1"})
## ```
class_name PoolBuff
extends RefCounted

## `apply()` 的动作名（逐字；与 `PoolService` 的内部写入一一对应）。
##
## ★ v0.48（用户裁决）：**暴露的是三件"有方向"的事**，不是一个万能 `set_state`：
##   · **添加**（`add_item`）——新物品一进来就是**显示**；
##   · **揭示**（`reveal`）——隐藏 → 显示；
##   · **禁用**（`disable`）——**只有显示能被禁用**，且禁用是**终局**。
##   没有"显示 → 隐藏"这个动作（隐藏是物品的基础状态，由内容 / 读档决定，玩家压不下去）。
const KIND_ADD_ITEM := &"add_item"          # 把一件已注册物品加进池子（→ 显示）
const KIND_REVEAL := &"reveal"              # 隐藏 → 显示
const KIND_DISABLE := &"disable"            # 显示 → 禁用（终局；隐藏的必须先揭示）
const KIND_APPLY_MODULE := &"apply_module"  # 把模块镶进某个位子（模块效果 = 池子数据的写入）
const ALL_KINDS: Array[StringName] = [
	KIND_ADD_ITEM, KIND_REVEAL, KIND_DISABLE, KIND_APPLY_MODULE,
]


## 统一分发：`op` 形如 `{kind, ...}`。
## **未知 kind / 缺字段 ⇒ `bad_op`**（不猜、不静默降级）。
static func apply(state: GameState, box_id: String, op: Dictionary) -> Dictionary:
	var kind := StringName(op.get("kind", &""))
	match kind:
		KIND_ADD_ITEM:
			return add_item(state, box_id, StringName(op.get("item_id", &"")))
		KIND_REVEAL:
			return reveal(state, box_id, StringName(op.get("item_id", &"")))
		KIND_DISABLE:
			return disable(state, box_id, StringName(op.get("item_id", &"")))
		KIND_APPLY_MODULE:
			return apply_module(
				state, box_id, StringName(op.get("module_id", &"")), int(op.get("slot", -1))
			)
		_:
			return _bad_op()


## 把一件**已注册**物品加进该盒池子（**落为"显示"**）。免费、可逆性见 `reveal` / `disable`。
static func add_item(state: GameState, box_id: String, item_id: StringName) -> Dictionary:
	return _through_gate(func() -> Dictionary:
		return PoolService._write_add_item(state, box_id, item_id))


## **揭示**：把一件**隐藏**的物品变成显示（此后它可见、可被禁用）。
## 已经是显示的 ⇒ 幂等成功；已被禁用 ⇒ `state_terminal`（终局不可逆）。
static func reveal(state: GameState, box_id: String, item_id: StringName) -> Dictionary:
	return _through_gate(func() -> Dictionary:
		return PoolService._write_set_state(state, box_id, item_id, ItemPool.ItemState.SHOWN))


## **禁用**：把一件**显示**的物品变成禁用（不参与抽取，权重在其余物品间重新归一）。
## ⚠️ **只有显示状态能被禁用**：隐藏的 ⇒ `not_revealed`（必须先 `reveal`）；
## 已禁用的 ⇒ `state_terminal`。
static func disable(state: GameState, box_id: String, item_id: StringName) -> Dictionary:
	return _through_gate(func() -> Dictionary:
		return PoolService._write_set_state(state, box_id, item_id, ItemPool.ItemState.DISABLED))


## 把 `module_id` 镶进该盒第 `slot` 位（**模块效果就是池子数据的一次写入**）。
## ★ 注意：**设备门槛 / 金币成本仍由 `DeviceService.socket()` 负责**——它是"能不能镶"的入口，
##   本方法是"把这次镶嵌落到池子数据上"的那一步。UI 请优先走 `DeviceService.socket()`。
static func apply_module(
	state: GameState, box_id: String, module_id: StringName, slot: int
) -> Dictionary:
	return _through_gate(func() -> Dictionary:
		return PoolService._write_module(state, box_id, module_id, slot))


# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.49：**干员的额外排除**也经 buff（不再由 `PoolService.extra_ban_provider` 旁路注入）
# ══════════════════════════════════════════════════════════════════════════════

## "出战干员排除了哪些物品"的提供者：`Callable() -> Array`（返回 `StringName` 列表）。
## 注入方 = `OperatorService._ready()`。**未注入 ⇒ 空数组**（行为与"没有干员"一致）。
static var _operator_ban_provider: Callable = Callable()


static func set_operator_ban_provider(cb: Callable) -> void:
	_operator_ban_provider = cb


static func clear_operator_ban_provider() -> void:
	_operator_ban_provider = Callable()


## 当前**生效中**的干员排除目标（`Array[StringName]`）。`_compute` 只问这一个入口。
##
## 为什么它也算"池子数据操作"：它会改变 `PoolState.weights_bp`（与模块 BAN 同一条 40/60 路径）。
## v0.46 定的"buff 是唯一接口"如果允许这条旁路存在，就等于留了第二个能改分布的入口。
static func operator_bans() -> Array[StringName]:
	var out: Array[StringName] = []
	if not _operator_ban_provider.is_valid():
		return out
	var raw = _operator_ban_provider.call()
	if not (raw is Array):
		return out
	for t in (raw as Array):
		out.append(StringName(t))
	return out


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

## 池子编辑服务（01-gacha.md §4.5 / §5.1 / §5.2 / §5.2.3 / §5.8）——池子两份数据的**唯一写入方**。
##
## 职责：由「该盒 `item_pool` + 该盒 `modules`」**推导**出 `PoolState`
## （`weights_bp` + `void_mass_bp`，**整数万分比**；`Σ weights_bp + void_mass_bp == 10000`）。
## **本系统只写数据、不算数字**：任何"当前概率是多少"的需求一律调 `EvalService`（07）。
##
## ★ 三条不得越界（01 §2）：
##   ① **模块不折进池子**——模块只存在于 `Box.modules`，不得在 `PoolState` / `item_pool` 里再放一份；
##   ② **派生状态不入档**——逐盒重建（本类的缓存**只在内存里**，载入时重建，见 §10.1 T24）；
##   ③ **不得持有全局单例**——没有"当前套系的池子"，**每次写入都必须显式指定 `box_id`**。
##
## ★ 编辑顺序**固定**（§5.2 第 3–6 步，顺序影响结果）：排除 → 提升 → 损耗 → 零和。
##   全部以**整数万分比**运算，用最大余数法保证 Σ 精确 —— 整数才能让 C1 的零和等式被**精确断言**。
class_name PoolService
extends RefCounted

const TOTAL_BP := ItemPool.TOTAL_BP          # 10000：全部质量（含 void）
const RECOVER_RATE := 0.60                   # 核心 D6：可回收比例；损耗 = 40%
## ⚠️ **v0.19 作废**：`UNSOCKET_REFUND_RATE = 0.5`（核心 D8 的"拆卸只返还 50% 材料"）。
##   **拆卸现在什么都不返还**（连金币也不退）⇒ 这个常量没有对象，已删除。
##   **不要把它加回来**：加回来就等于复活一条已被裁定取消的产出路径（核心 §15 D8 / §16.14）。

# ── 拒绝原因码（`[补充]`：文档只写"响亮地拒绝并指明冲突源"，未给码；这里集中定义便于测试）──
const R_OK := &""
const R_BOX_NOT_FOUND := &"box_not_found"
## v0.14 裁决：**没有设备就不能装模块**（与开盒侧 `GachaService.R_NO_DEVICE` 同名同义）
const R_NO_DEVICE := &"no_device"
const R_BAD_SLOT := &"bad_slot"
const R_UNKNOWN_MODULE := &"unknown_module"
const R_SLOT_OCCUPIED := &"slot_occupied"
## ★ **v0.44 起为墓碑**：`unsocket()` 已删除 ⇒ 不再有"拆空位"这个失败场景。
## 保留常量只为不让历史原因码"消失得无影无踪"（旧日志 / 旧测试仍能解释它）。
const R_SLOT_EMPTY := &"slot_empty"
const R_BAD_SHAPE := &"modules_shape"              # V7 / C4①（定长长度）
const R_UNKNOWN_TARGET := &"unknown_target"        # 目标物品不在池内（**不是** V1——V1 已作废）
const R_BAN_BOOST_CONFLICT := &"ban_boost_conflict"  # V2
const R_BOOST_OVER_CAP := &"boost_over_cap"        # V4
const R_BAN_LIMIT := &"ban_limit_exceeded"         # V5（派生自 C6）
const R_TAG_CONFLICT := &"exclusive_tag_conflict"  # V6
const R_RECOVER_UNSUPPORTED := &"recover_unsupported"
const R_BELOW_C6 := &"below_c6_floor"              # 可产出物品数 < 3
## ★ v0.19：镶嵌**不再消耗物品** ⇒ 三个旧码作废（保留为墓碑，不再有产出它们的路径）：
##   `R_COST_INSUFFICIENT`（物品素材不足）/ `R_NO_SPACE`（拆卸返还装不下）/ `R_REFUND_UNRESOLVED`（返还反查失败）。
##   **镶嵌的新失败码是 `currency_insufficient`**（金币不足）——与 02 / 04 同一枚码。
const R_CURRENCY_INSUFFICIENT := &"currency_insufficient"   # ★ v0.19：金币不足（镶嵌的唯一花钱失败）
const R_POOL_INVALID := &"pool_invalid"
const R_BAD_SERIES := &"bad_series"
## ★ v0.45：池子成员 / 三态的拒绝码
const R_UNKNOWN_ITEM := &"unknown_item"                 # `item_id` 没在 `ItemCatalog` 注册
const R_ITEM_ALREADY_IN_POOL := &"item_already_in_pool" # 已经在池中，不重复加
const R_ITEM_NOT_IN_POOL := &"item_not_in_pool"         # 要改状态的物品不在这池子里
const R_BAD_STATE := &"bad_item_state"                   # 状态值越界
## ★ v0.46：**不经 `PoolBuff` 直接调内部写入** ⇒ 拒绝。
## 这是"唯一写入门面"的**运行时兜底**（不是靠注释约定）：`PoolBuff` 写入时开门、写完关门，
## 任何其它调用方拿到的永远是这一枚码。
const R_WRITE_DENIED := &"write_denied"


## 变更信号（01 §4.5）。静态类自身不能发信号，故由一个单例承载：
## 订阅方一律连 `PoolService.bus.pool_changed`，**不得**另建一条通知路径。
## **必须携带 `box_id`**——订阅方按 `box_id` 失效与重取，**不得**做"套系级"失效
## （否则同套系另一个盒子的缓存会被误清或串味）。
class ChangeBus:
	extends RefCounted
	signal pool_changed(box_id: String, revision: int)

static var bus: ChangeBus = ChangeBus.new()

## box_id -> PoolState。**内存缓存、不入档**：`revision` 对不上就重算（07 的缓存键 = (box_id, revision)）。
static var _states: Dictionary = {}

## ★ v0.46：**写入闸门**——只有 `PoolBuff` 在写入期间把它打开。
## `_write_*` 在闸门关闭时一律拒绝（`write_denied`），于是"物品池 buff 是唯一接口"
## **在运行时成立**，而不是一条只能靠自觉的注释约定。
static var _write_gate: bool = false


static func _open_write_gate() -> void:
	_write_gate = true


static func _close_write_gate() -> void:
	_write_gate = false


## ★ v0.40（15 干员）：**出战干员的额外排除回调**。
##
## 干员为许愿机提供"类似模块、但无代价"的 BAN 效果——它**不写池子数据**，
## 只注入这个回调；`_compute` 在算派生状态时 `call()` 它拿 `Array[StringName]`（额外排除目标），
## 与模块 BAN 走**同一条** 40% 蒸发 / 60% 摊回的零和路径。
## 注入方 = `OperatorService._ready()`（与 `ItemService.series_item_provider` 同一模式）。
## 未注入（`is_valid() == false`）⇒ 无额外排除，行为与旧版完全一致。
static var extra_ban_provider: Callable = Callable()


# ══════════════════════════════════════════════════════════════════════════════
#  建档：为新盒子产出 Box.item_pool（基础池副本）+ 定长空位数组
# ══════════════════════════════════════════════════════════════════════════════

## 为新盒子产出 `Box.item_pool`（基础池副本）。**01 在发放盒子时调用**（§5.5 / §7）。
## 只取一份、**不构造池子内容**——内容全来自 `SeriesDef`（模板归 01）。
##
## `state` 目前不参与构造：签名保持文档口径（§4.5），供将来冻结套系级快照时使用。
static func init_pool(state: GameState, box_id: String, series_id: StringName) -> ItemPool:
	var series := GachaCatalog.get_series(series_id)
	if series == null:
		push_error("PoolService.init_pool: 未知 series_id `%s`" % series_id)
		return null
	var pool := ItemPool.new()
	pool.box_id = box_id
	pool.series_id = series_id
	pool.regular_count = series.regular_count
	pool.socket_count = series.socket_count
	pool.revision = 0
	pool.base_items = series.regular_items.duplicate()
	return pool


## 定长空位数组（长度 == socket_count，**空位为空项**）——"未配置的盒子"的 `modules`。
static func empty_slots(socket_count: int) -> Array[Module]:
	var out: Array[Module] = []
	for _i in maxi(socket_count, 0):
		out.append(null)
	return out


# ══════════════════════════════════════════════════════════════════════════════
#  只读入口
# ══════════════════════════════════════════════════════════════════════════════

## 取 `Box.item_pool`（生成数据的凭证）。
static func get_item_pool(state: GameState, box_id: String) -> ItemPool:
	var b := _find(state, box_id)
	return b.item_pool if b != null else null


## 取 `Box.modules`——**独立只读入口**（核心 §4.1.2：模块列表可以独立于池子被查看）。
## 返回副本：改它**不影响盒子**（写入只能走 `socket`——v0.44 起这是**唯一**写路径）。
static func get_modules(state: GameState, box_id: String) -> Array[Module]:
	var b := _find(state, box_id)
	if b == null:
		return [] as Array[Module]
	return b.modules.duplicate()


## 取当前派生状态（= f(item_pool, modules)）。**不返回概率、不做算术**（概率归 07）。
## 缓存按 `revision` 失效；`revision` 对不上或没有缓存就**逐盒重建**。
static func get_pool_state(state: GameState, box_id: String) -> PoolState:
	var b := _find(state, box_id)
	if b == null:
		return null
	return rebuild(state, box_id)


## **逐盒重建**派生状态（§5.2 第 0–9 步；文档里的 `_rebuild`）。
##
## **绝不复用"按 `series_id` 缓存的某一份池子"**——同套系的两个盒子可以有不同池子，
## 复用缓存会把它们误合并成一份（§2 的"三条不得越界"③）。
##
## 输入不合法（例如某盒 `modules` 里有个已下线的 `module_id`）→ 返回 `null` 并 `push_error`
## 列出缺失的 id，**禁止静默降级成基础池**（那会静默吃掉玩家投入的模块成本，§10.1 T24 ④）。
static func rebuild(state: GameState, box_id: String) -> PoolState:
	var b := _find(state, box_id)
	if b == null:
		return null
	if b.item_pool == null:
		push_error("PoolService.rebuild: 盒子 `%s` 没有 item_pool" % box_id)
		return null
	var missing := _missing_module_ids(b)
	if not missing.is_empty():
		push_error("PoolService.rebuild: 盒子 `%s` 引用了未注册的 module_id：%s" % [box_id, missing])
		return null
	var cached = _states.get(box_id, null)
	if cached != null and (cached as PoolState).revision == b.item_pool.revision:
		return cached
	var s := _compute(b, b.item_pool.revision)
	_states[box_id] = s
	return s


## 丢弃缓存（测试或换档时用；**派生值本来就不入档**，丢弃等于"下次重建"）。
static func drop_cached_state(box_id: String) -> void:
	_states.erase(box_id)


static func drop_all_cached_states() -> void:
	_states.clear()


# ══════════════════════════════════════════════════════════════════════════════
#  写入入口：镶嵌（**唯一写路径**）
# ══════════════════════════════════════════════════════════════════════════════

## 镶嵌：把 `Module` 写进该盒 `modules` 的**第 `slot` 位**（该位必须是空项）。
##
## · 玩家可指定**任意空位**；**往占用位放一律拒绝（`slot_occupied`）**——
##   ★ **v0.44（用户裁决）：拆卸与替换都已去掉**，**模块一旦镶上就永久锁定在这个位子上，
##   直到盒子被摧毁**；没有任何"取下来换一个"的路径（下方 `unsocket` 的墓碑说明）。
## · **成本 = 该模块的金币**（`ModuleDef.gold_cost`，经 `02` 的一次 `transact` 扣除）；
##   余额不足 ⇒ `currency_insufficient`，**什么都不改**（在写 `modules` / 扣寿命之前返回）；
## · **镶嵌即锁定进这个盒子**：配置**下一个盒子**需要**新的模块**（不存在"模块库存"）；
## · **★ 设备是硬门槛**（v0.14 裁决；v0.17 起玩家侧入口是 `DeviceService.socket()`——薄入口只做"校验 + 转发"，
##   本方法是**执行者**，这里的校验是**同一枚码的兜底**）——`state.has_device() == false` ⇒ 拒绝 `no_device`，
##   **一次寿命都不扣**（门槛检查排在所有消耗之前）；
## · **★ v0.14：装模块也消耗这个盒子的一次使用**（与兑现共用同一个计数器）——
##   归零即摧毁；**失败一律不扣次数**（校验失败、金币不足都在消耗之前返回）；
## · 返回 `{ok, reason, state, errors, destroyed}`：`destroyed == true` 表示这次镶嵌把盒子扣到 0、
##   盒子已被摧毁（**即使它从未兑现过**，那是合法路径）。
##
## `[登记]` **04 设备系统是"镶嵌（装模块）的入口 / 工具路径"，本方法仍是池子数据的唯一写入方**——
##   **"唯一写入方"这条不变量不因装置成为工具而改变**（v0.17：`04` 负责"开启盲盒 + 镶嵌模块"两个入口；
##   **v0.18 又加了第三件"设备升级"**）。
##   ⚠️ **v0.18**：**镶嵌既不花原石、也不看设备等级**（等级门控只作用于"开盒"）⇒ **本方法的语义一字未改**。
##   **未定项**：「是否必须先有装置才能镶嵌」（即装置成为镶嵌的**前置门槛**，而不只是 UI 路径）
##   —— 用户原话"设备系统**用于**给盲盒添加模块"读起来像工具路径，但"必须先有装置"也说得通。
##   **本实现按"工具路径"落地：不设任何装置门槛**；该判定留给 **04 重写**那一轮。
static func _write_module(state: GameState, box_id: String, module_id: StringName, slot: int) -> Dictionary:
	if not _write_gate:
		return _reject(R_WRITE_DENIED)
	var b := _find(state, box_id)
	if b == null:
		return _reject(R_BOX_NOT_FOUND)
	if not state.has_device():
		# ★ v0.14 裁决：**设备是硬门槛**——没有设备就不能装模块。
		#   这里在**任何消耗之前**返回 ⇒ **一次寿命都不扣**（与"校验失败不扣次数"同一纪律）。
		#   注意：设备只是**前置条件**，本函数仍是池子数据的**唯一写入方**（不变量不变）。
		return _reject(R_NO_DEVICE)
	if b.location != ItemConstants.LOC_WAREHOUSE:
		# ★ v0.26：**邮件里的盒子不可配置**（与物品同一纪律：邮件不是"可用持有"）。
		#   在任何消耗之前拒绝（不扣寿命、不扣金币、不改 modules）。
		return _reject(ItemConstants.REASON_BOX_IN_MAIL)
	if b.item_pool == null:
		return _reject(R_POOL_INVALID)
	if slot < 0 or slot >= b.modules.size():
		return _reject(R_BAD_SLOT)
	var mdef := GachaCatalog.get_module(module_id)
	if mdef == null:
		return _reject(R_UNKNOWN_MODULE)
	if b.modules[slot] != null:
		# ★ v0.44：位子已占用 ⇒ 一律拒绝。**模块镶上即永久锁定**（拆卸与替换都已删除），
		#   所以这里不是"先拆再装"的提示，而是**终局拒绝**。
		return _reject(R_SLOT_OCCUPIED)

	# 先做**计划校验**（V2 / V4 / V5 / V6 / V7 / C6），再花钱——非法计划不许产生任何消耗
	var plan := b.modules.duplicate()
	plan[slot] = Module.make(module_id, mdef.quality, _now())
	var plan_errors := _plan_errors(b.item_pool, plan)
	if not plan_errors.is_empty():
		return _reject(_code_of(plan_errors[0]), plan_errors)

	# ★★ v0.19：**镶嵌的成本 = 该模块的金币**（`ModuleDef.gold_cost`，用户裁决）。
	#   · **金额完全由模块字段决定**——不在这里算任何折扣、也不引入第二个价格来源；
	#   · 经 `02` 的一次 `transact` 扣除（**本函数不是余额的写入方**，只有 `ItemService` 是）；
	#   · **不足 ⇒ `currency_insufficient` 且什么都不改**（在写 `modules` / 扣寿命之前返回）；
	#   · **模块不再消耗任何物品**（旧口径 `item_cost` / `consume_by_filter` 已作废，核心 §16.14）。
	if mdef.gold_cost > 0:
		var pay := ItemService.transact([
			{
				"op": ItemConstants.OP_CURRENCY,
				"kind": ItemConstants.CURRENCY_GOLD,
				"delta": -mdef.gold_cost,
			},
		])
		if not pay["ok"]:
			return _reject(StringName(pay["reason"]))

	b.modules[slot] = Module.make(module_id, mdef.quality, _now())
	b.item_pool.revision += 1                     # ★ 每次写入 +1（revision 是缓存与失效的唯一依据）
	var s := _compute(b, b.item_pool.revision)
	_states[box_id] = s
	# ★ v0.14：**成功镶嵌消耗一次使用**（与兑现**共用同一个计数器**）。
	#   `uses_remaining` 归 0 ⇒ **归零即摧毁**（盒子连同 `item_pool` / `modules` 从清单移除）——
	#   **哪怕它一次都没兑现过也合法**，这就是"装模块把盒子扣到 0"的那条路径。
	var destroyed := state.spend_use(b)
	if destroyed:
		# 盒子已经没了：丢掉它的派生状态缓存，并且**不发** `pool_changed`
		# （订阅方按 box_id 取状态只会拿到 null；"盒子被摧毁"目前没有定义信号，已登记为待定）
		drop_cached_state(box_id)
		return {
			"ok": true, "reason": R_OK, "state": s, "errors": [] as Array[String],
			"destroyed": true,
		}
	bus.pool_changed.emit(box_id, b.item_pool.revision)
	return {
		"ok": true, "reason": R_OK, "state": s, "errors": [] as Array[String],
		"destroyed": false,
	}


## ── 墓碑：`unsocket()` 已于 **v0.44 删除**（用户裁决）────────────────────────────────
##
## **拆卸与替换都不再存在**：模块一旦镶嵌就**永久锁定在那个位子上**，直到盒子被摧毁
## （寿命归零 ⇒ 盒子连同 `modules` 一起消失，见 `GameState.remove_box()`）。
##
## **为什么整条路径删掉、而不是留着不用**：
##   · 拆卸是"能把模块取下来"的唯一入口，留着它就等于留了一条**绕过新规则的后门**
##     （将来任何人写一行 `unsocket(...)` 就能把永久承诺改回可逆，而没有任何断言会拦下）；
##   · 它的历史语义已经两次作废（v0.19 起零返还、v0.44 起连动作本身取消），
##     留着只会让读者以为"还能拆，只是不返还"。
##
## **不要把它加回来**（与 `UNSOCKET_REFUND_RATE` 的墓碑同一纪律）。若将来要恢复"可替换"，
## 那必须是**一条新裁决 + 一条新的、显式计价与确认的写入路径**（例如"覆盖式镶嵌"），
## 不能靠复活这个函数。
##
## 连带失效的东西（都保留为墓碑，不再有产出路径）：`R_SLOT_EMPTY`（没有"拆空位"这件事了）、
## `source.kind = &"refund"`（v0.19 起就没有调用方）、`DeviceService.replace()`（见 04 的墓碑）。


# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.45：池子成员与物品三态（**可编辑字段**，不走模块）
# ══════════════════════════════════════════════════════════════════════════════
#
# 用户裁决："**物品池中可以添加生成的物品，可以设置物品池中的物品的显示、隐藏、禁用**"
# （追问确认：做成**池子上的可编辑字段**，不是新的模块类型；**禁用 = 出候选集并重新归一、不产生 void**；
#  **隐藏 = 仍参与抽取，只是不在面板列出**；**添加 = 从已注册物品里挑**）。
#
# 与模块的分工（**不得混用**）：
#   · **模块 BAN**：需要镶嵌、花金币、扣寿命、永久；被排除质量 **40% 蒸发到 void、60% 摊回**；
#   · **本节的「禁用」**：直接改池子字段、**免费、可随时改回**；被禁用的物品**整体退出分布**，
#     其余物品在 10000 bp 里**重新归一**，**不产生任何 void**。
# 两者都能让一件物品"抽不到"，但**代价结构与概率后果完全不同**——所以是两个旋钮，不是一个。

## 新物品进池子（`item_id` 必须已在 `ItemCatalog` 注册；不得已在池中）。
##
## 返回 `{ok, reason, state, errors, destroyed}`（与 `socket()` 同形，便于上层统一处理）。
static func _write_add_item(state: GameState, box_id: String, item_id: StringName) -> Dictionary:
	if not _write_gate:
		return _reject(R_WRITE_DENIED)
	var b := _find(state, box_id)
	if b == null:
		return _reject(R_BOX_NOT_FOUND)
	if b.location != ItemConstants.LOC_WAREHOUSE:
		return _reject(ItemConstants.REASON_BOX_IN_MAIL)
	if b.item_pool == null:
		return _reject(R_POOL_INVALID)
	if ItemCatalog.get_def(item_id) == null:
		return _reject(R_UNKNOWN_ITEM)
	if b.item_pool.has_item(item_id):
		return _reject(R_ITEM_ALREADY_IN_POOL)
	if not b.item_pool.add_item(ItemCatalog.get_def(item_id)):
		return _reject(R_POOL_INVALID)

	b.item_pool.revision += 1
	var s := _compute(b, b.item_pool.revision)
	_states[box_id] = s
	bus.pool_changed.emit(box_id, b.item_pool.revision)
	return {
		"ok": true, "reason": R_OK, "state": s, "errors": [] as Array[String],
		"destroyed": false,
	}


## 改一件物品的三态（`ItemPool.ItemState`）。
##
## 拒绝条件（**都不改任何状态**）：盒子不存在 / 在邮件 / `item_id` 不在池中 / 状态越界 /
## **禁用后会让"可产出数"掉到 3 以下**（C6 下限，`regular_count − 3` 的同一枚码 `below_c6_floor`）。
static func _write_set_state(
	state: GameState, box_id: String, item_id: StringName, new_state: int
) -> Dictionary:
	if not _write_gate:
		return _reject(R_WRITE_DENIED)
	var b := _find(state, box_id)
	if b == null:
		return _reject(R_BOX_NOT_FOUND)
	if b.location != ItemConstants.LOC_WAREHOUSE:
		return _reject(ItemConstants.REASON_BOX_IN_MAIL)
	if b.item_pool == null:
		return _reject(R_POOL_INVALID)
	if not b.item_pool.has_item(item_id):
		return _reject(R_ITEM_NOT_IN_POOL)
	if new_state < ItemPool.ItemState.SHOWN or new_state > ItemPool.ItemState.DISABLED:
		return _reject(R_BAD_STATE)

	# ★ 幂等：设成"当前已经是"的状态 ⇒ 成功但**什么都不动**（不推进 revision、不发信号）。
	#   否则反复点同一个按钮会白白让 07 的缓存失效。
	if b.item_pool.state_of(item_id) == new_state:
		return {
			"ok": true, "reason": R_OK, "state": get_pool_state(state, box_id),
			"errors": [] as Array[String], "destroyed": false,
		}

	# C6：禁用是"减少可产出数"，必须守住 ≥ 3（改成别的状态只会增加或不变）
	var was_disabled := b.item_pool.state_of(item_id) == ItemPool.ItemState.DISABLED
	if new_state == ItemPool.ItemState.DISABLED and not was_disabled:
		if b.item_pool.enabled_count() - 1 < 3:
			return _reject(R_BELOW_C6)

	if not b.item_pool.set_state(item_id, new_state):
		return _reject(R_BAD_STATE)

	b.item_pool.revision += 1
	var s := _compute(b, b.item_pool.revision)
	_states[box_id] = s
	bus.pool_changed.emit(box_id, b.item_pool.revision)
	return {
		"ok": true, "reason": R_OK, "state": s, "errors": [] as Array[String],
		"destroyed": false,
	}


## 只读：`item_id(String) -> 状态(int)` 的副本（缺键 = 显示）。
func get_item_states(state: GameState, box_id: String) -> Dictionary:
	var b := _find(state, box_id)
	if b == null or b.item_pool == null:
		return {}
	return b.item_pool.item_states.duplicate()


## 试算：算出"若把 `module_id` 放进该盒第 `slot` 位"的**候选派生状态**。
##
## **不写入任何状态、不推进 `revision`、不触发缓存失效、不消耗任何实例**；
## 走与 `_compute` **完全相同**的计算路径（避免两套实现 ⇒ P6 实时预览 / 沙盒）。
## **09 的演出层不得调用它**（演出只播报，不得预览改变结果）。
static func preview_socket(state: GameState, box_id: String, slot: int, module_id: StringName) -> PoolState:
	var b := _find(state, box_id)
	if b == null or b.item_pool == null:
		return null
	if slot < 0 or slot >= b.modules.size():
		return null
	var mdef := GachaCatalog.get_module(module_id)
	if mdef == null:
		return null
	var plan := b.modules.duplicate()
	plan[slot] = Module.make(module_id, mdef.quality, 0)
	if not _plan_errors(b.item_pool, plan).is_empty():
		return null
	return _compute_with(b.item_pool, plan, b.item_pool.revision)


# ══════════════════════════════════════════════════════════════════════════════
#  校验（§5.2.3 V1–V7 + C4 / C6）
# ══════════════════════════════════════════════════════════════════════════════

## 校验"某个 `modules` 计划"是否合法。返回**空数组 = 合法**；否则每项形如 `"码：说明"`。
##
## 覆盖：V2（不得同时排除与提升）、V3（已占用位数 ≤ socket_count）、
## V4（提升倍数 ≤ ×3）、V5（排除数 ≤ `ban_limit`）、V6（互斥标记）、V7（数组形状 / 模块已注册）、
## 以及"目标物品必须在池内"与 C6 的可产出下界。
##
## ★ **V1 已随 v0.13 作废**（`targets` 不得包含隐藏物品——池里已经没有隐藏物品了）。
##   按 §5.2.3 的纪律：**编号保留、不重排、不得把它改写成别的断言再占用 V1**；
##   因此"目标必须是池内物品"这条**不叫 V1**，它属于 V7 的"非空项良构"。
static func validate_box(box: Box, series: SeriesDef) -> Array[String]:
	if box == null or box.item_pool == null:
		return [_msg(R_POOL_INVALID, "盒子或 item_pool 为 null")]
	var out := _plan_errors(box.item_pool, box.modules)
	if series != null:
		for p in series.validate():
			out.append(_msg(R_BAD_SERIES, p))
	return out


## 完整重建（写入路径与只读入口共用）。
static func _compute(b: Box, revision: int) -> PoolState:
	return _compute_with(b.item_pool, b.modules, revision)


static func _compute_with(pool: ItemPool, modules: Array[Module], revision: int) -> PoolState:
	var full_ids := pool.item_ids()
	var base_arr := pool.compute_weights_bp()
	var st := PoolState.new()
	st.box_id = pool.box_id
	st.series_id = pool.series_id
	st.revision = revision
	st.socket_count = pool.socket_count
	st.regular_count = pool.regular_count
	st.hidden_ids = pool.hidden_ids()       # ★ v0.45：派生视图（隐藏仍参与抽取，不影响分布）
	st.disabled_ids = pool.disabled_ids()   # ★ v0.45：禁用**不参与抽取** ⇒ 不进 weights_bp
	if base_arr.is_empty():
		return st                                  # 池子非法：交空状态，由 validate 报因

	# ① 基础权重（v0.12：由 rarity 派生；v0.13：全部物品共分 100%）
	#    `base` 同时是"按比例摊回"的依据（§5.2 第 5 步：AUTO → 按基础权重给其余未排除物品），
	#    因此在这里就转成按 item_id 索引的字典（PackedInt32Array 不能当比例表用）。
	# ★ v0.45：**禁用项退出候选集**。`compute_weights_bp()` 返回全长数组（与 `full_ids` 对位），
	#   禁用项在里面本来就是 0；下面直接**不把它们放进 `w`**——于是
	#   ① `weights_bp` 只含真正可产出的物品；② `banned_ids()` 不会把"禁用"误报成"被排除"。
	var ids: Array[StringName] = []
	for _e in full_ids:
		if not st.disabled_ids.has(_e):
			ids.append(_e)

	var base: Dictionary = {}
	var w: Dictionary = {}
	for i in full_ids.size():
		var _id := full_ids[i]
		if st.disabled_ids.has(_id):
			continue          # ★ v0.45：禁用项不参与抽取 ⇒ 不进候选集
		base[_id] = int(base_arr[i])
		w[_id] = int(base_arr[i])
	var mass := TOTAL_BP
	var void_bp := 0

	# ② 排除（BAN）：被排除项的**基础权重**成为 freed_mass；40% 蒸发为 void、60% 可回收
	var banned: Array[StringName] = []
	var boost_ops: Array = []
	var targeted: Array = []                       # [{target, slice}]
	var freed := 0
	for m in modules:
		if m == null:
			continue
		var d := GachaCatalog.get_module(m.module_id)
		if d == null:
			continue
		match d.op_type:
			ModuleDef.OpType.BAN:
				for t in d.targets:
					if w.has(t) and not banned.has(t):
						banned.append(t)
						freed += int(w[t])
			ModuleDef.OpType.BOOST:
				boost_ops.append(d)
			ModuleDef.OpType.RECOVER:
				pass  # 第二切片：本版仅定义接口（socket() 已在定义级拒绝它）
	# ★ v0.40（15 干员）：出战干员的额外排除——**走与模块 BAN 完全相同的路径**
	#   （`freed` 累加 ⇒ 下方 40% 蒸发 / 60% 摊回零和自动复用）。
	#   干员是"无代价被动"：不占盒子槽位、不改 `modules`，只在求值时注入排除集合。
	if extra_ban_provider.is_valid():
		var extra: Array = extra_ban_provider.call()
		for t in extra:
			var tn := StringName(t)
			if w.has(tn) and not banned.has(tn):
				banned.append(tn)
				freed += int(w[tn])
	# 逐模块切分"可回收质量"：AUTO 的块按基础权重摊给其余物品，TARGETED 的块全给其目标
	var surviving: Array[StringName] = []
	for id in ids:
		if not banned.has(id):
			surviving.append(id)
	if freed > 0:
		void_bp = int(floor(float(freed) * (1.0 - RECOVER_RATE)))   # 40% 蒸发（C2）
		var recoverable := freed - void_bp                          # 60%（用补数，零取整损失）
		var targeted_mass := 0
		for raw in modules:
			if raw == null:
				continue
			var d := GachaCatalog.get_module(raw.module_id)
			if d == null or d.op_type != ModuleDef.OpType.BAN:
				continue
			if d.redistribute_mode != ModuleDef.RedistributeMode.TARGETED:
				continue
			var mine := 0
			for t in d.targets:
				if banned.has(t):
					mine += int(base[t])
			var slice := int(floor(float(recoverable) * float(mine) / float(freed)))
			targeted_mass += slice
			if surviving.has(d.redistribute_target):
				targeted.append({"target": d.redistribute_target, "slice": slice})
		# 剩余的可回收质量按**基础权重**摊给仍可产出的物品（AUTO 语义）
		var auto_mass := recoverable - targeted_mass
		for t in banned:
			w[t] = 0
		_allocate(w, surviving, base, ids, mass - freed + auto_mass)

	# ③ 提升（BOOST）：目标 ×N，**增量从其他物品按比例扣除**（零和）
	for d in boost_ops:
		for t in d.targets:
			if not w.has(t):
				continue
			_apply_boost(w, ids, t, d.magnitude, mass)

	# ④ 零和收口 + 注入 TARGETED 切块（在提升之后加，避免被当作"其他物品"按比例扣掉）
	for item in targeted:
		w[item["target"]] = int(w[item["target"]]) + int(item["slice"])

	st.weights_bp = w
	st.void_mass_bp = void_bp
	_reconcile(st, ids)
	return st


## 把物品质量收口到 `TOTAL_BP − void_mass_bp`，保证 C1 的整数零和等式**精确成立**。
## （正常路径上 `_allocate` 已经精确；这里是最后一道保险，也覆盖 TARGETED 注入。）
static func _reconcile(st: PoolState, ids: Array[StringName]) -> void:
	var target := TOTAL_BP - st.void_mass_bp
	var alloc := _allocate(st.weights_bp, ids, st.weights_bp, ids, target)
	st.weights_bp = alloc


# ══════════════════════════════════════════════════════════════════════════════
#  整数分配工具（最大余数法：Σ 精确）
# ══════════════════════════════════════════════════════════════════════════════

## 把 `members` 的权重按 `basis` 的比例**重新分配**，使其合计**精确等于** `target_total`。
##
## 实现只有一处：`BpAlloc.allocate()`（01 与 07 共用）。此处只是本地化的包装，
## 免得"整数取整"在仓库里出现第二份实现（那会让 C1 的精确断言分家）。
static func _allocate(w: Dictionary, members: Array, basis: Dictionary, order: Array, target_total: int) -> Dictionary:
	return BpAlloc.allocate(w, members, basis, order, target_total)


## 提升：目标 ×`magnitude`，**增量从其他物品按比例扣除**。
## 目标的最终权重**不低于原值**（提升不会缩小），**总质量恒定**（零和）。
static func _apply_boost(w: Dictionary, ids: Array, target: StringName, magnitude: float, total: int) -> void:
	var w_t := int(w.get(target, 0))
	if w_t <= 0:
		return
	var others: Array[StringName] = []
	for id in ids:
		if id != target:
			others.append(id)
	var others_sum := 0
	for id in others:
		others_sum += int(w[id])
	var requested := roundi(float(w_t) * magnitude)
	var w_t_new := clampi(requested, w_t, total)
	var others_new := total - w_t_new
	if others_sum <= 0:
		w[target] = total                       # 池子只剩这一项可产出：全部质量归它（C6 会另行报错）
		return
	var alloc := _allocate(w, others, w, ids, others_new)
	for id in others:
		w[id] = int(alloc[id])
	w[target] = w_t_new


# ══════════════════════════════════════════════════════════════════════════════
#  计划校验 / 制造成本
# ══════════════════════════════════════════════════════════════════════════════

## 对一个 `modules` 计划做 V2–V7 + C4/C6 校验（不消耗、不写入）。
static func _plan_errors(pool: ItemPool, modules: Array[Module]) -> Array[String]:
	var out: Array[String] = []
	var ids := pool.item_ids()

	# V7：数组形状（定长长度恒 == socket_count；空位为空项；非空项良构）
	if modules.size() != pool.socket_count:
		out.append(_msg(R_BAD_SHAPE, "modules.size() = %d ≠ socket_count = %d（C4 的第①条）"
			% [modules.size(), pool.socket_count]))
	var occupied := 0
	var banned: Array[StringName] = []
	var boosted: Array[StringName] = []
	var tags_seen: Dictionary = {}
	var active: Array[ModuleDef] = []
	for m in modules:
		if m == null:
			continue
		occupied += 1
		var d := GachaCatalog.get_module(m.module_id)
		if d == null:
			out.append(_msg(R_UNKNOWN_MODULE, "`%s` 不在 ModuleDef 注册表里（V7：非空项良构）" % m.module_id))
			continue
		active.append(d)
		for t in d.targets:
			if not ids.has(t):
				out.append(_msg(R_UNKNOWN_TARGET, "`%s`.targets 含池外物品 `%s`（目标必须指向池内物品）" % [d.id, t]))
		if d.op_type == ModuleDef.OpType.RECOVER:
			out.append(_msg(R_RECOVER_UNSUPPORTED, "`%s` 是 RECOVER：本版仅定义接口（第二切片）" % d.id))
		if d.op_type == ModuleDef.OpType.BOOST:
			if d.magnitude > ModuleDef.BOOST_CAP:
				out.append(_msg(R_BOOST_OVER_CAP, "`%s`.magnitude = %.2f > ×%.1f（V4）"
					% [d.id, d.magnitude, ModuleDef.BOOST_CAP]))
			for t in d.targets:
				if not boosted.has(t):
					boosted.append(t)
		elif d.op_type == ModuleDef.OpType.BAN:
			for t in d.targets:
				if not banned.has(t):
					banned.append(t)
		for tag in d.exclusive_tags:
			if tags_seen.has(tag):
				out.append(_msg(R_TAG_CONFLICT, "`%s` 与 `%s` 共享互斥标记 `%s`（V6）"
					% [d.id, tags_seen[tag], tag]))
			else:
				tags_seen[tag] = d.id

	# V3 / C4：已占用位数 ≤ socket_count（长度恒等是结构性的，**这条才是真正的守护**）
	if occupied > pool.socket_count:
		out.append(_msg(R_BAD_SHAPE, "已占用位数 %d > socket_count %d（V3 / C4②）" % [occupied, pool.socket_count]))

	# V2：同一物品不得同时被排除与提升
	for t in banned:
		if boosted.has(t):
			out.append(_msg(R_BAN_BOOST_CONFLICT, "物品 `%s` 同时被排除与提升（V2）" % t))

	# V5 / C6：排除数 ≤ ban_limit（= regular_count − 3）
	var ban_limit := maxi(pool.regular_count - 3, 0)
	if banned.size() > ban_limit:
		out.append(_msg(R_BAN_LIMIT, "排除 %d 件 > ban_limit %d（V5 / C6）" % [banned.size(), ban_limit]))

	# C6：可产出物品数 ≥ 3（含"被提升取整成 0 bp"的情形）
	var producible := pool.regular_count - banned.size()
	if producible < 3:
		out.append(_msg(R_BELOW_C6, "可产出物品数 %d < 3（C6 下限）" % producible))
	return out


## ⚠️ **v0.19 已删除**：`_plan_cost_instances(mdef)`（为"按物品需求向量挑素材"而设）。
##
## 模块不再消耗物品（成本 = `ModuleDef.gold_cost` 的金币，核心 §4.5 / §16.14）
## ⇒ 这个函数**没有调用方**，整段删除；`ItemService.consume_by_filter()` 也随之失去调用方
## （API 与 tag `engine` 都保留为墓碑，见 `02-item.md` §5.7）。
## **不要把它加回来**：加回来就等于复活"物品 → 模块"这条已被裁定删除的路径（核心 §3）。


# ══════════════════════════════════════════════════════════════════════════════
#  小工具
# ══════════════════════════════════════════════════════════════════════════════

static func _find(state: GameState, box_id: String) -> Box:
	if state == null:
		return null
	return state.find_box(box_id)


static func _missing_module_ids(b: Box) -> Array[StringName]:
	var out: Array[StringName] = []
	for m in b.modules:
		if m != null and not GachaCatalog.has_module(m.module_id):
			out.append(m.module_id)
	return out


static func _now() -> int:
	return int(Time.get_ticks_msec())


static func _msg(code: StringName, text: String) -> String:
	return "%s：%s" % [code, text]


## 从 `"码：说明"` 里取回原因码（`socket` 的 `reason` 用）。
static func _code_of(entry: String) -> StringName:
	var i := entry.find("：")
	return StringName(entry.substr(0, i)) if i > 0 else StringName(entry)


static func _reject(reason: StringName, errors: Array = []) -> Dictionary:
	return {"ok": false, "reason": reason, "state": null, "errors": errors}

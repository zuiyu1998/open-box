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
const UNSOCKET_REFUND_RATE := 0.5            # 核心 D8：拆卸只返还 50% 材料

# ── 拒绝原因码（`[补充]`：文档只写"响亮地拒绝并指明冲突源"，未给码；这里集中定义便于测试）──
const R_OK := &""
const R_BOX_NOT_FOUND := &"box_not_found"
## v0.14 裁决：**没有设备就不能装模块**（与开盒侧 `GachaService.R_NO_DEVICE` 同名同义）
const R_NO_DEVICE := &"no_device"
const R_BAD_SLOT := &"bad_slot"
const R_UNKNOWN_MODULE := &"unknown_module"
const R_SLOT_OCCUPIED := &"slot_occupied"
const R_SLOT_EMPTY := &"slot_empty"
const R_BAD_SHAPE := &"modules_shape"              # V7 / C4①（定长长度）
const R_UNKNOWN_TARGET := &"unknown_target"        # 目标物品不在池内（**不是** V1——V1 已作废）
const R_BAN_BOOST_CONFLICT := &"ban_boost_conflict"  # V2
const R_BOOST_OVER_CAP := &"boost_over_cap"        # V4
const R_BAN_LIMIT := &"ban_limit_exceeded"         # V5（派生自 C6）
const R_TAG_CONFLICT := &"exclusive_tag_conflict"  # V6
const R_RECOVER_UNSUPPORTED := &"recover_unsupported"
const R_BELOW_C6 := &"below_c6_floor"              # 可产出物品数 < 3
const R_COST_INSUFFICIENT := &"cost_insufficient"
const R_NO_SPACE := &"no_space"                    # 拆卸返还装不下（裁决 17）
const R_REFUND_UNRESOLVED := &"refund_unresolved"  # resolve_item_id 反查不到
const R_POOL_INVALID := &"pool_invalid"
const R_BAD_SERIES := &"bad_series"


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


## 取 `Box.modules`——**独立只读入口**（核心 §4.1.2：模块列表可以独立于池子被查看 / 替换 / 拆卸）。
## 返回副本：改它**不影响盒子**（写入只能走 `socket` / `unsocket`）。
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
#  写入入口：镶嵌 / 替换 / 拆卸
# ══════════════════════════════════════════════════════════════════════════════

## 镶嵌：把 `Module` 写进该盒 `modules` 的**第 `slot` 位**（该位必须是空项）。
##
## · 玩家可指定**任意空位**；往**占用位**放必须**显式替换**（先 `unsocket`），**不做隐式覆盖**；
## · 制造消耗 = **一次 `ItemService.transact()`**：任一 `item_cost` 条目实例不足即**整体失败**
##   （原子、全有或全无）；**制造侧不做空间预检**——它只消耗不产出，不因仓库满而失败；
## · **镶嵌即锁定进这个盒子**：配置**下一个盒子**需要**新的模块**（不存在"模块库存"）；
## · **★ v0.14 裁决：设备是硬门槛**——`state.has_device() == false` ⇒ 拒绝 `no_device`，
##   **一次寿命都不扣**（门槛检查排在所有消耗之前）；
## · **★ v0.14：装模块也消耗这个盒子的一次使用**（与兑现共用同一个计数器）——
##   归零即摧毁；**失败一律不扣次数**（校验失败、制造成本不足都在消耗之前返回）；
## · 返回 `{ok, reason, state, errors, destroyed}`：`destroyed == true` 表示这次镶嵌把盒子扣到 0、
##   盒子已被摧毁（**即使它从未兑现过**，那是合法路径）。
##
## `[登记·待定]` **04 设备系统是"装模块的入口 / 工具路径"，本方法仍是池子数据的唯一写入方**——
##   **"唯一写入方"这条不变量不因装置成为工具而改变**。
##   **未定项**：「是否必须先有装置才能镶嵌」（即装置成为镶嵌的**前置门槛**，而不只是 UI 路径）
##   —— 用户原话"设备系统**用于**给盲盒添加模块"读起来像工具路径，但"必须先有装置"也说得通。
##   **本实现按"工具路径"落地：不设任何装置门槛**；该判定留给 **04 重写**那一轮。
static func socket(state: GameState, box_id: String, module_id: StringName, slot: int) -> Dictionary:
	var b := _find(state, box_id)
	if b == null:
		return _reject(R_BOX_NOT_FOUND)
	if not state.has_device():
		# ★ v0.14 裁决：**设备是硬门槛**——没有设备就不能装模块。
		#   这里在**任何消耗之前**返回 ⇒ **一次寿命都不扣**（与"校验失败不扣次数"同一纪律）。
		#   注意：设备只是**前置条件**，本函数仍是池子数据的**唯一写入方**（不变量不变）。
		return _reject(R_NO_DEVICE)
	if b.item_pool == null:
		return _reject(R_POOL_INVALID)
	if slot < 0 or slot >= b.modules.size():
		return _reject(R_BAD_SLOT)
	var mdef := GachaCatalog.get_module(module_id)
	if mdef == null:
		return _reject(R_UNKNOWN_MODULE)
	if b.modules[slot] != null:
		# 显式替换：先 unsocket 那一位，**不做隐式覆盖**
		return _reject(R_SLOT_OCCUPIED)

	# 先做**计划校验**（V2 / V4 / V5 / V6 / V7 / C6），再花钱——非法计划不许产生任何消耗
	var plan := b.modules.duplicate()
	plan[slot] = Module.make(module_id, mdef.quality, _now())
	var plan_errors := _plan_errors(b.item_pool, plan)
	if not plan_errors.is_empty():
		return _reject(_code_of(plan_errors[0]), plan_errors)

	# 制造消耗：按需求向量逐条挑选实例（选择顺序 = 02 §5.5：品质升序 → acquired_at → instance_id）
	var cost_ids = _plan_cost_instances(mdef)
	if cost_ids == null:
		return _reject(R_COST_INSUFFICIENT)
	if not cost_ids.is_empty():
		var res := ItemService.transact([
			{"op": ItemConstants.OP_CONSUME, "instance_ids": cost_ids, "tag": ItemConstants.TAG_ENGINE},
		])
		if not res["ok"]:
			return _reject(StringName(res["reason"]))

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


## 拆卸：把该盒 `modules` 的第 `slot` 位**置空**（**定长长度不变**）+ 返还 50% 材料。
##
## ★ **拆卸不要求设备**：v0.14 裁决把设备门槛只摆在**两个消耗寿命的动作**上（开盒、装模块），
##   拆卸既不消耗寿命、也不消耗设备。
##
## · 返还量 = **逐条 `floor(amount × 0.5)`**（余数不累加——与 04 §5.3 同一口径，保证与操作顺序无关）；
## · 返还走 `grant(item_id, { kind = &"refund" })` **新建实例**（新 UUID）——"可逆"说的是
##   **池子状态与物品数量**，不是**实例身份**（§10.1 T6 ③）；
## · **返还装不下 → 拒绝整个拆卸**（裁决 17）：空间预检**必须在事务之前**（先查再动），
##   禁止"先拆、先 grant，发现装不下再靠回滚补救"；
## · 只能拆**未兑现盒子**的池子（兑现后盒子连同 `modules` 一同消耗，没有拆卸路径）。
static func unsocket(state: GameState, box_id: String, slot: int) -> Dictionary:
	var b := _find(state, box_id)
	if b == null:
		return _reject(R_BOX_NOT_FOUND)
	if slot < 0 or slot >= b.modules.size():
		return _reject(R_BAD_SLOT)
	var m := b.modules[slot]
	if m == null:
		return _reject(R_SLOT_EMPTY)
	var mdef := GachaCatalog.get_module(m.module_id)
	if mdef == null:
		# 该模块已下线：不静默当基础池（那会静默吃掉玩家投入的模块成本）
		return _reject(R_UNKNOWN_MODULE)

	# 返还计划（逐条 floor，按 item_id 汇总）
	var refund: Dictionary = {}          # item_id(StringName) -> 件数
	var refund_size := 0
	for entry in mdef.item_cost:
		if entry == null:
			continue
		var item_id := ItemService.resolve_item_id(entry.category, entry.quality)
		if item_id == &"":
			return _reject(R_REFUND_UNRESOLVED)
		var def := ItemCatalog.get_def(item_id)
		if def == null:
			return _reject(R_REFUND_UNRESOLVED)
		var n := int(floor(float(entry.amount) * UNSOCKET_REFUND_RATE))
		if n <= 0:
			continue
		refund[item_id] = int(refund.get(item_id, 0)) + n
		refund_size += def.size * n

	# 空间预检（事务之前；主动操作放不下 = 拒绝整个操作）
	var usage := ItemService.warehouse_usage()
	if int(usage["used"]) + refund_size > int(usage["capacity"]):
		return _reject(R_NO_SPACE)

	# 一次 transact：全部返还在同一事务里（`kind = refund` ⇒ 主动操作 ⇒ 放不下整笔被拒）
	var ops: Array = []
	for item_id in refund.keys():
		for _i in int(refund[item_id]):
			ops.append({
				"op": ItemConstants.OP_GRANT,
				"item_id": item_id,
				"source": {"kind": ItemConstants.KIND_REFUND},
			})
	if not ops.is_empty():
		var res := ItemService.transact(ops)
		if not res["ok"]:
			return _reject(StringName(res["reason"]))

	b.modules[slot] = null                        # 置空；**长度不变**
	b.item_pool.revision += 1
	var s := _compute(b, b.item_pool.revision)
	_states[box_id] = s
	# ★ v0.14：**拆卸不消耗使用次数**（消耗点只有"装模块"与"兑现"两个）；
	#   因此 `destroyed` 恒为 false——盒子的寿命只由那两个动作决定。
	bus.pool_changed.emit(box_id, b.item_pool.revision)
	return {
		"ok": true, "reason": R_OK, "state": s, "errors": [] as Array[String],
		"destroyed": false,
	}


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
	var ids := pool.item_ids()
	var base_arr := pool.compute_weights_bp()
	var st := PoolState.new()
	st.box_id = pool.box_id
	st.series_id = pool.series_id
	st.revision = revision
	st.socket_count = pool.socket_count
	st.regular_count = pool.regular_count
	if base_arr.is_empty():
		return st                                  # 池子非法：交空状态，由 validate 报因

	# ① 基础权重（v0.12：由 rarity 派生；v0.13：全部物品共分 100%）
	#    `base` 同时是"按比例摊回"的依据（§5.2 第 5 步：AUTO → 按基础权重给其余未排除物品），
	#    因此在这里就转成按 item_id 索引的字典（PackedInt32Array 不能当比例表用）。
	var base: Dictionary = {}
	var w: Dictionary = {}
	for i in ids.size():
		base[ids[i]] = int(base_arr[i])
		w[ids[i]] = int(base_arr[i])
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


## 为一条需求向量选出要销毁的实例 id（**只读挑选**；真正销毁在那一次 `transact` 里）。
## 任一 entry 的合格实例不足 ⇒ 返回 `null`（**整体失败，不做部分消耗**）。
## 挑选顺序 = 02 §5.5（品质升序 → acquired_at → instance_id），与 `consume_by_filter` 同序。
static func _plan_cost_instances(mdef: ModuleDef) -> Variant:
	var ids: Array[String] = []
	for entry in mdef.item_cost:
		if entry == null or entry.amount <= 0:
			continue
		var candidates := ItemService.query(entry.category, entry.quality)
		if candidates.size() < entry.amount:
			return null
		for i in entry.amount:
			ids.append(candidates[i])
	return ids


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


## 从 `"码：说明"` 里取回原因码（`socket` / `unsocket` 的 `reason` 用）。
static func _code_of(entry: String) -> StringName:
	var i := entry.find("：")
	return StringName(entry.substr(0, i)) if i > 0 else StringName(entry)


static func _reject(reason: StringName, errors: Array = []) -> Dictionary:
	return {"ok": false, "reason": reason, "state": null, "errors": errors}

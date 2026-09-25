## 物品持有服务（02-item.md §4.3）——**物品实例列表的唯一写入方**。
##
## 注册为 autoload 单例 `ItemService`（见 project.godot）。
##
## 铁律（§4.3 末）：**没有任何其它系统可以直接改 `instances`、`count_index`、
## `warehouse_used` 或 `serial_counters`。** 与 PoolService 对池子状态的独占同级。
##
## 本类是纯数据服务，不依赖场景树，可在无头模式跑单测。
extends Node

# ── 持久状态 ────────────────────────────────────────────────────────────────────

## 仓库容量（**抽象单位**，不是"格数"）。数值归核心 D16 / 02 §11 M7，切片实测。
## 必须 >= 1（§5.9）：容量 0 会让一切被动产出进邮件、一切主动操作被拒，游戏当场不可玩。
var warehouse_capacity: int = 1000

## **唯一事实来源**：现存实例（顺序 = 入库顺序；**含邮件实例**）。
var instances: Array[ItemInstance] = []

## item_id(String) -> 已发放的最大 serial。**只增不减、持久化、绝不从现存实例重算**（§5.6）。
var serial_counters: Dictionary = {}

## 累计入库实例数（幂等命中不计入；**含进邮件的实例**）。
var total_granted: int = 0
## 累计销毁实例数（consume 与 discard 都计入）。
var total_consumed: int = 0

# ── 派生缓存（可由 instances 完全重建；**全部不入档**）──────────────────────────

## "<category>:<quality>" -> 仓库内实例数。§4.4 的 R5 封顶对象（切片 6 个键）。
var count_index: Dictionary = {}
## 同上，但只计邮件实例。
## [!] 实现补充：文档只列了 count_index 与 warehouse_used 两个派生缓存，
##     但 `count(c, q, &"mail")` 是 03 的必需接口（"邮件里有几件需求物品"），
##     逐次全量遍历实例列表会违反 §4.4 的性能论证，故同样增量维护。
var mail_count_index: Dictionary = {}
## 派生值 Σ(仓库内实例的 size)。与 count_index **由同一次写入一起更新**（§4.4 ④）。
var warehouse_used: int = 0

## instance_id -> ItemInstance 的索引。
## [!] 实现补充：文档未列，但 consume/claim/grant 幂等都需要 O(1) 按 id 查找；
##     没有它每次调用都是 O(n)。
var _by_id: Dictionary = {}

## 供 01 注入：series_id -> Array[StringName]（该套系的可产出 item_id）。
## `find_unstocked_items` 用它取候选集——SeriesDef 归 01，本系统不拥有它。
var series_item_provider: Callable = Callable()

## 只读锁：置 true 后拒绝一切写入（测试用，验证"单写入方"）。
var read_only: bool = false


# ══════════════════════════════════════════════════════════════════════════════
#  内部：派生缓存的维护
# ══════════════════════════════════════════════════════════════════════════════

func _key_of(inst: ItemInstance) -> String:
	var def := ItemCatalog.get_def(inst.item_id)
	if def == null:
		return ""
	return def.count_key()


func _index_of(loc: StringName) -> Dictionary:
	return count_index if loc == ItemConstants.LOC_WAREHOUSE else mail_count_index


## 索引 +1。**某键从 0 升上来时才新建条目**（R-M5：不保留 0 条目）。
func _index_add(key: String, loc: StringName) -> void:
	if key == "":
		return
	var idx := _index_of(loc)
	idx[key] = int(idx.get(key, 0)) + 1


## 索引 -1。**降到 0 即删除该键**（R-M5）。
func _index_sub(key: String, loc: StringName) -> void:
	if key == "":
		return
	var idx := _index_of(loc)
	var n := int(idx.get(key, 0)) - 1
	if n <= 0:
		idx.erase(key)  # 归零即消键：玩家可见行为是"没有这种物品时面板上就没有这个条目"
	else:
		idx[key] = n


func _size_of(inst: ItemInstance) -> int:
	var def := ItemCatalog.get_def(inst.item_id)
	return def.size if def != null else 0


## 位置变更的唯一实现（领取 / 落位都经它），同时维护两个派生值。
## **只改 location**——不创建实例、不改 instance_id / serial / source（§5.10）。
func _move(inst: ItemInstance, to_loc: StringName) -> void:
	if inst.location == to_loc:
		return
	var key := _key_of(inst)
	var sz := _size_of(inst)
	_index_sub(key, inst.location)
	if inst.location == ItemConstants.LOC_WAREHOUSE:
		warehouse_used -= sz
	inst.location = to_loc
	_index_add(key, to_loc)
	if to_loc == ItemConstants.LOC_WAREHOUSE:
		warehouse_used += sz


func _fits(size: int) -> bool:
	return warehouse_used + size <= warehouse_capacity


## §5.5 挑选顺序：( quality 升序 , acquired_at 升序 , instance_id 字典序 )
func _less(a: ItemInstance, b: ItemInstance) -> bool:
	var da := ItemCatalog.get_def(a.item_id)
	var db := ItemCatalog.get_def(b.item_id)
	var qa := da.quality if da != null else 0
	var qb := db.quality if db != null else 0
	if qa != qb:
		return qa < qb
	if a.acquired_at != b.acquired_at:
		return a.acquired_at < b.acquired_at
	return String(a.instance_id) < String(b.instance_id)


# ══════════════════════════════════════════════════════════════════════════════
#  溢出策略（§5.10 R-M14）
# ══════════════════════════════════════════════════════════════════════════════

## 解析生效的 overflow 策略。返回 &"" 表示非法（含"越权放宽"）。
##
## **只允许收紧、不允许放宽**：被动产出可显式声明 reject；
## **主动操作声明 mail 会被拒绝**——裁决 17 由此成为结构上不可绕过的红线，
## 而不是"记得这么写"的约定（否则 06 只要多传一个参数就能把转化变回反噬）。
func _resolve_overflow(kind: StringName, requested: StringName) -> StringName:
	var derived := ItemConstants.derive_overflow(kind)
	if derived == &"":
		return &""  # 未知 kind
	if requested == ItemConstants.OVERFLOW_DERIVE:
		return derived
	if requested == derived:
		return derived
	if requested == ItemConstants.OVERFLOW_REJECT and derived == ItemConstants.OVERFLOW_MAIL:
		return ItemConstants.OVERFLOW_REJECT  # 收紧：允许
	if requested == ItemConstants.OVERFLOW_MAIL and derived == ItemConstants.OVERFLOW_REJECT:
		return &""  # 放宽：禁止
	return &""


# ══════════════════════════════════════════════════════════════════════════════
#  serial 分配（§5.6）
# ══════════════════════════════════════════════════════════════════════════════

## **只在开盒产出时分配**（kind == gacha）。
## 转化 / 返还 / 解锁 / 迁移产出的实例 serial == 0，且**不推进计数器**。
## 计数器只增不减、绝不从现存实例重算——否则销毁编号最大的实例后同一编号会被复用，
## 与开箱日志对不上，"收藏编号"的叙事当场断裂。
func _allocate_serial(item_id: StringName, kind: StringName) -> int:
	if kind != ItemConstants.KIND_GACHA:
		return 0
	var k := String(item_id)
	var next := int(serial_counters.get(k, 0)) + 1
	serial_counters[k] = next
	return next


# ══════════════════════════════════════════════════════════════════════════════
#  grant：唯一入库入口（§4.3 / §5.10）
# ══════════════════════════════════════════════════════════════════════════════

## 创建**恰好 1 个**实例并决定其落位（**没有 amount 参数**）。
##
## 返回：成功 → 已带 location 的 ItemInstance；失败 → null（状态完全不变）。
##
## **裸 grant 的失败原因不外传**——"item_id 未注册 / kind 非法 / overflow 越权 /
## 空间被拒"都只是 null。需要区分原因的调用方**一律经 transact**（§5.11）。
##
## `instance_id` 非空且已存在 → **幂等命中**：不新建、不改任何计数器、
## **不改 location**（不得把邮件实例"顺手"搬进仓库），返回现存实例。
func grant(
	item_id: StringName,
	source: Dictionary = {},
	instance_id: String = "",
	overflow: StringName = ItemConstants.OVERFLOW_DERIVE
) -> ItemInstance:
	if read_only:
		return null

	var def := ItemCatalog.get_def(item_id)
	if def == null:
		return null

	var kind: StringName = source.get("kind", &"")
	if not ItemConstants.is_valid_kind(kind):
		return null

	var eff := _resolve_overflow(kind, overflow)
	if eff == &"":
		return null  # 未知 kind 或越权放宽

	# 幂等命中：必须在分配 serial / 判容量之前
	if instance_id != "":
		var existing := _by_id.get(instance_id, null) as ItemInstance
		if existing != null:
			return existing

	# 落位判定**先于**任何状态变更：被拒时不得留下 serial 或实例
	var fits := _fits(def.size)
	if not fits and eff == ItemConstants.OVERFLOW_REJECT:
		return null  # 主动操作：拒绝整个操作，状态完全不变

	var loc := ItemConstants.LOC_WAREHOUSE if fits else ItemConstants.LOC_MAIL
	var new_id := instance_id if instance_id != "" else Uuid.v4()

	var inst := ItemInstance.new()
	inst.instance_id = new_id
	inst.item_id = item_id
	inst.acquired_at = int(Time.get_unix_time_from_system())
	inst.source = source.duplicate(true)
	inst.serial = _allocate_serial(item_id, kind)
	inst.location = loc

	_attach(inst)
	return inst


## 把实例挂进列表与三个派生值（grant / transact 共用）。
func _attach(inst: ItemInstance) -> void:
	instances.append(inst)
	_by_id[inst.instance_id] = inst
	_index_add(_key_of(inst), inst.location)
	if inst.location == ItemConstants.LOC_WAREHOUSE:
		warehouse_used += _size_of(inst)
	total_granted += 1


# ══════════════════════════════════════════════════════════════════════════════
#  consume / discard：唯一出库入口（§4.3 / §5.7）
# ══════════════════════════════════════════════════════════════════════════════

## 按实例销毁，**全有或全无**（R-M6）。
##
## 返回 { ok: bool, consumed: Array[String], reason: StringName }。
##
## **任何真实调用都必须显式传 tag**：默认值 &"unknown" 只为签名兼容保留，
## 不传即当场失败（bad_tag）——R-M9 是**运行时不变量**，不只是测试约定。
## `&"discard"` 是保留值，只能走 discard() 入口。
##
## **不检查空间**：只消耗不产出，永远不会返回 no_space。
## 但**邮件实例不可被销毁**（not_in_warehouse）。
func consume(instance_ids: Array[String], tag: StringName = ItemConstants.TAG_UNKNOWN) -> Dictionary:
	return _destroy(instance_ids, tag, false)


## 主动丢弃（R-M13，裁决 16）：**死局逃生阀**。与 consume 共用实现与原子性，
## 但不产生产出、不计入三个出口标签（归因单列 &"discard"），仅对仓库实例生效。
## 丢弃是玩家**主动**行为，不违反 P5（P5 管的是被动产出不得丢失）。
func discard(instance_ids: Array[String]) -> Dictionary:
	return _destroy(instance_ids, ItemConstants.TAG_DISCARD, true)


func _destroy(ids: Array[String], tag: StringName, is_discard: bool) -> Dictionary:
	var fail := func(reason: StringName) -> Dictionary:
		return {"ok": false, "consumed": [] as Array[String], "reason": reason}

	if read_only:
		return fail.call(ItemConstants.REASON_BAD_OP)

	# 标签校验：R-M9 运行时不变量
	if is_discard:
		pass  # discard 入口自带合法标签
	else:
		if not ItemConstants.CALLER_TAGS.has(tag):
			return fail.call(ItemConstants.REASON_BAD_TAG)

	if ids.is_empty():
		return {"ok": true, "consumed": [] as Array[String], "reason": ItemConstants.REASON_OK}

	# 预校验，全部通过才动状态
	var seen: Dictionary = {}
	for id in ids:
		if seen.has(id):
			return fail.call(ItemConstants.REASON_DUPLICATE_ID)
		seen[id] = true
		var inst := _by_id.get(id, null) as ItemInstance
		if inst == null:
			return fail.call(ItemConstants.REASON_MISSING_INSTANCE)
		if not inst.is_in_warehouse():
			# 邮件实例不可销毁（核心 §4.7 第 1 条边界在出库口的落地）
			return fail.call(ItemConstants.REASON_NOT_IN_WAREHOUSE)

	# 生效
	var consumed: Array[String] = []
	for id in ids:
		var inst := _by_id[id] as ItemInstance
		_detach(inst)
		consumed.append(id)
	total_consumed += consumed.size()
	return {"ok": true, "consumed": consumed, "reason": ItemConstants.REASON_OK}


func _detach(inst: ItemInstance) -> void:
	instances.erase(inst)
	_by_id.erase(inst.instance_id)
	_index_sub(_key_of(inst), inst.location)
	if inst.location == ItemConstants.LOC_WAREHOUSE:
		warehouse_used -= _size_of(inst)


## 按条件挑选并销毁（04 / 05 的素材消耗）。
## **只在仓库实例内挑**（邮件实例不进合格集），按 §5.5 顺序取前 n 个。
##
## `n <= 0` 合法 no-op；**`n > 合格实例数` → 返回 [] 且状态不变**
## （调用方以 `result.size() == n` 判定成功）。
##
## [!] `tag` 参数是文档签名的实现补充：R-M9 禁止无标签销毁，
##     而本接口同样会销毁实例，故必须能带标签。
func consume_by_filter(
	category: StringName,
	quality_floor: int,
	n: int,
	tag: StringName = ItemConstants.TAG_UNKNOWN
) -> Array[String]:
	if n <= 0:
		return [] as Array[String]
	if not ItemConstants.CALLER_TAGS.has(tag):
		return [] as Array[String]
	var candidates := query(category, quality_floor)
	if candidates.size() < n:
		return [] as Array[String]
	var picked := candidates.slice(0, n)
	var res := _destroy(picked, tag, false)
	if not res["ok"]:
		return [] as Array[String]
	return picked


# ══════════════════════════════════════════════════════════════════════════════
#  transact：单次事务原语（§5.11）
# ══════════════════════════════════════════════════════════════════════════════

## 整批 ops **要么全部生效、要么完全不生效**。
##
## 为什么必须有：**单次 consume 原子 ≠ 组合原子**。转化的"销毁源实例 + 创建新实例"、
## 04/05 的"替换（拆旧装新）"都是一个逻辑动作；用多次调用拼起来，
## 中间任一步失败就会留下半个装置 / 凭空消失的物品。
##
## **替换与转化 = 一次 transact 调用，不得拼接。**
##
## 实现取"**全面预校验 + 预演落位 → 再生效**"，而不是"先做后回滚"——
## 这样失败路径上根本不需要回滚能力（回滚是事务系统里最难测对的部分）。
##
## 返回 { ok, reason, consumed, granted, discarded, mailed }。
## `mailed` **只可能来自被动产出的 grant op**；主动操作放不下则整个事务被拒、`mailed == []`。
##
## 边界（裁决 13）：**原子性只覆盖物品侧**。它不覆盖 Box 发放（01）、
## 任务进度（03）、解锁（10）、池子状态（05）——跨系统一致性靠各系统自己的幂等键 + 重放，
## **不承诺也不需要分布式事务**（纯单人）。
func transact(ops: Array) -> Dictionary:
	var empty: Array[String] = []
	var fail := func(reason: StringName) -> Dictionary:
		return {
			"ok": false, "reason": reason,
			"consumed": empty, "granted": empty, "discarded": empty, "mailed": empty,
		}

	if read_only:
		return fail.call(ItemConstants.REASON_BAD_OP)
	if ops.is_empty():
		return {
			"ok": true, "reason": ItemConstants.REASON_OK,
			"consumed": empty, "granted": empty, "discarded": empty, "mailed": empty,
		}

	# ── 阶段一：逐 op 预校验（类型 / 键集 / 标签 / item_id / kind / overflow）──────
	var remove_ids: Array[String] = []     # 全部待销毁的 id（跨 op 去重）
	var remove_tags: Array[StringName] = []  # 与 remove_ids 一一对应（用于区分 consumed / discarded）
	var grant_plans: Array[Dictionary] = []
	var seen_remove: Dictionary = {}

	for raw in ops:
		if not (raw is Dictionary):
			return fail.call(ItemConstants.REASON_BAD_OP)
		var op: Dictionary = raw
		var op_type: StringName = op.get("op", &"")
		if not ItemConstants.ALL_OPS.has(op_type):
			return fail.call(ItemConstants.REASON_BAD_OP)

		# 键集逐字校验：出现其它键或缺少必填键 → bad_op
		var allowed: Array = ItemConstants.OP_KEYS[op_type]
		for k in op.keys():
			if not allowed.has(k):
				return fail.call(ItemConstants.REASON_BAD_OP)
		for k in ItemConstants.OP_REQUIRED_KEYS[op_type]:
			if not op.has(k):
				return fail.call(ItemConstants.REASON_BAD_OP)

		match op_type:
			ItemConstants.OP_GRANT:
				var item_id: StringName = op.get("item_id", &"")
				var def := ItemCatalog.get_def(item_id)
				if def == null:
					return fail.call(ItemConstants.REASON_BAD_OP)
				var src = op.get("source", {})
				if not (src is Dictionary):
					return fail.call(ItemConstants.REASON_BAD_OP)
				var kind: StringName = (src as Dictionary).get("kind", &"")
				if not ItemConstants.is_valid_kind(kind):
					return fail.call(ItemConstants.REASON_BAD_OP)
				var eff := _resolve_overflow(kind, op.get("overflow", ItemConstants.OVERFLOW_DERIVE))
				if eff == &"":
					return fail.call(ItemConstants.REASON_BAD_OP)
				var req_id: String = op.get("instance_id", "")
				if req_id != "" and _by_id.has(req_id):
					return fail.call(ItemConstants.REASON_DUPLICATE_ID)
				grant_plans.append({
					"item_id": item_id, "source": (src as Dictionary).duplicate(true),
					"overflow": eff, "size": def.size, "instance_id": req_id,
				})

			ItemConstants.OP_CONSUME, ItemConstants.OP_DISCARD:
				var tag: StringName = (
					ItemConstants.TAG_DISCARD if op_type == ItemConstants.OP_DISCARD
					else op.get("tag", ItemConstants.TAG_UNKNOWN)
				)
				if op_type == ItemConstants.OP_CONSUME and not ItemConstants.CALLER_TAGS.has(tag):
					return fail.call(ItemConstants.REASON_BAD_TAG)
				var ids = op.get("instance_ids", [])
				if not (ids is Array):
					return fail.call(ItemConstants.REASON_BAD_OP)
				for id in (ids as Array):
					var sid := String(id)
					if seen_remove.has(sid):
						return fail.call(ItemConstants.REASON_DUPLICATE_ID)
					var inst := _by_id.get(sid, null) as ItemInstance
					if inst == null:
						return fail.call(ItemConstants.REASON_MISSING_INSTANCE)
					if not inst.is_in_warehouse():
						return fail.call(ItemConstants.REASON_NOT_IN_WAREHOUSE)
					seen_remove[sid] = true
					remove_ids.append(sid)
					remove_tags.append(tag)

	# ── 阶段二：预演落位（按 ops 书写顺序消费容量：先创建先占地方）────────────────
	# 先算出销毁会腾出多少空间
	var projected_used := warehouse_used
	for id in remove_ids:
		projected_used -= _size_of(_by_id[id] as ItemInstance)

	var mailed_plan: Array[bool] = []
	for plan in grant_plans:
		var fits := projected_used + int(plan["size"]) <= warehouse_capacity
		if not fits and StringName(plan["overflow"]) == ItemConstants.OVERFLOW_REJECT:
			# 主动操作产出放不下 → 整个事务被拒（源实例因此不会被销毁）
			return fail.call(ItemConstants.REASON_NO_SPACE)
		if fits:
			projected_used += int(plan["size"])
		mailed_plan.append(not fits)

	# ── 阶段三：生效（到这里不会再失败）────────────────────────────────────────
	var consumed_out: Array[String] = []
	var discarded_out: Array[String] = []
	for i in remove_ids.size():
		var inst := _by_id[remove_ids[i]] as ItemInstance
		_detach(inst)
		total_consumed += 1
		if remove_tags[i] == ItemConstants.TAG_DISCARD:
			discarded_out.append(remove_ids[i])
		else:
			consumed_out.append(remove_ids[i])

	var granted_out: Array[String] = []
	var mailed_out: Array[String] = []
	for i in grant_plans.size():
		var plan: Dictionary = grant_plans[i]
		var kind: StringName = (plan["source"] as Dictionary).get("kind", &"")
		var inst := ItemInstance.new()
		inst.instance_id = String(plan["instance_id"]) if String(plan["instance_id"]) != "" else Uuid.v4()
		inst.item_id = StringName(plan["item_id"])
		inst.acquired_at = int(Time.get_unix_time_from_system())
		inst.source = plan["source"]
		inst.serial = _allocate_serial(inst.item_id, kind)
		inst.location = (
			ItemConstants.LOC_MAIL if mailed_plan[i] else ItemConstants.LOC_WAREHOUSE
		)
		_attach(inst)
		granted_out.append(inst.instance_id)
		if mailed_plan[i]:
			mailed_out.append(inst.instance_id)

	return {
		"ok": true, "reason": ItemConstants.REASON_OK,
		"consumed": consumed_out, "granted": granted_out,
		"discarded": discarded_out, "mailed": mailed_out,
	}


# ══════════════════════════════════════════════════════════════════════════════
#  只读查询
# ══════════════════════════════════════════════════════════════════════════════

## 派生 + 缓存（§4.4）。**默认只数仓库**；要数邮件必须**显式**传参——
## **不做隐式合并**（核心 §4.7 第 1 条）。
func count(
	category: StringName,
	quality: int,
	location: StringName = ItemConstants.LOC_WAREHOUSE
) -> int:
	var key := ItemDef.make_count_key(category, quality)
	if location == ItemConstants.LOC_WAREHOUSE:
		return int(count_index.get(key, 0))
	if location == ItemConstants.LOC_MAIL:
		return int(mail_count_index.get(key, 0))
	return 0


## { used, capacity, ratio }，供 08 直接画占比条（§5.9）。
## **04/05/06/08 一律只读它，不得自己求和。**
func warehouse_usage() -> Dictionary:
	var ratio := 0.0
	if warehouse_capacity > 0:
		ratio = float(warehouse_used) / float(warehouse_capacity)
	return {"used": warehouse_used, "capacity": warehouse_capacity, "ratio": ratio}


## 邮件位置的实例，按 (acquired_at 升序, instance_id 字典序)（§5.5 同序）。
func mail_instances() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for inst in instances:
		if inst.is_in_mail():
			out.append(inst)
	out.sort_custom(_less)
	return out


## 只读：仓库内合格实例的 id 列表，按 §5.5 排序。**不含邮件实例。**
func query(category: StringName, quality_floor: int) -> Array[String]:
	var picked: Array[ItemInstance] = []
	for inst in instances:
		if not inst.is_in_warehouse():
			continue
		var def := ItemCatalog.get_def(inst.item_id)
		if def == null:
			continue
		if def.category == category and def.quality >= quality_floor:
			picked.append(inst)
	picked.sort_custom(_less)
	var out: Array[String] = []
	for inst in picked:
		out.append(inst.instance_id)
	return out


## (category, quality) → item_id 的**反查**（唯一性由 §5.12 V1 在加载时强制）。
## 未注册组合返回 &""。**04/05/06 唯一被允许用来取 item_id 的途径。**
func resolve_item_id(category: StringName, quality: int) -> StringName:
	return ItemCatalog.resolve_item_id(category, quality)


## 供 03/07/08 只读消费的快照。
func snapshot() -> Array[ItemInstance]:
	return instances.duplicate()


## 「**当前仓库内无持有**」口径：返回候选集中仓库里没有任何实例的 item_id。
##
## ⚠️ **绝不能用于 01 的 ×1.5 加权**：若用仓库口径判"未拥有"，玩家可以把实例**压在邮件里**，
## 让同一物品永远被算作未拥有，从而**刷到永久加成**（裁决 11 已验证）。
## ×1.5 **只读 10 的收藏口径** `collected` / `is_collected`。两口径合法但名字必须可分。
##
## 候选集由 01 经 `series_item_provider` 注入（SeriesDef 归 01，本系统不拥有它）。
func find_unstocked_items(series_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if not series_item_provider.is_valid():
		push_warning("ItemService.find_unstocked_items: series_item_provider 未注入（应由 01 设置）")
		return out
	var candidates: Array = series_item_provider.call(series_id)
	if not (candidates is Array):
		return out
	for c in (candidates as Array):
		var item_id := StringName(c)
		var def := ItemCatalog.get_def(item_id)
		if def == null:
			continue
		if count(def.category, def.quality, ItemConstants.LOC_WAREHOUSE) == 0:
			out.append(item_id)  # 含隐藏物品；是否纳入 ×1.5 由 01 按 C3 裁决
	return out


# ══════════════════════════════════════════════════════════════════════════════
#  claim：领取（§5.10）
# ══════════════════════════════════════════════════════════════════════════════

## 领取 = **只改 location**：不创建实例、不改 instance_id / serial / source / acquired_at、
## 不重跑幂等判定、不推进 serial_counters、不动两个计数器。
##
## **空间不足时是"部分成功"**（按 §5.5 顺序逐件判定、尽可能多领），不是整体拒绝：
## 邮件里的东西**已经是玩家的**（产出瞬间就已创建并拿到 UUID 与 serial），领取只是搬家；
## 整体拒绝等于"因为没地方放，所以什么都不给你"，把空间问题变成惩罚。
##
## 代价：UI 必须回报"已领取 M / 还剩 K 件"，`claim_all()` **不得**表述为"一键领完"。
func claim(instance_ids: Array[String]) -> Dictionary:
	if read_only:
		return {"ok": false, "claimed": [] as Array[String], "remaining": [] as Array[String],
			"reason": ItemConstants.REASON_BAD_OP}

	var seen: Dictionary = {}
	var candidates: Array[ItemInstance] = []
	var already_claimed: Array[String] = []
	for id in instance_ids:
		if seen.has(id):
			return {"ok": false, "claimed": [] as Array[String], "remaining": [] as Array[String],
				"reason": ItemConstants.REASON_DUPLICATE_ID}
		seen[id] = true
		var inst := _by_id.get(id, null) as ItemInstance
		if inst == null:
			return {"ok": false, "claimed": [] as Array[String], "remaining": [] as Array[String],
				"reason": ItemConstants.REASON_MISSING_INSTANCE}
		if inst.is_in_mail():
			candidates.append(inst)
		else:
			# 已在仓库 → no-op，但计入 claimed：领取是幂等的（只把 location 写成同一个值）
			already_claimed.append(inst.instance_id)

	candidates.sort_custom(_less)

	var claimed: Array[String] = already_claimed.duplicate()
	var remaining: Array[String] = []
	for inst in candidates:
		if _fits(_size_of(inst)):
			_move(inst, ItemConstants.LOC_WAREHOUSE)
			claimed.append(inst.instance_id)
		else:
			remaining.append(inst.instance_id)

	var reason := ItemConstants.REASON_OK
	if claimed.is_empty():
		reason = ItemConstants.REASON_NO_SPACE  # 一件都装不下
	return {
		"ok": claimed.size() == instance_ids.size(),
		"claimed": claimed, "remaining": remaining, "reason": reason,
	}


## 一键领取：对全部邮件实例执行同一过程，**永不失败**。
func claim_all() -> Dictionary:
	var ids: Array[String] = []
	for inst in mail_instances():
		ids.append(inst.instance_id)
	return claim(ids)


# ══════════════════════════════════════════════════════════════════════════════
#  自愈 / 对账 / 存档
# ══════════════════════════════════════════════════════════════════════════════

## 全量重算三个派生值（正常路径不调用，供对账与调试）。
## 与增量维护的结果必须**逐项相等**（§10.2 的一致性红线）。
func rebuild_count_index() -> Dictionary:
	count_index.clear()
	mail_count_index.clear()
	warehouse_used = 0
	for inst in instances:
		_index_add(_key_of(inst), inst.location)
		if inst.is_in_warehouse():
			warehouse_used += _size_of(inst)
	return {"count_index": count_index.duplicate(), "warehouse_used": warehouse_used}


## 守恒式自检（§5.7 R-M10）：`instances.size() == total_granted − total_consumed`
## **按"全部实例"、与 location 无关**——把带位置过滤的 count() 写进守恒式即是 bug。
func check_conservation() -> bool:
	return instances.size() == total_granted - total_consumed


## 载入后重建全部索引（count_index / warehouse_used / _by_id 都不入档）。
func rebuild_all() -> void:
	_by_id.clear()
	for inst in instances:
		_by_id[inst.instance_id] = inst
	rebuild_count_index()


## 存档形态（§4.6）。**文件与格式归 10**，本系统只提供这个字典。
## 键序固定：往返字节级稳定依赖它。
func to_save_dict() -> Dictionary:
	var arr: Array = []
	for inst in instances:
		arr.append(inst.to_dict())
	return {
		"instances": arr,
		"warehouse_capacity": warehouse_capacity,
		"serial_counters": serial_counters.duplicate(),
		"total_granted": total_granted,
		"total_consumed": total_consumed,
	}


func from_save_dict(d: Dictionary) -> void:
	instances.clear()
	var arr = d.get("instances", [])
	if arr is Array:
		for e in (arr as Array):
			if e is Dictionary:
				instances.append(ItemInstance.from_dict(e))
	warehouse_capacity = int(d.get("warehouse_capacity", 1000))
	var sc = d.get("serial_counters", {})
	serial_counters = {}
	if sc is Dictionary:
		# JSON 会把计数器的值解析成 float，必须还原成 int（否则往返不稳定，§4.6）
		for k in (sc as Dictionary).keys():
			serial_counters[k] = ItemInstance._normalize_dynamic((sc as Dictionary)[k])
	total_granted = int(d.get("total_granted", 0))
	total_consumed = int(d.get("total_consumed", 0))
	rebuild_all()


## 配置校验器（§5.12 / §5.9）。与 ItemCatalog.validate() 合并使用。
func validate_config() -> Dictionary:
	var errors: Array[String] = []
	if warehouse_capacity < 1:
		errors.append(
			"warehouse_capacity = %d，必须 >= 1——容量 0 会让一切被动产出进邮件、"
			% warehouse_capacity
			+ "一切主动操作被拒，游戏当场不可玩"
		)
	return {"ok": errors.is_empty(), "errors": errors}


func reset() -> void:
	instances.clear()
	_by_id.clear()
	count_index.clear()
	mail_count_index.clear()
	warehouse_used = 0
	serial_counters.clear()
	total_granted = 0
	total_consumed = 0

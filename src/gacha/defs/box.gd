## 盲盒（01-gacha.md §4.3）。
##
## ★ **两个并列数据**：`item_pool`（该盒的池子，生成数据的凭证）+ `modules`（**定长**模块数组）。
##   池子的"当前状态"是二者的函数（`PoolState`）——**派生值、不入档、载入时逐盒重建**。
##   **模块不折进池子**：不得在 `PoolState` 或 `item_pool` 里再放一份模块字段。
##
## ★★ **v0.61（用户裁决）：套系（`SeriesDef`）已整体删除**——盒子自带全部"出厂属性"：
##   `quality`（品质 1–4）、`item_pool.socket_count`（位子）、`uses_remaining`（寿命预算）、
##   `gem_cost`（开盒原石价）。**池子的物品就是 `item_pool.base_items`**，逐盒落盘。
##   从前这些字段挂在套系上（一个套系 → 多个盒子共享一份模板），现在**每个盒子各存一份**：
##   改默认曲线（`ItemConstants.BOX_*`）**不影响已经存在的盒子**。
##
## ★ `box_id` 是**身份、不是输入**：不参与权重与抽样；**稳定性来自持久化**，不来自派生。
##   `IUuid.v4()` 生成（`String`，与 `instance_id` 同源同类型，**无转换点**）。
##
## ★ `modules` 是**定长**数组（长度恒 == `item_pool.socket_count`，**空位为空项**）；
##   **槽位号 = 数组下标**（**不另设 `slot` 字段**）。
@tool
class_name Box
extends Resource

@export var box_id: String = ""                          # IUuid.v4()；与 instance_id 同类型、无转换
## ★ v0.61：**盒子自带的品质**（1–4）。设备等级门控、卖价表、默认位子/寿命都看它。
@export var quality: int = 1
@export var item_pool: ItemPool                          # 【生成数据的凭证】——roll() 消费它
@export var modules: Array[Module] = []                  # 定长，长度恒 == item_pool.socket_count，空位为空项
@export var source: StringName = &""                     # 来源任务 id（归因，见 03）
@export var acquired_tick: int = 0
## **使用次数 = 这个盒子的总寿命预算**（每盒可变、**入档**）。
##
## **两个消耗点共用这一个计数器**（各扣 1）：**装模块**（`PoolBuff.apply_module()`）与
## **兑现**（`GachaService.redeem()`）；**失败一律不扣**。
## **归零即摧毁**：盒子连同 `modules` 从囤积清单消失（`GameState.spend_use()`）。
## 初始值按**盒子品质**给默认（`ItemConstants.box_uses()`：10/15/20/25）。
@export var uses_remaining: int = 0                      # 0 = 用尽 ⇒ 盒子被摧毁

## ★ v0.26（用户裁决）：**盲盒同样是"持有物"的一类**——它和物品一样有**位置**与**体积**。
## · `location ∈ {warehouse, mail}`：仓库里的盒子可以配置 / 兑现；**邮件里的不可用**；
## · `size`：**每盒固定 1 单位**，**与物品记进同一份容量账**（容量仍只有一个判定点）；
## · 盒子进仓库/邮件的判定发生在 `GachaService.grant_box()`（问 02 的 `place_box()`）。
@export var location: StringName = &"warehouse"           # warehouse / mail
@export var size: int = 1                                # 每盒固定 1 单位（记进同一份容量账）
## ★ v0.61：**这个盒子的开盒原石成本**（每次开盒扣多少原石）——每盒自己存。
##
## · 牌库 / 任务发的盒子 = 按品质默认值（`ItemConstants.box_gem_cost()`）；
## · **生成的盒子** = 生成那一刻按期望算好并定死（`⌈M̄_gold × 品质倍率 ÷ 10⌉`，10 金币 = 1 原石），
##   之后编辑池子 / 装模块**不改价**（否则"先改后开"可以套利）；
## · **扣费以它为准**：`DeviceService.open_cost()` 用它乘设备折扣。
@export var gem_cost: int = 30


## 是否已用尽（用尽 ⇒ 盒子离开囤积清单，`modules` 随之消失）。
func is_exhausted() -> bool:
	return uses_remaining <= 0


## 消耗一次使用。返回是否成功——**已用尽则拒绝，绝不产生负值**。
func consume_one_use() -> bool:
	if uses_remaining <= 0:
		return false
	uses_remaining -= 1
	return true


## 该盒的位数（冻结在 item_pool 上；C4：同一池内恒定、运行时不可变）。
func socket_count() -> int:
	return item_pool.socket_count if item_pool != null else 0


## 已占用位数（非空项数）。→ C4 真正要守的是"已占用位数 ≤ socket_count"。
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


# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.61：造盒（套系删除后的唯一构造入口）
# ══════════════════════════════════════════════════════════════════════════════

## 造一个盒子。`socket_count` / `uses` / `gem_cost` 传 `-1` ⇒ 取该品质的默认值
## （`ItemConstants.box_*`）。**物品列表的顺序 = 产出顺序**，调用方给什么就是什么。
##
## 返回 `null` 表示"内容不足"（`items` 为空）——由调用方报错，不静默造空池。
static func make(
	p_quality: int,
	items: Array[ItemDef],
	socket_count: int = -1,
	uses: int = -1,
	gem_cost: int = -1,
	source: StringName = &""
) -> Box:
	var q := clampi(p_quality, 1, 4)
	var b := Box.new()
	b.box_id = IUuid.v4()
	b.quality = q
	var sc := socket_count if socket_count >= 0 else ItemConstants.box_socket_count(q)
	b.item_pool = PoolService.build_pool(b.box_id, items, sc)
	if b.item_pool == null:
		return null
	b.modules = PoolService.empty_slots(b.item_pool.socket_count)
	b.uses_remaining = uses if uses >= 0 else ItemConstants.box_uses(q)
	b.gem_cost = gem_cost if gem_cost >= 0 else ItemConstants.box_gem_cost(q)
	b.size = 1
	b.source = source
	b.acquired_tick = int(Time.get_ticks_msec())
	return b


# ══════════════════════════════════════════════════════════════════════════════
#  落盘 / 载入
# ══════════════════════════════════════════════════════════════════════════════

## 盒子的落盘形状。键序固定（往返字节级稳定的前提）。
##
## · `quality` / `gem_cost` / `uses_remaining` **入档**——它们是这个盒子自己的属性；
## · `item_pool` 落 `box_id` / `regular_count` / `socket_count` / `revision` / 三态 /
##   **物品列表**（v0.61：没有套系可推导 ⇒ **永远整份落盘**）；
## · `modules` 落**稀疏序列**（空位不写）。
func to_dict() -> Dictionary:
	var pool_subset := {}
	if item_pool != null:
		pool_subset = {
			"box_id": item_pool.box_id,
			"regular_count": item_pool.regular_count,
			"socket_count": item_pool.socket_count,
			"revision": item_pool.revision,
			"item_states": item_pool.item_states.duplicate(),
			"pool_item_ids": item_pool.item_ids(),
		}
	return {
		"box_id": box_id,
		"quality": quality,
		"gem_cost": gem_cost,
		"source": String(source),
		"acquired_tick": acquired_tick,
		"uses_remaining": uses_remaining,
		"location": String(location),
		"size": size,
		"item_pool": pool_subset,
		"modules": modules_to_sparse_array(),
	}


## 从落盘形状还原一个盒子。
##
## ★ v0.61：**不再有套系**——池子按 `pool_item_ids` 逐件重建。没有该键 ⇒ **拒绝载入**
##   （旧套系档已无法解析，静默造空池比报错更糟）。
## ★ `uses_remaining`：键存在 ⇒ 一律用档里的值（含 `0`，那是"已用尽"的合法状态）；
##   缺键 ⇒ 用调用方给的 `uses_when_missing`（补齐策略归载入层）。
static func from_dict(d: Dictionary, uses_when_missing: int = 0) -> Box:
	var b := Box.new()
	b.box_id = String(d.get("box_id", ""))
	b.quality = int(d.get("quality", 1))
	b.gem_cost = int(d.get("gem_cost", ItemConstants.box_gem_cost(b.quality)))
	var subset = d.get("item_pool", {})
	var socket_count := ItemConstants.box_socket_count(b.quality)
	var ids: Array[StringName] = []
	if subset is Dictionary:
		var pd: Dictionary = subset
		socket_count = int(pd.get("socket_count", socket_count))
		var raw_ids = pd.get("pool_item_ids", [])
		if raw_ids is Array:
			for raw in (raw_ids as Array):
				ids.append(StringName(raw))
	if ids.is_empty():
		push_error("Box.from_dict: 盒子 `%s` 没有 pool_item_ids，拒绝载入（不静默造空池）" % b.box_id)
		return null
	var items: Array[ItemDef] = []
	for id in ids:
		var def := ItemCatalog.get_def(id)
		if def == null:
			push_warning("Box.from_dict: 池内物品 `%s` 已不在内容表里，跳过（不静默替换）" % id)
			continue
		items.append(def)
	if items.is_empty():
		push_error("Box.from_dict: 盒子 `%s` 的物品全部失效，拒绝载入" % b.box_id)
		return null
	b.item_pool = PoolService.build_pool(b.box_id, items, socket_count)
	if b.item_pool == null:
		return null
	if subset is Dictionary:
		var pd2: Dictionary = subset
		b.item_pool.revision = int(pd2.get("revision", 0))
		var states = pd2.get("item_states", {})
		if states is Dictionary:
			for k in (states as Dictionary).keys():
				var st := int((states as Dictionary)[k])
				if st == ItemPool.ItemState.HIDDEN or st == ItemPool.ItemState.DISABLED:
					b.item_pool.item_states[String(k)] = st
	b.modules = modules_from_sparse_array(d.get("modules", []), b.item_pool.socket_count)
	b.source = StringName(d.get("source", ""))
	b.acquired_tick = int(d.get("acquired_tick", 0))
	b.uses_remaining = int(d["uses_remaining"]) if d.has("uses_remaining") else uses_when_missing
	b.location = StringName(d.get("location", String(ItemConstants.LOC_WAREHOUSE)))
	b.size = int(d.get("size", 1))
	return b

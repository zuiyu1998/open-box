## 盲盒（01-gacha.md §4.3）。
##
## ★ **两个并列数据**：`item_pool`（该盒的池子，生成数据的凭证）+ `modules`（**定长**模块数组）。
##   池子的"当前状态"是二者的函数（`PoolState`）——**派生值、不入档、载入时逐盒重建**。
##   **模块不折进池子**：不得在 `PoolState` 或 `item_pool` 里再放一份模块字段
##   （核心已否决 `PoolState.socketed` 这种形状）。
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
@export var series_id: StringName = &""
@export var item_pool: ItemPool                          # 【生成数据的凭证】——roll() 消费它
@export var modules: Array[Module] = []                  # 定长，长度恒 == item_pool.socket_count，空位为空项
@export var source: StringName = &""                     # 来源任务 id（归因，见 03）
@export var acquired_tick: int = 0
## **v0.14：使用次数 = 这个盒子的总寿命预算**（每盒可变、**入档**）。
##
## **两个消耗点共用这一个计数器**（各扣 1）：
##   · **装模块**（`PoolBuff.apply_module()` 成功镶嵌时）；
##   · **兑现**（`GachaService.redeem()` 成功兑现时）。
## **失败一律不扣**（校验失败不得消耗次数）。
##
## **归零即摧毁**：`uses_remaining == 0` ⇒ 盒子连同它的 `modules` 从囤积清单消失
## （`GameState.spend_use()`）。**不存在"用尽才消耗"的缓冲**——装模块把盒子扣到 0 时
## 照样摧毁，**哪怕它一次都没兑现过**（这是合法路径，不做防御性拦截）。
##
## 初始值由套系品质给出（`SeriesDef.uses_per_box` 与 `SeriesDef.expected_initial_uses()`：
## 品质 1/2/3/4 → **10/15/20/25**；数值裁决：寿命预算**远大于**镶嵌位数 2/3/4/5）。
## 摧毁前**可以继续编辑池子**（镶 / 拆模块），这些编辑只影响**之后**的那几次抽取。
##
## ★ **D17 提醒**：预算 = "每次抽取摊模块成本"的分母来源（`d = 预算 − 装模块数`，现为 **8–20**）⇒
##   改这条曲线等于改 `C/d`，**必须同步重标 D17**（P7 唯一的跨池锚点）。
@export var uses_remaining: int = 0                      # 0 = 用尽 ⇒ 盒子被摧毁

## ★ v0.26（用户裁决）：**盲盒同样是"持有物"的一类**——它和物品一样有**位置**与**体积**。
##
## · `location ∈ {warehouse, mail}`（与 `ItemInstance.location` **同一取值域**，取自
##   `ItemConstants.LOC_WAREHOUSE / LOC_MAIL`）：**仓库里的盒子可以配置 / 兑现；
##   邮件里的盒子不可用**（与物品同一纪律：邮件不是"可用持有"）。
## · `size`：**每盒固定 1 单位**（用户裁决），并且**与物品的 `size` 记进同一份容量账**
##   （`ItemService.warehouse_usage()` 同时算物品与盒子）——**容量仍然只有一个判定点**。
##   后果（必须正视）：**囤盒子本身会占地方**，仓库满时新盒子进邮件（被动产出永不丢失）。
## · 盒子进仓库/邮件的判定发生在 `GachaService.grant_box()`（问 02 的 `place_box()`）；
##   **开盒不释放空间**（盒子还在），**只有"次数归零被摧毁"才释放那 1 单位**。
@export var location: StringName = &"warehouse"           # warehouse / mail
@export var size: int = 1                                # 每盒固定 1 单位（记进同一份容量账）
## ★ v0.55/v0.56（用户裁决）：**这个盒子的开盒原石成本**（每次开盒扣多少原石）。
##
## · 单位**原石**（不是金币）；**`0` = 用套系的 `SeriesDef.gem_cost`**（牌库发的盒子都是 0）；
## · **在生成那一刻算好并定死**（`GachaService.generate_box()`：`⌈M̄_gold × 品质倍率 ÷ 10⌉`，
##   10 金币 = 1 原石）；之后玩家编辑池子 / 装模块把期望拉高了，**开盒价不变**
##   —— 否则"先改后开"可以套利；
## · **开盒扣费以它为准**：`DeviceService.open_cost()` 优先用它，为 0 才回退套系价，
##   折扣（设备等级）仍按 04 的曲线作用在它上面。
@export var open_gem_cost: int = 0


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


## 已占用位数（非空项数）。→ C4 真正要守的是"已占用位数 ≤ socket_count"
## （"长度恒等于 socket_count"是结构上恒真的，见 01 §10.1 T6/C4 与 §5.2 第 7 步）。
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
## 存档格式归 10（01 §4.3 / 10 的示例）；这里只提供形状，**不改动实例本身**。
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
## **长度由调用方给定**（= `item_pool.socket_count`），不由序列长度推导——
## 否则"定长"会随"镶了几个"变化，C4 的第①条断言当场失效。
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
#  落盘 / 载入（v0.14：`uses_remaining` 入档）
# ══════════════════════════════════════════════════════════════════════════════

## 盒子的落盘形状。键序固定（往返字节级稳定的前提）。
##
## · `uses_remaining` **入档**——它是玩家进度（"这个盒子还能开几次"），不落盘就等于读档后白送次数；
## · `item_pool` 只落**五项子集**（`box_id` / `series_id` / `regular_count` / `socket_count` /
##   `revision`）——基础池是模板的东西，载入时由 `series_id` 解析（01 §4.3 的裁决 ≤ 核心 §4.1.2）；
## · `modules` 落**稀疏序列**（空位不写）。
##
## `[补充]` **信封（`save.json` 的结构、迁移版本号）归 10**；本方法只提供**单个盒子**的形状，
## 与 01 §4.3 / 10 的示例逐字段一致（`uses_remaining` 是本版新增的那一项）。
func to_dict() -> Dictionary:
	var pool_subset := {}
	if item_pool != null:
		pool_subset = {
			"box_id": item_pool.box_id,
			"series_id": String(item_pool.series_id),
			"regular_count": item_pool.regular_count,
			"socket_count": item_pool.socket_count,
			"revision": item_pool.revision,
			# ★ v0.45：追加物品与三态必须落盘（否则读档丢掉玩家的编辑）
			"extra_item_ids": item_pool.extra_item_ids.duplicate(),
			"item_states": item_pool.item_states.duplicate(),
			# ★ v0.55：**生成的盲盒**池子是随机凑的，必须整份落盘（否则读档退回套系原样）
			"pool_item_ids": _pool_ids_for_save(),
		}
	return {
		"box_id": box_id,
		"series_id": String(series_id),
		"source": String(source),
		"acquired_tick": acquired_tick,
		"uses_remaining": uses_remaining,
		"location": String(location),
		"size": size,
		"open_gem_cost": open_gem_cost,
		"item_pool": pool_subset,
		"modules": modules_to_sparse_array(),
	}


## 从落盘形状还原一个盒子。
##
## **套系必须在注册表里**（`GachaCatalog`）——基础池不逐盒落盘，只能由 `series_id` 解析；
## 解析不到 ⇒ 返回 `null` 并 `push_error`，**禁止静默降级成基础池**
## （那会静默吃掉玩家投入的模块成本，§10.1 T24 ④ 的同一纪律）。
##
## ★ `uses_remaining` 的取值规则（v0.14 裁决）：
##   · **键存在 ⇒ 一律用档里的值**（哪怕是 `0`：那是"这个盒子已经用尽"，是**合法状态**，
##     **不许"好心补满"**）；
##   · **键缺失 ⇒ 用调用方给的 `uses_when_missing`**。**补齐策略不在这里**——
##     补齐需要"该盒所属套系的品质"，那是**载入层**的事（`GameState.box_from_dict()`，
##     它拿得到 `GachaCatalog`）；**`Box` 不承担策略**，本函数只接受一个值。
static func from_dict(d: Dictionary, uses_when_missing: int = 0) -> Box:
	var sid := StringName(d.get("series_id", ""))
	var series := GachaCatalog.get_series(sid)
	if series == null:
		push_error("Box.from_dict: 未知 series_id `%s`，拒绝载入（不静默降级）" % sid)
		return null
	var b := Box.new()
	b.box_id = String(d.get("box_id", ""))
	b.series_id = sid
	b.item_pool = PoolService.init_pool(null, b.box_id, sid)
	if b.item_pool == null:
		return null
	var subset = d.get("item_pool", {})
	if subset is Dictionary:
		var pd: Dictionary = subset
		b.item_pool.regular_count = int(pd.get("regular_count", b.item_pool.regular_count))
		b.item_pool.socket_count = int(pd.get("socket_count", b.item_pool.socket_count))
		b.item_pool.revision = int(pd.get("revision", 0))
		# ★ v0.55：**随机池优先**——生成的盲盒池子不是套系原样，整份列表在档里。
		#   先按它重建 base_items，再走下面的追加 / 三态（三态按 item_id 生效，顺序无关）。
		var full_ids = pd.get("pool_item_ids", [])
		var pool_rebuilt := false
		if full_ids is Array and not (full_ids as Array).is_empty():
			var rebuilt: Array[ItemDef] = []
			for raw in (full_ids as Array):
				var fdef := ItemCatalog.get_def(StringName(raw))
				if fdef == null:
					push_warning("Box.from_dict: 池内物品 `%s` 已不在内容表里，跳过（不静默替换）" % raw)
					continue
				rebuilt.append(fdef)
			if not rebuilt.is_empty():
				b.item_pool.base_items = rebuilt
				b.item_pool.regular_count = rebuilt.size()
				pool_rebuilt = true
		# ★ v0.45：池子成员不再是"完全由 series_id 推出"——**追加的物品必须读回来**，
		#   否则玩家的编辑会在读档时静默丢失（比"少了三态"更严重）。
		var extras = pd.get("extra_item_ids", [])
		if extras is Array:
			for raw in (extras as Array):
				var def := ItemCatalog.get_def(StringName(raw))
				if def == null:
					push_warning("Box.from_dict: 追加物品 `%s` 已不在内容表里，跳过（不静默替换）" % raw)
					continue
				# ★ v0.55：**`pool_item_ids` 已经含它了**（整份列表覆盖了"套系 + 追加"），
				#   这时只需把 id 记回 `extra_item_ids` 保持身份，**不要再 append 一次**
				#   （否则每次存读都会多出一件：实测 regular_count 9 → 10 → 11…）。
				if not pool_rebuilt:
					b.item_pool.base_items.append(def)
					b.item_pool.regular_count = maxi(b.item_pool.regular_count, b.item_pool.base_items.size())
				if not b.item_pool.extra_item_ids.has(def.item_id):
					b.item_pool.extra_item_ids.append(def.item_id)
		# ★ v0.45：三态（缺键 = 全部显示）
		var states = pd.get("item_states", {})
		if states is Dictionary:
			for k in (states as Dictionary).keys():
				var st := int((states as Dictionary)[k])
				if st == ItemPool.ItemState.HIDDEN or st == ItemPool.ItemState.DISABLED:
					b.item_pool.item_states[String(k)] = st
	b.modules = modules_from_sparse_array(d.get("modules", []), b.item_pool.socket_count)
	b.source = StringName(d.get("source", ""))
	b.acquired_tick = int(d.get("acquired_tick", 0))
	# ★ 键存在 ⇒ 用档里的值（含 0，那是"已用尽"的合法状态）；缺键 ⇒ 用调用方给的补齐值
	b.uses_remaining = int(d["uses_remaining"]) if d.has("uses_remaining") else uses_when_missing
	# ★ v0.26：位置与体积。**旧档没有这两个键 ⇒ 一律回填 `warehouse` / 1**
	#   （旧档里的盒子在旧口径下根本不在仓库/邮件里，回填"仓库"是唯一不丢东西的选择）。
	b.open_gem_cost = int(d.get("open_gem_cost", 0))   # ★ v0.56：开盒原石价（0 = 用套系价）
	b.location = StringName(d.get("location", String(ItemConstants.LOC_WAREHOUSE)))
	b.size = int(d.get("size", 1))
	return b


## ★ v0.55：**只有当池子不是套系原样时**才把整份物品列表写进档（省体积、旧档契约不变）。
## 判据：`base_items` 的 id 序列与 `series` 的 id 序列逐项相同 ⇒ 不写（可继续由 series 推出）。
func _pool_ids_for_save() -> Array[StringName]:
	var out: Array[StringName] = []
	if item_pool == null:
		return out
	var series := GachaCatalog.get_series(series_id)
	if series != null and item_pool.item_ids() == series.item_ids():
		return out                                  # 与套系一致 ⇒ 不落盘
	return item_pool.item_ids()
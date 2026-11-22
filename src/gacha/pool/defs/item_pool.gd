## 物品池（05-module-pool.md §4；v0.12 起代码在 `src/gacha/pool/defs/`）。`Box.item_pool` 是这个类型的一份实例。
##
## ★ 本类只回答「**基础分布是什么**」——它由每个物品的 `ItemDef.rarity` 归一化而来：
##     p_i = rarity_i / Σ rarity        （Σ 恒为 1.0，红线 C1 零和）
##
## ★ **v0.13：隐藏款已整体删除。** 因此：
##   - 全部物品**共分 100%**（此前常规物品只分 98%、隐藏物品固定 2%）；
##   - 红线 **C3（隐藏物品概率恒 2%、免疫一切池子编辑）随之作废**——它唯一的保护对象不存在了。
##
## ★ `rarity` 是**权重**而不是「稀有等级」：**数值越大越常见**（见 `item_def.gd`）。
##   所以「越稀有」的物品要把 `rarity` 写得越小。
##
## ★ 这里**没有**「未拥有物品 ×1.5」：那一步依赖**收藏状态**（`collected`，归 10），
##   只能在**求值时**做，归 07 的 `EvalService`（见 07-economy-rho.md §5.1 的序列）。
##   本类只给"基础分布"，求值链是：`ItemPool`（本类）→ 07 加权 / 归一化 → `probs`。
##
## ★ 本类**不存** `base_weights`——它是**派生值**。存下来就是第二个事实来源，
##   与「派生状态不入档」是同一条纪律（核心 §4.1.2 / §16.6）。
@tool
class_name ItemPool
extends Resource

## 全部可产出结果的合计：10000 bp == 100%（红线 C1：零和）。
## v0.13 起这就是**全部物品**的合计——不再有"常规 9800 + 隐藏 200"的切分。
const TOTAL_BP: int = 10000

## ★ v0.45：**池内每件物品的三态**（用户裁决）。它是**可编辑字段**（不走模块），
## 语义逐条钉死：
##   · **`SHOWN`（显示，默认）**：参与抽取，且在池子面板列出来；
##   · **`HIDDEN`（隐藏）**：**仍参与抽取**，只是**不在面板列出**（用户明确选了这一支——
##     代价是玩家看不到它的存在与权重，与 P1"一切可查可算"有张力，**已登记为已知取舍**）；
##   · **`DISABLED`（禁用）**：**不参与抽取**，权重在**其余物品间重新归一**，
##     **不产生 void**（与模块 BAN 的 40% 蒸发是两套语义，不得混用）。
enum ItemState { SHOWN = 0, HIDDEN = 1, DISABLED = 2 }

@export var box_id: String = ""                 # 稳定身份（归 01；`IUuid.v4()`，无转换点）
@export var series_id: StringName = &""         # 基础池的来源（引用 01 的 SeriesDef）
@export var regular_count: int = 0              # 冻结元数据：物品数（C6 的依据；★ v0.45：追加物品时同步 +1）
@export var socket_count: int = 0               # 冻结元数据：镶嵌位数（C4）
@export var revision: int = 0                   # 每次写入 +1
@export var base_items: Array[ItemDef] = []     # 该池的全部可产出物品（v0.13：不再有隐藏款）
## ★ v0.45：`item_id(String) -> ItemState(int)`。**缺键 = `SHOWN`**（不写全量，省档）；
## 只有被改成 HIDDEN / DISABLED 的物品才有条目。
@export var item_states: Dictionary = {}
## ★ v0.45：**超出套系、被玩家追加进池子**的物品 id（落盘用；运行时它们的 `ItemDef`
## 由 `ItemCatalog` 解析后并入 `base_items`）。空数组 = 池子就是套系原样。
@export var extra_item_ids: Array[StringName] = []


# ══════════════════════════════════════════════════════════════════════════════
#  产出顺序（权威定义）
# ══════════════════════════════════════════════════════════════════════════════

## 产出顺序 = **按 `base_items` 的顺序**（v0.13：不再有"隐藏物品排在最后"）。
## `compute_weights_bp()` 与 `compute_probabilities()` 都按这个顺序对齐，
## 所以调用方用小标号对位时必须以本方法为准，不要自己拼顺序。
func item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for d in base_items:
		if d != null:
			out.append(d.item_id)
	return out


## 归一化的分母：全部物品的 `rarity` 之和。
func total_rarity() -> int:
	var t := 0
	for d in base_items:
		if d != null:
			t += maxi(d.rarity, 0)
	return t


# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.45：物品三态（可编辑字段）
# ══════════════════════════════════════════════════════════════════════════════

## 该物品当前状态。**不在池中 ⇒ 返回 `SHOWN`**（调用方要先用 `has_item()` 判断在不在）。
func state_of(item_id: StringName) -> int:
	return int(item_states.get(String(item_id), ItemState.SHOWN))


func has_item(item_id: StringName) -> bool:
	for d in base_items:
		if d != null and d.item_id == item_id:
			return true
	return false


## 改状态。**不在池中 / 状态越界 ⇒ false、不改任何东西**（把关留给调用方统一报码）。
## 改回 `SHOWN` 时**删键**（保持"缺键 = 显示"的稀疏约定，存档不膨胀）。
func set_state(item_id: StringName, new_state: int) -> bool:
	if not has_item(item_id):
		return false
	if new_state < ItemState.SHOWN or new_state > ItemState.DISABLED:
		return false
	if new_state == ItemState.SHOWN:
		item_states.erase(String(item_id))
	else:
		item_states[String(item_id)] = new_state
	return true


## **参与抽取**的物品（= 非禁用）。顺序与 `base_items` 一致。
func enabled_items() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for d in base_items:
		if d != null and state_of(d.item_id) != ItemState.DISABLED:
			out.append(d)
	return out


func ids_with_state(s: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for d in base_items:
		if d != null and state_of(d.item_id) == s:
			out.append(d.item_id)
	return out


func hidden_ids() -> Array[StringName]:
	return ids_with_state(ItemState.HIDDEN)


func disabled_ids() -> Array[StringName]:
	return ids_with_state(ItemState.DISABLED)


## **参与抽取**的物品数（C6 的下限判的就是它，不是 `base_items.size()`）。
func enabled_count() -> int:
	return enabled_items().size()


## 追加一件物品进池子（`ItemDef` 必须已注册；`item_id` 不得已在池中）。
## **不动 `item_states`**（新物品默认 `SHOWN`）；`regular_count` 同步 +1，让 C6 / V5 的口径跟着池子走。
func add_item(def: ItemDef) -> bool:
	if def == null or def.item_id == &"":
		return false
	if has_item(def.item_id):
		return false
	base_items.append(def)
	if not extra_item_ids.has(def.item_id):
		extra_item_ids.append(def.item_id)
	regular_count += 1
	return true


## 池子是否可用。返回**空数组 = 可用**；否则每项是一条原因（不抛异常，便于测试与校验汇总）。
##
## ★ v0.45：判的是**参与抽取**的那部分——被禁用（`DISABLED`）的物品**不参与**，
## 因此"可产出数"用 `enabled_count()`，C6 的**≥ 3** 也按它判（禁用把池子压到 2 件 ⇒ 非法）。
func validate() -> Array[String]:
	var problems: Array[String] = []
	if base_items.is_empty():
		problems.append("no_items：池子至少要有一个物品（C6 要求可产出 ≥ 3 个）")
	var enabled := enabled_items()
	if enabled.is_empty():
		problems.append("all_disabled：所有物品都被禁用，没有任何可产出结果")
	var enabled_rarity := 0
	for d in enabled:
		enabled_rarity += maxi(d.rarity, 0)
	if enabled_rarity <= 0:
		problems.append("zero_rarity：可产出物品的 rarity 合计为 0，无法归一化")
	for d in enabled:
		if d.rarity < 1:
			problems.append("bad_rarity：%s 的 rarity < 1（0 表示永不产出，是配置错误）" % d.item_id)
	return problems


# ══════════════════════════════════════════════════════════════════════════════
#  ★ 核心方法：计算各个物品的产生概率
# ══════════════════════════════════════════════════════════════════════════════

## **计算各个物品的产生概率**，返回 `{ item_id: float }`，Σ == 1.0（红线 C1）。
##
## `p_i = rarity_i / Σ rarity`——全部物品共分 100%（v0.13，隐藏款已删除）。
##
## ★ 浮点视图**由规范整数形态派生**（`bp / 10000.0`），不另算一遍：
##   否则整数形态与浮点形态会在舍入上分家，成为两个事实来源。
## 池子不可用时返回**空字典**（原因见 `validate()`），不返回"看起来像概率"的假数据。
func compute_probabilities() -> Dictionary:
	var bp := compute_weights_bp()
	var out := {}
	if bp.is_empty():
		return out
	var ids := item_ids()
	for i in bp.size():
		out[ids[i]] = float(bp[i]) / float(TOTAL_BP)
	return out


## 单个物品的产生概率；不在池中的 id 返回 `0.0`。
func probability_of(item_id: StringName) -> float:
	return float(compute_probabilities().get(item_id, 0.0))


## 规范整数形态：**万分比**，Σ 精确等于 `TOTAL_BP`（10000）。
##
## 按 `rarity` 分配 `TOTAL_BP`，用**最大余数法**补齐取整差额，
## 使 Σ 恒精确等于 10000——红线 C1 的零和等式因此可以被**精确断言**（整数才能精确）。
##
## ★ v0.45：**返回长度恒等于 `base_items.size()`**（与 `item_ids()` 对位，调用方按小标号取值），
## 但**只在"参与抽取"的物品之间分配**——被禁用的物品拿到 **0**，其余物品把 10000 分完
## （即"重新归一、不产生 void"）。隐藏的物品**照常参与分配**（它只是不显示）。
##
## 池子不可用时返回**空数组**。
func compute_weights_bp() -> PackedInt32Array:
	var out := PackedInt32Array()
	if not validate().is_empty():
		return out

	var enabled := enabled_items()
	var total := 0
	for d in enabled:
		total += maxi(d.rarity, 0)
	if total <= 0:
		return out

	# 先按"参与抽取"的物品算，再按 item_id 回填到全长输出（禁用项留 0）
	var by_id: Dictionary = {}
	var allocated := 0
	var remainders: Array[Array] = []          # [余数, item_id, 是否已补过]
	for d in enabled:
		var r := maxi(d.rarity, 0)
		var exact := float(TOTAL_BP) * float(r) / float(total)
		var base := int(floor(exact))
		by_id[d.item_id] = base
		allocated += base
		remainders.append([exact - float(base), d.item_id, false])

	# 最大余数法：把差额逐个补给当前余数最大者；余数相同时取**池内顺序靠前**者 ⇒ 结果确定
	var order: Array[StringName] = []
	for d in base_items:
		if d != null:
			order.append(d.item_id)
	var deficit := TOTAL_BP - allocated
	for _k in deficit:
		var best := -1
		for j in remainders.size():
			if remainders[j][2]:
				continue
			if best == -1 or float(remainders[j][0]) > float(remainders[best][0]):
				best = j
			elif float(remainders[j][0]) == float(remainders[best][0]):
				if order.find(StringName(remainders[j][1])) < order.find(StringName(remainders[best][1])):
					best = j
		if best == -1:
			break
		by_id[remainders[best][1]] = int(by_id[remainders[best][1]]) + 1
		remainders[best][2] = true

	for id in order:
		out.append(int(by_id.get(id, 0)))
	return out


## 哪些物品被**取整成了 0 bp**（即概率为 0 ⇒ **永不产出**）。
##
## 这是极端 `rarity` 差距下的真实后果：例如 rarity 为 `[1, 200000]` 时，
## 那一件算下来只有 0.05 bp，取整后为 0 ⇒ **它的概率是 0**。
## 这是**配置质量问题而不是代码 bug**：模型严格按「p ∝ rarity」执行，
## 不偷偷给每件塞一个保底 1 bp（那会改变用户定义的公式）。
## 所以配置方要自己保证"每件都配得出"——本方法就是把这件事**变得可检查**，
## 而不是让它静默发生。返回空数组 = 没有物品被抹平。
func zero_bp_items() -> Array[StringName]:
	var out: Array[StringName] = []
	var bp := compute_weights_bp()
	if bp.is_empty():
		return out
	var ids := item_ids()
	for i in base_items.size():
		# ★ v0.45：被禁用的物品天然是 0 bp，那不是"被抹平"，不该出现在这里
		if state_of(ids[i]) == ItemState.DISABLED:
			continue
		if bp[i] == 0:
			out.append(ids[i])
	return out

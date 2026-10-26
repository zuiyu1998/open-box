## 物品注册表（02-item.md §4.1 的 [补充] / §5.12）。
##
## **不是 autoload class_name 的宿主**：本脚本注册为 autoload 单例 `ItemCatalog`（见 project.godot）。
##
## 存在的两个理由：
##   1. `grant` 只接收 `item_id`，而派生索引的键是 `(category, quality)`——
##      没有注册表就必须把 category / quality 冗余进**每个实例**（约 +30 B/实例，
##      且引入"实例属性与定义不一致"的风险）。
##   2. 04/05/06 需要把 `(category, quality)` 反查成 `item_id`。
##      **反查的唯一合法途径就是这里的 `resolve_item_id`**——否则三个系统会各自拼字符串，
##      拼错只能等到运行时才暴露。
extends Node

## ★ v0.21：**物品类别的内容目录**——`ItemCategoryDef` 的 `.tres` 放这里，
## `_ready()`（以及 `load_category_content()`）会**自动载入并注册**。
## **加一类 = 加一个 `.tres`，不改代码**（核心 §14.3 / R11 的直接落地）。
const CATEGORY_CONTENT_DIR := "res://src/items/content/categories"

## ★ v0.22：**物品的内容目录**——42 个 `ItemDef` 的 `.tres`（7 类别 × 6 档品质）放这里，
## `load_item_content()` 自动载入并注册。**内容由 `tools/gen_item_content.gd` 从
## `ItemConstants` 的六档阶梯生成**（改数值 = 改常量后重跑生成器，不要手改 `.tres`）。
const ITEM_CONTENT_DIR := "res://src/items/content/items"

## ★ v0.28：**货币（资源）的内容目录**——`CurrencyDef` 的 `.tres` 放这里，`_ready()` 自动载入。
## **必须要有**：V6 要求开局必发的 `gem` / `gold` 都已注册，否则 `grant_currency()` 走
## `transact` 会被 `unknown_currency` 拒掉，而**开局资源静默变成 0**（开盒直接卡死）。
const CURRENCY_CONTENT_DIR := "res://src/items/content/currencies"

## item_id(String) -> ItemDef
var _by_id: Dictionary = {}
## 派生索引键 "<category>:<quality>"(String) -> item_id(StringName)
var _by_count_key: Dictionary = {}
## category_id(StringName) -> ItemCategoryDef
var _categories: Dictionary = {}
## ★ v0.18 / v0.19：currency_id(String) -> CurrencyDef（资源 / 货币类）
var _currencies: Dictionary = {}
## 被重复注册的 item_id（V4 用；register 本身不拦截，交给 validate() 统一裁决）
var _duplicate_ids: Array[StringName] = []
## item_id(String) -> 首次注册时抓取的快照 {value, size}（V4 的错误信息要用它点名差异）
var _duplicate_first: Dictionary = {}


## 注册一个物品定义。
##
## **同一 item_id 重复注册不会被静默接受**：这里只**记录**冲突，由 `validate()` 报出（V4）。
## 不在 register 内直接报错，是因为加载时无法判断谁才是权威；与 V1 同一处理方式。
func register(def: ItemDef) -> void:
	if def == null:
		push_error("ItemCatalog.register: 传入了 null 的 ItemDef")
		return
	if def.item_id == &"":
		push_error("ItemCatalog.register: ItemDef.item_id 为空")
		return
	var key := String(def.item_id)
	if _by_id.has(key):
		if not _duplicate_first.has(key):
			var prev := _by_id[key] as ItemDef
			_duplicate_first[key] = {"value": prev.value, "size": prev.size}
			_duplicate_ids.append(def.item_id)
	_by_id[key] = def
	_by_count_key[def.count_key()] = def.item_id


func register_category(cat: ItemCategoryDef) -> void:
	if cat == null or cat.category_id == &"":
		push_error("ItemCatalog.register_category: 类别 id 为空")
		return
	_categories[cat.category_id] = cat


## ★ v0.21：**从内容目录载入全部 `ItemCategoryDef`**（幂等；同 id 覆盖）。
##
## 返回载入成功的条数。目录不存在 / 载入失败**只告警、不崩**——
## 类别缺失会在 `validate()` 里被"物品引用了未注册类别"点名（那是配置错误，必须报出来），
## 而在没有任何物品引用它时，缺类别并不致命（空内容的切片仍能跑）。
func load_category_content() -> int:
	var n := 0
	var dir := DirAccess.open(CATEGORY_CONTENT_DIR)
	if dir == null:
		push_warning(
			"ItemCatalog: 打不开类别内容目录 `%s`（没有类别内容时是正常的）" % CATEGORY_CONTENT_DIR
		)
		return 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var path := CATEGORY_CONTENT_DIR + "/" + fname
			if ResourceLoader.exists(path):
				var res = load(path)
				if res is ItemCategoryDef:
					register_category(res as ItemCategoryDef)
					n += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return n


## ★ v0.22：**从内容目录载入全部 `ItemDef`**（幂等；同 id 覆盖）。
##
## 返回载入成功的条数。**类别必须先载入**（`_ready()` 已保证顺序）：物品引用未注册的类别
## 会被 `validate()` 点名，那是配置错误。
func load_item_content() -> int:
	var n := 0
	var dir := DirAccess.open(ITEM_CONTENT_DIR)
	if dir == null:
		push_warning(
			"ItemCatalog: 打不开物品内容目录 `%s`（没有物品内容时是正常的）" % ITEM_CONTENT_DIR
		)
		return 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var path := ITEM_CONTENT_DIR + "/" + fname
			if ResourceLoader.exists(path):
				var res = load(path)
				if res is ItemDef:
					register(res as ItemDef)
					n += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return n


## ★ v0.28：从内容目录载入全部 `CurrencyDef`（幂等；同 id 覆盖）。返回载入条数。
func load_currency_content() -> int:
	var n := 0
	var dir := DirAccess.open(CURRENCY_CONTENT_DIR)
	if dir == null:
		push_warning(
			"ItemCatalog: 打不开货币内容目录 `%s`（没有货币内容时是正常的）" % CURRENCY_CONTENT_DIR
		)
		return 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var path := CURRENCY_CONTENT_DIR + "/" + fname
			if ResourceLoader.exists(path):
				var res = load(path)
				if res is CurrencyDef:
					register_currency(res as CurrencyDef)
					n += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return n


func _ready() -> void:
	# 顺序有意义：类别先于物品（物品引用类别），货币最后不依赖顺序（V6 只查是否注册）。
	load_category_content()
	load_item_content()
	load_currency_content()


## ★ v0.18：注册一种资源（货币类）。切片两种：`gem`（原石）/ `gold`（金币）。
func register_currency(def: CurrencyDef) -> void:
	if def == null or def.id == &"":
		push_error("ItemCatalog.register_currency: 传入了 null 或 id 为空的 CurrencyDef")
		return
	_currencies[String(def.id)] = def


func get_currency(kind: StringName) -> CurrencyDef:
	return _currencies.get(String(kind), null) as CurrencyDef


func has_currency(kind: StringName) -> bool:
	return _currencies.has(String(kind))


func all_currency_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _currencies.keys():
		out.append(StringName(k))
	return out


## ★ v0.19：**开局必发的两种货币必须已注册**（缺 `gem` 开不了盒、缺 `gold` 装不了模块）。
## 这是 V6 的"定义级"那一半——它必须在**加载期**拦住，而不是等运行期报 `unknown_currency`。
## 返回缺失的货币 id 列表（测试与配置校验器共用）。
func missing_required_currencies() -> Array[StringName]:
	var out: Array[StringName] = []
	for kind in ItemConstants.ALL_CURRENCIES:
		if not has_currency(kind):
			out.append(kind)
	return out


func get_def(item_id: StringName) -> ItemDef:
	return _by_id.get(String(item_id), null) as ItemDef


func get_category(category: StringName) -> ItemCategoryDef:
	return _categories.get(category, null) as ItemCategoryDef


## ★ v0.21：全部已注册类别，**按 `sort_order` 升序**（同序按 id 字典序，保证确定性）。
## UI（08）与任务需求（03）都用它枚举类别，**不得各自维护一份类别清单**。
func all_categories() -> Array[ItemCategoryDef]:
	var out: Array[ItemCategoryDef] = []
	for k in _categories.keys():
		out.append(_categories[k] as ItemCategoryDef)
	out.sort_custom(func(a: ItemCategoryDef, b: ItemCategoryDef) -> bool:
		if a.sort_order != b.sort_order:
			return a.sort_order < b.sort_order
		return String(a.category_id) < String(b.category_id))
	return out


func has_item(item_id: StringName) -> bool:
	return _by_id.has(String(item_id))


## `(category, quality)` → `item_id` 的**反查**（02-item.md §4.3 / §5.12 V1）。
## 未注册组合返回 `&""`。**04/05/06 唯一被允许用来取 item_id 的途径。**
func resolve_item_id(category: StringName, quality: int) -> StringName:
	var key := ItemDef.make_count_key(category, quality)
	return _by_count_key.get(key, &"")


func all_item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _by_id.keys():
		out.append(StringName(k))
	return out


func clear() -> void:
	_by_id.clear()
	_by_count_key.clear()
	_categories.clear()
	_currencies.clear()
	_duplicate_ids.clear()
	_duplicate_first.clear()


## 配置校验器（02-item.md §5.12）。
## 返回 { ok: bool, errors: Array[String] }；**只拦非法配置、不改任何数值**。
##
## V1：`(category, quality) → item_id` 唯一（一个两维键只允许对应一个 item_id）
## V2：`ItemDef.size > 0`
## V3：`ItemDef.value > 0`
## V4：同一 `item_id` 不得重复注册
## V8（★ v0.22）：`ItemDef.quality` ∈ 1..6（白 / 绿 / 蓝 / 紫 / 金 / 红）——越界的品质会让
##   派生索引键落到"不存在的档位"上（UI 取不到颜色、任务需求永远匹配不上），而它对
##   `M̄` 的影响是沉默的，所以必须在加载期拦。
## V9（★ v0.23）：**同一类别内，品质越高权重（`rarity`）必须越低**（严格单调）——权重与品质
##   挂钩；反过来的话"高品质反而更容易抽到"，品质轴当场失效（§5.1 / §5.12）。
## （容量 `warehouse_capacity >= 1` 由 ItemService.validate_config 一并检查）
func validate() -> Dictionary:
	var errors: Array[String] = []

	# V1：两维键唯一
	var seen: Dictionary = {}  # count_key -> item_id
	for k in _by_id.keys():
		var def := _by_id[k] as ItemDef
		var ck := def.count_key()
		if seen.has(ck):
			errors.append(
				"V1 冲突：(%s, %d) 同时对应 `%s` 与 `%s`——派生索引键必须唯一"
				% [def.category, def.quality, seen[ck], def.item_id]
			)
		else:
			seen[ck] = def.item_id

	# V2：size > 0
	for k in _by_id.keys():
		var def := _by_id[k] as ItemDef
		if def.size <= 0:
			errors.append("V2 非法：`%s`.size = %d，必须 > 0" % [def.item_id, def.size])

	# V3：value > 0
	# `value` 是每个物品的**固定**价值字段（`ItemDef.value`，口径归本系统、计算归 07）。
	# value <= 0 会让 `M̄ = Σ(pᵢ × vᵢ)` 失去意义：0 值物品等于"抽到也不算数"，
	# 负值更会让某个物品反过来拉低整体期望——ρ 的分子被污染，而 07 无从察觉。
	for k in _by_id.keys():
		var def := _by_id[k] as ItemDef
		if def.value <= 0:
			errors.append("V3 非法：`%s`.value = %d，必须 > 0" % [def.item_id, def.value])

	# V4：同一 item_id 不得重复注册
	# 实例只记 `item_id`、value 从定义查得（§4.2）。若同一 item_id 被定义两次，
	# 后者静默覆盖前者——**全部现存实例的价值会随之改变**，"同类物品的价值确定"
	# 就退化成"取决于哪份配置最后加载"。这类错误必须在加载期被拦下。
	for id in _duplicate_ids:
		var key := String(id)
		var first: Dictionary = _duplicate_first.get(key, {})
		var last := _by_id.get(key, null) as ItemDef
		errors.append(
			"V4 冲突：`%s` 被重复注册——首次 value=%d/size=%d，末次 value=%d/size=%d"
			% [id, int(first.get("value", 0)), int(first.get("size", 0)),
				last.value if last != null else 0, last.size if last != null else 0]
			+ "。同一 item_id 只允许一个定义：后者会静默覆盖前者，而实例按 item_id 取值，"
			+ "于是全部现存实例的价值随之改变——**同类物品的价值必须确定**"
		)

	# ★ v0.22 新增 V8：quality ∈ 1..6（六档：白 / 绿 / 蓝 / 紫 / 金 / 红）
	# 越界的品质会让派生索引键落到"不存在的档位"上：UI 取不到品质色、任务需求永远
	# 匹配不上，而它对 `M̄` 的影响是沉默的（`value` 照常进求和）——必须在加载期拦。
	for k in _by_id.keys():
		var def := _by_id[k] as ItemDef
		if not ItemConstants.is_valid_quality(def.quality):
			errors.append(
				"V8 非法：`%s`.quality = %d，必须落在 %d..%d（六档：白/绿/蓝/紫/金/红）"
				% [def.item_id, def.quality, ItemConstants.QUALITY_MIN, ItemConstants.QUALITY_MAX]
			)

	# ★ v0.23 新增 V9：**权重与品质挂钩——同一类别内，品质越高权重必须越低**（严格单调）。
	# `rarity` 是**权重**（越大越常见，`p_i = rarity_i / Σ rarity`）。若"高品质反而更容易出"，
	# 品质轴当场失效：开盒的稀缺感没了、任务的高品质需求也随之变便宜——而 07 只消费归一化
	# 后的分布，**看不出这是配置错误**。这里只强制"类别内"单调（类别之间的绝对量级属于内容
	# 设计，见 `02-item.md` §5.1 / `01-gacha.md` 的池子级约定）。
	var by_category: Dictionary = {}
	for k in _by_id.keys():
		var def := _by_id[k] as ItemDef
		if not by_category.has(def.category):
			by_category[def.category] = []
		(by_category[def.category] as Array).append(def)
	for cat in by_category.keys():
		var defs: Array = by_category[cat]
		for i in defs.size():
			for j in range(i + 1, defs.size()):
				var a: ItemDef = defs[i]
				var b: ItemDef = defs[j]
				if a.quality == b.quality:
					continue
				var hi: ItemDef = a if a.quality > b.quality else b
				var lo: ItemDef = b if a.quality > b.quality else a
				if hi.rarity >= lo.rarity:
					errors.append(
						"V9 冲突：类别 `%s` 里品质 %d 的 `%s`.rarity = %d 不低于品质 %d 的 `%s`.rarity = %d"
						% [cat, hi.quality, hi.item_id, hi.rarity, lo.quality, lo.item_id, lo.rarity]
						+ "——**品质越高权重必须越低**（严格单调；否则高品质反而更容易出，品质轴失效）"
					)

	# 类别必须已注册（否则 UI 与任务侧拿不到类别信息）
	for k in _by_id.keys():
		var def := _by_id[k] as ItemDef
		if def.category != &"" and not _categories.has(def.category):
			errors.append("类别未注册：`%s`.category = `%s`" % [def.item_id, def.category])

	# ★ v0.21：类别自身的定义校验 + **`sort_order` 不得重复**（重复的排序值 = 面板顺序不确定）
	var seen_order: Dictionary = {}
	for k in _categories.keys():
		var cat := _categories[k] as ItemCategoryDef
		for p in cat.validate():
			errors.append("类别非法：%s" % p)
		if cat.sort_order <= 0:
			continue
		if seen_order.has(cat.sort_order):
			errors.append(
				"类别排序冲突：`%s` 与 `%s` 的 sort_order 都是 %d（面板顺序会不确定）"
				% [seen_order[cat.sort_order], cat.category_id, cat.sort_order]
			)
		else:
			seen_order[cat.sort_order] = cat.category_id

	# V6（定义级那一半）：CurrencyDef 定义合法 + **开局必发的两种货币已注册**
	for k in _currencies.keys():
		var cdef := _currencies[k] as CurrencyDef
		for p in cdef.validate():
			errors.append("V6 非法：%s" % p)
	for kind in missing_required_currencies():
		errors.append(
			"V6 缺失：资源 `%s` 未注册——开局必发它、且它是某个动作的入场费"
			% kind
			+ "（缺 gem 开不了盒、缺 gold 装不了模块：这是必炸的配置错误，必须在加载期拦住）"
		)

	# V7（v0.20）：售出价格必须是**非负整数**（单位：金币）。
	# `0` 是合法值 = **不可售**（不是"免费送"）；负值会让售卖凭空销毁金币，
	# 而 07 只读派生量、**无从察觉**这类配置错误。
	for k in _by_id.keys():
		var def := _by_id[k] as ItemDef
		if def.sell_gold < 0:
			errors.append(
				"V7 非法：`%s`.sell_gold = %d，必须 >= 0（0 = 不可售；负值会让售卖销毁金币）"
				% [def.item_id, def.sell_gold]
			)

	return {"ok": errors.is_empty(), "errors": errors}

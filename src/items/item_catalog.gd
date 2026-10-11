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

	# 类别必须已注册（否则 UI 与任务侧拿不到类别信息）
	for k in _by_id.keys():
		var def := _by_id[k] as ItemDef
		if def.category != &"" and not _categories.has(def.category):
			errors.append("类别未注册：`%s`.category = `%s`" % [def.item_id, def.category])

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

	return {"ok": errors.is_empty(), "errors": errors}

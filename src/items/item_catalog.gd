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


## 注册一个物品定义。重复 item_id 会覆盖并告警（配置错误应在 validate 阶段被发现）。
func register(def: ItemDef) -> void:
	if def == null:
		push_error("ItemCatalog.register: 传入了 null 的 ItemDef")
		return
	if def.item_id == &"":
		push_error("ItemCatalog.register: ItemDef.item_id 为空")
		return
	if _by_id.has(String(def.item_id)):
		push_warning("ItemCatalog.register: item_id 重复注册，后者覆盖前者：%s" % def.item_id)
	_by_id[String(def.item_id)] = def
	_by_count_key[def.count_key()] = def.item_id


func register_category(cat: ItemCategoryDef) -> void:
	if cat == null or cat.category_id == &"":
		push_error("ItemCatalog.register_category: 类别 id 为空")
		return
	_categories[cat.category_id] = cat


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


## 配置校验器（02-item.md §5.12）。
## 返回 { ok: bool, errors: Array[String] }；**只拦非法配置、不改任何数值**。
##
## V1：`(category, quality) → item_id` 唯一（一个两维键只允许对应一个 item_id）
## V2：`ItemDef.size > 0`
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

	# 类别必须已注册（否则 UI 与任务侧拿不到类别信息）
	for k in _by_id.keys():
		var def := _by_id[k] as ItemDef
		if def.category != &"" and not _categories.has(def.category):
			errors.append("类别未注册：`%s`.category = `%s`" % [def.item_id, def.category])

	return {"ok": errors.is_empty(), "errors": errors}

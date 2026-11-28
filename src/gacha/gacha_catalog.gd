## 模块的注册表（01-gacha.md §5.2.3 V7）。
##
## ★ v0.61（用户裁决）：**套系（`SeriesDef`）已整体删除**——本类现在只管 `ModuleDef`：
##   · 盒子的品质 / 位子 / 寿命 / 开盒价都是 `Box` 自己的字段；
##   · 池子的物品就是 `ItemPool.base_items`（逐盒落盘），不再由模板推导。
extends Node

## module_id(String) -> ModuleDef
var _modules: Dictionary = {}

## ★ v0.41：**模块内容目录**——`ModuleDef` 的 `.tres` 放这里，`_ready()` 自动载入。
## **加一个模块 = 加一个 `.tres`，不改代码**（与套系 / 物品 / 货币三个内容目录同一纪律）。
## 模块的 `targets` 必须指向**池内物品**（`s01_XX` 之类），否则 `PoolService` 会以
## `unknown_target` 拒绝镶嵌——所以内容里的目标要跟套系池子对得上。
const MODULE_CONTENT_DIR := "res://src/gacha/content/modules"


## ★ v0.41：从内容目录载入全部 `ModuleDef`（幂等；同 id 覆盖）。返回载入条数。
##
## **必须排在套系之后**不是硬要求（模块只引用 `item_id`），但排在物品之后就够了；
## 目录不存在 / 载入失败**只告警、不崩**（没有模块内容时"模块镶嵌"区会是空的，那是合法状态）。
func load_module_content() -> int:
	var n := 0
	var dir := DirAccess.open(MODULE_CONTENT_DIR)
	if dir == null:
		push_warning(
			"GachaCatalog: 打不开模块内容目录 `%s`（没有模块内容时是正常的）" % MODULE_CONTENT_DIR
		)
		return 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var path := MODULE_CONTENT_DIR + "/" + fname
			if ResourceLoader.exists(path):
				var res = load(path)
				if res is ModuleDef:
					register_module(res as ModuleDef)
					n += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return n


func _ready() -> void:
	# ★ v0.61：**套系已删除**——不再载入套系内容，也没有"品质模板"这回事。
	load_module_content()   # ★ v0.41：模块内容（许愿机「模块镶嵌」区要用）
	# ★ v0.77：**模块也是仓库物品**——为每个 `ModuleDef` 镜像一个 `ItemDef`，
	#   这样它可以被"获得 / 持有 / 消耗"（镶嵌时消耗一件）。
	materialize_module_items()


func register_module(def: ModuleDef) -> void:
	if def == null or def.id == &"":
		push_error("GachaCatalog.register_module: 传入了 null 或 id 为空的 ModuleDef")
		return
	_modules[String(def.id)] = def


func get_module(module_id: StringName) -> ModuleDef:
	return _modules.get(String(module_id), null) as ModuleDef


func has_module(module_id: StringName) -> bool:
	return _modules.has(String(module_id))


func all_module_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _modules.keys():
		out.append(StringName(k))
	return out


func clear() -> void:
	_modules.clear()


## 配置校验（加载时）。返回 { ok, errors }——**只拦非法配置、不改任何数值**。
func validate() -> Dictionary:
	var errors: Array[String] = []
	for k in _modules.keys():
		var m: ModuleDef = _modules[k] as ModuleDef
		for p in m.validate():
			errors.append("ModuleDef `%s`：%s" % [k, p])
	return {"ok": errors.is_empty(), "errors": errors}

# ══════════════════════════════════════════════════════════════════════════════
#  ★ v0.77：**模块物品化**（模块既是"效果规格"，也是"仓库里的一件东西"）
# ══════════════════════════════════════════════════════════════════════════════

## 模块物品的分类 id（`ItemDef.category`）。UI 可据此把"模块"与普通物品分开列。
const MODULE_CATEGORY := &"module"

## 为每个已注册的 `ModuleDef` 镜像一个 `ItemDef`（**幂等**：已存在则跳过）。
##
## 为什么需要：v0.77 起"能镶"的前提是**仓库里真的有一件该模块**，镶嵌时**消耗**它。
## 于是模块必须能被 `ItemService` 持有——而 `ItemService` 只认 `ItemDef`。
##
## · `item_id` = **模块 id 本身**（`mod_ban_home_q1` 之类）——一件模块对应一个 id，
##   不需要额外的映射表；
## · `value = 0`、`rarity = 0`：**不参与**市场的"按价值上架"与任何随机池（模块只能被"发/买"）；
## · `size = 1×1`：与普通物品同一份容量账。
func materialize_module_items() -> void:
	if ItemCatalog == null:
		return
	if ItemCatalog.get_category(MODULE_CATEGORY) == null:
		var c := ItemCategoryDef.new()
		c.category_id = MODULE_CATEGORY
		c.display_name = "模块"
		ItemCatalog.register_category(c)
	for mid in all_module_ids():
		if ItemCatalog.get_def(mid) != null:
			continue
		var m := get_module(mid)
		if m == null:
			continue
		var d := ItemDef.new()
		d.item_id = mid
		d.display_name = m.display_name if String(m.display_name) != "" else String(mid)
		d.category = MODULE_CATEGORY
		d.quality = m.quality
		d.value = 0
		d.size = Vector2i(1, 1)
		d.rarity = 0
		ItemCatalog.register(d)
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

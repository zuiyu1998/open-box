## 套系与模块的注册表（01-gacha.md §4.1 / §5.2.3 V7）。
##
## 存在的两个理由：
##   1. V7 要求"`module_id` 能在 `ModuleDef` 注册表查到"——**注册表必须真的存在**；
##   2. `ItemPool` 只落 `series_id`（基础池**不逐盒落盘**），载入时**必须**由 `series_id`
##      解析回 `SeriesDef`（01 §4.3 的裁决），解析的宿主就是这里。
##
## `[补充]` **宿主的选择**：文档要求"注册表"与"由 `series_id` 解析"两件事存在，
## 但**没有指定宿主**。这里按仓库既有先例落地——02 的 `ItemCatalog` 是 autoload 单例，
## 本类同样注册为 autoload（`GachaCatalog`），于是 `PoolService` 的静态方法无需额外入参。
extends Node

## series_id(String) -> SeriesDef
var _series: Dictionary = {}
## module_id(String) -> ModuleDef
var _modules: Dictionary = {}


func register_series(def: SeriesDef) -> void:
	if def == null or def.series_id == &"":
		push_error("GachaCatalog.register_series: 传入了 null 或 series_id 为空的 SeriesDef")
		return
	_series[String(def.series_id)] = def


func register_module(def: ModuleDef) -> void:
	if def == null or def.id == &"":
		push_error("GachaCatalog.register_module: 传入了 null 或 id 为空的 ModuleDef")
		return
	_modules[String(def.id)] = def


func get_series(series_id: StringName) -> SeriesDef:
	return _series.get(String(series_id), null) as SeriesDef


func get_module(module_id: StringName) -> ModuleDef:
	return _modules.get(String(module_id), null) as ModuleDef


func has_series(series_id: StringName) -> bool:
	return _series.has(String(series_id))


func has_module(module_id: StringName) -> bool:
	return _modules.has(String(module_id))


func all_series_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _series.keys():
		out.append(StringName(k))
	return out


func all_module_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _modules.keys():
		out.append(StringName(k))
	return out


func clear() -> void:
	_series.clear()
	_modules.clear()


## 配置校验（加载时）。返回 { ok, errors }——**只拦非法配置、不改任何数值**。
func validate() -> Dictionary:
	var errors: Array[String] = []
	for k in _series.keys():
		var s: SeriesDef = _series[k] as SeriesDef
		for p in s.validate():
			errors.append("SeriesDef `%s`：%s" % [k, p])
	for k in _modules.keys():
		var m: ModuleDef = _modules[k] as ModuleDef
		for p in m.validate():
			errors.append("ModuleDef `%s`：%s" % [k, p])
	return {"ok": errors.is_empty(), "errors": errors}

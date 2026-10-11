## 装置注册表（04-device.md §8；核心 §14.3 数据驱动）。
##
## 存在的理由与 `GachaCatalog` 同型：
##   1. **玩家侧只给 `device_id`**（存档里存的就是 id 引用，不存定义副本）⇒ 必须有东西
##      能把 id 解析回 `DeviceDef`（等级曲线、准入上限、折扣都住在定义里）；
##   2. **开局那台的 id 常量**（`DeviceConstants.STARTING_DEVICE_ID`）在初始化路径被读，
##      它必须能查到定义，否则开局就是 0 台（= 永远开不了盒）。
##
## `[补充]` **宿主的选择**：按仓库既有先例落地——02 的 `ItemCatalog` / 01 的 `GachaCatalog`
## 都是 autoload 单例，本类同样注册为 autoload（`DeviceCatalog`），
## 于是 `DeviceService` 的静态方法无需额外入参。
##
## ★ **内容 = 一个 `.tres`**（R11：新增装置必须能纯配置产出）。本表的 `_ready()`
##   会尝试载入 `DEFAULT_CONTENT_PATH`；**载入失败则退回代码内的默认曲线**并给出警告——
##   宁可让游戏能跑（并吵一声），也不要因为一个资源文件坏掉就永远是 0 台。
extends Node

## 切片的内容配置（开局那台基础装置的等级曲线）。
const DEFAULT_CONTENT_PATH := "res://src/devices/content/dev_basic_q1.tres"

## device_id(String) -> DeviceDef
var _by_id: Dictionary = {}

## 载入失败时用的**代码内兜底曲线**（与 `.tres` 的推荐值一致；只用于让游戏可跑，不替代内容）。
const FALLBACK_LEVELS := [
	# [level, unlock_series_quality_max, open_cost_bp, upgrade_cost_gems]
	[1, 2, 10000, 0],
	[2, 3, 6000, 40],
	[3, 4, 2000, 120],
]


func _ready() -> void:
	ensure_default_content()


## 注册一个装置定义。
func register(def: DeviceDef) -> void:
	if def == null or def.id == &"":
		push_error("DeviceCatalog.register: 传入了 null 或 id 为空的 DeviceDef")
		return
	_by_id[String(def.id)] = def


func get_device(device_id: StringName) -> DeviceDef:
	return _by_id.get(String(device_id), null) as DeviceDef


func has_device_def(device_id: StringName) -> bool:
	return _by_id.has(String(device_id))


func all_device_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _by_id.keys():
		out.append(StringName(k))
	return out


func clear() -> void:
	_by_id.clear()


## 确保**开局那台**已经注册（幂等）。
##
## ★ 优先载入内容配置（`.tres`）；载不到就退回 `FALLBACK_LEVELS`（并 push_warning）。
## ★ 若已有同 id 的定义（例如测试自己注册的夹具），**不覆盖**——测试夹具优先。
func ensure_default_content() -> void:
	var id := DeviceConstants.STARTING_DEVICE_ID
	if has_device_def(id):
		return
	var def := _load_content(id)
	if def == null:
		push_warning(
			"DeviceCatalog: 载入 `%s` 失败，改用代码内兜底等级曲线（内容配置应尽快补上）"
			% DEFAULT_CONTENT_PATH
		)
		def = _build_fallback(id)
	register(def)


## 从 `.tres` 载入开局那台的定义；文件缺失 / 类型不对 ⇒ null。
func _load_content(id: StringName) -> DeviceDef:
	if not ResourceLoader.exists(DEFAULT_CONTENT_PATH):
		return null
	var res = load(DEFAULT_CONTENT_PATH)
	if res is DeviceDef:
		var def := res as DeviceDef
		if def.id == &"":
			def.id = id
		return def
	return null


## 代码内兜底（**不是内容**：数值在 `FALLBACK_LEVELS` 里，只为让游戏能启动）。
func _build_fallback(id: StringName) -> DeviceDef:
	var def := DeviceDef.new()
	def.id = id
	def.display_name = "基础装置"
	def.description = "开局发放的那一台。升级它可以让开盒更便宜、并打开更高品质的套系。"
	var levels: Array[DeviceLevelSpec] = []
	for row in FALLBACK_LEVELS:
		var spec := DeviceLevelSpec.new()
		spec.level = int(row[0])
		spec.unlock_series_quality_max = int(row[1])
		spec.open_cost_bp = int(row[2])
		spec.upgrade_cost_gems = int(row[3])
		levels.append(spec)
	def.levels = levels
	return def


## 配置校验（加载时）。返回 { ok, errors }——**只拦非法配置、不改任何数值**。
##
## 除了逐定义的 `DeviceDef.validate()`，还要求**开局那台必须存在且能开切片的套系**：
## 缺了它是"永远是 0 台"（死锁），等级 1 开不了任何套系则是"开局第一步走不动"。
func validate() -> Dictionary:
	var errors: Array[String] = []
	for k in _by_id.keys():
		var def := _by_id[k] as DeviceDef
		for p in def.validate():
			errors.append("DeviceDef `%s`：%s" % [k, p])
	var start_id := DeviceConstants.STARTING_DEVICE_ID
	if not has_device_def(start_id):
		errors.append(
			"开局装置缺失：`%s` 未注册——没有它玩家永远是 0 台，既不能开盒也不能装模块"
			% start_id
		)
	else:
		var start := get_device(start_id)
		if start.unlock_series_quality_max(1) < 1:
			errors.append(
				"开局装置不可用：`%s` 的等级 1 开不了任何套系（开局第一步就走不动）" % start_id
			)
	return {"ok": errors.is_empty(), "errors": errors}

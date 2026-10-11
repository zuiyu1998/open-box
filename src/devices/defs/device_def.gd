## 装置定义（蓝图）（04-device.md §4；核心 §4.4）。
##
## ★ **数据面 = 身份 + 展示 + 等级曲线**：
##   · `id` / `display_name` / `description`：身份与展示；
##   · `levels`：**等级曲线**（准入上限 + 开盒原石折扣 + 升级价，见 `DeviceLevelSpec`）。
##
## ★ **v0.17 的删除项（仍然不得复活，核心 §16.12）**：
##   `cost`（制造成本 `DeviceCost`）、`quality`（品质档位）、`exclusive_group`、`condition`、
##   `tags`、`unlock_flag`、`effects` / `apply_end` / `cross_end`。
##   **装置没有获取路径**（只有开局发放 / 缺键补发）⇒ 制造成本与解锁标记都没有对象。
##
## ★ **v0.19**：装置与模块的成本现在是**资源**（原石 / 金币），`gold_cost` 住在 `ModuleDef` 上，
##   **本类不承载任何"造它要花什么"的字段**（核心 §3 / §16.14）。
@tool
class_name DeviceDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

## ★ 等级曲线：**必须从 level = 1 起、逐级连续、无空洞**（配置校验器强制）。
## **等级上限 = `levels.size()`**——没有单独的 `max_level` 字段（同一事实不存两份）。
@export var levels: Array[DeviceLevelSpec] = []

const MAX_SERIES_QUALITY := 4


func max_level() -> int:
	return levels.size()


## 取某一级的曲线档；越界返回 null（调用方须按"无此等级"处理，不得静默取首档）。
func spec_for_level(level: int) -> DeviceLevelSpec:
	if level < 1 or level > levels.size():
		return null
	return levels[level - 1]


## 该等级**能开的最高套系品质**；等级非法 ⇒ 0（= 什么套系都开不了，绝不放行）。
func unlock_series_quality_max(level: int) -> int:
	var spec := spec_for_level(level)
	return spec.unlock_series_quality_max if spec != null else 0


## 该等级的**开盒原石折扣**（万分比）；等级非法 ⇒ 0（= 免费——但等级非法时 `can_open` 已经先拒绝，
## 因此这个 0 不会被用来放行任何东西）。
func open_cost_bp(level: int) -> int:
	var spec := spec_for_level(level)
	return spec.open_cost_bp if spec != null else 0


## **升到下一级的价格**（原石）；已满级 ⇒ -1（调用方据此拒绝 `device_max_level`）。
func upgrade_cost_to_next(level: int) -> int:
	if level < 1 or level >= levels.size():
		return -1
	return levels[level].upgrade_cost_gems


## 定义级校验（加载时）。返回空数组 = 合法。
##
## ① `id` 非空；② **等级从 1 起、逐级连续**（`levels[i].level == i + 1`）；
## ③ 每档自身合法（`DeviceLevelSpec.validate()`）；
## ④ **准入单调不减**（升一级不许把能开的套系变小——否则升级会变成惩罚）；
## ⑤ **折扣单调不增**（升一级不许把开盒变贵）。
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("bad_device_id：DeviceDef.id 为空")
	if display_name == "":
		problems.append("bad_device_name：%s.display_name 为空（UI 要显示它）" % id)
	if levels.is_empty():
		problems.append("no_levels：%s 没有等级曲线（至少要有一档，且必须是 level = 1）" % id)
	for i in levels.size():
		var spec := levels[i]
		if spec == null:
			problems.append("null_level：%s.levels[%d] 是 null" % [id, i])
			continue
		for p in spec.validate():
			problems.append("%s.levels[%d]：%s" % [id, i, p])
		if spec.level != i + 1:
			problems.append(
				"level_gap：%s.levels[%d].level = %d，必须逐级连续（应为 %d）"
				% [id, i, spec.level, i + 1]
			)
		if i > 0:
			var prev := levels[i - 1]
			if prev != null:
				if spec.unlock_series_quality_max < prev.unlock_series_quality_max:
					problems.append(
						"non_monotonic_unlock：%s 的准入从 %d 降到 %d（升级不许变小）"
						% [id, prev.unlock_series_quality_max, spec.unlock_series_quality_max]
					)
				if spec.open_cost_bp > prev.open_cost_bp:
					problems.append(
						"non_monotonic_discount：%s 的折扣从 %d 升到 %d（升级不许变贵）"
						% [id, prev.open_cost_bp, spec.open_cost_bp]
					)
	return problems

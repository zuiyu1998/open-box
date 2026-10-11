## 设备等级曲线的一档（04-device.md §4；核心 §4.4 / §15 D23 / D24）。
##
## ★ v0.18：设备有**等级 `level`**（1 起、连续、有上限）。**等级的效果只有两条**——
##   ① `unlock_series_quality_max`：**这一级能开的最高套系品质**（准入轴，`device_level_low`）；
##   ② `open_cost_bp`：**这一级的开盒原石折扣**（效率轴，万分比、整数、一律 `floori`）。
##
## ⚠️ **不得再加第三条效果**——尤其**不得**让它影响镶嵌位数 / 40% 损耗 / 寿命预算 / 池子权重
##   （那是 P7 与 C4 的功率面，一字不动）。等级是**准入 + 效率**，不是功率。
##
## ⚠️ **`level` 不是"品质档位"**：`DeviceDef.quality` 已在 v0.17 删除（核心 §16.12），
##   `level` 是设备的**成长刻度**，不产任何修正量、也不做内容释放梯度。
@tool
class_name DeviceLevelSpec
extends Resource

## 本档的等级（**必须从 1 起、逐级连续、无空洞**——由 `DeviceDef.validate()` 强制）。
@export var level: int = 1

## 这一级**能开**的最高套系品质（1–4）。比较对象是**该盒的 `series_quality`**（核心 §4.1.1）。
@export var unlock_series_quality_max: int = 1

## 这一级的**开盒原石折扣**（万分比）：`10000` = 原价、`5000` = 半价、`0` = 免费（最高级的合法取值）。
@export_range(0, 100000, 1) var open_cost_bp: int = 10000

## **从上一级升到本级**要花的原石（等级 1 必须写 0——开局即 1 级，不花原石）。
@export_range(0, 999999, 1) var upgrade_cost_gems: int = 0


## 定义级校验（加载时）。返回空数组 = 合法。
func validate() -> Array[String]:
	var problems: Array[String] = []
	if level < 1:
		problems.append("bad_level：DeviceLevelSpec.level = %d，必须 >= 1" % level)
	if unlock_series_quality_max < 1 or unlock_series_quality_max > 4:
		problems.append(
			"bad_unlock_series_quality_max：等级 %d 的 unlock_series_quality_max = %d，必须落在 1..4"
			% [level, unlock_series_quality_max]
		)
	if open_cost_bp < 0:
		problems.append("bad_open_cost_bp：等级 %d 的折扣为负" % level)
	if upgrade_cost_gems < 0:
		problems.append("bad_upgrade_cost_gems：等级 %d 的升级价为负" % level)
	if level == 1 and upgrade_cost_gems != 0:
		problems.append(
			"level1_upgrade_cost：等级 1 的 upgrade_cost_gems 必须为 0（开局即 1 级，不花原石）"
		)
	return problems

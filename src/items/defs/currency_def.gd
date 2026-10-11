## 资源（货币类）的定义（02-item.md §4.7；核心 §4.8）。
##
## ★ **资源是"无实例的持有"**：**一个计数器就是余额**——没有 `instance_id`、没有 `serial`、
##   没有 `location`；**不占仓库、不进邮件、不计入 `count()`、不进物品守恒等式**。
##   切片有两种（核心 §4.8 的币种表）：**原石 `gem`**（开盒 / 设备升级）、**金币 `gold`**（镶嵌模块）。
##
## ★ **加币种不加机制**：再加一种货币 = 再加一个 `.tres`（金币就是这样加进来的，v0.19）。
##   **数值（谁发 / 谁花 / 花多少）不在本文件**：口径归核心 §4.8，价格归 `04-device.md` §6
##   与 `ModuleDef.gold_cost`（核心 D24 / D25）。
##
## ★ **类名不叫 `Resource`**：那是 Godot 的内置类型，会撞名。
@tool
class_name CurrencyDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""


## 定义级校验（加载时）。返回空数组 = 合法。
## 配置校验器 V6（02-item.md §5.12）的**定义级那一半**：
## `id` 不能为空，且**开局必发的两种货币（gem / gold）必须已注册**（缺 `gem` 开不了盒、
## 缺 `gold` 装不了模块——都是必炸的配置错误，必须在加载期拦住而不是运行期报 unknown_currency）。
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("bad_currency_id：CurrencyDef.id 为空")
	if display_name == "":
		problems.append("bad_currency_name：%s.display_name 为空（UI 要显示它）" % id)
	return problems

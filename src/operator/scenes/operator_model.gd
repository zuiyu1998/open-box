## 干员页 —— Model（★ v0.40 MVC）。
##
## **纯数据与业务，不碰 UI**。它只做两件事，全部经既有系统入口（本类不自己算账）：
##   1. 展示：出战状态 / 等级 / 路线 / 排除目标 / 升级配方（读 `OperatorService` 与 `ItemService`）；
##   2. 行为：出战开关（`toggle_active`）、升级（`OperatorService.upgrade`）。
##
## 纪律：池子数据 / 金币账 / 物品账都不归本类；它只**发起**升级与出战切换、**只读**余额。
class_name OperatorModel
extends RefCounted

## 结果文案（View 渲染它）。
var result: String = ""

var state: GameState = null


func bind(s: GameState) -> void:
	state = s


## 只读快照：View 唯一的数据来源。
func snapshot() -> Dictionary:
	var lv := "干员 Lv.%d / Lv.%d" % [OperatorService.level, OperatorService.MAX_LEVEL]
	var route := OperatorService.current_route()
	var route_name := "养成路线：%s" % String(route.get("name", "未选择"))

	# 排除目标（当前路线的 ban_targets → 显示名）
	var bans := _bans_text()

	# 升级配方
	var req: Dictionary = OperatorService.upgrade_requirement()
	var upgrade_text := "已满级"
	var upgrade_disabled := true
	if not req.is_empty():
		var parts: PackedStringArray = PackedStringArray()
		for k in req.keys():
			var def := ItemCatalog.get_def(StringName(k))
			var name := def.display_name if def != null else String(k)
			parts.append("%s ×%d" % [name, int(req[k])])
		upgrade_text = "升级（%s）" % "、".join(parts)
		upgrade_disabled = not _can_upgrade(req)

	return {
		"level": lv,
		"route": route_name,
		"bans": bans,
		"toggle_text": "出战中" if OperatorService.active else "未出战",
		"toggle_active": OperatorService.active,
		"upgrade_text": upgrade_text,
		"upgrade_disabled": upgrade_disabled,
		"result": result,
	}


## 出战 / 未出战（无代价，即时切换）。
func toggle() -> void:
	OperatorService.toggle_active()
	result = "已出战" if OperatorService.active else "已撤回（未出战）"


## 升级：走 `OperatorService.upgrade()`。
func upgrade() -> void:
	var r := OperatorService.upgrade(state)
	if r["ok"]:
		result = "升级成功：Lv.%d" % int(r["level"])
	else:
		result = "升级失败：%s" % String(r["reason"])


# ══════════════════════════════════════════════════════════════════════════════
#  内部
# ══════════════════════════════════════════════════════════════════════════════

## 排除目标文案（"排除：旧木凳、铜制水壶"；未出战或空 → "无排除"）。
func _bans_text() -> String:
	var bans := OperatorService.active_bans()
	if bans.is_empty():
		return "无排除（未出战或无目标）"
	var parts: PackedStringArray = PackedStringArray()
	for id in bans:
		var def := ItemCatalog.get_def(id)
		parts.append(def.display_name if def != null else String(id))
	return "排除：%s" % "、".join(parts)


func _can_upgrade(req: Dictionary) -> bool:
	for k in req.keys():
		var def := ItemCatalog.get_def(StringName(k))
		if def == null:
			return false
		if ItemService.count(def.category, def.quality) < int(req[k]):
			return false
	return true

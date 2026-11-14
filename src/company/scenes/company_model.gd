## 公司页 —— Model（★ v0.39 MVC）。
##
## **纯数据与业务，不碰 UI**。它只做三件事，全部经既有系统入口（本类不自己算账）：
##   1. 展示：等级 / 路线 / 升级配方 / 产出倒计时 / 库存 / 金币（读 `CompanyService` 与 `ItemService`）；
##   2. 升级：走 `CompanyService.upgrade()`（提交配方物品，原子）；
##   3. 买盲盒：走 `CompanyService.buy()`（金币 → 盲盒，落位归 12）。
##
## 纪律：金币账 / 物品账 / 盲盒账都不归本类；它只**发起**升级与购买、**只读**余额。
class_name CompanyModel
extends RefCounted

## 结果文案（View 渲染它，与许愿机 / 市场页同一风格）。
var result: String = ""

var state: GameState = null


func bind(s: GameState) -> void:
	state = s


## 只读快照：View 唯一的数据来源。
func snapshot() -> Dictionary:
	var lv := "公司 Lv.%d / Lv.%d" % [CompanyService.level, CompanyService.MAX_LEVEL]
	var route := CompanyService.current_route()
	var route_name := "培养路线：%s" % String(route.get("name", "未选择"))

	# 升级配方
	var req: Dictionary = CompanyService.upgrade_requirement()
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

	# 产出倒计时
	var countdown := _countdown_text()

	# 库存
	var stock := _stock_text()

	# 金币 + 买盲盒
	var gold := "金币 %d" % ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var series := _first_series()
	var price := CompanyService.buy_price(series)
	var buy_text := "买一盒"
	var buy_disabled := true
	if price > 0:
		buy_text = "买一盒（%d 金币）" % price
		buy_disabled = CompanyService.stock_of(series) <= 0 \
			or ItemService.currency_balance(ItemConstants.CURRENCY_GOLD) < price

	return {
		"level": lv,
		"route": route_name,
		"upgrade_text": upgrade_text,
		"upgrade_disabled": upgrade_disabled,
		"countdown": countdown,
		"stock": stock,
		"gold": gold,
		"buy_text": buy_text,
		"buy_disabled": buy_disabled,
		"result": result,
	}


## 升级：走 `CompanyService.upgrade()`。
func upgrade() -> void:
	var r := CompanyService.upgrade(state)
	if r["ok"]:
		result = "升级成功：Lv.%d" % int(r["level"])
	else:
		result = "升级失败：%s" % String(r["reason"])


## 买一盒当前路线产出的盲盒。
func buy() -> void:
	var series := _first_series()
	if series == &"":
		result = "买入失败：当前路线没有可产的盲盒"
		return
	var r := CompanyService.buy(series, state)
	if r["ok"]:
		result = "买入成功：%s（- %d 金币）" % [String(r["series_id"]), int(r["paid"])]
	else:
		result = "买入失败：%s" % String(r["reason"])


# ══════════════════════════════════════════════════════════════════════════════
#  内部
# ══════════════════════════════════════════════════════════════════════════════

## 配方物品是否都够（不够 ⇒ 升级按钮置灰）。
func _can_upgrade(req: Dictionary) -> bool:
	for k in req.keys():
		var def := ItemCatalog.get_def(StringName(k))
		if def == null:
			return false
		if ItemService.count(def.category, def.quality) < int(req[k]):
			return false
	return true


## 当前路线产出的第一个系列（骨架：只有 1 个系列）。
func _first_series() -> StringName:
	var route := CompanyService.current_route()
	if route.is_empty():
		return &""
	var series_list: Array = route.get("series", [])
	return series_list[0] if series_list.size() > 0 else &""


func _countdown_text() -> String:
	var s := CompanyService.seconds_until_production()
	if s <= 0:
		return "产出中…"
	var h := s / 3600
	var m := (s % 3600) / 60
	return "距下次产出 %dh %dm" % [h, m]


func _stock_text() -> String:
	var series := _first_series()
	if series == &"":
		return "库存：空"
	var n := CompanyService.stock_of(series)
	if n <= 0:
		return "库存：空"
	return "库存：%s ×%d" % [String(series), n]

## 市场页 —— Model（★ v0.38 MVC）。
##
## **纯数据与业务，不碰 UI**。它只做三件事，全部经既有系统入口（本类不自己算账）：
##   1. 展示：金币余额（读 `ItemService`）、刷新倒计时、上架清单、可售实例（读 `MarketService`）；
##   2. 买入：走 `MarketService.buy()`（扣金币 + 发实例，原子）；
##   3. 卖出：走 `MarketService.sell()`（转发 `ItemService.sell()` 换金币）。
##
## 纪律：金币账 / 实例账仍归 02；本类只**发起**买卖、**只读**余额，不缓存副本、不自算价格。
class_name MarketModel
extends RefCounted

## 买卖结果文案（View 渲染它，与许愿机页的 `open_result` 同一风格）。
var result: String = ""


## 只读快照：View 唯一的数据来源。
func snapshot() -> Dictionary:
	var gold := "金币 %d" % ItemService.currency_balance(ItemConstants.CURRENCY_GOLD)
	var countdown := _countdown_text()

	# 上架清单（读 MarketService，自动确保新鲜）
	var ls := MarketService.listings_snapshot()
	var listing_lines: Array[String] = []
	var buy_options: Array[String] = []
	for l in ls:
		var id: StringName = l["item_id"]
		var def := ItemCatalog.get_def(id)
		var name := def.display_name if def != null else String(id)
		var qname := ItemConstants.quality_name(def.quality) if def != null else ""
		var line := "%s（%s）· %d 金币 · 剩 %d 件" % [
			name, qname, int(l["price"]), int(l["qty"]),
		]
		listing_lines.append(line)
		buy_options.append(line)

	# 可售实例（仓库里 sell_gold > 0 的实例）
	var sell_options: Array[String] = []
	for inst in ItemService.instances:
		if not WarehouseService.is_warehouse(inst.instance_id):
			continue
		var def := ItemCatalog.get_def(inst.item_id)
		if def == null or def.sell_gold <= 0:
			continue
		var name := def.display_name if def != null else String(inst.item_id)
		sell_options.append("%s（%s）· 卖 %d 金币" % [
			name, ItemConstants.quality_name(def.quality), def.sell_gold,
		])

	return {
		"gold": gold,
		"refresh": countdown,
		"listing_lines": listing_lines,
		"buy_options": buy_options,
		"buy_disabled": buy_options.is_empty(),
		"sell_options": sell_options,
		"sell_disabled": sell_options.is_empty(),
		"result": result,
	}


## 买入选中的上架项（`buy_index` = View 的 `BuyPicker` 选中下标）。
func buy(buy_index: int) -> void:
	var ls := MarketService.listings_snapshot()
	if buy_index < 0 or buy_index >= ls.size():
		result = "买入失败：请先选择要买的物品"
		return
	var id: StringName = ls[buy_index]["item_id"]
	var r := MarketService.buy(id, 1)
	if r["ok"]:
		result = "买入成功：%s ×%d（- %d 金币）" % [
			String(id), int(r["bought"]), int(r["paid"]),
		]
	else:
		result = "买入失败：%s" % String(r["reason"])


## 卖出选中的可售实例（`sell_index` = View 的 `SellPicker` 选中下标）。
func sell(sell_index: int) -> void:
	var ids := _sellable_ids()
	if sell_index < 0 or sell_index >= ids.size():
		result = "卖出失败：请先选择要卖的物品"
		return
	var r := MarketService.sell([ids[sell_index]])
	if r["ok"]:
		result = "卖出成功：+ %d 金币" % int(r["gold"])
	else:
		result = "卖出失败：%s" % String(r["reason"])


# ══════════════════════════════════════════════════════════════════════════════
#  内部
# ══════════════════════════════════════════════════════════════════════════════

## 距下次刷新的文案（读 MarketService；不在这里算时间戳）。
func _countdown_text() -> String:
	var s := MarketService.seconds_until_refresh()
	if s <= 0:
		return "刷新中…"
	var h := s / 3600
	var m := (s % 3600) / 60
	return "距刷新 %dh %dm" % [h, m]


## 仓库里可售实例的 instance_id（与 `snapshot()` 的 `sell_options` 同序）。
func _sellable_ids() -> Array[String]:
	var out: Array[String] = []
	for inst in ItemService.instances:
		if not WarehouseService.is_warehouse(inst.instance_id):
			continue
		var def := ItemCatalog.get_def(inst.item_id)
		if def != null and def.sell_gold > 0:
			out.append(inst.instance_id)
	return out

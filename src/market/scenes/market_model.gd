## 市场页 —— Model（★ v0.38 MVC）。
##
## **纯数据与业务，不碰 UI**。它只做两件事，全部经既有系统入口（本类不自己算账）：
##   1. 展示：金币余额（读 `ItemService`）、刷新倒计时、上架清单、待售盲盒（读 `MarketService`）；
##   2. 买入：买物品 `MarketService.buy()` / 买盲盒 `MarketService.buy_box()`。
## ★ v0.63（用户裁决）：**卖出入口已从市场页移除**（买卖不对称：市场只卖，不回收）。
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
	var listing_cards: Array[Dictionary] = []
	for l in ls:
		var id: StringName = l["item_id"]
		var def := ItemCatalog.get_def(id)
		var name := def.display_name if def != null else String(id)
		var qname := ItemConstants.quality_name(def.quality) if def != null else ""
		var line := "%s（%s）· %d 金币 · 剩 %d 件" % [
			name, qname, int(l["price"]), int(l["qty"]),
		]
		listing_lines.append(line)
		# ★ v0.58：一卡一件（View 按 2 列网格铺开，每卡自带购买按钮）
		listing_cards.append({
			"item_id": String(id),
			"name": name,
			"quality": qname,
			"price": int(l["price"]),
			"qty": int(l["qty"]),
		})

	return {
		"gold": gold,
		"refresh": countdown,
		"listing_lines": listing_lines,
		"listing_cards": listing_cards,
		"buy_disabled": listing_cards.is_empty(),
		# ★ v0.60：市场"待售盲盒"（每次刷新 8 个，每个一张卡）
		"box_cards": _box_cards(),
		# ★ v0.77：模块（实物，买了才能镶）
		"module_cards": _module_cards(),
		"box_disabled": _box_cards().is_empty(),
		"result": result,
	}


## ★ v0.77：模块卡片（`{module_id, name, quality, price}`）。
func _module_cards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in MarketService.module_listings_snapshot():
		var mid := StringName(m["module_id"])
		var mdef := GachaCatalog.get_module(mid)
		out.append({
			"module_id": String(mid),
			"name": mdef.display_name if mdef != null else String(mid),
			"quality": mdef.quality if mdef != null else 1,
			"price": int(m["price"]),
		})
	return out


## **买一件模块**（`module_id` 来自卡片按钮）。
func buy_module(module_id: StringName) -> void:
	var r := MarketService.buy_module(module_id)
	if r["ok"]:
		result = "买入模块成功：%s（- %d 金币）" % [String(module_id), int(r["paid"])]
	else:
		result = "买入模块失败：%s" % String(r["reason"])


## ★ v0.60：市场待售盲盒（元数据；买盒按钮带 box_id）。
func _box_cards() -> Array[Dictionary]:
	return MarketService.box_listings_snapshot()


## **买下一个盲盒**（`box_id` 来自卡片按钮）。
func buy_box(box_id: String) -> void:
	var r := MarketService.buy_box(box_id)
	if r["ok"]:
		result = "买入盲盒成功：- %d 金币" % int(r["paid"])
	else:
		result = "买入盲盒失败：%s" % String(r["reason"])


## ★ v0.58：**按 item_id 买入**（每个卡片自带购买按钮，不再有"选中下标"这一层）。
func buy_item(item_id: StringName) -> void:
	if item_id == &"":
		result = "买入失败：物品为空"
		return
	var r := MarketService.buy(item_id, 1)
	if r["ok"]:
		result = "买入成功：%s ×%d（- %d 金币）" % [
			String(item_id), int(r["bought"]), int(r["paid"]),
		]
	else:
		result = "买入失败：%s" % String(r["reason"])

## 距下次刷新的文案（读 `MarketService`；不在这里算时间戳）。
func _countdown_text() -> String:
	var s := MarketService.seconds_until_refresh()
	if s <= 0:
		return "刷新中…"
	var h := s / 3600
	var m := (s % 3600) / 60
	return "距刷新 %dh %dm" % [h, m]
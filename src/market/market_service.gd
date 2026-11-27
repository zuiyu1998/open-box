## 市场系统（★ v0.38 新增，第 13 个系统，`docs/systems/13-market.md`）。
##
## 注册为 autoload 单例 `MarketService`（见 project.godot）。
##
## **职责：让玩家"买"上架物品（花金币）与"卖"仓库物品（换金币）。**
## 它**不拥有**物品实例、也不拥有金币余额——那都是 `02`（`ItemService`）的账：
##  · 买入 = 一次 `ItemService.transact([{currency, -金币}, {grant, kind=&"market"}, …])`，
##    放不下（主动 kind ⇒ `OVERFLOW_REJECT`）时整笔被拒、金币分文不动、库存不减；
##  · 卖出 = 直接转发 `ItemService.sell()`（按 `ItemDef.value` 换金币），本系统不另定卖价。
##
## **上架刷新**：每 `REFRESH_SECONDS`（当前 6 小时）从全部**可交易**物品
## （`sell_gold > 0`，即"卖得出价"的物品）里随机抽 `SLOT_COUNT` 个不同的 `item_id`，
## 每格 `STOCK_PER_SLOT` 件、买价 = `sell_gold × BUY_PRICE_MULTIPLIER`。
##
## **确定性 / 测试**：`refresh()` 接受可选 `seed_override` 注入私有 RNG 种子；
## 正常路径每次刷新用随机种子。**库存与时间戳本轮只入内存**（`to_save_dict` / `from_save_dict`
## 只提供形状，等 `10` 的存档层落地后再接上）。
extends Node

## ★ v0.38：**刷新周期（秒）**——用户裁决"暂时为 6 小时"。
const REFRESH_SECONDS := 6 * 3600

## 上架格数（一次刷新随机抽多少个不同物品）。
const SLOT_COUNT := 6

## ★ v0.60：**每次刷新生成多少个盲盒用于售卖**（用户裁决：8 个；每个一张卡片 + 一个购买按钮）。
const BOX_SLOTS := 8

## 每个上架盲盒的池子件数（含材料那一件）。
const BOX_POOL_COUNT := 8

## 每格库存件数（买走一件 −1，归零即该格售罄）。
const STOCK_PER_SLOT := 1

## **买入价倍数**：买价 = `ItemDef.value × BUY_PRICE_MULTIPLIER`。
## 买入比卖出贵 ⇒ 市场抽成，差价是经济闭环的一部分（🔧 归市场系统，可标定）。
const BUY_PRICE_MULTIPLIER := 2

# ── 运行时状态 ──────────────────────────────────────────────────────────────────

## 上架清单：每格 `{ "item_id": StringName, "price": int, "qty": int }`。
var listings: Array[Dictionary] = []

## ★ v0.60：**盲盒上架库存**（脱离 `GameState` 的"待售盒子"——买下才进玩家仓库）。
## 刷新时**未卖出的旧盒直接丢掉**（它们是市场库存，不是玩家的东西）。
var box_listings: Array[Box] = []

## 本次上架的 Unix 时间戳（秒）。`ensure_fresh()` 据此判断是否要刷新。
var refreshed_at_unix: int = 0

## 私有 RNG（刷新抽物品用；测试经 `refresh(seed_override)` 注入确定值）。
var _rng: RandomNumberGenerator = null


# ══════════════════════════════════════════════════════════════════════════════
#  刷新
# ══════════════════════════════════════════════════════════════════════════════

## 重抽上架（覆盖式）。`seed_override >= 0` 时注入确定种子（测试用）；
## `now_unix >= 0` 时用给定时间戳作为本次上架时间（测试用），否则用系统当前时间。
##
## 抽法：从全部"**可交易**"物品（`sell_gold > 0`）里**不放回**抽 `SLOT_COUNT` 个不同 `item_id`
## （不足 `SLOT_COUNT` 个可交易物品时抽全部），每格 `STOCK_PER_SLOT` 件、价 = `sell_gold × 2`。
func refresh(seed_override: int = -1, now_unix: int = -1) -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
	if seed_override >= 0:
		_rng.seed = seed_override
	else:
		_rng.randomize()

	var pool: Array[StringName] = []
	for id in ItemCatalog.all_item_ids():
		var def := ItemCatalog.get_def(id)
		if def != null and def.value > 0:
			pool.append(id)

	# 不放回抽样：洗牌后取前 SLOT_COUNT 个（数量不足则全取）
	_shuffle(pool)
	listings.clear()
	var n := mini(SLOT_COUNT, pool.size())
	for i in n:
		var id: StringName = pool[i]
		var def := ItemCatalog.get_def(id)
		listings.append({
			"item_id": id,
			"price": def.value * BUY_PRICE_MULTIPLIER,
			"qty": STOCK_PER_SLOT,
		})
	_roll_box_listings()
	refreshed_at_unix = now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())


## ★ v0.60：生成本次上架的 8 个盲盒（**不交付给玩家**，买下才进仓库）。
##
## 材料从**已注册物品**里随机抽（用它的品质决定盲盒品质），池子件数 `BOX_POOL_COUNT`；
## 抽到凑不够件数的材料就跳过、换一个（品质 1 的材料也能靠"同品质补齐"生成）。
## 目标 8 个；内容不足时**少于 8 个也是合法结果**（不静默塞假盒）。
func _roll_box_listings() -> void:
	box_listings.clear()                       # 未卖出的旧盒直接丢（用户裁决：销毁）
	var st: GameState = GameSession.state
	if st == null:
		return
	var pool: Array[StringName] = []
	for id in ItemCatalog.all_item_ids():
		if ItemCatalog.get_def(id) != null:
			pool.append(id)
	if pool.is_empty():
		return
	_shuffle(pool)
	# 件数自适应：材料品质越低、可用物品越少 ⇒ 按"最多能凑多少"取（3…BOX_POOL_COUNT）。
	# 否则低品质材料会凑不满 8 件、整批少盒（真实内容与测试夹具都会遇到）。
	var guard := 0
	while box_listings.size() < BOX_SLOTS and guard < BOX_SLOTS * 8:
		guard += 1
		var material: StringName = pool[_rng.randi_range(0, pool.size() - 1)]
		var src := ItemCatalog.get_def(material)
		if src == null:
			continue
		var capacity := 1
		for id in pool:
			var d := ItemCatalog.get_def(id)
			if d == null or d.item_id == material:
				continue
			if d.quality <= src.quality:
				capacity += 1
		var want := mini(BOX_POOL_COUNT, capacity)
		if want < 3:
			continue
		var r := GachaService.generate_box(st, material, want, _rng.randi(), false)
		if not r["ok"]:
			continue
		box_listings.append(r["box"] as Box)


## 盲盒上架清单（**元数据副本**；买盒要的是 `box_id`，Box 实例不外传）。
func box_listings_snapshot() -> Array[Dictionary]:
	ensure_fresh()
	var out: Array[Dictionary] = []
	for b in box_listings:
		out.append({
			"box_id": b.box_id,
			"quality": b.quality,
			"size": b.item_pool.base_items.size() if b.item_pool != null else 0,
			"gem_cost": b.gem_cost,
			"price": GachaService.sell_price_gold(b),
		})
	return out


## ★ v0.60：**买下一个盲盒**（金币 = 它的品质卖价；买下后进玩家仓库）。
func buy_box(box_id: String) -> Dictionary:
	ensure_fresh()
	var idx := -1
	for i in box_listings.size():
		if box_listings[i].box_id == box_id:
			idx = i
			break
	if idx < 0:
		return {"ok": false, "reason": &"not_listed", "paid": 0}
	var b: Box = box_listings[idx]
	var price := GachaService.sell_price_gold(b)
	if price <= 0:
		return {"ok": false, "reason": &"not_listed", "paid": 0}
	var res := ItemService.transact([{
		"op": ItemConstants.OP_CURRENCY,
		"kind": ItemConstants.CURRENCY_GOLD,
		"delta": -price,
	}])
	if not res["ok"]:
		return {"ok": false, "reason": StringName(res["reason"]), "paid": 0}
	# 交付：从"上架库存"转入玩家仓库（盒子永不丢失 ⇒ 放不下进邮件）
	b.location = WarehouseService.place_box(b.size)
	if GameSession.state != null:
		GameSession.state.add_box(b)
	box_listings.remove_at(idx)
	return {"ok": true, "reason": ItemConstants.REASON_OK, "paid": price, "box_id": box_id}

## 惰性刷新：距上次上架 ≥ `REFRESH_SECONDS` 就自动重抽。
## `now_unix < 0` 用系统当前时间（测试可传固定值）。
func ensure_fresh(now_unix: int = -1) -> void:
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	if refreshed_at_unix <= 0 or (now - refreshed_at_unix) >= REFRESH_SECONDS:
		refresh(-1, now)


# ══════════════════════════════════════════════════════════════════════════════
#  查询
# ══════════════════════════════════════════════════════════════════════════════

## 当前上架清单（**先 `ensure_fresh()`，保证拿到的是新鲜货**）。返回**副本**。
func listings_snapshot() -> Array[Dictionary]:
	ensure_fresh()
	return listings.duplicate(true)


## 某件上架物品的库存（`item_id` 不在架上或已售罄 → 0）。
func stock_of(item_id: StringName) -> int:
	for l in listings:
		if StringName(l["item_id"]) == item_id:
			return int(l["qty"])
	return 0


## 买入价（只读）。**未上架或不可交易 ⇒ 返回 0**（0 = 买不到，不是免费）。
func buy_price(item_id: StringName) -> int:
	for l in listings:
		if StringName(l["item_id"]) == item_id:
			return int(l["price"])
	return 0


## 距下次刷新的剩余秒数（`now_unix < 0` 用系统当前时间）。
func seconds_until_refresh(now_unix: int = -1) -> int:
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	if refreshed_at_unix <= 0:
		return 0
	return maxi(REFRESH_SECONDS - (now - refreshed_at_unix), 0)


# ══════════════════════════════════════════════════════════════════════════════
#  买入 / 卖出
# ══════════════════════════════════════════════════════════════════════════════

## 买入 `count` 件某上架物品。**一次事务**：扣金币 + 发 `count` 个实例，同生共死。
##
## 返回 `{ ok, reason, bought, paid, item_id }`：
##  · `ok == false` 时**金币分文不动、库存不减、无任何实例**（原子）；
##  · 失败原因：`not_listed`（不在架上）/ `sold_out`（库存不足）/ `currency_insufficient`
##    （金币不够）/ `no_space`（仓库放不下，主动 kind 整笔拒绝）/ `bad_op`（非法参数）。
##  · 买价总额 = `buy_price(item_id) × count`。
func buy(item_id: StringName, count: int = 1) -> Dictionary:
	var fail := func(reason: StringName) -> Dictionary:
		return {"ok": false, "reason": reason, "bought": 0, "paid": 0, "item_id": String(item_id)}

	if count <= 0:
		return fail.call(ItemConstants.REASON_BAD_OP)
	var price := buy_price(item_id)
	if price <= 0:
		return fail.call(&"not_listed")
	if stock_of(item_id) < count:
		return fail.call(&"sold_out")

	var total := price * count

	# ── 组装事务：扣金币 + 逐个发物品（主动 kind ⇒ 放不下整笔拒绝）────────────────
	var ops: Array = [{
		"op": ItemConstants.OP_CURRENCY,
		"kind": ItemConstants.CURRENCY_GOLD,
		"delta": -total,
	}]
	for _i in count:
		ops.append({
			"op": ItemConstants.OP_GRANT,
			"item_id": item_id,
			"source": {"kind": ItemConstants.KIND_MARKET},
		})

	var res := ItemService.transact(ops)
	if not res["ok"]:
		return fail.call(StringName(res["reason"]))

	# 事务成功 ⇒ 扣库存（逐格扣，与"买几件"对应）
	_decrement_stock(item_id, count)
	return {
		"ok": true, "reason": ItemConstants.REASON_OK,
		"bought": count, "paid": total, "item_id": String(item_id),
	}


## 卖出：**直接转发 `ItemService.sell()`**（按 `sell_gold` 换金币）。
## 市场不另定卖价、不抽成——本系统的"卖"就是 02 已裁决的那条出口（核心 D26）。
func sell(instance_ids: Array[String]) -> Dictionary:
	return ItemService.sell(instance_ids)


## ★ v0.59：**卖出盲盒**——转发 `GachaService.sell_box()`（按品质固定价表发金币、销毁盒子）。
## 市场同样**不另定价**。
func sell_box(box_id: String) -> Dictionary:
	var st: GameState = GameSession.state
	if st == null:
		return {"ok": false, "reason": &"no_state", "gold": 0}
	return GachaService.sell_box(st, box_id)


# ══════════════════════════════════════════════════════════════════════════════
#  存档形状（★ v0.38：只提供形状，等 10 落地后接上）
# ══════════════════════════════════════════════════════════════════════════════

## 存档形态：上架清单 + 上架时间戳。键序固定（往返字节级稳定依赖它）。
## ★ 本轮**不真写盘**——存档文件 / 信封 / 版本归 10，尚未落地。
func to_save_dict() -> Dictionary:
	var arr: Array = []
	for l in listings:
		arr.append({
			"item_id": String(l["item_id"]),
			"price": int(l["price"]),
			"qty": int(l["qty"]),
		})
	return {"listings": arr, "refreshed_at_unix": refreshed_at_unix}


## 从存档形状还原（**覆盖式**）。旧档缺段 → 空上架（下次 `ensure_fresh` 会立即刷）。
func from_save_dict(d: Dictionary) -> void:
	listings.clear()
	var arr = d.get("listings", [])
	if arr is Array:
		for e in (arr as Array):
			if e is Dictionary:
				var ed: Dictionary = e
				listings.append({
					"item_id": StringName(ed.get("item_id", "")),
					"price": int(ed.get("price", 0)),
					"qty": int(ed.get("qty", 0)),
				})
	refreshed_at_unix = int(d.get("refreshed_at_unix", 0))


## 清空（新游戏 / 测试重置）。
func reset() -> void:
	listings.clear()
	box_listings.clear()          # ★ v0.60：上架盲盒也一并清掉（未卖出的直接丢）
	refreshed_at_unix = 0
	_rng = null


# ══════════════════════════════════════════════════════════════════════════════
#  内部
# ══════════════════════════════════════════════════════════════════════════════

## Fisher–Yates 洗牌（原地，用私有 RNG——**不碰全局 RNG**）。
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 库存递减（按上架顺序逐格扣；`count` 一定 ≤ 总库存，调用方已校验）。
func _decrement_stock(item_id: StringName, count: int) -> void:
	var left := count
	for i in listings.size():
		if left <= 0:
			break
		if StringName(listings[i]["item_id"]) == item_id:
			var take := mini(int(listings[i]["qty"]), left)
			listings[i]["qty"] = int(listings[i]["qty"]) - take
			left -= take

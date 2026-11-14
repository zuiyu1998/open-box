## 公司系统（★ v0.39 新增，第 14 个系统，`docs/systems/14-company.md`）。
##
## 注册为 autoload 单例 `CompanyService`（见 project.godot）。
##
## **职责：玩家经营的公司——按等级与培养路线，定时产出盲盒供玩家花金币购买。**
## 它**不拥有**盲盒（Box 归 01 的 `GameState`）、**不拥有**金币账与物品账（那是 02）：
##  · 买盲盒 = 先扣金币（02 的 `transact`）再 `GachaService.grant_box`（01 发盒，
##    落位走 `WarehouseService.place_box`——放得下进仓库、放不下进邮件）；
##  · 升级 = 提交指定物品（消耗走 02 的 `transact` 的 `consume` op），等级 +1。
##
## **三条核心规则**：
##   · **等级**：升级要提交固定配方（`{item_id: count}`），消耗后 +1，有上限 `MAX_LEVEL`；
##   · **培养路线**：互斥，选一条（`select_route`），决定产出的盲盒系列（`series` 列表）与买价；
##   · **定时产出**：每 `PRODUCTION_INTERVAL`（当前 1 小时）自动产 `PRODUCTION_BATCH` 盒进库存，
##     库存有上限 `STOCK_CAP`，满了不产出。
##
## **确定性 / 测试**：`produce()` / `ensure_produced()` 接受可选 `now_unix` 注入时间戳；
## 正常路径用系统时间。**状态本轮只入内存**（`to_save_dict` / `from_save_dict` 只提供形状，等 10 落地）。
extends Node

## ★ v0.39：**产出周期（秒）**——用户裁决"每 1 小时一批"。
const PRODUCTION_INTERVAL := 3600

## 每批产出的盲盒数。
const PRODUCTION_BATCH := 1

## 库存上限（满了不再产出）。
const STOCK_CAP := 10

## 公司等级上限。
const MAX_LEVEL := 5

## ★ 培养路线（骨架：当前只有 `series_01`，故先内置一条示范路线）。
##
## **将来多系列后改为内容配置**（`.tres`，与 ItemCatalog / GachaCatalog 同一纪律），
## 见 `docs/systems/14-company.md` §7 M1。
## 每条：`name` 显示名、`series` 可产出的盲盒系列列表、`prices` 每个系列的金币买价（🔧 可标定）。
const ROUTES := {
	&"standard": {
		"name": "标准线",
		"series": [&"series_01"],
		"prices": {&"series_01": 100},
	},
}

## 升级配方（🔧 可标定）：`level -> {item_id: count}`（升到 `level+1` 要提交这些物品）。
## 缺键 = 已满级 / 无需配方（`MAX_LEVEL` 封顶，见 `upgrade_requirement()`）。
const UPGRADE_REQUIREMENTS := {
	1: {&"home_q1": 1},
	2: {&"home_q2": 2},
	3: {&"home_q3": 3},
	4: {&"home_q4": 4},
}

# ── 运行时状态 ──────────────────────────────────────────────────────────────────

## 公司等级（1..MAX_LEVEL）。
var level: int = 1

## 当前培养路线 id（互斥：一次只选一条）。
var route_id: StringName = &"standard"

## 盲盒库存：`{ "series_id": StringName, "produced_at": int }`（产出的顺序 = 列表顺序）。
var stock: Array[Dictionary] = []

## 上次产出的 Unix 时间戳（秒）。`ensure_produced()` 据此判断是否要再产一批。
var last_production_unix: int = 0


# ══════════════════════════════════════════════════════════════════════════════
#  查询
# ══════════════════════════════════════════════════════════════════════════════

## 当前路线的只读视图（不存在 → 空字典）。
func current_route() -> Dictionary:
	return ROUTES.get(route_id, {})


## 全部路线（只读，副本）。
func routes() -> Dictionary:
	return ROUTES.duplicate(true)


## 当前等级升到下一级要提交的物品配方（`{item_id: count}`；满级 → 空字典）。
func upgrade_requirement() -> Dictionary:
	return UPGRADE_REQUIREMENTS.get(level, {})


## 某系列的买价（金币）。**不在当前路线的系列里 / 未标价 → 返回 0（0 = 买不到，不是免费）**。
func buy_price(series_id: StringName) -> int:
	var route := current_route()
	if route.is_empty():
		return 0
	var prices: Dictionary = route.get("prices", {})
	return int(prices.get(series_id, 0))


## 库存里某个系列的盒数。
func stock_of(series_id: StringName) -> int:
	var n := 0
	for s in stock:
		if StringName(s["series_id"]) == series_id:
			n += 1
	return n


## 库存快照（副本，按产出顺序）。
func stock_snapshot() -> Array[Dictionary]:
	return stock.duplicate(true)


## 距下次产出的剩余秒数。
func seconds_until_production(now_unix: int = -1) -> int:
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	if last_production_unix <= 0:
		return 0
	return maxi(PRODUCTION_INTERVAL - (now - last_production_unix), 0)


# ══════════════════════════════════════════════════════════════════════════════
#  培养路线
# ══════════════════════════════════════════════════════════════════════════════

## 切换培养路线（**互斥**）。`route_id` 不存在 → 返回 false、状态不变。
func select_route(id: StringName) -> bool:
	if not ROUTES.has(id):
		return false
	route_id = id
	return true


# ══════════════════════════════════════════════════════════════════════════════
#  升级
# ══════════════════════════════════════════════════════════════════════════════

## 升级：提交当前等级的配方物品（消耗），等级 +1。
##
## 返回 `{ ok, reason, level }`：
##  · 满级 ⇒ `max_level`；配方物品不足 ⇒ `missing_items`（**什么都不消耗**，原子）；
##  · 成功 ⇒ 消耗配方物品、`level += 1`。
func upgrade(state: GameState) -> Dictionary:
	var req := upgrade_requirement()
	if req.is_empty():
		return {"ok": false, "reason": &"max_level", "level": level}

	# 预检：配方物品都够（不足则整批不消耗）
	for k in req.keys():
		var item_id: StringName = StringName(k)
		var need: int = int(req[k])
		var def := ItemCatalog.get_def(item_id)
		if def == null:
			return {"ok": false, "reason": &"bad_recipe", "level": level}
		if ItemService.count(def.category, def.quality) < need:
			return {"ok": false, "reason": &"missing_items", "level": level}

	# 组装事务：逐个 consume（配方里的每种物品 × 数量）
	var ops: Array = []
	var consume_ids: Array[String] = []
	for k in req.keys():
		var item_id: StringName = StringName(k)
		var def := ItemCatalog.get_def(item_id)
		var ids := ItemService.query(def.category, def.quality)
		for i in int(req[k]):
			consume_ids.append(ids[i])
	if not consume_ids.is_empty():
		var res := ItemService.transact([
			{"op": ItemConstants.OP_CONSUME, "instance_ids": consume_ids, "tag": ItemConstants.TAG_CONVERT},
		])
		if not res["ok"]:
			return {"ok": false, "reason": StringName(res["reason"]), "level": level}

	level = mini(level + 1, MAX_LEVEL)
	return {"ok": true, "reason": ItemConstants.REASON_OK, "level": level}


# ══════════════════════════════════════════════════════════════════════════════
#  定时产出
# ══════════════════════════════════════════════════════════════════════════════

## 产出一批盲盒进库存（库存满则跳过）。`now_unix >= 0` 注入时间戳（测试）。
##
## 产出的系列 = 当前路线的 `series` 列表（当前只有 1 个系列，取第一个；将来多系列轮换 / 按等级解锁）。
func produce(now_unix: int = -1) -> int:
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var route := current_route()
	if route.is_empty():
		return 0
	var series_list: Array = route.get("series", [])
	if series_list.is_empty():
		return 0

	var produced := 0
	for _i in PRODUCTION_BATCH:
		if stock.size() >= STOCK_CAP:
			break
		# 骨架：只取第一个系列（将来按等级 / 路线在多个系列里轮换，见 §7 M2）
		var sid: StringName = series_list[0]
		stock.append({"series_id": sid, "produced_at": now})
		produced += 1
	last_production_unix = now
	return produced


## 惰性产出：距上次产出 ≥ `PRODUCTION_INTERVAL` 就再产一批。
func ensure_produced(now_unix: int = -1) -> void:
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	if last_production_unix <= 0 or (now - last_production_unix) >= PRODUCTION_INTERVAL:
		produce(now)


# ══════════════════════════════════════════════════════════════════════════════
#  购买
# ══════════════════════════════════════════════════════════════════════════════

## 买一盒库存盲盒：**先扣金币（02 事务）→ 再发盒（01）**。
##
## 返回 `{ ok, reason, series_id, paid }`：
##  · `not_listed`（系列不在当前路线）/ `out_of_stock`（库存无该系列）/
##    `currency_insufficient`（金币不够）/ `no_space`（放不下——由 grant_box 的 place_box 落邮件，
##    见下）。
## ⚠️ **原子性边界（裁决 13）**：扣金币（02）与发盒（01）是**两个系统**，不承诺跨系统原子。
##   实际顺序 = 预检（金币够 / 有库存）→ 扣金币 → 发盒；发盒失败概率极低（系列已在路线里注册）。
##   盲盒是**被动产出**（放不下进邮件、永不丢失），故不存在"扣了钱盒子凭空消失"。
func buy(series_id: StringName, state: GameState) -> Dictionary:
	var fail := func(reason: StringName) -> Dictionary:
		return {"ok": false, "reason": reason, "series_id": String(series_id), "paid": 0}

	var price := buy_price(series_id)
	if price <= 0:
		return fail.call(&"not_listed")
	if stock_of(series_id) <= 0:
		return fail.call(&"out_of_stock")
	if ItemService.currency_balance(ItemConstants.CURRENCY_GOLD) < price:
		return fail.call(ItemConstants.REASON_CURRENCY_INSUFFICIENT)
	if state == null:
		return fail.call(&"bad_state")

	# ① 扣金币（02 唯一写入方）
	var pay := ItemService.transact([
		{"op": ItemConstants.OP_CURRENCY, "kind": ItemConstants.CURRENCY_GOLD, "delta": -price},
	])
	if not pay["ok"]:
		return fail.call(StringName(pay["reason"]))

	# ② 从库存移除一盒（FIFO 里第一个该系列）
	var removed := _take_from_stock(series_id)
	if removed < 0:
		# 理论上不可达（预检过库存）；防御：金币已扣，只能继续发盒
		return fail.call(&"out_of_stock")

	# ③ 发盒（01；落位走 WarehouseService.place_box）
	var boxes := GachaService.grant_box(state, series_id, 1, &"company")
	if boxes.is_empty():
		return fail.call(&"grant_failed")

	return {"ok": true, "reason": ItemConstants.REASON_OK, "series_id": String(series_id), "paid": price}


# ══════════════════════════════════════════════════════════════════════════════
#  存档形状（★ v0.39：只提供形状，等 10 落地后接上）
# ══════════════════════════════════════════════════════════════════════════════

## 存档形态：等级 + 路线 + 库存 + 上次产出时间戳。键序固定。
func to_save_dict() -> Dictionary:
	var arr: Array = []
	for s in stock:
		arr.append({
			"series_id": String(s["series_id"]),
			"produced_at": int(s["produced_at"]),
		})
	return {
		"level": level,
		"route_id": String(route_id),
		"stock": arr,
		"last_production_unix": last_production_unix,
	}


## 从存档形状还原（覆盖式）。旧档缺段 → 默认等级 1 / 默认路线 / 空库存。
func from_save_dict(d: Dictionary) -> void:
	level = clampi(int(d.get("level", 1)), 1, MAX_LEVEL)
	route_id = StringName(d.get("route_id", String(&"standard")))
	stock.clear()
	var arr = d.get("stock", [])
	if arr is Array:
		for e in (arr as Array):
			if e is Dictionary:
				var ed: Dictionary = e
				stock.append({
					"series_id": StringName(ed.get("series_id", "")),
					"produced_at": int(ed.get("produced_at", 0)),
				})
	last_production_unix = int(d.get("last_production_unix", 0))


## 清空（新游戏 / 测试重置）。
func reset() -> void:
	level = 1
	route_id = &"standard"
	stock.clear()
	last_production_unix = 0


# ══════════════════════════════════════════════════════════════════════════════
#  内部
# ══════════════════════════════════════════════════════════════════════════════

## 从库存移除一盒（第一个匹配的系列），返回其下标；没找到 → -1。
func _take_from_stock(series_id: StringName) -> int:
	for i in stock.size():
		if StringName(stock[i]["series_id"]) == series_id:
			stock.remove_at(i)
			return i
	return -1

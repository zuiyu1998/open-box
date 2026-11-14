## 干员系统（★ v0.40 新增，第 15 个系统，`docs/systems/15-operator.md`）。
##
## 注册为 autoload 单例 `OperatorService`（见 project.godot）。
##
## **职责：干员为许愿机（开盒）提供"类似模块"的免费被动效果——排除（BAN）某些物品。**
## 与模块的**唯一区别**：
##  · 模块 = 镶嵌到某个盒子、花金币 + 扣 1 次寿命（有代价、占用槽位）；
##  · 干员 = **出战即生效**（`active`），**无代价、不占盒子槽位**，效果走与模块 BAN
##    **完全相同的池子求值路径**（40% 蒸发 void、60% 摊回其余物品）。
##
## **养成**：等级（提交配方物品升级）+ **互斥路线**（决定排除哪些物品）。
##
## **效果注入**：本系统**不写池子数据**（`PoolService` 仍是唯一写入方）——
## 它只向 `PoolService` 注入一个 `extra_ban_provider` 回调；`_compute` 在算派生状态时
## 调用它拿"出战干员的额外排除目标"，与模块 BAN 走**同一条** 40%/60% 零和路径。
## 这是全库既有的注入模式（`ItemService.series_item_provider` 同理）。
extends Node

## 等级上限。
const MAX_LEVEL := 5

## ★ 养成路线（骨架：互斥，选一条；决定排除哪些物品）。
##
## **将来多系列后改为内容配置**（`.tres`，与 ItemCatalog / GachaCatalog 同一纪律），
## 见 `docs/systems/15-operator.md` §7 M1。
## 每条：`name` 显示名、`ban_targets` 该路线排除的物品 id 列表。
const ROUTES := {
	&"precision": {
		"name": "精准线",
		"ban_targets": [&"home_q6"],   # 示范：排除「传世茶案」（品质 6）
	},
}

## 升级配方（🔧）：`level -> {item_id: count}`。
const UPGRADE_REQUIREMENTS := {
	1: {&"home_q1": 1},
	2: {&"home_q2": 2},
	3: {&"home_q3": 3},
	4: {&"home_q4": 4},
}

# ── 运行时状态 ──────────────────────────────────────────────────────────────────

## 是否出战（**出战才生效**；未出战 ⇒ 效果不注入求值）。
var active: bool = true

## 干员等级（1..MAX_LEVEL）。
var level: int = 1

## 当前养成路线 id（互斥）。
var route_id: StringName = &"precision"


# ══════════════════════════════════════════════════════════════════════════════
#  查询
# ══════════════════════════════════════════════════════════════════════════════

## 当前路线（不存在 → 空字典）。
func current_route() -> Dictionary:
	return ROUTES.get(route_id, {})


## 全部路线（副本）。
func routes() -> Dictionary:
	return ROUTES.duplicate(true)


## 当前等级升到下一级要提交的配方（满级 → 空字典）。
func upgrade_requirement() -> Dictionary:
	return UPGRADE_REQUIREMENTS.get(level, {})


## ★ 出战干员的额外排除目标（`PoolService` 的 `extra_ban_provider` 会调它）。
## **未出战 / 当前路线无 ban_targets ⇒ 空数组**（不注入任何排除）。
func active_bans() -> Array[StringName]:
	if not active:
		return [] as Array[StringName]
	var route := current_route()
	if route.is_empty():
		return [] as Array[StringName]
	var targets: Array = route.get("ban_targets", [])
	var out: Array[StringName] = []
	for t in targets:
		out.append(StringName(t))
	return out


## 是否出战（`set_active` / `toggle_active` 改它）。
func set_active(v: bool) -> void:
	active = v


func toggle_active() -> void:
	active = not active


# ══════════════════════════════════════════════════════════════════════════════
#  路线 / 升级
# ══════════════════════════════════════════════════════════════════════════════

## 切换路线（互斥）。未知 id → false、状态不变。
func select_route(id: StringName) -> bool:
	if not ROUTES.has(id):
		return false
	route_id = id
	return true


## 升级：提交配方物品，等级 +1（不足 → 原子失败）。
func upgrade(state: GameState) -> Dictionary:
	var req := upgrade_requirement()
	if req.is_empty():
		return {"ok": false, "reason": &"max_level", "level": level}

	for k in req.keys():
		var def := ItemCatalog.get_def(StringName(k))
		if def == null:
			return {"ok": false, "reason": &"bad_recipe", "level": level}
		if ItemService.count(def.category, def.quality) < int(req[k]):
			return {"ok": false, "reason": &"missing_items", "level": level}

	var consume_ids: Array[String] = []
	for k in req.keys():
		var def := ItemCatalog.get_def(StringName(k))
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
#  存档形状（★ v0.40：只提供形状，等 10 落地后接上）
# ══════════════════════════════════════════════════════════════════════════════

func to_save_dict() -> Dictionary:
	return {
		"active": active,
		"level": level,
		"route_id": String(route_id),
	}


func from_save_dict(d: Dictionary) -> void:
	active = bool(d.get("active", true))
	level = clampi(int(d.get("level", 1)), 1, MAX_LEVEL)
	route_id = StringName(d.get("route_id", String(&"precision")))


func reset() -> void:
	active = true
	level = 1
	route_id = &"precision"


# ══════════════════════════════════════════════════════════════════════════════
#  效果注入
# ══════════════════════════════════════════════════════════════════════════════

## ★ 把"出战干员的额外排除"注入给 `PoolService`。
## 在 `_ready` 调用一次即可——`PoolService.extra_ban_provider` 是静态回调，
## 池子求值（`_compute`）时会 `call()` 它取当前出战干员的 `active_bans()`。
func _ready() -> void:
	PoolService.extra_ban_provider = Callable(self, "active_bans")

## 仓库系统（★ v0.34 新增，第 12 个系统，`docs/systems/12-warehouse.md`）。
##
## **职责：管理用户的持有物（物品 + 盲盒）——放在哪、放得下吗、怎么取。**
## 数据只有两个来源（用户裁决）：
##   1. **初始化内容**：`initialize(state)` —— 新游戏开局发的内容（当前 = 一个初始盲盒；
##      将来"开局物品"也加在这里）；
##   2. **存档**：`hydrate(state, data)` —— 从 10 的存档把"仓库/邮件里有什么"注入回来
##      （**文件读写仍归 10**，本系统只收"持有的内容"，不碰 save.json 封装）。
##
## ★ **与 02 的边界（本次重构的契约，见 12-warehouse.md §2）**：
##   · 仓库系统（12）**接管**：位置（warehouse / mail）、容量账、领取（claim）；
##   · 02 物品系统**收缩**为：物品定义（`ItemDef`）、实例身份（`ItemInstance`）、发放/销毁；
##   · **迁移是分步的**：本文件先落"数据源"这一半（初始化 + 存档注入），
##     "把 `ItemService` 的 location / capacity / mail / claim 迁到 12"在下一批做
##     （涉及几十条测试与多个系统，必须等 runner 恢复后分步迁移，见 §7 迁移计划）。
##
## 本系统**不定义物品长什么样**（那是 02），**不写 save.json**（那是 10），
## **不画面板**（那是 08 / 11 的页面）。它只回答"这一局的持有物在哪、能不能放下"。
extends Node

## ★ 数据源一：新游戏初始化内容。开局发的初始盲盒（内容归 10 / 内容配置）。
const INITIAL_BOX_SERIES := &"series_01"


## ★ v0.35（W1-a）：**盲盒的仓库占位账**归本系统（从 `ItemService.box_warehouse_used` 迁来）。
##
## 盲盒与物品记进**同一份容量账**（v0.26 口径），但**判定点逐步收敛到本系统**：
##  · 本系统持有"盲盒占位"（`box_used`）；
##  · 物品占位与容量仍暂在 02（`ItemService.warehouse_used` / `warehouse_capacity`），
##   本系统**只读**它们来做盲盒判定（W1 后续刀再把它们整体迁过来）。
var box_used: int = 0

## ★ v0.36（B1）：**物品实例的位置映射**（`instance_id -> location`）。
##
## `location` 从 `ItemInstance` **移出**，变为本系统维护的映射——"这件东西在哪"
## **只有本系统这一份答案**（12-warehouse.md §7 方案 B 的第一步）。
## 键 = `instance_id`（String，与 `ItemInstance.instance_id` 同型）；值 = `StringName`（`LOC_WAREHOUSE` / `LOC_MAIL`）。
## 缺键 = 默认 `warehouse`（与旧 `ItemInstance.location` 的默认值一致，避免"凭空造位置"）。
var locations: Dictionary = {}


## 查询一个实例的当前位置。**缺键返回默认 `warehouse`**（旧实例默认值口径）。
func location_of(instance_id: String) -> StringName:
	return StringName(locations.get(instance_id, String(ItemConstants.LOC_WAREHOUSE)))


## 写入一个实例的位置（**只有"产出落位 / 领取 / 读档还原"可以写**）。
func set_location(instance_id: String, loc: StringName) -> void:
	locations[instance_id] = loc


## 移除一个实例的位置记录（**实例被销毁时**必须清掉，否则映射会泄漏）。
func remove_location(instance_id: String) -> void:
	locations.erase(instance_id)


## 该实例是否在仓库里。
func is_warehouse(instance_id: String) -> bool:
	return location_of(instance_id) == ItemConstants.LOC_WAREHOUSE


## 该实例是否在邮件里。
func is_mail(instance_id: String) -> bool:
	return location_of(instance_id) == ItemConstants.LOC_MAIL


## 清空全部位置映射（新游戏 / 测试重置时由外部调用）。
func reset_locations() -> void:
	locations.clear()


## ★ v0.36（B4）：位置段的存档形状——`{instance_id: "warehouse"|"mail"}`。
## 键序不敏感（字典），但值统一为 String，供 JSON 序列化与字节级稳定。
## 只输出**现存实例**的位置（已销毁实例的位置由 02 在 `_detach` 时移除，不会残留）。
func locations_to_dict() -> Dictionary:
	var out := {}
	for k in locations.keys():
		out[k] = String(locations[k])
	return out


## ★ v0.36（B4）：从存档位置段还原映射。**覆盖式**（调用方已先 `reset_locations()`）。
## 只接受 `warehouse` / `mail` 两种取值，其它一律按缺键处理（默认 warehouse）。
func locations_from_dict(d: Dictionary) -> void:
	for k in d.keys():
		var v := String(d[k])
		if v == String(ItemConstants.LOC_WAREHOUSE) or v == String(ItemConstants.LOC_MAIL):
			locations[k] = StringName(v)


## 盲盒在仓库里占的容量之和（派生值，不入档：载入后由 01 逐个 `place_box()` 重建）。
func box_fits(sz: int = 1) -> bool:
	return ItemService.warehouse_used + box_used + sz <= ItemService.warehouse_capacity


## 给一个新盒子**判定落位**：放得下 → `warehouse`（并记账）；放不下 → `mail`（不记账）。
func place_box(sz: int = 1) -> StringName:
	if box_fits(sz):
		box_used += sz
		return ItemConstants.LOC_WAREHOUSE
	return ItemConstants.LOC_MAIL


## 盒子被摧毁时释放它占的那一份容量。
func release_box(sz: int = 1) -> void:
	box_used = maxi(box_used - sz, 0)


## 领取：把邮件里的盒子搬回仓库（**放得下才搬**）。
func claim_box(sz: int = 1) -> bool:
	if not box_fits(sz):
		return false
	box_used += sz
	return true


## 读档时**按存档里的位置**重建盲盒占位（不重新判定落位）。
func restore_box_occupancy(sz: int = 1) -> void:
	box_used += sz


## 清账（新游戏 / 测试重置时由外部调用）。
func reset_box_usage() -> void:
	box_used = 0


## 初始化一局的持有物（覆盖式，用于"新游戏"）。
## ★ 当前内容 = 一个初始盲盒；开局物品将来也加在这里。
func initialize(state: GameState) -> void:
	if state == null:
		return
	reset_box_usage()
	reset_locations()
	if GachaCatalog.get_series(INITIAL_BOX_SERIES) != null:
		GachaService.grant_box(state, INITIAL_BOX_SERIES, 1, &"init")


## 数据源二：从存档注入持有物。
## ★ **占位实现**：读档归 10；本方法收一份"持有物内容"的字典并据此重建，
##   但**不解释 save.json 的封装**（信封、版本、迁移都归 10）。
##   接上 10 的读档流程后，这里按 `data["warehouse"]` / `data["mail"]` 重建实例与盒子。
func hydrate(state: GameState, data: Dictionary) -> void:
	if state == null:
		return
	# ★ 本版占位：真实注入待 10 的读档流程落地（12-warehouse.md §5 / §7）。
	pass

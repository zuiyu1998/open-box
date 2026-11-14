# 14 · 公司系统

- 上游：`../core-design.md`（**v0.39**：新增第 14 个系统）
- 依赖系统：`01-gacha.md`（盲盒 `Box` / `SeriesDef` / `grant_box`）、`02-item.md`（物品 / 金币余额 / 消耗）、`12-warehouse.md`（盲盒落位）、`10-progression.md`（存档）
- 被依赖：`08` / `11`（公司页）、`01`（买盲盒走 `grant_box`）
- 定位：**"公司几级、走哪条培养路线、产出哪些盲盒、多少钱买"只有这一份答案**。

## 1. 这个系统负责什么

1. **等级**：公司有 `level`（1..`MAX_LEVEL`），升级要提交固定配方（`{item_id: count}`），消耗后 +1。
2. **培养路线**：**互斥**——一次只选一条（`route_id`）；每条路线映射一个**盲盒系列列表**（`series`）与
   每个系列的**金币买价**（`prices`）。
3. **定时产出**：每 `PRODUCTION_INTERVAL`（当前 **1 小时**，用户裁决）自动产 `PRODUCTION_BATCH` 盒盲盒进库存，
   库存有上限 `STOCK_CAP`，满了不产出。
4. **购买**：玩家花**金币**买库存里的盲盒——扣金币（02）→ `GachaService.grant_box`（01 发盒，
   落位走 `WarehouseService.place_box`：放得下进仓库、放不下进邮件）。
5. **数据源（用户裁决）**：等级 / 路线 / 库存 / 时间戳，`to_save_dict()` / `from_save_dict()` 只提供**形状**；
   **存档读写 / 信封 / 版本仍归 `10`**（尚未落地）。
6. **★ v0.39：公司页（MVC 整页代码）归本系统**：`src/company/scenes/company_page.tscn` ＋
   `company_model` / `company_view` / `company_controller` 三个脚本。**视觉规格仍归 08**；11 只负责把场景放进 tab。

## 2. 不负责什么（边界）

| 不归本系统 | 归属 |
|---|---|
| 盲盒**是什么**（`Box` / `SeriesDef` / 池子 / 寿命）与发放（`grant_box`） | `01-gacha.md` |
| 物品**是什么**与实例的创建 / 销毁 / 查询 | `02-item.md` |
| **金币余额的账**（加减、非负、唯一写入方） | `02-item.md` |
| 盲盒**落位**（放得下仓库 / 放不下邮件） | `12-warehouse.md`（`place_box`） |
| 存档文件的读写、信封、版本、迁移 | `10-progression.md` |
| 公司面板长什么样 | `08-ui-panels.md` |

## 3. 数据结构

```gdscript
# res://src/company/company_service.gd —— autoload 单例 CompanyService
const PRODUCTION_INTERVAL := 3600      # ★ 产出周期（用户裁决：1 小时）
const PRODUCTION_BATCH := 1            # 每批产几盒
const STOCK_CAP := 10                  # 库存上限
const MAX_LEVEL := 5                   # 等级上限

# 培养路线（骨架：当前只有 series_01，先内置一条示范路线；将来做内容配置，见 §7 M1）
const ROUTES := {
    &"standard": { "name": "标准线", "series": [&"series_01"], "prices": {&"series_01": 100} },
}
# 升级配方（🔧）：level -> {item_id: count}
const UPGRADE_REQUIREMENTS := { 1: {&"home_q1": 1}, 2: {&"home_q2": 2}, ... }

var level: int = 1
var route_id: StringName = &"standard"
var stock: Array[Dictionary] = []        # {series_id, produced_at}
var last_production_unix: int = 0

func current_route() -> Dictionary
func routes() -> Dictionary
func upgrade_requirement() -> Dictionary
func buy_price(series_id: StringName) -> int
func stock_of(series_id: StringName) -> int
func stock_snapshot() -> Array[Dictionary]
func seconds_until_production(now_unix: int = -1) -> int
func select_route(id: StringName) -> bool
func upgrade(state: GameState) -> Dictionary
func produce(now_unix: int = -1) -> int
func ensure_produced(now_unix: int = -1) -> void
func buy(series_id: StringName, state: GameState) -> Dictionary
func to_save_dict() -> Dictionary
func from_save_dict(d: Dictionary) -> void
func reset() -> void
```

**★ v0.39：场景层（MVC；页面代码归 14，视觉规格归 08）**

```gdscript
# res://src/company/scenes/ —— 公司页
company_page.tscn        # 场景根 CompanyPage（挂 company_view.gd）+ 子节点 Controller
company_model.gd         # class_name CompanyModel extends RefCounted —— 快照 + 升级/买盲盒（走 CompanyService）
company_view.gd          # class_name CompanyView extends VBoxContainer —— 只渲染 + 发 upgrade/buy_requested 信号
company_controller.gd    # class_name CompanyController extends Node —— 连两者
```

## 4. 规则（写死）

- **R14-1 金币账 / 物品账 / 盲盒账都不归本系统**：买盲盒只**发起**扣款（02）与发盒（01），
  不自行加减余额、不缓存余额副本、不自己创建 `Box`。
- **R14-2 培养路线互斥**：`select_route` 一次只存一个 `route_id`；未知路线拒绝、状态不变。
- **R14-3 升级是主动消耗、不足整批拒绝**：配方物品不够 ⇒ 什么都不消耗（走 02 的 `transact`，
  原子）；满级 ⇒ `max_level`。
- **R14-4 定时产出、库存封顶**：`ensure_produced` 惰性按 `PRODUCTION_INTERVAL` 产出；库存 ≥ `STOCK_CAP` 不再产。
- **R14-5 买盲盒原子性边界（裁决 13）**：扣金币（02）与发盒（01）是**两个系统**、不承诺跨系统原子；
  顺序 = 预检 → 扣金币 → 发盒。盲盒是**被动产出**（放不下进邮件、永不丢失），故不存在"扣了钱盒子凭空消失"。
- **R14-6 只上架当前路线产出的系列**：`buy_price(series_id)` 只在 `route.series` 里返回正价，
  其余返回 0（0 = 买不到，不是免费）。

## 5. 接口

| 方向 | 接口 | 说明 |
|---|---|---|
| 08/11 → 14 | `level` / `current_route()` / `routes()` / `stock_snapshot()` / `buy_price()` / `seconds_until_production()` / `upgrade_requirement()` | 公司页取数（**只读**） |
| 14 → 02 | `ItemService.transact([...])` | 升级消耗物品 / 买盲盒扣金币 |
| 14 → 01 | `GachaService.grant_box(state, series_id, 1, &"company")` | 买盲盒发盒 |
| 14 → 全库 | `upgrade()` / `select_route()` / `buy()` | 行为入口 |
| 10 → 14 | `to_save_dict()` / `from_save_dict()` | 存档形状（**本轮不真写盘**，见 §7） |

## 6. 测试点

1. 等级：初始 1；提交配方物品升 1 级、配方被消耗；配方不足 / 满级 ⇒ 失败且不消耗。
2. 路线：默认 `standard`；互斥；未知路线拒绝且状态不变。
3. 产出：首次 `ensure_produced` 产一批；未到 1 小时不产；到点再产；库存封顶 `STOCK_CAP`。
4. 买盲盒：扣金币 + 发盒 + 库存 −1；金币不足 / 无库存 ⇒ 失败且原子。
5. 存档形状：`to_save_dict` / `from_save_dict` 往返一致；缺段 → 默认等级 1 / 默认路线 / 空库存。

（落地：`src/company/tests/test_company_service.gd`，43 条。）

## 7. 待定项

| # | 项 | 现状 |
|---|---|---|
| **M1** | **培养路线做成内容配置** | 当前内置 `ROUTES` 常量（一条示范路线 `standard` → `series_01`）；**将来多系列后改为 `.tres` 内容目录**（与 `ItemCatalog` / `GachaCatalog` 同一纪律） |
| **M2** | **多系列产出策略** | 当前只有 `series_01`，`produce()` 取路线 `series` 第一个；将来按等级 / 路线在多个系列里轮换或解锁 |
| **M3** | **数值标定（🔧）** | `PRODUCTION_INTERVAL`（1h）/ `PRODUCTION_BATCH`（1）/ `STOCK_CAP`（10）/ `MAX_LEVEL`（5）/ 买价（100）/ 升级配方，都是示意值 |
| **M4** | **存档真写盘** | 形状已给；接上 10 时把等级/路线/库存/时间戳并入存档 |
| **M5** | **公司页 UI** | **✅ 已做（v0.39）**：`src/company/scenes/company_page.tscn` ＋ `company_model` / `company_view` / `company_controller`（MVC，与仓库 / 许愿机 / 市场页同构），已接入 `game_screen` 的第四个 tab「公司」。**视觉规格（配色 / 线框）仍归 `08-ui-panels.md`**，当前是功能级 MVP |

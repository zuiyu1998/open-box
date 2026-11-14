# 15 · 干员系统

- 上游：`../core-design.md`（**v0.40**：新增第 15 个系统）
- 依赖系统：`01-gacha.md`（模块 BAN 语义 / 池子求值 `PoolService`）、`02-item.md`（物品 / 升级消耗）、`10-progression.md`（存档）
- 被依赖：`01`（求值经 `extra_ban_provider` 注入）、`08` / `11`（干员页）
- 定位：**"干员出没出战、走哪条养成路线、排除哪些物品"只有这一份答案**。

## 1. 这个系统负责什么

1. **免费 BAN 被动**：干员为许愿机（开盒）提供"类似模块、但无代价"的排除效果——
   **出战（`active`）即生效**，排除当前路线指定的物品（`ban_targets`）。
   效果走与模块 BAN **完全相同的池子求值路径**（40% 蒸发 void、60% 摊回其余物品），
   但**不占盒子槽位、不花金币、不扣寿命**。
2. **养成**：等级（提交配方物品升级）+ **互斥路线**（决定排除哪些物品）。
3. **数据源（用户裁决）**：出战 / 等级 / 路线，`to_save_dict()` / `from_save_dict()` 只提供**形状**；
   **存档读写 / 信封 / 版本仍归 `10`**（尚未落地）。
4. **★ v0.40：干员页（MVC 整页代码）归本系统**：`src/operator/scenes/operator_page.tscn` ＋
   `operator_model` / `operator_view` / `operator_controller` 三个脚本。**视觉规格仍归 08**；11 只负责把场景放进 tab。

## 2. 不负责什么（边界）

| 不归本系统 | 归属 |
|---|---|
| 池子数据的**写入**（`Box.modules` / `item_pool` / 派生状态） | `01-gacha.md`（`PoolService` 是唯一写入方） |
| 概率 / EV / ρ 的**求值** | `07-economy-rho.md`（`EvalService`） |
| 模块本身（`ModuleDef` / `Module`）与其代价 | `01-gacha.md` |
| 物品**是什么**与实例 / 金币账 | `02-item.md` |
| 存档文件的读写、信封、版本、迁移 | `10-progression.md` |

## 3. 数据结构

```gdscript
# res://src/operator/operator_service.gd —— autoload 单例 OperatorService
const MAX_LEVEL := 5

# 养成路线（骨架：互斥；决定排除哪些物品）
const ROUTES := {
    &"precision": { "name": "精准线", "ban_targets": [&"home_q6"] },
}
const UPGRADE_REQUIREMENTS := { 1: {&"home_q1": 1}, 2: {&"home_q2": 2}, ... }

var active: bool = true           # 出战（出战才生效）
var level: int = 1
var route_id: StringName = &"precision"

func current_route() -> Dictionary
func routes() -> Dictionary
func upgrade_requirement() -> Dictionary
func active_bans() -> Array[StringName]   # 出战的排除目标（未出战 → 空）
func set_active(v: bool) -> void
func toggle_active() -> void
func select_route(id: StringName) -> bool
func upgrade(state: GameState) -> Dictionary
func to_save_dict() -> Dictionary
func from_save_dict(d: Dictionary) -> void
func reset() -> void
```

**效果注入（`PoolService` 侧，★ v0.40）**：

```gdscript
# res://src/gacha/pool/pool_service.gd
static var extra_ban_provider: Callable = Callable()   # OperatorService._ready 注入

# _compute_with() 里，模块 BAN 之后：
if extra_ban_provider.is_valid():
    var extra: Array = extra_ban_provider.call()
    for t in extra:
        var tn := StringName(t)
        if w.has(tn) and not banned.has(tn):
            banned.append(tn)
            freed += int(w[tn])    # 走同一条 40% 蒸发 / 60% 摊回路径
```

**★ v0.40：场景层（MVC；页面代码归 15，视觉规格归 08）**

```gdscript
# res://src/operator/scenes/ —— 干员页
operator_page.tscn        # 场景根 OperatorPage（挂 operator_view.gd）+ 子节点 Controller
operator_model.gd         # class_name OperatorModel extends RefCounted —— 快照 + 出战切换/升级
operator_view.gd          # class_name OperatorView extends VBoxContainer —— 只渲染 + 发 toggle/upgrade_requested 信号
operator_controller.gd    # class_name OperatorController extends Node —— 连两者
```

## 4. 规则（写死）

- **R15-1 干员不写池子数据**：效果经 `extra_ban_provider` 注入、在求值时生效，
  **不改 `Box.modules`、不推进 `revision`、不占槽位**（`PoolService` 仍是唯一写入方）。
- **R15-2 出战才生效**：`active == false` ⇒ `active_bans()` 返回空 ⇒ 求值无任何排除。
- **R15-3 无代价**：与模块不同，干员**不花金币、不扣寿命、不需要设备**（它只是被动）。
- **R15-4 养成路线互斥**：`select_route` 一次只存一个 `route_id`；未知路线拒绝、状态不变。
- **R15-5 排除语义与模块 BAN 完全一致**：40% 蒸发 void、60% 摊回，C1 零和恒成立
  （`Σ weights_bp + void_mass_bp == 10000`）。
- **R15-6 升级是主动消耗、不足整批拒绝**：配方物品不够 ⇒ 什么都不消耗（走 02 `transact`，原子）。

## 5. 接口

| 方向 | 接口 | 说明 |
|---|---|---|
| 15 → 01 | `PoolService.extra_ban_provider = Callable(self, "active_bans")` | `_ready` 注入一次 |
| 01 → 15 | `extra_ban_provider.call()` | `_compute` 求值时取出战干员的排除目标 |
| 08/11 → 15 | `active_bans()` / `current_route()` / `routes()` / `level` / `upgrade_requirement()` | 干员页取数（**只读**） |
| 15 → 02 | `ItemService.transact([...])` | 升级消耗配方物品 |
| 10 → 15 | `to_save_dict()` / `from_save_dict()` | 存档形状（**本轮不真写盘**） |

## 6. 测试点

1. 等级：初始 1；提交配方物品升 1 级、配方被消耗；不足 ⇒ 失败且不消耗。
2. 路线：默认 `precision`；互斥；未知路线拒绝。
3. 出战：`active` 开/关 ⇒ `active_bans()` 返回 / 空。
4. **BAN 生效于求值**：出战 ⇒ 目标物品权重归零、`void_mass_bp` 增加（40% 蒸发）、
   `Σ weights_bp + void_mass_bp == 10000`（C1 零和）；未出战 ⇒ 目标物品有基础权重。

（落地：`src/operator/tests/test_operator_service.gd`，19 条。）

## 7. 待定项

| # | 项 | 现状 |
|---|---|---|
| **M1** | **养成路线做成内容配置** | 当前内置 `ROUTES` 常量（一条示范路线 `precision` → `home_q6`）；将来多路线 / 多系列后改为 `.tres` 内容目录 |
| **M2** | **多干员编队 / 出战选择** | 当前单干员（`active` 布尔）；多干员时改为"出战集合" |
| **M3** | **效果只做 BAN** | 干员"类似模块"当前只落 BAN；BOOST / 独立效果留待后续 |
| **M4** | **数值标定（🔧）** | `MAX_LEVEL` / 升级配方 / `ban_targets` 都是示意值 |
| **M5** | **存档真写盘** | 形状已给；接上 10 时把出战/等级/路线并入存档 |
| **M6** | **干员页 UI** | **✅ 已做（v0.40）**：`src/operator/scenes/operator_page.tscn` ＋ `operator_model` / `operator_view` / `operator_controller`（MVC，与仓库 / 许愿机 / 市场 / 公司页同构），已接入 `game_screen` 的第五个 tab「干员」。**视觉规格（配色 / 线框）仍归 `08-ui-panels.md`**，当前是功能级 MVP |

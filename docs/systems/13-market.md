# 13 · 市场系统

- 上游：`../core-design.md`（**v0.38**：新增第 13 个系统，§16.23 之后的下一编号）
- 依赖系统：`02-item.md`（物品定义 / 实例 / 资源余额）、`08-ui-panels.md`（市场面板视觉规格）、`10-progression.md`（存档）
- 被依赖：`08` / `11`（市场页）、`02`（买入产出走 `grant`）
- 定位：**"玩家能买什么、卖什么、花多少、什么时候刷新"只有这一份答案**。

> **★ v0.57 说明（用户裁决：**在市场里用"盲盒生成"造盒**）。** 四条：
> 1. **入口**：市场页底部「生成盲盒」区——**材料下拉**（列仓库物品，标注 `品质 N → 盲盒品质 M`）+ **件数 SpinBox（3–20，默认 8）** + 「生成」按钮 + 结果行。
> 2. **本系统只转发**：`MarketService.generate_box(item_id, count)` → `GachaService.generate_box()`；**品质映射 / 随机池 / 定价一律不在这里重算**（与"不另定买卖价"同一条纪律）。
> 3. **材料不被消耗**（01 的裁决）：市场只借它的**品质**；`item_id` 取自仓库实例，**实例数不变**。
> 4. **结果行必须报出**：盲盒品质 / 件数 / **开盒原石价** / 盒子 id——这三项就是玩家判断"值不值得造"的全部依据。

> **★ v0.64**：待售盒同样遵循"只显示材料"——市场刷新时造盒走的是 `generate_box()`，所以每张卡片买到的盒子，池子里**只有那件被当作材料的物品是显示状态**，其余是隐藏（仍可抽）。见 01 的 v0.64 条。
>
> **★ v0.63（用户裁决：市场页**只卖不收**）**：**删除「卖一件」与「卖盲盒」两个入口**——`SellRow` / `SellBoxRow` 节点、`MarketModel.sell()` / `sell_box()` 与 `_sellable_*` 全部移除；`snapshot()` 不再有 `sell_options` / `sell_disabled` / `sell_box_options` / `sell_box_disabled` 四个键。
> **市场页固定为两段**：在售物品（2 列，每件一个「购买」）→ 待售盲盒（2 列，每张一个「购买盲盒」）+ 结果行。
> `MarketService.sell()` / `sell_box()` **保留在服务层**（13 的系统能力，02/01 的接口契约还在，`test_market_service` 仍覆盖），只是**页面上不再提供入口**。
>
> **★ v0.62（用户裁决：撤销「生成盲盒」入口）**：市场页不再提供"玩家自己用物品造盒"的功能——`generate_box` 入口、材料下拉、件数输入、生成按钮与对应模型方法**全部删除**。
> **保留**：每次刷新 8 个待售盲盒（它们由 01 在刷新时生成，不是玩家操作）与「卖盲盒」。
> 理由（用户裁决）：造盒是**内容/系统侧**的行为，不该成为玩家在市场里的一键产出；市场的职责仍是"买 / 卖"。
>
> **★ v0.61（套系删除）**：市场"待售盲盒"由 `GachaService.generate_box(..., grant=false)` 造，盒子自带品质与开盒价；买价仍按 `sell_price_gold()`（品质表）。**不再有"套系"这一层**。
>
> **★ v0.60（用户裁决：**每次刷新生成 8 个盲盒售卖，每个一个购买按钮**）。** 六条：
> 1. **物品与盲盒并存**：原 6 件物品上架保留，**另加「盲盒」区**——`BOX_SLOTS = 8`，也是一行 2 列、每张卡片一个「购买盲盒」。
> 2. **盲盒从哪来**：刷新时用 `GachaService.generate_box(..., grant = false)` **只造不交付**——它们是**市场库存**，买下才进玩家仓库。
> 3. **买价 = `GachaService.sell_price_gold()`**（品质表 20/50/120/300 金币）；买入 = 扣金币 + 盒子进仓库（放不下进邮件，盒子永不丢失）+ 上架少一张。
> 4. **刷新时未售出的旧盒直接丢弃**（用户裁决）——它们不是玩家的东西，不进清单。
> 5. **池子件数自适应（3…8）**：材料品质越低可用物品越少，按"最多能凑多少"取，否则低品质材料会凑不满而整批少盒。
> 6. **上架盒的模板套系**：01 会为品质 1–4 **兜底创建** `series_auto_q<N>`（确定性 id，读档可复原）；缺模板时该品质的盒子根本造不出来。

> **★ v0.59（用户裁决：市场页卖出区加**卖盲盒**）。** 三条：
> 1. **入口**：`SellBoxRow`——盲盒下拉（`盲盒品质 N · M 件 · 卖 X 金币`）+ 「卖盲盒」按钮，与"卖一件（物品）"并列。
> 2. **只转发**：`MarketService.sell_box(box_id)` → `GachaService.sell_box()`；**卖价一律由 01 的品质表决定**，市场不另定价（与买卖物品同一条纪律）。
> 3. **候选 = 仓库里、卖价 > 0 的盒子**；邮件里的盒子不进候选（不是可用持有）。
>
> **★ v0.58 说明（用户裁决：上架物品改**一行 2 列**，每件一个购买按钮）。** 四条：
> 1. **版面**：`Listings` 单标签 + 一个 `BuyRow`（下拉 + 一个"买一件"）→ **`ScrollContainer` 里的 `GridContainer(columns = 2)`**；每件一张卡片：`名称（品质）` / `价格 · 剩 N 件` / **自己的「购买」按钮**。
> 2. **数据形状**：Model 的 `listing_cards` = `Array[Dictionary]{item_id, name, quality, price, qty}`；**买入入口从"按下标"改为 `buy_item(item_id)`**——卡片按钮直接带 id，不再有"选中项"这一层中间态（少一个可能与视图不一致的状态）。
> 3. **卡片是代码建的**：上架格数 `SLOT_COUNT` 固定但内容随刷新变，静态节点会对不上（与许愿机页"池子表格"同一套路子）；重建时 `remove_child()` + `queue_free()`，避免同帧旧卡还挂着。
> 4. **为什么 2 列**：上架 6 件竖排会把"卖出 / 生成盲盒"挤到屏幕外；2 列让 6 件在一屏内看完，且每件的按钮与它自己那一格绑定，点错的概率更低。

> **★ v0.57 附带修复**：`MarketController` 之前**没有 `bind_state()`**，所以顶层 `GameScreen.refresh()`（切 tab）**不会重渲染市场页**（金币 / 库存 / 生成候选都可能是旧的）。现在补上了，与其它页同形。

## 1. 这个系统负责什么

1. **上架与刷新**：每 `REFRESH_SECONDS`（当前 **6 小时**，用户裁决）从全部**可交易**物品
   （`ItemDef.sell_gold > 0`）里随机抽 `SLOT_COUNT` 个不同的 `item_id` 上架，每格 `STOCK_PER_SLOT` 件。
2. **买入**：玩家花**金币**买入上架物品——买价 = `sell_gold × BUY_PRICE_MULTIPLIER`（当前 ×2）。
   买入 = 一次 `ItemService.transact`（扣金币 + 发实例，同生共死）。
3. **卖出**：转发 `ItemService.sell()`（按 `sell_gold` 换金币）——**本系统不另定卖价、不抽成**。
4. **数据源（用户裁决）**：
   - 上架清单 + 上架时间戳，`to_save_dict()` / `from_save_dict()` 只提供**形状**；
   - **存档文件的读写 / 信封 / 版本仍归 `10`**（尚未落地，见 §7）。
5. **★ v0.38：市场页（MVC 整页代码）归本系统**：`src/market/scenes/market_page.tscn` ＋
   `market_model` / `market_view` / `market_controller` 三个脚本。**视觉规格仍归 08**；11 只负责把场景放进 tab。

## 2. 不负责什么（边界）

| 不归本系统 | 归属 |
|---|---|
| 物品**是什么**（`ItemDef`：类别 / 品质 / 价值 / 权重 / 大小 / `sell_gold`） | `02-item.md` |
| **金币余额的账**（加减、非负、唯一写入方） | `02-item.md`（`ItemService`） |
| 实例的创建 / 销毁 / 查询 | `02-item.md` |
| **卖出价**（`sell_gold` 的数值）与卖出口的实现 | `02-item.md`（`ItemService.sell()`；标定归核心 D26） |
| 存档文件的读写、信封、版本、迁移 | `10-progression.md` |
| 市场面板长什么样 | `08-ui-panels.md` |

## 3. 数据结构

```gdscript
# res://src/market/market_service.gd —— autoload 单例 MarketService
const REFRESH_SECONDS := 6 * 3600      # ★ 刷新周期（用户裁决：暂时 6 小时）
const SLOT_COUNT := 6                   # 上架格数
const STOCK_PER_SLOT := 1               # 每格库存件数
const BUY_PRICE_MULTIPLIER := 2         # 买价 = sell_gold × 2

var listings: Array[Dictionary] = []    # 每格 { item_id, price, qty }
var refreshed_at_unix: int = 0          # 上次上架的 Unix 时间戳

func refresh(seed_override: int = -1, now_unix: int = -1) -> void  # 重抽上架
func ensure_fresh(now_unix: int = -1) -> void                       # 惰性刷新
func listings_snapshot() -> Array[Dictionary]                        # 当前上架（副本）
func stock_of(item_id: StringName) -> int
func buy_price(item_id: StringName) -> int
func seconds_until_refresh(now_unix: int = -1) -> int
func buy(item_id: StringName, count: int = 1) -> Dictionary
func sell(instance_ids: Array[String]) -> Dictionary
func to_save_dict() -> Dictionary
func from_save_dict(d: Dictionary) -> void
func reset() -> void
```

**★ v0.38：场景层（MVC；页面代码归 13，视觉规格归 08）**

```gdscript
# res://src/market/scenes/ —— 市场页
market_page.tscn        # 场景根 MarketPage（挂 market_view.gd）+ 子节点 Controller
market_model.gd         # class_name MarketModel extends RefCounted —— 快照 + 买入/卖出（走 MarketService）
market_view.gd          # class_name MarketView extends VBoxContainer —— 只渲染 + 发 buy/sell_requested 信号
market_controller.gd    # class_name MarketController extends Node —— 连两者
```

## 4. 规则（写死）

- **R13-1 金币账只有一个写入方**：买入只**发起**扣款（`transact` 的 `currency` op），
  **不自行加减余额、不缓存余额副本**（与 04/01 对 02 的同一纪律）。
- **R13-2 买入是主动操作、放不下整笔拒绝**：产出 `source.kind = &"market"`（`ItemConstants.KIND_MARKET`，
  **主动 kind** ⇒ `derive_overflow` 为 `OVERFLOW_REJECT`）。仓库放不下 ⇒ 整笔被拒，
  **金币分文不动、库存不减、无任何实例**——绝不允许"扣了钱、东西进邮件"。
- **R13-3 买入与卖出不对称（差价即抽成）**：买价 = `sell_gold × BUY_PRICE_MULTIPLIER`，
  卖价 = `sell_gold`。**卖出价由 `02` 决定**，本系统**不得另定卖价**。
- **R13-4 只上架可交易物品**：`sell_gold <= 0`（不可售）的物品**永不进抽奖池**——
  否则会出现"0 价可买"或"买价 0 = 免费送"。
- **R13-5 上架确定、不放回**：一次刷新抽 `SLOT_COUNT` 个**互不相同**的 `item_id`
  （可交易物品不足 `SLOT_COUNT` 时抽全部）；私有 RNG 不碰全局 RNG（测试可注入 seed）。

## 5. 接口

| 方向 | 接口 | 说明 |
|---|---|---|
| 08/11 → 13 | `listings_snapshot()` / `buy_price(id)` / `stock_of(id)` / `seconds_until_refresh()` | 市场页取数（**只读**） |
| 13 → 02 | `ItemService.transact([...])` / `ItemService.sell(ids)` | 买入扣款+发实例 / 卖出换金币 |
| 13 → 全库 | `buy()` / `sell()` | 买卖入口 |
| 10 → 13 | `to_save_dict()` / `from_save_dict()` | 存档形状（**本轮不真写盘**，见 §7） |

## 6. 测试点

1. 刷新：从可交易物品抽 `SLOT_COUNT` 个**互不相同**的 item_id；`sell_gold == 0` 的物品不上架。
2. 确定性：`refresh(seed)` 两次同 seed 结果逐项相同。
3. 惰性刷新：距上次上架 ≥ 6 小时自动重抽；未到点时间戳不变。
4. 买入：扣金币 + 发实例 + 库存 −1；新实例 `source.kind == market`。
5. 买入原子性：金币不足 / 仓库满 ⇒ 整笔失败，金币、库存、实例全不变。
6. 售罄：库存归零后 `buy` 报 `sold_out`。
7. 卖出：转发 `ItemService.sell()`，卖价 = `sell_gold`。
8. 存档形状：`to_save_dict` / `from_save_dict` 往返一致；缺段 → 空上架。

（落地：`src/market/tests/test_market_service.gd`，282 条。）

## 7. 待定项

| # | 项 | 现状 |
|---|---|---|
| **M1** | **存档真写盘** | 形状已给（`to_save_dict` / `from_save_dict`），但系统 10（存档层）尚未落地——**接上 10 时把 `listings` + `refreshed_at_unix` 并入存档**，刷新时间戳须跨会话保留 |
| **M2** | **数值标定（🔧）** | `REFRESH_SECONDS`（6h）/ `SLOT_COUNT`（6）/ `STOCK_PER_SLOT`（1）/ `BUY_PRICE_MULTIPLIER`（×2）都是示意值，须与 `sell_gold`（D26）、金币供给（D25）一起标定 |
| **M3** | **刷新是否影响已售罄格** | 当前"刷新 = 整批重抽"，已售罄格在下次刷新前保持空；是否"售罄格提前补货"未裁决 |
| **M4** | **市场页 UI** | **✅ 已做（v0.38）**：`src/market/scenes/market_page.tscn` ＋ `market_model` / `market_view` / `market_controller`（MVC，与仓库页 / 许愿机页同构），已接入 `game_screen` 的第三个 tab「市场」。**视觉规格（配色 / 线框）仍归 `08-ui-panels.md`**，当前是功能级 MVP |

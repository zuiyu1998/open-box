# 12 · 仓库系统

- 上游：`../core-design.md`（**v0.34**：新增第 12 个系统，§16.23）
- 依赖系统：`02-item.md`（物品定义 / 实例身份）、`01-gacha.md`（盲盒）、`10-progression.md`（存档）
- 被依赖：`03`（需求匹配读持有量）、`08` / `11`（仓库页）、`01`（发盒的落位判定）
- 定位：**"用户的持有物放在哪、放得下吗、怎么取"只有这一份答案**。

## 1. 这个系统负责什么

1. **持有物（物品 + 盲盒）的位置管理**：`warehouse` / `mail` 两个位置。
2. **容量账**：仓库容量与已用（物品 `size` 之和 ＋ 盲盒每盒 1 单位，v0.26 口径）——**判定点只有一个**。
3. **领取**：邮件 → 仓库（放得下才搬、部分成功）。
4. **数据源（用户裁决）**：
   - **初始化内容**：`WarehouseService.initialize(state)`——新游戏开局发的持有物（当前 = 一个初始盲盒）；
   - **存档**：`WarehouseService.hydrate(state, data)`——从 10 的存档注入"仓库/邮件里有什么"。

## 2. 不负责什么（边界）

| 不归本系统 | 归属 |
|---|---|
| 物品**是什么**（`ItemDef`：类别/品质/价值/权重/大小/售价） | `02-item.md` |
| 实例**身份**（`instance_id` / `serial` / `source`）与发放/销毁 | `02-item.md` |
| 盲盒的池子/模块/寿命（`Box` 的业务字段） | `01-gacha.md` |
| 存档文件的读写、信封、版本、迁移 | `10-progression.md` |
| 仓库面板长什么样 | `08-ui-panels.md` / `11-flow.md` 的 `warehouse_page` |

## 3. 数据结构

```gdscript
# res://src/warehouse/warehouse_service.gd —— autoload 单例 WarehouseService
const INITIAL_BOX_SERIES := &"series_01"

func initialize(state) -> void   # 数据源一：初始化内容
func hydrate(state, data) -> void  # 数据源二：从存档注入（占位）
```

## 4. 规则（写死）

- **R12-1 数据只有两个来源**：初始化内容 / 存档注入。**任何其它地方不得"凭空造持有物"**。
- **R12-2 容量只有一个判定点**：物品与盲盒记进同一份容量账（v0.26），别处不得自算。
- **R12-3 不碰存档封装**：`hydrate()` 只收"内容字典"，**不读 save.json、不解释版本号/迁移**（归 10）。

## 5. 接口

| 方向 | 接口 | 说明 |
|---|---|---|
| 11 → 12 | `initialize(state)` | 新游戏初始化持有物（`GameSession.start_new_game()` 里调用） |
| 10 → 12 | `hydrate(state, data)` | 读档时注入持有物（**占位**，待 10 读档流程落地） |
| 12 → 全库 | 位置 / 容量 / 领取的查询与写入（**迁移后**） | 见 §7 |

## 6. 测试点

1. `initialize()` 新游戏 ⇒ 仓库里恰好 1 个初始盲盒（`series_01`、`warehouse`）。
2. `hydrate()` 是**占位**：本版不崩、不产生副作用（真实注入待 10）。
3. 边界：`initialize(null)` 不崩。

## 7. 待定项 / 迁移计划

| # | 项 | 现状 |
|---|---|---|
| **W1-a** | **盲盒容量账（`box_used` + `place_box/release_box/claim_box/restore_box_occupancy/box_fits`）迁到 12** | **✅ 已完成（v0.35）**：`WarehouseService` 持有盲盒占位并做盲盒判定/记账；`ItemService` / `gacha_service` / `game_state` 改为委托/只读 `WarehouseService.box_used`。1207 条测试全绿。**注意**：物品占位（`warehouse_used`）与容量（`warehouse_capacity`）**仍暂在 02**，12 的 `box_fits` 只读它们——容量账当前是"盲盒在 12、物品在 02"的过渡态 |
| **W1-b** | **领取（claim/claim_all/mail_instances/query/count 位置口径）迁到 12** | **未做**：领取要遍历/改 `ItemInstance.location` 并更新 02 的 `count_index`，而实例列表在 02 —— 涉及"位置字段 + 实例列表 + 聚合缓存"三者的归属决策（见下） |
| **W1-c** | **transact 落位预演委托 12（原子性）** | **未做**：`transact` 的"扣资源 + 销毁 + 发放 + 落位"要原子，落位判定与容量预演迁到 12 需 12 暴露"预演/回滚"接口，横跨两服务 |
| **W2** | `hydrate()` 的真实实现（从存档重建实例与盒子） | 占位；依赖 10 的读档流程与存档 schema 定型 |
| **W3** | "开局物品"（除盲盒外，是否再发若干物品） | 未定；内容归 10/内容配置，加在 `initialize()` 里即可 |

**W1-b/c 的设计决策点（需拍板后再动）：** "位置"这个语义的归属有三种切法——
① `location` 字段留在 `ItemInstance`（02 拥有、随存档序列化），**读写权**归 12（02 只提供实例遍历/查找，位置变更一律走 12）；② 实例列表整体搬到 12，02 退化为"物品定义 + 实例工厂"；③ 位置仍是 02 的，12 只做"领取/容量的**门面**"（这与"仓库接管位置"的裁决相悖，不推荐）。
推荐 **①**：字段留 02、读写权归 12，最贴合"02 管身份、12 管位置"的边界，且存档字段不动。

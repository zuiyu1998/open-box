# 12 · 仓库系统

- 上游：`../core-design.md`（**v0.34**：新增第 12 个系统，§16.23）
- 依赖系统：`02-item.md`（物品定义 / 实例身份）、`01-gacha.md`（盲盒）、`10-progression.md`（存档）
- 被依赖：`03`（需求匹配读持有量）、`08` / `11`（仓库页）、`01`（发盒的落位判定）
- 定位：**"用户的持有物放在哪、放得下吗、怎么取"只有这一份答案**。

## 1. 这个系统负责什么

1. **持有物（物品 + 盲盒）的位置管理**：`warehouse` / `mail` 两个位置。
   **★ v0.36：物品的位置账就是本系统的 `locations`（`instance_id -> location`）**——`ItemInstance` 不再携带 `location`（B2），"这件东西在哪"全库只有这一份答案。
2. **容量账**：仓库容量与已用（物品 `size` 之和 ＋ 盲盒每盒 1 单位，v0.26 口径）——**判定点只有一个**。
3. **领取**：邮件 → 仓库（放得下才搬、部分成功）。
4. **数据源（用户裁决）**：
   - **初始化内容**：`WarehouseService.initialize(state)`——新游戏开局发的持有物（当前 = 一个初始盲盒）；
   - **存档**：`WarehouseService.hydrate(state, data)`——从 10 的存档注入"仓库/邮件里有什么"。

## 2. 不负责什么（边界）

| 不归本系统 | 归属 |
|---|---|
| 物品**是什么**（`ItemDef`：类别/品质/价值/权重/大小/售价） | `02-item.md` |
| 实例**身份**（`instance_id` / `serial` / `source`）、**实例列表本身**与发放/销毁 | `02-item.md` |
| 物品的**位置**（`warehouse` / `mail`）——**★ v0.36：已从 02 迁入本系统**（`locations` 映射） | **本系统**（`02` 只调 `WarehouseService.location_of()` 等查询） |
| 盲盒的池子/模块/寿命（`Box` 的业务字段） | `01-gacha.md` |
| 存档文件的读写、信封、版本、迁移 | `10-progression.md` |
| 仓库面板长什么样 | `08-ui-panels.md` / `11-flow.md` 的 `warehouse_page` |

## 3. 数据结构

```gdscript
# res://src/warehouse/warehouse_service.gd —— autoload 单例 WarehouseService
const INITIAL_BOX_SERIES := &"series_01"

func initialize(state) -> void   # 数据源一：初始化内容
func hydrate(state, data) -> void  # 数据源二：从存档注入（占位）

# ★ v0.36（B 重构）：物品实例的位置账（`instance_id -> location`）——"在哪"只有这一份答案
var locations: Dictionary = {}
func location_of(id: String) -> StringName      # 缺键回默认 warehouse
func set_location(id: String, loc: StringName) -> void   # 只有落位 / 领取 / 读档还原能写
func remove_location(id: String) -> void         # 实例销毁时必须清（防映射泄漏）
func is_warehouse(id: String) -> bool
func is_mail(id: String) -> bool
func reset_locations() -> void
func locations_to_dict() -> Dictionary           # 存档位置段
func locations_from_dict(d: Dictionary) -> void  # 读档还原（只认 warehouse / mail）
```

## 4. 规则（写死）

- **R12-1 数据只有两个来源**：初始化内容 / 存档注入。**任何其它地方不得"凭空造持有物"**。
- **R12-2 容量只有一个判定点**：物品与盲盒记进同一份容量账（v0.26），别处不得自算。
- **R12-3 不碰存档封装**：`hydrate()` 只收"内容字典"，**不读 save.json、不解释版本号/迁移**（归 10）。
- **R12-4 物品位置只有这一份账（v0.36）**：`WarehouseService.locations` 是 `warehouse` / `mail` 的**唯一事实来源**。
  `ItemInstance` **不再携带 `location`**（B2）；任何系统读位置必须调 `location_of()` / `is_warehouse()` / `is_mail()`，
  **不得缓存副本、不得自行推断**。**实例销毁时必须 `remove_location()`**（02 的 `_detach` 已内建），否则映射泄漏。

## 5. 接口

| 方向 | 接口 | 说明 |
|---|---|---|
| 11 → 12 | `initialize(state)` | 新游戏初始化持有物（`GameSession.start_new_game()` 里调用；**同时清空 `locations`**） |
| 10 → 12 | `hydrate(state, data)` | 读档时注入持有物（**占位**，待 10 读档流程落地） |
| 12 → 02 | `location_of(id)` / `set_location(id, loc)` / `remove_location(id)` / `is_warehouse(id)` / `is_mail(id)` | **★ v0.36（B3）**：`ItemService` 的位置读写全走这五个方法（落位 / 领取 / 销毁清账） |
| 12 → 10 | `locations_to_dict()` / `locations_from_dict(d)` | **★ v0.36（B4）**：存档位置段（`{id: "warehouse"\|"mail"}`）；`ItemService.to_save_dict()` 把它并入 `inventory` 块 |

## 6. 测试点

1. `initialize()` 新游戏 ⇒ 仓库里恰好 1 个初始盲盒（`series_01`、`warehouse`）；`locations` 为空。
2. `hydrate()` 是**占位**：本版不崩、不产生副作用（真实注入待 10）。
3. 边界：`initialize(null)` 不崩。
4. **★ v0.36（B6）**：`ItemService` 全部位置断言（落位 / 领取 / 邮件 / 容量）走 `WarehouseService.location_of()` 等口径——
   全库 1259 条测试全绿（含 `src/warehouse/tests/` 的 52 条 B 重构专项断言）；`_state_snapshot` 含 `locations` 段，因此"事务失败 ⇒ 位置零变化"可被断言。
5. **★ v0.36（B4）**：`to_save_dict()` → JSON → `from_save_dict()` 往返字节级稳定，且 `locations` 段随 `inventory` 块往返。

## 7. 待定项 / 迁移计划

| # | 项 | 现状 |
|---|---|---|
| **W1-a** | **盲盒容量账（`box_used` + `place_box/release_box/claim_box/restore_box_occupancy/box_fits`）迁到 12** | **✅ 已完成（v0.35）**：`WarehouseService` 持有盲盒占位并做盲盒判定/记账；`ItemService` / `gacha_service` / `game_state` 改为委托/只读 `WarehouseService.box_used`。1259 条测试全绿。**注意**：物品占位（`warehouse_used`）与容量（`warehouse_capacity`）**仍暂在 02**，12 的 `box_fits` 只读它们——容量账当前是"盲盒在 12、物品在 02"的过渡态 |
| **W1-b** | **领取（claim/claim_all/mail_instances/query/count 位置口径）迁到 12** | **✅ 已完成（v0.36，B1–B3）**：`location` 从 `ItemInstance` 移出 ⇒ `WarehouseService.locations`（`instance_id -> location`）；`ItemService` 的 `_move` / `_attach` / `_detach` / `grant` / `transact` / `sell` / `claim` / `mail_instances` / `query` / `rebuild_count_index` 一律经 `WarehouseService.location_of()` / `is_warehouse()` / `is_mail()` 读写。**实例列表与 `count_index` 仍归 02**（它们不是"位置"，是"有什么"与"数几个"）——位置账与实例账因此分开、各只有一份 |
| **W1-c** | **transact 落位预演委托 12（原子性）** | **✅ 已完成（v0.36，B5）**：`transact` 的 grant-op 落位经 `WarehouseService.set_location()`；它本就是"全面预校验 → 预演落位 → 再生效"，**失败路径不写任何状态，因此不需要回滚能力**。容量预演仍读 02 的 `warehouse_used` / `warehouse_capacity`（物品容量暂在 02 的过渡态，见 W1-a） |
| **W2** | `hydrate()` 的真实实现（从存档重建实例与盒子） | 占位；依赖 10 的读档流程与存档 schema 定型 |
| **W3** | "开局物品"（除盲盒外，是否再发若干物品） | 未定；内容归 10/内容配置，加在 `initialize()` 里即可 |

**W1-b/c 的设计决策点（已裁决：方案 B，真迁移）。** `location` 从 `ItemInstance` **移出**，变为本系统维护的 `instance_id → location` 映射（`WarehouseService.locations`）。**分步计划（每步可编译可回归）：**

| 步 | 动作 | 波及 | 状态 |
|---|---|---|---|
| **B1** | `WarehouseService` 加 `locations: Dictionary` + `location_of(id)` / `set_location(id, loc)` / `remove_location(id)` / `is_warehouse(id)` / `is_mail(id)` / `reset_locations()` | 仓库系统 | **✅ v0.36** |
| **B2** | `ItemInstance` 删 `location` 字段与 `is_in_warehouse()` / `is_in_mail()`；`to_dict`/`from_dict` 删 `location` 键 | 02 定义 | **✅ v0.36** |
| **B3** | `ItemService` 全部 `inst.location` / `is_in_*` 改为 `WarehouseService.location_of(inst.instance_id)` 等；`_move`/`_attach`/`_detach`/`grant`/`transact`/`sell`/`claim`/`mail_instances`/`query`/`rebuild_count_index` 适配；`_detach` 时清位置映射 | 02 核心 | **✅ v0.36** |
| **B4** | 存档：`location` 从实例序列化移除，改由 `WarehouseService` 输出独立段（`locations: {id: loc}`） | 10 / 存档 schema | **✅ v0.36（落地边界见下）** |
| **B5** | `transact` 落位/回滚经 12（原子性） | 02 ↔ 12 | **✅ v0.36**（随 B3：grant-op 落位经 `WarehouseService.set_location`；`transact` 本就"全面预校验 → 再生效"，失败路径无需回滚） |
| **B6** | `test_item_system` 几十条位置/领取/邮件/容量断言迁移到 12 口径 | 测试 | **✅ v0.36**（`_state_snapshot` 加入 `locations` 段；新增 `src/warehouse/tests/test_warehouse_service.gd`（52 条），全库 1259 条测试全绿） |

> **B4 的落地边界（本次实现口径）**：系统 10（存档层 / `save.json` 封装 / 版本迁移）**在代码里尚未落地**（`src/flow/session.gd` 的 `has_save()` / `load()` 仍是占位，全库没有 `SaveService` / `ProgressionService`）。因此本次 B4 **不新建 10 的存档文件系统、不实现 v7 迁移函数**；只把"位置不再随实例序列化、由 12 输出独立 `locations` 段"这一**形状**落在 `ItemService.to_save_dict()` / `from_save_dict()` 上（该字典就是 10 将来落盘的 `inventory` 块）。`from_save_dict` 对缺 `locations` 段的旧档一律回填默认 `warehouse`。**"存档升 v7 + `migrate_v6_to_v7()`" 留待 10 落地时接上**——那时的迁移只需读旧档实例里的 `location` 键写入 12 的映射。

**注意**：`Box.location`（v0.26 加的）暂留 `Box` 上——它随 `Box` 序列化、容量账已在 12（W1-a），B 的目标是**物品实例**的位置；Box 位置是否同迁留待 B 完成后另行评估。

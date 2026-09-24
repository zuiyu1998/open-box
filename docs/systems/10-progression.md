# 10 · 收集与进度系统

- 上游：`../core-design.md` v0.6 ／ `README.md`
- 依赖系统：07 数值与期望（ρ 区间判定，只读）、01 盲盒（抽取结果、保底计数、未拥有款权重）、03 任务（里程碑任务的需求与奖励结算）、05 模块与池子（`PoolState` 快照）、02 物资（类别定义）
- 被依赖：01（「未拥有款」判定）、05（模块品质产出权限）、02 / 06（物资类别开关）、03（里程碑可见性）、08（图鉴与套系进度呈现）

> **本系统是 R11 的落点。** ρ 的成长**只能**来自内容释放（核心 §2.4），而内容释放的**发放动作**归本系统。因此：**内容产能是进度的唯一来源，本系统直接决定产品节奏**——内容跟不上 → 解锁链无货可发 → 进度停滞 → 玩家流失。本系统的设计目标是让"内容释放"成为**可配置数据**（§6），而不是手写代码。

> **v0.6 同步（本系统新增一条进度轴）**：镶嵌位数与装置槽位数改由**套系品质 `series_quality`** 决定（核心 §4.1.1 / C4），**解锁更高品质的套系因此成为一条新的主动进度轴**，其发放动作归本系统：新增载荷 `SERIES_QUALITY_UNLOCK`（§1 第 4 条 / §5 第 5 条），并新增持久化集合 `unlocked_series_qualities`（§4）。
> P7 的要害随之收敛为一条区分：**同一套系内不得增额；跨套系（解锁更高品质套系）是合法的、也是唯一的功率成长路径**（§5 第 10 条）。

## 1. 这个系统负责什么

1. **图鉴 `Codex`**：每款 `Item` 的收录状态（已收录 / 未收录 / 重复次数），以及**缺口可见性**。核心 §1.1 把「图鉴」列为"获取物资"这一步的系统职责；"**缺口的半衰期是周**"出自 `../archive/core-design-v0.1.md` §1.3（v0.5 §16「继承不变」未废止），本系统据此把**缺口可见性**定为硬要求（§9）。
2. **套系进度 `series_progress`**：单个套系的完成度，**常规 `regular_count` 款 + 1 隐藏分别计**（`regular_count` 由该套系的**套系品质**决定，8 或 12，核心 §4.1.1；分开计的理由见 §5 第 3 条）。
3. **里程碑任务链 `milestone_chain`**：链骨架（顺序、前置、解锁载荷、预告）的定义与发放。**谁定义、谁发奖励的裁决见 §8.1。**
4. **解锁发放 `grant_unlock()`**：新套系 / 新物资类别 / **更强模块的产出权限**（核心 §4.3）/ **套系品质解锁 `SERIES_QUALITY_UNLOCK`**（核心 v0.6 §4.1.1）。其中模块品质的释放节奏即 **D13**（R11 的核心载体）；**套系品质解锁决定"玩家最高能施工到什么档位"**，是 v0.6 新增的**唯一功率成长路径**（P7，§5 第 10 条）。
5. **全收集判定与终局表现**（核心 §10.1 / §10.2）；**存档结构**：`user://` JSON 的完整 schema、`pool_snapshot` / `state_snapshot` / 保底计数 / 开箱日志（seed + 结果）；**进度节奏表**：把核心 §10.2 的五阶段落成可配置数据（§6.2）。

## 2. 不负责什么（边界）

| 不负责 | 见 |
|---|---|
| 任务的需求向量匹配、奖励结算、需求随进度变宽 | `03-task.md` |
| 抽取判定 `roll()`、保底触发、未拥有款权重 ×1.5 的**计算** | `01-gacha.md` |
| `PoolState` 的结构（含 `void_mass`）与排除 / 提升 / 损耗 / 零和；ρ / M̄ / D̄ / B / σ 与 `void_prob` 的计算口径、归因分解 | `05-module-pool.md` / `07-economy-rho.md` |
| 物资类别与品质定义、堆叠、重复款转数量 | `02-material.md` |
| 装置槽位与转化端修正；转化表与损耗结算；面板布局、展开入口与 `headline` 渲染；开箱演出（含 `void` 的呈现） | `04-device.md` / `06-conversion.md` / `08-ui-panels.md` / `09-presentation.md` |
| **解锁发放之后的各系统行为**（解锁新套系后 01 怎么建池、解锁品质后 05 怎么造模块） | 各系统自己负责 |

**本系统的唯一写权限是"解锁发放"与"图鉴 / 套系进度 / 存档布局"。** 一切"解锁之后会怎样"都不在本系统内实现：本系统只把 `unlocked_*` 标志位、`unlocked_series_qualities` 与 `module_quality_ceiling` 放进共享状态，由对端读取（§8.2）。**位次本身永远不由本系统写入**（P7，§5 第 10 条）。

## 3. 核心概念与术语

沿用 `README.md` §5：套系 `Series`、款 / 物品 `Item`、池子 `Pool`、池子状态 `PoolState`、镶嵌位 `socket_slot`、隐藏款 `hidden`、保底 `pity`、任务 `Task`、物资 `Material`、类别 `category`、品质 `quality`、闭环收益率 `rho`。本系统新增的**落地命名**（核心文档只给概念，未给字符名）：

| 中文名 | 代码名 | 说明 |
|---|---|---|
| 图鉴 | `Codex` | 全部款与收录状态的集合 |
| 缺口 | `gap` / `gap_count` | 未收录的款 / 其数量 |
| 空洞 | `void` / `void_mass` | 排除损耗产生的**零价值结果**，**不是一款**（不计入 N）；求值与损耗写入见 `07-economy-rho.md` §5.4 / `05-module-pool.md` §5.4 |
| 套系进度 | `series_progress` | 单套系完成度，常规与隐藏分列 |
| 里程碑 | `MilestoneDef` | 里程碑任务链的一个节点 |
| 解锁载荷 | `UnlockPayload` | 里程碑发放的内容释放项 |
| 模块品质天花板 | `module_quality_ceiling` | 当前允许产出的模块品质上限 |
| 全收集 | `full_collection` | 已释放套系全部款收录 |
| 开箱日志 | `draw_log` | 每次兑现的 `{seed, pool_snapshot, state_snapshot, item_id, star}`（核心 §14.2 铁律 7） |
| 进度阶段 | `ProgressPhase` | 核心 §10.2 五阶段之一 |
| 套系品质 | `series_quality` | 套系（池子）的品质档位 1–4，**决定该套系的常规款数、镶嵌位数、装置槽位数与产出物资的品质区间**；核心 §4.1.1 |
| 已解锁套系品质 | `unlocked_series_qualities` | 玩家已解锁的品质档位集合；**其最大值 = 玩家最高能施工到的档位**（P7，§5 第 10 条） |

### 3.1 术语纪律：「品质」有两个含义（v0.6 新增）

**本系统两者都会出现，必须可分辨。**

| 写法（一律写全） | 代码名 | 含义 | 出处 |
|---|---|---|---|
| **物资品质** | `quality` | 物资的等级维度，1–5 序数 | `02-material.md` |
| **套系品质** | `series_quality` | 套系 / 池子的品质档位，1–4 | 核心 §4.1.1 |

**规则：本系统中孤立的"品质"二字视为歧义**——凡涉及两者之一，一律写全"物资品质"或"套系品质"。
二者**不是同一把尺子上的两个刻度、也无换算关系**：套系品质**决定**该套系产出物资的品质**区间**；物资品质只影响任务贡献度与作为装置/模块素材时的强度（核心 §4.2）。

## 4. 数据结构（GDScript Resource 字段定义）

```gdscript
# 下列各段各自落在其注释标注的文件中
# res://data/defs/unlock_payload.gd —— 内容释放的一项
class_name UnlockPayload
extends Resource
enum Kind { SERIES, MATERIAL_CATEGORY, MODULE_QUALITY, SERIES_QUALITY_UNLOCK }
# SERIES = 新套系 / MATERIAL_CATEGORY = 新物资类别 / MODULE_QUALITY = 更强模块的产出权限（D13）
# SERIES_QUALITY_UNLOCK = v0.6 新增：解锁一个更高品质的套系（核心 §4.1.1）
@export var kind: Kind = Kind.SERIES
@export var target_id: StringName          # series_id / category；MODULE_QUALITY 时留空
@export var magnitude: int = 1             # MODULE_QUALITY：提升到第几档模块品质；SERIES_QUALITY_UNLOCK：该套系的 series_quality（1–4）

# res://data/defs/milestone_def.gd —— 里程碑任务链的节点
class_name MilestoneDef
extends Resource
@export var id: StringName
@export var display_name: String
@export var order_index: int = 0
@export var requires: Array[StringName] = []      # 前置里程碑 id
@export var task_def_id: StringName               # 指向 TaskDef；需求与奖励结算归 03（§8.1）
@export var unlocks: Array[UnlockPayload] = []    # 内容释放载荷，归本系统发放
@export_multiline var teaser: String = ""         # 未达成时的预告（R11 可感知性，§9）

# res://data/defs/milestone_chain_def.gd
class_name MilestoneChainDef
extends Resource
@export var nodes: Array[MilestoneDef] = []

# res://data/progression/progression_phase_def.gd —— 核心 §10.2 五阶段的数据化
class_name ProgressionPhaseDef
extends Resource
@export var phase_id: StringName            # opening / breakthrough / takeoff / engineering / endgame
@export var display_name: String
@export var rho_min: float = 0.0            # 含
@export var rho_max: float = 0.0            # 不含；0.0 表示无上界
@export var pool_state_note: String = ""    # 只作文案呈现，不得参与任何计算
@export var collection_note: String = ""
@export var expect_unlock_kinds: Array[StringName] = []   # 本阶段预期释放的内容类型（节奏校验用）
@export var expect_max_series_quality: int = 1            # v0.6：本阶段玩家最高可施工到的套系品质，决定 ρ 上限；只作节奏校验与验收对照，不参与计算

# 运行时状态（由 GameState 持有，SaveService 持久化）
class_name ProgressionState
extends RefCounted
var collected: Dictionary = {}             # {series_id: {item_id: true}}   —— 图鉴
var duplicate_count: Dictionary = {}       # {series_id: {item_id: int}}
var unlocked_series: Array[StringName] = []
var unlocked_material_categories: Array[StringName] = []
var unlocked_series_qualities: Array[int] = []   # v0.6 新增：已解锁的套系品质档位集合，升序去重；max() = 最高可施工档位（P7）
var module_quality_ceiling: int = 1        # 初始 1 档；只增不减
var granted_unlock_ids: Dictionary = {}    # 发放幂等键
var milestone_state: Dictionary = {}       # {milestone_id: int} —— 见 §7.2
var full_collection_reached: bool = false
var current_phase: StringName = &"opening"

# 开箱日志条目（核心 §14.2 铁律 7）
class_name DrawLogEntry
extends RefCounted
var seq: int = 0
var seed: int = 0
var series_id: StringName
var pool_snapshot: Dictionary = {}   # {regular_count, revision, series_quality, socket_count, socketed, void_mass, weights_bp}，即 05 §4 的 PoolState 冻结副本
var state_snapshot: Dictionary = {}  # {m_bar, d_bar, b, rho}
var is_void: bool = false            # `[补充]` void 结果的显式标记（对齐 09 的 Result.is_void），避免靠空 item_id 反推
var item_id: StringName              # `void` 时为空 StringName（哨兵）；见 §5 第 1 条
var star: int = 1
```

**持久化口径（`[补充]`）**：所有权重与 `void_mass` 落盘为**整数万分比**（`weights_bp` / `void_mass`，1 bp = 0.01%）。理由：用户要求的"存 → 读 → 存字节级稳定"必须规避浮点格式化漂移与键序抖动；`PoolState` 的**结构与求值口径**仍归 `05-module-pool.md` / `07-economy-rho.md`（其 `void_mass` 为运行时 float），本系统只定义其**持久化布局**。
**`state_snapshot` 的最小字段集（`[补充]`）**：`{m_bar, d_bar, b, rho}`。理由：核心 §14.2 铁律 7 只要求"记录 state_snapshot"而未规定内容；这四个量是 `EvalService` 的全部输出标量，足以让任意历史开箱的归因可复算（P2）。
**`pool_snapshot` 的规模字段（v0.6 新增）**：每个 `pool_snapshot` / `pools` 条目额外冻结 `regular_count`（该套系常规款数）与 `series_quality`。理由：v0.6 中**位子数与池子规模都随套系品质变化**，读档时若不带上这两个值，就**无法校验位子数与池子规模是否仍等于其 `SeriesDef`**（T4 / T11），只能靠 `weights_bp` 的键数反推——而反推在 C6 的极值池上不可靠。二者是 `SeriesDef` 值的**冻结副本**，只读、不参与求值。
**`unlocked_series_qualities` 的持久化（v0.6 新增）**：以**整数数组**落盘（升序去重）。理由：读档后必须能**还原"玩家最高能施工到什么档位"**（P7）；该值**不得**由 `unlocked_series` 或 `module_quality_ceiling` 推导——它是一条独立的进度轴（§5 第 10 条）。

### 4.1 存档 JSON schema 示例（`user://save.json`）

键序为**字母序**（canonical 序列化，保证往返字节级稳定）。示例为**已镶嵌 1 个排除模块**的池子（排除 `s01_05`）：该套系为**套系品质 2**（`series_quality = 2` → 8 常规款 / 3 镶嵌位，核心 §4.1.1），其释放质量 1225 bp 中 40% 落为 `void`（`void_mass = 490`，即 4.90%），其余 60%（735 bp）按基础权重摊回剩下 7 款（各 +105 → 1330 bp）。故 `Σ 常规 9310 + void_mass 490 + 隐藏 200 == 10000 bp`（`README.md` §6.1）；`void_mass` 与 `weights_bp` 同单位、同精度。
`"schema_version": 2`（`[补充]`：v0.6 新增了 `series_quality` / `regular_count` / `unlocked_series_qualities` 三个字段，按 §7.4 约定必须递增版本，故示例即 v2；v1 档的迁移见 T3）。

```json
{
  "draw_log": [
    { "is_void": false, "item_id": "s01_02", "seed": 918273645, "seq": 1, "series_id": "series_01", "star": 3,
      "state_snapshot": { "b": 2.0, "d_bar": 12.0, "m_bar": 3.24, "rho": 0.54 }, "pool_snapshot": { "regular_count": 8,
        "revision": 4, "series_quality": 2, "socket_count": 3, "socketed": ["", "mod_ban_s01_05", ""], "void_mass": 490,
        "weights_bp": { "s01_01": 1330, "s01_02": 1330, "s01_03": 1330, "s01_04": 1330, "s01_05": 0,
                        "s01_06": 1330, "s01_07": 1330, "s01_08": 1330, "s01_hidden": 200 } } }
  ],
  "pools": {
    "series_01": {
      "pity_counter": { "hidden_streak": 15, "new_item_streak": 3 }, "regular_count": 8, "revision": 4,
      "series_quality": 2, "socket_count": 3, "socketed": ["", "mod_ban_s01_05", ""], "void_mass": 490,
      "weights_bp": { "s01_01": 1330, "s01_02": 1330, "s01_03": 1330, "s01_04": 1330, "s01_05": 0,
                      "s01_06": 1330, "s01_07": 1330, "s01_08": 1330, "s01_hidden": 200 }
    }
  },
  "progression": {
    "collected": { "series_01": { "s01_01": true, "s01_02": true, "s01_04": true } }, "current_phase": "opening",
    "duplicate_count": { "series_01": { "s01_01": 4, "s01_02": 1 } }, "full_collection_reached": false,
    "granted_unlock_ids": { "ms_01:material_category:ore": true }, "milestone_state": { "ms_01": 3, "ms_02": 1 },
    "module_quality_ceiling": 1, "unlocked_material_categories": ["ore", "fiber"], "unlocked_series": ["series_01"],
    "unlocked_series_qualities": [1, 2]
  },
  "schema_version": 2,
  "saved_at_unix": 1730000000
}
```

**边界说明：** `pool_snapshot` / `pools` 的字段取自 `05-module-pool.md` §4 的 `PoolState`（`revision` / `socketed` / `socket_count` / `void_mass`），模块编辑明细与其**求值口径**归 `05` / `07-economy-rho.md`，本系统只负责其**持久化布局**；`pity_counter` 的**规则**归 `01-gacha.md`。上例数值仅示意格式，口径一律以 `README.md` §6.1 与 `07-economy-rho.md` §5.4 为准。

## 5. 规则与公式

1. **收录**：`GachaService.roll()` 结算后，本系统记录 `collected[series_id][item_id] = true`；若已收录则 `duplicate_count += 1`（重复款转物资数量见 `02-material.md`；P5「重复永不是空手」由此兑现）。**空洞 `void` 不产生任何收录效果**：`void` 不产出物资，**不写图鉴**、**不推进 `series_progress`**、**不改动 `collected`**（因此 `is_collected()` 的返回值不变，即"未拥有款加权"的状态不受 `void` 影响）、不加 `duplicate_count`；它只落进 `draw_log`（`item_id` 为空、`is_void = true`，见 §4.1）。`void` 是否推进 `pity` 归 `01-gacha.md`，本系统不裁决。
2. **缺口**：`gap_count(series_id) = (regular_count(series_id) + 1) - collected_count(series_id)`；`gap_items(series_id)` 返回未收录款清单。`regular_count` 由该套系的**套系品质**决定（品质 1/2 = 8，品质 3/4 = 12，核心 §4.1.1），**只在运行时从 `SeriesDef` 读取，不得在本系统内写死 8**。核心 §5.5 的收官玩法（把池子编辑到只剩缺口款）以本清单为唯一依据。
3. **套系进度**：`series_progress` 必须**分列两个数字**——常规 `collected_normal / regular_count` 与隐藏 `collected_hidden ? 1 : 0 / 1`（同样不得写死分母）。**理由（由 C3 推出）**：隐藏款免疫一切池子编辑（核心 §5.4），并入同一百分比会让玩家以为"靠编辑能收敛它"，与 P4 冲突。
4. **里程碑链**：`MilestoneDef` 依 `order_index` 顺序推进；节点状态见 §7.2；节点达成后由本系统发放 `unlocks`。
5. **解锁发放**：`grant_unlock(payload)` 为**幂等**操作，幂等键 `"{milestone_id}:{kind}:{target_id}"`（`[补充]`：同一载荷重复发放不得重复生效，否则存档不确定）。四类载荷与各自的写入目标：

   | `Kind` | 发放后写入 | 语义 | 与其它载荷的关系 |
   |---|---|---|---|
   | `SERIES` | `unlocked_series` | **这个套系能不能开盒**（内容量） | 新池子的入场券 |
   | `MATERIAL_CATEGORY` | `unlocked_material_categories` | 物资类别开关 | 与位次无关 |
   | `MODULE_QUALITY` | `module_quality_ceiling` | **模块能造多强**（D13，R11 核心载体） | 与下一项是同一成长的两条腿 |
   | **`SERIES_QUALITY_UNLOCK`**（v0.6 新增） | `unlocked_series_qualities` | **这个档位的套系能不能施工**（功率上限） | `magnitude` = 该套系的 `series_quality`（1–4） |

   **关系与顺序**：`SERIES` 决定"有没有这个池子"，`SERIES_QUALITY_UNLOCK` 决定"这个池子的施工台有多大"。同一里程碑内若两者同时发放，执行顺序为 **`SERIES_QUALITY_UNLOCK` → `SERIES` → 其余**（`[补充]`：避免出现"盒子能开、施工台却未解锁"的中间态——该中间态下无法确定该套系的位次上限，05 会读到未授权的 `SeriesDef.socket_count`）。`MODULE_QUALITY` 与 `SERIES_QUALITY_UNLOCK` 则互为补充：前者决定**模块多强**，后者决定**能装几个**（核心 §4.1.1）。
   **发放只写 `unlocked_*` / `unlocked_series_qualities` / `module_quality_ceiling`，不直接写入任何位次**：位次永远由对端从 `SeriesDef` 读取（见 §10 的 T4）。
6. **全收集判定**：`full_collection_reached = 所有已解锁套系的全部款（regular_count 常规 + 1 隐藏）均已收录`（`regular_count` 逐套系取自其 `SeriesDef`）。后续释放新套系时，已达成标记**保留**并重新进入收集中状态（`[补充]`：内容释放是持续的，终局必须可重入，否则新内容会"取消"玩家已达成的成就）。
7. **终局表现**（核心 §10.1 / §10.2）：全收集不提供任何数值奖励；其表现是图鉴满格、套系进度满格，以及收官阶段**池子逼近只剩缺口款**的当前状态仍可随时展开查看。收尾是 **"我算赢了它"**，不是"我终于抽到了"。
8. **阶段判定只用于呈现**：`current_phase` 由 `EvalService` 的 ρ 落入哪一 `ProgressionPhaseDef` 区间决定（`07-economy-rho.md` 是唯一 ρ 口径）。**只读 ρ，绝不直接读池子结构**——`void` 已通过 `v = 0` 压低 `m_bar` 并体现于 ρ，阶段判定因此自动吸收 `void` 的影响，无需（也不得）另行读取 `void_mass`。**阶段判定不得以任何方式影响池子、权重或概率**（P1 铁律 7）。
9. **内容产能即节奏**：`milestone_chain` 的节点数与 `unlocks` 的载荷量，就是玩家进度的**全部**燃料（R11）。任何"没有新载荷可发"的里程碑节点都是设计缺陷，不是配置自由。
10. **套系品质解锁是唯一的功率成长路径（P7 的全部要害，v0.6 新增）**：`max_series_quality = max(unlocked_series_qualities)` 就是玩家**最高能施工到的档位**。这条规则的准确表述是**两句话，缺一即错**：
    - **同一套系内不得增额**：**没有任何**载荷、里程碑、进度、重复劳动或物资消耗可以提高某个**已解锁套系**的 `socket_count` / `device_slot_count`。这半句仍是 P7 的红线（T4）。
    - **跨套系是合法的、也是唯一的成长路径**：解锁更高品质的套系 = 得到一个**更大但池子也更大**的施工台（核心 §4.1.1 要求位子与款数同步长，否则 C6 失效）。这是 v0.6 新增的主动轴，**是内容释放，不是扩容**。
    - **因此不得写成"位子永远不能增加"**——那会误杀唯一的功率成长路径，把 P7 变成"开盒端永久冻结"（那正是 v0.6 要修掉的问题）。
    - 本系统在此轴上的职责**只有发放**：写入 `unlocked_series_qualities`，不去读写任何位次（§2 / §8.2）。

## 6. 参数表（推荐值 + 调参旋钮标记）

### 6.1 结构与解锁节奏

| 参数 | 推荐值 | 🔧 | 说明 |
|---|---|---|---|
| 已释放套系总数 | 切片 1 / 目标 6–8 | 🔧 | 内容量 = 进度容量（R11） |
| **套系品质档位数 / 已解锁最高档** | 切片只出 1 档（**品质 2**，核心 §13.1）/ 目标 4 档 | 🔧 ★ | **直接决定 ρ 上限**——档位上限即施工台功率上限（§5 第 10 条）；4 档是否全出见 §11 Q5 |
| 模块品质档位数 / `module_quality_ceiling` 初始值 | 4 档 / 初始 1 | 🔧 | 开局只能产出最低档模块（核心 §14.3） |
| **D13 · 模块品质释放节奏** | **每 2 个里程碑 +1 档**（1→4 共 6 节点） | 🔧 ★ | **R11 关键**：这是内容释放的主要载体，不由里程碑一次性全开 |
| 里程碑链节点数 | 切片 1 / 目标 8–10 | 🔧 | 与内容产能同阶 |
| 解锁顺序模板 | 新物资类别 → 模块品质 +1 → 新套系 + 套系品质解锁 → 模块品质 +1 → … | 🔧 | 交错释放，避免同类内容断层（R7）；**品质梯度不宜过陡**（§11 Q6 / 核心 R13） |

### 6.2 进度节奏表（核心 §10.2 的数据化）

| 阶段 | `rho_min`（含） | `rho_max`（不含） | **最高套系品质**（决定 ρ 上限） | 池子状态 | 收集状态 | 预期释放 |
|---|---|---|---|---|---|---|
| 开局 `opening` | 0.0 | 0.9 🔧 | 1（8 常规 / 2 位） | 原始池 | 零星几款 | 无 |
| 破局 `breakthrough` | 0.9 🔧 | 1.1 🔧 | 1（8 常规 / 2 位） | 首次镶嵌（排除无用款） | 首个套系过半 | 新物资类别 |
| 起飞 `takeoff` | 1.1 | 3.0 | **2**（8 常规 / 3 位） | 模块开始集中概率 | 快速补全前期套系 | 模块品质 +1 / 新套系 + 套系品质解锁 |
| 工程期 `engineering` | 3.0 | 10.0 | **3**（12 常规 / 4 位） | 每次镶嵌都是替换（核心 §3.3） | 长尾款显形 | 模块品质 +2 / 套系品质解锁 |
| 收官 `endgame` | 10.0 | 0.0（无上界） | **4**（12 常规 / 5 位） | 池子逼近只剩缺口款 | 集齐（隐藏款除外） | 最后解锁 + 全收集 |

**最高套系品质列（v0.6 新增）就是 ρ 上限的直接来源**：核心 §2.4 中"跨套系才增长"的功率在这一列上被落成节奏——玩家在某一阶段最高能施工到哪一档，决定他此刻的位子上限，从而决定 ρ 能爬到哪。档位对应的款数 / 位数取自核心 §4.1.1（🔧 旋钮）。
ρ 区间为 🔧 旋钮，必须**无重叠、无空隙**地覆盖 `[0, ∞)`；阶段判定只读 `EvalService` 的 ρ（`void` 压低 `m_bar` 的效果已含在 ρ 内，见 §5 第 8 条），**最高套系品质**、池子状态与收集状态三列只作文案与验收对照，不参与计算。

### 6.3 存档

| 参数 | 推荐值 | 🔧 | 说明 |
|---|---|---|---|
| 存档路径 | `user://save.json`（+ `save.bak`） | — | 核心 §14.1 `save_service.gd` |
| `draw_log` 保留条数 | 首发不裁剪 | 🔧 | 裁剪策略未定，见 §11；**不得静默裁剪** |
| 自动存档时机 | 每次兑现后、每次解锁发放后 | 🔧 | 保证 `draw_log` 与图鉴不脱节 |

## 7. 流程 / 状态机

### 7.1 收录流程

```
GachaService.roll() 结算（01） ──▶ 本系统 record_result(series_id, result)
      ├─ result.is_void → 图鉴 / series_progress / collected / duplicate_count 全不变（§5 第 1 条）
      ├─ 首次收录 → collected = true → 重算 gap_count → 图鉴点亮
      └─ 重复     → duplicate_count += 1（转物资数量，见 02-material.md）
  ──▶ 本系统 append_draw_log({seed, pool_snapshot, state_snapshot, item_id, is_void, star})
  ──▶ 重算 current_phase（只读 EvalService 的 ρ，纯呈现）
```

### 7.2 里程碑链状态机

```
LOCKED ──(requires 全部 COMPLETED)──▶ AVAILABLE ──(03 受理任务)──▶ IN_PROGRESS
                                          └─(03 结算 TaskDef）──▶ 本系统 grant_unlock() ──▶ COMPLETED
```

同一节点内两个写入方**顺序固定**：`03 先结算 TaskDef.rewards` → `本系统后发放 MilestoneDef.unlocks`（`[补充]`：同一事务内两个写入方的顺序必须确定，否则存档字节级不稳定）。状态取值 `LOCKED=0 / AVAILABLE=1 / IN_PROGRESS=2 / COMPLETED=3`。

### 7.3 全收集状态机

```
COLLECTING ──(所有已解锁套系的 regular_count 款常规全部集齐)──▶ NORMAL_COMPLETE   ← 对应 §6.2「收官」的收集状态
           ──(隐藏款亦收录)────────────────▶ FULL_COLLECTION
           ──(新套系释放)──────────────────▶ 回到 COLLECTING（标记保留，见 §5 第 6 条）
```

### 7.4 存档流程与版本迁移

```
收集状态 ──▶ to_dict() ──▶ JSON.stringify(sort_keys = true) ──▶ 写 save.json.tmp
        ──▶ 备份旧档为 save.bak ──▶ 原子替换为 save.json
读取：load() ──▶ 校验 schema_version ──▶ 低于当前版本则 migrate() ──▶ 反序列化
```

`[补充]`（原子写与 `save.bak`）：崩溃时 JSON 存档不得半写损坏，否则玩家直接丢档。
`[补充]`（`schema_version` 与迁移函数约定）：每次改字段必须递增版本并提供 `migrate_vN_to_vN+1()`；迁移必须幂等，且迁移后四条红线与往返稳定性均须成立（§10）。
**v1 → v2 迁移（v0.6，`[补充]`）**：v1 档没有套系品质概念，迁移时 ① 为每个 `pools` / `pool_snapshot` 条目按其 `series_id` 回填 `series_quality` 与 `regular_count`（取自 `SeriesDef`，与 v0.5 的 8 常规 / 3 位一致 → 品质 2）；② 回填 `unlocked_series_qualities = [1..该档最高品质]`（**只增不减**，与"玩家已解锁套系的最高档"对齐，保证最高可施工档位不因升级存档而回退）。理由是迁移必须把新进度轴的还原点补齐，否则读档后 P7 的档位不可判定。

## 8. 与其它系统的接口

### 8.1 里程碑任务链的归属裁决（与 `03-task.md` 的边界）

> **裁决：链骨架归 10，需求与奖励结算归 03。**

| 归谁 | 拥有什么 |
|---|---|
| **10 收集与进度** | `MilestoneChainDef` / `MilestoneDef`：**链的顺序、前置条件、解锁载荷 `unlocks`、未达成预告 `teaser`、发放动作 `grant_unlock()`** |
| **03 任务** | `TaskDef`（经 `MilestoneDef.task_def_id` 指向）：**需求向量匹配、物资扣减、`TaskDef.rewards` 结算（盲盒 / 券）** |
| **共有义务** | 同一任务的两个写入方按 §7.2 固定顺序执行，各自只写自己拥有的数据（README 铁律 2） |

**红线**：`TaskDef.rewards` **不得**包含任何内容释放载荷（新套系 / 新类别 / 模块品质）。内容释放只有一条发放路径：`MilestoneDef.unlocks` → `grant_unlock()`。否则解锁会出现第二个写入源，存档将不可复现。

### 8.2 接口清单

| 方向 | 接口 | 对端 |
|---|---|---|
| 提供 | `is_collected(series_id, item_id) -> bool`（供"未拥有款权重 ×1.5"判定）；`is_series_unlocked(series_id)` | 01 |
| 提供 | `module_quality_ceiling` / `can_produce_module(module_def) -> bool` | 05 |
| 提供 | `max_series_quality() -> int` / `is_series_quality_unlocked(q) -> bool`（**最高可施工档位**，只读；本系统不写位次） | 05 / 01 |
| 提供 | `is_material_category_unlocked(category)` | 02 / 06 |
| 提供 | `gap_items(series_id)` / `series_progress(series_id)` / `codex_state()`；`current_phase`、`milestone_state`、`full_collection_reached` | 08 / 03 |
| 提供 | `snapshot_state() -> Dictionary`（= `state_snapshot`） | 01 / 07 |
| 消费 | `TaskService.task_completed(task_id)` 信号 → 若属里程碑链则 `grant_unlock()` | 03 |
| 消费 | `GachaService.roll()` 结果 → `record_collection()` + `append_draw_log()` | 01 |
| 消费 | `EvalService.compute(state).rho` → `current_phase`（**只读，不得回写**） | 07 |
| 消费 | `PoolService.get_pool_state(series_id)` → `pool_snapshot` | 05 |

## 9. UI 需求

呈现规格与布局见 `08-ui-panels.md`；本系统**要求必须呈现**以下信息（对应核心 §14.1 的 `scenes/collection/`）：

| 面板 | 必须呈现 | 理由 |
|---|---|---|
| **图鉴 `Codex`** | 按套系分组的 `regular_count + 1` 格（品质 1/2 为 9 格，品质 3/4 为 13 格）；**未收录款以占位剪影常驻可见**；缺口计数与缺口清单**默认展开，不得折叠**；任何一屏都要能一眼看到"还差几款" | 缺口可见性是硬要求（§1）；缺口半衰期是周 |
| **套系进度** | 常规 `x / regular_count` 与隐藏 `0 或 1` **分列两个数字**；可施工档位（`max_series_quality()`）与各位次的占用可见 | C3：隐藏款免疫编辑，合并会误导（§5 第 3 条）；v0.6：分母随套系品质变，且玩家必须看得见自己的施工台上限（P7 的呈现面） |
| **里程碑链** | 节点列表、当前节点、**未达成节点的 `teaser` 预告** | R11 + R7：内容释放必须被玩家感知，否则 ρ 涨了也"毫无感觉" |
| **全收集表现** | 图鉴满格标记；收官阶段可展开查看"池子逼近只剩缺口款"的当前状态 | 核心 §10.1「我算赢了它」 |

## 10. 测试点与验收标准

| # | 测试 | 判据 |
|---|---|---|
| T1 ★ | **存档往返一致性** | 存 → 读 → 存，连续 10 轮，`save.json` **字节级完全一致**（哈希相同）；键序稳定（`JSON.stringify(sort_keys = true)`） |
| T2 ★ | **池子快照可复现抽取（必须覆盖 `void`）** | 对 `draw_log` 中**每一条**记录，用其 `pool_snapshot` + `seed` 重跑 `GachaService.roll(series_id, pool_snapshot, seed)`，`item_id` 与 `star` 必须与日志一致（100% 命中，0 例外）。**含 `void` 的记录必须同样命中**：`pool_snapshot` 一旦漏记 `void_mass`，`void` 就抽不出来（或被误抽成某款），这是 `void` 引入后最容易漏的一条。用例集**必须显式包含**至少 1 条 `is_void == true` 的记录 |
| T3 ★ | **版本迁移** | 用 v1 存档跑 `migrate_v1_to_v2()`：① 红线（含 C4 / C6）仍成立，且 `series_quality` / `regular_count` / `unlocked_series_qualities` 已按 §7.4 回填（不是默认值） ② 迁移后往返仍字节级稳定 ③ 迁移幂等（再迁移一次无变化） |
| T4 ★ | **红线 C4 不得被解锁破坏（逐套系断言）** | 遍历整条里程碑链，全部达成后，**对每一个已解锁套系**断言 `pool_state.socket_count == 该套系 SeriesDef.socket_count`（`device_slot_count` 同理）。**跨套系不同是合法的**——那正是 v0.6 唯一合法的功率成长路径（§5 第 10 条）；**同一套系内被改变才是失败**。实现必须**逐套系**取各自的 `SeriesDef` 比对，不得只比对某个"全局位数"或某个硬编码常数。**本系统是最容易偷偷加位次的地方（P7），此测试为强制项** |
| T5 | **红线 + 序列化不改权重 / `void`** | 任意解锁、任意阶段下 C1（口径已修订为 `Σp_常规 + void_prob ≤ 0.98`，见 `README.md` §6.1）/ C2 / C3 / C4 按 `05-module-pool.md` / `07-economy-rho.md` 的定义口径成立；本系统另行断言 `weights_bp` 与 `void_mass` 经存 → 读 → 存后**逐项完全相等**（序列化不得引入量化误差，也不得让 `void` 被吸收或重新推导） |
| T6 | **阶段判定不改概率 / 发放幂等** | ① 手动构造落入五个阶段的状态，同一 `pool_state` 的分布哈希必须相同（防"按进度暗改爆率"，P1 铁律 7）；② 同一 `unlock_key` 重复发放 100 次，`unlocked_*`、`unlocked_series_qualities` 与 `module_quality_ceiling` 不变 |
| T8 | **缺口可见性与完成度分列 / `void` 不改收集状态** | ① 未收录款在默认视图可见、无折叠路径可隐藏缺口、`gap_count` 与实际未收录数一致；② 隐藏款未收录时 `series_progress` 的常规数字不受影响，常规 `regular_count / regular_count` 满格时 `NORMAL_COMPLETE` 成立而 `full_collection_reached` 仍为假（**两个品质档位各验一次**：8 常规与 12 常规）；③ 对同一池子先后制造 `void` 结果与正常结果，`void` 那一次使 `collected` / `duplicate_count` / `gap_count` / `series_progress` **逐项不变**，且 `is_collected()` 的返回值不变（§5 第 1 条） |
| T10 ★ | **含 `void` 的存档往返一致性** | 构造 `void_mass > 0` 且 `draw_log` 含 `is_void == true` 条目的存档，存 → 读 → 存连续 10 轮**字节级稳定**；断言 `void_mass` / `revision` / `socketed` / `socket_count` 与逐款 `weights_bp` 逐项完全相等，且 `void_mass` 不得在读档时被丢弃、取整或由 `weights_bp` 反推 |
| T11 ★ | **红线 C6 在任何解锁进度下不得被破坏（v0.6 新增）** | 对**任意解锁进度**、**任意合法 `PoolState`**，断言**可产出常规款数 ≥ 3**（口径见 `05-module-pool.md` / `07-economy-rho.md`）。用例集**必须覆盖每个品质档位**（8 常规与 12 常规各至少一例），并覆盖"排除已到上限"的极值池：品质 1/2 最多排 5 款、品质 3/4 最多排 9 款，各自排到极限后仍须留下 ≥ 3 款可产出 |
| T12 ★ | **含多档品质套系存档的往返一致性（v0.6 新增）** | 构造**同时含多个不同 `series_quality` 套系**的存档（至少覆盖 8 常规与 12 常规各一），存 → 读 → 存连续 10 轮**字节级稳定**；断言每个 `pool_snapshot` / `pools` 条目的 `series_quality` 与 `regular_count` **逐项完全相等、不丢失、不被推导**（不得由 `weights_bp` 键数反推，也不得读档时按"当前最高档"统一改写），且读档后 `max(unlocked_series_qualities)` 与写档前一致（**P7 的还原点**：玩家最高能施工到什么档位不得因存档往返而变化） |

**切片失败信号（本系统相关，配合核心 §13.4）：**

- 测试者**找不到缺口在哪** → 图鉴失败（缺口可见性未达标，本系统最严重的失败）；**说不出"下一个解锁是什么"** → `teaser` 预告失败，R11 的可感知性未落地；
- 测试者解锁新套系 / 新品质（含**套系品质**档位）后**毫不知情，或 ρ 无变化** → 内容释放未接上经济，R11 直接命中；
- 测试者认为"全收集就是抽到就完" → 终局表现失败，核心 §10.1 的"我算赢了它"未兑现；
- **T1 / T2 任一失败** → 直接阻塞发布：核心 §13.1 的"开箱日志（seed + 池子快照 + 结果）"与 P1 的可查可算承诺同时失效。

## 11. 待定项

| # | 待定项 | 影响 |
|---|---|---|
| Q1 | **D13 的具体节奏**（每 2 个里程碑 +1 档？按套系释放？） | ⛔ R11 关键，需与内容产能同步排期；核心 D13 未决 |
| Q2 | **全收集之后有什么**（核心未定义通关后内容） | 本系统只判定与呈现，**不得在此处私加新机制** |
| Q3 | `draw_log` 的裁剪策略与存档体积上限；图鉴是否需要物品文案 / 成就系统 | 前者会削弱 P1 的审计能力，需显式决策，**禁止静默裁剪**；后者核心 §13.2 已排除成就，需另行立项 |
| Q4 | 数据版本迁移的正式策略（跨大版本兼容承诺）；存档导入导出 / 云存档 | 前者影响存档格式冻结时点；后者核心已定"暂不做" |
| Q5 ★ | **套系品质梯度的释放节奏**（v0.6 新增）：第 2 档排在第几个里程碑？第 3 / 4 档要不要全出，还是止步于 3 档 | ⛔ **R11 关键**——品质档位是 v0.6 唯一的功率成长轴（§5 第 10 条），它的释放节奏就是 ρ 上限的释放节奏。**但本系统不得自行取值**：这是内容产能排期问题，须与核心 D3 的曲线形状、D13 的模块品质节奏一起定（§6.1 / §6.2 目前给的是推荐排法） |
| Q6 | **低品质套系被淘汰的风险**（核心 R13 在本系统的落点，v0.6 新增）：高品质套系同时给更多位子与更高价值物资（核心 §4.1.1），低品质盒可能沦为废料 | 本系统的**唯一对策手段是发放顺序**：把品质梯度放平（相邻档不同时给"更多位子 + 更高价值物资"），并保证每个阶段的**预期释放**里仍有低品质套系的用武之地。**结构性的对抗仍归核心 §10.3 的需求结构变宽与 D14（品质梯度不宜过陡）**，本系统只负责不把这个风险放大 |

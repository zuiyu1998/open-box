# 10 · 收集与进度系统

- 上游：`../core-design.md` **v0.9** ／ `README.md`
- 依赖系统：07 数值与期望（ρ 区间判定，只读）、01 盲盒（抽取结果、保底计数、未拥有物品权重）、03 任务（里程碑任务的需求与奖励结算）、05 模块与池子（`PoolState` 快照）、02 物品（类别定义、**物品实例列表与 `serial_counters` 的写入方**、`location` 与仓库容量占用的**写入方**）
- 被依赖：01（「未拥有物品」判定）、05（模块品质产出权限）、02 / 06（物品类别开关）、03（里程碑可见性）、08（图鉴与套系进度呈现、**仓库占用与邮件抽屉**）

> **v0.9 同步（仓库容量与邮件）**：①存档 schema 升到 **4**——实例加 `location`（`warehouse` / `mail`），并新增**仓库容量** `warehouse_capacity` 的持久化（它是**进度解锁物**，必须入档，§4 / §5 第 14 条）；②**容量由里程碑解锁**（核心 D15，内容门控，与 P7 一致）——新增载荷 `WAREHOUSE_CAPACITY`（§4 / §5 第 5 条），并**明确禁止任何靠消耗物品 / 重复开盒增加容量的路径**（§5 第 14 条）；③**`source.kind` 的迁移取值按核心 v0.9 裁决 4 定为 `&"migrate"`**（本文旧稿的 `&"migration"` 作废）；④新增 **v3 → v4 迁移规则**（§7.4），**实例数量守恒、绝不丢弃**；⑤`collected` 裁决**上游已采纳**（§5 第 13 条）；⑥**裁决 17 收窄了"产出溢出"的适用范围**：**被动产出（开盒）放不下 → 进邮件**，**主动操作（转化 / 拆卸返还）放不下 → 拒绝整个操作**（§5 第 15 条末条）；⑦**新增主动丢弃**（裁决 16）：玩家可销毁仓库内实例，记账只走 `total_consumed`，**不得回退** `collected` / `duplicate_count` / `serial_counters`（§5 第 16 条）；⑧**守恒等式按全部实例**（裁决 12）：`total_granted − total_consumed == Σ 全部现存实例（含邮件）`，`count()` 只是带 `location` 过滤的查询（§5 第 15 条 / T17 ⑥ / T20）。**里程碑链、品质解锁、进度节奏、五条红线一律未改。**

> **v0.8 同步（物品实例化：本系统是改动最大的一份）**
> 1. **存档大改**：持有量从"每个 `(category, quality)` 一行计数"改为**实例列表 `Array[ItemInstance]`** 的序列化（§4 / §4.1），`schema_version` 升到 **3**（v2 → v3 迁移规则见 §7.4）。
> 2. **新增持久化字段 `serial_counters`**：记录该玩家每种物品**已开出多少个**，是收藏编号 `serial` 的唯一分配依据，**只在开盒产出时 +1**（§3 / §4 / §5 第 12 条）。
> 3. **只持久化现存实例**：已消耗的实例不写档——审计由 `draw_log` 承担（它已记录 `seed` + `pool_snapshot`），见 §5 第 11 条。
> 4. **`collected` 保留为独立持久化标记，不由实例列表推导**（§5 第 13 条）——收录是**不可逆事实**，已消耗的实例不该让收录消失。
> 5. **存档体积成为新的真实代价**：每实例约 120 B、5000 实例 ≈ 600 KB（`source` 是大头）→ §6.3 参数表 + §11 **Q8（切片阶段必须实测）**。

> **本系统是 R11 的落点。** ρ 的成长**只能**来自内容释放（核心 §2.4），而内容释放的**发放动作**归本系统。因此：**内容产能是进度的唯一来源，本系统直接决定产品节奏**——内容跟不上 → 解锁链无货可发 → 进度停滞 → 玩家流失。本系统的设计目标是让"内容释放"成为**可配置数据**（§6），而不是手写代码。

> **v0.6 同步（本系统新增一条进度轴）**：镶嵌位数与装置槽位数改由**套系品质 `series_quality`** 决定（核心 §4.1.1 / C4），**解锁更高品质的套系因此成为一条新的主动进度轴**，其发放动作归本系统：新增载荷 `SERIES_QUALITY_UNLOCK`（§1 第 4 条 / §5 第 5 条），并新增持久化集合 `unlocked_series_qualities`（§4）。
> P7 的要害随之收敛为一条区分：**同一套系内不得增额；跨套系（解锁更高品质套系）是合法的、也是唯一的功率成长路径**（§5 第 10 条）。

## 1. 这个系统负责什么

1. **图鉴 `Codex`**：每个物品 `Item` 的收录状态（已收录 / 未收录 / 重复次数），以及**缺口可见性**。核心 §1.1 把「图鉴」列为"获取物品"这一步的系统职责；"**缺口的半衰期是周**"出自 `../archive/core-design-v0.1.md` §1.3（v0.5 §16「继承不变」未废止），本系统据此把**缺口可见性**定为硬要求（§9）。**v0.8：收录是不可逆事实**——`collected` **不由实例列表推导**（§5 第 13 条）。
2. **套系进度 `series_progress`**：单个套系的完成度，**常规 `regular_count` 个物品 + 1 个隐藏物品分别计**（`regular_count` 由该套系的**套系品质**决定，8 或 12，核心 §4.1.1；分开计的理由见 §5 第 3 条）。
3. **里程碑任务链 `milestone_chain`**：链骨架（顺序、前置、解锁载荷、预告）的定义与发放。**谁定义、谁发奖励的裁决见 §8.1。**
4. **解锁发放 `grant_unlock()`**：新套系 / 新物品类别 / **更强模块的产出权限**（核心 §4.3）/ **套系品质解锁 `SERIES_QUALITY_UNLOCK`**（核心 v0.6 §4.1.1）/ **仓库容量扩容 `WAREHOUSE_CAPACITY`**（核心 v0.9 D15）。其中模块品质的释放节奏即 **D13**（R11 的核心载体）；**套系品质解锁决定"玩家最高能施工到什么档位"**，是 v0.6 新增的**唯一功率成长路径**（P7，§5 第 10 条）；**容量解锁是 v0.9 新增的第二个内容门控载荷**（§5 第 14 条），它同样**只有发放权、没有产出权**。
5. **全收集判定与终局表现**（核心 §10.1 / §10.2）；**存档结构**：`user://` JSON 的完整 schema、**物品实例列表 `Array[ItemInstance]`（含 `location`）与 `serial_counters` 的持久化布局（v0.8 / v0.9）**、**仓库容量 `warehouse_capacity` 的持久化（v0.9）**、`pool_snapshot` / `state_snapshot` / 保底计数 / 开箱日志（seed + 结果）；**进度节奏表**：把核心 §10.2 的五阶段落成可配置数据（§6.2）。

## 2. 不负责什么（边界）

| 不负责 | 见 |
|---|---|
| 任务的需求向量匹配、奖励结算、需求随进度变宽 | `03-task.md` |
| 抽取判定 `roll()`、保底触发、未拥有物品权重 ×1.5 的**计算** | `01-gacha.md` |
| `PoolState` 的结构（含 `void_mass`）与排除 / 提升 / 损耗 / 零和；ρ / M̄ / D̄ / B / σ 与 `void_prob` 的计算口径、归因分解 | `05-module-pool.md` / `07-economy-rho.md` |
| 物品类别与品质定义、**物品实例列表（`ItemInstance`）的创建 / 销毁 / 查询、`serial` 的分配与派生 `count`** | `02-item.md`（`ItemService` 是**唯一写入方**）。本系统只定义其**持久化布局**并做审计，**不得自行创建、销毁或改写实例** |
| 装置槽位与转化端修正；转化表与损耗结算；面板布局、展开入口与 `headline` 渲染；开箱演出（含 `void` 的呈现） | `04-device.md` / `06-conversion.md` / `08-ui-panels.md` / `09-presentation.md` |
| **解锁发放之后的各系统行为**（解锁新套系后 01 怎么建池、解锁品质后 05 怎么造模块） | 各系统自己负责 |
| **`location` 的写入**（产出溢出判定、进邮件、领取）、**仓库占用的计算**与 `count()` 的仓库口径 | `02-item.md`（核心 §4.7 / §14.2 铁律 9）。本系统**只发放容量、只持久化 `location` 与 `warehouse_capacity`**，**不得**在任何路径上自行判定溢出、改写 `location` 或推导占用。**主动操作（转化 / 拆卸返还）的空间拒绝**（裁决 17，判定归 06 / 04、执行归 02）与**主动丢弃的销毁**（裁决 16，归 02）同样不在本系统 |
| **`ItemDef.size`**、容量的**抽象单位**与 UI 的占比换算 | `02-item.md`（`size`）/ `08-ui-panels.md`（换算与呈现）。本系统只持久化容量数值本身 |

**本系统的唯一写权限是"解锁发放"与"图鉴 / 套系进度 / 存档布局"。** 一切"解锁之后会怎样"都不在本系统内实现：本系统只把 `unlocked_*` 标志位、`unlocked_series_qualities`、`module_quality_ceiling` 与 **`warehouse_capacity`** 放进共享状态，由对端读取（§8.2）。**位次本身永远不由本系统写入**（P7，§5 第 10 条）；**容量同理——本系统只写入"解锁到多少"，从不参与"装不装得下"的判定**（判定在 02 的 `grant()` 内部，核心 §4.7）。

## 3. 核心概念与术语

沿用 `README.md` §5：套系 `Series`、物品 `Item`、池子 `Pool`、池子状态 `PoolState`、镶嵌位 `socket_slot`、隐藏物品 `hidden`、保底 `pity`、任务 `Task`、类别 `category`、品质 `quality`、闭环收益率 `rho`。本系统新增的**落地命名**（核心文档只给概念，未给字符名）：

| 中文名 | 代码名 | 说明 |
|---|---|---|
| 图鉴 | `Codex` | 全部物品与收录状态的集合 |
| 缺口 | `gap` / `gap_count` | 未收录的物品 / 其数量 |
| 空洞 | `void` / `void_mass` | 排除损耗产生的**零价值结果**，**不是一个物品**（不计入 N）；求值与损耗写入见 `07-economy-rho.md` §5.4 / `05-module-pool.md` §5.4 |
| 套系进度 | `series_progress` | 单套系完成度，常规与隐藏分列 |
| 里程碑 | `MilestoneDef` | 里程碑任务链的一个节点 |
| 解锁载荷 | `UnlockPayload` | 里程碑发放的内容释放项 |
| 模块品质天花板 | `module_quality_ceiling` | 当前允许产出的模块品质上限 |
| 全收集 | `full_collection` | 已释放套系全部物品收录 |
| 开箱日志 | `draw_log` | 每次兑现的 `{seed, pool_snapshot, state_snapshot, item_id, quality}`（核心 §14.2 铁律 7；`quality` 即该 `item_id` 在 `ItemDef` 上的品质，二者同源自洽） |
| 进度阶段 | `ProgressPhase` | 核心 §10.2 五阶段之一 |
| 套系品质 | `series_quality` | 套系（池子）的品质档位 1–4，**决定该套系的常规物品数、镶嵌位数、装置槽位数与产出物品的品质区间**；核心 §4.1.1 |
| 已解锁套系品质 | `unlocked_series_qualities` | 玩家已解锁的品质档位集合；**其最大值 = 玩家最高能施工到的档位**（P7，§5 第 10 条） |
| 物品实例 | `ItemInstance` | 玩家实际持有的**一个**物品：`instance_id` / `item_id` / `acquired_at` / `source` / `serial` / **`location`**（核心 §4.2.1 / §4.7）。**创建、销毁与 `location` 的写入归 02**，本系统只持久化其布局（v0.8 / v0.9） |
| 收藏编号 | `serial` | **该玩家开出的第 N 个此物品**；**只有开盒产出会推进计数器**（`serial ≥ 1`），转化 / 拆卸返还 / 解锁发放产生的实例为 `serial = 0`；**v2 → v3 迁移回填**的实例为 `serial = 1 … N`（§7.4 第 3 条：它们对应 v2 的真实持有，故占用编号，但 `source.kind = &"migrate"` 仍可区分来源）（核心 §4.2.3，v0.8） |
| 序号计数器 | `serial_counters` | `{item_id: int}`——该玩家**已开出**多少个该物品；**只在开盒产出时 +1**，是 `serial` 的唯一分配依据（v0.8 新增，§5 第 12 条） |
| 溯源 | `source` | 实例的来源：开盒 `{kind: &"gacha", series_id, box_seed, draw_index}`；其余只带 `kind`。**`kind` 的取值域（核心 v0.9 裁决 4）：`&"gacha"` / `&"convert"` / `&"refund"` / `&"mail"` / `&"migrate"` / `&"unlock"`**——各取值的语义与分配归 `02-item.md` §4.2，本系统只用 `&"migrate"` 一档（迁移回填）`[补充]` |
| 仓库容量 | `warehouse_capacity` | **抽象单位**的仓库总容量；**由里程碑解锁、只增不减**（核心 D15 / §4.7，§5 第 14 条）。UI 换算为**占比**显示，换算与呈现归 `08-ui-panels.md` |
| 位置 | `location` | 实例的落位：`&"warehouse"`（仓库，计入 `count()`）/ `&"mail"`（邮件，**不计入可用持有**）。**写入方 02**：产出时由 02 的 `grant()` 内部判定溢出，领取（`mail → warehouse`）只是改位置（核心 §4.7 / §14.2 铁律 9）。本系统**只持久化该字段**（§5 第 15 条） |
| 邮件 | `mail` | 放不下产出的**兜底容器**：无上限、不过期、手动或一键领取。**它不是第二个仓库**——邮件实例不可用于交付 / 装配 / 镶嵌 / 转化（核心 §4.7）。本文只负责它的**持久化口径**，呈现归 08 |
| 物品大小 | `ItemDef.size` | 单个实例占用的容量单位（**同种物品大小相同**，核心 §4.2 / D16）。归 `02-item.md`；本系统不拥有其数值 |

### 3.1 术语纪律：「品质」有两个含义（v0.6 新增）

**本系统两者都会出现，必须可分辨。**

| 写法（一律写全） | 代码名 | 含义 | 出处 |
|---|---|---|---|
| **物品品质** | `quality` | 物品的等级维度，1–5 序数 | `02-item.md` |
| **套系品质** | `series_quality` | 套系 / 池子的品质档位，1–4 | 核心 §4.1.1 |

**规则：本系统中孤立的"品质"二字视为歧义**——凡涉及两者之一，一律写全"物品品质"或"套系品质"。
二者**不是同一把尺子上的两个刻度、也无换算关系**：套系品质**决定**该套系产出物品的品质**区间**；物品品质只影响任务贡献度与作为装置/模块素材时的强度（核心 §4.2）。

## 4. 数据结构（GDScript Resource 字段定义）

```gdscript
# 下列各段各自落在其注释标注的文件中
# res://data/defs/unlock_payload.gd —— 内容释放的一项
class_name UnlockPayload
extends Resource
enum Kind { SERIES, ITEM_CATEGORY, MODULE_QUALITY, SERIES_QUALITY_UNLOCK, WAREHOUSE_CAPACITY }
# SERIES = 新套系 / ITEM_CATEGORY = 新物品类别 / MODULE_QUALITY = 更强模块的产出权限（D13）
# SERIES_QUALITY_UNLOCK = v0.6 新增：解锁一个更高品质的套系（核心 §4.1.1）
# WAREHOUSE_CAPACITY = v0.9 新增：仓库容量扩容（核心 D15；容量只能由里程碑解锁）
@export var kind: Kind = Kind.SERIES
@export var target_id: StringName          # series_id / category；MODULE_QUALITY 与 WAREHOUSE_CAPACITY 时留空
@export var magnitude: int = 1             # MODULE_QUALITY：提升到第几档模块品质；SERIES_QUALITY_UNLOCK：该套系的 series_quality（1–4）；WAREHOUSE_CAPACITY：**新增的容量单位数（加到 `warehouse_capacity` 上，不是目标值）**

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

# res://data/defs/item_instance.gd —— 物品实例（**所有权属 02**，核心 §4.2.1 / §14.1；此处只列持久化字段）
class_name ItemInstance
extends Resource
@export var instance_id: String = ""       # UUIDv4，全局唯一，兼作幂等键（Godot 无内置 UUID，需自实现）
@export var item_id: StringName = &""      # 指向 ItemDef
@export var acquired_at: int = 0           # 开出时刻（Unix 秒）
@export var source: Dictionary = {}        # {kind, series_id, box_seed, draw_index}；kind != &"gacha" 时后三项缺省
@export var serial: int = 0                # 收藏编号；**开盒产出 ≥ 1**，0 = 非开盒来源（转化 / 返还 / 解锁发放）；v2 迁移回填为 1…N
@export var location: StringName = &"warehouse"  # v0.9：warehouse / mail。**写入方 02**（产出时在 grant() 内判定溢出）；本系统只持久化，见 §5 第 15 条

# 运行时状态（由 GameState 持有，SaveService 持久化）
class_name ProgressionState
extends RefCounted
var items: Array[ItemInstance] = []        # v0.8：**只读引用** 02 的 `ItemService.instances`（现存实例，**含仓库与邮件两侧**）；本系统不创建 / 不销毁，只在序列化时读取
var warehouse_capacity: int = 0            # v0.9：**只读引用** 02 的 `ItemService.warehouse_capacity`（抽象单位）；本系统只定义其**持久化布局**，写入路径只有两条：①解锁发放（§5 第 5 条）②读档还原。**占用/溢出判定不在本系统**（核心 §4.7）
var serial_counters: Dictionary = {}       # v0.8 新增：{item_id: int} 已开出数；**只在开盒产出 +1**；写入方 02（§5 第 12 条）
var collected: Dictionary = {}             # {series_id: {item_id: true}} —— 图鉴；**不可逆事实，不由 items 推导**（§5 第 13 条）
var duplicate_count: Dictionary = {}       # {series_id: {item_id: int}} —— 图鉴重复次数；同样不可逆、不由 items 推导
var unlocked_series: Array[StringName] = []
var unlocked_item_categories: Array[StringName] = []
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
var quality: int = 1                 # 该物品的品质，取自 `ItemDef.quality`（与 `item_id` 同源自洽；`void` 记录此值无意义，与 `is_void` 一并判读）
```

**持久化口径（`[补充]`）**：所有权重与 `void_mass` 落盘为**整数万分比**（`weights_bp` / `void_mass`，1 bp = 0.01%）。理由：用户要求的"存 → 读 → 存字节级稳定"必须规避浮点格式化漂移与键序抖动；`PoolState` 的**结构与求值口径**仍归 `05-module-pool.md` / `07-economy-rho.md`（其 `void_mass` 为运行时 float），本系统只定义其**持久化布局**。
**`state_snapshot` 的最小字段集（`[补充]`）**：`{m_bar, d_bar, b, rho}`。理由：核心 §14.2 铁律 7 只要求"记录 state_snapshot"而未规定内容；这四个量是 `EvalService` 的全部输出标量，足以让任意历史开箱的归因可复算（P2）。
**`pool_snapshot` 的规模字段（v0.6 新增）**：每个 `pool_snapshot` / `pools` 条目额外冻结 `regular_count`（该套系常规物品数）与 `series_quality`。理由：v0.6 中**位子数与池子规模都随套系品质变化**，读档时若不带上这两个值，就**无法校验位子数与池子规模是否仍等于其 `SeriesDef`**（T4 / T11），只能靠 `weights_bp` 的键数反推——而反推在 C6 的极值池上不可靠。二者是 `SeriesDef` 值的**冻结副本**，只读、不参与求值。
**`unlocked_series_qualities` 的持久化（v0.6 新增）**：以**整数数组**落盘（升序去重）。理由：读档后必须能**还原"玩家最高能施工到什么档位"**（P7）；该值**不得**由 `unlocked_series` 或 `module_quality_ceiling` 推导——它是一条独立的进度轴（§5 第 10 条）。
**实例列表的持久化（v0.8，`[补充]`）**：`items` 以 **`Array[ItemInstance]`** 落盘（`inventory.instances`），**只写现存实例**——已消耗的实例不留墓碑（核心 §4.2.2 第 3 条）。理由：①审计由 `draw_log` 承担（它已记录 `seed` + `pool_snapshot` + `state_snapshot`），实例列表只需回答"我现在有什么"；②保留墓碑会让存档随游玩时长无界增长（每实例约 120 B，§6.3）。**实例列表的创建 / 销毁 / 查询归 02**，本系统只定义其**持久化布局**（与 `pool_snapshot` 同一处理方式）。
**`serial_counters` 的持久化（v0.8，`[补充]`）**：以 `{item_id: int}` 落盘（键序字母序）。理由：`serial` 必须**跨存档单调**——若只靠现存实例推 `max(serial)`，玩家把该物品全部交付任务后编号会**回退**，再开出的"第 3 个"会变成新的第 1 个。该字段是 `serial` 的**唯一**分配依据，且**只增不减**（§5 第 12 条 / T16）。
**键名与取值对齐（v0.8，`[补充]`）**：`inventory` 块的四个键 = **02 §4.6 `to_save_dict()` 的返回字典**（`instances` / `serial_counters` / `total_granted` / `total_consumed`），本系统**只落盘、不改写**；`count_index` **不入档**（派生值，载入后由实例列表重建）；实例的来源判别键按 02 §4.2 已定的 **`source.kind`** 落地（取值域由**核心 v0.9 裁决 4** 定为 `&"gacha"` / `&"convert"` / `&"refund"` / `&"mail"` / `&"migrate"` / `&"unlock"`，04/05/06 一致——早期草案里写作 `origin` 的同名提案已由 `06-conversion.md` §11 C8 作废，**全库不得并存两个键名**）；**迁移回填一档按裁决 4 写作 `&"migrate"`**（本文与 08 旧稿的 `&"migration"` **作废**，全库不得并存两种拼写）。另：计数器一律写作 **`serial_counters`**（与 02 §4.6 的字典键名一致），**单数写法作废**。
**`location` 的持久化（v0.9，`[补充]`）**：`location` 随实例逐条落盘（`"warehouse"` / `"mail"`），是 `instances` 条目的一个键（键序按字母序排在 `item_id` 与 `serial` 之间）。理由：**仓库与邮件是同一个实例列表的两个位置，不是两份数据**（核心 §14.2 铁律 9）——若不入档，读档后要么凭空丢失邮件侧实例（违反 P5 的"产出永不丢失"），要么必须靠调 `count()` 反推（那就把派生值偷偷变成事实来源）。本系统**只落盘、不改写**：读档时不得按容量重新判定 `location`、不得"顺手"把装不下的搬到邮件（那会让占用率变化凭空改变持有位置，且与 02 的 `grant()` 判定路径形成第二个判定源）。
**`warehouse_capacity` 的持久化（v0.9，`[补充]`）**：以单个整数落盘（`progression.warehouse_capacity`）。理由：**容量是进度解锁物**（核心 D15），它记录"玩家已被发放到多少"；若不入档，读档后只能回到初始容量，玩家的解锁进度会**回退**（与 §4 的 `unlocked_series_qualities` 同一条理由：进度轴必须有还原点），且会让所有邮件侧实例的可用性发生无解释的变化。它**只增不减**、**不由 `size` 之和或持有量推导**（那等于承认"囤积换容量"，直接违反 P7 / §5 第 14 条）。

### 4.1 存档 JSON schema 示例（`user://save.json`）

键序为**字母序**（canonical 序列化，保证往返字节级稳定）。示例为**已镶嵌 1 个排除模块**的池子（排除 `s01_05`）：该套系为**套系品质 2**（`series_quality = 2` → 8 个常规物品 / 3 镶嵌位，核心 §4.1.1），其释放质量 1225 bp 中 40% 落为 `void`（`void_mass = 490`，即 4.90%），其余 60%（735 bp）按基础权重摊回剩下 7 个物品（各 +105 → 1330 bp）。故 `Σ 常规 9310 + void_mass 490 + 隐藏 200 == 10000 bp`（`README.md` §6.1）；`void_mass` 与 `weights_bp` 同单位、同精度。
`"schema_version": 4`（`[补充]`：v0.8 把持有量从"每个 `(category, quality)` 一行计数"改为**实例列表**并新增 `serial_counters`（→ v3）；**v0.9 给每个实例加 `location` 并新增 `progression.warehouse_capacity`（→ v4）**。按 §7.4 约定必须递增版本，故示例即 **v4**；v1 → v2 见 T3，v2 → v3 与 **v3 → v4** 见 §7.4）。
示例中 `location` 逐条落盘：除第 5 条外的四条实例都在 `warehouse`（含迁移回填的一条），**第 5 条演示一次"产出溢出进邮件"**（`location == "mail"`，`serial` 照常分配、`instance_id` 照常生成——**邮件的实例与其他实例是同一份数据**，只是位置不同，核心 §14.2 铁律 9）。本示例同时满足**守恒等式（裁决 12）**：`total_granted 191 − total_consumed 186 == 5`，恰为实例条目数——**含邮件那一条**（`count()` 只是带 `location` 过滤的查询，不参与该等式）。

```json
{
  "draw_log": [
    { "is_void": false, "item_id": "s01_02", "quality": 3, "seed": 918273645, "seq": 1, "series_id": "series_01",
      "state_snapshot": { "b": 2.0, "d_bar": 12.0, "m_bar": 3.24, "rho": 0.54 }, "pool_snapshot": { "regular_count": 8,
        "revision": 4, "series_quality": 2, "socket_count": 3, "socketed": ["", "mod_ban_s01_05", ""], "void_mass": 490,
        "weights_bp": { "s01_01": 1330, "s01_02": 1330, "s01_03": 1330, "s01_04": 1330, "s01_05": 0,
                        "s01_06": 1330, "s01_07": 1330, "s01_08": 1330, "s01_hidden": 200 } } }
  ],
  "inventory": {
    "instances": [
      { "acquired_at": 1729999990, "instance_id": "6f1c0b7e-3d2a-4c9f-9b41-2f5a7c0d1e88", "item_id": "s01_01",
        "location": "warehouse", "serial": 187,
        "source": { "box_seed": 918273645, "draw_index": 3, "kind": "gacha", "series_id": "series_01" } },
      { "acquired_at": 1729999990, "instance_id": "b0a5f2d4-8c31-4a76-8e19-7d3f4b62a1c0", "item_id": "s01_02",
        "location": "warehouse", "serial": 2,
        "source": { "box_seed": 918273645, "draw_index": 4, "kind": "gacha", "series_id": "series_01" } },
      { "acquired_at": 1729999999, "instance_id": "1d9e77aa-55b2-4f08-b3c6-0a2e6c8f9d31", "item_id": "s01_01",
        "location": "warehouse", "serial": 0, "source": { "kind": "convert" } },
      { "acquired_at": 1730000000, "instance_id": "c47b1e02-9a63-4d5c-8f27-6b18e0a4d5f9", "item_id": "s01_01",
        "location": "warehouse", "serial": 1, "source": { "kind": "migrate" } },
      { "acquired_at": 1730000005, "instance_id": "9a2f41c8-6e70-4b13-9d58-3c04f7e2b6a1", "item_id": "s01_08",
        "location": "mail", "serial": 12,
        "source": { "box_seed": 553120994, "draw_index": 7, "kind": "gacha", "series_id": "series_01" } }
    ],
    "serial_counters": { "s01_01": 187, "s01_02": 2, "s01_08": 12 },
    "total_consumed": 186,
    "total_granted": 191
  },
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
    "granted_unlock_ids": { "ms_01:item_category:ore": true }, "milestone_state": { "ms_01": 3, "ms_02": 1 },
    "module_quality_ceiling": 1, "unlocked_item_categories": ["ore", "fiber"], "unlocked_series": ["series_01"],
    "unlocked_series_qualities": [1, 2], "warehouse_capacity": 1000
  },
  "schema_version": 4,
  "saved_at_unix": 1730000010
}
```

### 4.2 实例列表与 `DrawLogEntry` 的关系（v0.8，`[补充]`）

| | 实例列表 `inventory.instances` | `draw_log` |
|---|---|---|
| 回答的问题 | **我现在有什么**：每个物品个体是第几个、何时开出、从哪个盒子来 | **历史上开过什么**：当时的池子与状态是什么样 |
| 范围 | **只含现存实例**（被消耗的实例即消失） | 逐次兑现全量累积（不裁剪，见 Q3 / §6.3） |
| 唯一标识 | `instance_id`（UUIDv4，幂等键） | `seq`（日志序号）+ `seed` |
| 溯源 | `source = {kind, series_id, box_seed, draw_index}` | `{seed, series_id, pool_snapshot, state_snapshot, item_id, quality, is_void}` |
| 体积 | 每实例约 120 B（**`source` 是大头**） | 每条约 0.5–1 KB（`pool_snapshot` 的 `weights_bp` 是大头） |
| 写入方 | **02**（`ItemService`） | 本系统 |

**关系（关键）：** 实例的 `source.box_seed` **指向** `draw_log` 中 `seed` 相同的那一条（`draw_index` 指定同一批内的第几次兑现）。因此**实例只存轻量溯源指针，不重复存 `pool_snapshot`**——审计所需的池子快照全部留在日志里。**推论：不得为了压缩体积而砍掉实例的 `source`**（那会切断实例与日志的对应关系，溯源与收藏编号叙事同时失效）；要省体积先裁剪 `draw_log`（Q3）。

**边界说明：** `pool_snapshot` / `pools` 的字段取自 `05-module-pool.md` §4 的 `PoolState`（`revision` / `socketed` / `socket_count` / `void_mass`），模块编辑明细与其**求值口径**归 `05` / `07-economy-rho.md`，本系统只负责其**持久化布局**；`pity_counter` 的**规则**归 `01-gacha.md`。上例数值仅示意格式，口径一律以 `README.md` §6.1 与 `07-economy-rho.md` §5.4 为准。

## 5. 规则与公式

1. **收录**：`GachaService.roll()` 结算后，本系统记录 `collected[series_id][item_id] = true`；若已收录则 `duplicate_count += 1`（**开出的那个物品本身由 02 落为一个新实例**，见 `02-item.md`；P5「重复永不是空手」由此兑现）。**收录是记录"曾开出过"，不是"现在还持有"**——因此 **`collected` / `duplicate_count` 只增不减，绝不因实例被消耗而回退**（v0.8 裁决见第 13 条）。**空洞 `void` 不产生任何收录效果，也不产生实例**：`void` 不产出物品，**不写图鉴**、**不推进 `series_progress`**、**不改动 `collected`**（因此 `is_collected()` 的返回值不变，即"未拥有物品加权"的状态不受 `void` 影响）、不加 `duplicate_count`、**不推进 `serial_counters`**；它只落进 `draw_log`（`item_id` 为空、`is_void = true`，见 §4.1）。`void` 是否推进 `pity` 归 `01-gacha.md`，本系统不裁决。
2. **缺口**：`gap_count(series_id) = (regular_count(series_id) + 1) - collected_count(series_id)`；`gap_items(series_id)` 返回未收录物品清单。`regular_count` 由该套系的**套系品质**决定（品质 1/2 = 8，品质 3/4 = 12，核心 §4.1.1），**只在运行时从 `SeriesDef` 读取，不得在本系统内写死 8**。核心 §5.5 的收官玩法（把池子编辑到只剩缺口物品）以本清单为唯一依据。
3. **套系进度**：`series_progress` 必须**分列两个数字**——常规 `collected_normal / regular_count` 与隐藏 `collected_hidden ? 1 : 0 / 1`（同样不得写死分母）。**理由（由 C3 推出）**：隐藏物品免疫一切池子编辑（核心 §5.4），并入同一百分比会让玩家以为"靠编辑能收敛它"，与 P4 冲突。
4. **里程碑链**：`MilestoneDef` 依 `order_index` 顺序推进；节点状态见 §7.2；节点达成后由本系统发放 `unlocks`。
5. **解锁发放**：`grant_unlock(payload)` 为**幂等**操作，幂等键 `"{milestone_id}:{kind}:{target_id}"`（`[补充]`：同一载荷重复发放不得重复生效，否则存档不确定）。**五类载荷**与各自的写入目标：

   | `Kind` | 发放后写入 | 语义 | 与其它载荷的关系 |
   |---|---|---|---|
   | `SERIES` | `unlocked_series` | **这个套系能不能开盒**（内容量） | 新池子的入场券 |
   | `ITEM_CATEGORY` | `unlocked_item_categories` | 物品类别开关 | 与位次无关 |
   | `MODULE_QUALITY` | `module_quality_ceiling` | **模块能造多强**（D13，R11 核心载体） | 与下一项是同一成长的两条腿 |
   | **`SERIES_QUALITY_UNLOCK`**（v0.6 新增） | `unlocked_series_qualities` | **这个档位的套系能不能施工**（功率上限） | `magnitude` = 该套系的 `series_quality`（1–4） |
   | **`WAREHOUSE_CAPACITY`**（v0.9 新增） | `warehouse_capacity` | **仓库能装多少**（核心 D15，内容门控） | `magnitude` = **新增容量单位数**（累加，不是目标值）；写入后**只增不减**（§5 第 14 条） |

   **关系与顺序**：`SERIES` 决定"有没有这个池子"，`SERIES_QUALITY_UNLOCK` 决定"这个池子的施工台有多大"。同一里程碑内若两者同时发放，执行顺序为 **`SERIES_QUALITY_UNLOCK` → `SERIES` → 其余**（`[补充]`：避免出现"盒子能开、施工台却未解锁"的中间态——该中间态下无法确定该套系的位次上限，05 会读到未授权的 `SeriesDef.socket_count`）。`MODULE_QUALITY` 与 `SERIES_QUALITY_UNLOCK` 则互为补充：前者决定**模块多强**，后者决定**能装几个**（核心 §4.1.1）。`WAREHOUSE_CAPACITY` 与三者都无耦合：它只与"玩家到此刻为止能囤多少"有关，**不参与任何位次或概率**。
   **发放只写 `unlocked_*` / `unlocked_series_qualities` / `module_quality_ceiling` / `warehouse_capacity`，不直接写入任何位次**：位次永远由对端从 `SeriesDef` 读取（见 §10 的 T4）。容量同理——**本系统只写"解锁到多少"，从不判定"装不装得下"**（判定在 02 的 `grant()` 内部，核心 §4.7）。
6. **全收集判定**：`full_collection_reached = 所有已解锁套系的全部物品（regular_count 个常规物品 + 1 个隐藏物品）均已收录`（`regular_count` 逐套系取自其 `SeriesDef`）。后续释放新套系时，已达成标记**保留**并重新进入收集中状态（`[补充]`：内容释放是持续的，终局必须可重入，否则新内容会"取消"玩家已达成的成就）。
7. **终局表现**（核心 §10.1 / §10.2）：全收集不提供任何数值奖励；其表现是图鉴满格、套系进度满格，以及收官阶段**池子逼近只剩缺口物品**的当前状态仍可随时展开查看。收尾是 **"我算赢了它"**，不是"我终于抽到了"。
8. **阶段判定只用于呈现**：`current_phase` 由 `EvalService` 的 ρ 落入哪一 `ProgressionPhaseDef` 区间决定（`07-economy-rho.md` 是唯一 ρ 口径）。**只读 ρ，绝不直接读池子结构**——`void` 已通过 `v = 0` 压低 `m_bar` 并体现于 ρ，阶段判定因此自动吸收 `void` 的影响，无需（也不得）另行读取 `void_mass`。**阶段判定不得以任何方式影响池子、权重或概率**（P1 铁律 7）。
9. **内容产能即节奏**：`milestone_chain` 的节点数与 `unlocks` 的载荷量，就是玩家进度的**全部**燃料（R11）。任何"没有新载荷可发"的里程碑节点都是设计缺陷，不是配置自由。
10. **套系品质解锁是唯一的功率成长路径（P7 的全部要害，v0.6 新增）**：`max_series_quality = max(unlocked_series_qualities)` 就是玩家**最高能施工到的档位**。这条规则的准确表述是**两句话，缺一即错**：
    - **同一套系内不得增额**：**没有任何**载荷、里程碑、进度、重复劳动或物品消耗可以提高某个**已解锁套系**的 `socket_count` / `device_slot_count`。这半句仍是 P7 的红线（T4）。
    - **跨套系是合法的、也是唯一的成长路径**：解锁更高品质的套系 = 得到一个**更大但池子也更大**的施工台（核心 §4.1.1 要求位子与物品数同步长，否则 C6 失效）。这是 v0.6 新增的主动轴，**是内容释放，不是扩容**。
    - **因此不得写成"位子永远不能增加"**——那会误杀唯一的功率成长路径，把 P7 变成"开盒端永久冻结"（那正是 v0.6 要修掉的问题）。
    - 本系统在此轴上的职责**只有发放**：写入 `unlocked_series_qualities`，不去读写任何位次（§2 / §8.2）。
11. **只持久化现存实例（v0.8）**：存档只序列化**现存实例**——已消耗的实例不写档、不留墓碑（核心 §4.2.2 第 3 条）。**审计由 `draw_log` 承担**：它按核心 §14.2 铁律 7 已逐次记录 `seed` + `pool_snapshot` + `state_snapshot` + `item_id` + `quality`，因此"历史上开过什么、当时池子是什么样"**完全可复算**（T2），不需要实例列表留历史。二者分工见 §4.2：**实例列表回答"我现在有什么"，`draw_log` 回答"历史上开过什么"**。
12. **`serial` 的分配与 `serial_counters`（v0.8）**：`serial_counters` 的结构是 `{item_id: int}`（键序字母序落盘）。分配规则：**开盒产出时，先 `serial_counters[item_id] += 1`，再把该值写进新实例的 `serial`**（首个为 1）；**转化产出、拆卸返还、解锁发放产生的实例 `serial = 0`，且一律不推进 `serial_counters`**（核心 §4.2.3：`serial` 的含义是"该玩家**开出**的第 N 个"，非开盒来源没有编号可给）。
    - **只有开盒产出会 +1**：这是 `serial_counters` 的**唯一**增量来源（写档、读档、结算任务都不得改动它；**唯一例外是 v2 → v3 迁移的一次性回填**，见 §7.4 第 3 条——那是给 v2 的真实持有补发编号，不是"开出"）。
    - **写入方是 02**：`serial_counters` 与实例列表同属 02 的唯一写权限，本系统只定义其**持久化布局**（§2）。
    - **现存实例的 `serial` 可以不连续**（中间那些被交付任务消耗了）——**连续性不是不变量，最大值对齐才是**：恒有 `serial_counters[item_id] == max(现存实例的 serial)`（T16）。
    - **幂等（与第 5 条合起来看）**：`ItemService.grant` **以 `instance_id` 为幂等键**——同一 `instance_id` 重复发放**不得产生第二个实例**（核心 §14.2 铁律 8、README §3.8）。它**不是**靠"读档时去重"实现的，因此不会与 `grant_unlock()` 的幂等键 `"{milestone_id}:{kind}:{target_id}"`（第 5 条）重叠：**实例幂等由 02 按 `instance_id` 保证，解锁幂等由本系统按键保证，二者共同保证读档重放（重放 `draw_log` / 重放解锁发放 / 中断补送 `INTAKE`）不产生重复实例与重复解锁**。
13. **`collected` 与实例列表的关系（v0.8 裁决）**：**保留独立的 `collected` / `duplicate_count` 标记，不由实例列表推导。**
    - **裁决**：`is_collected(series_id, item_id)` **只读 `collected`**，**不得**实现为"实例列表里存在该 `item_id` 的实例"。
    - **理由（三条）**：①**收录是不可逆事实**——"曾开出过"与"现在是否还持有"是两件事；玩家把最后一个该物品交付任务后，实例消失，但**收录不该消失**，否则图鉴会在玩家认真玩游戏时**退格**；②退格会直接摧毁"缺口的半衰期是周"（§1 / §9）与 P1 的可查可算：玩家会看到自己明明开过的物品重新变成剪影，且`is_collected()` 的翻转还会**反向影响 01 的"未拥有物品权重 ×1.5"**（同一物品被反复计成新物品，等于暗中改概率，P1 铁律 7）；③`void` 不写图鉴（第 1 条）已经确立"收录只由开盒产出推进"，与 `serial_counters` 同源，独立标记不必与实例同生命周期。
    - **推论**：`collected`（是否收录）与 `serial_counters`（开出过几个）是**同一类不可逆记账**，都保留；`duplicate_count` 与之同源、同样保留（三者与实例列表的区别见 §4.2）。`serial_counters` 与 `duplicate_count` 是否合并见 §11 Q7（**本系统不得自行合并**）。
    - **上游已采纳（核心 v0.9 裁决 11）**：本裁决已获采纳——**`collected` 保留为独立标记、绝不由实例推导**。同一裁决另定：**未拥有物品权重 ×1.5 与图鉴一律用收藏口径（`collected`，即 `is_collected()`）**；而 02 的 `find_missing_items` 已改名 **`find_unstocked_items`**，口径是 **"当前仓库无持有"**（`count() == 0`，即"能拿得出几个"）。**两者口径不同、不得互相替代**：图鉴与 ×1.5 要"曾开出过"（不因交付任务而回退），任务面板缺口要"现在拿得出来"。本系统只提供前者（`collected` / `is_collected()`），后者归 02。

14. **容量只能由里程碑解锁（核心 D15 的落地，v0.9 新增）**：`warehouse_capacity` 的**唯一增量路径**是 `WAREHOUSE_CAPACITY` 载荷（经 §5 第 5 条的 `grant_unlock()`），起点是初始容量常量（§6.3）。
    - **明确禁止的路径（P7 红线，与位次同源）**：**任何靠消耗物品 / 重复开盒 / 按持有量、开出总数、游玩时长 / 用某类物品或券兑换来增加容量的设计，一律否决。** 理由：核心 §4.1.1 与 P7 已经把"功率成长"锁死在**内容门控**上；容量若可随重复劳动增长，就退化为"刷量指标"，玩家会把开盒从"做决定"改成"刷容量"，中心机制（燃料还是引擎）当场的压力反而被消解。
    - **也不得提供任何"临时扩容 / 扩容道具 / 付费扩容"接口**（核心 §13.2 已排除付费）。
    - **容量只增不减**：不因消耗、迁移、读档或退款而下降；`grant_unlock()` 的幂等键覆盖重复发放（第 5 条）。
    - **容量的占用与溢出判定完全不在本系统**（核心 §4.7：产出溢出判定在 02 的 `grant()` 内部）。本系统在这条轴上的职责**只有发放**——即保证"容量会随里程碑成长"（核心 R14 对策②），而"装不下会怎样"由邮件兜底，**永不丢失**（对策①）。
15. **仓库与邮件是同一个实例列表的两个位置（核心 §14.2 铁律 9，v0.9 新增）**：本系统在存档层只做两件事——**逐条落盘 `location`** 与**落盘 `warehouse_capacity`**。由此推出六条硬约束：
    - **读档不得重算 `location`**：不得按容量重新判定、不得把装不下的实例"顺手"搬进邮件，也不得删除邮件侧实例（那会让持有位置随占用率变化而漂移，并给 02 的 `grant()` 造出第二个判定源）。
    - **`count()` 只统计 `location == warehouse`**——因此 §8.2 中"物品持有量"的核对读到的**天然只含仓库**；本系统**不得**为了对账把邮件实例加回去。
    - **领取只改 `location`**（核心 §4.7）：不创建实例、不重分配 `serial`、不重跑幂等判定；因此**实例数在任何领取操作前后完全不变**（T17 ⑤）。
    - **邮件无上限、不过期**：因此"仓库满了"永远不是死局（核心 R14 对策①）；本系统**不得**给邮件加任何上限、过期或自动清理逻辑。
    - **守恒等式按全部实例（裁决 12，v0.9）**：`total_granted − total_consumed == Σ 全部现存实例`——**含邮件侧**。`count()` 只是**带 `location` 过滤的查询**（`count(c, q, &"warehouse")` 是等式的一个子集，`count(c, q, &"mail")` 是另一个子集，裁决 14），**不得**用仓库口径的 `count()` 去反推总量，也不得据此写"仓库 Σcount == 差值"的断言——那在**有邮件条目时必然失败**（T17 ⑥ / T20）。
    - **只有被动产出会进邮件（裁决 17，v0.9）**：`location == mail` **只**由**被动产出（开盒）**的溢出产生；**主动操作（转化 / 拆卸返还）放不下时整个操作被拒绝**——**不产生实例、不产生任何存档变更**。因此存档层**不存在**"主动操作的失败墓碑"，也**不得**为它写入任何条目（若写，就等于承认"销毁了源、产出进了邮件"的净损失路径）。
16. **主动丢弃是主动行为，不是"产出丢失"（v0.9 裁决 16）**：玩家可主动销毁仓库内任意实例（入口 / 二次确认 / 批量归 `08-ui-panels.md` R-22 / §9.7）。在存档与进度侧，它的记账只有这几条：
    - **只改实例列表与 `total_consumed`**：被丢弃的实例从存档消失（与"被消耗"同一条路径），**守恒等式照常成立**（第 15 条）。
    - **不得回退任何不可逆记账**：`collected` / `duplicate_count` / `serial_counters` **一律不变**（第 13 条：收录是"曾开出过"的事实——交付任务尚且不让它退格，主动丢弃更不能）；图鉴格子**不得**退回剪影。
    - **不得给任何回报**：**不产生**新实例、不返还券、不换算任何资源——否则它会变成第二条产出路径，与"销毁"语义冲突。**它也不写 `draw_log`**（丢弃不是兑现），见 §11 Q11。
    - **P5 不适用于此**：P5 管的是**被动产出不得丢失**；丢弃是玩家**主动**行为（核心裁决 16）。本系统**不得**以"违反 P5"为由拒绝提供丢弃路径——**没有它，"仓库满"会变死局**。

## 6. 参数表（推荐值 + 调参旋钮标记）

### 6.1 结构与解锁节奏

| 参数 | 推荐值 | 🔧 | 说明 |
|---|---|---|---|
| 已释放套系总数 | 切片 1 / 目标 6–8 | 🔧 | 内容量 = 进度容量（R11） |
| **套系品质档位数 / 已解锁最高档** | 切片只出 1 档（**品质 2**，核心 §13.1）/ 目标 4 档 | 🔧 ★ | **直接决定 ρ 上限**——档位上限即施工台功率上限（§5 第 10 条）；4 档是否全出见 §11 Q5 |
| 模块品质档位数 / `module_quality_ceiling` 初始值 | 4 档 / 初始 1 | 🔧 | 开局只能产出最低档模块（核心 §14.3） |
| **D13 · 模块品质释放节奏** | **每 2 个里程碑 +1 档**（1→4 共 6 节点） | 🔧 ★ | **R11 关键**：这是内容释放的主要载体，不由里程碑一次性全开 |
| 里程碑链节点数 | 切片 1 / 目标 8–10 | 🔧 | 与内容产能同阶 |
| **仓库容量初始值 / 解锁节奏（v0.9，核心 D15 / D16）** | 初始 **1000**（示意）/ **每 2 个里程碑 +500** | 🔧 ★ | **内容门控**：容量只能由里程碑解锁（§5 第 14 条）；数值须与 `ItemDef.size`、任务需求向量、开盒产出量**一起标定**，切片阶段实测（核心 D16） |
| 解锁顺序模板 | 新物品类别 → 模块品质 +1 → 新套系 + 套系品质解锁 → 模块品质 +1 → … | 🔧 | 交错释放，避免同类内容断层（R7）；**品质梯度不宜过陡**（§11 Q6 / 核心 R13） |

### 6.2 进度节奏表（核心 §10.2 的数据化）

| 阶段 | `rho_min`（含） | `rho_max`（不含） | **最高套系品质**（决定 ρ 上限） | 池子状态 | 收集状态 | 预期释放 |
|---|---|---|---|---|---|---|
| 开局 `opening` | 0.0 | 0.9 🔧 | 1（8 个常规物品 / 2 位） | 原始池 | 零星几个物品 | 无 |
| 破局 `breakthrough` | 0.9 🔧 | 1.1 🔧 | 1（8 个常规物品 / 2 位） | 首次镶嵌（排除无用物品） | 首个套系过半 | 新物品类别 |
| 起飞 `takeoff` | 1.1 | 3.0 | **2**（8 个常规物品 / 3 位） | 模块开始集中概率 | 快速补全前期套系 | 模块品质 +1 / 新套系 + 套系品质解锁 |
| 工程期 `engineering` | 3.0 | 10.0 | **3**（12 个常规物品 / 4 位） | 每次镶嵌都是替换（核心 §3.3） | 长尾物品显形 | 模块品质 +2 / 套系品质解锁 |
| 收官 `endgame` | 10.0 | 0.0（无上界） | **4**（12 个常规物品 / 5 位） | 池子逼近只剩缺口物品 | 集齐（隐藏物品除外） | 最后解锁 + 全收集 |

**最高套系品质列（v0.6 新增）就是 ρ 上限的直接来源**：核心 §2.4 中"跨套系才增长"的功率在这一列上被落成节奏——玩家在某一阶段最高能施工到哪一档，决定他此刻的位子上限，从而决定 ρ 能爬到哪。档位对应的物品数 / 位数取自核心 §4.1.1（🔧 旋钮）。
ρ 区间为 🔧 旋钮，必须**无重叠、无空隙**地覆盖 `[0, ∞)`；阶段判定只读 `EvalService` 的 ρ（`void` 压低 `m_bar` 的效果已含在 ρ 内，见 §5 第 8 条），**最高套系品质**、池子状态与收集状态三列只作文案与验收对照，不参与计算。

### 6.3 存档

| 参数 | 推荐值 | 🔧 | 说明 |
|---|---|---|---|
| 存档路径 | `user://save.json`（+ `save.bak`） | — | 核心 §14.1 `save_service.gd` |
| `draw_log` 保留条数 | 首发不裁剪 | 🔧 | 裁剪策略未定，见 §11；**不得静默裁剪** |
| 自动存档时机 | 每次兑现后、每次解锁发放后 | 🔧 | 保证 `draw_log` 与图鉴不脱节 |
| **每实例存档体积（v0.8）** | **约 120 B**（`instance_id` UUID 约 36 B + `item_id` + `acquired_at` + `serial` + **`source`（大头）**） | — | 核心 §4.2.2 第 4 条。**不得为省体积砍 `source`**（切断与 `draw_log` 的对应，见 §4.2）；要省先裁 `draw_log`（Q3） |
| **5000 现存实例的实例区体积（v0.8）** | **约 600 KB** | — | **估算值**，必须实测：见 §11 **Q8**（切片阶段必做） |
| **`serial` 分配口径（v0.8）** | `serial = serial_counters[item_id]` 自增后的值；非开盒来源固定 `0` | ❌ | **非旋钮**：编号必须与实例自洽（§5 第 12 条 / T16） |
| **`location` 的存档开销（v0.9）** | 每实例 **约 +20 B**（`"location": "warehouse"`） | — | 核心 §14.2 铁律 9。**不得为省体积省略该键**——省略等于丢掉"这件东西在哪儿"的事实，读档后要么丢实例（违反 P5）要么必须反推（把派生值变成事实来源）。体积实测并入 Q8 |
| **`warehouse_capacity` 的存档（v0.9）** | 单个整数（`progression.warehouse_capacity`） | ❌ | **非旋钮**：容量是**解锁进度**，必须入档且只增不减（§5 第 14 条 / T19）；不得由 `size` 之和或持有量推导 |

## 7. 流程 / 状态机

### 7.1 收录流程

```
GachaService.roll() 结算（01）
  ──▶ 02 落实例（ItemService.grant）：新 UUIDv4 + acquired_at + source{kind: &"gacha", …} + serial（= serial_counters +1）
  ──▶ 本系统 record_result(series_id, result)
      ├─ result.is_void → **无实例**；图鉴 / series_progress / collected / duplicate_count / serial_counters 全不变（§5 第 1 条）
      ├─ 首次收录 → collected = true → 重算 gap_count → 图鉴点亮
      └─ 重复     → duplicate_count += 1（实例本身已由 02 持有，见 02-item.md）
  ──▶ 本系统 append_draw_log({seed, pool_snapshot, state_snapshot, item_id, is_void, quality})
  ──▶ 重算 current_phase（只读 EvalService 的 ρ，纯呈现）
```

**顺序是硬的（v0.8）：** **02 先创建实例（含分配 `serial`），本系统再记图鉴与日志**——若反过来，`draw_log` 会记录一次"图鉴已收录但实例不存在"的中间态，中断补送时无法判定幂等。`void` 是唯一不产生实例的分支。

### 7.2 里程碑链状态机

```
LOCKED ──(requires 全部 COMPLETED)──▶ AVAILABLE ──(03 受理任务)──▶ IN_PROGRESS
                                          └─(03 结算 TaskDef）──▶ 本系统 grant_unlock() ──▶ COMPLETED
```

同一节点内两个写入方**顺序固定**：`03 先结算 TaskDef.rewards` → `本系统后发放 MilestoneDef.unlocks`（`[补充]`：同一事务内两个写入方的顺序必须确定，否则存档字节级不稳定）。状态取值 `LOCKED=0 / AVAILABLE=1 / IN_PROGRESS=2 / COMPLETED=3`。

### 7.3 全收集状态机

```
COLLECTING ──(所有已解锁套系的 regular_count 个常规物品全部集齐)──▶ NORMAL_COMPLETE   ← 对应 §6.2「收官」的收集状态
           ──(隐藏物品亦收录)────────────────▶ FULL_COLLECTION
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
**v1 → v2 迁移（v0.6，`[补充]`）**：v1 档没有套系品质概念，迁移时 ① 为每个 `pools` / `pool_snapshot` 条目按其 `series_id` 回填 `series_quality` 与 `regular_count`（取自 `SeriesDef`，与 v0.5 的 8 个常规物品 / 3 位一致 → 品质 2）；② 回填 `unlocked_series_qualities = [1..该档最高品质]`（**只增不减**，与"玩家已解锁套系的最高档"对齐，保证最高可施工档位不因升级存档而回退）。理由是迁移必须把新进度轴的还原点补齐，否则读档后 P7 的档位不可判定。

**v2 → v3 迁移（v0.8，`[补充]`）**：v2 档把持有量存为"每个 `(category, quality)` 一行计数"（`inventory.counts`，**没有实例**）。v2 → v3 的规则**必须确定、必须保量、必须幂等**：

1. **展开计数为实例**：对持有量块的每个 `"<category>:<quality>"` 键（v2 的 `entry_key` 形态；本文记该块为 `inventory.counts`，旧档若键名不同按此形态识别），按其 `count` 生成 **N 个实例**（N = 该键的 `count`）。v2 档若**完全不含**持有量块，则迁移得到空实例列表（不是错误）。
2. **`item_id` 的取法**：v2 的键**不含 `item_id`**，故取**该 `(category, quality)` 下 `item_id` 字典序最小者**（来自 `ItemDef` 表）。这是**有损但保量**：迁移后该键的实例数 == v2 的 `count`，因此**数量与 ρ 完全不受影响**；丢掉的只是 v2 **从未记录过**的字段（`serial` / `acquired_at` / `source`）。
3. **`serial` 依次回填（与 `serial_counters` 对齐）**：对每个 `item_id`，其 N 个实例按 **`serial = 1 … N`** 依次分配（`acquired_at` 相同，故以数组下标为序），并回填 **`serial_counters[item_id] = N`**——迁移后恒有 `serial_counters == max(现存实例的 serial)`（T16）。**`duplicate_count` 不得用于回填 `serial` / `serial_counters`**：它可能大于现存实例数（消耗过的实例不计入 `count`），拿它回填会让编号越过实例，破坏自洽。
4. **`acquired_at` 取迁移时刻**（Unix 秒，同一批同一值）。理由：v2 无法还原历史时刻；取迁移时刻可保证该字段非零、可排序、可显示（呈现规格见 `08-ui-panels.md` §9.3b）。
5. **`source` 一律记为 `{ kind: &"migrate" }`**（核心 v0.9 裁决 4 的取值；旧稿的 `&"migration"` 作废）。理由：迁入的实例**不是开盒产出**，不得伪装成 `kind: &"gacha"`（否则溯源会指向不存在的 `box_seed` / `draw_index`，并让"来自哪个盒子"显示假信息）。其**呈现必须与开盒实例可区分**（`kind != &"gacha"` 即天然可分，规格归 08）。
6. **迁移幂等**：迁移完成后 `schema_version` 即为 3，**再跑一次必须不产生重复实例**（已为 v3 的档不进本迁移）；`item_id` 选取、`serial` 分配、`acquired_at` 取值三步**全部是确定性的**（同输入必得同输出），因此"迁移 → 往返 → 再迁移"字节级稳定（T15）。
7. **`collected` / `duplicate_count` / `draw_log` / `pools` 一律原样保留**，**不得**由实例列表推导或重算（§5 第 13 条）。

**v3 → v4 迁移（v0.9，`[补充]`）**：v3 档有实例列表，但**没有 `location`、也没有仓库容量**。规则同样必须**确定、保量、幂等**，且**绝不丢弃**：

1. **`location` 一律回填 `&"warehouse"`（本系统的裁决）。** 理由：v3 的实例语义就是"我持有的东西"，v3 既无容量也无邮件；把它们直接回填成 `mail`，会让玩家的持有**在一瞬间失去可用性**（邮件实例不可用于交付 / 装配 / 镶嵌 / 转化，核心 §4.7），读起来就是"东西被没收了"——与 P5 的立意直接冲突。**"默认全部留在玩家手里"是唯一不制造负体验的默认值**；真装不下时再由第 3 条按确定性规则处理，且那部分**可领取、不丢失**。
2. **容量初始值的定息**：`warehouse_capacity = WAREHOUSE_CAPACITY_INIT + Σ（该档 `milestone_state` 中已 COMPLETED 的里程碑所携带的 WAREHOUSE_CAPACITY 载荷的 magnitude）`，按 `MilestoneChainDef` 顺序累加，**下限 `WAREHOUSE_CAPACITY_INIT`**。理由：容量是**内容门控的进度**（§5 第 14 条），迁移必须还原"玩家已走到哪一步"，而不是一律打回初始容量——后者会让所有老档当场爆仓，也会让同一条进度轴在迁移前后**回退**（与 v1 → v2 回填 `unlocked_series_qualities` 的理由完全同源）。
3. **若迁移后 `Σ size(仓库侧实例) > warehouse_capacity`：按 `acquired_at` 升序保留，其余转 `mail`。** 逐实例贪心：按 `acquired_at` 升序累加 `size`，**累加值 ≤ 容量**的实例留在 `warehouse`，**第一个越界的实例及其后全部改为 `mail`**（同刻按 `instance_id` 字典序，与 `02-item.md` §5.5 同一打破规则，保证确定性）。两条禁令：**不得为迁就持有量而上调容量**（那等于承认"靠堆积换容量"，违反 §5 第 14 条 / P7）；**更不得丢弃任何实例**——**实例总数在迁移前后必须完全相等**（T18），这是核心 v0.9 的"装不下就进邮件 ⇒ 产出永不丢失"在存档层的落点。
4. **迁移只写两个字段**：逐实例写 `location`、写 `progression.warehouse_capacity`。`instance_id` / `item_id` / `acquired_at` / `serial` / `source` / `serial_counters` / `collected` / `duplicate_count` / `draw_log` / `pools` **一律原样保留**（延续 v2 → v3 第 7 条的精神）。**不得**借迁移顺手"修正" `serial` 或重算图鉴。
5. **迁移幂等**：迁移完成后 `schema_version` 即为 4，**再跑一次不得产生任何 `location` 或容量的变化**；第 1 / 2 / 3 步**全部确定性**（同输入必得同输出），因此"迁移 → 往返 → 再迁移"字节级稳定（T18）。
6. **邮件侧不是死局（必须一并说明）**：核心 §4.7 已定"**消耗类主动操作不检查空间**"——玩家把仓库里的物品交付 / 装配 / 镶嵌 / 转化腾出空间后即可领取邮件，容量还会随里程碑继续增长。因此第 3 条产生的邮件条目**不构成进度损失**；呈现层需在首次进入时给出一次说明（`08-ui-panels.md` §9.7）。

> **v0.9 迁移的代价必须说清**：v3 档**不存在"物品在哪儿"这个事实**，所以 v4 的 `location` 是**按确定规则重建**的位置，不是历史真实位置；同理容量是按里程碑进度**定息**的，不是 v3 曾经有过的数。这是最小损失的可行规则——任何"看起来更真实"的逐实例猜测都是编造。**唯一不可妥协的是数量守恒**：迁入实例数 == v3 的实例数。

> **迁移的代价必须说清**：v2 的计数**无法还原**具体 `item_id` 的归属与真实开盒时刻，所以 v2 玩家的 `serial` 是**从迁移时刻的持有量连续编号**的（不是历史真实编号），且迁入实例的 `source` 只有 `kind`。这是**最小损失的可行规则**——v2 存档里根本不存在这些信息，任何"看起来更真实"的回填都是编造。

## 8. 与其它系统的接口

### 8.1 里程碑任务链的归属裁决（与 `03-task.md` 的边界）

> **裁决：链骨架归 10，需求与奖励结算归 03。**

| 归谁 | 拥有什么 |
|---|---|
| **10 收集与进度** | `MilestoneChainDef` / `MilestoneDef`：**链的顺序、前置条件、解锁载荷 `unlocks`、未达成预告 `teaser`、发放动作 `grant_unlock()`** |
| **03 任务** | `TaskDef`（经 `MilestoneDef.task_def_id` 指向）：**需求向量匹配、物品扣减、`TaskDef.rewards` 结算（盲盒 / 券）** |
| **共有义务** | 同一任务的两个写入方按 §7.2 固定顺序执行，各自只写自己拥有的数据（README 铁律 2） |

**红线**：`TaskDef.rewards` **不得**包含任何内容释放载荷（新套系 / 新类别 / 模块品质）。内容释放只有一条发放路径：`MilestoneDef.unlocks` → `grant_unlock()`。否则解锁会出现第二个写入源，存档将不可复现。

### 8.2 接口清单

| 方向 | 接口 | 对端 |
|---|---|---|
| 提供 | `is_collected(series_id, item_id) -> bool`（供"未拥有物品权重 ×1.5"判定）；`is_series_unlocked(series_id)` | 01 |
| 提供 | `module_quality_ceiling` / `can_produce_module(module_def) -> bool` | 05 |
| 提供 | `max_series_quality() -> int` / `is_series_quality_unlocked(q) -> bool`（**最高可施工档位**，只读；本系统不写位次） | 05 / 01 |
| 提供 | `is_item_category_unlocked(category)` | 02（`02-item.md`）/ 06 |
| 提供 | `gap_items(series_id)` / `series_progress(series_id)` / `codex_state()`；`current_phase`、`milestone_state`、`full_collection_reached` | 08 / 03 |
| 提供 | `snapshot_state() -> Dictionary`（= `state_snapshot`） | 01 / 07 |
| 提供 | `collected` / `is_collected()` / `duplicate_count`（**图鉴收录与重复次数；不可逆，不由实例列表推导**，§5 第 13 条） | 01 / 08 |
| 提供 | `serial_counters` 的**持久化布局**（字段与键序；**写入仍归 02**）`[补充]` | 02（`ItemService`） |
| 提供 | `warehouse_capacity` 的**发放与持久化布局**（容量数值只能由里程碑解锁，§5 第 14 条；**占用 / 溢出判定归 02**）`[补充]` | 02（`ItemService`）/ 08（占比换算与呈现） |
| 消费 | `TaskService.task_completed(task_id)` 信号 → 若属里程碑链则 `grant_unlock()` | 03 |
| 消费 | `GachaService.roll()` 结果 → `record_collection()` + `append_draw_log()`（**实例的创建在同一次兑现中由 02 完成，本系统不读写实例列表，只在 `serial_counters` 的落盘布局上与 02 对齐**） | 01 |
| 消费 | `EvalService.compute(state).rho` → `current_phase`（**只读，不得回写**） | 07 |
| 消费 | `PoolService.get_pool_state(series_id)` → `pool_snapshot` | 05 |
| 消费 | `ItemService` 的**现存实例列表**（只读）→ 存档序列化（**含 `location`**）；`ItemService.count(category, quality)`（派生值，**只统计 `location == warehouse`**，v0.9）→ 套系 / 图鉴侧的核对；`count(category, quality, &"mail")`（裁决 14，仅在需要显示"邮件侧持有"时**显式查询**，不得与仓库读数相加）；`ItemService.warehouse_capacity`（只读）→ 存档序列化 | 02 |

## 9. UI 需求

呈现规格与布局见 `08-ui-panels.md`；本系统**要求必须呈现**以下信息（对应核心 §14.1 的 `scenes/collection/`）：

| 面板 | 必须呈现 | 理由 |
|---|---|---|
| **图鉴 `Codex`** | 按套系分组的 `regular_count + 1` 格（品质 1/2 为 9 格，品质 3/4 为 13 格）；**未收录物品以占位剪影常驻可见**；缺口计数与缺口清单**默认展开，不得折叠**；任何一屏都要能一眼看到"还差几个物品"。**v0.8：收录不可逆**——已消耗的实例**不得**让格子退回剪影（§5 第 13 条） | 缺口可见性是硬要求（§1）；缺口半衰期是周 |
| **套系进度** | 常规 `x / regular_count` 与隐藏 `0 或 1` **分列两个数字**；可施工档位（`max_series_quality()`）与各位次的占用可见 | C3：隐藏物品免疫编辑，合并会误导（§5 第 3 条）；v0.6：分母随套系品质变，且玩家必须看得见自己的施工台上限（P7 的呈现面） |
| **里程碑链** | 节点列表、当前节点、**未达成节点的 `teaser` 预告** | R11 + R7：内容释放必须被玩家感知，否则 ρ 涨了也"毫无感觉" |
| **全收集表现** | 图鉴满格标记；收官阶段可展开查看"池子逼近只剩缺口物品"的当前状态 | 核心 §10.1「我算赢了它」 |
| **实例的编号与溯源（v0.8，转交 08）** | 本系统不做呈现，但**必须提供**：现存实例列表（`serial` / `acquired_at` / `source` / **`location`**）与 `serial_counters` 读档还原值；`serial == 0` 与 `kind == &"migrate"` 的实例呈现规格归 `08-ui-panels.md` §9.3b。**v0.9**：图鉴 / 套系进度**不得**因**主动丢弃**而退格（§5 第 16 条；丢弃是主动行为，与"交付消耗"同样是"不再持有"，不是"未收录"） | v0.8 的收藏叙事价值（核心 §4.2.1）；读者要知道"这是你的第 N 个"从哪来 |
| **仓库占用与邮件（v0.9，转交 08）** | 本系统不做呈现，但**必须提供**：`warehouse_capacity` 的当前值（占比换算、阈值与线框图归 `08-ui-panels.md` §9.7）；图鉴 / 套系进度侧的持有核对一律走**仓库口径**（`count()`），**邮件侧实例不得计入** | 容量是解锁进度（P1 要求可查）；**邮件不是第二个仓库**（核心 §4.7 的边界必须由界面兑现，而不是让玩家点了才失败） |

## 10. 测试点与验收标准

| # | 测试 | 判据 |
|---|---|---|
| T1 ★ | **存档往返一致性** | 存 → 读 → 存，连续 10 轮，`save.json` **字节级完全一致**（哈希相同）；键序稳定（`JSON.stringify(sort_keys = true)`） |
| T2 ★ | **池子快照可复现抽取（必须覆盖 `void`）** | 对 `draw_log` 中**每一条**记录，用其 `pool_snapshot` + `seed` 重跑 `GachaService.roll(series_id, pool_snapshot, seed)`，`item_id` 与 `quality` 必须与日志一致（100% 命中，0 例外）。**含 `void` 的记录必须同样命中**：`pool_snapshot` 一旦漏记 `void_mass`，`void` 就抽不出来（或被误抽成某个物品），这是 `void` 引入后最容易漏的一条。用例集**必须显式包含**至少 1 条 `is_void == true` 的记录 |
| T3 ★ | **版本迁移** | 用 v1 存档跑 `migrate_v1_to_v2()`：① 红线（含 C4 / C6）仍成立，且 `series_quality` / `regular_count` / `unlocked_series_qualities` 已按 §7.4 回填（不是默认值） ② 迁移后往返仍字节级稳定 ③ 迁移幂等（再迁移一次无变化） |
| T4 ★ | **红线 C4 不得被解锁破坏（逐套系断言）** | 遍历整条里程碑链，全部达成后，**对每一个已解锁套系**断言 `pool_state.socket_count == 该套系 SeriesDef.socket_count`（`device_slot_count` 同理）。**跨套系不同是合法的**——那正是 v0.6 唯一合法的功率成长路径（§5 第 10 条）；**同一套系内被改变才是失败**。实现必须**逐套系**取各自的 `SeriesDef` 比对，不得只比对某个"全局位数"或某个硬编码常数。**本系统是最容易偷偷加位次的地方（P7），此测试为强制项** |
| T5 | **红线 + 序列化不改权重 / `void`** | 任意解锁、任意阶段下 C1（口径已修订为 `Σp_常规 + void_prob ≤ 0.98`，见 `README.md` §6.1）/ C2 / C3 / C4 按 `05-module-pool.md` / `07-economy-rho.md` 的定义口径成立；本系统另行断言 `weights_bp` 与 `void_mass` 经存 → 读 → 存后**逐项完全相等**（序列化不得引入量化误差，也不得让 `void` 被吸收或重新推导） |
| T6 | **阶段判定不改概率 / 发放幂等** | ① 手动构造落入五个阶段的状态，同一 `pool_state` 的分布哈希必须相同（防"按进度暗改爆率"，P1 铁律 7）；② 同一 `unlock_key` 重复发放 100 次，`unlocked_*`、`unlocked_series_qualities` 与 `module_quality_ceiling` 不变 |
| T8 | **缺口可见性与完成度分列 / `void` 不改收集状态** | ① 未收录物品在默认视图可见、无折叠路径可隐藏缺口、`gap_count` 与实际未收录数一致；② 隐藏物品未收录时 `series_progress` 的常规数字不受影响，常规 `regular_count / regular_count` 满格时 `NORMAL_COMPLETE` 成立而 `full_collection_reached` 仍为假（**两个品质档位各验一次**：8 个常规物品与 12 个常规物品）；③ 对同一池子先后制造 `void` 结果与正常结果，`void` 那一次使 `collected` / `duplicate_count` / `gap_count` / `series_progress` **逐项不变**，且 `is_collected()` 的返回值不变（§5 第 1 条） |
| T10 ★ | **含 `void` 的存档往返一致性** | 构造 `void_mass > 0` 且 `draw_log` 含 `is_void == true` 条目的存档，存 → 读 → 存连续 10 轮**字节级稳定**；断言 `void_mass` / `revision` / `socketed` / `socket_count` 与逐物品 `weights_bp` 逐项完全相等，且 `void_mass` 不得在读档时被丢弃、取整或由 `weights_bp` 反推 |
| T11 ★ | **红线 C6 在任何解锁进度下不得被破坏（v0.6 新增）** | 对**任意解锁进度**、**任意合法 `PoolState`**，断言**可产出常规物品数 ≥ 3**（口径见 `05-module-pool.md` / `07-economy-rho.md`）。用例集**必须覆盖每个品质档位**（8 个常规物品与 12 个常规物品各至少一例），并覆盖"排除已到上限"的极值池：品质 1/2 最多排除 5 个物品、品质 3/4 最多排除 9 个物品，各自排除到极限后仍须留下 ≥ 3 个可产出物品 |
| T12 ★ | **含多档品质套系存档的往返一致性（v0.6 新增）** | 构造**同时含多个不同 `series_quality` 套系**的存档（至少覆盖 8 个常规物品与 12 个常规物品各一），存 → 读 → 存连续 10 轮**字节级稳定**；断言每个 `pool_snapshot` / `pools` 条目的 `series_quality` 与 `regular_count` **逐项完全相等、不丢失、不被推导**（不得由 `weights_bp` 键数反推，也不得读档时按"当前最高档"统一改写），且读档后 `max(unlocked_series_qualities)` 与写档前一致（**P7 的还原点**：玩家最高能施工到什么档位不得因存档往返而变化） |
| T13 ★ | **实例列表往返字节级稳定（v0.8 新增）** | 构造含**多个实例**的存档（至少覆盖：`serial ≥ 1` 的开盒实例、`serial == 0` 的转化 / 返还实例、`kind == &"migrate"` 实例、同一 `item_id` 多实例），存 → 读 → 存连续 10 轮 `save.json` **字节级完全一致**；断言 `instance_id` / `item_id` / `acquired_at` / `serial` / `source`（含 `box_seed` / `draw_index` / `kind`）**逐项完全相等**，`inventory.serial_counters` 逐项相等且**未被读档重算**；断言**已消耗的实例不在档内**（无墓碑条目） |
| T14 ★ | **含 `serial == 0` 实例的存档往返（v0.8 新增）** | 单独构造由**转化产出**与**拆卸返还**产生的实例（`serial == 0`、`source.kind == &"convert"` / `&"refund"`），往返 10 轮后断言：①`serial` **仍为 0**——不得被"修正"为 ≥ 1、不得被 `serial_counters` 覆盖；②`source.kind` 未被改成 `&"gacha"`；③`serial_counters` **未因它们变化**（非开盒来源不推进计数器，§5 第 12 条）；④这几条实例**不影响** `max(serial)` 的对齐断言（T16） |
| T15 ★ | **v2 → v3 迁移幂等（v0.8 新增）** | 用 v2 档（含持有量块的 `(category, quality)` 计数）跑 `migrate_v2_to_v3()`：①**保量**——每个键迁移后的实例数 == v2 的 `count`，且 `Σ` 各 `(category, quality)` 的实例数 == 迁移前的派生持有量（不得多、不得少）；②**幂等**——对同一档重复调用迁移、或对已是 v3 的档再迁移，**不产生重复实例**，实例总数不变；③迁移后往返 10 轮字节级稳定；④`collected` / `duplicate_count` / `draw_log` / `pools` **逐项未被改写**；⑤全部迁入实例的 `source.kind == &"migrate"`、`serial ≥ 1`（按 §7.4 第 3 条依次分配） |
| T16 ★ | **迁移后 `serial_counters` 与实例 `serial` 最大值一致（v0.8 新增）** | ①对每个 `item_id` 断言 `serial_counters[item_id] == max(该 item_id 现存实例的 serial)`（**无实例时为 0**），且**恒不小于**任何现存实例的 `serial`；②**`serial == 0` 的实例不参与该最大值**；③迁移后立即成立，继续开盒一次后恰为 `max + 1`，新实例 `serial == max + 1`；④把该物品的实例**全部交付任务消耗**后再开盒：`serial_counters` **不回退**（不因 `max(现存) == 0` 而归零，§4 的 `serial_counters` 持久化理由） |
| T17 ★ | **含 `location == mail` 实例的存档往返（v0.9 新增）** | 构造同时含 `location == "warehouse"` 与 `location == "mail"` 实例的存档（至少覆盖：开盒入仓库、**溢出进邮件的开盒实例**、`serial == 0` 的转化实例、`migrate` 实例），存 → 读 → 存连续 10 轮 `save.json` **字节级完全一致**：①每条实例的 `location` 逐项相等且**未被读档重算**（按容量反推位置、把装不下的"顺手"搬进邮件、读档自动领取——三者任一发生即失败）；②`progression.warehouse_capacity` 逐项相等；③**实例总数守恒**（`warehouse` + `mail` 之和在往返前后完全不变）；④`count()` **只统计仓库侧**——断言其值 == 仓库侧实例数，且**邮件侧实例不参与**（把邮件实例计入即失败，核心 §4.7 边界 1 / §14.2 铁律 9）；⑤**领取只改 `location`**：对任一条邮件实例执行领取，断言 `instance_id` / `item_id` / `acquired_at` / `serial` / `source` **逐位不变**、实例总数不变、`serial_counters` 不变；⑥**守恒等式（裁决 12）**：断言 `total_granted − total_consumed == 实例总数（仓库 + 邮件）`，并在**往返前后 / 领取前后**逐次成立——**不得**写成"仓库 Σcount == 差值"（那只是等式的一个子集，有邮件条目时必然失败） | **仓库与邮件是同一份数据的两个位置**，不是两份表；位置丢在存档层 = 产出丢失（核心 v0.9 P5 兜底） |
| T18 ★ | **v3 → v4 迁移不丢实例（数量守恒，v0.9 新增）** | 用 v3 档（有实例列表，**无 `location`、无 `warehouse_capacity`**）跑 `migrate_v3_to_v4()`：①**保量**——迁移后的实例数 **== 迁移前**的实例数（不得多、不得少、**不得丢弃**）；②`location` 回填规则逐条成立：默认全为 `warehouse`；**若超容则按 `acquired_at` 升序保留、其余转 `mail`**（同刻按 `instance_id` 字典序），且断言 `Σ size(warehouse) ≤ warehouse_capacity`；③容量 == `WAREHOUSE_CAPACITY_INIT + Σ 已 COMPLETED 里程碑的容量载荷`，**下限为初始值**，且**绝不因持有量而上调**；④**幂等**——重复调用、或对已是 v4 的档再迁移，`location` 与容量**零变化**；⑤`instance_id` / `serial` / `source` / `serial_counters` / `collected` / `duplicate_count` / `draw_log` / `pools` **逐项未被改写**；⑥迁移后往返 10 轮字节级稳定 | **迁移绝不丢弃**（核心 §4.7"产出永不丢失"）；`location` 回填按 §7.4 的裁决 |
| T19 ★ | **容量解锁与占用占比一致（v0.9 新增）** | ①发放一个 `WAREHOUSE_CAPACITY` 载荷后，`warehouse_capacity` 恰为 `原值 + magnitude`（**累加语义**，不是覆盖）；②**P7 断言**：静态检查确认容量**只有** `grant_unlock()` 一条写入路径，**不存在**靠消耗物品 / 重复开盒 / 按持有量 / 按游玩时长 / 用券兑换改变容量的接口，且容量**只增不减**（消耗、领取、迁移、读档后均不下降）；③UI 侧的占用占比（已用 ÷ 容量，呈现规格归 `08-ui-panels.md` §9.7）与 02 的 `warehouse_usage()` **逐项相等**，并在**容量解锁前后**、**领取前后**、**消耗物品前后**各验一次（分子分母都必须跟着变）；④**容量边界处不得出现"显示还能放但实际放不下"**：构造 `剩余容量 == 某物品 size` 的临界存档，UI 提示与 `grant()` 的实际落位（`warehouse` / `mail`）必须**一致** | 容量必须与 P7 一致地**内容门控**（§5 第 14 条）；R14 的对策③建立在"提示可信"之上 |
| T20 ★ | **主动丢弃的记账正确性（v0.9 裁决 16 / 12 新增）** | 丢弃 N 个仓库实例后：①实例总数 **−N**、`total_consumed` **+N**，守恒等式 `total_granted − total_consumed == 全部实例数（含邮件）` 仍成立；②`collected` / `duplicate_count` / `serial_counters` **逐项不变**，图鉴格子**不退回剪影**（第 13 / 16 条）；③被丢弃的实例**不在档内**（无墓碑，与"只持久化现存实例"一致）；④**无任何回报**：`total_granted` 不变、无新实例、无券；⑤`draw_log` **不新增条目**（丢弃不是兑现）；⑥丢弃是**纯主动**路径：静态检查确认全库不存在除玩家确认流程之外的 `&"discard"` 调用（**不得**有任何"自动丢弃"实现） | P5 管被动、丢弃是主动（裁决 16）；守恒等式必须含邮件（裁决 12） |

**切片失败信号（本系统相关，配合核心 §13.4）：**

- 测试者**找不到缺口在哪** → 图鉴失败（缺口可见性未达标，本系统最严重的失败）；**说不出"下一个解锁是什么"** → `teaser` 预告失败，R11 的可感知性未落地；
- 测试者解锁新套系 / 新品质（含**套系品质**档位）后**毫不知情，或 ρ 无变化** → 内容释放未接上经济，R11 直接命中；
- 测试者认为"全收集就是抽到就完" → 终局表现失败，核心 §10.1 的"我算赢了它"未兑现；
- **测试者说"东西不见了"、或认为邮件里的物品已经不属于自己**（v0.9）→ 兜底未被理解（核心 R14 对策①）：检查 ①容量占比是否可见（`08-ui-panels.md` §9.7）②演出是否告知"本件已存入邮件"（`09-presentation.md` §5.9）③邮件条目的禁用态是否给出说明（08 §9.7）。**处置：改呈现，不得靠调大容量掩盖**；
- **测试者因为"仓库满了"而不敢开盒**（v0.9）→ 核心 R14 直接命中（v0.9 的首要新风险）：检查容量是否随里程碑持续成长（§5 第 14 条）与开盒前的保守提示是否可信（08 §9.7 / R14 对策③）；
- **T1 / T2 任一失败** → 直接阻塞发布：核心 §13.1 的"开箱日志（seed + 池子快照 + 结果）"与 P1 的可查可算承诺同时失效。

## 11. 待定项

| # | 待定项 | 影响 |
|---|---|---|
| Q1 | **D13 的具体节奏**（每 2 个里程碑 +1 档？按套系释放？） | ⛔ R11 关键，需与内容产能同步排期；核心 D13 未决 |
| Q2 | **全收集之后有什么**（核心未定义通关后内容） | 本系统只判定与呈现，**不得在此处私加新机制** |
| Q3 | `draw_log` 的裁剪策略与存档体积上限；图鉴是否需要物品文案 / 成就系统 | 前者会削弱 P1 的审计能力，需显式决策，**禁止静默裁剪**；后者核心 §13.2 已排除成就，需另行立项 |
| Q4 | 数据版本迁移的正式策略（跨大版本兼容承诺）；存档导入导出 / 云存档 | 前者影响存档格式冻结时点；后者核心已定"暂不做" |
| Q5 ★ | **套系品质梯度的释放节奏**（v0.6 新增）：第 2 档排在第几个里程碑？第 3 / 4 档要不要全出，还是止步于 3 档 | ⛔ **R11 关键**——品质档位是 v0.6 唯一的功率成长轴（§5 第 10 条），它的释放节奏就是 ρ 上限的释放节奏。**但本系统不得自行取值**：这是内容产能排期问题，须与核心 D3 的曲线形状、D13 的模块品质节奏一起定（§6.1 / §6.2 目前给的是推荐排法） |
| Q6 | **低品质套系被淘汰的风险**（核心 R13 在本系统的落点，v0.6 新增）：高品质套系同时给更多位子与更高价值物品（核心 §4.1.1），低品质盒可能沦为废料 | 本系统的**唯一对策手段是发放顺序**：把品质梯度放平（相邻档不同时给"更多位子 + 更高价值物品"），并保证每个阶段的**预期释放**里仍有低品质套系的用武之地。**结构性的对抗仍归核心 §10.3 的需求结构变宽与 D14（品质梯度不宜过陡）**，本系统只负责不把这个风险放大 |
| Q7 | **`serial_counters` 与 `duplicate_count` 是否合并为一条不可逆计数**（v0.8 新增）：二者数值高度重合（都只在开盒产出推进），但 `serial_counters` 是 `serial` 的分配依据、`duplicate_count` 是图鉴的重复次数展示 | 切片期**保留两条**（§5 第 13 条：都不可逆、都不得由实例列表推导，合并会让 02 的编号分配与图鉴口径耦合）。若合并，**必须以 `serial_counters` 为唯一源**，并同步改 `02-item.md` 的图鉴口径与 `08-ui-panels.md` 的重复次数展示——**本系统不得自行合并** |
| Q8 ★ | **切片阶段必须实测存档体积**（v0.8 新增）：每实例约 120 B、5000 实例 ≈ 600 KB 是**估算**（核心 §4.2.2 第 4 条），且 `source` 是大头 | ⛔ **切片期必做**：按真实产出速率实测 1 小时 / 10 小时的存档体积、写盘耗时与读档耗时（含 `draw_log` 与实例列表两部分）。若超预算：**优先裁剪 `draw_log`（Q3）与压缩键名，不得砍 `source`**（溯源是 v0.8 的叙事价值，§4.2）；实测结果需回改核心 §4.2.2 第 4 条与本文 §6.3 的数 |
| Q9 ★ | **跨文档命名与取值对齐**（v0.8 新增，**部分已裁决**）：①迁移产出的实例来源取值——**已由核心 v0.9 裁决 4 定案为 `&"migrate"`**（取值域：`gacha` / `convert` / `refund` / `mail` / `migrate` / `unlock`；本文与 08 旧稿的 `migration` 作废）；②计数器键名以 02 §4.6 的 **`serial_counters`** 为准 | ①**已解决**：三处（02 / 08 / 10）统一使用 `&"migrate"`，**全库不得并存两种拼写**；02 需在取值域中同步补入 `migrate` 与 `mail`（本文不得自行改 02 的结构）②计数器键名同理，**单数写法作废** |
| Q10 ★ | **容量与 `size` 的具体数值**（v0.9 新增，对应核心 D16）：初始容量、里程碑扩容幅度、`ItemDef.size` 的品质梯度（核心示意 1 / 2 / 5 / 10）三者必须**一起标定**，且要与任务需求向量、开盒产出量、R14 的"不敢开盒"阈值联立 | ⛔ **切片期必做**：本系统只提供**发放机制与持久化**（§5 第 14 条 / §6.3），**不得自行取值**。若实测发现"仓库在上线后 30 分钟内即满"或"玩家因此停止开盒"，优先调**扩容节奏**（内容侧）而非取消容量（那会撤掉中心机制的第一道真实压力） |
| Q11 | **主动丢弃是否需要留痕**（v0.9 新增，裁决 16）：玩家可能想知道"我丢过什么" | **不留痕**：`draw_log` 是**兑现审计**（seed + `pool_snapshot`），与丢弃无关；丢弃的可追溯性由 `total_consumed` 的增量承担 | 若将来确需一条丢弃账，必须**新增独立日志**——**不得**往 `draw_log` 里塞非兑现条目（那会让"逐条 `pool_snapshot` 可复现抽取"的 T2 失效） |

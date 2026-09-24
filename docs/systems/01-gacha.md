# 01 · 盲盒与概率系统

- 上游：`../core-design.md` **v0.6** ／ `README.md`（系统索引与所有权边界）
- 依赖系统：07 数值与期望（**共用同一套池子求值路径**）、05 模块与池子编辑（池子状态）、02 物资、10 收集与进度（图鉴即"未拥有"判定源）
- 被依赖：03 任务（盲盒奖励入账）、08 界面、09 演出、10 收集（全收集判定）

> 本文只负责**细化**：套系基础结构、基础权重表、未拥有款 ×1.5、保底、抽取判定 `roll()`、种子记录、盲盒囤积与兑现、分池独立；与 `../core-design.md` 冲突处以核心设计书为准。**`[补充]`** = 核心设计书未规定、为落地必须钉死的实现细节（一句话说明理由）。

## 1. 这个系统负责什么

1. **`SeriesDef` 基础结构**：`regular_count` 常规款 + 1 隐藏，含基础权重表、保底参数、`series_quality`（套系品质）与由它决定的 `socket_count` / `device_slot_count`（**每套系常量**，核心 §4.1.1）。
2. **基础权重表**：常规款均等（未编辑池合计 98%），隐藏款固定 2%；**未拥有款权重 ×1.5** 只改常规款之间的**相对比例**。
3. **抽取判定 `GachaService.roll(...)`**：纯函数，消费 07 求出的 `PoolEvaluation`（`probs` + `void_prob`）与 `seed`，输出 `GachaResult`；**抽样必须覆盖空洞 `void`**。
4. **保底**：连续 8 次未出新款则下次必出，`pity_counter` 状态与 UI 可见性。
5. **隐藏款免疫规则**：**规则在此声明**、执行在 `05-module-pool.md`；**分池独立**：两池互不继承保底。
6. **盲盒囤积清单与兑现时机**（核心 §4.6）；**种子记录与可复现**：给定 `(series, pool_state, owned_items, pity_counter, seed)` 输出完全确定（铁律 1）。

## 2. 不负责什么（边界）

| 不拥有的东西 | 归属 | 引用 |
|---|---|---|
| 编辑后的池子概率状态（ban / boost / 损耗 / 零和） | 05 | 见 `05-module-pool.md` |
| **概率求值路径**（权重 → ×1.5 → 编辑 → 归一化的函数本体）＋ EV / ρ / σ / `headline` / 归因的计算口径 | 07 | 见 `07-economy-rho.md` |
| 开箱演出时间轴与音画分级；默认层/展开层的渲染、展开入口、实时联动 | 09 / 08 | 见 `09-presentation.md` ／ `08-ui-panels.md` |
| 开出物资的属性（`category` / `quality` / 堆叠） | 02 | 见 `02-material.md` |
| 任务奖励结算（盲盒作为奖励被发放） | 03 | 见 `03-task.md` |
| 图鉴、套系进度、全收集判定、**存档结构** | 10 | 见 `10-progression.md` |

**三条边界裁决（README §2.1）：** ①池子概率的**状态**归 05、**求值**归 07，01 只消费求值结果，**自己不算概率**；②"被排除的款"由 09 依 05 的状态过滤，**`roll()` 只按池子状态抽样，不做展示判断**；③款的价值 `v` 由 07 从产出物资推得，**01 不定义 `v`**，`ItemDef` 不设价值字段。**④（README §6.1 裁决）** 空洞 `void` 只负责"被抽到"，其**概率质量**由 05 产生、07 求值为 `void_prob`；C1 措辞相应为"常规款概率和 **≤ 98%**，差额 = `void_prob`"。

## 3. 核心概念与术语

严格使用 `README.md` §5 术语表的中文名 + 代码名，不自造同义词。

| 中文名 | 代码名 | 在本文中的含义 |
|---|---|---|
| 盲盒 | `Box` | 可囤积、未兑现的抽取机会；**绑定一个套系** |
| 套系 / 款 | `Series` / `Item` / `ItemDef` | 一个独立概率池：`regular_count` 常规款（品质 1–2 = 8，品质 3–4 = 12）+ 1 隐藏；款即池中的一个可产出物 |
| 常规款 / 隐藏款 | `regular` / `hidden` | `regular_count` 款均等合计 98%、可被池子编辑（**款数随套系品质** `series_quality`，核心 §4.1.1）／ 1 款概率恒 2%、免疫一切池子编辑（C3） |
| 池子 / 池子状态 / 空洞 | `Pool` / `PoolState` / `void` | 某套系当前的概率分布（**状态定义归 05**）；空洞 = 排除损耗产生的**零价值结果**，抽中时**不产出任何物资**但仍消耗一个盲盒（§5.6） |
| 未拥有款 | `unowned_item` | 不在图鉴中的款；重复开出只增数量、不改归属 |
| 保底 | `pity` / `pity_counter` | 连续 8 次未出新款则下次必出 |
| 兑现 / 囤积 | `redeem` / `pending_boxes` | 消费一个盲盒结算一次抽取 ／ 已获得未兑现清单 |
| 期望 / 默认层 | `ev` / `headline` | 单池数学期望（**算归 07**）；最好物品 + 其概率 + EV（**产出归 07**、渲染归 08） |

> **术语纪律（v0.6）：「品质」有两个含义，必须区分。**
>
> | 写法 | 代码名 | 含义 |
> |---|---|---|
> | **物资品质** | `quality` | 物资的等级维度，1–5 序数（见 `02-material.md`） |
> | **套系品质** | `series_quality` | **套系（池子）的分级**，决定 `regular_count` / `socket_count` / `device_slot_count` / 物资品质区间（见核心 §4.1.1） |
>
> **凡本文出现"品质"，必须能一眼分辨是哪一种**——一律写全"物资品质"或"套系品质"，**不得裸用"品质"**；涉及池子规模、镶嵌位数的必是**套系品质**。

## 4. 数据结构（GDScript Resource 字段定义）

### 4.1 `SeriesDef`（01 拥有，`res://data/defs/series_def.gd`）

```gdscript
class_name SeriesDef extends Resource

const HIDDEN_COUNT: int = 1
@export var series_id: StringName = &""
@export var series_quality: int = 2              # 套系品质 1..4（核心 §4.1.1）；**不是**物资品质 `quality`
@export var regular_count: int = 8               # 常规款数：随套系品质取 8（品质 1–2）/ 12（品质 3–4）
@export var regular_items: Array[ItemDef] = []   # 长度必须 == regular_count（位子与池子必须同步长，核心 §4.1.1）
@export var hidden_item: ItemDef                 # 恰 1 款
@export var socket_count: int = 3                # **该套系的常量**，随套系品质取值（品质 1–4 → 2/3/4/5）：只被 05 读取，不提供增加接口
@export var device_slot_count: int = 4           # **该套系的常量**，随套系品质取值（核心 D4）：只被 04 读取
@export_group("基础权重表")
@export var regular_weight_total: float = 0.98   # C1 红线（修订后为 ≤ 0.98，差额 = void_prob）
@export var hidden_weight: float = 0.02          # C3 红线：隐藏款概率
@export var unowned_weight_mult: float = 1.5     # 🔧 未拥有款权重倍率
@export_group("保底")
@export var pity_threshold: int = 8              # 🔧 连续 8 次未出新款
@export var pity_enabled: bool = true
@export var pity_includes_hidden: bool = true    # [补充] 保底候选集含隐藏款（核心 §5.4）
```

`[补充]` **配置校验（`SeriesDef` 加载时）**：①`regular_items.size() == regular_count`；②`regular_count` / `socket_count` / `device_slot_count` 必须与核心 §4.1.1 的套系品质表一致，且 `socket_count / regular_count` 落在约 25%–40%。理由：三者由同一品质共同决定，若允许单独配置就会产生"位子多于池子所能承受"的非法组合，C6 的 ≥3 款断言将无从保证（P7 明确否决"只加位子、不同时扩大池子"的配置）。

### 4.2 `ItemDef`（01 拥有，`res://data/defs/item_def.gd`）

```gdscript
class_name ItemDef extends Resource
@export var item_id: StringName = &""
@export var display_name: String = ""
@export var star: int = 1                        # 1..5，演出分级用（见 09-presentation.md）
@export var is_hidden: bool = false
@export var yield_material_id: StringName = &""  # 产出物资（属性见 02-material.md）
@export var yield_amount: int = 1
```

> `[补充]` **一款对应一种物资的产出**：核心 §4.2 规定"重复款即数量增加"，即一款对应一类物资，故用一个产出字段对落地。

### 4.3 囤积清单与保底状态（01 拥有；`GameState` 承载，存档格式归 10）

```gdscript
class_name Box extends Resource

@export var series_id: StringName = &""   # [补充] 盲盒必须绑定套系，否则分池与兑现无从判定
@export var source: StringName = &""      # 来源任务 id，用于归因（见 03-task.md）
@export var acquired_tick: int = 0
# autoload/game_state.gd 中由 01 拥有的状态
@export var pending_boxes: Array[Box] = []
@export var pity_counters: Dictionary[StringName, int] = {}  # series_id -> 0..pity_threshold
```

### 4.4 `GachaResult`（01 拥有）

```gdscript
class_name GachaResult extends Resource   # [补充] Resource 承载，便于按核心 §14.2.7 写入开箱日志
@export var ok: bool = true
@export var error: StringName = &""       # [补充] 纯函数不崩溃，用错误码返回
@export var series_id: StringName = &""
@export var item_id: StringName = &""     # [补充] 抽中 void 时为空串哨兵（不产出任何物资）
@export var star: int = 1                 # void 时为 0（分级与演出见 09-presentation.md）
@export var is_void: bool = false         # [补充] 本次抽中空洞：仍消耗一个 Box
@export var is_new: bool = false          # 决定 pity_counter 走向；void 时恒为 false
@export var pity_triggered: bool = false
@export var probability: float = 0.0      # 本次所用分布中该结果的概率（void 时为 void_prob）
@export var seed: int = 0
@export var draw_index: int = 0           # [补充] 批次内序号，用于复现批量兑现顺序
```

### 4.5 共享求值接口（**类型与实现归 07**，01 只调用）

```gdscript
# 函数本体只存在于 autoload/eval_service.gd（07 拥有），签名以 07 §4.1 为准
static func EvalService.evaluate_pool(pool_state: PoolState, series: SeriesDef) -> PoolEvaluation
# PoolEvaluation = { probs: PackedFloat32Array, void_prob: float, is_normalized: bool, revision: int }
```

`PoolEvaluation` 的类型与字段归 07（见 `07-economy-rho.md` §4）；本文只钉死"**`roll()` 必须消费它、不得重新计算权重**"（05 §8.1：**01 不得读 `PoolState` 原始结构**）。它不含保底覆盖，因此 C3 红线始终可测：隐藏款恒 0.02；`void_prob` 是**抽样空间的一部分**，不是抽样之外的额外惩罚。

## 5. 规则与公式

### 5.1 基础权重表

| 款 | 数量 | 权重 | 依据 |
|---|---|---|---|
| 常规款 | `regular_count`（品质 1–2 = 8，品质 3–4 = 12） | 每款 `0.98 / regular_count`（均等）；`regular_count == 8` → `0.1225`；`== 12` → `≈ 0.0817` | C1，核心 §4.1 / §4.1.1 |
| 隐藏款 | 1 | `0.02`（固定，不可编辑） | C3，核心 §5.4 |
| 合计 | `regular_count + 1`（9 或 13） | `1.00` | 未编辑池：常规 98% + 隐藏 2%；编辑后：常规 + `void` 合计 98% |

### 5.2 权重路径（与 `EvalService` **共用同一份代码**）

```
① 基础权重    w_i = regular_weight_total / regular_count
              （regular_count == 8 → 0.1225；regular_count == 12 → 0.98 / 12 ≈ 0.0817）   （常规款）
② 未拥有 ×1.5  w_i *= 1.5（仅当 item_i ∉ owned_items），随后把 regular_count 款常规按比例归一化回 0.98
③ 模块编辑    ban → 0 ／ boost → ×N（增量从其他常规款按比例扣除，零和）  ← 归 05
④ 隐藏款      全程 0.02，不参与 ② 的归一化、不受 ③ 影响               （C3）
⑤ 空洞 void   排除释放质量的 40% 落为 void_prob（Σ常规 + void_prob == 0.98） ← 归 05
──────────────────────────────────────────────────────────────
→ PoolEvaluation（常规款 + void_prob = 0.98，隐藏款 0.02，Σ == 1.0）
```

**`[补充]` 权重路径的固定顺序（①→②→③→④→⑤）**：核心设计未规定顺序，而顺序会改变分布，必须钉死才能单测与复现；选此顺序是为了让"编辑 + 损耗"成为分布的最后一道工序，归因面板才能干净地说出"这 +0.42 来自模块、−0.08 来自损耗"（P2 / P6）。`void` 是这条路径的**产物**，不是抽样时的临时扣减。

×1.5 的效果是**相对比例，不是总量**（示例，其余款均已拥有，`regular_count == 8`）：全部未拥有 → 各 12.25%；1 款未拥有 → 该款 **17.29%**、其余各 11.53%；2 款未拥有 → 各 **16.33%**、其余各 10.89%。三例均取自未编辑池（`void_prob = 0`），故常规合计为 98%。

> **示例的前提（v0.6）：以上三个百分比均假设 `regular_count == 8`**（套系品质 1–2）。
> `regular_count == 12`（套系品质 3–4）时基础权重降为 `0.98 / 12 ≈ 0.0817`，×1.5 的相对比例关系不变：
> 1 款未拥有 → 该款 `1.5 / 12.5 × 0.98 ≈ 11.76%`、其余各 `≈ 7.84%`；12 款全未拥有 → 各 `0.98 / 12 ≈ 8.17%`。（相对比例只由款数决定，与基础权重无关。）

**保证"同一份代码"的方式（README §2.2 铁律）：**

1. **单一实现**：权重与归一化逻辑只存在于 `eval_service.gd`；`gacha_service.gd` 内不得出现概率公式与 `0.98` / `0.02` / `1.5` 字面量，CI 用静态检查（grep）守护。
2. **契约测试**：同一 `(pool_state, series)` 下，`EvalService.compute(...)` 的 `distribution` / `void_prob` 与 `evaluate_pool(...)` 的 `probs` / `void_prob` 逐项相等；并用测试钩子取回 `roll` 实际使用的 `PoolEvaluation`，断言与之一致。
3. **频率一致性**：固定 `seed` 抽 1e6 次，经验频率 vs 理论分布做卡方检验（常规款相对误差 < 1%，隐藏款 2% ± 0.1%，**`void` 频率 == `void_prob` ± 0.1%**）。
4. **红线同夹具**：C1 / C3（含 `void` 守恒式）必须在 `EvalService` 与 `roll` **两侧同时**断言，任一侧偏离即失败（R4 头号 bug 源）。

### 5.3 保底（pity）

`pity_counter[series_id] ∈ [0, pity_threshold]`，**每个套系一个独立计数器**：

```
本次兑现已结算
 ├─ is_new == true        → pity_counter[s] = 0
 ├─ 有未拥有款 & 未出新款（含 void）→ pity_counter[s] = min(pity_counter[s] + 1, 8)
 └─ 无未拥有款（已全收集） → 不增长（不处于"连续未出新款"语义中）
```

- **触发**：兑现前 `pity_counter[s] >= pity_threshold` 时本次**必出未拥有款**，`pity_triggered = true`。
- **`[补充]` `void` 与保底——裁决：计入。** `void` 结果 `is_new = false`，`pity_counter[s] + 1`。理由：①`void` 确实不是新款，按"连续未出新款"的字面语义即应计入；②否则排除操作会**双重惩罚**玩家（既拿不到物资、又拖慢保底），把 C2 的"损耗是重量"变成隐形惩罚；③`void` 是空手结果，与 P5（重复与过剩永远不是空手）存在张力，保底计入正是 P5 的补偿侧。
- `[补充]` **触发时的抽样方式**：在**同一份 `PoolEvaluation` 的未拥有款子集内按相对权重条件抽样**（不新建分布、不改权重、**排除 `void`**），避免出现第二条概率路径。
- `[补充]` **候选集与边界**：候选集 = 未拥有且当前可产出的款，**含隐藏款**（`pity_includes_hidden = true`，理由：核心 §5.4 的隐藏款"独立保底"本切片以**单一保底机制**落地）；候选集为空（全收集）时保底不触发、计数封顶在阈值、不报错。
- 保底**不改变池子分布本身**；保底是否计入默认层概率与 EV 的口径归 07。

### 5.4 隐藏款免疫（**规则在此声明，执行在 05**）

| 操作 | 对隐藏款 |
|---|---|
| 排除 `ban` / 提升 `boost` / 回收 `recover` | 不可用（`socket()` 拒绝）、不波及；概率恒 0.02 |
| 未拥有 ×1.5 | **不适用**（`[补充]`：否则隐藏款概率会偏离 2%，违反 C3 的"恒为 2%"） |
| 保底条件覆盖 | 参与候选（§5.3），但**池子分布中的 2% 始终不变** |
| 空洞 `void` | 与隐藏款无关：`void` 只可能从**常规款**释放的质量中产生，隐藏款的 0.02 不参与损耗 |

**执行点**：`PoolService.socket()` / `unsocket(slot)` 的白名单校验与错误返回，见 `05-module-pool.md`。**保底不是编辑**：它是对分布的**条件覆盖**（"必出"），故不违反 C3；C3 的测试对象是**分布**（隐藏款 0.02），不是单次结果。

### 5.5 分池独立

每个套系一份 `SeriesDef`、一份基础权重、一个 `pity_counter`、一份 `PoolState`；**无跨池继承**：A 池攒到 7 次未出新款，B 池仍从 0 开始；兑现只作用于盲盒绑定的套系。切片期只有 1 个套系（核心 §13.1），但结构、存档与 UI 一律按 **N 套系**设计。

### 5.6 随机与可复现

```gdscript
# [补充] 在核心 §9 铁律 1 的 (series_id, pool_state, seed) 上显式追加 pity_counter：
#        纯函数不得读全局状态；保底计数是其唯一额外输入，probs 与 ×1.5 一律来自 07 的 PoolEvaluation。
static func roll(series_id: StringName, evaluation: PoolEvaluation, seed: int,
        pity_counter: int) -> GachaResult
```

- 内部步骤只有 `校验 → evaluate_pool(...) → 判定 armed → 条件/全量抽样 → 返回 Result`，**无任何副作用**（演出只播报，不得重抽）；`[补充]` **抽样算法与顺序固定**：累计概率 + 线性/二分查找，款序为 `regular_items` 的数组固定顺序、隐藏款置于其后；禁用字典遍历顺序；`RandomNumberGenerator` 必须显式赋 `seed`，禁用 `randi()` / `randf()` 等全局随机函数。
- **`void` 的抽样规格（README §6.1）**：抽样空间 = `evaluation.probs`（`regular_count` 常规 + 1 隐藏）**加上 `void_prob`**，总和恒为 1.0；`void` 段的区间位置固定（置于款序末尾）。抽中 `void` → `is_void = true`、`item_id = &""`、`star = 0`、`is_new = false`、**不产生任何物资**（不调用 02 的入库接口），但**仍消耗一个 `Box`**。
- `[补充]` **`seed` 在兑现时刻生成并记录**（不预生成于盲盒获取时）：否则"把盒子攒到池子编好再开"（核心 §4.6）在数值上不成立。兑现日志 `{ seed, series_id, pool_snapshot, item_id, star, is_void }`（核心 §14.2.7）：**`void` 结果以 `is_void = true` + 空 `item_id` 落盘**，使"抽到空洞"可复现、可对账；**持久化格式归 10**。

## 6. 参数表（推荐值 + 调参旋钮标记）

🔧 = 调参旋钮；标"红线"者不可调，改动即破坏 C1 / C3。

| 参数 | 字段 / 位置 | 推荐值 | 性质 | 说明 |
|---|---|---|---|---|
| 套系品质 | `SeriesDef.series_quality` | **1..4**（切片取 **2**） | 内容驱动（里程碑解锁） | 核心 §4.1.1：决定 `regular_count` / `socket_count` / `device_slot_count` / 物资品质区间；**不得靠消耗物资或重复开盒提升** |
| 常规款 / 隐藏款数量 | `regular_count`（== `regular_items.size()`） / `hidden_item` | **8 / 1**（品质 1–2）、**12 / 1**（品质 3–4） | 随套系品质固定 | 核心 §4.1 / §4.1.1；同一套系内恒定、运行时不可变 |
| 常规款概率总和 / 单款基础权重 | `regular_weight_total` / 派生 `0.98 / regular_count` | **≤ 0.98** / **0.1225**（款数 8）· **≈ 0.0817**（款数 12） | **红线 C1** | 差额 = `void_prob`（README §6.1 修订）；`Σ常规 + void_prob + 0.02 == 1.0`；权重随款数变化，见 §5.2 |
| 隐藏款权重 | `hidden_weight` | **0.02** | **红线 C3** | 恒 2%，不可编辑 |
| 未拥有款权重倍率 | `unowned_weight_mult` | **1.5** | 🔧 | 只改变常规款内部相对比例 |
| 保底阈值 | `pity_threshold` | **8** | 🔧 | 核心 §4.1 写明"连续 8 次"，改动须回写核心文档 |
| 保底参数组（启用 / 候选含隐藏款 / 抽样方式 / 全收集后行为 / `void` 计入） | `pity_enabled` / `pity_includes_hidden` / 条件覆盖 / `min(+1, 阈值)` 封顶 | **true / true** / 子集内相对权重 | 🔧 / 固定 | `[补充]` 见 §5.3：`void` 计入保底推进；armed 时 `void` 不参与 |
| RNG / 抽样顺序 | `RandomNumberGenerator` / `SeriesDef` 固定序 + `void` 段 | 显式 `seed` / 常规序 → 隐藏 → `void` | 固定 | `[补充]` 跨平台可复现 |
| 镶嵌位数量 | `SeriesDef.socket_count` | 随套系品质：**2 / 3 / 4 / 5**（品质 1/2/3/4；切片取品质 2 = **3**） | **该套系的常量**（运行时不可变） | **C4**：由套系品质决定、同一套系内恒定；位子与池子必须同步长（核心 §4.1.1）；D3 曲线已不再是开工阻塞（§11）；行为归 05 |
| 装置槽位数 | `SeriesDef.device_slot_count` | 随套系品质同步（核心 D4，推荐：是） | **该套系的常量**（运行时不可变） | P7 的另一半；只被 04 读取，行为见 `04-device.md` |

## 7. 流程 / 状态机

```
     [囤积清单 pending_boxes（01 拥有）]
                │ redeem(box)  ← 兑现时机是玩家决策（核心 §4.6）
                ▼
     [求值 → roll 结算（纯函数 evaluate_pool + 覆盖 void 的抽样）] ──校验失败──▶ [拒绝：盲盒不消耗、计数不改、不发物资]
                │ GachaResult（**先结算后演出**，核心 §16）
                ▼
     [演出（见 09-presentation）]  ← 可跳过；演出只播报，不得重抽
                │ 提交（唯一副作用段）
                ▼
     物资入库(02)｜void 例外：不入库 ／ 图鉴标记(10) ／ pity_counter +1（void 亦计入）+ 开箱日志(01 + 10)
```

保底分支（同一次结算内）：`armed = (pity_counter[s] >= pity_threshold) and 候选集非空`；`armed` → 未拥有款子集内条件抽样、`pity_triggered = true`，**此时 `void` 不参与**（保底保证的是"必出新款"）；`!armed` → 在 `PoolEvaluation.probs` + `void_prob` 上全量抽样。出新款 → 计数清零；未出新款 **或 `void`** → +1（封顶）。

- `[补充]` **批量兑现**：一次兑现 N 个盲盒 = 按清单顺序 **N 次独立结算**，`draw_index` 递增；顺序必须确定，日志与回放依赖它。

## 8. 与其它系统的接口

| 对端 | 方向 | 内容 |
|---|---|---|
| **07 数值与期望** | 调用 → | `EvalService.evaluate_pool(pool_state, series) -> PoolEvaluation`（`probs` + `void_prob`）：**唯一权重路径**（README §2.2 铁律）；`headline` / EV / ρ 由 07 产出，01 不产出、08 不另算 |
| **05 模块与池子** | 只读 ← | **不读 `PoolState` 原始结构**（05 §8.1），只消费经 07 求值的 `PoolEvaluation`；`void_prob` 由 05 的损耗产生；隐藏款免疫规则（§5.4）由 05 在 `socket()` 校验中**执行** |
| **02 物资** | 调用 → | 按 `yield_material_id` / `yield_amount` 入库（接口定义见 `02-material.md`）；**`void` 结果不产生任何物资，故不调用入库接口** |
| **03 任务** | 被调用 ← | `GachaService.grant_box(series_id, count, source)`：任务奖励发放盲盒入清单 |
| **10 收集与进度** | 双向 | 只读 `owned_items`（×1.5 与 `is_new` 的判定源）；交付开箱日志内容（seed + 池子快照 + 结果 + `is_void`），**持久化格式与文件归 10**；全收集判定归 10 |
| **09 演出** | 交付 → | `GachaResult`（`item_id` / `star` / `is_void` / `is_new` / `pity_triggered`）；`void` 的演出呈现归 09，排除款过滤由 09 依池子状态完成 |
| **08 界面** | 交付 → | 囤积清单、`pity_counter`、`SeriesDef`（款数 N）、错误码、`is_void` / `void_prob`（§9） |

## 9. UI 需求

数据由 01 提供，**渲染与布局归 08**（见 `08-ui-panels.md`）。

| 需求 | 内容 | 依据 |
|---|---|---|
| 架上面板 | 囤积清单按套系分组、数量、单个/批量兑现入口 | 核心 §8.1 |
| **保底可见性** | 展开层显示"距离保底还差 M 次"（`pity_counter` 与阈值都可读）；已触发时提示"**必出新款**" | **P1：保底计数必须可查**；核心 §5.4 |
| 分池提示 | 保底计数**按套系分别显示**，不得合并成一个数字 | §5.5 |
| 兑现与错误提示 | 即时结算、无等待、无冷却，批量兑现显示进度；`GachaResult.error` 映射为可读文案且**不消耗盲盒** | 核心 §4.6 / §5.6 |
| **空洞呈现** | 展开层与直方图必须有独立的 `void` 柱（渲染归 08），**镶嵌预览必须显示"排除会让 `void_prob` 升到多少"**（否则玩家会抱怨"排除之后反而更容易白开"，§10.3）；01 提供 `void_prob` 与 `is_void` | 05 §5.4 ／ 07 §5.4 |

**禁止项：** 不得显示"下一次会出**哪一款**"（P4 单次悬念不可消除，只允许提示"必出新款"）；不得在 UI 层自行计算概率或 EV（`headline` 一律取自 07，核心 §6.4）；`seed` 与日志只在展开层或调试面板出现，不得出现任何"按进度调爆率"的暗示（P1）。

## 10. 测试点与验收标准

全部测试在**无头模式**运行（铁律 1）；夹具覆盖"原始池 / 已 ban / 已 boost / 组合"四类 `PoolState`，并**各跑 `regular_count == 8` 与 `== 12` 两种套系**（核心 §4.1.1）。

### 10.1 红线测试（缺一即阻塞发布）

- **T（C1 概率守恒，修订）**：任意合法 `PoolState` 下 `Σ probs(常规款) + void_prob == 0.98` 且 `Σ probs + void_prob + 0.02 == 1.0`（**容差 1e-6**；与 07 §10.1 T2 同源，07 以上界 `≤` 形式表述），**含 ×1.5 生效后的归一化路径**。
- **C3**：同上 `p_hidden == 0.02` 恒成立；**隐藏款未拥有时也不因 ×1.5 变化**；ban / boost 隐藏款的请求被 05 拒绝（跨系统测试）。
- **C4 / C2（交界）**：`pool_state.socket_count` **恒等于该套系 `SeriesDef.socket_count`**（即随套系品质取值的那个数，2/3/4/5），且**01 的任何代码路径都不得改变它**——含校验失败回滚、批量兑现、保底触发、存档载入与配置重载；也不实现、不修改损耗率，只断言消费的分布与 05 状态一致（完整测试见 `05-module-pool.md`）。
- **C6（v0.6 新增，交界）**：**任意合法 `PoolState` 下，可产出常规款数 ≥ 3**（即 `regular_count − 已排除款数 ≥ 3`）；01 侧断言"抽样空间中常规款条目数 ≥ 3 且 `probs` 长度 == `regular_count`"，越界请求由 05 在 `socket()` 时拒绝（完整测试见 `05-module-pool.md`）。夹具须覆盖 `regular_count == 8` 与 `== 12` 两种套系。

### 10.2 功能测试

- **确定性与 `void` 专项**：同 `(evaluation, pity_counter, seed)` 跑 1000 次结果完全相同，不同 `seed` 分布一致；`void` 抽样频率 == `void_prob`（1e6 次，±0.1%）；`void` 结果**不产出任何物资**（02 的入库接口不被调用）但**仍消耗一个 `Box`**；`void` 使 `pity_counter + 1`；**保底 armed 的那一次绝不出现 `void`**；存档往返后以同一 `seed` 重放仍得到 `void`。
- **×1.5**：1 款 / 2 款 / 0 款未拥有三种情形与 §5.2 的 17.29% / 16.33% / 12.25% 逐项相符（**该三例假设 `regular_count == 8`**，`void_prob = 0` 时常规合计仍为 98%）；`regular_count == 12` 时按 §5.2 的比例关系重算并断言。
- **保底与分池**：连抽 8 次不出新款 → `pity_counter == 8` → 第 9 次必出新款且 `pity_triggered == true`，出新款后清零；**全收集时**保底不触发、计数封顶、不报错；A 池计数到 8 时 B 池仍为 0，A 的保底不影响 B 的抽样。
- **零概率款 / 错误处理 / 批量兑现 / 日志**：被 ban 款在 1e6 次抽样中出现 0 次；未知 `series_id` / 空池 / 配置不合法 → `ok == false` 且不发物资、不改 `pity_counter`、不消耗盲盒；批量兑现顺序确定、`draw_index` 连续，重放同批 `seed` 得同批结果；每次兑现都产生 `{seed, series_id, pool_snapshot, item_id, star, is_void}`，存档载入后以同一 `seed` + 快照重放结果一致。

### 10.3 切片失败信号（要正视）

| 信号 | 指向 |
|---|---|
| 测试者在 10 分钟内把池子编到接近必出 | **C4 未生效或 C6 保底（≥3 款可产出）失效，检查代码**；同时确认 C1 / C3 红线是否真的在跑 |
| 测试者问"这个盒子平均能拿多少"却找不到答案 | 核心 §6 默认层失败；核对 `headline` 是否被 UI 另算 |
| 测试者怀疑概率被暗改 / 显示的分布与实际不符 | **R4（头号 bug 源）**：共享求值路径被绕过 |
| 测试者从不囤积，拿到盒子就开；或对保底毫无感知、把保底理解为"系统预先知道我要什么" | 核心 §4.6 兑现时机未成立（检查清单可见性）／ 保底 UI 可见性失败、提示文案越界（显示了具体款），见 §9 |
| **玩家反映"排除之后反而更容易白开"，或不明白排除为何会减少产出** | **`void` 的代价超出预期，或未在 UI / 镶嵌预览中说明**；检查直方图的 `void` 柱与镶嵌预览文案（05 §5.4 / §9），必要时下调 D6 损耗率 |

**验收标准**：§10.1 全绿 + §10.2 全部通过 + §5.2 四项共享路径保证全绿，且能由无头模式单条命令跑完。

## 11. 待定项

| # | 待定项 | 推荐 | 影响 |
|---|---|---|---|
| G1 | 核心 §5.4 的"隐藏款**独立保底**（开满 N 次必出）"与术语表"连续 8 次未出新款"是同一机制还是两套计数器 | 按**单一保底**落地（候选集含隐藏款） | 若为两套需回写核心文档并增加计数器 |
| G2 | `[补充]` 的权重路径顺序（×1.5 与编辑、损耗的先后）最终确认 | ①→②→③→④→⑤（见 §5.2） | 顺序改变分布与归因面板口径 |
| G3 | 保底是否计入默认层显示的概率与 EV；`void` 是否进入默认层 | 由 07 定口径，`PoolEvaluation` 保持无条件分布，`void_prob` 单列 | 影响 `headline` 语义（P2） |
| G4 | "仅剩隐藏款未拥有"且保底触发时结果完全确定，与 P4"预知"字面存在张力 | 视为设计意图（核心 §5.4 明确要求保底） | 若不可接受需把保底候选集限制为常规款 |
| G5 | 未拥有款 ×1.5 是否随进度变化；批量兑现中单个盒子校验失败的处理；第 2 套系池边界；日志持久化格式 | **恒定 1.5**（随进度变化即"按进度调权"，P1 否决）；全部预校验后再逐个提交；切片不做第 2 套系但结构按 N 套系预留；日志格式归 10 | P1 红线、错误文案、存档结构 |
| G6 ⚠️ | `void` 的最终形态：**完全无产出**（07 E2 / 05 M3）是否成立；`void` **计入保底**（§5.3）与 P5"永远不是空手"的张力如何回写核心设计书 | 维持"完全无产出"；保底计入保持 | 若要改为"产出极低价值废料"，需回改 01 / 02 / 09；C1 措辞修订须回改核心设计书 |
| G7 ★ | **核心 D3（v0.6 改版）：套系品质 → 常规款数 / 镶嵌位数的曲线**——由"取一个数"变为**取一条品质曲线** | **按核心 §4.1.1 的表落地**（品质 1：8 款/2 位 · 2：8 款/3 位 · 3：12 款/4 位 · 4：12 款/5 位）；**不再是开工阻塞**：切片只有 1 个套系，取**品质 2 = `regular_count` 8 / `socket_count` 3**（沿用 v0.5 手感数据），曲线形状推迟到**第 2 个套系上线前**定 | 曲线形状直接决定 **ρ 上限与 R2 强度**，且**一旦上线极难回改**；曲线若有改动，`regular_count` / `socket_count` / `device_slot_count`、本文 §5.1 与 §5.2 的权重与示例数字、C6 的 ≥3 断言须同步更新 |

> **D3 状态（v0.6）：不再是开工阻塞项。** 切片单套系取**套系品质 2 = 8 款常规 / 3 镶嵌位**（核心 §13.1 / §15 D3）；
> 阻塞解除的代价是**文档内的数字多了一个维度**——凡权重、概率示例与测试夹具，都必须写明所假设的 `regular_count`（§5.2 / §10.2）。

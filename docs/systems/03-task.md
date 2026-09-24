# 03 · 任务系统

- 上游：`../core-design.md` **v0.6** ／ `README.md`
- 依赖系统：02 物资（持有向量、扣减）、01 盲盒（发放未兑现 `Box`）、04 装置（转化端修正）、07 数值与期望（D̄ / B / ρ 口径、预期产出）
- 被依赖：08 界面与信息呈现（任务面板）、10 收集与进度（里程碑解锁落地、存档）

## 1. 这个系统负责什么

任务 = **需求向量 + 奖励**，是循环里「完成任务」这一步的全部内容，也是**盲盒回流的主要来源**（核心 §4.3）。

| 职责 | 说明 |
|---|---|
| **`TaskDef` 定义** | 需求向量（若干「`category` × `quality` × 数量」）与奖励（`Box` / 套系券 / 位次） |
| **常规任务 `regular`** | 可重复、循环引擎；每次交付后重生成需求并回到队列。**盲盒回流的主要来源** |
| **里程碑任务 `milestone`** | 一次性；解锁新套系 / 新物资类别 / 更强模块的产出权限（D13） |
| **需求匹配** | 需求向量 vs 持有物资向量的可行性与缺口计算 |
| **奖励结算** | 原子交付：扣物资 → 发奖励（**发放的是未兑现的 `Box`，进入囤积**） |
| **需求随进度变宽** | 长期压力的**唯一合法来源**（核心 §10.3 / D10） |
| **任务队列与刷新** | 队列容量、补位、放弃、批量交付 |

**宪法约束**：本系统**不得**引入任何形式的概率调整。压力只能来自需求结构（见 §5.6 与 §10 的守护性测试）。

## 2. 不负责什么（边界）

| 不拥有 | 归属 |
|---|---|
| 盲盒发放后的抽取、保底、囤积清单 | 见 `01-gacha.md` |
| 物资属性定义、持有量、堆叠、扣减实现 | 见 `02-material.md` |
| 装置对 D̄ / B / 需求品质下限的修正计算 | 见 `04-device.md` |
| 池子概率与池子状态 | 见 `05-module-pool.md` |
| ρ / M̄ / D̄ / B 的定义与计算口径、归因 | 见 `07-economy-rho.md` |
| 任务面板的呈现规格 | 见 `08-ui-panels.md` |
| 里程碑解锁的**发放与结果落地** | 见 `10-progression.md`（03 只产出解锁意图） |
| 位次数量常量（`SeriesDef.socket_count` / 装置槽位数）——是**每套系的常量**（随套系品质 `series_quality` 取值，见核心 §4.1.1） | 见核心 §14.2 铁律 5，**03 无任何修改接口** |

## 3. 核心概念与术语

- **需求向量 `requirements`**：`Array[TaskRequirement]`，每项是一个「类别 × 品质 × 数量」三元组。
- **持有向量**：当前背包按 `(category, quality)` 分组的物资量，由 02 提供（见 `02-material.md`）。
- **有效品质下限 `effective_floor`**：需求项的品质下限经 04 的装置修正后的值。
- **可行性 `feasible`**：存在一种单位分配，使每一项需求都被满足。
- **缺口报告 `MatchReport`**：不可行时逐项缺多少、以及最小割给出的"最紧约束类别"。
- **需求变宽 `widening`**：随 `progress_tier` 上升，需求项更多、品质下限更高、类别更分散。
- **进度档位 `progress_tier`**：需求变宽的唯一输入，只在**刷新时**读取。
- **冻结**：任务实例一经生成，其 `requirements` 逐字段不再变化。
- **"品质"的两个含义（术语纪律）**：本文档出现的"品质"（`quality` / `quality_floor` / `品质下限`）一律指**物资品质**，归 `02-material.md`；**套系品质 `series_quality`**（决定常规款数 `regular_count`、镶嵌位数、装置槽位数，归核心 §4.1.1）与本系统无关——本系统既不读写 `series_quality`，也不得把二者混用。

## 4. 数据结构（GDScript Resource 字段定义）

**选择：嵌套 `Resource`，不用 `Dictionary`。** 理由：① 需求向量必须**可在 Inspector 里结构化编辑**——R11 要求内容纯配置产出，`Dictionary` 没有字段校验、键名靠约定，配错不报错；② 存档要稳定 schema（见 `10-progression.md`），`Dictionary` 的键易漂移；③ 同一组类型可复用为运行时缺口报告对象。
> `[补充]` Godot 4.5 中把嵌套 `Resource` 用作 `@export` 元素类型需要独立脚本文件与 `class_name`，故拆为 4 个文件（`task_requirement.gd` / `reward_entry.gd` / `task_widening_profile.gd` / `task_def.gd`），理由是不拆则 Inspector 无法展开编辑，违背 R11 的数据驱动目标。

```gdscript
# res://data/defs/task_requirement.gd
class_name TaskRequirement
extends Resource
## 一条需求项：「类别 × 品质 × 数量」三元组。
@export var category: StringName = &""   ## 见 02-material.md 的 MaterialDef.category
@export var quality_floor: int = 1       ## 品质下限：仅 quality >= 该值的物资可计入
@export var amount: int = 1              ## 需求量（物理单位数，非加权贡献点）
```

```gdscript
# res://data/defs/reward_entry.gd
class_name RewardEntry
extends Resource
## 奖励项。核心 §4.3 的三种奖励：盲盒 / 套系券 / 位次。
enum Kind { BOX, SERIES_TICKET, SLOT_UNLOCK }
@export var kind: Kind = Kind.BOX
@export var series_id: StringName = &""  ## kind 为 BOX / SERIES_TICKET 时有效
@export var count: int = 1
@export var unlock_id: StringName = &""  ## kind 为 SLOT_UNLOCK 时有效，落地见 10-progression.md
```

```gdscript
# res://data/defs/task_widening_profile.gd
class_name TaskWideningProfile
extends Resource
## 需求变宽曲线。全部字段均为 🔧 调参旋钮，见 §6。
@export var tier_per_extra_requirement: int = 3   ## 每 N 档 +1 条需求项（宽度轴）
@export var tier_per_quality_step: int = 4        ## 每 N 档 品质下限 +1（稀有度轴）
@export var max_requirements: int = 4             ## 需求项数硬上限
@export var max_quality_floor: int = 3            ## 品质下限硬上限
@export var amount_growth_per_tier: float = 0.15  ## 数量轴温和线性补偿
@export var rarity_bias: float = 0.6              ## 类别取样偏向低产出占比类别的程度
@export var solvency_cap: float = 0.35            ## 单任务需求总量 <= 该档预期产出的 35%
@export var max_tier: int = 40                    ## 变宽有界，超过后不再变宽
```

```gdscript
# res://data/defs/task_def.gd
class_name TaskDef
extends Resource
enum TaskKind { REGULAR, MILESTONE }
@export var task_id: StringName = &""
@export var display_name: String = ""
@export var kind: TaskKind = TaskKind.REGULAR
@export var base_requirements: Array[TaskRequirement] = []   ## 需求向量（tier 0 基础值）
@export var widening: TaskWideningProfile = null             ## null = 不随进度变宽（里程碑用）
@export var rewards: Array[RewardEntry] = []
@export var unlock_ids: Array[StringName] = []  ## 仅里程碑：解锁意图，结果落地见 10-progression.md
@export var category_pool: Array[StringName] = []  ## 可抽样的类别池（只用已解锁类别）
```

```gdscript
# res://data/runtime/task_instance.gd（运行时状态，进存档）
class_name TaskInstance
extends Resource
@export var task_def_path: String = ""          ## TaskDef 的 res:// 路径
@export var requirements: Array[TaskRequirement] = []  ## 刷新时生成并冻结（P1）
@export var generated_tier: int = 0
@export var generated_seed: int = 0             ## 需求生成 seed，保证可复现
@export var completed_count: int = 0            ## 常规任务：已交付次数
@export var state: int = 0                      ## 见 §7 状态机
@export var is_completed: bool = false          ## 里程碑任务：一次性终结标记
```

## 5. 规则与公式

### 5.1 品质在需求中的口径（明确选择）

**品质只决定"资格下限"，不做加权贡献度**：需求量 `amount` 以**物理单位数**计，1 单位合格物资 = 1 点满足度。

对核心 §4.2「品质决定任务贡献度」的落地口径：**品质决定该物资能否计入某一档需求**（高品质可顶替低品质，反之不行），并继续由 §4.2 的另一半——"作为装置/模块素材时的强度"——承担品质的强度语义。
`[补充]` 不采用"贡献度 = 品质"的加权口径，理由：① `D̄` 的"单位物资"口径必须唯一且确定，否则 ρ 不可归因（P2、`07-economy-rho.md`）；② 加权会让"烧高品质当燃料更省单位"成为隐藏最优解，与 §1.2「完成任务是执行、不是决策」冲突；③ P6 要求心算友好。该口径是否成立列入 §11 待定项。

### 5.2 匹配算法

```
有效下限  effective_floor(r) = max(1, r.quality_floor + mods.quality_floor_delta)   # mods 来自 04
合格判定  ok(m, r) ⟺ m.category == r.category ∧ m.quality >= effective_floor(r)
可行性    maxflow = Σ amount_r  ⟺  存在整数分配 x(m,r) ≥ 0，使
            ∀m: Σ_r x(m,r) ≤ m.qty      （一件物资只能满足一个需求项）
            ∀r: Σ_m x(m,r) = r.amount
```

- 建模为**运输问题**，用整数最大流判定（源→物资堆 容量 `qty`，堆→需求项 容量 `qty`（仅合格边），需求项→汇 容量 `amount`）。
- **禁止用贪心近似判定**：贪心会产生"明明够却判不够"的假缺口，直接破坏 P1 的可信度。`[补充]` 核心文档未规定判定算法，此处补足为最大流并禁止贪心，理由同上。
- **缺口报告**由最大流残余 + **最小割**生成：逐项缺口 = `amount_r − flow_r`，并给出最紧约束的 `(category, quality_floor)` 档，供 §9 缺口高亮使用。

### 5.3 部分满足如何结算（明确规则）

> **全有或全无（all-or-nothing）。不存在部分奖励，不做暂存槽。**

1. 匹配是**只读查询**（`TaskService.evaluate(instance, inventory) -> MatchReport`），不冻结、不预留物资。
2. 只有当**每一需求项都满足**时才能交付；交付时**一次性扣除**全部需求物资。
3. **不引入暂存槽**：允许把物资预存进任务会使燃料取舍变成"可后悔操作"，削弱 §3 的永久代价，且与 §1.2 冲突。
4. **不按比例发放奖励**：按比例奖励会让"永远差一点"也无限回流 `Box`，摧毁 ρ 的可计算性（`07-economy-rho.md`）与"燃料有代价"（核心 §3）。
5. **超额不消耗**：交付只扣足以满足需求的量，多余物资留在背包。

### 5.4 扣减顺序

在合格物资中**按品质由低到高优先扣减**（同品质按 `material_id` 字典序）。
`[补充]` 核心文档未规定扣减顺序；固定为"最低合格品质优先"，理由：① 交付是执行（§1.2），必须有一条确定规则；② 高品质物资同时是最好的**引擎**素材（§4.2），该规则把高品质留给"使用物资"这个唯一决策点。规则导致的 D̄ 变化必须可由归因面板读到（P2）。

### 5.5 需求生成与冻结

```
n_req   = clamp(base.size() + floor(t / tier_per_extra_requirement), base.size(), max_requirements)
t       = min(progress_tier, widening.max_tier)
floor   = min(max(base_floor) + floor(t / tier_per_quality_step), max_quality_floor)
amount_i= ceil(base_amount_i × (1 + amount_growth_per_tier × t))
类别     = 从 (category_pool ∩ 已解锁类别) 中按权重抽 n_req 个不重复类别
权重(c)  = (1 − rarity_bias) + rarity_bias × (1 − base_output_share(c))
```

- `base_output_share(c)` **只读 `SeriesDef` 基础权重表**（见 `01-gacha.md`），**绝不读 `PoolState`**。若需求读取玩家编辑后的池子，等于对镶嵌行为施加隐性惩罚，破坏 P1 与 P7 的承诺。
- **可满足性守门**：若 `Σ amount > solvency_cap × expected_output(t)`，先按比例回退 `amount`，再回退 `n_req`；`n_req ≤ |category_pool ∩ 已解锁类别|`。
- **数量轴只做温和线性补偿**：核心 §10.3 点名的压力主轴是"更分散、更稀有的类别"，数量轴**不得**成为主要压力源（否则退化成数值墙，R7）。`[补充]` 核心只点名宽度与稀有度两轴，此处限定第三轴的从属地位。
- **冻结**：生成即冻结，`progress_tier` 上升**不得回溯修改**已生成任务的需求。`[补充]` 这是 P1（不得暗改）在任务侧的必然推论，明确写死以防实现时"顺手刷新"。
- **可复现**：`generated_seed = hash(save_seed, task_id, completed_count)`，同一存档的刷新结果完全确定（进存档，见 `10-progression.md`）。

### 5.6 进度档位与"压力只能来自需求结构"

```
progress_tier = 常规任务交付总次数 + milestone_tier_weight × 已完成里程碑数
```

**硬规则（本系统的宪法条款）：**

1. 需求变宽是**唯一的长期压力来源**；`progress_tier` **只能**作为需求生成（§5.5）的输入。
2. **任何以 `progress_tier` / 完成数 / 游戏时间为输入去修改 `SeriesDef` 基础权重、隐藏款概率、保底参数或 `PoolState` 的实现，一律否决**（P1 + §3.7 跨系统铁律 7）。
3. 需求变宽**必须可预告**：任务面板要显示"下一档位的需求结构变化"（如"下档位起需求将要求第 3 类类别、品质下限 +1"）。`[补充]` 长期压力若不可预告，玩家会怀疑系统暗改（R12 同类风险），这是 P1 的要求在任务侧的落地。
4. 变宽造成的 ρ 下滑必须**逐项可归因**到需求结构项（宽度 / 品质下限 / 数量），归因口径见 `07-economy-rho.md`。

### 5.7 队列、刷新与可接数量

- 队列容量常量 `QUEUE_CAPACITY = 3`，**恒满**：交付或放弃后立刻补位，队列中不出现空位。
- **可接数量 = 队列容量**，不设第二层"接取"动作。`[补充]` 切片内"接取"不产生决策只增加点击；任务面板直接标明可交付 / 不可交付即可。
- **无手动刷新**。`[补充]` 本作没有刷新资源，免费刷新会退化成"刷到好任务为止"的最优解（D12 精神、R1）。
- **放弃不惩罚**：不可满足或暂时不想做可放弃，当次不消耗任何资源，放弃计数只进入刷新种子。`[补充]` 施加惩罚会诱导玩家"不敢放弃"而回避任务分配这个唯一的决策点（与 R10 同理）。
- 里程碑任务独立展示，**不占队列位**。

### 5.8 批量交付（可选）

`TaskService.deliver_batch(instance_ids)`：**按玩家选择顺序逐个判定**，不可行者跳过并报告原因，不阻塞其余任务；**不做跨任务的全局最优分配**。`[补充]` 核心 D12「不提供一键最优配置」在任务侧的直接体现。
**不做自动交付**：自动化会把唯一的决策点（燃料/引擎与任务分配，§1.2 / P3）自动化掉，违反 R1 对策。

### 5.9 奖励结算（含盲盒交付）

| 奖励类型 | 交付形式 | 落地 |
|---|---|---|
| `BOX` | 发放**未兑现**的 `Box`，直接进入囤积清单；**不触发抽取、不播放开箱演出** | 见 `01-gacha.md` |
| `SERIES_TICKET` | 套系券：可兑换指定套系的 1 个未兑现 `Box` | 见 `01-gacha.md`（兑换入口归 01） |
| `SLOT_UNLOCK` | 位次奖励 | 见 `10-progression.md`；位次常量见 `05-module-pool.md` |

`[补充]` 两条落地补足：① 核心 §4.3 只列出"券"为奖励类型而未定义效果，此处取最小定义"可指定套系兑换 1 个 `Box`"，**切片内不发放**，待确认；② "位次"奖励的语义限定为**在既有常量上限内开放一个位次**——**在同一个套系内不得增额**，`SLOT_UNLOCK` 不得改变同一套系内的 `SeriesDef.socket_count` / 装置槽位常量；**跨套系（解锁更高品质套系）是唯一合法的功率成长路径**（P7、核心 §4.1.1 / §14.2 铁律 5），切片内不发放（D3 已从取一个数变为取一条品质曲线、不再是开工阻塞；D4 待定）。

**奖励与实际发放数必须守恒**：`发放量 = Σ rewards.count × 交付次数 + 04 提供的 B 修正`，B 的修正由 04 计算（见 `04-device.md`），口径由 07 定义（见 `07-economy-rho.md`）；03 只记录并上报，不自行解释 B。

## 6. 参数表（推荐值 + 调参旋钮标记）

| 参数 | 推荐值 | 类型 | 说明 |
|---|---|---|---|
| `QUEUE_CAPACITY` | 3 | 常量 | 切片正好容纳 3 个常规任务 |
| `milestone_tier_weight` | 2 | 🔧 | 里程碑对 `progress_tier` 的贡献 |
| `tier_per_extra_requirement` | 3 | 🔧 | **需求变宽·宽度轴**：每 3 档 +1 条需求项 |
| `tier_per_quality_step` | 4 | 🔧 | **需求变宽·稀有度轴**：每 4 档 品质下限 +1 |
| `max_requirements` | 4 | 🔧 | 需求项数上限（受 P6 心算负担约束，R5） |
| `max_quality_floor` | 3 | 🔧 | 品质下限上限（品质档位 1–4，切片 1–3） |
| `amount_growth_per_tier` | 0.15 | 🔧 | 数量轴线性补偿，从属轴 |
| `rarity_bias` | 0.6 | 🔧 | 类别取样偏向低产出占比类别的程度 |
| `solvency_cap` | 0.35 | 🔧 | 单任务需求总量 ≤ 该档预期产出 35%，可满足性守门 |
| `max_tier` | 40 | 🔧 | 变宽上界 |
| 常规任务奖励 B | 1–2 `Box` | 🔧 | 盲盒回流的主要来源 |
| 切片里程碑奖励 | 2 `Box` + 1 解锁 | — | 一次性 |

**切片任务清单（核心 §13.1：3 个可重复常规任务 + 1 个里程碑任务）**

| `task_id` | 类型 | 需求向量（tier 0） | 奖励 |
|---|---|---|---|
| `task_regular_a` 粗料交付 | 常规 | `ore` ≥1 × 10 | 1 `Box` |
| `task_regular_b` 双料配比 | 常规 | `ore` ≥1 × 6 + `fiber` ≥1 × 6 | 2 `Box` |
| `task_regular_c` 精料交付 | 常规 | `ore` ≥3 × 5 | 2 `Box` |
| `task_ms_01` 整备验收 | 里程碑 | `ore` ≥2 × 12 + `fiber` ≥2 × 12 | 2 `Box` + 解锁"第二品质模块产出权限"（D13） |

## 7. 流程 / 状态机

```
任务实例状态： QUEUED ──交付成功──▶ DELIVERED
                 │                     ├─ 常规：completed_count+1 → 重新生成需求（tier 已更新）→ QUEUED
                 │                     └─ 里程碑：COMPLETED（终结）
                 └──玩家放弃──▶ ABANDONED（移除并补位）
```

**结算序列（原子，一次交付）**：`[补充]` 核心文档未规定结算原子性，此处明确为单一事务并带失败回滚，理由：扣减与发放若中途失败会产生"物资没了但盒子没到"的不可解释状态，直接摧毁 P1 可信度。

1. 重算可行性（§5.2），不可行即中止并返回缺口报告；
2. 计算扣减清单（§5.4）与经 04 修正后的消耗量、经 04 修正后的 B；
3. 提交：`02` 扣减 → `01` 发放未兑现 `Box` → `10` 落地 `unlock_ids` 与位次 → 更新实例状态与 `progress_tier`；
4. 任一步失败 → 回滚全部已提交步骤，实例状态不变；
5. 记录结算事件 `task_delivered(task_id, tier, consumed, rewards, mods)`，供归因面板（`08-ui-panels.md`）与开箱日志（见 `01-gacha.md` 的存档约定）使用。

## 8. 与其它系统的接口

| 方向 | 接口 | 说明 |
|---|---|---|
| 03 → 02 | `MaterialService.query(category, quality_floor)` / `MaterialService.consume(list)` | 只读查询 + 唯一写入入口；扣减实现见 `02-material.md` |
| 03 → 01 | `BoxService.grant(series_id, count)` | 发放**未兑现** `Box`，03 从不调用抽取 |
| 04 → 03 | `DeviceService.get_task_modifiers()` → `{d_bar_multiplier, bonus_boxes, quality_floor_delta}` | 修正计算归 04，03 只消费 |
| 03 → 07 | `unmodified_requirement_totals`、`settlement_records`、`expected_output(t)` | ρ / D̄ / B 的口径与归因归 07，03 不解释 ρ |
| 03 → 10 | `unlock_ids`、位次奖励意图 | 解锁发放与存档归 10 |
| 03 → 08 | `MatchReport`、奖励预告（含 04 修正后 B）、变宽预告 | 面板规格归 08 |
| 07 → 03 | `expected_output(t)`（可满足性守门输入） | 口径见 `07-economy-rho.md` |

## 9. UI 需求

面板规格归 `08-ui-panels.md`，本系统只提供数据：

1. **需求向量 vs 持有向量对照**（核心 §8.1 任务面板）：逐项显示"需要 / 持有 / 缺口"，缺口高亮取自 §5.2 的 `MatchReport`。
2. **可交付状态**：可行 = 可点击；不可行 = 缺口高亮 + 最小割给出的最紧约束档。
3. **奖励预告**：显示装置修正后的实际发放 `Box` 数，而非 `TaskDef` 原值（P2）。
4. **变宽预告**：显示下一档位的需求结构变化（§5.6 规则 3）。
5. **批量交付多选**（可选）：多选后一次确认，逐个结算并回报被跳过的任务。

## 10. 测试点与验收标准

**A. 奖励守恒**

1. 交付 N 次 → 囤积清单中该套系 `Box` 增量 == `Σ rewards.count × N + B 修正量`，无凭空产生、无重复发放。
2. 扣减清单总量 == `requirements` 总量（不可行时零扣减）。
3. 里程碑任务**只能完成一次**，第二次交付被拒绝且不扣物资、不发奖励。
4. 结算任一步注入失败 → 物资、`Box`、`progress_tier` 全部回到交付前（回滚测试）。

**B. 需求匹配边界情况**

5. 恰好满足 / 超出一单位（不扣多余）/ 空背包 / 品质全部低于下限。
6. 同一堆物资**不得**同时计入两个需求项（防止重复计数）。
7. 混合品质：低品质优先扣减顺序正确（§5.4）。
8. **假缺口反例（禁止贪心）**：构造"按需求项顺序贪心会失败、但实际可行"的用例，断言判定为可行。
9. 04 的"需求品质下限 −1"生效后，由不可行翻为可行。

**C. 冻结与可复现**

10. 交付后 `progress_tier` 上升，已刷新任务的需求**逐字段不变**。
11. 同一 `save_seed` 重放 → 刷新结果与 `generated_seed` 完全一致。

**D. 守护性测试：「压力只能来自需求结构，不能来自降低概率」★**

12. 对 `progress_tier = 0…50` 逐档快照 `SeriesDef` 基础权重表、隐藏款参数、保底参数：**全档位哈希恒定**（配置层不随进度变化）。
13. 在**不执行任何 `PoolService` 写入**的前提下，逐档断言 `EvalService` 的 `pool_distribution` 恒定——运行时不因进度调权（P1）。
14. ρ 随档位下滑的归因项集合 ⊆ `{需求宽度, 品质下限, 需求数量}`，**不得出现任何池权重类归因项**。
15. 源码级扫描：池子权重写入路径唯一为 `PoolService`；**不存在**任何以 `progress_tier` / 完成数 / 游戏时间为输入的权重修改 API。
16. `SLOT_UNLOCK` 与任何奖励路径都不得改变**同一套系内**的 `socket_count` / 装置槽位常量（对齐 C4 回归测试）；跨套系取值不同（更高品质套系）是合法的（核心 §4.1.1）。

**E. 切片失败信号（要正视）**

- 测试者感觉"任务越要越稀有"但**说不出这是需求变宽**，或怀疑系统暗改了概率 → 变宽预告与归因失效（P1 / R12）。
- 测试者在中后期仍只刷一个任务、从不看第二个 → 宽度轴太缓。
- 测试者把物资**全部**用掉、从不考虑装配 → 中心机制不成立（对齐核心 §13.4）。
- 测试者因需求变宽产生"被惩罚"感而非"要选更宽的库存"感 → `solvency_cap` 过低或变宽曲线过陡。
- 3 个常规任务对盲盒回流的贡献占比 < 90% → 与核心 §4.3「常规任务是回流主要来源」不符。

## 11. 待定项

| # | 决策 | 推荐 | 影响 |
|---|---|---|---|
| T1 | 品质在需求中的口径：仅"资格下限"还是加权贡献度 | **仅资格下限**（§5.1） | 决定 D̄ 口径的唯一性与 ρ 可归因性（P2） |
| T2 | "位次"奖励的语义：是否只允许开放**同一套系内**既有常量上限内的位次 | **只允许开放，同一套系内不增额**；跨套系（解锁更高品质套系）是唯一合法的功率成长路径 | 与 P7 / C4 直接冲突与否。**D3 已从取一个数变为取一条品质曲线，且不再是开工阻塞**（D4 待定） |
| T3 | 套系券的效果定义（核心仅列出，未定义） | "可指定套系兑换 1 个 `Box`" | 决定 01 与 03 的接口 |
| T4 | 队列容量与刷新是否引入刷新资源 | **保持 3 且无手动刷新** | 关系 R1 / D12 |
| T5 | 是否把"燃料用哪一档品质"提升为玩家显式选择 | 暂不做（§1.2 交付是执行） | 会强化 §3 取舍，但违反 §1.2 |
| T6 | 核心 D11 场景约束是否并入任务批次（"每批任务附带 1 条环境约束"） | 待核心确认 | 抑制 R1 的主要手段，落点在本系统的队列层 |
| T7 | 批量交付是否允许跨任务全局分配 | **不允许**（§5.8） | 关系 D12 |
| T8 | `progress_tier` 是否改为绑定里程碑而非交付次数 | 待手感测试 | 影响变宽节奏 |

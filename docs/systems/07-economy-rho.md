# 07 · 数值与期望系统

- 上游：`../core-design.md` **v0.6（镶嵌位数随套系品质提升）** ／ `README.md`
- 依赖系统：`05-module-pool.md`（池子状态）、`02-material.md`（物资价值定义）、`03-task.md`（需求与奖励）、`04-device.md`（转化端修正）、`06-conversion.md`（损耗修正）
- 被依赖：**全部系统**（本系统是地基，只读被引用）

> **本系统是《Open Box》的地基。** 所有数字的口径都在这里定义，其它系统只提供输入，不得各自解释。

> **v0.6 同步说明**：ρ 的定义、归因算法与共享求值路径**全部未变**。本次只同步两处上游变更——
> 常规款数与镶嵌位数不再固定（由套系品质 `series_quality` 决定，核心 §4.1.1），
> 以及 `void` 的**地位**由"损耗"升格为"自限机制"（核心 §5.3，定义不变）。

---

## 1. 这个系统负责什么

1. **概率求值路径**——本作唯一的一条。`EvalService` 与 `GachaService` 必须共用它（README §2.2 铁律）。
2. **ρ 的定义与计算**：`ρ = (M̄ / D̄) × B`
3. **M̄ / D̄ / B 的口径**：把物资、任务、装置、池子编辑折算成同一单位
4. **σ（方差）**：第二轴的显式数值
5. **`headline`**：盲盒默认层那两个数字的**产出方**（渲染归 08）
6. **归因**：把 ρ 的变化逐项分解到模块 / 装置 / 任务结构 / 损耗
7. **缓存与失效**：UI 高频调用下的性能保证

---

## 2. 不负责什么（边界）

| 不负责 | 归属 |
|---|---|
| 抽取判定、保底、隐藏款规则 | `01-gacha.md` |
| 池子状态的变更（排除 / 提升 / 损耗的**写入**） | `05-module-pool.md` |
| 物资的类别 / 品质定义与持有量 | `02-material.md` |
| 任务需求向量与奖励结算 | `03-task.md` |
| 装置 / 模块的具体效果参数 | `04-device.md` / `05-module-pool.md` |
| `headline` 的**渲染** | `08-ui-panels.md` |

> **关键边界**：`EvalService` 是**纯读出方**。它读 `PoolState`，但**绝不修改它**。唯一的写入方是 `PoolService`（05）。

---

## 3. 核心概念与术语

| 术语 | 代码名 | 说明 |
|---|---|---|
| 任务价值点 | `TVU` (Task Value Unit) | **本作的统一计价单位**。物资、需求、产出全部折算成 TVU |
| 单盒期望产出 | `m_bar` | 开 1 盒平均产出多少 TVU |
| 单任务平均消耗 | `d_bar` | 完成 1 个任务平均消耗多少 TVU |
| 单任务奖励盒数 | `b` | 完成 1 个任务平均奖励多少个盲盒 |
| 闭环收益率 | `rho` | `(m_bar / d_bar) × b`，无量纲 |
| 方差 | `sigma` | 单盒产出（TVU）的标准差 |
| 封面数据 | `headline` | `{best_item, best_item_prob, ev}` |
| 空洞 | `void` | 排除损耗产生的零价值结果（见 §5.4） |
| 归因 | `attribution` | ρ 变化的逐项分解 |
| 基线 | `baseline` | 无任何模块 / 装置的原始池 + 基础任务结构 |
| 常规款数 | `regular_count` | 该套系常规款的款数（由套系品质决定，核心 §4.1.1）；C6 与 `headline` 候选集依赖它 |
| 套系品质 | `series_quality` | 该套系的品质等级，决定 `regular_count` / `socket_count` 与物资品质区间。**与物资品质 `quality` 不是同一个概念** |

> **⚠️ 术语纪律（v0.6）："品质"有两个含义，本系统内不得混用。**
> - **物资品质 `quality`**（1–5 序数，见 `02-material.md`）：本系统中 **`v_i`（物资的 TVU 价值）涉及的是它**；
> - **套系品质 `series_quality`**（1–4，核心 §4.1.1）：决定该套系的 `regular_count` 与 `socket_count`，由里程碑任务解锁。
>
> 两者**没有任何换算关系**：`v_i` 的高低不改变 `regular_count`，`series_quality` 也不直接进入 `v_i` 的定义（它只通过"高品质套系提供更高品质区间的物资"间接影响 `v_i` 的分布）。

### 3.1 为什么需要 TVU

物资有类别与品质两个维度（见 `02-material.md`），任务需求也是向量，两者无法直接比较。**TVU 是把它们压成一个标量的桥。**

- 物资 `i` 的价值 `v_i` 定义为：**它能贡献的 TVU 数**
- 任务需求的 TVU = 需求向量中各项折算之和
- 于是 M̄ 与 D̄ 可以相除

**TVU 是本作唯一允许出现的"通用价值"单位。** 任何系统不得引入第二套计价。

---

## 4. 数据结构

```gdscript
# res://autoload/eval_service.gd
class_name EvalService

## 单池求值结果——EvalService 与 GachaService 共用的唯一数据契约
class PoolEvaluation:
    var probs: PackedFloat32Array      # 每个 Item 的最终概率，length = series.items.size()
    var void_prob: float               # 空洞概率（排除损耗产生，见 §5.4）
    var is_normalized: bool            # 是否满足 probs.sum() + void_prob == 1.0
    var revision: int                  # 求值时的 pool_state.revision，用于缓存校验

## ρ 的完整分解
class EvalResult:
    var rho: float
    var m_bar: float
    var d_bar: float
    var b: float
    var sigma: float
    var headline: Headline
    var attribution: Array[AttributionEntry]
    var distribution: PackedFloat32Array
    var void_prob: float
    var revision: int

class Headline:
    var best_item_id: StringName        # 当前池中价值最高的"可产出"款
    var best_item_prob: float           # 其最终概率（受池子编辑影响）
    var ev: float                       # = m_bar，单位 TVU

class AttributionEntry:
    var source_kind: int                # MODULE / DEVICE / TASK_STRUCTURE / LOSS / BASELINE
    var source_id: StringName           # 模块或装置的 id
    var delta_rho: float
    var delta_m_bar: float
    var delta_d_bar: float
    var delta_b: float
    var delta_void_prob: float = 0.0    # 该项贡献的 void 概率增量
    var void_breakdown: Dictionary = {} # item_id -> 该款被排除所贡献的 void 分量（LOSS 条目专用）
    var note: String                    # 人类可读，如「排除 3 款」
```

> `[补充]` `delta_void_prob` 与 `void_breakdown` 是按 `08-ui-panels.md` §11 的 **U9** 契约请求新增的：08 的直方图与"空洞来源"行需要逐款分解，若让 UI 层自行按 40% 换算，即违反"单一数据源"（跨系统铁律 3）。**因此分解必须在 `EvalService` 内完成**。08 侧对应的实现要求见其 §5 R-10/R-11 与 §9。

```gdscript
## 只读依赖：本系统读取但不修改
class_name PoolState:
    var series_id: StringName
    var revision: int                   # ★ 每次 PoolService 写入时 +1，缓存与失效的唯一依据
    var banned: Array[StringName]
    var boosted: Dictionary             # item_id -> multiplier
    var socket_count: int               # 该套系的常量（由套系品质决定），从 SeriesDef.socket_count 拷贝，运行时不可变（C4）
    var regular_count: int              # 该套系的常规款数（由套系品质决定），从 SeriesDef 拷贝；C6 与 headline 候选集依赖它
    var socketed_modules: Array[StringName]
```

> `[补充]` `regular_count` 随 `socket_count` 一起在 `PoolService` 建档时从 `SeriesDef` 拷入 `PoolState`，理由是让求值与缓存**只依赖 `PoolState` 一个输入**（`revision` 驱动），避免求值路径回头读 `SeriesDef` 造成两份事实来源。

### 4.1 接口签名

```gdscript
## 唯一求值路径。EvalService 与 GachaService 都必须调用它。
static func evaluate_pool(pool_state: PoolState, series: SeriesDef) -> PoolEvaluation

## ρ 的完整计算
static func compute(state: GameState) -> EvalResult

## 单点查询（UI 高频调用，走缓存）
static func get_headline(state: GameState) -> Headline
static func get_rho(state: GameState) -> float
```

---

## 5. 规则与公式

### 5.1 概率求值（唯一路径）

```
evaluate_pool(pool_state, series):
  1. w[i] = series.base_weight[i]
  2. 隐藏款：w[hidden] 固定，不允许被 3~6 步影响（C3）
  3. 未拥有款加权：w[i] *= 1.5          （规则归 01，此处执行）
  4. 排除：w[banned] = 0，释放质量 m = Σ series.base_weight[banned]
  5. 提升：w[boosted[i]] *= multiplier
  6. 损耗：释放质量中仅 0.6 可回收，0.4 记为 void_mass
  7. 归一化：probs = w / Σw  （在 regular_count 款常规款之间，不假设款数），隐藏款独立占 2%
  8. void_prob = void_mass（见 §5.4）
```

> `[补充]` 步骤顺序被固定（加权 → 排除 → 提升 → 损耗 → 归一化），因为顺序会影响结果。固定顺序使求值可复现，也让归因可对账。

### 5.2 三个因子

```
m_bar = Σ (probs[i] × v_i)        # void 的 v = 0，不贡献
d_bar = 任务需求向量的 TVU 折算（含装置修正）
b     = 任务奖励盒数（含装置修正）

rho = (m_bar / d_bar) × b
```

量纲校验：
```
(TVU / 盒) / (TVU / 任务) × (盒 / 任务) = 任务 / 盒 × 盒 / 任务 = 无量纲 ✓
```
ρ 的含义即"**每投入 1 个盲盒，最终回收多少个盲盒**"。

> `[补充]` 核心设计书 §2.3 写作 `M̄ = Σ(pᵢ × vᵢ) × 池子修正`。此处把"池子修正"**显式展开为编辑后的 `pᵢ`**，因为池子编辑的全部效果就体现在 `pᵢ` 上，不存在独立的修正乘数。这是表述澄清，不是机制改动。

**`regular_count` 进入公式的位置（v0.6）：** 核心 §4.1.1 起，常规款数由**套系品质**决定（品质 1/2 = 8 款，品质 3/4 = 12 款），**不再是常量 8**——所以本系统内部不得再假设"8 款常规"：

| 量 | 与 `regular_count` 的关系 |
|---|---|
| `m_bar` | **无关**。只依赖最终分布 `probs`（含 `void`），求和范围是**实际存在的款**，8 或 12 都不进入公式 |
| `sigma` | **无关**，理由同上（§5.3） |
| `headline.best_item` | **依赖**。头奖候选集 = 该套系全部常规款 ∪ 隐藏款中**可产出**者，取 `v` 最高；款数变了候选集就变了（核心 §6.1） |
| C6 判定 | **依赖**。排除上限 = `regular_count − 3`，即可产出常规款数 ≥ 3（§10.1 T7） |

> 因此 `probs` 的长度、归一化范围、C6 校验一律以 `pool_state.regular_count` 为准，**不得写死 8**。

### 5.3 方差

```
sigma = sqrt( Σ probs[i] × (v_i - m_bar)² )     # void 以 v = 0 参与
```

求和范围同样是**实际存在的款**（含 `void`），**与 `regular_count` 无关**——款数变化不改变方差公式本身，只改变分布的取值集合。

**σ 是一等公民数值**（核心设计书 §7）：必须显示，且直方图必须同时呈现编辑前后的形状。

### 5.4 空洞（`void`）——一处必须解决的内部矛盾

**核心设计书存在一处内部矛盾：**

| 条目 | 原文 |
|---|---|
| C1 | 常规款概率之和**恒为 98%** |
| C2 | 排除释放的概率仅 60% 可回收，**40% 蒸发** |

若 40% 真的消失且 Σp 仍需为 1，则抽取分布不成立。**本系统采用如下解法：**

> **蒸发的概率不消失，而是落为一个显式的零价值结果 `void`。**
> 于是：`Σ probs(常规款) + void_prob + 0.02(隐藏) = 1.0`

设计上的好处：
- 损耗**可见**（直方图上多出一根柱子），玩家能亲眼看到"我把池子凿出了一个洞"；
- 损耗**可计价**（`void` 的 `v = 0`，直接压低 `m_bar`），符合 P2 可归因；
- 不需要"归一化抹掉损耗"这种让损耗失效的做法。

**代价**：C1 的措辞需要从"恒为 98%"调整为"**常规款概率之和 ≤ 98%，差额即为 void_prob**"。

⚠️ **此项需要在核心设计书中同步修订，已记入 §11 与 `README.md` 待定项汇总。**

> **v0.6：`void` 从"损耗"升格为"自限机制"（核心 §5.3）。定义完全不变**——仍是 `Σ probs(常规) + void_prob + 0.02 == 1.0`，`void` 的 `v = 0`，上面那套口径**一字不改**。
> 变的是它在设计里的**角色**：v0.5 靠"镶嵌位数固定为常数"抑制 R2；v0.6 位子随**套系品质**变多，
> 于是**防止"位子变多导致池子被收敛"的主要机制就是这里的 40% 损耗**——每排除一款就永久损失 40% 质量，
> 排得越狠池子越"漏"，`m_bar` 塌陷、ρ 下降，**过度排除自我惩罚**。
> 本系统因此把 `void` 对 ρ 的压制作用确认为 **R2 的头号对策**（核心 §5.3 / R2）。

### 5.5 归因算法

采用**顺序分解（sequential decomposition）**，固定顺序：

```
baseline → +模块 → +装置 → +任务结构 → +损耗 = 当前 ρ
```

- 每一步的增量记为一条 `AttributionEntry`
- **满足可加性**：`Σ delta_rho == rho_current − rho_baseline`（玩家能对账，这是 P2 的硬要求）

> `[补充]` 备选方案是 leave-one-out（逐项移除求差），更直观但**不满足可加性**，玩家会发现各项之和与总变化对不上。因此选顺序分解，并把"顺序依赖"作为已知代价接受——固定顺序使其稳定可预期。
> 可选：在展开层额外提供 leave-one-out 的"独立贡献"视图作为补充，但**默认视图必须是可加性的顺序分解**。

---

## 6. 参数表

| 参数 | 符号 | 推荐值 | 说明 |
|---|---|---|---|
| 隐含款概率 | `hidden_prob` | 0.02 | 常量，不受任何编辑影响（C3） |
| 常规款数 | `regular_count` | 8（品质 1/2）／ 12（品质 3/4） | 由套系品质决定（核心 §4.1.1）；从 `SeriesDef` 拷入 `PoolState`，同一套系内恒定。**不得写死 8** |
| 镶嵌位数 | `socket_count` | 2 / 3 / 4 / 5（按品质） | 与 `regular_count` **同步长**；本系统只读，不进入 ρ 公式（C4） |
| 位子 / 池子比例 | `socket_count / regular_count` | **25%–40%** | 核心 §4.1.1 的硬约束；低于此比例会让 C6 形同虚设（位子相对款数过多 → 可排除过多）🔧 |
| 常规款概率和 | `Σp_regular` | ≤ 0.98 | 差额为 `void_prob`（§5.4）🔧 |
| 排除回收率 | `recover_rate` | 0.60 | 即损耗 40%（核心文档 D6）🔧🔧 |
| 未拥有款加权 | `new_item_mult` | 1.5 | 规则归 01 |
| 提升强度上限 | `boost_cap` | ×3 | 核心文档 D7 🔧 |
| 缓存失效依据 | `revision` | — | `PoolState.revision` 变化即失效 |
| 归因顺序 | — | 模块 → 装置 → 任务 → 损耗 | 常量，不可配置 |

🔧 = 调参旋钮 ／ 🔧🔧 = 主旋钮

**`recover_rate` 是本系统与 05 共享的主旋钮**：它同时决定 ρ 的上限、R2（池子编辑过强）的强度、以及排除操作的痛感。

---

## 7. 流程

```
GameState 变化
   │
   ├── PoolState.revision 变化？ ──是──▶ 缓存失效
   ├── 装置变更？               ──是──▶ 缓存失效
   ├── 任务结构变更？           ──是──▶ 缓存失效
   │
   ▼
EvalService.compute(state)
   │
   ├─ evaluate_pool()  ← 与 GachaService 共用
   ├─ m_bar / d_bar / b / sigma
   ├─ headline
   └─ attribution（顺序分解）
   │
   ▼
EvalResult（按 revision 缓存）
   │
   ├──▶ 08 六面板渲染
   ├──▶ 08 试算预览
   ├──▶ 09 兑现对照
   └──▶ 11? 无（本系统不驱动任何写入）
```

**本系统是纯只读的。** 它不产生任何状态变更，也不发出任何会改变游戏状态的事件。

---

## 8. 与其它系统的接口

| 系统 | 方向 | 接口 |
|---|---|---|
| 01 盲盒 | 01 → 07 | 01 提供 `SeriesDef.base_weight`、保底状态；07 向其提供 `PoolEvaluation.probs`（**01 不得自行计算**） |
| 02 物资 | 02 → 07 | 02 提供 `v_i`（物资的 TVU 价值） |
| 03 任务 | 03 → 07 | 03 提供需求向量与奖励，07 折算 `d_bar` / `b` |
| 04 装置 | 04 → 07 | 04 提供已装配装置的修正项 |
| 05 池子 | 05 → 07 | 05 提供 `PoolState`（含 `revision`）；**07 只读** |
| 06 转化 | 06 → 07 | 06 提供转化损耗修正项 |
| 08 界面 | 07 → 08 | 07 提供 `EvalResult` / `headline`；**08 只渲染，不计算** |
| 09 演出 | 07 → 09 | 07 提供"产出对 ρ 的影响"用于兑现后提示 |
| 10 进度 | 07 → 10 | 07 提供 ρ 阶段判定（开局 / 破局 / 起飞 / 工程期 / 收官） |

### 8.1 共享求值路径的保证方式

> **`evaluate_pool()` 是唯一实现。** `EvalService` 与 `GachaService` 都只能调用它。
> - `GachaService.roll()` 从 `PoolEvaluation.probs` + `void_prob` 依 `seed` 抽样，**不得重新计算权重**；
> - 任何地方出现第二份权重计算逻辑即为严重缺陷；
> - 守护测试见 §10.1。

---

## 9. UI 需求

本系统**产出数据不产出界面**，但下列呈现由本系统的口径决定：

| 呈现 | 归属 | 由本系统提供 |
|---|---|---|
| 盲盒默认层（头奖 / 概率 / EV） | 08 | `headline` |
| 循环面板（ρ / M̄ / D̄ / B） | 08 | 三个因子与 ρ |
| 归因面板 | 08 | `attribution[]` |
| 分布直方图（含编辑前后对比） | 08 | `distribution` + 基线的 `distribution` |
| 试算预览 | 08 | `compute()` 的假设态结果 |
| 兑现对照（预期 vs 实际） | 09 | `m_bar` / `sigma` |

**必须满足（P2 / P6）**：
- `headline` 与展开层的分布数字**必须同源**——都来自同一次 `compute()`；
- 试算必须展示 `void_prob` 的变化，否则玩家无法理解 40% 损耗；
- 归因各项**必须能对账**（合计 = 相对基线的总变化）。

---

## 10. 测试点与验收标准

### 10.1 红线测试（必须自动化，进 CI）

| # | 测试 | 判据 |
|---|---|---|
| T1 | **C3 隐藏款常量** | 任意模块组合下 `probs[hidden] == 0.02`（浮点容差 1e-6） |
| T2 | **C1 概率守恒** | `Σ probs(常规) + void_prob ≤ 0.98` 且 `Σ probs + void_prob + probs[hidden] == 1.0`（容差 1e-6） |
| T3 | **C2 损耗率** | 排除单款后 `void_prob` 增量 == `0.4 × 该款释放质量` |
| T4 | **C4 镶嵌位常量（按套系）** | `pool_state.socket_count` 恒等于**该套系** `SeriesDef.socket_count`；**跨套系允许不同，同一套系内任何路径不得改变** |
| T5 | **共享路径** | 用同一 `PoolState` 调 `evaluate_pool()` 与 `GachaService` 的权重来源，逐元素相等 |
| T6 | **归因可加性** | `Σ attribution.delta_rho == rho − rho_baseline`（容差 1e-9） |
| T7 | **C6 保留可产出款（v0.6 新增）** | 任意合法 `PoolState` 下，**可产出常规款数 ≥ 3**（等价于 `banned.size() ≤ regular_count − 3`） |

### 10.2 功能测试

| # | 测试 | 判据 |
|---|---|---|
| T8 | 纯函数性 | 同 `(state, series, seed)` 两次调用，`EvalResult` 逐字段相等 |
| T9 | 缓存正确性 | `revision` 变化后 `compute()` 结果必须变化；未变化时必须命中缓存 |
| T10 | 只读性 | 调用 `compute()` 前后，`PoolState` / `GameState` 逐字段不变 |
| T11 | `headline` 一致性 | `headline.ev == m_bar`；`headline.best_item_prob == probs[best_item]`；候选集取自该套系 `regular_count` 款常规款 ∪ 隐藏款 |

### 10.3 验收信号（切片）

- ✅ 测试者能在 2 分钟内说出自己 ρ 的主要贡献来源（P2 达成）
- ✅ 测试者能理解 `void` 的含义，并据此决定是否继续排除
- ✅ **测试者不再问"为什么位子会变"**——开始问"怎么拿到更高品质的套系"即算通过（说明**品质 → 镶嵌位**的关系被理解了，核心 §4.1.1 / P7）
- ❌ **测试者认为"显示的期望"与实际开出的东西不符** → 共享路径失效，头号缺陷，立即停止其他工作排查
- ❌ **测试者发现归因各项之和对不上总变化** → 归因算法回归，P2 失效

---

## 11. 待定项

| # | 待定项 | 推荐 | 影响 |
|---|---|---|---|
| **E1** ⚠️ | **C1 措辞修订**：`Σp_regular` 是"恒为 98%"还是"≤ 98%（差额为 void）" | **改为 ≤ 98% + void**（§5.4） | **需同步修订核心设计书**；不改则 C1 与 C2 无法同时成立 |
| **E2** | `void` 的呈现方式：完全无产出，还是产出极低价值废料？ | 完全无产出（最简、最易理解） | 影响演出（09）与玩家体感 |
| **E3** | 归因是否额外提供 leave-one-out 视图 | 仅在展开层提供 | 关系认知负担 |
| **E4** | `sigma_rho`（ρ 的区间估计）是否需要 | 切片不做 | 后期可能有用 |
| **E5** | 是否提供"平均可完成 N 个任务"这类更具体的默认层文案 | 推荐提供，作为 `ev` 的补充 | 影响 08 的渲染 |
| **E6** ⚠️ | **品质 → 镶嵌位曲线（核心 D3）**：切片单套系取品质 2 = 3 位，曲线推迟到第 2 个套系前定 | 核心 §4.1.1 的 8/2 · 8/3 · 12/4 · 12/5 | **一旦上线极难回改**：曲线同时决定 **ρ 上限与 R2 强度**；本系统 §6 的 `regular_count` / `socket_count` / 位子池子比例按其取值 |

> **E1 是唯一需要回改上游文档的项，优先级最高。**

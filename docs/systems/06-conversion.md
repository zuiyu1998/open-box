# 06 · 转化系统

- 上游：`../core-design.md` **v0.6** ／ `README.md`
- 依赖系统：**02 物资**（类别/品质定义、持有向量、唯一物资写入接口）、**07 数值与期望**（价值口径 v 与归因条目格式）、**08 界面与信息呈现**（呈现规格）
- 被依赖：**04 装置**（消费本文档的转化损耗基准与下限，提供修正值）、**07 数值与期望**（消费转化结算结果作为 ρ 归因输入量）、**10 收集与进度**（图鉴登记口径，见 §8）

> **命名去歧义（必读）**
> - 本文档的「转化」指**类别间物资转换**——即核心文档 §11 教学曲线在 15–30 min 引入的动作。
> - 核心文档 §2.3 的「转化端 `convert_end`」是 **ρ 的 D̄/B 因子**，施工工具是装置，与本文档不是同一事物。全文一律写全称。
> - 术语表的 `loss` 已被**排除损耗**占用；本文档的转化损耗一律写作 `conversion_loss`。**两套损耗互不引用、互不修正。**
> [补充] 理由：术语表 `loss` 已占用，转化损耗需要独立标识符，否则两个系统的损耗会被下游误接成同一条修正链。

---

## 1. 这个系统负责什么

**转化解决盲盒的根本矛盾：随机产出 vs 确定性需求。**

盲盒产出的是**随机类别**，任务需求的是**确定类别**（需求向量的定义见 `03-task.md`）。没有转化，玩家会因为「开出来的一直不是我需要的那一类」而卡死——这不是难度，是系统缺陷。转化的职责就是给这条裂缝补一个**有代价、可计算、可归因**的出口：**把不对口的燃料，改造成对口的燃料。**

三条定位：

1. **它服务循环的「使用物资」这一步**（核心 §1.1）。转化是玩家在"使用物资"上的第三个动作，因此合规于 P3，也**增加**了这一步的深度。
2. **它不构成第三个物资出口。** 核心 §3 的二元取舍（燃料 / 引擎）不变：转化产出的仍是物资，最终仍要交付任务或作为装置/模块素材，出口裁决权归 `03-task.md` / `04-device.md` / `05-module-pool.md`。转化是**燃料路径的预处理**，不是并行的第三条路。
3. **它在教学曲线上必须最早、最简**（核心 §11）：15–30 min 引入，**早于装置**（30 min–1 h）。因此转化必须在**一个数字**内被理解，且**不依赖任何装置修正**即可使用。

## 2. 不负责什么（边界）

| 不拥有 | 归属 |
|---|---|
| 装置对 `conversion_loss` 的修正值 | 见 `04-device.md`（本文档只提供**基准与下限**，并执行结算） |
| 物资的类别 / 品质定义、持有量、堆叠、背包写入实现 | 见 `02-material.md` |
| 任务需求向量、需求匹配、奖励结算、需求随进度变宽 | 见 `03-task.md` |
| 品质价值口径 v、ρ/M̄/D̄/B/σ/归因条目格式 | 见 `07-economy-rho.md` |
| 面板呈现规格、默认层/展开层、展开入口 | 见 `08-ui-panels.md` |
| 图鉴登记与全收集判定 | 见 `10-progression.md` |
| 池子概率与池子状态 | 见 `05-module-pool.md`（转化**不触碰池子**） |

**关键边界：转化不做需求匹配。** 转化只改变玩家的持有向量；「这个向量能不能满足任务」是 `03-task.md` 的判定。

## 3. 核心概念与术语

| 中文名 | 代码名 | 说明 |
|---|---|---|
| 转化 | `convert` | 把一种「类别 × 品质」的物资换成另一种的动作 |
| 转化表 | `conversion_table` / `ConversionDef` | 类别→类别的**有向**表项集合，本文档拥有 |
| 表项 | `ConversionEntry` | 一条源→目标的有向边 |
| 源物资 / 目标物资 | `source_material` / `target_material` | 表项的输入与输出 |
| 转化损耗 / 损耗率基准 | `conversion_loss` / `conversion_loss_base` | **基准推荐 30%**（核心 D9）；`conversion_loss` 是本次结算的实际值 |
| 损耗下限 | `conversion_loss_floor` | 装置修正的**最低可达值**，推荐 10%（D9） |
| 折算比 | `ratio` | `count_out / count_in` 的实数比，UI 只展示这一个数字 |
| 报价 | `ConversionQuote` | 转化前的纯函数试算结果 |
| 残余 | `remainder_value` | 取整丢弃的价值，计入已声明的损耗，见 §5.3 |
| 品质折算 | `quality_step` | 源品质 ≠ 目标品质的表项（如多个低品质换一个高品质） |

术语表既有条目（`Material` / `category` / `quality` / `fuel` / `engine` / `rho` / `ev`）沿用，不自造同义词。

## 4. 数据结构（GDScript Resource 字段定义）

```gdscript
# data/defs/conversion_def.gd  —— 06 拥有
extends Resource
class_name ConversionDef

## 转化表：类别→类别的有向表项集合。
## 类别与品质的语义、MaterialDef 字段见 02-material.md。
@export var table_id: StringName = &"conversion_default"
@export var entries: Array[ConversionEntry] = []

## 转化损耗基准（核心 D9，是 ρ 的主要旋钮之一）。
## 装置修正见 04-device.md；本文档只提供基准与下限，并执行结算。
@export var conversion_loss_base: float = 0.30
@export var conversion_loss_floor: float = 0.10

## [补充] 首切片是否允许品质折算表项；理由：教学曲线要求 15–30 min 只需理解跨类别平移。
@export var allow_quality_conversion: bool = false
```

```gdscript
# data/defs/conversion_entry.gd
extends Resource
class_name ConversionEntry

@export var entry_id: StringName = &""
@export var source_category: StringName = &""
@export var source_quality: int = 1
@export var target_category: StringName = &""
@export var target_quality: int = 1
@export var display_name: String = ""

## [补充] 表项解锁门（核心 §4.3 里程碑释放新类别时需要承载）；解锁发放归 10-progression.md。
@export var required_milestone: StringName = &""
```

```gdscript
# 结算所需的只读快照——让 quote()/convert() 保持纯函数（README §3.1）
extends RefCounted
class_name ConversionContext

var held: Dictionary = {}                 # material_id -> count，来自 02 的持有向量
var value_of_quality: Dictionary = {}     # quality -> v，口径见 07-economy-rho.md
var device_loss_reduction: float = 0.0    # 来自 04，见 04-device.md
var unlocked_milestones: Dictionary = {}  # 已解锁里程碑，来源见 10-progression.md
```

```gdscript
# 纯函数输出，可无头单测
extends RefCounted
class_name ConversionQuote

var ok: bool = false
var reject_reason: StringName = &""   # &"unsupported_edge" / &"locked" / &"insufficient" / &"over_held"
var entry_id: StringName = &""
var ratio: float = 0.0                # 折算比：UI 唯一需要展示的数字
var count_in: int = 0
var count_out: int = 0
var min_count_in: int = 0             # 达到 count_out >= 1 所需的最小源数量
var conversion_loss: float = 0.0
var value_in: float = 0.0
var value_out: float = 0.0
var remainder_value: float = 0.0
```

```gdscript
# 归因输入量（条目格式归 07-economy-rho.md）
extends Resource
class_name ConversionLogEntry

@export var entry_id: StringName = &""
@export var source_material_id: StringName = &""
@export var target_material_id: StringName = &""
@export var count_in: int = 0
@export var count_out: int = 0
@export var conversion_loss: float = 0.0
@export var value_in: float = 0.0
@export var value_out: float = 0.0
```

## 5. 规则与公式

### 5.1 结算链（唯一公式）

```
conversion_loss = clampf(conversion_loss_base − device_loss_reduction,
                         conversion_loss_floor, conversion_loss_base)

ratio     = v(source) × (1 − conversion_loss) / v(target)
count_out = floori(count_in × ratio)          # 一律向下取整，禁止向上

value_in  = count_in  × v(source)
value_out = count_out × v(target)
```

- `v()` 的**口径归 07**（见 `07-economy-rho.md`）；本文档只决定它的**用法**：先乘 `(1 − conversion_loss)`，再按目标单位取整。
- **无装置时 `device_loss_reduction = 0`，`conversion_loss` 恒为 0.30。** 15–30 min 的引入点因此不涉及任何修正概念。
- [补充] **一次转化只接受同一「类别 × 品质」的单一源物资。** 理由：教学曲线上 15–30 min 必须简单直观，多源混合会引入心算负担（R5 / P6）。
- [补充] **`count_out < 1` 时拒绝提交**，并返回 `min_count_in = ceili(v(target) / (v(source) × (1 − conversion_loss)))`。理由：核心未定义整数结算的边界，必须避免"提交后什么都没得到"。

### 5.2 品质折算规则

- `source_quality == target_quality`：**跨类别平移**，首切片唯一形态（核心 §13.1）。
- `source_quality != target_quality`：**品质折算**，由表项显式配置，公式不变（`v()` 已含品质维度）。
- **硬约束（套利封印的前提）：表项不得附带任何奖励倍率。** 换算收益只能来自 `v()` 的比例，不得出现"向上折算额外送 1 个"之类的加成。
- 品质向上折算（多个低品质 → 一个高品质）**不保证收益**，它是否划算完全由 `v()` 的曲线形状决定；`v()` 若超线性，则该表项是**内容设计**而非数值缺陷，必须走 §10 的套利环测试逐一验证。品质折算表项的释放节奏见 §11。

### 5.3 守恒要求与唯一写入入口

**守恒三断言**（每次结算必须全部成立，进入 §10 测试）：

```
(1) value_out ≤ value_in × (1 − conversion_loss)          # 不凭空产生
(2) remainder_value < v(target)                            # 取整残余上界
(3) value_in − value_out = value_in × conversion_loss + remainder_value   # 变化可加总
```

- **转化是唯一允许改变「玩家持有类别分布」的后天入口。** 物资进入背包只有两个来源：**开盒**（见 `01-gacha.md` / `09-presentation.md`）与**转化**（本文档）；`category` 是 `MaterialDef` 的不可变属性（见 `02-material.md`），物资**不得原地换类别**，只能"销毁源 + 产出目标"。
- [补充] **`quote()` 与 `convert()` 必须共用同一函数体**，UI 预览值与实际结算值必须逐位相等。理由：把 README §2.2「显示的分布＝实际用的分布」这条铁律复用到转化，防止第二处"显示与实际不一致"的 bug 源。
- [补充] **拒绝即零副作用**：任何 `ok == false` 的路径都不得写入背包（原子性）。理由：核心未定义结算失败时的状态边界。
- **残余即已声明损耗。** `remainder_value` 不得静默消失：它是第 (3) 条的一部分，进归因（P2）。

### 5.4 套利环封印（由公式保证，由测试守护）

对转化表上任意**有向闭路** `k` 步：

```
Π ratio_k = (1 − conversion_loss)^k ≤ 0.9^k < 1
```

闭路上每次折算的 `v(source)/v(target)` 逐项相消（回到同一「类别 × 品质」），因此只要满足：**(a) 每条边 `conversion_loss ≥ conversion_loss_floor > 0`**、**(b) 结算永远 `floori`**、**(c) 表项无奖励倍率**、**(d) 不自动生成反向表项**，A→B→A **在数学上不可能净赚**。品质折算不破坏该结论。

- [补充] **反向表项必须显式配置，不自动生成。** 理由：配置期自动补反向边是意外制造 `ratio ≥ 1` 环的主要途径。
- **表连通性约束（由核心 §10.3 推出）：** 转化表**不得完全连通**。若任意类别两两可达，`category` 维度失效，任务需求的摩擦（§10.3 后期唯一压力来源）被消掉，R1/R5 同时触发。首切片推荐 2 类别 2 条有向边。

## 6. 参数表（推荐值 + 调参旋钮标记）

| 参数 | 代码名 | 推荐值 | 旋钮 | 说明 |
|---|---|---|---|---|
| 转化损耗基准 | `conversion_loss_base` | **0.30** | 🔧（核心 D9） | **ρ 的主要旋钮之一**；提高 → 转化变贵 → 卡关压力上升 |
| 转化损耗下限 | `conversion_loss_floor` | **0.10** | 🔧 | 修正的绝对下限（D9 明示"可被装置降到 10%"）；不得为 0 |
| 装置修正值 | `device_loss_reduction` | 归 **04** | — | 见 `04-device.md`，本文档不定义 |
| 最小产出 | `min_count_out` | 1 | — | 常量，不提供接口使其 < 1 |
| 源数量上限 | — | 无上限 | — | 转化的唯一代价是损耗，不额外设次数/冷却 |
| 品质折算 | `allow_quality_conversion` | **首切片 false** | 🔧 | 见 §11 |
| 首切片表项数 | `entries.size()` | **2**（A→B、B→A） | 🔧 | 2 类别，核心 §13.1 的切片范围 |
| 表连通性 | — | 非完全连通 | — | 硬约束，见 §5.4 |
| 折扣上限 | — | 修正不得使 `conversion_loss` 低于下限 | — | 结算取 `clampf` |

## 7. 流程 / 状态机

```
IDLE
 └─▶ SELECT_SOURCE   选源：类别 + 品质 + 持有量（读 02 的持有向量）
      └─▶ SELECT_TARGET  选目标：仅列出转化表中存在的**出边**
           └─▶ PREVIEW     quote() 实时报价：ratio / count_in / count_out / conversion_loss
                ├─ ok == false ─▶ REJECTED（显示 min_count_in 或"不可转化"）─▶ IDLE
                └─ ok == true  ─▶ CONFIRM ─▶ SETTLE ─▶ COMMIT ─▶ RESULT ─▶ IDLE
```

- **SETTLE** 纯函数，输出 `ConversionQuote` + `ConversionLogEntry`。
- **COMMIT** 是本文档的**唯一写入入口**：`ConversionService.convert()` 是唯一被允许提交跨类别物资变更的函数，它通过 02 的唯一物资写入接口提交一个 `delta`（接口见 `02-material.md`）。
- **原子性**：SETTLE 与 COMMIT 必须成对成功，任何一步失败则本次调用不改变状态。
- **不在流程内做需求匹配**：缺口提示由任务面板提供（见 `03-task.md` / `08-ui-panels.md`）。
- **教学介入点**：15–30 min。此阶段 UI 只暴露 SELECT → PREVIEW → CONFIRM，`conversion_loss` 恒为 30%，**不出现任何"可降低"字样**（那是装置在 30 min–1 h 引入的内容，见 `04-device.md`）。

## 8. 与其它系统的接口

| 对方 | 方向 | 接口 |
|---|---|---|
| **02 物资** | 读 / 写 | 读：持有向量、`MaterialDef` 的 `category` / `quality`。写：**只经由 02 的唯一物资写入接口**提交 delta；本文档不直接改背包 |
| **03 任务** | 只读参照 | 不调用 03 的匹配逻辑；转化的产出是否满足需求由 03 判定 |
| **04 装置** | 被调用 | 04 提供 `device_loss_reduction`；本文档提供 `conversion_loss_base` 与 `conversion_loss_floor`（README 所有权表） |
| **05 模块与池子** | 无 | 转化不读、不写池子状态 |
| **07 数值与期望** | 双向 | 本文档请求 `v()` 口径并产出 `ConversionLogEntry` 作为 ρ 归因输入量；**ρ 的口径归 07**，本文档不解释 ρ |
| **08 界面与信息** | 被呈现 | 本文档声明必需信息元素（§9），呈现规格归 08 |
| **10 收集与进度** | 单向声明 | [补充] **转化产出不触发图鉴登记**（图鉴只由开盒产出登记），登记口径的最终措辞归 `10-progression.md`。理由：否则转化会成为刷图鉴的后天路径，收集意义受损 |

## 9. UI 需求

### 9.1 归属裁决（明确）

> **转化不新增第七个常驻面板。** 核心 §8.1 明确只有六面板；新增面板会稀释"界面即玩法"的预算，也与 R3（池子编辑变成第二个工作台）同型。

- **入口与呈现规格**：内嵌于**任务面板**（核心 §8.1「任务面板 = '使用物资'的工作台」）——在缺口高亮旁提供转化入口。该入口的形态、位置与展开规格归 **08**。
- **操作场景**：钻取到独立工作台场景 `scenes/workbench/conversion.tscn`（核心 §14.1 已列出 `scenes/workbench/ # 转化`）。本文档只声明必需信息元素，布局规格归 08。
- 一句话：**数据与结算归 06，呈现归 08，入口寄生在任务面板，操作落在 workbench 场景。**

### 9.2 必需信息元素（08 负责渲染）

- 源：类别 / 品质 / **持有量**（来自 02）
- 目标：类别 / 品质（**只列出转化表中存在的出边**，无出边的目标不显示）
- **折算比 `ratio`**：15–30 min 教学阶段**唯一需要展示的数字**
- 本次将消耗 `count_in` / 产出 `count_out`（实时预览，P6）
- `conversion_loss` 的**单一数字展示**（引入时恒为 30%）
- 不足时显示 `min_count_in`；`ok == false` 时禁用提交

### 9.3 禁止项

- **禁止一键最优配置**：只提供试算，不提供自动决策（D12：一键最优直接关系 R1）。
- **禁止在 15–30 min 引入时展示概率、ρ、方差或"损耗叠加"**——前 15 分钟不需要理解概率（核心 §11）。
- **禁止把 `v()` 的计算结果在 UI 层另算**（P1 / 铁律 3 的精神：显示值必须来自同一计算源）。

## 10. 测试点与验收标准

| # | 测试 | 断言 |
|---|---|---|
| T1 | **转化守恒** | §5.3 三断言全部成立；`value_out ≤ value_in × (1 − conversion_loss)`；`remainder_value < v(target)`；`Σ 归因条目 == 背包总价值变化`（P2） |
| T2 | **损耗率正确性** | 无装置时 `conversion_loss == 0.30`（逐位）；修正拉满时 `== 0.10`；任何输入下 `0.10 ≤ conversion_loss ≤ 0.30`；`conversion_loss` 可被逐项归因到 04 的装置条目 |
| T3 | **无套利环（守护测试）** | 枚举转化表所有 2–3 步**有向闭路**，断言 `Π ratio < 1` 且结算后 `value_end < value_start`；**含品质折算路径**；任一闭路净赚即测试失败并列出该环 |
| T4 | **单一写入入口** | 静态检查：除 `ConversionService.convert()` 外，无任何代码路径写出跨类别物资；`category` 不可原地修改 |
| T5 | **显示即实际** | 对同一输入，`quote().count_out == convert()` 实际产出的 `count_out`（逐位相等） |
| T6 | **拒绝零副作用** | `ok == false` 的所有路径（`unsupported_edge` / `locked` / `insufficient` / `over_held`）调用后背包快照逐位不变 |
| T7 | **类别维度不失效** | 构造检查：转化表不得使**单一类别**可满足所有任务需求（由 §10.3 推出的硬约束） |
| T8 | **教学曲线可测** | 15–30 min 无装置状态下转化可用；UI 在只有一个数字（`ratio`）时即可完成一次转化；引入点不出现概率/ρ/修正概念 |
| T9 | **求解最小量** | `min_count_in` 一次即可成功（`min_count_in − 1` 必失败），边界不差一 |

### 失败信号（对齐核心 §13.4）

- **测试者从不使用转化，遇到缺口只会等下一个盲盒** → 转化不可达或入口埋太深（同 R12 型问题）。
- **测试者把转化当"万能兑换机"，不再看任务需求结构** → 表连通性过强，`category` 维度已失效（T7 应先失败）。
- **测试者在 15–30 min 的引入点就追问"损耗率和 ρ 什么关系"** → 转化不够直观，需简化而非补充说明。
- **测试者反复尝试 A→B→A 套利** → 损耗不可见/提示不足；**若真的净赚，按 T3 严重 bug 处理**。
- **测试者抱怨"按了转化却什么都没拿到"** → `min_count_in` 提示缺失（T9）。

## 11. 待定项

| # | 待定项 | 推荐 | 备选 | 影响 |
|---|---|---|---|---|
| C1 | 品质折算表项的释放节奏 | **第二切片**，由里程碑逐步解锁（与 D13 同构） | 首切片即开放 | 影响教学负担与 R11 内容节奏 |
| C2 | 多源混合转化 | **不提供**（一次单源） | 支持按比例混合 | 提供会显著抬高心算负担（R5 / P6） |
| C3 | 转化是否需要次数 / 冷却限制 | **不需要**，损耗即代价 | 每日次数 | 增加限制会削弱"简单直观"，且需要新的状态字段 |
| C4 | 转化产出是否计入图鉴 | **不计入**（最终措辞归 `10-progression.md`） | 计入 | 计入会让转化成为刷图鉴路径 |
| C5 | 任务面板是否提供"补齐缺口"的一键转化 | **不提供**，只给入口不给决策（对齐 D12） | 提供 | 直接关系 R1（"使用物资"退化为点击流水线） |
| C6 | 是否展示转化对 ρ 的影响 | 引入阶段**不展示**，装置引入后再接入归因面板 | 始终展示 | 关系核心 §11 的教学顺序 |
| C7 | `conversion_loss` 是否随进度变宽/变窄 | **恒定**（符合 P7 功率封顶；成长靠内容释放 §2.4） | 随进度变化 | 变化即等于"按进度调参"，触碰 P1 |

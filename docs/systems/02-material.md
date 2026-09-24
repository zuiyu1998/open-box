# 02 · 物资系统

- 上游：`../core-design.md` **v0.6** ／ `README.md`
- 依赖系统：01 盲盒（产出来源）、03 任务（消耗请求）、04 装置 / 05 模块与池子（引擎出口消耗请求）、06 转化（转换请求）、07 数值与期望（消费 `v` 的定义）
- 被依赖：03、04、05、06、07、08、10

> 一句话职责：**定义物资的两维属性与价值口径，并作为物资持有量的唯一写入方，管理堆叠与数量增减。**

---

## 1. 这个系统负责什么

1. **`MaterialDef` 两维定义**：类别 `category` × **物资品质 `quality`**（核心 §4.2、D2 推荐值）。**术语纪律：本文档中的"品质"一律指物资品质 `quality`；"套系品质 `series_quality`"是核心 §4.1.1 的概念，本文档只引用、不拥有。**
2. **物资价值 `v_i` 的定义**（口径归本系统，计算归 07）。
3. **背包与堆叠规则**：同类别同品质一叠 + 数量上限。
4. **重复款 → 数量增加**（P5「重复与过剩永远不是空手」）。
5. **物资来源清单**：本系统只负责"入库动作"，来源规则指向对应系统。
6. **两个出口在物资侧的表现**：燃料 `fuel` / 引擎 `engine` 的扣减与堆叠状态变化。
7. **UI 呈现需求**：图标、品质色、数量徽标。
8. **R5 责任**：物资心算负担由本系统封顶——**背包格数上界 = 类别数 × 品质数**，与套系数、款数、进度全部无关。

**切片范围（核心 §13.1）：2 个类别 × 3 档品质 = 6 种物资、6 个背包格。这是硬上限，不是目标值。**

---

## 2. 不负责什么（边界）

| 不归本系统 | 归属 |
|---|---|
| 任务需求匹配、缺口高亮、奖励结算 | 见 `docs/systems/03-task.md` |
| 类别间转换与损耗（D9） | 见 `docs/systems/06-conversion.md` |
| 物资作为装置素材被消耗的规则与量 | 见 `docs/systems/04-device.md` |
| 物资作为模块素材被消耗的规则与量 | 见 `docs/systems/05-module-pool.md` |
| EV / `M̄` / `D̄` / `B` / ρ / σ 与归因 | 见 `docs/systems/07-economy-rho.md` |
| 款（`Item`）级图鉴、套系进度、存档结构 | 见 `docs/systems/10-progression.md` |
| 开箱演出与"被排除款不出现" | 见 `docs/systems/09-presentation.md` |
| 面板布局、展开入口、"共有 N 款"提示 | 见 `docs/systems/08-ui-panels.md` |
| 位次占用（装置槽位、镶嵌位）的记录——其数量**由套系品质决定**（核心 §4.1.1），本文档不假设任何固定值 | 见 `docs/systems/04-device.md` / `docs/systems/05-module-pool.md` |

**边界声明：本系统是物资数量的唯一写入方，但从不决定"该消耗多少"。** 03/04/05/06 提出请求，本系统只执行扣减并回报成功或失败。

---

## 3. 核心概念与术语

| 中文名 | 代码名 | 本系统中的含义 |
|---|---|---|
| 物资 | `Material` | 从盲盒开出的实体资源，有类别与品质 |
| 类别 | `category` | 物资的种类维度，决定能满足哪类任务需求 |
| 品质 / **物资品质** | `quality` | **本文档的"品质"一律指此**：物资的等级维度（序数，1 = 最低），决定任务贡献度与素材强度 |
| 套系品质 | `series_quality` | 套系的品质分级（1 普通 / 2 精良 / 3 稀有 / 4 传说），决定该套系的常规款数 `regular_count`、镶嵌位数、装置槽位数与物资品质区间。**归属核心 §4.1.1，本文档只引用、不拥有**（与上行的物资品质是两个不同概念，不得混用） |
| 堆叠 | `stack` | 一个背包格：同类别 + 同品质的物资合并计数 |
| 堆叠键 | `stack_key` | `"<category>:<quality>"`，堆叠的唯一身份 |
| 物资单位 | `unit` | `M̄` / `D̄` 的计量单位；1 单位 = 该物资 `unit_value` 份价值 |
| 燃料 | `fuel` | 出口之一：交付任务被消耗 |
| 引擎 | `engine` | 出口之一：装配为装置 / 镶嵌为模块 |
| 款 | `Item` | 池中的一个可产出物；一款产出一笔物资（数量 ≥ 1） |
| 物资价值 | `v` | 单款产出对 `M̄` 的贡献口径 |

术语一律沿用 `README.md` §5，不得自造同义词。**术语纪律（v0.6）："品质"一词在本文档内一律指物资品质 `quality`；提到套系分级时必须写全"套系品质 `series_quality`"并注明归属核心 §4.1.1。二者不可互相顶替。**

---

## 4. 数据结构（GDScript Resource 字段定义）

### 4.1 `MaterialDef`（`res://data/defs/material_def.gd`）

```gdscript
@tool
class_name MaterialDef
extends Resource

@export var material_id: StringName = &""      # 唯一 id，推荐 = "<category>_<quality>"
@export var category: StringName = &""          # 类别，指向 MaterialCategoryDef.id
@export_range(1, 5) var quality: int = 1        # 物资品质 quality 序数，1 = 最低（≠ 套系品质 series_quality，见核心 §4.1.1）
@export var display_name: String = ""           # 展示名，如"星尘·精良"
@export var icon: Texture2D                     # 背包/任务面板图标
@export var unit_value: int = 1                 # v 的单位价值（本系统定义，07 使用）
@export_range(1, 99999) var stack_limit: int = 999  # 单堆叠上限
@export var tags: Array[StringName] = []        # 预留：场景约束/特殊需求标记（见 03）

func stack_key() -> StringName:
	return StringName("%s:%d" % [category, quality])

func key() -> StringName:
	return stack_key()
```

> `[补充]` **`MaterialCategoryDef` 类别注册表**（`category_id` / `display_name` / `icon` / `sort_order`）：理由是核心 §14.3 与 R11 要求"新物资类别"可**纯配置产出**，若 `category` 用 `enum` 则每加一类都要改代码。`MaterialDef.category` 用 `StringName` 引用该表。

> `[补充]` **`star` 与 `quality` 同源**：核心 §6.1 默认层显示星级、§14.2 存档记录 `star`，本系统让二者共用同一 1–5 序数，理由是避免出现"物资品质等级"与"星级"两套并行等级，直接加重 R5。（**套系品质 `series_quality` 不属于本文档**，见核心 §4.1.1）

### 4.2 `InventoryStack`（运行时堆叠）

```gdscript
class_name InventoryStack
extends Resource

@export var stack_key: StringName = &""
@export var category: StringName = &""
@export_range(1, 5) var quality: int = 1
@export var count: int = 0                      # 当前持有数量
@export var last_source: StringName = &""       # 最近一次入库来源标签
@export var last_gain_serial: int = 0           # [补充] 新获得高亮的排序依据
```

### 4.3 `MaterialService`（`res://autoload/material_service.gd`，唯一写入方）

```gdscript
extends Node

var inventory: Dictionary = {}                  # stack_key -> InventoryStack
var total_granted: int = 0                      # 累计入库（数量守恒对账）
var total_consumed: int = 0                     # 累计出库（含转化投入与损耗）

# 唯一入库入口：开盒产出 / 转化产出 / 拆除返还 / 解锁发放都走这里
func grant(category: StringName, quality: int, amount: int,
		source: StringName = &"unknown") -> void: ...

# 唯一出库入口：fuel / engine / convert 三种出口标签
func consume(category: StringName, quality: int, amount: int,
		tag: StringName) -> bool: ...

func count_of(category: StringName, quality: int) -> int: ...
func snapshot() -> Array[InventoryStack]: ...    # 供 03/07/08 只读消费
func can_afford(category: StringName, quality: int, amount: int) -> bool: ...
```

**铁律：没有任何其它系统可以直接改 `inventory` 或 `count`。** 与 `PoolService` 对池子状态的独占同级（`README.md` §3.2）。

---

## 5. 规则与公式

### 5.1 两维定义

| 维度 | 取值范围 | 切片推荐 | 作用 |
|---|---|---|---|
| `category` 类别 | 可配置的 `StringName` 清单 | **2 个：`stardust` 星尘 / `crystal` 晶核** | 决定能满足哪类任务需求（匹配规则见 `docs/systems/03-task.md`） |
| `quality` **物资品质** | 1–5 序数 | **3 档：1 普通 / 2 精良 / 3 稀有** | 决定任务贡献度与作为素材的强度（消耗规则见 `docs/systems/04-device.md` / `docs/systems/05-module-pool.md`）。**指物资品质，与套系品质 `series_quality` 无关** |

**为什么是这 2 个类别（R5 的直接回答）：**

1. **两个类别是"需求向量"最小的非退化规模。** 只有 1 类时任务需求退化成标量（只要数量），"需求结构"这条后期摩擦来源（核心 §10.3）失效；2 类即可让需求向量真实存在。
2. **星尘 / 晶核的定位差异体现在需求侧而非价值侧**：前期常规任务主吃星尘，里程碑与后期任务开始要求晶核（后期摩擦见 `docs/systems/03-task.md` 与 `docs/systems/10-progression.md`）。
3. **2 × 3 = 6 格可心算。** 玩家可以一眼看完整个背包，不需要查表（P6）。
4. 两者的相互转换唯一方向对由 06 定义，见 `docs/systems/06-conversion.md`。

### 5.2 物资价值 `v_i` 的定义（口径归本系统，计算归 07）

```
v_i = unit_value(category_i, quality_i) × amount_i
      └──────┬──────┘                     └──┬──┘
      MaterialDef.unit_value            该款单次产出数量（≥ 1）
```

- `v_i` 是**池中第 i 款物品一次产出的价值**，也是本系统交给 07 的唯一价值口径。
- 07 用它计算 `M̄ = Σ(pᵢ × vᵢ) × 池子修正`（核心 §2.3）——**本系统不参与该求和，也不做任何池子修正**。计算与归因见 `docs/systems/07-economy-rho.md`。
- 默认层"最好的物品"即 `v_i` 最大的可产出款（核心 §6.1），该判定由 07 产出，本系统只保证 `unit_value` 与 `amount` 可读。
- 本系统对 `v` 的可心算性负责：**推荐全部物资的 `unit_value` 严格等于其品质阶梯值**，与类别无关。这样玩家只需记住 3 个数字，而不是 6 个（R5）。

### 5.3 背包与堆叠

| 规则 | 内容 |
|---|---|
| **R-M1 堆叠键** | `stack_key = "<category>:<quality>"`。**同类别同品质必合并成一格，不论来自哪一款。** |
| **R-M2 格数上界** | 背包格数 ≤ 类别数 × 品质数（切片 = 6）。**上界只随内容（新类别）变化，绝不随进度、套系、款数变化**（P7 同精神）。 |
| **R-M3 数量上限** | 每格 `count ≤ stack_limit`（推荐 999，🔧）。 |
| **R-M4 溢出** | 溢出量进入 `overflow_buffer` 缓冲并高亮提示，**绝不丢弃、绝不静默扣减**（P5）。切片推荐值下几乎不触发，见 §11。 |
| **R-M5 归零** | `count == 0` 时删除该格（不保留空格），并清除新获得高亮。 |

> `[补充]` **溢出缓冲 `overflow_buffer`**：核心文档未定义堆叠上限，而 P5 明令禁止"什么都没得到"，因此满格时的多余产出必须有一个不丢失的去处。

### 5.4 重复款 → 数量增加（P5）

- 任何款被重复产出时，**该款对应的 `(category, quality)` 堆叠 `count += amount`**，且 `amount ≥ 1`。
- **两款不同但 `(category, quality)` 相同，同样合并进同一格。** 这是刻意的：物资层不区分款，款级收集归图鉴（见 `docs/systems/10-progression.md`）。
- **不存在"空手"结果**：概率为 0 的款不会产出（那是排除，见 `docs/systems/05-module-pool.md`），但任何一次实际产出都至少让某一格 +1。
- 重复款的第二个价值出口是**引擎原料**（核心 §7 P5）：多余的物资是装置与模块的素材，规则见 `docs/systems/04-device.md` / `docs/systems/05-module-pool.md`。

### 5.5 两个出口在物资侧的表现

| 出口 | 核心 §3 | 物资侧的状态变化 | 谁决定量与规则 |
|---|---|---|---|
| **燃料 `fuel`** | 交付给任务 | 调用 `consume(category, quality, n, &"fuel")` → 该格 `count -= n`；归零则删除格 → 请求方（03）再结算奖励 | 需求匹配见 `docs/systems/03-task.md` |
| **引擎 `engine`** | 装配装置 / 镶嵌模块 | 调用 `consume(..., &"engine")` → 该格 `count -= n`。**物资被永久消灭；位次占用不在本系统记录。** | 素材量与规则见 `docs/systems/04-device.md` / `docs/systems/05-module-pool.md` |
| **转化 `convert`** | 类别间转换 | 调用 `consume(..., &"convert")` 出库；产出的另一类别走 `grant(..., &"convert")` 入库 | 见 `docs/systems/06-conversion.md` |

**补充约束（本系统硬规则）：**

- **R-M6 原子扣减**：`consume` 要么全量成功、要么完全不改状态，失败返回 `false`。**禁止部分扣减。** `[补充]` 理由：03 的交付必须是确定的成功/失败，且部分扣减会让 §10 的数量守恒测试无法对账。
- **R-M7 不允许负数**：任何路径都不得让 `count < 0`；`consume` 前必须 `can_afford`。
- **R-M8 拆除返还**：核心 D8 的"拆除返还 50%"由 04/05 判定金额，本系统只把它当作一次 `grant(source = &"refund")` 入库，不重算返还率。见 `docs/systems/04-device.md` / `docs/systems/05-module-pool.md`。
- **R-M9 出口标签记账**：每次 `consume` 记录 `tag`（`fuel` / `engine` / `convert`）。`[补充]` 理由：P2 要求逐项归因，07 需要按出口读取扣减量，本系统只提供原始事件、不做归因计算。
- **R-M10 数量守恒**：任意时刻恒有 `Σ count == total_granted − total_consumed`。任何破坏该等式的路径都是 bug。

### 5.6 物资的来源清单

| 来源 | 归属 | 本系统的动作 |
|---|---|---|
| **开盲盒产出（主来源）** | 款与权重的判定见 `docs/systems/01-gacha.md`，演出见 `docs/systems/09-presentation.md` | 结算后 `grant(source = &"gacha")` |
| **类别间转化产出** | 见 `docs/systems/06-conversion.md` | `grant(source = &"convert")` |
| **拆除装置 / 模块返还 50%**（核心 D8） | 见 `docs/systems/04-device.md` / `docs/systems/05-module-pool.md` | `grant(source = &"refund")` |
| **里程碑 / 套系解锁发放** | 见 `docs/systems/10-progression.md` | `grant(source = &"unlock")` |
| 任务奖励 | **不含物资**（核心 §4.3：奖励为盲盒、券、位次），见 `docs/systems/03-task.md` | — |

**明确排除：任务不产出物资。** 否则"交付物资 → 拿回物资"会形成自环，虚高 ρ 并使燃料出口失去代价（核心 §3.1）。

---

## 6. 参数表（推荐值 + 调参旋钮标记）

| 参数 | 位置 | 推荐值 | 说明 |
|---|---|---|---|
| `category` 数量 🔧 | 内容配置 | **2**（切片） | 每加一类，背包格数与心算负担同时上升（R5）。加类属内容释放，见 `docs/systems/10-progression.md` |
| 类别清单 | `MaterialCategoryDef` | `stardust` 星尘 / `crystal` 晶核 | 推荐由里程碑解锁晶核（`docs/systems/10-progression.md`） |
| `quality` **物资品质**档数 🔧 | 内容配置 | **3**（切片：1 普通 / 2 精良 / 3 稀有） | 指**物资品质**（1–5 序数，与套系品质 `series_quality` 无关）；终局上限 5；与模块品质梯度节奏（核心 D13）解耦，见 §11 |
| `unit_value` 阶梯 🔧 | `MaterialDef` | **1 / 3 / 9**（几何 ×3） | **与类别无关**。3 个数字可心算；改这里等于整体缩放 `M̄`，是 ρ 的主力旋钮之一（实际影响由 07 结算） |
| `stack_limit` 🔧 | `MaterialDef` | **999** | 切片取宽值以避免引入背包管理玩法；字段与边界测试必须存在 |
| 溢出缓冲容量 🔧 | `MaterialService` | 999 | `[补充]` 不丢产出的兜底 |
| 物资品质色（`quality`） | UI 主题 | 1 `#B9C0C9` 灰白 / 2 `#4FA3E3` 青蓝 / 3 `#A66CF2` 紫 | 见 §9；指**物资品质**；4/5 档预留 |
| 数量徽标格式 | UI 主题 | `1–999` 直显；`≥1000` 转 `1.2k` | 仅显示层，不改变真实数值 |

---

## 7. 流程 / 状态机

### 7.1 单堆叠生命周期

```
[不存在] ──grant(n)──▶ [持有 count=n] ──grant(n)──▶ [持有 count=n+m]
                          │                              │
                          │                        count==stack_limit
                          │                              ▼
                          │                        [满] ──grant──▶ overflow_buffer（不丢失）
                          │                              │
                          └────consume(n)（燃料/引擎/转化）────┘
                                     │
                              count==0 ──▶ [不存在]（删除格）
```

### 7.2 一次开盒入库（本系统视角）

```
01 结算 roll() → 款 + amount
   → 09 演出（本系统不参与）
   → MaterialService.grant(category, quality, amount, &"gacha")
       ├─ 无该 stack_key → 新建 InventoryStack，count = amount
       └─ 已有 → count += amount（超过 stack_limit 的部分进 overflow_buffer）
   → total_granted += amount
   → 标 last_gain_serial，通知 08 高亮新获得格
```

### 7.3 一次消耗（燃料 / 引擎 / 转化统一路径）

```
请求方（03 / 04 / 05 / 06）
   → MaterialService.consume(category, quality, amount, tag)
       ├─ amount > count        → 返回 false，状态不变（原子）
       ├─ amount == count       → count = 0，删除格，返回 true
       └─ amount < count        → count -= amount，返回 true
   → total_consumed += amount，记录出口标签
   → 07 只读读取扣减事件做归因（见 docs/systems/07-economy-rho.md）
```

---

## 8. 与其它系统的接口

| 方向 | 接口 | 说明 |
|---|---|---|
| 01 → 02 | `grant(category, quality, amount, &"gacha")` | 抽取结果入库。**款 → 物资的映射字段归属见 §11 待定项** |
| 03 → 02 | `can_afford()` / `consume(..., &"fuel")` | 需求匹配与奖励结算归 03，见 `docs/systems/03-task.md` |
| 04 → 02 | `consume(..., &"engine")` | 装置素材量与槽位占用归 04，见 `docs/systems/04-device.md` |
| 05 → 02 | `consume(..., &"engine")` | 模块素材量与镶嵌位归 05，见 `docs/systems/05-module-pool.md` |
| 06 → 02 | `consume(..., &"convert")` / `grant(..., &"convert")` | 转换表与损耗归 06，见 `docs/systems/06-conversion.md` |
| 02 → 07 | `snapshot()` 与 `unit_value` / `amount` | 07 用 `v_i` 算 `M̄` 与归因；**本系统不参与计算**，见 `docs/systems/07-economy-rho.md` |
| 02 → 08 | `snapshot()`（类别/品质/数量/品质色/图标） | 渲染归 08，需求见 §9 与 `docs/systems/08-ui-panels.md` |
| 02 → 10 | 堆叠序列化 | 存档结构归 10，见 `docs/systems/10-progression.md` |

> `[补充]` **`regular_count` / `socket_count` 是每套系常量**：核心 §4.1.1 已给出"常规款数"与"镶嵌位"（品质 1–2 为 8 款 / 品质 3–4 为 12 款），此处补上其代码名以便与 01/05 对齐字段。理由：02 在任何地方都**不得假设"8 款常规"或固定镶嵌位**——二者的数值由套系品质 `series_quality` 决定，归属 01（`SeriesDef`）与 05。

> `[补充]` **款 → 物资产出的字段位置暂定在 `SeriesDef` 的款条目**（`{ item_id, weight, category, quality, amount }`）：核心 §14.1 的 `SeriesDef` 字段清单里只列了权重/隐藏款/保底/`socket_count`，未给出款到物资的映射位置。本系统只要求该条目引用 `MaterialDef` 的 `category` / `quality` / `amount`，归属待 `docs/systems/01-gacha.md` 确认（记录于 §11）。

---

## 9. UI 需求

**呈现归 08，以下为物资侧的硬需求（见 `docs/systems/08-ui-panels.md`）。**

| 需求 | 规格 |
|---|---|
| **图标** | 每 `MaterialDef` 一个图标；切片 6 个图标即够（2 类别 × 3 品质） |
| **品质色** | 格边框/底光按 `quality` 取色（1 灰白 / 2 青蓝 / 3 紫），**颜色是品质的第一识别通道**，图标是第二通道（色盲冗余） |
| **数量徽标** | 右下角数字徽标，`1–999` 直显，`≥1000` 转 `1.2k`；数量为 0 时不留空格 |
| **类别标识** | 类别以图标形状 / 组内分组区分；**不得只靠颜色区分类别**（与品质色冲突） |
| **新获得高亮** | 入库时该格高亮 + 数量滚动，持续 ≤ 1s，不阻塞任何操作 |
| **满格标记** | `count == stack_limit` 时角标提示；溢出时给出"必须处理"的显眼提示，且**说明产出未丢失**（P5） |
| **一格一物** | 背包界面不得出现同类别同品质的两个格子；出现即为 bug（R-M1） |
| **可心算** | 切片背包 6 格应能在一屏内完整呈现，不滚动、不翻页（P6 + R5） |
| **不显示计算** | 不在物资格上显示 `v_i` 或 ρ 影响（那是 07/08 的事）；物资面板只回答"我有什么、有多少" |

---

## 10. 测试点与验收标准

### 10.1 堆叠边界（必测）

1. `count = 1` 与 `count = stack_limit` 两端各测一次入库、扣减、归零。
2. 同 `(category, quality)` 的两款不同物资产出 → **合并为一格**，格数不变。
3. 同类别不同品质 → 两格；不同类别同品质 → 两格。
4. `count == stack_limit` 时再 `grant` → 溢出量完整进入 `overflow_buffer`，`Σ count` 不变、总产出不丢（P5）。
5. `consume` 恰好等于 `count` → 格被删除，`snapshot()` 中不再出现该 `stack_key`。
6. 背包格数上界：随机产出 10000 次后，格数 ≤ 类别数 × 品质数（切片 ≤ 6）。

### 10.2 数量守恒（必测）

1. 随机执行 1000 次 `grant` / `consume` / 转化序列后，恒有
   `Σ snapshot().count == total_granted − total_consumed`。
2. **消耗无凭空产生**：任何 `consume` 成功后，被消耗的数量必须**全部**计入 `total_consumed`，不得有"扣减不记账"或"记账不扣减"。
3. 转化路径的损耗体现为"出库 A、入库 A'（A' < A）"，等式仍成立（出库按全部 A 计）。
4. 失败路径：`consume` 超出持有量 → 返回 `false` 且 `inventory` 与两个计数器**完全不变**（R-M6 原子性）。
5. 任何路径后 `count < 0` 出现即为致命 bug（R-M7）。
6. 跨系统红线（C1–C4）归 01/05/07 守护，见 `docs/systems/05-module-pool.md` / `docs/systems/07-economy-rho.md`；本系统的对应红线是：**物资的任何写入都不得触碰池子状态或概率**（`README.md` §3.2）。

### 10.3 单写入方测试

- 静态检查：除 `MaterialService` 外，任何脚本对 `inventory` / `count` 的赋值都应被禁止（同 `PoolService` 的处理）。
- 拆除返还只走 `grant(source = &"refund")`，返还率不出现第二处实现（R-M8）。

### 10.4 切片失败信号（要正视）

| 信号 | 含义 | 对策方向 |
|---|---|---|
| 测试者说"我分不清哪堆是哪堆" | 品质色/图标不可辨 | 加大图标差异与边框对比，而非增加文字 |
| 测试者能说出某类物资"值多少"却说不出自己有多少 | 价值与持有量脱节 | 收紧 `v` 阶梯的心算性（类别不影响价值） |
| 背包出现超过 6 格 | R-M1 堆叠键被破坏 | **检查代码，不是调参** |
| 测试者问"这个物资到底有什么用" | 两个出口在物资层不可见 | 由 08 在任务/装配面板联动高亮，见 `docs/systems/08-ui-panels.md` |
| 测试者认为某次开盒"什么都没得到" | P5 破裂（产出被丢弃或数量为 0） | 立刻查 `grant` 与溢出路径 |
| 测试者抱怨"背包满了很烦" | 堆叠上限过低，引入了核心文档没有的背包管理玩法 | 🔧 提高 `stack_limit`（切片推荐 999） |

---

## 11. 待定项

| # | 待定项 | 现状与影响 |
|---|---|---|
| **M1** | **款 → 物资产出的字段归属**（`SeriesDef` 还是 02 自持） | 见 §8 `[补充]`；影响 `v_i` 的可读路径，需与 `docs/systems/01-gacha.md` 对齐 |
| **M2** | 堆叠上限是否应成为**真实压力** | 切片推荐 999（几乎不触发）。若后期希望背包构成资源压力，会引入核心文档未定义的管理玩法，须先回核心文档决策 |
| **M3** | 类别是否应影响价值（`unit_value` 是否偏离品质阶梯） | 推荐**不影响**（3 个数字可心算，R5）。若后期类别需要价值差异，等价于在 `v` 上再叠一层倍率，会直接加重 R5 |
| **M4** | 品质档位总数与全量维度 | 切片 3 档、上限 5 档；核心 D2（类别 × 品质两维）的推荐值已被本系统采用，**最终档数需与 D13 模块品质梯度的释放节奏一起定**（见 `docs/systems/05-module-pool.md`） |
| **M5** | 新类别的解锁方式 | 推荐由里程碑任务解锁（`docs/systems/10-progression.md`），但解锁节奏属内容产能问题（R11），需与 R11 对策一并评估 |

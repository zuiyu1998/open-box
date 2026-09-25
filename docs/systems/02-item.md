# 02 · 物品系统

- 上游：`../core-design.md` **v0.9** ／ `README.md`
- 依赖系统：01 盲盒（产出来源，**物品即池中条目本身**）、03 任务（消耗请求）、04 装置 / 05 模块与池子（引擎出口消耗请求）、06 转化（销毁源实例 + 创建新实例）、07 数值与期望（消费 `v`）、08 界面与信息呈现（仓库占比与邮件领取的呈现）、10 收集与进度（图鉴口径、存档结构）
- 被依赖：01、03、04、05、06、07、08、10

> **v0.9 说明（仓库容量与邮件）**：上游已裁决 **物品占地方，装不下的产出进邮件**（核心 §4.7）。
> ①`ItemDef` 新增 **`size`**（**同种物品大小相同**），实例新增 **`location`**（`warehouse` / `mail`）；②仓库容量 `warehouse_capacity` 是**抽象单位**（示意 1000），UI 只换算为**占比**显示；③**被动产出（开盒 / 迁移 / 解锁）放不下就进邮件**，而**主动操作（转化 / 拆卸返还）放不下则拒绝整个操作**（**裁决 17**），**邮件无上限、不过期**；④**领取只改 `location`**——不创建实例、不重新分配 `serial`、不重跑幂等判定；⑤**`count()` 只统计 `location == warehouse`**，邮件实例**不计入可用持有**，不可用于交付 / 装配 / 镶嵌 / 转化；⑥**只消耗不产出的操作不检查空间**，**只有"产出"会遇到空间问题**（被动产出进邮件、主动操作被拒）；⑦**玩家可主动丢弃仓库实例**（死局逃生阀，**裁决 16**）。
> **P5 的兜底论证换掉（v0.9）**：v0.7 的"无上限 ⇒ 不可能丢"随容量一并失效；新论证**分两层**——**被动产出**："**装不下就进邮件 ⇒ 产出永不丢失**"；**主动操作**："**放不下就拒绝整个操作 ⇒ 既没丢也没少**"（§5.3 / R-M14）。**除此以外规则与数值一律不变**：C1–C6、P1–P7、ρ 公式、40% 损耗、2% 隐藏物品、品质曲线、25%–40% 比例全部照旧。
> **v0.8 沿革（物品实例化）**：持有模型由**无上限计数**改为**实例列表 `Array[ItemInstance]`**，每个实例持有 **UUIDv4（`instance_id`，全局唯一，兼作幂等键）**，**`count` 变为派生值**；实例自带**溯源**（`acquired_at` + `source`）与**收藏编号**（`serial`）；**"堆叠"在结构上不可能存在**。**实现提醒**：Godot **没有**内置 UUID，`ResourceUID.create_id()` 返回 int64 的 `uid://` 串，**不是 UUID**（见 §4.5）。**v0.7 历史**：「物资」与「款」已合并为「物品」（`Item`），本文档由 `02-material.md` 改名而来。

> 一句话职责：**定义物品的两维属性与价值口径，并作为物品实例列表的唯一写入方，管理实例的创建、销毁与位置（仓库 / 邮件），`count` 为派生值。**

---

## 1. 这个系统负责什么

1. **`ItemDef` 两维定义**：类别 `category` × **物品品质 `quality`**（核心 §4.2、D2）。**术语纪律：本文档的"品质"一律指物品品质 `quality`；"套系品质 `series_quality`"归属核心 §4.1.1，本文档只引用、不拥有。**
2. **物品价值 `v_i` 的定义**（`ItemDef.value`；口径归本系统，计算归 07）。
3. **持有模型 = 实例列表**（v0.8）：**持有量就是 `Array[ItemInstance]`**。同一 `item_id` 的多个实例是**互不相同的个体**，不合并、不堆叠。**每个实例还有一个位置 `location`**（仓库 / 邮件，v0.9）。
4. **`count` 是派生值**：`count(category, quality)` 由**仓库内**实例**数出并缓存**（v0.9：**只统计 `location == warehouse`**，§5.9）；**任何地方都不得把它当作存储字段读写**（核心 §14.2 铁律 8）。
5. **重复物品 → 新增一个实例**（P5「重复与过剩永远不是空手」，§5.4）。
6. **来源清单与两个出口在物品侧的表现**：本系统只负责"创建实例 / 按实例销毁"这两个动作，来源与出口规则指向对应系统（§5.7、§5.8）。
7. **UI 呈现需求**：图标、品质色、数量徽标、实例级溯源明细（§9）。
8. **R5 责任**：**玩家看到的是派生索引的键（类别数 × 品质数，切片 6 个），不是实例列表**。实例数可以上万，聚合视图恒为 6 个数字，实例级明细只在按需展开处出现。**这是 v0.8 唯一的变化点：无上限计数 → 无上限实例列表 + 派生计数，心算负担不变。**
9. **仓库与邮件是实例的两个位置**（v0.9）：仓库有容量 `warehouse_capacity`（**抽象单位**，示意 1000），已用 = `Σ（仓库内实例的 size）`，对外只给**占比**（§5.9）。**溢出按产出类型分流（裁决 17）**：**被动产出**（开盒 / 迁移 / 解锁）放不下 → **进邮件**；**主动操作**（转化 / 拆卸返还）放不下 → **拒绝整个操作**。**"放得下 / 放不下"只有一个判定点**：由 `grant` 内部按传入的 `overflow` 策略决定——01/03/04/05/06 **不得各自判断容量**，也不得自行构造或改写实例。
10. **玩家可主动丢弃**（裁决 16，§5.7 R-M13）：仓库满 → 邮件领不出 → 任务交不了 → 拿不到新盒子 的死局由此可解；丢弃是**主动行为**，不违反 P5。

**切片范围（核心 §13.1）：2 个类别 × 3 档品质 = 6 种物品（6 个派生索引键）；实例数无上限。**

---

## 2. 不负责什么（边界）

| 不归本系统 | 归属 |
|---|---|
| 任务需求匹配、缺口高亮、奖励结算 | `docs/systems/03-task.md` |
| 类别间转换与损耗（D9） | `docs/systems/06-conversion.md` |
| 物品作为装置 / 模块素材被销毁的规则与量 | `docs/systems/04-device.md` / `05-module-pool.md` |
| EV / `M̄` / `D̄` / `B` / ρ / σ 与归因 | `docs/systems/07-economy-rho.md` |
| 图鉴、套系进度、存档文件与格式 | `docs/systems/10-progression.md` |
| 开箱演出与"被排除物品不出现" | `docs/systems/09-presentation.md` |
| 面板布局、聚合与展开入口、"共有 N 个物品"提示 | `docs/systems/08-ui-panels.md` |
| 位次占用（装置槽位、镶嵌位）——其数量**由套系品质决定**（核心 §4.1.1） | `04-device.md` / `05-module-pool.md` |
| **"未拥有物品权重 ×1.5"与保底**——本系统只提供缺口清单（§8） | `docs/systems/01-gacha.md` |
| 仓库 / 邮件面板的布局、**占比显示**、领取交互、开盒前的**下界式空间预告**（R14 对策③；算法与文案归 `01 §5.7`，**不得做件数预测**，见 §9）；容量成长节奏（D15）与容量 / `size` 的数值标定（D16，需切片实测） | `08-ui-panels.md`（面板）；核心 §15 / 本文档 §11 M7·M8（数值） |

**边界声明：本系统是物品实例列表的唯一写入方，但从不决定"该销毁几个、销毁哪几个"。** 03/04/05/06 提出请求（给出实例 id，或"类别 + 品质下限 + 数量"），本系统只执行销毁并回报成功或失败。**`location` 的写入同样独占**：只有 `grant`（产出落位）与 `claim`（领取）能改它，且**产出落位由本系统判定容量**——调用方不传"放哪儿"。

---

## 3. 核心概念与术语

| 中文名 | 代码名 | 本系统中的含义 |
|---|---|---|
| 物品 | `Item` | **既是池中的一个可产出物，也是玩家积累的资源**（v0.7 合并），有类别与品质 |
| 物品定义 | `ItemDef` | 一种物品的**静态属性**：`item_id` / `display_name` / `category` / `quality` / `value` / **`size`** / `is_hidden`；**归属本系统**，01 的 `SeriesDef` 只引用 |
| 物品实例 | `ItemInstance` | 玩家实际持有的**一个**物品；**每个实例持有一个 UUID，全局唯一** |
| 实例 id | `instance_id` | **UUIDv4，全局唯一**，兼作**幂等键**（同一 id 重复发放不得产生第二个实例） |
| 收藏编号 | `serial` | **该玩家开出的第 N 个此物品**；`0` = 非开盒来源（转化 / 返还 / 解锁 / 迁移） |
| 溯源 | `source` | 实例来自哪里：**开放字典**，`kind` 必填，其余键按来源类型附加（§4.2） |
| **物品大小** | `size` | `ItemDef.size`：该物品占仓库多少空间（**同种物品大小相同**，必须 > 0，§5.12）；**不是容量字段**——容量在仓库上 |
| **位置** | `location` | 实例所在的容器：`&"warehouse"` 仓库 / `&"mail"` 邮件（v0.9） |
| **仓库容量 / 已用** | `warehouse_capacity` / `warehouse_used` | 容量的**抽象单位**上限（示意 1000，UI 只换算为**占比**，**不是"格"**）；已用是**派生值** `Σ（location == warehouse 的实例的 size）`（§5.9） |
| **邮件** | `mail` | **被动产出**装不下的落点；**无上限、不过期**；其实例**不计入 `count`**、不可用于交付 / 装配 / 镶嵌 / 转化（§5.10） |
| 持有量 | `count` | **派生值**：由实例列表数出并缓存，**不是存储字段** |
| 派生索引 | `count_index` | `"<category>:<quality>" → int` 的派生缓存；R5 的封顶对象（切片 6 个键），也是本系统最常被读的接口 |
| 类别 | `category` | 物品的种类维度，决定能满足哪类任务需求 |
| 品质 / **物品品质** | `quality` | **本文档的"品质"一律指此**：1–5 序数，决定任务贡献度、素材强度与演出分级 |
| 套系品质 | `series_quality` | 套系的分级（1–4），决定该套系的常规**物品数**、镶嵌位数、装置槽位与物品品质区间。**归属核心 §4.1.1，本文档只引用、不拥有** |
| 燃料 / 引擎 | `fuel` / `engine` | 物品的两个出口：交付任务被销毁 / 装配为装置或模块被销毁 |
| 物品价值 | `value` | `ItemDef.value`，该物品的 TVU 价值 `v`（1 单位 = 该物品 `value` 份价值），EV 计算的输入 |

**术语纪律（"品质"两义）**：「品质」在本文档内一律指**物品品质 `quality`**（1–5 序数）；提到套系分级必须写全**"套系品质 `series_quality`"**（1–4，核心 §4.1.1）并注明归属，二者不可互相顶替。**`star` 已不存在**：演出分级直接读 `quality`。
**术语纪律（持有模型，含 v0.9 修订）**：不使用"堆叠""堆叠键""满格"，也不再使用 v0.7 的**"持有量键"**（那个键概念已随计数模型一并取消，身份已由 `instance_id` 承担）。持有一律说**实例**（`ItemInstance`），数量一律说 `count`（**派生**；重复就是**多一个实例**）。**v0.9 起"容量"与"溢出"解禁并重新钉死**：容量一律说**仓库容量 `warehouse_capacity`**（**抽象单位**，**不说"格""背包格""堆叠上限"**，且**容量属于仓库、不属于物品定义**）；溢出一律说**产出溢出**（"产出放不下仓库 → **按 `overflow` 分流：被动进邮件 / 主动被拒**"，§5.10 / R-M14），**不是** v0.6 已删除的溢出缓冲 `overflow_buffer`（§5.3），也**不是**任何"丢弃 / 蒸发"路径；**"丢弃"只说玩家主动的 `discard`**（R-M13）。

---

## 4. 数据结构（GDScript Resource 字段定义）

### 4.1 `ItemDef`（`res://data/defs/item_def.gd`；01 的 `SeriesDef` 只引用它）

```gdscript
@tool
class_name ItemDef
extends Resource

@export var item_id: StringName = &""           # 唯一 id，推荐 = "<category>_<quality>"
@export var display_name: String = ""           # 展示名，如"星尘·精良"
@export var category: StringName = &""          # 类别，指向 ItemCategoryDef.id
@export_range(1, 5) var quality: int = 1        # 物品品质 quality 序数（≠ 套系品质 series_quality，核心 §4.1.1）
@export var value: int = 1                      # 该物品的 TVU 价值 v（本系统定义，07 使用）
@export var size: int = 1                       # 该物品占仓库多少空间；同种物品大小相同（v0.9，必须 > 0）
@export var is_hidden: bool = false             # 是否为隐藏物品（概率恒 2%，免疫一切池子编辑）
@export var icon: Texture2D                     # 面板/条目图标（原样沿用 MaterialDef.icon）
@export var tags: Array[StringName] = []        # 预留：场景约束/特殊需求标记（见 03）
```

> **`ItemDef` 不再有产出映射字段**（`yield_material_id` / `yield_amount` 随 v0.7 合并删除）。**`size` 不是容量字段**：它是**定义级常量**（同种物品大小相同），**容量在仓库上、不在物品定义上**——所以这**不是** v0.6 已删除的"堆叠上限 / 背包格"从后门回来（核心 §4.7 明确"仓库只是实例的一个位置属性，不是独立系统"）。派生索引的键固定为 `"<category>:<quality>"`（§4.4）——它只是索引键，不是持有量的身份。
> `[补充]` **`icon` 与 `tags` 原样沿用 `MaterialDef` 的同名字段**（v0.7 术语合并未涉及它们，规则不变）：`icon` 由 §9 的图标需求使用，`tags` 供 03 的场景约束预留。二者不是新增机制。
> `[补充]` **`ItemCatalog`（`item_id → ItemDef` 只读注册表；`ItemCategoryDef` 为类别注册表）**：`grant` 只接收 `item_id`，而派生索引的键是 `(category, quality)`——没有注册表就必须把 `category` / `quality` **冗余进每个实例**（每实例多约 30 B，且引入"实例属性与定义不一致"的风险）。类别用 `StringName` 引用注册表而非 `enum`，才能让"新物品类别"纯配置产出（核心 §14.3 / R11）。**v0.9 起注册表还必须提供反查 `resolve_item_id(category, quality) -> StringName`，并在加载时强制 `(category, quality)` 唯一**（§5.12）——否则 04/05/06 会各自拼 `item_id` 字符串，拼错只能等到运行时才暴露。
> `[补充]` **`star` 字段已删除**：演出分级改用 `quality >= 阈值`（见 09）。二者本就同源同值，保留两个名字等于两套并行等级，直接加重 R5。

### 4.2 `ItemInstance`（`res://data/defs/item_instance.gd`，v0.8 新增）

```gdscript
class_name ItemInstance
extends Resource

@export var instance_id: String = ""            # UUIDv4（36 字符，小写），全局唯一，兼作幂等键
@export var item_id: StringName = &""           # 指向 ItemDef；category/quality 经 ItemCatalog 查出
@export var acquired_at: int = 0                # 入库时刻（int(Time.get_unix_time_from_system())，Unix 秒）
@export var source: Dictionary = {}             # 溯源：开放字典，kind 必填，其余键按来源类型附加（见下表）
@export var serial: int = 0                     # 该玩家开出的第 N 个此物品；0 = 非开盒来源
@export var location: StringName = &"warehouse" # 所在容器：&"warehouse" 仓库 / &"mail" 邮件（v0.9）
func to_dict() -> Dictionary: ...                # 键序固定（§4.6 的字节级稳定依赖它）
static func from_dict(d: Dictionary) -> ItemInstance: ...
```

**`source` 的 Dictionary 结构（v0.9：**开放字典**——`kind` 必填，其余键按来源类型附加，允许扩展）：**

| 键 | 类型 | 含义 | 出现条件 |
|---|---|---|---|
| `kind` | `StringName` | `&"gacha"` / `&"convert"` / `&"refund"` / `&"mail"` / `&"migrate"` / `&"unlock"` | **全部实例（必填）** |
| `series_id` | `StringName` | 来自哪个套系 | 仅 `gacha`，否则 `&""` |
| `box_seed` | `int` | 该次兑现的种子（与开箱日志的 `seed` 同源） | 仅 `gacha`，否则 `0` |
| `draw_index` | `int` | 该次兑现在该批盲盒中的序号（与 `GachaResult.draw_index` 同源） | 仅 `gacha`，否则 `-1` |

> `[补充]` **`kind` 是核心 §4.2.1 的三键之外唯一新增的键**：核心 §4.2.3 要求新实例的 `source` 记"由转化产生"而非"开盒"，而三键在非开盒来源上全是空值，无法表达来源类型。它同时是 `serial` 分配（§5.6）与来源清单（§5.8）的判定依据。**`kind` 的取值域是本系统钉死的六个值**（`gacha` / `convert` / `refund` / `mail` / `migrate` / `unlock`）；**未知 `kind` 一律拒绝 `grant`**（返回 `null`，状态不变），否则 §5.8 的来源清单与 07 的归因都会出现无主条目。
> `[补充]` **`source` 是开放字典，不是固定四键结构；且 `kind` 与 `location` 是两件事**：`kind` 必填，其余键**按来源类型附加**（`gacha` 附三键，`convert` 附源类别 / 损耗率等由 06 定义，`mail` / `migrate` 只需 `kind`）——**读取方必须先判 `kind` 再取键**，不得假设四键齐全（不齐时给 `&"" / 0 / -1` 等中性默认值，见上表"出现条件"列），这条也让"以后给某类来源加一个键"不必改存档 schema。`kind` 是**历史事实**（来源），`location` 是**当前状态**（位置）：**产出溢出只写 `location = mail`，绝不改写 `kind`**（§5.8 / §5.10），之后的领取同样只改 `location`。
> `[补充]` **`acquired_at` 是秒级整数**（照核心 §4.2.1），一次批量兑现会产出同一秒的多个实例——先后由 §5.5 的第二打破键决定。**`instance_id` 由 `grant` 生成，不由调用方传入**；仅在**重放**（存档重放 / 日志补发）时经可选第三参传入同一个 id 以命中幂等（§4.3）。**幂等键不写进 `source`**——它是身份不是溯源，塞进去会让存档里出现两份 id（+38 B/实例）。

### 4.3 `ItemService`（`res://autoload/item_service.gd`，唯一写入方）

```gdscript
extends Node

var warehouse_capacity: int = 1000          # 仓库容量（抽象单位；数值归 D16 / §11 M7）[持久]
var instances: Array[ItemInstance] = []     # 唯一事实来源：现存实例（顺序 = 入库顺序；**含邮件实例**）
var count_index: Dictionary = {}            # [派生缓存] "<category>:<quality>" -> int（**只含仓库实例**）
var warehouse_used: int = 0                 # [派生缓存] Σ(仓库内实例的 size)；与 count_index 同源维护
var serial_counters: Dictionary = {}        # [持久] item_id -> 已发放的最大 serial（只增不减）
var total_granted: int = 0                  # 累计入库实例数（幂等命中不计入；**含进邮件的实例**）
var total_consumed: int = 0                 # 累计销毁实例数
# 唯一入库入口：1 次 grant = 1 个实例（没有 amount 参数）；**内部决定落位**（§5.10）
func grant(item_id: StringName, source: Dictionary = {}, instance_id: String = "", overflow: StringName = &"") -> ItemInstance: ...
func consume(instance_ids: Array[String], tag: StringName = &"unknown") -> Dictionary: ...   # 唯一出库入口：全有或全无（原子）；tag ∈ fuel / engine / convert（&"unknown" 与保留值 &"discard" 一律 → &"bad_tag"）
func consume_by_filter(category: StringName, quality_floor: int, n: int) -> Array[String]: ...   # 按 §5.5 顺序挑选并销毁（只在仓库实例内挑）
func transact(ops: Array[Dictionary]) -> Dictionary: ...   # 单次事务原语（§5.11）；op ∈ grant / consume / discard；替换与转化必须走它
func count(category: StringName, quality: int, location: StringName = &"warehouse") -> int: ...   # 派生 + 缓存（§4.4）；默认只数仓库
func warehouse_usage() -> Dictionary: ...        # { used, capacity, ratio }（§5.9）
func mail_instances() -> Array[ItemInstance]: ...# 邮件位置的实例，按 acquired_at 升序（§5.5 同序）
func claim(instance_ids: Array[String]) -> Dictionary: ...    # 领取：**只改 location**（§5.10）
func claim_all() -> Dictionary: ...              # 一键领取：仓库有空位时尽可能多领
func discard(instance_ids: Array[String]) -> Dictionary: ...  # 主动丢弃（R-M13）：只作用于仓库实例；出口归因单列 &"discard"
func query(category: StringName, quality_floor: int) -> Array[String]: ...   # 只读，只含仓库实例
func resolve_item_id(category: StringName, quality: int) -> StringName: ...  # 反查（唯一性见 §5.12）
func find_unstocked_items(series_id: StringName) -> Array[StringName]: ...   # 缺口清单（§8）
func snapshot() -> Array[ItemInstance]: ...          # 供 03/07/08 只读消费
func rebuild_count_index() -> Dictionary: ...        # 自愈 / 对账（§4.4、§10.2）
```

**行为规格（逐条钉子）：**

- **`grant`**：正常路径 → 生成 UUIDv4 → 写 `serial`（§5.6）→ 追加实例 → **按 `overflow` 决定落位**（§5.10）：落仓库则 `count_index[key] += 1` 且 `warehouse_used += size`，落邮件则两者都不动，**被拒则整个 `grant` 失败**（返回 `null`、不创建实例、状态完全不变）→ `total_granted += 1`（**成功入库与成功入邮件都计入**）。返回**已带 `location` 的实例**——调用方读 `instance.location` 即知去向，**不需要、也不允许**自己算空间。`instance_id` 非空且**已存在** → **幂等命中**：不新建、不改任何计数器、**不改 `location`**，返回现存实例。`item_id` 未注册、`source.kind` 不在 §4.2 的六值域内、**或 `overflow` 越权放宽**（主动操作声明 `&"mail"`）→ 返回 `null`，状态完全不变。**裸 `grant` 的失败原因不外传**（上述失败与"空间被拒"都只是 `null`）：需要区分"空间被拒"与"配置错误"的调用方**一律经 `transact`**（`reason == &"no_space"` / `&"bad_op"`，§5.11）。
- **`discard`**（R-M13，裁决 16）：与 `consume` **共用同一实现与同一原子性**（全有或全无、只作用于仓库实例），但**不产生任何产出**且**不计入三个出口标签**——单列 `&"discard"`，**07 的出口归因必须排除它**（否则 ρ 的出口账被污染）；计入 `total_consumed`，守恒式因此仍成立。
- **`transact`**（§5.11）：整批 `ops` 要么全部生效、要么完全不生效；失败时 `instances` / `count_index` / `warehouse_used` / 三个计数器**逐项回到事务前**。**替换与转化必须走它**，不得拼多次调用。
- **`consume`**：按实例销毁，**全有或全无**。返回 `{ ok: bool, consumed: Array[String], reason: StringName }`（`[补充]` GDScript 无 `Result` 类型，用 `Dictionary`；`reason ∈ &"" / &"missing_instance" / &"duplicate_id" / &"not_in_warehouse" / &"bad_tag" / &"no_space"`——后两个是**保留值**：`consume` / `discard` **不检查空间**、永远不会返回 `&"no_space"`（列入只为让出库族接口共用一套原因码，调用方不必按接口分支），而 `&"bad_tag"` 会在 `tag` 缺失或越域时**立刻**返回）。任一 id 不存在、入参内**重复出现同一个 id**、**或任一 id 的 `location != warehouse`** → `ok == false`，`instances` / `count_index` / `warehouse_used` / 两个计数器**完全不变**。空列表是合法 no-op。**`consume` 不检查空间**（只消耗不产出，核心 §4.7 第 2 条）。
- **`consume_by_filter` / `query`**：**只在仓库实例内**挑选（邮件实例不进合格集）；随后按 §5.5 顺序取前 `n` 个原子销毁，返回被销毁的 `instance_id` 列表。`n <= 0` 合法 no-op；**`n > 合格实例数` → 返回 `[]` 且状态不变**，调用方以 `result.size() == n` 判定成功。只读接口不改变任何状态。
- **`count` / `claim` / `claim_all`**：`count` **默认只数仓库**（`location == &"warehouse"`），要数邮件必须**显式传参** `count(c, q, &"mail")`——**不做隐式合并**（核心 §4.7 第 1 条）。`claim` / `claim_all` **只改 `location`**——不创建实例、不改 `instance_id` / `serial` / `source`、不重跑幂等判定、不推进 `serial_counters`；同时把 `count_index` 与 `warehouse_used` 加上（§5.10）。
- **`resolve_item_id`**：`(category, quality)` → `item_id` 的**反查**，未注册组合返回 `&""`；它是 04/05/06 唯一被允许用来取 `item_id` 的途径（§5.12）。**`find_unstocked_items` 是"当前仓库内无持有"口径**（§8），**不用于** 01 的 ×1.5 加权（那个用收藏口径 `collected`）。

**铁律：没有任何其它系统可以直接改 `instances`、`count_index`、`warehouse_used` 或 `serial_counters`。** 与 `PoolService` 对池子状态的独占同级（`README.md` §3.2）。

### 4.4 `count` 派生索引（缓存结构、失效时机、为什么不能逐帧遍历）

```
count_index / warehouse_used : int   # 两个派生缓存（可由实例列表完全重建）：前者按 "<category>:<quality>" 只计**仓库实例**，后者 = Σ(仓库内实例的 size)
写入点        : 只有这几处 —— grant()（**落仓库才 +**）/ consume*_() / discard() / claim*_()（**领取才 +**）/ transact() 内部
失效与自愈    : 实例增删**或位置变更**的**同一次调用内**完成更新（不存在"下一帧才更新"）；某键降到 0 → 删除该键（R-M5，不保留 0 条目）；rebuild_count_index() 全量重算**两个派生值**（正常路径不调用，供 §10.2 对账与调试）
```

**为什么不能逐帧遍历实例列表：** ①查询是**帧级高频**（六面板 + 试算 + 任务面板随每次输入变化都会读），而实例数可达数千（§4.6），O(n) 乘上帧率不可接受；②成本会**随存档体积增长**——存档越大越卡，玩家无法解释也无法通过配置缓解（P6 / R7 同精神）；③03 的需求匹配是**最大流判定**，输入是聚合后的持有量而非实例列表，把全量遍历塞进图构建会让判定耗时随实例数增长。核心 §4.2.2 的"必须缓存"因此落地为**增量维护保性能 + 全量重算保正确性**两条路径，两者结果必须**逐项相等**（§10.2 的一致性红线）。④v0.9 的 `warehouse_used` 与 `count_index` 是**同一类派生缓存**：仓库占比是面板常驻显示，全量求和同样不能逐帧做；两者必须由**同一次写入**一起更新，否则会出现"数量对了但占比不对"的不可解释状态（而占比正是本版唯一的容量反馈通道）。

### 4.5 UUIDv4 生成器（Godot 无内置 UUID，必须自己实现）

```gdscript
# res://data/defs/uuid.gd —— 静态工具，不依赖节点，可在无头模式跑单测
class_name Uuid
extends RefCounted
static var _crypto := Crypto.new()               # Crypto 是 RefCounted，持有一个静态实例即可

static func v4() -> String:
	var b: PackedByteArray = _crypto.generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40        # version = 4（第 7 字节高 4 位 = 0100）
	b[8] = (b[8] & 0x3F) | 0x80        # variant = RFC 4122（第 9 字节高 2 位 = 10）
	var h := b.hex_encode()            # 32 个小写十六进制字符
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4),
		h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]
```

**实现要点：**

1. **随机源必须是 `Crypto`（OS CSPRNG）**：`Crypto.generate_random_bytes(16)`；不要每次 `new()`。**两位必须手工设置**，否则字节流只是"看起来像 UUID"：`version` 位（第 7 字节高 4 位 = `0x4`）与 `variant` 位（第 9 字节高 2 位 = `0b10`）。
2. **格式 8-4-4-4-12、32 位小写十六进制**；比较一律按小写字符串——大小写不统一会让同一个 id 出现两种写法，幂等键当场失效。
3. **禁止 `ResourceUID.create_id()`**（返回 int64 的 `uid://` 串，**不是 UUID**，核心 §4.2.2）；**禁止 `randi()` / `RandomNumberGenerator` / 任何可复现种子流**——池子与保底用的是"给定 seed 完全可复现"的随机流，实例身份必须与它**无关**，否则同一次重放会产出同一个 UUID，幂等键立刻失去意义（§10.1 第 3 条）。生成开销只落在 `grant` 路径（非热路径）。

### 4.6 存档形态与体积代价（交给 10）

```gdscript
func to_save_dict() -> Dictionary:
	return {
		"instances": instances.map(func(i): return i.to_dict()), "warehouse_capacity": warehouse_capacity,   # 现存实例（**仓库 + 邮件都在**）+ v0.9 容量必须持久（D15 若可成长则更必须）
		"serial_counters": serial_counters,                        # 编号计数器必须持久（§5.6）
		"total_granted": total_granted, "total_consumed": total_consumed,
	}
```

- **只持久化现存实例**：已销毁的实例**不留历史**（`README.md` §3 铁律 9）。审计由**开箱日志**承担——它已记录 `{ seed, series_id, pool_snapshot, item_id, quality, is_void }`（核心 §14.2 铁律 7）。**邮件实例属于"现存"**：`location` 是实例字段，随实例一起入档（否则"邮件无上限、不过期"当场失效）。
- **三个派生值都不入档**：`count_index`、`warehouse_used`（载入后由实例列表重建；存它们等于把派生值偷偷变成第二个事实来源，违反核心 §14.2 铁律 8）；**`serial_counters` 与 `warehouse_capacity` 必须入档**（前者是无法从现存实例推导的历史计数，§5.6；后者是可被里程碑改变的配置性状态，核心 D15）。
- **往返字节级稳定**：`to_dict()` 键序固定、实例顺序原样保留、取键顺序必须显式写死（Godot 的 `Dictionary` 保持插入序，但不得依赖它"碰巧"一致）。持久化文件与格式**归 10**，本系统只提供上述字典。

| 体积项 | 量级 |
|---|---|
| 单实例 JSON（`instance_id` 36 字符 + `item_id` + `acquired_at` + `serial` + `source` 四键） | **约 120 B**（上游口径，**未含 v0.9 的 `location`**），其中 **`source` 是大头** |
| 5000 实例 / 10000 实例 | **约 600 KB** / 约 1.2 MB |

> **该数字是估算，切片必须实测**（§11 M6）：按朴素 JSON（含键名与 `source` 四键）逐字段相加会落在 150–200 B/实例区间，因此"是否折叠 `source` 短键、是否换二进制/压缩格式"必须用实测数据裁决。**v0.9 的 `location` 是新增的固定成本（约 +20 B/实例），上游的 120 B 口径未含它**——M6 实测必须一并计入（不改变估算量级，故 §11 M6 只追加口径、不改数字）。

---

## 5. 规则与公式

### 5.1 两维定义

| 维度 | 取值范围 | 切片推荐 | 作用 |
|---|---|---|---|
| `category` 类别 | 可配置的 `StringName` 清单 | **2 个：`stardust` 星尘 / `crystal` 晶核** | 决定能满足哪类任务需求（见 `03-task.md`） |
| `quality` **物品品质** | 1–5 序数 | **3 档：1 普通 / 2 精良 / 3 稀有** | 决定任务贡献度、作为素材的强度与演出分级（见 04/05）。**指物品品质，与套系品质无关** |

**为什么是这 2 个类别（R5 的直接回答）：** ①1 类时任务需求退化成标量，"需求结构"这条后期摩擦来源（核心 §10.3）失效，2 类即让需求向量真实存在；②星尘 / 晶核的定位差异在**需求侧**——前期常规任务主吃星尘，里程碑与后期任务开始要求晶核（见 03 / 10）；③**2 × 3 = 6 个 `count_index` 键可心算**，玩家一眼看完全部持有量（P6），**实例数不进入这个等式**（§1 第 8 条）。

### 5.2 物品价值 `v_i` 的定义（口径归本系统，计算归 07）

`v_i = ItemDef.value(item_i)`，即**池中第 i 个物品一次产出的价值**，也是本系统交给 07 的唯一价值口径。

- **一次产出恒为 1 个该物品**（v0.8：该次入库**新增 1 个实例**），因此 `v_i` 不含任何数量因子。07 用它计算 `M̄ = Σ(pᵢ × vᵢ) × 池子修正`（核心 §2.3）——**本系统不参与该求和，也不做任何池子修正**（见 `07-economy-rho.md`）。
- 默认层"最好的物品"即 `v_i` 最大的可产出物品（核心 §6.1），该判定由 07 产出，本系统只保证 `value` 可读；本系统还对 `v` 的可心算性负责——**推荐全部物品的 `value` 严格等于其品质阶梯值**，与类别无关，玩家只需记住 3 个数字而不是 6 个（R5）。

### 5.3 持有模型：实例列表（v0.8）

| 规则 | 内容 |
|---|---|
| **R-M1 实例即持有** | 持有 = `instances` 列表里的实例。**同一 `item_id` 的多个实例是互不相同的个体，永不合并。** 实例的身份只有 `instance_id`。**v0.9 补充：可用持有 = 其中 `location == warehouse` 的实例**——邮件实例**仍是玩家的实例，但不是可用持有**（§5.9 / §5.10）。 |
| **R-M2 索引键数由维度决定** | `count_index` 键数 ≤ 类别数 × 品质数（切片 = 6）。它是两个维度相乘的自然结果，**不是容量上限**，且**与实例数无关**（P7 同精神）。 |
| **R-M5 归零** | 某键的 `count` 降到 0 → 从 `count_index` 删除该键（不保留 0 条目）。玩家可见行为与 v0.7 一致："没有这种物品时，面板上就没有这个条目"。**v0.9：把最后一个该物品实例"领取"进仓库只是位置变更，不影响本规则**（键的增删只由 `count` 是否为 0 决定）。 |

> **R-M3（数量上限）与 R-M4（溢出缓冲 `overflow_buffer`）仍留空**（v0.6 已删），以保持其它文档对 R-M1 / R-M5–R-M10 的引用稳定。**但 v0.9 的仓库容量既不是 R-M3 也不是 R-M4 的复活**：R-M3 是"持有**数量**上限"——**实例数仍然无上限**，被动产出超出的实例照样被创建、只是落在邮件；R-M4 是"超出上限就被丢弃 / 缓冲"的容器——**邮件永不丢弃、且不计入持有**。二者是**位置容量与位置归属**，不改变"**被动产出必被创建**"这条结构事实（**主动操作**放不下时**整个操作被拒**、连产出都不产生，规则见 R-M14 / §5.10）。
> **为什么"堆叠"在结构上不可能存在**：堆叠的前提是"同种物品可以合并成一个计数"；实例模型下**每个物品都是个体**，`grant` 只会**追加**一个实例，**没有"往同一个堆上加一个"的对象**。
> **P5 的兜底论证（v0.9 换掉，并按裁决 17 分层）**：**被动产出**（开盒 / 迁移 / 解锁）的兜底是"**装不下就进邮件 ⇒ 产出永不丢失**"；**主动操作**（转化 / 拆卸返还）的兜底是"**装不下就拒绝整个操作 ⇒ 既没丢也没少**"（源实例不销毁）。两条合起来覆盖**所有**产出路径，**没有任何"装不下就丢弃"的分支**；v0.7 的"无上限 ⇒ 不可能丢"依赖容量不存在，已失效（核心 §16.4 / §14.2 铁律 9）。

### 5.4 重复物品 → 新增实例（P5）

- **开出一个物品 = 新增 1 个实例**（`grant` 每次只创建 1 个）。**同一个 `item_id` 开出两次 = 两个实例**，落在同一个 `count_index` 键上，`count == 2`；**两个不同但 `(category, quality)` 相同的物品**同样计入同一个键——**聚合层不区分具体物品，实例层各自持有身份**，物品级收集归图鉴（见 10）。
- **一个实例只能被销毁一次**：`consume` 后该 `instance_id` 从列表消失，再次传入即为 `missing_instance`（§10.3）。重复物品的第二个价值出口是**引擎原料**（核心 §7 P5），规则见 04 / 05。
- **`count` 不是存下来的 2，是数出来的 2。** 任何把 `count` 当字段维护的实现都是 v0.8 的红线违例（核心 §14.2 铁律 8）。

### 5.5 挑选与销毁顺序（上游已裁决）

`consume_by_filter(category, quality_floor, n)` 与 `query(category, quality_floor)` 的挑选顺序：

```
合格集 = { 实例 i | i.category == category ∧ i.quality >= quality_floor }；排序键 = ( quality 升序 , acquired_at 升序 , instance_id 字典序 )
```

1. **最低合格品质优先**——把高品质留给引擎（核心 §4.2.3 明文，与 `03-task.md` §5.4 同一精神）；**同品质内按 `acquired_at` 升序**（先入先出，核心 §4.2.3 明文）。
2. `[补充]` **同一秒并列时按 `instance_id` 字典序**：`acquired_at` 是 Unix **秒**，一次批量兑现会产出同一秒的多个实例，必须有一条确定的打破规则，否则挑选顺序不可复现、§10.3 无法断言。选 `instance_id` 而非列表下标，是因为**列表下标会随存档载入顺序变化，而 UUID 是稳定身份**。
3. `consume(instance_ids)` **不做挑选**（实例由调用方给定），但同一次调用内不得重复（§4.3）。**边界声明**：§5.5 只规定"给定类别 + 品质下限 + 数量时挑哪几个实例"（即 `query` / `consume_by_filter` 的返回顺序）；跨需求项的分配（谁满足哪一条需求，核心 §5.2 的最大流）**归 03**，02 的职责是"给我一组实例 id，我立刻原子销毁"。

### 5.6 `serial` 分配规则（上游已裁决）

```
serial = 0            → 非开盒来源（转化 / 拆除返还 / 解锁发放）；serial = N (N >= 1) → 该玩家开出的第 N 个此物品
serial_counters       → item_id -> 已发放的最大 N：只增不减、持久化、绝不从现存实例重算
```

- **只在开盒产出时分配**（`source.kind == &"gacha"`）：`serial_counters[item_id] += 1`，新实例取该值。**转化与拆卸返还产生的新实例 `serial = 0`**，且**不推进** `serial_counters`。
- **计数器必须持久、只增不减**：若改从现存实例的 `max(serial)` 推导，销毁编号最大的实例后同一个编号会被**复用**，与开箱日志对不上，"收藏编号"的叙事当场断裂；**编号不复用、不回收**——即使某个 `item_id` 的实例全部被销毁，计数器也不归零，下一次开出继续 `N + 1`。`[补充]` 核心只规定了"第 N 个此物品"，本节把"**计数器持久 / 只增不减 / 非开盒来源不占号**"三条钉死；否则"第 N 个"按现存实例数、按开盒次数还是按全部来源计数是完全不确定的。`serial` 是**该玩家**的编号（纯单人前提），不表示全局稀有度，也不是价值或强度的输入。

### 5.7 两个出口在物品侧的表现

| 出口 | 核心 §3 | 物品侧的状态变化 | 谁决定量与规则 |
|---|---|---|---|
| **燃料 `fuel`** | 交付给任务 | `consume(instance_ids, &"fuel")` → **实例被销毁**（列表移除、该键派生 `count` −1）；请求方（03）再结算奖励 | 需求匹配与跨需求项分配见 `03-task.md` |
| **引擎 `engine`** | 装配装置 / 镶嵌模块 | `consume(instance_ids, &"engine")` → **实例被永久消灭**；位次占用不在本系统记录 | 素材量与规则见 04 / 05 |
| **转化 `convert`** | 类别间转换 | `consume(..., &"convert")` 销毁源实例；产出另一类别走 `grant(item_id, { kind = &"convert" })` → **新实例：新 UUID、`serial = 0`** | 见 `06-conversion.md` |

**补充约束（本系统硬规则）：**

- **R-M6 原子销毁**：`consume` 要么全量成功、要么完全不改状态，失败返回 `ok == false`。**禁止部分销毁。** `[补充]` 理由：03 的交付与 04/05 的装配都是单一事务，部分销毁会产生"半个装置"这种不可解释状态，并使 §10.5 的守恒式无法对账。**v0.9 追加**：**邮件实例不可被销毁**（`reason == &"not_in_warehouse"`，同样全不变）——这是核心 §4.7 第 1 条边界在出库口的落地；"消耗类操作不检查空间"（第 2 条）说的正是"`consume` 没有容量分支"，**与"是否在仓库"是两回事**。
- **R-M7 不存在负持有**：`count` 由实例列表数出，**结构上不可能为负**（v0.7 的"不得 `count < 0`"由此天然满足，不再需要 `can_afford`）。前置校验改为**实例存在性 + 入参不重复 + 位于仓库**。
- **R-M8 拆除返还**：核心 D8 的"拆除返还 50%"由 04/05 判定数量，本系统只当作一次 `grant(item_id, { kind = &"refund" })` 执行（**新实例、新 UUID、`serial = 0`**），不重算返还率。**v0.9：返还是"主动操作"的一部分**——放不下时**整个拆卸 / 替换被拒**（`refund` → `overflow = &"reject"`，R-M14）：源实例不销毁、也不产生返还实例，**绝不"只给一半"**。
- **R-M9 出口标签记账**：`consume` 记录 `tag`，**标签域 = `fuel` / `engine` / `convert` / `discard`（四个，逐字）**：前三者由调用方显式传，**`&"discard"` 是保留值、只由 `discard()` 入口写入**（`consume(ids, &"discard")` 被判 `&"bad_tag"`——丢弃仍只能走丢弃入口，§5.10 R-M13）。`[补充]` 核心给出的签名没有 tag 参数，但 P2 要求逐项归因、07 需要按出口读取销毁量，故补一个**默认为 `&"unknown"` 的第二参数**：默认值**只为签名兼容**保留——**任何真实调用不显式传 `tag` 即当场失败**（`ok == false`、`reason == &"bad_tag"`、状态完全不变），因此 R-M9 是**运行时不变量**，而不只是一条测试约定。**理由**：`&"unknown"` 或缺失标签会让 07 把销毁量归到三个出口之外，三份出口数字之和小于总销毁量，ρ 的归因链出现黑洞；`&"discard"` 单列则是为了让"玩家丢弃"与"设计出口"在归因里**可分**。§10.6 的静态检查同时断言"除测试外没有调用点使用默认 `tag`"。
- **R-M10 数量守恒**：任意时刻恒有 **`instances.size() == total_granted − total_consumed`**（**裁决 12：守恒式按"全部实例"，与 `location` 无关**）。注意 `Σ count(c,q,&"warehouse") + Σ count(c,q,&"mail")` 只是它的恒等展开，**不得**把带位置过滤的 `count()` 写进守恒式——那会让**位置概念污染守恒式**，也使 03/06 侧那句"仓库 Σcount == 差值"在 v0.9 下**不成立**（邮件实例也在差值里）。**幂等命中的 `grant` 不增加 `total_granted`**；**`claim` 两边都不动**（只改位置）；**`consume` 与 `discard` 都增加 `total_consumed`**（因此守恒式不变）。任何破坏该等式的路径都是 bug。
- **R-M13 主动丢弃（裁决 16）**：`discard(instance_ids)` **只作用于仓库实例**、按实例原子销毁、**不产生产出**、**不计入三个出口标签**（单列 `&"discard"`，见 §4.3）。`[补充]` **它是死局逃生阀**：仓库满 → 邮件领不出 → 任务交不了 → 拿不到新盒子 → 仓库仍然满；没有这条路径，容量在极端情况下会把玩家**锁死**（这与 R14 是同一个风险的两个面）。**丢弃不违反 P5**——P5 管"被动产出不得丢失"，丢弃是玩家**主动**行为；UI 必须二次确认（归 08）。

### 5.8 物品的来源清单（`source.kind` 的六值域，v0.9）

| 来源 | 归属 | 本系统的动作 |
|---|---|---|
| **开盲盒产出（主来源）** | 抽中的**物品本身就是入库内容**；判定见 `01-gacha.md`，演出见 `09-presentation.md` | `grant(item_id, { kind = &"gacha", series_id, box_seed, draw_index })` → **创建 1 个新实例并分配 `serial`** |
| **类别间转化产出** | `06-conversion.md` | `grant(item_id, { kind = &"convert" })` → 新实例，`serial = 0` |
| **拆除装置 / 模块返还 50%**（核心 D8） | 04 / 05 | `grant(item_id, { kind = &"refund" })` → 新实例，`serial = 0`。**v0.9：返还是"主动操作"的一部分**——放不下则**整个拆卸 / 替换被拒**（`overflow = &"reject"`，不产生实例、源实例也不销毁），**绝不"只给一半"**（R-M14） |
| **里程碑 / 套系解锁发放** | `10-progression.md` | `grant(item_id, { kind = &"unlock" })` → 新实例，`serial = 0` |
| **存档迁移产出**（v2 → v3 等，v0.9） | `10-progression.md` | `grant(item_id, { kind = &"migrate" })` → 新实例；`serial` 口径由 10 决定，本系统只按传入的 `kind` 落位。**防回归记录（已闭环）**：取值是 **`migrate`**——`10-progression.md` §10 T15 已在 v0.9 全库改用 `&"migrate"`，**旧拼写 `&"migration"` 已作废、两种拼写不得并存**；本系统按 `migrate` 实现且**未知 `kind` 一律被 `grant` 拒绝**，所以任何回退到旧拼写的改动会**当场失败**，不会静默降级 |
| **（保留值）系统补偿 / 邮件直投** | 当前无归属系统 | `grant(item_id, { kind = &"mail" })` **合法且被接受**（落位仍走 §5.10 的正常判定），但**切片内没有任何调用方**——保留该值只为让取值域完整，将来加补偿类邮件时不必扩域。**"产出溢出"不写 `kind = &"mail"`**：溢出是**落点**不是来源，由 `location` 承担（§4.2 / §5.10） |

**明确排除：任务不产出物品**——任务奖励**不含物品**（核心 §4.3：奖励为盲盒、券、位次），见 `03-task.md`。否则"交付物品 → 拿回物品"会形成自环，虚高 ρ 并使燃料出口失去代价（核心 §3.1）。

### 5.9 仓库容量与占用（v0.9）

- **R-M11 容量是抽象单位**：`warehouse_capacity`（示意 1000）**不是"格数"**，UI **只显示占比**（`used ÷ capacity`）；落地时**不得**把 `size` 渲染成"占 N 格"——那会把连续量重新讲成离散量，与 D16 的标定自由冲突。**已用 `warehouse_used = Σ（location == warehouse 的实例的 size）`**，是派生值 + 缓存（§4.4），**不入档**（§4.6）。**可容纳性判定逐件原子**：能容下这**一个**实例（`used + size <= capacity`）才算放得下——**不存在"半个实例入库"**（§10.8 第 7 条），放不下时怎么办**由 `overflow` 策略决定**（R-M14 / §5.10）。**`warehouse_usage() -> { used, capacity, ratio }`**（`ratio = float(used) / float(capacity) ∈ [0, 1]`，供 08 直接画条）：**04/05/06/08 一律只读它**，不得自己求和。`[补充]` **`warehouse_capacity` 必须 ≥ 1**（校验器强制，§5.12）：容量 0 会让**一切被动产出**直接进邮件、**一切主动操作**被拒，游戏当场不可玩——那是配置错误，不是设计选择。容量成长（核心 D15）**只能走"改 `warehouse_capacity`"这一条路**，且**不得**把已入库实例挤出仓库（那会让"持有"变成可被回溯撤销的量）。

### 5.10 邮件与产出溢出（v0.9）

> **唯一的溢出判定点：`grant` 内部**——放得下 → `warehouse`；放不下 → **按 `overflow` 策略分流**（R-M14）。**开盒 / 转化 / 拆卸返还 / 迁移一律经它**（核心 §4.7）。**全库唯一允许判断容量的地方就是这里**；别处出现容量判断即为 bug（§10.6）。**R-M12 邮件无上限、不过期**：邮件实例与仓库实例**同在一个 `instances` 列表**里（核心 §14.2 铁律 9："同一个实例列表的两个位置，不是两份数据"），只有 `location` 不同；**不设容量、不设过期**（过期会违反 P5）。

- **R-M14 溢出策略按"主动 / 被动"分流（裁决 17）**：**被动产出**（`gacha` / `migrate` / `unlock`）放不下 → **进邮件**（玩家没有主动要求这一刻，判它失败等于让"盒子开了"变成失败，违反 P5）；**主动操作**（`convert` / `refund`）放不下 → **拒绝整个操作**。理由：主动操作**销毁源实例腾出空间**，若它的产出反而进邮件，玩家就是**净损失可用持有**——转化会长出"反噬"，与"转化是燃料路径的预处理"的立意直接冲突。
- **落地：`grant` 的第四参数 `overflow`**（`&""` / `&"mail"` / `&"reject"`）：`&""`（默认）= **按 `source.kind` 推导**（`gacha` / `migrate` / `unlock` / `mail` → `mail`；`convert` / `refund` → `reject`）。**只允许收紧、不允许放宽**：被动产出可以显式声明 `reject`，**主动操作声明 `mail` 会被 `grant` 拒绝**（返回 `null`）——裁决 17 由此成为**结构上不可绕过**的红线，而不是"记得这么写"的约定。拒绝时**状态完全不变**（不创建实例，`count_index` / `warehouse_used` / 计数器都不动）；在 `transact` 里则是 `ok == false`、`reason == &"no_space"`、**逐项回到事务前**，**源实例因此不会被销毁**——这才是"拒绝整个操作"的完整含义。

- **可用持有 = 仅仓库**：`count()` 默认只数仓库；邮件实例**不可**交付 / 装配 / 镶嵌 / 转化（`consume` → `&"not_in_warehouse"`，R-M6），`query` / `consume_by_filter` 也看不见它们。要数邮件必须**显式** `count(c, q, &"mail")`——**不做隐式合并**（核心 §4.7 第 1 条）。
- **领取只改 `location`**（`claim(ids)` / `claim_all()`）：不创建实例、不改 `instance_id` / `serial` / `source` / `acquired_at`、不重跑幂等判定、不推进 `serial_counters`；同时把 `count_index` 与 `warehouse_used` 加上（核心 §14.2 铁律 9）。
- **裁决——「领取时空间不足」= 部分成功（按 `acquired_at` 升序尽可能多领），不是整体拒绝**：返回 `{ ok, claimed, remaining, reason }`，`ok == (claimed.size() == ids.size())`（与 `consume_by_filter` 的 `size == n` 约定同构）；逐件判定，**一件都装不下时 `claimed == []`、`reason == &"no_space"`**（同一枚空间原因码，见 §5.11）；同秒并列按 `instance_id` 字典序（§5.5）。`claim_all()` 对全部邮件实例执行同一过程，**永不失败**（`ok == remaining.is_empty()`）。**理由三条**：①**邮件里的东西已经是玩家的**——实例在产出瞬间就已创建并拿到 UUID 与 `serial`（核心 §4.7），领取只是搬家；整体拒绝等于"因为没地方放，所以什么都不给你"，把一个**空间问题变成惩罚**，而本版加容量的目的是"囤积占地方"，不是"没收"；②**整体拒绝会把容量不足放大成死锁式体验**——仓库只差 3 空间、邮件里最老的 5 件各占 1 时，整体拒绝会逼玩家先去交付/装配腾出整块空间，于是 R14（不敢开盒）被自己放大；③**与 `grant` 共用同一套"逐件原子容纳"规则**，全库只有一种容纳语义，测试只需验一条（§10.8）。**代价（诚实记录）**：部分领取让"领了多少"必须读返回值——**UI 必须回报"已领取 M / 还剩 K 件"**（归 08），且 `claim_all()` **不得**表述为"一键领完"。**`reason` 取值域**：`&""` / `&"no_space"`（**与 §5.11 同一枚空间原因码**，此处含义＝"一件都装不下"）/ `&"missing_instance"` / `&"duplicate_id"` / `&"not_in_mail"`（对已在仓库的实例重复领取＝no-op 且计入 `claimed`：领取是幂等的，它只把 `location` 写成同一个值）。

### 5.11 事务原语 `transact(ops)`（v0.9，上游裁决）

```gdscript
ops = [ { op = &"consume", instance_ids = ["…"], tag = &"convert" }, { op = &"grant", item_id = &"crystal_q2", source = { kind = &"convert" } } ]
transact(ops) -> { ok, reason, consumed, granted, discarded, mailed: Array[String] }
# ── op 键集（**逐字**；出现其它键、或缺少必填键 → { ok = false, reason = &"bad_op" }）──────────────
#   grant   : { op, item_id, source{ kind, … }, [overflow], [instance_id] }
#             ⚠ **没有 `count`**：一次 grant 只创建 1 个实例 → 要造 k 个目标实例就写 **k 条 grant op**
#             ⚠ **没有 `serial`**：serial 由 §5.6 内部按 kind 赋值，调用方不得传
#   consume : { op, instance_ids, tag }    # tag ∈ fuel / engine / convert（&"discard" 是保留值，只由 discard 入口写）
#   discard : { op, instance_ids }         # 无 tag；归因单列 &"discard"（R-M13）
# ── mailed：**只可能来自 `overflow = &"mail"`（被动产出）的 grant op**；若事务内全是主动操作的 grant
#    （convert / refund），则 **`mailed == []`** —— 放不下就是**整个事务失败**，绝不产生邮件实例（06 的 T14 断言此事）
```

- **规格：整批 `ops` 要么全部生效、要么完全不生效。** 失败时 `instances` / `count_index` / `warehouse_used` / 三个计数器**逐项回到事务前**（§10.8 第 5 条按逐项断言验收，不接受"看起来没变"）。**落位判定在事务内同样逐件进行，并按 `ops` 的书写顺序消费容量**（先创建的先占地方）——这条顺序**写死**，因此"事务里哪个 `grant` 进了邮件"完全可复现、可断言；**主动操作的产出放不下则整个事务被拒**（`overflow = &"reject"` 在事务内同样生效，`reason == &"no_space"`）。**边界（裁决 13）：`transact` 的原子性只覆盖物品侧**——`ItemService` 自己的 `instances` / `count_index` / `warehouse_used` / 三个计数器。它**不**覆盖 Box 发放（01）、任务进度（03）、解锁（10）、池子状态（05）：跨系统一致性靠**各系统自己的幂等键 + 重放恢复**，**不承诺（也不需要）分布式事务**（纯单人）。因此 03 在"交付物品 + 发盒"这类跨系统流程里**不得**假设 `transact` 能回滚奖励发放——顺序与幂等归 03。
- **为什么必须有：单次 `consume` 原子 ≠ 组合原子。** 转化的"销毁源实例 + 创建新实例"、04/05 的"替换（拆旧装新）"都是**一个逻辑动作**；用"多次销毁 + 多次创建"拼起来时，中间任一步失败就会留下**半个装置 / 凭空消失的物品**，而 `consume` 自身的原子性对此毫无帮助（它只保证"这一次销毁全有或全无"）。**因此：替换与转化 = 一次 `transact` 调用，不得拼接。** `[补充]` 核心未规定该接口，但"每个写入入口原子"推不出"组合原子"——这是落地必需的原语。
- **`transact` 只接受 `grant` / `consume` / `discard` 三类 op**：`claim` 不进事务（它只改位置、不改数量、不参与守恒式，且天然不失败）；**`discard` 进事务**是因为"先丢弃腾出空间、再转化"是一个完整的玩家意图（与 grant/consume 的组合同语义）；未知 `op` / 缺必填键 / 多出键 → `ok == false`、`reason == &"bad_op"`、状态完全不变。**`reason` 取值域（逐字给出，供 03/04/05/06/07 对接）**：`&""`（成功）/ `&"bad_op"`（op 类型或键集非法）/ `&"bad_tag"`（`tag` 不在 §5.7 R-M9 的域内）/ `&"missing_instance"` / `&"duplicate_id"` / `&"not_in_warehouse"` / **`&"no_space"`（裁决 17 的落点：主动操作产出放不下，不产生任何实例）**。

### 5.12 配置校验器（加载时强制，v0.9 新增两条）

| # | 规则 | 违反时 | 理由 |
|---|---|---|---|
| **V1** | **`(category, quality) → item_id` 唯一**：一个两维键**只允许对应一个 `item_id`** | 加载失败，报出冲突的两个 `item_id` | 派生索引的键就是 `(category, quality)`（§4.4）：若两个 `item_id` 共享一个键，则 `count` 的含义不确定、`resolve_item_id` 的反查结果不确定，而 04/05/06 都要靠反查取 `item_id` |
| **V2** | **`ItemDef.size > 0`** | 加载失败 | `size == 0` 的物品等价于"不占地方"，仓库容量对这类物品**完全失效**（`used` 不增长）——那是容量机制上的一个漏洞；负值更会让 `warehouse_used` 反向增长。**校验器只拦非法配置、不改任何数值**；`warehouse_capacity >= 1` 同由它强制（理由见 §5.9） |

---

## 6. 参数表（推荐值 + 调参旋钮标记）

| 参数 | 位置 | 推荐值 | 说明 |
|---|---|---|---|
| `category` 数量 🔧 | 内容配置 / `ItemCategoryDef` | **2**（切片：`stardust` 星尘 / `crystal` 晶核） | 每加一类，`count_index` 键数与心算负担同时上升（R5）；加类属内容释放，见 10 |
| `quality` **物品品质**档数 🔧 | 内容配置 | **3**（切片：1 普通 / 2 精良 / 3 稀有） | 指**物品品质**（1–5 序数，与套系品质无关）；终局上限 5；与 D13 解耦，见 §11 |
| `value` 阶梯 🔧 | `ItemDef` | **1 / 3 / 9**（几何 ×3） | **与类别无关**。3 个数字可心算；改这里等于整体缩放 `M̄`，是 ρ 的主力旋钮之一（实际影响由 07 结算） |
| 实例数上限 | 结构 | **无上限** | `grant` 除"`item_id` 未注册 / `kind` 非法 / **主动操作空间被拒**"外永远成功；**v0.9 的容量是"位置容量"、不是"数量上限"**（§5.3）——P5 由"被动产出进邮件 / 主动操作被拒"**两层**满足（R-M14） |
| **仓库容量 `warehouse_capacity`** 🔧 | `ItemService`（配置） | **1000**（**抽象单位**，示意） | 核心 D16：需与任务需求向量、开箱产出量一起标定，**切片实测**（§11 M7）；UI 只显示**占比**；必须 ≥ 1（§5.9） |
| **`ItemDef.size`** 🔧 | `ItemDef` | 按品质 **1 / 2 / 5 / 10**（示意） | 核心 D16 的示意值，与容量一并标定（§11 M7）；**同种物品大小相同**、必须 > 0（§5.12 V2） |
| 邮件上限 / 过期 | 结构 | **无上限、不过期** | 核心 §4.7 明文；过期会违反 P5，故**不是**可调参数 |
| 领取策略 | 常量 | **按 `acquired_at` 升序尽可能多领**（部分成功） | §5.10 的裁决；若上游改判为"整体拒绝"，只需改 `claim` 一处，`grant`、守恒式与 §10.8 其余各条均不受影响 |
| **溢出策略（`overflow`）与主动丢弃（`discard`）** | 常量 / 结构 | **被动产出 → `mail`；主动操作 → `reject`**；丢弃**始终可用**（仅对仓库实例） | 都不是调参旋钮：`overflow` 只允许**收紧**（主动操作声明 `mail` 会被 `grant` 拒绝，裁决 17 / §5.10 R-M14）；`discard` 是死局逃生阀（裁决 16 / R-M13），不产出、无出口标签、归因单列 `&"discard"`，UI 二次确认（归 08） |
| `count_index` 键数 | 由维度决定 | **6**（切片 2 × 3） | **不可调，也不是容量上限**；与实例数无关（R-M2） |
| `instance_id` 形态 | 常量 | **UUIDv4**：36 字符小写、version 4、variant RFC 4122 | **不可配置**：格式一旦入档，改动即破坏幂等键与存档（§4.5） |
| `serial` 起点 | 常量 | **1**（`0` 保留给非开盒来源） | 编号不复用；计数器持久、只增不减（§5.6） |
| 物品品质色（`quality`） | UI 主题 | 1 `#B9C0C9` 灰白 / 2 `#4FA3E3` 青蓝 / 3 `#A66CF2` 紫 | 见 §9；指**物品品质**；4/5 档预留（数量徽标格式同为 UI 常量：`1–999` 直显，`≥1000` 转 `1.2k`） |

---

## 7. 流程 / 状态机

### 7.1 实例生命周期

**状态有三种：`warehouse`（可用持有）、`mail`（装不下，但仍是玩家的实例）、已销毁。**

```
[不存在] ──grant()──▶ [warehouse] ──(仓库满时) grant()──▶ [mail]     （同一 item_id 也是两个独立实例）
                          ▲                                  │
                          └──────────claim()（只改 location）─┘
[warehouse] ──consume(ids, tag)──▶ 已销毁   ；[mail] 不可销毁（→ &"not_in_warehouse"，R-M6）
```

**没有"堆叠"这个对象，也没有"因装不下而消失"这个结局**：**被动产出**装不下**一定**变成一个 `mail` 实例（进邮件，P5 的新兜底，§5.3），**主动操作**装不下则**整个操作被拒**、连源实例都不动（R-M14）；销毁 = 从 `instances` 移除，`count_index` 由列表数出，不存在"删除计数条目"这个动作；**主动丢弃（`discard`）是玩家自己开的逃生阀**（R-M13）。

### 7.2 一次开盒入库（本系统视角）

```
01 结算 roll() → 物品（恰 1 个；void 结果不调用本系统） → 09 演出（本系统不参与）
   → ItemService.grant(item.item_id, { kind = &"gacha", series_id, box_seed, draw_index })   # 被动产出 → overflow 推导为 mail（R-M14）
       ├─ item_id 未注册 / kind 不在六值域 → 返回 null，状态完全不变
       ├─ instance_id 已存在 → 幂等命中：返回现存实例，不新建、不计数、**不改 location**
       └─ 正常 → 生成 UUIDv4 → serial = ++serial_counters[item_id] → 追加实例 → 逐件判定落位
                 ├─ used + size <= capacity → location = warehouse → count_index[key] += 1、warehouse_used += size
                 └─ 否则 → location = mail → **两个派生值都不动（不进 count）**；total_granted += 1（**两种落点都计入**，§5.3 守恒式）
   → 通知 08：落仓库 → 高亮该聚合条目；**开盒前的空间预告只能是下界式**（见 §9 文案规格；**不得**做件数预测）
     `[补充]` **结算后的精确件数才允许出现**：落点为 mail 的实例由本次兑现汇总给出（"其中 M 件进了邮件，不会丢失"）——**结算前不得出现任何 M**
     开箱日志归 01 / 10（开出一个物品 = 新增一个实例，没有"计数 +1"这个动作；日志不记 location，由存档承担）
```

### 7.3 一次按实例销毁 / 按条件销毁（燃料 / 引擎 / 转化 / 丢弃统一路径）

```
请求方（03 / 04 / 05 / 06）→ ItemService.consume(instance_ids, tag)   # 主动丢弃走 discard(ids)：同一实现，归因单列 &"discard"（R-M13）
   ├─ 任一 id 不存在 / 入参内重复 / **任一 id 在邮件** → { ok = false, reason }：instances、count_index、warehouse_used、两个计数器**完全不变**（原子，R-M6）
   └─ 全部有效 → 逐个从 instances 移除 → 对应键 count_index −1（归零即消键）、warehouse_used −= Σ size → total_consumed += n，记录 tag 与事件 → 07 只读取用做归因
     （**不检查空间**：消耗不产出，永远不因容量失败）

请求方（04 / 05 的素材消耗）→ ItemService.consume_by_filter(category, quality_floor, n)
   → 合格集（**只含仓库实例**）按 §5.5 排序 → 取前 n 个 → 一次性全部销毁 → 返回被销毁的 id 列表（size == n；n > 合格集大小 → 返回 []，状态不变）
```

### 7.4 一次领取 / 一次事务（v0.9）

```
claim(ids) / claim_all()：候选集 = 指定的（或全部）mail 实例，按 (acquired_at 升序, instance_id 字典序) 逐件判定
   ├─ 放得下 → location = warehouse；count_index[key] += 1、warehouse_used += size；**放不下 → 留在 mail、进入 remaining**（部分成功，§5.10）
   └─ 返回 { ok = claimed.size() == 请求数, claimed, remaining, reason }；全程不创建实例、不改 instance_id / serial / source、不推进 serial_counters、不动两个计数器

transact(ops)（06 转化 / 04 拆卸装配替换）→ 先预校验全部 ops（id 存在性、是否在仓库、item_id / kind / overflow 合法、op 类型合法）
   ├─ 任一不合法 → { ok = false, reason }：**逐项**回到事务前（instances / count_index / warehouse_used / 三个计数器）
   ├─ **预演落位**：按 ops 顺序先 consume / discard 腾空间 → grant 再逐件判定；**任一 `overflow = &"reject"` 的产出放不下 → { ok = false, reason = &"no_space" }、逐项回到事务前（源实例不销毁、`mailed == []`）**（R-M14 的落地）
   └─ 全部通过 → 生效 → 返回 { ok, consumed, discarded, granted, mailed }（`mailed` 只会来自被动产出的 grant op；**主动操作的 grant 永不落邮件**）
```

---

## 8. 与其它系统的接口

| 方向 | 接口 | 说明 |
|---|---|---|
| 01 → 02 | `grant(item_id, { kind = &"gacha", series_id, box_seed, draw_index })` | 抽取结果入库：**创建 1 个实例并分配 `serial`**；`void` 结果不调用本接口。**v0.9：落仓库还是落邮件由 02 判定**（`gacha` 是**被动产出** → `overflow` 推导为 `mail`；01 不传、也不得判断容量），01 读返回值的 `instance.location` 即知去向。**不存在任何产出映射字段**（v0.7） |
| 02 → 01 | `find_unstocked_items(series_id)` | 「**当前仓库内无持有**」口径：返回该套系中**仓库里没有任何实例**的 `item_id`（含隐藏物品，**由 01 按 C3 自行过滤**）。⚠️ **它绝不能用于 ×1.5**：**裁决 11 已验证**——若用仓库口径判"未拥有"，玩家可以把实例**压在邮件里**，让同一物品**永远**被算作未拥有，从而**刷到永久加成**；×1.5 **只读 10 的收藏口径** `collected` / `is_collected`。两口径**合法但必须名字可分**（§4.3）。**加权与保底规则归 01**，02 只提供清单 |
| 02 → 04 / 05 / 06 | `resolve_item_id(category, quality) -> StringName` | 把"类别 + 品质"换成 `item_id` 的**唯一合法途径**（唯一性由 §5.12 V1 在加载时强制）；未注册组合返回 `&""`。**04/05/06 不得各自拼 `item_id` 字符串**（拼错只能在运行时暴露） |
| 03 → 02 | `query(category, quality_floor)` / `count(category, quality, location)` / `consume(ids, &"fuel")` | 03 的需求匹配（最大流）读聚合查询，选定实例后一次性原子销毁。**裁决 14**：`count(c, q, &"mail")` 让 03 能回答"**邮件里有几件需求物品**"，据此把"仓库满 + 邮件有货"提示给 08（03 §9 第 6 条的 UI 义务）；**不要把它与仓库数量相加**——那等于把邮件当第二仓库。**多需求项交付可用 `transact([consume…, consume…])` 一次提交**，同时满足跨需求项原子性与 `fuel` 标签（对应 `03-task.md` §11 T9；**取舍归 03**，02 只提供原语） |
| 04 → 02 / 05 → 02 | `consume(ids, &"engine")` / `consume_by_filter(...)` / `transact(...)` | 装置素材量与槽位占用归 04（`04-device.md`）；模块素材量与镶嵌位归 05（`05-module-pool.md`）。**"替换（拆旧装新）"必须走一次 `transact`**——旧实例的返还（`kind = &"refund"`）与新实例的创建同属一个逻辑动作，拼接两次会留下半个装置（§5.11）；**`refund` 是"主动操作"**：放不下则**整个事务被拒**（`reason == &"no_space"`，源实例不销毁、不创建返还实例、`unsocket` 返回失败，R-M14 / R-M8） |
| 06 → 02 | `transact([{consume, &"convert"}, {grant, kind = &"convert"}])` | 转换表与损耗归 06。**v0.9：转化 = 一次事务里的"销毁源实例 + 创建新实例"**（新 UUID、`serial = 0`），**不再表述为两次各自提交的调用**（§5.11）。**放不下时整个事务被拒**（`ok == false`、`reason == &"no_space"`；**源实例不销毁**、**`mailed == []`**）——这正是裁决 17 要防的"转化反噬"：若产出进邮件，转化就成了**净损失可用持有**（与 `06` 的 T14 断言一致） |
| 02 → 07 | `snapshot()` / `count()` / `ItemDef.value` / `warehouse_usage()` | 07 用 `v_i` 算 `M̄` 与归因；**本系统不参与计算**。**口径提醒（v0.9）**：`count()` 默认只含仓库实例，**邮件实例不是"可用持有"**（容量导致的邮件堆积是**未取用**而不是**已消耗**）；**`discard` 的销毁量单列**，07 的三个出口数字不得并入它（R-M13） |
| 02 → 08 | `snapshot()` / `count(c, q, location)` / `warehouse_usage()` / `mail_instances()` / `claim(ids)` / `claim_all()` / `discard(ids)` | 渲染归 08：默认层聚合呈现、实例级明细按需展开（§9）。**v0.9 新增**：仓库**占比**（读 `warehouse_usage()`）、邮件条目与来源、领取交互（回报"已领取 M / 还剩 K 件"）、**主动丢弃的二次确认**；08 **不得**自行求和容量、也不得自行判定落位（§10.6） |
| 02 → 10 | `to_save_dict()` / `from_save_dict()`（§4.6） | 存档结构与文件归 10；**`warehouse_capacity` 入档、两个派生值不入档**（§4.6）。**v2 → v3 迁移产出实例时 `source.kind` 写 `&"migrate"`**（`migrate` 不是 `migration`，§5.8）；`migrate` 是**被动产出**→ 放不下进邮件 |

> `[补充]` **`find_unstocked_items` 是"当前仓库内无持有"口径，与图鉴口径不同**：02 只回答"`location == warehouse` 的实例里现在有没有这个 `item_id`"（**邮件里的实例不算持有**；**裁决 11 已验证：若 01 用仓库口径判"未拥有"，玩家可以把实例压在邮件里让同一物品永远算未拥有，从而刷到永久 ×1.5 加成**——所以 ×1.5 **只读** 10 的 `collected` / `is_collected`）；10 的 `collected` / `gap_items` 回答"**是否曾经收录**"。在"只持久化现存实例"（§4.6）下二者会分叉——把某物品的最后一个实例交付掉之后，02 会重新把它算作"未持有"。**两个口径都合法，但名字必须可分**：`find_unstocked_items`（仓库口径，02）／`collected` / `is_collected`（收藏口径，10）。
> `[补充]` **`regular_count` / `socket_count` 是每套系常量**：02 在任何地方都**不得假设"8 个常规物品"或固定镶嵌位**——数值由套系品质决定，归属 01（`SeriesDef`）与 05。`find_unstocked_items` 的返回**含隐藏物品**，是否把它纳入 ×1.5 由 01 按 C3 裁决（02 不复述 01 的加权规则）。

---

## 9. UI 需求

**呈现归 08，以下为物品侧的硬需求（见 `08-ui-panels.md`）。**

| 需求 | 规格 |
|---|---|
| **图标 / 品质色** | 每 `ItemDef` 一个图标（切片 6 个即够：2 类别 × 3 品质）；条目边框/底光按 `quality` 取色（1 灰白 / 2 青蓝 / 3 紫），**颜色是品质的第一识别通道**，图标是第二通道（色盲冗余）；类别以图标形状 / 组内分组区分，**不得只靠颜色区分类别** |
| **数量徽标** | 右下角数字徽标，**值取自 `count()` 派生查询**（**只含仓库实例**，邮件数量**不并入**徽标，§5.10）；`1–999` 直显，`≥1000` 转 `1.2k`；**数量无上限，缩写只做显示，绝不截断真实数值**；数量为 0 时该条目不存在（不保留空条目） |
| **仓库占用 + 邮件与开盒前预告（v0.9）** | **默认只显示占比**（读 `warehouse_usage().ratio`，如"仓库 62%"）——核心 §4.7 明文"UI 换算为占比显示"；抽象单位的裸数字只允许出现在**展开层**（P6：不让玩家做除法）；接近上限时给可感知提示；**不得**把 `size` 渲染成"格"（§5.9）。邮件条目显示**数量与来源**（哪个盒子 / 哪次转化 / 哪次返还，读 `source`），提供"逐条领取 / 一键领取"，**领取后必须回报实际结果**（"已领取 M / 还剩 K 件"）——空间不足时是**部分成功**（§5.10），`claim_all()` **不得**表述为"一键领完"；**主动丢弃必须二次确认**（R-M13）。兑现 / 批量开盒前的空间预告**只允许下界式文案**（完整规格见下表后的"开盒前空间预告的文案规格"，与 `01` §5.7 / `08` R-20 同一份）——**禁止任何件数预测** |
| **新获得高亮** | 入库时该**聚合条目**高亮 + 数量滚动，持续 ≤ 1s，不阻塞任何操作 |
| **一键一条目** | 默认面板按 `(category, quality)` **聚合**，一个键一个条目；出现两个即为 bug（R-M1）。**不得逐实例罗列**——那会把 R5 的 6 个数字变成 N 个条目 |
| **实例级明细** | `[补充]` 展开层 / 详情页可按需列出该键下的实例（`serial` / `acquired_at` / `source`，每项一句话："第 N 个 · 来自套系 X · 何时"）。**默认视图不展示**；理由是核心 §4.2.1 把"溯源与收藏编号"列为实例化的三个用途之一，必须有一个可看的地方（呈现规格归 08） |
| **可心算** | 切片的 6 个 `count_index` 键应能在一屏内完整呈现，不滚动、不翻页（P6 + R5），**与实例数无关**；**邮件实例不进入这 6 个数字**（§5.10），否则心算口径会被位置拆成两套 |
| **不显示计算** | 不在物品条目上显示 `v_i` 或 ρ 影响（那是 07/08 的事）；物品面板只回答"我有什么、有多少" |

**开盒前空间预告的文案规格（v0.9；与 `01-gacha.md` §5.7 ／ `08-ui-panels.md` R-20 是同一份规格，此处只落物品侧的两个输入）**

1. `N = floor(可用空间 ÷ 池内最大 ItemDef.size)`——它是"**无论开出什么都放得下**"的**保证**，不是预测。
2. 文案：**"仓库剩余空间至少还能放下 N 件本套系物品"**。
3. **仅当本次结算盒数 `k > N` 时**追加一句：**"超出部分会进邮件，不会丢失。"**
4. `N == 0` 时退化为：**"仓库已满，本次产出会进邮件（不会丢失）。"**
5. **精确件数只在结算之后**由落点汇总给出（"**其中 M 件进了邮件**"）——**结算前不得出现任何 M**。
6. **禁止件数预测**（"本次 3 件进邮件"之类）：它会暴露"这次没抽到 `void`"，甚至可被反推大件，**违反 P4**（单次悬念不可消除）。`02` 只提供两个输入：`warehouse_usage()` 与 `ItemDef.size`（文案与算法属 `01` / `08`，**02 不产出预告文本**）。

---

## 10. 测试点与验收标准

### 10.1 实例与幂等（必测，v0.8 新增）

1. **幂等**：对同一 `instance_id` 重复 `grant`（重放同一 `source`）→ `instances.size()` 不变、返回**同一个**实例、`total_granted` 与 `count` 均不变、**`location` 也不变**（幂等命中不得把邮件实例"顺手"搬进仓库，§4.3）。**"不得产生第二个实例"必须逐项断言**（核心 §14.2 铁律 8）。
2. **UUID 唯一性**：连续生成 1e5 个 → **零碰撞**；逐个校验格式（36 字符、4 个 `-`、version nibble == `4`、variant 高 2 位 == `10`、全小写）。
3. **UUID 不来自可复现种子**：同一 `(series_id, box_seed, draw_index)` 重放两次（不传 `instance_id`）→ 得到**不同**的 id（实例身份与抽取随机流无关）。
4. **`serial` 语义**：开盒产出 `serial >= 1` 且对同一 `item_id` **严格单调、不复用**（销毁编号最大的实例后再开出一个，新编号 > 历史最大值）；**转化 / 拆除返还 / 解锁产出 `serial == 0`** 且不推进 `serial_counters`。**未知 `item_id`**：`grant(&"nope")` → 返回 `null`，`instances` 与计数器完全不变。

### 10.2 `count` 派生一致性（必测）

1. **逐项相等**：随机 1000 次增删后，`rebuild_count_index()` 与增量维护的 `count_index` **键集合与每个键的值都相等**，且每个键的值 == `instances` 中该 `(category, quality)` 的实例数。
2. **增删后立即生效**：`grant` / `consume` 返回后的**同一帧内** `count()` 即为新值（不存在"下一帧才更新"）。
3. **归零即消键 / 不存在负值**：某键降到 0 → 不保留 0 条目（R-M5）；`count()` 恒 ≥ 0，且结构上不可能为负（R-M7）。
4. **键数上界**：随机产出 10000 次后键数 ≤ 类别数 × 品质数（切片 ≤ 6），**与实例数无关**（R-M2）。
5. **禁止逐帧遍历**（性能红线的可测形式）：n = 5000 实例下 1e5 次 `count()` 的耗时不得随 n 线性增长；代码检查 `count()` 内不得出现对 `instances` 的全量循环（§4.4）。

### 10.3 原子性（必测）

1. **失败即全不变**：`consume` 中任一 id 不存在 → `ok == false`，`instances` / `count_index` / 两个计数器**完全不变**（R-M6）。
2. **入参内重复 id** → 失败（`reason == &"duplicate_id"`）且状态不变；空列表 → 合法 no-op；`consume_by_filter` 的 `n > 合格实例数` → 返回 `[]` 且状态不变。
3. **挑选顺序**：构造混合数据集（跨品质、跨秒、同秒），逐项断言返回顺序 == "最低合格品质优先 → `acquired_at` 升序 → `instance_id` 字典序"（§5.5）。
4. **一次只能销毁一次**：同一 `instance_id` 连续销毁两次 → 第二次 `missing_instance`；失败重试不产生"半个装置"（对齐 `03-task.md` §7 的单一事务口径）。

### 10.4 存档往返（必测）

1. **字节级稳定**：`to_save_dict()` → JSON → `from_save_dict()` → `to_save_dict()`，两次序列化**字节完全相同**（字段顺序、列表顺序、数值格式全部稳定）。
2. **顺序与历史保持**：载入后 `instances` 顺序与原存档一致、取键顺序固定；`serial_counters` 完整恢复（含已被消耗物品的历史编号）。
3. **只存现存实例 / 载入后自洽且幂等**：销毁 k 个实例后存档实例数 = n − k，**不出现任何已销毁实例的痕迹**（`README.md` 铁律 9）；载入后 `rebuild_count_index()` 与 `instances` 逐项一致（`count_index` 不入档），用存档中已有的 `instance_id` 重放 `grant` → 不产生第二个实例。

### 10.5 数量守恒（必测）

1. 随机执行 1000 次 `grant` / `consume` / `discard` / 转化 / `claim` 后恒有 **`instances.size() == total_granted − total_consumed`**（**裁决 12：守恒式按"全部实例"、与 `location` 无关**——把带位置过滤的 `count()` 写进守恒式即是 bug）；**幂等命中的 `grant` 不增加 `total_granted`**；**`claim` 两边都不动**（只改位置）；**`consume` 与 `discard` 都增加 `total_consumed`**。
2. **销毁无凭空产生**：任何 `consume` / `discard` 成功后，每个被销毁实例都计入 `total_consumed`，不得"销毁不记账"或"记账不销毁"；转化路径体现为"销毁 k 个源实例、创建 m 个目标实例（`m < k`）"，等式仍成立（销毁按全部 k 计）。跨系统红线（C1–C6）归 01/05/07 守护；本系统的红线是：**物品的任何写入都不得触碰池子状态或概率**，且**不得绕过 `ItemService`**（`README.md` §3.2）。

### 10.6 单写入方测试

- 静态检查：除 `ItemService` 外，任何脚本对 `instances` / `count_index` / `warehouse_used` / `serial_counters` 的赋值都应被禁止（同 `PoolService` 的处理）；实例身份（`instance_id` / `serial` / `source`）**只由 `ItemService` 在 `grant` 内写入**，**`location` 只由 `grant` / `claim`（及 `transact` 内部）写入**，03/04/05/06 只传递 `instance_id`，不得自行构造或改写实例，**也不得读写 `warehouse_capacity` 做自己的容量判断**（§5.10 的"唯一判定点"）；拆除返还只走 `grant(item_id, { kind = &"refund" })`，返还率不出现第二处实现（R-M8）。
- **`tag` 默认值检查（R-M9，v0.9 追加）**：静态检查必须断言"除测试代码外，没有调用点使用 `consume()` 的默认 `tag`"；运行时不变量是**任何不传 / 越域 `tag` 的调用立即失败**（`reason == &"bad_tag"`，`&"unknown"` 与保留值 `&"discard"` 都不合法）；**`discard` 的销毁量必须单列、不得并入 fuel / engine / convert 中的任何一个**（裁决 16，否则出口账被污染）。**容量判断的单一位置（v0.9）**：全库只有 `grant` / `claim` / `transact`（内部走同一函数）允许出现 `used + size <= capacity` 形式的判断；UI 与 03/04/05/06 一律只读 `warehouse_usage()`，`grep` 层面就应可查。

### 10.7 切片失败信号（要正视）

| 信号 | 含义 | 对策方向 |
|---|---|---|
| 测试者说"我分不清哪个是哪个" | 品质色/图标不可辨 | 加大图标差异与边框对比，而非增加文字 |
| 测试者能说出某类物品"值多少"却说不出自己有多少 | 价值与持有量脱节 | 收紧 `v` 阶梯的心算性（类别不影响价值） |
| 面板出现超过 6 个键，或按实例逐条罗列 | 聚合视图被破坏（R-M1） | **检查代码，不是调参** |
| 测试者问"这个物品到底有什么用" | 两个出口在物品层不可见 | 由 08 在任务/装配面板联动高亮 |
| 测试者认为某次开盒"什么都没得到" | P5 破裂 | 先查 `grant` 是否被调用、`item_id` 是否已注册、`source.kind` 是否在六值域内（非法会返回 `null`）；**v0.9 下被动产出不可能因容量丢失**（装不下就进邮件），**主动操作被拒时是"操作没发生"（源实例仍在）、不是东西丢了**——若东西"不见了"，只可能是①代码或配置问题，或②**邮件入口不可见**（东西在邮件里却看不到，对玩家等价于丢失，归 08） |
| 测试者开始"不敢开盒"，把盒子一直攒着不兑现 | **R14：仓库容量抑制开箱意愿**（核心 §12） | 按 R14 的四条对策逐条核对：邮件兜底是否可见、**下界式空间预告**是否出现（"至少还能放下 N 件"，**不得**是件数预测——那是 P4 违例）、容量能否按 D15 成长、**邮件是否被误读成"过期会丢"**；再查**死局**（满仓 → 领不出 → 交不了 → 拿不到盒子）时玩家知不知道能**主动丢弃**（裁决 16）、丢弃入口是否可见 |
| 测试者抱怨"东西领不出来" | 领取的部分成功未被呈现 | 领取是**部分成功**（§5.10）：查 UI 是否回报了"已领取 M / 还剩 K 件"；若测试者以为整批失败，那是**呈现问题，不要改规则** |
| 测试者问"这个物品是第几个、从哪来的"却找不到答案 | 实例级溯源入口缺失 | 归 08 的展开层（§9 实例级明细），不是 02 的 bug |

### 10.8 仓库容量、邮件与事务（v0.9 新增，必测）

1. **被动产出的溢出三种边界**：把 `warehouse_used` 造到 `capacity − size`（**刚好放得下**）→ 该 `grant` 落 `warehouse`；造到 `capacity − size + 1`（**超出一件**）→ 落 `mail`，且 `count_index` / `warehouse_used` **都不动**；连续 `grant` 多件（**超出多件**）→ 恰好填满仓库，其余**全部**进邮件，逐项核对落点（`overflow` 推导为 `mail` 的那几类来源各验一次）。
2. **邮件实例不计入 `count()`（最容易错的一条）**：`grant` 落邮件后 `count(c, q)` **不增加**，`count(c, q, &"mail")` 增加 1；**两个口径互不隐式合并**——同一个实例**不得同时**被两个口径计入。
3. **领取只改 `location`**：领取前后实例**总数不变**、`instance_id` 集合**逐项相等**、`serial` / `source` / `acquired_at` **逐项不变**、`total_granted` / `total_consumed` / `serial_counters` 不变；对同一批 id 重复 `claim` → 幂等（仍计入 `claimed`，`instances` 不变）。
4. **领取后占用正确且不超容**：随机 `grant` / `claim` / `consume` 交替 1000 次后恒有 `warehouse_used == Σ（location == warehouse 的 size）`（与增量缓存逐项相等）且 `warehouse_used <= capacity`；任何一步都不得越过容量。
5. **事务原子性 + 主动操作的空间拒绝（裁决 17）**：①必然失败的组合（如 `[consume(合法 id, &"convert"), grant(未注册 item_id)]`）→ `ok == false`，且 `instances` / `count_index` / `warehouse_used` / `total_granted` / `total_consumed` / `serial_counters` **逐项等于事务前快照**（**逐项断言**，不接受"看起来没变"）；②**空间拒绝**：把仓库造到装不下转化产物 → `ok == false`、`reason == &"no_space"`、**源实例逐项仍在**（实例列表逐项比对）、无新实例、两个派生值回到事务前、**`mailed == []`**（主动操作的 grant **永不落邮件**，与 06 的 T14 同源）——这是 **P5 在主动操作上的兜底**；③**越权放宽被拒**：`convert` / `refund` 的 op 声明 `overflow = &"mail"` → 直接失败（不产生邮件实例）；④成功路径逐项等于"按 `ops` 顺序单步执行"的结果（含"先销毁 / 丢弃腾空间、后创建"的落位结果）。
6. **配置校验器拒绝非法配置**：两个 `item_id` 共享同一 `(category, quality)` → **加载被拒绝**并报出冲突双方（V1）；`size <= 0` → 被拒绝（V2）；`warehouse_capacity == 0` → 被拒绝（§5.9）；**合法配置一律照常加载**（校验器不得改任何数值）。
7. **容量边界处不出现"部分入库"**：**被动产出**在 `used + size > capacity` 时该实例**完整地**在邮件（`location == mail`、`warehouse_used` 不增长），**不存在**"实例在仓库却只算一半 `size`"或"半个实例在仓库"的中间态（**主动操作**在同一位置上的正确行为是**整个操作被拒**，见第 5 条）；一次超过容量 10 倍的批量产出的最终态满足 `warehouse_used <= capacity` 且 `mail_count == 总产出数 − 入库数`。
8. **主动丢弃是死局逃生阀（裁决 16）**：先把仓库造满（`warehouse_used == capacity`）→ ①`discard(仓库实例)` 成功、`warehouse_used` 相应下降、`total_consumed` 增加、守恒式仍成立；②随后 `claim()` **至少能领进 1 件**（**死局可解**）；③**丢弃量单列**——`fuel` / `engine` / `convert` 三份出口数字之和不含丢弃量（归因不被污染）；④**丢弃不产生产出**（`instances.size()` 只减不增），且**不能丢弃邮件实例**（→ `&"not_in_warehouse"`）；⑤丢弃进事务（`op = &"discard"`）时与 `consume` 同一原子性。

---

## 11. 待定项

| # | 待定项 | 现状与影响 |
|---|---|---|
| **M3** | 类别是否应影响价值（`value` 是否偏离品质阶梯） | 推荐**不影响**（3 个数字可心算，R5）。若后期类别需要价值差异，等价于在 `v` 上再叠一层倍率，会直接加重 R5 |
| **M4** | 品质档位总数与全量维度 | 切片 3 档、上限 5 档；核心 D2 的推荐值已被本系统采用，**最终档数需与 D13 模块品质梯度的释放节奏一起定**（见 `05-module-pool.md`） |
| **M5** | 新类别的解锁方式 | 推荐由里程碑任务解锁（见 10），但解锁节奏属内容产能问题（R11），需与 R11 对策一并评估 |
| **M6** | **存档体积实测**（v0.8 新增） | 实例化把存档从"每键一行"变成"**每个体一行**"（上游估算约 120 B/实例、5000 实例 ≈ 600 KB，`source` 是大头；**v0.9 的 `location` 未含在该估算内，实测时一并计**）。**切片阶段必须实测**：真实 JSON 字节数、单实例均值、载入耗时；若显著超出 600 KB 量级，需回报上游重新裁决（可选方向：`source` 折叠为短键、二进制/压缩存储——**压缩不得改变幂等键与 `serial` 语义**） |
| **M7** | **容量与 `size` 的数值标定**（核心 D16，v0.9 新增） | 上游示意：容量 `1000`、`size` 按品质 `1 / 2 / 5 / 10`。**这两个数一起决定"仓库多久满"**，必须与任务需求向量（03）、单次开盒产出量与批量兑现规模（01/09）**联合标定**，切片阶段实测（做法同 M6：先量真实产出速率，再反推容量）。**风险两头**：容量太小 → R14（不敢开盒）当场成立；太大 → 容量形同虚设，"囤积占地方"的压力归零 |
| **M8** | **容量是否可成长**（核心 D15，v0.9 新增） | 推荐**由里程碑解锁**（内容门控，与 P7 一致）；若固定不变，"仓库满了"会从挑战变成死局（R14）。**裁决未定前本系统按"`warehouse_capacity` 是可改配置 + 入档"实现**（§4.6 / §5.9），使两种方案都不必改存档结构；**容量成长绝不得把已入库实例挤出仓库**（§5.9） |

> **已删除的待定项（记录以免重提）：** **M1「款 → 物资产出的字段归属」**——v0.7 术语合并后不再存在，物品即池中条目，**没有任何产出映射字段**；**M2「堆叠上限是否应成为真实压力」**——v0.8 之后**堆叠在结构上不可能存在**（§5.3），该问题彻底作废。**（编号 M1 / M2 留空；M3–M5 保持不变，M6 为 v0.8 新增，M7 / M8 为 v0.9 新增。）** **v0.9 已裁决、不再列为待定**：容量与 `size` 的**机制**已由核心 §4.7、裁决 16 / 17 与本文档 §5.7 / §5.9 / §5.10 钉死（谁占地方、被动产出进邮件、主动操作被拒、领取只改位置、可主动丢弃、只消耗不产出的操作不查空间）；**只剩标定数值（M7）与成长策略（M8）两件事待定**。

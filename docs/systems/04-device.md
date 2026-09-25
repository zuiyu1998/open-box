# 04 · 装置系统

- 上游：`../core-design.md` **v0.9** ／ `README.md`
- 依赖系统：`02-item.md`（素材消耗与返还）、`05-module-pool.md`（跨端组合条件只读池子状态）、`06-conversion.md`（转化损耗基准值）、`03-task.md`（需求向量与奖励结算的执行方）、`07-economy-rho.md`（D̄ / B / ρ 的计算口径与归因产出）
- 被依赖：`03-task.md`（结算时读取修正）、`06-conversion.md`（读取损耗修正）、`07-economy-rho.md`（把修正作为输入）、`08-ui-panels.md`（架上 / 归因面板渲染）、`10-progression.md`（品质梯度的解锁发放）

---

## 1. 这个系统负责什么

装置是循环中**"引擎"出口在转化端的施工工具**（`engine` / `convert_end`，核心 §3）。

| 职责 | 内容 |
|---|---|
| 定义装置 | `DeviceDef`：效果类型 + 目标 + 系数 + 成本 + 品质 + 条件 + 互斥 |
| 管理位次 | 槽位 `device_slot` 的数量由**该套系的品质 `series_quality`** 决定（核心 §4.1.1 / D4），构造时从 `SeriesDef.device_slot_count` 注入并冻结，**是"每套系常量"而不是可变状态**（P7 / C4） |
| 装配 / 拆卸 | 装配**销毁物品实例**（`ItemService.consume(instance_ids)`，原子）；拆卸按原 `cost` 逐条 `floor(amount × 0.5)` **返还 50%**——返还**创建新实例**（**新 UUID**、`source = { kind = &"refund" }`；`serial = 0` 由 02 内部置位，**`serial` 不是 `grant` 的参数**）；**拆卸前须通过空间预检：返还装不下则整个拆卸被拒绝**（裁决 17）（R10，核心 D8；实例语义见 §5.3） |
| 提供修正 | 只输出**修正量**（降 D̄ / 提 B / 降转化损耗 / 降需求品质下限），最终数值口径归 `07` |
| 品质梯度 | 作为内容释放载体之一（R11 / D13），高阶装置由里程碑任务释放 |
| 归因条目 | 每个已装配装置产生一条可读归因项，满足 P2 |

**服务循环的哪一步：** "使用物品"（核心 §1.1）——装置是"同一份物品，用掉还是留下改造循环"里的**留下**。

---

## 2. 不负责什么（边界）

| 不属于本系统 | 归属 |
|---|---|
| 转化损耗的**基准值**（30%）。装置只提供**修正** | 见 `06-conversion.md` |
| 任务需求向量（`TaskDef`）的结构与匹配 | 见 `03-task.md` |
| ρ / M̄ / D̄ / B / σ 的**计算口径**与归因汇总 | 见 `07-economy-rho.md` |
| 池子状态、镶嵌位、排除 / 提升 / 损耗 | 见 `05-module-pool.md` |
| 物品的类别 / 品质定义、**持有量（派生值）与物品实例列表** | 见 `02-item.md`（`ItemService` 是实例列表的**唯一写入方**） |
| 六面板渲染、展开入口、实时联动 | 见 `08-ui-panels.md` |
| **槽位数量的最终值** `SeriesDef.device_slot_count`（随 `series_quality` 取值） | 见 `01-gacha.md`（`SeriesDef` 归属）；本文只读并冻结，曲线形状见本文 §11 / 核心 D3·D4 |
| 里程碑解锁的发放逻辑 | 见 `10-progression.md`（本文只消费 `unlock_flag`） |

**硬边界：** 装置**永不**触碰概率、池子、抽取。装置只读池子状态（用于跨端组合条件判定），不写。

---

## 3. 核心概念与术语

术语一律使用 `README.md` §5 的中文名 + 代码名，不自造同义词。

| 中文名 | 代码名 | 本文用法 |
|---|---|---|
| 装置 | `Device` | 一件可装配的转化端施工件 |
| 槽位 | `device_slot` | 数量 = 该套系的 `SeriesDef.device_slot_count`；**同一套系内恒定、运行时不可变**（v0.6：不再固定为 4） |
| 转化端 | `convert_end` | 装置唯一合法作用端 |
| 引擎 | `engine` | 物品出口之一：装配为装置 / 模块 |
| 物品 | `Item` | 装置素材来源（消耗规则见 §5.5） |
| **物品实例** | `ItemInstance` | 装配时被**销毁**的那个物品个体；拆卸返还时**新建**（见 §5.3）；实例列表归 02 |
| **实例 id** | `instance_id` | **UUIDv4，全局唯一**；装配消耗按它指定实例，**返还实例的 UUID 全新**（原实例已销毁，不可恢复） |
| **收藏编号** | `serial` | **返还实例一律 `serial = 0`**——上游裁决：只有开盒产出才分配收藏编号；**它是实例字段，不是 `grant` 的参数**，由 02 内部置位（§5.3） |
| **物品品质** | `quality` | 1–5 序数，见 `02-item.md`；`DeviceDef.cost[].quality` 用的是它 |
| **套系品质** | `series_quality` | 核心 §4.1.1 的套系分级，决定**装置槽位数**（本文）与镶嵌位数（`05`）；由里程碑解锁 |
| 闭环收益率 | `rho` / ρ | 装置的效果最终体现在 ρ 上（口径见 `07`） |

**术语纪律 —— "品质"有两个含义，本文必须分辨：** **物品品质** = `quality`（1–5 序数，见 `02-item.md`）；**套系品质** = `series_quality`（核心 §4.1.1），它决定**槽位数**。本文出现装置的**"品质梯度"**（§1 / §5.5 / D13 / R11）时，指的是**后者所在的这套品质体系**——"按品质梯度释放内容"的节奏，**不是**物品等级：装置自身的档位是 `DeviceDef.quality`（4 档枚举），释放节奏与 `series_quality` 体系对齐；`DeviceDef.cost[].quality` 才是物品品质。

**作用端固定：** `DeviceDef.apply_end` 只有 `CONVERT_END` 一个合法取值，不提供其它枚举值——装置不可能作用在开盒端（核心 §4.4）。

**两套位次体系相互独立：** 装置占 `device_slot`（数量 = 该套系 `SeriesDef.device_slot_count`，本文），模块占 `socket_slot`（数量 = 该套系 `SeriesDef.socket_count`，见 `05-module-pool.md`）。二者互不占用、互不换算、互不提供扩容接口；装置**不能**被镶嵌进池子，模块**不能**被装入装置槽位。两条曲线同步（核心 D4 推荐"是"），但**同一套系内各自恒定**。

**"两端"的含义（本文澄清）：** 核心 §13.1 的"两端各至少 2 个"指**转化端的两个半边**——
**消耗侧**（降 D̄、降需求品质下限、降转化损耗）与**奖励侧**（提 B）。
装置本身**全部**在转化端；与开盒端（模块）的组合见 §5.4。

**新增字段说明：** 本文出现 `[补充]` 标记的字段均为核心文档已命名的能力（核心 §14.3 列出 `DeviceDef` 含"作用端、目标、强度、条件、互斥"）在 GDScript 层的落地形状，**不引入新机制**。

---

## 4. 数据结构（GDScript Resource 字段定义）

```gdscript
# res://src/devices/defs/device_effect.gd
class_name DeviceEffect
extends Resource

## 效果类型：四类均在转化端，顺序与核心 §4.4 的效果示例一致
enum EffectType {
	REDUCE_D_BAR,                    # 降低任务物品消耗 D̄
	RAISE_B,                         # 提高任务奖励 B
	REDUCE_CONVERSION_LOSS,          # 降低转化损耗（基准值见 06-conversion.md）
	LOWER_REQUIRED_QUALITY_FLOOR,    # 降低任务需求品质下限
}

## 作用目标：全局，或限定某物品类别（category 定义见 02-item.md）
enum TargetScope { GLOBAL, CATEGORY }

@export var type: EffectType = EffectType.REDUCE_D_BAR
@export var target_scope: TargetScope = TargetScope.GLOBAL
@export var target_category: StringName = &""   # 仅 TargetScope.CATEGORY 时生效
@export_range(0.0, 5.0, 0.01) var coefficient: float = 0.0
## [补充] 同组取最大而非相加，用于表达"同类装置不叠加、只能换更强的"，理由：核心未定义叠加时的冲突解，而 P7 要求功率可封顶。
@export var stack_group: StringName = &""
```

```gdscript
# res://src/devices/defs/device_cost.gd
class_name DeviceCost
extends Resource

## [补充] 装配成本条目的字段形状，核心文档未给出；按 D2 的"类别 × 品质 两维"落地，与 ItemDef 对齐。
## v0.9：本条目是**需求向量**，不是计数扣减指令——
##   装配 → 交 02 按 (category, quality) 挑选 amount 个实例并**销毁**（原子，全有或全无）；
##   拆卸 → 按本条目逐条 floor(amount × 0.5) **新建**实例（新 UUID；serial = 0 由 02 内部置位）。
##   返还落到哪个 item_id：一律调 02 的 resolve_item_id(category, quality) 反查（裁决 9），
##   本系统**不得**自己构造 item_id 字符串；该映射的"唯一"由配置校验器强制（§5.3 / §11 04-F）。
@export var category: StringName = &""
@export var quality: int = 1
@export_range(1, 99, 1) var amount: int = 1
```

```gdscript
# res://src/devices/defs/device_condition.gd
class_name DeviceCondition
extends Resource

## [补充] 核心 §14.3 列出 DeviceDef 含"条件"但未定义形状，此处给出最小可配置形状。
@export var required_task_tag: StringName = &""       # 任务带该 tag 时才生效（tag 归 03-task.md）
@export var min_required_quality: int = 0              # 任务品质要求 >= 该值时生效
@export var min_completed_tasks: int = 0               # 该任务已完成的次数门槛
```

```gdscript
# res://src/devices/defs/cross_end_condition.gd
class_name CrossEndCondition
extends Resource

## 跨端非线性组合的条件（装置在转化端 × 模块在开盒端，规则见 §5.4）
## [补充] 字段为落地形状，非线性本身来自 ρ 的乘法结构（核心 §2.3），不新增机制。
@export var required_module_tag: StringName = &""      # 需已镶嵌带该 tag 的模块（tag 见 05-module-pool.md）
@export var required_category: StringName = &""        # 池中该类别物品占比门槛所看的类别
@export_range(0.0, 1.0, 0.01) var min_pool_ratio: float = 0.0
@export_range(1.0, 3.0, 0.05) var bonus_multiplier: float = 1.0
```

```gdscript
# res://src/devices/defs/device_def.gd
class_name DeviceDef
extends Resource

## 作用端：装置被固定为转化端，唯一合法值（核心 §4.4 / 所有权边界表）
enum ApplyEnd { CONVERT_END }

enum Quality { COMMON, RARE, EPIC, MYTHIC }

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var quality: Quality = Quality.COMMON
@export var apply_end: ApplyEnd = ApplyEnd.CONVERT_END

@export var effects: Array[DeviceEffect] = []
@export var cost: Array[DeviceCost] = []

## 互斥：同组只能装配 1 件（核心 §14.3 的"互斥"字段）
@export var exclusive_group: StringName = &""
@export var condition: DeviceCondition                  # null = 无条件
@export var cross_end: CrossEndCondition                # null = 无跨端组合

## 产出权限：由里程碑任务释放（D13 的载体之一），发放逻辑见 10-progression.md
@export var unlock_flag: StringName = &""
@export var tags: Array[StringName] = []
```

```gdscript
# res://src/devices/device_service.gd（状态部分）
class_name DeviceLoadout
extends Resource

## ★ 槽位数是"每套系的常量"，由该套系的 series_quality 决定（核心 §4.1.1 / D4）。
##   构造时从 SeriesDef.device_slot_count 注入并冻结，之后运行时不可变（P7 / README §3.4）。
##   全工程唯一来源 = SeriesDef；除它以外任何地方都不得持有或改写槽位数。
@export var series_id: StringName = &""

## 冻结值：只允许在 _init 中赋值一次；不提供 setter。
var _slot_count: int = 0

## 构造签名：DeviceLoadout.new(series_def.id, series_def.device_slot_count)
## [补充] 非法值按 0 处理并报错，理由：宁可拒绝配置，也不能静默给出可写入口（P7）。
func _init(p_series_id: StringName = &"", p_device_slot_count: int = 0) -> void:
	series_id = p_series_id
	_slot_count = maxi(p_device_slot_count, 0)
	slots.resize(_slot_count)

## 返回该套系冻结的槽位数。**同一套系内恒为同一个值，任何路径都不得改变它。**
func slot_count() -> int:
	return _slot_count

## 长度恒为 slot_count()，元素可为 null（空槽）。
## 存档加载时 slots.size() 与该套系的 SeriesDef.device_slot_count 不符一律拒绝。
## [补充] 存档校验规则：核心只规定槽位是每套系常量，未规定存档被篡改时的行为，此处补边界处理。
@export var slots: Array[DeviceDef] = []
```

**禁止实现的接口（P7 的代码层体现）：** 不提供 `add_slot()` / `grow_slots()` / `set_slot_count()` / `upgrade_slots()`，也不提供任何在运行时改写 `_slot_count` 或 `SeriesDef.device_slot_count` 的入口。任何"槽位随进度 / 随开盒次数增长"的设计一律否决；**同一套系内的扩容接口一个都不留**（换套系不是扩容，是内容）。

---

## 5. 规则与公式

### 5.1 效果语义与系数方向

| `EffectType` | 语义 | `coefficient` 单位 | 正数含义 | 合法 `TargetScope` |
|---|---|---|---|---|
| `REDUCE_D_BAR` | 降低任务物品消耗 D̄ | 比例（0.10 = −10%） | 降低 | `GLOBAL` / `CATEGORY` |
| `RAISE_B` | 提高任务奖励 B | 绝对盒数（1.0 = +1 盒） | 提高 | `GLOBAL` / `CATEGORY` |
| `REDUCE_CONVERSION_LOSS` | 降低转化损耗 | **绝对百分点**（0.15 = −15pp） | 降低 | `GLOBAL` |
| `LOWER_REQUIRED_QUALITY_FLOOR` | 降低任务需求品质下限 | 整数档位（1 = 降 1 档） | 降低 | `GLOBAL` |

**装置只输出修正量，不输出结果值。** 例如装置给 `reduce_d_bar = 0.10`，最终 D̄ 由 `07-economy-rho.md` 的口径算出；转化损耗基准 30% 由 `06-conversion.md` 持有，装置只给 `loss_reduction_pp`。

### 5.2 叠加规则

1. 逐条效果先判定 `condition`（不满足则整件装置**所有**效果不生效，但在架上仍占槽）。
2. 相同 `(type, target_scope, target_category)` 且 `stack_group` 为空的效果：**相加**。
3. `stack_group` 非空的效果：同组内**取最大值**，不相加（可用"换更强的"表达，同时天然封顶）。
4. 汇总后套用上限（§6 参数表）：`REDUCE_D_BAR` 总额 clamp 到 ≤ 0.60 🔧；`LOWER_REQUIRED_QUALITY_FLOOR` clamp 到 ≤ 2 档 🔧 且不得使下限 < 1。
   `[补充]` 上限的具体数值核心未给出，为落地所需：防止 D̄ 归零导致 ρ 发散（P7 功率封顶的直接推论）。
5. `RAISE_B` **不设额外数值上限**——槽位是"每套系常量"（只在跨套系时随品质增长，且由内容释放门控）、装置品质档位有限，功率已由 P7 结构性封顶。
6. **取整不在本系统**：需求数量、损耗百分点的取整口径归 `03` / `06` / `07`，装置只交浮点修正值。

### 5.3 装配与拆卸（可逆但昂贵，D8 / R10）

**v0.8：装配与拆卸作用的对象是「物品实例」，不是「计数」**——这是本系统在物品实例化模型下唯一改变的形态，**数值规则（50% / 逐条 `floor`）一字不动**。

```
装配：校验（槽位 / 解锁 / 互斥 / 条件）
      → 挑选实例：按 cost 逐条在 (category, quality) 命中集内挑 amount 个实例
        （挑选顺序沿用 02/03 的精神：最低合格品质优先，同品质内 acquired_at 升序）
      → ItemService.consume(instance_ids, &"engine")   # 销毁实例，**原子：全有或全无**
      → 写入该槽位 → 触发 07 重算 → 归因与 ρ 刷新（P2）
        # 装配只消耗、不产出 ⇒ **不做空间预检**（核心 §4.7 边界 2）

拆卸：校验槽位非空 → 按 cost 逐条计算返还量 floor(amount × 0.5)
      → ★ **空间预检（在事务之前，先查再动）**：Σ(返还实例的 ItemDef.size) ≤ 仓库剩余空间？
          ├─ 否 → **拒绝整个拆卸操作**：返回失败 + 可读错误（还缺多少空间）
          │       ★ 拆卸不执行——槽位不变、**原实例不销毁**、**不创建任何返还实例**（逐项不变）
          └─ 是 → 继续
      → item_id = ItemService.resolve_item_id(category, quality)   # ★ 反查接口归 02，不得自己拼字符串
      → ItemService.grant(item_id, { kind = &"refund" })            # ★ 新建实例，新 UUID
        # ★ serial 不是 grant 的参数：第三位是幂等键 instance_id；返还实例的 serial = 0 由 02 内部置位
      → 槽位置 null → 触发 07 重算

替换：**一次 ItemService.transact() 调用**（02 提供的单次事务原语）内 = 拆卸（含 50% 返还）+ 装配，
      ★ 空间预检同样放在**事务之前**：返还装不下则**整体拒绝**，槽位与实例列表逐项不变；
      不是"多次 consume / grant 调用拼起来"；任一失败则物品侧事务整体回滚
      （**回滚必须撤销本次已创建的全部返还实例**：数量与实例列表逐项回到事务前）
```

- **返还率 50% 是全局常量**（核心 D8），不可被配置或装置修改，也不提供上调接口。
- **消耗是销毁实例**：装配消耗经 `ItemService.consume(instance_ids)` 落地，**不做任何 `count -= n` 的计数扣减**；实例列表的唯一写入方是 02（README §2.1），装置只发起请求。
- **原子性**：一次装配的全部 `DeviceCost` 条目必须在**同一事务**内全部成功；任一条目实例不足即**整体失败、实例列表完全不变**（对应 02 的 R-M6 原子扣减）。因为一次装配涉及**多次实例销毁**（替换则还叠加多次实例创建），**失败面比计数模型更大**，所以"同一事务"是硬要求而非实现细节。
- **⚠️ 返还的是新实例，不是原实例——原实例在装配时已销毁。**
  - "返还 50%" 在实例模型下**不是把实例改回来**，而是**创建新实例**：`ItemService.grant(item_id, { kind = &"refund" })`，**UUID 全新**；
  - **⚠️ `serial` 不是 `grant` 的参数**：正确签名是 `grant(item_id: StringName, source: Dictionary = {}, instance_id: String = "")`（02 §4.3）——第三位是**幂等键 `instance_id`**，**不是 `serial`**。把 `serial = 0` 写进第三位，会让**所有拆卸返还共享同一个幂等键 `0`**，于是**第二次返还起被幂等逻辑吞掉，玩家只拿得回一次**——**这是会直接吃掉玩家资产的 bug，本文档禁止出现这种写法**；
  - **`source` 是开放字典、`kind` 必填**（核心 v0.9）：返还写 `source = { kind = &"refund" }`；**不得把 `value` 直接写成一个 `StringName`**（v0.8 的旧写法把 `source` 当成字符串传，类型错误——`source` 的合法类型是 `Dictionary`）。`serial = 0` 由 02 按"非开盒来源"**内部置位**（02 §5.6），装置侧**不传、不写、不参与**；
  - **原 `instance_id` 不可能恢复**——它已在装配时被销毁，且核心 §4.2.2 明确"已消耗的实例不保留历史"（只持久化现存实例）；
  - **`serial = 0`**（上游裁决：**只有开盒产出才分配收藏编号**）。返还实例在叙事上**不等于"你原来那一个"**，也不占用收藏编号序列；
  - 因此"返还 50%"是**数量意义上的 50%**，不是**个体意义上的复原**；数量规则**不变**，仍按**原有的逐条 `floor(amount × 0.5)`**（见下条）。
- **返还的 `item_id` 一律经 02 的 `resolve_item_id(category, quality)` 反查**（上游裁决 9）：装配成本是两维需求（**`DeviceCost` 保持两维**，裁决 5），而返还必须落到具体 `item_id`；**该映射的唯一性由配置校验器强制**（一个 `(category, quality)` 只允许对应一个 `item_id`，配置期不合法即报错），**不再是"切片下碰巧唯一"的兜底说明**。装置侧**不得**自己构造 id 字符串（不得拼 `"<category>_<quality>"`），也**不得**从已销毁的实例读回 `item_id`——反查接口归 02，装置只调用（§11 / **04-F**）。
- **⚠️ 拆卸返还装不下 → 拒绝整个拆卸操作**（上游**裁决 17**，**推翻 v0.9 早先的"返还也进邮件"**）：产出溢出按**操作性质**分叉——
  - **被动产出（开盒）**：放不下 → **进邮件**（`location = mail`，产出永不丢失，核心 §4.7）；
  - **主动操作（转化 / 拆卸返还）**：放不下 → **拒绝整个操作**。理由是**主动操作不能反噬**：它销毁源实例腾出空间，产出的新实例却进邮件，就变成**净损失可用持有**，与"转化是燃料路径的预处理"的立意直接冲突；拆卸同理——玩家主动拆，返还却进邮件，等于**拆了个寂寞**。
  - **因此拆卸必须做空间预检，且预检在事务之前**（**先查再动**）：`Σ(返还实例的 ItemDef.size) > 仓库剩余空间` ⇒ **返回失败**并给出可读错误（缺多少空间），**槽位不变、原实例不销毁、不创建任何返还实例**（逐项不变）。**禁止"先销毁 / 先 `grant`，发现放不下再靠回滚"**——那会让玩家在一次被拒绝的操作里看到自己的东西消失过。
  - **装配侧仍不做空间预检**：它只消耗不产出（核心 §4.7 边界 2），不会因仓库满而失败。
- **邮件实例不可用于装配**（核心 §4.7 边界 1 / §14.2 铁律 9）：`count()` 只统计 `location == warehouse` 的实例，**邮件里的实例不是可用持有**，不可用于装配装置；因此挑选天然只落在仓库内实例上。**这是 02 的口径**——装置侧**不得自行读 `location` 或自行统计**（那会造出第二个事实来源）。**守恒口径以全部实例（含邮件）为准**（裁决 12）：`count()` 只是**带 `location` 过滤的查询**，**不得**把它写进任何守恒等式（"仓库 Σcount == 差值"这类写法是错的）。
- **消耗类操作不检查空间**（核心 §4.7 边界 2）：装配只消耗不产出，不因仓库满而失败；**装置侧唯一的空间分支就是拆卸的返还预检**（见上条），装配路径**不实现"空间不足"分支**。
- **不承诺跨系统原子性**（裁决 13）：`ItemService.transact()` **只覆盖物品侧**（实例的销毁与创建），**不**包含槽位等装置侧状态，也**不**跨 04 / 05 / 06 组事务。装置侧状态在物品事务成功后写入；其后的失败由装置侧自行回退或自愈，**不得**要求物品侧回滚（本文档任何"跨系统回滚"的说法都以此为准）。
- **逐条向下取整**：每 `DeviceCost` 条目返还 `floor(amount * 0.5)`，余数**不**累加到其它条目——保证返还量只与消耗量有关，与操作顺序无关（守恒可测，见 T2）。`[补充]` 取整与"替换 = 单事务"核心只规定"可拆、返还 50%"，此处补落地细节以保证确定性。
- 拆卸**不会**降低装置品质、不消耗额外费用；"昂贵"仅体现为 50% 净损失。
- 装配 / 拆卸 / 替换**都不改变**任何套系的槽位数；切换套系只是取用另一个套系的冻结值（见 T1 / T1b）。

### 5.4 跨端非线性组合（装置 × 模块）

两端各有一组封顶的施工工具：装置在**转化端**（核心 §4.4），模块在**开盒端**（核心 §4.5）。二者的组合在 ρ 上**相乘**（ρ 的定义与口径见 `07-economy-rho.md`），因此两个"看起来只是加减"的修正会产出**超线性**结果：

| 端 | 典型效果 | 单独效果 |
|---|---|---|
| 转化端 · 装置 | `REDUCE_D_BAR` 0.20 → D̄ 下降 | ρ 提升约 1/(1−0.20) |
| 开盒端 · 模块 | 提升任务所需类别物品概率 → M̄ 上升 | ρ 提升约 M̄ 增幅 |

两者同时成立时 ρ 的增幅**大于各自增幅之和**。这是**结构性的**，不需要任何隐藏加成。

**显式组合（可选，纯配置）：** `DeviceDef.cross_end` 非空时，条件满足则把该装置**全部效果系数**乘以 `bonus_multiplier`：

- 条件 = 已镶嵌的模块带 `required_module_tag` **且** 池中 `required_category` 物品占比 ≥ `min_pool_ratio`（池子状态**只读**，来自 `05-module-pool.md`）；
- 判定在 `07` 求值时进行，装置自身不缓存池子状态；
- 该加成必须在归因面板单独成条（P2：任何 ρ 上升都要可归因）。

**切片要求：** 至少 1 组跨端组合。示例——`DEV_C02 定向采购`（对类别 A 降低 D̄ 20%）× `05` 中"提升类别 A 对应物品概率"的模块。

### 5.5 素材消耗与品质梯度

- 装置**只能**由物品装配而成：成本是 `cost` 向量（类别 + 品质 + 数量），在装配瞬间**销毁对应实例**（`ItemService.consume(instance_ids)`，原子，见 §5.3）；物品侧的状态变化见 `02-item.md`。**可消耗的只有仓库内实例**——邮件实例不参与挑选，也不计入 `count()`（§5.3 与核心 §4.7）。
- **实例化带来的形态差异只有一处**：装配**销毁实例**、拆卸**新建实例**（新 UUID、`serial = 0`）；**`cost` 的数值、返还率 50%、逐条 `floor` 取整规则、装置效果数值全部不变。**
- **品质梯度只改变量，不改变机制**：`COMMON → RARE → EPIC → MYTHIC` 的差异仅体现在 `effects[].coefficient` 与 `cost` 上，效果类型集合完全相同。
- **术语（见 §3）：** 本条与标题里的"品质梯度"指 `DeviceDef.quality` 与内容释放节奏，属 `series_quality` 所在的品质体系；`DeviceDef.cost[].quality` 才是物品品质 `quality`（1–5）。
- 新增装置**必须能纯配置产出**（写一个 `.tres` 即可，不改代码）——这是 R11 的核心对策，也是核心 §14.3 的硬要求。
- 高阶装置的 `unlock_flag` 由里程碑任务释放（见 `10-progression.md`），是 D13 节奏的载体之一。

---

## 6. 参数表（推荐值 + 调参旋钮标记）

| 参数 | 推荐值 | 说明 | 旋钮 |
|---|---|---|---|
| 槽位数 `device_slot_count` | **由该套系 `series_quality` 决定**（核心 §4.1.1 / D4；曲线示意：品质 1 → 3 槽、2 → 4 槽、3 → 5 槽、4 → 6 槽，示意值待定） | 只读 `SeriesDef.device_slot_count` 并冻结；**同一套系内恒定**、跨套系才增长；**决定转化端功率上限** | 🔧（曲线形状） |
| 装置品质档数 | 4（常用 / 稀有 / 史诗 / 神话） | 内容释放刻度，与 `05` 的模块品质对齐 | 🔧 |
| 拆卸返还率 | **50%**（常量） | 核心 D8 定为可拆返还 50%，**不作为旋钮** | — |
| `REDUCE_D_BAR` 汇总上限 | 0.60 | 防止 D̄ 归零导致 ρ 发散（P7 的直接推论） | 🔧 |
| `LOWER_REQUIRED_QUALITY_FLOOR` 上限 | 2 档，且下限 ≥ 1 | 同上 | 🔧 |
| 转化损耗修正下限 | 令损耗不低于 **10%** | 核心 D9 明确"30% 可被降到 10%" | 🔧 |
| `cross_end.bonus_multiplier` | 1.25 | 跨端组合强度；过高会盖过单端决策 | 🔧 |

### 6.1 切片装置清单（切片套系为品质 2 ⇒ 4 槽 ／ 提供 7 件 ⇒ 必然产生"换掉谁"）

| id | 名称 | 归属半边 | 效果（推荐值） | 品质 | 成本（推荐） |
|---|---|---|---|---|---|
| `DEV_C01` | 精简配方 | 消耗侧 | `REDUCE_D_BAR` 0.10 `GLOBAL` | COMMON | 类别 A × 品质 1 × 2 |
| `DEV_C02` | 定向采购 | 消耗侧 | `REDUCE_D_BAR` 0.20 `CATEGORY`（类别 A） | RARE | 类别 A × 品质 1 × 4 ＋ 类别 B × 品质 2 × 1 |
| `DEV_Q01` | 降级验收 | 消耗侧 | `LOWER_REQUIRED_QUALITY_FLOOR` 1 | RARE | 类别 B × 品质 2 × 2 |
| `DEV_L01` | 恒温槽 | 消耗侧 | `REDUCE_CONVERSION_LOSS` 0.15（基准见 `06`） | RARE | 类别 B × 品质 2 × 3 |
| `DEV_B01` | 加压交付 | 奖励侧 | `RAISE_B` +1.0 `GLOBAL`，`stack_group="flat_box"` | COMMON | 类别 A × 品质 1 × 3 |
| `DEV_B02` | 连锁结算 | 奖励侧 | `RAISE_B` +2.0 `GLOBAL`，`stack_group="flat_box"`，条件：任务品质要求 ≥ 2 | EPIC | 类别 A × 品质 3 × 2 ＋ 类别 B × 品质 2 × 2 |
| `DEV_X01` | 闭环伺服 | 奖励侧 | `RAISE_B` +1.0 ＋ `REDUCE_D_BAR` 0.10，`cross_end`：需提升模块 tag ＋ 类别 A 池占比 ≥ 0.20，×1.25 | MYTHIC | 类别 A × 品质 3 × 3（`unlock_flag` 由里程碑释放） |

**两端各 ≥ 2 件 ✅**（消耗侧 4 件、奖励侧 3 件），**跨端组合 1 组 ✅**（`DEV_X01`，另有 `DEV_C02 × 提升模块` 的隐式组合）。

---

## 7. 流程 / 状态机

```
                 equip(def, slot)                  unequip(slot) / replace
   ┌─────────┐ ──────────────────────▶ ┌───────────┐ ──────────────────▶ ┌─────────┐
   │  EMPTY  │                         │ EQUIPPED  │                      │ EMPTY   │
   └─────────┘ ◀────────────────────── └───────────┘ ◀────────────────── └─────────┘
                    拆卸（返还 50%）                    拆卸（返还 50%）
                              replace = unequip + equip（单事务）
```

| 状态 | 含义 | 可执行操作 |
|---|---|---|
| `EMPTY` | 槽位为空 | `equip` |
| `EQUIPPED` | 槽位有装置，效果生效中 | `unequip` / `replace` |

**每次状态迁移后必须触发（P2）：**
1. `07` 重算 D̄ / B / ρ（口径见 `07-economy-rho.md`）；
2. 归因面板刷新——每个装置一条：`装置 C02：−0.18（转化端·降 D̄ 20%）`；
3. 循环面板与任务面板同步（面板规格见 `08-ui-panels.md`）。

**跨端组合条件变化同样要走这条链路：** 模块镶嵌 / 拆卸会改变池子占比，从而可能开关 `cross_end` 加成，因此 `05` 的池子变更也必须触发 `07` 重算（共享求值路径，README §2.2）。装置自身**不订阅**池子事件，只被 `07` 在求值时读取。

---

## 8. 与其它系统的接口

| 方向 | 接口 | 说明 |
|---|---|---|
| → `02-item.md` | `ItemService.consume(instance_ids: Array[String], &"engine")` ／ `ItemService.grant(item_id: StringName, source: Dictionary = {}, instance_id: String = "")` ／ `ItemService.transact(...)` ／ `ItemService.resolve_item_id(category, quality)` | 装配**销毁实例**、拆卸**新建实例**（新 UUID，`source = { kind = &"refund" }`）；**`serial` 不是 `grant` 的参数**（第三位是幂等键 `instance_id`），返还实例的 `serial = 0` 由 02 内部置位；**替换走一次 `transact()`**；返还的 `item_id` 由 `resolve_item_id()` 反查；**实例列表的唯一写入方是 02**，装置只发起请求（README §2.1） |
| → `03-task.md` | `get_modifiers() -> DeviceModifiers` | 提供 `d_bar_reduction` / `b_bonus` / `quality_floor_delta`，任务结算时应用；需求向量结构不在此处 |
| → `06-conversion.md` | `get_loss_reduction_pp() -> float` | 只给修正；**基准损耗率 30% 归 06** |
| → `07-economy-rho.md` | 作为 `state` 的一部分 | 07 读取修正并产出 ρ 与归因；装置**不算 ρ、不算 D̄** |
| ← `05-module-pool.md` | `get_pool_state()`（只读） | 仅用于 `cross_end` 条件判定；装置永不写池子 |
| ← `01-gacha.md` | `SeriesDef.device_slot_count`（**只读**） | 该套系 `series_quality` 对应的装置槽位数（核心 §4.1.1 / D4）。构造 `DeviceLoadout` 时读取并冻结，之后运行时不可变（P7）；**曲线与取值归 01，本文只消费** |
| ← `10-progression.md` | `unlock_flag` 置位 | 决定哪些装置可被装配 |
| → `08-ui-panels.md` | `get_slots()` / `get_modifiers()` | 架上 / 归因面板渲染；08 不另算数值 |

**公开 API（`DeviceService`，autoload）：**

```gdscript
func slot_count() -> int                          # 返回本套系冻结的槽位数（构造时取自 SeriesDef.device_slot_count），非全局常数
func get_loadout(series_id: StringName) -> DeviceLoadout   # [补充] 按套系取用其冻结的槽位配置；理由：槽位数是"每套系常量"，必须能按套系取值
func get_slots() -> Array[DeviceDef]              # 只读副本
func equip_device(def_id: StringName, slot_index: int) -> EquipResult
func unequip_device(slot_index: int) -> RefundResult
func replace_device(def_id: StringName, slot_index: int) -> EquipResult
func get_modifiers() -> DeviceModifiers           # 纯读取，无副作用
```

**铁律：** 槽位数量是**每套系常量**（README §3.4）；`equip_device` 的 `slot_index` 越界即返回失败，**不得**扩容，也不得因越界而"顺带"写入 `SeriesDef`。

**铁律（v0.8 实例化）：**
1. `equip_device` 的**实例销毁必须原子**——全部 `cost` 条目要么全成功，要么实例列表完全不变；
2. `unequip_device` 的返还**必须经 `ItemService.grant` 新建实例**——装置侧**不得**持有任何"原实例引用"，**不得**尝试复用或复原原 `instance_id`，**不得**自行生成 UUID（UUID 生成归 02）；
3. `replace_device` 必须是**一次 `ItemService.transact()` 调用**（02 提供的单次事务原语）——在同一事务内完成"拆卸（新建返还实例）+ 装配（销毁实例）"，**不得用多次 `consume` / `grant` 调用拼装**；任一失败**物品侧事务整体回滚**，包含撤销刚 `grant` 的返还实例（见 §5.3 与 T2）。**空间预检在事务之前**：返还装不下则**整体拒绝**（裁决 17）；
4. `unequip_device` 的**空间预检必须先于任何状态变更**——`Σ(返还实例的 ItemDef.size) > 仓库剩余空间` ⇒ 返回失败并给出可读错误，**槽位不变、原实例不销毁、不创建返还实例**；**禁止先销毁或先 `grant` 再靠回滚补救**（裁决 17）；
5. `get_modifiers()` 等只读接口**不触碰实例列表**。
6. **不承诺跨系统原子性**（裁决 13）：`transact()` **只覆盖物品侧**；装置侧槽位状态不在其中，**不得**要求物品事务覆盖它或让它回滚。

---

## 9. UI 需求

| 面板 / 交互 | 内容 | 依据 |
|---|---|---|
| 架上 · 装置区 | **恒显示该套系 `device_slot_count` 个槽位**（含空槽；切片套系为 4）；空槽不可被"扩展"提示诱导；每槽显示名称、品质、效果摘要、条件状态 | §8.1 架上面板 |
| 装配工作台 | 候选装置列表（已解锁 / 未解锁）、`cost` 向量 vs 持有物品对照与缺口高亮 | P6 / R5 |
| 试算预览 | 装配**前后** ρ 与 D̄ / B 的对比；共用 `EvalService`，不在 UI 层另算 | P6 / README §3.3 |
| 拆卸确认 | 明确列出**返还 50% 的具体物品清单**与**净损失**（R10）；**必须写明"返还的是新实例（收藏编号为空），原实例已在装配时销毁"，不得暗示能取回原来那一个**（§5.3）。**★ 空间不足提示**：返还装不下时按钮置灰 / 前置拦截，并显示**还缺多少空间**与"需要腾出多少"（裁决 17）；**不得**先执行拆卸再报错 | 核心 §3.3 / R10 / 裁决 17 |
| 替换确认（实例向） | 替换 = 拆卸 + 装配，**必须在同一事务内完成**；界面须提示"**物品侧**事务任一步失败则整体回滚，返还的新实例也会被撤销"（**不承诺跨系统原子性**，裁决 13）；**★ 返还空间不足时整体拒绝并给出可读错误**（裁决 17） | 核心 §3.3 / §5.3 |
| 替换提示 | **必须显示"被换下来的是哪件装置、损失多少"**，否则取舍感消失 | 核心 §3.3（同类要求适用于镶嵌界面） |
| 归因面板 | 每装置一条独立贡献；跨端加成单独成条 | P2 |
| 品质释放提示 | 未解锁装置显示"由哪个里程碑释放"，但不预告隐藏概率相关内容 | D13 / 10 |

**不得提供：** 一键最优配置（D12 明确不提供）；任何"+1 槽位"的购买 / 升级入口（P7）。

---

## 10. 测试点与验收标准

| # | 测试 | 断言 |
|---|---|---|
| **T1** ★ | **槽位数每套系常量不变量（同一套系内）** | 对**同一套系**：`loadout.slot_count() == series_def.device_slot_count` 在**任何路径**下都不变——`equip` 越界（`slot_index` = 该套系槽位数 / −1 / 999）必须失败且不扩容；`replace` / `unequip` 不改变槽位数；序列化往返后仍等于 `SeriesDef.device_slot_count`；反射 / 属性遍历确认 `_slot_count` 无可写入口，且不存在 `add_slot()` / `grow_slots()` / `set_slot_count()` / `upgrade_slots()`；`get_slots().size()` 恒等于 `slot_count()` |
| **T1b** ★ | **存档篡改与跨套系** | 存档槽位数组长度与 `SeriesDef.device_slot_count` 不符时（如 4 槽套系被写成 5 项）**必须被拒绝**：丢弃该字段、按 `SeriesDef` 重建该套系 loadout 并记录日志，**不得**采纳篡改值、**不得**因此改写 `SeriesDef`；跨套系：两个 `series_quality` 不同的套系 `slot_count()` 可以不同（这是合法的内容轴），切换套系后取值随对应 `SeriesDef` 正确变化，且任一槽位数都不因切换 / 装配 / 拆卸而改变 |
| **T2** ★ | **拆卸返还 50% 守恒（v0.9：实例化 + 空间预检 + 单事务）** | 装配后物品净变化 = `−Σ cost`；拆卸后 = `+Σ floor(cost × 0.5)`（**守恒口径以全部实例（含邮件）为准**，裁决 12——不得使用"仓库 Σcount == 差值"这类等式）；断言 `refund_total ≤ 0.5 × cost_total` 且 `refund_total > 0.5 × cost_total − \|cost\|`（逐条取整误差 ≤ 1/条）；连做 N 次"装配 → 拆卸"总净损失**线性**于 N、无漂移（**按数量计**——UUID 必然逐次变化，**不得把 UUID 差异算作损失**）。**v0.9 扩展断言：** ① 返还**实例数** == Σ floor(cost × 0.5)（**数量规则不变**）；② 返还实例的 `instance_id` **全部是新的**（与事务前实例列表的 UUID 集合**交集为空**，且新实例之间互不重复）；③ 返还实例 **`serial == 0`** 且 `source == { kind = &"refund" }`——断言的是"**02 内部置位的结果**"，不是调用方传参：**`grant` 不传 `serial`**（签名只有 `item_id` / `source` / `instance_id` 三位），并**必须**有一条"**连续返还两次得到两个不同 `instance_id`、两次都成功**"的断言（守卫幂等键被误写成 `0` 的回归——那会让第二次返还被幂等吞掉）；④ **返还空间不足时拆卸被拒绝**（裁决 17）：把仓库填到放不下返还量 → `unsocket` **返回失败**，`PoolState` 与实例列表**逐项不变**（**不销毁原实例、不创建返还实例**、槽位仍为 `EQUIPPED`）；装置侧**必须做空间预检**并给出可读错误（含"还缺多少空间"），**不得先销毁再发现放不下**——断言"失败路径上实例列表与 `PoolState` 的快照逐项相等"；⑤ **事务原子性**：替换是**一次 `ItemService.transact()`**，构造装配侧失败 → **物品侧**实例列表逐项回到事务前（**含撤销本次已 `grant` 的返还新实例**），数量与 UUID 集合均与事务前完全一致（**只覆盖物品侧，不承诺跨系统原子性**——裁决 13）。①②③④⑤ 与"连做 N 次线性无漂移"合起来构成 v0.9 的 T2 全量断言。返还量与实际操作顺序无关；任何路径不得返还 > 50% |
| T3 | 效果叠加与上限 | 同 `stack_group` 取最大不相加；不同组相加；`REDUCE_D_BAR` 汇总 clamp 至 0.60；品质下限 ≥ 1；`REDUCE_CONVERSION_LOSS` 不得使损耗低于 10%（配合 `06`） |
| T4 | 跨端组合 | 条件不满足 → `bonus_multiplier` 不生效；池占比跨过阈值 → 立即生效并触发 `07` 重算；加成在归因中单独成条（P2） |
| T5 | 数据驱动（R11） | **新增一个 `.tres` 装置、零代码改动**即可出现在候选列表、可装配、效果生效；效果类型只用现有 4 类 |
| T6 | 互斥与条件 | 同 `exclusive_group` 第二件装配失败；`condition` 不满足时效果为 0 但槽位仍被占用；条件恢复后自动生效 |
| T7 | 纯函数 / 确定性 | `get_modifiers()` 对同一 `state` 输出完全一致且无副作用；给定 `(state, series, seed)`，`07` 的 ρ 与归因完全可复现（README §3.1） |

**失败信号（要正视）：**

| 信号 | 含义 | 处理 |
|---|---|---|
| 测试者**从不装配**任何装置 | "引擎"出口在转化端无价值，中心机制半边失效 | 检查效果可见性与教学时序（核心 §11 的 30 min 引入点） |
| 测试者**反复拆卸重装**、表现出懊悔 | 50% 返还太贵，R10 恐惧成立 | 不做全额返还；优先检查"拆卸前损失是否可见" |
| 测试者抱怨"想再装一个但槽位不够" | ⚠️ **这是设计意图，不是 bug**（核心 §13.4） | 若产生的是挫败而非取舍感，说明替换提示缺位或 50% 太高 |
| 归因面板只能看到 ρ 总数 | P2 失败 | 补齐逐装置条目 |
| 跨端组合从未被任何测试者发现 | 组合不可见 | 在归因 / 试算中前置提示，而非加大系数 |

---

## 11. 待定项

| # | 待定项 | 推荐 | 影响 |
|---|---|---|---|
| **D4**（继承核心） | **装置槽位是否随品质同步** | **是**（核心 D4 推荐值）：`device_slot_count` 与 `socket_count` 同曲线同步增长，否则 ρ 的两个因子失衡、转化端过早封顶 | 转化端功率上限；由 `series_quality` 决定（本文 §4 / §6） |
| **04-E** ★（与核心 D3 合并） | **槽位曲线本身**（每档 `series_quality` 的装置槽位数） | 与镶嵌位曲线**同一条曲线**，示意 3 / 4 / 5 / 6 槽 | **必须与核心 D3（镶嵌位曲线）一起做手感测试**：两者共同决定 ρ 上限与 R2 强度，只测其一没有意义；曲线一旦上线极难回改 |
| 04-A | 装置品质档数（4 档）与释放节奏 | 4 档，由里程碑逐步释放 | R11 / D13 的载体之一，需与 `10-progression.md`、`05-module-pool.md` 的模块品质节奏对齐 |
| 04-B | `cross_end.bonus_multiplier` 的强度 | 1.25 | 过高会让"两端各投一点"成为唯一解，压缩核心 §3.2 的二级取舍 |
| 04-C | 是否在切片启用 `exclusive_group` | 切片不启用（字段保留） | 字段已在核心 §14.3 列出，切片先验证机制本身（与"不做模块品质梯度"同一处理原则） |
| 04-D | 拆卸是否需要冷却 / 次数限制 | 不需要 | 单次 50% 净损失已是充分成本；加冷却会放大 R10 恐惧 |
| **04-F** ✅（v0.9 已裁决） | **装配成本的两维需求 `(category, quality)` 与实例的 `item_id` 维度的对应关系** | **已解决（裁决 1 + 裁决 9）**：`(category, quality) → item_id` 的**唯一性由配置校验器强制**（配置期即报错，**不再是"切片下碰巧唯一"的兜底说明**），**反查一律调 02 的 `resolve_item_id(category, quality)`**，04 不得自己构造 id 字符串。**`DeviceCost` 保持两维**（裁决 5），不改为 `item_id` 级 | 已闭环：①实例化冲突有唯一正解；②盲盒产出随机，`item_id` 级要求会让玩家卡在"我需要星尘但只开出晶核"（裁决 5 的理由）；③**事务原语由 02 提供**（裁决 2：`ItemService.transact()` 一次调用，T2 ⑤ 依赖它） |
| **04-G** ✅（v0.9 已裁决） | **返还实例的 `source` 形状与 `serial = 0` 的合法性** | **已解决**：`source` 是**开放字典、`kind` 必填**（核心 v0.9），返还写 `source = { kind = &"refund" }`（可再带 `device_id` / `slot`）；`serial = 0` 由 02 按"非开盒来源"**内部置位**，允许重复 | 原悬空点已由上游补定义。**`serial` 不是 `grant` 的参数**这一条同时是本版最重要 bug 的根因（§5.3）：写进第三位会被当成**幂等键**，第二次返还会被吞掉 |

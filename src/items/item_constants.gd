## 物品系统的全部字符串常量（02-item.md §4.2 / §5.7 / §5.10 / §5.11）。
##
## 存在的理由：这些取值域在文档里是「逐字给出」的，任何拼错都只能在运行时暴露
## （例如把 migrate 写成 migration，会被 grant 拒绝而不是静默降级）。
## 集中一处后，静态检查与单元测试可以直接断言它们。
class_name ItemConstants
extends RefCounted

# ── source.kind 六值域（02-item.md §5.8）────────────────────────────────────────
# 未知 kind 一律拒绝 grant（返回 null，状态不变）。
const KIND_GACHA := &"gacha"      # 开盒产出（主来源）
const KIND_CONVERT := &"convert"  # 类别间转化产出
## **★ v0.19：`refund` 已失去调用方**——拆卸什么都不返还（核心 §15 D8）⇒ 不再有产出它的路径。
## **保留为保留值**（`ALL_KINDS` 与 `ACTIVE_KINDS` 都不动）。
const KIND_REFUND := &"refund"    # （保留值）曾经是"拆卸装置 / 模块的返还"
const KIND_MAIL := &"mail"        # 保留值：系统补偿 / 邮件直投（切片内无调用方）
const KIND_MIGRATE := &"migrate"  # 存档迁移产出（注意不是 migration）
const KIND_UNLOCK := &"unlock"    # 里程碑 / 套系解锁发放

const ALL_KINDS: Array[StringName] = [
	KIND_GACHA, KIND_CONVERT, KIND_REFUND, KIND_MAIL, KIND_MIGRATE, KIND_UNLOCK,
]

# ── 实例位置（02-item.md §4.2 / §5.10）──────────────────────────────────────────
const LOC_WAREHOUSE := &"warehouse"
const LOC_MAIL := &"mail"

# ── 溢出策略（02-item.md §5.10 R-M14）───────────────────────────────────────────
# 空串 = 按 source.kind 推导；只允许收紧、不允许放宽。
const OVERFLOW_DERIVE := &""
const OVERFLOW_MAIL := &"mail"      # 被动产出：装不下 → 进邮件
const OVERFLOW_REJECT := &"reject"  # 主动操作：装不下 → 拒绝整个操作

# 被动产出（放不下进邮件）
const PASSIVE_KINDS: Array[StringName] = [KIND_GACHA, KIND_MIGRATE, KIND_UNLOCK, KIND_MAIL]
# 主动操作（放不下拒绝整个操作）
const ACTIVE_KINDS: Array[StringName] = [KIND_CONVERT, KIND_REFUND]

# ── consume / discard 的出口标签（02-item.md §5.7 R-M9）─────────────────────────
const TAG_FUEL := &"fuel"
## **★ v0.19：`engine` 已失去调用方**——物品不再被"造装置 / 造模块"消耗（核心 §3 / §16.14）。
## **保留为保留值**（不删域：删了会让旧档 / 旧测试无从解释），但**全库不得再有产出它的路径**。
const TAG_ENGINE := &"engine"
const TAG_CONVERT := &"convert"
## ★ v0.20（用户裁决）：**售卖**——把物品卖给系统换**金币**（`ItemService.sell()` 专用）。
## 它是**与"交付任务"并列的独立出口**（核心 §3 的出口表 / `02-item.md` §5.7）。
## **只能由 `sell()` 入口写入**（与 `discard` 同一纪律：别的入口不得冒用这个标签）。
const TAG_SELL := &"sell"
const TAG_DISCARD := &"discard"  # 保留值：只由 discard() 入口写入
const TAG_UNKNOWN := &"unknown"  # 仅为签名兼容保留；真实调用不传即失败

# 允许调用方显式传入的标签（discard / sell 不在内——它们各只能走自己的入口）
const CALLER_TAGS: Array[StringName] = [TAG_FUEL, TAG_ENGINE, TAG_CONVERT]

# ── reason 取值域（02-item.md §5.10 / §5.11）────────────────────────────────────
const REASON_OK := &""
const REASON_BAD_OP := &"bad_op"
const REASON_BAD_TAG := &"bad_tag"
const REASON_MISSING_INSTANCE := &"missing_instance"
const REASON_DUPLICATE_ID := &"duplicate_id"
const REASON_NOT_IN_WAREHOUSE := &"not_in_warehouse"
const REASON_NOT_IN_MAIL := &"not_in_mail"
## ★ v0.20：该物品**不可售**（`ItemDef.sell_gold == 0`）——售卖入口专用
const REASON_NOT_SELLABLE := &"not_sellable"
const REASON_NO_SPACE := &"no_space"  # 空间问题的唯一原因码（transact 与 claim 共用）
## ★ v0.26：**这个盒子在邮件里**——邮件不是"可用持有"，所以不能配置 / 兑现（与物品同一纪律）。
## 专门给盲盒用：物品侧的同一情形用 `not_in_warehouse`，**两者不得混用**（原因码要能指认对象）。
const REASON_BOX_IN_MAIL := &"box_in_mail"

# ── 事务 op 类型（02-item.md §5.11）────────────────────────────────────────────
const OP_GRANT := &"grant"
const OP_CONSUME := &"consume"
const OP_DISCARD := &"discard"
## ★ v0.18 新增第四类：资源（货币类）的加减（02-item.md §4.7 / §5.13）。
## `{ "op": &"currency", "kind": &"gem", "delta": -30 }` —— delta < 0 = 扣除、> 0 = 发放。
const OP_CURRENCY := &"currency"
## ★ v0.20 新增第五类：**售卖**（`ItemService.sell()` 专用）——`{ "op": &"sell", "instance_ids": [...] }`。
## 与 `discard` 同一形状，但**会计入 `sold` 而不是 `discarded`**，且它通常与一条
## `currency(+金币)` op 同处一次事务（"销毁 + 得钱"同生共死，02-item.md §5.14）。
const OP_SELL := &"sell"

const ALL_OPS: Array[StringName] = [OP_GRANT, OP_CONSUME, OP_DISCARD, OP_CURRENCY, OP_SELL]

# 事务 op 的合法键集（逐字；出现其它键或缺少必填键 → bad_op）
const OP_KEYS := {
	OP_GRANT: [&"op", &"item_id", &"source", &"overflow", &"instance_id"],
	OP_CONSUME: [&"op", &"instance_ids", &"tag"],
	OP_DISCARD: [&"op", &"instance_ids"],
	OP_CURRENCY: [&"op", &"kind", &"delta"],
	OP_SELL: [&"op", &"instance_ids"],
}
const OP_REQUIRED_KEYS := {
	OP_GRANT: [&"op", &"item_id"],
	OP_CONSUME: [&"op", &"instance_ids", &"tag"],
	OP_DISCARD: [&"op", &"instance_ids"],
	OP_CURRENCY: [&"op", &"kind", &"delta"],
	OP_SELL: [&"op", &"instance_ids"],
}

# ── 资源（货币类）：切片两种（核心 §4.8 的币种表）────────────────────────────────
## **原石**：消耗点 = ① 开盒（兑现）② 设备升级。
const CURRENCY_GEM := &"gem"
## **金币**：消耗点 = **镶嵌模块**（数额 = 该模块的 `ModuleDef.gold_cost`）。
const CURRENCY_GOLD := &"gold"
const ALL_CURRENCIES: Array[StringName] = [CURRENCY_GEM, CURRENCY_GOLD]

## 资源发放的 `source`（与实例的 `source.kind` 同一纪律：发放不得来路不明）。
const CURRENCY_SOURCE_TASK := &"task"
const CURRENCY_SOURCE_MILESTONE := &"milestone"
const CURRENCY_SOURCE_INIT := &"init"
const ALL_CURRENCY_SOURCES: Array[StringName] = [
	CURRENCY_SOURCE_TASK, CURRENCY_SOURCE_MILESTONE, CURRENCY_SOURCE_INIT,
]

## ★ v0.19：资源不足**统一用这一枚码**（币种由动作决定）——
## 旧名 `gem_insufficient`（v0.18）已更名（核心 §15 D25 / §16.14）。
const REASON_CURRENCY_INSUFFICIENT := &"currency_insufficient"
const REASON_UNKNOWN_CURRENCY := &"unknown_currency"

# ── 开局初始资源（★ v0.18 / v0.19；🔧 切片标定，归核心 D24 / D25）───────────────────
## **新游戏初始化发多少**——**这是"开局初始值"的唯一来源**：
##   · 它必须 **≥ 开第一个盒子所需**（否则第一个盒子开不了 ⇒ 开局死锁）；
##   · 它必须 **≥ 装第一个模块所需**（否则中心机制的第一次体验被闸门挡住）。
## ★ **v5 → v6 迁移的回填值也必须读这里**（`10-progression.md` §7.4 第 11 条）——
##   **不得在两处各写一个数**。
const INIT_GEM := 60   # 原石：够开 2 个品质 2 的盒子（默认单价 30）后再剩一点
const INIT_GOLD := 30  # 金币：够装 1–2 个默认价（20）的模块


# ── 物品品质 `quality`：★ v0.22 —— 6 档（白 / 绿 / 蓝 / 紫 / 金 / 红）────────────
## **这是"物品品质"的唯一档位定义**（`02-item.md` §5.1 / §6）。它与**套系品质
## `series_quality`（1..4，归 01 的 `SeriesDef`）是两条不同的轴**，不得混用：
## 前者是"这一件物品有多好"，后者是"这个盒子的池子有多大 / 位子有几个"。
##
## · 值域 = `QUALITY_MIN..QUALITY_MAX`（**1..6**，序数，越小越差）；
## · 每档有**两个名字**：**颜色名**（白 / 绿 / 蓝 / 紫 / 金 / 红——UI 的第一识别通道）
##   与**档位名**（普通 / 精良 / 稀有 / 史诗 / 传说 / 神话——文案里读得出口）；
## · **颜色只是 UI 常量**（`quality_color()`）：它**不影响任何数值**（`value` / `rarity` /
##   `size` / `sell_gold` 都是各自独立的字段），改色不改平衡；
## · **档数会抬高 `count_index` 的键域上界**（类别数 × 品质数 = 7 × 6 = **42**，
##   `02-item.md` §5.1 R-M2 / §11 M12）⇒ 加档 = 心算负担上升，不是免费的。
const QUALITY_MIN := 1
const QUALITY_MAX := 6
## 颜色名（UI 第一识别通道；下标即档位）
const QUALITY_NAMES := {
	1: "白", 2: "绿", 3: "蓝", 4: "紫", 5: "金", 6: "红",
}
## 档位名（文案 / 日志 / 测试用；与颜色名一一对应）
const QUALITY_TIER_NAMES := {
	1: "普通", 2: "精良", 3: "稀有", 4: "史诗", 5: "传说", 6: "神话",
}
## 品质色（🔧 UI 常量，**可调、不影响平衡**）。1/3/4 沿用旧值，2 由青蓝改绿、5/6 新增。
const QUALITY_COLORS := {
	1: Color("#B9C0C9"),  # 白（灰白，避免纯白与背景互吞）
	2: Color("#4CAF50"),  # 绿
	3: Color("#4FA3E3"),  # 蓝（旧青蓝）
	4: Color("#A66CF2"),  # 紫（旧值）
	5: Color("#F2B01E"),  # 金
	6: Color("#E0453C"),  # 红
}

# ── ★ v0.22：物品内容的**六档数值阶梯**（🔧 全部是示意值，标定只改这一处）───────────
## `value`：几何 ×3（`02-item.md` §6 的价值阶梯）。它是 `M̄ = Σ(pᵢ × vᵢ)` 的唯一输入，
##   改这里等于整体缩放期望 ⇒ 07 的 ρ 主力旋钮之一。
## `size`：仓库占用（核心 D16 示意 1/2/5/10，5–6 档按同精神外推，**待标定**）。
## `rarity`：**权重**（越大越常见）——**★ v0.23：它与品质挂钩，品质越高权重必须越低**
##   （严格单调，由 `ItemCatalog.validate()` 的 **V9** 在加载期强制）。六档默认阶梯
##   60:30:10:5:2:1（🔧 归核心 D19）；生成器按它写内容，标定只改这一行。
## `sell_gold`：售出单价（金币），品质 ×2 的等比（🔧 归核心 D26，与 D25 一起标定）。
## **这些表是"内容生成"的唯一数据源**（`tools/gen_item_content.gd` 读它们写 42 个 `.tres`）；
## 手改 `.tres` 之前先改这里，否则下次重新生成会被覆盖。
const QUALITY_VALUE := {1: 1, 2: 3, 3: 9, 4: 27, 5: 81, 6: 243}
const QUALITY_SIZE := {1: 1, 2: 2, 3: 5, 4: 10, 5: 20, 6: 40}
const QUALITY_RARITY := {1: 60, 2: 30, 3: 10, 4: 5, 5: 2, 6: 1}
const QUALITY_SELL_GOLD := {1: 2, 2: 4, 3: 8, 4: 16, 5: 32, 6: 64}

# ── ★ v0.22：42 个物品的**展示名**（7 类别 × 6 档，下标 0 = 品质 1）──────────────
## 内容（名字）与数值（上面四张表）分开：**改名不动平衡，改数不动名字**。
## `item_id` 的形态固定为 `<category>_q<quality>`（`02-item.md` §4.1 / §5.12 V1 的反查口径）。
const ITEM_NAMES := {
	&"home": [
		"旧木凳", "竹编收纳筐", "铜制水壶", "雕花立柜", "古董屏风", "传世茶案",
	],
	&"art": [
		"素描习作", "石版小画", "青铜胸像", "油画原作", "名匠手作", "失落名画",
	],
	&"tool_material": [
		"生锈铁钉", "木工刨刀", "淬火钢锭", "精密卡尺", "合金工具组", "铭匠锻具",
	],
	&"energy": [
		"干电池", "手摇发电机", "蓄电池组", "动力核心", "高能电池组", "聚变芯体",
	],
	&"medical": [
		"医用绷带", "退烧药片", "手术器械", "特效血清", "自体修复剂", "不灭良方",
	],
	&"information": [
		"便签字条", "手抄笔记", "技术手册", "加密档案", "原始图纸", "失落典籍",
	],
	&"electronic": [
		"电阻元件", "二极管", "集成电路", "微处理器", "量子芯片", "奇点回路",
	],
}


static func is_valid_quality(q: int) -> bool:
	return q >= QUALITY_MIN and q <= QUALITY_MAX


## 颜色名（越界返回空串——调用方应先 `is_valid_quality`，越界是配置错误）。
static func quality_name(q: int) -> String:
	return String(QUALITY_NAMES.get(q, ""))


## 档位名（越界返回空串，同上）。
static func quality_tier_name(q: int) -> String:
	return String(QUALITY_TIER_NAMES.get(q, ""))


## 品质色（越界返回灰色——UI 不得因为一条坏配置而整屏崩掉，但校验器会先拦住它）。
static func quality_color(q: int) -> Color:
	return QUALITY_COLORS.get(q, Color("#808080"))


## 物品展示名（`ITEM_NAMES` 的只读查询）。**未配置的类别 / 档位返回空串**——
## 生成器据此发现"漏配"，测试断言 42 个名字全非空。
static func item_name(category: StringName, q: int) -> String:
	if not ITEM_NAMES.has(category):
		return ""
	var names: Array = ITEM_NAMES[category]
	if q < 1 or q > names.size():
		return ""
	return String(names[q - 1])


## 六档数值阶梯的只读查询（内容生成器用；表缺失返回 -1，让"漏配"立刻暴露）。
static func quality_value(q: int) -> int:
	return int(QUALITY_VALUE.get(q, -1))


static func quality_size(q: int) -> int:
	return int(QUALITY_SIZE.get(q, -1))


static func quality_rarity(q: int) -> int:
	return int(QUALITY_RARITY.get(q, -1))


static func quality_sell_gold(q: int) -> int:
	return int(QUALITY_SELL_GOLD.get(q, -1))


static func is_valid_kind(kind: StringName) -> bool:
	return ALL_KINDS.has(kind)


static func is_passive(kind: StringName) -> bool:
	return PASSIVE_KINDS.has(kind)


## source.kind → 默认溢出策略。未知 kind 返回 &""（调用方应先校验 kind）。
static func derive_overflow(kind: StringName) -> StringName:
	if PASSIVE_KINDS.has(kind):
		return OVERFLOW_MAIL
	if ACTIVE_KINDS.has(kind):
		return OVERFLOW_REJECT
	return &""

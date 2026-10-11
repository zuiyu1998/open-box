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
const TAG_DISCARD := &"discard"  # 保留值：只由 discard() 入口写入
const TAG_UNKNOWN := &"unknown"  # 仅为签名兼容保留；真实调用不传即失败

# 允许调用方显式传入的标签（discard 不在内——它只能走 discard()）
const CALLER_TAGS: Array[StringName] = [TAG_FUEL, TAG_ENGINE, TAG_CONVERT]

# ── reason 取值域（02-item.md §5.10 / §5.11）────────────────────────────────────
const REASON_OK := &""
const REASON_BAD_OP := &"bad_op"
const REASON_BAD_TAG := &"bad_tag"
const REASON_MISSING_INSTANCE := &"missing_instance"
const REASON_DUPLICATE_ID := &"duplicate_id"
const REASON_NOT_IN_WAREHOUSE := &"not_in_warehouse"
const REASON_NOT_IN_MAIL := &"not_in_mail"
const REASON_NO_SPACE := &"no_space"  # 空间问题的唯一原因码（transact 与 claim 共用）

# ── 事务 op 类型（02-item.md §5.11）────────────────────────────────────────────
const OP_GRANT := &"grant"
const OP_CONSUME := &"consume"
const OP_DISCARD := &"discard"
## ★ v0.18 新增第四类：资源（货币类）的加减（02-item.md §4.7 / §5.13）。
## `{ "op": &"currency", "kind": &"gem", "delta": -30 }` —— delta < 0 = 扣除、> 0 = 发放。
const OP_CURRENCY := &"currency"

const ALL_OPS: Array[StringName] = [OP_GRANT, OP_CONSUME, OP_DISCARD, OP_CURRENCY]

# 事务 op 的合法键集（逐字；出现其它键或缺少必填键 → bad_op）
const OP_KEYS := {
	OP_GRANT: [&"op", &"item_id", &"source", &"overflow", &"instance_id"],
	OP_CONSUME: [&"op", &"instance_ids", &"tag"],
	OP_DISCARD: [&"op", &"instance_ids"],
	OP_CURRENCY: [&"op", &"kind", &"delta"],
}
const OP_REQUIRED_KEYS := {
	OP_GRANT: [&"op", &"item_id"],
	OP_CONSUME: [&"op", &"instance_ids", &"tag"],
	OP_DISCARD: [&"op", &"instance_ids"],
	OP_CURRENCY: [&"op", &"kind", &"delta"],
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

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
const KIND_REFUND := &"refund"    # 拆卸装置 / 模块的返还
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

const ALL_OPS: Array[StringName] = [OP_GRANT, OP_CONSUME, OP_DISCARD]

# 事务 op 的合法键集（逐字；出现其它键或缺少必填键 → bad_op）
const OP_KEYS := {
	OP_GRANT: [&"op", &"item_id", &"source", &"overflow", &"instance_id"],
	OP_CONSUME: [&"op", &"instance_ids", &"tag"],
	OP_DISCARD: [&"op", &"instance_ids"],
}
const OP_REQUIRED_KEYS := {
	OP_GRANT: [&"op", &"item_id"],
	OP_CONSUME: [&"op", &"instance_ids", &"tag"],
	OP_DISCARD: [&"op", &"instance_ids"],
}


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

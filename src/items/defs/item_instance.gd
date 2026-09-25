## 物品实例（02-item.md §4.2）。
##
## 玩家实际持有的**一个**物品。**每个实例持有一个 UUID，全局唯一**，兼作幂等键。
## 持有模型就是 `Array[ItemInstance]`——同一 item_id 的多个实例是**互不相同的个体**，
## 永不合并、不堆叠（§5.3：「堆叠」在结构上不可能存在，因为没有可合并的对象）。
class_name ItemInstance
extends Resource

## UUIDv4（36 字符，小写）。由 ItemService.grant 生成，**不由调用方传入**；
## 仅在重放（存档重放 / 日志补发）时经可选参数传入同一个 id 以命中幂等。
@export var instance_id: String = ""

## 指向 ItemDef；category / quality 经 ItemCatalog 查出（不冗余进实例，省约 30 B/实例）
@export var item_id: StringName = &""

## 入库时刻（int(Time.get_unix_time_from_system())，Unix **秒**）。
## 秒级精度意味着一批兑现会产出同秒的多个实例——先后由 instance_id 字典序打破（§5.5）。
@export var acquired_at: int = 0

## 溯源。**开放字典**：kind 必填，其余键按来源类型附加（见 ItemConstants）。
## kind 是**历史事实**（来源），location 是**当前状态**（位置）——
## 产出溢出只写 location，**绝不改写 kind**。
@export var source: Dictionary = {}

## 该玩家开出的第 N 个此物品；**0 = 非开盒来源**（转化 / 返还 / 解锁 / 迁移）。
## 编号不复用、不回收；计数器持久、只增不减（§5.6）。
@export var serial: int = 0

## 所在容器：ItemConstants.LOC_WAREHOUSE / LOC_MAIL（v0.9）。
## **只有 grant（产出落位）与 claim（领取）能改它。**
@export var location: StringName = &"warehouse"


## 序列化。**键序固定**——§4.6 的"往返字节级稳定"依赖它。
func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"item_id": String(item_id),
		"acquired_at": acquired_at,
		"source": source.duplicate(true),
		"serial": serial,
		"location": String(location),
	}


static func from_dict(d: Dictionary) -> ItemInstance:
	var inst := ItemInstance.new()
	inst.instance_id = String(d.get("instance_id", ""))
	inst.item_id = StringName(d.get("item_id", ""))
	inst.acquired_at = int(d.get("acquired_at", 0))
	var src = d.get("source", {})
	inst.source = normalize_source(src) if src is Dictionary else {}
	inst.serial = int(d.get("serial", 0))
	inst.location = StringName(d.get("location", String(ItemConstants.LOC_WAREHOUSE)))
	return inst


## 把"看起来是整数"的 float 还原成 int。
##
## [!] 实现必需：`JSON.parse_string` 把**所有**数字解析成 float，
## 于是 `box_seed: 0` 往返一次就变成 `box_seed: 0.0`——
## 这会让 §4.6 的"往返字节级稳定"当场失败（§10.4 第 1 条就是这么测出来的）。
## 存档格式归 10，但只要它用 JSON，这层还原就必须在这里做。
static func _normalize_dynamic(v):
	if v is float:
		var f: float = v
		# 只还原整数值，且避开超出 int64 精度的量级
		if f == floor(f) and absf(f) < 9.0e15:
			return int(f)
	return v


## `source` 是**开放字典**，故逐值还原而非逐键硬编码——
## 这样"以后给某类来源加一个整数键"不必改这里（§4.2 的开放字典设计）。
static func normalize_source(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src.keys():
		out[k] = _normalize_dynamic(src[k])
	return out


## 深拷贝（事务预演用；正式生效前不得改动真实实例）。
func clone() -> ItemInstance:
	return ItemInstance.from_dict(to_dict())


func kind() -> StringName:
	return source.get("kind", &"")


func is_in_warehouse() -> bool:
	return location == ItemConstants.LOC_WAREHOUSE


func is_in_mail() -> bool:
	return location == ItemConstants.LOC_MAIL

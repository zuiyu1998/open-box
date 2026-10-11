## 装置（运行态）——玩家**实际持有的那一台**（04-device.md §4）。
##
## ★ **本体只有两个字段**：指向定义的 `device_id` + 当前 `level`。
##   **没有耐久 / 绑定 / 使用计数 / 槽位**（核心 §15 D21：不消耗、不损耗、不绑定盒子、
##   不限制次数、不可离开玩家）⇒ `devices` 只增不减、"持有 0 台"在规则上不可达。
##
## ★ 区分：`DeviceDef` 是**蓝图**（内容配置），`Device` 是**实例**（运行态 + 落盘）。
##   与 `ModuleDef` / `Module` 同一分法。
##
## ★ **落盘归 10**：存档条目形态 = `{ "id": <device_id>, "level": <level> }`
##   （`10-progression.md` §7.4 第 11 条，v5 → v6 迁移里旧字符串条目回填 `level = 1`）。
class_name Device
extends RefCounted

var device_id: StringName = &""
var level: int = 1


static func make(device_id: StringName, level: int = 1) -> Device:
	var d := Device.new()
	d.device_id = device_id
	d.level = maxi(level, 1)
	return d


func to_dict() -> Dictionary:
	return {"id": String(device_id), "level": level}


## `[补充]` 本方法**不做"缺键补 level"**：等级是玩家进度，回填属于**迁移**（归 10），
## 不是解析期的宽容默认。缺键 ⇒ 返回 null，由载入层报错拒绝（不得静默当 1 级）。
static func from_dict(d: Dictionary) -> Device:
	if not d.has("id") or not d.has("level"):
		return null
	var id := StringName(d["id"])
	if id == &"":
		return null
	var lv := int(d["level"])
	if lv < 1:
		return null
	return Device.make(id, lv)


## 两个字段相等即视为同一状态（测试与快照比对用）。
func equals_state(other: Device) -> bool:
	return (
		other != null
		and other.device_id == device_id
		and other.level == level
	)

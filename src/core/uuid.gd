## UUIDv4 生成器（02-item.md §4.5）。
##
## Godot **没有**内置 UUID：ResourceUID.create_id() 返回 int64 的 uid:// 串，
## **不是 UUID**，也不符合本项目的幂等键需求。因此必须自己实现。
##
## 三条硬约束（§4.5 实现要点）：
##   1. 随机源必须是 Crypto（OS CSPRNG），且只持有一个静态实例；
##      version / variant 两位必须手工设置，否则字节流只是"看起来像 UUID"。
##   2. 格式 8-4-4-4-12、32 位**小写**十六进制——比较一律按小写，
##      大小写不统一会让同一个 id 出现两种写法，幂等键当场失效。
##   3. **禁止** randi() / RandomNumberGenerator / 任何可复现种子流。
##      池子与保底用的是"给定 seed 完全可复现"的随机流，实例身份必须与它**无关**；
##      否则同一次重放会产出同一个 UUID，幂等键立刻失去意义（§10.1 第 3 条）。
class_name Uuid
extends RefCounted

static var _crypto := Crypto.new()


## 返回一个 36 字符的小写 UUIDv4 字符串。
static func v4() -> String:
	var b: PackedByteArray = _crypto.generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40  # version = 4（第 7 字节高 4 位 = 0100）
	b[8] = (b[8] & 0x3F) | 0x80  # variant = RFC 4122（第 9 字节高 2 位 = 10）
	var h := b.hex_encode()      # 32 个小写十六进制字符
	return "%s-%s-%s-%s-%s" % [
		h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12),
	]


## 校验一个字符串是否是本生成器产出形态的 UUIDv4（§10.1 第 2 条）。
static func is_valid(s: String) -> bool:
	if s.length() != 36:
		return false
	if s != s.to_lower():
		return false
	var hex_only := s.replace("-", "")
	if hex_only.length() != 32:
		return false
	for i in hex_only.length():
		var c := hex_only[i]
		var ok := (c >= "0" and c <= "9") or (c >= "a" and c <= "f")
		if not ok:
			return false
	if s[8] != "-" or s[13] != "-" or s[18] != "-" or s[23] != "-":
		return false
	# version nibble == 4
	if s[14] != "4":
		return false
	# variant 高 2 位 == 10b → 首字符落在 8 / 9 / a / b
	var v := s[19]
	if v != "8" and v != "9" and v != "a" and v != "b":
		return false
	return true

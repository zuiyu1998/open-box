## UUID 生成（02-item.md §4.5）。
##
## ★ v0.24 / v0.25（用户裁决）：**改用已安装的插件**
## `addons/minos_uuid_generator`（`minos-UUID-generator-for-godot` by Minoqi，MIT；
## 全局类 `MinosUUIDGenerator`）——id 的**布局与熵全部由插件产出**，本项目不再自己
## 拼字节、不再自己设置 version / variant 位、也不再自己格式化。
##
## ★ **形态变了，必须知道**：插件产出 **`8-4-4-12`（31 字符、3 个 `-`、小写字母数字
##   `a–z0–9`，即 base36）**，**不是 RFC 4122 的 UUIDv4**（没有 version nibble `4`、
##   也没有 variant `10` 位，而且**不是十六进制**）。
##   方法名仍叫 `v4()`，只是为了不让 01/02/10 的调用点与存档字段名跟着改；
##   **形状的唯一权威是插件的 `MinosUUIDGenerator.generate_new_UUID()`**。
##
## 两个代价（已登记，不许"忘了就没事"）：
##   1. **熵来自全局 `randi()` 流**（插件内部用 `Array.pick_random()`）⇒ 若任何代码对
##      **全局** RNG 调 `seed()`，同一段重放会产出同一串 id，幂等键就会把"新实例"
##      误判成"重放"而静默丢弃。**因此全库禁止对全局 RNG `seed()`**——v0.24 曾用一条
##      测试守着"seed 两次仍不同"，v0.25 起它守不住了（插件不给熵入口），只能靠纪律
##      （`02-item.md` §10.1 已把这条降级为"已知限制"）。
##   2. 插件把生成过的 id 记在**静态** `usedUUID` 数组里（进程内去重）。它随进程增长、
##      不落盘；**存档读回的老 id 不在其中**，所以跨档的唯一性仍只靠随机性（约 112 bit）。
class_name IUuid
extends RefCounted

## 插件默认把每条新 id `print` 出来——本项目在 `grant` 路径上批量生成，
## 必须一次性关掉它的调试输出（否则 2 万条用例会刷屏）。
static var _silenced := false


## 返回一个插件产出的 id 字符串（`8-4-4-12`，小写字母数字 base36）。
static func v4() -> String:
	_silence_plugin_debug()
	return MinosUUIDGenerator.generate_new_UUID()


## 校验一个字符串是否是本生成器产出形态（§10.1 第 2 条）。
## 插件只负责"生产"，**读档 / 测试仍需要一个形态校验**（坏 id 进档 = 幂等键失效），
## 所以这条留在本文件；它只描述契约，不参与生成。
static func is_valid(s: String) -> bool:
	if s.length() != 31:
		return false
	if s != s.to_lower():
		return false
	var parts := s.split("-")
	if parts.size() != 4:
		return false
	if parts[0].length() != 8 or parts[1].length() != 4 \
			or parts[2].length() != 4 or parts[3].length() != 12:
		return false
	for p in parts:
		for i in String(p).length():
			var c := String(p)[i]
			# 插件用的是 a–z0–9（base36），**不是十六进制**——别按 hex 收紧它
			var ok := (c >= "0" and c <= "9") or (c >= "a" and c <= "z")
			if not ok:
				return false
	return true


static func _silence_plugin_debug() -> void:
	if _silenced:
		return
	_silenced = true
	MinosUUIDGenerator.printNewUUID = false
	MinosUUIDGenerator.printNewUUIDNode = false
	MinosUUIDGenerator.printSuccessfulRemoval = false
	MinosUUIDGenerator.printFailedRemoval = false

## 本局会话容器（★ v0.28；归流程管理系统的"会话生命周期"这一半）。
##
## **它只回答一件事：这一局的状态对象是哪个。** 不读档、不写档、不解释存档格式——
## 建档 / 读档的规则归 10（`10-progression.md`）；本类只**持有**那一份 `GameState`，
## 让"切换场景之后，新场景还拿得到这一局"这件事成立。
##
## 为什么要它（而不是让每个场景自己 `new_game()`）：
##   · **一局只能有一个 `GameState`**——两个场景各建一份，玩家的物品 / 盒子就分家了；
##   · `FlowService` **不持有游戏数据**（11-flow.md §2 的边界）；把"状态"塞进流程状态机会
##     让"我在哪个节点"和"我这局有什么"混成一份数据。
##   · 所以：**流程管"在哪"，会话管"这一局是谁"**，两者都不解释存档。
##
## ★ 本版（10 未实现）的能力边界：
##   · `start_new_game()` —— 走 `GameState.new_game()`（**开局 = 设备 + 原石 + 金币**，v0.18 口径）；
##   · `has_save()` / `load()` —— **占位**：返回 `false` / 失败。**读档归 10**，接上时只改这两个方法。
extends Node

## 这一局的运行时状态（null = 还没有局）。
var state: GameState = null


func has_session() -> bool:
	return state != null


## 开一局新游戏（覆盖旧的一局）。**由"新游戏"按钮 / 测试调用**，只此一处。
func start_new_game() -> GameState:
	state = GameState.new_game()
	return state


## 是否存在可继续的存档。★ **占位实现**：存档层（10）未落地 ⇒ 恒为 false。
func has_save() -> bool:
	return false


## 读档并成为当前这一局。★ **占位实现**：返回 false（读档归 10）。
func load() -> bool:
	return false


## 结束这一局（回菜单时可选调用）。
func clear() -> void:
	state = null

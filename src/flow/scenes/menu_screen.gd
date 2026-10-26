## 游戏菜单（★ v0.27；流程节点 `menu` 的**功能骨架**）。
##
## **长什么样归 08**（`08-ui-panels.md`：面板布局与文案属呈现层）；这里只钉死**四件事**——
## 游戏名称 + 四个按钮（**新游戏 / 继续 / 设置 / 存档**）与它们**各自走哪条路**：
##
##   · **新游戏** → `FlowService.transition(game)`（"新档"由 10 在建档时决定，本层不判；
##     `11-flow.md` F2 的口径：菜单→游戏只有一条边，**不把"新档 / 继续"建进状态机**）
##   · **继续**   → 同一条边（`game`）；"有没有档可继续"由 10 提供，本层只负责请求
##   · **设置**   → `FlowService.open_settings()`（记住来源 = 菜单，关掉回菜单）
##   · **存档**   → **发出 `save_requested` 信号**，由 10 接（本系统不碰存档：不读、不写）
##
## 纪律：本脚本**不得**直接 `change_scene_to_file`（换场景只有 `FlowService.apply_scene()` 一处）；
## 也不得读写 `GameState` / `ItemService`（11-flow.md §2 的边界）。
extends Control

## 「存档」按钮被按下。**10 订阅它**（S/F2：存档 UI 与档位判断都不在 11）。
signal save_requested
## 「继续」按钮被按下且**没有档可继续**时发出（由 10 决定可继续性；本层只转发结果）。
signal continue_unavailable

const TITLE_TEXT := "Open Box"

@onready var _title: Label = $Title
@onready var _btn_new: Button = $Buttons/NewGame
@onready var _btn_continue: Button = $Buttons/Continue
@onready var _btn_settings: Button = $Buttons/Settings
@onready var _btn_save: Button = $Buttons/Save


func _ready() -> void:
	_title.text = TITLE_TEXT
	_btn_new.pressed.connect(_on_new_game)
	_btn_continue.pressed.connect(_on_continue)
	_btn_settings.pressed.connect(_on_settings)
	_btn_save.pressed.connect(_on_save)
	refresh()


## 由 10 在"档位是否有可继续"变化后调用（本层不自己查档）。
func refresh(has_save: bool = true) -> void:
	_btn_continue.disabled = not has_save
	_btn_save.disabled = false


func _on_new_game() -> void:
	# ★ v0.28：**开一局**（`GameState.new_game()`）由会话容器代持，然后进游戏场景；
	#   游戏场景在 `_ready()` 里从 `GameSession` 取这一局 —— 一局只能有一个 GameState。
	GameSession.start_new_game()
	FlowService.transition(FlowService.NODE_GAME)


func _on_continue() -> void:
	if _btn_continue.disabled:
		continue_unavailable.emit()
		return
	# ★ v0.28：读档归 10（`GameSession.load()` 目前是占位 false）⇒ 没档就明确拒绝，不装作能继续
	if not GameSession.load():
		continue_unavailable.emit()
		return
	FlowService.transition(FlowService.NODE_GAME)


func _on_settings() -> void:
	FlowService.open_settings()


func _on_save() -> void:
	save_requested.emit()

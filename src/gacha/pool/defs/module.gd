## 一个**已镶嵌模块的实例**（01-gacha.md §4.3）。
##
## ★ 挂在 `Box.modules` 上、**不在 `ItemPool` 里**、**不含 `slot`**——
##   **槽位 = 它在定长数组里的下标**，全仓库不存在第二份副本。
##
## ★ 模块是**消耗品**：拆卸 = 把该位置空 + 只返还 50% 材料；兑现 = 随盒消失；
##   **不存在"模块库存"**（本系统不提供任何"模块仓库 / 回收再用"接口）。
##   理由：若本体可回收再用，同一个模块就能在多个盒子上轮流使用 ⇒ D17 被归零，
##   P7 改写后唯一的跨池锚点随之消失。
class_name Module
extends Resource

@export var module_id: StringName = &""   # 指向 ModuleDef（编辑规则蓝图）
@export var quality: int = 1              # 模块品质梯度（D13；制造时从 ModuleDef 复制）
@export var socketed_at: int = 0          # [补充] 镶嵌时刻（tick），供排序与回放；**不参与求值**


static func make(p_module_id: StringName, p_quality: int, p_socketed_at: int) -> Module:
	var m := Module.new()
	m.module_id = p_module_id
	m.quality = p_quality
	m.socketed_at = p_socketed_at
	return m


func clone() -> Module:
	return Module.make(module_id, quality, socketed_at)

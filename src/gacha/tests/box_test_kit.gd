## 测试用造盒工具（★ v0.61：套系删除后，测试不再能"注册一个套系再发盒"）。
##
## 为什么单独一份：几乎所有测试都需要"一个池子内容确定、位子/寿命确定的盒子"，
## 而**确定性**正是断言的前提（第 i 件物品的概率、顺序、寿命扣减都依赖它）。
## 用 `grant_random_box()` 会打乱顺序 ⇒ 断言会"看起来绿、其实没测到东西"。
class_name BoxTestKit
extends RefCounted


## 造一个盒子（不发给玩家）：物品顺序 = 传入顺序。
static func make(
	quality: int,
	items: Array[ItemDef],
	socket_count: int = -1,
	uses: int = -1,
	gem_cost: int = -1
) -> Box:
	return Box.make(quality, items, socket_count, uses, gem_cost)


## 造 `count` 个盒子并发给 `state`（每个盒子池子相同、顺序相同）。
static func grant(
	state: GameState,
	count: int,
	quality: int,
	items: Array[ItemDef],
	socket_count: int = -1,
	uses: int = -1,
	source: StringName = &"test"
) -> Array[Box]:
	var out: Array[Box] = []
	for _i in maxi(count, 0):
		var b := make(quality, items, socket_count, uses)
		if b == null:
			break
		b.source = source
		GachaService.grant_box(state, b)
		out.append(b)
	return out

## ★ v0.77：**给仓库发模块实物**（镶嵌要消耗一件）。
##
## `ids` 为空 ⇒ 把当前注册表里的**每个模块各发 1 件**（多数夹具的意图）。
## 会先确保"模块已物品化"（`GachaCatalog.materialize_module_items()`），
## 因为夹具常常在 `_ready` 之后才 `register_module()`。
static func grant_modules(state: GameState, ids: Array = []) -> void:
	if state == null:
		return
	GachaCatalog.materialize_module_items()
	var list: Array = ids if not ids.is_empty() else GachaCatalog.all_module_ids()
	for raw in list:
		var mid := StringName(raw)
		ItemService.grant(mid, {"kind": ItemConstants.KIND_UNLOCK})
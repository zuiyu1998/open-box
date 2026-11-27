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

## 整数万分比（bp）的**唯一分配实现**（01-gacha.md §5.2 / 07-economy-rho.md §5.1）。
##
## 为什么必须只有一处：`Σ weights_bp + void_mass_bp == 10000`（C1 的整数零和等式）
## 要求每一次"重新分配权重"都精确落回目标总量。若 01 与 07 各写一份取整逻辑，
## 两处会在舍入上分家 —— 那正是文档反复禁止的"第二个事实来源"。
##
## 规则（与 `ItemPool.compute_weights_bp()` 同一套）：
##   按 `basis` 的比例取整分配，再用**最大余数法**补齐差额；
##   余数相同时取 `order` 中下标靠前者 ⇒ 结果**确定、可复现**。
class_name BpAlloc
extends RefCounted


## 把 `members` 的权重按 `basis` 的比例重新分配，使其合计**精确等于** `target_total`。
##
## · `w`      —— 当前权重（`id -> bp`），**不被改动**；
## · `members`—— 参与分配的项（通常是"仍可产出"的物品）；
## · `basis`  —— 比例依据（基础权重，或当前权重）；
## · `order`  —— 确定性的并列打破顺序（通常是池子的固定物品序）；
## · 不在 `members` 里的键一律归 0（例如被排除的物品）。
##
## 返回新的 `id -> bp` 字典。**basis 为 0 的项不参与补差额**——
## 否则一个被排除的项可能因为"余数并列、下标靠前"而拿到 +1 bp、重新变得可产出。
static func allocate(
	w: Dictionary,
	members: Array,
	basis: Dictionary,
	order: Array,
	target_total: int
) -> Dictionary:
	var out: Dictionary = {}
	for k in w.keys():
		out[k] = int(w[k])

	if members.is_empty() or target_total <= 0:
		for id in members:
			out[id] = 0
		return out

	var basis_sum := 0
	for id in members:
		basis_sum += int(basis.get(id, 0))

	if basis_sum <= 0:
		# 没有可用的比例依据 ⇒ 均分，但**仍要精确**（差额按下标靠前补齐）
		var each := target_total / members.size()
		var left := target_total - each * members.size()
		for j in members.size():
			out[members[j]] = each + (1 if j < left else 0)
		return out

	var remainders: Array = []
	var allocated := 0
	for id in members:
		var b_i := int(basis.get(id, 0))
		var exact := float(target_total) * float(b_i) / float(basis_sum)
		var f := int(floor(exact))
		out[id] = f
		allocated += f
		if b_i > 0:
			remainders.append([exact - float(f), order.find(id), id])

	var member_set := {}
	for id in members:
		member_set[id] = true
	for k in out.keys():
		if not member_set.has(k):
			out[k] = 0

	remainders.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var deficit := target_total - allocated
	var idx := 0
	while deficit > 0 and idx < remainders.size():
		var id = remainders[idx][2]
		out[id] = int(out[id]) + 1
		deficit -= 1
		idx += 1
	return out


static func sum_of(w: Dictionary) -> int:
	var t := 0
	for v in w.values():
		t += int(v)
	return t

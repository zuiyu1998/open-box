## 物品定义（02-item.md §4.1）。
##
## 一种物品的**静态属性**。归属本系统（02）；01 的 SeriesDef 只**引用**它，不定义它。
##
## v0.7 术语合并后，「物资」与「款」已统一为「物品」——**池中的物品就是你得到的物品**，
## 因此本类**没有任何产出映射字段**（yield_material_id / yield_amount 已删除）。
##
## v0.9 新增 `size`：**不是容量字段**，而是定义级常量（同种物品大小相同）；
## 容量在仓库上、不在物品定义上。所以这**不是** v0.6 已删除的"堆叠上限 / 背包格"从后门回来。
@tool
class_name ItemDef
extends Resource

@export var item_id: StringName = &""       # 唯一 id，推荐 = "<category>_<quality>"
@export var display_name: String = ""       # 展示名，如"星尘·精良"
@export var category: StringName = &""      # 类别，指向 ItemCategoryDef.category_id
## 物品品质 `quality`（≠ 套系品质 `series_quality`）。★ v0.22：**6 档**——
## 白 1 / 绿 2 / 蓝 3 / 紫 4 / 金 5 / 红 6（`ItemConstants.QUALITY_*`，02-item.md §5.1）。
## 越界由校验器 **V8** 拦下（`ItemCatalog.validate()`），不是靠 `@export_range`（它只约束检查器）。
@export_range(1, 6) var quality: int = 1
@export var value: int = 1                  # 该物品的 TVU 价值 v（本系统定义，07 使用）
@export var size: int = 1                   # 占仓库多少空间；必须 > 0（§5.12 V2）
@export_range(1, 100000) var rarity: int = 10
## ★ `rarity` 是**权重**，不是「稀有等级」：**数值越大越常见**。
## 物品池的产生概率由它归一化而来（`ItemPool.compute_probabilities()`）：
##   p_i = rarity_i / Σ rarity——**全部物品共分 100%**（v0.13 起隐藏款已删除）。
## 所以「越稀有的物品」应当把 `rarity` 写得**越小**。必须 ≥ 1：`rarity == 0` 的物品
## 出率为 0（永不产出），那是配置错误而不是设计意图。
## ★ v0.23（用户裁决）：**权重与品质挂钩——同一类别内，品质越高权重必须越低**。
## 这条由校验器 **V9** 在加载期强制（严格单调）；`ItemConstants.QUALITY_RARITY` 给出
## 六档的默认阶梯，生成器按它写内容。**"品质高反而更容易出"是配置错误，不是风格选择**。
@export var icon: Texture2D                 # 面板 / 条目图标
@export var tags: Array[StringName] = []    # 预留：场景约束 / 特殊需求标记（见 03）

## ★ v0.20（用户裁决）：**售出价格（单位：金币）**——把这件物品卖成金币时**每件**能换到多少。
##
## · **单位是金币 `gold`**（不是物品价值 `value`、也不是原石）：`value` 是 TVU 的账面价值（07 用它算 `M̄`、
##   **与售卖无关**），`sell_gold` 是**兑换口径**——两者**互不换算**（别把 `value` 当价格用）。
## · **`0` = 不可售**（不是"免费送"）：卖出入口必须对它报 `not_sellable`。
## · **售卖是一条独立的物品出口**（与"交付任务"并列）：`ItemService.sell()` 一次事务里
##   **销毁仓库实例 + 按本字段发放金币**（原子；`02-item.md` §5.7 / §5.14）。
## · **标定归核心 D26**（🔧）：它是"金币供给"的第二条来源（第一条是任务奖励），
##   ⇒ 售价定高了会把 v0.19 的金币闸门（D25）冲垮，必须与 `ModuleDef.gold_cost` 一起测。
@export_range(0, 999999, 1) var sell_gold: int = 0


## 派生索引键。它只是索引键，**不是持有量的身份**（身份已由 instance_id 承担）。
func count_key() -> String:
	return "%s:%d" % [category, quality]


static func make_count_key(p_category: StringName, p_quality: int) -> String:
	return "%s:%d" % [p_category, p_quality]

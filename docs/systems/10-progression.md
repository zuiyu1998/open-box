# 10 · 收集与进度系统

- 上游：`../core-design.md` **v0.13（去除隐藏款）** ／ `README.md`
- 依赖系统：07 数值与期望（ρ 区间判定，只读）、01 盲盒（抽取结果、未拥有物品权重、**囤积清单 `pending_boxes` 与 `Box`**）、03 任务（里程碑任务的需求与奖励结算）、05 模块与池子（**`Box.item_pool` / `Box.modules` 的逐盒重建入口**，v0.10）、02 物品（类别定义、**物品实例列表与 `serial_counters` 的写入方**、`location` 与仓库容量占用的**写入方**）
- 被依赖：01（「未拥有物品」判定）、05（模块品质产出权限）、02 / 06（物品类别开关）、03（里程碑可见性）、08（图鉴与套系进度呈现、**仓库占用与邮件抽屉**）

> **v0.14 同步（盲盒添加使用次数）——本系统的改动全在存档侧与 T 系列断言上。**
> **核心 v0.14 给盒子加了 `Box.uses_remaining: int`——它是该盒的"总寿命预算"**（**每盒可变**，不是套系常量）：**发放时按该盒所属套系品质初始化——品质 1→10、2→15、3→20、4→25**（存活范围 **10–25**）。★ **别与位数混**：**镶嵌位数仍是 2/3/4/5**（随套系品质，核心 §4.1.1）——**预算远大于位数**（用户口径："盲盒的使用次数**远远超过**镶嵌的次数"）⇒ **装满镶嵌位烧不光预算**。四条口径（逐条照此）：①**两个消耗点、共用同一计数器、各 −1**：**镶嵌一个模块**、**兑现一次**——**没有第三个消耗点**；②**归零 ⇒ 盒子立即被摧毁**（连同 `item_pool` / `modules`）——**不再有"用尽才消耗盒子"这种缓冲语义，归零就是消失**；③**"次数归零即摧毁"仍成立，哪怕从未兑现**——可由"**镶嵌 + 兑现累计到 0**"触发（**不是**靠装满位子），玩家必须自己数着剩余次数；④**模块在盒子被摧毁前一直挂在该盒上**（"留到用完" → "**留到盒子被摧毁**"），**两次消耗之间可继续编辑池子**。抽取侧连带口径不变：**`pool_snapshot` 每次抽取各一份**、**`draw_index` 每次抽取 +1**。**本系统的改动集中在存档侧与 T 系列断言上**，共三处：
> ① **`pending_boxes` 的盒子条目由四个字段变五个字段**：`box_id` / `series_id` / `item_pool` / `modules` / **`uses_remaining`**（§1 第 5 条 / §2 / §4 / §4.1 / §5 第 17 条 / §8.2 / T21 同步；**v0.10 的"四个字段"口径一律作废**）；
> ② **`uses_remaining` 随盒子落盘**——它是**输入（且可变）**，**不是派生值**：**键存在时，重放 / 读档 / 迁移一律读回原值、不得重算、不得按品质补满**（与 `box_id` 的"**稳定性来自持久化**"同一纪律）；**迁移 / 载入为缺键的老盒子按品质补齐初始预算（品质 1–4 ⇒ 10/15/20/25）；只有缺键才补，键存在时用存档值、哪怕它是 `0`**（已裁决，见 §7.4 第 8 条与 §11 **Q19**）（§4 / §5 第 17 条 / §7.4 / T21 / T23）；
> ③ **"随盒子一同消失"改口径**：盒子**归零即被摧毁**（**"次数归零即摧毁"哪怕从未兑现**——由"镶嵌 + 兑现累计到 0"触发）——`uses_remaining == 0` ⇒ 连同 `box_id` / `item_pool` / `modules` 一起消失；**被摧毁前模块一直在**（§4 / §5 第 17 条）。
> **不变**：schema 仍为 **v5**（**只加一个盒子字段、不改块的形状，因此不递增版本号、不新增迁移步骤**——§7.4 第 8 条）；两处派生值纪律（池子当前状态不入档、`revision` 随盒子落盘）、里程碑链、品质解锁、进度节奏、五条红线、`collected` 裁决、物品实例部分、`item_pool` 落盘子集五项**一律未改**。

> **v0.13 同步（去除隐藏款）——本系统的改动集中在"完成度口径"与"存档示例"两处。**
> 上游删除了隐藏款（核心 §5.4 / §16.8）：每个套系**不再有 1 个隐藏物品**、**全部物品共分 100%**、红线 **C3 作废**（**行号保留、不重编号**），`ItemDef.is_hidden` / `ItemPool.hidden_item` / `HIDDEN_TOTAL_BP` 已一并删除。共四处：
> ① **套系完成度不再分列**：`series_progress` 由"常规 `collected_normal / regular_count` + 隐藏 `0 或 1`"改为**一个数字** `collected / regular_count`（§1 第 2 条 / §5 第 3 条 / §9）；`gap_count` = **未收录物品数**（§5 第 2 条）。
> ② **`NORMAL_COMPLETE` 与 `full_collection_reached` 从此同义**（池中全部是常规物品）——**状态机与章节结构一律保留**，只是两者的判据指同一件事（§5 第 6 条 / §7.3）。
> ③ **§4.1 的存档示例重算**（`s01_hidden: 200` 删除，8 个物品的 `weights_bp` 合计**恰好 10000**，示例旁给出整数算术）；**§11 Q17 改述为 v0.13 实况**——不再有"无法被编辑影响"的那一款，残留风险 = "**抬缺口很贵**"，实测目标改为"**达到可接受出率所需的物品成本**"。**不变**：C1 / C2 / C4 / C6、`void`、无保底、池子逐盒一份、`weights_bp` 与 ρ 公式。

> **v0.11 同步（去除保底系统）**：上游删除了保底（核心 §4.1 / §5.4 / §5.6 / §16.6），本系统受影响的**只有存档侧**：① **删除保底计数器**（`pity_counters` / `pity_counter` **不再存在、不入档**，§4.1 / §4.2 / §5 第 19 条）：抽取因此**无状态**——`roll(evaluation, seed)`（**没有 `pity_counter` 入参**），一次抽取的概率**就是**公布的分布；**本版没有因保底而产生的迁移步骤**（v4 的 `pity_counter` **一律丢弃**、不建新块，§7.4 第 5 条；v0.10 老 v5 档若带该块则**读档忽略、下次写档消失**，§4.1）；
> ② **`collected` 与图鉴一律保留**（收藏口径与保底无关，**裁决 11 继续有效**）——**不要误删**；`void` 不推进任何计数器。**代价登记**：全收集尾部**不再有任何保证**（核心 **R15** / **D18**）⇒ **§11 Q17**——**v0.13 起本项已大幅缓解**（隐藏款删除后每一款都受编辑影响，见文首 v0.13 说明与 §11 Q17）；**禁令**：本系统**不得**以任何"隐式必出 / 暗改概率"的方式缓解尾部（P1）。

> **v0.10 同步（池子随盒子走 → **存档 schema 升到 5**）**：上游把池子从"套系的共享状态"改为"**盒子的属性**"（核心 §4.1.2 / §16.5）——**`Box` 下面挂着两个并列字段**：**`item_pool`（物品池，生成数据的凭证）** 与 **`modules`（模块列表，镶嵌在该盒上、唯一作用就是更改 `item_pool` 的状态）**；模块**镶嵌进具体盒子并锁定在那里**；兑现时机从"等池子编好再开"改为"**给哪些盒子配置好了，就先开哪些**"。本系统受影响的**全在存档侧**：**schema 升到 5**（**`Box` 的字段全部入档**——v0.10 当时是四个，**v0.14 起是五个**，见文首 v0.14 说明；旧的"每套系一份 `pools` 块"在 v5 中**不再存在**）；**持久化形态照上游澄清落地**（§4：存 **`item_pool` 落盘子集五项** + `modules` 稀疏序列；**池子的"当前状态"（`weights_bp` / `void_mass_bp` / `probs`）是派生值、一个字段都不入档**，载入后由 `PoolService` **逐盒重建**）；**新增 v4 → v5 迁移规则**（§7.4：v4 的套系施工台 `socketed` **不落到任何盒子**，**一律丢弃、不折算成物品、不产生任何补偿**，逐盒签发 `box_id`、回填 `item_pool` 与空 `modules`）。
> （~~保底计数归套系、不随盒子走~~——该结论随 v0.11 删除保底而整体作废，见文首 v0.11 说明。P7 已改写见核心 §7 / D17；`box_id` 已裁决为「加」见 §11 Q13。）
> **里程碑链、品质解锁、进度节奏、五条红线、`collected` 裁决、物品实例部分一律未改**（C1 / C2 / **C3【v0.13 作废】** / C6 与 `void` 自限本来就是**单池**约束，池子随盒子走不触及它们；**C3 的作废由隐藏款删除造成，与池子归谁无关**）。

> **v0.9 同步（仓库容量与邮件）**：①存档 schema 升到 **4**——实例加 `location`（`warehouse` / `mail`），并新增**仓库容量** `warehouse_capacity` 的持久化（它是**进度解锁物**，必须入档，§4 / §5 第 14 条）；②**容量由里程碑解锁**（核心 D15，内容门控，与 P7 一致）——新增载荷 `WAREHOUSE_CAPACITY`（§4 / §5 第 5 条），并**明确禁止任何靠消耗物品 / 重复开盒增加容量的路径**（§5 第 14 条）；③**`source.kind` 的迁移取值按核心 v0.9 裁决 4 定为 `&"migrate"`**（本文旧稿的 `&"migration"` 作废）；④新增 **v3 → v4 迁移规则**（§7.4），**实例数量守恒、绝不丢弃**；⑤`collected` 裁决**上游已采纳**（§5 第 13 条）；⑥**裁决 17 收窄了"产出溢出"的适用范围**：**被动产出（开盒）放不下 → 进邮件**，**主动操作（转化 / 拆卸返还）放不下 → 拒绝整个操作**（§5 第 15 条末条）；⑦**新增主动丢弃**（裁决 16）：玩家可销毁仓库内实例，记账只走 `total_consumed`，**不得回退** `collected` / `duplicate_count` / `serial_counters`（§5 第 16 条）；⑧**守恒等式按全部实例**（裁决 12）：`total_granted − total_consumed == Σ 全部现存实例（含邮件）`，`count()` 只是带 `location` 过滤的查询（§5 第 15 条 / T17 ⑥ / T20）。**里程碑链、品质解锁、进度节奏、五条红线一律未改。**

> **本系统是 R11 的落点。** ρ 的成长**只能**来自内容释放（核心 §2.4），而内容释放的**发放动作**归本系统。因此：**内容产能是进度的唯一来源，本系统直接决定产品节奏**——内容跟不上 → 解锁链无货可发 → 进度停滞 → 玩家流失。本系统的设计目标是让"内容释放"成为**可配置数据**（§6），而不是手写代码。

> **v0.6 同步（本系统新增一条进度轴）**：镶嵌位数改由**套系品质 `series_quality`** 决定（核心 §4.1.1 / C4），**解锁更高品质的套系因此成为一条新的主动进度轴**，其发放动作归本系统：新增载荷 `SERIES_QUALITY_UNLOCK`（§1 第 4 条 / §5 第 5 条），并新增持久化集合 `unlocked_series_qualities`（§4）。
> P7 的要害随之收敛为一条区分：**同一套系内不得增额；跨套系（解锁更高品质套系）是合法的、也是唯一的功率成长路径**（§5 第 10 条）。**`[v0.10]` 这半句里的两个细节已被改写**：镶嵌位是**每池（盒）常量**（不再表述为"每套系"），且"跨套系是**唯一**成长路径"不再成立（跨池复制改由**模块成本**约束）——**细则与理由见 §5 第 10 条末条**，本块保留 v0.6 原话作为沿革记录。

## 1. 这个系统负责什么

1. **图鉴 `Codex`**：每个物品 `Item` 的收录状态（已收录 / 未收录 / 重复次数），以及**缺口可见性**。核心 §1.1 把「图鉴」列为"获取物品"这一步的系统职责；"**缺口的半衰期是周**"出自 `../archive/core-design-v0.1.md` §1.3（v0.5 §16「继承不变」未废止），本系统据此把**缺口可见性**定为硬要求（§9）。**v0.8：收录是不可逆事实**——`collected` **不由实例列表推导**（§5 第 13 条）。
2. **套系进度 `series_progress`**：单个套系的完成度，**一个数字 `collected / regular_count`**（v0.13：**不再分列**——池中全部是常规物品，隐藏款已删除，核心 §5.4）。`regular_count` 个物品**全部是常规物品**，`regular_count` 由该套系的**套系品质**决定，8 或 12（核心 §4.1.1）。
3. **里程碑任务链 `milestone_chain`**：链骨架（顺序、前置、解锁载荷、预告）的定义与发放。**谁定义、谁发奖励的裁决见 §8.1。**
4. **解锁发放 `grant_unlock()`**：新套系 / 新物品类别 / **更强模块的产出权限**（核心 §4.3）/ **套系品质解锁 `SERIES_QUALITY_UNLOCK`**（核心 v0.6 §4.1.1）/ **仓库容量扩容 `WAREHOUSE_CAPACITY`**（核心 v0.9 D15）。其中模块品质的释放节奏即 **D13**（R11 的核心载体）；**套系品质解锁决定"玩家最高能施工到什么档位"**，是 v0.6 新增的**唯一功率成长路径**（P7，§5 第 10 条）；**容量解锁是 v0.9 新增的第二个内容门控载荷**（§5 第 14 条），它同样**只有发放权、没有产出权**。
5. **全收集判定与终局表现**（核心 §10.1 / §10.2）；**存档结构**：`user://` JSON 的完整 schema、**物品实例列表 `Array[ItemInstance]`（含 `location`）与 `serial_counters` 的持久化布局（v0.8 / v0.9）**、**仓库容量 `warehouse_capacity` 的持久化（v0.9）**、**囤积清单与每个 `Box` 的五个字段（`box_id` / `series_id` / `item_pool` / `modules` / `uses_remaining`）的持久化布局（v0.10 / v0.14）**、`pool_snapshot` / `state_snapshot` / 开箱日志（seed + 结果）；**进度节奏表**：把核心 §10.2 的五阶段落成可配置数据（§6.2）。★ **v0.16 登记（开局基础装置）**：**开局发放的那台基础装置**是**开盒 / 装模块的硬门槛**（**没设备就打不开盲盒、也装不了模块**），因此它是**开局初始状态的组成部分、属于玩家进度、必须落盘**——**重放 / 读档一律读回原值，不得重算、不得凭空再发一台**（与 `Box` 五个字段同一纪律，§5 第 17 条）。**⚠️ 缺口**：**本档（v5）目前没有任何装置 / 设备条目**（`ProgressionState` 无对应字段、§4.1 示例的块里也没有它）——**是否新增 `devices` 块、`schema_version` 是否随之递增、载入后缺设备时是"报错"还是"补发"，三项均待上游裁决**（§11 **Q20**）；**本文不发明该块的结构**。★ **v0.16 补充（设备不消耗——可回滚的默认）**：**设备不会被消耗、不会损耗**（**无耐久度、无使用计数**），判定 = "**持有至少一台即可**"、**判定无参**——因此存档侧**只需表达"玩家持有一台（或多台，若将来允许）设备"这个事实**，**不需要耐久度 / 使用计数 / 绑定关系**。（**若将来改为"设备绑定盒子 / 有服务上限"，判定入口会变成带 `box_id` 的形式，届时存档要新增相应字段**——**当前只登记、不实现**。）

## 2. 不负责什么（边界）

| 不负责 | 见 |
|---|---|
| 任务的需求向量匹配、奖励结算、需求随进度变宽 | `03-task.md` |
| 抽取判定 `roll(evaluation, seed)`、未拥有物品权重 ×1.5 的**计算** | `01-gacha.md`（**保底已随 v0.11 删除**，见文首 v0.11 说明） |
| `PoolState` 的结构、`Box.item_pool` / `Box.modules` 的编辑规则与排除 / 提升 / 损耗 / 零和、**池子当前状态的逐盒重建**；ρ / M̄ / D̄ / B / σ 与 `void_prob` 的计算口径、归因分解 | `05-module-pool.md` / `07-economy-rho.md`。`[v0.10]` **池子从"每套系一份"变为"每个盒子一份"；盒子的"当前池子状态"是「`item_pool` 基础数据 + 该盒 `modules`」的**函数**（派生值）**（核心 §4.1.2）——`ItemPool` / `Module` 的类型定义、编辑、推导与**重建**归 05，`Box` 载体、`box_id` 身份与囤积清单归 01（`01-gacha.md` §4.3）；**本系统只负责 `Box` 五个字段（`box_id` / `series_id` / `item_pool` / `modules` / **`uses_remaining`（v0.14）**）的落盘布局与"随盒子落盘"的义务**（§4 / §5 第 17–18 条），**不得**自己重建、改写或复制任何盒子的池子 |
| 物品类别与品质定义、**物品实例列表（`ItemInstance`）的创建 / 销毁 / 查询、`serial` 的分配与派生 `count`** | `02-item.md`（`ItemService` 是**唯一写入方**）。本系统只定义其**持久化布局**并做审计，**不得自行创建、销毁或改写实例** |
| **设备**（开盒 / 装模块的入口工具与硬门槛；**不带修正、不绑定盒子、不限制次数、没有槽位**）的开局发放与"持有至少一台"判定；转化表与损耗结算；面板布局、展开入口与 `headline` 渲染；开箱演出（含 `void` 的呈现） | `04-device.md` / `06-conversion.md` / `08-ui-panels.md` / `09-presentation.md` |
| **解锁发放之后的各系统行为**（解锁新套系后 01 怎么建池、解锁品质后 05 怎么造模块） | 各系统自己负责 |
| **`location` 的写入**（产出溢出判定、进邮件、领取）、**仓库占用的计算**与 `count()` 的仓库口径 | `02-item.md`（核心 §4.7 / §14.2 铁律 9）。本系统**只发放容量、只持久化 `location` 与 `warehouse_capacity`**，**不得**在任何路径上自行判定溢出、改写 `location` 或推导占用。**主动操作（转化 / 拆卸返还）的空间拒绝**（裁决 17，判定归 06 / 04、执行归 02）与**主动丢弃的销毁**（裁决 16，归 02）同样不在本系统 |
| **`ItemDef.size`**、容量的**抽象单位**与 UI 的占比换算 | `02-item.md`（`size`）/ `08-ui-panels.md`（换算与呈现）。本系统只持久化容量数值本身 |

**本系统的唯一写权限是"解锁发放"与"图鉴 / 套系进度 / 存档布局"。** 一切"解锁之后会怎样"都不在本系统内实现：本系统只把 `unlocked_*` 标志位、`unlocked_series_qualities`、`module_quality_ceiling` 与 **`warehouse_capacity`** 放进共享状态，由对端读取（§8.2）。**位次本身永远不由本系统写入**（P7，§5 第 10 条）；**容量同理——本系统只写入"解锁到多少"，从不参与"装不装得下"的判定**（判定在 02 的 `grant()` 内部，核心 §4.7）。

## 3. 核心概念与术语

沿用 `README.md` §5：套系 `Series`、物品 `Item`、池子 `Pool`、池子状态 `PoolState`、镶嵌位 `socket_slot`、任务 `Task`、类别 `category`、品质 `quality`、闭环收益率 `rho`（**`pity` / 保底已随 v0.11 删除**；**隐藏物品 `hidden` 已随 v0.13 删除**——池中全部是常规物品，核心 §5.4）。本系统新增的**落地命名**（核心文档只给概念，未给字符名）：

| 中文名 | 代码名 | 说明 |
|---|---|---|
| 图鉴 | `Codex` | 全部物品与收录状态的集合 |
| 缺口 | `gap` / `gap_count` | 未收录的物品 / 其数量 |
| 空洞 | `void` / `void_mass` | 排除损耗产生的**零价值结果**，**不是一个物品**（不计入 N）；求值与损耗写入见 `07-economy-rho.md` §5.4 / `05-module-pool.md` §5.4 |
| 套系进度 | `series_progress` | 单套系完成度，**一个数字**：已收录物品数 / `regular_count`（v0.13：不再分列常规与隐藏） |
| 里程碑 | `MilestoneDef` | 里程碑任务链的一个节点 |
| 解锁载荷 | `UnlockPayload` | 里程碑发放的内容释放项 |
| 模块品质天花板 | `module_quality_ceiling` | 当前允许产出的模块品质上限 |
| 全收集 | `full_collection` | 已释放套系全部物品收录 |
| 开箱日志 | `draw_log` | 每次兑现的 `{seed, pool_snapshot, state_snapshot, item_id, quality}`（核心 §14.2 铁律 7；`quality` 即该 `item_id` 在 `ItemDef` 上的品质，二者同源自洽） |
| 进度阶段 | `ProgressPhase` | 核心 §10.2 五阶段之一 |
| 套系品质 | `series_quality` | 套系（池子）的品质档位 1–4，**决定该套系的常规物品数、镶嵌位数与产出物品的品质区间**；核心 §4.1.1 |
| 已解锁套系品质 | `unlocked_series_qualities` | 玩家已解锁的品质档位集合；**其最大值 = 玩家最高能施工到的档位**（P7，§5 第 10 条） |
| 物品实例 | `ItemInstance` | 玩家实际持有的**一个**物品：`instance_id` / `item_id` / `acquired_at` / `source` / `serial` / **`location`**（核心 §4.2.1 / §4.7）。**创建、销毁与 `location` 的写入归 02**，本系统只持久化其布局（v0.8 / v0.9） |
| 收藏编号 | `serial` | **该玩家开出的第 N 个此物品**；**只有开盒产出会推进计数器**（`serial ≥ 1`），转化 / 拆卸返还 / 解锁发放产生的实例为 `serial = 0`；**v2 → v3 迁移回填**的实例为 `serial = 1 … N`（§7.4 第 3 条：它们对应 v2 的真实持有，故占用编号，但 `source.kind = &"migrate"` 仍可区分来源）（核心 §4.2.3，v0.8） |
| 序号计数器 | `serial_counters` | `{item_id: int}`——该玩家**已开出**多少个该物品；**只在开盒产出时 +1**，是 `serial` 的唯一分配依据（v0.8 新增，§5 第 12 条） |
| 溯源 | `source` | 实例的来源：开盒 `{kind: &"gacha", series_id, box_seed, draw_index}`；其余只带 `kind`。**`kind` 的取值域（核心 v0.9 裁决 4）：`&"gacha"` / `&"convert"` / `&"refund"` / `&"mail"` / `&"migrate"` / `&"unlock"`**——各取值的语义与分配归 `02-item.md` §4.2，本系统只用 `&"migrate"` 一档（迁移回填）`[补充]` |
| 仓库容量 | `warehouse_capacity` | **抽象单位**的仓库总容量；**由里程碑解锁、只增不减**（核心 D15 / §4.7，§5 第 14 条）。UI 换算为**占比**显示，换算与呈现归 `08-ui-panels.md` |
| 位置 | `location` | 实例的落位：`&"warehouse"`（仓库，计入 `count()`）/ `&"mail"`（邮件，**不计入可用持有**）。**写入方 02**：产出时由 02 的 `grant()` 内部判定溢出，领取（`mail → warehouse`）只是改位置（核心 §4.7 / §14.2 铁律 9）。本系统**只持久化该字段**（§5 第 15 条） |
| 邮件 | `mail` | 放不下产出的**兜底容器**：无上限、不过期、手动或一键领取。**它不是第二个仓库**——邮件实例不可用于交付 / 装配 / 镶嵌 / 转化（核心 §4.7）。本文只负责它的**持久化口径**，呈现归 08 |
| 物品大小 | `ItemDef.size` | 单个实例占用的容量单位（**同种物品大小相同**，核心 §4.2 / D16）。归 `02-item.md`；本系统不拥有其数值 |

### 3.1 术语纪律：「品质」有两个含义（v0.6 新增）

**本系统两者都会出现，必须可分辨。**

| 写法（一律写全） | 代码名 | 含义 | 出处 |
|---|---|---|---|
| **物品品质** | `quality` | 物品的等级维度，1–5 序数 | `02-item.md` |
| **套系品质** | `series_quality` | 套系 / 池子的品质档位，1–4 | 核心 §4.1.1 |

**规则：本系统中孤立的"品质"二字视为歧义**——凡涉及两者之一，一律写全"物品品质"或"套系品质"。
二者**不是同一把尺子上的两个刻度、也无换算关系**：套系品质**决定**该套系产出物品的品质**区间**；物品品质只影响任务贡献度与作为**模块**素材时的强度（**v0.16：装置不带修正、也没有槽位——"装置强度"已不存在**）（核心 §4.2）。

## 4. 数据结构（GDScript Resource 字段定义）

```gdscript
# 下列各段各自落在其注释标注的文件中
# res://src/progression/defs/unlock_payload.gd —— 内容释放的一项
class_name UnlockPayload
extends Resource
enum Kind { SERIES, ITEM_CATEGORY, MODULE_QUALITY, SERIES_QUALITY_UNLOCK, WAREHOUSE_CAPACITY }
# SERIES = 新套系 / ITEM_CATEGORY = 新物品类别 / MODULE_QUALITY = 更强模块的产出权限（D13）
# SERIES_QUALITY_UNLOCK = v0.6 新增：解锁一个更高品质的套系（核心 §4.1.1）
# WAREHOUSE_CAPACITY = v0.9 新增：仓库容量扩容（核心 D15；容量只能由里程碑解锁）
@export var kind: Kind = Kind.SERIES
@export var target_id: StringName          # series_id / category；MODULE_QUALITY 与 WAREHOUSE_CAPACITY 时留空
@export var magnitude: int = 1             # MODULE_QUALITY：提升到第几档模块品质；SERIES_QUALITY_UNLOCK：该套系的 series_quality（1–4）；WAREHOUSE_CAPACITY：**新增的容量单位数（加到 `warehouse_capacity` 上，不是目标值）**

# res://src/progression/defs/milestone_def.gd —— 里程碑任务链的节点
class_name MilestoneDef
extends Resource
@export var id: StringName
@export var display_name: String
@export var order_index: int = 0
@export var requires: Array[StringName] = []      # 前置里程碑 id
@export var task_def_id: StringName               # 指向 TaskDef；需求与奖励结算归 03（§8.1）
@export var unlocks: Array[UnlockPayload] = []    # 内容释放载荷，归本系统发放
@export_multiline var teaser: String = ""         # 未达成时的预告（R11 可感知性，§9）

# res://src/progression/defs/milestone_chain_def.gd
class_name MilestoneChainDef
extends Resource
@export var nodes: Array[MilestoneDef] = []

# res://src/progression/defs/progression_phase_def.gd —— 核心 §10.2 五阶段的数据化
class_name ProgressionPhaseDef
extends Resource
@export var phase_id: StringName            # opening / breakthrough / takeoff / engineering / endgame
@export var display_name: String
@export var rho_min: float = 0.0            # 含
@export var rho_max: float = 0.0            # 不含；0.0 表示无上界
@export var stage_note_text: String = ""    # 只作文案呈现，不得参与任何计算（v0.10 改名：旧名 `pool_state_note` 已废弃——该词在 v0.10 专指"池子的当前状态"，与本字段无关；本字段只是 §6.2 进度表"池子状态"列的展示文案）
@export var collection_note: String = ""
@export var expect_unlock_kinds: Array[StringName] = []   # 本阶段预期释放的内容类型（节奏校验用）
@export var expect_max_series_quality: int = 1            # v0.6：本阶段玩家最高可施工到的套系品质，决定 ρ 上限；只作节奏校验与验收对照，不参与计算

# res://src/items/defs/item_instance.gd —— 物品实例（**所有权属 02**，核心 §4.2.1 / §14.1；此处只列持久化字段）
class_name ItemInstance
extends Resource
@export var instance_id: String = ""       # UUIDv4，全局唯一，兼作幂等键（Godot 无内置 UUID，需自实现）
@export var item_id: StringName = &""      # 指向 ItemDef
@export var acquired_at: int = 0           # 开出时刻（Unix 秒）
@export var source: Dictionary = {}        # {kind, series_id, box_seed, draw_index}；kind != &"gacha" 时后三项缺省
@export var serial: int = 0                # 收藏编号；**开盒产出 ≥ 1**，0 = 非开盒来源（转化 / 返还 / 解锁发放）；v2 迁移回填为 1…N
@export var location: StringName = &"warehouse"  # v0.9：warehouse / mail。**写入方 02**（产出时在 grant() 内判定溢出）；本系统只持久化，见 §5 第 15 条

# 运行时状态（由 GameState 持有，SaveService 持久化）
class_name ProgressionState
extends RefCounted
var items: Array[ItemInstance] = []        # v0.8：**只读引用** 02 的 `ItemService.instances`（现存实例，**含仓库与邮件两侧**）；本系统不创建 / 不销毁，只在序列化时读取
var warehouse_capacity: int = 0            # v0.9：**只读引用** 02 的 `ItemService.warehouse_capacity`（抽象单位）；本系统只定义其**持久化布局**，写入路径只有两条：①解锁发放（§5 第 5 条）②读档还原。**占用/溢出判定不在本系统**（核心 §4.7）
var boxes: Array[Box] = []                 # v0.10：**只读引用** 01 的 `pending_boxes`（囤积清单；每个盒子带 **`item_pool` 与 `modules` 两个并列字段**，**v0.14 起另有 `uses_remaining`**）；本系统不创建 / 不销毁 / 不改写盒子，**也不入档盒子的"当前池子状态"**（派生值，见 §5 第 18 条），只在序列化时读取这几个字段（§4 / §5 第 17 条）
var serial_counters: Dictionary = {}       # v0.8 新增：{item_id: int} 已开出数；**只在开盒产出 +1**；写入方 02（§5 第 12 条）
var collected: Dictionary = {}             # {series_id: {item_id: true}} —— 图鉴；**不可逆事实，不由 items 推导**（§5 第 13 条）
var duplicate_count: Dictionary = {}       # {series_id: {item_id: int}} —— 图鉴重复次数；同样不可逆、不由 items 推导
var unlocked_series: Array[StringName] = []
var unlocked_item_categories: Array[StringName] = []
var unlocked_series_qualities: Array[int] = []   # v0.6 新增：已解锁的套系品质档位集合，升序去重；max() = 最高可施工档位（P7）
var module_quality_ceiling: int = 1        # 初始 1 档；只增不减
var granted_unlock_ids: Dictionary = {}    # 发放幂等键
var milestone_state: Dictionary = {}       # {milestone_id: int} —— 见 §7.2
var full_collection_reached: bool = false
var current_phase: StringName = &"opening"

# 开箱日志条目（核心 §14.2 铁律 7）
class_name DrawLogEntry
extends RefCounted
var seq: int = 0
var seed: int = 0
var series_id: StringName
var pool_snapshot: Dictionary = {}   # **这是 draw_log 的字段，不是 pending_boxes 的字段**。形态 = {item_pool: {regular_count, revision, socket_count}, modules: [{index, module_id, quality, socketed_at}…], void_mass_bp, weights_bp}，即 05 §4 派生状态的**冻结副本**（v0.10：`socketed` 已被否决、模块信息按稀疏序列写作 `modules`，并补 `item_pool` 元数据使日志自足）
var state_snapshot: Dictionary = {}  # {m_bar, d_bar, b, rho}
var is_void: bool = false            # `[补充]` void 结果的显式标记（对齐 09 的 Result.is_void），避免靠空 item_id 反推
var item_id: StringName              # `void` 时为空 StringName（哨兵）；见 §5 第 1 条
var quality: int = 1                 # 该物品的品质，取自 `ItemDef.quality`（与 `item_id` 同源自洽；`void` 记录此值无意义，与 `is_void` 一并判读）
```

**持久化口径（`[补充]`）**：权重与 `void_mass` 的**规范表示**是**整数万分比**（`weights_bp`，Σ == 10000；`void_mass_bp`，1 bp = 0.01%，核心 §4.1.2 定稿）——**落盘的唯一位置是 `draw_log.pool_snapshot`**（v0.10：盒子的当前池子状态**一个字段都不落盘**，见 §5 第 18 条）。理由：用户要求的"存 → 读 → 存字节级稳定"必须规避浮点格式化漂移与键序抖动，且**只有整数才能让 C1 的零和等式被精确断言**；浮点 `probs` 只在 07 归一化时出现一次。`PoolState` 的**结构与求值口径**仍归 `05-module-pool.md` / `07-economy-rho.md`（其运行时 `void_mass` 为 float），本系统只定义其**持久化布局**。
**`state_snapshot` 的最小字段集（`[补充]`）**：`{m_bar, d_bar, b, rho}`。理由：核心 §14.2 铁律 7 只要求"记录 state_snapshot"而未规定内容；这四个量是 `EvalService` 的全部输出标量，足以让任意历史开箱的归因可复算（P2）。
**`pool_snapshot` 的规模字段（v0.6 新增，v0.10 收窄）**：每个 `pool_snapshot` / **盒子的 `item_pool`** 条目额外冻结 `regular_count`（该套系常规物品数）与 `socket_count`（位数）。理由：v0.6 中**位子数与池子规模都随套系品质变化**，读档时若不带上这两个值，就**无法校验位子数与池子规模是否仍等于其 `SeriesDef`**（T4 / T11），只能靠 `weights_bp` 的键数反推——而反推在 C6 的极值池上不可靠。二者是 `SeriesDef` 值的**冻结副本**，只读、不参与求值。**`series_quality` 不再入档**（它由 `series_id` 解析 `SeriesDef` 得到，§4 的落盘子集只有五项）。
**`unlocked_series_qualities` 的持久化（v0.6 新增）**：以**整数数组**落盘（升序去重）。理由：读档后必须能**还原"玩家最高能施工到什么档位"**（P7）；该值**不得**由 `unlocked_series` 或 `module_quality_ceiling` 推导——它是一条独立的进度轴（§5 第 10 条）。
**实例列表的持久化（v0.8，`[补充]`）**：`items` 以 **`Array[ItemInstance]`** 落盘（`inventory.instances`），**只写现存实例**——已消耗的实例不留墓碑（核心 §4.2.2 第 3 条）。理由：①审计由 `draw_log` 承担（它已记录 `seed` + `pool_snapshot` + `state_snapshot`），实例列表只需回答"我现在有什么"；②保留墓碑会让存档随游玩时长无界增长（每实例约 120 B，§6.3）。**实例列表的创建 / 销毁 / 查询归 02**，本系统只定义其**持久化布局**（与 `pool_snapshot` 同一处理方式）。
**`serial_counters` 的持久化（v0.8，`[补充]`）**：以 `{item_id: int}` 落盘（键序字母序）。理由：`serial` 必须**跨存档单调**——若只靠现存实例推 `max(serial)`，玩家把该物品全部交付任务后编号会**回退**，再开出的"第 3 个"会变成新的第 1 个。该字段是 `serial` 的**唯一**分配依据，且**只增不减**（§5 第 12 条 / T16）。
**键名与取值对齐（v0.8，`[补充]`）**：`inventory` 块的四个键 = **02 §4.6 `to_save_dict()` 的返回字典**（`instances` / `serial_counters` / `total_granted` / `total_consumed`），本系统**只落盘、不改写**；`count_index` **不入档**（派生值，载入后由实例列表重建）；实例的来源判别键按 02 §4.2 已定的 **`source.kind`** 落地（取值域由**核心 v0.9 裁决 4** 定为 `&"gacha"` / `&"convert"` / `&"refund"` / `&"mail"` / `&"migrate"` / `&"unlock"`，04/05/06 一致——早期草案里写作 `origin` 的同名提案已由 `06-conversion.md` §11 C8 作废，**全库不得并存两个键名**）；**迁移回填一档按裁决 4 写作 `&"migrate"`**（本文与 08 旧稿的 `&"migration"` **作废**，全库不得并存两种拼写）。另：计数器一律写作 **`serial_counters`**（与 02 §4.6 的字典键名一致），**单数写法作废**。
**`location` 的持久化（v0.9，`[补充]`）**：`location` 随实例逐条落盘（`"warehouse"` / `"mail"`），是 `instances` 条目的一个键（键序按字母序排在 `item_id` 与 `serial` 之间）。理由：**仓库与邮件是同一个实例列表的两个位置，不是两份数据**（核心 §14.2 铁律 9）——若不入档，读档后要么凭空丢失邮件侧实例（违反 P5 的"产出永不丢失"），要么必须靠调 `count()` 反推（那就把派生值偷偷变成事实来源）。本系统**只落盘、不改写**：读档时不得按容量重新判定 `location`、不得"顺手"把装不下的搬到邮件（那会让占用率变化凭空改变持有位置，且与 02 的 `grant()` 判定路径形成第二个判定源）。
**`warehouse_capacity` 的持久化（v0.9，`[补充]`）**：以单个整数落盘（`progression.warehouse_capacity`）。理由：**容量是进度解锁物**（核心 D15），它记录"玩家已被发放到多少"；若不入档，读档后只能回到初始容量，玩家的解锁进度会**回退**（与 §4 的 `unlocked_series_qualities` 同一条理由：进度轴必须有还原点），且会让所有邮件侧实例的可用性发生无解释的变化。它**只增不减**、**不由 `size` 之和或持有量推导**（那等于承认"囤积换容量"，直接违反 P7 / §5 第 14 条）。

**盒子数据的持久化（v0.10 / v0.14，`[补充]`）**：**`Box` 的五个字段随该盒子逐条落盘**（`pending_boxes` 块，§4.1；**v0.10 定稿四个、v0.14 新增 `uses_remaining`**）：`box_id` / `series_id` / `item_pool` / `modules` / **`uses_remaining`**——前四个是**上游已澄清的裁决**（核心 §4.1.2 / §16.5），最后一个是 **v0.14 的裁决**，本文照此落地：

| 落盘对象 | 形态 | 说明 |
|---|---|---|
| **`box_id`（身份）** | **`String`（不是 `StringName`）**，**`Uuid.v4()`** | 盒子的**稳定身份**（归 01，核心 §4.1.2 / §16.5 定稿）。**类型必须是 `String`**：它与 `ItemInstance.instance_id` **同为 `Uuid.v4()` 产出**，两个身份字段的类型必须一致——**不得引入 `StringName(...)` 转换点**，否则"同一身份逐位相等"的断言会被一个隐式转换破坏（核心 §4.1.2 明写）。**必须入档**：`headline` / 池子面板 / ρ / 镶嵌 / 开箱日志与重放都要能回答"**这是/来自哪一个盒子**"；没有它，同套系的两个盒子在缓存与存档层会被误认为同一份池子。**与 `item_pool.box_id` 是同一个事实，档里只存一次**（存盒子条目上） |
| **`item_pool`（物品池）** | **落盘子集 = 五项**：`box_id` / `series_id` / `regular_count` / `socket_count` / `revision` | 05 §4 已裁定的**落盘子集**（`[补充]` 归 10 的布局）。**引用而非副本**：基础池**是套系模板 `SeriesDef` 的东西**，盒子只持有引用 —— 载入时由 `series_id` 解析出 `base_items` / `base_weights`（它们在内存里，**不逐盒落盘**）。**两条理由**：① 逐盒落盘 = **同一份模板被复制 N 份**（囤 100 盒 = 100 份基础权重表），体积直接回到"每盒 450 B"那一档，而我们放弃落派生状态就是为了避开它；② 否则基础池有**两份副本**（`SeriesDef` 一份、每盒一份），**内容配置一改就静默不一致**。`regular_count` / `socket_count` 是**冻结元数据**（v0.6 既有理由：读档必须能校验"位数与池子规模仍等于其 `SeriesDef`"，见上一条），`revision` 是**每次 05 写入 +1 的编辑修订号**（主副本在这里）。**五项里 `box_id` / `series_id` 就是盒子条目上那两个键**（同一事实不重复落盘），因此 §4.1 的 `item_pool` 子对象里只出现 `regular_count` / `socket_count` / `revision` 三项。它是**生成数据的凭证**（它的求值结果 `PoolEvaluation` 才是 `roll(evaluation, seed)` 的入参——§8.2） |
| **`modules`（模块列表）** | **落盘 = 已占用槽位的稀疏序列 `{index, module_id, quality, socketed_at}`** | **运行期类型是 `Array[Module]`**，`Module = { module_id, quality, socketed_at }`——**不含 `slot`**（核心 §4.1.2 / 05 §4 定稿）；数组是**长度恒 == `item_pool.socket_count` 的定长数组**，**下标就是镶嵌位号**（空位为空项，C4 在数据结构上直接可见）。**落盘不必存空位**，每项带 **`index`（由数组下标生成，不是 `Module` 的字段）**+ `module_id` + `quality` + `socketed_at`（按 `index` 升序规范化）；**`index` 必须落盘**——否则读档后"位子占用 x / N"与"第几位装了什么"都无法还原（只留 id 列表是不够的）。**空序列 `[]` = 未配置**（不写空位、也不写 `index` 为空的条目）。模块**不折进池子**——它与 `item_pool` **并列**（核心 §4.1.2 明令：**不得**再把模块塞进池子自己的字段，`PoolState.socketed` 那种形状已被否决；05 §4 已删掉它，并提供**独立**只读入口 `get_modules(state, box_id) -> Array[Module]`） |
| **`uses_remaining`（总寿命预算，v0.14 新增）** | **单个整数**（`uses_remaining`） | **每盒可变的总寿命预算**：发放时按该盒所属套系品质初始化（**品质 1→10 / 2→15 / 3→20 / 4→25**；**与位数 2/3/4/5 不是一回事**——**预算远大于位数**）。**两个消耗点、共用同一计数器、各 −1**：**①镶嵌一个模块　②兑现一次**——**没有第三个消耗点**；**归零 ⇒ 盒子立即被摧毁**（连同 `item_pool` / `modules` 一起从囤积清单消失；**"次数归零即摧毁"哪怕从未兑现**——由"镶嵌 + 兑现累计到 0"触发，**不是**靠装满位子）。**必须入档、且随盒子落盘**：它是**玩家进度**（"这个盒子还剩几次寿命"），不落盘就等于**读档后白送次数**。**它是输入（可变）、不是派生值**——**键存在时重放 / 读档 / 迁移一律读回原值，不得重算、不得按品质补满**（与 `box_id` 的"**稳定性来自持久化**"同一纪律）；**载入 / 迁移对缺该键的老盒子按品质补齐初始预算（品质 1–4 ⇒ 10/15/20/25）；只有缺键才补，键存在时用存档值、哪怕它是 `0`**（§7.4 第 8 条）。**它不进入 `item_pool` 的子对象**（那是 `ItemPool` 的落盘子集，与寿命预算无关） |

- **`base_items` / `base_weights` 不逐盒落盘（v0.10 裁决，05 §4 / T17 同口径；**这是同一笔交易，代价必须写明**）**：基础池**是套系模板 `SeriesDef` 的东西**，盒子只持有**引用**（`series_id`），载入时解析。**代价（已接受，不是 bug）**：**内容配置调整基础权重时，所有存量盒子的基础池会一起变**——与"派生状态不入档、可重建"**同源**（它们都是"不复制、只引用"的必然结果）；**断言要写成"一致地变"，不是"各不相同"**（05 T17 ③）。
- **`weights_bp` / `void_mass_bp` 仍然落盘的地方只有一处：`draw_log.pool_snapshot`**（兑现时刻的历史**冻结副本**，T2 逐条复现依赖它；**那是 `draw_log` 的字段，不是 `pending_boxes` 的字段**）。它与"当前状态不入档"**不冲突**：**快照是日志**（回答"当时是什么样"，不可再算出来），**状态是派生值**（回答"现在是什么样"，可以随时重建）；快照里的模块信息按同一口径写作稀疏序列 `{index, module_id, quality, socketed_at}`（**`socketed` 这个键名已被否决**，§4.1）。
- **`revision` 是 `ItemPool` 的字段、随盒子落盘（不是派生状态的一部分）**：它是**每盒自己的编辑修订号**（05 每次写入 +1；主副本在 `ItemPool`，派生状态里那份只是**镜像**）——因此它**跨会话单调、每盒各自独立**，读档**不得**把它归零或重算。07 的缓存键 `(box_id, revision)` 因此跨会话仍然有效；`draw_log` 里记下的 `revision` 与主副本同口径，可跨档比较。**推论**：**不得**在任何地方断言"载入后 `revision` 重新起算"（那是它还在派生状态里的旧口径）。
- **禁令**：读档**不得**按"当前套系的施工台"或"最高品质套系"改写任何盒子的 `item_pool` / `modules`，**不得**把某个盒子的配置复制给同套系的其它盒子（那是 P7 v0.10 明令否决的"免成本跨池复制"），**不得**按容量 / 进度 / 时间重算盒子的池子（P1 铁律 7）。

### 4.1 存档 JSON schema 示例（`user://save.json`）

键序为**字母序**（canonical 序列化，保证往返字节级稳定）。示例为**同套系两个盒子、配置不同**（v0.10 的"分批"）：盒 1 在**第 1 号位**上镶了 1 个排除模块（`modules` 里是 `{ index: 1, module_id: "mod_ban_s01_05", quality: 2, socketed_at: … }`，排除 `s01_05`），盒 2 **未配置**（`modules = []`，注意**落盘是稀疏序列**：**空位不写**）。该套系为**套系品质 2**（`series_quality = 2` → 8 个物品 / 3 镶嵌位，核心 §4.1.1；**v0.13：这 8 个全部是常规物品**）——**注意 `series_quality` 不落盘**：它由 `series_id` 解析 `SeriesDef` 得到（§4 的落盘子集只有五项）；同理各物品的 `ItemDef.rarity`（`02-item.md`）是**内容配置、不落盘**，基础权重由它归一化**派生**（v0.12，核心 §5.1）。**注意存档里没有权重**：盒 1 的池子状态**是由 `item_pool` + `modules` 载入后重建出来的**，盒 2 重建出的是**基础池**（`void_mass_bp = 0`）。**示例的整数算术（v0.13 重算；`p_i = rarity_i / Σ rarity`）**：该套系 8 个物品的 `rarity` 取到 **`Σ rarity = 100`** ⇒ **1 个单位 = 100 bp**、合计恰好 **10000 bp**（`s01_05` 的 `rarity = 20` → **2000 bp**；`s01_01` / `s01_02` / `s01_03` 各 `rarity = 12` → **1200 bp**；`s01_04` / `s01_06` / `s01_07` / `s01_08` 各 `rarity = 11` → **1100 bp** ⇒ 2000 + 3×1200 + 4×1100 == 10000 ✓）。盒 1 排除了 `s01_05`：它释放的 **2000 bp 中 40% 蒸发为 `void`**（`void_mass_bp = 800`），其余 **1200 bp 按 `rarity` 摊回剩下 7 项**（余下 `Σ rarity = 80` ⇒ **1 个单位 = 15 bp**）——`rarity = 12` 的三项各 **+180 → 1380 bp**、`rarity = 11` 的四项各 **+165 → 1265 bp** ⇒ **`Σ 物品 9200 + void_mass_bp 800 == 10000 bp` ✓**（C1 的口径见 `README.md` §6.1）。**v0.14 的 `uses_remaining` 在本例中按新基线取值**（该套系品质 2 ⇒ **初始 15**）：**盒 1 = 14**（**镶了 1 个模块 ⇒ −1**、**未兑现过**，与 `revision = 4` 自洽），**盒 2 = 15**（未配置、未兑现）。**同为 `series_01`、`item_pool` 也相同，但 `modules` 不同 ⇒ 重建出的两个池子不同**——这正是"池子随盒子走"的存档形态（核心 §4.1.2 / §6.1）。**权重只在 `draw_log.pool_snapshot` 里出现**（那张是兑现时刻的冻结日志，不是盒子状态；**它是 `draw_log` 的字段**）——**日志那条由某个已被兑现的盒子产生**（兑现即消耗，它已不在 `pending_boxes` 里，与清单中这两个盒子无关），`void_mass_bp` 与 `weights_bp` 同单位、同精度。
`"schema_version": 5`（`[补充]`：v0.8 把持有量从"每个 `(category, quality)` 一行计数"改为**实例列表**并新增 `serial_counters`（→ v3）；v0.9 给每个实例加 `location` 并新增 `progression.warehouse_capacity`（→ v4）；**v0.10 把"每套系一份 `pools`"改为"每个 `Box` 带 `box_id` / `item_pool` / `modules`"（→ v5）**——v0.10 当时还新增了一个独立的 `pity_counters` 块，**该块已随 v0.11 删除保底而取消**。按 §7.4 约定必须递增版本，故示例即 **v5**；v1 → v2 见 T3，v2 → v3 / v3 → v4 / **v4 → v5** 见 §7.4。**v0.11 只删一个块，因此 `schema_version` 仍为 5、也没有新增迁移步骤**（§7.4 第 5 条）；**v0.10 写出的档若仍带 `pity_counters`：读档一律忽略该键**（不报错、不迁移）、**下次写档不再写出**。**v0.14 只给盒子条目加一个字段（`uses_remaining`），因此 schema 仍为 v5、同样不新增迁移步骤**（§7.4 第 8 条）。★ **v0.16 登记：本档没有装置 / 设备条目**——开局必须发放的那台**基础装置**（**开盒 / 装模块的硬门槛**，否则**开局死锁**：开盒需设备 → 设备由物品制造 → 物品来自开盒）**目前无处落盘**：是**新增一个 `devices` 块**还是**并入既有块**、`schema_version` 是否随之递增（若属"新增块"，按 §7.4 的约定应为 **v6 + `migrate_v5_to_v6()`**；**"仍 v5"那条只覆盖 `uses_remaining` 的"新增字段 + 载入补齐"**），**均待上游裁决**（§11 **Q20**）。**本文不发明块结构。** ★ **存档只需表达"持有一台（或多台）设备"这一事实**：**设备不消耗、不损耗 ⇒ 不存耐久度 / 使用计数 / 绑定关系**（判定 = "**持有至少一台即可**"，**无参**）；**若将来改为设备绑定盒子 / 有服务上限 ⇒ 判定入口变为带 `box_id` 的形式、存档新增字段**（**可回滚的默认，当前只登记、不实现**）。`pending_boxes` 条目的键 = 01 §4.3 的 `Box`（`series_id` / `source` / `acquired_tick`）+ 定稿的 **`box_id`** / **`item_pool`** / **`modules`** / **`uses_remaining`**（**v0.14 起共五个字段**）；其中 **`item_pool` 的子对象只出现 `regular_count` / `socket_count` / `revision`**（`box_id` / `series_id` 就是盒子条目上那两个键，同一事实不重复落盘；`base_items` / `base_weights` / `series_quality` 一律不落，由 `series_id` 解析）。**盒子的"当前池子状态"不存在于本档内**（派生值，载入后逐盒重建，§4 / §5 第 18 条）。
示例中 `location` 逐条落盘：除第 5 条外的四条实例都在 `warehouse`（含迁移回填的一条），**第 5 条演示一次"产出溢出进邮件"**（`location == "mail"`，`serial` 照常分配、`instance_id` 照常生成——**邮件的实例与其他实例是同一份数据**，只是位置不同，核心 §14.2 铁律 9）。本示例同时满足**守恒等式（裁决 12）**：`total_granted 191 − total_consumed 186 == 5`，恰为实例条目数——**含邮件那一条**（`count()` 只是带 `location` 过滤的查询，不参与该等式）。

```json
{
  "draw_log": [
    { "is_void": false, "item_id": "s01_02", "quality": 3, "seed": 918273645, "seq": 1, "series_id": "series_01",
      "state_snapshot": { "b": 2.0, "d_bar": 12.0, "m_bar": 3.24, "rho": 0.54 },
      "pool_snapshot": { "item_pool": { "regular_count": 8, "revision": 4, "socket_count": 3 },
        "modules": [ { "index": 1, "module_id": "mod_ban_s01_05", "quality": 2, "socketed_at": 1730000000 } ],
        "void_mass_bp": 800,
        "weights_bp": { "s01_01": 1380, "s01_02": 1380, "s01_03": 1380, "s01_04": 1265, "s01_05": 0,
                        "s01_06": 1265, "s01_07": 1265, "s01_08": 1265 } } }
  ],
  "inventory": {
    "instances": [
      { "acquired_at": 1729999990, "instance_id": "6f1c0b7e-3d2a-4c9f-9b41-2f5a7c0d1e88", "item_id": "s01_01",
        "location": "warehouse", "serial": 187,
        "source": { "box_seed": 918273645, "draw_index": 3, "kind": "gacha", "series_id": "series_01" } },
      { "acquired_at": 1729999990, "instance_id": "b0a5f2d4-8c31-4a76-8e19-7d3f4b62a1c0", "item_id": "s01_02",
        "location": "warehouse", "serial": 2,
        "source": { "box_seed": 918273645, "draw_index": 4, "kind": "gacha", "series_id": "series_01" } },
      { "acquired_at": 1729999999, "instance_id": "1d9e77aa-55b2-4f08-b3c6-0a2e6c8f9d31", "item_id": "s01_01",
        "location": "warehouse", "serial": 0, "source": { "kind": "convert" } },
      { "acquired_at": 1730000000, "instance_id": "c47b1e02-9a63-4d5c-8f27-6b18e0a4d5f9", "item_id": "s01_01",
        "location": "warehouse", "serial": 1, "source": { "kind": "migrate" } },
      { "acquired_at": 1730000005, "instance_id": "9a2f41c8-6e70-4b13-9d58-3c04f7e2b6a1", "item_id": "s01_08",
        "location": "mail", "serial": 12,
        "source": { "box_seed": 553120994, "draw_index": 7, "kind": "gacha", "series_id": "series_01" } }
    ],
    "serial_counters": { "s01_01": 187, "s01_02": 2, "s01_08": 12 },
    "total_consumed": 186,
    "total_granted": 191
  },
  "pending_boxes": [
    { "acquired_tick": 1729999990, "box_id": "3f2c8a51-9c47-42e0-8a17-6b0d5e94c7f2",
      "item_pool": { "regular_count": 8, "revision": 4, "socket_count": 3 },
      "modules": [ { "index": 1, "module_id": "mod_ban_s01_05", "quality": 2, "socketed_at": 1730000000 } ],
      "series_id": "series_01", "source": "task_regular_a", "uses_remaining": 14 },
    { "acquired_tick": 1730000001, "box_id": "b71e0d38-4a95-4f6c-9d20-1c8a7f3b5e46",
      "item_pool": { "regular_count": 8, "revision": 0, "socket_count": 3 },
      "modules": [], "series_id": "series_01", "source": "task_regular_b", "uses_remaining": 15 }
  ],
  "progression": {
    "collected": { "series_01": { "s01_01": true, "s01_02": true, "s01_04": true } }, "current_phase": "opening",
    "duplicate_count": { "series_01": { "s01_01": 4, "s01_02": 1 } }, "full_collection_reached": false,
    "granted_unlock_ids": { "ms_01:item_category:ore": true }, "milestone_state": { "ms_01": 3, "ms_02": 1 },
    "module_quality_ceiling": 1, "unlocked_item_categories": ["ore", "fiber"], "unlocked_series": ["series_01"],
    "unlocked_series_qualities": [1, 2], "warehouse_capacity": 1000
  },
  "schema_version": 5,
  "saved_at_unix": 1730000010
}
```

### 4.2 实例列表与 `DrawLogEntry` 的关系（v0.8，`[补充]`）

| | 实例列表 `inventory.instances` | `draw_log` |
|---|---|---|
| 回答的问题 | **我现在有什么**：每个物品个体是第几个、何时开出、从哪个盒子来 | **历史上开过什么**：当时的池子与状态是什么样 |
| 范围 | **只含现存实例**（被消耗的实例即消失） | 逐次兑现全量累积（不裁剪，见 Q3 / §6.3） |
| 唯一标识 | `instance_id`（UUIDv4，幂等键） | `seq`（日志序号）+ `seed` |
| 溯源 | `source = {kind, series_id, box_seed, draw_index}` | `{seed, series_id, pool_snapshot, state_snapshot, item_id, quality, is_void}` |
| 体积 | 每实例约 120 B（**`source` 是大头**） | 每条约 0.5–1 KB（`pool_snapshot` 的 `weights_bp` 是大头） |
| 写入方 | **02**（`ItemService`） | 本系统 |

**关系（关键）：** 实例的 `source.box_seed` **指向** `draw_log` 中 `seed` 相同的那一条（`draw_index` 指定同一批内的第几次兑现）。因此**实例只存轻量溯源指针，不重复存 `pool_snapshot`**——审计所需的池子快照全部留在日志里。**推论：不得为了压缩体积而砍掉实例的 `source`**（那会切断实例与日志的对应关系，溯源与收藏编号叙事同时失效）；要省体积先裁剪 `draw_log`（Q3）。

**边界说明：** `pending_boxes[]` 的 `box_id` / `series_id` / `item_pool` / `modules` / **`uses_remaining`（v0.14）**（核心 §4.1.2 定稿的 `Box` 字段集；写入方 **01** 与 **05**，本系统只落盘不解释）与 `draw_log.pool_snapshot` 的字段均取自核心 §4.1.2 与 `05-module-pool.md` §4，模块编辑明细、**推导**（`PoolService` 是唯一写入方）与**求值**（`EvalService` 是唯一求值方）归 `05` / `07-economy-rho.md`，本系统只负责其**持久化布局**；**三者的区别是**：**五个字段是盒子的输入**（随盒子长期活着、可继续镶嵌与改寿命预算）——**它们在盒子归零被摧毁时才一同消失**（v0.14 改口径：**被摧毁前模块一直在**；不再有"兑现即随盒子消失"，也不再有"用尽后仍留着一段时间"的缓冲），而 `pool_snapshot` 是**兑现那一刻**的冻结副本（**历史审计**，T2 的逐条复现依赖它——它记的是**结果**，因为盒子被摧毁后这份结果再也算不出来）。**基础池只存引用**（`series_id` → `SeriesDef` 解析），因此**不落** `base_items` / `base_weights` / `series_quality`（§4 的落盘子集只有五项）。**`pool_snapshot` 里的 `socketed` 已被否决**（核心 §4.1.2 明令："模块在池子里"的形状不得存在），其中的模块信息按同一口径写作**稀疏序列 `modules`**（`{index, module_id, quality, socketed_at}`，**`Module` 本身不含 `slot`**），并额外冻结 `item_pool` 元数据，使这条日志**自足**（不依赖那个盒子此刻是否还存在）。**v0.11 删除保底 ⇒ 本档不再有 `pity_counters` 块、也不存在任何保底计数**（§5 第 19 条）。上例数值仅示意格式，口径一律以 `README.md` §6.1 与 `07-economy-rho.md` §5.4 为准。

## 5. 规则与公式

1. **收录**：`GachaService.roll(evaluation, seed)` 结算后，本系统记录 `collected[series_id][item_id] = true`；若已收录则 `duplicate_count += 1`（**开出的那个物品本身由 02 落为一个新实例**，见 `02-item.md`；P5「重复永不是空手」由此兑现）。**收录是记录"曾开出过"，不是"现在还持有"**——因此 **`collected` / `duplicate_count` 只增不减，绝不因实例被消耗而回退**（v0.8 裁决见第 13 条）。**空洞 `void` 不产生任何收录效果，也不产生实例**：`void` 不产出物品，**不写图鉴**、**不推进 `series_progress`**、**不改动 `collected`**（因此 `is_collected()` 的返回值不变，即"未拥有物品加权"的状态不受 `void` 影响）、不加 `duplicate_count`、**不推进 `serial_counters`**；它只落进 `draw_log`（`item_id` 为空、`is_void = true`，见 §4.1）。**`void` 不推进任何计数器**（v0.11 删除保底，核心 §5.6）——它只落 `draw_log`，不产生任何跨次状态，本系统不裁决。
2. **缺口**：`gap_count(series_id) = regular_count(series_id) - collected_count(series_id)`（**v0.13：= 未收录物品数 = 全部物品减已收录**；隐藏款删除前此式分子为 `regular_count + 1`）；`gap_items(series_id)` 返回未收录物品清单。`regular_count` 由该套系的**套系品质**决定（品质 1/2 = 8，品质 3/4 = 12，核心 §4.1.1），**只在运行时从 `SeriesDef` 读取，不得在本系统内写死 8**。核心 §5.5 的收官玩法（把池子编辑到只剩缺口物品）以本清单为唯一依据。
3. **套系进度**：`series_progress` 是**一个数字**——`collected / regular_count`（分子 = 该套系**已收录物品数**，分母 = 该套系的物品总数 `regular_count`，同样不得写死分母）。**v0.13：不再分列**——池中**全部物品都是常规物品**（隐藏款已删除，核心 §5.4），原先"常规与隐藏分列"的理由（**由 C3 推出**：隐藏物品免疫一切池子编辑，合并成同一百分比会让玩家以为"靠编辑能收敛它"）**随 C3 作废而失效**，该分列口径一并删除。
4. **里程碑链**：`MilestoneDef` 依 `order_index` 顺序推进；节点状态见 §7.2；节点达成后由本系统发放 `unlocks`。
5. **解锁发放**：`grant_unlock(payload)` 为**幂等**操作，幂等键 `"{milestone_id}:{kind}:{target_id}"`（`[补充]`：同一载荷重复发放不得重复生效，否则存档不确定）。**五类载荷**与各自的写入目标：

   | `Kind` | 发放后写入 | 语义 | 与其它载荷的关系 |
   |---|---|---|---|
   | `SERIES` | `unlocked_series` | **这个套系能不能开盒**（内容量） | 新池子的入场券 |
   | `ITEM_CATEGORY` | `unlocked_item_categories` | 物品类别开关 | 与位次无关 |
   | `MODULE_QUALITY` | `module_quality_ceiling` | **模块能造多强**（D13，R11 核心载体） | 与下一项是同一成长的两条腿 |
   | **`SERIES_QUALITY_UNLOCK`**（v0.6 新增） | `unlocked_series_qualities` | **这个档位的套系能不能施工**（功率上限） | `magnitude` = 该套系的 `series_quality`（1–4） |
   | **`WAREHOUSE_CAPACITY`**（v0.9 新增） | `warehouse_capacity` | **仓库能装多少**（核心 D15，内容门控） | `magnitude` = **新增容量单位数**（累加，不是目标值）；写入后**只增不减**（§5 第 14 条） |

   **关系与顺序**：`SERIES` 决定"有没有这个池子"，`SERIES_QUALITY_UNLOCK` 决定"这个池子的施工台有多大"。同一里程碑内若两者同时发放，执行顺序为 **`SERIES_QUALITY_UNLOCK` → `SERIES` → 其余**（`[补充]`：避免出现"盒子能开、施工台却未解锁"的中间态——该中间态下无法确定该套系的位次上限，05 会读到未授权的 `SeriesDef.socket_count`）。`MODULE_QUALITY` 与 `SERIES_QUALITY_UNLOCK` 则互为补充：前者决定**模块多强**，后者决定**能装几个**（核心 §4.1.1）。`WAREHOUSE_CAPACITY` 与三者都无耦合：它只与"玩家到此刻为止能囤多少"有关，**不参与任何位次或概率**。
   **发放只写 `unlocked_*` / `unlocked_series_qualities` / `module_quality_ceiling` / `warehouse_capacity`，不直接写入任何位次**：位次永远由对端从 `SeriesDef` 读取（见 §10 的 T4）。容量同理——**本系统只写"解锁到多少"，从不判定"装不装得下"**（判定在 02 的 `grant()` 内部，核心 §4.7）。
6. **全收集判定**：`full_collection_reached = 所有已解锁套系的**全部物品**（每个套系 `regular_count` 个，**v0.13：全部是常规物品**，隐藏款已删除）均已收录`（`regular_count` 逐套系取自其 `SeriesDef`）。后续释放新套系时，已达成标记**保留**并重新进入收集中状态（`[补充]`：内容释放是持续的，终局必须可重入，否则新内容会"取消"玩家已达成的成就）。**v0.13 说明（必须明确写出，不得含糊）**：隐藏款删除后，本标记与 §7.3 的 `NORMAL_COMPLETE`（常规物品全部集齐）**同义**——两者判据指同一件事（分母都是 `regular_count`、分子都是同样的收录数）。**结构保留、不得删改**：§7.3 仍保留两个状态与三条迁移（它同时承载"新套系释放 ⇒ 回到 `COLLECTING`、标记保留"这条可重入规则），本标记也仍是**独立持久化字段**（`ProgressionState.full_collection_reached`，不由实例列表或 `collected` 推导）。
7. **终局表现**（核心 §10.1 / §10.2）：全收集不提供任何数值奖励；其表现是图鉴满格、套系进度满格，以及收官阶段**池子逼近只剩缺口物品**的当前状态仍可随时展开查看。收尾是 **"我算赢了它"**，不是"我终于抽到了"。
8. **阶段判定只用于呈现**：`current_phase` 由 `EvalService` 的 ρ 落入哪一 `ProgressionPhaseDef` 区间决定（`07-economy-rho.md` 是唯一 ρ 口径）。**只读 ρ，绝不直接读池子结构**——`void` 已通过 `v = 0` 压低 `m_bar` 并体现于 ρ，阶段判定因此自动吸收 `void` 的影响，无需（也不得）另行读取 `void_mass`。**阶段判定不得以任何方式影响池子、权重或概率**（P1 铁律 7）。
9. **内容产能即节奏**：`milestone_chain` 的节点数与 `unlocks` 的载荷量，就是玩家进度的**全部**燃料（R11）。任何"没有新载荷可发"的里程碑节点都是设计缺陷，不是配置自由。
10. **套系品质解锁是唯一的功率成长路径（P7 的全部要害，v0.6 新增；`[v0.10]` 标题里的"唯一"已被改写，见本项末条）**：`max_series_quality = max(unlocked_series_qualities)` 就是玩家**最高能施工到的档位**。这条规则的准确表述是**两句话，缺一即错**（`[v0.10]` 两条常量轴线已被上游**拆开**，见核心 §14.2 铁律 5）：
    - **同一池（= 同一个盒子）内不得增额**：`socket_count` 是**每池常量**（随该盒所属套系的品质取值，核心 §4.1.1 / §14.2 铁律 5）——**没有任何**载荷、里程碑、进度、重复劳动或物品消耗可以提高**某个已解锁盒子**的 `socket_count`。这半句仍是 P7 的红线（T4 逐盒断言）。（**v0.16：`device_slot_count` 已删除**——**槽位原本服务"装置修正（转化端）"；D4 作废、装置又不带修正 / 不绑定盒子 / 不限制次数 ⇒ 槽位没有服务对象**。★ 别混：**"镶嵌位 / `socket_count`"是盒子的位子——保留，且它正是 C4 的对象**。）
    - **跨套系是合法的成长路径**（v0.6 的原始表述是"**也是唯一的**"——**该半句已被 v0.10 改写，见本项末条**）：解锁更高品质的套系 = 得到一个**更大但池子也更大**的施工台（核心 §4.1.1 要求位子与物品数同步长，否则 C6 失效）。这是 v0.6 新增的主动轴，**是内容释放，不是扩容**。
    - **因此不得写成"位子永远不能增加"**——那会误杀这条功率成长路径（v0.10 之后它**不再是唯一**的，但仍是**最主要**的），把 P7 变成"开盒端永久冻结"（那正是 v0.6 要修掉的问题）。
    - 本系统在此轴上的职责**只有发放**：写入 `unlocked_series_qualities`，不去读写任何位次（§2 / §8.2）。
    - `[v0.10]` **注意：P7 已被上游改写（核心 §7 / §16.5），本节的两句话要按新口径读**——"**功率不随重复劳动增长**"**已不再成立**：池子随盒子走之后，位子总数 = **盒数 × 每池位数**，而盒数无上限。新口径是"**单池功率仍封顶于 N**（不可绕过），跨池复制要付**模块成本**"（核心 D17）。因此：**① 本节的实质规则一字未改**——**同一池（盒）内仍不得增额**（C4 / P7 的共同否决项，T4 逐盒照测）；**② 但"跨套系是唯一的功率成长路径"这半句在 v0.10 下不再成立**——玩家给**更多盒子**配置模块是合法的，只是要付模块的物品成本；**不得**以"P7 只允许跨套系成长"为由拒绝或封堵它（那会把经济约束误读回结构性禁令）。
11. **只持久化现存实例（v0.8）**：存档只序列化**现存实例**——已消耗的实例不写档、不留墓碑（核心 §4.2.2 第 3 条）。**审计由 `draw_log` 承担**：它按核心 §14.2 铁律 7 已逐次记录 `seed` + `pool_snapshot` + `state_snapshot` + `item_id` + `quality`，因此"历史上开过什么、当时池子是什么样"**完全可复算**（T2），不需要实例列表留历史。二者分工见 §4.2：**实例列表回答"我现在有什么"，`draw_log` 回答"历史上开过什么"**。
12. **`serial` 的分配与 `serial_counters`（v0.8）**：`serial_counters` 的结构是 `{item_id: int}`（键序字母序落盘）。分配规则：**开盒产出时，先 `serial_counters[item_id] += 1`，再把该值写进新实例的 `serial`**（首个为 1）；**转化产出、拆卸返还、解锁发放产生的实例 `serial = 0`，且一律不推进 `serial_counters`**（核心 §4.2.3：`serial` 的含义是"该玩家**开出**的第 N 个"，非开盒来源没有编号可给）。
    - **只有开盒产出会 +1**：这是 `serial_counters` 的**唯一**增量来源（写档、读档、结算任务都不得改动它；**唯一例外是 v2 → v3 迁移的一次性回填**，见 §7.4 第 3 条——那是给 v2 的真实持有补发编号，不是"开出"）。
    - **写入方是 02**：`serial_counters` 与实例列表同属 02 的唯一写权限，本系统只定义其**持久化布局**（§2）。
    - **现存实例的 `serial` 可以不连续**（中间那些被交付任务消耗了）——**连续性不是不变量，最大值对齐才是**：恒有 `serial_counters[item_id] == max(现存实例的 serial)`（T16）。
    - **幂等（与第 5 条合起来看）**：`ItemService.grant` **以 `instance_id` 为幂等键**——同一 `instance_id` 重复发放**不得产生第二个实例**（核心 §14.2 铁律 8、README §3.8）。它**不是**靠"读档时去重"实现的，因此不会与 `grant_unlock()` 的幂等键 `"{milestone_id}:{kind}:{target_id}"`（第 5 条）重叠：**实例幂等由 02 按 `instance_id` 保证，解锁幂等由本系统按键保证，二者共同保证读档重放（重放 `draw_log` / 重放解锁发放 / 中断补送 `INTAKE`）不产生重复实例与重复解锁**。
13. **`collected` 与实例列表的关系（v0.8 裁决）**：**保留独立的 `collected` / `duplicate_count` 标记，不由实例列表推导。**
    - **裁决**：`is_collected(series_id, item_id)` **只读 `collected`**，**不得**实现为"实例列表里存在该 `item_id` 的实例"。
    - **理由（三条）**：①**收录是不可逆事实**——"曾开出过"与"现在是否还持有"是两件事；玩家把最后一个该物品交付任务后，实例消失，但**收录不该消失**，否则图鉴会在玩家认真玩游戏时**退格**；②退格会直接摧毁"缺口的半衰期是周"（§1 / §9）与 P1 的可查可算：玩家会看到自己明明开过的物品重新变成剪影，且`is_collected()` 的翻转还会**反向影响 01 的"未拥有物品权重 ×1.5"**（同一物品被反复计成新物品，等于暗中改概率，P1 铁律 7）；③`void` 不写图鉴（第 1 条）已经确立"收录只由开盒产出推进"，与 `serial_counters` 同源，独立标记不必与实例同生命周期。
    - **推论**：`collected`（是否收录）与 `serial_counters`（开出过几个）是**同一类不可逆记账**，都保留；`duplicate_count` 与之同源、同样保留（三者与实例列表的区别见 §4.2）。`serial_counters` 与 `duplicate_count` 是否合并见 §11 Q7（**本系统不得自行合并**）。
    - **上游已采纳（核心 v0.9 裁决 11）**：本裁决已获采纳——**`collected` 保留为独立标记、绝不由实例推导**。同一裁决另定：**未拥有物品权重 ×1.5 与图鉴一律用收藏口径（`collected`，即 `is_collected()`）**；而 02 的 `find_missing_items` 已改名 **`find_unstocked_items`**，口径是 **"当前仓库无持有"**（`count() == 0`，即"能拿得出几个"）。**两者口径不同、不得互相替代**：图鉴与 ×1.5 要"曾开出过"（不因交付任务而回退），任务面板缺口要"现在拿得出来"。本系统只提供前者（`collected` / `is_collected()`），后者归 02。

14. **容量只能由里程碑解锁（核心 D15 的落地，v0.9 新增）**：`warehouse_capacity` 的**唯一增量路径**是 `WAREHOUSE_CAPACITY` 载荷（经 §5 第 5 条的 `grant_unlock()`），起点是初始容量常量（§6.3）。
    - **明确禁止的路径（P7 红线，与位次同源）**：**任何靠消耗物品 / 重复开盒 / 按持有量、开出总数、游玩时长 / 用某类物品或券兑换来增加容量的设计，一律否决。** 理由：核心 §4.1.1 与 P7 已经把"功率成长"锁死在**内容门控**上；容量若可随重复劳动增长，就退化为"刷量指标"，玩家会把开盒从"做决定"改成"刷容量"，中心机制（燃料还是引擎）当场的压力反而被消解。
    - **也不得提供任何"临时扩容 / 扩容道具 / 付费扩容"接口**（核心 §13.2 已排除付费）。
    - **容量只增不减**：不因消耗、迁移、读档或退款而下降；`grant_unlock()` 的幂等键覆盖重复发放（第 5 条）。
    - **容量的占用与溢出判定完全不在本系统**（核心 §4.7：产出溢出判定在 02 的 `grant()` 内部）。本系统在这条轴上的职责**只有发放**——即保证"容量会随里程碑成长"（核心 R14 对策②），而"装不下会怎样"由邮件兜底，**永不丢失**（对策①）。
15. **仓库与邮件是同一个实例列表的两个位置（核心 §14.2 铁律 9，v0.9 新增）**：本系统在存档层只做两件事——**逐条落盘 `location`** 与**落盘 `warehouse_capacity`**。由此推出六条硬约束：
    - **读档不得重算 `location`**：不得按容量重新判定、不得把装不下的实例"顺手"搬进邮件，也不得删除邮件侧实例（那会让持有位置随占用率变化而漂移，并给 02 的 `grant()` 造出第二个判定源）。
    - **`count()` 只统计 `location == warehouse`**——因此 §8.2 中"物品持有量"的核对读到的**天然只含仓库**；本系统**不得**为了对账把邮件实例加回去。
    - **领取只改 `location`**（核心 §4.7）：不创建实例、不重分配 `serial`、不重跑幂等判定；因此**实例数在任何领取操作前后完全不变**（T17 ⑤）。
    - **邮件无上限、不过期**：因此"仓库满了"永远不是死局（核心 R14 对策①）；本系统**不得**给邮件加任何上限、过期或自动清理逻辑。
    - **守恒等式按全部实例（裁决 12，v0.9）**：`total_granted − total_consumed == Σ 全部现存实例`——**含邮件侧**。`count()` 只是**带 `location` 过滤的查询**（`count(c, q, &"warehouse")` 是等式的一个子集，`count(c, q, &"mail")` 是另一个子集，裁决 14），**不得**用仓库口径的 `count()` 去反推总量，也不得据此写"仓库 Σcount == 差值"的断言——那在**有邮件条目时必然失败**（T17 ⑥ / T20）。
    - **只有被动产出会进邮件（裁决 17，v0.9）**：`location == mail` **只**由**被动产出（开盒）**的溢出产生；**主动操作（转化 / 拆卸返还）放不下时整个操作被拒绝**——**不产生实例、不产生任何存档变更**。因此存档层**不存在**"主动操作的失败墓碑"，也**不得**为它写入任何条目（若写，就等于承认"销毁了源、产出进了邮件"的净损失路径）。
16. **主动丢弃是主动行为，不是"产出丢失"（v0.9 裁决 16）**：玩家可主动销毁仓库内任意实例（入口 / 二次确认 / 批量归 `08-ui-panels.md` R-22 / §9.7）。在存档与进度侧，它的记账只有这几条：
    - **只改实例列表与 `total_consumed`**：被丢弃的实例从存档消失（与"被消耗"同一条路径），**守恒等式照常成立**（第 15 条）。
    - **不得回退任何不可逆记账**：`collected` / `duplicate_count` / `serial_counters` **一律不变**（第 13 条：收录是"曾开出过"的事实——交付任务尚且不让它退格，主动丢弃更不能）；图鉴格子**不得**退回剪影。
    - **不得给任何回报**：**不产生**新实例、不返还券、不换算任何资源——否则它会变成第二条产出路径，与"销毁"语义冲突。**它也不写 `draw_log`**（丢弃不是兑现），见 §11 Q11。
    - **P5 不适用于此**：P5 管的是**被动产出不得丢失**；丢弃是玩家**主动**行为（核心裁决 16）。本系统**不得**以"违反 P5"为由拒绝提供丢弃路径——**没有它，"仓库满"会变死局**。

17. **`Box` 的五个字段必须随盒子一起持久化（v0.10 / v0.14，核心 §4.1.2 / §16.5）**：`Box` 下挂着 **`box_id`（身份，`String` = `Uuid.v4()`）**、**`series_id`**、**`item_pool`（物品池，生成数据的凭证）**、**`modules`（模块列表，`Array[Module]`）**、**`uses_remaining`（总寿命预算，v0.14 新增：每盒可变、按套系品质初始化 **10–25**（品质 1→10 / 2→15 / 3→20 / 4→25）；**镶嵌一个模块 −1、兑现一次 −1**，共用同一计数器；**归零即被摧毁**）**，**五个都要入档**（`pending_boxes` 块，§4）。五条硬约束：
    - **缺任一个即出事**：若不入档，读档后全部盒子会**塌回同一个基础池**——"分批"（核心 §4.1.2 / §4.6）在载入瞬间消失；若丢 `box_id`，"哪个盒子"失去唯一数据源（缓存 / 日志 / 重放无法指认）；若只丢 `modules`，玩家已投入的**模块成本凭空蒸发**（模块锁定进盒子 ⇒ 丢了模块就是丢了资产，与 P5「重复永不是空手」同型的负体验）；**若丢 `uses_remaining`，读档就等于白送次数**（它是**玩家进度**，v0.14）。
    - **落盘的是"输入"**：`box_id` / `series_id` / `item_pool`（落盘子集五项：`box_id` / `series_id` / `regular_count` / `socket_count` / `revision`，其中前两项就是盒子条目上那两个键）/ `modules`（**已占用槽位的稀疏序列 `{index, module_id, quality, socketed_at}`**，**空位不必存**、但 **`index` 必须落盘**，否则位子占用无法还原）/ **`uses_remaining`（单个整数，与 `item_pool` 子对象无关）**；**池子的当前状态是「`item_pool` + `modules`」的函数**（由 05 推导、07 求值，核心 §4.1.2）。本系统**只落盘输入**，**不落盘任何池子状态**（第 18 条）。
    - **`box_id` 只生成一次，此后一律"读回落盘值"（本条防的是第二套 id 生成机制）**：它在 01 的 **`grant_box`** 里生成一次（`Uuid.v4()`）并**随盒子落盘**；**重放 / 读档 / 迁移都只能读档里那个值，绝不重新生成**——这与 README §3.12 / 裁决 13 的既有模型一致：**幂等靠"重放同一个已记录的值"，不靠"重算出一个相同的值"**。**不得**发明 `Uuid.v5` / 下标派生 / 查表拼串之类的确定性派生（那会引入第二套 id 生成机制，并让身份有两个来源）——**稳定性来自持久化，不是来自派生**。**唯一例外**：v4 及更早的档**没有身份可读**，由 v4 → v5 迁移**签发一次**（§7.4 第 1 / 7 条）。**`uses_remaining` 适用同一条纪律**：它是**输入（且可变）**，**键存在时读档 / 重放一律读回原值、不得重算、不得按品质补满（哪怕它是 `0`）**；**只有缺键才按该盒所属套系品质补齐初始预算（10/15/20/25）**（v0.14 / §7.4 第 8 条）。
    - **`modules` 的运行期与落盘形态不同，且 `Module` 不含 `slot`（不得给模块自带槽位）**：运行期是**长度恒 == `socket_count` 的定长数组**（空位为空项、**下标即槽位号**），落盘是**只含已占用槽位的稀疏序列（外加由下标生成的 `index`）**；`Module = { module_id, quality, socketed_at }`——**槽位一律来自数组下标**。所以"把空位当空项写进档"是错的，读档要按 `socket_count` **重建定长数组**、把每项放回它的 `index` 位；而给 `Module` 加一个 `slot` 字段就是**两个事实来源**（下标 vs 字段），二者会静默不一致（§4）。
    - **读档不得重算 `modules`；盒子归零即被摧毁**：不得按"当前套系施工台"或"最高品质套系"改写任何盒子的 `modules`，**不得把某个盒子的配置复制给同套系的其它盒子**（那是 P7 v0.10 明令否决的"免成本复制同一套配置到任意多个盒子"，核心 §7）；**v0.14 改口径**：**镶嵌一个模块 −1、兑现一次 −1（共用同一`uses_remaining` 预算，没有第三个消耗点）**；**归零（`== 0`）⇒ 盒子立即被摧毁**——连同其 `box_id` / `item_pool` / `modules` **一起消失**（**"次数归零即摧毁"哪怕从未兑现**——由"**镶嵌 + 兑现累计到 0**"触发；**不是**靠"装满位子"：**预算 10–25 远大于位数 2/3/4/5**），且不写回套系、也不被同套系其它盒子继承，**盒数增加不改变任何既有盒子的池子**（核心 §16.5）。
18. **池子的"当前状态"是派生值，一个字段都不入档（v0.10 新增）**：**`weights_bp` / `void_mass_bp` / `probs` 一律不写进存档**——它们是「`item_pool` 基础数据 + 该盒 `modules`」的**计算结果**，载入后由 `PoolService` **逐盒重建**。这与 `count_index`（02 的派生计数缓存）与 `warehouse_used`（占用派生量）**同类**：**派生值不入档，只落输入**。**`revision` 不属于派生状态**——它是 `ItemPool` 的字段，**随盒子落盘**（§4 / §5 第 17 条）。
    - **理由**：存它等于**把函数的结果当成第二个事实来源**——两份数据一旦不同（写档路径与重建路径分叉、旧档残留、修 bug 后规则变化），就会出现"存档说的"与"规则算的"两个池子，而**没有任何依据能判定哪个对**。这与 README §3.2（单一写入入口）和"`count` 是派生值"（v0.8）是同一条纪律。
    - **代价与前提**：**重建必须无损**——载入后重建出的池子状态必须与存档前**逐项相等**（**T24 是新增强制项**）。若不无损，就不许把它排除在存档之外。
    - **唯一仍然落盘权重与 `void_mass_bp` 的例外是 `draw_log.pool_snapshot`**：那是**兑现时刻的历史冻结日志**（核心 §14.2 铁律 7 要求，T2 逐条复现依赖它），回答"当时是什么样"——**它是日志，不是状态**，不受本条约束；其中模块信息按稀疏序列写作 `modules`（`socketed` 这个键名已被否决）。**但要与 `pending_boxes` 分清**：快照是 `draw_log` 的字段，盒子条目里**不允许**出现任何权重类键（T21 有键集合断言）。
    - **`revision` 的推论（v0.10 改口径）**：它是 `ItemPool` 的**每盒编辑修订号**（主副本随盒子落盘，派生状态里只是镜像），因此**跨会话单调、每盒各自独立**；读档**不得**把它归零或重算，也不得断言"载入后重新起算"（那是它还在派生状态里的旧口径，已作废）。
19. **~~保底与保底计数器按套系计、不随盒子走~~（原 v0.10 第 19 条）——**整条随 v0.11 删除保底而作废**：`pity_counters` / `pity_counter` **不存在、不入档**；抽取**无状态**（`roll(evaluation, seed)`，无 `pity_counter` 入参）；`void` 不推进任何计数器（核心 §4.1 / §5.6 / §16.6）。**`collected` 与图鉴照旧保留**（收藏口径与保底无关，§5 第 13 条 / 裁决 11）。**代价**：全收集尾部**不再有任何保证**（核心 **R15** / **D18**）⇒ **§11 Q17**——**v0.13：本项已大幅缓解**（隐藏款删除后不再有"无法被编辑影响"的那一款，残留风险变成"抬缺口很贵"，见 §11 Q17）；**禁令**：**不得以"隐式必出"复活保底**——将来若要缓解尾部，机制必须**可公布可查**（P1 / P6）。

## 6. 参数表（推荐值 + 调参旋钮标记）

### 6.1 结构与解锁节奏

| 参数 | 推荐值 | 🔧 | 说明 |
|---|---|---|---|
| 已释放套系总数 | 切片 1 / 目标 6–8 | 🔧 | 内容量 = 进度容量（R11） |
| **套系品质档位数 / 已解锁最高档** | 切片只出 1 档（**品质 2**，核心 §13.1）/ 目标 4 档 | 🔧 ★ | **直接决定 ρ 上限**——档位上限即施工台功率上限（§5 第 10 条）；4 档是否全出见 §11 Q5 |
| 模块品质档位数 / `module_quality_ceiling` 初始值 | 4 档 / 初始 1 | 🔧 | 开局只能产出最低档模块（核心 §14.3） |
| **D13 · 模块品质释放节奏** | **每 2 个里程碑 +1 档**（1→4 共 6 节点） | 🔧 ★ | **R11 关键**：这是内容释放的主要载体，不由里程碑一次性全开 |
| 里程碑链节点数 | 切片 1 / 目标 8–10 | 🔧 | 与内容产能同阶 |
| **仓库容量初始值 / 解锁节奏（v0.9，核心 D15 / D16）** | 初始 **1000**（示意）/ **每 2 个里程碑 +500** | 🔧 ★ | **内容门控**：容量只能由里程碑解锁（§5 第 14 条）；数值须与 `ItemDef.size`、任务需求向量、开盒产出量**一起标定**，切片阶段实测（核心 D16） |
| 解锁顺序模板 | 新物品类别 → 模块品质 +1 → 新套系 + 套系品质解锁 → 模块品质 +1 → … | 🔧 | 交错释放，避免同类内容断层（R7）；**品质梯度不宜过陡**（§11 Q6 / 核心 R13） |

### 6.2 进度节奏表（核心 §10.2 的数据化）

| 阶段 | `rho_min`（含） | `rho_max`（不含） | **最高套系品质**（决定 ρ 上限） | 池子状态 | 收集状态 | 预期释放 |
|---|---|---|---|---|---|---|
| 开局 `opening` | 0.0 | 0.9 🔧 | 1（8 个常规物品 / 2 位） | 原始池 | 零星几个物品 | 无 |
| 破局 `breakthrough` | 0.9 🔧 | 1.1 🔧 | 1（8 个常规物品 / 2 位） | 首次镶嵌（排除无用物品） | 首个套系过半 | 新物品类别 |
| 起飞 `takeoff` | 1.1 | 3.0 | **2**（8 个常规物品 / 3 位） | 模块开始集中概率 | 快速补全前期套系 | 模块品质 +1 / 新套系 + 套系品质解锁 |
| 工程期 `engineering` | 3.0 | 10.0 | **3**（12 个常规物品 / 4 位） | 每次镶嵌都是替换（核心 §3.3） | 长尾物品显形 | 模块品质 +2 / 套系品质解锁 |
| 收官 `endgame` | 10.0 | 0.0（无上界） | **4**（12 个常规物品 / 5 位） | 池子逼近只剩缺口物品 | 集齐（v0.13：**全部物品**，不再有"隐藏物品除外"） | 最后解锁 + 全收集 |

**最高套系品质列（v0.6 新增）就是 ρ 上限的直接来源**：核心 §2.4 中"跨套系才增长"的功率在这一列上被落成节奏——玩家在某一阶段最高能施工到哪一档，决定他此刻的位子上限，从而决定 ρ 能爬到哪。档位对应的物品数 / 位数取自核心 §4.1.1（🔧 旋钮）。
ρ 区间为 🔧 旋钮，必须**无重叠、无空隙**地覆盖 `[0, ∞)`；阶段判定只读 `EvalService` 的 ρ（`void` 压低 `m_bar` 的效果已含在 ρ 内，见 §5 第 8 条），**最高套系品质**、池子状态与收集状态三列只作文案与验收对照，不参与计算。

### 6.3 存档

| 参数 | 推荐值 | 🔧 | 说明 |
|---|---|---|---|
| 存档路径 | `user://save.json`（+ `save.bak`） | — | 核心 §14.1 `save_service.gd` |
| `draw_log` 保留条数 | 首发不裁剪 | 🔧 | 裁剪策略未定，见 §11；**不得静默裁剪** |
| 自动存档时机 | 每次兑现后、每次解锁发放后 | 🔧 | 保证 `draw_log` 与图鉴不脱节 |
| **每实例存档体积（v0.8）** | **约 120 B**（`instance_id` UUID 约 36 B + `item_id` + `acquired_at` + `serial` + **`source`（大头）**） | — | 核心 §4.2.2 第 4 条。**不得为省体积砍 `source`**（切断与 `draw_log` 的对应，见 §4.2）；要省先裁 `draw_log`（Q3） |
| **5000 现存实例的实例区体积（v0.8）** | **约 600 KB** | — | **估算值**，必须实测：见 §11 **Q8**（切片阶段必做） |
| **`serial` 分配口径（v0.8）** | `serial = serial_counters[item_id]` 自增后的值；非开盒来源固定 `0` | ❌ | **非旋钮**：编号必须与实例自洽（§5 第 12 条 / T16） |
| **`location` 的存档开销（v0.9）** | 每实例 **约 +20 B**（`"location": "warehouse"`） | — | 核心 §14.2 铁律 9。**不得为省体积省略该键**——省略等于丢掉"这件东西在哪儿"的事实，读档后要么丢实例（违反 P5）要么必须反推（把派生值变成事实来源）。体积实测并入 Q8 |
| **`warehouse_capacity` 的存档（v0.9）** | 单个整数（`progression.warehouse_capacity`） | ❌ | **非旋钮**：容量是**解锁进度**，必须入档且只增不减（§5 第 14 条 / T19）；不得由 `size` 之和或持有量推导 |
| **`uses_remaining` 的存档（v0.14）** | 单个整数（每盒一个；**初始 10/15/20/25 按品质**） | ❌ | **非旋钮**：它是**玩家进度**（"这个盒子还剩几次寿命"；**镶嵌 −1 / 兑现 −1**），**必须入档**且随盒子落盘；**键存在时读档 / 重放 / 迁移一律读回原值、不得按品质补满（哪怕它是 `0`）；缺键时按品质补齐 10/15/20/25**（§5 第 17 条 / §7.4 第 8 条 / T21） |
| **每个盒子的落盘开销 / 囤积总量（v0.10 新增，粗估，须实测）** | **约 150–200 B/盒**（未配置～1 个模块）；**每个已镶嵌模块再 +约 65 B**（`{index, module_id, quality, socketed_at}`）→ 3 个约 **350 B**、满 5 位约 **470–500 B**；总量量级 **100 盒 ≈ 20–35 KB / 1000 盒 ≈ 200–350 KB** | — | 口径 = **只存"基础池引用 + 冻结元数据 + `modules`"**：`box_id`（UUID 约 36 B）+ `series_id` + `source` + `acquired_tick`（约 90 B）、`item_pool` 元数据（`regular_count` / `socket_count` / `revision`）约 80 B、`modules` 稀疏序列按**已占用槽位**计（**`series_quality` / `base_items` / `base_weights` 不落盘**，由 `series_id` 解析，§4）。**这是量级、不是预算**——与 Q8 一起实测：见 §11 **Q12**（体积 + **载入耗时**：每盒都要重建池子、**随盒数线性增长**） |

## 7. 流程 / 状态机

### 7.1 收录流程

```
GachaService.roll(evaluation, seed) 结算（01）
  ──▶ 02 落实例（ItemService.grant）：新 UUIDv4 + acquired_at + source{kind: &"gacha", …} + serial（= serial_counters +1）
  ──▶ 本系统 record_result(series_id, result)
      ├─ result.is_void → **无实例**；图鉴 / series_progress / collected / duplicate_count / serial_counters 全不变（§5 第 1 条）
      ├─ 首次收录 → collected = true → 重算 gap_count → 图鉴点亮
      └─ 重复     → duplicate_count += 1（实例本身已由 02 持有，见 02-item.md）
  ──▶ 本系统 append_draw_log({seed, pool_snapshot, state_snapshot, item_id, is_void, quality})
  ──▶ 重算 current_phase（只读 EvalService 的 ρ，纯呈现）
```

**顺序是硬的（v0.8）：** **02 先创建实例（含分配 `serial`），本系统再记图鉴与日志**——若反过来，`draw_log` 会记录一次"图鉴已收录但实例不存在"的中间态，中断补送时无法判定幂等。`void` 是唯一不产生实例的分支。

### 7.2 里程碑链状态机

```
LOCKED ──(requires 全部 COMPLETED)──▶ AVAILABLE ──(03 受理任务)──▶ IN_PROGRESS
                                          └─(03 结算 TaskDef）──▶ 本系统 grant_unlock() ──▶ COMPLETED
```

同一节点内两个写入方**顺序固定**：`03 先结算 TaskDef.rewards` → `本系统后发放 MilestoneDef.unlocks`（`[补充]`：同一事务内两个写入方的顺序必须确定，否则存档字节级不稳定）。状态取值 `LOCKED=0 / AVAILABLE=1 / IN_PROGRESS=2 / COMPLETED=3`。

### 7.3 全收集状态机

```
COLLECTING ──(所有已解锁套系的 regular_count 个物品全部集齐)──▶ NORMAL_COMPLETE   ← 对应 §6.2「收官」的收集状态
           ──(全部物品收录 — v0.13：与 NORMAL_COMPLETE 同义)──▶ FULL_COLLECTION
           ──(新套系释放)──────────────────▶ 回到 COLLECTING（标记保留，见 §5 第 6 条）
# v0.13：池中全部是常规物品（隐藏款已删除）⇒ 两个状态的判据相同；状态机结构保留、不删不改（§5 第 6 条）
```

### 7.4 存档流程与版本迁移

```
收集状态 ──▶ to_dict() ──▶ JSON.stringify(sort_keys = true) ──▶ 写 save.json.tmp
        ──▶ 备份旧档为 save.bak ──▶ 原子替换为 save.json
读取：load() ──▶ 校验 schema_version ──▶ 低于当前版本则 migrate() ──▶ 反序列化
```

`[补充]`（原子写与 `save.bak`）：崩溃时 JSON 存档不得半写损坏，否则玩家直接丢档。
`[补充]`（`schema_version` 与迁移函数约定）：每次改字段必须递增版本并提供 `migrate_vN_to_vN+1()`；迁移必须幂等，且迁移后四条红线与往返稳定性均须成立（§10）。
**v1 → v2 迁移（v0.6，`[补充]`）**：v1 档没有套系品质概念，迁移时 ① 为每个 `pools` / `pool_snapshot` 条目按其 `series_id` 回填 `series_quality` 与 `regular_count`（取自 `SeriesDef`，与 v0.5 的 8 个常规物品 / 3 位一致 → 品质 2）；② 回填 `unlocked_series_qualities = [1..该档最高品质]`（**只增不减**，与"玩家已解锁套系的最高档"对齐，保证最高可施工档位不因升级存档而回退）。理由是迁移必须把新进度轴的还原点补齐，否则读档后 P7 的档位不可判定。

**v2 → v3 迁移（v0.8，`[补充]`）**：v2 档把持有量存为"每个 `(category, quality)` 一行计数"（`inventory.counts`，**没有实例**）。v2 → v3 的规则**必须确定、必须保量、必须幂等**：

1. **展开计数为实例**：对持有量块的每个 `"<category>:<quality>"` 键（v2 的 `entry_key` 形态；本文记该块为 `inventory.counts`，旧档若键名不同按此形态识别），按其 `count` 生成 **N 个实例**（N = 该键的 `count`）。v2 档若**完全不含**持有量块，则迁移得到空实例列表（不是错误）。
2. **`item_id` 的取法**：v2 的键**不含 `item_id`**，故取**该 `(category, quality)` 下 `item_id` 字典序最小者**（来自 `ItemDef` 表）。这是**有损但保量**：迁移后该键的实例数 == v2 的 `count`，因此**数量与 ρ 完全不受影响**；丢掉的只是 v2 **从未记录过**的字段（`serial` / `acquired_at` / `source`）。
3. **`serial` 依次回填（与 `serial_counters` 对齐）**：对每个 `item_id`，其 N 个实例按 **`serial = 1 … N`** 依次分配（`acquired_at` 相同，故以数组下标为序），并回填 **`serial_counters[item_id] = N`**——迁移后恒有 `serial_counters == max(现存实例的 serial)`（T16）。**`duplicate_count` 不得用于回填 `serial` / `serial_counters`**：它可能大于现存实例数（消耗过的实例不计入 `count`），拿它回填会让编号越过实例，破坏自洽。
4. **`acquired_at` 取迁移时刻**（Unix 秒，同一批同一值）。理由：v2 无法还原历史时刻；取迁移时刻可保证该字段非零、可排序、可显示（呈现规格见 `08-ui-panels.md` §9.3b）。
5. **`source` 一律记为 `{ kind: &"migrate" }`**（核心 v0.9 裁决 4 的取值；旧稿的 `&"migration"` 作废）。理由：迁入的实例**不是开盒产出**，不得伪装成 `kind: &"gacha"`（否则溯源会指向不存在的 `box_seed` / `draw_index`，并让"来自哪个盒子"显示假信息）。其**呈现必须与开盒实例可区分**（`kind != &"gacha"` 即天然可分，规格归 08）。
6. **迁移幂等**：迁移完成后 `schema_version` 即为 3，**再跑一次必须不产生重复实例**（已为 v3 的档不进本迁移）；`item_id` 选取、`serial` 分配、`acquired_at` 取值三步**全部是确定性的**（同输入必得同输出），因此"迁移 → 往返 → 再迁移"字节级稳定（T15）。
7. **`collected` / `duplicate_count` / `draw_log` / `pools` 一律原样保留**，**不得**由实例列表推导或重算（§5 第 13 条）。

**v3 → v4 迁移（v0.9，`[补充]`）**：v3 档有实例列表，但**没有 `location`、也没有仓库容量**。规则同样必须**确定、保量、幂等**，且**绝不丢弃**：

1. **`location` 一律回填 `&"warehouse"`（本系统的裁决）。** 理由：v3 的实例语义就是"我持有的东西"，v3 既无容量也无邮件；把它们直接回填成 `mail`，会让玩家的持有**在一瞬间失去可用性**（邮件实例不可用于交付 / 装配 / 镶嵌 / 转化，核心 §4.7），读起来就是"东西被没收了"——与 P5 的立意直接冲突。**"默认全部留在玩家手里"是唯一不制造负体验的默认值**；真装不下时再由第 3 条按确定性规则处理，且那部分**可领取、不丢失**。
2. **容量初始值的定息**：`warehouse_capacity = WAREHOUSE_CAPACITY_INIT + Σ（该档 `milestone_state` 中已 COMPLETED 的里程碑所携带的 WAREHOUSE_CAPACITY 载荷的 magnitude）`，按 `MilestoneChainDef` 顺序累加，**下限 `WAREHOUSE_CAPACITY_INIT`**。理由：容量是**内容门控的进度**（§5 第 14 条），迁移必须还原"玩家已走到哪一步"，而不是一律打回初始容量——后者会让所有老档当场爆仓，也会让同一条进度轴在迁移前后**回退**（与 v1 → v2 回填 `unlocked_series_qualities` 的理由完全同源）。
3. **若迁移后 `Σ size(仓库侧实例) > warehouse_capacity`：按 `acquired_at` 升序保留，其余转 `mail`。** 逐实例贪心：按 `acquired_at` 升序累加 `size`，**累加值 ≤ 容量**的实例留在 `warehouse`，**第一个越界的实例及其后全部改为 `mail`**（同刻按 `instance_id` 字典序，与 `02-item.md` §5.5 同一打破规则，保证确定性）。两条禁令：**不得为迁就持有量而上调容量**（那等于承认"靠堆积换容量"，违反 §5 第 14 条 / P7）；**更不得丢弃任何实例**——**实例总数在迁移前后必须完全相等**（T18），这是核心 v0.9 的"装不下就进邮件 ⇒ 产出永不丢失"在存档层的落点。
4. **迁移只写两个字段**：逐实例写 `location`、写 `progression.warehouse_capacity`。`instance_id` / `item_id` / `acquired_at` / `serial` / `source` / `serial_counters` / `collected` / `duplicate_count` / `draw_log` / `pools` **一律原样保留**（延续 v2 → v3 第 7 条的精神）。**不得**借迁移顺手"修正" `serial` 或重算图鉴。
5. **迁移幂等**：迁移完成后 `schema_version` 即为 4，**再跑一次不得产生任何 `location` 或容量的变化**；第 1 / 2 / 3 步**全部确定性**（同输入必得同输出），因此"迁移 → 往返 → 再迁移"字节级稳定（T18）。
6. **邮件侧不是死局（必须一并说明）**：核心 §4.7 已定"**消耗类主动操作不检查空间**"——玩家把仓库里的物品交付 / 装配 / 镶嵌 / 转化腾出空间后即可领取邮件，容量还会随里程碑继续增长。因此第 3 条产生的邮件条目**不构成进度损失**；呈现层需在首次进入时给出一次说明（`08-ui-panels.md` §9.7）。

> **v0.9 迁移的代价必须说清**：v3 档**不存在"物品在哪儿"这个事实**，所以 v4 的 `location` 是**按确定规则重建**的位置，不是历史真实位置；同理容量是按里程碑进度**定息**的，不是 v3 曾经有过的数。这是最小损失的可行规则——任何"看起来更真实"的逐实例猜测都是编造。**唯一不可妥协的是数量守恒**：迁入实例数 == v3 的实例数。

> **迁移的代价必须说清**：v2 的计数**无法还原**具体 `item_id` 的归属与真实开盒时刻，所以 v2 玩家的 `serial` 是**从迁移时刻的持有量连续编号**的（不是历史真实编号），且迁入实例的 `source` 只有 `kind`。这是**最小损失的可行规则**——v2 存档里根本不存在这些信息，任何"看起来更真实"的回填都是编造。

**v4 → v5 迁移（v0.10，`[补充]`）**：v4 档的池子是**每套系一份**（`pools[series_id]`），**没有任何 per-box 池子**；v4 的盒子（若有清单）**三个新字段都缺**——没有 `box_id`（v4 的盒子没有身份）、没有 `item_pool`、也没有 `modules`（v4 连"模块属于哪个盒子"这个概念都没有）。规则同样必须**保量、幂等**：

1. **逐盒签发/回填四个字段**：**`box_id`** —— **仅当该盒没有 `box_id` 时签发一次 `Uuid.v4()`**（v4 的盒子没有身份，这次签发就是它们的"首次持久化"；**档里已有 `box_id` 的盒子一律原样保留、绝不重新签发**）；**`item_pool`** = 该盒所属套系的**基础池引用 + 冻结元数据**（`series_id` + `regular_count` / `socket_count`，**`revision` 回填 `0`**——该盒子的池子尚未被任何编辑写过，与"`modules` 空序列"自洽）；**`modules`** = **空序列 `[]`**；**`uses_remaining`（v0.14）** = **文档里已有该键则原样保留（读回、不重算，哪怕它是 `0`）；缺键则按该盒所属套系品质补齐初始预算（品质 1–4 ⇒ 10/15/20/25）**（**已裁决 = 按品质补齐**，核心 §15 **D20③** / §11 **Q19**；分层与红线见下条）。**⇒ v4 的 `pools[series_id].socketed` 一个模块都不落到任何盒子上，v4 的编辑后权重（`weights_bp` / `void_mass_bp`）也一个字节都不回填。**
   - **盒子清单的来源**：v4 档**若确实含囤积清单块**，**原样搬入**并逐盒补齐这三个字段（**一颗都不许丢**，T23 ①）；若该档不含清单块（**既有 schema 示例里确实没有它**——见 §11 Q13 ①），迁移后 `pending_boxes` 为**空数组**，这不是错误。
2. **理由（四段，必须写明）**：
   - **`modules` 回填空序列，是因为 v4 根本没有这个量**：v4 的 `socketed` 是**套系施工台的状态**（不属于任何盒子、可反复替换与拆下、且形状是"池子里的一个槽位数组"）；v5 的 `modules` 是**盒子的一个并列字段**（`Array[Module]`，镶嵌即锁定；**v0.14 起：模块在盒子被摧毁前一直挂着**——"随兑现一同消耗"是 v0.13 及以前的口径、**已作废**，核心 §4.1.2 / §16.9）。**把套系级 `socketed` 搬成某个盒子的 `modules` 是类型错误**，不是保真——`socketed` 的空位占位（`""`）更**不得**变成 `modules` 里的空项（落盘形态是**只含已占用槽位的稀疏序列**，见 §4；写空项会让"空序列 = 未配置"这个定义失效，直接破坏 03 §10 G 第 25 条）。
   - **"复制给所有同套系盒子"被 P7 明令否决**：那正是"**免成本把同一套配置复制到任意多个盒子**"（核心 §7 的否决项）；一次读档就会把套系级的**一份**编辑放大成"**盒数 × N**"的编辑强度，把 P7 从经济约束打回"不存在"（核心 §16.5）。
   - **"只给某一个盒子"同样是错的**：选哪个盒子**没有任何可解释的依据**（"第一个"？"最近一个"？），且等于给老档一个"免费保留配置"的例外——玩家无法理解为什么是这个盒子，违反 P1（一切可查可算）与"迁移必须确定"的要求。
   - **损失面必须诚实说明**：v4 的施工台状态**不是持有资产**——v4 档里**没有任何"未镶嵌模块"的持有清单**，模块一旦镶嵌既不能变回物品，拆卸也只返还 50% 素材（核心 §16.5 已明确：**模块是消耗品、模块本体不回收、不存在模块库存**——否则同一个模块能在任意多个盒子上轮换，D17 的跨池锚点直接归零）。因此本步**不产生任何新的资产损失**；真正的资产（物品实例、`collected` / `duplicate_count` / `serial_counters` / `draw_log` / `warehouse_capacity` / `unlocked_*`）**一律原样保留**。
3. **施工台编辑的折算裁决（明确，不留白）：一律「丢弃」，不折算成等价物品、不返还、不补偿。**
   - **裁决内容**：`pools[series_id].socketed` 里列出的模块**不产生任何物品、不返还任何素材、不进任何余额、不写 `total_granted`**；`migrate_v4_to_v5()` 里**没有这条分支**——不得留下"若配置允许则折算…"的 `if`、不得留下 TODO（留白会在实现期变成第二个写入源）。
   - **为什么选丢弃，而不是折算成等价物品**（三条理由）：① **折算率没有任何依据可依**：v4 的模块制造时消耗 `ModuleDef.item_cost`、**拆卸时只返还 50%**——"折算"要取 100% / 50% / 按 `socket_count` 折算 / 其它，**取哪个都是编造**，而 v0.10 的模块成本（核心 **D17**）**本身还没标定**，此时定折算率等于在未标定的旋钮上再叠一个数；② **折算会造出 v4 从未存在过的产出路径**：它必然 `grant` 新实例并改写 `total_granted`，与守恒等式（`total_granted − total_consumed == Σ 全部实例`，裁决 12）以及"迁移不发放资产"的既有先例（v2 → v3 只补 `serial`/`acquired_at`/`source`，v3 → v4 只补 `location`/容量）**直接冲突**；③ **它不是持有资产**：v4 的施工台状态是"**当前生效的配置**"，不是"你攒着的东西"——v4 档里**根本没有"未镶嵌模块"的持有清单**，所以**丢掉它不等于丢东西**（真资产——实例、图鉴、编号、日志、容量、解锁——一律原样保留）。
   - **诚实说明代价**：老档玩家会失去那份套系级编辑、且**拿不到补偿**。接受它的理由是本版把"池子归谁"重写了，而那份编辑在新结构里**无处安放**（放给所有盒子 = P7 明令否决的免成本跨池复制；放给某一个盒子 = 任意且不可解释）。**若产品将来决定补偿**，那必须是**另一条独立设计**（需上游立项、单独标定折算率并与 D17 一起校准），**不属于 v4 → v5 迁移**，也不得回填进本步。
   - **其余禁令**：**不得**给任何盒子（含"第一个""最近一个"）预置模块；**不得**把 `socketed` 的模块 id 写进任何盒子的 `modules`；**不得**改写 `total_granted` / `total_consumed`。
4. **派生状态一概不由迁移产出**：`weights_bp` / `void_mass_bp` / `probs` **迁移时既不回填也不落盘**（它们不入档，§5 第 18 条）——迁移只写"输入"（`box_id` / `item_pool`（含 `revision = 0`）/ `modules`），载入后由 05 逐盒重建（T24 验证重建无损）。**注意 `revision` 不是派生状态**：它是 `ItemPool` 的字段，迁移**必须**给出（= 0，见第 1 条）。
5. **v4 的 `pools[series_id].pity_counter` 一律丢弃（v0.11）**：v0.10 曾把它"**取出**"到 `pity_counters` 块；**保底删除后该搬运步骤作废**——`pity_counter` **不搬运、不落盘、不建新块**（与 `socketed` 同等对待）。因此 **v5 档里没有 `pity_counters`**，**本版没有因保底而产生的迁移步骤**（`schema_version` 仍为 5）；v0.10 写出的老档若带该块，按 §4.1 的规则**读档忽略、下次写档消失**。其 `socketed` / `weights_bp` / `void_mass_bp` **按第 1 / 4 条丢弃**（这正是第 3 段的裁决），`regular_count` / `socket_count` 是 `SeriesDef` 的**冻结副本**、**随 `pools` 块消失后由第 1 条重新冻结到每个盒子的 `item_pool` 上**（`series_quality` 不落盘，由 `series_id` 解析）。
6. **迁移只写 `pending_boxes` 块**：逐盒新增 `box_id`（签发）、`item_pool`、`modules`，保留 `series_id` / `source` / `acquired_tick`；`inventory` / `draw_log` / `progression` **一律原样保留**（延续 v3 → v4 第 4 条的精神）。**不得**借迁移顺手"修正" `modules` / `serial`，也不得重算图鉴。
7. **幂等与"确定性"的边界（必须写清，这里有一个真实让步）**：迁移完成后 `schema_version` 即为 5，**对已是 v5 的档再跑不得产生任何变化**（含 `box_id`：**已有的身份一律读回、不重新签发**）；第 1 / 3 / 5 步的**内容**全部确定性（同输入必得同输出）——**但"给没有身份的老盒子签发 `Uuid.v4()`"是随机动作，因此本步不再满足"同一份 v4 档迁移两次得到逐字节相同的档"**。
   - **为什么接受这个让步**：`box_id` 必须与 `ItemInstance.instance_id` **同型同源**（核心 §4.1.2 定稿：`box_id : String`，`Uuid.v4()`）；**不得**用"确定性派生 id"（`Uuid.v5` / 拿下标或 `series_id` 拼一个）来换字节级稳定——那会造出**第二套 id 生成机制**，也让身份有两个来源（第 1 条已把这条钉死）。
   - **为什么必须在迁移里签发而不是留到载入**：载入后**立刻**需要身份（05 的逐盒重建 / 缓存键 / 08 的选中盒子 / 日志与重放都要"哪一个盒子"），留到首次载入再补会造出"没有身份的 v5 档"这一中间态，且**补发 = 读档写档**（与"载入过程不写档"的 T24 ⑤ 冲突）。**签发一次、写入档之后，它就只是一份持久化数据**（"稳定性来自持久化，不是来自派生"）。
   - **断言怎么写**：T23 的幂等断言只能是"**对已是 v5 的档再迁移零变化（`box_id` 逐位不变）**"，**不得**写成"同一 v4 输入两次迁移字节相等"（那必然失败）。**除首次签发的 `box_id` 外**的每一项仍必须逐位可复现。
8. **v0.14 增补：盒子条目再加一个字段（`uses_remaining`），但版本号不动**：`pending_boxes` 的条目**从四个字段变五个字段**（`box_id` / `series_id` / `item_pool` / `modules` / **`uses_remaining`**），**块的形状不变、schema 仍为 5、不新增迁移函数**（`migrate_v4_to_v5()` 之后不需要 `v5 → v6`）。**本条只规定两件事**：① `uses_remaining` 是**输入（且可变）**——**键存在时，读档 / 重放 / 迁移一律读回原值，不得重算、不得按品质补满（哪怕它是 `0`——那是"该盒已用尽"的合法状态，不许被"好心补满"）**（与 `box_id` 的"**稳定性来自持久化**"同一纪律，§5 第 17 条）；② **载入时若某盒的字典缺 `uses_remaining`，按该盒所属套系的品质补齐初始预算（品质 1–4 ⇒ 10 / 15 / 20 / 25）**——**已裁决（核心 §15 D20③，§11 Q19 已关闭）**：理由是 **`0` 在新语义下等于"归零 ⇒ 摧毁"**，取 `0` 会让**一份旧档的全部盒子在载入瞬间被摧毁**（v0.14 之前的所有存档都缺该键）。★ **补齐的分层**：补齐需要该盒所属套系的**品质** ⇒ 它发生在**能拿到 `SeriesDef` 注册表的那一层**——即 §7.4 载入路径上"由 `series_id` 解析 `SeriesDef`"的那个环节（`load()` / `migrate()` 所在的存档层），**`Box` 自己不去查表**。**只有缺键才补**；**`schema_version` 不动（仍 v5）**——这是"**新增字段 + 载入补齐**"，不是格式变更。**红线**：`uses_remaining` 与 `item_pool` 子对象**互不影响**——它**不得**被写进 `item_pool` 的五项落盘子集，也**不得**由 `revision` / `modules` / 套系品质在读档时推导出来。★ **装置侧的读档不变量（v0.16 登记，与本条并列）**：**开局必须发放一台基础装置**（**开盒 / 装模块的硬门槛**，否则**开局死锁**），**载入 / 新游戏后必须存在至少一台可用于开盒 / 装模块的设备**——那台装置是**玩家进度、必须落盘、读档读回原值、不得凭空再发一台**；**判定的默认形态是"持有至少一台即可"（无参）**，且**设备不消耗、不损耗**（**存档侧不存耐久度 / 使用计数 / 绑定关系**；**若将来改为设备绑定盒子 / 有服务上限，判定入口会变成带 `box_id` 的形式、存档需新增字段**——**可回滚的默认、当前只登记不实现**）；**载入时若发现没有可用设备**，处置（**载入校验失败即报错** vs **补发一台**）**待裁**，**其存档形态与 `schema_version` 亦待裁**（§11 **Q20**；**本文不选边、不发明结构**）。
9. **前序迁移的条款不受影响**：v2 → v3 第 7 条与 v3 → v4 第 4 条里"`pools` 一律原样保留"的话**依然成立**——那两步不碰池子；**本步是唯一改动 `pools` 形态的迁移**。

> **v0.10 迁移的代价必须说清**：v4 档**不存在"这个盒子会开出什么"这个事实**（整个套系只有一份池子）、也**不存在"盒子身份"**，所以 v5 每个盒子的 `box_id` 是**新签发的**、`item_pool` 是**按确定规则回填的基础池引用**、`modules` 是**空序列**——**不是历史真实配置**；v4 那份套系级编辑**结构上无处安放**（第 2 段），裁决是"**丢弃，不折算**"（第 3 段）。**唯一不可妥协的是三件事**：① **盒子一个都不许丢**；② **不得产生任何补偿或任何免费的编辑**（P7）；③ **迁移输出里没有"折算"分支**。

## 8. 与其它系统的接口

### 8.1 里程碑任务链的归属裁决（与 `03-task.md` 的边界）

> **裁决：链骨架归 10，需求与奖励结算归 03。**

| 归谁 | 拥有什么 |
|---|---|
| **10 收集与进度** | `MilestoneChainDef` / `MilestoneDef`：**链的顺序、前置条件、解锁载荷 `unlocks`、未达成预告 `teaser`、发放动作 `grant_unlock()`** |
| **03 任务** | `TaskDef`（经 `MilestoneDef.task_def_id` 指向）：**需求向量匹配、物品扣减、`TaskDef.rewards` 结算（盲盒 / 券）** |
| **共有义务** | 同一任务的两个写入方按 §7.2 固定顺序执行，各自只写自己拥有的数据（README 铁律 2） |

**红线**：`TaskDef.rewards` **不得**包含任何内容释放载荷（新套系 / 新类别 / 模块品质）。内容释放只有一条发放路径：`MilestoneDef.unlocks` → `grant_unlock()`。否则解锁会出现第二个写入源，存档将不可复现。

### 8.2 接口清单

| 方向 | 接口 | 对端 |
|---|---|---|
| 提供 | `is_collected(series_id, item_id) -> bool`（供"未拥有物品权重 ×1.5"判定）；`is_series_unlocked(series_id)` | 01 |
| 提供 | `module_quality_ceiling` / `can_produce_module(module_def) -> bool` | 05 |
| 提供 | `max_series_quality() -> int` / `is_series_quality_unlocked(q) -> bool`（**最高可施工档位**，只读；本系统不写位次） | 05 / 01 |
| 提供 | `is_item_category_unlocked(category)` | 02（`02-item.md`）/ 06 |
| 提供 | `gap_items(series_id)` / `series_progress(series_id)` / `codex_state()`；`current_phase`、`milestone_state`、`full_collection_reached` | 08 / 03 |
| 提供 | `snapshot_state() -> Dictionary`（= `state_snapshot`） | 01 / 07 |
| 提供 | `collected` / `is_collected()` / `duplicate_count`（**图鉴收录与重复次数；不可逆，不由实例列表推导**，§5 第 13 条） | 01 / 08 |
| 提供 | `serial_counters` 的**持久化布局**（字段与键序；**写入仍归 02**）`[补充]` | 02（`ItemService`） |
| 提供 | `warehouse_capacity` 的**发放与持久化布局**（容量数值只能由里程碑解锁，§5 第 14 条；**占用 / 溢出判定归 02**）`[补充]` | 02（`ItemService`）/ 08（占比换算与呈现） |
| 消费 | `TaskService.task_completed(task_id)` 信号 → 若属里程碑链则 `grant_unlock()` | 03 |
| 消费 | `GachaService.roll(evaluation, seed)` 结果 → `record_collection()` + `append_draw_log()`（**实例的创建在同一次兑现中由 02 完成，本系统不读写实例列表，只在 `serial_counters` 的落盘布局上与 02 对齐**；`[v0.10]` 入参是**被兑现那个盒子的池子求值结果** `PoolEvaluation`，不是 `series_id`；`[v0.11]` **入参里没有 `pity_counter`**——抽取无状态） | 01 |
| 消费 | `EvalService.compute(state, box_id).rho` → `current_phase`（**只读，不得回写**；`[v0.10]` 入参**必须能定位到具体盒子**——ρ / `headline` 的参照物是"某一个盒子的池子"，核心 §9 铁律 2 / §14.1，缓存键 = `(box_id, revision)`，归 07） | 07 |
| 提供 | **`Box` 五字段（`box_id` / `series_id` / `item_pool` / `modules` / `uses_remaining`（v0.14））的持久化布局**（`item_pool` 的**落盘子集五项**；`base_items` / `base_weights` / `series_quality` 不落，由 `series_id` 解析；**`modules` 落盘为稀疏序列 `{index, module_id, quality, socketed_at}`**；**`uses_remaining` 落单个整数、读回不重算**；**池子的当前状态一个字段都不入档**）`[补充]` | 01（`pending_boxes` 与 `box_id` 的落盘形态）/ 05（`ItemPool` / `Module` 与逐盒重建） |
| 消费 | `PoolService.get_item_pool(state, box_id)` / `get_modules(state, box_id)`（**只读入口，05 §4.1**；`[v0.10]` 类型已按核心定稿为 `ItemPool` 与 **`Array[Module]`**——**05 §4.1 的签名 `get_modules(state, box_id: String) -> Array[Module]` 与本条一致，落盘的 `index` 由此而来**）→ 读写档时的盒子字段；**05 的 `_rebuild(state, box_id)` 是内部的逐盒重建，本系统不调用、也不缓存其输出**——它只是"输入可以不入档"的前提（§5 第 18 条 / T24） | 05 |
| 消费 | `PoolService.get_pool_state(state, box_id)`（**该盒池子的当前状态**，派生值）→ `draw_log.pool_snapshot`（**兑现时刻的冻结快照**，历史审计用；`[v0.10]` 其模块信息按稀疏序列写作 `modules`（`{index, module_id, quality, socketed_at}`，`socketed` 已被否决），并冻结 `item_pool` 元数据使日志自足） | 05 |
| 消费 | `ItemService` 的**现存实例列表**（只读）→ 存档序列化（**含 `location`**）；`ItemService.count(category, quality)`（派生值，**只统计 `location == warehouse`**，v0.9）→ 套系 / 图鉴侧的核对；`count(category, quality, &"mail")`（裁决 14，仅在需要显示"邮件侧持有"时**显式查询**，不得与仓库读数相加）；`ItemService.warehouse_capacity`（只读）→ 存档序列化 | 02 |

## 9. UI 需求

呈现规格与布局见 `08-ui-panels.md`；本系统**要求必须呈现**以下信息（对应核心 §14.1 的 `scenes/collection/`）：

| 面板 | 必须呈现 | 理由 |
|---|---|---|
| **图鉴 `Codex`** | 按套系分组的 `regular_count` 格（品质 1/2 为 8 格，品质 3/4 为 12 格；**v0.13：原"+1 个隐藏物品"那一格已删除**）；**未收录物品以占位剪影常驻可见**；缺口计数与缺口清单**默认展开，不得折叠**；任何一屏都要能一眼看到"还差几个物品"。**v0.8：收录不可逆**——已消耗的实例**不得**让格子退回剪影（§5 第 13 条） | 缺口可见性是硬要求（§1）；缺口半衰期是周 |
| **套系进度** | **一个数字**：`collected / regular_count`（**v0.13：不再分列常规与隐藏**）；可施工档位（`max_series_quality()`）与各位次的占用可见 | v0.6：分母随套系品质变，且玩家必须看得见自己的施工台上限（P7 的呈现面）。（**v0.13：原"C3：隐藏物品免疫编辑、合并会误导"这条理由已随 C3 作废**） |
| **里程碑链** | 节点列表、当前节点、**未达成节点的 `teaser` 预告** | R11 + R7：内容释放必须被玩家感知，否则 ρ 涨了也"毫无感觉" |
| **全收集表现** | 图鉴满格标记；收官阶段可展开查看"池子逼近只剩缺口物品"的当前状态 | 核心 §10.1「我算赢了它」 |
| **实例的编号与溯源（v0.8，转交 08）** | 本系统不做呈现，但**必须提供**：现存实例列表（`serial` / `acquired_at` / `source` / **`location`**）与 `serial_counters` 读档还原值；`serial == 0` 与 `kind == &"migrate"` 的实例呈现规格归 `08-ui-panels.md` §9.3b。**v0.9**：图鉴 / 套系进度**不得**因**主动丢弃**而退格（§5 第 16 条；丢弃是主动行为，与"交付消耗"同样是"不再持有"，不是"未收录"） | v0.8 的收藏叙事价值（核心 §4.2.1）；读者要知道"这是你的第 N 个"从哪来 |
| **仓库占用与邮件（v0.9，转交 08）** | 本系统不做呈现，但**必须提供**：`warehouse_capacity` 的当前值（占比换算、阈值与线框图归 `08-ui-panels.md` §9.7）；图鉴 / 套系进度侧的持有核对一律走**仓库口径**（`count()`），**邮件侧实例不得计入** | 容量是解锁进度（P1 要求可查）；**邮件不是第二个仓库**（核心 §4.7 的边界必须由界面兑现，而不是让玩家点了才失败） |
| **盒子的剩余寿命预算（v0.14，转交 08 / 01）** | 本系统不做呈现，但**必须提供**：每个盒子 `uses_remaining` 的**读档还原值**（"这个盒子还剩几次寿命"；**镶嵌与兑现各扣 1**）——呈现规格归 `08-ui-panels.md`，清单侧的读数归 01。**本系统只负责它落盘与读回**；`is_exhausted()`（`uses_remaining <= 0`）是**派生判断、不入档**，**不得**在存档层重算或改写该字段 | 寿命预算是**玩家进度**（P1 要求可查，§5 第 17 条）；**被摧毁前模块一直在**——界面不得提前把盒子 / 模块显示成"已消耗"；**镶嵌会真的烧掉寿命**（预算 10–25 远大于位数 2/3/4/5，**装满位子烧不光预算**，但"镶嵌 + 兑现累计到 0"仍会摧毁盒子），界面必须让玩家数得清 |

## 10. 测试点与验收标准

| # | 测试 | 判据 |
|---|---|---|
| T1 ★ | **存档往返一致性** | 存 → 读 → 存，连续 10 轮，`save.json` **字节级完全一致**（哈希相同）；键序稳定（`JSON.stringify(sort_keys = true)`） |
| T2 ★ | **池子快照可复现抽取（必须覆盖 `void`）** | 对 `draw_log` 中**每一条**记录，用其 `pool_snapshot` 还原出**当时的 `evaluation`**（`weights_bp` / `void_mass_bp` 归一化而来）+ `seed` 重跑 **`GachaService.roll(evaluation, seed)`**（`[v0.11]` **入参里没有 `pity_counter`**：抽取**无状态**，`evaluation` + `seed` 即可完全复现；`[v0.10]` 入参是**被兑现那个盒子的池子求值结果**，不是 `series_id`），`item_id` 与 `quality` 必须与日志一致（100% 命中，0 例外）。**含 `void` 的记录必须同样命中**：`pool_snapshot` 一旦漏记 `void_mass_bp`，`void` 就抽不出来（或被误抽成某个物品），这是 `void` 引入后最容易漏的一条。用例集**必须显式包含**至少 1 条 `is_void == true` 的记录 |
| T3 ★ | **版本迁移** | 用 v1 存档跑 `migrate_v1_to_v2()`：① 红线（含 C4 / C6）仍成立，且 `series_quality` / `regular_count` / `unlocked_series_qualities` 已按 §7.4 回填（不是默认值） ② 迁移后往返仍字节级稳定 ③ 迁移幂等（再迁移一次无变化） |
| T4 ★ | **红线 C4 不得被解锁破坏（逐套系断言；v0.10：逐**盒**断言）** | 遍历整条里程碑链，全部达成后，**对每一个已解锁套系**断言该套系的镶嵌位常量 == `SeriesDef.socket_count`（**v0.16：`device_slot_count` 已删除、不再有这条平行断言**）。`[v0.10]` **断言对象是每个盒子自己的 `item_pool.socket_count`**（以及"由该盒 `modules` 重建出的池子状态"的位数恒定）——逐个盒子取**该盒所属套系**的 `SeriesDef` 比对，同一池（盒）内恒定；**不得**只断言某个"全局池"。**跨套系不同是合法的**（§5 第 10 条）；**同一套系内被改变才是失败**。实现必须**逐盒**取各自的 `SeriesDef` 比对，不得只比对某个"全局位数"或某个硬编码常数。**本系统是最容易偷偷加位次的地方（P7），此测试为强制项** |
| T5 | **红线 + 序列化不改权重 / `void`** | 任意解锁、任意阶段下 C1（**v0.13 口径：`Σ probs(全部物品) + void_prob ≤ 1.0`**——**浮点视图、留取整容差**；**精确性由整数形态断言** `Σ weights_bp + void_mass_bp == 10000`，见 `README.md` §6.1）/ C2 / **C3【v0.13 作废—跳过】** / C4 按 `05-module-pool.md` / `07-economy-rho.md` 的定义口径成立；本系统另行断言 `weights_bp` 与 `void_mass_bp` 经存 → 读 → 存后**逐项完全相等**（序列化不得引入量化误差，也不得让 `void` 被吸收或重新推导）。`[v0.10]` **该断言的落点是 `draw_log.pool_snapshot`**（历史冻结副本）——**盒子的当前池子状态不在档内**，它的对应要求是"重建无损"（**T24**）：载入后由 `item_pool` + `modules` 重建出的 `weights_bp` / `void_mass_bp` 必须与存档前逐项相等 |
| T6 | **阶段判定不改概率 / 发放幂等** | ① 手动构造落入五个阶段的状态，**同一盒子**（同一 `item_pool` + `modules`）的分布哈希必须相同（防"按进度暗改爆率"，P1 铁律 7）；② 同一 `unlock_key` 重复发放 100 次，`unlocked_*`、`unlocked_series_qualities` 与 `module_quality_ceiling` 不变 |
| T8 | **缺口可见性与完成度 / `void` 不改收集状态** | ① 未收录物品在默认视图可见、无折叠路径可隐藏缺口、`gap_count` 与实际未收录数（**= 全部物品 − 已收录**，v0.13）一致；② `series_progress` 是**一个数字**且**满格即全收集**：全部 `regular_count` 个物品收录后 `series_progress == regular_count / regular_count`、`NORMAL_COMPLETE` 与 `full_collection_reached` **同时为真**（**v0.13 起二者同义**）；**反向断言**：少收录任意一个物品时二者**同时为假**，且 `gap_count ≥ 1`（**两个品质档位各验一次**：8 个物品与 12 个物品）；③ 对同一池子先后制造 `void` 结果与正常结果，`void` 那一次使 `collected` / `duplicate_count` / `gap_count` / `series_progress` **逐项不变**，且 `is_collected()` 的返回值不变（§5 第 1 条） |
| T10 ★ | **含 `void` 的存档往返一致性** | 构造 `void_mass_bp > 0` 且 `draw_log` 含 `is_void == true` 条目的存档，存 → 读 → 存连续 10 轮**字节级稳定**；断言 `void_mass_bp` / `revision` / `modules`（稀疏序列，含 `index`）/ `socket_count` 与逐物品 `weights_bp` 逐项完全相等（`[v0.10]` 该断言的对象是 `draw_log.pool_snapshot`——**那是日志字段，不是盒子字段**；其中的 `socketed` 已被否决、模块信息写作 `modules`），且 `void_mass_bp` 不得在读档时被丢弃、取整或由 `weights_bp` 反推 |
| T11 ★ | **红线 C6 在任何解锁进度下不得被破坏（v0.6 新增）** | 对**任意解锁进度**、**任意合法池子**（`[v0.10]` 即任意 `item_pool` + `modules` 组合），断言**可产出常规物品数 ≥ 3**（口径见 `05-module-pool.md` / `07-economy-rho.md`）。用例集**必须覆盖每个品质档位**（8 个常规物品与 12 个常规物品各至少一例），并覆盖"排除已到上限"的极值池：品质 1/2 最多排除 5 个物品、品质 3/4 最多排除 9 个物品，各自排除到极限后仍须留下 ≥ 3 个可产出物品 |
| T12 ★ | **含多档品质套系存档的往返一致性（v0.6 新增）** | 构造**同时含多个不同 `series_quality` 套系**的存档（至少覆盖 8 个常规物品与 12 个常规物品各一），存 → 读 → 存连续 10 轮**字节级稳定**；断言每个 `pool_snapshot` / **盒子的 `item_pool`**（v0.10，替代旧的 `pools` 条目）的 `regular_count` 与 `socket_count` **逐项完全相等、不丢失、不被推导**（不得由 `weights_bp` 键数反推，也不得读档时按"当前最高档"统一改写；**`series_quality` 不落盘**——断言它由 `series_id` 解析 `SeriesDef` 得到，且读档后 `max(unlocked_series_qualities)` 与写档前一致，即 **P7 的还原点**：玩家最高能施工到什么档位不得因存档往返而变化） |
| T13 ★ | **实例列表往返字节级稳定（v0.8 新增）** | 构造含**多个实例**的存档（至少覆盖：`serial ≥ 1` 的开盒实例、`serial == 0` 的转化 / 返还实例、`kind == &"migrate"` 实例、同一 `item_id` 多实例），存 → 读 → 存连续 10 轮 `save.json` **字节级完全一致**；断言 `instance_id` / `item_id` / `acquired_at` / `serial` / `source`（含 `box_seed` / `draw_index` / `kind`）**逐项完全相等**，`inventory.serial_counters` 逐项相等且**未被读档重算**；断言**已消耗的实例不在档内**（无墓碑条目） |
| T14 ★ | **含 `serial == 0` 实例的存档往返（v0.8 新增）** | 单独构造由**转化产出**与**拆卸返还**产生的实例（`serial == 0`、`source.kind == &"convert"` / `&"refund"`），往返 10 轮后断言：①`serial` **仍为 0**——不得被"修正"为 ≥ 1、不得被 `serial_counters` 覆盖；②`source.kind` 未被改成 `&"gacha"`；③`serial_counters` **未因它们变化**（非开盒来源不推进计数器，§5 第 12 条）；④这几条实例**不影响** `max(serial)` 的对齐断言（T16） |
| T15 ★ | **v2 → v3 迁移幂等（v0.8 新增）** | 用 v2 档（含持有量块的 `(category, quality)` 计数）跑 `migrate_v2_to_v3()`：①**保量**——每个键迁移后的实例数 == v2 的 `count`，且 `Σ` 各 `(category, quality)` 的实例数 == 迁移前的派生持有量（不得多、不得少）；②**幂等**——对同一档重复调用迁移、或对已是 v3 的档再迁移，**不产生重复实例**，实例总数不变；③迁移后往返 10 轮字节级稳定；④`collected` / `duplicate_count` / `draw_log` / `pools` **逐项未被改写**；⑤全部迁入实例的 `source.kind == &"migrate"`、`serial ≥ 1`（按 §7.4 第 3 条依次分配） |
| T16 ★ | **迁移后 `serial_counters` 与实例 `serial` 最大值一致（v0.8 新增）** | ①对每个 `item_id` 断言 `serial_counters[item_id] == max(该 item_id 现存实例的 serial)`（**无实例时为 0**），且**恒不小于**任何现存实例的 `serial`；②**`serial == 0` 的实例不参与该最大值**；③迁移后立即成立，继续开盒一次后恰为 `max + 1`，新实例 `serial == max + 1`；④把该物品的实例**全部交付任务消耗**后再开盒：`serial_counters` **不回退**（不因 `max(现存) == 0` 而归零，§4 的 `serial_counters` 持久化理由） |
| T17 ★ | **含 `location == mail` 实例的存档往返（v0.9 新增）** | 构造同时含 `location == "warehouse"` 与 `location == "mail"` 实例的存档（至少覆盖：开盒入仓库、**溢出进邮件的开盒实例**、`serial == 0` 的转化实例、`migrate` 实例），存 → 读 → 存连续 10 轮 `save.json` **字节级完全一致**：①每条实例的 `location` 逐项相等且**未被读档重算**（按容量反推位置、把装不下的"顺手"搬进邮件、读档自动领取——三者任一发生即失败）；②`progression.warehouse_capacity` 逐项相等；③**实例总数守恒**（`warehouse` + `mail` 之和在往返前后完全不变）；④`count()` **只统计仓库侧**——断言其值 == 仓库侧实例数，且**邮件侧实例不参与**（把邮件实例计入即失败，核心 §4.7 边界 1 / §14.2 铁律 9）；⑤**领取只改 `location`**：对任一条邮件实例执行领取，断言 `instance_id` / `item_id` / `acquired_at` / `serial` / `source` **逐位不变**、实例总数不变、`serial_counters` 不变；⑥**守恒等式（裁决 12）**：断言 `total_granted − total_consumed == 实例总数（仓库 + 邮件）`，并在**往返前后 / 领取前后**逐次成立——**不得**写成"仓库 Σcount == 差值"（那只是等式的一个子集，有邮件条目时必然失败） | **仓库与邮件是同一份数据的两个位置**，不是两份表；位置丢在存档层 = 产出丢失（核心 v0.9 P5 兜底） |
| T18 ★ | **v3 → v4 迁移不丢实例（数量守恒，v0.9 新增）** | 用 v3 档（有实例列表，**无 `location`、无 `warehouse_capacity`**）跑 `migrate_v3_to_v4()`：①**保量**——迁移后的实例数 **== 迁移前**的实例数（不得多、不得少、**不得丢弃**）；②`location` 回填规则逐条成立：默认全为 `warehouse`；**若超容则按 `acquired_at` 升序保留、其余转 `mail`**（同刻按 `instance_id` 字典序），且断言 `Σ size(warehouse) ≤ warehouse_capacity`；③容量 == `WAREHOUSE_CAPACITY_INIT + Σ 已 COMPLETED 里程碑的容量载荷`，**下限为初始值**，且**绝不因持有量而上调**；④**幂等**——重复调用、或对已是 v4 的档再迁移，`location` 与容量**零变化**；⑤`instance_id` / `serial` / `source` / `serial_counters` / `collected` / `duplicate_count` / `draw_log` / `pools` **逐项未被改写**；⑥迁移后往返 10 轮字节级稳定 | **迁移绝不丢弃**（核心 §4.7"产出永不丢失"）；`location` 回填按 §7.4 的裁决 |
| T19 ★ | **容量解锁与占用占比一致（v0.9 新增）** | ①发放一个 `WAREHOUSE_CAPACITY` 载荷后，`warehouse_capacity` 恰为 `原值 + magnitude`（**累加语义**，不是覆盖）；②**P7 断言**：静态检查确认容量**只有** `grant_unlock()` 一条写入路径，**不存在**靠消耗物品 / 重复开盒 / 按持有量 / 按游玩时长 / 用券兑换改变容量的接口，且容量**只增不减**（消耗、领取、迁移、读档后均不下降）；③UI 侧的占用占比（已用 ÷ 容量，呈现规格归 `08-ui-panels.md` §9.7）与 02 的 `warehouse_usage()` **逐项相等**，并在**容量解锁前后**、**领取前后**、**消耗物品前后**各验一次（分子分母都必须跟着变）；④**容量边界处不得出现"显示还能放但实际放不下"**：构造 `剩余容量 == 某物品 size` 的临界存档，UI 提示与 `grant()` 的实际落位（`warehouse` / `mail`）必须**一致** | 容量必须与 P7 一致地**内容门控**（§5 第 14 条）；R14 的对策③建立在"提示可信"之上 |
| T20 ★ | **主动丢弃的记账正确性（v0.9 裁决 16 / 12 新增）** | 丢弃 N 个仓库实例后：①实例总数 **−N**、`total_consumed` **+N**，守恒等式 `total_granted − total_consumed == 全部实例数（含邮件）` 仍成立；②`collected` / `duplicate_count` / `serial_counters` **逐项不变**，图鉴格子**不退回剪影**（第 13 / 16 条）；③被丢弃的实例**不在档内**（无墓碑，与"只持久化现存实例"一致）；④**无任何回报**：`total_granted` 不变、无新实例、无券；⑤`draw_log` **不新增条目**（丢弃不是兑现）；⑥丢弃是**纯主动**路径：静态检查确认全库不存在除玩家确认流程之外的 `&"discard"` 调用（**不得**有任何"自动丢弃"实现） | P5 管被动、丢弃是主动（裁决 16）；守恒等式必须含邮件（裁决 12） |

| T21 ★ | **`Box` 五字段入档、派生状态一个都不入档（v0.10；v0.14 增 `uses_remaining`）** | 构造 `pending_boxes` 含**至少三个盒子**的存档：①第 1 号位镶 1 个排除模块（**且 `uses_remaining` 已被消耗过几次、不等于初始值**）、②**同套系但槽位占用完全不同**、③未配置。存 → 读 → 存连续 10 轮 `save.json` **字节级完全一致**；断言每个盒子的 `box_id` / `series_id` / `source` / `acquired_tick` 与 **`item_pool`（`regular_count` / `revision` / `socket_count`，**恰好这三项**）**、**`modules`（逐项 `index` + `module_id` + `quality` + `socketed_at`，按 `index` 升序）**、**`uses_remaining`（单个整数）** 全部**逐项相等**——**含 `uses_remaining` 的往返断言**：**存 → 读 → 存字节级稳定**且**逐项相等**，**读档不得把它重置为初始值、也不得按品质补满**（**键存在时读回、哪怕它是 `0`；缺键时按该盒所属套系品质补齐 10/15/20/25**，见 §7.4 第 8 条与 §11 **Q19**，见 §4 / §5 第 17 条）；② **反向断言（关键）**：盒子条目里**不存在** `weights_bp` / `void_mass_bp` / `probs` / `socketed` 任何一个键，**也不存在** `base_items` / `base_weights` / `series_quality`（对整档做**键集合**断言 + 源码级扫描：写档路径不含任何权重写入）——**派生值入档即失败**（§5 第 18 条），**基础池逐盒落盘即失败**（§4）；③ **`index` 必须落盘**：把盒 ① 的模块从 `index 1` 改到 `index 2` 再往返，断言档内 `index` 逐项变化、且载入后**位子占用（x / `socket_count`）**与"哪个位子空着"**逐位还原**；④ 断言**空位不落盘**：`modules` 的条目数 == 已占用槽位数（不得出现占位项），未配置盒子载入后仍是**空序列**（**"读档重算 `modules`"即失败**，§5 第 17 条） | **五个字段必须随盒子落盘**（§5 第 17 条）；**池子的当前状态是派生值，不入档**（§5 第 18 条）；**`uses_remaining` 是输入、不是派生值——读回不重算**（v0.14） |
| T22 ★ | **同套系的两个盒子载入后仍然不同（v0.10，禁趋同）** | 存档里放**同套系**的两个盒子：盒 A 的 `modules` 有一个占用项（`index 1`）、盒 B 的 `modules == []`（**两者 `item_pool` 完全相同**）。读档后断言：① 重建出的两个池子状态**不同**（`void_mass_bp` 不同、`s01_05` 的权重在 A 为 0 而在 B 非 0），且各自与写档前**逐项相等**；② `EvalService.evaluate_pool()` 对两盒给出的分布**不同**、`headline` 也**不同**（核心 §6.1 的"同套系两盒封面数字可以不一样"）；③ **反向断言（趋同即失败）**：不得出现"读档时按套系重建一份池子、再发给该套系所有盒子"的实现——静态检查 `PoolService` 的重建入口**必须逐盒**（按 `box_id`）读该盒自己的 `item_pool` + `modules`，**不得存在"按 `series_id` 缓存一份 `PoolState` 再复用"的缓存键**；④ 把盒 A 的某个槽位换一个模块再重建，**盒 B 的池子哈希不变**，且 A 的 `revision` 递增、**B 的 `revision` 逐位不变**（每盒各自独立） | "分批"的存档侧兜底（核心 §4.1.2）；**这是本版最容易被实现"顺手优化"掉的一条** |
| T23 ★ | **v4 → v5 迁移：不丢盒子、不改写编辑、不折算（v0.10；`uses_remaining` 见 v0.14）** | 用 v4 档（`pools` **每套系一份**、含 `socketed` 与 `weights_bp`）跑 `migrate_v4_to_v5()`：① **盒子数守恒**——迁移后 `pending_boxes` 条数 == 迁移前（**不得丢弃任何盒子**；v4 档不含清单块时得空数组，不是错误）；② **逐盒补齐字段**——断言全部盒子 **`modules == []`**（**空序列**）、`item_pool` 的 `regular_count` / `socket_count` == 该盒所属 `SeriesDef` 的对应值、**`revision == 0`**、**`box_id` 为合法 `Uuid.v4()`（`String`）且逐盒互不相同**；**若输入档里某个盒子已有 `box_id`，断言它被原样保留（逐位不变、不重新签发）**；**`uses_remaining`（v0.14）**：**输入档已有该键 ⇒ 逐位不变（哪怕它是 `0`）；缺键 ⇒ 按该盒所属套系品质补齐初始预算 10/15/20/25**（已裁决 = 按品质补齐；§7.4 第 8 条与 §11 **Q19**）；**⇒ v4 的 `pools[series_id].socketed` 没有落到任何盒子上**；③ **"不改写编辑"的具体断言**：**不存在任何盒子拿到非空 `modules`**；逐盒 `series_id` / `source` / `acquired_tick` 迁移前后**逐项相等**；**迁移不写派生量**（盒子条目里**不存在** `weights_bp` / `void_mass_bp` / `probs`），也**不写** `base_items` / `base_weights` / `series_quality`；**没有"折算/补偿"分支**——`total_granted` / `total_consumed` / 实例总数 / `serial_counters` / `collected` / `duplicate_count` / `draw_log` **逐项不变**；④ **v5 档中不存在 `pity_counters`**（v0.11 删除保底；v4 的 `pools[series_id].pity_counter` **被丢弃**——不搬运、不建新块），且**不再存在 `pools` 块**；⑤ **幂等（按 §7.4 第 7 条的边界写）**——对**已是 v5 的档**再迁移，全部盒子**五个字段零变化**（**含 `box_id` 逐位不变、绝不重新签发；也含 `uses_remaining` 逐位不变**），往返 10 轮字节级稳定；**不得**断言"同一 v4 输入两次迁移字节相等"（首次签发 `box_id` 是随机的，该断言必然失败）——**除首次签发的 `box_id` 外**的每一项仍须逐位可复现 | v0.10 下"施工台状态"与"盒子字段"**不是同一个量**（§7.4）；机械搬运会把一份套系级编辑放大成"盒数 × N"，正是 P7 明令否决的"免成本跨池复制"；本裁决只做**结构搬家**（签发 `box_id` + 回填 `item_pool` + 空 `modules`），**不做任何编辑迁移、不产生任何补偿**；**v0.14 的 `uses_remaining` 按"缺键取 0"补入，读回不重算**（§7.4 第 8 条） |
| T24 ★ | **载入后重建出的池子状态与存档前逐项相等（v0.10，**"派生值不入档"的前提**）** | 构造含多个盒子的存档（至少覆盖：未配置盒、1 个槽位占用的盒、**装满 `socket_count` 个槽位**的盒、**品质 4 的 12 物品盒**）。**写档前**先在内存里把每个盒子的池子状态取证（逐物品 `weights_bp`、`void_mass_bp`、`socket_count` / `regular_count`）；**载入后**由 `PoolService` 按 `box_id` 逐盒重建，断言重建结果与取证**逐项完全相等**（**不允许任何一项不等**——包括 `void_mass_bp` 的 1 bp 级相等）；② 断言重建走的是**与镶嵌/拆卸同一条实现**（单一写入方 / 单一求值方，核心 §4.1.2 把"推导"与"求值"拆给了 05 / 07）——不得为"载入"另写一套池子计算；③ **槽位还原**：重建后每个盒子的**位子占用（x / `socket_count`）与"第几位装了什么"逐位相等**（`index` 落盘的意义就在这里）；④ **缺 `ModuleDef` 的失败路径**：人为让某盒 `modules` 里出现一个已下线的 `module_id` → 断言**载入报错并明确列出缺失的模块 id**，**不得**静默降级成基础池、**不得**改写该盒的 `modules`（那会静默吃掉玩家投入的模块成本）；⑤ 断言**载入过程不写档**：重建出的状态**不得**被回写进 `save.json`（重建是只读推导，写档路径只有玩家动作与自动存档时机，§6.3） | **这是"池子当前状态不入档"能成立的前提**：不入档的正当性完全建立在"随时能无损重建"之上；若重建有损，就必须把权重要回档里——**那时本条失败即等于 T21 的第二条断言作废**（§4 / §5 第 18 条） |

**切片失败信号（本系统相关，配合核心 §13.4）：**

- 测试者**找不到缺口在哪** → 图鉴失败（缺口可见性未达标，本系统最严重的失败）；**说不出"下一个解锁是什么"** → `teaser` 预告失败，R11 的可感知性未落地；
- 测试者解锁新套系 / 新品质（含**套系品质**档位）后**毫不知情，或 ρ 无变化** → 内容释放未接上经济，R11 直接命中；
- 测试者认为"全收集就是抽到就完" → 终局表现失败，核心 §10.1 的"我算赢了它"未兑现；
- **测试者说"东西不见了"、或认为邮件里的物品已经不属于自己**（v0.9）→ 兜底未被理解（核心 R14 对策①）：检查 ①容量占比是否可见（`08-ui-panels.md` §9.7）②演出是否告知"本件已存入邮件"（`09-presentation.md` §5.9）③邮件条目的禁用态是否给出说明（08 §9.7）。**处置：改呈现，不得靠调大容量掩盖**；
- **测试者因为"仓库满了"而不敢开盒**（v0.9）→ 核心 R14 直接命中（v0.9 的首要新风险）：检查容量是否随里程碑持续成长（§5 第 14 条）与开盒前的保守提示是否可信（08 §9.7 / R14 对策③）；
- **T1 / T2 任一失败** → 直接阻塞发布：核心 §13.1 的"开箱日志（seed + 池子快照 + 结果）"与 P1 的可查可算承诺同时失效。

## 11. 待定项

| # | 待定项 | 影响 |
|---|---|---|
| Q1 | **D13 的具体节奏**（每 2 个里程碑 +1 档？按套系释放？） | ⛔ R11 关键，需与内容产能同步排期；核心 D13 未决 |
| Q2 | **全收集之后有什么**（核心未定义通关后内容） | 本系统只判定与呈现，**不得在此处私加新机制** |
| Q3 | `draw_log` 的裁剪策略与存档体积上限；图鉴是否需要物品文案 / 成就系统 | 前者会削弱 P1 的审计能力，需显式决策，**禁止静默裁剪**；后者核心 §13.2 已排除成就，需另行立项 |
| Q4 | 数据版本迁移的正式策略（跨大版本兼容承诺）；存档导入导出 / 云存档 | 前者影响存档格式冻结时点；后者核心已定"暂不做" |
| Q5 ★ | **套系品质梯度的释放节奏**（v0.6 新增）：第 2 档排在第几个里程碑？第 3 / 4 档要不要全出，还是止步于 3 档 | ⛔ **R11 关键**——品质档位是 v0.6 口径下唯一的功率成长轴（`[v0.10]` 已不再"唯一"，见 §5 第 10 条末条），它的释放节奏就是 ρ 上限的释放节奏。**但本系统不得自行取值**：这是内容产能排期问题，须与核心 D3 的曲线形状、D13 的模块品质节奏一起定（§6.1 / §6.2 目前给的是推荐排法） |
| Q6 | **低品质套系被淘汰的风险**（核心 R13 在本系统的落点，v0.6 新增）：高品质套系同时给更多位子与更高价值物品（核心 §4.1.1），低品质盒可能沦为废料 | 本系统的**唯一对策手段是发放顺序**：把品质梯度放平（相邻档不同时给"更多位子 + 更高价值物品"），并保证每个阶段的**预期释放**里仍有低品质套系的用武之地。**结构性的对抗仍归核心 §10.3 的需求结构变宽与 D14（品质梯度不宜过陡）**，本系统只负责不把这个风险放大 |
| Q7 | **`serial_counters` 与 `duplicate_count` 是否合并为一条不可逆计数**（v0.8 新增）：二者数值高度重合（都只在开盒产出推进），但 `serial_counters` 是 `serial` 的分配依据、`duplicate_count` 是图鉴的重复次数展示 | 切片期**保留两条**（§5 第 13 条：都不可逆、都不得由实例列表推导，合并会让 02 的编号分配与图鉴口径耦合）。若合并，**必须以 `serial_counters` 为唯一源**，并同步改 `02-item.md` 的图鉴口径与 `08-ui-panels.md` 的重复次数展示——**本系统不得自行合并** |
| Q8 ★ | **切片阶段必须实测存档体积**（v0.8 新增）：每实例约 120 B、5000 实例 ≈ 600 KB 是**估算**（核心 §4.2.2 第 4 条），且 `source` 是大头 | ⛔ **切片期必做**：按真实产出速率实测 1 小时 / 10 小时的存档体积、写盘耗时与读档耗时（含 `draw_log` 与实例列表两部分）。若超预算：**优先裁剪 `draw_log`（Q3）与压缩键名，不得砍 `source`**（溯源是 v0.8 的叙事价值，§4.2）；实测结果需回改核心 §4.2.2 第 4 条与本文 §6.3 的数 |
| Q9 ★ | **跨文档命名与取值对齐**（v0.8 新增，**部分已裁决**）：①迁移产出的实例来源取值——**已由核心 v0.9 裁决 4 定案为 `&"migrate"`**（取值域：`gacha` / `convert` / `refund` / `mail` / `migrate` / `unlock`；本文与 08 旧稿的 `migration` 作废）；②计数器键名以 02 §4.6 的 **`serial_counters`** 为准 | ①**已解决**：三处（02 / 08 / 10）统一使用 `&"migrate"`，**全库不得并存两种拼写**；02 需在取值域中同步补入 `migrate` 与 `mail`（本文不得自行改 02 的结构）②计数器键名同理，**单数写法作废** |
| Q10 ★ | **容量与 `size` 的具体数值**（v0.9 新增，对应核心 D16）：初始容量、里程碑扩容幅度、`ItemDef.size` 的品质梯度（核心示意 1 / 2 / 5 / 10）三者必须**一起标定**，且要与任务需求向量、开盒产出量、R14 的"不敢开盒"阈值联立 | ⛔ **切片期必做**：本系统只提供**发放机制与持久化**（§5 第 14 条 / §6.3），**不得自行取值**。若实测发现"仓库在上线后 30 分钟内即满"或"玩家因此停止开盒"，优先调**扩容节奏**（内容侧）而非取消容量（那会撤掉中心机制的第一道真实压力） |
| Q11 | **主动丢弃是否需要留痕**（v0.9 新增，裁决 16）：玩家可能想知道"我丢过什么" | **不留痕**：`draw_log` 是**兑现审计**（seed + `pool_snapshot`），与丢弃无关；丢弃的可追溯性由 `total_consumed` 的增量承担 | 若将来确需一条丢弃账，必须**新增独立日志**——**不得**往 `draw_log` 里塞非兑现条目（那会让"逐条 `pool_snapshot` 可复现抽取"的 T2 失效） |
| Q12 ★ | **盒子落盘的体积与载入耗时——必须实测（v0.10 新增，与 Q8 的物品实例实测同类）**：**本文不再给出按"存编辑后权重"的旧结构推算的数字**（那个方案已被否决，§5 第 18 条）；当前口径是"只存**基础池引用 + 冻结元数据 + `modules`**"，粗估每盒 **150–200 B**（未配置～1 个模块），每个已镶嵌模块再 +约 65 B（`{index, module_id, quality, socketed_at}`）——**这个数只是量级，不构成预算** | ⛔ **切片期必做**：按真实囤积速度实测 1 小时 / 10 小时的**存档体积**与**载入耗时**（**每盒都要重建池子 ⇒ 载入耗时随盒数线性增长，这是本版的主要风险**，比体积更值得盯）。**不得**为省一次重建或省体积而把 `weights_bp` / `void_mass_bp` 塞回档里（那是派生值，入档即制造第二事实来源，§5 第 18 条）；实测结果需**替换**本文 §6.3 的两个量级数 |
| Q13 ✅ | **囤积清单的存档形态与盒子的稳定身份（v0.10 提出，**已裁决**）**：① **v0.10 之前，存档 schema 从未把"囤积清单"写进任何键**（v4 示例里只有 `draw_log` / `inventory` / `pools` / `progression`）——**这是本次结构改动暴露出来的既有缺口**，v5 用 `pending_boxes` 补上；② **`Box.box_id` 是 01 的正式字段**（01 的 **G11 ✅**；05 §4 与 README §5 已同步）：**01 的 `Box` 字段集定稿 = `box_id` / `series_id` / `item_pool` / `modules`**（v0.10；**v0.14 起再加 `uses_remaining` ⇒ 共五个**，见文首 v0.14 说明与 §5 第 17 条）（核心 §4.1.2 / §16.5），`box_id : String` = `Uuid.v4()`，与 `ItemInstance.instance_id` **同型同源**；核心明确"`headline` / 池子面板 / ρ / 镶嵌 / 开箱日志与重放都必须能回答**来自哪一个盒子**" | **已关闭**：本文按此落地——`box_id` **随盒子条目落盘**（§4 / §4.1），"哪个盒子"从此是**身份指代**、不再依赖数组下标；`item_pool.box_id` 是同一事实、不重复落盘。**连带约束**：盒子的稳定身份在**迁移里为"历史上没有身份"的老盒子签发一次**（v4 档没有它），因此 v4 → v5 迁移**不再是逐位确定的**（随机 `Uuid.v4()`），断言按 §7.4 第 7 条的边界写（T23 ⑤）——这是"加身份"的必要代价，**不得**改用确定性派生 id 换字节级稳定（**稳定性来自持久化，不是来自派生**） |
| Q15 ✅ | **`revision` 的入档与跨会话语义（v0.10 提出，**已裁决**）**：`revision` **不是派生状态**——它是 `ItemPool` 的字段（05 §4），**随盒子落盘**（属 `ItemPool` 落盘子集五项之一），派生状态里那份只是**镜像** | **已关闭**：**每盒各自的编辑修订号**，**跨会话单调**、读档不得归零或重算；07 的缓存键 `(box_id, revision)` 跨会话仍有效，因此 05 的 **T11 可以按跨存档断言（每盒独立）**。**旧口径作废**：不得再写"`revision` 不入档 / 载入后重新起算 / 只在会话内单调" |
| Q16 ✅ | **`item_pool` 的基础数据是否逐盒落盘（v0.10 提出，**已裁决**）**：**不逐盒落盘**——`ItemPool` 的落盘子集**只有五项**（`box_id` / `series_id` / `regular_count` / `socket_count` / `revision`）；`base_items` / `base_weights` / `series_quality` **一律不落**，载入时由 `series_id` 解析 `SeriesDef`（05 §4 / T17 同口径） | **已关闭**：① 逐盒落盘 = 同一份模板**被复制 N 份**（囤 100 盒 = 100 份基础权重表），体积直接回到"每盒 450 B"那一档——而我们放弃落派生状态正是为了避开它；② 否则基础池有**两份副本**（`SeriesDef` 一份、每盒一份），**内容配置一改就静默不一致**。**代价（同一笔交易，已接受，不是 bug）**：**内容配置调整基础权重时，所有存量盒子的基础池会一起变**——与"派生状态不入档、可重建"同源；**断言写成"一致地变"（05 T17 ③），不得写成"各不相同"** |
| Q17 ★ | **全收集尾部的成本（v0.11 提出，v0.13 改述，对应核心 R15 / D18）**：v0.11 删除保底后尾部无界；**v0.13 删除隐藏款后这条已大幅缓解**——**不再有"最难、又无法被编辑影响"的那一款**（隐藏物品恒 2%、期望 50 抽、免疫一切池子编辑），**每一款都受池子编辑影响**。**残留风险从"不可能"变成"贵"**：C2 的 40% 损耗与 C6 的 ≥3 下限限制了你能把缺口物品的概率抬多高。本系统是**全收集判定与进度节奏**的落点，终局卡住等于进度卡住 | ⛔ **切片期必做（与 §6.2 收官阶段一起测）**：把某套系编辑到只剩少数缺口后，记录"开出下一个缺口物品"的**实际次数分布**，并**实测"达到可接受出率所需付出的物品成本"**（为抬缺口得镶嵌多少模块 × `ModuleDef.item_cost` ⇒ 这是 **D17** 的输入）。**四条纪律全部保留**：①**不得以任何"隐式必出"缓解尾部**（暗改某次的权重、看不见的加速、未公布的补偿——P1 / 核心 §16.6）；②将来若要加缓解机制，**必须可公布、可查**（P1 / P6）；③**不发明新机制**——本系统在这条轴上的可用手段**只有内容侧**（§5 第 9 条：里程碑链的释放节奏；以及 §9 的缺口可见性呈现）；④**与 `01-gacha.md` / `05-module-pool.md` 的口径一致**——概率只来自 `rarity` 配置与玩家自己的编辑，**没有特例、没有免疫区**（核心 §5.4）。**核心 D18 的选项②（松绑 C3）已随 C3 作废而失去意义**，尾部缓解只剩内容侧旋钮；若实测确有死墙，优先调 `rarity` 配置与常规物品的价值密度，**不得**把保底以"隐式必出"加回来 |
| Q18 ★ | **盒子有寿命预算 ⇒ 模块成本的摊薄与 D17 的重新标定（v0.14 提出，对应核心 D17 / P7）**：一个盒子的模块配置覆盖的是**该盒实际开出的 `d` 次**（**`d = k − m`**、**定义式 `m + d == k`**：`k` = **初始寿命 10–25**、`m` = 镶嵌模块的累计次数（**含"替换"的重新镶嵌**——**替换 = 拆卸 + 重新镶嵌**，**D20② 已裁决"不退还"** ⇒ **每替换一个位子额外 −1 寿命**，该位子累计 2 次；**不再受位数 2/3/4/5 封顶**）、`d` = **实际开出的次数**（**不替换时 8–20；替换越多越小、`d = 0` 即未开即毁**）；**`m = 0 ⇒ d = k`**，**每装一个模块就少开一次盒**），因此同一笔模块物品成本的**单位成本变成 `C(box)/d`**（**不是 `C(box)/k`**——那只在 `m = 0` 时成立）——**跨池复制的抑制力度整体位移**（07 §5.6 的 `N̄(box) = M̄(box) − C(box)/d`）。**结论不得弱化**：`C/d` 相比"预算 = 位数"的旧基线**又降了约 5 倍** ⇒ **D17 的标定基线位移更严重**；**P7 在 v0.10 被软化后，唯一的跨池约束就是 D17** ⇒ **D17 必须重新标定**，**若沿用 v0.10 的旧标定，P7 唯一的跨池锚点实质归零** | **本文只登记、不取值**（标定归核心 §15 的 **D17**；本系统**不得**自行改 `ModuleDef.item_cost`）。**若切片实测发现"跨池复制太便宜"**，优先调 **D17 的数值**，**不得**回头加结构性禁令（如"一个模块只能镶一个盒子"——那是 D17 要解决的同一件事，且会与模块作为消耗品的既有裁决冲突）。改动须与 C2 的 `recover_rate`、C6 的 ≥3 下限**一起标定**（07 §6 / §10.1 T7） | **不影响任何存档结构**；影响的是配置侧的模块成本与 P7 的力度——**07 §11 E10 是同一条的呈现侧登记**。★ **数值注记**：`C/k` 与 `C/(k − m)` **的差距现在很小**（`k` = 10–25、**不替换时** `k − m` = 8–20，**同一量级**），用哪个不影响结论，但**口径必须唯一**（本文与 07 一律写 `C/d`） |
| Q19 ✅ | **核心 D20 的三点登记（v0.14 提出，**②③ 已裁决、仅剩 ①**）**：①**标定基线位移比原先估计的更严重**（预算从 2–5 抬到 **10–25**，**不替换时** `d` = **8–20** ⇒ `C/d` 相比"预算 = 位数"的旧基线**又降约 5 倍**；`C/k` 与 `C/(k−m)` 的**数值差距现在很小**，但口径仍必须唯一 = `C/d`）；②**"拆卸是否退还那一次"——已裁决 = 不退还**（归属核心 §15 **D20②**）：**拆卸零成本也不退还** ⇒ **替换 = 拆 + 装 每次多烧 1 次寿命**（该位子历史累计 **2 次**：原装 1 + 新装 1）；**配置是沉没成本**，与"**模块是消耗品、拆卸只返还 50% 材料、模块本体不回收**"同一设计意图；③**迁移 / 载入缺键取值——已裁决 = 按品质补齐**（见下栏） | **②③ 已裁决、仅剩 ①（摊薄口径，现行结论 = `C/d`）；本文不推荐、不取值**。**②的落地后果**：**每替换一个位子额外 −1 寿命 ⇒ 配置迭代不再免费**（"免费反复试配置"这条路径被关闭，P7 的模块成本约束更紧），**代价是每换一次模块白烧一次寿命、过度替换会摧毁盒子**（**预算 10–25、位数 2–5 ⇒ 每盒大约能承受 5–20 次替换**，但**每次替换都更接近"归零即摧毁"**）；**③的裁决与理由（本轮已关闭）**：**取 `0`** 会让**一份旧档的全部盒子在载入瞬间被摧毁**（"`0` = 归零 ⇒ 摧毁"），因此**改为按该盒所属套系品质补齐初始预算（品质 1–4 ⇒ 10 / 15 / 20 / 25）**；**只有缺键才补**——**键存在时一律用存档值、哪怕它是 `0`**（那是"该盒已用尽"的合法状态，不许被"好心补满"）；**补齐需要品质 ⇒ 它发生在能拿到 `SeriesDef` 注册表的那一层（§7.4 的 `load()` / `migrate()`，由 `series_id` 解析 `SeriesDef` 的环节），`Box` 自己不去查表**；**`schema_version` 不动（仍 v5）**——这是"新增字段 + 载入补齐"，不是格式变更 | ① 决定 **D17** 的重新标定幅度与 P7 的力度（07 §5.6 / §6）；② 决定"配置迭代"是否**免费**——直接影响 R2 / R15 的缓冲强度与**每盒可用开盒次数的真实损耗**（**新数值下"装满位子即烧光预算"已不成立**——`位数 ≤ 5 < 10 ≤ k`；**但 D20② 已裁决不退还 ⇒ 替换每次额外 −1，反复替换确实会把预算烧光（"未开即毁"仍是合法路径）**）；③ 已裁决：**老档的盒子活着**（按品质补齐初始预算；此后一律读回存档值）。**②③ 不改 schema、不改字段数**（`schema_version` 仍 v5）；**仅剩 ①（摊薄口径，现行结论 = `C/d`）待上游确认**，并能追到用户原话 |
| Q20 ★ | **开局基础装置与装置状态的落盘（v0.16 登记，**本文不裁定**）**：用户裁决——①**设备系统的主要功能是开启盲盒和给盲盒添加模块**；②**是硬门槛：必须先有设备才能开盒 / 装模块**；③**开局直接送一台基础装置**（否则**开局死锁**：开盒需设备 → 设备由物品制造 → 物品来自开盒）。**⚠️ 缺口：本档（v5）没有任何装置 / 设备条目**（`ProgressionState` 无对应字段、§4.1 示例的块里都没有它）⇒ **开局那台装置目前无处落盘**。**待裁三项（本文一律不裁定、不发明结构）**：①**存档形态**——**新增一个 `devices` 块**还是**并入既有块**；②**`schema_version`**——若属"新增块"，按 §7.4"每次改字段必须递增版本并提供 `migrate_vN_to_vN+1()`"应为 **v6 + `migrate_v5_to_v6()`**（**§7.4 第 8 条"仍 v5"只覆盖 `uses_remaining` 的"新增字段 + 载入补齐"，不覆盖本条**）；③**载入不变量与失败处置**——**载入 / 新游戏后必须存在至少一台可用于开盒 / 装模块的设备**（**判定无参**；否则玩家即处于"开不了盒也装不了模块"的死锁态）：**载入校验失败即报错** 还是 **补发** | **已可写死的不变量**：那台装置**属于玩家进度、必须落盘**，**重放 / 读档一律读回原值，不得重算、不得凭空再发一台**（与 `Box` 五个字段同一纪律，§5 第 17 条；§7.4 第 8 条的装置侧不变量）。★ **设备不消耗、不损耗**（**无耐久度、无使用计数**），**判定 = "持有至少一台即可"（无参）** ⇒ 存档 **只需表达"玩家持有一台（或多台）设备"这个事实**，**不存耐久度 / 使用计数 / 绑定关系**；**若将来改为设备绑定盒子 / 有服务上限 ⇒ 判定入口变为带 `box_id` 的形式、存档需新增字段**（**可回滚的默认；当前只登记、不实现**）。**影响**：不落盘 ⇒ 读档后玩家可能**开不了盒也装不了模块**（进度直接停摆）；若选"补发"则等于**读档白送一台设备**（与"不凭空再发一台"冲突）——两项必须显式裁决。**上游落地位置**：新块 / 迁移 / 开局发放的写入动作归 `04-device.md` 与 `01-gacha.md`（开局初始状态），**本系统只负责其持久化布局** |

## 套系内容生成器（★ v0.26）——用**现有的 42 个物品资源**拼出一个盲盒套系（`SeriesDef`）。
##
## 用法（项目根目录）：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . --script res://tools/gen_series_content.gd
##
## 产物：`res://src/gacha/content/series_01.tres`
##
## 为什么是"生成"而不是手写 `.tres`：`regular_items` 是 `Array[ItemDef]` 的**资源引用**，
## 手写要自己维护 `ext_resource` 的 id 与 8 个路径；生成器直接把真实物品资源装进套系，
## 且**引用的是同一份 `ItemDef`**（价值 / 权重 / 大小仍只有一处定义，改物品内容不用动套系）。
##
## 选材（品质 2「精良」套系：8 件常规物品、3 个镶嵌位、15 次寿命，见核心 §4.1.1）：
##   **六类各取一件白/绿档**——前期主线吃"家居 + 工具"，其余四类是任务的散点需求。
##   全部取自 `src/items/content/items/`（真实内容），不新建任何物品。
extends SceneTree

const ITEM_DIR := "res://src/items/content/items"
const OUT_PATH := "res://src/gacha/content/series_01.tres"

## 8 件（品质 2 套系的物品数由 `SeriesDef.expected_regular_count(2) == 8` 固定）
const PICKS := [
	"home_q1", "home_q2",
	"tool_material_q1", "tool_material_q2",
	"energy_q1", "medical_q1",
	"information_q1", "electronic_q1",
]


func _init() -> void:
	var items: Array[ItemDef] = []
	for id in PICKS:
		var path := "%s/%s.tres" % [ITEM_DIR, id]
		if not ResourceLoader.exists(path):
			printerr("缺物品资源：%s（先跑 tools/gen_item_content.gd）" % path)
			quit(1)
			return
		var res = load(path)
		if not (res is ItemDef):
			printerr("不是 ItemDef：%s" % path)
			quit(1)
			return
		items.append(res as ItemDef)

	var s := SeriesDef.new()
	s.series_id = &"series_01"
	s.series_quality = 2                                              # 精良（切片主线）
	s.regular_count = SeriesDef.expected_regular_count(2)             # 8
	s.socket_count = SeriesDef.expected_socket_count(2)               # 3
	s.uses_per_box = SeriesDef.expected_initial_uses(2)               # 15
	s.gem_cost = 30                                                   # 🔧 归核心 D24
	s.unowned_weight_mult = 1.5
	s.regular_items = items

	var problems := s.validate()
	if not problems.is_empty():
		printerr("套系校验失败：")
		for p in problems:
			printerr("  - %s" % p)
		quit(1)
		return

	var abs_dir := ProjectSettings.globalize_path("res://src/gacha/content")
	if not DirAccess.dir_exists_absolute(abs_dir):
		var mk := DirAccess.make_dir_recursive_absolute(abs_dir)
		if mk != OK:
			printerr("无法创建内容目录 %s（err=%d）" % [abs_dir, mk])
			quit(1)
			return

	var err := ResourceSaver.save(s, OUT_PATH)
	if err != OK:
		printerr("写盘失败 %s（err=%d）" % [OUT_PATH, err])
		quit(1)
		return

	print("生成完成：`series_01`（%d 件物品 / %d 位 / %d 次）→ %s"
		% [items.size(), s.socket_count, s.uses_per_box, OUT_PATH])
	print("  物品：" + ", ".join(PICKS))
	quit(0)

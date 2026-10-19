## 物品内容生成器（★ v0.22）——把「7 类别 × 6 档品质 = 42 个 `ItemDef`」写成 `.tres`。
##
## 用法（在项目根目录）：
##   Godot_v4.5.1-stable_win64_console.exe --headless --path . --script res://tools/gen_item_content.gd
##
## 为什么要有生成器，而不是手写 42 个 `.tres`：
##   1. **数值只有一个来源**：`ItemConstants.QUALITY_VALUE / QUALITY_SIZE / QUALITY_RARITY /
##      QUALITY_SELL_GOLD` 是六档阶梯的唯一定义；手写 42 份等于把同一组数字抄 42 遍，
##      改一处就漏 41 处（而 `value` 直接进 `M̄`，写错是沉默的）。
##   2. **名字与数值分开**：`ItemConstants.ITEM_NAMES` 管内容（展示名），上面的四张表管平衡。
##   3. **重跑即重建**：**改常量后重跑本脚本**，`.tres` 全量覆盖；**不要手改 `.tres`**。
##
## 本脚本不依赖 autoload（`--script` 下 autoload 不可靠）：它只 `new()` 出 `ItemDef` 再存盘。
extends SceneTree

const OUT_DIR := "res://src/items/content/items"


func _init() -> void:
	var written := 0
	var problems: Array[String] = []

	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		var mk := DirAccess.make_dir_recursive_absolute(abs_dir)
		if mk != OK:
			printerr("无法创建内容目录 %s（err=%d）" % [abs_dir, mk])
			quit(1)
			return

	for q in range(ItemConstants.QUALITY_MIN, ItemConstants.QUALITY_MAX + 1):
		# 六档阶梯必须齐全（缺一档就不生成，避免写出半套内容）
		var value := ItemConstants.quality_value(q)
		var size := ItemConstants.quality_size(q)
		var rarity := ItemConstants.quality_rarity(q)
		var sell_gold := ItemConstants.quality_sell_gold(q)
		if value <= 0 or size <= 0 or rarity <= 0 or sell_gold < 0:
			problems.append("品质 %d 的阶梯缺失或不合法（value=%d size=%d rarity=%d sell_gold=%d）"
				% [q, value, size, rarity, sell_gold])
			continue
		# ★ v0.23：权重与品质挂钩 ⇒ 阶梯本身就是"越高越低"。低一档存在时先校验一次，
		#   免得生成出 V9 直接拒绝的内容（生成器与校验器必须说同一件事）。
		if q > ItemConstants.QUALITY_MIN:
			var prev_rarity := ItemConstants.quality_rarity(q - 1)
			if prev_rarity <= rarity:
				problems.append("权重阶梯违反 V9：品质 %d 的 rarity=%d 不低于品质 %d 的 %d"
					% [q, rarity, q - 1, prev_rarity])
				continue
		for cat in ItemConstants.ITEM_NAMES.keys():
			var shown := ItemConstants.item_name(StringName(cat), q)
			if shown == "":
				problems.append("类别 `%s` 的 %d 档没有展示名" % [cat, q])
				continue
			var def := ItemDef.new()
			def.item_id = StringName("%s_q%d" % [cat, q])
			def.display_name = shown
			def.category = StringName(cat)
			def.quality = q
			def.value = value
			def.size = size
			def.rarity = rarity
			def.sell_gold = sell_gold
			var path := "%s/%s.tres" % [OUT_DIR, def.item_id]
			var err := ResourceSaver.save(def, path)
			if err != OK:
				problems.append("写盘失败 %s（err=%d）" % [path, err])
			else:
				written += 1

	if not problems.is_empty():
		printerr("生成失败：")
		for p in problems:
			printerr("  - %s" % p)
		quit(1)
		return

	print("生成完成：%d 个 ItemDef → %s" % [written, OUT_DIR])
	quit(0)

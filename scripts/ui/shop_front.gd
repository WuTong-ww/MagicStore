extends HBoxContainer

var host
var guest_name: Label
var guest_status: Label
var case_label: Label
var begin_button: Button
var rest_button: Button
var next_button: Button
var history_button: Button

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var view := VBoxContainer.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(view)
	var scene_panel := MidnightUI.panel()
	scene_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_child(scene_panel)
	var scene_box := VBoxContainer.new()
	scene_panel.add_child(scene_box)
	scene_box.add_child(MidnightUI.label("灯亮着，故事就会来。", 24, MidnightUI.GOLD))
	var art := MidnightUI.image("res://assets/shop_front.svg")
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_box.add_child(art)
	scene_box.add_child(MidnightUI.label("前台  /  今夜的第一位来客，正等你翻开手记。", 15, MidnightUI.MUTED))
	view.add_child(MidnightUI.label("储物柜 · 工坊 · 原料商店 · 采集   /   后续开放", 14, MidnightUI.MUTED))
	var side := MidnightUI.panel()
	side.custom_minimum_size.x = 365
	add_child(side)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	side.add_child(column)
	column.add_child(MidnightUI.label("今 日 来 客", 14, MidnightUI.GOLD))
	var profile := HBoxContainer.new()
	column.add_child(profile)
	var portrait := MidnightUI.image("res://assets/portrait_lin.svg")
	portrait.custom_minimum_size = Vector2(83, 100)
	profile.add_child(portrait)
	var profile_text := VBoxContainer.new()
	profile_text.add_theme_constant_override("separation", 4)
	profile_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile.add_child(profile_text)
	guest_name = MidnightUI.label("", 25)
	profile_text.add_child(guest_name)
	profile_text.add_child(MidnightUI.label(str(GameState.content.get("npc", {}).get("role", "")), 16, MidnightUI.MUTED))
	guest_status = MidnightUI.label("", 15, MidnightUI.GOLD)
	profile_text.add_child(guest_status)
	case_label = MidnightUI.label("", 17)
	case_label.custom_minimum_size.y = 64
	column.add_child(case_label)
	begin_button = MidnightUI.button("请入咨询区", func(): await host.run_action("start_visit"))
	column.add_child(begin_button)
	history_button = MidnightUI.button("翻看来客手记", func(): host.show_history())
	column.add_child(history_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var rules: Dictionary = GameState.content.get("rules", {})
	rest_button = MidnightUI.button("休息 %d 分钟 · 精力 +%d" % [int(rules.get("rest_minutes", 60)), int(rules.get("rest_energy", 30))], func(): await host.run_action("rest"))
	column.add_child(rest_button)
	next_button = MidnightUI.button("打烊，进入下一天", func(): await host.run_action("next_day"))
	column.add_child(next_button)
	column.add_child(MidnightUI.label("隔日回访仅用于验证记忆，不代表正式客流。", 12, MidnightUI.MUTED))
	refresh()

func refresh() -> void:
	if not is_instance_valid(begin_button):
		return
	var state: Dictionary = GameState.snapshot()
	var npc: Dictionary = GameState.content.get("npc", {})
	guest_name.text = str(npc.get("name", "等待内容载入"))
	case_label.text = str(npc.get("case_title", "")) + "\n把烦心事留在这里，一次谈清一点。"
	var no_save := state.is_empty()
	var active: Dictionary = GameState.active_visit()
	var already_today := false
	for visit: Dictionary in state.get("visits", []):
		if int(visit.get("day", -1)) == int(floor(float(state.get("clock_minutes", 0)) / 1440.0)):
			already_today = true
	begin_button.text = "继续原接待 →" if not active.is_empty() else "请入咨询区 →"
	begin_button.disabled = no_save or (already_today and active.is_empty())
	guest_status.text = "打开存档后开始" if no_save else ("接待进行中" if not active.is_empty() else ("今日已接待 · 明日可回访" if already_today else "等待接待"))
	rest_button.disabled = no_save
	next_button.disabled = no_save
	history_button.disabled = no_save

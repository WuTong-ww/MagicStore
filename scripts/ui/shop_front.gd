extends HBoxContainer

var host
var guest_name: Label
var guest_status: Label
var case_label: Label
var begin_button: Button
var rest_button: Button
var next_button: Button
var history_button: Button
var study_button: Button
var guest_picker: OptionButton
var guest_role: Label
var portrait: TextureRect
var guests: Array = []

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
	column.add_theme_constant_override("separation", 6)
	side.add_child(column)
	column.add_child(MidnightUI.label("今 日 来 客", 14, MidnightUI.GOLD))
	guest_picker = OptionButton.new()
	guest_picker.fit_to_longest_item = false
	guest_picker.item_selected.connect(func(_index: int): refresh())
	column.add_child(guest_picker)
	var profile := HBoxContainer.new()
	column.add_child(profile)
	portrait = MidnightUI.image("res://assets/portrait_lin.svg")
	portrait.custom_minimum_size = Vector2(76, 86)
	profile.add_child(portrait)
	var profile_text := VBoxContainer.new()
	profile_text.add_theme_constant_override("separation", 4)
	profile_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile.add_child(profile_text)
	guest_name = MidnightUI.label("", 25)
	profile_text.add_child(guest_name)
	guest_role = MidnightUI.label("", 16, MidnightUI.MUTED)
	profile_text.add_child(guest_role)
	guest_status = MidnightUI.label("", 15, MidnightUI.GOLD)
	profile_text.add_child(guest_status)
	case_label = MidnightUI.label("", 17)
	case_label.custom_minimum_size.y = 40
	column.add_child(case_label)
	begin_button = MidnightUI.button("请入咨询区", _begin)
	column.add_child(begin_button)
	var tools := HBoxContainer.new()
	column.add_child(tools)
	history_button = MidnightUI.button("来客手记", func(): host.show_history())
	history_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(history_button)
	study_button = MidnightUI.button("术式研习", func(): host.open_divination("study"))
	study_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(study_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var rules: Dictionary = GameState.content.get("rules", {})
	rest_button = MidnightUI.button("休息 %d 分钟 · 精力 +%d" % [int(rules.get("rest_minutes", 60)), int(rules.get("rest_energy", 30))], func(): await host.run_action("rest"))
	column.add_child(rest_button)
	next_button = MidnightUI.button("打烊，进入下一天", func(): await host.run_action("next_day"))
	column.add_child(next_button)
	column.add_child(MidnightUI.label("联调来客 · 可选择案例与回访", 12, MidnightUI.MUTED))
	refresh()

func refresh() -> void:
	if not is_instance_valid(begin_button):
		return
	var state: Dictionary = GameState.player_snapshot()
	var no_save := state.is_empty()
	var active: Dictionary = GameState.active_visit()
	var previous_index := maxi(guest_picker.selected, 0)
	guests = GameState.divination_guests()
	var active_view: Dictionary = GameState.divination_view()
	if not active.is_empty() and not guests.any(func(row: Dictionary) -> bool: return row.npc_id == active.npc_id and row.case_id == active_view.case_id):
		var returning: Dictionary = active_view.guest.duplicate()
		returning.merge({"case_id": active_view.case_id, "label": returning.name + " · 接待中"})
		guests.append(returning)
	guest_picker.clear()
	for row: Dictionary in guests:
		guest_picker.add_item(row.label)
		if row.npc_id == active.get("npc_id") and row.case_id == active_view.get("case_id"):
			previous_index = guest_picker.item_count - 1
	guest_picker.select(clampi(previous_index, 0, guests.size() - 1) if not guests.is_empty() else -1)
	guest_picker.disabled = no_save or not active.is_empty()
	var guest: Dictionary = guests[guest_picker.selected] if guest_picker.selected >= 0 else {}
	guest_name.text = guest.get("name", "等待内容载入")
	guest_role.text = guest.get("role", "")
	portrait.visible = guest.get("npc_id") == "npc_lin"
	case_label.text = guest.get("case_title", "")
	var already_today: bool = guest.get("visited_today", false)
	begin_button.text = "继续原接待 →" if not active.is_empty() else "请入咨询区 →"
	begin_button.disabled = no_save or (already_today and active.is_empty())
	guest_status.text = "打开存档后开始" if no_save else ("接待进行中" if not active.is_empty() else ("今日已接待 · 明日可回访" if already_today else "等待接待"))
	rest_button.disabled = no_save
	next_button.disabled = no_save
	history_button.disabled = no_save
	study_button.disabled = no_save or not active.is_empty()

func _begin() -> void:
	if not GameState.active_visit().is_empty():
		await host.run_action("start_visit")
		return
	if guest_picker.selected < 0:
		return
	var row: Dictionary = guests[guest_picker.selected]
	await host.run_action("start_visit", {"npc_id": row.npc_id, "case_id": row.case_id})

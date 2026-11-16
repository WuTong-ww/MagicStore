extends HBoxContainer

var host
var guest_name: Label
var guest_status: Label
var case_label: Label
var begin_button: Button
var wait_button: Button
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
	view.add_child(MidnightUI.button("查看候客、预约与人物档案", func(): host.open_people()))
	var side := MidnightUI.panel()
	side.custom_minimum_size.x = 365
	add_child(side)
	var column := VBoxContainer.new()
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(side_scroll)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	side_scroll.add_child(column)
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
	wait_button = MidnightUI.button("等一会儿", _wait_for_guest)
	column.add_child(wait_button)
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
	column.add_child(MidnightUI.label("熟客的故事，会在下一次见面继续。", 16, MidnightUI.MUTED))
	refresh()

func refresh() -> void:
	if not is_instance_valid(begin_button):
		return
	var state: Dictionary = GameState.player_snapshot()
	var no_save := state.is_empty()
	var active: Dictionary = GameState.active_visit()
	var previous_index := maxi(guest_picker.selected, 0)
	guests = []
	for arrival: Dictionary in GameState.people_view().get("queue", []):
		var case_id: String = arrival.case_id if not str(arrival.case_id).is_empty() else ("invitation" if arrival.npc_id == "npc_lin" else "archive")
		guests.append({"npc_id":arrival.npc_id,"arrival_id":arrival.arrival_id,"case_id":case_id,"label":arrival.name,"name":arrival.name,"role":arrival.role,"case_title":"想看看店里的商品" if arrival.intent == "shopping" else "有些事想和你谈谈"})
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
	guest_name.text = guest.get("name", "暂时没有来客")
	guest_role.text = guest.get("role", "")
	portrait.visible = guest.get("npc_id") == "npc_lin"
	case_label.text = guest.get("case_title", "")
	var already_today: bool = guest.get("visited_today", false)
	begin_button.text = "继续原接待 →" if not active.is_empty() else "请入咨询区 →"
	begin_button.disabled = no_save or (active.is_empty() and guests.is_empty()) or (already_today and active.is_empty())
	var empty_shop: bool = not no_save and active.is_empty() and guests.is_empty()
	var remaining := maxi(0,int(GameState.content.get("rules",{}).get("closing_minute",1320))-int(state.get("clock_minutes",0))%1440)
	wait_button.visible = empty_shop
	wait_button.disabled = not empty_shop or remaining <= 0
	wait_button.text = "等一会儿 · %d 分钟" % mini(30,remaining) if remaining > 0 else "今天已打烊"
	if no_save:
		guest_status.text = "打开存档后开始"
	elif not active.is_empty():
		guest_status.text = "接待进行中"
	elif empty_shop:
		guest_status.text = "今天的营业结束了。" if remaining <= 0 else "店里暂时安静，坐一会儿吧。"
	else:
		guest_status.text = "今日已接待 · 明日可回访" if already_today else "等待接待"
	rest_button.disabled = no_save
	next_button.disabled = no_save
	history_button.disabled = no_save
	study_button.disabled = no_save or not active.is_empty()

func _wait_for_guest() -> void:
	var state: Dictionary = GameState.player_snapshot()
	if state.is_empty() or not GameState.active_visit().is_empty() or not GameState.people_view().get("queue",[]).is_empty():
		return
	var remaining := maxi(0,int(GameState.content.get("rules",{}).get("closing_minute",1320))-int(state.clock_minutes)%1440)
	if remaining > 0:
		await host.run_action("wait",{"minutes":mini(30,remaining)})

func _begin() -> void:
	if not GameState.active_visit().is_empty():
		await host.run_action("start_visit")
		return
	if guest_picker.selected < 0:
		return
	var row: Dictionary = guests[guest_picker.selected]
	if row.has("arrival_id"):
		await host.run_action("start_arrival", {"arrival_id":row.arrival_id})

extends Control

const UI = preload("res://scripts/ui/ui_kit.gd")
const ArrivalUI = preload("res://scripts/ui/arrival_ui.gd")

const SceneArt = preload("res://scripts/shop/scene_visual.gd")
var scene_visual: Control
const LIN_PORTRAIT := "res://assets/portraits/npc_lin_neutral.png"
const LIN_PORTRAIT_FALLBACK := "res://assets/portrait_lin.svg"
const LIN_EXPRESSIONS := {"neutral":"res://assets/portraits/npc_lin_neutral.png", "hesitant":"res://assets/portraits/npc_lin_hesitant.png", "relieved":"res://assets/portraits/npc_lin_relieved.png"}

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
var arrival_source: Label
var patience_list: VBoxContainer
var quiet_suggestions: HBoxContainer
var arrival_copy: Dictionary = {}
var daily_panel: VBoxContainer
var daily_title: Label
var daily_progress: Label
var daily_letters: VBoxContainer
var daily_read_button: Button
var daily_summary: Label
var daily_monologue: Label
var legacy_title: Label
var legacy_note: Label
var guest_profile: HBoxContainer
var daily_fonts: Dictionary = {}

func _ready() -> void:
	arrival_copy = ArrivalUI.load_config()
	var stage := SceneArt.new()
	scene_visual = stage
	add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.setup("front")
	for key: String in stage.config.scenes[stage.scene_id].hotspots:
		_add_hotspot(stage,key)
	var drawer := preload("res://scripts/ui/paper_drawer.gd").new()
	drawer.name = "FrontDrawer"
	add_child(drawer)
	drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell: Dictionary = preload("res://scripts/ui/shell_config.gd").load_config()
	drawer.offset_top = shell.layout.drawer_inset_top
	drawer.offset_bottom = -float(shell.layout.drawer_inset_bottom)
	stage.label_occluders.append(drawer.panel)
	drawer.panel.item_rect_changed.connect(stage._layout)
	drawer.panel.visibility_changed.connect(stage._layout)
	var column: VBoxContainer = drawer.content
	_build_daily_journal(column)
	legacy_title = UI.label("今日来客", 16, UI.GOLD)
	column.add_child(legacy_title)
	patience_list = VBoxContainer.new()
	patience_list.name = "ArrivalPatienceList"
	column.add_child(patience_list)
	guest_picker = OptionButton.new()
	guest_picker.fit_to_longest_item = false
	guest_picker.item_selected.connect(func(_index: int): refresh())
	column.add_child(guest_picker)
	var profile := HBoxContainer.new()
	guest_profile = profile
	profile.add_theme_constant_override("separation", 12)
	column.add_child(profile)
	portrait = UI.image(LIN_PORTRAIT if ResourceLoader.exists(LIN_PORTRAIT) else LIN_PORTRAIT_FALLBACK)
	portrait.custom_minimum_size = Vector2(120, 148)
	profile.add_child(portrait)
	var profile_text := VBoxContainer.new()
	profile_text.add_theme_constant_override("separation", 4)
	profile_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile.add_child(profile_text)
	guest_name = UI.label("", 26)
	profile_text.add_child(guest_name)
	guest_role = UI.label("", 16, UI.MUTED)
	profile_text.add_child(guest_role)
	arrival_source = UI.label("", 14, UI.MUTED)
	profile_text.add_child(arrival_source)
	guest_status = UI.label("", 15, UI.GOLD)
	profile_text.add_child(guest_status)
	case_label = UI.label("", 18)
	case_label.custom_minimum_size.y = 52
	column.add_child(case_label)
	quiet_suggestions = HBoxContainer.new()
	quiet_suggestions.name = "ZeroGuestSuggestions"
	column.add_child(quiet_suggestions)
	for destination: String in arrival_copy.get("suggestions", {}):
		var suggestion := UI.button(arrival_copy.suggestions[destination], func():
			if destination == "study":
				host.open_divination("study")
			else:
				host.show_screen(destination))
		suggestion.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quiet_suggestions.add_child(suggestion)
	begin_button = UI.button("请入咨询区", _begin)
	begin_button.custom_minimum_size.y = 52
	column.add_child(begin_button)
	wait_button = UI.button("等一会儿", _wait_for_guest)
	column.add_child(wait_button)
	var tools := HBoxContainer.new()
	column.add_child(tools)
	history_button = UI.button("来客手记", func(): host.show_history())
	history_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(history_button)
	study_button = UI.button("术式研习", func(): host.open_divination("study"))
	study_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(study_button)
	rest_button = UI.button("休息", func(): await host.run_action("rest"))
	column.add_child(rest_button)
	next_button = UI.button("打烊，进入下一天", _close_or_next_day)
	column.add_child(next_button)
	legacy_note = UI.label("熟客的故事，会在下一次见面继续。", 15, UI.MUTED)
	column.add_child(legacy_note)
	refresh()

func _build_daily_journal(column: VBoxContainer) -> void:
	daily_fonts = preload("res://scripts/ui/shell_config.gd").load_config().layout
	daily_panel = VBoxContainer.new()
	daily_panel.name = "DailyLoopPanel"
	column.add_child(daily_panel)
	daily_progress = UI.label("",int(daily_fonts.status_size),UI.MUTED)
	daily_progress.name = "DailyLoopProgress"
	daily_panel.add_child(daily_progress)
	daily_title = UI.label("",int(daily_fonts.brand_size))
	daily_panel.add_child(daily_title)
	daily_letters = VBoxContainer.new()
	daily_letters.name = "DailyLoopLetters"
	daily_panel.add_child(daily_letters)
	daily_read_button = UI.button("",func(): await host.run_action("read_morning_letters"))
	daily_read_button.name = "ReadMorningLetters"
	daily_panel.add_child(daily_read_button)
	daily_summary = UI.label("",int(daily_fonts.brand_size))
	daily_summary.name = "DailyLoopSummary"
	daily_panel.add_child(daily_summary)
	daily_monologue = UI.label("",int(daily_fonts.brand_size),UI.MUTED)
	daily_monologue.name = "DailyLoopMonologue"
	daily_panel.add_child(daily_monologue)

func _add_hotspot(parent: Control, key: String) -> Button:
	var target: String = parent.config.scenes[parent.scene_id].hotspots[key].target
	return parent.hotspot(key,func():
		if target == "consultation":
			_enter_consultation()
		elif target == "people":
			host.open_people()
		else:
			host.show_screen(target))

func _place_node(node: Control, center: Vector2, size: Vector2) -> void:
	node.anchor_left = center.x
	node.anchor_right = center.x
	node.anchor_top = center.y
	node.anchor_bottom = center.y
	node.offset_left = -size.x * 0.5
	node.offset_right = size.x * 0.5
	node.offset_top = -size.y * 0.5
	node.offset_bottom = size.y * 0.5

func _enter_consultation() -> void:
	if not GameState.active_visit().is_empty():
		host.show_screen("consultation")
		return
	if GameState.daily_loop_view().get("enabled",false):
		await _begin()
		return
	if guest_picker.selected >= 0:
		await _begin()

func refresh() -> void:
	if is_instance_valid(scene_visual):
		scene_visual.refresh()
	if not is_instance_valid(begin_button):
		return
	var state: Dictionary = GameState.player_snapshot()
	var no_save := state.is_empty()
	var active: Dictionary = GameState.active_visit()
	var daily: Dictionary = GameState.daily_loop_view()
	daily_panel.visible = not no_save and daily.get("enabled",false)
	if daily_panel.visible:
		_refresh_daily_journal(daily,active)
		return
	legacy_title.show()
	legacy_note.show()
	guest_profile.show()
	arrival_source.show()
	patience_list.show()
	begin_button.show()
	case_label.show()
	next_button.show()
	rest_button.show()
	var previous_index := maxi(guest_picker.selected, 0)
	var people: Dictionary = GameState.people_view()
	guests = []
	for arrival: Dictionary in people.get("queue", []):
		var case_id: String = arrival.case_id if not str(arrival.case_id).is_empty() else ("invitation" if arrival.npc_id == "npc_lin" else "archive")
		var level := ArrivalUI.patience(arrival)
		guests.append({"npc_id":arrival.npc_id,"arrival_id":arrival.arrival_id,"case_id":case_id,"label":str(arrival.name) + " · " + str(level.get("icon", "")),"name":arrival.name,"role":arrival.role,"source":arrival.get("source", ""),"case_title":"想看看店里的商品" if arrival.intent == "shopping" else "有些事想和你谈谈"})
	_refresh_patience(people)
	var active_view: Dictionary = GameState.divination_view()
	if not active.is_empty() and not guests.any(func(row: Dictionary) -> bool: return row.npc_id == active.npc_id and row.case_id == active_view.case_id):
		var returning: Dictionary = active_view.guest.duplicate()
		returning.merge({"case_id": active_view.case_id, "label": returning.name + " · 接待中"})
		for arrival: Dictionary in people.get("in_service", []):
			if arrival.npc_id == active.npc_id:
				returning.merge({"arrival_id": arrival.arrival_id, "source": arrival.source})
		guests.append(returning)
	guest_picker.visible = not guests.is_empty()
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
	arrival_source.text = ArrivalUI.source_text(guest) if guest.has("arrival_id") else ""
	portrait.visible = guest.get("npc_id") == "npc_lin"
	if portrait.visible:
		var expression := "neutral"
		var active_visit: Dictionary = GameState.active_visit()
		for turn: Dictionary in active_visit.get("dialogue", []):
			var line := str(turn.get("text", ""))
			if line.contains("担心") or line.contains("犹豫") or line.contains("害怕"):
				expression = "hesitant"
			elif line.contains("放心") or line.contains("轻松") or line.contains("谢谢"):
				expression = "relieved"
		var expression_path: String = LIN_EXPRESSIONS.get(expression, LIN_PORTRAIT)
		if ResourceLoader.exists(expression_path):
			portrait.texture = load(expression_path)
	case_label.text = guest.get("case_title", "还没有来客，先翻翻档案，或者安静等一会儿。")
	var already_today: bool = guest.get("visited_today", false)
	begin_button.text = "继续原接待 →" if not active.is_empty() else "请入咨询区 →"
	begin_button.disabled = no_save or (active.is_empty() and guests.is_empty()) or (already_today and active.is_empty())
	var empty_shop: bool = not no_save and active.is_empty() and guests.is_empty()
	var zero_guest_day: bool = empty_shop and ArrivalUI.zero_guest_day(people)
	quiet_suggestions.visible = zero_guest_day
	if zero_guest_day:
		guest_name.text = arrival_copy.get("empty_title", "")
		case_label.text = arrival_copy.get("empty_advice", "")
	var remaining := maxi(0,int(GameState.content.get("rules",{}).get("closing_minute",1320))-int(state.get("clock_minutes",0))%1440)
	wait_button.visible = empty_shop
	wait_button.disabled = not empty_shop or remaining <= 0
	wait_button.text = "等一会儿 · %d 分钟" % mini(30,remaining) if remaining > 0 else "今天已打烊"
	if no_save:
		guest_status.text = "打开存档后开始"
	elif not active.is_empty():
		guest_status.text = "接待进行中"
	elif empty_shop:
		guest_status.text = arrival_copy.get("empty_status", "") if zero_guest_day else ("今天的营业结束了。" if remaining <= 0 else "店里暂时安静，坐一会儿吧。")
	else:
		guest_status.text = "今日已接待 · 明日可回访" if already_today else "等待接待"
	var rules: Dictionary = GameState.content.get("rules", {})
	rest_button.text = "休息 %d 分钟 · 精力 +%d" % [int(rules.get("rest_minutes", 60)), int(rules.get("rest_energy", 30))]
	rest_button.disabled = no_save
	next_button.disabled = no_save
	history_button.disabled = no_save
	study_button.disabled = no_save or not active.is_empty()

func _refresh_daily_journal(daily: Dictionary, active: Dictionary) -> void:
	var copy: Dictionary = daily.copy
	var phase := str(daily.phase)
	var pending: bool = is_instance_valid(host) and bool(host.busy)
	var completed := int(daily.completed)
	var total := int(daily.total)
	legacy_title.hide()
	legacy_note.hide()
	guest_picker.hide()
	patience_list.hide()
	quiet_suggestions.hide()
	wait_button.hide()
	rest_button.hide()
	arrival_source.hide()
	portrait.hide()
	guests.clear()
	daily_progress.text = str(copy.day_progress).format({"day":daily.day,"completed":completed,"total":total})
	daily_title.text = str(copy.morning_title) if phase == "morning" else (str(copy.closing_title) if phase == "closing" else "")
	daily_title.visible = not daily_title.text.is_empty()
	for child: Node in daily_letters.get_children():
		daily_letters.remove_child(child)
		child.queue_free()
	for letter: Dictionary in daily.letters:
		var sender := UI.label(str(letter.name),int(daily_fonts.status_size),UI.GOLD)
		daily_letters.add_child(sender)
		daily_letters.add_child(UI.label(str(letter.text),int(daily_fonts.brand_size)))
	if phase == "morning" and daily.letters.is_empty():
		daily_letters.add_child(UI.label(str(copy.letters_empty),int(daily_fonts.brand_size),UI.MUTED))
	daily_letters.visible = phase != "closing" and daily_letters.get_child_count() > 0
	daily_read_button.text = str(copy.read_letters)
	daily_read_button.visible = phase == "morning"
	daily_read_button.disabled = pending
	var next_guest: Dictionary = daily.next_guest
	if not active.is_empty():
		next_guest = GameState.divination_view().get("guest",{})
	guest_profile.visible = phase == "reception" and not next_guest.is_empty()
	guest_name.text = str(next_guest.get("name",""))
	guest_role.text = str(next_guest.get("role",""))
	guest_status.text = str(copy.guest_active) if not active.is_empty() else str(copy.guest_waiting)
	case_label.visible = phase == "reception" and completed >= total
	case_label.text = str(copy.all_served)
	begin_button.visible = phase == "reception"
	begin_button.text = str(copy.resume_visit) if not active.is_empty() else str(copy.next_customer)
	begin_button.disabled = phase != "reception" or pending or (active.is_empty() and (completed >= total or next_guest.is_empty()))
	next_button.visible = phase != "morning"
	next_button.text = str(copy.next_day) if phase == "closing" else str(copy.close_shop)
	next_button.disabled = pending or not active.is_empty() or (phase == "reception" and completed < total)
	history_button.disabled = pending
	study_button.disabled = pending or not active.is_empty()
	daily_summary.visible = phase == "closing"
	daily_monologue.visible = phase == "closing"
	if phase == "closing":
		var summary: Dictionary = daily.summary
		var fields := summary.duplicate(true)
		fields["notes"] = str(copy.notes_empty) if summary.get("notes",[]).is_empty() else "\n".join(PackedStringArray(summary.notes))
		daily_summary.text = str(copy.summary_format).format(fields)
		daily_monologue.text = str(copy.monologue_title)+"\n"+str(summary.monologue)

func _close_or_next_day() -> void:
	var daily: Dictionary = GameState.daily_loop_view()
	var kind := "close_shop" if daily.get("enabled",false) and daily.get("phase") == "reception" else "next_day"
	await host.run_action(kind)

func _refresh_patience(people: Dictionary) -> void:
	for child: Node in patience_list.get_children():
		patience_list.remove_child(child)
		child.queue_free()
	var waiting: Array = people.get("queue", []).duplicate()
	waiting.append_array(people.get("outside_queue", []))
	for row: Dictionary in waiting:
		var level := ArrivalUI.patience(row)
		var line := UI.label(str(row.get("name", "")) + " · " + ArrivalUI.patience_text(row), 14, Color(str(level.get("color", "ffffff"))))
		patience_list.add_child(line)
	for key: String in ["outside_queue", "appointment_requests"]:
		var count: int = people.get(key, []).size()
		if count > 0:
			patience_list.add_child(UI.label(str(arrival_copy.get("outside_format" if key == "outside_queue" else "requests_format", "")) % count, 14, UI.GOLD))

func _wait_for_guest() -> void:
	if GameState.daily_loop_view().get("enabled",false):
		return
	var state: Dictionary = GameState.player_snapshot()
	if state.is_empty() or not GameState.active_visit().is_empty() or not GameState.people_view().get("queue",[]).is_empty():
		return
	var remaining := maxi(0,int(GameState.content.get("rules",{}).get("closing_minute",1320))-int(state.clock_minutes)%1440)
	if remaining > 0:
		await host.run_action("wait",{"minutes":mini(30,remaining)})

func _begin() -> void:
	var daily: Dictionary = GameState.daily_loop_view()
	if daily.get("enabled",false):
		if daily.get("phase") != "reception":
			return
		if not GameState.active_visit().is_empty():
			host.show_screen("consultation")
		else:
			await host.run_action("next_customer")
		return
	if not GameState.active_visit().is_empty():
		await host.run_action("start_visit")
		return
	if guest_picker.selected < 0:
		return
	var row: Dictionary = guests[guest_picker.selected]
	if row.has("arrival_id"):
		await host.run_action("start_arrival", {"arrival_id":row.arrival_id})

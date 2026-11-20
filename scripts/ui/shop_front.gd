extends HBoxContainer

const UI = preload("res://scripts/ui/ui_kit.gd")

const FRONT_ART := "res://assets/shop_front_scene.png"
const FRONT_ART_FALLBACK := "res://assets/shop_front.svg"
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

func _ready() -> void:
	add_theme_constant_override("separation", 16)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(left)
	var scene_panel := UI.panel()
	scene_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scene_panel)
	var scene_box := VBoxContainer.new()
	scene_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_box.add_theme_constant_override("separation", 10)
	scene_panel.add_child(scene_box)
	scene_box.add_child(UI.label("灯亮着，故事就会来。", 24, UI.GOLD))
	var hint := UI.label("前台不再只是贴图：可以直接点击店内区域，切换功能、查看来客与进入接待。", 14, UI.MUTED)
	hint.custom_minimum_size.y = 28
	scene_box.add_child(hint)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(760, 430)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_box.add_child(stage)
	var art := UI.image(FRONT_ART if ResourceLoader.exists(FRONT_ART) else FRONT_ART_FALLBACK)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	stage.add_child(art)
	var vignette := ColorRect.new()
	vignette.color = Color(0.01, 0.06, 0.08, 0.12)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(vignette)
	_add_hotspot(stage, "店外", Vector2(0.12, 0.53), Vector2(88, 52), func(): host.show_screen("exterior"))
	_add_hotspot(stage, "原料商店", Vector2(0.53, 0.41), Vector2(124, 48), func(): host.show_screen("market"))
	_add_hotspot(stage, "储物柜", Vector2(0.47, 0.73), Vector2(116, 48), func(): host.show_screen("inventory"))
	_add_hotspot(stage, "咨询区", Vector2(0.75, 0.57), Vector2(108, 48), _enter_consultation)
	_add_hotspot(stage, "工坊", Vector2(0.90, 0.50), Vector2(92, 48), func(): host.show_screen("workshop"))
	_add_hotspot(stage, "来客信件", Vector2(0.55, 0.88), Vector2(126, 42), func(): host.open_people())
	var slogan := UI.label("点一点店内区域，直接与店铺互动。", 18, UI.GOLD)
	_place_node(slogan, Vector2(0.57, 0.97), Vector2(420, 26))
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slogan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(slogan)
	var shortcut_row := HBoxContainer.new()
	shortcut_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(shortcut_row)
	var browse_button := UI.button("查看候客、预约与人物档案", func(): host.open_people())
	browse_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shortcut_row.add_child(browse_button)
	var consult_button := UI.button("进入咨询区", _enter_consultation)
	consult_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shortcut_row.add_child(consult_button)
	var side := UI.panel()
	side.custom_minimum_size.x = 360
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(side)
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	side.add_child(side_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	side_scroll.add_child(column)
	column.add_child(UI.label("今日来客", 16, UI.GOLD))
	guest_picker = OptionButton.new()
	guest_picker.fit_to_longest_item = false
	guest_picker.item_selected.connect(func(_index: int): refresh())
	column.add_child(guest_picker)
	var profile := HBoxContainer.new()
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
	guest_status = UI.label("", 15, UI.GOLD)
	profile_text.add_child(guest_status)
	case_label = UI.label("", 18)
	case_label.custom_minimum_size.y = 52
	column.add_child(case_label)
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
	next_button = UI.button("打烊，进入下一天", func(): await host.run_action("next_day"))
	column.add_child(next_button)
	column.add_child(UI.label("熟客的故事，会在下一次见面继续。", 15, UI.MUTED))
	refresh()

func _add_hotspot(parent: Control, text: String, center: Vector2, size: Vector2, callback: Callable) -> Button:
	var button := UI.button(text, callback)
	button.custom_minimum_size = size
	button.add_theme_font_size_override("font_size", 18)
	button.tooltip_text = text
	_place_node(button, center, size)
	parent.add_child(button)
	return button

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
	if guest_picker.selected >= 0:
		await _begin()

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
	var rules: Dictionary = GameState.content.get("rules", {})
	rest_button.text = "休息 %d 分钟 · 精力 +%d" % [int(rules.get("rest_minutes", 60)), int(rules.get("rest_energy", 30))]
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

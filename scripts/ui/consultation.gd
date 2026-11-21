extends Control

const UI = preload("res://scripts/ui/ui_kit.gd")
const LAYOUT_CONFIG := "res://data/ui/consultation.json"

const SceneArt = preload("res://scripts/shop/scene_visual.gd")
const LIN_EXPRESSIONS := {"neutral":"res://assets/portraits/npc_lin_neutral.png", "hesitant":"res://assets/portraits/npc_lin_hesitant.png", "relieved":"res://assets/portraits/npc_lin_relieved.png"}

const OracleGuide = preload("res://scripts/divination/oracle_guide.gd")

var host
var transcript: RichTextLabel
var input: TextEdit
var send_button: Button
var questions: HFlowContainer
var title: Label
var reading_button: Button
var end_button: Button
var return_button: Button
var contact_button: Button
var card_title: Label
var card_text: RichTextLabel
var clue_label: Label
var cost_label: Label
var visit_label: Label
var service_summary: Label
var service_button: Button
var casebook_button: Button
var shop_button: Button
var card_backs: HBoxContainer
var room_art: Control
var guest_portrait: TextureRect
var _question_rows: Array = []
var _question_visit_id := ""
var _last_busy := false
var _submitting_question := false
var _submitting_text := false
var layout_config: Dictionary = {}
var dialogue_panel: PanelContainer
var conversation: VBoxContainer
var drawer_panel: PanelContainer
var drawer_toggle: Button
var drawer_open := false
var drawer_tween: Tween
var _layout_pending := false
var _rendered_visit_id := ""
var _rendered_clue_count := 0
var _new_clue_turn := -1
var _default_seat: Array = []

static func layout_config_valid(config: Dictionary) -> bool:
	var height: Variant = config.get("transcript_minimum_height")
	if config.get("version") != 2 or not (height is int or height is float) or not is_finite(float(height)) or height <= 0 or height != floor(height):
		return false
	for key: String in ["portrait_minimum_size","banner_minimum_size"]:
		if not config.get(key) is Array or config[key].size() != 2 or not config[key].all(func(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value)) and value > 0 and value == floor(value)):
			return false
	for key: String in ["top_inset","bottom_inset","edge_inset","dialogue_ratio","dialogue_minimum_height","dialogue_padding","dialogue_gap","drawer_width","drawer_bookmark_width","drawer_seconds","drawer_gap","title_font_size","body_font_size","small_font_size","input_height","question_minimum_width","question_height","question_gap","portrait_z","dialogue_z","drawer_z","text_limit","bubble_main_ratio","bubble_spacer_ratio"]:
		var value: Variant = config.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value <= 0:
			return false
	if config.dialogue_ratio >= 1 or not config.get("seat_rect") is Array or config.seat_rect.size() != 4:
		return false
	for value: Variant in config.seat_rect:
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0:
			return false
	if config.seat_rect[2] <= 0 or config.seat_rect[3] <= 0 or not config.get("portrait_occlusion_layer") is String:
		return false
	var compact: Variant = config.get("compact_seat")
	if not compact is Dictionary:
		return false
	for key: String in ["height_limit","narrow_width_limit"]:
		if not (compact.get(key) is int or compact.get(key) is float) or not is_finite(float(compact[key])) or compact[key] <= 0:
			return false
	for key: String in ["rect","narrow_rect"]:
		if not compact.get(key) is Array or compact[key].size() != 4 or not compact[key].all(func(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value)) and value >= 0):
			return false
		if compact[key][2] <= 0 or compact[key][3] <= 0:
			return false
	if not config.get("copy") is Dictionary:
		return false
	for pair: Array in [["bubble_padding",4],["bubble_avatar_size",2]]:
		if not config.get(pair[0]) is Array or config[pair[0]].size() != pair[1] or not config[pair[0]].all(func(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value)) and value > 0):
			return false
	for key: String in ["bubble_guest_color","bubble_player_color","bubble_text_color","bubble_stamp_color"]:
		if not config.get(key) is String or not Color.html_is_valid(config[key]):
			return false
	for key: String in ["input_hint","send","keyboard_hint","drawer_open","drawer_close","tab_reading","tab_casebook","tab_shop","empty_title","empty_visit","guest_title","clues","case_clues","reading_title","unopened_card","reading_quote","all_methods","casebook","shop","history","end","return","contact","contact_hint","case_note","shop_note","blank_question","long_question","player_name","guest_name","clue_stamp"]:
		if not config.copy.get(key) is String or config.copy[key].is_empty():
			return false
	return true

static func load_layout_config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_CONFIG))
	return parsed if parsed is Dictionary and layout_config_valid(parsed) else {}

func _process(_delta: float) -> void:
	if is_instance_valid(transcript) and _interaction_busy() != _last_busy:
		refresh()

func _ready() -> void:
	layout_config = load_layout_config()
	if layout_config.is_empty():
		return
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	var copy: Dictionary = layout_config.copy
	room_art = SceneArt.new()
	room_art.name = "ConsultationArtwork"
	add_child(room_art)
	room_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_art.setup("consultation")
	guest_portrait = UI.image(LIN_EXPRESSIONS.neutral)
	guest_portrait.name = "SeatedGuest"
	guest_portrait.z_index = int(layout_config.portrait_z)
	guest_portrait.visible = false
	room_art.add_child(guest_portrait)
	var scene: Dictionary = room_art.config.get("scenes", {}).get("S03", {})
	var seat: Array = scene.get("seat_rect", layout_config.seat_rect).duplicate()
	var seat_scale: float = float(scene.get("seat_scale", 1.0))
	seat[0] -= float(seat[2]) * (seat_scale - 1.0) * 0.5
	seat[1] -= float(seat[3]) * (seat_scale - 1.0)
	seat[2] *= seat_scale
	seat[3] *= seat_scale
	_default_seat = seat.duplicate()
	room_art.place(guest_portrait, seat)
	# A1R may supply this layer; no synthetic opaque rectangle covers the guest.
	var occlusion: CanvasItem = room_art.layer_nodes.get(layout_config.portrait_occlusion_layer)
	if occlusion != null:
		_fit_portrait_occlusion(occlusion)

	dialogue_panel = UI.panel()
	dialogue_panel.name = "PaperConversation"
	dialogue_panel.z_index = int(layout_config.dialogue_z)
	add_child(dialogue_panel)
	var padding := UI.margin(int(layout_config.dialogue_padding))
	dialogue_panel.add_child(padding)
	conversation = VBoxContainer.new()
	conversation.add_theme_constant_override("separation", int(layout_config.dialogue_gap))
	padding.add_child(conversation)
	var title_row := HBoxContainer.new()
	conversation.add_child(title_row)
	title = UI.label("", int(layout_config.title_font_size))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	clue_label = UI.label("", int(layout_config.small_font_size), UI.MUTED)
	clue_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_row.add_child(clue_label)
	transcript = UI.rich()
	transcript.bbcode_enabled = true
	transcript.theme_type_variation = &"Dialogue"
	transcript.name = "DialogueHistory"
	transcript.custom_minimum_size.y = float(layout_config.transcript_minimum_height)
	transcript.add_theme_font_size_override("normal_font_size", int(layout_config.body_font_size))
	conversation.add_child(transcript)
	questions = HFlowContainer.new()
	questions.add_theme_constant_override("h_separation", int(layout_config.question_gap))
	questions.add_theme_constant_override("v_separation", int(layout_config.dialogue_gap))
	conversation.add_child(questions)
	var input_row := HBoxContainer.new()
	conversation.add_child(input_row)
	input = TextEdit.new()
	input.placeholder_text = copy.input_hint
	input.custom_minimum_size.y = float(layout_config.input_height)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.add_theme_font_size_override("font_size", int(layout_config.body_font_size))
	input.gui_input.connect(_on_input_gui_input)
	input_row.add_child(input)
	send_button = UI.button(copy.send, _send_text)
	input_row.add_child(send_button)
	var hint := UI.label(copy.keyboard_hint % int(GameState.content.get("rules", {}).get("talk_minutes", 5)), int(layout_config.small_font_size), UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	conversation.add_child(hint)

	drawer_panel = UI.panel()
	drawer_panel.name = "ConsultationDrawer"
	drawer_panel.z_index = int(layout_config.drawer_z)
	add_child(drawer_panel)
	var drawer_margin := UI.margin(int(layout_config.dialogue_padding))
	drawer_panel.add_child(drawer_margin)
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drawer_margin.add_child(tabs)
	var service := _drawer_page(tabs, copy.tab_reading)
	service.add_child(UI.label(copy.reading_title, int(layout_config.title_font_size)))
	card_backs = HBoxContainer.new()
	card_backs.visible = false
	service.add_child(card_backs)
	card_title = UI.label(copy.unopened_card, int(layout_config.body_font_size))
	service.add_child(card_title)
	cost_label = UI.label("", int(layout_config.small_font_size), UI.MUTED)
	service.add_child(cost_label)
	card_text = UI.rich()
	card_text.scroll_following = false
	card_text.custom_minimum_size.y = float(layout_config.transcript_minimum_height)
	service.add_child(card_text)
	reading_button = UI.button(copy.reading_quote, func(): host.open_divination("tarot"))
	service.add_child(reading_button)
	service_button = UI.button(copy.all_methods, func(): host.open_divination("reading"))
	service.add_child(service_button)
	service_summary = UI.label("", int(layout_config.small_font_size), UI.MUTED)
	service.add_child(service_summary)
	var notes := _drawer_page(tabs, copy.tab_casebook)
	visit_label = UI.label("", int(layout_config.small_font_size), UI.MUTED)
	notes.add_child(visit_label)
	notes.add_child(UI.label(copy.case_note, int(layout_config.body_font_size)))
	casebook_button = UI.button(copy.casebook, func(): host.open_divination("casebook"))
	notes.add_child(casebook_button)
	notes.add_child(UI.button(copy.history, func(): host.show_history()))
	end_button = UI.button(copy.end, func(): await host.run_action("end_visit"))
	notes.add_child(end_button)
	return_button = UI.button(copy.return, func(): host.confirm_return_visit())
	notes.add_child(return_button)
	contact_button = UI.button(copy.contact, func(): host.confirm_contact_invitation())
	contact_button.tooltip_text = copy.contact_hint
	notes.add_child(contact_button)
	var accounts := _drawer_page(tabs, copy.tab_shop)
	accounts.add_child(UI.label(copy.shop_note, int(layout_config.body_font_size)))
	shop_button = UI.button(copy.shop, func(): host.open_divination("shop"))
	accounts.add_child(shop_button)
	drawer_toggle = UI.button(copy.drawer_open, func(): set_drawer_expanded(not drawer_open))
	drawer_toggle.name = "ConsultationBookmark"
	drawer_toggle.z_index = int(layout_config.drawer_z) + 1
	add_child(drawer_toggle)
	resized.connect(_queue_layout)
	conversation.minimum_size_changed.connect(_queue_layout)
	refresh()
	_queue_layout()

func _drawer_page(tabs: TabContainer, caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = caption
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", int(layout_config.question_gap))
	scroll.add_child(column)
	return column

func _queue_layout() -> void:
	if _layout_pending:
		return
	_layout_pending = true
	call_deferred("_layout_consultation")

func _layout_consultation() -> void:
	_layout_pending = false
	if not is_instance_valid(dialogue_panel):
		return
	var edge := float(layout_config.edge_inset)
	var available_width := maxf(0.0, size.x - edge * 2.0)
	var minimum_height := dialogue_panel.get_combined_minimum_size().y
	var desired_height := maxf(float(layout_config.dialogue_minimum_height), size.y * float(layout_config.dialogue_ratio))
	var height := maxf(minimum_height, desired_height)
	dialogue_panel.size = Vector2(available_width, height)
	dialogue_panel.position = Vector2(edge, size.y - float(layout_config.bottom_inset) - dialogue_panel.size.y)
	_layout_portrait()
	if drawer_tween != null and drawer_tween.is_running():
		drawer_tween.kill()
	var width := minf(float(layout_config.drawer_width), size.x - float(layout_config.drawer_bookmark_width))
	drawer_panel.size = Vector2(width, maxf(0.0, dialogue_panel.position.y - float(layout_config.top_inset) - float(layout_config.drawer_gap)))
	drawer_panel.position = Vector2(size.x-width if drawer_open else size.x, float(layout_config.top_inset))
	drawer_toggle.position = Vector2(drawer_panel.position.x - float(layout_config.drawer_bookmark_width), float(layout_config.top_inset))
	drawer_toggle.size.x = float(layout_config.drawer_bookmark_width)

func _fit_portrait_occlusion(occlusion: CanvasItem) -> void:
	if room_art.config.scene_settings.version == 3:
		guest_portrait.z_index = mini(int(layout_config.portrait_z),occlusion.z_index-1)
	else:
		occlusion.z_index = clampi(occlusion.z_index,guest_portrait.z_index+1,mini(int(layout_config.dialogue_z),int(layout_config.drawer_z))-1)

func _layout_portrait() -> void:
	# Short windows reserve more than a third for readable dialogue. A separate
	# source-space pose keeps the guest's face above that paper without moving
	# the room or changing the shared cover transform.
	var compact: Dictionary = layout_config.compact_seat
	var seat: Array = _default_seat
	if size.y <= float(compact.height_limit):
		seat = compact.narrow_rect if size.x <= float(compact.narrow_width_limit) else compact.rect
		if room_art.config.get("scene_settings",{}).get("version",2) == 3:
			var scene: Dictionary = room_art.config.scenes[room_art.scene_id]
			seat = scene.get("seat_narrow_rect",seat) if size.x <= float(compact.narrow_width_limit) else scene.get("seat_compact_rect",seat)
	for row: Dictionary in room_art.placed_nodes:
		if row.node == guest_portrait:
			row.rect = seat
	var projected: Rect2 = room_art.projected_rect(seat)
	guest_portrait.position = projected.position
	guest_portrait.size = projected.size

func set_drawer_expanded(expanded: bool, animate: bool = true) -> void:
	drawer_open = expanded
	drawer_toggle.text = layout_config.copy.drawer_close if expanded else layout_config.copy.drawer_open
	if drawer_tween != null and drawer_tween.is_running():
		drawer_tween.kill()
	var target_x := size.x - drawer_panel.size.x if expanded else size.x
	if not animate:
		drawer_panel.position.x = target_x
		drawer_toggle.position.x = target_x - float(layout_config.drawer_bookmark_width)
		return
	drawer_tween = create_tween().set_parallel(true)
	drawer_tween.tween_property(drawer_panel, "position:x", target_x, float(layout_config.drawer_seconds)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	drawer_tween.tween_property(drawer_toggle, "position:x", target_x-float(layout_config.drawer_bookmark_width), float(layout_config.drawer_seconds)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_input_gui_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.keycode not in [KEY_ENTER, KEY_KP_ENTER]:
		return
	# Some input methods deliver committed characters as key events.
	if event.unicode >= 32:
		return
	# The OS commits IME candidates; suppress the editor's newline while composing.
	if input.has_ime_text():
		input.accept_event()
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	input.accept_event()
	if event.shift_pressed:
		if input.editable:
			input.insert_text_at_caret("\n")
		return
	if not event.echo:
		_send_text()

func _send_text() -> void:
	if _interaction_busy() or GameState.active_visit().is_empty():
		return
	var text := input.text.strip_edges()
	if text.is_empty():
		host.show_notice(layout_config.copy.blank_question)
		return
	if text.length() > int(layout_config.text_limit):
		host.show_notice(layout_config.copy.long_question % int(layout_config.text_limit))
		return
	_submitting_text = true
	refresh()
	var result: Dictionary = await host.run_action("talk", {"text": text})
	if result.get("success", false) and is_instance_valid(input):
		input.text = ""
	if is_instance_valid(self):
		_submitting_text = false
		refresh()

func refresh() -> void:
	if not is_instance_valid(transcript):
		return
	var visit: Dictionary = GameState.active_visit()
	var active := not visit.is_empty()
	_last_busy = _interaction_busy()
	var view: Dictionary = GameState.divination_view()
	var guest: Dictionary = view.get("guest", {})
	room_art.refresh()
	room_art.visible = true
	guest_portrait.visible = active and guest.get("npc_id", "") == "npc_lin"
	if guest_portrait.visible:
		var expression := "neutral"
		for turn: Dictionary in visit.get("dialogue", []):
			var line := str(turn.get("text", ""))
			if line.contains("担心") or line.contains("犹豫") or line.contains("害怕"):
				expression = "hesitant"
			elif line.contains("放心") or line.contains("轻松") or line.contains("谢谢"):
				expression = "relieved"
		var portrait_path: String = LIN_EXPRESSIONS.get(expression, LIN_EXPRESSIONS.neutral)
		if ResourceLoader.exists(portrait_path):
			guest_portrait.texture = load(portrait_path)
	title.text = layout_config.copy.guest_title % guest.get("name", "") if active else layout_config.copy.empty_title
	visit_label.text = str(guest.get("case_title", "")) if active else layout_config.copy.empty_visit
	var visit_id := str(visit.get("visit_id", ""))
	var clue_count: int = view.get("clues", []).size()
	if visit_id != _rendered_visit_id:
		_rendered_visit_id = visit_id
		_rendered_clue_count = clue_count
		_new_clue_turn = -1
	elif clue_count > _rendered_clue_count:
		_new_clue_turn = visit.get("dialogue", []).size() - 1
	_rendered_clue_count = clue_count
	var new_text := history_bbcode(visit.get("dialogue", []), guest, layout_config, _new_clue_turn)
	if new_text != transcript.text:
		transcript.text = new_text
	clue_label.text = layout_config.copy.clues % (view.get("clues", []).size() + view.get("services", []).size())
	var reading: Dictionary = visit.get("reading", {})
	var paid := not reading.is_empty()
	var services: Array = view.get("services", [])
	var quote: Dictionary = view.get("quote", {})
	card_backs.visible = paid or services.is_empty()
	card_title.text = str(reading.get("title", "尚未揭示的三牌阵"))
	if reading.has("cards"):
		card_title.text = "塔罗三牌阵"
	card_text.text = str(reading.get("text", "先选术式和报酬。收款成功后，结果会留在本次服务里。"))
	cost_label.text = "原牌面已保存 · 重看免费" if paid else "塔罗 · 三张牌"
	if not paid and not services.is_empty():
		var last: Dictionary = services.back()
		card_title.text = last.method_title
		card_text.text = OracleGuide.summary(last)
		cost_label.text = last.method_title + " · 已保存"
	elif reading.has("cards"):
		for service: Dictionary in services:
			if service.result.get("medium", {}).get("cards") == reading.cards:
				card_text.text = OracleGuide.summary(service)
				break
	reading_button.text = "塔罗已留存" if paid else "塔罗报价"
	reading_button.disabled = not active or paid
	service_button.disabled = not active
	service_button.text = "继续报价" if not quote.is_empty() else "全部术式"
	service_summary.text = "已结算 %d 项  ·  可逐项重看" % services.size() if quote.is_empty() else "已约定%s  ·  等待收款" % quote.method_title
	casebook_button.disabled = not active
	casebook_button.text = "案例手记 · 可听取回访" if not view.get("feedback_options", []).is_empty() else "案例手记 · 线索与判断"
	shop_button.disabled = not active
	end_button.disabled = not active
	return_button.visible = active and GameState.next_return_time() > 0
	contact_button.visible = active and not GameState.contact_invitation().is_empty()
	send_button.disabled = not active or _last_busy
	input.editable = active and not _last_busy
	_refresh_topics(_available_questions(),str(visit.get("visit_id","")))

func _available_questions() -> Array:
	if GameState.active_visit().is_empty():
		return []
	var supplied: Variant = GameState.call("conversation_questions") if GameState.has_method("conversation_questions") else GameState.divination_view().get("topics",[])
	var result: Array = []
	if not supplied is Array:
		return result
	for item: Variant in supplied:
		if not item is Dictionary or not item.get("topic_id") is String or not item.get("label") is String or item.topic_id.is_empty() or item.label.strip_edges().is_empty() or not item.get("enabled",false):
			continue
		result.append({"topic_id":str(item.topic_id),"label":str(item.label),"enabled":true,"generated":bool(item.get("generated",false))})
		if result.size() == 3:
			break
	return result

func _interaction_busy() -> bool:
	return _submitting_question or _submitting_text or (is_instance_valid(host) and bool(host.busy)) or bool(GameState.provider_status().get("pending",false))

func _refresh_topics(topics: Array, visit_id: String = "") -> void:
	var changed := _question_visit_id != visit_id or _question_rows != topics or questions.get_child_count() != topics.size()
	if changed:
		for node in questions.get_children():
			questions.remove_child(node)
			node.queue_free()
		_question_rows = topics.duplicate(true)
		_question_visit_id = visit_id
		for topic: Dictionary in topics:
			var button := UI.button(topic.label, _submit_question.bind(visit_id,str(topic.topic_id),str(topic.label)))
			button.add_theme_font_size_override("font_size", int(layout_config.body_font_size))
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
			button.custom_minimum_size = Vector2(float(layout_config.question_minimum_width),float(layout_config.question_height))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.set_meta("topic_id",topic.topic_id)
			button.set_meta("question_label",topic.label)
			button.set_meta("generated",topic.get("generated",false))
			questions.add_child(button)
		_queue_layout()
	for index in range(topics.size()):
		questions.get_child(index).disabled = _last_busy or not topics[index].get("enabled",false)

func _submit_question(visit_id: String, topic_id: String, label: String) -> void:
	if _interaction_busy() or visit_id.is_empty() or str(GameState.active_visit().get("visit_id","")) != visit_id:
		return
	if not _available_questions().any(func(row: Dictionary) -> bool: return row.topic_id == topic_id and row.label == label):
		return
	_submitting_question = true
	refresh()
	await host.run_action("talk",{"text":label,"topic_id":topic_id})
	if is_instance_valid(self):
		_submitting_question = false
		refresh()

static func _escape_bbcode(value: String) -> String:
	# Only opening brackets can start markup; escape user/model content before
	# mixing it with the fixed presentation tags below.
	return value.replace("[", "[lb]")

static func history_bbcode(dialogue: Array, guest: Dictionary, config: Dictionary, stamp_turn: int = -1) -> String:
	var lines: PackedStringArray = []
	var copy: Dictionary = config.copy
	var padding: Array = config.bubble_padding
	var padding_text := "%d,%d,%d,%d" % padding
	for index: int in range(dialogue.size()):
		var turn: Dictionary = dialogue[index]
		var speaker := str(turn.get("speaker", ""))
		var body := _escape_bbcode(str(turn.get("text", "")))
		if speaker not in ["npc", "player", "shopkeeper"]:
			lines.append("[center][i]" + body + "[/i][/center]")
			continue
		var player := speaker in ["player", "shopkeeper"]
		var speaker_name: String = copy.player_name if player else str(guest.get("name", copy.guest_name))
		var bubble_color: String = config.bubble_player_color if player else config.bubble_guest_color
		var align_tag := "right" if player else "left"
		var avatar := ""
		if not player and guest.get("npc_id") == "npc_lin":
			avatar = "[img=%dx%d]%s[/img] " % [config.bubble_avatar_size[0],config.bubble_avatar_size[1],LIN_EXPRESSIONS.neutral]
		var bubble := "[cell expand=%d shrink=false bg=%s padding=%s][color=%s][%s]%s[b]%s[/b]\n%s[/%s][/color]" % [int(config.bubble_main_ratio),bubble_color,padding_text,config.bubble_text_color,align_tag,avatar,_escape_bbcode(speaker_name),body,align_tag]
		if index == stamp_turn and not player:
			bubble += "\n[color=%s][b]〔%s〕[/b][/color]" % [config.bubble_stamp_color,_escape_bbcode(copy.clue_stamp)]
		bubble += "[/cell]"
		var spacer := "[cell expand=%d shrink=false] [/cell]" % int(config.bubble_spacer_ratio)
		lines.append("[table=2]" + (spacer + bubble if player else bubble + spacer) + "[/table]")
	return "\n".join(lines)

extends Control

const UI = preload("res://scripts/ui/ui_kit.gd")
const Materials = preload("res://scripts/ui/panel_materials.gd")
const LAYOUT_CONFIG := "res://data/ui/consultation.json"

const SceneArt = preload("res://scripts/shop/scene_visual.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const Portrait = preload("res://scripts/people/portrait.gd")
const ResponsiveConfig = preload("res://scripts/ui/responsive_config.gd")
const ViewportMetrics = preload("res://scripts/ui/viewport_metrics.gd")
const ResponsiveLayout = preload("res://scripts/ui/responsive_layout.gd")
const AppearanceEditorConfig = preload("res://scripts/people/appearance_editor_config.gd")

const OracleGuide = preload("res://scripts/divination/oracle_guide.gd")
const CaseBoard = preload("res://scripts/ui/case_board.gd")

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
var guest_portrait: Control
var bubble_avatar_textures: Array[Texture2D] = []
var _history_signature := ""
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
var case_board: Control
var input_row: HBoxContainer
var keyboard_hint: Label
var title_row: HBoxContainer
var _material_tabs: TabContainer
var _material_drawer_margin: MarginContainer
var _material_book_frame: Control
var _material_book_title: Label
var _material_book_vine: TextureRect
var _material_book_summary: RichTextLabel
var _material_letter_padding: MarginContainer
var _material_letter_frame: Control
var _material_nameplate: Control
var _material_name: Label
var _material_scene_base := Color.WHITE

static func layout_config_valid(config: Dictionary) -> bool:
	var height: Variant = config.get("transcript_minimum_height")
	if config.get("version") != 2 or not (height is int or height is float) or not is_finite(float(height)) or height <= 0 or height != floor(height):
		return false
	for key: String in ["portrait_minimum_size","banner_minimum_size"]:
		if not config.get(key) is Array or config[key].size() != 2 or not config[key].all(func(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value)) and value > 0 and value == floor(value)):
			return false
	var maximum_width: Variant = config.get("dialogue_max_width")
	if not (maximum_width is int or maximum_width is float) or not is_finite(float(maximum_width)) or maximum_width != floor(float(maximum_width)) or maximum_width < config.banner_minimum_size[0]:
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
	guest_portrait = Portrait.new()
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
	_material_letter_padding = padding
	dialogue_panel.add_child(padding)
	conversation = VBoxContainer.new()
	conversation.add_theme_constant_override("separation", int(layout_config.dialogue_gap))
	padding.add_child(conversation)
	title_row = HBoxContainer.new()
	conversation.add_child(title_row)
	title = UI.label("", int(layout_config.title_font_size))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	clue_label = UI.label("", int(layout_config.small_font_size), UI.MUTED)
	clue_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_row.add_child(clue_label)
	var history_scroll := ScrollContainer.new()
	history_scroll.name = "ConversationBodyScroll"
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	conversation.add_child(history_scroll)
	var history_column := VBoxContainer.new()
	history_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_scroll.add_child(history_column)
	transcript = UI.rich()
	transcript.bbcode_enabled = true
	transcript.theme_type_variation = &"Dialogue"
	transcript.name = "DialogueHistory"
	# Keep the existing text budget plus the new composite-avatar header visible.
	transcript.custom_minimum_size.y = float(layout_config.transcript_minimum_height) + float(layout_config.bubble_avatar_size[1]) + float(layout_config.bubble_padding[1]) + float(layout_config.bubble_padding[3])
	transcript.add_theme_font_size_override("normal_font_size", int(layout_config.body_font_size))
	history_column.add_child(transcript)
	questions = HFlowContainer.new()
	questions.add_theme_constant_override("h_separation", int(layout_config.question_gap))
	questions.add_theme_constant_override("v_separation", int(layout_config.dialogue_gap))
	history_column.add_child(questions)
	input_row = HBoxContainer.new()
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
	keyboard_hint = hint
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	conversation.add_child(hint)

	drawer_panel = UI.panel()
	drawer_panel.name = "ConsultationDrawer"
	drawer_panel.z_index = int(layout_config.drawer_z)
	add_child(drawer_panel)
	var drawer_margin := UI.margin(int(layout_config.dialogue_padding))
	_material_drawer_margin = drawer_margin
	drawer_panel.add_child(drawer_margin)
	var tabs := TabContainer.new()
	_material_tabs = tabs
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
	case_board = CaseBoard.new()
	case_board.name = "CaseBoard"
	case_board.host = host
	case_board.story_choice_saved.connect(_refresh_case_board)
	add_child(case_board)
	case_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_material_consultation()
	resized.connect(_queue_layout)
	get_tree().root.size_changed.connect(_queue_layout)
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
	if not is_instance_valid(dialogue_panel): return
	var metrics: Dictionary = ViewportMetrics.measure(self)
	var responsive: Dictionary = ResponsiveConfig.load_config()
	if not ViewportMetrics.valid(metrics) or responsive.is_empty(): return
	var client_size: Vector2 = metrics.visible_css
	var maximum_height: float = client_size.y*float(responsive.dialogue_max_ratio)
	var available: Rect2
	var minimum: Vector2
	if _case_board_enabled():
		case_board.call("_layout_material_speech")
		available = ViewportMetrics.css_rect(case_board.speech_panel,metrics)
		available.size.y = minf(available.size.y,maximum_height)
		var speech: Array = case_board.config.layout.speech_rect
		minimum = Vector2(speech[2],speech[3]).max(dialogue_panel.get_combined_minimum_size())
	else:
		var dialogue_width := minf(float(layout_config.dialogue_max_width),client_size.x-float(responsive.safe_margin)*2.0)
		var desired_height := maxf(float(layout_config.dialogue_minimum_height),client_size.y*float(layout_config.dialogue_ratio))
		var dialogue_height := minf(maximum_height,desired_height)
		available = Rect2(Vector2((client_size.x-dialogue_width)/2.0,client_size.y-float(responsive.dialogue_bottom)-dialogue_height),Vector2(dialogue_width,dialogue_height))
		minimum = Vector2(responsive.dialogue_minimum[0],responsive.dialogue_minimum[1]).max(dialogue_panel.get_combined_minimum_size())
	ResponsiveLayout.apply(dialogue_panel,ResponsiveLayout.fit_minimum(minimum,available,metrics,Vector2(0.5,1),true))
	_layout_portrait()
	if drawer_tween != null and drawer_tween.is_running(): drawer_tween.kill()
	if _layout_material_tools(metrics,responsive): return
	var width := minf(float(responsive.drawer_width),client_size.x)
	var top: float = 0.0 if metrics.short else float(layout_config.top_inset)
	var height: float = client_size.y if metrics.short else maxf(1.0,available.position.y-top-float(layout_config.drawer_gap))
	var drawer_box := Rect2(Vector2(client_size.x-width if drawer_open else client_size.x,top),Vector2(width,height))
	var drawer_minimum := drawer_panel.get_combined_minimum_size().max(Vector2(float(layout_config.drawer_width),height))
	ResponsiveLayout.apply(drawer_panel,ResponsiveLayout.fit_minimum(drawer_minimum,drawer_box,metrics,Vector2(0.5,0.5),true))
	var toggle_size := drawer_toggle.get_combined_minimum_size().max(Vector2(responsive.toggle_size[0],responsive.toggle_size[1]))
	var toggle_box := Rect2(Vector2(maxf(0,drawer_box.position.x-toggle_size.x),maxf(top,float(responsive.toggle_top))),toggle_size)
	ResponsiveLayout.apply(drawer_toggle,ResponsiveLayout.fit_minimum(toggle_size,toggle_box,metrics))

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
	var metrics: Dictionary = ViewportMetrics.measure(self)
	var responsive: Dictionary = ResponsiveConfig.load_config()
	var seat: Array = _default_seat
	if _case_board_enabled():
		seat = case_board.config.layout.portrait_rect
	elif ViewportMetrics.valid(metrics) and metrics.short:
		seat = compact.narrow_rect if metrics.visible_css.x <= float(compact.narrow_width_limit) else compact.rect
		if room_art.config.get("scene_settings",{}).get("version",2) == 3:
			var scene: Dictionary = room_art.config.scenes[room_art.scene_id]
			seat = scene.get("seat_narrow_rect",seat) if metrics.visible_css.x <= float(compact.narrow_width_limit) else scene.get("seat_compact_rect",seat)
	for row: Dictionary in room_art.placed_nodes:
		if row.node == guest_portrait:
			row.rect = seat
	var projected: Rect2 = room_art.projected_rect(seat)
	guest_portrait.position = projected.position
	guest_portrait.size = projected.size
	if ViewportMetrics.valid(metrics) and metrics.short and not responsive.is_empty():
		guest_portrait.position.y = maxf(float(responsive.safe_margin)/metrics.css_per_local_unit.y,projected.position.y-float(responsive.portrait_lift)/metrics.css_per_local_unit.y)

func set_drawer_expanded(expanded: bool, animate: bool = true) -> void:
	var from_panel := drawer_panel.position
	var from_toggle := drawer_toggle.position
	drawer_open = expanded
	drawer_toggle.text = layout_config.copy.drawer_close if expanded else layout_config.copy.drawer_open
	_layout_consultation()
	if not animate or not is_inside_tree(): return
	var panel_destination := drawer_panel.position
	var toggle_destination := drawer_toggle.position
	drawer_panel.position = from_panel
	drawer_toggle.position = from_toggle
	drawer_tween = create_tween().set_parallel(true)
	drawer_tween.tween_property(drawer_panel,"position",panel_destination,float(layout_config.drawer_seconds)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	drawer_tween.tween_property(drawer_toggle,"position",toggle_destination,float(layout_config.drawer_seconds)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

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
	guest_portrait.visible = active
	if guest_portrait.visible:
		guest_portrait.configure(guest_appearance(guest),presentation_mood(guest))
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
	_render_history(visit.get("dialogue",[]),guest,_new_clue_turn)
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
	_refresh_case_board()
	_refresh_material_public_summary(view)

func _case_board_enabled() -> bool:
	return is_instance_valid(case_board) and not case_board.config.is_empty() and bool(GameState.case_board_view().get("enabled",false))

func _refresh_case_board() -> void:
	if not is_instance_valid(case_board):
		return
	case_board.refresh()
	var board_enabled := _case_board_enabled()
	var free_questions: bool = board_enabled and GameState.free_question_enabled()
	if board_enabled and not case_board._blocking_prelude().is_empty():
		free_questions = false
	dialogue_panel.visible = not board_enabled or free_questions
	drawer_panel.visible = not board_enabled
	drawer_toggle.visible = not board_enabled
	title_row.visible = not board_enabled
	questions.visible = not board_enabled
	keyboard_hint.visible = not board_enabled
	if board_enabled:
		transcript.custom_minimum_size.y = float(case_board.config.layout.card_name_height)
		transcript.add_theme_font_size_override("normal_font_size",int(case_board.config.layout.small_font))
		input.custom_minimum_size.y = float(layout_config.input_height)
		case_board.speech_panel.visible = not free_questions and not case_board.public_view.get("closed",false)
		case_board.reaction_panel.visible = not free_questions and case_board.public_view.get("closed",false)
	else:
		transcript.custom_minimum_size.y = float(layout_config.transcript_minimum_height)+float(layout_config.bubble_avatar_size[1])+float(layout_config.bubble_padding[1])+float(layout_config.bubble_padding[3])
		transcript.add_theme_font_size_override("normal_font_size",int(layout_config.body_font_size))
	_queue_layout()

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
		if not player:
			var records := Appearance.layer_records(guest_appearance(guest),presentation_mood(guest))
			if records.size() == 1 and records[0].layer == "preset" and records[0].available:
				avatar = "[img=%dx%d]%s[/img] " % [config.bubble_avatar_size[0],config.bubble_avatar_size[1],records[0].path]
		var bubble := "[cell expand=%d shrink=false bg=%s padding=%s][color=%s][%s]%s[b]%s[/b]\n%s[/%s][/color]" % [int(config.bubble_main_ratio),bubble_color,padding_text,config.bubble_text_color,align_tag,avatar,_escape_bbcode(speaker_name),body,align_tag]
		if index == stamp_turn and not player:
			bubble += "\n[color=%s][b]〔%s〕[/b][/color]" % [config.bubble_stamp_color,_escape_bbcode(copy.clue_stamp)]
		bubble += "[/cell]"
		var spacer := "[cell expand=%d shrink=false] [/cell]" % int(config.bubble_spacer_ratio)
		lines.append("[table=2]" + (spacer + bubble if player else bubble + spacer) + "[/table]")
	return "\n".join(lines)

static func guest_appearance(guest: Dictionary) -> Dictionary:
	var value: Variant = guest.get("appearance",{})
	return Appearance.for_display(value if value is Dictionary else {},str(guest.get("npc_id","")))

static func presentation_mood(guest: Dictionary) -> String:
	var catalog := Appearance.load_config()
	var value: Variant = guest.get("mood")
	return value if value is String and value in catalog.get("moods",[]) else str(catalog.get("default_mood","neutral"))

func _render_history(dialogue: Array, guest: Dictionary, stamp_turn: int) -> void:
	var signature := JSON.stringify([dialogue,guest,stamp_turn,FileAccess.get_sha256(Appearance.CONFIG_PATH)])
	if signature == _history_signature:
		return
	_history_signature = signature
	transcript.text = ""
	bubble_avatar_textures.clear()
	for index: int in range(dialogue.size()):
		var turn: Dictionary = dialogue[index]
		var speaker := str(turn.get("speaker",""))
		if speaker not in ["npc","player","shopkeeper"]:
			transcript.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
			transcript.push_italics()
			transcript.add_text(str(turn.get("text","")))
			transcript.pop()
			transcript.pop()
			continue
		var player := speaker in ["player","shopkeeper"]
		transcript.push_table(2)
		transcript.set_table_column_expand(0,true,int(layout_config.bubble_spacer_ratio if player else layout_config.bubble_main_ratio),false)
		transcript.set_table_column_expand(1,true,int(layout_config.bubble_main_ratio if player else layout_config.bubble_spacer_ratio),false)
		if player:
			_history_spacer()
		_history_bubble(turn,guest,player,index == stamp_turn)
		if not player:
			_history_spacer()
		transcript.pop()
		transcript.newline()

func _history_spacer() -> void:
	transcript.push_cell()
	transcript.add_text(" ")
	transcript.pop()

func _history_bubble(turn: Dictionary, guest: Dictionary, player: bool, stamp: bool) -> void:
	var copy: Dictionary = layout_config.copy
	transcript.push_cell()
	var color := Color(layout_config.bubble_player_color if player else layout_config.bubble_guest_color)
	transcript.set_cell_row_background_color(color,color)
	var padding: Array = layout_config.bubble_padding
	transcript.set_cell_padding(Rect2(padding[0],padding[1],padding[2],padding[3]))
	transcript.push_color(Color(layout_config.bubble_text_color))
	transcript.push_paragraph(HORIZONTAL_ALIGNMENT_RIGHT if player else HORIZONTAL_ALIGNMENT_LEFT)
	if not player:
		var ui := AppearanceEditorConfig.load_config()
		var dimensions := Vector2i(ui.layout.bubble_composite_size[0],ui.layout.bubble_composite_size[1])
		var texture := Portrait.composite_texture(guest_appearance(guest),presentation_mood({"mood":turn.get("mood")}),{},dimensions)
		if texture != null:
			bubble_avatar_textures.append(texture)
			transcript.add_image(texture,int(layout_config.bubble_avatar_size[0]),int(layout_config.bubble_avatar_size[1]))
			transcript.add_text(" ")
	transcript.push_bold()
	transcript.add_text(copy.player_name if player else str(guest.get("name",copy.guest_name)))
	transcript.pop()
	transcript.add_text("\n"+str(turn.get("text","")))
	if stamp and not player:
		transcript.push_color(Color(layout_config.bubble_stamp_color))
		transcript.push_bold()
		transcript.add_text("\n〔"+copy.clue_stamp+"〕")
		transcript.pop()
		transcript.pop()
	transcript.pop()
	transcript.pop()
	transcript.pop()

func consume_drawer_event(event: InputEventMouseButton) -> bool:
	var metrics: Dictionary = ViewportMetrics.measure(self)
	if _case_board_enabled() or not drawer_open or not is_visible_in_tree() or not ViewportMetrics.valid(metrics) or (not metrics.short and Materials.load_config().is_empty()) or not event.pressed: return false
	var point: Vector2 = event.position*metrics.css_per_local_unit
	if ViewportMetrics.css_rect(drawer_panel,metrics).has_point(point) or ViewportMetrics.css_rect(drawer_toggle,metrics).has_point(point): return false
	if event.button_index == MOUSE_BUTTON_LEFT: set_drawer_expanded(false,false)
	return true

func _setup_material_consultation() -> void:
	_material_scene_base = room_art.modulate
	if Materials.load_config().is_empty(): return
	Materials.apply_panel(dialogue_panel,"letter")
	Materials.apply_panel(drawer_panel,"notebook")
	Materials.apply_panel(_material_tabs,"plain")
	var tab_style: StyleBox = Materials.style_for("paper","cream")
	if tab_style != null:
		for state: String in ["tab_unselected","tab_selected","tab_hovered","tab_disabled"]:
			_material_tabs.get_tab_bar().add_theme_stylebox_override(state,tab_style)
	Materials.apply_button(drawer_toggle,"paper_tag","legacy_consultation_book")
	# A neutral Control separates the layout container from its two page guides.
	# The actual TabContainer and its TabBar stay intact on the right page.
	var old_parent: Node = _material_drawer_margin.get_parent()
	old_parent.remove_child(_material_drawer_margin)
	_material_book_frame = Control.new()
	_material_book_frame.name = "ConsultationNotebookPages"
	_material_book_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer_panel.add_child(_material_book_frame)
	_material_book_frame.add_child(_material_drawer_margin)
	_material_book_title = UI.label(layout_config.copy.tab_casebook,int(layout_config.title_font_size))
	_material_book_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material_book_frame.add_child(_material_book_title)
	_material_book_vine = Materials.make_divider()
	_material_book_frame.add_child(_material_book_vine)
	_material_book_summary = UI.rich()
	_material_book_summary.mouse_filter = Control.MOUSE_FILTER_PASS
	_material_book_summary.add_theme_font_size_override("normal_font_size",int(layout_config.body_font_size))
	_material_book_frame.add_child(_material_book_summary)
	# Keep the existing conversation minimum; the new nameplate is an overlay,
	# not another nested framed section or a discarded body/input control.
	var old_letter_parent: Node = _material_letter_padding.get_parent()
	old_letter_parent.remove_child(_material_letter_padding)
	_material_letter_frame = Control.new()
	_material_letter_frame.name = "ConversationLetterContents"
	dialogue_panel.add_child(_material_letter_frame)
	_material_letter_frame.add_child(_material_letter_padding)
	_material_letter_padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material_letter_frame.custom_minimum_size = _material_letter_padding.get_combined_minimum_size()
	_material_letter_padding.minimum_size_changed.connect(func():
		_material_letter_frame.custom_minimum_size = _material_letter_padding.get_combined_minimum_size())
	_material_nameplate = Panel.new()
	_material_nameplate.name = "ConversationGuestNameplate"
	_material_nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material_letter_frame.add_child(_material_nameplate)
	Materials.apply_panel(_material_nameplate,"smalltag","cream")
	_material_name = UI.label("",int(layout_config.body_font_size))
	_material_name.name = "ConversationGuestNameText"
	_material_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	_material_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material_nameplate.add_child(_material_name)
	drawer_panel.resized.connect(_queue_material_consultation)
	_queue_material_consultation()

func _queue_material_consultation() -> void:
	_layout_material_consultation.call_deferred()

func _refresh_material_public_summary(view: Dictionary) -> void:
	if not is_instance_valid(_material_name): return
	var guest: Dictionary = view.get("guest",{})
	_material_name.text = str(guest.get("name",""))
	var padding: float = float(layout_config.dialogue_padding)
	_material_name.position = Vector2(padding,padding*0.5)
	_material_name.size = _material_name.get_combined_minimum_size()
	_material_nameplate.size = _material_name.size+Vector2(padding*2.0,padding)
	_material_nameplate.position = Vector2(padding,-_material_nameplate.size.y*0.5)
	_material_letter_padding.add_theme_constant_override("margin_top",int(padding+_material_nameplate.size.y*0.5))
	_material_book_title.text = str(guest.get("name",layout_config.copy.tab_casebook))
	# The public opening is a customer statement, never a world-fact upgrade.
	_material_book_summary.text = str(view.get("opening_statement",""))
	_queue_material_consultation()

func _layout_material_consultation() -> void:
	if not is_instance_valid(_material_book_frame): return
	var material: Dictionary = Materials.load_config()
	var guides: Array = Materials.content_rects(drawer_panel.size,"notebook")
	if material.is_empty() or guides.size() != 2: return
	var left: Rect2 = guides[0]
	var right: Rect2 = guides[1]
	var header_height: float = float(layout_config.title_font_size)+float(material.layout.divider_gap)*2.0
	_material_book_title.position = left.position
	_material_book_title.size = Vector2(left.size.x,header_height)
	_material_book_vine.position = left.position+Vector2(0,header_height)
	_material_book_vine.size = Vector2(left.size.x,float(material.layout.divider_height))
	var inset: float = header_height+float(material.layout.divider_height)+float(material.layout.divider_gap)
	_material_book_summary.position = left.position+Vector2(0,inset)
	_material_book_summary.size = Vector2(left.size.x,maxf(1,left.size.y-inset))
	_material_drawer_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_material_drawer_margin.position = right.position
	_material_drawer_margin.size = right.size
	for edge: String in ["margin_left","margin_top","margin_right","margin_bottom"]: _material_drawer_margin.add_theme_constant_override(edge,0)
	var metrics: Dictionary = ViewportMetrics.measure(self)
	if ViewportMetrics.valid(metrics):
		var effective: Vector2 = drawer_panel.get_global_transform_with_canvas().get_scale()*metrics.css_per_local_unit
		drawer_panel.set_meta("material_effective_css_scale",effective)
		drawer_panel.set_meta("material_effective_font_sizes",{"body":float(layout_config.body_font_size)*effective.y,"small":float(layout_config.small_font_size)*effective.y})
		drawer_panel.set_meta("material_content_rects",guides)

func _update_material_scene_dimming() -> void:
	if not is_instance_valid(room_art): return
	var material: Dictionary = Materials.load_config()
	if material.is_empty():
		room_art.modulate = _material_scene_base
		return
	var opened: bool = is_instance_valid(case_board) and case_board.is_visible_in_tree() and case_board.paper.is_visible_in_tree() if _case_board_enabled() else drawer_open
	var opacity: float = float(material.backdrop.opacity) if opened else 0.0
	room_art.modulate = _material_scene_base*Color(1.0-opacity,1.0-opacity,1.0-opacity,1)

func _layout_material_tools(metrics: Dictionary, responsive: Dictionary) -> bool:
	var material: Dictionary = Materials.load_config()
	if material.is_empty(): return false
	var client_size: Vector2 = metrics.visible_css
	var margin: float = float(responsive.safe_margin)
	var width: float = minf(float(material.layout.book_preferred_width),client_size.x-margin*2.0)
	var height: float = client_size.y if metrics.short else minf(float(material.layout.book_preferred_height),client_size.y-margin*2.0)
	var top: float = 0.0 if metrics.short else (client_size.y-height)*0.5
	var left: float = client_size.x-width-(0.0 if metrics.short else margin) if drawer_open else client_size.x
	var box := Rect2(Vector2(left,top),Vector2(width,height))
	var minimum := Vector2(material.layout.book_minimum_size[0],material.layout.book_minimum_size[1])
	ResponsiveLayout.apply(drawer_panel,ResponsiveLayout.fit_minimum(minimum,box,metrics,Vector2(0.5,0.5),true))
	drawer_panel.set_meta("material_fixed_layout",bool(metrics.short))
	var toggle_size := drawer_toggle.get_combined_minimum_size().max(Vector2(responsive.toggle_size[0],responsive.toggle_size[1]))
	var toggle_box := Rect2(Vector2(maxf(0,left-toggle_size.x),maxf(top,float(responsive.toggle_top))),toggle_size)
	ResponsiveLayout.apply(drawer_toggle,ResponsiveLayout.fit_minimum(toggle_size,toggle_box,metrics))
	_queue_material_consultation()
	_update_material_scene_dimming()
	return true

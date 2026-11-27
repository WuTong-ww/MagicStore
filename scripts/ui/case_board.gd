extends Control
signal input_overlay_changed
## This screen consumes only the committed public projection. It never reads
## the case definition, card order, answers, or the private world state.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Nationality = preload("res://scripts/people/nationality.gd")
const Materials = preload("res://scripts/ui/panel_materials.gd")
const Icons = preload("res://scripts/ui/icon_policy.gd")
const Config = preload("res://scripts/ui/case_board_config.gd")
const EvidenceToken = preload("res://scripts/ui/case_evidence_token.gd")
const DeductionSlot = preload("res://scripts/ui/case_deduction_slot.gd")
const StoryUI = preload("res://scripts/ui/story_ui_config.gd")
const ResponsiveConfig = preload("res://scripts/ui/responsive_config.gd")
const ViewportMetrics = preload("res://scripts/ui/viewport_metrics.gd")
const ResponsiveLayout = preload("res://scripts/ui/responsive_layout.gd")
const Flow = preload("res://scripts/ui/case_flow.gd")
const CardArt = preload("res://scripts/ui/case_card_art.gd")
const CardZoom = preload("res://scripts/ui/case_card_zoom.gd")
var flow: Control
var card_art_index: Dictionary = {}
var card_zoom: Control
signal story_choice_saved
var host
var config: Dictionary = {}
var story_config: Dictionary = {}
var responsive_config: Dictionary = {}
var drawer_backdrop: ColorRect
var drawer_toggle: Button
var drawer_open := false
var canvas: Control
var paper: Panel
var slot_area: VBoxContainer
var book_title: Label
var book_slot_scroll: ScrollContainer
var book_left_vine: TextureRect
var book_right_vine: TextureRect
var speech_nameplate: Control
var speech_name: Label
var reaction_nameplate: Control
var reaction_name: Label
var heading: Label
var instruction: Label
var speech_panel: Panel
var speech_label: RichTextLabel
var cards_row: HBoxContainer
var card_nodes: Array[Button] = []
var question_buttons: GridContainer
var advice_buttons: HBoxContainer
var utility_buttons: HBoxContainer
var question_area: Control
var evidence_box: GridContainer
var evidence_scroll: ScrollContainer
var evidence_title: Label
var slot_nodes: Dictionary = {}
var reaction_panel: Panel
var reaction_label: RichTextLabel
var reaction_title: Label
var end_button: Button
var extra_button: Button
var eliminate_button: Button
var method_button: Button
var learning_copy: Dictionary = {}
var _method_open := false
var public_view: Dictionary = {}
var _pending := false
# Future LEARN public adapter; empty keeps the actual-case path.
var public_view_getter: Callable
var command_submitter: Callable
var _selected_evidence := ""
var _extra_open := false
var _elimination_open := false
var _question_signature := ""
var _advice_signature := ""
var _evidence_signature := ""
var _slot_signatures: Dictionary = {}

func _ready() -> void:
	config = Config.load_config()
	card_art_index = CardArt.load_index()
	learning_copy = preload("res://scripts/learning/learning_rules.gd").load_config().get("ui",{}).get("copy",{})
	story_config = StoryUI.load_config()
	if config.is_empty():
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	z_index = int(config.layout.z_index)
	theme = load("res://themes/paper.tres")
	canvas = Control.new()
	canvas.name = "CaseBoardCanvas"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	canvas.size = Vector2(config.layout.base_width,config.layout.base_height)
	var heading_paper := _panel("CaseHeadingPaper",config.layout.heading_rect)
	var heading_box := VBoxContainer.new()
	heading_box.name = "CaseHeading"
	heading_box.add_theme_constant_override("separation",0)
	_fill(heading_paper,heading_box,int(config.layout.slot_padding))
	heading = _label("",int(config.layout.title_font))
	heading_box.add_child(heading)
	instruction = _label("",int(config.layout.small_font))
	heading_box.add_child(instruction)
	speech_panel = _panel("CaseGuestReply",config.layout.speech_rect)
	speech_label = UI.rich()
	speech_label.name = "CasePublicReply"
	speech_label.add_theme_font_size_override("normal_font_size",int(config.layout.body_font))
	_fill(speech_panel,speech_label,int(config.layout.padding))
	cards_row = HBoxContainer.new()
	cards_row.name = "CaseCardRow"
	cards_row.add_theme_constant_override("separation",int(config.layout.card_gap))
	cards_row.minimum_size_changed.connect(_queue_table_layout)
	canvas.add_child(cards_row)
	_place(cards_row,config.layout.cards_rect)
	for index: int in range(int(config.layout.card_count)):
		_build_card(index)
	question_area = Control.new()
	question_area.name = "CaseQuestionArea"
	canvas.add_child(question_area)
	_place(question_area,config.layout.question_rect)
	question_buttons = GridContainer.new()
	question_buttons.name = "CaseQuestions"
	question_buttons.columns = int(config.layout.question_columns)
	question_buttons.add_theme_constant_override("h_separation",int(config.layout.question_gap))
	question_buttons.add_theme_constant_override("v_separation",int(config.layout.question_gap))
	question_area.add_child(question_buttons)
	question_buttons.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	question_buttons.offset_bottom = float(config.layout.question_height)
	advice_buttons = _button_row("CaseAdvice")
	question_area.add_child(advice_buttons)
	advice_buttons.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	advice_buttons.offset_bottom = float(config.layout.question_height)
	utility_buttons = _button_row("CaseUtilities")
	question_area.add_child(utility_buttons)
	utility_buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	utility_buttons.offset_top = -float(config.layout.card_name_height)
	extra_button = _button(config.copy.extra_question,func():
		_extra_open = not _extra_open
		refresh())
	extra_button.name = "CaseExtraQuestion"
	utility_buttons.add_child(extra_button)
	eliminate_button = _button(config.copy.eliminate,func():
		_elimination_open = not _elimination_open
		instruction.text = config.copy.choose_elimination if _elimination_open else config.copy.deduction_instruction)
	eliminate_button.name = "CaseEliminate"
	utility_buttons.add_child(eliminate_button)
	method_button = _button(str(learning_copy.get("method_tools","")),func():
		_method_open = not _method_open
		_extra_open = false
		refresh())
	method_button.name = "CaseMethodTools"
	utility_buttons.add_child(method_button)
	paper = _panel("CaseBoardPaper",config.layout.board_rect)
	book_title = _label(config.copy.board_title,int(config.layout.title_font))
	paper.add_child(book_title)
	_place(book_title,config.layout.board_title_rect)
	slot_area = VBoxContainer.new()
	slot_area.add_theme_constant_override("separation",int(config.layout.slot_gap))
	paper.add_child(slot_area)
	_place(slot_area,config.layout.slots_rect)
	for index: int in range(int(config.layout.slot_count)):
		var slot := DeductionSlot.new()
		slot.name = "CaseSlot_"+str(index)
		slot.board = self
		slot.custom_minimum_size.y = float(config.layout.slot_height)
		slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slot.add_theme_stylebox_override("panel",_style("locked"))
		slot_area.add_child(slot)
		slot_nodes[str(index)] = slot
	evidence_title = _label(config.copy.evidence_title,int(config.layout.small_font))
	evidence_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	paper.add_child(evidence_title)
	_place(evidence_title,config.layout.evidence_title_rect)
	evidence_scroll = ScrollContainer.new()
	evidence_scroll.name = "CaseEvidenceScroll"
	evidence_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper.add_child(evidence_scroll)
	_place(evidence_scroll,config.layout.evidence_rect)
	evidence_box = GridContainer.new()
	evidence_box.columns = int(config.layout.evidence_columns)
	evidence_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	evidence_box.add_theme_constant_override("h_separation",int(config.layout.evidence_gap))
	evidence_box.add_theme_constant_override("v_separation",int(config.layout.evidence_gap))
	evidence_scroll.add_child(evidence_box)
	reaction_panel = _panel("CaseReaction",config.layout.reaction_rect)
	var reaction_box := VBoxContainer.new()
	_fill(reaction_panel,reaction_box,int(config.layout.padding))
	var rating := HBoxContainer.new()
	reaction_box.add_child(rating)
	rating.add_child(_image_icon(config.copy.star,float(config.layout.seal_size),Color(config.colors.ink)))
	reaction_title = _label("",int(config.layout.title_font))
	rating.add_child(reaction_title)
	reaction_label = UI.rich()
	reaction_label.name = "CaseReactionText"
	reaction_label.add_theme_font_size_override("normal_font_size",int(config.layout.body_font))
	reaction_box.add_child(reaction_label)
	end_button = _button(config.copy.end_visit,func(): await _submit("end_visit",{}))
	end_button.name = "CaseEndVisit"
	question_area.add_child(end_button)
	end_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	end_button.offset_bottom = float(config.layout.question_height)
	_build_short_drawer()
	_setup_materials()
	flow = Flow.new()
	flow.name = "CaseFlow"
	flow.board = self
	add_child(flow)
	resized.connect(_layout)
	get_tree().root.size_changed.connect(_on_client_resized)
	_layout()
	refresh()

func _place(node: Control, values: Array) -> void:
	node.position = Vector2(values[0],values[1])
	node.size = Vector2(values[2],values[3])

func _fill(parent: Control, child: Control, padding: int) -> void:
	var margin := UI.margin(padding)
	parent.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(child)

func _label(text: String, font_size: int) -> Label:
	var label := UI.label(text,font_size,Color(config.colors.ink))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _panel(node_name: String, rect: Array) -> Panel:
	var node := Panel.new()
	node.name = node_name
	node.add_theme_stylebox_override("panel",_style("paper"))
	canvas.add_child(node)
	_place(node,rect)
	return node

func _style(color_key: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(config.colors[color_key])
	style.border_color = Color(config.colors.gold)
	style.set_border_width_all(int(config.layout.border))
	style.set_corner_radius_all(int(config.layout.slot_padding))
	style.content_margin_left = float(config.layout.slot_padding)
	style.content_margin_right = float(config.layout.slot_padding)
	style.content_margin_top = float(config.layout.slot_padding)
	style.content_margin_bottom = float(config.layout.slot_padding)
	return style

func _image_icon(id: String, side: float, tint: Color) -> TextureRect:
	var symbol := TextureRect.new()
	symbol.texture = Icons.texture(id)
	symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	symbol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	symbol.custom_minimum_size = Vector2.ONE*side
	symbol.modulate = tint
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return symbol

func _button(text: String, callback: Callable) -> Button:
	var button := UI.button(text,callback)
	button.custom_minimum_size.y = float(config.layout.card_name_height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size",int(config.layout.button_font))
	return button

func _button_row(node_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation",int(config.layout.question_gap))
	return row

func _build_card(index: int) -> void:
	var button := _button("",func():
		if button_card_revealed(index): show_card_zoom(index)
		else: await _submit("case_flip_card",{"card_index":index}))
	button.name = "CaseCard_"+str(index)
	button.custom_minimum_size = Vector2(config.layout.card_width,config.layout.card_height)
	button.tooltip_text = config.copy.card_tooltip
	cards_row.add_child(button)
	var art := TextureRect.new()
	art.name = "CardArt"
	art.set_meta("case_card_ratio",true)
	art.texture = load(config.assets.card_back)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	art.offset_bottom = float(config.layout.card_art_height)
	var blank := Panel.new()
	blank.name = "CardBlankFace"
	blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(blank)
	blank.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Materials.apply_panel(blank,"paper","cream")
	blank.hide()
	var ornament := CenterContainer.new()
	ornament.name = "CardOrnament"
	ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ornament.add_child(_image_icon(config.copy.ornament,float(config.layout.ornament_font),Color(config.colors.ink)))
	button.add_child(ornament)
	ornament.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ornament.offset_bottom = -float(config.layout.card_name_height)
	ornament.hide()
	var name_label := _label("",int(config.layout.body_font))
	name_label.name = "CardName"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_child(name_label)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -float(config.layout.card_name_height)
	name_label.offset_bottom = -float(config.layout.slot_padding)
	var rank := _label("",int(config.layout.title_font))
	rank.name = "CardRank"
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_child(rank)
	var strip := UI.rich()
	strip.name = "CardClueStrip"
	strip.fit_content = false
	strip.scroll_active = true
	strip.mouse_filter = Control.MOUSE_FILTER_PASS
	strip.add_theme_font_size_override("normal_font_size",int(config.flow.font_size))
	button.add_child(strip)
	strip.hide()
	card_nodes.append(button)
	Materials.apply_tarot_card(button,art,"case_card_"+str(index))

func _layout() -> void:
	if canvas == null or config.is_empty():
		return
	var factor := minf(size.x/float(config.layout.base_width),size.y/float(config.layout.base_height))
	# Hidden/newly attached controls can receive a zero-sized layout before the
	# parent container sorts. Keep the previous invertible transform until then.
	if factor <= 0.0: return
	canvas.scale = Vector2.ONE*factor
	canvas.position = (size-canvas.size*factor)/2.0
	_layout_short_drawer()
	_queue_table_layout()
	if is_instance_valid(flow): flow.layout()

func _queue_table_layout() -> void:
	_layout_cards_on_table.call_deferred()

func _layout_cards_on_table() -> void:
	if not is_inside_tree() or not is_instance_valid(cards_row): return
	var metrics := ViewportMetrics.measure(self)
	if not ViewportMetrics.valid(metrics): return
	var height: float = maxf(float(config.card_view.minimum_height)*minf(1.0,metrics.visible_css.y/float(config.layout.base_height)),metrics.visible_css.y*float(config.card_view.height_ratio))
	var width: float = height*float(config.card_view.ratio)
	var strip_height: float = float(config.flow.button_height) if metrics.short else float(config.card_view.strip_height)
	var extra: float = float(config.layout.card_name_height)+strip_height
	var row_size := Vector2(width*card_nodes.size()+float(config.layout.card_gap)*(card_nodes.size()-1),height+extra)
	var bottom: float = metrics.visible_css.y-float(config.flow.bottom)
	if is_instance_valid(host) and host.shell_dock != null: bottom = ViewportMetrics.css_rect(host.shell_dock,metrics).position.y-float(config.flow.gap)
	ResponsiveLayout.apply(cards_row,ResponsiveLayout.fit_minimum(row_size,Rect2(Vector2(float(config.flow.gap),bottom-row_size.y),row_size),metrics))
	var tools_size := Vector2(maxf(row_size.x,utility_buttons.get_combined_minimum_size().x),maxf(float(config.flow.button_height),utility_buttons.get_combined_minimum_size().y))
	ResponsiveLayout.apply(utility_buttons,ResponsiveLayout.fit_minimum(tools_size,Rect2(Vector2(float(config.flow.gap),bottom-row_size.y-tools_size.y-float(config.flow.gap)),tools_size),metrics))
	for button: Button in card_nodes:
		button.custom_minimum_size = Vector2(width,height+extra)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var art: TextureRect = button.get_node("CardArt")
		art.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		art.position = Vector2.ZERO
		art.size = Vector2(width,height)
		var blank: Control = button.get_node("CardBlankFace")
		blank.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		blank.position = Vector2.ZERO
		blank.size = art.size
		var name_text: Label = button.get_node("CardName")
		name_text.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		name_text.position = Vector2(0,height)
		name_text.size = Vector2(width,float(config.layout.card_name_height))
		var rank: Label = button.get_node("CardRank")
		rank.position = Vector2(0,height*0.35)
		rank.size = Vector2(width,height*0.3)
		var strip: RichTextLabel = button.get_node("CardClueStrip")
		strip.position = Vector2(0,height+float(config.layout.card_name_height))
		strip.size = Vector2(width,strip_height)
	_layout_material_speech()

func refresh() -> void:
	if config.is_empty() or _pending:
		return
	public_view = public_view_getter.call() if public_view_getter.is_valid() else GameState.case_board_view()
	visible = bool(public_view.get("enabled",false))
	if not visible:
		return
	var closed := bool(public_view.get("closed",false))
	var phase := str(public_view.get("phase","questions"))
	var prelude: Dictionary = _blocking_prelude()
	# Free conversation can change energy while the optional choices are open.
	# Keep the basic card path accessible when that saved eligibility changes.
	if not public_view.get("can_extra_question",false) or not prelude.is_empty():
		_extra_open = false
	if public_view.get("method_tools",[]).is_empty() or closed: _method_open = false
	heading.text = str(public_view.get("title",config.copy.heading))
	instruction.text = config.copy.closed_instruction if closed else (config.copy.question_round.format({"round":int(public_view.get("round",0))+1}) if phase == "questions" else (config.copy.cards_instruction if phase == "cards" else config.copy.deduction_instruction))
	if _extra_open:
		instruction.text = config.copy.extra_instruction
	if not prelude.is_empty() and not story_config.is_empty():
		instruction.text = str(story_config.copy.prelude_instruction)
	var reply := str(public_view.get("last_answer",""))
	speech_label.text = reply if not reply.is_empty() else str(public_view.get("question",config.copy.empty_speech))
	if reply.is_empty() and public_view.has("mentor_intro"): speech_label.text = str(public_view.mentor_intro)
	var story_lines: Array[String] = StoryUI.public_lines(public_view.get("story_lines",[]))
	var separator := str(story_config.get("copy",{}).get("separator","\n\n"))
	if not prelude.is_empty():
		var text := str(prelude.get("text",""))
		if not text.is_empty() and text not in story_lines:
			story_lines.append(text)
	if not story_lines.is_empty() and (reply.is_empty() or not prelude.is_empty()):
		speech_label.text = separator.join(story_lines)
	var guest_info: String = str(public_view.get("guest_information",Nationality.information(public_view.get("guest",GameState.divination_view().get("guest",{})))))
	if not guest_info.is_empty(): speech_label.text = guest_info+"\n\n"+speech_label.text
	cards_row.visible = not _extra_open and not _method_open
	_refresh_cards()
	_refresh_slots()
	_refresh_evidence()
	_refresh_questions()
	_refresh_advice()
	extra_button.visible = bool(public_view.get("can_extra_question",false)) and not closed
	eliminate_button.visible = bool(public_view.get("can_eliminate",false)) and not closed
	method_button.visible = not public_view.get("method_tools",[]).is_empty() and not closed
	utility_buttons.visible = not closed and prelude.is_empty() and (phase != "questions" or method_button.visible)
	end_button.visible = closed
	reaction_panel.visible = closed
	speech_panel.visible = not closed
	if closed:
		reaction_title.text = config.copy.close_title.format({"stars":str(int(public_view.get("stars",1)))})
		reaction_label.text = str(public_view.get("reaction",config.copy.reaction_empty))
		if not story_lines.is_empty():
			reaction_label.text += separator+separator.join(story_lines)
	_set_busy(bool(host.busy) if is_instance_valid(host) else false)
	_refresh_material_name()
	if is_instance_valid(flow): flow.refresh()

func _blocking_prelude() -> Dictionary:
	var value: Variant = public_view.get("prelude",{})
	return value if value is Dictionary and value.get("blocks_progress",false) else {}

func _refresh_cards() -> void:
	var cards: Array = public_view.get("cards",[])
	for index: int in range(card_nodes.size()):
		var button := card_nodes[index]
		var row: Dictionary = cards[index] if index < cards.size() else {"index":index,"revealed":false}
		var revealed := bool(row.get("revealed",false))
		button.set_meta("revealed",revealed)
		button.set_meta("available",revealed or (bool(row.get("enabled",false)) and not public_view.get("closed",false) and _blocking_prelude().is_empty()))
		var art: TextureRect = button.get_node("CardArt")
		art.texture = CardArt.texture(str(row.get("deck_id","")),card_art_index) if revealed else load(str(config.assets.card_back))
		button.get_node("CardBlankFace").visible = revealed and art.texture == null
		button.get_node("CardOrnament").hide()
		button.get_node("CardRank").text = str(row.get("mark",row.get("suit",""))) if revealed and art.texture == null else ""
		var display_name := str(row.get("name",""))
		if display_name.is_empty(): display_name = str(config.card_view.fallback)
		button.get_node("CardName").text = display_name if revealed else ""
		var strip: RichTextLabel = button.get_node("CardClueStrip")
		strip.text = str(row.get("text","")) if revealed else ""
		strip.visible = revealed
		button.tooltip_text = str(row.get("name",""))+"\n"+str(row.get("text","")) if revealed else config.copy.card_tooltip
		Materials.apply_tarot_card(button,art,"case_card_"+str(index))
	_queue_table_layout()

func button_card_revealed(index: int) -> bool:
	return index >= 0 and index < public_view.get("cards",[]).size() and public_view.cards[index].get("revealed",false)

func show_card_zoom(index: int) -> void:
	if not button_card_revealed(index): return
	if is_instance_valid(card_zoom): card_zoom.queue_free()
	card_zoom = CardZoom.new()
	card_zoom.board = self
	card_zoom.row = public_view.cards[index].duplicate(true)
	add_child(card_zoom)

func _refresh_questions() -> void:
	if _method_open:
		var tools: Array = public_view.get("method_tools",[])
		question_buttons.visible = true
		question_buttons.offset_top = -float(config.layout.card_height)-float(config.layout.question_gap)
		question_buttons.offset_bottom = -float(config.layout.question_gap)
		var tool_signature := JSON.stringify(tools)+"methods"
		if tool_signature == _question_signature: return
		_question_signature = tool_signature
		_clear(question_buttons)
		for tool: Dictionary in tools:
			var button := _button(str(tool.text),func(): await _submit(tool.action,tool.params))
			button.name = "CaseMethod_"+str(question_buttons.get_child_count())
			button.set_meta("available",true)
			button.custom_minimum_size.y = float(config.layout.question_height)
			question_buttons.add_child(button)
			Materials.apply_button(button,"paper_tag",button.name)
		return
	var prelude := _blocking_prelude()
	var blocked := not prelude.is_empty()
	var rows: Array = prelude.get("options",[]) if blocked else (public_view.get("extra_questions",[]) if _extra_open else public_view.get("questions",[]))
	question_buttons.visible = (blocked or public_view.get("phase") == "questions" or _extra_open) and not public_view.get("closed",false)
	question_buttons.offset_top = -float(config.layout.card_height)-float(config.layout.question_gap) if _extra_open else 0.0
	question_buttons.offset_bottom = -float(config.layout.question_gap) if _extra_open else float(config.layout.question_height)
	var signature := JSON.stringify([rows,_extra_open,prelude.get("id","")])
	if signature == _question_signature:
		return
	_question_signature = signature
	_clear(question_buttons)
	for row: Dictionary in rows:
		var action := "story_choice" if blocked else ("case_extra_question" if _extra_open else "case_question")
		var payload := {"choice_id":row.id} if blocked else {"question_id":row.id}
		var button := _button(str(row.get("text","")),func(): await _submit(action,payload))
		button.name = ("StoryChoice_" if blocked else "CaseQuestion_")+str(question_buttons.get_child_count())
		if blocked:
			button.set_meta("choice_id",str(row.id))
		button.set_meta("available",bool(row.get("enabled",true)))
		button.custom_minimum_size.y = float(config.layout.question_height)
		button.tooltip_text = str(row.get("reason",""))
		question_buttons.add_child(button)
		Materials.apply_button(button,"paper_tag","case_question_"+str(row.id))

func _refresh_advice() -> void:
	var rows: Array = public_view.get("advice",[])
	advice_buttons.visible = public_view.get("phase") == "deduction" and not _extra_open and not _method_open and not public_view.get("closed",false) and _blocking_prelude().is_empty()
	var signature := JSON.stringify(rows)
	if signature == _advice_signature:
		return
	_advice_signature = signature
	_clear(advice_buttons)
	for row: Dictionary in rows:
		var text: String = str(row.text)+(" · "+str(row.preview) if row.has("preview") else "")
		var button := _button(text,func(): await _submit("case_close",{"advice_id":row.id}))
		button.name = "CaseAdvice_"+str(advice_buttons.get_child_count())
		button.set_meta("available",bool(row.get("enabled",false)))
		advice_buttons.add_child(button)
		button.theme_type_variation = "WaxButton"
		Materials.apply_button(button,"wax","case_advice_"+str(row.id))

func _refresh_slots() -> void:
	var rows: Array = public_view.get("slots",[])
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var slot: Control = slot_nodes.get(str(row.id),slot_nodes.get(str(index)))
		if slot == null: continue
		slot.slot_id = row.id
		slot_nodes[row.id] = slot
		var signature := JSON.stringify(row)+str(public_view.get("closed",false))+str(_blocking_prelude().is_empty())
		if _slot_signatures.get(row.id) == signature: continue
		_slot_signatures[row.id] = signature
		_clear(slot)
		Materials.apply_panel(slot,"plain")
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_theme_constant_override("separation",int(config.layout.slot_gap))
		slot.add_child(column)
		var header := HBoxContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_child(header)
		var title_text: String = String(learning_copy.get("key_label","{title}")).format({"title":row.title}) if row.get("critical_hint",false) else str(row.title)
		var title := _label(title_text,int(config.layout.body_font))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var status_key := "slot_sealed" if not str(row.get("selected","")).is_empty() else ("slot_attached" if not row.get("attached_ids",[]).is_empty() else "slot_empty")
		var status := _label(str(config.flow[status_key]),int(config.layout.small_font))
		status.name = "CaseSlotStatus"
		status.autowrap_mode = TextServer.AUTOWRAP_OFF
		status.add_theme_color_override("font_color",Color(config.colors.muted))
		header.add_child(status)
		if not row.get("unlocked",false):
			var locked := _label(config.copy.locked,int(config.layout.small_font))
			locked.size_flags_vertical = Control.SIZE_EXPAND_FILL
			column.add_child(locked)
		else:
			var answers := GridContainer.new()
			answers.name = "CaseAnswerRow"
			answers.columns = int(config.layout.question_columns)
			answers.add_theme_constant_override("h_separation",int(config.layout.question_gap))
			answers.add_theme_constant_override("v_separation",int(config.layout.question_gap))
			answers.size_flags_vertical = Control.SIZE_EXPAND_FILL
			column.add_child(answers)
			for answer: Dictionary in row.get("candidates",[]):
				var button := _button(str(answer.text),func(): await _activate_candidate(str(row.id),str(answer.id)))
				button.name = "CaseAnswer_"+str(answers.get_child_count())
				button.add_theme_font_size_override("font_size",int(config.layout.answer_font))
				button.mouse_filter = Control.MOUSE_FILTER_PASS
				button.set_meta("available",bool(answer.get("enabled",true)) and not public_view.get("closed",false) and _blocking_prelude().is_empty())
				answers.add_child(button)
				var selected: bool = str(row.get("selected","")) == str(answer.id)
				Materials.apply_candidate(button,str(row.id)+":"+str(answer.id),selected)
				var stamp: Control = button.get_node_or_null("MaterialSelectionStamp")
				if not selected and stamp != null:
					button.remove_child(stamp)
					stamp.queue_free()
				elif stamp != null:
					# Adopt the single material-owned stamp; keep the historical lookup API.
					stamp.name = "CaseWaxSeal"
					stamp.tooltip_text = config.copy.sealed
		if row.get("attached_ids",[]).is_empty(): _make_empty_drop_outline(slot)
	_queue_material_pages()

func _refresh_evidence() -> void:
	var rows: Array = public_view.get("evidence",[])
	var signature := JSON.stringify([rows,_selected_evidence,public_view.get("closed",false)])
	if signature == _evidence_signature: return
	_evidence_signature = signature
	_clear(evidence_box)
	evidence_title.text = config.copy.selected_material if not _selected_evidence.is_empty() else config.copy.evidence_title
	if rows.is_empty():
		var guidance := _label(config.copy.evidence_empty,int(config.layout.small_font))
		guidance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		evidence_box.add_child(guidance)
	for row: Dictionary in rows:
		var token := EvidenceToken.new()
		token.name = "CaseEvidence_"+str(evidence_box.get_child_count())
		token.evidence_id = row.id
		token.drag_label = str(row.text)
		var kind := str(row.get("kind",""))
		var source: String = str(row.get("source",config.copy.get(kind,config.copy.testimony)))
		token.text = source+" · "+str(row.text)
		token.tooltip_text = token.text
		token.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		token.add_theme_font_size_override("font_size",int(config.layout.small_font))
		token.custom_minimum_size.y = float(config.layout.evidence_height)
		token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		token.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		token.set_meta("available",public_view.get("phase") == "deduction" and not public_view.get("closed",false))
		Materials.apply_evidence(token,kind,str(row.id))
		token.toggle_mode = true
		token.set_pressed_no_signal(str(row.id) == _selected_evidence)
		token.drag_preview_factory = func() -> Control: return Materials.make_drag_preview(token.drag_label,kind,str(row.id))
		# EvidenceToken is constructed directly, so it has no UIkit sound callback.
		token.button_down.connect(_play_material_paper_sound.bind(token))
		token.pressed.connect(func():
			_selected_evidence = str(row.id)
			_refresh_evidence()
			if is_instance_valid(flow): flow.refresh())
		evidence_box.add_child(token)
	_queue_material_pages()

func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _set_busy(value: bool) -> void:
	for button: Node in find_children("*","Button",true,false):
		button.disabled = value or not bool(button.get_meta("available",true))

func can_drop_material(slot_id: String, payload: Variant) -> bool:
	return not _pending and not bool(host.busy) and _blocking_prelude().is_empty() and public_view.get("phase") == "deduction" and not public_view.get("closed",false) and payload is Dictionary and payload.get("kind") == "case_evidence" and payload.get("evidence_id") is String and slot_nodes.has(slot_id) and public_view.get("evidence",[]).any(func(row: Dictionary) -> bool: return row.id == payload.evidence_id)

func activate_slot(slot_id: String) -> void:
	if _elimination_open:
		_elimination_open = false
		await _submit("case_eliminate",{"slot_id":slot_id})
	elif not _selected_evidence.is_empty():
		await attach_material(slot_id,_selected_evidence)

func _activate_candidate(slot_id: String, answer_id: String) -> void:
	if _elimination_open or not _selected_evidence.is_empty():
		await activate_slot(slot_id)
	else:
		await _submit("case_choose_answer",{"slot_id":slot_id,"answer_id":answer_id})

func attach_material(slot_id: String, evidence_id: String) -> void:
	var payload := {"kind":"case_evidence","evidence_id":evidence_id}
	if not can_drop_material(slot_id,payload):
		return
	# Relevance is public routing, never correctness. Incorrect material receives
	# an immediate nudge and still leaves the saved state completely untouched.
	var related: bool = public_view.evidence.any(func(row: Dictionary) -> bool: return row.id == evidence_id and slot_id in row.slot_ids)
	if not related:
		host.show_notice(config.copy.not_related)
		_feedback("cancel",slot_nodes[slot_id],false)
		return
	await _submit("case_attach_evidence",{"slot_id":slot_id,"evidence_id":evidence_id})

func _submit(action: String, values: Dictionary) -> void:
	if _pending or not is_instance_valid(host) or host.busy:
		return
	_pending = true
	_set_busy(true)
	if is_instance_valid(flow): flow.refresh()
	var target: Control = card_nodes[int(values.card_index)] if action == "case_flip_card" else slot_nodes.get(str(values.get("slot_id","")),question_area)
	var source_position := Vector2.ZERO
	var flying_text := ""
	var before_evidence: Array = public_view.get("evidence",[]).map(func(row: Dictionary) -> String: return str(row.id))
	if action == "case_attach_evidence":
		for token: Node in evidence_box.get_children():
			if token.get("evidence_id") == values.get("evidence_id"):
				source_position = canvas.get_global_transform().affine_inverse()*token.get_global_rect().get_center()
				flying_text = token.text
	var result: Dictionary
	if command_submitter.is_valid():
		result = await command_submitter.call(action,values)
	else:
		result = await host.run_action(action,values)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_pending = false
	if result.get("success",false):
		_method_open = false
		if action == "case_extra_question":
			_extra_open = false
		if action == "case_attach_evidence":
			_selected_evidence = ""
		if action == "case_flip_card":
			_feedback("card_flip",target,true)
			await _animate_saved_flip(target)
		else: refresh()
		if action == "story_choice":
			story_choice_saved.emit()
		if action == "case_attach_evidence":
			_fly_material(source_position,target,flying_text)
		elif action in ["case_question","case_extra_question"]:
			var reply_origin: Vector2 = canvas.get_global_transform().affine_inverse()*speech_panel.get_global_rect().get_center()
			for token: Node in evidence_box.get_children():
				if token.get("evidence_id") is String and token.evidence_id not in before_evidence:
					_fly_material(reply_origin,token,token.text)
		if action != "case_flip_card": _feedback("paper" if action in ["case_question","case_extra_question"] else "confirm",target,true,action)
	else:
		refresh()
		_feedback("cancel",target,false)

func _animate_saved_flip(target: Control) -> void:
	var wind := get_node_or_null("/root/WindField")
	if wind != null and wind.reduced_motion:
		refresh()
		return
	_pending = true
	_set_busy(true)
	if is_instance_valid(flow): flow.refresh()
	target.pivot_offset = target.size/2.0
	var half: float = float(config.layout.flip_seconds)*0.5
	var shrink := create_tween()
	shrink.tween_property(target,"scale:x",0.0,half)
	await shrink.finished
	if not is_inside_tree(): return
	_pending = false
	refresh()
	_pending = true
	_set_busy(true)
	if is_instance_valid(flow): flow.refresh()
	var expand := create_tween()
	expand.tween_property(target,"scale:x",1.0,half)
	await expand.finished
	_pending = false
	refresh()
	var strip: Control = target.get_node("CardClueStrip")
	var origin := strip.position
	strip.position.y -= float(config.card_view.strip_slide)
	create_tween().tween_property(strip,"position",origin,float(config.card_view.strip_seconds))

func _fly_material(origin: Vector2, target: Control, text: String) -> void:
	var reduced := get_node_or_null("/root/WindField")
	if reduced != null and reduced.reduced_motion:
		return
	var paper_token := PanelContainer.new()
	paper_token.name = "CaseSavedMaterialFlight"
	paper_token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Materials.apply_panel(paper_token,"smalltag","neutral")
	paper_token.size = Vector2(config.layout.fly_width,config.layout.fly_height)
	canvas.add_child(paper_token)
	paper_token.position = origin-paper_token.size/2.0
	var label := _label(text,int(config.layout.small_font))
	label.clip_text = false
	paper_token.add_child(label)
	label.custom_minimum_size.x = float(config.layout.fly_width)
	var destination: Vector2 = canvas.get_global_transform().affine_inverse()*target.get_global_rect().get_center()-paper_token.size/2.0
	var tween := create_tween()
	tween.tween_property(paper_token,"position",destination,float(config.layout.feedback_seconds)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(paper_token.queue_free)

func _feedback(sound: String, target: Control, success: bool, action: String = "") -> void:
	var audio := get_tree().root.find_child("ShopAudio",true,false)
	if audio != null: audio.play_ui(sound)
	if not is_instance_valid(target): return
	var reduced := get_node_or_null("/root/WindField")
	if reduced != null and reduced.reduced_motion: return
	if success and action not in ["case_flip_card","case_attach_evidence","case_choose_answer"]: return
	var duration := float(config.layout.feedback_seconds)
	if success and action == "case_flip_card":
		target.pivot_offset = target.size/2.0
		target.scale.x = 0.0
		create_tween().tween_property(target,"scale:x",1.0,float(config.layout.flip_seconds)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif success and action == "case_choose_answer":
		var seal: Control = target.find_child("CaseWaxSeal",true,false)
		if seal != null:
			var running: Variant = seal.get_meta("material_stamp_tween") if seal.has_meta("material_stamp_tween") else null
			if not (running is Tween and running.is_valid() and running.is_running()): Materials.animate_stamp(seal)
	elif not success:
		var origin := target.position
		var tween := create_tween()
		tween.tween_property(target,"position:x",origin.x+float(config.layout.reject_offset),duration/3.0)
		tween.tween_property(target,"position:x",origin.x-float(config.layout.reject_offset),duration/3.0)
		tween.tween_property(target,"position",origin,duration/3.0)

func _build_short_drawer() -> void:
	responsive_config = ResponsiveConfig.load_config()
	if responsive_config.is_empty(): return
	drawer_backdrop = ColorRect.new()
	drawer_backdrop.name = "CaseToolsBackdrop"
	drawer_backdrop.color = Color(responsive_config.overlay_color)
	drawer_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer_backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			set_drawer_expanded(false,false)
			accept_event())
	canvas.add_child(drawer_backdrop)
	canvas.move_child(drawer_backdrop,0)
	drawer_toggle = _button(str(responsive_config.copy.case_open),func(): set_drawer_expanded(not drawer_open,false))
	drawer_toggle.name = "CaseToolsBookmark"
	canvas.add_child(drawer_toggle)
	drawer_backdrop.hide()
	drawer_toggle.hide()

func _layout_short_drawer() -> void:
	if responsive_config.is_empty() or not is_instance_valid(drawer_toggle): return
	var metrics: Dictionary = ViewportMetrics.measure(self)
	if not ViewportMetrics.valid(metrics): return
	var material: Dictionary = Materials.load_config()
	if material.is_empty():
		_layout_legacy_paper(metrics)
		return
	var margin: float = float(responsive_config.safe_margin)
	var width: float = minf(float(material.layout.book_preferred_width),float(metrics.visible_css.x)-margin*2.0)
	var height: float = float(metrics.visible_css.y) if metrics.short else minf(float(material.layout.book_preferred_height),float(metrics.visible_css.y)-margin*2.0)
	var top: float = 0.0 if metrics.short else (float(metrics.visible_css.y)-height)*0.5
	var available := Rect2(Vector2(float(metrics.visible_css.x)-width-(0.0 if metrics.short else margin),top),Vector2(width,height))
	var minimum := Vector2(material.layout.book_minimum_size[0],material.layout.book_minimum_size[1])
	ResponsiveLayout.apply(paper,ResponsiveLayout.fit_minimum(minimum,available,metrics,Vector2(0.5,0.5),true))
	paper.set_meta("material_fixed_layout",bool(metrics.short))
	paper.z_index = int(responsive_config.overlay_z)+1
	paper.visible = drawer_open
	ResponsiveLayout.apply(drawer_backdrop,ResponsiveLayout.fit_minimum(metrics.visible_css,Rect2(Vector2.ZERO,metrics.visible_css),metrics))
	drawer_backdrop.z_index = int(responsive_config.overlay_z)
	drawer_backdrop.visible = drawer_open
	drawer_toggle.text = str(responsive_config.copy.case_close if drawer_open else responsive_config.copy.case_open)
	var toggle_size := Vector2(responsive_config.toggle_size[0],responsive_config.toggle_size[1]).max(drawer_toggle.get_combined_minimum_size())
	var left: float = available.position.x-toggle_size.x if drawer_open else float(metrics.visible_css.x)-toggle_size.x
	var toggle_top: float = maxf(float(responsive_config.toggle_top),top) if drawer_open else float(responsive_config.toggle_top)
	ResponsiveLayout.apply(drawer_toggle,ResponsiveLayout.fit_minimum(toggle_size,Rect2(Vector2(maxf(0,left),toggle_top),toggle_size),metrics))
	drawer_toggle.z_index = int(responsive_config.overlay_z)+2
	drawer_toggle.show()
	_queue_material_pages()
	_layout_material_speech()
	_notify_material_dimming()
	input_overlay_changed.emit()

func input_overlay_open() -> bool:
	return is_visible_in_tree() and drawer_open and is_instance_valid(paper) and paper.visible

func set_drawer_expanded(value: bool, _animate: bool = false) -> void:
	drawer_open = value
	_layout_short_drawer()
	if value and is_instance_valid(drawer_toggle): drawer_toggle.grab_focus()

func consume_drawer_event(event: InputEventMouseButton) -> bool:
	var metrics: Dictionary = ViewportMetrics.measure(self)
	if not is_visible_in_tree() or not drawer_open or not ViewportMetrics.valid(metrics) or (not metrics.short and Materials.load_config().is_empty()) or not event.pressed: return false
	var point: Vector2 = event.position*metrics.css_per_local_unit
	if ViewportMetrics.css_rect(paper,metrics).has_point(point) or ViewportMetrics.css_rect(drawer_toggle,metrics).has_point(point): return false
	if event.button_index == MOUSE_BUTTON_LEFT: set_drawer_expanded(false,false)
	return true

func _on_client_resized() -> void:
	_layout.call_deferred()

func _layout_legacy_paper(metrics: Dictionary) -> void:
	if responsive_config.is_empty() or not is_instance_valid(drawer_toggle): return
	if not ViewportMetrics.valid(metrics): return
	if not metrics.short:
		drawer_backdrop.hide()
		drawer_toggle.hide()
		paper.scale = Vector2.ONE
		paper.rotation = 0
		paper.z_index = 0
		paper.visible = true
		_place(paper,config.layout.board_rect)
		return
	var available: Rect2 = ResponsiveLayout.drawer_box(metrics,float(responsive_config.case_drawer_width))
	var minimum := Vector2(config.layout.board_rect[2],config.layout.board_rect[3]).max(paper.get_combined_minimum_size())
	ResponsiveLayout.apply(paper,ResponsiveLayout.fit_minimum(minimum,available,metrics,Vector2(0.5,0.5),true))
	paper.z_index = int(responsive_config.overlay_z)+1
	paper.visible = drawer_open
	ResponsiveLayout.apply(drawer_backdrop,ResponsiveLayout.fit_minimum(metrics.visible_css,Rect2(Vector2.ZERO,metrics.visible_css),metrics))
	drawer_backdrop.z_index = int(responsive_config.overlay_z)
	drawer_backdrop.visible = drawer_open
	drawer_toggle.text = str(responsive_config.copy.case_close if drawer_open else responsive_config.copy.case_open)
	var toggle_size := Vector2(responsive_config.toggle_size[0],responsive_config.toggle_size[1]).max(drawer_toggle.get_combined_minimum_size())
	var left: float = available.position.x-toggle_size.x if drawer_open else float(metrics.visible_css.x)-toggle_size.x
	ResponsiveLayout.apply(drawer_toggle,ResponsiveLayout.fit_minimum(toggle_size,Rect2(Vector2(maxf(0,left),float(responsive_config.toggle_top)),toggle_size),metrics))
	drawer_toggle.z_index = int(responsive_config.overlay_z)+2
	drawer_toggle.show()

func _setup_materials() -> void:
	var material: Dictionary = Materials.load_config()
	if material.is_empty(): return
	Materials.apply_panel(paper,"notebook")
	Materials.apply_panel(speech_panel,"letter")
	Materials.apply_panel(reaction_panel,"letter")
	var heading_paper: Control = canvas.get_node("CaseHeadingPaper")
	Materials.apply_panel(heading_paper,"plain")
	var heading_vine: TextureRect = Materials.make_divider()
	heading_vine.name = "CaseHeadingVine"
	heading_paper.add_child(heading_vine)
	heading_vine.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	if not material.is_empty(): heading_vine.offset_top = -float(material.layout.divider_height)
	var old_parent: Node = slot_area.get_parent()
	old_parent.remove_child(slot_area)
	book_slot_scroll = ScrollContainer.new()
	book_slot_scroll.name = "CaseNotebookSlotsScroll"
	book_slot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper.add_child(book_slot_scroll)
	book_slot_scroll.add_child(slot_area)
	slot_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	book_left_vine = Materials.make_divider()
	book_left_vine.name = "CaseNotebookLeftVine"
	paper.add_child(book_left_vine)
	book_right_vine = Materials.make_divider()
	book_right_vine.name = "CaseNotebookRightVine"
	paper.add_child(book_right_vine)
	evidence_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_nameplate = Panel.new()
	speech_nameplate.name = "CaseGuestNameplate"
	speech_nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speech_panel.add_child(speech_nameplate)
	Materials.apply_panel(speech_nameplate,"smalltag","cream")
	speech_name = _label("",int(config.layout.body_font))
	speech_name.name = "CaseGuestNameText"
	speech_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	speech_nameplate.add_child(speech_name)
	reaction_nameplate = Panel.new()
	reaction_nameplate.name = "CaseReactionGuestNameplate"
	reaction_nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reaction_panel.add_child(reaction_nameplate)
	Materials.apply_panel(reaction_nameplate,"smalltag","cream")
	reaction_name = _label("",int(config.layout.body_font))
	reaction_name.name = "CaseGuestNameText"
	reaction_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	reaction_nameplate.add_child(reaction_name)
	paper.resized.connect(_queue_material_pages)
	book_slot_scroll.resized.connect(_queue_material_pages)
	Materials.apply_button(extra_button,"paper_tag","case_extra_question")
	Materials.apply_button(eliminate_button,"paper_tag","case_eliminate")
	Materials.apply_button(end_button,"paper_tag","case_end")
	Materials.apply_button(drawer_toggle,"paper_tag","case_drawer")
	# This transparent input shield remains a blocker; dim only the scene below,
	# not the header/cards/nameplate a second time.
	drawer_backdrop.color = Color.TRANSPARENT
	_refresh_material_name()
	_queue_material_pages()

func _refresh_material_name() -> void:
	if not is_instance_valid(speech_nameplate): return
	var guest: Dictionary = public_view.get("guest",GameState.divination_view().get("guest",{}))
	var padding: float = float(config.layout.padding)
	for pair: Array in [[speech_nameplate,speech_name,speech_panel],[reaction_nameplate,reaction_name,reaction_panel]]:
		var nameplate: Control = pair[0]
		var label: Label = pair[1]
		var parent: Control = pair[2]
		label.text = str(guest.get("name",""))
		label.position = Vector2(padding,padding*0.5)
		label.size = label.get_combined_minimum_size()
		nameplate.size = label.size+Vector2(padding*2.0,padding)
		nameplate.position = Vector2(padding,-nameplate.size.y*0.5)
		for child: Node in parent.get_children():
			if child is MarginContainer: child.add_theme_constant_override("margin_top",int(padding+nameplate.size.y*0.5))
	_layout_material_speech.call_deferred()

func _layout_material_speech() -> void:
	if not is_inside_tree() or not is_instance_valid(speech_panel) or Materials.load_config().is_empty(): return
	var metrics: Dictionary = ViewportMetrics.measure(self)
	if not ViewportMetrics.valid(metrics): return
	var client: Vector2 = metrics.visible_css
	var margin: float = float(responsive_config.safe_margin)
	var minimum := Vector2(config.layout.speech_rect[2],config.layout.speech_rect[3])
	var parent: Node = get_parent()
	if parent != null:
		var conversation: Variant = parent.get("dialogue_panel")
		if conversation is Control: minimum = minimum.max(conversation.get_combined_minimum_size())
	var cards: Rect2 = ViewportMetrics.css_rect(cards_row,metrics)
	var right_space: float = client.x-margin-maxf(margin,cards.end.x+margin)
	var width: float = minf(minimum.x,right_space)
	var header_bottom := margin
	var bottom: float = client.y-margin
	if is_instance_valid(host):
		var header: Variant = host.get("shell_header")
		var dock: Variant = host.get("shell_dock")
		if header is Control: header_bottom = ViewportMetrics.css_rect(header,metrics).end.y
		if dock is Control: bottom = minf(bottom,ViewportMetrics.css_rect(dock,metrics).position.y-margin)
	var toggle_bottom: float = header_bottom
	if is_instance_valid(drawer_toggle) and drawer_toggle.is_visible_in_tree() and not drawer_open:
		toggle_bottom = maxf(toggle_bottom,ViewportMetrics.css_rect(drawer_toggle,metrics).end.y)
	var nameplate_half: float = speech_nameplate.size.y*0.5 if is_instance_valid(speech_nameplate) else 0.0
	var top: float = maxf(header_bottom,toggle_bottom)+margin+nameplate_half
	var height: float = minf(minf(minimum.y,client.y*float(responsive_config.dialogue_max_ratio)),bottom-top)
	if width <= 0 or height <= 0: return
	var available := Rect2(Vector2(client.x-margin-width,top),Vector2(width,height))
	var layout: Dictionary = ResponsiveLayout.fit_minimum(minimum,available,metrics,Vector2(0.5,0),true)
	ResponsiveLayout.apply(speech_panel,layout)
	ResponsiveLayout.apply(reaction_panel,layout)
	var effective: Vector2 = speech_panel.get_global_transform_with_canvas().get_scale()*metrics.css_per_local_unit
	speech_panel.set_meta("material_effective_css_scale",effective)
	speech_panel.set_meta("material_effective_font_sizes",{"body":float(config.layout.body_font)*effective.y,"name":float(config.layout.body_font)*effective.y})

func _queue_material_pages() -> void:
	_layout_material_pages.call_deferred()

func _layout_material_pages() -> void:
	if not is_instance_valid(paper) or not is_instance_valid(book_slot_scroll): return
	var material: Dictionary = Materials.load_config()
	var guides: Array = Materials.content_rects(paper.size,"notebook")
	if material.is_empty() or guides.size() != 2: return
	var left: Rect2 = guides[0]
	var right: Rect2 = guides[1]
	var divider_height: float = float(material.layout.divider_height)
	var gap: float = float(material.layout.divider_gap)
	var title_height: float = float(config.layout.board_title_rect[3])
	book_title.position = left.position
	book_title.size = Vector2(left.size.x,title_height)
	book_left_vine.position = left.position+Vector2(0,title_height)
	book_left_vine.size = Vector2(left.size.x,divider_height)
	book_slot_scroll.position = left.position+Vector2(0,title_height+divider_height+gap)
	book_slot_scroll.size = Vector2(left.size.x,maxf(1,left.size.y-title_height-divider_height-gap))
	var evidence_heading_height: float = float(config.layout.evidence_title_rect[3])*2.0
	evidence_title.position = right.position
	evidence_title.size = Vector2(right.size.x,evidence_heading_height)
	book_right_vine.position = right.position+Vector2(0,evidence_heading_height)
	book_right_vine.size = Vector2(right.size.x,divider_height)
	evidence_scroll.position = right.position+Vector2(0,evidence_heading_height+divider_height+gap)
	evidence_scroll.size = Vector2(right.size.x,maxf(1,right.size.y-evidence_heading_height-divider_height-gap))
	evidence_box.columns = maxi(1,int(floor(float(config.layout.evidence_columns)/float(guides.size()))))
	for slot: Control in slot_area.get_children():
		var answers: GridContainer = slot.find_child("CaseAnswerRow",true,false)
		if answers == null or answers.get_child_count() == 0: continue
		var width := 1.0
		for answer: Control in answers.get_children(): width = maxf(width,answer.get_combined_minimum_size().x)
		var answer_gap: float = float(config.layout.question_gap)
		answers.columns = clampi(int(floor((left.size.x+answer_gap)/(width+answer_gap))),1,int(config.layout.question_columns))
	var metrics: Dictionary = ViewportMetrics.measure(self)
	if ViewportMetrics.valid(metrics):
		var effective: Vector2 = paper.get_global_transform_with_canvas().get_scale()*metrics.css_per_local_unit
		paper.set_meta("material_effective_css_scale",effective)
		paper.set_meta("material_effective_font_sizes",{"body":float(config.layout.body_font)*effective.y,"answer":float(config.layout.answer_font)*effective.y,"small":float(config.layout.small_font)*effective.y})
		paper.set_meta("material_content_rects",guides)

func _make_empty_drop_outline(slot: Control) -> void:
	var material: Dictionary = Materials.load_config()
	if material.is_empty(): return
	var outline := Control.new()
	outline.name = "CaseDropOutline"
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(outline)
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outline.draw.connect(func():
		var line: Dictionary = material.empty_slot
		var color := Color(line.color)
		var width: float = float(line.width)
		var dash: float = float(line.dash)
		var gap: float = float(line.gap)
		var size: Vector2 = outline.size-Vector2.ONE*width
		var origin := Vector2.ONE*width*0.5
		var corners: Array[Vector2] = [origin,origin+Vector2(size.x,0),origin+size,origin+Vector2(0,size.y)]
		for index: int in range(corners.size()):
			var start: Vector2 = corners[index]
			var finish: Vector2 = corners[(index+1)%corners.size()]
			var direction: Vector2 = (finish-start).normalized()
			var length: float = start.distance_to(finish)
			var at := 0.0
			while at < length:
				outline.draw_line(start+direction*at,start+direction*minf(at+dash,length),color,width,true)
				at += dash+gap)
	outline.resized.connect(outline.queue_redraw)

func _play_material_paper_sound(button: BaseButton) -> void:
	var audio: Node = get_tree().root.find_child("ShopAudio",true,false)
	if audio != null: audio.play_ui(str(button.get_meta("material_audio_key","click")))

func _notify_material_dimming() -> void:
	var parent: Node = get_parent()
	if parent != null and parent.has_method("_update_material_scene_dimming"): parent.call("_update_material_scene_dimming")
	if parent != null and parent.has_method("_queue_layout"): parent.call("_queue_layout")

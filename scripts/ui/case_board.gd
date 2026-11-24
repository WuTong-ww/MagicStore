extends Control
## This screen consumes only the committed public projection. It never reads
## the case definition, card order, answers, or the private world state.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Config = preload("res://scripts/ui/case_board_config.gd")
const EvidenceToken = preload("res://scripts/ui/case_evidence_token.gd")
const DeductionSlot = preload("res://scripts/ui/case_deduction_slot.gd")
const StoryUI = preload("res://scripts/ui/story_ui_config.gd")
signal story_choice_saved
var host
var config: Dictionary = {}
var story_config: Dictionary = {}
var canvas: Control
var paper: Panel
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
var public_view: Dictionary = {}
var _pending := false
var _selected_evidence := ""
var _extra_open := false
var _elimination_open := false
var _question_signature := ""
var _advice_signature := ""
var _evidence_signature := ""
var _slot_signatures: Dictionary = {}

func _ready() -> void:
	config = Config.load_config()
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
	paper = _panel("CaseBoardPaper",config.layout.board_rect)
	var title := _label(config.copy.board_title,int(config.layout.title_font))
	paper.add_child(title)
	_place(title,config.layout.board_title_rect)
	var slot_area := VBoxContainer.new()
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
	reaction_title = _label("",int(config.layout.title_font))
	reaction_box.add_child(reaction_title)
	reaction_label = UI.rich()
	reaction_label.name = "CaseReactionText"
	reaction_label.add_theme_font_size_override("normal_font_size",int(config.layout.body_font))
	reaction_box.add_child(reaction_label)
	end_button = _button(config.copy.end_visit,func(): await _submit("end_visit",{}))
	end_button.name = "CaseEndVisit"
	question_area.add_child(end_button)
	end_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	end_button.offset_bottom = float(config.layout.question_height)
	resized.connect(_layout)
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
	var button := _button("",func(): await _submit("case_flip_card",{"card_index":index}))
	button.name = "CaseCard_"+str(index)
	button.custom_minimum_size = Vector2(config.layout.card_width,config.layout.card_height)
	button.tooltip_text = config.copy.card_tooltip
	cards_row.add_child(button)
	var art := TextureRect.new()
	art.name = "CardArt"
	art.texture = load(config.assets.card_back)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	art.offset_bottom = float(config.layout.card_art_height)
	var ornament := _label(config.copy.ornament,int(config.layout.ornament_font))
	ornament.name = "CardOrnament"
	ornament.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ornament.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	card_nodes.append(button)

func _layout() -> void:
	if canvas == null or config.is_empty():
		return
	var factor := minf(size.x/float(config.layout.base_width),size.y/float(config.layout.base_height))
	canvas.scale = Vector2.ONE*factor
	canvas.position = (size-canvas.size*factor)/2.0

func refresh() -> void:
	if config.is_empty() or _pending:
		return
	public_view = GameState.case_board_view()
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
	heading.text = str(public_view.get("title",config.copy.heading))
	instruction.text = config.copy.closed_instruction if closed else (config.copy.question_round.format({"round":int(public_view.get("round",0))+1}) if phase == "questions" else (config.copy.cards_instruction if phase == "cards" else config.copy.deduction_instruction))
	if _extra_open:
		instruction.text = config.copy.extra_instruction
	elif closed:
		instruction.text += " "+str(config.copy.star).repeat(int(public_view.get("stars",1)))
	if not prelude.is_empty() and not story_config.is_empty():
		instruction.text = str(story_config.copy.prelude_instruction)
	var reply := str(public_view.get("last_answer",""))
	speech_label.text = reply if not reply.is_empty() else str(public_view.get("question",config.copy.empty_speech))
	var story_lines: Array[String] = StoryUI.public_lines(public_view.get("story_lines",[]))
	var separator := str(story_config.get("copy",{}).get("separator","\n\n"))
	if not prelude.is_empty():
		var text := str(prelude.get("text",""))
		if not text.is_empty() and text not in story_lines:
			story_lines.append(text)
	if not story_lines.is_empty() and (reply.is_empty() or not prelude.is_empty()):
		speech_label.text = separator.join(story_lines)
	cards_row.visible = not _extra_open
	_refresh_cards()
	_refresh_slots()
	_refresh_evidence()
	_refresh_questions()
	_refresh_advice()
	extra_button.visible = bool(public_view.get("can_extra_question",false)) and not closed
	eliminate_button.visible = bool(public_view.get("can_eliminate",false)) and not closed
	utility_buttons.visible = not closed and phase != "questions" and prelude.is_empty()
	end_button.visible = closed
	reaction_panel.visible = closed
	speech_panel.visible = not closed
	if closed:
		reaction_title.text = config.copy.close_title.format({"stars":str(config.copy.star).repeat(int(public_view.get("stars",1)))})
		reaction_label.text = str(public_view.get("reaction",config.copy.reaction_empty))
		if not story_lines.is_empty():
			reaction_label.text += separator+separator.join(story_lines)
	_set_busy(bool(host.busy) if is_instance_valid(host) else false)

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
		button.set_meta("available",bool(row.get("enabled",false)) and not public_view.get("closed",false) and _blocking_prelude().is_empty())
		var art: TextureRect = button.get_node("CardArt")
		var path: String = str(row.get("image","")) if revealed else str(config.assets.card_back)
		if revealed and path.is_empty():
			path = str(config.assets.faces.get(str(row.get("deck_id","")),""))
		art.texture = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
		button.get_node("CardOrnament").visible = revealed and art.texture == null
		button.get_node("CardName").text = str(row.get("name","")) if revealed else ""
		button.tooltip_text = str(row.get("name",""))+"\n"+str(row.get("text","")) if revealed else config.copy.card_tooltip
		button.add_theme_stylebox_override("normal",_style("selected" if revealed else "paper_soft"))

func _refresh_questions() -> void:
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

func _refresh_advice() -> void:
	var rows: Array = public_view.get("advice",[])
	advice_buttons.visible = public_view.get("phase") == "deduction" and not _extra_open and not public_view.get("closed",false) and _blocking_prelude().is_empty()
	var signature := JSON.stringify(rows)
	if signature == _advice_signature:
		return
	_advice_signature = signature
	_clear(advice_buttons)
	for row: Dictionary in rows:
		var button := _button(str(row.text),func(): await _submit("case_close",{"advice_id":row.id}))
		button.name = "CaseAdvice_"+str(advice_buttons.get_child_count())
		button.set_meta("available",bool(row.get("enabled",false)))
		advice_buttons.add_child(button)

func _refresh_slots() -> void:
	var rows: Array = public_view.get("slots",[])
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var slot: Control = slot_nodes.get(str(row.id),slot_nodes.get(str(index)))
		if slot == null:
			continue
		slot.slot_id = row.id
		slot_nodes[row.id] = slot
		var signature := JSON.stringify(row)+str(public_view.get("closed",false))+str(_blocking_prelude().is_empty())
		if _slot_signatures.get(row.id) == signature:
			continue
		_slot_signatures[row.id] = signature
		_clear(slot)
		slot.add_theme_stylebox_override("panel",_style("paper" if row.get("unlocked",false) else "locked"))
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_theme_constant_override("separation",int(config.layout.slot_gap))
		slot.add_child(column)
		var header := HBoxContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_child(header)
		var title := _label(str(row.title),int(config.layout.body_font))
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var sealed := not str(row.get("selected","")).is_empty()
		if sealed:
			var seal := PanelContainer.new()
			seal.name = "CaseWaxSeal"
			seal.custom_minimum_size = Vector2.ONE*float(config.layout.seal_size)
			seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var wax := _style("seal")
			wax.set_corner_radius_all(int(config.layout.seal_size)/2)
			wax.content_margin_top = 0
			wax.content_margin_bottom = 0
			wax.content_margin_left = 0
			wax.content_margin_right = 0
			seal.add_theme_stylebox_override("panel",wax)
			seal.tooltip_text = config.copy.sealed
			header.add_child(seal)
			var mark := _label(config.copy.seal_mark,int(config.layout.small_font))
			mark.add_theme_color_override("font_color",Color(config.colors.paper))
			mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			seal.add_child(mark)
		else:
			var status := _label(config.copy.attached.format({"count":row.get("attached_ids",[]).size()}),int(config.layout.small_font))
			status.autowrap_mode = TextServer.AUTOWRAP_OFF
			status.add_theme_color_override("font_color",Color(config.colors.muted))
			header.add_child(status)
		if not row.get("unlocked",false):
			var locked := _label(config.copy.locked,int(config.layout.small_font))
			locked.size_flags_vertical = Control.SIZE_EXPAND_FILL
			column.add_child(locked)
			continue
		var answers := _button_row("CaseAnswerRow")
		answers.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(answers)
		for answer: Dictionary in row.get("candidates",[]):
			var button := _button(str(answer.text),func(): await _activate_candidate(str(row.id),str(answer.id)))
			button.name = "CaseAnswer_"+str(answers.get_child_count())
			button.add_theme_font_size_override("font_size",int(config.layout.answer_font))
			button.mouse_filter = Control.MOUSE_FILTER_PASS
			button.set_meta("available",bool(answer.get("enabled",true)) and not public_view.get("closed",false) and _blocking_prelude().is_empty())
			if str(row.get("selected","")) == str(answer.id):
				button.add_theme_stylebox_override("normal",_style("selected"))
				button.add_theme_stylebox_override("disabled",_style("selected"))
			answers.add_child(button)

func _refresh_evidence() -> void:
	var rows: Array = public_view.get("evidence",[])
	var signature := JSON.stringify([rows,_selected_evidence,public_view.get("closed",false)])
	if signature == _evidence_signature:
		return
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
		var kind := str(row.get("kind","testimony"))
		var source: String = str(row.get("source",config.copy.get(kind,config.copy.testimony)))
		token.text = source+" · "+str(row.text)
		token.tooltip_text = token.text
		token.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		token.add_theme_font_size_override("font_size",int(config.layout.small_font))
		token.custom_minimum_size.y = float(config.layout.evidence_height)
		token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		token.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		token.set_meta("available",public_view.get("phase") == "deduction" and not public_view.get("closed",false))
		var material_color := "tool" if kind == "tool" else ("testimony" if kind == "testimony" else "paper")
		token.add_theme_stylebox_override("normal",_style("selected" if row.id == _selected_evidence else material_color))
		token.add_theme_stylebox_override("disabled",_style(material_color))
		token.pressed.connect(func():
			_selected_evidence = str(row.id)
			_refresh_evidence())
		evidence_box.add_child(token)

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
	var target: Control = card_nodes[int(values.card_index)] if action == "case_flip_card" else slot_nodes.get(str(values.get("slot_id","")),question_area)
	var source_position := Vector2.ZERO
	var flying_text := ""
	var before_evidence: Array = public_view.get("evidence",[]).map(func(row: Dictionary) -> String: return str(row.id))
	if action == "case_attach_evidence":
		for token: Node in evidence_box.get_children():
			if token.get("evidence_id") == values.get("evidence_id"):
				source_position = canvas.get_global_transform().affine_inverse()*token.get_global_rect().get_center()
				flying_text = token.text
	var result: Dictionary = await host.run_action(action,values)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_pending = false
	if result.get("success",false):
		if action == "case_extra_question":
			_extra_open = false
		if action == "case_attach_evidence":
			_selected_evidence = ""
		refresh()
		if action == "story_choice":
			story_choice_saved.emit()
		if action == "case_attach_evidence":
			_fly_material(source_position,target,flying_text)
		elif action in ["case_question","case_extra_question"]:
			var reply_origin: Vector2 = canvas.get_global_transform().affine_inverse()*speech_panel.get_global_rect().get_center()
			for token: Node in evidence_box.get_children():
				if token.get("evidence_id") is String and token.evidence_id not in before_evidence:
					_fly_material(reply_origin,token,token.text)
		_feedback("page" if action in ["case_flip_card","case_question","case_extra_question"] else "confirm",target,true,action)
	else:
		refresh()
		_feedback("cancel",target,false)

func _fly_material(origin: Vector2, target: Control, text: String) -> void:
	var reduced := get_node_or_null("/root/WindField")
	if reduced != null and reduced.reduced_motion:
		return
	var paper_token := PanelContainer.new()
	paper_token.name = "CaseSavedMaterialFlight"
	paper_token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper_token.add_theme_stylebox_override("panel",_style("selected"))
	paper_token.size = Vector2(config.layout.fly_width,config.layout.fly_height)
	canvas.add_child(paper_token)
	paper_token.position = origin-paper_token.size/2.0
	var label := _label(text,int(config.layout.small_font))
	label.max_lines_visible = 2
	label.clip_text = true
	paper_token.add_child(label)
	var destination: Vector2 = canvas.get_global_transform().affine_inverse()*target.get_global_rect().get_center()-paper_token.size/2.0
	var tween := create_tween()
	tween.tween_property(paper_token,"position",destination,float(config.layout.feedback_seconds)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(paper_token.queue_free)

func _feedback(sound: String, target: Control, success: bool, action: String = "") -> void:
	var audio := get_tree().root.find_child("ShopAudio",true,false)
	if audio != null:
		audio.play_ui(sound)
	if not is_instance_valid(target):
		return
	var reduced := get_node_or_null("/root/WindField")
	if reduced != null and reduced.reduced_motion:
		return
	if success and action not in ["case_flip_card","case_attach_evidence","case_choose_answer"]:
		return
	var duration := float(config.layout.feedback_seconds)
	var tween := create_tween()
	if success and action == "case_flip_card":
		target.pivot_offset = target.size/2.0
		target.scale.x = 0.0
		tween.tween_property(target,"scale:x",1.0,float(config.layout.flip_seconds)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif success and action == "case_attach_evidence":
		target.modulate = Color(config.colors.gold)
		tween.tween_property(target,"modulate",Color.WHITE,duration)
	elif success and action == "case_choose_answer":
		var seal: Control = target.find_child("CaseWaxSeal",true,false)
		if seal != null:
			seal.pivot_offset = seal.size/2.0
			seal.scale = Vector2.ONE*float(config.layout.seal_scale)
			tween.tween_property(seal,"scale",Vector2.ONE,duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif not success:
		var origin := target.position
		tween.tween_property(target,"position:x",origin.x+float(config.layout.reject_offset),duration/3.0)
		tween.tween_property(target,"position:x",origin.x-float(config.layout.reject_offset),duration/3.0)
		tween.tween_property(target,"position",origin,duration/3.0)

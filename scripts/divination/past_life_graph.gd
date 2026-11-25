extends VBoxContainer
## Renders only the already-stripped public past-line projection.

const UI = preload("res://scripts/ui/ui_kit.gd")
const CardChoice = preload("res://scripts/ui/card_choice.gd")

signal interpret_requested(instance_id: String, group_id: String, option_id: String, text: String)
signal verify_requested(interpretation_id: String)

var model: Dictionary = {}
var actionable: bool = false
var copy: Dictionary = {}
var layout: Dictionary = {}
var choice: CardChoice
var input: LineEdit
var submit: Button

func render(public_model: Dictionary, can_act: bool = false) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	choice = null
	input = null
	submit = null
	model = public_model.duplicate(true)
	actionable = can_act
	var ui: Dictionary = model.get("ui",{})
	copy = ui.get("copy",{})
	layout = ui.get("layout",{})
	if copy.is_empty() or layout.is_empty():
		return
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",int(layout.row_gap))
	if not model.get("available",false):
		add_child(_label(copy.empty))
		return
	add_child(_label(str(model.get("title",copy.title)),true))
	for row: Dictionary in model.get("rows",[]):
		_era(row)
	if not model.get("fragments",[]).is_empty():
		add_child(_label(copy.observed,true))
		for fragment: Dictionary in model.fragments:
			var record := VBoxContainer.new()
			record.add_theme_constant_override("separation",int(layout.node_gap))
			record.add_child(_label(fragment.title,true))
			record.add_child(_label(fragment.text))
			add_child(record)
	if not model.get("interpretations",[]).is_empty():
		add_child(_label(copy.interpretation_heading,true))
		for interpretation: Dictionary in model.interpretations:
			_interpretation(interpretation)
	if not model.get("links",[]).is_empty():
		for link: Dictionary in model.links:
			add_child(_label(link.label))
	if not model.get("options",[]).is_empty():
		_entry()

func _label(text: String, heading: bool = false) -> Label:
	var label := UI.label(text,int(layout.title_size if heading else layout.font_size),UI.GOLD if heading else UI.Palette.INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _era(row: Dictionary) -> void:
	var panel := UI.panel("plain")
	panel.name = "PastEraRow%d" % int(row.ordinal)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(panel)
	var margin := UI.margin(int(layout.panel_margin))
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",int(layout.node_gap))
	margin.add_child(content)
	content.add_child(_label(row.title,true))
	if row.get("known",false):
		var image_path: String = row.get("image_path","")
		if not image_path.is_empty() and ResourceLoader.exists(image_path):
			var illustration := UI.image(image_path)
			illustration.custom_minimum_size.y = float(layout.image_height)
			illustration.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			content.add_child(illustration)
	else:
		# No TextureRect, private path or unknown identity metadata is retained.
		panel.custom_minimum_size.y = float(layout.unknown_min_height)
		panel.self_modulate.a = float(layout.fog_opacity)
	var identities := HFlowContainer.new()
	identities.add_theme_constant_override("h_separation",int(layout.node_gap))
	identities.add_theme_constant_override("v_separation",int(layout.node_gap))
	content.add_child(identities)
	for identity: Dictionary in row.get("nodes",[]):
		var text: String = identity.label
		if identity.has("present_name"):
			text += "\n"+str(identity.present_name)
		var label := _label(text)
		label.custom_minimum_size.x = float(layout.node_min_width)
		identities.add_child(label)

func _interpretation(record: Dictionary) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation",int(layout.node_gap))
	section.add_child(_label(str(copy.get(record.status,copy.unverified))))
	section.add_child(_label(record.player_text))
	add_child(section)
	if record.get("can_verify",false):
		var id: String = record.interpretation_id
		var button := UI.button(copy.evidence_heading,func() -> void:
			if actionable:
				verify_requested.emit(id)
		)
		button.name = "PastLineVerify_"+id
		button.disabled = not actionable
		button.add_theme_font_size_override("font_size",int(layout.font_size))
		section.add_child(button)

func _entry() -> void:
	add_child(_label(copy.options_heading,true))
	choice = CardChoice.new()
	choice.name = "PastLineInterpretationChoice"
	choice.fit_to_longest_item = false
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.add_theme_font_size_override("font_size",int(layout.font_size))
	for option: Dictionary in model.options:
		choice.add_item(option.label)
	choice.disabled = not actionable
	choice.select(0)
	add_child(choice)
	input = LineEdit.new()
	input.name = "PastLineInterpretationText"
	input.placeholder_text = copy.invalid_interpretation
	input.editable = actionable
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_size_override("font_size",int(layout.font_size))
	add_child(input)
	submit = UI.button(copy.options_heading,_submit)
	submit.name = "PastLineInterpretationSubmit"
	submit.add_theme_font_size_override("font_size",int(layout.font_size))
	add_child(submit)
	choice.item_selected.connect(func(_index: int) -> void: _sync_submit())
	input.text_changed.connect(func(_text: String) -> void: _sync_submit())
	_sync_submit()

func _sync_submit() -> void:
	if is_instance_valid(submit):
		submit.disabled = not actionable or not is_instance_valid(choice) or choice.selected < 0 or input.text.strip_edges().is_empty()

func _submit() -> void:
	if not actionable or not is_instance_valid(submit) or submit.disabled or choice.selected < 0 or choice.selected >= model.options.size():
		return
	var option: Dictionary = model.options[choice.selected]
	interpret_requested.emit(model.instance_id,option.group_id,option.option_id,input.text)

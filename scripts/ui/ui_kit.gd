class_name MidnightUI
extends RefCounted

const Palette = preload("res://scripts/ui/palette.gd")
const Fonts = preload("res://scripts/ui/font_policy.gd")
const Style = preload("res://scripts/ui/style_config.gd")
const Materials = preload("res://scripts/ui/panel_materials.gd")
static var GOLD := Palette.PAPER_ACCENT
static var MUTED := Palette.MUTED

static func label(text: String, size: int = 18, color: Color = Color.TRANSPARENT) -> Label:
	var node := Label.new()
	node.text = text
	if size >= 24:
		node.theme_type_variation = "Title"
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", Palette.INK if color == Color.TRANSPARENT else color)
	if Fonts.composite() != null:
		node.add_theme_font_override("font",Fonts.composite())
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

static func button(text: String, callback: Callable, role: String = "secondary") -> Button:
	var node := Button.new()
	node.text = text
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.focus_mode = Control.FOCUS_ALL
	node.clip_text = false
	node.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	node.theme_type_variation = "WaxButton" if role == "primary" else "PaperButton"
	var style := Style.load_config()
	if not style.is_empty(): node.custom_minimum_size.y = style.metrics.minimum_button_height
	if Fonts.composite() != null: node.add_theme_font_override("font",Fonts.composite())
	Materials.apply_button(node,"wax" if role == "primary" else "paper_tag")
	node.pressed.connect(callback)
	node.pressed.connect(func():
		if node.is_inside_tree():
			var audio := node.get_tree().root.find_child("ShopAudio",true,false)
			if audio != null:
				audio.play_ui(str(node.get_meta("material_audio_key","click"))))
	return node

static func panel(role: String = "paper", variant: String = "") -> PanelContainer:
	var node := PanelContainer.new()
	if ResourceLoader.exists("res://themes/paper.tres"):
		node.theme = load("res://themes/paper.tres")
	Materials.apply_panel(node,role,variant)
	return node

static func paper_window(window: Window, role: String = "dialogue") -> void:
	# This Window-local theme never changes the shared application theme.
	window.transparent_bg = true
	window.transparent = true
	if not window.has_meta("responsive_design_size"):
		window.set_meta("responsive_design_size",window.size)
	var background := window.get_node_or_null("PaperWindowBackground") as Panel
	if background == null:
		background = Panel.new()
		background.name = "PaperWindowBackground"
		background.theme = load("res://themes/paper.tres")
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		window.add_child(background)
		window.move_child(background,0)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.set_meta("material_fixed_layout",true)
	background.set_meta("material_window_content",true)
	background.set_as_top_level(true)
	Materials.apply_panel(background,role)
	var style := Style.load_config()
	if style.is_empty() or window.get_meta("material_window_theme",false): return
	var base: Theme = window.theme if window.theme != null else load("res://themes/paper.tres") as Theme
	var local: Theme = base.duplicate() as Theme
	for slot: String in ["background","embedded_border","embedded_unfocused_border"]:
		local.set_stylebox(slot,"Window",StyleBoxEmpty.new())
	for type: String in ["Panel","PanelContainer","ItemList","Tree","TabContainer","AcceptDialog","ConfirmationDialog"]:
		local.set_stylebox("panel",type,StyleBoxEmpty.new())
	for type: String in ["LineEdit","TextEdit"]:
		var previous: StyleBox = window.get_theme_stylebox("normal",type)
		var empty := StyleBoxEmpty.new()
		for side: int in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: empty.set_content_margin(side,previous.get_margin(side))
		local.set_stylebox("normal",type,empty)
		local.set_stylebox("read_only",type,empty)
		local.set_stylebox("focus",type,_paper_focus(style))
	for type: String in ["ItemList","Tree"]:
		local.set_stylebox("focus",type,_paper_focus(style))
		var selected := StyleBoxFlat.new()
		selected.bg_color = Color(style.colors.paper_hover)
		local.set_stylebox("selected",type,selected)
		local.set_stylebox("selected_focus",type,selected)
	for slot: String in ["tab_unselected","tab_hovered","tab_disabled"]:
		local.set_stylebox(slot,"TabBar",StyleBoxEmpty.new())
	local.set_stylebox("tab_selected","TabBar",_paper_focus(style))
	local.set_stylebox("tab_focus","TabBar",_paper_focus(style))
	local.set_color("title_color","Window",Color(style.colors.ink))
	var font_config := Fonts.load_config()
	if not font_config.is_empty() and ResourceLoader.exists(font_config.regular):
		local.set_font("title_font","Window",load(str(font_config.regular)) as Font)
	window.theme = local
	window.set_meta("material_window_theme",true)

static func _paper_focus(style: Dictionary) -> StyleBoxFlat:
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color(style.colors.night)
	focus.set_border_width(SIDE_BOTTOM,int(style.metrics.border_width))
	return focus

static func paper_heading(text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	var style := Style.load_config()
	if style.is_empty(): return box
	box.add_theme_constant_override("separation",int(style.metrics.gap))
	var heading := label(text,int(style.metrics.dialogue_size),Color(style.colors.ink))
	var font_config := Fonts.load_config()
	if not font_config.is_empty() and ResourceLoader.exists(font_config.regular):
		heading.add_theme_font_override("font",load(str(font_config.regular)) as Font)
	box.add_child(heading)
	box.add_child(Materials.make_divider())
	return box

static func image(path: String) -> TextureRect:
	var node := TextureRect.new()
	node.texture = load(path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func rich() -> RichTextLabel:
	var node := RichTextLabel.new()
	if Fonts.composite() != null:
		for slot: String in ["normal_font","bold_font","italics_font","bold_italics_font","mono_font"]:
			node.add_theme_font_override(slot,Fonts.composite())
	node.bbcode_enabled = false
	node.selection_enabled = true
	node.scroll_following = true
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return node

static func margin(amount: int = 18) -> MarginContainer:
	var node := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		node.add_theme_constant_override("margin_" + side, amount)
	return node

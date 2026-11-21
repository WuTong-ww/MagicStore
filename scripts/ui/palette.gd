extends Theme
## Both themes are built from this palette. No gameplay values live here.
const PAPER := Color("f3e9d6")
const MILK_TEA := Color("e2d2b4")
const INK := Color("3b2a1e")
const MUTED := Color("7a6450")
const NIGHT_TEAL := Color("1f3a3d")
const GOLD := Color("c99a4b")
const PAPER_ACCENT := Color("7a5b2d")
const MOSS := Color("6e7f4f")
const PLUM := Color("9c86b8")
const ROSE := Color("b5654d")

@export var chrome := false:
	set(value):
		chrome = value
		_build()

func _init() -> void:
	_build()

func _box(background: Color, border: Color, margin: float = 12.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

func _build() -> void:
	var noto := FontVariation.new()
	noto.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	noto.variation_opentype = {2003265652: 400.0}
	var wenkai: Font = load("res://assets/fonts/LXGWWenKai-Regular.ttf")
	default_font = noto
	default_font_size = 18
	var text := PAPER if chrome else INK
	var secondary := MILK_TEA if chrome else MUTED
	var base := Color(NIGHT_TEAL, 0.8) if chrome else PAPER
	var panel := _box(base, GOLD if chrome else MILK_TEA, 14)
	var normal := _box(NIGHT_TEAL if chrome else PAPER, GOLD)
	var hover := _box(Color("315154") if chrome else Color("ebe0c9"), GOLD)
	var pressed := _box(Color("163034") if chrome else MILK_TEA, GOLD)
	var disabled := _box(Color("294346") if chrome else Color("e9dfcb"), MILK_TEA if not chrome else MUTED)
	var field := _box(Color("284448") if chrome else Color("fbf5e9"), MILK_TEA)
	set_type_variation("Title", "Label")
	set_type_variation("Dialogue", "RichTextLabel")
	set_font("font", "Title", wenkai)
	set_font("normal_font", "Dialogue", wenkai)
	set_font_size("normal_font_size", "Dialogue", 20)
	for type: String in ["Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "ItemList", "PopupMenu", "TabBar"]:
		set_font("font", type, noto)
		set_font_size("font_size", type, 18)
	for type: String in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "ItemList", "PopupMenu", "TabBar", "Tree"]:
		set_color("font_color", type, text)
		set_color("font_hover_color", type, text)
		set_color("font_pressed_color", type, text)
		set_color("font_focus_color", type, text)
		set_color("font_disabled_color", type, secondary)
	set_color("default_color", "RichTextLabel", text)
	set_color("font_selected_color", "ItemList", text)
	set_color("font_placeholder_color", "LineEdit", secondary)
	set_color("font_placeholder_color", "TextEdit", secondary)
	for type: String in ["Button", "OptionButton"]:
		set_stylebox("normal", type, normal)
		set_stylebox("hover", type, hover)
		set_stylebox("pressed", type, pressed)
		set_stylebox("disabled", type, disabled)
		set_stylebox("focus", type, hover)
	for type: String in ["TextEdit", "LineEdit"]:
		set_stylebox("normal", type, field)
		set_stylebox("focus", type, field)
		set_stylebox("read_only", type, field)
	for type: String in ["PanelContainer", "Panel", "PopupMenu", "PopupPanel", "AcceptDialog", "ConfirmationDialog", "ItemList", "Tree"]:
		set_stylebox("panel", type, panel)
	set_stylebox("background", "Window", panel)
	set_stylebox("embedded_border", "Window", panel)
	set_stylebox("embedded_unfocused_border", "Window", panel)
	set_color("title_color", "Window", text)
	set_color("title_outline_modulate", "Window", Color.TRANSPARENT)
	set_stylebox("tab_selected", "TabBar", pressed)
	set_stylebox("tab_unselected", "TabBar", normal)
	set_color("font_selected_color", "TabBar", text)
	set_color("font_unselected_color", "TabBar", secondary)
	set_stylebox("background", "ProgressBar", _box(MILK_TEA, MILK_TEA, 0))
	set_stylebox("fill", "ProgressBar", _box(MOSS, MOSS, 0))
	set_color("font_color", "ProgressBar", text)
	set_constant("separation", "VBoxContainer", 8)
	set_constant("separation", "HBoxContainer", 8)

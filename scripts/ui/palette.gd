extends Theme
## Theme colors and dimensions are presentation data, shared by all themes.
const Fonts = preload("res://scripts/ui/font_policy.gd")
const Style = preload("res://scripts/ui/style_config.gd")
const ButtonMaterial = preload("res://scripts/ui/button_material_style.gd")
static var _style: Dictionary = Style.load_config()
static var PAPER := _color("paper")
static var MILK_TEA := _color("paper_soft")
static var INK := _color("ink")
static var MUTED := _color("muted")
static var NIGHT_TEAL := _color("night")
static var GOLD := _color("border")
static var PAPER_ACCENT := _color("wood")
static var MOSS := _color("sage")
static var PLUM := _color("sage")
static var ROSE := _color("wax")

static func _color(key: String) -> Color:
	return Color(_style.colors[key]) if not _style.is_empty() else Color.TRANSPARENT

@export var chrome := false:
	set(value):
		chrome = value
		_build()

func _init() -> void:
	_build()

func _box(background: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(int(_style.metrics.border_width))
	box.set_corner_radius_all(int(_style.metrics.corner_radius))
	box.content_margin_left = _style.metrics.horizontal_padding
	box.content_margin_right = _style.metrics.horizontal_padding
	box.content_margin_top = _style.metrics.vertical_padding
	box.content_margin_bottom = _style.metrics.vertical_padding
	return box

func _material_box(role: String, state: String) -> StyleBox:
	var box := ButtonMaterial.new()
	box.configure(role,state,_style)
	return box

func _build() -> void:
	if _style.is_empty():
		push_error("Invalid POLISH style configuration")
		return
	var face := Fonts.composite()
	if face == null:
		push_error("Invalid embedded POLISH font configuration")
		return
	default_font = face
	default_font_size = int(_style.metrics.font_size)
	var text := PAPER if chrome else INK
	var secondary := MILK_TEA if chrome else MUTED
	var base := NIGHT_TEAL if chrome else PAPER
	var panel := _box(base, GOLD if chrome else MILK_TEA)
	var normal := _box(NIGHT_TEAL if chrome else PAPER, GOLD)
	var hover := _box(_color("night_hover") if chrome else _color("paper_hover"), GOLD)
	var pressed := _box(_color("night_pressed") if chrome else MILK_TEA, GOLD)
	var disabled := _box(NIGHT_TEAL if chrome else MILK_TEA, MILK_TEA if not chrome else MUTED)
	var field := _box(NIGHT_TEAL if chrome else _color("field"), MILK_TEA)
	set_type_variation("Title", "Label")
	set_type_variation("Dialogue", "RichTextLabel")
	set_type_variation("WaxButton", "Button")
	set_type_variation("PaperButton", "Button")
	for type: String in ["Label", "Title", "Button", "WaxButton", "PaperButton", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "ItemList", "PopupMenu", "TabBar", "Tree", "ProgressBar"]:
		set_font("font", type, face)
		set_font_size("font_size", type, int(_style.metrics.font_size))
	set_font("title_font", "Window", face)
	for type: String in ["RichTextLabel", "Dialogue"]:
		for slot: String in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
			set_font(slot,type,face)
	set_font_size("normal_font_size", "Dialogue", int(_style.metrics.dialogue_size))
	for type: String in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "ItemList", "PopupMenu", "TabBar", "Tree"]:
		set_color("font_color", type, text)
		set_color("font_hover_color", type, text)
		set_color("font_pressed_color", type, text)
		set_color("font_focus_color", type, text)
		set_color("font_disabled_color", type, secondary)
	for state: String in ["normal","hover","pressed","focus"]:
		set_color("icon_"+state+"_color","Button",text)
	set_color("icon_disabled_color","Button",secondary)
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
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		for role: String in ["wax","paper"]:
			var type: String = "WaxButton" if role == "wax" else "PaperButton"
			set_stylebox(state,type,_material_box(role,state))
			var entry: Dictionary = _style.button_materials[role]
			var ink: String = entry.disabled_text if state == "disabled" else entry.text_color
			set_color("font_color" if state == "normal" else "font_"+state+"_color",type,Color(ink))
	set_constant("icon_max_width","Button",int(_style.metrics.icon_size))
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
	set_stylebox("background", "ProgressBar", _box(MILK_TEA, MILK_TEA))
	set_stylebox("fill", "ProgressBar", _box(MOSS, MOSS))
	set_color("font_color", "ProgressBar", text)
	set_constant("separation", "VBoxContainer", int(_style.metrics.gap))
	set_constant("separation", "HBoxContainer", int(_style.metrics.gap))

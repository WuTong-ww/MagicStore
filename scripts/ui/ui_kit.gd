class_name MidnightUI
extends RefCounted

const Palette = preload("res://scripts/ui/palette.gd")
const GOLD := Palette.PAPER_ACCENT
const MUTED := Palette.MUTED

static func label(text: String, size: int = 18, color: Color = Palette.INK) -> Label:
	var node := Label.new()
	node.text = text
	if size >= 24:
		node.theme_type_variation = "Title"
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

static func button(text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.focus_mode = Control.FOCUS_ALL
	node.clip_text = false
	node.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	node.custom_minimum_size.y = 42
	node.pressed.connect(callback)
	node.pressed.connect(func():
		if node.is_inside_tree():
			var audio := node.get_tree().root.find_child("ShopAudio",true,false)
			if audio != null:
				audio.play_ui("click"))
	return node

static func panel() -> PanelContainer:
	var node := PanelContainer.new()
	if ResourceLoader.exists("res://themes/paper.tres"):
		node.theme = load("res://themes/paper.tres")
	return node

static func paper_window(window: Window) -> void:
	# A Window owns a viewport, so its Theme alone does not paint the content
	# canvas. Supply an explicit background behind its independent UI tree.
	if window.has_node("PaperWindowBackground"):
		return
	var background := Panel.new()
	background.name = "PaperWindowBackground"
	background.theme = load("res://themes/paper.tres")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(background)
	window.move_child(background,0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func image(path: String) -> TextureRect:
	var node := TextureRect.new()
	node.texture = load(path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func rich() -> RichTextLabel:
	var node := RichTextLabel.new()
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

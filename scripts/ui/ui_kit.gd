class_name MidnightUI
extends RefCounted

const GOLD := Color("d5bd86")
const MUTED := Color("8da4a5")

static func label(text: String, size: int = 18, color: Color = Color("e6e3d4")) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

static func button(text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(callback)
	return node

static func panel() -> PanelContainer:
	return PanelContainer.new()

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

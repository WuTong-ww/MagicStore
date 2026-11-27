extends Node
## Event-driven sizing: register new controls once, then react to their resize.
const Metrics = preload("res://scripts/ui/viewport_metrics.gd")
const PATH := "res://data/ui/readability.json"
var host: Control
var config: Dictionary = {}
var _queued: Dictionary = {}
var _buttons: Dictionary = {}
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	for key: String in ["button_height","button_font","horizontal_padding","vertical_padding","window_padding","wrap_characters","layout_ready_scale","header_icon_size","long_text_factor"]:
		if not (value.get(key) is int or value.get(key) is float) or not is_finite(float(value[key])) or float(value[key]) <= 0: return false
	if not value.get("header_icons") is Dictionary or not value.get("capture_sizes") is Array: return false
	for role: String in ["save","settings","notes"]:
		if not value.header_icons.get(role) is String or value.header_icons[role].is_empty(): return false
	return value.capture_sizes.size() == 4 and value.capture_sizes.all(func(s: Variant) -> bool: return s is Array and s.size() == 2 and s.all(func(n: Variant) -> bool: return (n is int or n is float) and is_finite(float(n)) and n > 0))
static func load_config() -> Dictionary:
	return preload("res://scripts/ui/packed_ui_data.gd").load_web(PATH,valid)
static func css_scale(control: Control) -> Vector2:
	var metrics := Metrics.measure(control)
	if not Metrics.valid(metrics): return Vector2.ONE
	var window := control.get_window()
	var physical: Vector2 = metrics.visible_css
	if window != control.get_tree().root:
		physical = Vector2(window.size)
		if control.get_tree().root.gui_embed_subwindows and not window.force_native: physical *= metrics.css_per_local_unit
	var logical: Vector2 = window.get_visible_rect().size
	if logical.x <= 0 or logical.y <= 0: return Vector2.ONE
	return (control.get_global_transform_with_canvas().get_scale()*physical/logical).abs()
func _ready() -> void:
	config = load_config()
	get_tree().node_added.connect(register)
	get_tree().root.size_changed.connect(refit)
	for node: Node in host.find_children("*","Button",true,false): register(node)
func _exit_tree() -> void:
	if get_tree().node_added.is_connected(register): get_tree().node_added.disconnect(register)
	if get_tree().root.size_changed.is_connected(refit): get_tree().root.size_changed.disconnect(refit)
func register(node: Node) -> void:
	if not node is Button or not host.is_ancestor_of(node): return
	_buttons[node.get_instance_id()] = weakref(node)
	if not node.resized.is_connected(queue_fit.bind(node)): node.resized.connect(queue_fit.bind(node))
	if not node.visibility_changed.is_connected(queue_fit.bind(node)): node.visibility_changed.connect(queue_fit.bind(node))
	queue_fit(node)
func refit() -> void:
	for id: int in _buttons.keys():
		var button: Button = _buttons[id].get_ref()
		if button == null: _buttons.erase(id)
		else: queue_fit(button)
func queue_fit(node: Button) -> void:
	if not is_instance_valid(node) or _queued.has(node.get_instance_id()): return
	_queued[node.get_instance_id()] = true
	fit.call_deferred(weakref(node),node.get_instance_id())
func fit(reference: WeakRef, id: int) -> void:
	_queued.erase(id)
	var button: Button = reference.get_ref()
	if button == null:
		_buttons.erase(id)
		return
	if config.is_empty() or not button.is_inside_tree(): return
	if not button.is_visible_in_tree(): return
	button.clip_text = false
	button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if not button.has_meta("r4_requested_font"):
		button.set_meta("r4_requested_font",button.get_theme_font_size("font_size"))
		button.set_meta("r4_requested_minimum",button.custom_minimum_size)
	var physical := css_scale(button)
	if physical.x <= 0 or physical.y <= 0: return
	if physical.y < float(config.layout_ready_scale):
		return
	var original: Vector2 = button.get_meta("r4_requested_minimum")
	var font_size := maxi(int(button.get_meta("r4_requested_font")),ceili(float(config.button_font)/physical.y))
	if not button.has_theme_font_size_override("font_size") or button.get_theme_font_size("font_size") != font_size:
		button.add_theme_font_size_override("font_size",font_size)
	if button.text.is_empty():
		# Image buttons keep the current height supplied by their responsive layout.
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y,float(config.button_height)/physical.y)
		return
	button.custom_minimum_size.y = maxf(original.y,float(config.button_height)/physical.y)
	if button.get_meta("r4_chrome",false): return
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var style := button.get_theme_stylebox("normal")
	var padding := style.get_minimum_size() if style != null else Vector2(config.horizontal_padding*2,config.vertical_padding*2)
	var icon_width := float(button.icon.get_width())+float(config.horizontal_padding) if button.icon != null else 0.0
	var natural_width := button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var minimum_width: float = minf(natural_width,float(font_size)*float(config.wrap_characters))+padding.x+icon_width
	button.custom_minimum_size.x = maxf(original.x,minimum_width)
	var width := maxf(1,button.size.x-padding.x)
	if button.icon != null: width = maxf(1,width-button.icon.get_width()-float(config.horizontal_padding))
	var text_size := button.get_theme_font("font").get_multiline_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,width,font_size)
	button.custom_minimum_size.y = maxf(maxf(original.y,float(config.button_height)/physical.y),text_size.y+padding.y)

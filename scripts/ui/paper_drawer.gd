class_name PaperDrawer
extends Control
## Reversible presentation only. Never writes gameplay state.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Shell = preload("res://scripts/ui/shell_config.gd")
var content: VBoxContainer
var panel: PanelContainer
var bookmark: Button
var expanded := true
var slide: Tween
var config: Dictionary

func _ready() -> void:
	config = Shell.load_config()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = UI.panel()
	panel.name = "PaperPanel"
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	bookmark = UI.button(config.drawer_close, func(): set_expanded(not expanded))
	bookmark.name = "DrawerBookmark"
	add_child(bookmark)
	resized.connect(_layout)
	_layout()

func set_expanded(value: bool, animate: bool = true) -> void:
	expanded = value
	if expanded:
		panel.show()
	bookmark.text = config.drawer_close if value else config.drawer_open
	if slide != null:
		slide.kill()
	if not animate:
		_layout()
		return
	var width := minf(float(config.drawer_width),size.x)
	slide = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	slide.tween_property(panel,"position:x",size.x-width if expanded else size.x,config.drawer_seconds)
	slide.parallel().tween_property(bookmark,"position:x",size.x-width-bookmark.size.x if expanded else size.x-bookmark.size.x,config.drawer_seconds)
	slide.finished.connect(func(): panel.visible = expanded)

func _layout() -> void:
	if not is_instance_valid(panel) or config.is_empty():
		return
	var width := minf(float(config.drawer_width),size.x)
	panel.position = Vector2(size.x-width if expanded else size.x,0)
	panel.visible = expanded
	panel.size = Vector2(width,size.y)
	bookmark.size = bookmark.get_combined_minimum_size()
	bookmark.position = Vector2(panel.position.x-bookmark.size.x,0)

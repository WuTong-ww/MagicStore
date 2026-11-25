class_name PaperDrawer
extends Control
## Reversible presentation only. Never writes gameplay state.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Shell = preload("res://scripts/ui/shell_config.gd")
const ResponsiveConfig = preload("res://scripts/ui/responsive_config.gd")
const ViewportMetrics = preload("res://scripts/ui/viewport_metrics.gd")
const ResponsiveLayout = preload("res://scripts/ui/responsive_layout.gd")
const Materials = preload("res://scripts/ui/panel_materials.gd")
const NotebookPages = preload("res://scripts/ui/notebook_pages.gd")
var content: VBoxContainer
var right_content: VBoxContainer
var notebook_pages: Control
var panel: PanelContainer
var bookmark: Button
var expanded := true
var slide: Tween
var config: Dictionary
var responsive_config: Dictionary = {}
var backdrop: ColorRect
var _content_order: Array[Node] = []

func _ready() -> void:
	config = Shell.load_config()
	responsive_config = ResponsiveConfig.load_config()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop = ColorRect.new()
	backdrop.name = "DrawerBackdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.color = Materials.backdrop_color()
	backdrop.set_meta("material_drawer_backdrop",true)
	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			set_expanded(false,false)
			accept_event())
	add_child(backdrop)
	backdrop.hide()
	panel = UI.panel("notebook")
	panel.name = "PaperPanel"
	add_child(panel)
	var pages := NotebookPages.new()
	pages.name = "DrawerNotebookPages"
	panel.add_child(pages)
	notebook_pages = pages
	# Keep this exact VBox instance usable by the existing front/shop builders.
	content = pages.left
	right_content = pages.right
	bookmark = UI.button(config.drawer_close, func(): set_expanded(not expanded))
	bookmark.name = "DrawerBookmark"
	add_child(bookmark)
	resized.connect(_layout)
	get_tree().root.size_changed.connect(_on_client_resized)
	_layout()

func begin_content_update() -> void:
	# Return both pages to the original receiver before a legacy builder clears
	# its children. References, signals, action callbacks and group nodes survive.
	if not is_instance_valid(content) or not is_instance_valid(right_content): return
	var current: Array[Node] = []
	current.append_array(content.get_children())
	current.append_array(right_content.get_children())
	var ordered: Array[Node] = []
	for child: Node in _content_order:
		if is_instance_valid(child) and child in current: ordered.append(child)
	for child: Node in current:
		if child not in ordered: ordered.append(child)
	for index: int in range(ordered.size()):
		var child: Node = ordered[index]
		if child.get_parent() != content: child.reparent(content,false)
		content.move_child(child,index)
	_content_order = ordered

func balance_content_pages() -> void:
	if not is_instance_valid(content) or not is_instance_valid(right_content): return
	begin_content_update()
	var rows: Array[Node] = content.get_children()
	_content_order = rows.duplicate()
	var material: Dictionary = Materials.load_config()
	if material.is_empty(): return
	# Preserve reading order and complete logical groups. Split at the nearest
	# visible half-height boundary; no child or title spans the notebook spine.
	var gap: float = float(content.get_theme_constant("separation"))
	var total := 0.0
	var visible_count := 0
	for child: Node in rows:
		if child is Control and child.visible:
			total += child.get_combined_minimum_size().y+gap
			visible_count += 1
	var split := rows.size()
	var used := 0.0
	var passed := 0
	var best_distance := INF
	for index: int in range(rows.size()):
		var child: Node = rows[index]
		if child is Control and child.visible:
			used += child.get_combined_minimum_size().y+gap
			passed += 1
			var distance: float = absf(used-total*0.5)
			if passed < visible_count and distance < best_distance:
				best_distance = distance
				split = index+1
	for index: int in range(split,rows.size()): rows[index].reparent(right_content,false)
	if content.has_theme_constant_override("separation"):
		right_content.add_theme_constant_override("separation",content.get_theme_constant("separation"))
	panel.set_meta("material_content_order",rows.map(func(child: Node) -> String: return str(child.name)))
	panel.set_meta("material_content_split",split)
	_layout.call_deferred()

func set_expanded(value: bool, animate: bool = true) -> void:
	expanded = value
	if expanded:
		panel.show()
	bookmark.text = config.drawer_close if value else config.drawer_open
	if slide != null:
		slide.kill()
	var metrics: Dictionary = ViewportMetrics.measure(self)
	if not ViewportMetrics.valid(metrics): return
	var previous_panel: Vector2 = panel.position
	var previous_bookmark: Vector2 = bookmark.position
	_layout()
	if metrics.short or not animate: return
	var target_panel: Vector2 = panel.position
	var target_bookmark: Vector2 = bookmark.position
	panel.show()
	panel.position = previous_panel
	bookmark.position = previous_bookmark
	slide = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	slide.tween_property(panel,"position",target_panel,config.drawer_seconds)
	slide.parallel().tween_property(bookmark,"position",target_bookmark,config.drawer_seconds)
	slide.finished.connect(func(): panel.visible = expanded)

func _layout() -> void:
	if not is_instance_valid(panel) or config.is_empty():
		return
	var metrics: Dictionary = ViewportMetrics.measure(self)
	if responsive_config.is_empty() or not ViewportMetrics.valid(metrics): return
	if slide != null and slide.is_running(): slide.kill()
	var material: Dictionary = Materials.load_config()
	var client: Vector2 = metrics.visible_css
	var margin: float = float(responsive_config.safe_margin)
	var minimum: Vector2 = NotebookPages.minimum_book_size()
	var preferred: Vector2 = NotebookPages.preferred_book_size()
	if material.is_empty():
		minimum = Vector2(responsive_config.drawer_minimum[0],responsive_config.drawer_minimum[1])
		preferred = Vector2(config.drawer_width,client.y)
		begin_content_update()
		notebook_pages.right_scroll.hide()
	else:
		notebook_pages.right_scroll.show()
	var width: float = minf(preferred.x,client.x-margin*2.0)
	var safe_height: float = maxf(1.0,client.y-float(config.top_height)-float(config.dock_height)-margin*2.0)
	var height: float = client.y if metrics.short else minf(preferred.y,safe_height)
	var top: float = 0.0 if metrics.short else float(config.top_height)+margin+(safe_height-height)*0.5
	var left: float = client.x-width-(0.0 if metrics.short else margin) if expanded else client.x
	var available := Rect2(Vector2(left,top),Vector2(width,height))
	ResponsiveLayout.apply(panel,ResponsiveLayout.fit_minimum(minimum,available,metrics,Vector2(0.5,0.5),true))
	if material.is_empty():
		notebook_pages.left_scroll.position = Vector2.ZERO
		notebook_pages.left_scroll.size = panel.size
	panel.set_meta("material_fixed_layout",bool(metrics.short))
	panel.set_meta("material_content_rects",Materials.content_rects(panel.size,"notebook"))
	panel.set_meta("material_effective_css_scale",panel.get_global_transform_with_canvas().get_scale()*metrics.css_per_local_unit)
	panel.z_index = int(responsive_config.overlay_z)+1
	panel.visible = expanded
	ResponsiveLayout.apply(backdrop,ResponsiveLayout.fit_minimum(client,Rect2(Vector2.ZERO,client),metrics))
	backdrop.z_index = int(responsive_config.overlay_z)
	backdrop.visible = expanded
	var toggle_size := Vector2(responsive_config.toggle_size[0],responsive_config.toggle_size[1]).max(bookmark.get_combined_minimum_size())
	var toggle_left: float = left-toggle_size.x if expanded else client.x-toggle_size.x
	var toggle_box := Rect2(Vector2(maxf(0,toggle_left),float(responsive_config.toggle_top)),toggle_size)
	ResponsiveLayout.apply(bookmark,ResponsiveLayout.fit_minimum(toggle_size,toggle_box,metrics))
	bookmark.z_index = int(responsive_config.overlay_z)+2

func _on_client_resized() -> void:
	_layout.call_deferred()

func consume_drawer_event(event: InputEventMouseButton) -> bool:
	var metrics: Dictionary = ViewportMetrics.measure(self)
	if not is_visible_in_tree() or not expanded or not ViewportMetrics.valid(metrics) or not event.pressed: return false
	var point: Vector2 = event.position*metrics.css_per_local_unit
	if ViewportMetrics.css_rect(panel,metrics).has_point(point) or ViewportMetrics.css_rect(bookmark,metrics).has_point(point): return false
	if event.button_index == MOUSE_BUTTON_LEFT: set_expanded(false,false)
	return true

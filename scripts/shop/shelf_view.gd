class_name ShelfView
extends Control
## Committed-inventory presentation. No action, save or wind simulation lives here.
const ItemArt = preload("res://scripts/shop/item_visual.gd")
const LayoutCore = preload("res://scripts/shop/shelf_layout.gd")
signal item_selected(item_id: String)
signal item_added(item_id: String, quantity: int, node: Node2D)
signal item_removed(item_id: String, quantity: int, node: Node2D)

var visuals: Dictionary = {}
var layout_result: Dictionary = {"entries":[],"overflow":[]}
var selected_item := ""
var debug_lines := false:
	set(value):
		debug_lines = value
		if is_instance_valid(_debug_overlay):
			_debug_overlay.visible = value
			_debug_overlay.queue_redraw()
var _scene_visual: Control
var _settings: Dictionary = {}
var _display_view: Dictionary = {}
var _snapshot: Dictionary = {}
var _native_root: Node2D
var _debug_overlay: Node2D
var _paper: TextureRect
var _name_tag: PanelContainer
var _entries: Dictionary = {}
var _items: Dictionary = {}
var _shadows: Dictionary = {}
var _targets: Dictionary = {}
var _selection_tweens: Dictionary = {}
var _selection_lifts: Dictionary = {}
var _item_motion: Dictionary = {}
var _outgoing_placements: Dictionary = {}
var _hovered_item := ""
var _force_layout := true
var _opened := false
var _baseline_save := ""
var _baseline_version := -1
var _baseline_items: Dictionary = {}
var _baseline_batches: Array = []

func setup(scene_visual: Control, data: Dictionary) -> void:
	if is_instance_valid(_scene_visual) and _scene_visual.resized.is_connected(_project):
		_scene_visual.resized.disconnect(_project)
	_scene_visual = scene_visual
	visuals = data
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _scene_visual.has_method("interaction_z_index"):
		z_index = int(_scene_visual.call("interaction_z_index"))
	if not _scene_visual.resized.is_connected(_project):
		_scene_visual.resized.connect(_project)
	var scene: Dictionary = visuals.get("scenes",{}).get("S04",{})
	_settings = scene.get("shelf_layout",{}).duplicate(true)
	_force_layout = true
	if not is_instance_valid(_native_root):
		_native_root = Node2D.new()
		_native_root.name = "NativeShelf"
		add_child(_native_root)
		_debug_overlay = Node2D.new()
		_debug_overlay.name = "ShelfDebug"
		_debug_overlay.z_index = 4
		_native_root.add_child(_debug_overlay)
		_debug_overlay.draw.connect(_draw_debug)
		_paper = TextureRect.new()
		_paper.name = "ShelfPaper"
		_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_paper.z_index = 3
		add_child(_paper)
	if LayoutCore.settings_valid(scene,visuals.get("items",{})):
		_make_paper()
	else:
		_settings = {}
	_project()
	visible = _opened and not _settings.is_empty()

func update_inventory(view: Dictionary, snapshot: Dictionary, opened: bool) -> void:
	_opened = opened
	var save_id := str(snapshot.get("save_id",""))
	var version := int(snapshot.get("state_version",-1))
	var stale := save_id == _baseline_save and version < _baseline_version
	if not stale:
		_snapshot = snapshot.duplicate(true)
	var display_view := _display_view if stale else view
	var changed_save := not save_id.is_empty() and save_id != _baseline_save
	var committed := not save_id.is_empty() and version >= 0 and (changed_save or version > _baseline_version)
	var current_items: Dictionary = snapshot.get("player",{}).get("items",view.get("items",{}))
	var current_batches: Array = snapshot.get("shop",{}).get("batches",view.get("shop",{}).get("batches",[]))
	var deltas := {"added":{},"removed":{}}
	if committed and not changed_save and _baseline_version >= 0:
		deltas = _deltas(_baseline_items,current_items,_baseline_batches,current_batches)
	if changed_save:
		selected_item = ""
		_hovered_item = ""
	var quantities_changed: bool = _display_view.get("items",{}) != display_view.get("items",{})
	_display_view = display_view.duplicate(true)
	var previous_items := _items.duplicate()
	_outgoing_placements = _entries.duplicate(true)
	if _settings.is_empty():
		layout_result = {"entries":[],"overflow":[]}
	elif _force_layout or quantities_changed or changed_save:
		layout_result = LayoutCore.layout(_display_view,visuals)
		_render_entries()
		_force_layout = false
	_refresh_tints()
	_project()
	visible = opened and not _settings.is_empty()
	if not opened:
		_hovered_item = ""
		for id: String in _item_motion.keys():
			set_item_motion(id,Vector2.ZERO,0.0)
	_update_name_tag()
	if committed:
		_baseline_save = save_id
		_baseline_version = version
		_baseline_items = current_items.duplicate(true)
		_baseline_batches = current_batches.duplicate(true)
		for id: String in deltas.removed:
			item_removed.emit(id,int(deltas.removed[id]),previous_items.get(id,_items.get(id)))
		for id: String in deltas.added:
			item_added.emit(id,int(deltas.added[id]),_items.get(id))
	_outgoing_placements.clear()
	for id: String in previous_items:
		if not _items.has(id) and is_instance_valid(previous_items[id]):
			previous_items[id].queue_free()

func get_item_node(id: String) -> Node2D:
	return _items.get(id)

func item_placement(id: String) -> Dictionary:
	return _entries.get(id,_outgoing_placements.get(id,{})).duplicate(true)

func set_item_motion(id: String, offset_native: Vector2, angle_deg: float) -> void:
	if not _entries.has(id) or not offset_native.is_finite() or not is_finite(angle_deg):
		return
	_item_motion[id] = {"offset":offset_native,"angle":angle_deg}
	_apply_item_pose(id)

func get_hit_rect(id: String) -> Rect2:
	return _targets[id].get_global_rect() if _targets.has(id) and is_instance_valid(_targets[id]) else Rect2()

func select_item(id: String) -> void:
	if id == selected_item or int(_display_view.get("items",{}).get(id,0)) <= 0:
		return
	var previous := selected_item
	selected_item = id
	_move_selection(previous)
	_move_selection(id)
	item_selected.emit(id)

func _render_entries() -> void:
	for tween: Tween in _selection_tweens.values():
		if tween.is_running():
			tween.kill()
	_selection_tweens.clear()
	var retained: Dictionary = {}
	_entries.clear()
	for node: Node in _shadows.values()+_targets.values():
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	_shadows.clear()
	_targets.clear()
	for entry: Dictionary in layout_result.get("entries",[]):
		var id: String = entry.item_id
		_entries[id] = entry
		var pivot: Node2D = _items.get(id)
		if not is_instance_valid(pivot):
			pivot = Node2D.new()
			pivot.name = "ShelfItem_"+id
			pivot.z_index = 1
			_native_root.add_child(pivot)
		for child: Node in pivot.get_children():
			pivot.remove_child(child)
			child.queue_free()
		retained[id] = pivot
		pivot.set_meta("item_id",id)
		pivot.set_meta("quantity",entry.quantity)
		_selection_lifts[id] = _lift_for(id).y
		var offset := Vector2(_settings.stack_offset_px[0],_settings.stack_offset_px[1])
		for copy_index: int in range(int(entry.copy_count)-1,-1,-1):
			var sprite := Sprite2D.new()
			sprite.name = "ItemSprite" if copy_index == 0 else "ItemSprite_"+str(copy_index)
			sprite.texture = ItemArt.texture_for(visuals,id,false)
			sprite.centered = false
			sprite.scale = Vector2.ONE*float(entry.scale)
			sprite.position = -entry.support*float(entry.scale)+offset*copy_index
			sprite.set_meta("copy_index",copy_index)
			pivot.add_child(sprite)
		if int(entry.quantity) > int(_settings.max_copies):
			var note := _tag(str(_settings.quantity_format)%int(entry.quantity),_settings.quantity_tag,"QuantityTag","QuantityText")
			note.z_index = 4
			pivot.add_child(note)
			note.position = Vector2(_settings.quantity_tag.offset_px[0],_settings.quantity_tag.offset_px[1])
		_make_shadow(entry)
		var target := Control.new()
		target.name = "ItemTarget_"+id
		target.mouse_filter = Control.MOUSE_FILTER_STOP
		target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		target.z_index = 2
		_native_root.add_child(target)
		target.position = entry.visible_rect.position-_lift_for(id)
		target.size = entry.visible_rect.size
		target.mouse_entered.connect(func(): _hovered_item = id; _update_name_tag())
		target.mouse_exited.connect(func():
			if _hovered_item == id:
				_hovered_item = ""
				_update_name_tag())
		target.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				target.accept_event()
				select_item(id))
		_targets[id] = target
	_items = retained
	for id: String in _item_motion.keys():
		if not _items.has(id):
			_item_motion.erase(id)
	for id: String in _selection_lifts.keys():
		if not _items.has(id):
			_selection_lifts.erase(id)
	for id: String in _items:
		_apply_item_pose(id)
	if int(_display_view.get("items",{}).get(selected_item,0)) <= 0:
		selected_item = ""
	_debug_overlay.queue_redraw()

func _make_shadow(entry: Dictionary) -> void:
	var shadow := Sprite2D.new()
	shadow.name = "ItemShadow_"+str(entry.item_id)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.BLACK,Color.WHITE])
	var texture := GradientTexture2D.new()
	texture.width = int(_settings.shadow.texture_size[0])
	texture.height = int(_settings.shadow.texture_size[1])
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5,0.5)
	texture.fill_to = Vector2(1,0.5)
	shadow.texture = texture
	shadow.position = entry.pivot
	shadow.scale = Vector2(float(entry.bottom_width)*float(entry.scale)*float(_settings.shadow.width_factor)/texture.width,float(_settings.shadow.height_px)/texture.height)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_mul; uniform float opacity; void fragment(){ float g=texture(TEXTURE,UV).r; COLOR=vec4(vec3(1.0-opacity*(1.0-g)),1.0); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("opacity",float(_settings.shadow.opacity))
	shadow.material = material
	_native_root.add_child(shadow)
	_shadows[entry.item_id] = shadow

func _make_paper() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = int(_settings.paper.seed)
	noise.frequency = float(_settings.paper.noise_frequency)
	var texture := NoiseTexture2D.new()
	texture.width = int(_settings.paper.texture_size[0])
	texture.height = int(_settings.paper.texture_size[1])
	texture.noise = noise
	texture.seamless = true
	_paper.texture = texture
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_mul; uniform float opacity; void fragment(){ COLOR=vec4(vec3(1.0-opacity*texture(TEXTURE,UV).r),1.0); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("opacity",float(_settings.paper.opacity))
	_paper.material = material

func _tag(text: String, settings: Dictionary, node_name: String, label_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(settings.paper_color)
	style.content_margin_left = settings.padding_px[0]
	style.content_margin_right = settings.padding_px[0]
	style.content_margin_top = settings.padding_px[1]
	style.content_margin_bottom = settings.padding_px[1]
	if settings.has("border_color"):
		style.border_color = Color(settings.border_color)
		style.set_border_width_all(int(settings.border_width_px))
	panel.add_theme_stylebox_override("panel",style)
	var label := Label.new()
	label.name = label_name
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color",Color(settings.text_color))
	label.add_theme_font_size_override("font_size",int(settings.font_size))
	if ResourceLoader.exists(settings.font_path):
		label.add_theme_font_override("font",load(settings.font_path))
	panel.add_child(label)
	panel.reset_size()
	return panel

func _update_name_tag() -> void:
	if _settings.is_empty():
		return
	var label := ItemArt.name_for(visuals,_hovered_item,_display_view.get("catalog",{}).get("items",{}))
	if not is_instance_valid(_name_tag):
		_name_tag = _tag(label,_settings.name_tag,"HoverName","NameText")
		_name_tag.z_index = 5
		_native_root.add_child(_name_tag)
	else:
		(_name_tag.get_node("NameText") as Label).text = label
		_name_tag.reset_size()
	_name_tag.visible = _opened and _entries.has(_hovered_item)
	if _name_tag.visible:
		_name_tag.position = _entries[_hovered_item].pivot+Vector2(-_name_tag.size.x/2.0,float(_settings.name_tag.drop_px))

func _lift_for(id: String) -> Vector2:
	return Vector2(0,float(_settings.selection_lift_px)) if id == selected_item else Vector2.ZERO

func _move_selection(id: String) -> void:
	if not _items.has(id):
		return
	if _selection_tweens.has(id) and _selection_tweens[id].is_running():
		_selection_tweens[id].kill()
	var target := _lift_for(id).y
	if is_inside_tree() and float(_settings.selection_seconds) > 0:
		var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_method(_set_selection_lift.bind(id),float(_selection_lifts.get(id,0.0)),target,float(_settings.selection_seconds))
		_selection_tweens[id] = tween
	else:
		_set_selection_lift(target,id)

func _set_selection_lift(value: float, id: String) -> void:
	_selection_lifts[id] = value
	_apply_item_pose(id)

func _apply_item_pose(id: String) -> void:
	if not _items.has(id) or not is_instance_valid(_items[id]) or not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	var motion: Dictionary = _item_motion.get(id,{"offset":Vector2.ZERO,"angle":0.0})
	var shift: Vector2 = motion.offset-Vector2(0,float(_selection_lifts.get(id,0.0)))
	_items[id].position = entry.pivot+shift
	_items[id].rotation_degrees = float(entry.rotation_degrees)+float(motion.angle)
	if _targets.has(id) and is_instance_valid(_targets[id]):
		var bounds: Rect2 = entry.visible_rect
		var corners := [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]
		var first: Vector2 = entry.pivot+(corners[0]-entry.pivot).rotated(deg_to_rad(float(motion.angle)))+shift
		var hit := Rect2(first,Vector2.ZERO)
		for corner: Vector2 in corners:
			hit = hit.expand(entry.pivot+(corner-entry.pivot).rotated(deg_to_rad(float(motion.angle)))+shift)
		_targets[id].position = hit.position
		_targets[id].size = hit.size

func _refresh_tints() -> void:
	if _settings.is_empty():
		return
	var period := str(_scene_visual.get("current_period"))
	if not period in ["day","night"]:
		var timing: Dictionary = visuals.scene_settings
		var minute := int(_snapshot.get("clock_minutes",timing.day_minute))%int(timing.minutes_per_day)
		period = "day" if minute >= int(timing.day_minute) and minute < int(timing.night_minute) else "night"
	for id: String in _items:
		var shelf: Dictionary = visuals.scenes.S04.shelves[int(_entries[id].shelf_index)]
		var tint := Color(shelf["light_tint_"+period])
		for child: Node in _items[id].get_children():
			if child is Sprite2D:
				var strength := 1.0-float(child.get_meta("copy_index"))*float(_settings.stack_darkening_step)
				child.modulate = Color(tint.r*strength,tint.g*strength,tint.b*strength,tint.a)

func _project() -> void:
	if _settings.is_empty() or not is_instance_valid(_native_root) or not is_instance_valid(_scene_visual):
		return
	_native_root.position = _scene_visual.call("native_point",Vector2.ZERO,_settings.native_size,_settings.source_crop)
	_native_root.scale = Vector2.ONE*float(_scene_visual.call("native_scale",_settings.native_size,_settings.source_crop))
	var canvas: Array = visuals.scene_settings.canvas
	var rectangle: Rect2 = _scene_visual.call("projected_rect",[0,0,canvas[0],canvas[1]])
	_paper.position = rectangle.position
	_paper.size = rectangle.size
	_debug_overlay.visible = debug_lines
	_debug_overlay.queue_redraw()

func _draw_debug() -> void:
	if not debug_lines or _settings.is_empty():
		return
	var style: Dictionary = _settings.debug
	for shelf: Dictionary in visuals.scenes.S04.shelves:
		_debug_overlay.draw_line(Vector2(shelf.x_start,shelf.y),Vector2(shelf.x_end,shelf.y),Color(style.line_color),float(style.line_width_px))
	for entry: Dictionary in layout_result.get("entries",[]):
		_debug_overlay.draw_circle(entry.pivot,float(style.point_radius_px),Color(style.point_color))

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _settings.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and OS.get_keycode_string(event.keycode) == str(_settings.debug.toggle_key):
		debug_lines = not debug_lines
		get_viewport().set_input_as_handled()

static func _deltas(before: Dictionary, after: Dictionary, old_batches: Array, new_batches: Array) -> Dictionary:
	var added: Dictionary = {}
	var removed: Dictionary = {}
	var old := _batch_map(old_batches)
	var newer := _batch_map(new_batches)
	if not old.is_empty() and not newer.is_empty():
		var keys: Array = old.keys()
		for key: String in newer:
			if key not in keys:
				keys.append(key)
		for key: String in keys:
			if old.has(key) and newer.has(key) and old[key].item_id != newer[key].item_id:
				continue
			var row: Dictionary = newer.get(key,old.get(key,{}))
			var difference := int(newer.get(key,{}).get("remaining",0))-int(old.get(key,{}).get("remaining",0))
			if difference > 0:
				added[row.item_id] = int(added.get(row.item_id,0))+difference
			elif difference < 0:
				removed[row.item_id] = int(removed.get(row.item_id,0))-difference
	var ids: Array = before.keys()
	for id: String in after:
		if id not in ids:
			ids.append(id)
	var batches_agree := not old_batches.is_empty() and not new_batches.is_empty()
	for id: String in ids:
		if int(added.get(id,0))-int(removed.get(id,0)) != int(after.get(id,0))-int(before.get(id,0)):
			batches_agree = false
	if not batches_agree:
		added.clear()
		removed.clear()
		for id: String in ids:
			var difference := int(after.get(id,0))-int(before.get(id,0))
			if difference > 0:
				added[id] = difference
			elif difference < 0:
				removed[id] = -difference
	return {"added":added,"removed":removed}

static func _batch_map(batches: Array) -> Dictionary:
	var result: Dictionary = {}
	for row: Variant in batches:
		if not row is Dictionary or not row.get("batch_id") is String or not row.get("item_id") is String or result.has(row.batch_id):
			return {}
		result[row.batch_id] = row
	return result

extends Control
## Isolated draft: title presentation only; all writes belong to Main actions.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Config = preload("res://scripts/ui/title_config.gd")
const Art = preload("res://scripts/shop/scene_visual.gd")
const Motion = preload("res://scripts/presentation/scene_motion.gd")
const Wind = preload("res://scripts/presentation/wind_field.gd")
const Spring = preload("res://scripts/presentation/damped_spring.gd")
const Notes = preload("res://scripts/ui/story_notes.gd")
const Geometry = preload("res://scripts/ui/title_geometry.gd")
const GlassShader = preload("res://shaders/title_glass.gdshader")
signal new_requested(name: String)
signal continue_requested
signal settings_requested
signal entry_closed
var host: Control
var config_path := Config.PATH
var config: Dictionary = {}
var scene_id := "S01"
var current_period := "dusk"
var layer_nodes: Dictionary = {}
var motion_controller: Node
var art_root: Control
var native_art_root: Control
var sign_static_parent: Control
var window_light_image: Image
var window_mask_image: Image
var window_glow_atlas: AtlasTexture
var overlay_root: Control
var window_glow: TextureRect
var status: Label
var buttons: Dictionary = {}
var new_panel: PanelContainer
var new_name: LineEdit
var new_submit: Button
var new_cancel: Button
var credits_panel: PanelContainer
var notes_panel: PanelContainer
var opening_notes: Control
var title_visual: Control
var transition: Tween
var light_tween: Tween
var request_pending := false
var entering := false
var awaiting_note := false
var _hovered: Dictionary = {}
var _focused: Dictionary = {}
var _springs: Dictionary = {}
var _leaves: CPUParticles2D
var _wind: Node
var _time := 0.0

func _ready() -> void:
	config = Config.load_config(config_path)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if config.is_empty():
		hide()
		return
	_wind = get_node_or_null("/root/WindField")
	_build()
	resized.connect(_layout)
	_layout()
	if not Config.missing_resources(config).is_empty(): status.text = str(config.copy.missing_assets)
	refresh_continue()

func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _image(path: String, parent: Node) -> TextureRect:
	var node := TextureRect.new()
	node.texture = _texture(path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _place(node: Control, rect: Array) -> void:
	node.position = Vector2(rect[0],rect[1])
	node.size = Vector2(rect[2],rect[3])

func _build() -> void:
	var fallback := ColorRect.new()
	fallback.color = Color(config.layout.fallback_color)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fallback)
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_root = Control.new()
	art_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art_root)
	var geometry: Dictionary = config.geometry
	var native := Vector2(geometry.background_size[0],geometry.background_size[1])
	native_art_root = Control.new()
	native_art_root.name = "TitleNativeArt"
	native_art_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_root.add_child(native_art_root)
	var projection := Geometry.background_projection(geometry,config.canvas)
	native_art_root.position = projection.position
	native_art_root.size = native
	native_art_root.scale = Vector2.ONE*(projection.size.x/native.x)
	var background := _image(str(config.assets.background),native_art_root)
	background.size = native
	fallback.visible = background.texture == null
	window_glow = TextureRect.new()
	native_art_root.add_child(window_glow)
	window_glow.name = "TitleWindowGlow"
	window_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	window_glow.stretch_mode = TextureRect.STRETCH_SCALE
	window_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	window_glow.size = native
	window_glow.modulate.a = 0
	var raw_glow := _texture(str(config.assets.window_glow))
	if raw_glow != null:
		var composed := Geometry.build_light(raw_glow,geometry)
		if not composed.is_empty():
			window_light_image = composed.light
			window_mask_image = composed.mask
			window_glow_atlas = composed.atlas
			window_glow.texture = ImageTexture.create_from_image(window_light_image)
			var glass := ShaderMaterial.new()
			glass.shader = GlassShader
			glass.set_shader_parameter("glass_mask",ImageTexture.create_from_image(window_mask_image))
			window_glow.material = glass
	var descriptors: Dictionary = {}
	for key: String in ["hanging_sign","tree_canopy"]:
		var parent: Control = native_art_root
		if key == "hanging_sign":
			sign_static_parent = Control.new()
			sign_static_parent.name = "TitleSignCalibration"
			sign_static_parent.mouse_filter = Control.MOUSE_FILTER_IGNORE
			native_art_root.add_child(sign_static_parent)
			var static_pose: Dictionary = geometry.hanging_sign
			sign_static_parent.position = Vector2(static_pose.translation[0],static_pose.translation[1])
			sign_static_parent.scale = Vector2.ONE*float(static_pose.scale)
			sign_static_parent.rotation_degrees = float(static_pose.rotation_degrees)
			parent = sign_static_parent
		var layer := _image(str(config.assets[key]),parent)
		var dimensions: Array = geometry.asset_sizes[key]
		layer.size = Vector2(dimensions[0],dimensions[1])
		if key != "hanging_sign": layer.scale = native/layer.size
		var pivot: Array = geometry.hanging_sign.pivot if key == "hanging_sign" else geometry.canopy_pivot
		layer.pivot_offset = Vector2(pivot[0],pivot[1])
		layer_nodes[key] = layer
		descriptors[key] = {"path":config.assets[key],"rect":[0,0,dimensions[0],dimensions[1]],"native_size":dimensions,"pivot_px":pivot,"motion":{"type":"pendulum" if key == "hanging_sign" else "sway_shader","parameters":config.motion.hanging_sign.duplicate(true) if key == "hanging_sign" else {}}}
	var motion_config: Dictionary = Wind.load_settings()
	if not motion_config.is_empty():
		# Only real declared layers are expected; the original S01 remains untouched.
		motion_config.expected_layers[scene_id] = descriptors.keys()
		motion_controller = Motion.new()
		add_child(motion_controller)
		motion_controller.bind(self,{"layers":descriptors},motion_config)
		for row: Dictionary in config.menu:
			var spring = Spring.new()
			var parameters: Dictionary = motion_config.spring.duplicate(true)
			parameters.merge(motion_config.layer_defaults.pendulum,true)
			spring.configure(parameters)
			_springs[row.id] = spring
	if ResourceLoader.exists(str(config.assets.calligraphy)):
		title_visual = _image(str(config.assets.calligraphy),art_root)
	else:
		var heading := UI.label(str(config.copy.title),int(config.layout.title_font),Color(config.layout.title_color))
		if ResourceLoader.exists(str(config.assets.font)): heading.add_theme_font_override("font",load(str(config.assets.font)))
		var ink := ShaderMaterial.new()
		ink.shader = preload("res://shaders/title_ink.gdshader")
		ink.set_shader_parameter("grain_strength",float(config.layout.ink_grain_strength))
		heading.material = ink
		art_root.add_child(heading)
		title_visual = heading
	_place(title_visual,config.layout.title_rect)
	var subtitle := UI.label(str(config.copy.subtitle),int(config.layout.subtitle_font),Color(config.layout.title_color))
	if ResourceLoader.exists(str(config.assets.font)): subtitle.add_theme_font_override("font",load(str(config.assets.font)))
	if title_visual is Label: subtitle.material = title_visual.material
	art_root.add_child(subtitle)
	_place(subtitle,config.layout.subtitle_rect)
	for row: Dictionary in config.menu:
		var id := str(row.id)
		var button := UI.button(str(row.text),_activate.bind(id))
		button.name = "TitleMenu_"+id
		button.tooltip_text = str(row.tooltip)
		button.add_theme_font_size_override("font_size",int(config.layout.menu_font))
		for color_key: String in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
			button.add_theme_color_override(color_key,Color(config.layout.text_color))
		button.add_theme_color_override("font_disabled_color",Color(config.layout.disabled_text_color))
		var wood := _texture(str(config.assets.wood_sign))
		if wood != null:
			for state: String in ["normal","hover","pressed","focus","disabled"]:
				var style := StyleBoxTexture.new()
				style.texture = wood
				button.add_theme_stylebox_override(state,style)
		art_root.add_child(button)
		_place(button,row.rect)
		button.pivot_offset = button.size*0.5
		button.mouse_entered.connect(_set_highlight.bind(id,true,false))
		button.mouse_exited.connect(_set_highlight.bind(id,false,false))
		button.focus_entered.connect(_set_highlight.bind(id,true,true))
		button.focus_exited.connect(_set_highlight.bind(id,false,true))
		buttons[id] = button
	status = UI.label("",int(config.layout.notice_font),Color(config.layout.text_color))
	art_root.add_child(status)
	_place(status,config.layout.notice_rect)
	overlay_root = Control.new()
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_root)
	_build_new_panel()
	credits_panel = _panel(config.layout.credits_rect)
	var credits_box := _box(credits_panel)
	credits_box.add_child(UI.label(str(config.copy.credits_title),int(config.layout.menu_font)))
	var credits := UI.rich()
	credits.text = str(config.copy.credits_body)
	credits_box.add_child(credits)
	credits_box.add_child(UI.button(str(config.copy.close),func():
		credits_panel.hide()
		refresh_continue()))
	credits_panel.hide()
	notes_panel = _panel(config.layout.notes_rect)
	opening_notes = Notes.new()
	_box(notes_panel).add_child(opening_notes)
	# Keyboard reading has a harmless focus anchor during the opening modal.
	opening_notes.body.focus_mode = Control.FOCUS_ALL
	opening_notes.close_requested.connect(_close_opening)
	notes_panel.hide()
	_build_leaves()

func _panel(rect: Array) -> PanelContainer:
	var panel := UI.panel()
	overlay_root.add_child(panel)
	_place(panel,rect)
	return panel

func _box(parent: Control) -> VBoxContainer:
	var margin := UI.margin(int(config.layout.panel_margin))
	parent.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",int(config.layout.gap))
	margin.add_child(box)
	return box

func _build_new_panel() -> void:
	new_panel = _panel(config.layout.new_panel_rect)
	var box := _box(new_panel)
	box.add_child(UI.label(str(config.copy.name_prompt),int(config.layout.body_font)))
	new_name = LineEdit.new()
	new_name.name = "TitleNewName"
	new_name.text = str(config.copy.default_name)
	new_name.max_length = int(config.layout.name_length)
	new_name.custom_minimum_size.y = float(config.layout.button_height)
	box.add_child(new_name)
	new_submit = UI.button(str(config.copy.create),func():
		if not request_pending: new_requested.emit(new_name.text))
	new_submit.name = "TitleCreate"
	box.add_child(new_submit)
	new_cancel = UI.button(str(config.copy.cancel),func():
		if request_pending: return
		host.cancel_ui_new_game()
		new_panel.hide()
		refresh_continue())
	box.add_child(new_cancel)
	new_panel.hide()

func _activate(id: String) -> void:
	if request_pending or entering or new_panel.visible or credits_panel.visible: return
	match id:
		"continue": continue_requested.emit()
		"new":
			var pending: Dictionary = host.ui_new_game_intent()
			new_name.text = str(pending.get("name",config.copy.default_name))
			new_name.editable = pending.is_empty()
			new_submit.text = str(config.copy.create if pending.is_empty() else config.copy.retry)
			new_panel.show()
			refresh_continue()
			if not pending.is_empty(): new_submit.grab_focus()
			else: new_name.grab_focus()
		"settings": settings_requested.emit()
		"credits":
			credits_panel.show()
			refresh_continue()

func refresh_continue() -> void:
	if config.is_empty() or not buttons.has("continue"): return
	var entries: Array = SaveService.list_saves()
	var blocked: bool = request_pending or entering or new_panel.visible or credits_panel.visible
	for button: Button in buttons.values(): button.disabled = blocked
	buttons["continue"].disabled = blocked or not entries.any(func(row: Dictionary) -> bool: return row.get("valid",false) or row.get("backup_available",false))
	buttons["continue"].tooltip_text = str(config.copy.no_saves) if buttons["continue"].disabled else str(config.menu[0].tooltip)

func set_request_pending(value: bool, message: String = "") -> void:
	request_pending = value
	new_name.editable = false if value or not host.ui_new_game_intent().is_empty() else true
	new_submit.disabled = value
	new_cancel.disabled = value
	for button: Button in buttons.values(): button.disabled = value
	status.text = str(config.copy.saving) if value else message
	if not value:
		new_submit.text = str(config.copy.retry) if not host.ui_new_game_intent().is_empty() else str(config.copy.create)
		refresh_continue()

func _set_highlight(id: String, enabled: bool, focus: bool) -> void:
	if focus: _focused[id] = enabled
	else: _hovered[id] = enabled
	if light_tween != null and light_tween.is_running(): light_tween.kill()
	var lit := ["continue","new"].any(func(key: String) -> bool: return not buttons[key].disabled and (_hovered.get(key,false) or _focused.get(key,false)))
	light_tween = create_tween()
	light_tween.tween_property(window_glow,"modulate:a",float(config.geometry.window_light.strength) if lit else 0.0,float(config.motion.light_seconds))

func _build_leaves() -> void:
	var texture := _texture(str(config.assets.leaf))
	if texture == null: return
	var leaves: Dictionary = config.motion.leaves
	_leaves = CPUParticles2D.new()
	_leaves.name = "TitleActualLeafSprites"
	_leaves.texture = texture
	_leaves.amount = int(leaves.amount)
	_leaves.lifetime = float(leaves.lifetime)
	_leaves.local_coords = true
	_leaves.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_leaves.emission_rect_extents = Vector2(leaves.rect[2],leaves.rect[3])*0.5
	_leaves.position = Vector2(leaves.rect[0],leaves.rect[1])+_leaves.emission_rect_extents
	_leaves.gravity = Vector2(leaves.gravity[0],leaves.gravity[1])
	_leaves.scale_amount_min = float(leaves.scale)
	_leaves.scale_amount_max = float(leaves.scale)
	art_root.add_child(_leaves)

func _process(delta: float) -> void:
	if config.is_empty() or not visible: return
	_time += delta
	var reduced: bool = is_instance_valid(_wind) and _wind.reduced_motion == true
	for id: String in _springs:
		var hovered: bool = _hovered.get(id,false) or _focused.get(id,false)
		var factor := float(config.motion.reduced_hover_factor) if reduced else 1.0
		var wind: float = _wind.get_wind(buttons[id].position.x/float(config.canvas[0]),false) if is_instance_valid(_wind) else 0.0
		var angle: float = _springs[id].step(delta,wind*float(config.motion.wind_torque))
		if hovered: angle += sin(_time*float(config.motion.hover_frequency))*float(config.motion.hover_degrees)*factor
		buttons[id].rotation_degrees = clampf(angle,-float(config.motion.hover_degrees),float(config.motion.hover_degrees))
	if is_instance_valid(_leaves):
		_leaves.emitting = not reduced and not entering
		_leaves.visible = not reduced
		var wind: float = _wind.get_wind(0.5,false) if is_instance_valid(_wind) else 0.0
		_leaves.initial_velocity_min = absf(wind)*float(config.motion.leaves.speed)
		_leaves.initial_velocity_max = _leaves.initial_velocity_min

func _layout() -> void:
	if config.is_empty() or size.x <= 0 or size.y <= 0: return
	var native := Vector2(config.canvas[0],config.canvas[1])
	var fitted: Rect2 = Art.cover_rect(size,native)
	for node: Control in [art_root,overlay_root]:
		node.position = fitted.position
		node.size = native
		node.scale = Vector2.ONE*(fitted.size.x/native.x)

func native_point(point: Vector2, native_size: Array, source_crop: Array) -> Vector2:
	var crop: Array = source_crop if not source_crop.is_empty() else [0,0,native_size[0],native_size[1]]
	var background := (point-Vector2(crop[0],crop[1]))/Vector2(crop[2]-crop[0],crop[3]-crop[1])*Vector2(config.geometry.background_size[0],config.geometry.background_size[1])
	var logical := Geometry.logical_point(background,config.geometry,config.canvas)
	return art_root.position+logical*art_root.scale

func native_scale(native_size: Array, source_crop: Array) -> float:
	return native_point(Vector2.RIGHT,native_size,source_crop).x-native_point(Vector2.ZERO,native_size,source_crop).x

func finish_entry(result: Dictionary, is_new: bool, command_id: String) -> void:
	if not result.get("success",false) or entering: return
	entering = true
	new_panel.hide()
	credits_panel.hide()
	for button: Button in buttons.values(): button.disabled = true
	var had_title := visible and art_root.visible
	show()
	host.set_title_blocking(true)
	if had_title:
		var reduced: bool = is_instance_valid(_wind) and _wind.reduced_motion == true
		var seconds := float(config.motion.reduced_fade_seconds if reduced else config.motion.zoom_seconds)
		var factor := float(config.motion.reduced_zoom_scale if reduced else config.motion.zoom_scale)
		var door: Array = config.geometry.door_center
		var center := Geometry.logical_point(Vector2(door[0],door[1]),config.geometry,config.canvas)
		art_root.pivot_offset = center
		transition = create_tween()
		transition.tween_property(art_root,"scale",art_root.scale*factor,seconds)
		transition.parallel().tween_property(art_root,"modulate:a",0.0,float(config.motion.reduced_fade_seconds if reduced else config.motion.fade_seconds))
		await transition.finished
	if not result.get("replayed",false):
		if not host.play_title_entry_cue(command_id): status.text = str(config.copy.entry_audio_missing)
	art_root.hide()
	if is_instance_valid(motion_controller): motion_controller.set_active(false)
	if is_instance_valid(_leaves): _leaves.emitting = false
	if is_new:
		# This getter is read only after Main's successful awaited save result.
		var public: Dictionary = GameState.story_view() if GameState.has_method("story_view") else {}
		var first: Array = public.get("notes",[]).filter(func(row: Dictionary) -> bool: return row.get("page_number") == 1 and row.get("unlocked",false) and row.get("text") is String)
		if not first.is_empty():
			opening_notes.set_view(public,str(GameState.player_snapshot().get("save_id","")))
			opening_notes.select_page(str(first[0].id))
			awaiting_note = true
			notes_panel.show()
			opening_notes.body.grab_focus()
			return
		host.show_notice(str(config.copy.notes_unavailable))
	_close_opening()

func _close_opening() -> void:
	if not entering: return
	awaiting_note = false
	notes_panel.hide()
	entering = false
	hide()
	host.set_title_blocking(false)
	entry_closed.emit()

func dismiss_direct() -> void:
	if transition != null and transition.is_running(): transition.kill()
	entering = false
	awaiting_note = false
	if is_instance_valid(motion_controller): motion_controller.set_active(false)
	if is_instance_valid(_leaves): _leaves.emitting = false
	hide()

func shutdown_async() -> bool:
	set_process(false)
	if transition != null and transition.is_running(): transition.kill()
	if light_tween != null and light_tween.is_running(): light_tween.kill()
	if is_instance_valid(_leaves): _leaves.emitting = false
	if is_instance_valid(motion_controller): return await motion_controller.shutdown_async()
	return true

func _exit_tree() -> void:
	if transition != null and transition.is_running(): transition.kill()
	if light_tween != null and light_tween.is_running(): light_tween.kill()

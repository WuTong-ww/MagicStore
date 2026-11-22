extends Node
## Presentation only. Backgrounds, committed inventory and scene fade stay owned by their producers.
const Wind = preload("res://scripts/presentation/wind_field.gd")
const Spring = preload("res://scripts/presentation/damped_spring.gd")
const Sway = preload("res://shaders/scene_sway.gdshader")
const Flow = preload("res://shaders/scene_flow.gdshader")
const AudioSettings = preload("res://scripts/audio/shop_audio.gd")

var wind_source: Node
var diagnostics: Array[Dictionary] = []
var motion_time_seconds := 0.0
var cpu_update_usec := 0
var chime_play_count := 0
var shelf_states: Dictionary = {}
var _scene: Control
var _scene_config: Dictionary = {}
var _settings: Dictionary = {}
var _layers: Dictionary = {}
var _particles: Array[CPUParticles2D] = []
var _shelf: Control
var _active := true
var _paused := false
var _reduced := false
var _seen_events: Dictionary = {}
var _last_transition: Array = []
var _chime_player: AudioStreamPlayer
var _chime_playbacks: Array[WeakRef] = []

func bind(scene_visual: Control, scene_config: Dictionary, settings: Dictionary) -> void:
	_detach()
	diagnostics.clear()
	_scene = scene_visual
	_scene_config = scene_config.duplicate(true)
	if scene_config.get("scenes") is Dictionary:
		_scene_config = scene_config.scenes.get(str(scene_visual.get("scene_id")),{}).duplicate(true)
	_settings = settings.duplicate(true) if Wind.settings_valid(settings) else {}
	motion_time_seconds = 0.0
	chime_play_count = 0
	_seen_events.clear()
	_last_transition.clear()
	if _settings.is_empty():
		_diagnostic("settings","invalid_motion")
		return
	if not is_instance_valid(wind_source):
		wind_source = get_node_or_null("/root/WindField")
	if is_instance_valid(wind_source):
		_reduced = wind_source.get("reduced_motion") == true
		if wind_source.has_signal("reduced_motion_changed") and not wind_source.is_connected("reduced_motion_changed",_on_reduced_motion_changed):
			wind_source.connect("reduced_motion_changed",_on_reduced_motion_changed)
	else:
		_reduced = bool(_settings.defaults.reduced_motion)
		_diagnostic("WindField","invalid_motion")
	sync_layers()
	_sync_particles()

func bind_shelf(shelf: Control) -> void:
	if _shelf == shelf:
		return
	_disconnect_shelf()
	_shelf = shelf
	if is_instance_valid(_shelf):
		_shelf.connect("item_added",_on_item_added)
		_shelf.connect("item_removed",_on_item_removed)

func set_active(value: bool) -> void:
	_active = value
	if not value:
		_pause()
	else:
		_sync_particles()

func shutdown() -> void:
	set_active(false)
	set_process(false)
	_stop_chime()

func shutdown_async() -> bool:
	shutdown()
	if _pending_chime_playbacks() == 0:
		return true
	var config: Dictionary = AudioSettings.load_config()
	if config.is_empty():
		return false
	var deadline := Time.get_ticks_usec()+int(float(config.shutdown_timeout_seconds)*1000000.0)
	while _pending_chime_playbacks() > 0 and Time.get_ticks_usec() < deadline:
		for frame: int in range(int(config.shutdown_poll_frames)):
			await get_tree().process_frame
	return _pending_chime_playbacks() == 0

func sync_layers() -> void:
	if not is_instance_valid(_scene) or _settings.is_empty():
		return
	var nodes: Dictionary = _scene.get("layer_nodes")
	var descriptors: Dictionary = _scene_config.get("layers",{})
	var retained: Dictionary = {}
	for id: String in descriptors:
		var descriptor: Dictionary = descriptors[id]
		var motion: Variant = descriptor.get("motion")
		if descriptor.get("legacy",false) or descriptor.get("display","") in ["hidden","cell"] or (motion is Dictionary and motion.get("type") == "static"):
			_diagnostic(id,"static")
			continue
		if not motion is Dictionary or not motion.get("type") in _settings.layer_defaults or not motion.get("parameters") is Dictionary:
			_diagnostic(id,"invalid_motion")
			continue
		var kind: String = motion.type
		var parameters: Dictionary = _settings.layer_defaults[kind].duplicate(true)
		parameters.merge(motion.parameters,true)
		if not _parameters_valid(kind,parameters) or not _native_valid(descriptor.get("native_size")):
			_diagnostic(id,"invalid_motion")
			continue
		var node: TextureRect = nodes.get(id) as TextureRect
		if not is_instance_valid(node) or node.texture == null:
			_diagnostic(id,"waiting_layer")
			continue
		if _layers.has(id) and _layers[id].node == node and _layers[id].kind == kind and _layers[id].parameters == parameters:
			retained[id] = _layers[id]
			retained[id].descriptor = descriptor
			continue
		if _layers.has(id):
			_restore_layer(_layers[id])
		var state := {"node":node,"kind":kind,"parameters":parameters,"descriptor":descriptor,
			"base_rotation":node.rotation_degrees,"base_material":node.material,"indoor":_indoor(id)}
		if kind == "flow" or kind == "sway_shader":
			var material := ShaderMaterial.new()
			material.shader = Flow if kind == "flow" else Sway
			node.material = material
			state.material = material
		if kind == "pendulum" or kind == "sway_shader":
			var spring = Spring.new()
			var physics: Dictionary = parameters if kind == "pendulum" else _settings.layer_defaults.pendulum
			var spring_parameters: Dictionary = _settings.spring.duplicate(true)
			spring_parameters.merge(physics,true)
			if bool(state.indoor):
				spring_parameters.max_angle_degrees = minf(float(spring_parameters.max_angle_degrees),float(_settings.limits.indoor_max_degrees))
			if not spring.configure(spring_parameters):
				_restore_layer(state)
				_diagnostic(id,"invalid_motion")
				continue
			state.spring = spring
		retained[id] = state
	for id: String in _layers:
		if not retained.has(id):
			_restore_layer(_layers[id])
	_layers = retained
	var expected: Array = _settings.get("expected_layers",{}).get(str(_scene.get("scene_id")),[])
	for id: String in expected:
		if not descriptors.has(id):
			_diagnostic(id,"waiting_layer")
	for state: Dictionary in _layers.values():
		_update_layer(state,0.0)

static func _native_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(n: Variant) -> bool:
		return (n is int or n is float) and is_finite(float(n)) and float(n) > 0)

static func _parameters_valid(kind: String, parameters: Dictionary) -> bool:
	for value: Variant in parameters.values():
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0:
			return false
	if kind == "pendulum":
		return float(parameters.k) > 0 and float(parameters.c) > 0 and float(parameters.mass) > 0 and float(parameters.max_angle_degrees) > 0
	return true

func _indoor(id: String) -> bool:
	return str(_scene.get("scene_id")) in _settings.events.indoor_scene_ids and not id in _settings.events.outdoor_layer_ids

func _process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	var started := Time.get_ticks_usec()
	if not is_finite(delta) or delta <= 0 or _settings.is_empty():
		cpu_update_usec = Time.get_ticks_usec()-started
		return
	if not _visible():
		_pause()
		cpu_update_usec = Time.get_ticks_usec()-started
		return
	_paused = false
	motion_time_seconds += delta
	for state: Dictionary in _layers.values():
		_update_layer(state,delta)
	_update_shelf(delta)
	_sync_particles()
	_project_particles()
	cpu_update_usec = Time.get_ticks_usec()-started

func _visible() -> bool:
	return _active and is_instance_valid(_scene) and _scene.is_inside_tree() and _scene.is_visible_in_tree()

func _wind_at(state: Dictionary) -> float:
	if not is_instance_valid(wind_source) or not wind_source.has_method("get_wind"):
		return 0.0
	var descriptor: Dictionary = state.descriptor
	var native: Array = descriptor.native_size
	var pivot: Array = descriptor.get("pivot_px",[0,0])
	return float(wind_source.call("get_wind",clampf(float(pivot[0])/float(native[0]),0.0,1.0),bool(state.indoor)))

func _native_dimensions(state: Dictionary) -> Vector2:
	var descriptor: Dictionary = state.descriptor
	var selected := str(_scene.get("current_period"))
	var transform: Dictionary = descriptor.get("variant_transforms",{}).get(selected,descriptor.get("source_transform",{}))
	var native: Array = transform.get("native_size",descriptor.native_size)
	var crop: Array = transform.get("source_crop",[0,0,native[0],native[1]])
	return Vector2(float(crop[2])-float(crop[0]),float(crop[3])-float(crop[1]))

func _update_layer(state: Dictionary, delta: float) -> void:
	var node: TextureRect = state.node
	if not is_instance_valid(node) or not node.is_visible_in_tree():
		return
	var parameters: Dictionary = state.parameters
	var native := _native_dimensions(state)
	var wind := _wind_at(state)
	if state.kind == "pendulum":
		var angle: float = state.spring.step(delta,wind*float(parameters.wind_torque)) if delta > 0 else state.spring.angle_degrees
		var limit: float = minf(float(parameters.max_angle_degrees),float(_settings.limits.indoor_max_degrees)) if state.indoor else float(parameters.max_angle_degrees)
		node.rotation_degrees = clampf(float(state.base_rotation)+angle,-limit,limit)
		return
	var material: ShaderMaterial = state.material
	material.set_shader_parameter("motion_time",motion_time_seconds)
	material.set_shader_parameter("native_size",native)
	if state.kind == "flow":
		for key: String in ["speed_px_s","distortion_px","noise_frequency","edge_fade_px"]:
			material.set_shader_parameter(key,float(parameters[key]))
		material.set_shader_parameter("motion_factor",float(_settings.reduced.flow_factor) if _reduced else 1.0)
	else:
		var impulse: float = state.spring.step(delta) if delta > 0 else state.spring.angle_degrees
		var max_amplitude := native.x*float(_settings.limits.outdoor_tip_width_fraction)
		if state.indoor:
			max_amplitude = minf(max_amplitude,tan(deg_to_rad(float(_settings.limits.indoor_max_degrees)))*native.y)
		material.set_shader_parameter("amplitude_px",minf(float(parameters.amplitude_px),max_amplitude))
		material.set_shader_parameter("frequency_hz",float(parameters.frequency_hz))
		material.set_shader_parameter("pivot_uv",node.pivot_offset/node.size if node.size.x > 0 and node.size.y > 0 else Vector2.ZERO)
		material.set_shader_parameter("wind",clampf(wind+impulse/float(_settings.layer_defaults.pendulum.max_angle_degrees),-1.0,1.0))

func on_presentation_events(events: Array) -> void:
	if _settings.is_empty():
		return
	for event: Variant in events:
		if not event is Dictionary or not event.get("kind","") in _settings.events.guest_kinds:
			continue
		var identity := str([event.get("save_id"),event.get("state_version"),event.get("sequence"),event.get("arrival_id"),event.get("kind")])
		if _seen_events.has(identity):
			continue
		_seen_events[identity] = true
		while _seen_events.size() > int(_settings.wind.gust_cache_size):
			_seen_events.erase(_seen_events.keys()[0])
		if _visible():
			_kick_layers(_settings.events.chime_layers)
			_play_chime()
	# Main owns the single global WindField.notify_door_event call per event.

func _play_chime() -> void:
	var matching: Array[String] = []
	var expected: Array = _settings.get("expected_layers",{}).get(str(_scene.get("scene_id")),[])
	for id: String in _settings.events.chime_layers:
		var descriptor: Dictionary = _scene_config.get("layers",{}).get(id,{})
		var declared: bool = not descriptor.is_empty() and not descriptor.get("legacy",false) and not descriptor.get("display","") in ["hidden","cell"]
		if _layers.has(id) or declared or id in expected:
			matching.append(id)
	if matching.is_empty():
		return
	var path: String = _settings.events.chime_audio
	var stream: AudioStream
	if not path.is_empty() and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		for id: String in matching:
			_diagnostic(id,"missing_audio")
		return
	if not is_instance_valid(_chime_player):
		_chime_player = AudioStreamPlayer.new()
		_chime_player.name = "WindChimeAudio"
		if AudioServer.get_bus_index("UI") >= 0:
			_chime_player.bus = "UI"
		add_child(_chime_player)
	_remember_chime_playback()
	_chime_player.stream = stream
	_chime_player.play()
	_remember_chime_playback()
	chime_play_count += 1

func _remember_chime_playback() -> void:
	_chime_playbacks = _chime_playbacks.filter(func(handle: WeakRef) -> bool: return handle.get_ref() != null)
	if is_instance_valid(_chime_player) and _chime_player.has_stream_playback():
		_chime_playbacks.append(weakref(_chime_player.get_stream_playback()))

func _pending_chime_playbacks() -> int:
	# Release temporary strong refs inside this synchronous helper before awaiting.
	var pending := 0
	for handle: WeakRef in _chime_playbacks:
		if handle.get_ref() != null:
			pending += 1
	return pending

func _stop_chime() -> void:
	_remember_chime_playback()
	if is_instance_valid(_chime_player):
		_chime_player.stop()
		_chime_player.stream = null
		_chime_player.queue_free()
	_chime_player = null

func on_scene_changed(previous: String, next: String) -> void:
	if _settings.is_empty() or previous.is_empty() or next.is_empty() or previous == next or _last_transition == [previous,next]:
		return
	_last_transition = [previous,next]
	if _settings.events.consultation_scene in [previous,next] and _visible():
		_kick_layers(_settings.events.curtain_layers)

func _kick_layers(ids: Array) -> void:
	var amplitude := float(_settings.layer_defaults.pendulum.event_kick_degrees)*_event_factor()
	for id: String in ids:
		if _layers.has(id) and _layers[id].has("spring"):
			_layers[id].spring.kick_degrees(amplitude)

func _event_factor() -> float:
	return float(_settings.reduced.event_factor) if _reduced else 1.0

func _on_item_added(id: String, _quantity: int, node: Node2D) -> void:
	if not _visible() or not is_instance_valid(_shelf) or not _shelf.is_visible_in_tree() or not is_instance_valid(node):
		return
	var placement: Dictionary = _shelf.call("item_placement",id)
	if placement.is_empty():
		return
	var state := _shelf_state(id)
	state.drop.reset(-float(_settings.shelf.drop_px)*_event_factor())
	_apply_shelf_pose(id,state)
	_kick_neighbors(id,placement)

func _on_item_removed(id: String, _quantity: int, _node: Node2D) -> void:
	if not is_instance_valid(_shelf):
		return
	var placement: Dictionary = _shelf.call("item_placement",id)
	shelf_states.erase(id)
	if is_instance_valid(_shelf.call("get_item_node",id)):
		_shelf.call("set_item_motion",id,Vector2.ZERO,0.0)
	if _visible() and _shelf.is_visible_in_tree() and not placement.is_empty():
		_kick_neighbors(id,placement)

func _shelf_state(id: String) -> Dictionary:
	if not shelf_states.has(id):
		var drop = Spring.new()
		var pendulum = Spring.new()
		var drop_parameters: Dictionary = _settings.spring.duplicate(true)
		drop_parameters.merge(_settings.shelf.drop,true)
		var angle_parameters: Dictionary = _settings.spring.duplicate(true)
		angle_parameters.merge(_settings.shelf.pendulum,true)
		drop.configure(drop_parameters)
		pendulum.configure(angle_parameters)
		shelf_states[id] = {"drop":drop,"pendulum":pendulum}
	return shelf_states[id]

func _kick_neighbors(id: String, placement: Dictionary) -> void:
	var neighbors: Array[Dictionary] = []
	for entry: Dictionary in _shelf.get("layout_result").get("entries",[]):
		if entry.item_id != id and entry.shelf_index == placement.shelf_index:
			neighbors.append(entry)
	neighbors.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var da: float = absf(a.pivot.x-placement.pivot.x)
		var db: float = absf(b.pivot.x-placement.pivot.x)
		return a.item_id < b.item_id if is_equal_approx(da,db) else da < db)
	for index: int in range(mini(neighbors.size(),int(_settings.shelf.neighbor_count))):
		var neighbor: Dictionary = neighbors[index]
		var state := _shelf_state(neighbor.item_id)
		var direction := -1.0 if neighbor.pivot.x < placement.pivot.x else 1.0
		state.pendulum.kick_degrees(direction*float(_settings.shelf.neighbor_degrees)*_event_factor())
		_apply_shelf_pose(neighbor.item_id,state)

func _update_shelf(delta: float) -> void:
	if not is_instance_valid(_shelf) or not _shelf.is_visible_in_tree():
		_clear_shelf_states()
		return
	for id: String in shelf_states.keys():
		if not is_instance_valid(_shelf.call("get_item_node",id)):
			shelf_states.erase(id)
			continue
		var state: Dictionary = shelf_states[id]
		state.drop.step(delta)
		state.pendulum.step(delta)
		_apply_shelf_pose(id,state)

func _apply_shelf_pose(id: String, state: Dictionary) -> void:
	var placement: Dictionary = _shelf.call("item_placement",id)
	if placement.is_empty():
		return
	var base := float(placement.rotation_degrees)
	var limit := minf(float(_settings.shelf.max_total_degrees),float(_settings.limits.indoor_max_degrees))
	var angle := clampf(base+float(state.pendulum.angle_degrees),-limit,limit)-base
	_shelf.call("set_item_motion",id,Vector2(0,float(state.drop.angle_degrees)),angle)

func _clear_shelf_states() -> void:
	if is_instance_valid(_shelf):
		for id: String in shelf_states:
			_shelf.call("set_item_motion",id,Vector2.ZERO,0.0)
	shelf_states.clear()

func _on_reduced_motion_changed(value: bool) -> void:
	if value and not _reduced and not _settings.is_empty():
		var factor := float(_settings.reduced.event_factor)
		for id: String in shelf_states:
			var state: Dictionary = shelf_states[id]
			state.drop.reset(float(state.drop.angle_degrees)*factor,float(state.drop.velocity_degrees)*factor)
			state.pendulum.reset(float(state.pendulum.angle_degrees)*factor,float(state.pendulum.velocity_degrees)*factor)
			_apply_shelf_pose(id,state)
		for state: Dictionary in _layers.values():
			if state.has("spring"):
				state.spring.reset(float(state.spring.angle_degrees)*factor,float(state.spring.velocity_degrees)*factor)
				_update_layer(state,0.0)
	_reduced = value
	if value:
		_clear_particles()
	else:
		_sync_particles()

func particle_count() -> int:
	var total := 0
	for emitter: CPUParticles2D in _particles:
		if is_instance_valid(emitter):
			total += emitter.amount
	return total

func _sync_particles() -> void:
	if _settings.is_empty() or not _visible() or _reduced:
		_clear_particles()
		return
	if not _particles.is_empty():
		return
	var regions: Array = _settings.particles.regions.get(str(_scene.get("scene_id")),[])
	if regions.is_empty():
		_diagnostic("particles","missing_region")
		return
	var remaining := int(_settings.particles.max_alive)
	for region: Dictionary in regions:
		var amount := mini(int(region.amount),remaining)
		if amount <= 0:
			break
		var emitter := CPUParticles2D.new()
		emitter.name = "MotionParticles_"+str(_particles.size())
		emitter.amount = amount
		emitter.lifetime = float(region.lifetime_seconds)
		emitter.local_coords = true
		emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emitter.emission_rect_extents = Vector2(region.rect[2],region.rect[3])*0.5
		var drift: Array = region.get("drift_px_s",[0,0])
		var velocity := Vector2(drift[0],drift[1])
		emitter.direction = velocity.normalized() if not velocity.is_zero_approx() else Vector2.RIGHT
		emitter.initial_velocity_min = velocity.length()
		emitter.initial_velocity_max = velocity.length()
		var gravity: Array = region.get("gravity_px_s2",[0,0])
		emitter.gravity = Vector2(gravity[0],gravity[1])
		emitter.color = Color(region.color)
		emitter.color.a *= float(region.get("opacity",1.0))
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color.WHITE,Color(1,1,1,0)])
		var texture := GradientTexture2D.new()
		texture.width = maxi(2,ceili(float(region.size_px)))
		texture.height = texture.width
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5,0.5)
		texture.fill_to = Vector2(1.0,0.5)
		texture.gradient = gradient
		emitter.texture = texture
		emitter.scale_amount_min = float(region.size_px)/float(texture.width)
		emitter.scale_amount_max = emitter.scale_amount_min
		emitter.set_meta("region",region.duplicate(true))
		add_child(emitter)
		_particles.append(emitter)
		remaining -= amount
	_project_particles()

func _project_particles() -> void:
	for emitter: CPUParticles2D in _particles:
		var region: Dictionary = emitter.get_meta("region")
		var rectangle: Array = region.rect
		var center := Vector2(float(rectangle[0])+float(rectangle[2])*0.5,float(rectangle[1])+float(rectangle[3])*0.5)
		emitter.position = _scene.call("native_point",center,region.native_size,region.source_crop)
		emitter.scale = Vector2.ONE*float(_scene.call("native_scale",region.native_size,region.source_crop))

func _clear_particles() -> void:
	for emitter: CPUParticles2D in _particles:
		if is_instance_valid(emitter):
			emitter.emitting = false
			emitter.free()
	_particles.clear()

func _pause() -> void:
	if _paused:
		return
	_paused = true
	_clear_particles()
	_clear_shelf_states()
	for state: Dictionary in _layers.values():
		if state.has("spring"):
			state.spring.reset()
		if is_instance_valid(state.node):
			state.node.rotation_degrees = state.base_rotation

func _restore_layer(state: Dictionary) -> void:
	if is_instance_valid(state.node):
		state.node.material = state.base_material
		state.node.rotation_degrees = state.base_rotation

func _diagnostic(id: String, status: String) -> void:
	for row: Dictionary in diagnostics:
		if row.layer_id == id and row.status == status:
			return
	diagnostics.append({"scene_id":str(_scene.get("scene_id")) if is_instance_valid(_scene) else "",
		"layer_id":id,"status":status,"message":_settings.get("diagnostics",{}).get(status,"")})

func _disconnect_shelf() -> void:
	_clear_shelf_states()
	if is_instance_valid(_shelf):
		if _shelf.is_connected("item_added",_on_item_added):
			_shelf.disconnect("item_added",_on_item_added)
		if _shelf.is_connected("item_removed",_on_item_removed):
			_shelf.disconnect("item_removed",_on_item_removed)
	_shelf = null

func _detach() -> void:
	_stop_chime()
	_disconnect_shelf()
	_clear_particles()
	for state: Dictionary in _layers.values():
		_restore_layer(state)
	_layers.clear()
	if is_instance_valid(wind_source) and wind_source.is_connected("reduced_motion_changed",_on_reduced_motion_changed):
		wind_source.disconnect("reduced_motion_changed",_on_reduced_motion_changed)

func _exit_tree() -> void:
	_detach()
	_scene = null
	wind_source = null

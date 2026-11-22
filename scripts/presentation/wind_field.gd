extends Node
## Presentation-only clock/preferences. No GameState access or global RNG use.
const SETTINGS_PATH := "res://data/ui/motion.json"
const Spring = preload("res://scripts/presentation/damped_spring.gd")
signal reduced_motion_changed(value: bool)
var settings: Dictionary = {}
## May be overridden before ready to isolate preferences in a test user directory.
var settings_path := ""
var time_seconds := 0.0
var reduced_motion := false
var weather := ""
var _door_started := -INF
var _door_events: Dictionary = {}
var _noise: FastNoiseLite
var _noise_seed := 0
var _gust_cache: Dictionary = {}

static func _number(value: Variant, minimum: float = 0, maximum: float = INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func _positive(value: Variant) -> bool:
	return _number(value) and value > 0

static func _integer(value: Variant, minimum: int = 0) -> bool:
	return _number(value,minimum) and value == floor(float(value))

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _strings(value: Variant) -> bool:
	if not value is Array:
		return false
	var found: Array = []
	for entry: Variant in value:
		if not _text(entry) or found.has(entry):
			return false
		found.append(entry)
	return true

static func _pair(value: Variant, positive: bool = false) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and value[1] >= value[0] and (not positive or value[0] > 0)

static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0],-INF) and _number(value[1],-INF)

static func _finite_tree(value: Variant) -> bool:
	if value is float:
		return is_finite(value)
	if value is Dictionary:
		for entry: Variant in value.values():
			if not _finite_tree(entry):
				return false
	if value is Array:
		for entry: Variant in value:
			if not _finite_tree(entry):
				return false
	return true

static func _spring_parameters(parameters: Dictionary, simulation: Dictionary) -> bool:
	var combined := parameters.duplicate(true)
	combined.merge(simulation,true)
	return Spring.parameters_valid(combined)

static func settings_valid(data: Dictionary) -> bool:
	if not data.get("labels") is Dictionary or not _text(data.labels.get("settings_description")):
		return false
	if data.get("version") != 1 or not _finite_tree(data):
		return false
	for key: String in ["defaults","labels","wind","reduced","spring","limits","layer_defaults","shelf","particles","events","diagnostics"]:
		if not data.get(key) is Dictionary:
			return false
	var path: Variant = data.get("settings_path")
	if not path is String or not path.begins_with("user://") or not path.ends_with(".cfg"):
		return false
	for part: String in path.trim_prefix("user://").split("/",true):
		if part.is_empty() or part in [".",".."] or part.contains("\\") or part.contains(":"):
			return false
	if not data.defaults.get("reduced_motion") is bool or not _integer(data.get("seed")):
		return false
	for key: String in ["reduced_motion","save_failed"]:
		if not _text(data.labels.get(key)):
			return false
	var wind: Dictionary = data.wind
	for key: String in ["base","noise_amplitude","gust_jitter_seconds","propagation_seconds"]:
		if not _number(wind.get(key)):
			return false
	for key: String in ["noise_frequency","gust_mean_seconds","door_duration_seconds","rain_multiplier"]:
		if not _positive(wind.get(key)):
			return false
	if not _pair(wind.get("gust_duration_seconds"),true) or not _pair(wind.get("gust_strength")) or not _integer(wind.get("gust_cache_size"),1) or not _text(wind.get("rain_weather")):
		return false
	# One independently jittered event per mean-duration slot: intervals telescope
	# to the configured mean. Adjacent events cannot overlap with these bounds.
	if wind.gust_jitter_seconds+wind.gust_duration_seconds[1] >= wind.gust_mean_seconds:
		return false
	if not _number(wind.get("indoor_factor"),0,1) or not _number(wind.get("door_factor"),wind.indoor_factor,1):
		return false
	for key: String in ["wind_factor","flow_factor","event_factor"]:
		if not _number(data.reduced.get(key),0,1):
			return false
	var simulation: Dictionary = data.spring
	if not _positive(simulation.get("fixed_step_seconds")) or not _integer(simulation.get("max_substeps"),1):
		return false
	for key: String in ["indoor_max_degrees","outdoor_tip_width_fraction","settle_degrees","settle_seconds"]:
		if not _positive(data.limits.get(key)):
			return false
	var layers: Dictionary = data.layer_defaults
	for key: String in ["sway_shader","pendulum","flow"]:
		if not layers.get(key) is Dictionary:
			return false
	if not _number(layers.sway_shader.get("amplitude_px")) or not _positive(layers.sway_shader.get("frequency_hz")):
		return false
	if not _spring_parameters(layers.pendulum,simulation) or layers.pendulum.max_angle_degrees > data.limits.indoor_max_degrees:
		return false
	for key: String in ["wind_torque","event_kick_degrees"]:
		if not _number(layers.pendulum.get(key)):
			return false
	for key: String in ["speed_px_s","distortion_px","noise_frequency","edge_fade_px"]:
		if not _number(layers.flow.get(key)):
			return false
	var shelf: Dictionary = data.shelf
	if not shelf.get("drop") is Dictionary or not shelf.get("pendulum") is Dictionary or not _spring_parameters(shelf.drop,simulation) or not _spring_parameters(shelf.pendulum,simulation):
		return false
	if not _positive(shelf.get("drop_px")) or not _number(shelf.get("neighbor_degrees")) or not _integer(shelf.get("neighbor_count"),1) or not _positive(shelf.get("max_total_degrees")):
		return false
	if shelf.max_total_degrees > data.limits.indoor_max_degrees or shelf.pendulum.max_angle_degrees > shelf.max_total_degrees or shelf.neighbor_degrees > shelf.pendulum.max_angle_degrees:
		return false
	if not _particles_valid(data.particles):
		return false
	for key: String in ["guest_kinds","indoor_scene_ids","outdoor_layer_ids","curtain_layers","chime_layers"]:
		if not _strings(data.events.get(key)):
			return false
	if data.events.guest_kinds.is_empty():
		return false
	if not _text(data.events.get("consultation_scene")) or not data.events.get("chime_audio") is String:
		return false
	if not data.events.chime_audio.is_empty() and not (data.events.chime_audio.begins_with("res://assets/audio/") and data.events.chime_audio.ends_with(".ogg") and not ".." in data.events.chime_audio):
		return false
	for key: String in ["static","waiting_layer","invalid_motion","missing_audio","missing_region"]:
		if not _text(data.diagnostics.get(key)):
			return false
	if data.has("expected_layers"):
		if not data.expected_layers is Dictionary:
			return false
		for scene: Variant in data.expected_layers:
			if not _text(scene) or not _strings(data.expected_layers[scene]):
				return false
	return true

static func _particles_valid(particles: Dictionary) -> bool:
	if not _integer(particles.get("max_alive")) or not particles.get("regions") is Dictionary:
		return false
	for scene: Variant in particles.regions:
		if not _text(scene) or not particles.regions[scene] is Array:
			return false
		var amount := 0
		for region: Variant in particles.regions[scene]:
			if not region is Dictionary or not _vector(region.get("native_size")) or not _integer(region.native_size[0],1) or not _integer(region.native_size[1],1):
				return false
			var native: Array = region.native_size
			var crop: Variant = region.get("source_crop")
			var rectangle: Variant = region.get("rect")
			if not crop is Array or crop.size() != 4 or not rectangle is Array or rectangle.size() != 4:
				return false
			for axis: int in range(4):
				if not _number(crop[axis]) or not _number(rectangle[axis]):
					return false
			if crop[2] <= crop[0] or crop[3] <= crop[1] or crop[2] > native[0] or crop[3] > native[1] or rectangle[2] <= 0 or rectangle[3] <= 0:
				return false
			if rectangle[0] < crop[0] or rectangle[1] < crop[1] or rectangle[0]+rectangle[2] > crop[2] or rectangle[1]+rectangle[3] > crop[3]:
				return false
			if not _integer(region.get("amount"),1) or not _positive(region.get("lifetime_seconds")) or not _positive(region.get("size_px")):
				return false
			if not region.get("color") is String or not Color.html_is_valid(region.color):
				return false
			for key: String in ["gravity_px_s2","drift_px_s"]:
				if region.has(key) and not _vector(region[key]):
					return false
			if region.has("opacity") and not _number(region.opacity,0,1):
				return false
			amount += int(region.amount)
		if amount > particles.max_alive:
			return false
	return true

static func load_settings() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	return parsed if parsed is Dictionary and settings_valid(parsed) else {}

func _ready() -> void:
	settings = load_settings() if settings.is_empty() else (settings.duplicate(true) if settings_valid(settings) else {})
	if settings.is_empty():
		set_process(false)
		return
	if settings_path.is_empty():
		settings_path = settings.settings_path
	reduced_motion = settings.defaults.reduced_motion
	var saved := ConfigFile.new()
	if saved.load(settings_path) == OK:
		var value: Variant = saved.get_value("motion","reduced_motion",reduced_motion)
		if value is bool:
			reduced_motion = value

func _process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	if is_finite(delta) and delta > 0 and is_finite(time_seconds+delta):
		time_seconds += delta

func _packet(seed_value: int, slot: int) -> Dictionary:
	var key := str(seed_value)+"/"+str(slot)
	if _gust_cache.has(key):
		return _gust_cache[key]
	var random := RandomNumberGenerator.new()
	random.seed = key.hash()
	var wind: Dictionary = settings.wind
	var packet := {"start":slot*float(wind.gust_mean_seconds)+random.randf_range(0,float(wind.gust_jitter_seconds)),
		"duration":random.randf_range(float(wind.gust_duration_seconds[0]),float(wind.gust_duration_seconds[1])),
		"strength":random.randf_range(float(wind.gust_strength[0]),float(wind.gust_strength[1]))}
	if _gust_cache.size() >= int(wind.gust_cache_size):
		_gust_cache.erase(_gust_cache.keys()[0])
	_gust_cache[key] = packet
	return packet

## Raw deterministic wind, independent of the mutable instance clock/preference.
## One jittered event per slot has long-run mean interval gust_mean_seconds.
func sample_at(seed_value: int, time_s: float, x_normalized: float, indoor: bool, door: float = 0, weather_id: String = "") -> float:
	if settings.is_empty() or not is_finite(time_s) or time_s < 0 or not is_finite(x_normalized) or not is_finite(door):
		return 0
	var wind: Dictionary = settings.wind
	var local_time := time_s-clampf(x_normalized,0,1)*float(wind.propagation_seconds)
	if _noise == null or _noise_seed != seed_value:
		_noise = FastNoiseLite.new()
		_noise.seed = seed_value
		_noise_seed = seed_value
	_noise.frequency = float(wind.noise_frequency)
	var noise := _noise.get_noise_1d(local_time)*float(wind.noise_amplitude)
	var gust := 0.0
	if local_time >= 0:
		var slot := int(floor(local_time/float(wind.gust_mean_seconds)))
		for candidate: int in range(maxi(0,slot-1),slot+1):
			var packet := _packet(seed_value,candidate)
			var phase := (local_time-float(packet.start))/float(packet.duration)
			if phase > 0 and phase < 1:
				gust += float(packet.strength)*(1.0-cos(TAU*phase))*0.5
	var rain := float(wind.rain_multiplier) if weather_id == wind.rain_weather else 1.0
	var value := float(wind.base)*rain+noise+gust
	return value*lerpf(float(wind.indoor_factor),float(wind.door_factor),clampf(door,0,1)) if indoor else value

func get_wind(x_normalized: float, indoor: bool = true) -> float:
	if settings.is_empty():
		return 0
	var duration := float(settings.wind.door_duration_seconds)
	var age := time_seconds-_door_started
	var door := (1.0+cos(PI*age/duration))*0.5 if age >= 0 and age < duration else 0.0
	var value := sample_at(int(settings.seed),time_seconds,x_normalized,indoor,door,weather)
	return value*float(settings.reduced.wind_factor) if reduced_motion else value

func notify_door_event(event_id: String) -> bool:
	if event_id.is_empty() or _door_events.has(event_id):
		return false
	_door_events[event_id] = true
	_door_started = time_seconds
	return true

func set_weather(value: String) -> void:
	weather = value

func set_reduced_motion(value: bool) -> bool:
	if settings.is_empty():
		return false
	if value == reduced_motion:
		return true
	var saved := ConfigFile.new()
	var loaded := saved.load(settings_path)
	if loaded != OK and loaded != ERR_FILE_NOT_FOUND:
		return false
	saved.set_value("motion","reduced_motion",value)
	if saved.save(settings_path) != OK:
		return false
	reduced_motion = value
	reduced_motion_changed.emit(value)
	return true

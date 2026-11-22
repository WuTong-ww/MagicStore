extends SceneTree
## Real wall-clock benchmark, never a Movie Maker/fixed-FPS performance claim.
## This only displays independent read-only fixtures; it performs no game action.
const CONFIG_PATH := "res://data/art/motion_validation.json"
const SceneArt = preload("res://scripts/shop/scene_visual.gd")
const Shelf = preload("res://scripts/shop/shelf_view.gd")
var settings: Dictionary = {}
var checks := 0
var failures := 0
var rows: Array[Dictionary] = []
var measurements: Array[Dictionary] = []
var wind: Node
var _wind_original: Dictionary = {}
var _window_original: Dictionary = {}
var _fixture_version := 1
var _original_snapshot: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

static func _number(value: Variant, minimum: float = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum

static func _positive(value: Variant) -> bool:
	return _number(value) and value > 0

static func _integer(value: Variant, minimum: int = 1) -> bool:
	return _number(value,minimum) and value == floor(float(value))

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _safe_path(value: Variant, prefix: String, extension: String = "") -> bool:
	if not _text(value) or not value.begins_with(prefix) or not value.ends_with(extension):
		return false
	if not prefix.ends_with("/") and value != prefix and not value.begins_with(prefix+"/"):
		return false
	for part: String in value.trim_prefix("res://").split("/",true):
		if part.is_empty() or part in [".",".."] or part.contains("\\") or part.contains(":"):
			return false
	return true

static func validation_valid(data: Dictionary) -> bool:
	if data.get("version") != 1 or not data.get("window") is Dictionary or not data.get("performance") is Dictionary or not data.get("movie") is Dictionary:
		return false
	if not _integer(data.window.get("width")) or not _integer(data.window.get("height")) or not data.window.get("borderless") is bool:
		return false
	var perf: Dictionary = data.performance
	for key: String in ["warmup_frames_per_scene","sample_frames_per_scene","settle_frames","shelf_stimulus_interval_frames"]:
		if not _integer(perf.get(key)):
			return false
	for key: String in ["fps_target","motion_cpu_limit_ms"]:
		if not _positive(perf.get(key)):
			return false
	if not perf.get("vsync_enabled") is bool or perf.get("cases") != ["baseline","enabled","reduced"]:
		return false
	for key: String in ["required_rendering_method","required_adapter_contains","required_vendor_contains","fixture_save_id","shelf_stimulus_item"]:
		if not _text(perf.get(key)):
			return false
	if not _integer(perf.get("fixture_clock_minutes"),0) or not _safe_path(perf.get("json_output"),"res://.tools/art/a6/",".json") or not _safe_path(perf.get("csv_output"),"res://.tools/art/a6/",".csv"):
		return false
	if not _safe_path(perf.get("status_output"),"res://.tools/art/a6/",".json") or perf.status_output == perf.json_output:
		return false
	if not perf.get("scenes") is Array or perf.scenes.size() != 2:
		return false
	var kinds: Array = []
	for scene: Variant in perf.scenes:
		if not scene is Dictionary or not _text(scene.get("page")) or not _text(scene.get("scene_id")) or scene.get("kind") not in ["water","shelf"] or kinds.has(scene.kind):
			return false
		kinds.append(scene.kind)
	if not perf.get("inventory_quantities") is Dictionary or perf.inventory_quantities.is_empty() or not perf.inventory_quantities.has(perf.shelf_stimulus_item):
		return false
	for id: Variant in perf.inventory_quantities:
		if not _text(id) or not _integer(perf.inventory_quantities[id]):
			return false
	var quantities: Variant = perf.get("shelf_stimulus_quantities")
	if not quantities is Array or quantities.size() != 2 or not _integer(quantities[0]) or not _integer(quantities[1]) or quantities[0] == quantities[1]:
		return false
	var oracle: Variant = perf.get("statistics_fixture")
	if not oracle is Dictionary or not oracle.get("samples") is Array or oracle.samples.is_empty():
		return false
	for value: Variant in oracle.samples:
		if not _number(value):
			return false
	for key: String in ["mean","p50","p95","p99","max"]:
		if not _number(oracle.get(key)):
			return false
	return _movie_valid(data.movie)

static func _movie_valid(movie: Dictionary) -> bool:
	for key: String in ["fps","frame_count","avi_header_probe_bytes"]:
		if not _integer(movie.get(key)):
			return false
	if not _positive(movie.get("duration_seconds")) or not is_equal_approx(float(movie.frame_count),float(movie.fps)*float(movie.duration_seconds)) or not _integer(movie.get("action_frame"),0) or movie.action_frame >= movie.frame_count or not movie.get("reduced_motion") is bool:
		return false
	if not _integer(movie.get("writer_frame_offset"),0) or movie.writer_frame_offset >= movie.frame_count or movie.action_frame >= movie.frame_count-movie.writer_frame_offset:
		return false
	for key: String in ["capture_directory","save_directory"]:
		if not _safe_path(movie.get(key),".tools/art/a6/"):
			return false
	if not _safe_path(movie.get("compressed_directory"),"docs/screenshots/a6") or not movie.get("modes") is Dictionary or not movie.modes.has(movie.get("default_mode")):
		return false
	for mode: Variant in movie.modes:
		var value: Variant = movie.modes[mode]
		if not _text(mode) or not value is Dictionary or not _text(value.get("page")) or not _text(value.get("basename")) or value.get("action") not in ["guest_arrival","none","procure_item"]:
			return false
		if not value.basename.is_valid_filename():
			return false
	if not movie.get("fixture") is Dictionary or not movie.get("gust") is Dictionary or not movie.get("compression") is Dictionary:
		return false
	for key: String in ["shop_name","arrival_id","npc_id","case_id","stock_item_id"]:
		if not _text(movie.fixture.get(key)):
			return false
	for key: String in ["arrival_after_minutes","schedule_end_after_minutes","wait_minutes","stock_quantity"]:
		if not _integer(movie.fixture.get(key)):
			return false
	if movie.fixture.schedule_end_after_minutes <= movie.fixture.arrival_after_minutes or movie.fixture.wait_minutes < movie.fixture.arrival_after_minutes:
		return false
	if not _integer(movie.gust.get("slot"),0) or not _number(movie.gust.get("lead_seconds")):
		return false
	for key: String in ["video_codec","preset","pixel_format","audio_codec","audio_bitrate"]:
		if not _text(movie.compression.get(key)):
			return false
	if movie.compression.has("windows_transcoder"):
		var fallback: Variant = movie.compression.windows_transcoder
		if not fallback is Dictionary or not fallback.get("enabled") is bool or fallback.get("quality") != "HD1080p" or not _positive(fallback.get("timeout_seconds")) or not _positive(fallback.get("bitrate_budget_fraction")) or fallback.bitrate_budget_fraction >= 1:
			return false
	return _integer(movie.compression.get("crf"),0) and _integer(movie.compression.get("max_public_bytes"))

static func _percentile(sorted: Array[float], quantile: float) -> float:
	var index := (sorted.size()-1)*quantile
	return lerpf(sorted[int(floor(index))],sorted[int(ceil(index))],index-floor(index))

static func statistics(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count":0}
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var total := 0.0
	for value: float in sorted:
		total += value
	return {"count":sorted.size(),"mean":total/sorted.size(),"p50":_percentile(sorted,0.5),"p95":_percentile(sorted,0.95),"p99":_percentile(sorted,0.99),"max":sorted[-1]}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MOTION PERFORMANCE FAIL: "+label)

func _configuration_checks() -> void:
	check(validation_valid(settings),"actual validation JSON is finite and structurally valid")
	if not validation_valid(settings):
		return
	var bad := settings.duplicate(true)
	bad.performance.fps_target = NAN
	check(not validation_valid(bad),"NaN benchmark target rejected")
	bad = settings.duplicate(true); bad.performance.sample_frames_per_scene = 0
	check(not validation_valid(bad),"empty hardware sample rejected")
	bad = settings.duplicate(true); bad.performance.motion_cpu_limit_ms = -1
	check(not validation_valid(bad),"negative dynamic CPU budget rejected")
	bad = settings.duplicate(true); bad.performance.csv_output = "res://.tools/art/a6/../escape.csv"
	check(not validation_valid(bad),"benchmark output cannot traverse out of its evidence directory")
	bad = settings.duplicate(true); bad.window.width = 1920.5
	check(not validation_valid(bad),"fractional output dimensions rejected")
	bad = settings.duplicate(true); bad.movie.frame_count += 1
	check(not validation_valid(bad),"movie frame count must match fps and duration")
	bad = settings.duplicate(true); bad.movie.action_frame = bad.movie.frame_count
	check(not validation_valid(bad),"recorded action must occur within the clip")
	bad = settings.duplicate(true); bad.movie.fixture.wait_minutes = 0
	check(not validation_valid(bad),"movie requires a real positive wait interval")
	bad = settings.duplicate(true); bad.movie.compression.erase("windows_transcoder")
	check(validation_valid(bad),"Windows transcoder block is optional for manual/ffmpeg compatibility")
	if settings.movie.compression.has("windows_transcoder"):
		for mutation: Array in [["enabled","true"],["quality","HD720p"],["timeout_seconds",0],["timeout_seconds",INF],["bitrate_budget_fraction",0],["bitrate_budget_fraction",1]]:
			bad = settings.duplicate(true)
			bad.movie.compression.windows_transcoder[mutation[0]] = mutation[1]
			check(not validation_valid(bad),"invalid optional Windows transcoder setting rejected / "+str(mutation))
	var source: Array[float] = []
	for value: Variant in settings.performance.statistics_fixture.samples:
		source.append(float(value))
	var result := statistics(source)
	for key: String in ["mean","p50","p95","p99","max"]:
		check(is_equal_approx(float(result[key]),float(settings.performance.statistics_fixture[key])),"hand-derived statistical oracle / "+key)
	check(source == settings.performance.statistics_fixture.samples,"statistics cannot reorder the raw samples")

func run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	settings = parsed if parsed is Dictionary else {}
	_configuration_checks()
	if failures > 0:
		_finish()
		return
	var arguments := OS.get_cmdline_args()
	var invalid_mode := OS.has_feature("movie") or Engine.get_write_movie_path() != ""
	for argument: String in arguments:
		invalid_mode = invalid_mode or argument == "--write-movie" or argument.begins_with("--write-movie=") or argument == "--fixed-fps" or argument.begins_with("--fixed-fps=")
	check(not invalid_mode,"real-time benchmark rejects Movie Maker and fixed-FPS simulation")
	if invalid_mode:
		_write_status({"status":"rejected_nonrealtime","hardware_evaluated":false,"passed":false,"measurements":[],"reason":"录像或固定模拟帧率不能作为实机性能证据。"})
		_finish()
		return
	if DisplayServer.get_name() == "headless":
		print("MOTION PERFORMANCE SKIP: headless cannot validate Intel Iris Xe rendering or real frame cadence")
		_write_status({"status":"skipped_headless","hardware_evaluated":false,"passed":null,"measurements":[],"reason":"无图形渲染器，不作实机性能结论。"})
		_finish()
		return
	wind = root.get_node_or_null("WindField")
	var valid_wind := is_instance_valid(wind) and wind.has_method("step") and wind.has_method("get_wind")
	check(valid_wind,"production WindField autoload is available")
	if not valid_wind:
		_write_status({"status":"missing_wind_autoload","hardware_evaluated":false,"passed":false,"measurements":[]})
		_finish()
		return
	_original_snapshot = root.get_node("GameState").player_snapshot()
	_wind_original = {"process":wind.is_processing(),"time":wind.get("time_seconds"),"reduced":wind.get("reduced_motion"),"weather":wind.get("weather")}
	_window_original = {"size":root.size,"scale":root.content_scale_size,"borderless":root.borderless,"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"low_usage":OS.low_processor_usage_mode}
	root.borderless = settings.window.borderless
	root.size = Vector2i(int(settings.window.width),int(settings.window.height))
	root.content_scale_size = root.size
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.performance.vsync_enabled else DisplayServer.VSYNC_DISABLED)
	wind.set_process(false)
	for _frame: int in range(int(settings.performance.settle_frames)):
		await process_frame
	var environment := _environment()
	for mode: String in settings.performance.cases:
		for scene: Dictionary in settings.performance.scenes:
			await _measure(mode,scene)
	check(root.get_node("GameState").player_snapshot() == _original_snapshot,"read-only display benchmark leaves the real game snapshot unchanged")
	var aggregate: Array[Dictionary] = []
	for mode: String in settings.performance.cases:
		aggregate.append(_summarize(mode,"combined",rows.filter(func(row: Dictionary) -> bool: return row.mode == mode)))
	var hardware := bool(environment.target_adapter) and bool(environment.target_renderer) and bool(environment.target_resolution)
	var accepted: bool = hardware and failures == 0 and measurements.size() == settings.performance.cases.size()*settings.performance.scenes.size() and measurements.all(func(result: Dictionary) -> bool: return result.passed) and aggregate.all(func(result: Dictionary) -> bool: return result.passed)
	var report := {"status":"measured","passed":accepted,"hardware_evaluated":true,"environment":environment,
		"configuration":settings.duplicate(true),"criteria":{"fps_target":settings.performance.fps_target,"frame_budget_ms":1000.0/float(settings.performance.fps_target),"motion_cpu_limit_ms":settings.performance.motion_cpu_limit_ms,"frame_gate":"max","motion_cpu_gate":"max"},
		"measurement_scope":{"wall_frame":"Time.get_ticks_usec between actual process-frame boundaries; includes scheduling/render stalls and harness work",
			"motion_cpu":"sum of completed SceneMotion.step counters plus timed original WindField._process invoked manually once per visible frame; automatic Wind process disabled",
			"excluded_motion_cpu":"setup, shelf signal callbacks, A7 relayout, engine dispatch and GPU execution; shelf stimulus wall time reported separately",
			"gpu_time_ms":null,"engine_monitor":"Performance.TIME_PROCESS is auxiliary and may be delayed; never treated as GPU timing",
			"fixture":"S07 actual approved flow and S04 nine independent item IDs; quantity changes are read-only display fixtures, not committed game actions"},
		"measurements":measurements,"cases":aggregate,"row_count":rows.size()}
	_write_outputs(report)
	_restore()
	check(accepted,"actual adapter/resolution and every observed frame/CPU-update satisfy configured budgets")
	_finish()

func _environment() -> Dictionary:
	var adapter := RenderingServer.get_video_adapter_name()
	var vendor := RenderingServer.get_video_adapter_vendor()
	var method := RenderingServer.get_current_rendering_method()
	return {"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"os":OS.get_name(),"processor":OS.get_processor_name(),
		"adapter":adapter,"vendor":vendor,"driver":RenderingServer.get_current_rendering_driver_name(),"api":RenderingServer.get_video_adapter_api_version(),"rendering_method":method,
		"viewport_size":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"window_size":[root.size.x,root.size.y],"window_visible":root.visible,"window_focused":root.has_focus(),"vsync_mode":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,
		"target_adapter":adapter.to_lower().contains(str(settings.performance.required_adapter_contains).to_lower()) and vendor.to_lower().contains(str(settings.performance.required_vendor_contains).to_lower()),
		"target_renderer":method == settings.performance.required_rendering_method,
		"target_resolution":root.size == Vector2i(int(settings.window.width),int(settings.window.height)) and root.get_visible_rect().size == Vector2(float(settings.window.width),float(settings.window.height))}

func _view(quantities: Dictionary) -> Dictionary:
	var batches: Array = []
	for id: String in quantities:
		batches.append({"batch_id":"performance_"+id,"item_id":id,"remaining":quantities[id]})
	return {"items":quantities.duplicate(true),"catalog":JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/catalog.json")),"shop":{"batches":batches}}

func _snapshot(view: Dictionary) -> Dictionary:
	return {"save_id":settings.performance.fixture_save_id,"state_version":_fixture_version,"clock_minutes":settings.performance.fixture_clock_minutes,"player":{"items":view.items.duplicate(true)},"shop":view.shop.duplicate(true)}

func _measure(mode: String, scene: Dictionary) -> void:
	var stage := SceneArt.new()
	stage.name = "Performance_"+str(scene.scene_id)+"_"+mode
	root.add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.cabinet_state = "open"
	stage.setup(str(scene.page))
	check(stage.scene_id == scene.scene_id,"production page maps to requested real scene / "+str(scene.scene_id))
	var controller: Node = stage.get("motion_controller") as Node
	check(is_instance_valid(controller) and controller.has_method("bind_shelf"),"real SceneVisual exposes its bound motion controller / "+str(scene.scene_id))
	if not is_instance_valid(controller):
		stage.queue_free()
		await process_frame
		return
	var shelf: Control
	var quantities: Dictionary = settings.performance.inventory_quantities.duplicate(true)
	if scene.kind == "shelf":
		shelf = Shelf.new()
		stage.add_child(shelf)
		shelf.setup(stage,stage.config)
		var view := _view(quantities)
		shelf.update_inventory(view,_snapshot(view),true)
		controller.call("bind_shelf",shelf)
		for id: String in quantities:
			check(is_instance_valid(shelf.call("get_item_node",id)),"real independent item appears in nine-ID fixture / "+id)
	elif scene.kind == "water":
		var water: TextureRect = stage.layer_nodes.get("water_mask") as TextureRect
		check(is_instance_valid(water) and water.material is ShaderMaterial,"actual S07 water layer has its production flow material")
	wind.time_seconds = 0.0
	wind.set_weather("")
	wind.reduced_motion = mode == "reduced"
	wind.reduced_motion_changed.emit(wind.reduced_motion)
	controller.call("set_active",mode != "baseline")
	controller.set_process(mode != "baseline")
	if mode == "baseline":
		# set_active alone pauses uniforms but leaves the flow GPU material bound.
		# These fixture nodes are discarded after this case; C/Sofa/static art stay intact.
		for id: String in stage.layer_nodes:
			var layer: TextureRect = stage.layer_nodes[id]
			if layer.material is ShaderMaterial and layer.material.shader.resource_path in ["res://shaders/scene_flow.gdshader","res://shaders/scene_sway.gdshader"]:
				layer.material = null
	var sample_rows: Array[Dictionary] = []
	var warmup := int(settings.performance.warmup_frames_per_scene)
	var count := int(settings.performance.sample_frames_per_scene)
	var last := Time.get_ticks_usec()
	var delta := 1.0/float(settings.performance.fps_target)
	var drawn_before := 0
	for frame: int in range(warmup+count):
		if frame == warmup:
			drawn_before = Engine.get_frames_drawn()
		var stimulus_usec := 0
		if is_instance_valid(shelf) and frame % int(settings.performance.shelf_stimulus_interval_frames) == 0:
			var stimulus_start := Time.get_ticks_usec()
			var values: Array = settings.performance.shelf_stimulus_quantities
			var index := floori(float(frame)/float(settings.performance.shelf_stimulus_interval_frames)) % values.size()
			quantities[settings.performance.shelf_stimulus_item] = values[index]
			_fixture_version += 1
			var view := _view(quantities)
			shelf.update_inventory(view,_snapshot(view),true)
			stimulus_usec = Time.get_ticks_usec()-stimulus_start
		var wind_usec := 0
		if mode != "baseline":
			var wind_start := Time.get_ticks_usec()
			wind.call("_process",delta)
			wind_usec = Time.get_ticks_usec()-wind_start
		await process_frame
		var now := Time.get_ticks_usec()
		var wall_ms := float(now-last)/1000.0
		last = now
		delta = wall_ms/1000.0
		if frame < warmup:
			continue
		var active := 1 if controller.is_processing() else 0
		var controller_usec := int(controller.get("cpu_update_usec")) if active else 0
		var row := {"mode":mode,"scene_id":str(scene.scene_id),"frame":frame-warmup,"wall_frame_ms":wall_ms,
			"controller_cpu_ms":controller_usec/1000.0,"wind_cpu_ms":wind_usec/1000.0,"motion_cpu_ms":(controller_usec+wind_usec)/1000.0,
			"active_controllers":active,"particles":int(controller.call("particle_count")),"engine_monitor_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"stimulus_wall_ms":stimulus_usec/1000.0}
		rows.append(row)
		sample_rows.append(row)
	var result := _summarize(mode,str(scene.scene_id),sample_rows)
	result.rendered_frames = Engine.get_frames_drawn()-drawn_before
	result.rendering_continued = result.rendered_frames >= count
	result.passed = result.passed and result.rendering_continued
	measurements.append(result)
	print("MOTION PERFORMANCE SAMPLE: ",JSON.stringify(result))
	stage.queue_free()
	for _frame: int in range(int(settings.performance.settle_frames)):
		await process_frame

func _summarize(mode: String, scene_id: String, samples: Array) -> Dictionary:
	var wall: Array[float] = []
	var cpu: Array[float] = []
	var controller_cpu: Array[float] = []
	var wind_cpu: Array[float] = []
	var stimulus: Array[float] = []
	var particles := 0
	var controllers := 0
	for row: Dictionary in samples:
		wall.append(float(row.wall_frame_ms)); cpu.append(float(row.motion_cpu_ms))
		controller_cpu.append(float(row.controller_cpu_ms)); wind_cpu.append(float(row.wind_cpu_ms)); stimulus.append(float(row.stimulus_wall_ms))
		particles = maxi(particles,int(row.particles)); controllers = maxi(controllers,int(row.active_controllers))
	if samples.is_empty():
		return {"mode":mode,"scene_id":scene_id,"count":0,"passed":false}
	var frame_stats := statistics(wall)
	var cpu_stats := statistics(cpu)
	var fps := 1000.0/float(frame_stats.mean)
	var budget := 1000.0/float(settings.performance.fps_target)
	var fps_mean_met := fps >= float(settings.performance.fps_target)
	var all_frames_met := float(frame_stats.max) <= budget
	var cpu_met := float(cpu_stats.max) <= float(settings.performance.motion_cpu_limit_ms)
	return {"mode":mode,"scene_id":scene_id,"count":samples.size(),"wall_sample_seconds":float(frame_stats.mean)*samples.size()/1000.0,"wall_frame_ms":frame_stats,"wall_mean_fps":fps,
		"motion_cpu_ms":cpu_stats,"controller_cpu_ms":statistics(controller_cpu),"wind_cpu_ms":statistics(wind_cpu),"stimulus_wall_ms":statistics(stimulus),
		"active_controllers_max":controllers,"particles_max":particles,"fps_mean_reaches_target":fps_mean_met,"p99_frame_meets_budget":float(frame_stats.p99) <= budget,
		"every_frame_meets_budget":all_frames_met,"motion_cpu_max_meets_budget":cpu_met,"passed":fps_mean_met and all_frames_met and cpu_met}

func _write_status(report: Dictionary) -> void:
	# A later full headless suite must not erase earlier real GPU measurements.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tools/art/a6"))
	var status_file := FileAccess.open(settings.performance.status_output,FileAccess.WRITE)
	check(status_file != null,"performance status evidence is writable without overwriting real measurements")
	if status_file != null:
		status_file.store_string(JSON.stringify(report,"\t")+"\n")
		status_file.close()

func _write_outputs(report: Dictionary) -> void:
	var perf: Dictionary = settings.performance
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tools/art/a6"))
	var json_file := FileAccess.open(perf.json_output,FileAccess.WRITE)
	check(json_file != null,"performance JSON evidence is writable")
	if json_file != null:
		json_file.store_string(JSON.stringify(report,"\t")+"\n")
		json_file.close()
	var csv_file := FileAccess.open(perf.csv_output,FileAccess.WRITE)
	check(csv_file != null,"raw performance CSV evidence is writable")
	if csv_file != null:
		var columns := PackedStringArray(["mode","scene_id","frame","wall_frame_ms","motion_cpu_ms","controller_cpu_ms","wind_cpu_ms","active_controllers","particles","engine_monitor_process_ms","stimulus_wall_ms"])
		csv_file.store_csv_line(columns)
		for row: Dictionary in rows:
			var values := PackedStringArray()
			for column: String in columns:
				values.append(str(row[column]))
			csv_file.store_csv_line(values)
		csv_file.close()

func _restore() -> void:
	if is_instance_valid(wind) and not _wind_original.is_empty():
		wind.time_seconds = _wind_original.time
		wind.set_weather(str(_wind_original.weather))
		wind.reduced_motion = _wind_original.reduced
		wind.reduced_motion_changed.emit(wind.reduced_motion)
		wind.set_process(_wind_original.process)
	if not _window_original.is_empty():
		root.borderless = _window_original.borderless
		root.size = _window_original.size
		root.content_scale_size = _window_original.scale
		Engine.max_fps = _window_original.max_fps
		DisplayServer.window_set_vsync_mode(_window_original.vsync)
		OS.low_processor_usage_mode = _window_original.low_usage

func _finish() -> void:
	print("MOTION PERFORMANCE: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

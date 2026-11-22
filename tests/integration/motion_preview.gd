extends SceneTree
## Actual Main and approved water Li; fixed render time is not a gameplay clock.
const CONFIG_PATH := "res://data/art/motion_preview.json"
const SceneArt = preload("res://scripts/shop/scene_visual.gd")
const Teardown = preload("res://tests/ui_teardown.gd")
var settings: Dictionary = {}
var main: Control
var game: Node
var saves: Node
var wind: Node
var output := ""
var round_number := 1
var checks := 0
var failures: Array[String] = []
var protected_shas: Dictionary = {}
var previews: Array[Dictionary] = []
var pixel_readbacks: Array[Dictionary] = []
var actions: Array[Dictionary] = []
var baseline: Dictionary = {}
var original_wind: Dictionary = {}
var original_save_root := ""

func _initialize() -> void:
	call_deferred("run")

static func _number(value: Variant, minimum: float = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum

static func _integer(value: Variant, minimum: int = 1) -> bool:
	return _number(value,minimum) and value == floor(float(value))

static func _path(value: Variant) -> bool:
	if not value is String or value.is_empty():
		return false
	for part: String in value.trim_prefix("res://").split("/",true):
		if part.is_empty() or part in [".",".."] or part.contains("\\") or part.contains(":"):
			return false
	return true

static func settings_valid(data: Dictionary) -> bool:
	if data.get("version") != 1 or data.get("periods") != ["day","night"]:
		return false
	if not data.get("borderless") is bool or not data.get("embed_subwindows") is bool:
		return false
	for key: String in ["max_rounds","expected_preview_count_per_size","settle_frames"]:
		if not _integer(data.get(key)):
			return false
	if not _number(data.get("navigation_settle_seconds")) or data.navigation_settle_seconds <= 0 or not data.get("save_name") is String or data.save_name.strip_edges().is_empty():
		return false
	for key: String in ["output_prefix","save_prefix","preference_prefix"]:
		if not _path(data.get(key)) or not data[key].begins_with("res://.tools/art/a6/preview-"):
			return false
	if not data.get("dimensions") is Array or data.dimensions.is_empty() or not data.get("capture_times_seconds") is Array or data.capture_times_seconds.size() != 2:
		return false
	var seen: Array = []
	for size: Variant in data.dimensions:
		if not size is Array or size.size() != 2 or not _integer(size[0]) or not _integer(size[1]) or seen.has(size):
			return false
		seen.append(size)
	for time: Variant in data.capture_times_seconds:
		if not _number(time):
			return false
	if data.capture_times_seconds[0] != 0 or data.capture_times_seconds[1] <= data.capture_times_seconds[0]:
		return false
	if not data.get("stock") is Dictionary or not data.stock.get("item_id") is String or data.stock.item_id.is_empty() or not _integer(data.stock.get("quantity")):
		return false
	for key: String in ["settled_seconds","expected_drop_px","settle_tolerance_px"]:
		if not _number(data.stock.get(key)) or data.stock[key] <= 0:
			return false
	if not data.get("pixel") is Dictionary:
		return false
	var pixel: Dictionary = data.pixel
	if pixel.get("viewport_size") not in data.dimensions or pixel.get("scene_id") != "S07" or pixel.get("layer_id") != "water_mask" or pixel.get("texture_filter") != "linear":
		return false
	if not pixel.get("unshaded_control") is bool or pixel.unshaded_control != true:
		return false
	var feather: Variant = pixel.get("feather_alpha_range")
	if pixel.get("transparent_alpha") != 0 or pixel.get("opaque_alpha") != 255 or not feather is Array or feather.size() != 2 or feather[0] != 1 or feather[1] != 254:
		return false
	for key: String in ["shore_radius_px","minimum_opaque_changed_pixels","difference_gain"]:
		if not _integer(pixel.get(key)):
			return false
	if not _number(pixel.get("loop_offset_seconds")) or pixel.loop_offset_seconds <= 0:
		return false
	if not data.get("protected_paths") is Array or data.protected_paths.is_empty() or not data.get("notes") is Dictionary:
		return false
	for path: Variant in data.protected_paths:
		if not _path(path):
			return false
	for key: String in ["front","period_fixture","water","reduced","stock","pixel","long_wrap","selection"]:
		if not data.notes.get(key) is String or data.notes[key].strip_edges().is_empty():
			return false
	return true

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("MOTION PREVIEW FAIL: "+label)

func _snapshot_sha() -> String:
	return JSON.stringify(game.snapshot()).sha256_text()

func _unchanged(label: String) -> void:
	check(game.snapshot() == baseline,"render-only operation preserves full game snapshot / "+label)

func _freeze() -> Node:
	var controller: Node = main.screen.scene_visual.motion_controller
	controller.set_process(false)
	wind.set_process(false)
	return controller

func _settle() -> void:
	for _frame: int in range(int(settings.settle_frames)):
		await process_frame

func _draw_ready() -> void:
	await _settle()
	await RenderingServer.frame_post_draw

func _schema_checks() -> void:
	check(settings_valid(settings),"actual preview JSON validates")
	if not settings_valid(settings):
		return
	var bad := settings.duplicate(true)
	bad.pixel.texture_filter = "nearest"
	check(not settings_valid(bad),"nearest cannot stand in for production feather filtering")
	bad = settings.duplicate(true); bad.capture_times_seconds[1] = NAN
	check(not settings_valid(bad),"NaN render time rejected")
	bad = settings.duplicate(true); bad.dimensions[0][0] = 0
	check(not settings_valid(bad),"empty render size rejected")
	bad = settings.duplicate(true); bad.output_prefix = "res://.tools/art/a6/preview-fail/../escape"
	check(not settings_valid(bad),"output traversal rejected")
	bad = settings.duplicate(true); bad.pixel.shore_radius_px = 0
	check(not settings_valid(bad),"empty shoreline criterion rejected")
	bad = settings.duplicate(true); bad.stock.settled_seconds = 0
	check(not settings_valid(bad),"stock settling interval must be positive")

func run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	settings = parsed if parsed is Dictionary else {}
	_schema_checks()
	if not failures.is_empty():
		_finish()
		return
	if DisplayServer.get_name() == "headless":
		print("MOTION PREVIEW SKIP: actual production PNG/GPU alpha evidence requires a graphical renderer")
		_finish()
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--round=") and argument.trim_prefix("--round=").is_valid_int():
			round_number = int(argument.trim_prefix("--round="))
		else:
			check(false,"unknown preview argument / "+argument)
	check(round_number >= 1 and round_number <= int(settings.max_rounds),"capture round is within the authorized limit")
	check(RenderingServer.get_current_rendering_method() == "gl_compatibility","actual Compatibility renderer required")
	output = str(settings.output_prefix)+str(round_number)
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"new evidence round cannot overwrite any earlier capture")
	if not failures.is_empty():
		_finish()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_collect_hashes()
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	wind = root.get_node("WindField")
	root.borderless = settings.borderless
	root.gui_embed_subwindows = settings.embed_subwindows
	original_save_root = saves.base_dir
	original_wind = {"path":wind.settings_path,"reduced":wind.reduced_motion,"time":wind.time_seconds,"weather":wind.weather,"process":wind.is_processing(),
		"preferences_existed":FileAccess.file_exists(wind.settings_path),"preferences_sha256":FileAccess.get_sha256(wind.settings_path) if FileAccess.file_exists(wind.settings_path) else ""}
	wind.set_process(false)
	var run_id: String = game.make_id("preview")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(str(settings.preference_prefix)))
	wind.settings_path = str(settings.preference_prefix)+"/"+run_id+".cfg"
	saves.base_dir = str(settings.save_prefix)+"/"+run_id
	game.set_people_generation_options(false)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	main.save_window.hide()
	main.presentation_audio.settings_path = wind.settings_path
	for size: Array in settings.dimensions:
		root.size = Vector2i(int(size[0]),int(size[1]))
		root.content_scale_size = root.size
		var result: Dictionary = await main.run_action("new_game",{"name":settings.save_name})
		check(result.success,"isolated actual new_game succeeds / "+str(size))
		actions.append({"action_type":"new_game","success":result.success,"state_version":result.get("state_version"),"save_id":game.player_snapshot().get("save_id"),"size":size})
		baseline = game.snapshot()
		check(wind.set_reduced_motion(false),"normal motion preference saved only to isolated path")
		await _preview_size(size)
	await main.prepare_close_async()
	await Teardown.release_audio(main)
	main.queue_free()
	await _settle()
	wind.settings_path = original_wind.path
	wind.reduced_motion = original_wind.reduced
	wind.time_seconds = original_wind.time
	wind.set_weather(str(original_wind.weather))
	wind.reduced_motion_changed.emit(wind.reduced_motion)
	wind.set_process(original_wind.process)
	saves.base_dir = original_save_root
	var original_preferences_unchanged: bool = FileAccess.file_exists(original_wind.path) == original_wind.preferences_existed and (not original_wind.preferences_existed or FileAccess.get_sha256(original_wind.path) == original_wind.preferences_sha256)
	check(original_preferences_unchanged,"original preference file is unchanged by isolated UI capture")
	var resources_unchanged := true
	for path: String in protected_shas:
		var same: bool = FileAccess.get_sha256("res://"+path) == protected_shas[path]
		check(same,"protected resource remains byte-identical / "+path)
		resources_unchanged = resources_unchanged and same
	check(previews.size() == settings.dimensions.size()*int(settings.expected_preview_count_per_size),"all requested production Main preview frames exist")
	check(pixel_readbacks.size() == settings.periods.size(),"both formal day/night GPU readbacks exist")
	var receipt := {"version":1,"kind":"production_motion_preview","round":round_number,"checks":checks,"failures":failures.duplicate(),"passed":failures.is_empty(),
		"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),
		"config_sha256":FileAccess.get_sha256(CONFIG_PATH),"protected_shas":protected_shas,"protected_files_unchanged":resources_unchanged,
		"original_preferences_unchanged":original_preferences_unchanged,
		"notes":settings.notes.duplicate(true),"actions":actions,"previews":previews,"pixel_readbacks":pixel_readbacks,"visual_status":"待root逐张检查，未自动宣称美术通过。"}
	var file := FileAccess.open(output+"/receipt.json",FileAccess.WRITE)
	check(file != null,"capture receipt is writable")
	if file != null:
		file.store_string(JSON.stringify(receipt,"\t")+"\n")
		file.close()
	_finish()

func _collect_hashes() -> void:
	for path: String in settings.protected_paths:
		check(FileAccess.file_exists("res://"+path),"protected implementation/config exists / "+path)
		protected_shas[path] = FileAccess.get_sha256("res://"+path)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ART_ASSET_MANIFEST.json"))
	for asset: Dictionary in manifest.assets:
		var path: String = asset.path
		var sha := FileAccess.get_sha256("res://"+path)
		check(not sha.is_empty() and sha == asset.sha256,"actual formal asset SHA matches its manifest / "+path)
		protected_shas[path] = sha

func _open(page: String) -> Node:
	main.show_screen(page,true)
	var controller := _freeze()
	await create_timer(float(settings.navigation_settle_seconds)).timeout
	await _settle()
	if main.screen.get("drawer") is Control:
		main.screen.drawer.set_expanded(false,false)
	_unchanged("open "+page)
	return controller

func _period(period: String) -> void:
	var stage: Control = main.screen.scene_visual
	if stage.fade != null and stage.fade.is_running():
		stage.fade.kill()
	stage.current_period = period
	var scene: Dictionary = stage.config.scenes[stage.scene_id]
	for key: String in stage.backgrounds:
		stage.backgrounds[key].texture = SceneArt.texture_for(SceneArt.background_path(scene,key,stage.cabinet_state))
		stage.backgrounds[key].modulate.a = 1.0 if key == period else 0.0
	for key: String in stage.layer_nodes:
		var descriptor: Dictionary = scene.layers[key]
		var node: TextureRect = stage.layer_nodes[key]
		node.texture = SceneArt.texture_for(SceneArt.layer_path(descriptor,period))
		node.visible = descriptor.get("state",stage.cabinet_state) == stage.cabinet_state
		node.modulate.a = 1.0 if period in descriptor.get("periods",[period]) else 0.0
		node.pivot_offset = SceneArt.layer_pivot(descriptor,period,node.size)
	stage.motion_controller.sync_layers()
	_unchanged("render-only period "+period)

func _time(seconds: float) -> void:
	var controller: Node = main.screen.scene_visual.motion_controller
	controller.motion_time_seconds = seconds
	wind.time_seconds = seconds
	controller.sync_layers()

func _capture(label: String, size: Array, metadata: Dictionary) -> void:
	await _draw_ready()
	var image := root.get_texture().get_image()
	check(image != null and image.get_size() == Vector2i(int(size[0]),int(size[1])),"actual Main framebuffer dimensions / "+label)
	if image == null:
		return
	var path := output+"/"+label+"-"+str(int(size[0]))+"x"+str(int(size[1]))+".png"
	check(image.save_png(path) == OK,"save actual production Main frame / "+label)
	var row := metadata.duplicate(true)
	row.merge({"label":label,"path":path,"size":size,"sha256":FileAccess.get_sha256(path),"snapshot_sha256":_snapshot_sha(),"render_only_period_fixture":true},true)
	previews.append(row)
	_unchanged("capture "+label)

func _preview_size(size: Array) -> void:
	await _open("front")
	_period("day")
	_time(0)
	for node: TextureRect in main.screen.scene_visual.backgrounds.values():
		check(node.material == null,"front complete background remains static and has no motion shader")
	await _capture("front-day-static",size,{"note":settings.notes.front,"period":"day","time_seconds":0})
	await _open("gathering")
	for period: String in settings.periods:
		_period(period)
		for seconds: Variant in settings.capture_times_seconds:
			_time(float(seconds))
			await _capture("water-"+period+"-t"+str(int(seconds)),size,{"note":settings.notes.period_fixture,"period":period,"time_seconds":seconds,"reduced_motion":false})
		if size == settings.pixel.viewport_size:
			await _pixel_readback(period)
	main.open_network_settings()
	await _settle()
	var toggle := main.find_child("ReducedMotionCheck",true,false) as CheckButton
	check(toggle != null,"actual Main settings exposes reduced-motion control")
	if toggle != null:
		toggle.button_pressed = true
		check(wind.reduced_motion,"actual settings toggle enables reduced motion")
	await _capture("settings-reduced",size,{"note":settings.notes.reduced,"reduced_motion":true})
	if toggle != null:
		var dialog: Window = toggle.get_window()
		check(dialog != root,"motion toggle belongs to the actual settings dialog")
		if dialog != root:
			dialog.hide()
			dialog.queue_free()
			await _settle()
	await _open("gathering")
	_period("day")
	for seconds: Variant in settings.capture_times_seconds:
		_time(float(seconds))
		await _capture("water-day-reduced-t"+str(int(seconds)),size,{"note":settings.notes.reduced,"period":"day","time_seconds":seconds,"reduced_motion":true})
	check(wind.set_reduced_motion(false),"stock preview restores normal event amplitude")
	var controller: Node = await _open("inventory")
	var before: Dictionary = game.snapshot()
	var result: Dictionary = await main.run_action("procure_item",{"item_id":settings.stock.item_id,"quantity":int(settings.stock.quantity)})
	check(result.success,"real procurement saves successfully before any stock animation frame")
	actions.append({"action_type":"procure_item","success":result.success,"item_id":settings.stock.item_id,"quantity":settings.stock.quantity,"state_version":result.get("state_version"),"before_sha256":JSON.stringify(before).sha256_text(),"after_sha256":_snapshot_sha(),"size":size})
	baseline = game.snapshot()
	controller.set_process(false)
	var shelf: Control = main.screen.shelf_view
	var node: Node2D = shelf.get_item_node(str(settings.stock.item_id))
	var placement: Dictionary = shelf.item_placement(str(settings.stock.item_id))
	check(is_instance_valid(node) and not placement.is_empty(),"actual purchased independent item has a visible shelf placement")
	if is_instance_valid(node) and not placement.is_empty():
		var initial: float = node.position.y-float(placement.pivot.y)
		check(is_equal_approx(initial,-float(settings.stock.expected_drop_px)),"real saved procurement begins twelve native pixels above the shelf")
		await _capture("stock-initial",size,{"note":settings.notes.stock,"native_offset_y":initial,"time_seconds":0,"action_type":"procure_item"})
		controller.step(float(settings.stock.settled_seconds))
		var settled: float = node.position.y-float(placement.pivot.y)
		check(absf(settled) <= float(settings.stock.settle_tolerance_px),"actual production spring returns to the measured shelf baseline")
		await _capture("stock-settled",size,{"note":settings.notes.stock,"native_offset_y":settled,"time_seconds":settings.stock.settled_seconds,"action_type":"procure_item"})
	_unchanged("completed dimension")

func _pixel_readback(period: String) -> void:
	var stage: Control = main.screen.scene_visual
	var source: TextureRect = stage.layer_nodes.get(str(settings.pixel.layer_id)) as TextureRect
	check(source != null and source.material is ShaderMaterial,"actual formal water Texture and ShaderMaterial are present / "+period)
	if source == null or not source.material is ShaderMaterial:
		return
	var original: ShaderMaterial = source.material
	var native: Vector2 = original.get_shader_parameter("native_size")
	var speed: float = original.get_shader_parameter("speed_px_s")
	check(speed > 0 and native.x > 0,"actual water speed and native-width uniforms define the real wrap period")
	if speed <= 0 or native.x <= 0:
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(int(settings.pixel.viewport_size[0]),int(settings.pixel.viewport_size[1]))
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var picture := TextureRect.new()
	picture.size = Vector2(viewport.size)
	picture.texture = source.texture
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	picture.modulate = source.modulate
	picture.self_modulate = source.self_modulate
	var material: ShaderMaterial = original.duplicate(true)
	picture.material = material
	viewport.add_child(picture)
	var loop := native.x/speed
	var samples := {"start":settings.capture_times_seconds[0],"one_second":settings.capture_times_seconds[1],"loop_before":loop-float(settings.pixel.loop_offset_seconds),"loop_after":loop+float(settings.pixel.loop_offset_seconds)}
	var record := {"kind":"actual_water_gpu","period":period,"source_texture":source.texture.resource_path,"source_sha256":FileAccess.get_sha256(source.texture.resource_path),
		"shader_path":original.shader.resource_path,"uniform_native_size":[native.x,native.y],"speed_px_s":speed,"distortion_px":original.get_shader_parameter("distortion_px"),
		"noise_frequency":original.get_shader_parameter("noise_frequency"),"edge_fade_px":original.get_shader_parameter("edge_fade_px"),"motion_factor":original.get_shader_parameter("motion_factor"),"filter":"linear","size":settings.pixel.viewport_size,"samples":{}}
	picture.material = null
	await _draw_ready()
	var control := viewport.get_texture().get_image()
	check(control != null,"same-filter unshaded formal Li control exists / "+period)
	if control != null:
		control.convert(Image.FORMAT_RGBA8)
		var control_path := output+"/gpu-water-"+period+"-unshaded.png"
		check(control.save_png(control_path) == OK,"save original-alpha GPU control / "+period)
		record.control = {"kind":"unshaded_formal_gpu","filter":"linear","path":control_path,"sha256":FileAccess.get_sha256(control_path)}
	picture.material = material
	for label: String in samples:
		material.set_shader_parameter("motion_time",float(samples[label]))
		await _draw_ready()
		var image := viewport.get_texture().get_image()
		check(image != null,"actual GPU water readback exists / "+period+"/"+label)
		if image == null:
			continue
		image.convert(Image.FORMAT_RGBA8)
		var path := output+"/gpu-water-"+period+"-"+label+".png"
		check(image.save_png(path) == OK,"save formal GPU RGBA water readback / "+period+"/"+label)
		record.samples[label] = {"time_seconds":samples[label],"path":path,"sha256":FileAccess.get_sha256(path)}
	pixel_readbacks.append(record)
	viewport.queue_free()
	await _settle()
	_unchanged("actual water GPU readback "+period)

func _finish() -> void:
	print("MOTION PREVIEW: %d checks, %d failures, %d actual Main PNGs, %d formal GPU periods" % [checks,failures.size(),previews.size(),pixel_readbacks.size()])
	quit(0 if failures.is_empty() else 1)

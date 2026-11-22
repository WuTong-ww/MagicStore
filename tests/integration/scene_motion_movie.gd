extends SceneTree
## Movie Maker evidence, not a real-time performance benchmark. The only game
## action in a front/stock clip uses the genuine saved async action boundary.
const VALIDATION_PATH := "res://data/art/motion_validation.json"
const Validation = preload("res://tests/integration/motion_performance.gd")
const Bridge = preload("res://scripts/shop/people_bridge.gd")
const Wind = preload("res://scripts/presentation/wind_field.gd")
const SceneArt = preload("res://scripts/shop/scene_visual.gd")
var main: Control
var game: Node
var saves: Node
var wind: Node
var validation: Dictionary = {}
var movie: Dictionary = {}
var mode := ""
var reduced := false
var mode_settings: Dictionary = {}
var controller: Node
var ready_for_movie := false
var finishing := false
var drawn_frames := 0
var setup_finished_at_frame := -1
var checks := 0
var failures := 0
var action_started := false
var action_finished := false
var action_record: Dictionary = {}
var received_events: Array = []
var samples: Array = []
var gust_packet: Dictionary = {}
var wind_start := 0.0
var before_action: Dictionary = {}
var measured_initial_drop: Variant = null
var before_door_event_count := 0
var setup_resource_sha256: Dictionary = {}
var finished_resource_sha256: Dictionary = {}

func _initialize() -> void:
	process_frame.connect(_before_frame)
	RenderingServer.frame_post_draw.connect(_after_draw)
	call_deferred("setup_movie")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MOTION MOVIE FAIL: "+label)

func setup_movie() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VALIDATION_PATH))
	check(parsed is Dictionary and Validation.validation_valid(parsed),"movie parameters pass the shared validation JSON contract")
	if not parsed is Dictionary or not Validation.validation_valid(parsed):
		quit(1)
		return
	validation = parsed
	movie = validation.movie
	setup_resource_sha256 = resource_sha256()
	mode = str(movie.default_mode)
	reduced = bool(movie.reduced_motion)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		elif argument == "--reduced":
			reduced = true
		else:
			check(false,"unknown movie argument / "+argument)
	check(movie.modes.has(mode),"requested movie mode exists in validated data")
	check(DisplayServer.get_name() != "headless","movie evidence requires an actual Compatibility window")
	# Godot consumes engine arguments; the runtime movie feature is authoritative.
	check(OS.has_feature("movie"),"capture is running through Godot Movie Maker")
	if failures:
		quit(1)
		return
	mode_settings = movie.modes[mode]
	root.size = Vector2i(validation.window.width,validation.window.height)
	root.content_scale_size = root.size
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	wind = root.get_node_or_null("WindField")
	check(wind != null and Wind.settings_valid(wind.settings),"use the actual configured WindField autoload, never a movie-only substitute")
	if wind == null or not Wind.settings_valid(wind.settings):
		quit(1)
		return
	wind.set_process(false)
	gust_packet = wind.call("_packet",int(wind.settings.seed),int(movie.gust.slot)).duplicate(true)
	wind_start = maxf(0,float(gust_packet.start)-float(movie.gust.lead_seconds))
	check(float(gust_packet.start)+float(gust_packet.duration)+float(wind.settings.wind.propagation_seconds) <= wind_start+float(movie.duration_seconds),"unchanged natural gust and right-side propagation fit within the selected recording window")
	wind.time_seconds = wind_start
	wind.settings_path = "user://movie-"+mode+".cfg"
	check(wind.set_reduced_motion(reduced),"movie preference is saved only in this isolated presentation environment")
	saves.base_dir = "res://"+str(movie.save_directory)+"/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var created: Dictionary = await game.execute_action_async({"type":"new_game","action_id":game.make_id("movie_new"),"name":movie.fixture.shop_name})
	check(created.success,"create a genuine isolated game before the recording fixture")
	if not created.success:
		quit(1)
		return
	var fixture: Dictionary = game.snapshot()
	fixture.people.arrivals = {}
	var scene_data := SceneArt.load_config()
	check(not scene_data.is_empty(),"actual scene configuration validates before deriving fixture day metadata")
	if scene_data.is_empty():
		quit(1)
		return
	var scene_settings: Dictionary = scene_data.scene_settings
	var day := floori(float(fixture.clock_minutes)/float(scene_settings.minutes_per_day))
	fixture.people.days = {str(day):{"day":day,"natural_count":0,"arrival_ids":[]}}
	if mode_settings.action == "guest_arrival":
		var arrival := Bridge._arrival(str(movie.fixture.arrival_id),str(movie.fixture.npc_id),int(fixture.clock_minutes)+int(movie.fixture.arrival_after_minutes),"fixed_story",str(movie.fixture.case_id))
		arrival.schedule_end = int(fixture.clock_minutes)+int(movie.fixture.schedule_end_after_minutes)
		fixture.people.arrivals[arrival.arrival_id] = arrival
	check(saves.write_save(fixture).success,"planned fixture validates as a real save before loading")
	var loaded: Dictionary = await game.execute_action_async({"type":"load_game","action_id":game.make_id("movie_load"),"save_id":fixture.save_id})
	check(loaded.success,"load the valid isolated planned fixture through the real action API")
	if not loaded.success:
		quit(1)
		return
	before_action = game.snapshot()
	game.presentation_events_committed.connect(_on_committed)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# Main queues its normal save browser in ready; queue our close after it.
	call_deferred("finish_setup")

func finish_setup() -> void:
	main.save_window.hide()
	main.show_screen(str(mode_settings.page))
	if main.screen.get("drawer") is Control:
		main.screen.drawer.set_expanded(false,false)
	controller = main.screen.scene_visual.motion_controller
	check(controller != null,"record the production SceneVisual motion controller")
	check(main.screen.scene_visual.current_period == "day","all clips begin on the actual saved daylight clock")
	if mode == "water":
		var layer: TextureRect = main.screen.scene_visual.layer_nodes.get("water_mask")
		check(layer != null and layer.material is ShaderMaterial,"water clip uses the real S07 water Li with its actual flow material")
	before_door_event_count = wind.get("_door_events").size()
	setup_finished_at_frame = drawn_frames
	check(setup_finished_at_frame < int(movie.action_frame),"real scene is ready before the configured action frame")
	ready_for_movie = failures == 0
	if failures:
		finish_movie()

func _before_frame() -> void:
	if finishing or not ready_for_movie:
		return
	wind.time_seconds = wind_start+float(drawn_frames)/float(movie.fps)
	var next_frame := drawn_frames+1
	if next_frame == int(movie.action_frame) and not action_started and mode_settings.action != "none":
		action_started = true
		call_deferred("run_recorded_action",next_frame)

func run_recorded_action(requested_frame: int) -> void:
	var action := {"type":"wait" if mode_settings.action == "guest_arrival" else "procure_item","action_id":game.make_id("movie_action"),"expected_version":game.state.state_version}
	if mode_settings.action == "guest_arrival":
		action["minutes"] = int(movie.fixture.wait_minutes)
	else:
		action["item_id"] = str(movie.fixture.stock_item_id)
		action["quantity"] = int(movie.fixture.stock_quantity)
	var result: Dictionary = await game.execute_action_async(action)
	action_record = {"requested_frame":requested_frame,"drawn_frames_before_completion":drawn_frames,"action_id":action.action_id,"action_type":action.type,"success":result.success,"state_version":result.get("state_version",-1),"error_code":result.get("error_code","")}
	action_finished = true
	check(result.success,"recorded action actually saves successfully")
	check(main.screen.scene_visual.current_period == "day","real committed action preserves daylight")
	if mode == "stock":
		measured_initial_drop = stock_offset_y()
		var factor: float = float(wind.settings.reduced.event_factor) if reduced else 1.0
		check(measured_initial_drop != null and is_equal_approx(float(measured_initial_drop),-float(wind.settings.shelf.drop_px)*factor),"actual saved procurement immediately applies the configured native drop pose")
	print("MOTION MOVIE ACTION: "+JSON.stringify(action_record))

func _on_committed(events: Array) -> void:
	for event: Dictionary in events:
		received_events.append(event.duplicate(true))
		print("MOTION MOVIE COMMITTED EVENT: "+JSON.stringify(event))

func _after_draw() -> void:
	if finishing:
		return
	drawn_frames += 1
	if ready_for_movie:
		var sample := {"frame":drawn_frames,"wind_time_seconds":wind.time_seconds,"wind_left":wind.get_wind(0.0,false),"wind_right":wind.get_wind(1.0,false),"controller_time_seconds":controller.motion_time_seconds}
		if mode == "stock":
			sample["native_stock_offset_y"] = stock_offset_y()
		samples.append(sample)
	# Pinned 4.6.3 Writer empirically writes one frame beyond post-draw callbacks.
	# Data records that measured offset; the AVI header remains the final oracle.
	if not movie.is_empty() and drawn_frames >= int(movie.frame_count)-int(movie.writer_frame_offset):
		finish_movie()

func stock_offset_y() -> Variant:
	var shelf: Control = main.screen.shelf_view
	var item_id: String = movie.fixture.stock_item_id
	var node: Node2D = shelf.get_item_node(item_id)
	var placement: Dictionary = shelf.item_placement(item_id)
	return node.position.y-float(placement.pivot.y) if node != null and not placement.is_empty() else null

func finish_movie() -> void:
	if finishing:
		return
	finishing = true
	check(ready_for_movie and drawn_frames == int(movie.get("frame_count",-1))-int(movie.get("writer_frame_offset",0)),"normal completion observes the configured post-draw callback count, distinct from Writer frames")
	if ready_for_movie:
		check(root.size == Vector2i(validation.window.width,validation.window.height),"recorded window retains the configured native dimensions")
		check(mode_settings.action == "none" or action_finished,"scheduled real action completed before the final frame")
		if mode == "front":
			check(received_events.size() == 1 and received_events[0].arrival_id == movie.fixture.arrival_id and received_events[0].kind == "guest_entered","front clip records exactly one real committed guest entry")
			check(wind.get("_door_events").size() == before_door_event_count+1,"Main forwards the genuine committed event to the single global door-wind path")
		elif mode == "water":
			check(game.snapshot() == before_action and received_events.is_empty(),"water clip changes no game state and invents no door event")
			check(float(controller.motion_time_seconds) > 0,"actual visible S07 flow clock advances")
		elif mode == "stock":
			var expected := int(before_action.player.items.get(movie.fixture.stock_item_id,0))+int(movie.fixture.stock_quantity)
			check(int(game.shop_view().items.get(movie.fixture.stock_item_id,0)) == expected,"stock clip contains exactly the genuinely procured amount")
			var final_offset: Variant = stock_offset_y()
			check(final_offset != null and absf(float(final_offset)) <= float(wind.settings.limits.settle_degrees),"recorded stock drop returns to its original native shelf baseline")
	finished_resource_sha256 = resource_sha256()
	check(finished_resource_sha256 == setup_resource_sha256,"all four setup resource hashes remain unchanged throughout recording")
	write_receipt()
	print("MOTION MOVIE: %d checks, %d failures, %d observed post-draw callbacks, %d expected Writer frames (offset %d); independent AVI header must verify Writer count; fixed fps recording is not a real-time performance result"%[checks,failures,drawn_frames,int(movie.frame_count),int(movie.writer_frame_offset)])
	quit(1 if failures else 0)

func resource_sha256() -> Dictionary:
	return {"configuration_sha256":FileAccess.get_sha256(VALIDATION_PATH),"motion_settings_sha256":FileAccess.get_sha256(Wind.SETTINGS_PATH),"scene_config_sha256":FileAccess.get_sha256(SceneArt.CONFIG_PATH),"art_manifest_sha256":FileAccess.get_sha256("res://assets/ART_ASSET_MANIFEST.json")}

func write_receipt() -> void:
	if movie.is_empty():
		return
	var directory: String = "res://"+str(movie.capture_directory)
	DirAccess.make_dir_recursive_absolute(directory)
	var basename: String = str(mode_settings.get("basename",mode))+("-reduced" if reduced else "")
	var file := FileAccess.open(directory+"/"+basename+"-harness.json",FileAccess.WRITE)
	if file == null:
		check(false,"write local movie evidence receipt")
		return
	file.store_string(JSON.stringify({"kind":"actual_godot_movie_maker_evidence","mode":mode,"reduced_motion":reduced,"checks":checks,"failures":failures,"observed_post_draw_callbacks":drawn_frames,"writer_expected_frames":int(movie.frame_count),"writer_frame_offset":int(movie.writer_frame_offset),"writer_offset_evidence":"Pinned Godot 4.6.3 front Attempt2: 600 observed post-draw callbacks produced 601 Writer frames; retained AVI/header remains independent evidence.","fps":movie.fps,"configured_duration_seconds":movie.duration_seconds,"setup_finished_at_frame":setup_finished_at_frame,"window":[root.size.x,root.size.y],"configuration_sha256":setup_resource_sha256.get("configuration_sha256",""),"motion_settings_sha256":setup_resource_sha256.get("motion_settings_sha256",""),"scene_config_sha256":setup_resource_sha256.get("scene_config_sha256",""),"art_manifest_sha256":setup_resource_sha256.get("art_manifest_sha256",""),"finished_resource_sha256":finished_resource_sha256,"configuration_unchanged":finished_resource_sha256 == setup_resource_sha256,"natural_gust":{"seed":wind.settings.seed if wind != null else null,"packet":gust_packet,"recording_time_start":wind_start,"interval_was_not_modified":true},"action":action_record,"committed_events":received_events,"measured_initial_stock_offset_y":measured_initial_drop,"controller_diagnostics":controller.diagnostics if controller != null else [],"front_full_layer_linkage_passed":false,"front_limitations":"Missing approved chime/flower/curtain/tree Li and missing windchime audio remain a partial art result; a saved entry and safe static fallback are not full linkage acceptance.","not_real_time_performance":true,"samples":samples},"\t")+"\n")
	file.close()

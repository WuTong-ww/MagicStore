extends SceneTree
const Teardown = preload("res://tests/ui_teardown.gd")
const SceneArt = preload("res://scripts/shop/scene_visual.gd")
const Shelf = preload("res://scripts/shop/shelf_view.gd")
const AudioSettings = preload("res://scripts/audio/shop_audio.gd")
const MOTION := "res://scripts/presentation/scene_motion.gd"
var checks := 0
var failures := 0

class ControlledWind extends Node:
	signal reduced_motion_changed(value: bool)
	var reduced_motion := false
	var value := 0.0
	func get_wind(_x: float, _indoor: bool = true) -> float:
		return value
	func reduce(value_in: bool) -> void:
		reduced_motion = value_in
		reduced_motion_changed.emit(value_in)

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SCENE MOTION FAIL: "+label)

func diagnostic(controller: Node, id: String, status: String) -> bool:
	for row: Dictionary in controller.get("diagnostics"):
		if row.get("layer_id") == id and row.get("status") == status:
			return true
	return false

func art() -> TextureRect:
	var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
	image.fill(Color(0.3,0.5,0.4,0.6))
	var node := TextureRect.new()
	node.texture = ImageTexture.create_from_image(image)
	node.size = Vector2(128,128)
	node.pivot_offset = Vector2(64,12)
	return node

func descriptor(type: String) -> Dictionary:
	return {"native_size":[100,100],"pivot_px":[50,10],
		"motion":{"type":type,"parameters":{}}}

func fixture(settings: Dictionary) -> Dictionary:
	var stage := SceneArt.new()
	stage.config = {"scene_settings":{"canvas":[2560,1440]}}
	stage.scene_id = "S02"
	stage.current_period = "day"
	stage.size = Vector2(1280,720)
	root.add_child(stage)
	var scene := {"layers":{}}
	for pair: Array in [["sofa","static"],["leaf","sway_shader"],["windchime","pendulum"],["water","flow"],["hidden_C","sway_shader"]]:
		var node := art()
		stage.add_child(node)
		stage.layer_nodes[pair[0]] = node
		scene.layers[pair[0]] = descriptor(pair[1])
	scene.layers.hidden_C.display = "hidden"
	scene.layers.missing_leaf = descriptor("sway_shader")
	scene.layers.bad = {"motion":{"type":"pendulum","parameters":{"k":-1}}}
	stage.layer_nodes.bad = art()
	stage.add_child(stage.layer_nodes.bad)
	var background := art()
	stage.add_child(background)
	stage.backgrounds.day = background
	var wind := ControlledWind.new()
	root.add_child(wind)
	var controller = load(MOTION).new()
	controller.wind_source = wind
	stage.add_child(controller)
	controller.set_process(false)
	controller.bind(stage,scene,settings)
	return {"stage":stage,"scene":scene,"wind":wind,"motion":controller}

func snapshot(version: int) -> Dictionary:
	return {"save_id":"a6-motion-fixture","state_version":version,"clock_minutes":600}

func inventory(quantity: int) -> Dictionary:
	return {"items":{"spring_water":1,"moon_dust":quantity,"quartz":1},
		"catalog":JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/catalog.json")),
		"shop":{"batches":[{"batch_id":"a","item_id":"spring_water","remaining":1},
			{"batch_id":"b","item_id":"moon_dust","remaining":quantity},
			{"batch_id":"c","item_id":"quartz","remaining":1}]}}

func run() -> void:
	check(FileAccess.file_exists(MOTION),"SceneMotion component exists")
	if not FileAccess.file_exists(MOTION):
		await finish()
		return
	var script: Script = load(MOTION)
	check(script != null and script.can_instantiate(),"SceneMotion compiles")
	if script == null or not script.can_instantiate():
		await finish()
		return
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/motion.json"))
	settings.particles.regions.S02 = [{"native_size":[100,100],"source_crop":[0,0,100,100],
		"rect":[10,10,80,80],"amount":40,"lifetime_seconds":3,"gravity_px_s2":[0,8],
		"drift_px_s":[3,1],"color":"#897A5A","size_px":2,"opacity":0.25}]
	var f := fixture(settings)
	var controller = f.motion
	var stage = f.stage
	var original := (stage.layer_nodes.water.texture as Texture2D).get_image().get_data()
	check(stage.layer_nodes.sofa.material == null and is_zero_approx(stage.layer_nodes.sofa.rotation),"static sofa is unchanged")
	check(stage.layer_nodes.hidden_C.material == null and stage.backgrounds.day.material == null,"hidden complete C and backdrop never acquire motion")
	check(diagnostic(controller,"missing_leaf","waiting_layer") and diagnostic(controller,"bad","invalid_motion"),"missing Li and invalid parameters have individual diagnostics")
	check(stage.layer_nodes.leaf.material is ShaderMaterial and stage.layer_nodes.water.material is ShaderMaterial,"approved synthetic sway and flow have distinct handlers")
	check(controller.particle_count() > 0 and controller.particle_count() <= int(settings.particles.max_alive),"approved region creates a nonzero bounded CPU-particle budget")
	controller.step(0.25)
	check(is_equal_approx(float(stage.layer_nodes.water.material.get_shader_parameter("motion_time")),0.25),"flow uses explicit controller time")
	check((stage.layer_nodes.water.texture as Texture2D).get_image().get_data() == original,"flow preserves source texture bytes and alpha")
	var time_before: float = controller.motion_time_seconds
	stage.hide()
	controller.step(10.0)
	check(is_equal_approx(controller.motion_time_seconds,time_before),"hidden scene does not accumulate time")
	stage.show()
	controller.step(0.1)
	check(is_equal_approx(controller.motion_time_seconds,time_before+0.1),"resuming adds only visible elapsed time")
	controller.set_active(false)
	controller.step(10.0)
	check(is_equal_approx(controller.motion_time_seconds,time_before+0.1),"explicit inactive scene pauses")
	controller.set_active(true)
	controller.on_presentation_events([{"save_id":"f","state_version":1,"sequence":0,"arrival_id":"a","kind":"guest_entered"}])
	controller.step(0.1)
	check(absf(stage.layer_nodes.windchime.rotation_degrees) > 0.0 and absf(stage.layer_nodes.windchime.rotation_degrees) <= float(settings.limits.indoor_max_degrees),"committed guest event excites an indoor pendulum within the angle limit")
	for index: int in range(600):
		controller.step(1.0/120.0)
	check(absf(stage.layer_nodes.windchime.rotation_degrees) < float(settings.limits.settle_degrees),"no-force pendulum settles relative to its baseline within five seconds")
	f.wind.reduce(true)
	check(controller.particle_count() == 0,"reduced motion clears live particle nodes immediately")
	check(controller.cpu_update_usec >= 0,"CPU update duration is available independently of frame/GPU time")
	stage.queue_free()
	await process_frame
	check(f.wind.reduced_motion_changed.get_connections().is_empty(),"scene destruction disconnects the shared wind signal")
	f.wind.queue_free()
	await check_shelf(settings)
	await check_chime_audio(settings)
	await check_flow_pixels()
	await finish()

func check_shelf(settings: Dictionary) -> void:
	var visuals: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/visuals.json"))
	visuals.scenes.S04.shelf_layout.selection_seconds = 0.03
	var stage := SceneArt.new()
	stage.config = visuals
	stage.scene_id = "S04"
	stage.current_period = "day"
	stage.size = Vector2(1280,720)
	root.add_child(stage)
	var shelf := Shelf.new()
	stage.add_child(shelf)
	shelf.setup(stage,visuals)
	shelf.update_inventory(inventory(1),snapshot(1),true)
	check(shelf.has_method("set_item_motion") and shelf.has_method("item_placement"),"shelf exposes native additive pose and read-only placement")
	if not shelf.has_method("set_item_motion") or not shelf.has_method("item_placement"):
		stage.queue_free()
		return
	var placement: Dictionary = shelf.item_placement("moon_dust")
	var pivot: Vector2 = placement.pivot
	var item: Node2D = shelf.get_item_node("moon_dust")
	var shadow: Node2D = shelf.find_child("ItemShadow_moon_dust",true,false)
	var original_target: Rect2 = shelf.get_hit_rect("moon_dust")
	shelf.set_item_motion("moon_dust",Vector2(2,-4),0.0)
	shelf.select_item("moon_dust")
	await create_timer(0.06).timeout
	for frame: int in range(8):
		await process_frame
	if not item.position.is_equal_approx(pivot+Vector2(2,-10)):
		print("SCENE MOTION POSE DIAGNOSTIC: actual=",item.position," expected=",pivot+Vector2(2,-10)," lifts=",shelf.get("_selection_lifts"))
	check(item.position.is_equal_approx(pivot+Vector2(2,-10)),"selection tween and motion offset compose without fighting over node.position")
	check(shadow.position.is_equal_approx(pivot),"shadow stays at its original contact under combined pose")
	var projected_offset := Vector2(2,-10)*stage.native_scale(visuals.scenes.S04.shelf_layout.native_size,visuals.scenes.S04.shelf_layout.source_crop)
	check(shelf.get_hit_rect("moon_dust").position.is_equal_approx(original_target.position+projected_offset),"actual mouse target follows the composed translation")
	placement.pivot = Vector2.ZERO
	check(shelf.item_placement("moon_dust").pivot == pivot,"placement API does not expose mutable layout ownership")
	var wind := ControlledWind.new()
	root.add_child(wind)
	var controller = load(MOTION).new()
	controller.wind_source = wind
	stage.add_child(controller)
	controller.set_process(false)
	controller.bind(stage,visuals.scenes.S04,settings)
	controller.bind_shelf(shelf)
	controller.bind_shelf(shelf)
	check(shelf.item_added.get_connections().size() == 1 and shelf.item_removed.get_connections().size() == 1,"repeated binding connects shelf deltas once")
	shelf.update_inventory(inventory(2),snapshot(2),true)
	check(item.position.y < pivot.y-float(visuals.scenes.S04.shelf_layout.selection_lift_px),"committed addition starts above the selected baseline")
	wind.reduce(true)
	check(is_equal_approx(item.position.y,pivot.y-float(visuals.scenes.S04.shelf_layout.selection_lift_px)-float(settings.shelf.drop_px)*float(settings.reduced.event_factor)),"enabling reduced motion halves an already active drop immediately")
	wind.reduce(false)
	shelf.update_inventory(inventory(1),snapshot(3),true)
	check(item.position.is_equal_approx(pivot-Vector2(0,float(visuals.scenes.S04.shelf_layout.selection_lift_px))),"partial removal clears the retained item's old drop pose rather than leaving it suspended")
	shelf.update_inventory(inventory(2),snapshot(4),true)
	for index: int in range(600):
		controller.step(1.0/120.0)
	check(absf(item.position.y-(pivot.y-float(visuals.scenes.S04.shelf_layout.selection_lift_px))) < 0.1,"drop spring returns to the exact selected baseline")
	check(absf(item.rotation_degrees) <= float(settings.limits.indoor_max_degrees),"base micro-rotation plus motion respects the total angle limit")
	var removed_placement: Array = []
	shelf.item_removed.connect(func(id: String,_quantity: int,node: Node2D):
		removed_placement.append([shelf.item_placement(id),is_instance_valid(node)]))
	shelf.update_inventory(inventory(0),snapshot(5),true)
	check(not removed_placement.is_empty() and not removed_placement[0][0].is_empty() and removed_placement[0][1],"removal synchronously exposes the outgoing native placement")
	check(not controller.shelf_states.has("moon_dust"),"removed inventory does not retain an animation on the pending-free node")
	controller.set_active(false)
	check(controller.shelf_states.is_empty(),"inactive presentation clears shelf impulses")
	stage.queue_free()
	wind.queue_free()
	await process_frame

func audio_fixture(settings: Dictionary, scene_id: String = "S02") -> Dictionary:
	var stage := SceneArt.new()
	stage.config = {"scene_settings":{"canvas":[2560,1440]}}
	stage.scene_id = scene_id
	stage.size = Vector2(1280,720)
	root.add_child(stage)
	var wind := ControlledWind.new()
	root.add_child(wind)
	var controller = load(MOTION).new()
	controller.wind_source = wind
	stage.add_child(controller)
	controller.set_process(false)
	controller.bind(stage,{"layers":{}},settings)
	return {"stage":stage,"wind":wind,"motion":controller}

func check_chime_audio(original: Dictionary) -> void:
	var settings := original.duplicate(true)
	settings.particles.regions.S02 = []
	var events := [{"save_id":"audio-fixture","state_version":1,"sequence":0,
		"arrival_id":"guest-a","kind":"guest_entered"}]
	for path: Variant in [false,"","res://assets/audio/ui/a6-no-chime-fixture.ogg"]:
		var invalid := settings.duplicate(true)
		invalid.events.chime_audio = path
		var f := audio_fixture(invalid)
		f.motion.on_presentation_events(events)
		check(f.motion.find_child("WindChimeAudio",true,false) == null,"invalid/missing chime source creates no player / "+str(path))
		check(diagnostic(f.motion,"settings","invalid_motion") if path is bool else diagnostic(f.motion,"wind_chime","missing_audio"),"invalid/missing chime source is diagnosed / "+str(path))
		f.stage.queue_free()
		f.wind.queue_free()
		await process_frame
	# Existing short UI Ogg is strictly a lifecycle fixture, never production chime art/audio.
	settings.events.chime_audio = "res://assets/audio/ui/notify.ogg"
	var silent := audio_fixture(settings,"S07")
	silent.motion.on_presentation_events(events)
	check(silent.motion.find_child("WindChimeAudio",true,false) == null,"valid stream does not ring in a scene without a declared or expected chime")
	silent.stage.queue_free()
	silent.wind.queue_free()
	await process_frame
	var live := audio_fixture(settings)
	live.motion.set_process(true)
	check(live.motion.is_processing(),"shutdown fixture begins with component frame processing enabled")
	live.motion.on_presentation_events(events)
	var player := live.motion.find_child("WindChimeAudio",true,false) as AudioStreamPlayer
	check(player != null and player.has_stream_playback(),"expected chime scene can play a real stream once even while its Li is missing")
	check(live.motion.get("chime_play_count") == 1,"first committed chime event produces one actual play call")
	live.motion.on_presentation_events(events)
	check(live.motion.get("chime_play_count") == 1,"replayed committed event cannot restart the chime")
	if player != null:
		var player_handle: WeakRef = weakref(player)
		var playback_handle: WeakRef = weakref(player.get_stream_playback()) if player.has_stream_playback() else null
		check(live.motion.has_method("shutdown"),"motion exposes synchronous pre-drain shutdown")
		if live.motion.has_method("shutdown"):
			live.motion.shutdown()
			check(not player.playing and player.stream == null,"shutdown stops optional audio and clears its stream before scene destruction")
			check(not live.motion.is_processing(),"shutdown disables component frame processing")
			live.motion.on_presentation_events([{"save_id":"audio-fixture","state_version":2,"sequence":0,
				"arrival_id":"guest-b","kind":"guest_entered"}])
			check(live.motion.get("chime_play_count") == 1,"shutdown cannot create new playback from later committed events")
			live.motion.shutdown()
			check(not player.playing and player.stream == null and not live.motion.is_processing(),"repeated synchronous shutdown is idempotent")
		live.stage.queue_free()
		live.wind.queue_free()
		var deadline := Time.get_ticks_usec()+int(float(AudioSettings.load_config().shutdown_timeout_seconds)*1000000.0)
		while Time.get_ticks_usec() < deadline and (player_handle.get_ref() != null or (playback_handle != null and playback_handle.get_ref() != null)):
			await process_frame
		check(player_handle.get_ref() == null,"scene destruction leaves no orphaned AudioStreamPlayer")
		check(playback_handle == null or playback_handle.get_ref() == null,"scene destruction releases the actual mixer playback")
	else:
		live.stage.queue_free()
		live.wind.queue_free()
		await process_frame

func check_flow_pixels() -> void:
	if DisplayServer.get_name() == "headless":
		print("SCENE MOTION SKIP: actual shader pixel/alpha readback requires the graphical renderer")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(32,32)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var source := Image.create(32,32,false,Image.FORMAT_RGBA8)
	source.fill(Color.TRANSPARENT)
	for y: int in range(4,28):
		for x: int in range(4,28):
			source.set_pixel(x,y,Color(float(x)/31.0,float(y)/31.0,0.4,1.0))
	var picture := TextureRect.new()
	picture.size = Vector2(32,32)
	picture.texture = ImageTexture.create_from_image(source)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/scene_flow.gdshader")
	material.set_shader_parameter("native_size",Vector2(32,32))
	material.set_shader_parameter("speed_px_s",2.0)
	material.set_shader_parameter("distortion_px",0.0)
	material.set_shader_parameter("noise_frequency",0.1)
	material.set_shader_parameter("edge_fade_px",1.0)
	material.set_shader_parameter("motion_time",0.0)
	picture.material = material
	viewport.add_child(picture)
	await process_frame
	await RenderingServer.frame_post_draw
	var before := viewport.get_texture().get_image()
	material.set_shader_parameter("motion_time",2.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var after := viewport.get_texture().get_image()
	check(before != null and after != null,"graphical shader target yields real pixel images")
	if before != null and after != null:
		check(before.get_pixel(16,16) != after.get_pixel(16,16),"speed>0 with zero distortion still scrolls water interior")
		var alpha_fixed := true
		var shore_fixed := true
		for y: int in range(32):
			for x: int in range(32):
				var first := before.get_pixel(x,y)
				var second := after.get_pixel(x,y)
				alpha_fixed = alpha_fixed and first.a == second.a
				if first.a < 1.0 or x in [4,27] or y in [4,27]:
					shore_fixed = shore_fixed and first == second
		check(alpha_fixed,"flow preserves every original raster alpha byte")
		check(shore_fixed,"flow keeps transparent and shore boundary pixels fixed")
		before.save_png(ProjectSettings.globalize_path("res://.tools/art/a6/renderer-flow-before.png"))
		after.save_png(ProjectSettings.globalize_path("res://.tools/art/a6/renderer-flow-after.png"))
	viewport.queue_free()
	await process_frame
	await check_flow_concavity_and_horizon()
	await check_formal_flow_horizon()

func flow_frame(viewport: SubViewport, material: ShaderMaterial, seconds: float) -> Image:
	material.set_shader_parameter("motion_time",seconds)
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	check(image != null,"flow GPU sample exists / "+str(seconds))
	if image != null:
		image.convert(Image.FORMAT_RGBA8)
	return image

func flow_stats(first: Image, second: Image, region: Rect2i) -> Dictionary:
	var before: PackedByteArray = first.get_region(region).get_data()
	var after: PackedByteArray = second.get_region(region).get_data()
	var differences: Array[int] = []
	var total := 0
	var maximum := 0
	var changed := 0
	for index: int in range(0,before.size(),4):
		var pixel_changed := false
		for channel: int in range(3):
			var delta := absi(int(before[index+channel])-int(after[index+channel]))
			differences.append(delta)
			total += delta
			maximum = maxi(maximum,delta)
			pixel_changed = pixel_changed or delta > 0
		if pixel_changed:
			changed += 1
	differences.sort()
	return {"pixels_changed":changed,"max_rgb_byte_delta":maximum,
		"mean_rgb_byte_delta":float(total)/float(differences.size()),
		"p99_rgb_byte_delta":differences[floori(float(differences.size()-1)*0.99)]}

func check_flow_concavity_and_horizon() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64,64)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var source := Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y: int in range(64):
		for x: int in range(64):
			source.set_pixel(x,y,Color(float(x)/63.0,float(y)/63.0,float(x+y)/126.0,1.0))
	var concave: Image = source.duplicate()
	for y: int in range(32,64):
		for x: int in range(32,64):
			concave.set_pixel(x,y,Color.TRANSPARENT)
	concave.set_pixel(21,21,Color.TRANSPARENT)
	var picture := TextureRect.new()
	picture.size = Vector2(64,64)
	picture.texture = ImageTexture.create_from_image(concave)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/scene_flow.gdshader")
	material.set_shader_parameter("native_size",Vector2(64,64))
	material.set_shader_parameter("speed_px_s",4.0)
	material.set_shader_parameter("distortion_px",0.0)
	material.set_shader_parameter("noise_frequency",0.05)
	material.set_shader_parameter("edge_fade_px",8.0)
	picture.material = material
	viewport.add_child(picture)
	var start: Image = await flow_frame(viewport,material,0.0)
	var moving: Image = await flow_frame(viewport,material,0.5)
	check(start.get_pixel(31,31) == moving.get_pixel(31,31),"diagonal concave opaque shore pixel remains RGB-identical")
	check(start.get_pixel(20,20) == moving.get_pixel(20,20),"one-pixel diagonal notch is protected even when all distant taps are opaque")
	picture.texture = ImageTexture.create_from_image(source)
	# This full-opacity affine texture isolates continuity from irregular-mask fallback.
	var region := Rect2i(24,24,16,16)
	var late_first: Image = await flow_frame(viewport,material,14.5)
	var late_second: Image = await flow_frame(viewport,material,15.0)
	var late := flow_stats(late_first,late_second,region)
	check(int(late.pixels_changed) >= 64,"opaque interior keeps scrolling near the old whole-width cycle rather than freezing at base")
	# Existing parameters imply spatial span20 and period5, not whole-width period16.
	var center: Image = await flow_frame(viewport,material,5.0)
	var near_before: Image = await flow_frame(viewport,material,4.875)
	var near_after: Image = await flow_frame(viewport,material,5.125)
	var closer_before: Image = await flow_frame(viewport,material,4.9375)
	var closer_after: Image = await flow_frame(viewport,material,5.0625)
	var across := flow_stats(near_before,near_after,region)
	var closer := flow_stats(closer_before,closer_after,region)
	check(int(across.pixels_changed) >= 64,"finite-span wrap samples have observable motion rather than a vacuous equal-image pair")
	check(float(closer.mean_rgb_byte_delta) <= float(across.mean_rgb_byte_delta) and int(closer.max_rgb_byte_delta) <= int(across.max_rgb_byte_delta),"approaching the finite-span wrap contracts the actual raster difference")
	var left: PackedByteArray = near_before.get_region(region).get_data()
	var middle: PackedByteArray = center.get_region(region).get_data()
	var right: PackedByteArray = near_after.get_region(region).get_data()
	var residual := 0
	for index: int in range(0,middle.size(),4):
		for channel: int in range(3):
			residual = maxi(residual,absi(int(right[index+channel])+int(left[index+channel])-2*int(middle[index+channel])))
	check(residual <= 1,"two sides of finite-span wrap match affine-texture velocity within one raster quantization byte")
	print("FLOW SYNTHETIC CONTINUITY: ",JSON.stringify({"late":late,"epsilon_0_125":across,"epsilon_0_0625":closer,"symmetric_residual_bytes":residual}))
	viewport.queue_free()
	await process_frame

func check_formal_flow_horizon() -> void:
	var visuals: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/visuals.json"))
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/motion.json"))
	var layer: Dictionary = visuals.scenes.S07.layers.water_mask
	var parameters: Dictionary = settings.layer_defaults.flow.duplicate(true)
	parameters.merge(layer.motion.parameters,true)
	var results: Array[Dictionary] = []
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920,1080)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var picture := TextureRect.new()
	picture.size = Vector2(viewport.size)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/scene_flow.gdshader")
	for key: String in ["speed_px_s","distortion_px","noise_frequency","edge_fade_px"]:
		material.set_shader_parameter(key,float(parameters[key]))
	material.set_shader_parameter("motion_factor",1.0)
	picture.material = material
	viewport.add_child(picture)
	var region := Rect2i(1440,800,288,128)
	for period: String in ["day","night"]:
		var path: String = layer.variants[period]
		picture.texture = SceneArt.texture_for(path)
		var transform: Dictionary = layer.variant_transforms[period]
		var crop: Array = transform.source_crop
		var native := Vector2(float(crop[2])-float(crop[0]),float(crop[3])-float(crop[1]))
		material.set_shader_parameter("native_size",native)
		var old_cycle := native.x/float(parameters.speed_px_s)
		var first: Image = await flow_frame(viewport,material,old_cycle-1.0)
		var second: Image = await flow_frame(viewport,material,old_cycle-0.5)
		var stats := flow_stats(first,second,region)
		check(int(stats.pixels_changed) >= 64,"formal "+period+" opaque-water ROI remains moving at417/417.5s")
		first.get_region(region).save_png(ProjectSettings.globalize_path("res://.tools/art/a6/renderer-flow-"+period+"-roi417.png"))
		second.get_region(region).save_png(ProjectSettings.globalize_path("res://.tools/art/a6/renderer-flow-"+period+"-roi417_5.png"))
		var record := {"period":period,"source":path,"source_sha256":FileAccess.get_sha256(path),"old_cycle_pre_wrap":stats,"continuity":[]}
		# The frozen production parameters give L50/speed4 = 12.5 seconds.
		var cycle := 1.0/float(parameters.noise_frequency)/float(parameters.speed_px_s)
		for epsilon: float in [0.001,0.0005]:
			var before: Image = await flow_frame(viewport,material,cycle-epsilon)
			var after: Image = await flow_frame(viewport,material,cycle+epsilon)
			record.continuity.append({"epsilon_seconds":epsilon,"rgb":flow_stats(before,after,region)})
		results.append(record)
		print("FLOW FORMAL ROI: ",JSON.stringify(record))
	var file := FileAccess.open("res://.tools/art/a6/renderer-flow-horizon.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"kind":"actual_formal_flow_roi_target","roi":[1440,800,288,128],"results":results,
		"scope":"ROI motion and quantized temporal deltas; not the separate full-Li shore audit or a mathematical C1 proof."},"\t")+"\n")
	file.close()
	viewport.queue_free()
	await process_frame

func finish() -> void:
	print("SCENE MOTION: %d checks, %d failures" % [checks,failures])
	await Teardown.drain(self)
	quit(1 if failures else 0)

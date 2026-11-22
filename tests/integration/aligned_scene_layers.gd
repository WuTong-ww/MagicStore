extends SceneTree
const Visual = preload("res://scripts/shop/scene_visual.gd")
const Fixture = preload("res://tests/fixtures/scene_visual_config.gd")
const UITeardown = preload("res://tests/ui_teardown.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ALIGNED SCENE LAYERS FAIL: "+label)

func settle() -> void:
	for frame: int in range(5):
		await process_frame

func crop_transform() -> Dictionary:
	return {"method":"equal_aspect_cover","filter":"Lanczos","scale":1.25,"source_crop":[0,80,1536,944],"runtime_size":[1920,1080],"native_size":[1536,1024]}

func run() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Visual.CONFIG_PATH))
	var old := Fixture.legacy(raw)
	var aligned := Fixture.aligned(raw)
	check(Visual.config_valid(old),"v2 legacy slice configuration remains supported")
	check(Visual.config_valid(aligned),"v3 accepts aligned layers without old S02/S05/S06 slice names")
	check(not old.scenes.S04.has("shelves") and not aligned.scenes.S04.has("shelves"),"historical fixtures explicitly retain their slot contract without inheriting production shelves")
	check(Visual.config_valid(raw) and raw.scenes.S04.get("shelves",[]) is Array and not raw.scenes.S04.get("shelves",[]).is_empty(),"active A7 source-pixel shelves validate independently of historical slot fixtures")
	check(not raw.scenes.S04.layers.has("slot"),"active A7 configuration has no storage-box slice alias")
	for malformed_items: Variant in [[],null,"invalid"]:
		var bad_items := raw.duplicate(true)
		bad_items.items = malformed_items
		check(not Visual.config_valid(bad_items),"invalid item map type returns false before typed shelf validation")
	for malformed_options: Variant in [[],null,"invalid"]:
		var bad_options := raw.duplicate(true)
		bad_options.scenes.S04.shelf_layout = malformed_options
		check(not Visual.config_valid(bad_options),"invalid shelf options type returns false before label validation")
	for malformed_labels: Variant in [[],null,{"details_heading":"","all_items_heading":"有效标题","overflow_heading":"有效标题"}]:
		var bad_labels := raw.duplicate(true)
		bad_labels.scenes.S04.shelf_layout.labels = malformed_labels
		check(not Visual.config_valid(bad_labels),"invalid drawer label data is rejected before dynamic UI")
	var missing_shelf_geometry := raw.duplicate(true)
	missing_shelf_geometry.scenes.S04.erase("shelves")
	check(not Visual.config_valid(missing_shelf_geometry),"new cabinet without either valid shelves or a legacy slot is rejected")
	var seat_config := aligned.duplicate(true)
	seat_config.scenes.S03["seat_compact_rect"] = [600,150,550,850]
	seat_config.scenes.S03["seat_narrow_rect"] = [600,150,550,850]
	check(Visual.config_valid(seat_config),"v3 scene may retain compact and narrow seats with its own artwork")
	seat_config.scenes.S03.seat_compact_rect[1] = NAN
	check(not Visual.config_valid(seat_config),"nonfinite compact seat is rejected before consultation layout")
	check(Visual.config_valid(JSON.parse_string(JSON.stringify(old))) and Visual.config_valid(JSON.parse_string(JSON.stringify(aligned))),"both formats retain numeric validity through the actual JSON codec")
	check(Visual.layer_path({"path":Fixture.DAY,"variants":"unused-v2-metadata"},"day") == Fixture.DAY,"v2 fallback path ignores unvalidated future metadata")
	for field: String in ["native_size","pivot_px","z_index","motion","rect","source_region","legacy","variants"]:
		var invalid := aligned.duplicate(true)
		match field:
			"native_size": invalid.scenes.S02.layers.moving_object.native_size = [0,1440]
			"pivot_px": invalid.scenes.S02.layers.moving_object.pivot_px = [INF,360]
			"z_index": invalid.scenes.S02.layers.moving_object.z_index = 1.5
			"motion": invalid.scenes.S02.layers.moving_object.motion.type = "unsupported"
			"rect": invalid.scenes.S02.layers.moving_object.rect = [1,0,2559,1440]
			"source_region": invalid.scenes.S02.layers.moving_object["source_region"] = [0,0,100,100]
			"legacy": invalid.scenes.S02.layers.moving_object["legacy"] = true
			"variants": invalid.scenes.S02.layers.moving_object.variants.night = "not-a-resource"
		check(not Visual.config_valid(invalid),"reject invalid aligned field / "+field)
	var invalid := aligned.duplicate(true)
	invalid.scenes.S02.layers.moving_object.motion.parameters.amplitude = NAN
	check(not Visual.config_valid(invalid),"reject nonfinite motion parameter")
	invalid = aligned.duplicate(true)
	invalid.scenes.S02.layers.moving_object.pivot_px = [2561,360]
	check(not Visual.config_valid(invalid),"reject pivot outside the actual native source canvas")
	invalid = aligned.duplicate(true)
	invalid.scenes.S03.layers.erase("sofa_mask")
	check(not Visual.config_valid(invalid),"v3 consultation requires its sofa occluder")
	invalid = aligned.duplicate(true)
	invalid.scenes.S04.layers.slot.erase("legacy")
	check(not Visual.config_valid(invalid),"localized inventory cell must be explicitly marked legacy")
	invalid = aligned.duplicate(true)
	invalid.scenes.S04.layers.erase("slot")
	check(not Visual.config_valid(invalid),"historical aligned inventory without shelf geometry still requires its explicit legacy slot alias")
	var cropped := aligned.duplicate(true)
	cropped.scenes.S02.layers.moving_object["source_transform"] = crop_transform()
	check(Visual.config_valid(cropped),"source cover/crop transform can declare actual variant pixels")
	for bad_crop: Array in [[-1,80,1536,944],[0,80,1536,80],[0,NAN,1536,944],[0,80,1537,944],[0,80,"invalid",944]]:
		invalid = cropped.duplicate(true)
		invalid.scenes.S02.layers.moving_object.source_transform.source_crop = bad_crop
		check(not Visual.config_valid(invalid),"reject malformed, nonfinite or out-of-source crop / "+str(bad_crop))
	invalid = cropped.duplicate(true)
	invalid.scenes.S02.layers.moving_object.source_transform.scale = 1.0
	check(not Visual.config_valid(invalid),"declared scale must describe the actual crop to runtime transform")
	invalid = cropped.duplicate(true)
	invalid.scenes.S02.layers.moving_object.source_transform.native_size = [1536,1024.5]
	check(not Visual.config_valid(invalid),"variant native source dimensions remain whole positive pixels")
	invalid = cropped.duplicate(true)
	invalid.scenes.S02.layers.moving_object["variant_transforms"] = {"night":{"method":"unknown"}}
	check(not Visual.config_valid(invalid),"variant crop transform is independently validated")
	invalid = cropped.duplicate(true)
	invalid.scenes.S02.layers.moving_object.erase("variants")
	invalid.scenes.S02.layers.moving_object["variant_transforms"] = {"night":crop_transform()}
	check(not Visual.config_valid(invalid),"a variant crop cannot move the pivot when that variant has no corresponding image")
	if Visual.config_valid(aligned):
		await check_runtime(aligned)
	if Visual.config_valid(cropped):
		await check_crop_pivot(cropped)
	await check_state_backgrounds(Fixture.aligned(raw))
	print("ALIGNED SCENE LAYERS: %d checks, %d failures" % [checks,failures])
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func check_runtime(config: Dictionary) -> void:
	var game := root.get_node("GameState")
	var committed: Dictionary = game.snapshot()
	game.state = {"clock_minutes":540}
	var stage: Control = Visual.new()
	root.add_child(stage)
	stage.size = Vector2(1280,720)
	stage.setup("front",config)
	await settle()
	var node: TextureRect = stage.layer_nodes.moving_object
	var instance := node.get_instance_id()
	check(node.texture == load(Fixture.DAY),"day variant is selected on initial presentation")
	check(node.z_index == 4 and node.get_meta("motion") == config.scenes.S02.layers.moving_object.motion,"z and future motion metadata come from configuration")
	check(stage.z_index+node.z_index < 0,"positive local art z stays below the main paper/chrome canvas")
	for dimensions: Vector2 in [Vector2(1280,720),Vector2(1920,1080),Vector2(2560,1080),Vector2(800,600)]:
		stage.size = dimensions
		await settle()
		var covered := Visual.cover_rect(dimensions,Vector2(2560,1440))
		check(node.get_rect().is_equal_approx(covered),"whole source layer shares the background cover transform / "+str(dimensions))
		check(node.pivot_offset.is_equal_approx(node.size*Vector2(0.25,0.25)),"native pixel pivot scales to the actual rendered rectangle / "+str(dimensions))
		check(node.material == null and is_zero_approx(node.rotation),"A1R does not activate future dynamic motion / "+str(dimensions))
	game.state.clock_minutes = 1080
	stage.refresh()
	check(node.get_instance_id() == instance and node.texture == load(Fixture.NIGHT),"night reuses the same aligned node and selects its matching variant")
	stage.queue_free()
	await settle()
	stage = Visual.new()
	root.add_child(stage)
	stage.size = Vector2(1280,720)
	stage.setup("exterior",config)
	check(stage.current_period == "night","exterior starts in actual night period")
	game.state.clock_minutes = 1321
	stage.refresh()
	check(stage.current_period == "closed" and stage.layer_nodes.moving_object.texture == load(Fixture.NIGHT),"closed falls back to the aligned night layer when no closed variant is supplied")
	stage.queue_free()
	await settle()
	stage = Visual.new()
	root.add_child(stage)
	stage.size = Vector2(1280,720)
	stage.setup("inventory",config)
	check(not stage.layer_nodes.has("slot") and config.scenes.S04.layers.slot.legacy,"legacy cell alias stays available without being painted as a scene layer")
	check(stage.layer_nodes.door_open.visible and not stage.layer_nodes.door_closed.visible,"cabinet open uses the configured state layer")
	stage.cabinet_state = "closed"
	stage.refresh()
	check(not stage.layer_nodes.door_open.visible and stage.layer_nodes.door_closed.visible,"cabinet closed changes presentation without replacing the inventory")
	stage.queue_free()
	await settle()
	var signed := config.duplicate(true)
	signed.scenes.S02.layers.moving_object.z_index = -4
	stage = Visual.new()
	root.add_child(stage)
	stage.size = Vector2(1280,720)
	stage.setup("front",signed)
	check(stage.backgrounds.day.z_index < stage.layer_nodes.moving_object.z_index,"valid negative-z art remains above the scene background")
	stage.queue_free()
	await settle()
	var legacy := Fixture.legacy(config)
	legacy.scenes.S02["layer_format"] = "aligned_full_canvas"
	legacy.scenes.S02.layers.letter["native_size"] = "unused-v2-metadata"
	legacy.scenes.S02.layers.letter["pivot_px"] = "unused-v2-metadata"
	legacy.scenes.S02.layers.letter["variants"] = {"day":Fixture.NIGHT,"night":Fixture.NIGHT}
	stage = Visual.new()
	root.add_child(stage)
	stage.size = Vector2(1280,720)
	stage.setup("front",legacy)
	check(stage.layer_nodes.get("letter") != null and stage.layer_nodes.letter.texture == load(Fixture.DAY) and stage.layer_nodes.letter.pivot_offset == Vector2.ZERO,"schema v2 keeps original slice behavior even when future metadata is present")
	stage.queue_free()
	await settle()
	game.state = committed

func check_state_backgrounds(config: Dictionary) -> void:
	var paths := {"open":{"day":Fixture.DAY,"night":Fixture.NIGHT},"closed":{"day":Fixture.NIGHT,"night":Fixture.DAY}}
	config.scenes.S04["state_backgrounds"] = paths
	check(Visual.config_valid(config),"cabinet may retain its own actual cleanplate for each state and period")
	for bad: Variant in [null,{}, {"open":paths.open}, {"open":paths.open,"closed":{"day":"bad","night":Fixture.NIGHT}}, {"open":paths.open,"closed":paths.closed,"unknown":paths.open}]:
		var invalid := config.duplicate(true)
		invalid.scenes.S04.state_backgrounds = bad
		check(not Visual.config_valid(invalid),"reject incomplete, unsafe or unknown cabinet background state / "+str(bad))
	var invalid := config.duplicate(true)
	invalid.scenes.S02["state_backgrounds"] = paths
	check(not Visual.config_valid(invalid),"cabinet state backgrounds are not accepted on unrelated aligned scenes")
	var game := root.get_node("GameState")
	var committed: Dictionary = game.snapshot()
	game.state = {"clock_minutes":540}
	var stage: Control = Visual.new()
	root.add_child(stage)
	stage.size = Vector2(1280,720)
	stage.setup("inventory",config)
	await settle()
	var backdrop_id: int = stage.backgrounds.day.get_instance_id()
	check(stage.backgrounds.day.texture == load(Fixture.DAY),"open cabinet selects its actual day B_all")
	stage.cabinet_state = "closed"
	stage.refresh()
	check(stage.backgrounds.day.texture == load(Fixture.NIGHT) and stage.backgrounds.night.texture == load(Fixture.DAY),"closing selects both period cleanplates from the matching closed C")
	game.state.clock_minutes = 1080
	stage.refresh()
	check(stage.current_period == "night" and stage.backgrounds.night.texture == load(Fixture.DAY),"night keeps the matching closed-state background")
	stage.cabinet_state = "open"
	stage.refresh()
	check(stage.backgrounds.day.get_instance_id() == backdrop_id and stage.backgrounds.night.texture == load(Fixture.NIGHT),"reopening changes actual textures on existing background nodes")
	stage.queue_free()
	await settle()
	game.state = committed

func check_crop_pivot(config: Dictionary) -> void:
	var game := root.get_node("GameState")
	var committed: Dictionary = game.snapshot()
	game.state = {"clock_minutes":540}
	config.scenes.S02.layers.moving_object["variant_transforms"] = {"night":{"method":"equal_aspect_cover","filter":"Lanczos","scale":0.9375,"source_crop":[0,192,2048,1344],"runtime_size":[1920,1080],"native_size":[2048,1536]}}
	var stage: Control = Visual.new()
	root.add_child(stage)
	stage.size = Vector2(1280,720)
	stage.setup("front",config)
	await settle()
	var node: TextureRect = stage.layer_nodes.moving_object
	check(node.pivot_offset.is_equal_approx(node.size*Vector2(0.25,176.0/864.0)),"reference pivot maps to actual variant pixels before subtracting source crop")
	game.state.clock_minutes = 1080
	stage.refresh()
	check(node.pivot_offset.is_equal_approx(node.size*Vector2(0.25,192.0/1152.0)),"night pivot uses its own original dimensions and crop on the same layer node")
	check(Visual.layer_pivot(config.scenes.S02.layers.moving_object,"closed",node.size).is_equal_approx(node.pivot_offset),"closed variant fallback applies the matching night crop as well as its texture")
	stage.queue_free()
	await settle()
	game.state = committed

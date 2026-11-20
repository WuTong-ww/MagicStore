extends SceneTree
var checks := 0
var failures := 0
var captures := 0
const CAPTURE_DIR := "res://.tools/c-ui-captures"
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("SCENE VISUALS FAIL: " + label)
func run() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/visuals.json"))
	check(parsed.has("scenes") and parsed.get("scenes", {}).size() == 7, "seven scene records are configured")
	check(FileAccess.file_exists("res://scripts/shop/scene_visual.gd"), "shared scene renderer exists")
	if failures > 0:
		print("SCENE VISUALS: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var visual_script: Script = load("res://scripts/shop/scene_visual.gd")
	check(visual_script.config_valid(parsed), "scene configuration validates")
	for row: Array in [[539,"closed"],[540,"day"],[1079,"day"],[1080,"night"],[1320,"night"],[1321,"closed"],[1980,"day"]]:
		check(visual_script.period(parsed,"S01",row[0]) == row[1], "exterior clock boundary " + str(row[0]))
	check(visual_script.period(parsed,"S02",1321) == "night", "indoor scenes keep night lamps after closing")
	var invalid := parsed.duplicate(true)
	invalid.scenes.S02.layers.letter.rect = [2500,1400,200,200]
	check(not visual_script.config_valid(invalid), "out of bounds slice is rejected")
	invalid = parsed.duplicate(true)
	invalid.scene_settings.fade_seconds = -0.5
	check(not visual_script.config_valid(invalid), "negative fade duration is rejected")
	invalid = parsed.duplicate(true)
	invalid.scenes.S02.layers.lamp_on.periods = ["unknown"]
	check(not visual_script.config_valid(invalid),"unknown layer period is rejected")
	invalid = parsed.duplicate(true)
	invalid.scenes.S04.layers.erase("slot")
	check(not visual_script.config_valid(invalid),"missing required storage cell is rejected")
	invalid = parsed.duplicate(true)
	invalid.scene_settings.inventory_columns = 0.5
	check(not visual_script.config_valid(invalid),"fractional grid column count is rejected")
	invalid = parsed.duplicate(true)
	invalid.scenes.S04.layers.door_open.source_region = [-1,0,392,1261]
	check(not visual_script.config_valid(invalid),"negative source texture crop coordinate is rejected")
	var fitted: Rect2 = visual_script.fit_rect(Vector2(1000,400), Vector2(2560,1440))
	check(is_equal_approx(fitted.size.x/fitted.size.y,2560.0/1440.0) and is_equal_approx(fitted.position.x,(1000.0-fitted.size.x)/2.0), "letterboxed canvas retains 16:9 and centers artwork")
	var door: Dictionary = parsed.scenes.S04.layers.door_open
	var cropped: Texture2D = visual_script.texture_for(door.path,door.source_region)
	check(cropped is AtlasTexture and cropped.region == Rect2(410,2,392,1261),"door uses configured source PNG region through an AtlasTexture")
	check(cropped != null and cropped.get_size() == Vector2(392,1261),"door cropped dimensions follow source pixels rather than the scene target rectangle")
	check(visual_script.texture_for(door.path,[1200,0,392,1261]) == null,"source region beyond actual PNG dimensions is rejected at load time")
	if cropped != null:
		var uncropped: Texture2D = visual_script.texture_for(door.path)
		var region := Rect2(Vector2(door.rect[0],door.rect[1]),Vector2(door.rect[2],door.rect[3]))
		var crop_fitted: Rect2 = visual_script.fit_rect(region.size,cropped.get_size())
		var uncropped_fitted: Rect2 = visual_script.fit_rect(region.size,uncropped.get_size())
		check(crop_fitted.size.y > uncropped_fitted.size.y and crop_fitted.size.y > region.size.y*0.9,"removing transparent PNG margins lets the door fill the intended tall target rectangle")
	await check_runtime(parsed)
	print("SCENE VISUALS: %d checks, %d failures, %d graphical captures" % [checks, failures, captures])
	quit(1 if failures else 0)

func settle() -> void:
	for frame: int in range(12):
		await process_frame

func check_runtime(config: Dictionary) -> void:
	var game := root.get_node("GameState")
	var saves := root.get_node("SaveService")
	saves.base_dir = "res://.tools/scene-visual-test-saves/"+game.make_id("run")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	var created: Dictionary = await main.run_action("new_game",{"name":"昼夜场景验收"})
	check(created.success,"create isolated scene visual save")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		main.show_screen("front")
		await settle()
		var visual: Control = main.screen.scene_visual
		for key: String in config.scenes.S02.hotspots:
			var button: Button = visual.get_node("Hotspot_"+key)
			var expected: Rect2 = visual.projected_rect(config.scenes.S02.hotspots[key].rect)
			check(button.get_rect().is_equal_approx(expected),"hotspot shares art coordinate transform / "+key+" / "+str(dimensions))
			check(Rect2(Vector2.ZERO,visual.size).grow(1).encloses(button.get_rect()),"hotspot remains inside artwork viewport / "+key)
		# Populate all nine known icons in a render-only fixture; restore before
		# any real action so this never manufactures saved inventory.
		var inventory_snapshot: Dictionary = game.snapshot()
		for count: int in [1,3]:
			game.state.player.items.clear()
			for id: String in config.items.keys().slice(0,count):
				game.state.player.items[id] = 1
			main.show_screen("inventory")
			await settle()
			check_fixed_cells(main.screen.inventory_grid,config,count,dimensions)
			if count == 1:
				await capture("a1-inventory-single-render-only-"+str(dimensions.x))
		for id: String in config.items:
			game.state.player.items[id] = 1
		main.show_screen("inventory")
		await settle()
		var grid: GridContainer = main.screen.inventory_grid
		check_fixed_cells(grid,config,9,dimensions)
		var resized_dimensions := Vector2i(1920,1080) if dimensions.x == 1280 else Vector2i(1280,720)
		root.size = resized_dimensions
		root.content_scale_size = resized_dimensions
		await settle()
		check_fixed_cells(grid,config,9,resized_dimensions)
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		check_fixed_cells(grid,config,9,dimensions)
		for actions: Node in main.screen.find_children("ItemActions","",true,false):
			for button: Button in actions.get_children():
				var width := button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
				check(not button.clip_text and button.size.x >= width,"local inventory action button gives its full label enough width / "+button.text)
		check(grid != null and grid.columns == config.scene_settings.inventory_columns and grid.get_child_count() == game.shop_view().items.size(),"inventory dynamically creates one cell per item at "+str(dimensions))
		for cell: Control in grid.get_children():
			check(cell.get_node("ItemIcon").texture != null and not cell.get_node("ItemDetails/ItemName").text.is_empty() and cell.get_node("ItemDetails/ItemQuantity").text.contains("数量"),"inventory icon, name and quantity use live controls")
		for cell: Control in grid.get_children():
			var name_label: Label = cell.get_node("ItemDetails/ItemName")
			var quantity: Label = cell.get_node("ItemDetails/ItemQuantity")
			check(not name_label.get_global_rect().intersects(quantity.get_global_rect()),"full nine-item grid name and quantity do not overlap / "+cell.name+" / "+str(dimensions))
			check(cell.get_global_rect().grow(1).encloses(name_label.get_global_rect()) and cell.get_global_rect().grow(1).encloses(quantity.get_global_rect()),"full nine-item grid text fits inside its cell / "+cell.name)
			check(name_label.size.y >= name_label.get_minimum_size().y and quantity.size.y >= quantity.get_minimum_size().y,"full nine-item grid gives both labels their font height / "+cell.name)
		await capture("a1-inventory-open-"+str(dimensions.x))
		var original: Dictionary = game.snapshot()
		var cabinet_button: Button = main.screen.scene_visual.get_node("Hotspot_cabinet")
		await click_at(cabinet_button.get_global_rect().get_center())
		check(not main.screen.cabinet_open,"actual click on configured wooden cabinet edge toggles cabinet / "+str(dimensions))
		check(main.screen.scene_visual.cabinet_state == "closed" and main.screen.inventory_grid == null and game.snapshot() == original,"cabinet presentation toggle does not settle inventory or change a save")
		main.screen.cabinet_open = true
		main.screen.refresh()
		main.screen.cabinet_open = false
		main.screen.refresh()
		main.screen.refresh()
		check(main.screen.inventory_grid == null,"same-frame open/closed and repeated refreshes keep no detached grid")
		await settle()
		await capture("a1-inventory-closed-"+str(dimensions.x))
		game.state = inventory_snapshot
	# Render/test fixture establishes 17:59; the observed transition itself must
	# come from a real saved wait action below, including its failed-write attempt.
	game.state.clock_minutes = 1079
	game.state.people.clock = 1079
	main.show_screen("exterior")
	await settle()
	var artwork: Control = main.screen.scene_visual
	check(artwork.current_period == "day","17:59 exterior starts on day variant")
	await capture("a1-exterior-day-1920")
	saves.fail_next_write = true
	var failed: Dictionary = await main.run_action("wait",{"minutes":1})
	check(not failed.success and artwork.current_period == "day" and int(game.player_snapshot().clock_minutes) == 1079,"save failure crossing 18:00 leaves day artwork and clock unchanged")
	var success: Dictionary = await main.run_action("wait",{"minutes":1})
	check(success.success and main.screen.scene_visual == artwork and artwork.current_period == "night","successful committed clock reuses persistent artwork and starts night fade")
	check(artwork.backgrounds.night.modulate.a < 1.0 and artwork.backgrounds.day.modulate.a > 0.0,"time change crossfades rather than replacing artwork immediately")
	if DisplayServer.get_name() != "headless":
		await create_timer(0.3).timeout
		await capture("a1-exterior-transition-1920")
		await create_timer(0.4).timeout
	else:
		await create_timer(0.7).timeout
	check(is_equal_approx(artwork.backgrounds.night.modulate.a,1.0) and is_zero_approx(artwork.backgrounds.day.modulate.a),"crossfade finishes at configured 0.6 seconds")
	await capture("a1-exterior-night-1920")
	main.show_screen("front")
	await settle()
	await capture("a1-front-night-1920")
	var exterior_button: Button = main.screen.scene_visual.get_node("Hotspot_exterior")
	var center := exterior_button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	root.push_input(motion)
	await settle()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = center
	press.pressed = true
	root.push_input(press)
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release)
	await settle()
	check(main.current_screen == "exterior","mouse click at transformed hotspot reaches destination")
	# Closing artwork is a render-only fixture: it deliberately does not save
	# a synthetic 22:01 state, and restores the complete committed snapshot.
	if DisplayServer.get_name() != "headless":
		var committed: Dictionary = game.snapshot()
		game.state.clock_minutes = 1321
		game.state.people.clock = 1321
		main.show_screen("exterior")
		await settle()
		check(main.screen.scene_visual.current_period == "closed","render-only 22:01 fixture displays closed exterior")
		await capture("a1-exterior-closed-render-only-1920")
		game.state = committed
		main.show_screen("exterior")
		await settle()
		check(game.snapshot() == committed and main.screen.scene_visual.current_period == "night","render-only fixture restores committed clock and night artwork")
	main.queue_free()
	await settle()

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var picture := root.get_texture().get_image()
	check(picture.save_png(CAPTURE_DIR+"/"+label+".png") == OK,"save graphical capture "+label)
	captures += 1


func click_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion)
	await settle()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = position
	press.pressed = true
	root.push_input(press)
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release)
	await settle()

func check_fixed_cells(grid: GridContainer, config: Dictionary, count: int, dimensions: Vector2i) -> void:
	check(grid.get_child_count() == count,"render-only item count "+str(count)+" / "+str(dimensions))
	for cell: Control in grid.get_children():
		check(cell.size.x <= grid.size.x/float(config.scene_settings.inventory_columns)+1.0 and cell.size.y <= grid.size.y/float(config.scene_settings.inventory_rows)+1.0,"sparse and full inventory use fixed grid cell dimensions / "+str(count)+" items / "+str(dimensions))

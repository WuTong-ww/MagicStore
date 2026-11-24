extends "res://tests/integration/a1r_scene_preview.gd"
## Actual production artwork at all 17 scene/state/period combinations.
## Only the renderer receives a display-clock fixture: no saved time, inventory
## or visit is mutated to manufacture the nighttime review frames.

func run() -> void:
	capture_prefix = "v3-production"
	capture_dir = CAPTURE_DIR+"/v3-production"
	var config := Visual.load_config()
	check(not config.is_empty() and config.scene_settings.version == 3,"production configuration is the active v3 scene format")
	check(DisplayServer.get_name() != "headless","production screenshots require a real graphical window")
	if failures:
		print("A1R PRODUCTION: %d checks, %d failures, 0 captures" % [checks,failures])
		await UITeardown.drain(self)
		quit(1)
		return
	var visuals_hash := FileAccess.get_sha256(Visual.CONFIG_PATH)
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	root.get_node("SaveService").base_dir = "res://.tools/a1r-production-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"正式场景画面验收"})).get("success",false),"create an isolated game through the real action transaction")
	check((await main.run_action("start_visit")).get("success",false),"start a real visit for the sofa composition")
	main.save_window.hide()
	main.people_window.hide()
	var committed: Dictionary = game.snapshot()
	for dimensions: Vector2i in SIZES:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		for page: String in PAGES:
			main.show_screen(page)
			await settle()
			var visual: Control = main.screen.room_art if page == "consultation" else main.screen.scene_visual
			check(visual.config == config,"actual screen loads the unmodified production configuration / "+page)
			var states: Array = ["open","closed"] if page == "inventory" else ["open"]
			var periods: Array = ["day","night","closed"] if page == "exterior" else ["day","night"]
			for cabinet: String in states:
				if page == "inventory":
					main.screen.cabinet_open = cabinet == "open"
					main.screen.refresh()
					await settle()
				for requested_period: String in periods:
					var display_clock := int(config.scene_settings.day_minute)
					if requested_period == "night":
						display_clock = int(config.scene_settings.night_minute)
					elif requested_period == "closed":
						display_clock = int(config.scene_settings.closing_minute)+1
					show_display_clock(visual,display_clock)
					await settle()
					var label := page+" / "+cabinet+" / "+requested_period+" / "+str(dimensions)
					check(visual.current_period == requested_period,"renderer selects the requested presentation period / "+label)
					check_scene(visual,page,dimensions)
					check_buttons(main,label)
					check_actual_resources(visual,requested_period,cabinet,label)
					check(game.snapshot() == committed,"rendering and navigation preserve complete committed state / "+label)
					var state_suffix := "-"+cabinet if page == "inventory" else ""
					await capture(capture_prefix+"-"+visual.scene_id+"-"+requested_period+state_suffix+"-"+str(dimensions.x)+"x"+str(dimensions.y))
	check(captures == 34,"17 production state/period combinations at both window sizes are captured")
	check(FileAccess.get_sha256(Visual.CONFIG_PATH) == visuals_hash,"production review never rewrites the artwork configuration")
	print("A1R PRODUCTION: %d checks, %d failures, %d actual graphical captures; renderer=%s" % [checks,failures,captures,DisplayServer.get_name()])
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func check_actual_resources(visual: Control, requested_period: String, cabinet: String, label: String) -> void:
	var scene: Dictionary = visual.config.scenes[visual.scene_id]
	var expected_path := Visual.background_path(scene,requested_period,cabinet)
	check(visual.backgrounds[requested_period].texture == Visual.texture_for(expected_path),"visible backdrop is the exact production state/period resource / "+label)
	for variant: String in visual.backgrounds:
		check(is_equal_approx(visual.backgrounds[variant].modulate.a,1.0 if variant == requested_period else 0.0),"only the requested period backdrop is visible / "+label+" / "+variant)
	for key: String in scene.layers:
		var layer: Dictionary = scene.layers[key]
		if layer.get("display","") in ["hidden","cell"]:
			check(not visual.layer_nodes.has(key),"semantic aliases and legacy cells are not painted over the room / "+label+" / "+key)
		else:
			check(visual.layer_nodes.has(key),"every real foreground cutout has a renderer node / "+label+" / "+key)
			if not visual.layer_nodes.has(key):
				continue
			var art: TextureRect = visual.layer_nodes[key]
			check(art.texture == Visual.texture_for(Visual.layer_path(layer,requested_period)),"foreground uses the exact matching period texture / "+label+" / "+key)
			check(art.visible == (layer.get("state",cabinet) == cabinet),"foreground visibility matches the requested cabinet state / "+label+" / "+key)

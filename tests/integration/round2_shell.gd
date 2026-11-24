extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
## A3R regression: full-window artwork and readable, independently placed UI.
const SIZES := [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(800,600)]
const CAPTURE_DIR := "res://.tools/round2/A3R"
const SceneArt = preload("res://scripts/shop/scene_visual.gd")
const Shell = preload("res://scripts/ui/shell_config.gd")
var checks := 0
var failures := 0
var captures := 0
var main: Control
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ROUND2 SHELL FAIL: " + label)

func settle() -> void:
	for frame: int in range(15):
		await process_frame

func run() -> void:
	check_shell_config()
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	root.get_node("SaveService").base_dir = "res://.tools/round2-shell-saves/" + game.make_id("run")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	var created: Dictionary = await main.run_action("new_game", {"name":"第二轮界面验收"})
	check(created.get("success",false), "create isolated save")
	var before_navigation: Dictionary = game.snapshot()
	for dimensions: Vector2i in SIZES:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		for page: String in ["exterior","front","consultation","inventory","workshop","market","gathering"]:
			main.show_screen(page)
			await settle()
			check_fullscreen(page,dimensions)
			check_buttons(main,page+" / "+str(dimensions))
			if page in ["front","consultation","inventory"]:
				await capture(page+"-"+str(dimensions.x)+"x"+str(dimensions.y))
	check(game.snapshot() == before_navigation,"resizing and navigation preserve saved game state")
	await check_zero_guest()
	var started: Dictionary = await main.run_action("start_visit")
	check(started.get("success",false),"real arrival can start consultation")
	for dimensions: Vector2i in SIZES:
		root.size = dimensions
		root.content_scale_size = dimensions
		main.show_screen("consultation")
		await settle()
		check_fullscreen("consultation",dimensions)
		check(main.screen.guest_portrait.visible,"active guest portrait is shown / "+str(dimensions))
		var portrait_rect: Rect2 = main.screen.guest_portrait.get_global_rect()
		check(portrait_rect.position.y+portrait_rect.size.y*0.5 < main.screen.dialogue_panel.get_global_rect().position.y,"guest face remains above dialogue panel / "+str(dimensions))
		check_buttons(main,"active consultation / "+str(dimensions))
		var viewport := Rect2(Vector2.ZERO,Vector2(dimensions))
		check(viewport.encloses(main.screen.input.get_global_rect()),"consultation input fits window / "+str(dimensions))
		check(viewport.encloses(main.screen.send_button.get_global_rect()),"consultation send button fits window / "+str(dimensions))
		await capture("consultation-active-"+str(dimensions.x)+"x"+str(dimensions.y))
	print("ROUND2 SHELL RESULT: %d checks, %d failures, %d graphical captures; renderer=%s" % [checks,failures,captures,DisplayServer.get_name()])
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func check_shell_config() -> void:
	var config := Shell.load_config()
	check(not config.is_empty() and Shell.config_valid(config),"shell JSON has a validated contract")
	if config.is_empty():
		return
	var invalid := config.duplicate(true)
	invalid.drawer_width = -1
	check(not Shell.config_valid(invalid),"shell rejects negative drawer width")
	invalid = config.duplicate(true)
	invalid.navigation[1].page = invalid.navigation[0].page
	check(not Shell.config_valid(invalid),"shell rejects duplicate destinations")
	invalid = config.duplicate(true)
	invalid.navigation[0].label = ""
	check(not Shell.config_valid(invalid),"shell rejects blank destination labels")
	invalid = config.duplicate(true)
	invalid.screen_minimum = [800]
	check(not Shell.config_valid(invalid),"shell rejects malformed minimum window dimensions")

func check_fullscreen(page: String,dimensions: Vector2i) -> void:
	var viewport := Rect2(Vector2.ZERO,Vector2(dimensions))
	check(main.scene_holder.get_global_rect().is_equal_approx(viewport),"scene holder fills window / "+page+" / "+str(dimensions))
	var visual: Control = main.screen.room_art if page == "consultation" else main.screen.scene_visual
	check(visual.get_global_rect().is_equal_approx(viewport),"scene artwork fills window / "+page+" / "+str(dimensions))
	for background: TextureRect in visual.backgrounds.values():
		check(background.texture != null,"scene background has an imported texture / "+page+" / "+str(dimensions))
		check(background.get_global_rect().grow(1).encloses(viewport),"cover background has no uncovered edges / "+page+" / "+str(dimensions))
	if page == "inventory" and main.screen.shelf_view != null:
		check(viewport.grow(1).encloses(main.screen.shelf_view.get_global_rect()),"inventory shelf interaction region stays inside cropped window / "+str(dimensions))
	if page == "front":
		var drawer: Control = main.screen.get_node("FrontDrawer")
		for key: String in visual.config.scenes[visual.scene_id].hotspots:
			var entry: Dictionary = visual.config.scenes[visual.scene_id].hotspots[key]
			var hotspot: Button = visual.get_node("Hotspot_"+key)
			check(hotspot.get_meta("decorative_hotspot",false),"hotspot has explicit decorative hit-target metadata / "+key)
			check(hotspot.get_rect().is_equal_approx(visual.projected_rect(entry.rect)),"hotspot uses shared cover projection / "+key)
			if entry.get("display","button") != "transparent":
				var label := visual.get_node_or_null("HotspotLabel_"+key) as Label
				check(label != null,"hotspot label is independent of click target / "+key)
				if label != null:
					var text_width := label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x
					check(label.size.x+1 >= text_width,"hotspot label fits full text / "+key)
					check(viewport.encloses(label.get_global_rect()),"hotspot label remains inside cropped viewport / "+key)
					check(not label.is_visible_in_tree() or not drawer.panel.get_global_rect().intersects(label.get_global_rect()),"expanded drawer never partly clips hotspot label / "+key)

func check_buttons(node: Node,label: String) -> void:
	if node is Button and node.is_visible_in_tree() and not node.get_meta("decorative_hotspot",false):
		var button: Button = node
		check(not button.text.strip_edges().is_empty(),"visible button has text / "+label+" / "+str(button.name))
		var font: Font = button.get_theme_font("font")
		var font_size := button.get_theme_font_size("font_size")
		var text_width := 0.0
		for line: String in button.text.split("\n"):
			text_width = maxf(text_width,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
		var padding := button.get_theme_stylebox("normal").get_minimum_size().x
		var icon_width := 0.0
		if button.icon != null:
			icon_width = button.icon.get_width()+button.get_theme_constant("h_separation")
		if button is OptionButton:
			icon_width += button.get_theme_icon("arrow").get_width()+button.get_theme_constant("h_separation")
		if button is CheckButton:
			icon_width += maxf(button.get_theme_icon("checked").get_width(),button.get_theme_icon("unchecked").get_width())+button.get_theme_constant("h_separation")
		if button.autowrap_mode == TextServer.AUTOWRAP_OFF:
			check(button.size.x+1.0 >= text_width+padding+icon_width,"button text and padding fit / "+label+" / "+button.text+" / required="+str(text_width+padding+icon_width)+" actual="+str(button.size.x))
		else:
			var inner_width := maxf(1.0,button.size.x-padding-icon_width)
			var wrapped := font.get_multiline_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,inner_width,font_size,-1,TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND|TextServer.BREAK_ADAPTIVE)
			check(wrapped.x <= inner_width+1.0 and wrapped.y+button.get_theme_stylebox("normal").get_minimum_size().y <= button.size.y+1.0,"wrapped button text fits complete lines / "+label+" / "+button.text)
	for child: Node in node.get_children():
		check_buttons(child,label)

func check_zero_guest() -> void:
	# Rendering-only fixture; restore the committed snapshot before next action.
	var original: Dictionary = game.snapshot()
	var day := floori(float(game.state.clock_minutes)/1440.0)+1
	game.state.clock_minutes = day*1440+540
	game.state.people.clock = game.state.clock_minutes
	game.state.people.days[str(day)] = {"day":day,"natural_count":0,"arrival_ids":[],"expected":0.0,"weather":"rain"}
	for row: Dictionary in game.state.people.arrivals.values():
		if row.state in ["queued","outside","appointment_requested"]:
			row.state = "left"
	main.show_screen("front")
	await settle()
	check(not main.screen.guest_picker.visible,"zero-customer day hides empty guest dropdown")
	check(main.screen.quiet_suggestions.visible,"zero-customer day retains three useful destinations")
	await capture("zero-guest-front")
	game.state = original
	main.show_screen("front")
	await settle()

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await create_timer(0.3).timeout
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var picture := root.get_texture().get_image()
	check(picture.save_png(CAPTURE_DIR+"/"+label+".png") == OK,"save graphical capture / "+label)
	captures += 1

extends SceneTree
## Real window sizes; this target never overrides the production stretch basis.
## Missing future APIs are ordinary assertion failures, never preload failures.
const Teardown = preload("res://tests/ui_teardown.gd")
const SIZES: Array[Vector2i] = [Vector2i(1280,529),Vector2i(1280,720),Vector2i(1366,768),Vector2i(1920,1080),Vector2i(2560,1440)]
var checks := 0
var failures := 0
var main: Control
var game: Node
var saves: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH LAYOUT FAIL: "+label)

func settle() -> void:
	for frame: int in range(14): await process_frame

func css_rect(node: Control) -> Rect2:
	var logical: Vector2 = root.get_visible_rect().size
	if logical.x <= 0 or logical.y <= 0: return Rect2()
	var factor := Vector2(root.size)/logical
	var transform := node.get_global_transform_with_canvas()
	var bounds := Rect2((transform*Vector2.ZERO)*factor,Vector2.ZERO)
	for point: Vector2 in [Vector2(node.size.x,0),node.size,Vector2(0,node.size.y)]:
		bounds = bounds.expand((transform*point)*factor)
	return bounds

func fits(node: Control) -> bool:
	return node != null and Rect2(Vector2(-1,-1),Vector2(root.size)+Vector2(2,2)).encloses(css_rect(node))

func measure(dimensions: Vector2i) -> void:
	root.size = dimensions
	await settle()
	check(root.size == dimensions,"actual Window permits requested client size / "+str(dimensions))
	var native_minimum: Vector2i = DisplayServer.window_get_min_size()
	check(native_minimum.y <= 529,"native user-resize minimum permits529 height / "+str(dimensions))
	check(root.content_scale_size == Vector2i(1920,1080),"production1920x1080 basis retained / "+str(dimensions))
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND,"production aspect expands instead of squeezing / "+str(dimensions))
	check(main.has_method("presentation_metrics"),"Main exposes measured presentation metrics / "+str(dimensions))
	if not main.has_method("presentation_metrics"): return
	var value: Variant = main.call("presentation_metrics")
	check(value is Dictionary and value.get("ready") == true,"presentation metrics are ready / "+str(dimensions))
	if not value is Dictionary or value.get("ready") != true: return
	var logical: Vector2 = root.get_visible_rect().size
	check(value.get("visible_css") is Vector2 and value.visible_css.is_equal_approx(Vector2(root.size)),"native CSS extent comes from real Window / "+str(dimensions))
	check(value.get("logical_size") is Vector2 and value.logical_size.is_equal_approx(logical),"metrics retain the actual stretched logical extent / "+str(dimensions))
	check(value.get("css_per_local_unit") is Vector2 and value.css_per_local_unit.is_equal_approx(Vector2(root.size)/logical),"one actual logical-to-client conversion / "+str(dimensions))
	check(value.get("short") is bool and value.short == (dimensions.y < 640),"short mode follows actual client height / "+str(dimensions))
	print("POLISH WINDOW METRICS: "+JSON.stringify({"requested":[dimensions.x,dimensions.y],"actual":[root.size.x,root.size.y],"native_minimum":[native_minimum.x,native_minimum.y],"basis":[root.content_scale_size.x,root.content_scale_size.y],"visible":[logical.x,logical.y],"metrics":value}))

func check_full_height(panel: Control, label: String) -> void:
	var rectangle := css_rect(panel)
	check(fits(panel) and absf(rectangle.position.y) <= 1 and absf(rectangle.end.y-float(root.size.y)) <= 1,label+" covers the complete actual client height")

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	saves.base_dir = "res://.tools/r3-polish/layout-saves/"+game.make_id("run")
	root.gui_embed_subwindows = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# Isolate presentation resize from unrelated asynchronous admission commits.
	main.set_process(false)
	await settle()
	var initial: Dictionary = game.snapshot()
	for dimensions: Vector2i in SIZES:
		await measure(dimensions)
		var title: Control = main.get("title_control")
		check(title != null and title.is_visible_in_tree(),"real TITLE remains visible before creation / "+str(dimensions))
		if title == null: continue
		var buttons: Dictionary = title.get("buttons")
		for key: String in ["continue","new","settings","credits"]:
			check(buttons.get(key) is Button and fits(buttons[key]),"TITLE safe menu stays inside actual window / "+key+" / "+str(dimensions))
	check(game.snapshot() == initial,"TITLE resizing never changes world state")
	if not (await main.run_action("new_game",{"name":"真实短窗口布局"})).get("success",false):
		check(false,"create isolated default sequential game")
		await finish()
		return
	check((await main.run_action("read_morning_letters")).get("success",false),"default sequential letters remain enabled")
	check((await main.run_action("next_customer")).get("success",false),"enter the real default CASE board")
	main.show_screen("consultation")
	await settle()
	var consultation: Control = main.screen
	var board: Control = consultation.get("case_board")
	check(board != null and board.is_visible_in_tree() and game.case_board_view().get("enabled",false),"default CASE is exercised without disabling it")
	if board == null:
		await finish()
		return
	var before: Dictionary = game.snapshot()
	var save_path: String = saves._path(str(before.save_id))
	var disk_hash: String = FileAccess.get_sha256(save_path)
	for dimensions: Vector2i in SIZES:
		await measure(dimensions)
		var speech: Control = board.get("speech_panel")
		check(speech != null and speech.is_visible_in_tree() and fits(speech) and css_rect(speech).size.y <= float(root.size.y)*0.45+1,"default CASE speech fits at most45percent of actual height / "+str(dimensions))
		if dimensions.y < 640:
			check(board.has_method("set_drawer_expanded"),"default CASE has a reversible short tools drawer")
			if board.has_method("set_drawer_expanded"):
				board.call("set_drawer_expanded",true,false)
				await settle()
				check_full_height(board.get("paper") as Control,"default CASE short paper")
				board.call("set_drawer_expanded",false,false)
				await settle()
				var toggle: Control = board.get("drawer_toggle")
				check(toggle != null and toggle.is_visible_in_tree() and fits(toggle),"default CASE drawer can be reopened from visible control")
				if toggle != null: check(not css_rect(toggle).intersects(css_rect(main.shell_header)),"closed CASE bookmark does not cover header actions")
	check(game.snapshot() == before and FileAccess.get_sha256(save_path) == disk_hash,"CASE resize and drawer toggles preserve complete save and disk bytes")
	check((await main.run_action("set_free_question",{"enabled":true})).get("success",false),"enable real saved optional conversation")
	await measure(Vector2i(1280,529))
	var dialogue: Control = consultation.get("dialogue_panel")
	check(dialogue != null and dialogue.is_visible_in_tree() and fits(dialogue) and css_rect(dialogue).size.y <= float(root.size.y)*0.45+1,"optional real conversation stays within45percent of short client height")
	for property: String in ["input","send_button"]:
		var control: Control = consultation.get(property)
		check(control != null and control.is_visible_in_tree() and fits(control),"complete optional input control remains inside short window / "+property)
	before = game.snapshot()
	disk_hash = FileAccess.get_sha256(save_path)
	main.show_screen("front")
	await settle()
	var drawer: Control = main.screen.get_node_or_null("FrontDrawer")
	check(drawer != null,"real front retains its paper drawer")
	if drawer != null:
		drawer.call("set_expanded",true,false)
		await settle()
		check_full_height(drawer.get("panel") as Control,"front short drawer")
		drawer.call("set_expanded",false,false)
		await settle()
		check(not css_rect(drawer.get("bookmark") as Control).intersects(css_rect(main.shell_header)),"closed front bookmark does not cover header actions")
	check(game.snapshot() == before and FileAccess.get_sha256(save_path) == disk_hash,"front drawer presentation changes no saved fact")
	await finish()

func finish() -> void:
	if is_instance_valid(main):
		check(await main.prepare_close_async(),"actual Main releases TITLE and MUSIC lifecycle resources")
		main.queue_free()
	await Teardown.drain(self)
	print("POLISH LAYOUT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

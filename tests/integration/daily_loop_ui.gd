extends SceneTree
## Real UI commands and save failures exercise the committed daily-loop view.
const UITeardown = preload("res://tests/ui_teardown.gd")
const SIZES := [Vector2i(1280,720),Vector2i(1920,1080)]
const CAPTURE_DIR := "res://.tools/c-ui-captures"
var game: Node
var saves: Node
var main: Control
var checks := 0
var failures := 0
var captures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("DAILY LOOP UI FAIL: "+label)

func settle() -> void:
	for frame: int in range(15):
		await process_frame

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/daily-loop-ui-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"每日接待界面验收"})).get("success",false),"new game is created through the real UI command")
	await settle()
	check(not main.screen.wait_button.visible and not main.screen.rest_button.visible,"default front removes waiting and rest entrances")
	check(not main.screen.guest_picker.visible and not main.screen.patience_list.visible,"default front removes arbitrary guest choice and patience")
	check(game.has_method("daily_loop_view"),"core exposes a public committed daily-loop view")
	if not game.has_method("daily_loop_view"):
		await finish()
		return
	var view: Dictionary = game.daily_loop_view()
	check(view.enabled and view.phase == "morning","new game opens at morning letters")
	var letters: Button = main.screen.find_child("ReadMorningLetters",true,false)
	check(letters != null and letters.visible and not letters.disabled,"morning letter action is available")
	check(main.screen.begin_button.disabled,"morning cannot start reception before reading letters")
	await capture_sizes("morning")
	if letters == null:
		await finish()
		return
	var before: Dictionary = game.snapshot()
	saves.fail_next_write = true
	letters.pressed.emit()
	await settle()
	check(game.snapshot() == before and game.daily_loop_view().phase == "morning","failed morning save preserves state and phase")
	check(letters.visible and not letters.disabled and main.screen.begin_button.disabled,"failed morning save retains the morning controls")
	letters.pressed.emit()
	await settle()
	check(game.daily_loop_view().phase == "reception" and not main.screen.begin_button.disabled,"reading saved letters unlocks the next customer")
	check(not letters.visible,"committed reading removes the morning action")
	var total := int(game.daily_loop_view().total)
	for index: int in range(total):
		before = game.snapshot()
		if index == 0:
			saves.fail_next_write = true
			main.screen.begin_button.pressed.emit()
			await settle()
			check(game.snapshot() == before and main.current_screen == "front","failed next-customer save does not enter consultation")
		main.screen.begin_button.pressed.emit()
		await settle()
		check(main.current_screen == "consultation" and not game.active_visit().is_empty(),"next customer immediately opens a real consultation / "+str(index))
		check((await main.run_action("end_visit")).get("success",false),"real consultation ends / "+str(index))
		await settle()
		check(main.current_screen == "front" and int(game.daily_loop_view().completed) == index+1,"front reflects only committed reception progress / "+str(index))
		if index == 0:
			check(not main.screen.begin_button.disabled,"first completion immediately offers the next customer")
			await capture_sizes("served")
	check(main.screen.begin_button.disabled and not main.screen.next_button.disabled,"all customers served enables closing instead of more admissions")
	before = game.snapshot()
	saves.fail_next_write = true
	main.screen.next_button.pressed.emit()
	await settle()
	check(game.snapshot() == before and game.daily_loop_view().phase == "reception","failed closing save leaves reception and resources unchanged")
	main.screen.next_button.pressed.emit()
	await settle()
	check(game.daily_loop_view().phase == "closing","closing button commits the night summary")
	var summary: Label = main.screen.find_child("DailyLoopSummary",true,false)
	var monologue: Label = main.screen.find_child("DailyLoopMonologue",true,false)
	check(summary != null and summary.visible and not summary.text.is_empty(),"night summary shows saved stars and resource changes")
	check(monologue != null and monologue.visible and not monologue.text.is_empty(),"night summary includes the shopkeeper's saved monologue")
	check(main.screen.scene_visual.current_period == "night","closing shows the actual saved night storefront")
	await capture_sizes("closing")
	main.screen.next_button.pressed.emit()
	await settle()
	check(game.daily_loop_view().phase == "morning" and int(game.daily_loop_view().day) == 2,"next day returns to morning letters")
	check(int(game.player_snapshot().player.energy) == 100,"next-day controls show the restored daily energy")
	await finish()

func capture_sizes(phase: String) -> void:
	var before: Dictionary = game.snapshot()
	for dimensions: Vector2i in SIZES:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		var panel: Control = main.screen.find_child("DailyLoopPanel",true,false)
		check(panel != null and panel.visible,"daily journal is displayed / "+phase+" / "+str(dimensions))
		check(not main.screen.wait_button.visible and not main.screen.rest_button.visible,"no waiting controls reappear after refresh / "+phase+" / "+str(dimensions))
		check_buttons(main.screen,phase+" / "+str(dimensions))
		check(Rect2(Vector2.ZERO,main.size).encloses(main.resources.get_global_rect()),"daily header fits window / "+str(dimensions))
		if DisplayServer.get_name() != "headless":
			await create_timer(0.25).timeout
			RenderingServer.force_draw()
			DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
			var path := CAPTURE_DIR+"/r3-loop-"+phase+"-"+str(dimensions.x)+"x"+str(dimensions.y)+".png"
			check(root.get_texture().get_image().save_png(path) == OK,"save graphical capture / "+path)
			captures += 1
	check(game.snapshot() == before,"resizing daily journal does not change saved state / "+phase)

func check_buttons(node: Node, label: String, scroll: ScrollContainer = null) -> void:
	if node is ScrollContainer:
		scroll = node
	if node is Button and node.is_visible_in_tree():
		var bounds: Rect2 = node.get_global_rect()
		if scroll == null:
			check(Rect2(Vector2.ZERO,main.size).grow(1).encloses(bounds),"button fits window / "+label+" / "+node.name)
		else:
			var viewport: Rect2 = scroll.get_global_rect()
			check(bounds.position.x >= viewport.position.x-1 and bounds.end.x <= viewport.end.x+1,"journal button fits scroll width / "+label+" / "+node.name)
	for child: Node in node.get_children():
		check_buttons(child,label,scroll)

func finish() -> void:
	print("DAILY LOOP UI: %d checks, %d failures, %d graphical captures; renderer=%s"%[checks,failures,captures,DisplayServer.get_name()])
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

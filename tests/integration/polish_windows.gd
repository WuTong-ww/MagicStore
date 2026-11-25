extends SceneTree
## Real Main modal geometry and repeated-open scaling regression.
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
		printerr("RESPONSIVE WINDOWS FAIL: "+label)

func settle() -> void:
	for index: int in range(14): await process_frame

func inspect(window: Window, label: String) -> void:
	check(window != null and window.visible,"real modal opens / "+label)
	if window == null or not window.visible: return
	var logical: Vector2 = root.get_visible_rect().size
	var css_per_unit := Vector2(root.size)/logical
	var bounds := Rect2(Vector2(window.position)*css_per_unit,Vector2(window.size)*css_per_unit)
	check(Rect2(Vector2(-1,-1),Vector2(root.size)+Vector2(2,2)).encloses(bounds),"complete modal fits actual client / "+label)
	check(window.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT and window.content_scale_size.x > 0 and window.content_scale_size.y > 0,"modal retains an independent complete design basis and scales the entire paper / "+label)
	var inner: Vector2 = window.get_visible_rect().size
	var minimum: Vector2 = window.get_contents_minimum_size().max(Vector2(window.min_size))
	check(inner.x+1 >= minimum.x and inner.y+1 >= minimum.y,"content is uniformly fitted without squeezing its combined minimum / "+label)
	check(root.content_scale_size == Vector2i(1920,1080),"modal fitting never overwrites production root stretch / "+label)
	window.hide()

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	saves.base_dir = "res://.tools/r3-polish/modal-saves/"+game.make_id("run")
	root.gui_embed_subwindows = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await settle()
	check(main.has_method("presentation_metrics"),"first responsive Main integration exists")
	if not main.has_method("presentation_metrics"):
		await finish()
		return
	check((await main.run_action("new_game",{"name":"完整弹窗布局"})).get("success",false),"create genuine isolated sequential save")
	check((await main.run_action("read_morning_letters")).get("success",false),"read actual morning letters")
	check((await main.run_action("next_customer")).get("success",false),"start a real CASE visit for modal views")
	var before: Dictionary = game.snapshot()
	var save_path: String = saves._path(str(before.save_id))
	var disk_hash: String = FileAccess.get_sha256(save_path)
	for dimensions: Vector2i in SIZES:
		root.size = dimensions
		await settle()
		main.open_saves()
		await settle()
		var save_basis: Vector2i = main.save_window.content_scale_size
		inspect(main.save_window,"save / "+str(dimensions))
		main.open_saves()
		await settle()
		check(main.save_window.content_scale_size == save_basis,"reopening the fitted book never turns its display size into a new design size / "+str(dimensions))
		main.save_window.hide()
		main.open_people()
		await settle()
		inspect(main.people_window,"people / "+str(dimensions))
		check(main.show_history(),"open actual visit history / "+str(dimensions))
		await settle()
		inspect(main.history_window,"history / "+str(dimensions))
		main.open_divination("tarot")
		await settle()
		inspect(main.workbench,"workbench / "+str(dimensions))
		main.open_network_settings()
		await settle()
		var shown: Array[Window] = []
		for child: Node in main.get_children():
			if child is Window and child.visible: shown.append(child)
		check(shown.size() == 1,"exactly the real settings modal is visible / "+str(dimensions))
		if shown.size() == 1: inspect(shown[0],"settings / "+str(dimensions))
	check(game.snapshot() == before and FileAccess.get_sha256(save_path) == disk_hash,"opening and fitting all modals changes no world/disk fact")
	await finish()

func finish() -> void:
	if is_instance_valid(main):
		for child: Node in main.get_children():
			if child is Window: child.hide()
		check(await main.prepare_close_async(),"close actual TITLE/MUSIC resources")
		main.queue_free()
	await Teardown.drain(self)
	print("RESPONSIVE WINDOWS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

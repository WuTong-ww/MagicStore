extends SceneTree
## First wheel after crossing into an embedded window must use current coordinates.
const Pointer = preload("res://scripts/ui/web_wheel_pointer.gd")
const Teardown = preload("res://tests/ui_teardown.gd")
var checks := 0
var failures := 0
var main: Control
var pointer := Pointer.new()

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("WEB WHEEL POINTER FAIL: "+label)
func settle() -> void:
	for frame: int in range(12): await process_frame
func wheel_at(control: Control, down: bool) -> void:
	var point := control.get_global_transform_with_canvas()*(control.size*0.5)
	var local_point: Vector2 = root.get_screen_transform().affine_inverse()*(control.get_viewport().get_screen_transform()*point)
	var native_point := root.get_final_transform()*local_point
	# The old pointer is outside the scrolling window. No click primes it.
	check(pointer.sync_pointer(Vector2.ZERO),"prime a stale pointer outside the content")
	check(pointer.sync_pointer(native_point),"synchronously apply the wheel's current backing coordinates")
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = native_point
		event.global_position = native_point
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await settle()
func run() -> void:
	var game: Node = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	saves.base_dir = "res://.tools/r3-web/wheel-pointer-saves/"+game.make_id("run")
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280,529)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await settle()
	check((await main.run_action("new_game",{"name":"滚轮定位验收"})).get("success",false),"create an isolated real save")
	await settle()
	var before: Dictionary = game.snapshot()
	var path: String = saves._path(str(before.save_id))
	var disk_sha := FileAccess.get_sha256(path)
	check(main.open_learning(),"open the actual nine-course window")
	await settle()
	var scroll: ScrollContainer = main.learning_window.find_child("LearningListScroll",true,false)
	check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,"real course content overflows")
	if scroll != null:
		var previous := scroll.scroll_vertical
		await wheel_at(scroll,true)
		check(scroll.scroll_vertical > previous,"first down wheel routes from the root into the embedded window without a click")
		await wheel_at(scroll,false)
		check(scroll.scroll_vertical == previous,"first up wheel returns to the original position")
	check(not pointer.sync_pointer(Vector2(NAN,0)),"reject non-finite coordinates")
	check(game.snapshot()==before and FileAccess.get_sha256(path)==disk_sha,"wheel routing leaves the world and persisted bytes unchanged")
	main.learning_window.hide()
	check(await main.prepare_close_async(),"release presentation resources")
	main.queue_free()
	await Teardown.drain(self)
	print("WEB WHEEL POINTER: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

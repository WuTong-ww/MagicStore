extends SceneTree
## GUI dispatch regression. Scrollbar values are observed, never assigned.
## Actual trusted DOM wheel delivery is checked separately in the Web probe.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Drawer = preload("res://scripts/ui/paper_drawer.gd")
const Teardown = preload("res://tests/ui_teardown.gd")
var checks := 0
var failures := 0
var main: Control

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH WHEEL FAIL: "+label)
func settle() -> void:
	for frame: int in range(10): await process_frame
func wheel(scroll: ScrollContainer, down: bool) -> void:
	var point := scroll.get_global_rect().get_center()
	var viewport: Viewport = scroll.get_viewport()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	event.position = point
	event.global_position = point
	event.pressed = true
	viewport.push_input(event,true)
	await settle()

func run() -> void:
	var game: Node = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-polish/wheel-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.size = Vector2i(1280,529)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"滚轮验收"})).get("success",false),"create only through the saved action boundary")
	await settle()
	var before: Dictionary = game.snapshot()
	var save_path: String = saves._path(str(before.save_id))
	var disk_sha := FileAccess.get_sha256(save_path)
	main.open_network_settings()
	await settle()
	var scroll: ScrollContainer = main.find_child("SettingsLetterScroll",true,false)
	check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,"real settings letter has overflow to exercise")
	if scroll != null:
		var previous := scroll.scroll_vertical
		await wheel(scroll,true)
		check(scroll.scroll_vertical > previous,"wheel over real modal content scrolls down")
		await wheel(scroll,false)
		check(scroll.scroll_vertical == previous,"wheel scrolls the modal back up")
		scroll.get_window().hide()
	var drawer: Control = Drawer.new()
	root.add_child(drawer)
	drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await settle()
	var label: Label = UI.label(main.shell_config.brand,18)
	label.custom_minimum_size.y = drawer.panel.size.y*3.0
	drawer.content.add_child(label)
	await settle()
	var left: ScrollContainer = drawer.notebook_pages.left_scroll
	var right: ScrollContainer = drawer.notebook_pages.right_scroll
	check(left.get_v_scroll_bar().max_value > left.get_v_scroll_bar().page,"actual drawer page contains a long readable object")
	await wheel(left,true)
	check(left.scroll_vertical > 0 and right.scroll_vertical == 0,"wheel over text reaches its drawer page and leaves the other page still")
	await wheel(left,false)
	check(left.scroll_vertical == 0,"drawer wheel returns to its upper boundary")
	check(game.snapshot() == before and FileAccess.get_sha256(save_path) == disk_sha,"wheel navigation changes neither world nor persisted save")
	drawer.queue_free()
	check(await main.prepare_close_async(),"close real presentation resources")
	main.queue_free()
	await Teardown.drain(self)
	print("POLISH WHEEL: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

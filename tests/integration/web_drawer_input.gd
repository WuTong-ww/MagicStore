extends SceneTree
## Real pointer dispatch: visible notebook controls must win over overlapping chrome.
const Teardown = preload("res://tests/ui_teardown.gd")
var checks := 0
var failures := 0
var main: Control

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("WEB DRAWER INPUT FAIL: "+label)
func settle() -> void:
	for frame: int in range(12): await process_frame
func pointer(control: Control, button: int = MOUSE_BUTTON_LEFT) -> void:
	var point: Vector2 = control.get_global_transform_with_canvas()*(control.size*0.5)
	var viewport: Viewport = control.get_viewport()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.global_position = point
	event.pressed = true
	viewport.push_input(event,true)
	if button == MOUSE_BUTTON_LEFT:
		event = event.duplicate()
		event.pressed = false
		viewport.push_input(event,true)
	await settle()
func settings_open() -> bool:
	return main.get_children().any(func(node: Node) -> bool:
		return node is Window and node.visible and node.title == "设置")
func run() -> void:
	var game: Node = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	saves.base_dir = "res://.tools/r3-web/drawer-input-saves/"+game.make_id("run")
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280,529)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await settle()
	check((await main.run_action("new_game",{"name":"抽屉点击验收"})).get("success",false),"create isolated save through the real action boundary")
	await settle()
	var before: Dictionary = game.snapshot()
	var path: String = saves._path(str(before.save_id))
	var disk_sha := FileAccess.get_sha256(path)
	var drawer: Control = main.screen.get_node("FrontDrawer")
	var study: Button = main.screen.study_button
	check(drawer.panel.is_visible_in_tree() and study.is_visible_in_tree(),"real expanded front notebook exposes its study button")
	await pointer(study)
	check(is_instance_valid(main.learning_window) and main.learning_window.visible,"clicking the visible study button opens the course window")
	check(not settings_open(),"the overlapping wooden settings button does not receive that click")
	if is_instance_valid(main.learning_window) and main.learning_window.visible:
		var scroll: ScrollContainer = main.learning_window.find_child("LearningListScroll",true,false)
		check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,"real nine-course content overflows its fitted short window")
		if scroll != null:
			var previous := scroll.scroll_vertical
			await pointer(scroll,MOUSE_BUTTON_WHEEL_DOWN)
			check(scroll.scroll_vertical > previous,"wheel over the real course window moves its content")
			await pointer(scroll,MOUSE_BUTTON_WHEEL_UP)
			check(scroll.scroll_vertical == previous,"wheel returns the real course content to its original position")
		main.learning_window.hide()
	await settle()
	await pointer(drawer.bookmark)
	check(not drawer.expanded,"the visible bookmark closes the overlay")
	var settings: Array[Node] = main.shell_header.get_child(0).get_children().filter(func(node: Node) -> bool:
		return node is Button and node.text == str(main.shell_config.settings_label))
	check(settings.size()==1,"the regular settings control remains available")
	if settings.size()==1:
		await pointer(settings[0])
		check(settings_open(),"closing the notebook restores normal header hit testing")
	for child: Node in main.get_children():
		if child is Window and child.visible: child.hide()
	check(game.snapshot()==before and FileAccess.get_sha256(path)==disk_sha,"presentation clicks and wheel leave the complete world and saved bytes unchanged")
	check(await main.prepare_close_async(),"release real presentation resources")
	main.queue_free()
	await Teardown.drain(self)
	print("WEB DRAWER INPUT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

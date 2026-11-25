extends SceneTree
const Teardown = preload("res://tests/ui_teardown.gd")
var checks := 0
var failures := 0
var main: Control

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SURFACE CONSUMERS FAIL: "+label)

func settle() -> void:
	for frame: int in range(12): await process_frame

func run() -> void:
	var game: Node = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	saves.base_dir = "res://.tools/r3-polish/surface-saves/"+game.make_id("run")
	root.size = Vector2i(1280,720)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"物件面板验收"})).get("success",false),"create through the actual saved action")
	check(main.shell_header.get_meta("material_role","") == "wood" and main.shell_dock.get_meta("material_role","") == "wood","header and navigation are the same single wooden material")
	var front: Control = main.screen.get_node("FrontDrawer")
	check(front.panel.get_meta("material_role","") == "notebook","front controls occupy a leather notebook")
	check(front.has_node("PaperPanel/DrawerNotebookPages"),"front notebook keeps two real page viewports off its spine")
	var before: Dictionary = game.snapshot()
	var disk: String = FileAccess.get_sha256(saves._path(str(before.save_id)))
	var front_was_visible := front.visible
	main.open_saves()
	await settle()
	check(main.save_window.get_node("PaperWindowBackground").get_meta("material_role","") == "notebook" and main.save_window.has_node("SaveNotebookPages"),"save book has one material and two live pages")
	check(not front.visible and main.scene_holder.visible,"save book hides other UI panels while retaining actual scene art")
	var overlays: Array[Node] = main.find_children("*","ColorRect",true,false).filter(func(node: Node) -> bool: return node.get_meta("material_modal_backdrop",false) and node.is_visible_in_tree())
	check(overlays.size() == 1 and is_equal_approx(overlays[0].color.a,0.15),"exactly one data-owned fifteen-percent modal dimmer is visible")
	check(not main.people_window.visible and not main.history_window.visible and not main.workbench.visible,"save book hides every competing popup")
	main.save_window.hide()
	await settle()
	check(front.visible == front_was_visible,"closing the book restores the prior panel presentation")
	main.open_network_settings()
	await settle()
	var settings: Window
	for node: Node in main.get_children():
		if node is Window and node.title == "设置" and node.visible: settings = node
	check(settings != null and settings.has_node("PaperWindowBackground") and settings.get_node("PaperWindowBackground").get_meta("material_role","") == "dialogue","settings are one actual letter sheet")
	if settings != null:
		check(settings.has_node("SettingsLetterScroll"),"settings preserve complete content with a real scroll container")
		settings.hide()
		settings.queue_free()
	await settle()
	main.show_screen("inventory")
	await settle()
	var drawer: Control = main.screen.drawer
	check(drawer.panel.get_meta("material_role","") == "notebook" and drawer.has_node("PaperPanel/DrawerNotebookPages"),"inventory ledger is another real two-page notebook")
	check(game.snapshot() == before and FileAccess.get_sha256(saves._path(str(before.save_id))) == disk,"all material/modal/navigation changes preserve the complete save and disk")
	check(await main.prepare_close_async(),"presentation releases actual TITLE/MUSIC resources")
	main.queue_free()
	await Teardown.drain(self)
	print("SURFACE CONSUMERS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

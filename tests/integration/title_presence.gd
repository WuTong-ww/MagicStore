extends SceneTree
## Future behavioral RED. UNRUN. Does not preload any future TITLE class.
## The current AICASE Main scene is independently loadable before TITLE exists.
var checks := 0
var failures := 0
var main: Control

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TITLE PRESENCE FAIL: "+label)

func run() -> void:
	var game: Node = root.get_node("GameState")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.get_node("SaveService").base_dir = "res://.tools/r3-title/presence/"+game.make_id("run")
	var before: Dictionary = game.snapshot()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	check(main.has_method("ui_new_game_intent"),"existing Main exposes the stable UI creation intent")
	check(main.has_method("set_title_blocking"),"existing Main installs the TITLE modal input boundary")
	check(main.has_node("TitleControl"),"startup installs a real TitleControl node")
	var title: Control = main.get_node_or_null("TitleControl")
	check(is_instance_valid(title) and title.visible,"startup shows TITLE before an explicit user action")
	if is_instance_valid(title):
		var menus: Array[Node] = title.find_children("TitleMenu_*","Button",true,false)
		check(menus.size() == 4,"four real wooden-sign menu controls exist")
		for id: String in ["continue","new","settings","credits"]:
			check(title.find_child("TitleMenu_"+id,true,false) != null,"expected menu control / "+id)
	var save_window: Window = main.get("save_window")
	check(not save_window.visible,"startup no longer auto-opens the save book")
	check(game.snapshot() == before,"the TITLE presence probe changes no saved game state")
	check(await main.prepare_close_async(),"existing Main releases its real presentation resources")
	main.queue_free()
	await process_frame
	await process_frame
	print("TITLE PRESENCE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

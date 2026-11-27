extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
## Production content stays separate from test fixtures and old-save records.
const Loader = preload("res://scripts/core/content_loader.gd")
var game: Node
var main: Control
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PROJECT CLEANUP: "+label)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(ProjectSettings.get_setting("display/window/size/window_width_override"),ProjectSettings.get_setting("display/window/size/window_height_override"))
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	game.set_people_generation_options(false)
	root.get_node("SaveService").base_dir = "res://.tools/test-project-cleanup/"+game.make_id("run")
	for removed: String in ["start-people-demo.cmd","scripts/dev/run-people-demo.ps1","scenes/people/people_demo.tscn","scripts/people/people_demo.gd","tests/people/demo.gd","scripts/divination/demo_economy.gd"]:
		check(not FileAccess.file_exists("res://"+removed),"obsolete standalone entry is removed: "+removed)
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	check(not authored.has("cards") and not str(authored.npc.returning).contains("演示"),"active story data does not contain legacy card samples or developer dialogue")
	var loaded := Loader.load_content()
	check(loaded.success and loaded.content.cards.size() == 3 and loaded.content.cards.map(func(row: Dictionary) -> String: return row.card_id) == ["star","hermit","temperance"],"original single-card IDs remain available through the compatibility loader")
	var previous_fixture_flag := OS.get_environment("MAGIC_DEV_FIXTURES")
	OS.set_environment("MAGIC_DEV_FIXTURES","1")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check((await main.run_action("new_game",{"name":"正式入口清理验证"})).success,"new actual save can be created after content separation")
	check(game.snapshot().npcs.keys() == ["npc_lin"],"a new game does not preload ordinary or reference demo wallets")
	check(game.snapshot().people.families.is_empty() and not game._divination.data.guests.keys().any(func(id: String) -> bool: return id.begins_with("npc_demo_")),"fresh people and case catalogs contain no demonstration family or guests")
	var queue: Array = game.people_view().queue
	check(main.screen.guests.size() == queue.size() and main.screen.guests.all(func(row: Dictionary) -> bool: return row.has("arrival_id") and queue.any(func(arrival: Dictionary) -> bool: return row.arrival_id == arrival.arrival_id)),"old developer environment switch cannot bypass the actual arrival queue")
	check(game._divination.data.decks.tarot.size() == 78,"current readings still use the full tarot deck")
	check((await main.run_action("start_visit")).success,"fixed story reception remains usable")
	var reply: Dictionary = await main.run_action("reading")
	check(reply.success and game.active_visit().reading.get("cards",[]).size() == 3,"a paid reading still records its actual three-card spread")
	check(root.get_node("SaveService").read_save(game.state.save_id).success,"current saved game validates with separate compatibility records")
	OS.set_environment("MAGIC_DEV_FIXTURES",previous_fixture_flag)
	print("PROJECT CLEANUP RESULT: %d checks, %d failures" % [checks,failures])
	await UITeardown.drain(self)
	quit(0 if failures == 0 else 1)

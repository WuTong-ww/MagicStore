extends SceneTree
## Two independent processes verify the integrated A/B/C save, not a second A save file.

const Bridge = preload("res://scripts/shop/people_bridge.gd")
const FILE := "user://test-restart-integrated-people/index.json"
var gs: Node
var saves: Node
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error("INTEGRATED PEOPLE RESTART: " + message)

func act(kind: String, extra: Dictionary = {}) -> Dictionary:
	var request := {"type": kind, "action_id": gs.make_id("restart_people")}
	request.merge(extra, true)
	var result: Dictionary = gs.execute_action(request)
	check(result.success, kind + " / " + str(result.get("message", "")))
	return result

func run() -> void:
	gs = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "user://test-restart-integrated-people/saves"
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args[0] not in ["write", "read"]:
		check(false, "Choose write or read")
	elif args[0] == "write":
		write_fixture()
	else:
		read_fixture()
	quit(1 if failed else 0)

func write_fixture() -> void:
	act("new_game", {"name": "整合跨进程恢复"})
	var queue: Array = Bridge.public_view(gs.state).queue
	var arrival: Dictionary = queue.filter(func(row: Dictionary) -> bool: return row.npc_id == "npc_lin")[0]
	act("start_arrival", {"arrival_id": arrival.arrival_id})
	act("talk", {"text": "为什么还没回信？", "topic_id": "letter"})
	act("reading")
	act("save_appearance", {"appearance": {"face": "face_02", "hair": "hair_03", "outfit": "outfit_01"}})
	# A known uncommon appointment is introduced as reproducible test setup.
	var waiting: Dictionary = Bridge._arrival("arrival_restart_appointment", "npc_lin_friend", int(gs.state.clock_minutes), "natural", "archive")
	gs.state.people.arrivals[waiting.arrival_id] = waiting
	Bridge.People.advance(gs.state.people, gs.people_config, int(gs.state.clock_minutes))
	act("book_arrival", {"arrival_id": waiting.arrival_id, "at": int(gs.state.clock_minutes) + 1440, "guest_agreed": true})
	var file := FileAccess.open(FILE, FileAccess.WRITE)
	check(file != null, "can write index beside isolated saves")
	if file != null:
		file.store_string(JSON.stringify(gs.snapshot()))
		file.close()
	print("INTEGRATED PEOPLE RESTART WRITE: saved active paid visit, shared memory, appearance, appointment and wallets")

func read_fixture() -> void:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(FILE)) != OK or not parser.data is Dictionary:
		check(false, "cannot read restart index")
		return
	var expected: Dictionary = saves._normalize_numbers(parser.data)
	act("load_game", {"save_id": expected.save_id})
	check(gs.state.people == expected.people, "A identity, memory, appearance and appointment preserved")
	check(gs.state.npcs == expected.npcs and gs.state.player == expected.player, "wallet and inventory preserved")
	check(gs.state.active_visit_id == expected.active_visit_id and gs.state.visits == expected.visits, "unfinished B visit and original cards preserved")
	check(Bridge.validate(gs.state).is_empty(), "all cross-module references remain valid")
	var before: Dictionary = gs.snapshot()
	act("reading")
	check(gs.snapshot() == before, "paid reading replay does not charge or alter A data")
	act("end_visit")
	check(gs.state.people.profiles.npc_lin.familiarity == 1, "resumed encounter completes once")
	print("INTEGRATED PEOPLE RESTART READ: original people, queue, resources and paid encounter restored")

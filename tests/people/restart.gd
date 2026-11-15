extends SceneTree

const People = preload("res://scripts/people/people.gd")
const Memory = preload("res://scripts/people/memory.gd")
const FILE := "user://people-test/roundtrip.json"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args[0] not in ["write", "read"]:
		push_error("Choose write or read")
		quit(1)
		return
	if args[0] == "write":
		write_fixture()
	else:
		read_fixture()

func fail(message: String) -> void:
	push_error("PEOPLE RESTART FAIL: " + message)
	quit(1)

func write_fixture() -> void:
	var config := People.load_config()
	config.arrival.family_percent = 0
	var people := People.create("save_restart_people", 912, 540)
	People.plan_day(people, config, 0, 0, 1)
	var arrival: Dictionary = people.arrivals.arrival_0_0
	arrival.at = 600
	arrival.schedule_end = 800
	People.advance(people, config, 600)
	if not People.begin(people, arrival.arrival_id, "visit_restart"):
		fail("could not begin")
		return
	if not Memory.record(people, arrival.npc_id, {"memory_id": "memory_restart", "visit_id": "visit_restart", "topic_id": "friend", "kind": "statement", "audience": "both", "text": "想和朋友重新联系", "source_id": "action_restart"}):
		fail("could not record memory")
		return
	if not People.finish(people, arrival.arrival_id, "visit_restart", "聊了朋友") or not People.validate(people).is_empty():
		fail("invalid fixture")
		return
	var profile: Dictionary = people.profiles[arrival.npc_id]
	var fixture := {"state": people, "expected": {"npc_id": arrival.npc_id, "name": profile.name,
		"appearance": profile.appearance.duplicate(true), "memory_id": "memory_restart"}}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://people-test")) != OK:
		fail("cannot create isolated test directory")
		return
	var file := FileAccess.open(FILE, FileAccess.WRITE)
	if file == null:
		fail("cannot write fixture")
		return
	file.store_string(JSON.stringify(fixture))
	file.flush()
	file.close()
	print("PEOPLE RESTART WRITE: stable person, relationship and memory saved to isolated fixture")
	quit(0)

func read_fixture() -> void:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(FILE)) != OK or not parser.data is Dictionary:
		fail("cannot read fixture")
		return
	var fixture: Dictionary = parser.data
	var people: Dictionary = fixture.get("state", {})
	var expected: Dictionary = fixture.get("expected", {})
	if not People.validate(people).is_empty() or not people.profiles.has(expected.get("npc_id")):
		fail("restored structure invalid")
		return
	var profile: Dictionary = people.profiles[expected.npc_id]
	if profile.name != expected.name or profile.appearance != expected.appearance or not profile.met or int(profile.familiarity) != 1:
		fail("identity changed across process")
		return
	var visible := Memory.visible(people, expected.npc_id, "player")
	if visible.size() != 1 or visible[0].memory_id != expected.memory_id or Memory.followups(people, expected.npc_id, "visit_return").is_empty():
		fail("memory or followup lost")
		return
	var next_return := People._next_return_slot(profile, 1440 + 600)
	if not People.schedule_return(people, expected.npc_id, "arrival_restart_return", next_return):
		fail("same person cannot return")
		return
	if people.arrivals.arrival_restart_return.npc_id != expected.npc_id:
		fail("return identity changed")
		return
	print("PEOPLE RESTART READ: original identity, appearance, history and followup restored")
	quit(0)

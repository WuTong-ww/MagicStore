extends SceneTree
## The shared v3 character configuration must retain the strict dialogue boundary.
const Policy = preload("res://scripts/providers/dialogue_policy.gd")
const Generated = preload("res://scripts/people/generated_person.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("NAMES DIALOGUE FAIL: "+label)
func run() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/people/character_protocol.json"))
	check(raw.size()==17 and Generated.protocol_valid(raw),"new shared character protocol is the complete validated v3 contract")
	check(Policy.settings_valid(raw) and not Policy.load_settings().is_empty(),"dialogue accepts the complete shared contract")
	for key: String in raw:
		var bad := raw.duplicate(true)
		bad.erase(key)
		check(not Policy.settings_valid(bad),"missing shared field is rejected / "+key)
	var bad := raw.duplicate(true)
	bad["unexpected"] = "not accepted"
	check(not Policy.settings_valid(bad),"extra configuration fields remain rejected")
	for field: String in ["bundle_version","default_bundle_version","birth_identity_version"]:
		bad = raw.duplicate(true)
		bad[field] = true
		check(not Policy.settings_valid(bad),"boolean version remains rejected / "+field)
	bad = raw.duplicate(true)
	bad.person_fields_v3 = raw.person_fields_v2
	check(not Policy.settings_valid(bad),"broken v3 person contract remains rejected")
	bad = raw.duplicate(true)
	bad.moods.append("angry")
	check(not Policy.settings_valid(bad),"extra mood remains rejected")
	var game: Node = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-names/dialogue-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.daily_loop_config.enabled = false
	check((await game.execute_action_async({"type":"new_game","name":"本地对白接线"})).success,"real new game succeeds with shared configuration")
	check((await game.execute_action_async({"type":"start_visit","action_id":"names_dialogue_start","npc_id":"npc_lin","case_id":"invitation"})).success,"real fixed consultation begins")
	var command := {"type":"talk","action_id":"names_dialogue_talk","topic_id":"letter","text":"为什么还没回信？"}
	var talked: Dictionary = await game.execute_action_async(command)
	check(talked.success,"actual local authored dialogue succeeds: "+str(talked))
	var committed: Dictionary = game.snapshot()
	check(talked.success and saves.read_save(committed.save_id).state==committed,"authored dialogue still crosses durable save boundary")
	var replayed: Dictionary = await game.execute_action_async(command)
	check(talked.success and replayed.get("replayed",false) and game.snapshot()==committed,"authored dialogue replay remains idempotent")
	print("NAMES DIALOGUE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

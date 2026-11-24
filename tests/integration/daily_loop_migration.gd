extends SceneTree
var checks := 0
var failures := 0
var game: Node
var saves: Node
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("DAILY MIGRATION FAIL: "+label)
func run() -> void:
	game = root.get_node("GameState")
	# Isolate the daily-flow contract while CASE separately tests the new board.
	game._divination.board_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-loop-migration/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.daily_loop_config.enabled = false
	check((await game.execute_action_async({"type":"new_game","name":"迁移源"})).success,"source creates")
	var old: Dictionary = game.snapshot()
	# A synthetic schema9 fixture cannot contain future birth-policy fields.
	old.people.erase("birth_identity_version")
	for profile: Dictionary in old.people.profiles.values():
		profile.erase("birth_identity")
	old.schema_version = 9
	check(not old.divination.has("emergent_cases") or old.divination.get("emergent_cases")=={"version":1,"instances":{}},"historical projection retains no populated schema14 ordinary-case namespace")
	old.divination.erase("emergent_cases")
	old.erase("daily_loop")
	check(saves.write_save(old).success,"historic schema9 validates")
	var path: String = saves._path(old.save_id)
	var sha := FileAccess.get_sha256(path)
	game.daily_loop_config.enabled = true
	check((await game.execute_action_async({"type":"load_game","save_id":old.save_id})).success,"historic schema9 loads")
	check(game.state.schema_version == SaveService.CURRENT_SCHEMA and game.state.has("daily_loop"),"old save migrates to explicit daily progress in memory")
	check(FileAccess.get_sha256(path) == sha,"load leaves historic bytes untouched")
	await active_schema9()
	await crowded_schema9()
	await mode_recovery()
	print("DAILY MIGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var command := {"type":kind,"action_id":game.make_id("migrate")}
	command.merge(fields,true)
	return await game.execute_action_async(command)

func active_schema9() -> void:
	game.daily_loop_config.enabled = false
	check((await act("new_game",{"name":"旧接待继续"})).success,"disabled flow creates a genuine legacy traffic baseline")
	check((await act("start_visit",{"npc_id":"npc_lin","case_id":"invitation"})).success,"legacy source has a genuine active visit")
	var talk_reply: Dictionary = await act("talk",{"text":"为什么还没回信？","topic_id":"letter"})
	check(talk_reply.success,"legacy source includes witnessed clues and conversation: "+str(talk_reply))
	var old: Dictionary = game.snapshot()
	# A synthetic schema9 fixture cannot contain future birth-policy fields.
	old.people.erase("birth_identity_version")
	for profile: Dictionary in old.people.profiles.values():
		profile.erase("birth_identity")
	old.schema_version = 9
	check(not old.divination.has("emergent_cases") or old.divination.get("emergent_cases")=={"version":1,"instances":{}},"historical projection retains no populated schema14 ordinary-case namespace")
	old.divination.erase("emergent_cases")
	old.erase("daily_loop")
	check(saves.write_save(old).success,"active schema9 envelope validates")
	var path: String = saves._path(old.save_id)
	var sha := FileAccess.get_sha256(path)
	game.daily_loop_config.enabled = true
	check((await act("load_game",{"save_id":old.save_id})).success,"active schema9 loads in sequential mode")
	var migrated: Dictionary = game.snapshot()
	check(migrated.schema_version == SaveService.CURRENT_SCHEMA and migrated.daily_loop.phase == "reception" and migrated.active_visit_id == old.active_visit_id,"migration adopts the real active visit without a morning lock")
	for key: String in ["player","npcs","clock_minutes","visits","processed_actions"]:
		check(migrated[key] == old[key],"migration preserves exact historic "+key)
	var historical_people: Dictionary = migrated.people.duplicate(true)
	check(historical_people.get("birth_identity_version",0)==1,"migration adds the checked birth-policy marker")
	historical_people.erase("birth_identity_version")
	var historical_divination: Dictionary = migrated.divination.duplicate(true)
	check(historical_divination.get("emergent_cases")=={"version":1,"instances":{}},"old daily progress gains only an empty schema14 ordinary-case namespace")
	historical_divination.erase("emergent_cases")
	check(historical_people == old.people and historical_divination == old.divination,"migration preserves people, old plans, outcomes and identities exactly")
	check(FileAccess.get_sha256(path) == sha and saves.read_save(old.save_id).state.schema_version == 9,"load never rewrites historical bytes")
	var command := {"type":"end_visit","action_id":game.make_id("first_save")}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.success and game.snapshot() == migrated and FileAccess.get_sha256(path) == sha,"failed first action keeps both migrated memory and old bytes")
	var ended: Dictionary = await game.execute_action_async(command)
	check(ended.success and game.daily_loop_view().completed == 1 and saves.read_save(old.save_id).state.schema_version == SaveService.CURRENT_SCHEMA,"same-ID retry ends the old visit and first persists current schema")
	var committed: Dictionary = game.snapshot()
	check((await game.execute_action_async(command)).get("replayed",false) and game.snapshot() == committed,"replay never completes the old visit twice")
	check((await act("next_customer")).success and game.state.active_visit_id != old.active_visit_id,"an old active visit can continue immediately into the next new slot")
	check(game.state.people.days == old.people.days,"sequential continuation never recalculates an old day plan")
	var reloaded: Dictionary = game.snapshot()
	check((await act("load_game",{"save_id":old.save_id})).success and game.snapshot() == reloaded,"active schema10 reloads exact progress")
	var bad: Dictionary = reloaded.duplicate(true)
	bad.erase("daily_loop")
	check(not saves.validate_snapshot(bad).success,"schema10 requires its explicit namespace")
	bad = reloaded.duplicate(true)
	bad.daily_loop.cursor = bad.daily_loop.arrival_ids.size()+1
	check(not saves.validate_snapshot(bad).success,"invalid progress cannot skip unserved customers")

func crowded_schema9() -> void:
	game.daily_loop_config.enabled = false
	check((await act("new_game",{"name":"旧日满员"})).success,"legacy full-day source creates")
	var old: Dictionary = game.snapshot()
	# A synthetic schema9 fixture cannot contain future birth-policy fields.
	old.people.erase("birth_identity_version")
	for profile: Dictionary in old.people.profiles.values():
		profile.erase("birth_identity")
	old.schema_version = 9
	check(not old.divination.has("emergent_cases") or old.divination.get("emergent_cases")=={"version":1,"instances":{}},"historical projection retains no populated schema14 ordinary-case namespace")
	old.divination.erase("emergent_cases")
	old.erase("daily_loop")
	# Historic planned traffic may already occupy every slot before migration.
	for row: Dictionary in old.people.arrivals.values():
		if row.state == "queued":
			row.state = "left"
	var people = load("res://scripts/people/people.gd")
	var day := floori(float(old.clock_minutes)/1440.0)
	var added := 0
	while people.arrival_count_on_day(old.people,day) < 20:
		var id := "arrival_full_"+str(added)
		old.people.arrivals[id] = {"arrival_id":id,"npc_id":"npc_lin","source":"natural","at":int(old.clock_minutes)+1,
			"deadline":-1,"state":"planned","intent":"divination","urgency":0,"schedule_end":1320,"referrer_npc_id":"","case_id":"invitation","visit_id":""}
		added += 1
	check(people.arrival_count_on_day(old.people,day) == 20 and saves.write_save(old).success,"schema9 with twenty real old arrival records is legal")
	var path: String = saves._path(old.save_id)
	var sha := FileAccess.get_sha256(path)
	game.daily_loop_config.enabled = true
	check((await act("load_game",{"save_id":old.save_id})).success,"a historically full day loads without rewriting bytes")
	var historical_people: Dictionary = game.state.people.duplicate(true)
	check(historical_people.get("birth_identity_version",0)==1,"full-day migration adds the checked birth-policy marker")
	historical_people.erase("birth_identity_version")
	check(historical_people == old.people and FileAccess.get_sha256(path) == sha,"full-day migration preserves every old person and arrival")
	var read: Dictionary = await act("read_morning_letters")
	check(read.success,"morning can reserve its separate sequential roster even after twenty old arrivals: "+str(read))
	if not read.success:
		return
	var count: int = game.daily_loop_view().total
	for index: int in range(count):
		check((await act("next_customer")).success,"full legacy day admits sequential slot "+str(index))
		check((await act("end_visit")).success,"full legacy day completes sequential slot "+str(index))
	check((await act("close_shop")).success and (await act("next_day")).success,"full legacy day can close and enter tomorrow")
	check(game.state.people.days == old.people.days,"old traffic plan is never recalculated")
	for id: String in old.people.arrivals:
		check(game.state.people.arrivals[id] == old.people.arrivals[id],"original arrival remains byte-equivalent after the new day / "+id)
	for id: String in old.people.profiles:
		var profile: Dictionary = game.state.people.profiles[id]
		check(profile.name == old.people.profiles[id].name and profile.appearance == old.people.profiles[id].appearance and profile.origin == old.people.profiles[id].origin,"old name, origin and appearance never reroll / "+id)
		if not game.state.visits.any(func(visit: Dictionary) -> bool: return visit.npc_id == id):
			check(profile == old.people.profiles[id],"unvisited old profile is unchanged / "+id)
	check(game.state.visits.size() == count and game.state.processed_actions.size() == old.processed_actions.size()+count*2+3,"migration adds only the real sequential visits and committed commands")
	var forged: Dictionary = game.snapshot()
	var row: Dictionary = old.people.arrivals[old.people.arrivals.keys()[0]].duplicate(true)
	row.merge({"arrival_id":"arrival_daily_100_0","source":"daily_loop","at":144000,"deadline":-1,"state":"planned","visit_id":"","case_id":"archive","intent":"divination","daily_kind":"case","daily_loop_day":100,"daily_loop_index":0},true)
	forged.people.arrivals[row.arrival_id] = row
	check(people.sequential_arrival(row) and not saves.validate_snapshot(forged).success,"a locally well-formed daily source still requires a real roster reference")
	var historic_forgery: Dictionary = old.duplicate(true)
	historic_forgery.people.arrivals[row.arrival_id] = row
	check(not saves.validate_snapshot(historic_forgery).success,"schema9 cannot use a future source marker to bypass its old capacity contract")

func mode_recovery() -> void:
	game.daily_loop_config.enabled = true
	check((await act("new_game",{"name":"模式恢复"})).success,"mode recovery source creates")
	check((await act("read_morning_letters")).success,"source day opens")
	var total: int = game.daily_loop_view().total
	for index: int in range(total):
		check((await act("next_customer")).success and (await act("end_visit")).success,"source day completes ordered slot "+str(index))
	check((await act("close_shop")).success and (await act("next_day")).success,"mode recovery reaches day-two morning")
	var roster: Array = game.snapshot().daily_loop.arrival_ids
	game.daily_loop_config.enabled = false
	var waited: Dictionary = await act("wait",{"minutes":1})
	check(waited.success,"a played sequential save can commit a legacy wait: "+str(waited))
	if not waited.success:
		game.daily_loop_config.enabled = true
		return
	check(game.state.daily_loop.mode == "legacy" and game.state.daily_loop.arrival_ids == roster,"legacy mode is durable and retains the original same-day roster")
	for id: String in roster:
		check(game.state.people.arrivals[id].state == "planned","legacy director leaves reserved sequential people outside / "+id)
	check((await act("start_visit",{"npc_id":"npc_lin","case_id":"invitation"})).success,"legacy mode may admit an additional ordinary legacy reception")
	var legacy_visit: String = game.state.active_visit_id
	game.daily_loop_config.enabled = true
	check((await act("load_game",{"save_id":game.state.save_id})).success and game.state.active_visit_id == legacy_visit,"switching back preserves an extra active legacy reception")
	check((await act("end_visit")).success,"extra legacy reception can end before the original roster resumes")
	check(game.state.daily_loop.mode == "sequential" and game.state.daily_loop.arrival_ids == roster and game.state.daily_loop.cursor == 0,"same-day sequential restoration keeps every original slot")
	check((await act("read_morning_letters")).success and (await act("next_customer")).success,"restored same-day roster remains playable")
	var matched: String = game.state.daily_loop.active_arrival_id
	game.daily_loop_config.enabled = false
	check((await act("end_visit")).success,"a sequential reception can finish after switching to legacy")
	check(game.state.daily_loop.cursor == 1 and game.state.people.arrivals[matched].state == "completed","ending under legacy advances the matching sequential slot once")
	check((await act("next_day")).success,"legacy next-day archives the unserved remainder")
	var interrupted: Dictionary = game.state.daily_loop.history["1"]
	check(interrupted.status == "interrupted" and interrupted.arrival_ids == roster and interrupted.cursor == 1,"interrupted history preserves exact roster and completed cursor")
	var new_save_id: String = game.state.save_id
	game.daily_loop_config.enabled = true
	check((await act("load_game",{"save_id":new_save_id})).success,"new-day restoration loads interrupted provenance")
	check((await act("read_morning_letters")).success and (await act("next_customer")).success,"a new sequential day can start after the legacy day transition")
	check(game.state.people.arrivals[matched].state == "completed" and game.state.active_visit_id != legacy_visit,"restoration does not repeat any already completed visit")

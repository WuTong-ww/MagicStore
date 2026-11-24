extends SceneTree
var checks := 0
var failures := 0
var game: Node
var saves: Node
var sequence := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("CASE MIGRATION FAIL: "+label)
func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var command := {"type":kind,"action_id":"case_migration_"+str(sequence)}
	command.merge(fields,true)
	var result: Dictionary = await game.execute_action_async(command)
	check(result.success,kind+": "+str(result))
	return result
func historical_divination(value: Dictionary) -> Dictionary:
	var old: Dictionary = value.duplicate(true)
	check(old.get("emergent_cases")=={"version":1,"instances":{}},"historical case projection excludes only the empty schema14 ordinary-case namespace")
	old.erase("emergent_cases")
	old.erase("settings")
	for case: Dictionary in old.cases.values():
		case.erase("board")
	return old
func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/case-migration/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.daily_loop_config.enabled = false
	await act("new_game",{"name":"旧咨询进度迁移"})
	await act("start_visit")
	await act("talk",{"topic_id":"letter","text":"回信写好了吗？"})
	await act("reading")
	var source_visit: String = game.state.active_visit_id
	var event: Dictionary = game.divination_view().event
	await act("record_prediction",{"subject_id":event.subject_id,"text":"先发消息会见到旧友","condition":"if_message","expected":"met","window_start":event.due_at,"window_end":int(event.due_at)+30})
	await act("give_advice",{"advice_key":"message"})
	await act("end_visit")
	await act("next_day")
	await act("start_visit")
	await act("talk",{"topic_id":"invitation","text":"邀请上写了什么？"})
	await act("receive_feedback",{"event_id":event.event_id})
	var old: Dictionary = game.snapshot()
	# This historical version projection excludes future birth-policy fields.
	old.people.erase("birth_identity_version")
	for profile: Dictionary in old.people.profiles.values():
		profile.erase("birth_identity")
	old.schema_version = 10
	old.erase("story")
	old.divination = historical_divination(old.divination)
	check(not old.divination.cases[source_visit].event.feedback.report.is_empty(),"historic source has genuinely settled feedback and rewards")
	check(saves.write_save(old).success,"schema10 historical projection saves without new namespaces")
	var path: String = saves._path(old.save_id)
	var sha := FileAccess.get_sha256(path)
	game.daily_loop_config.enabled = true
	await act("load_game",{"save_id":old.save_id})
	var migrated: Dictionary = game.snapshot()
	check(migrated.schema_version==saves.CURRENT_SCHEMA and migrated.divination.settings=={"free_question":false},"schema11 migration defaults free question to false")
	for key: String in ["save_id","name","state_version","clock_minutes","player","npcs","visits","processed_actions","active_visit_id"]:
		check(migrated[key]==old[key],"migration preserves historic "+key)
	var historical_people: Dictionary = migrated.people.duplicate(true)
	check(historical_people.get("birth_identity_version",0)==1,"migration adds the checked birth-policy marker")
	historical_people.erase("birth_identity_version")
	check(historical_people==old.people and migrated.shop==old.shop,"migration preserves identities, rewards and inventory")
	check(historical_divination(migrated.divination)==old.divination,"all existing world, statements, clues, hypotheses, predictions, services and events are preserved")
	for case: Dictionary in migrated.divination.cases.values():
		check(case.board=={},"old case retains empty board without redrawing or recalculating")
	check(not game.case_board_view().enabled,"old active case stays on the existing consultation interface")
	check(FileAccess.get_sha256(path)==sha and saves.read_save(old.save_id).state.schema_version==10,"load migration changes no old bytes")
	var command := {"type":"set_free_question","action_id":"case_migration_first_commit","enabled":true}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED" and game.snapshot()==migrated and FileAccess.get_sha256(path)==sha,"failed first action preserves migrated memory and original file")
	var retried: Dictionary = await game.execute_action_async(command)
	check(retried.success and game.free_question_enabled() and saves.read_save(old.save_id).state.schema_version==saves.CURRENT_SCHEMA,"same-ID retry first persists schema11 and setting")
	var committed: Dictionary = game.snapshot()
	var replay: Dictionary = await game.execute_action_async(command)
	check(replay.success and replay.get("replayed",false) and game.snapshot()==committed,"migration action replay cannot reapply history")
	check(game.state.divination.effects==old.divination.effects and game.state.people.referrals==old.people.referrals,"successful first action never reissues historic effects or referral")
	await act("load_game",{"save_id":old.save_id})
	check(game.snapshot()==committed,"schema11 reload keeps the exact committed migration")
	for mutation: String in ["missing_settings","invalid_setting","missing_board","invalid_board"]:
		var bad: Dictionary = committed.duplicate(true)
		match mutation:
			"missing_settings": bad.divination.erase("settings")
			"invalid_setting": bad.divination.settings.free_question = "false"
			"missing_board": bad.divination.cases[source_visit].erase("board")
			"invalid_board": bad.divination.cases[source_visit].board = {"phase":"closed","stars":99}
		check(not saves.validate_snapshot(bad).success,"schema11 rejects "+mutation)
	print("CASE MIGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

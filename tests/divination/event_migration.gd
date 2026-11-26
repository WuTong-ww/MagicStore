extends SceneTree
## Real persistence exercises old raw validation before in-memory schema migration.

const Generated = preload("res://scripts/people/generated_person.gd")
const CaseSave = preload("res://scripts/divination/case_save.gd")
const GeneratedCases = preload("res://scripts/divination/generated_cases.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("EVENT MIGRATION FAIL: " + label)

func act(kind: String, extra: Dictionary = {}) -> Dictionary:
	var command := {"type":kind,"action_id":game.make_id("event_migration"),"expected_version":game.state.get("state_version",0)}
	command.merge(extra,true)
	return await game.execute_action_async(command)

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	check(game.content_error.is_empty() and game._divination != null,"current content and event interfaces compile")
	if failures:
		quit(1)
		return
	saves.base_dir = "res://.tools/event-migration-saves/" + game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	for schema: int in [1,2,3,4]:
		await check_schema(schema)
	await check_pending_and_resolved()
	await check_legacy_unreported_feedback()
	await check_generated_eventless()
	await check_generated_return_guard()
	check_generic_effect_validation()
	print("EVENT MIGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func old_copy(schema: int) -> Dictionary:
	var legacy: Dictionary = game.snapshot()
	# Synthetic old versions cannot retain TITLE15's creation receipt.
	if saves.NEW_GAME_RECEIPT_SCHEMA <= int(legacy.get("schema_version",0)) and int(legacy.get("schema_version",0)) <= saves.CURRENT_SCHEMA:
		for action_id: String in legacy.processed_actions.keys():
			if legacy.processed_actions[action_id].get("action_type") == "new_game":
				legacy.processed_actions.erase(action_id)
	legacy.schema_version = schema
	if legacy.has("divination"):
		check(not legacy.divination.has("emergent_cases") or legacy.divination.get("emergent_cases")=={"version":1,"instances":{}},"historical projection retains no populated schema14 ordinary-case namespace")
		legacy.divination.erase("emergent_cases")
		legacy.divination.erase("past_lines")
		for case: Dictionary in legacy.divination.cases.values():
			case.erase("cause")
		legacy.divination.erase("legacy_eventless_visits")
	if legacy.has("people"):
		# The synthetic v1-v4 projection cannot include the later birth policy.
		legacy.people.erase("birth_identity_version")
		for profile: Dictionary in legacy.people.profiles.values():
			profile.erase("birth_identity")
		check(not legacy.people.has("birth_identity_version") and legacy.people.profiles.values().all(func(profile: Dictionary) -> bool: return not profile.has("birth_identity")),"synthetic old people excludes future birth fields / v"+str(schema))
		legacy.people.erase("unlocked_topics")
		legacy.people.erase("family_library_version")
		legacy.people.erase("family_metrics")
	if schema < 3:
		legacy.erase("people")
		legacy.erase("shop")
	if schema == 1:
		legacy.erase("divination")
		legacy.player.erase("items")
		for wallet: Dictionary in legacy.npcs.values():
			wallet.erase("items")
	return legacy

func check_schema(schema: int) -> void:
	check((await act("new_game",{"name":"事件旧档兼容"+str(schema)})).success,"create source / v"+str(schema))
	var legacy := old_copy(schema)
	check(saves.write_save(legacy).success,"write synthetic old-version namespace shape / v"+str(schema))
	var path: String = saves._path(legacy.save_id)
	var hash_before := FileAccess.get_sha256(path)
	check(saves.read_save(legacy.save_id).success,"raw old save validates before migration / v"+str(schema))
	check((await act("load_game",{"save_id":legacy.save_id})).success,"load old schema / v"+str(schema))
	# Historical v1-v4 contracts/event invariants stay; current destination is G5 v9.
	check(game.state.schema_version == SaveService.CURRENT_SCHEMA,"migrate to current schema in memory / v"+str(schema))
	check(game.state.divination.get("legacy_eventless_visits") is Array,"initialize eventless migration ledger / v"+str(schema))
	check(game.state.people.get("unlocked_topics") is Dictionary,"initialize topic effects namespace / v"+str(schema))
	check(FileAccess.get_sha256(path) == hash_before and saves.read_save(legacy.save_id).state.schema_version == schema,"loading leaves old bytes unchanged / v"+str(schema))
	var before: Dictionary = game.snapshot()
	var retry_id: String = game.make_id("migration_retry")
	saves.fail_next_write = true
	var failed: Dictionary = await act("wait",{"minutes":1,"action_id":retry_id})
	check(not failed.success and failed.get("error_code") == "SAVE_WRITE_FAILED" and game.snapshot() == before and FileAccess.get_sha256(path) == hash_before,"failed first action preserves old file and migrated memory / v"+str(schema))
	check((await act("wait",{"minutes":1,"action_id":retry_id})).success,"retry first successful action / v"+str(schema))
	check(saves.read_save(legacy.save_id).state.schema_version == SaveService.CURRENT_SCHEMA,"next successful action persists current schema / v"+str(schema))
	var committed: Dictionary = game.snapshot()
	check((await act("wait",{"minutes":1,"action_id":retry_id})).success and game.snapshot() == committed,"same action replay cannot repeat migration settlement / v"+str(schema))

func check_pending_and_resolved() -> void:
	check((await act("new_game",{"name":"事件历史保留"})).success,"create pending source")
	check((await act("start_visit")).success,"start legacy pending event")
	var pending := old_copy(4)
	var visit_id: String = pending.active_visit_id
	var event_before: Dictionary = pending.divination.cases[visit_id].event.duplicate(true)
	var plans: Dictionary = pending.people.days.duplicate(true)
	check(saves.write_save(pending).success,"write v4 pending event")
	var invalid_fact: Dictionary = pending.duplicate(true)
	invalid_fact.divination.cases[visit_id].world_facts.changed_entrance.value = "outside_declared_domain"
	check(not saves.validate_snapshot(invalid_fact).success,"reject an event fact value outside its declared domain")
	check((await act("load_game",{"save_id":pending.save_id})).success,"load v4 pending event")
	check(game.state.divination.cases[visit_id].event == event_before and game.state.people.days == plans,"migration preserves pending event identity and planned days")
	check((await act("reading")).success,"pay service for resolved legacy fixture")
	var due := int(game.state.divination.cases[visit_id].event.due_at)
	check((await act("record_prediction",{"text":"约定时段内会有结果。","subject_id":event_before.subject_id,"expected":"met","condition":"always","window_start":due,"window_end":due+30})).success,"record legacy prediction")
	check((await act("end_visit")).success and (await act("next_day")).success,"advance actual world event")
	check((await act("start_visit")).success,"create actual return visit for legacy feedback source")
	var resolved := old_copy(4)
	var case: Dictionary = resolved.divination.cases[visit_id]
	case.event.evaluation = "deviated"
	case.event.evaluated_at = due+30
	case.event.feedback.report = {"feedback_id":"feedback_legacy_migration","event_id":case.event.event_id,"visit_id":resolved.active_visit_id,"at":resolved.clock_minutes,"evaluation":"deviated","text":"原始旧档中的反馈。","evidence":"sufficient"}
	var effect := {"effect_id":case.event.event_id+"_trust","event_id":case.event.event_id,"prediction_id":case.prediction.prediction_id,"visit_id":visit_id,"npc_id":case.npc_id,"subject_id":case.event.subject_id,"recipient":"A","kind":"trust","amount":-2,"starts_at":resolved.clock_minutes,"expires_at":-1}
	resolved.divination.effects.append(effect)
	resolved.people.effect_ids.append(effect.effect_id)
	var old_event: Dictionary = case.event.duplicate(true)
	var old_effects: Array = resolved.divination.effects.duplicate(true)
	plans = resolved.people.days.duplicate(true)
	check(saves.write_save(resolved).success,"write v4 resolved result and old kind-based effect id")
	var original_hash := FileAccess.get_sha256(saves._path(resolved.save_id))
	check((await act("load_game",{"save_id":resolved.save_id})).success,"load resolved v4 effects")
	check(game.state.divination.cases[visit_id].event == old_event and game.state.divination.effects == old_effects and game.state.people.days == plans,"preserve resolved outcome evaluation effect ids and day plans verbatim")
	check(FileAccess.get_sha256(saves._path(resolved.save_id)) == original_hash,"resolved migration is read-only")

func check_generated_eventless() -> void:
	check((await act("new_game",{"name":"生成案例旧档兼容"})).success,"create generated source")
	# Build a real approved offline package as a prior-version fixture. This is
	# confined to the test save; no model calls or player save paths are involved.
	game.state = old_copy(4)
	var generation_id := "g3_old_generated"
	var result: Dictionary = Generated.apply(game.state.people,game.people_config,generation_id,Generated.offline_bundle(generation_id),Generated.offline_provenance(generation_id),int(game.state.clock_minutes)+1)
	check(result.success,"build old approved generated identity")
	if not result.success:
		return
	game._sync_generated_catalog()
	check((await act("wait",{"minutes":1})).success,"persist old generated fixture")
	check((await act("start_arrival",{"arrival_id":result.arrival_id})).success,"start prior-version generated case")
	var legacy := old_copy(4)
	var visit_id: String = legacy.active_visit_id
	check(legacy.divination.cases[visit_id].event.is_empty(),"old generated visit has no retrospective event")
	check(saves.write_save(legacy).success,"write generated v4 fixture")
	var hash_before := FileAccess.get_sha256(saves._path(legacy.save_id))
	check((await act("load_game",{"save_id":legacy.save_id})).success,"load old generated eventless visit")
	check(visit_id in game.state.divination.get("legacy_eventless_visits",[]) and game.state.divination.cases[visit_id].event.is_empty(),"legacy ledger preserves eventless generated visit")
	check(FileAccess.get_sha256(saves._path(legacy.save_id)) == hash_before,"generated migration leaves old bytes unchanged")
	var invalid_marker: Dictionary = game.snapshot()
	invalid_marker.divination["legacy_eventless_visits"] = ["unknown_visit"]
	check(not saves.validate_snapshot(invalid_marker).success,"eventless compatibility marker cannot refer to an unknown visit")
	check((await act("wait",{"minutes":1})).success and saves.read_save(legacy.save_id).state.schema_version == SaveService.CURRENT_SCHEMA,"migrated generated case persists current schema without adding an event")

func check_legacy_unreported_feedback() -> void:
	check((await act("new_game",{"name":"旧事件首次反馈兼容"})).success,"create unreported legacy source")
	check((await act("start_visit")).success and (await act("reading")).success,"prepare original paid event")
	var source_id: String = game.state.active_visit_id
	var event: Dictionary = game.state.divination.cases[source_id].event
	check((await act("record_prediction",{"text":"在约定时间内得到实际结果。","subject_id":event.subject_id,"expected":"met","condition":"always","window_start":int(event.due_at),"window_end":int(event.due_at)+30})).success,"record prediction before old event")
	check((await act("end_visit")).success and (await act("next_day")).success and (await act("start_visit")).success,"start actual later reception after event occurred")
	var legacy := old_copy(4)
	var old_event: Dictionary = legacy.divination.cases[source_id].event
	old_event.erase("rule_index")
	old_event.evaluation = "deviated"
	old_event.evaluated_at = int(old_event.due_at)+30
	check(old_event.feedback.report.is_empty(),"legacy occurred event has never been disclosed")
	check(saves.write_save(legacy).success,"write old resolved-unreported event without rule metadata")
	var hash_before := FileAccess.get_sha256(saves._path(legacy.save_id))
	check((await act("load_game",{"save_id":legacy.save_id})).success,"load old unreported result")
	var expected_pending := old_event.duplicate(true)
	expected_pending.evaluation = "pending"
	expected_pending.evaluated_at = -1
	check(game.state.divination.cases[source_id].event == expected_pending and FileAccess.get_sha256(saves._path(legacy.save_id)) == hash_before,"loading preserves old world result and file bytes while withdrawing only the unreported verdict in memory")
	check(game.state.divination.cases[source_id].event.evaluation == "pending" and game.state.divination.cases[source_id].event.evaluated_at == -1,"migration clears only the legacy premature verdict until real feedback")
	var before: Dictionary = game.snapshot()
	var action_id: String = game.make_id("old_feedback_retry")
	saves.fail_next_write = true
	var failed: Dictionary = await act("receive_feedback",{"event_id":old_event.event_id,"action_id":action_id})
	check(not failed.success and failed.get("error_code") == "SAVE_WRITE_FAILED" and game.snapshot() == before and FileAccess.get_sha256(saves._path(legacy.save_id)) == hash_before,"first old-event feedback reaches write then rolls back its metadata and effects")
	saves.fail_next_write = false
	check((await act("receive_feedback",{"event_id":old_event.event_id,"action_id":action_id})).success,"old unreported event can disclose through real feedback action")
	var settled: Dictionary = game.snapshot()
	check(not settled.divination.cases[source_id].event.feedback.report.is_empty() and settled.divination.cases[source_id].event.outcome == old_event.outcome and settled.divination.cases[source_id].event.resolved_at == old_event.resolved_at,"legacy disclosure preserves actual outcome and occurrence time")
	check((await act("receive_feedback",{"event_id":old_event.event_id,"action_id":action_id})).success and game.snapshot() == settled,"same old-event feedback ID cannot repeat metadata or rewards")
	check(saves.read_save(legacy.save_id).success,"old-event feedback and new effect provenance survive disk validation")

func check_generic_effect_validation() -> void:
	var case := {"case_id":"fixture","visit_id":"visit_fixture","npc_id":"npc_fixture","prediction":{},"event":{"event_id":"event_fixture","due_at":10,"outcome_id":"met","rule_index":0,"feedback":{"report":{}}}}
	var state := {"clock_minutes":10,"people":{"profiles":{"npc_fixture":{}},"relationships":{}}}
	var data := {"cases":{"fixture":{"event":{"rules":[{}],"outcomes":{"met":{"effects":[{"kind":"trust","delta":2},{"kind":"trust","delta":1}]}}}}},"topic_index":{},"economy":{}}
	var effect := {"effect_id":"event_fixture_resolve_met_outcome_0_trust","event_id":"event_fixture","prediction_id":"","visit_id":"visit_fixture","npc_id":"npc_fixture","recipient":"A","kind":"trust","amount":2,"starts_at":10,"expires_at":-1,"stage":"resolve","outcome_id":"met","rule_index":0,"effect_index":0,"effect_source":"outcome"}
	check(CaseSave._effect(effect,case,state,data),"generic resolved effect can have no prediction or report")
	var second := effect.duplicate(true)
	second.effect_index = 1
	second.amount = 1
	second.effect_id = "event_fixture_resolve_met_outcome_1_trust"
	check(CaseSave._effect(second,case,state,data) and second.effect_id != effect.effect_id,"same-kind effects retain distinct source indices")
	state.clock_minutes = 20
	var late_resolve := effect.duplicate(true)
	late_resolve.starts_at = 11
	check(not CaseSave._effect(late_resolve,case,state,data),"reject resolve effect timestamp after its canonical event")
	data.cases.fixture.event.feedback_effects = [{"kind":"trust","delta":2}]
	var feedback := effect.duplicate(true)
	feedback.effect_source = "feedback"
	feedback.effect_id = "event_fixture_resolve_met_feedback_0_trust"
	check(not CaseSave._effect(feedback,case,state,data),"reject feedback source forged as resolve stage before disclosure")
	case.event.feedback.report = {"at":15}
	feedback.stage = "feedback"
	feedback.effect_id = "event_fixture_feedback_met_feedback_0_trust"
	check(not CaseSave._effect(feedback,case,state,data),"reject feedback effect timestamp before actual disclosure")
	feedback.starts_at = 15
	check(CaseSave._effect(feedback,case,state,data),"accept feedback effect at actual disclosure")
	data.cases.fixture.event.outcomes.met.effects[0].stage = "feedback"
	check(not CaseSave._effect(effect,case,state,data),"reject explicit source stage mismatch despite valid stable id")
	data.cases.fixture.event.outcomes.met.effects[0].erase("stage")
	for field: String in ["outcome_id","kind","effect_id","amount","recipient"]:
		var broken := effect.duplicate(true)
		broken[field] = 101 if field == "amount" else "forged"
		check(not CaseSave._effect(broken,case,state,data),"reject forged effect source / "+field)

func check_generated_return_guard() -> void:
	check((await act("new_game",{"name":"生成来客回访事件引用"})).success,"create new generated return source")
	var generation_id := "g3_return_guard"
	var applied: Dictionary = Generated.apply(game.state.people,game.people_config,generation_id,Generated.offline_bundle(generation_id),Generated.offline_provenance(generation_id),int(game.state.clock_minutes)+1)
	check(applied.success,"prepare approved generated return guest")
	if not applied.success:
		return
	game._sync_generated_catalog()
	check((await act("wait",{"minutes":1})).success and (await act("start_arrival",{"arrival_id":applied.arrival_id})).success,"start new generated event once")
	var source_id: String = game.state.active_visit_id
	var source_event: Dictionary = game.state.divination.cases[source_id].event.duplicate(true)
	check(not source_event.is_empty(),"first generated reception owns the canonical event")
	check((await act("end_visit")).success and (await act("next_day")).success,"finish canonical reception before return")
	var draft: Dictionary = game.snapshot()
	var source_visit: Dictionary = draft.visits.filter(func(row: Dictionary) -> bool: return row.visit_id == source_id)[0]
	var return_id: String = game.make_id("return_case_guard")
	var returning: Dictionary = source_visit.duplicate(true)
	returning.merge({"visit_id":return_id,"day":floori(float(draft.clock_minutes)/1440.0),"phase":"talking","dialogue":[{"speaker":"npc","text":"我想接着聊上次的事。"}],"reading":{},"started_at":draft.clock_minutes,"ended_at":-1},true)
	var record: Dictionary = draft.divination.cases[source_id].duplicate(true)
	record["visit_id"] = return_id
	for key: String in ["event","prediction","purchase","item_use","services"]:
		record[key] = {}
	for key: String in ["conversation","branches","hypotheses","advice"]:
		record[key] = []
	record["open_service_id"] = ""
	var allowed: Array = game._divination.data.cases[record.case_id].world_facts.values().map(func(fact: Dictionary) -> String: return fact.requires_clue)
	record["inherited_clue_ids"] = GeneratedCases.inherited_clues(draft,returning,record.case_id,allowed)
	returning.clue_ids = record.inherited_clue_ids.duplicate()
	draft.visits.append(returning)
	draft.divination.cases[return_id] = record
	var visits := {}
	for row: Dictionary in draft.visits:
		visits[row.visit_id] = row
	check(CaseSave.validate(draft,game._divination.data,visits).is_empty(),"new generated return can reference an earlier same-person same-case event")
	check(return_id not in draft.divination.legacy_eventless_visits,"new return is not forged into legacy migration metadata")
	check(CaseSave._prior_event_exists(record,returning,draft.divination.cases,visits),"canonical event proof finds the completed source reception")
	for condition: String in ["other_npc","other_case","unfinished","future"]:
		var changed_cases: Dictionary = draft.divination.cases.duplicate(true)
		var changed_visits: Dictionary = visits.duplicate(true)
		match condition:
			"other_npc":
				changed_cases[source_id].npc_id = "another_npc"
			"other_case":
				changed_cases[source_id].case_id = "another_case"
			"unfinished":
				changed_visits[source_id].phase = "talking"
			"future":
				changed_visits[source_id].ended_at = int(returning.started_at)+1
		check(not CaseSave._prior_event_exists(record,returning,changed_cases,changed_visits),"canonical event proof rejects invalid source / "+condition)

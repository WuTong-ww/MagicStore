extends SceneTree
const Catalog = preload("res://scripts/divination/catalog.gd")
const Generated = preload("res://scripts/divination/generated_cases.gd")
const Loader = preload("res://scripts/core/content_loader.gd")
const Person = preload("res://scripts/people/generated_person.gd")
const EventCopy = preload("res://scripts/divination/event_copy.gd")
const Session = preload("res://scripts/divination/session.gd")
const CaseSave = preload("res://scripts/divination/case_save.gd")
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
		printerr("G3 WORKFLOWS FAIL: "+label)
func fixture(npc: String) -> Dictionary:
	var request := {"title":"分工的下一步","opening":"我想把分工说清楚。","question":"我该怎样和搭档商量分工？","situation":"我们还没商量好分工。","concern":"我担心说不清。","detail":"我们有一张共同的草图。","hidden_fact":"草图背面留着约定。","followup":"我想继续聊上次的事。"}
	# Keep the original authored event scenario inside a complete legacy v1
	# person package so catalog admission still exercises its strict validator.
	var bundle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/people/fixtures/person_generation.json")).bundle
	bundle.person.merge({"name":"许禾","role":"修灯师"},true)
	bundle.contact.name = "江岑"
	bundle.case = request
	# Keep the original concern verbatim as a prefix while meeting v1 length.
	bundle.case.concern += "想说清楚。"
	bundle.relationship = {"kind":"搭档","shared_history":"我们一起修过旧灯。"}
	return {"schema_version":5,"clock_minutes":540,"player":{"coins":40,"energy":100,"items":{}},"npcs":{npc:{"coins":60,"items":{}}},"people":{"profiles":{npc:{"npc_id":npc,"name":"许禾","role":"修灯师","generated_bundle":bundle,"generation_id":"generation_fixture","generation_member":"person"}}},"divination":{"skills":["tarot"],"cases":{},"past":{},"ledger":[],"effects":[],"legacy_eventless_visits":[]},"visits":[],"active_visit_id":"","processed_actions":{}}
func run() -> void:
	var loaded: Dictionary = Loader.load_content()
	check(loaded.success,"base content loads")
	var data := Catalog.load_data(loaded.content)
	check(data.cases.archive.has("event"),"archive defines a data-driven event")
	var state := fixture("npc_generic_workflow")
	var fixture_valid := not Person.validate_bundle(state.people.profiles.npc_generic_workflow.generated_bundle).is_empty()
	check(fixture_valid,"authored workflow uses a complete valid legacy v1 package")
	if not fixture_valid:
		print("G3 WORKFLOWS: %d checks, %d failures" % [checks,failures])
		quit(1)
		return
	var generated := Generated.catalog(state,data)
	var id := Generated.case_id("npc_generic_workflow")
	check(not generated.is_empty() and generated.cases[id].has("event"),"schema5 generated case has a bounded template event")
	check(Generated.catalog(state,data) == generated,"template choice is stable across reload projection")
	state.people.profiles.npc_generic_workflow.generated_bundle.case["rules"] = []
	check(Generated.catalog(state,data).is_empty(),"model-supplied rule field is rejected rather than executed")
	check(EventCopy.config_valid(EventCopy.load_config()),"event UI text and timing JSON validates")
	var invalid := EventCopy.load_config().duplicate(true)
	invalid.windows[0].duration = 0
	check(not EventCopy.config_valid(invalid),"event UI rejects an empty forecast time window")
	generated_unlock_validation(data,loaded.content)
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/g3-workflow-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	await archive_flow()
	await generated_flows()
	print("G3 WORKFLOWS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func generated_unlock_validation(base_data: Dictionary, content: Dictionary) -> void:
	# Focused case-record contract; effect provenance itself is covered through
	# real transactions in event_effects.gd and Bridge.validate.
	var npc := "npc_generic_unlock"
	var state := fixture(npc)
	var data := Generated.catalog(state,base_data)
	var id := Generated.case_id(npc)
	var visit := {"visit_id":"visit_unlock_gate","npc_id":npc,"day":0,"phase":"talking","clue_ids":[Generated.clue_id(npc,"hidden")],"dialogue":[{"speaker":"npc","text":"我想继续核对这件事。"}],"reading":{},"started_at":540,"ended_at":-1}
	state.visits.append(visit)
	state.active_visit_id = visit.visit_id
	var session := Session.new(data,content)
	check(session.add_case(state,visit,id,true,{"public_npc":{"npc_id":npc,"name":"许禾","role":"修灯师"}}),"generated unlock case fixture binds canonical facts")
	var case: Dictionary = state.divination.cases[visit.visit_id]
	var visits := {visit.visit_id:visit}
	check(not CaseSave.validate(state,data,visits).is_empty(),"generated private topic without prerequisite or unlock is rejected")
	state.people["unlocked_topics"] = {npc:[{"topic_id":Generated.topic_id(npc,"hidden"),"at":540,"effect_id":"fixture_only","event_id":case.event.event_id}]}
	check(CaseSave.validate(state,data,visits).is_empty(),"an explicitly unlocked generated topic can save its obtained clue without inventing prerequisite knowledge")
	state.people.unlocked_topics[npc][0].at = 541
	check(not CaseSave.validate(state,data,visits).is_empty(),"a future unlock cannot retroactively authorize earlier knowledge")

func act(kind: String, extra: Dictionary = {}, action_id: String = "") -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("g3_flow") if action_id.is_empty() else action_id}
	action.merge(extra,true)
	var result: Dictionary = await game.execute_action_async(action)
	check(result.get("success",false),kind+" / "+str(result.get("message","")))
	return result

func talk_available() -> void:
	var seen := []
	for pass_index: int in range(2):
		var topics: Array = game.divination_view().get("topics",[])
		for topic: Dictionary in topics:
			if topic.enabled and topic.topic_id not in seen:
				await act("talk",{"text":topic.label,"topic_id":topic.topic_id})
				seen.append(topic.topic_id)

func advise_and_predict() -> Dictionary:
	await talk_available()
	var view: Dictionary = game.divination_view()
	var event: Dictionary = view.event
	check(not event.is_empty(),"real reception creates a pending event")
	if event.is_empty():
		return {}
	await act("reading")
	await act("record_prediction",{"subject_id":event.subject_id,"text":"先按已经核对的信息行动，再听取实际反馈。","condition":"always","expected":"met","window_start":int(event.due_at),"window_end":int(event.due_at)+30})
	var choices: Array = game.divination_view().event.advice_options
	await act("give_advice",{"advice_key":choices[0].advice_key})
	if not event.get("item_effect_available",false):
		await act("buy_case_item")
		var before: Dictionary = game.snapshot()
		var unused: Dictionary = await game.execute_action_async({"type":"use_case_item","action_id":game.make_id("not_applicable")})
		check(not unused.success and unused.error_code == "ITEM_USE_BLOCKED" and game.snapshot() == before,"a case without a configured item effect safely refuses item use")
	return {"visit_id":view.visit_id,"event_id":event.event_id,"due_at":event.due_at}

func receive_and_check(origin: Dictionary) -> void:
	if game.active_visit().is_empty():
		check(false,"feedback requires a successfully admitted return visit")
		return
	var before: Dictionary = game.snapshot()
	var topics: Array = game.divination_view().get("topics",[]).filter(func(row: Dictionary) -> bool: return row.enabled)
	if not topics.is_empty():
		var prepared: Dictionary = game._prepare_talk({"text":topics[0].label,"topic_id":topics[0].topic_id})
		var actual: Dictionary = game.state.divination.cases[origin.visit_id].event
		var encoded: String = JSON.stringify(prepared.get("request",{}))
		check(prepared.success and not encoded.contains(actual.actual_action) and not encoded.contains("rule_index"),"dialogue request does not receive undisclosed event facts or rule bookkeeping")
		check(game.snapshot() == before,"preparing dialogue never discloses or settles the pending feedback")
	var id: String = game.make_id("g3_feedback")
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async({"type":"receive_feedback","action_id":id,"event_id":origin.event_id})
	check(not failed.success and failed.error_code == "SAVE_WRITE_FAILED" and game.snapshot() == before,"feedback save failure leaves report, evaluation and rewards unchanged")
	var delivered := await act("receive_feedback",{"event_id":origin.event_id},id)
	if not delivered.success:
		return
	var report: Dictionary = delivered.result.feedback
	check(report.evaluation != "pending" and report.evidence == "sufficient" and report.has("outcome"),"real sufficient feedback verifies the prediction")
	var committed: Dictionary = game.snapshot()
	var replay: Dictionary = await game.execute_action_async({"type":"receive_feedback","action_id":id,"event_id":origin.event_id})
	check(replay.success and game.snapshot() == committed,"same feedback action ID cannot repeat effects")
	var saved: Dictionary = saves.read_save(game.state.save_id)
	check(saved.success and saved.state == committed,"event and feedback survive actual disk validation")

func archive_flow() -> void:
	await act("new_game",{"name":"旧物事件完整流程"})
	await act("start_visit",{"npc_id":"npc_lin","case_id":"archive"})
	var origin := await advise_and_predict()
	if origin.is_empty():
		return
	await act("end_visit")
	await act("next_day")
	check(game.state.divination.cases[origin.visit_id].event.evaluation == "pending","archive world resolution does not evaluate before disclosure")
	check(not game.divination_view(origin.visit_id).event.has("outcome"),"archive player view keeps hidden result separate")
	await act("start_visit",{"npc_id":"npc_lin","case_id":"archive"})
	await receive_and_check(origin)
	await act("end_visit")

func generated_flows() -> void:
	var templates: Dictionary = load("res://scripts/divination/event_schema.gd").load_templates().templates
	var covered := []
	for index: int in range(64):
		var generation_id := "g3_workflow_"+str(index)
		var npc_id: String = Person._ids(generation_id).npc_id
		var definition := Generated.event_definition(npc_id,Person.offline_bundle(generation_id).case,templates)
		if definition.template_id in covered:
			continue
		await act("new_game",{"name":"生成事件流程"+str(covered.size()+1)})
		# Isolated input fixture only: all observed admission/clock/reception,
		# advice, feedback, save failure and replay below use actual transactions.
		var prepared: Dictionary = game.snapshot()
		var applied := Person.apply(prepared.people,game.people_config,generation_id,Person.offline_bundle(generation_id),Person.offline_provenance(generation_id),int(prepared.clock_minutes)+1)
		check(applied.success,"approved local person fixture validates")
		if not applied.success:
			return
		game.state = prepared
		game._sync_generated_catalog()
		await act("wait",{"minutes":1})
		await act("start_arrival",{"arrival_id":applied.arrival_id})
		var origin := await advise_and_predict()
		if origin.is_empty():
			return
		check(game.state.divination.cases[origin.visit_id].event.template_id == definition.template_id,"actual case uses stable local template / "+definition.template_id)
		var return_at: int = game.next_return_time()
		check(return_at > int(game.state.clock_minutes),"generated guest can agree to a real return time")
		var ended := await act("end_visit",{"return_at":return_at,"guest_agreed":true})
		if not ended.success:
			return
		while int(game.state.clock_minutes)/1440 < return_at/1440:
			await act("next_day")
		while int(game.state.clock_minutes) < return_at:
			var waited := await act("wait",{"minutes":mini(180,return_at-int(game.state.clock_minutes))})
			if not waited.success:
				return
		check(game.state.divination.cases[origin.visit_id].event.evaluation == "pending","template remains pending until actual feedback / "+definition.template_id)
		var returned := await act("start_arrival",{"arrival_id":ended.result.return_appointment.arrival_id})
		if not returned.success:
			return
		await receive_and_check(origin)
		await act("end_visit")
		covered.append(definition.template_id)
		if covered.size() == templates.size():
			break
	check(covered.size() == templates.size(),"all three generated templates complete advice-to-feedback workflows")

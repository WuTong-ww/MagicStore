extends SceneTree
## Authored old history/stock is setup. All new arrivals, uses, advice, clocks,
## outcomes and reports below cross the actual saved async action boundary.
const Shop = preload("res://scripts/shop/shop.gd")
const People = preload("res://scripts/people/people.gd")
const Bridge = preload("res://scripts/shop/people_bridge.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0
var original_config: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		printerr("COMPONENT FEEDBACK FAIL: "+label)
	return value

func command(kind: String, fields: Dictionary = {}) -> Dictionary:
	var result := {"type":kind,"action_id":game.make_id("component_feedback"),"expected_version":game.state.get("state_version",0)}
	result.merge(fields,true)
	return result

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var outcome: Dictionary = await game.execute_action_async(command(kind,fields))
	check(outcome.get("success",false),"saved async "+kind+" / "+str(outcome.get("message","")))
	return outcome

func run() -> void:
	if "--write-uids" in OS.get_cmdline_user_args() and not FileAccess.file_exists("res://tests/integration/shop_component_feedback.gd.uid"):
		var uid_file := FileAccess.open("res://tests/integration/shop_component_feedback.gd.uid",FileAccess.WRITE)
		uid_file.store_line(ResourceUID.id_to_text(ResourceUID.create_id()))
		uid_file.close()
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/g4/component-feedback-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	original_config = game.people_config.duplicate(true)
	# Only this functional fixture guarantees later ordinary returns. It is not
	# evidence about natural return probability or the economic runner.
	game.people_config.arrival.ordinary_return_percent = 100
	game.people_config.arrival.burst.probability = 0.0
	await relationship_flow("accepted","archive","verify","archive","verified","sufficient",true)
	await relationship_flow("rejected","archive","verify","","paused","sufficient",false)
	await relationship_flow("partial","archive","ask","","heard","partial",false)
	await relationship_flow("never","invitation","private","letter","private","sufficient",false)
	game.people_config = original_config
	saves.fail_next_write = false
	print("COMPONENT FEEDBACK: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func authored_known_ordinary(label: String, case_id: String) -> Dictionary:
	saves.fail_next_write = false
	if not (await act("new_game",{"name":"商品反馈隔离-"+label})).success:
		return {}
	var random := RandomNumberGenerator.new()
	random.seed = 37
	var npc_id: String = People._ordinary_legacy(game.state.people,game.people_config,random,0,91)
	var profile: Dictionary = game.state.people.profiles[npc_id]
	profile.met = true
	profile.return_bias = 0
	profile.return_schedule = {"weekdays":[0,1,2,3,4,5,6],"start":540,"end":1320}
	var goal: Dictionary = profile.goal
	var statement := "我和%s是朋友，想重新联系。" % game.state.people.profiles[goal.subject_id].name
	var historical_id := "visit_known_ordinary_"+label
	var statement_id := "known_statement_"+label
	var historical := {"visit_id":historical_id,"npc_id":npc_id,"day":0,"phase":"ended","clue_ids":[],"dialogue":[{"speaker":"npc","text":statement}],"reading":{},"started_at":int(game.state.clock_minutes),"ended_at":int(game.state.clock_minutes)}
	game.state.npcs[npc_id] = {"coins":60,"items":{}}
	game.state.visits.append(historical)
	var old_case := "invitation" if case_id == "archive" else "archive"
	check(game._divination.add_case(game.state,historical,old_case,false,{"public_npc":{"name":profile.name,"role":profile.role}}),"authored legacy reception retains a canonical eventless case / "+label)
	game.state.divination.legacy_eventless_visits.append(historical_id)
	game.state.processed_actions[statement_id] = {"success":true,"error_code":"","message":"已保存的历史陈述夹具","state_version":int(game.state.state_version),"action_type":"talk","result":{"visit_id":historical_id,"clue_ids":[]}}
	check(People.reveal_relationship(game.state.people,goal.relationship_id,historical_id,statement_id),"fixture discloses only the ordinary person's existing goal edge with an explicit historical source / "+label)
	Shop._add(game.state,"friendship_knot",2,"fixture",game.state.save_id)
	var arrival_id := "arrival_known_ordinary_"+label
	game.state.people.arrivals[arrival_id] = Bridge._arrival(arrival_id,npc_id,int(game.state.clock_minutes)+1,"return",case_id)
	var prepared: Dictionary = saves.write_save(game.snapshot())
	if not check(prepared.success,"authored old history, existing goal and stock pass the real save validator / "+label+" / "+str(prepared.get("message",""))):
		return {}
	if not (await act("wait",{"minutes":1})).success or not (await act("start_arrival",{"arrival_id":arrival_id})).success:
		return {}
	var visit_id: String = game.state.active_visit_id
	var case: Dictionary = game.state.divination.cases[visit_id]
	check(profile.template_id == "ordinary_v1" and case.event.subject_id == goal.subject_id,"actual ordinary return binds the publicly known goal rather than a default or unrelated subject / "+label)
	return {"npc_id":npc_id,"relation_id":goal.relationship_id,"visit_id":visit_id,"event_id":case.event.event_id,"before":int(game.state.people.relationships[goal.relationship_id].closeness)}

func relationship_flow(label: String, case_id: String, advice_key: String, topic_id: String, outcome_id: String, evidence: String, changes: bool) -> void:
	var origin := await authored_known_ordinary(label,case_id)
	if origin.is_empty():
		return
	var sold := await act("sell_product",{"item_id":"friendship_knot"})
	if not sold.success:
		return
	var use_action := command("use_product",{"item_id":"friendship_knot","transaction_id":sold.result.transaction_id})
	var before: Dictionary = game.snapshot()
	var disk_before: Dictionary = saves.read_save(before.save_id).state
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(use_action)
	check(not failed.success and failed.get("error_code") == "SAVE_WRITE_FAILED" and game.snapshot() == before and saves.read_save(before.save_id).state == disk_before,"failed relationship use publishes no partial stock, goal or event source / "+label)
	var used: Dictionary = await game.execute_action_async(use_action)
	if not check(used.success,"same-ID relationship use retry commits once / "+label+" / "+str(used.get("message",""))):
		return
	var use_id: String = used.result.item_use.item_use_id
	origin["use_id"] = use_id
	origin["use_action_id"] = use_action.action_id
	origin["initial_reply"] = game.state.processed_actions[use_action.action_id].duplicate(true)
	origin["initial_use"] = used.result.item_use.duplicate(true)
	check(int(game.state.people.relationships[origin.relation_id].closeness) == origin.before and game.state.shop.uses.back().component_results[0].result.status == "pending","use is pending and does not directly change the relationship / "+label)
	var committed: Dictionary = game.snapshot()
	var replay: Dictionary = await game.execute_action_async(use_action)
	check(replay.get("replayed",false) and game.snapshot() == committed,"same-ID use replay never double consumes / "+label)
	if not topic_id.is_empty() and not (await act("talk",{"topic_id":topic_id,"text":"请核对这件事已经知道的材料。"})).success:
		return
	var advised := await act("give_advice",{"advice_key":advice_key})
	if not advised.success:
		return
	var case: Dictionary = game.state.divination.cases[origin.visit_id]
	check(case.advice.back().accepted == (label != "rejected"),"accepted/refused follows the real local advice gate / "+label)
	if not (await act("end_visit")).success or not (await act("next_day")).success:
		return
	case = game.state.divination.cases[origin.visit_id]
	check(case.event.occurrence != "pending" and case.event.outcome_id == outcome_id and case.event.evidence == evidence,"actual G3 resolver supplies the expected evidence/outcome / "+label)
	var effects: Array = game.state.divination.effects.filter(func(row: Dictionary) -> bool: return row.get("effect_source") == "product_component" and row.get("item_use_id") == use_id)
	var relation: Dictionary = game.state.people.relationships[origin.relation_id]
	check(effects.size() == (1 if changes else 0) and int(relation.closeness) == int(origin.before)+(3 if changes else 0),"People applies only the legal G3 relationship delta / "+label)
	check(case.event.feedback.report.is_empty(),"hidden resolution does not fabricate a customer report / "+label)
	if changes and not effects.is_empty():
		check(relation.changes.any(func(row: Dictionary) -> bool: return row.get("effect_id") == effects[0].effect_id and int(row.to)-int(row.from) == 3),"actual closeness change retains the product's G3 effect ID")
	if not await admit_real_return(origin.npc_id):
		return
	if label == "never":
		before = game.snapshot()
		var unavailable: Dictionary = await game.execute_action_async(command("receive_feedback",{"event_id":origin.event_id}))
		check(not unavailable.success and unavailable.error_code == "FEEDBACK_UNAVAILABLE" and game.snapshot() == before,"never-disclosed outcome cannot invent a report on a real return")
	else:
		await receive_real_feedback(origin,label,evidence,changes)
	check_initial_and_reload(origin,label)
	var before_late_replay: Dictionary = game.snapshot()
	var late_replay: Dictionary = await game.execute_action_async({"type":"use_product","action_id":origin.use_action_id,"item_id":"friendship_knot"})
	check(late_replay.get("replayed",false) and late_replay.get("result") == origin.initial_reply.result and game.snapshot() == before_late_replay,"replaying the original use after late feedback returns its original result without another delta / "+label)
	if not (await act("load_game",{"save_id":game.state.save_id})).success:
		return
	check(game.state.processed_actions[origin.use_action_id] == origin.initial_reply,"disk reload preserves the initial reply after late feedback / "+label)
	check(not JSON.stringify(Shop.view(game.state,game.shop_config).shop.uses).contains(origin.relation_id),"public use projection withholds the private relationship selector / "+label)

func admit_real_return(npc_id: String) -> bool:
	# Only real public queue rows are admitted. The functional return configuration
	# keeps this finite without injecting a future arrival/report or changing time.
	for attempt: int in range(96):
		for row: Dictionary in game.people_view().get("queue",[]):
			if row.npc_id == npc_id:
				return (await act("start_arrival",{"arrival_id":row.arrival_id})).success
		var now := int(game.state.clock_minutes)
		var end := floori(float(now)/1440.0)*1440+int(game.content.rules.closing_minute)
		var next := end
		for row: Dictionary in game.state.people.arrivals.values():
			if row.npc_id == npc_id and row.state == "planned" and int(row.at) > now:
				next = mini(next,int(row.at))
		if now >= end:
			if not (await act("next_day")).success: return false
		elif not (await act("wait",{"minutes":mini(180,maxi(1,next-now))})).success:
			return false
	check(false,"the actual ordinary scheduler did not expose a usable return within the finite guard")
	return false

func receive_real_feedback(origin: Dictionary, label: String, evidence: String, changes: bool) -> void:
	var request := command("receive_feedback",{"event_id":origin.event_id})
	var before: Dictionary = game.snapshot()
	var disk: Dictionary = saves.read_save(before.save_id).state
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(request)
	check(not failed.success and failed.error_code == "SAVE_WRITE_FAILED" and game.snapshot() == before and saves.read_save(before.save_id).state == disk,"failed report save publishes no report, link or extra delta / "+label)
	var delivered: Dictionary = await game.execute_action_async(request)
	if not check(delivered.success,"same report action retries through the real saved boundary / "+label+" / "+str(delivered.get("message",""))):
		return
	var report: Dictionary = delivered.result.feedback
	check(report.evidence == evidence and (report.has("outcome") if evidence == "sufficient" else not report.has("outcome")),"report reveals only the evidence actually available / "+label)
	var refs: Array = report.get("item_component_refs",[])
	var use: Dictionary = game.state.shop.uses.filter(func(row: Dictionary) -> bool: return row.item_use_id == origin.use_id)[0]
	if changes:
		check(refs.size() == 1 and refs[0].item_use_id == origin.use_id and refs[0].component_id == "primary" and refs[0].actual_delta == 3,"real NPC report references the exact applied product component and actual delta")
		check(use.component_results[0].feedback_refs.any(func(row: Dictionary) -> bool: return row.kind == "npc_feedback" and row.source_id == report.feedback_id) and game.state.shop.feedback_links.any(func(row: Dictionary) -> bool: return row.item_use_id == origin.use_id and row.feedback_id == report.feedback_id),"Shop feedback links only the genuine report and exact component")
	else:
		check(refs.is_empty() and not use.component_results[0].feedback_refs.any(func(row: Dictionary) -> bool: return row.kind == "npc_feedback") and not game.state.shop.feedback_links.any(func(row: Dictionary) -> bool: return row.item_use_id == origin.use_id),"refused or partial-evidence cooperation cannot pretend an NPC relationship effect / "+label)
	var committed: Dictionary = game.snapshot()
	var replay: Dictionary = await game.execute_action_async(request)
	check(replay.get("replayed",false) and game.snapshot() == committed,"report replay never applies another relationship change / "+label)

func check_initial_and_reload(origin: Dictionary, label: String) -> void:
	check(game.state.processed_actions[origin.use_action_id] == origin.initial_reply,"late NPC feedback never rewrites the first use reply / "+label)
	var ledger: Array = game.state.shop.ledger.filter(func(row: Dictionary) -> bool: return row.action_id == origin.use_action_id)
	check(ledger.size() == 1 and ledger[0].result == origin.initial_use,"late feedback preserves the initial committed use ledger / "+label)
	var snapshot: Dictionary = game.snapshot()
	var stored: Dictionary = saves.read_save(snapshot.save_id)
	check(stored.success and stored.state == snapshot,"component sources, reports and initial reply survive actual disk validation / "+label)
	var missing := snapshot.duplicate(true)
	missing.divination.cases[origin.visit_id].erase("product_components")
	check(not saves.validate_snapshot(missing).success,"missing case component source is rejected after the full flow / "+label)
	var wrong := snapshot.duplicate(true)
	wrong.processed_actions[origin.use_action_id].result.item_use.item_use_id = "wrong_use_action_identity"
	check(not saves.validate_snapshot(wrong).success,"changed replay action/use identity is rejected after the full flow / "+label)
	var renamed := snapshot.duplicate(true)
	var original_reply: Dictionary = renamed.processed_actions[origin.use_action_id]
	renamed.processed_actions.erase(origin.use_action_id)
	renamed.processed_actions["renamed_use_action"] = original_reply
	check(not saves.validate_snapshot(renamed).success,"renaming the committed action ID breaks the use-to-action source and is rejected / "+label)

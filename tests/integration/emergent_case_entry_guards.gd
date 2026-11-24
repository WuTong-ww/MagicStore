extends RefCounted
## UNRUN: root supplies real planned-ready and queued-ready candidate snapshots
## from its action path, with an actual strict Session. No fabricated codec.
const DailyLoop = preload("res://scripts/core/daily_loop.gd")
const Bridge = preload("res://scripts/shop/people_bridge.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func run(planned: Dictionary, queued: Dictionary, live_session, people_config: Dictionary, arrival_id: String) -> Dictionary:
	var planned_hash := Schema.definition_hash(planned)
	var queued_hash := Schema.definition_hash(queued)
	var live_hash := Schema.definition_hash({"data":live_session.data,"definitions":live_session.case_definitions,"bindings":live_session.verified_bindings})
	var built: Dictionary = live_session.candidate_for(planned)
	check(built.get("success",false) and built.get("bindings",{}).has(arrival_id),"actual strict builder supplies this ready arrival binding")
	if not failures.is_empty():
		return {"checks":checks,"failures":failures}
	var bindings: Dictionary = built.bindings
	var row: Dictionary = planned.people.arrivals[arrival_id]
	check(row.state=="planned" and planned.active_visit_id.is_empty(),"planned source is captured before entry")
	check(DailyLoop.validate(planned,bindings).is_empty(),"complete real planned-ready roster validates with builder bindings")
	check(not DailyLoop.validate(planned).is_empty(),"same dynamic roster cannot pass the backward-compatible empty binding default")
	check(DailyLoop.verified_ready_case(planned,row,bindings),"actual ready owner/definition hash is accepted")
	for mutation: String in ["missing_binding","extra_binding_key","binding_owner","binding_case","binding_hash","reserved","record_owner","record_case","record_hash","definition_hash","definition_subject","fixed","family","generated","shopping","other_arrival","prefix_only"]:
		var bad := planned.duplicate(true)
		var table := bindings.duplicate(true)
		var bad_row: Dictionary = bad.people.arrivals[arrival_id]
		var record: Dictionary = bad.divination.emergent_cases.instances[arrival_id]
		var profile: Dictionary = bad.people.profiles[row.npc_id]
		match mutation:
			"missing_binding": table.erase(arrival_id)
			"extra_binding_key": table[arrival_id].definition = record.definition.duplicate(true)
			"binding_owner": table[arrival_id].npc_id = "npc_lin"
			"binding_case": table[arrival_id].case_id = "ec_unverified"
			"binding_hash": table[arrival_id].definition_hash = "unverified"
			"reserved": record.status = "reserved"
			"record_owner": record.npc_id = "npc_lin"
			"record_case": record.case_id = "ec_unverified"
			"record_hash": record.definition_hash = "unverified"
			"definition_hash": record.definition.question += " 篡改"
			"definition_subject": record.definition.outcomes.subject_id = "npc_lin"
			"fixed": profile.template_id = "fixed_story"
			"family": profile.family_library_member = true
			"generated": profile.generation_member = "person"
			"shopping": bad_row.intent = "shopping"
			"other_arrival": bad_row.arrival_id += "_other"
			"prefix_only":
				table.erase(arrival_id)
				bad.divination.emergent_cases.instances.erase(arrival_id)
				bad_row.case_id = "ec_prefix_is_not_authority"
		check(not DailyLoop.verified_ready_case(bad,bad_row,table),"reject unverified dynamic entry: "+mutation)
		check(not DailyLoop.validate(bad,table).is_empty(),"full daily validation also rejects: "+mutation)
	var admitted: Dictionary = live_session.candidate_for(queued)
	check(admitted.get("success",false),"queued candidate resolves with the actual builder")
	if admitted.get("success",false):
		var session = admitted.session
		var definition: Dictionary = session.case_definitions[bindings[arrival_id].case_id]
		check(queued.people.arrivals[arrival_id].state=="queued" and queued.active_visit_id.is_empty(),"queued source is a real pre-start candidate")
		var work := queued.duplicate(true)
		var action := {"action_id":"entry_guard_start","arrival_id":arrival_id,"visit_id":"visit_entry_guard"}
		var result: Dictionary = Bridge.start(work,action,session,people_config,true)
		check(result.get("success",false),"real bridge creates the ordinary CASE visit")
		if result.get("success",false):
			var case: Dictionary = work.divination.cases[action.visit_id]
			check(case.case_id==definition.id and case.event.subject_id==row.npc_id and case.event.target_name==definition.outcomes.target_name,"subject and target come from the verified owner and outcome")
			check(work.visits.back().dialogue[0].text==definition.question,"first public statement is exactly the verified question")
			check(case.world_facts==definition.truth and case.board.definition_id==definition.id and case.board.hash==bindings[arrival_id].definition_hash,"real CASE board and private facts use the same verified definition")
		for mutation: String in ["missing_binding","stale_definition","stale_template","stale_binding","owner"]:
			var rejected: Dictionary = live_session.candidate_for(queued)
			check(rejected.get("success",false),"fresh strict candidate for bridge negative: "+mutation)
			if not rejected.get("success",false):
				continue
			var rejected_session = rejected.session
			var before := queued.duplicate(true)
			match mutation:
				"missing_binding": rejected_session.verified_bindings.erase(arrival_id)
				"stale_definition": rejected_session.case_definitions[definition.id].question += " 篡改"
				"stale_template": rejected_session.data.cases[definition.id].event.target_name += " 篡改"
				"stale_binding": rejected_session.verified_bindings[arrival_id].definition_hash = "stale"
				"owner": before.people.profiles[row.npc_id].family_library_member = true
			var before_hash := Schema.definition_hash(before)
			var denied: Dictionary = Bridge.start(before,action,rejected_session,people_config,true)
			check(not denied.get("success",false) and denied.get("error_code")=="CASE_INVALID","bridge refuses invalid ready binding before entry: "+mutation)
			check(Schema.definition_hash(before)==before_hash,"rejected bridge start changes no row/profile/visit/wallet: "+mutation)
	check(Schema.definition_hash(planned)==planned_hash and Schema.definition_hash(queued)==queued_hash,"all supplied legal snapshots remain unchanged")
	check(Schema.definition_hash({"data":live_session.data,"definitions":live_session.case_definitions,"bindings":live_session.verified_bindings})==live_hash,"negative attempts never pollute the live Session")
	return {"checks":checks,"failures":failures}

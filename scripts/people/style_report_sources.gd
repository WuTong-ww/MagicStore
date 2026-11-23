extends RefCounted
## Trusted read-only joins over GameState's committed, validated snapshot.
## No SaveService preload: Save -> Bridge -> this adapter must stay acyclic.
const Report = preload("res://scripts/people/style_report.gd")
const DIMENSIONS := ["inquiry","caution","commerce","relations","rhythm","reflection"]

static func public_report(state: Dictionary) -> Dictionary:
	var rules := Report.load_rules()
	return Report.derive(collect(state,rules),rules)

static func collect(state: Dictionary, rules: Dictionary) -> Dictionary:
	var facts := {"version":1,"save_id":str(state.get("save_id","")),"state_version":int(state.get("state_version",0)),"as_of_game_minute":int(state.get("clock_minutes",0)),"window":{"visit_ids":[],"started_at":0,"ended_at":0},"visits":[],"talks":[],"predictions":[],"paid_services":[],"trades":[],"manual_contacts":[],"arrival_episodes":[],"disclosed_feedback":[],"reviews":[],"coverage":{},"evidence":{}}
	for dimension: String in DIMENSIONS:
		facts.coverage[dimension] = {"status":"complete","missing_count":0,"baseline_at":null,"reason":""}
	if not Report.rules_valid(rules):
		return facts
	var selected: Array = []
	var all_visits: Dictionary = {}
	for raw: Variant in state.get("visits",[]):
		if not raw is Dictionary or not raw.get("visit_id") is String:
			continue
		all_visits[raw.visit_id] = raw
		if raw.get("phase") == "ended" and _integer(raw.get("started_at")) and _integer(raw.get("ended_at")) and raw.ended_at >= raw.started_at:
			selected.append(raw)
	selected.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.ended_at < b.ended_at if a.ended_at != b.ended_at else a.visit_id < b.visit_id)
	selected = selected.slice(maxi(0,selected.size()-int(rules.window.latest_ended_visits)))
	var actions: Dictionary = state.get("processed_actions",{})
	var cases: Dictionary = state.get("divination",{}).get("cases",{})
	for visit: Dictionary in selected:
		facts.window.visit_ids.append(visit.visit_id)
		if facts.visits.is_empty():
			facts.window.started_at = int(visit.started_at)
		facts.window.started_at = mini(int(facts.window.started_at),int(visit.started_at))
		facts.window.ended_at = maxi(int(facts.window.ended_at),int(visit.ended_at))
		var ended := _find_action(actions,["end_visit"],"visit_id",visit.visit_id)
		var basis := _basis(facts,rules,"visit",visit.visit_id,visit.visit_id,ended.get("id",""),visit.ended_at)
		facts.visits.append({"id":visit.visit_id,"basis_id":basis,"started_at":int(visit.started_at),"ended_at":int(visit.ended_at)})
		if ended.is_empty():
			_miss(facts,rules,"rhythm")
		var case: Dictionary = cases.get(visit.visit_id,{})
		_talks(facts,rules,visit,case,actions)
		_prediction_and_services(facts,rules,state,visit,case,actions)
	_trades(facts,rules,state,all_visits,actions)
	_contacts(facts,rules,state,all_visits,actions)
	_arrivals(facts,rules,state,all_visits)
	_feedback(facts,rules,state,all_visits,actions)
	for key: String in ["talks","predictions","paid_services","trades","manual_contacts","arrival_episodes","disclosed_feedback","reviews"]:
		facts[key].sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.id < b.id)
	return facts

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value == floor(value) and value <= 9007199254740991

static func _action(actions: Dictionary, id: String, kinds: Array) -> Dictionary:
	var row: Dictionary = actions.get(id,{})
	if row.get("success") != true or row.get("action_type") not in kinds or not _integer(row.get("state_version")) or not row.get("result") is Dictionary:
		return {}
	return {"id":id,"order":int(row.state_version),"result":row.result}

static func _find_action(actions: Dictionary, kinds: Array, field: String, value: String) -> Dictionary:
	var matches: Array = []
	for id: String in actions:
		var row := _action(actions,id,kinds)
		if not row.is_empty() and row.result.get(field) == value:
			matches.append(row)
	if matches.size() != 1:
		return {}
	return matches[0]

static func _basis(facts: Dictionary, rules: Dictionary, kind: String, source_id: String, visit_id: String, action_id: String, at: Variant, related: Array = []) -> String:
	var id := kind+":"+source_id
	facts.evidence[id] = {"id":id,"kind":kind,"label":rules.copy.evidence_labels[kind],"text":rules.copy.evidence_text[kind],"visit_id":visit_id,"action_id":action_id,"at":int(at) if _integer(at) else null,"related_visit_ids":related.duplicate()}
	return id

static func _miss(facts: Dictionary, rules: Dictionary, dimension: String, unknown: bool = false) -> void:
	var row: Dictionary = facts.coverage[dimension]
	row.missing_count += 1
	row.status = "unknown" if unknown or row.status == "unknown" else "partial"
	row.reason = rules.copy.coverage_unknown if row.status == "unknown" else rules.copy.coverage_incomplete

static func _talks(facts: Dictionary, rules: Dictionary, visit: Dictionary, case: Dictionary, actions: Dictionary) -> void:
	if not case.get("conversation") is Array:
		_miss(facts,rules,"inquiry",true)
		return
	var seen := {}
	for raw: Variant in case.conversation:
		if not raw is Dictionary or not raw.get("action_id") is String:
			_miss(facts,rules,"inquiry")
			continue
		var id: String = raw.action_id
		if seen.has(id):
			if seen[id] != raw:
				_miss(facts,rules,"inquiry")
			continue
		seen[id] = raw
		var source := _action(actions,id,["talk"])
		var index: Variant = raw.get("statement_index")
		var dialogue: Array = visit.get("dialogue",[])
		if source.is_empty() or source.result.get("visit_id") != visit.visit_id or not _integer(raw.get("at")) or raw.at < visit.started_at or raw.at > visit.ended_at or not _integer(index) or index < 1 or index >= dialogue.size() or dialogue[int(index)].get("speaker") != "npc" or dialogue[int(index)-1].get("speaker") != "player" or dialogue[int(index)].get("text") != source.result.get("reply_text"):
			_miss(facts,rules,"inquiry")
			continue
		var channel: String = raw.get("channel","unknown") if raw.get("channel") in ["button","free_text"] else "unknown"
		if channel == "unknown":
			_miss(facts,rules,"inquiry")
		var basis := _basis(facts,rules,"talk",id,visit.visit_id,id,raw.at)
		facts.talks.append({"id":id,"visit_id":visit.visit_id,"basis_id":basis,"at":int(raw.at),"order":source.order,"channel":channel})

static func _prediction_and_services(facts: Dictionary, rules: Dictionary, state: Dictionary, visit: Dictionary, case: Dictionary, actions: Dictionary) -> void:
	if not case.get("services") is Dictionary or not case.get("prediction") is Dictionary:
		_miss(facts,rules,"caution",true)
		return
	var prediction: Dictionary = case.prediction
	if not prediction.is_empty():
		var source := _find_action(actions,["record_prediction"],"prediction_id",str(prediction.get("prediction_id","")))
		if source.is_empty() or source.result.get("visit_id") != visit.visit_id or not _integer(prediction.get("at")) or prediction.at < visit.started_at or prediction.at > visit.ended_at:
			_miss(facts,rules,"caution")
		else:
			var basis := _basis(facts,rules,"prediction",prediction.prediction_id,visit.visit_id,source.id,prediction.at)
			facts.predictions.append({"id":prediction.prediction_id,"visit_id":visit.visit_id,"basis_id":basis,"at":int(prediction.at),"order":source.order})
	for id: String in case.services:
		var service: Dictionary = case.services[id]
		var status: String = service.get("status","")
		if status not in ["paid","quoted","cancelled"] or not service.get("method_id") is String:
			_miss(facts,rules,"caution")
			continue
		var source := _find_action(actions,["settle_service","reading"] if status == "paid" else ["quote_service"],"service_id",id)
		var at: Variant = service.get("paid_at") if status == "paid" else service.get("quoted_at")
		var valid: bool = not source.is_empty() and source.result.get("visit_id") == visit.visit_id and _integer(at)
		if status == "paid":
			var payments: Array = state.get("divination",{}).get("ledger",[]).filter(func(row: Dictionary) -> bool: return row.get("category") == "divination" and row.get("reference_id") == id)
			valid = valid and source.result.get("service_result") == service.get("result") and payments.size() == 1
			if payments.size() == 1:
				var payment: Dictionary = payments[0]
				valid = valid and payment.get("visit_id") == visit.visit_id and payment.get("npc_id") == visit.npc_id and payment.get("payment") == service.get("payment") and _integer(payment.get("at")) and _integer(service.get("minutes")) and int(payment.at)+int(service.minutes) == int(at)
		if not valid:
			_miss(facts,rules,"caution")
		var basis := _basis(facts,rules,"service",id,visit.visit_id,source.get("id",""),at if valid else null)
		facts.paid_services.append({"id":id,"visit_id":visit.visit_id,"basis_id":basis,"at":int(at) if valid else null,"order":source.get("order") if valid else null,"method_id":service.method_id,"status":status})

static func _trades(facts: Dictionary, rules: Dictionary, state: Dictionary, visits: Dictionary, actions: Dictionary) -> void:
	var collected := {}
	if not state.get("shop",{}).get("ledger") is Array:
		_miss(facts,rules,"commerce",true)
	for entry: Dictionary in state.get("shop",{}).get("ledger",[]):
		if entry.get("category") != "product":
			continue
		var sale: Dictionary = entry.get("result",{})
		var visit_id: String = sale.get("visit_id","")
		if visit_id not in facts.window.visit_ids:
			continue
		var source := _action(actions,str(entry.get("action_id","")),["sell_product"])
		var valid: bool = not source.is_empty() and _integer(entry.get("at")) and visits.has(visit_id) and sale.get("npc_id") == visits[visit_id].npc_id and _integer(sale.get("quantity")) and sale.quantity > 0
		for field: String in ["transaction_id","item_id","visit_id","npc_id","quantity","source_batches"]:
			valid = valid and sale.get(field) == source.get("result",{}).get(field)
		if not valid:
			_miss(facts,rules,"commerce")
			continue
		_trade(facts,rules,collected,str(sale.transaction_id),visit_id,int(entry.at),"shop",int(sale.quantity),source.id)
	for entry: Dictionary in state.get("divination",{}).get("ledger",[]):
		if entry.get("category") != "product" or entry.get("visit_id") not in facts.window.visit_ids:
			continue
		var id: String = entry.get("reference_id","")
		var visit_id: String = entry.visit_id
		var source := _find_action(actions,["buy_case_item"],"transaction_id",id)
		var purchase: Dictionary = state.divination.cases.get(visit_id,{}).get("purchase",{})
		if source.is_empty() or source.result.get("visit_id") != visit_id or purchase.get("transaction_id") != id or purchase.get("item_id") != entry.get("item_id") or purchase.get("at") != entry.get("at") or visits[visit_id].npc_id != entry.get("npc_id") or not _integer(entry.get("quantity")) or entry.quantity < 1:
			_miss(facts,rules,"commerce")
			continue
		_trade(facts,rules,collected,id,visit_id,int(entry.at),"divination",int(entry.quantity),source.id)
	for id: String in collected:
		facts.trades.append(collected[id])

static func _trade(facts: Dictionary, rules: Dictionary, collected: Dictionary, id: String, visit_id: String, at: int, space: String, quantity: int, action_id: String) -> void:
	if collected.has(id):
		var previous: Dictionary = collected[id]
		if previous.visit_id != visit_id or previous.at != at or previous.quantity != quantity:
			_miss(facts,rules,"commerce")
		return
	var basis := _basis(facts,rules,"trade",id,visit_id,action_id,at)
	collected[id] = {"id":id,"visit_id":visit_id,"basis_id":basis,"at":at,"namespace":space,"kind":"product","quantity":quantity}

static func _contacts(facts: Dictionary, rules: Dictionary, state: Dictionary, visits: Dictionary, actions: Dictionary) -> void:
	var seen := {}
	for arrival: Dictionary in state.get("people",{}).get("arrivals",{}).values():
		if arrival.get("agreed_return") != true and arrival.get("source") != "invited_contact":
			continue
		var visit_id: String = arrival.get("source_visit_id","")
		if visit_id not in facts.window.visit_ids:
			continue
		var kind: String = "return" if arrival.get("agreed_return") == true else "invite"
		var source := _action(actions,str(arrival.get("source_action_id","")),["end_visit"] if kind == "return" else ["invite_contact"])
		var valid := not source.is_empty()
		if kind == "return":
			valid = valid and source.get("result",{}).get("visit_id") == visit_id and source.get("result",{}).get("return_appointment",{}).get("arrival_id") == arrival.get("arrival_id") and visits[visit_id].npc_id == arrival.get("npc_id")
		else:
			valid = valid and source.get("result",{}).get("arrival_id") == arrival.get("arrival_id") and source.get("result",{}).get("npc_id") == arrival.get("npc_id") and visits[visit_id].npc_id == arrival.get("referrer_npc_id") and state.people.get("revealed_relationships",{}).has(arrival.get("relationship_id"))
		if not valid:
			_miss(facts,rules,"relations")
			continue
		if seen.has(source.id):
			continue
		seen[source.id] = true
		var at: Variant = int(visits[visit_id].ended_at) if kind == "return" else null
		var basis := _basis(facts,rules,"contact",source.id,visit_id,source.id,at)
		facts.manual_contacts.append({"id":source.id,"visit_id":visit_id,"basis_id":basis,"at":at,"kind":kind,"arrival_id":arrival.arrival_id})

static func _arrivals(facts: Dictionary, rules: Dictionary, state: Dictionary, visits: Dictionary) -> void:
	var people: Dictionary = state.get("people",{})
	var metrics: Dictionary = people.get("family_metrics",{})
	if not _integer(metrics.get("baseline_at")) or not metrics.get("physical_arrivals") is Array:
		_miss(facts,rules,"rhythm",true)
		return
	facts.coverage.rhythm.baseline_at = int(metrics.baseline_at)
	if metrics.baseline_at > facts.window.started_at and not facts.visits.is_empty():
		_miss(facts,rules,"rhythm")
	var seen := {}
	for episode: Dictionary in metrics.physical_arrivals:
		if not _integer(episode.get("at")) or episode.at > facts.window.ended_at:
			continue
		if episode.at < metrics.baseline_at:
			_miss(facts,rules,"rhythm")
			continue
		var id := JSON.stringify([episode.arrival_id,int(episode.at)])
		if seen.has(id):
			continue
		seen[id] = true
		var arrival: Dictionary = people.get("arrivals",{}).get(episode.arrival_id,{})
		if arrival.is_empty():
			_miss(facts,rules,"rhythm")
			continue
		var visit_id := ""
		var resolved: Variant = null
		var status := "waiting"
		var linked: Dictionary = visits.get(arrival.get("visit_id",""),{})
		if linked.get("phase") == "ended" and linked.get("visit_id") in facts.window.visit_ids and int(linked.started_at) >= int(episode.at) and arrival.get("at") == episode.at:
			status = "served"
			visit_id = linked.visit_id
			resolved = int(linked.ended_at)
		elif arrival.get("at") == episode.at and arrival.get("state") == "left" and arrival.get("loss") is Dictionary and arrival.loss.get("at") == arrival.get("left_at"):
			status = "lost"
			resolved = arrival.left_at
		elif arrival.get("at") != episode.at or arrival.get("state") not in ["queued","outside","appointment_requested","in_service"]:
			_miss(facts,rules,"rhythm")
			continue
		if resolved != null and (not _integer(resolved) or resolved < facts.window.started_at or resolved > facts.window.ended_at):
			continue
		if resolved == null and episode.at < facts.window.started_at:
			continue
		var basis := _basis(facts,rules,"arrival",id,visit_id,"",resolved if resolved != null else episode.at)
		facts.arrival_episodes.append({"id":id,"arrival_id":episode.arrival_id,"visit_id":visit_id,"basis_id":basis,"at":int(episode.at),"resolved_at":int(resolved) if resolved != null else null,"state":status})

static func _feedback(facts: Dictionary, rules: Dictionary, state: Dictionary, visits: Dictionary, actions: Dictionary) -> void:
	for visit_id: String in facts.window.visit_ids:
		var case: Dictionary = state.get("divination",{}).get("cases",{}).get(visit_id,{})
		var event: Dictionary = case.get("event",{})
		var report: Dictionary = event.get("feedback",{}).get("report",{})
		# Never inspect occurrence/outcome/evaluation outside the disclosed report.
		if report.is_empty() or report.get("evaluation") != "deviated" or report.get("can_review") != true:
			continue
		var source := {}
		for action_id: String in actions:
			var action := _action(actions,action_id,["receive_feedback"])
			if not action.is_empty() and action.result.get("feedback",{}).get("feedback_id") == report.get("feedback_id") and action.result.get("feedback",{}).get("event_id") == event.get("event_id") and action.result.get("feedback",{}).get("evaluation") == report.evaluation:
				source = action
		var effect := {}
		for raw: Dictionary in state.get("divination",{}).get("effects",[]):
			if raw.get("event_id") == event.get("event_id") and raw.get("prediction_id") == case.get("prediction",{}).get("prediction_id") and raw.get("visit_id") == visit_id and raw.get("kind") == "review_growth" and raw.get("recipient") == "C" and raw.get("effect_id") in state.get("shop",{}).get("effects_applied",[]):
				effect = raw
		if source.is_empty() or effect.is_empty() or not _integer(report.get("at")) or not visits.has(report.get("visit_id")) or source.result.get("visit_id") != report.visit_id:
			_miss(facts,rules,"reflection")
			continue
		var related: Array = [report.visit_id] if report.visit_id != visit_id else []
		var basis := _basis(facts,rules,"feedback",report.feedback_id,visit_id,source.id,report.at,related)
		facts.disclosed_feedback.append({"id":report.feedback_id,"visit_id":visit_id,"basis_id":basis,"at":int(report.at),"event_id":event.event_id,"prediction_id":case.prediction.prediction_id,"effect_id":effect.effect_id,"evaluation":"deviated","reviewable":true,"disclosed":true})
		for entry: Dictionary in state.get("shop",{}).get("ledger",[]):
			if entry.get("category") != "review" or entry.get("result",{}).get("effect_id") != effect.effect_id:
				continue
			var reviewed := _action(actions,str(entry.get("action_id","")),["review_case"])
			if reviewed.is_empty() or reviewed.result.get("effect_id") != effect.effect_id or effect.effect_id not in state.shop.get("reviews",[]) or not _integer(entry.get("at")) or entry.at < report.at:
				_miss(facts,rules,"reflection")
				continue
			var review_basis := _basis(facts,rules,"review",reviewed.id,visit_id,reviewed.id,entry.at,related)
			facts.reviews.append({"id":reviewed.id,"visit_id":visit_id,"basis_id":review_basis,"at":int(entry.at),"effect_id":effect.effect_id,"feedback_id":report.feedback_id})

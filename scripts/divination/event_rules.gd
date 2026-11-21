extends RefCounted
## Hidden resolution, player prediction and actual disclosure are distinct records.
const CONDITIONS := {"always": "无附加条件", "if_message": "若先发消息确认", "if_attend": "若直接去展览"}

static func conditions(definition: Dictionary) -> Dictionary:
	var result := {}
	for id: String in definition.get("prediction_conditions",{}):
		result[id] = definition.prediction_conditions[id].label
	return CONDITIONS.duplicate() if result.is_empty() else result

static func labels(definition: Dictionary) -> Dictionary:
	return definition.get("prediction_labels",{}).duplicate(true)

static func create(visit: Dictionary, definition: Dictionary) -> Dictionary:
	var due := int(visit.day) * 1440 + int(definition.minute_of_day)
	if due <= int(visit.started_at):
		due += 1440
	var event := {
		"event_id":"event_"+String(visit.visit_id).trim_prefix("visit_"),
		"subject_id":definition.subject_id,"target_name":definition.target_name,
		"due_at":due,"occurrence":"pending","resolved_at":-1,
		"outcome_id":"","outcome":"","evidence":"pending","actual_action":"",
		"advice_id":"","item_use_id":"","branch_id":"",
		"evaluation":"pending","evaluated_at":-1,
		"feedback":{"mode":"pending","available_at":-1,"disclosure":{},"report":{}}
	}
	if definition.has("template_id"):
		event["template_id"] = definition.template_id
	return event

static func advance(state: Dictionary, data: Dictionary) -> void:
	var jobs: Array[Dictionary] = []
	for case: Dictionary in state.divination.cases.values():
		var event: Dictionary = case.get("event",{})
		if not event.is_empty() and event.occurrence == "pending" and int(event.due_at) <= int(state.clock_minutes):
			jobs.append(case)
	jobs.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return a.event.event_id < b.event.event_id if a.event.due_at == b.event.due_at else a.event.due_at < b.event.due_at)
	for case: Dictionary in jobs:
		_resolve(case,data.cases[case.case_id].event,state)

static func _selected_advice(case: Dictionary) -> Dictionary:
	var entries: Array = case.get("advice",[])
	for index: int in range(entries.size()-1,-1,-1):
		if entries[index].get("accepted",false):
			return entries[index]
	return entries.back() if not entries.is_empty() else {}

static func _matches(when: Dictionary, case: Dictionary, definition: Dictionary, state: Dictionary) -> bool:
	var advice := _selected_advice(case)
	if when.has("advice") and not _contains(when.advice,advice.get("advice_key","")):
		return false
	if when.has("accepted") and when.accepted != advice.get("accepted",false):
		return false
	for id: String in when.get("fact",{}):
		var actual: Variant = case.get("world_facts",{}).get(id,{}).get("value",definition.world_facts[id].default)
		if actual != when.fact[id]:
			return false
	if when.has("branch"):
		var required: Array = when.branch if when.branch is Array else [when.branch]
		if not required.all(func(id: String) -> bool: return id in case.get("branches",[])):
			return false
	if when.has("item_effect") and not _contains(when.item_effect,case.get("item_use",{}).get("effect_key","")):
		return false
	for id: String in when.get("relationship_min",{}):
		var relation: Dictionary = state.get("people",{}).get("relationships",{}).get(id,{})
		if relation.is_empty() or int(relation.get("closeness",0)) < int(when.relationship_min[id]):
			return false
	if when.has("personality_in"):
		var profile: Dictionary = state.get("people",{}).get("profiles",{}).get(case.get("npc_id",""),{})
		if not profile.get("personality_id","") in when.personality_in:
			return false
	return true

static func _contains(expected: Variant, actual: Variant) -> bool:
	return actual in expected if expected is Array else expected == actual

static func _resolve(case: Dictionary, definition: Dictionary, state: Dictionary = {}) -> void:
	var event: Dictionary = case.event
	if event.occurrence != "pending":
		return
	var outcome_id := ""
	var rule_index := -1
	for index: int in range(definition.rules.size()):
		var rule: Dictionary = definition.rules[index]
		if _matches(rule.when,case,definition,state):
			outcome_id = rule.outcome
			rule_index = index
			break
	if outcome_id.is_empty():
		return
	var selected: Dictionary = definition.outcomes[outcome_id]
	var advice := _selected_advice(case)
	var item_use: Dictionary = case.get("item_use",{})
	var linked_item := false
	var effect: Dictionary = definition.get("item_effect",{})
	if advice.get("accepted",false) and item_use.get("effect_key","") == effect.get("key","") and not effect.get("key","").is_empty():
		linked_item = advice.get("advice_key","") in effect.get("advice_keys",[])
		for option: Dictionary in definition.advice_options:
			if option.key == advice.get("advice_key") and item_use.effect_key in option.get("item_effect_keys",[]):
				linked_item = true
	var linked_branch := ""
	for id: String in definition.get("branch_ids",[]):
		if id in case.get("branches",[]):
			linked_branch = id
			break
	event.merge({"occurrence":"occurred" if selected.outcome == "met" else "did_not_occur",
		"resolved_at":event.due_at,"outcome_id":outcome_id,"outcome":selected.outcome,
		"evidence":selected.evidence,"actual_action":selected.actual_action,
		"advice_id":advice.get("advice_id",""),"item_use_id":item_use.get("item_use_id","") if linked_item else "",
		"branch_id":linked_branch,"rule_index":rule_index,"evaluation":"pending","evaluated_at":-1},true)
	event.feedback.mode = selected.feedback
	event.feedback.disclosure = {}
	if selected.feedback != "never":
		event.feedback.available_at = int(event.due_at)+int(selected.delay_minutes)
		if selected.evidence != "none":
			event.feedback.disclosure = {"text":selected.text,"evidence":selected.evidence}
			if selected.evidence == "sufficient":
				event.feedback.disclosure.merge({"occurrence":event.occurrence,"outcome":event.outcome,"actual_action":event.actual_action,"occurred_at":event.due_at if event.occurrence == "occurred" else -1})
	else:
		event.feedback.available_at = -1
	if not state.is_empty():
		_emit_effects(state,case,definition,"resolve")

static func _evaluate(case: Dictionary, at: int, definition: Dictionary = {}) -> void:
	var event: Dictionary = case.event
	var prediction: Dictionary = case.prediction
	if prediction.is_empty():
		return
	event.evaluated_at = at
	if event.evidence != "sufficient":
		event.evaluation = "insufficient"
		return
	var condition: Dictionary = definition.get("prediction_conditions",{}).get(prediction.condition,{})
	if condition.has("outcomes") and not _contains(condition.outcomes,event.outcome_id):
		event.evaluation = "condition_not_met"
	else:
		var met_within: bool = event.occurrence == "occurred" and int(event.due_at) >= int(prediction.window_start) and int(event.due_at) <= int(prediction.window_end)
		event.evaluation = "aligned" if (prediction.expected == "met") == met_within else "deviated"

static func can_report(event: Dictionary, clock: int) -> bool:
	var feedback: Dictionary = event.get("feedback",{})
	return event.get("occurrence") != "pending" and event.get("evidence") in ["sufficient","partial","insufficient"] and feedback.get("mode") in ["delayed","immediate"] and int(feedback.get("available_at",-1)) >= 0 and int(feedback.available_at) <= clock and feedback.get("report",{}).is_empty() and not str(feedback.get("disclosure",{}).get("text","")).is_empty()

static func disclose(state: Dictionary, case: Dictionary, current: Dictionary, _economy: Dictionary, definition: Dictionary = {}) -> Dictionary:
	var event: Dictionary = case.event
	if not event.feedback.report.is_empty():
		return event.feedback.report
	if not can_report(event,int(state.clock_minutes)):
		return {}
	if definition.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/divination.json"))
		definition = data.cases.get(case.get("case_id",""),{}).get("event",{})
	# Pre-G3 resolved records have an outcome but no rule-source metadata. Add
	# provenance only in this successful feedback candidate; never re-resolve
	# their historical choice or mutate the old file while loading it.
	if not event.has("rule_index"):
		var rules: Array = definition.get("rules",[])
		for index: int in range(rules.size()):
			if rules[index].outcome == event.outcome_id:
				event["rule_index"] = index
				break
	_evaluate(case,int(state.clock_minutes),definition)
	var report: Dictionary = event.feedback.disclosure.duplicate(true)
	if event.evidence != "sufficient":
		for key: String in ["occurrence","outcome","actual_action","occurred_at"]:
			report.erase(key)
	report.merge({"feedback_id":"feedback_"+String(event.event_id).trim_prefix("event_"),"event_id":event.event_id,"visit_id":current.visit_id,"at":int(state.clock_minutes),"evaluation":"no_prediction" if case.prediction.is_empty() else event.evaluation})
	event.feedback.report = report
	_emit_effects(state,case,definition,"feedback")
	for entry: Dictionary in state.divination.effects:
		if entry.event_id == event.event_id and entry.kind == "review_growth":
			report["can_review"] = true
	return report

static func _emit_effects(state: Dictionary, case: Dictionary, definition: Dictionary, stage: String) -> void:
	var selected: Dictionary = definition.get("outcomes",{}).get(case.event.outcome_id,{})
	for source: String in ["outcome","feedback"]:
		var entries: Array = selected.get("effects",[]) if source == "outcome" else definition.get("feedback_effects",[])
		for index: int in range(entries.size()):
			var spec: Dictionary = entries[index]
			if spec.get("stage","resolve" if source == "outcome" else "feedback") != stage:
				continue
			var context := {"evaluation":"no_prediction" if case.prediction.is_empty() else case.event.evaluation,"outcome":case.event.outcome,"outcome_id":case.event.outcome_id}
			var matches := true
			for key: String in spec.get("when",{}):
				if not _contains(spec.when[key],context.get(key)):
					matches = false
			if not matches:
				continue
			var kind: String = "arrival_boost" if spec.kind == "traffic_boost" else spec.kind
			var recipient := "A" if kind in ["trust","familiarity","npc_relationship","referral","unlock_topic"] else "C"
			var amount: int = int(spec.get("amount",spec.get("delta",spec.get("qty",1))))
			var metadata := {"stage":stage,"outcome_id":case.event.outcome_id,"rule_index":int(case.event.get("rule_index",-1)),"effect_index":index,"effect_source":source}
			for key: String in ["rel_id","delta","qty","template","topic_id","minutes"]:
				if spec.has(key):
					metadata[key] = spec[key]
			if spec.has("npc_id") or spec.has("target_npc_id"):
				metadata["target_npc_id"] = spec.get("target_npc_id",spec.get("npc_id",""))
			_effect(state,case,recipient,kind,amount,int(spec.get("minutes",0)),spec.get("item_id",""),metadata)

static func _effect(state: Dictionary, case: Dictionary, recipient: String, kind: String, amount: int, duration: int = 0, item_id: String = "", metadata: Dictionary = {}) -> Dictionary:
	var event: Dictionary = case.event
	var at := int(event.due_at) if metadata.get("stage") == "resolve" else int(state.clock_minutes)
	var id := "%s_%s" % [event.event_id,kind]
	if not metadata.is_empty():
		id = "%s_%s_%s_%s_%d_%s" % [event.event_id,metadata.stage,metadata.outcome_id,metadata.effect_source,int(metadata.effect_index),kind]
	for old: Dictionary in state.divination.effects:
		if old.effect_id == id:
			return old
	var effect: Dictionary = {"effect_id":id,"event_id":event.event_id,"prediction_id":case.get("prediction",{}).get("prediction_id",""),"visit_id":case.visit_id,"npc_id":case.npc_id,"subject_id":event.subject_id,"recipient":recipient,"kind":kind,"amount":amount,"starts_at":at,"expires_at":at+duration if duration > 0 else -1}
	effect.merge(metadata,true)
	if not item_id.is_empty():
		effect["item_id"] = item_id
	state.divination.effects.append(effect)
	return effect

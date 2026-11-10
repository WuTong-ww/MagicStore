extends RefCounted
## The case outcome, forecast evaluation and player disclosure are separate records.

const Economy = preload("res://scripts/divination/demo_economy.gd")
const CONDITIONS := {"always": "无附加条件", "if_message": "若先发消息确认", "if_attend": "若直接去展览"}

static func create(visit: Dictionary, definition: Dictionary) -> Dictionary:
	var due := int(visit.day) * 1440 + int(definition.minute_of_day)
	if due <= int(visit.started_at):
		due += 1440
	return {
		"event_id": "event_" + String(visit.visit_id).trim_prefix("visit_"),
		"subject_id": definition.subject_id, "target_name": definition.target_name,
		"due_at": due, "occurrence": "pending", "resolved_at": -1,
		"outcome_id": "", "outcome": "", "evidence": "pending", "actual_action": "",
		"advice_id": "", "item_use_id": "", "branch_id": "",
		"evaluation": "pending", "evaluated_at": -1,
		"feedback": {"mode": "pending", "available_at": -1, "disclosure": {}, "report": {}}
	}

static func advance(state: Dictionary, data: Dictionary) -> void:
	var jobs: Array[Dictionary] = []
	var clock := int(state.clock_minutes)
	for case: Dictionary in state.divination.cases.values():
		var event: Dictionary = case.event
		if event.is_empty():
			continue
		if event.occurrence == "pending" and int(event.due_at) <= clock:
			jobs.append({"case": case, "at": int(event.due_at), "stage": 0})
		if not case.prediction.is_empty() and event.evaluation == "pending":
			var evaluation_time := maxi(int(event.due_at), int(case.prediction.window_end))
			if evaluation_time <= clock:
				jobs.append({"case": case, "at": evaluation_time, "stage": 1})
	jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.at != b.at:
			return a.at < b.at
		var a_id: String = a.case.event.event_id
		var b_id: String = b.case.event.event_id
		return a.stage < b.stage if a_id == b_id else a_id < b_id
	)
	for job in jobs:
		var case: Dictionary = job.case
		if job.stage == 0:
			_resolve(case, data.cases[case.case_id].event)
		else:
			_evaluate(case, int(job.at))

static func _resolve(case: Dictionary, definition: Dictionary) -> void:
	var event: Dictionary = case.event
	var advice: Dictionary = case.advice.back() if not case.advice.is_empty() else {}
	for index: int in range(case.advice.size() - 1, -1, -1):
		if case.advice[index].accepted:
			advice = case.advice[index]
			break
	var item_use: Dictionary = case.item_use
	var confirmed_venue: bool = "confirmed_venue" in case.branches
	var changed_entrance: bool = case.world_facts.get("changed_entrance", {}).get("value", true)
	var helped_by_item: bool = item_use.get("effect_key", "") == definition.item_effect.key
	var outcome_id := "waited"
	if advice.get("accepted", false):
		match advice.advice_key:
			"message":
				outcome_id = "sent"
			"attend":
				outcome_id = "arrived" if not changed_entrance or confirmed_venue or helped_by_item else "lost"
			"private":
				outcome_id = "private"
			"note":
				outcome_id = "note"
	var selected: Dictionary = definition.outcomes[outcome_id]
	event.merge({
		"occurrence": "occurred" if selected.outcome == "met" else "did_not_occur",
		"resolved_at": event.due_at, "outcome_id": outcome_id, "outcome": selected.outcome,
		"evidence": selected.evidence, "actual_action": selected.actual_action,
		"advice_id": advice.get("advice_id", ""), "item_use_id": item_use.get("item_use_id", "") if advice.get("advice_key") == "attend" and advice.get("accepted") and helped_by_item else "",
		"branch_id": "confirmed_venue" if confirmed_venue else ""
	}, true)
	event.feedback.mode = selected.feedback
	if selected.feedback == "never":
		return
	event.feedback.available_at = maxi(int(event.due_at) + int(selected.get("delay", definition.feedback_delay)), int(case.prediction.get("window_end", -1)))
	event.feedback.disclosure = {"text": selected.text, "evidence": selected.evidence}
	if selected.evidence == "sufficient":
		event.feedback.disclosure.merge({
			"occurrence": event.occurrence, "outcome": event.outcome,
			"actual_action": event.actual_action, "occurred_at": event.due_at if event.occurrence == "occurred" else -1
		})

static func _evaluate(case: Dictionary, at: int) -> void:
	var event: Dictionary = case.event
	var prediction: Dictionary = case.prediction
	var condition_met := true
	match prediction.condition:
		"if_message":
			condition_met = event.outcome_id == "sent"
		"if_attend":
			condition_met = event.outcome_id in ["arrived", "lost"]
	event.evaluated_at = at
	if not condition_met:
		event.evaluation = "condition_not_met"
	elif event.evidence != "sufficient":
		event.evaluation = "insufficient"
	else:
		var met_within_window: bool = event.occurrence == "occurred" and int(event.due_at) >= int(prediction.window_start) and int(event.due_at) <= int(prediction.window_end)
		event.evaluation = "aligned" if (prediction.expected == "met") == met_within_window else "deviated"

static func can_report(event: Dictionary, clock: int) -> bool:
	return event.feedback.mode == "delayed" and int(event.feedback.available_at) <= clock and event.feedback.report.is_empty()

static func disclose(state: Dictionary, case: Dictionary, current: Dictionary, economy: Dictionary) -> Dictionary:
	var event: Dictionary = case.event
	var report: Dictionary = event.feedback.disclosure.duplicate(true)
	report.merge({
		"feedback_id": "feedback_" + String(event.event_id).trim_prefix("event_"),
		"event_id": event.event_id, "visit_id": current.visit_id, "at": int(state.clock_minutes),
		"evaluation": "no_prediction" if case.prediction.is_empty() else event.evaluation
	})
	event.feedback.report = report
	if report.evaluation == "aligned":
		_effect(state, case, "A", "trust", 2)
		if event.outcome == "met":
			_effect(state, case, "C", "reputation", 1)
			_effect(state, case, "C", "arrival_boost", 1, 2 * 1440)
			if event.outcome_id == "sent":
				_effect(state, case, "A", "referral", 1)
				var gift := _effect(state, case, "C", "gift", 1, 0, economy.gift_id)
				Economy.gift(state, current, gift, economy)
	elif report.evaluation == "deviated":
		_effect(state, case, "A", "trust", -2)
		_effect(state, case, "C", "review_growth", 1)
		report["can_review"] = true
	return report

static func _effect(state: Dictionary, case: Dictionary, recipient: String, kind: String, amount: int, duration: int = 0, item_id: String = "") -> Dictionary:
	var at := int(state.clock_minutes)
	var effect: Dictionary = {
		"effect_id": "%s_%s" % [case.event.event_id, kind],
		"event_id": case.event.event_id, "prediction_id": case.prediction.prediction_id,
		"visit_id": case.visit_id, "npc_id": case.npc_id, "subject_id": case.event.subject_id, "recipient": recipient,
		"kind": kind, "amount": amount, "starts_at": at,
		"expires_at": at + duration if duration > 0 else -1
	}
	if not item_id.is_empty():
		effect["item_id"] = item_id
	state.divination.effects.append(effect)
	return effect

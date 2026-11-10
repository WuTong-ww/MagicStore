extends RefCounted
## Validate the v2 namespace before SaveService accepts it.

const Catalog = preload("res://scripts/divination/catalog.gd")
const Events = preload("res://scripts/divination/event_rules.gd")
const OracleSaved = preload("res://scripts/divination/oracle_saved.gd")
const MAX_INT := 2147483647

static func validate(state: Dictionary, data: Dictionary, visits: Dictionary) -> String:
	var work: Variant = state.get("divination")
	if not work is Dictionary or not work.get("skills") is Array or not work.get("cases") is Dictionary or not work.get("past") is Dictionary or not work.get("ledger") is Array or not work.get("effects") is Array:
		return "问卜存档字段不完整"
	if not "tarot" in work.skills or work.cases.size() != visits.size():
		return "基础术式或接待案例缺失"
	var skills: Dictionary = {}
	for id in work.skills:
		if not id is String or not data.methods.has(id) or skills.has(id):
			return "未知或重复的已学术式"
		skills[id] = true
	var events: Dictionary = {}
	var services: Dictionary = {}
	for visit_id: String in work.cases:
		var visit: Variant = visits.get(visit_id)
		var case: Variant = work.cases[visit_id]
		if not visit is Dictionary or not case is Dictionary or case.get("visit_id") != visit_id or case.get("npc_id") != visit.npc_id or not data.cases.has(case.get("case_id")):
			return "案例未关联有效接待"
		if not _case_records(case, visit, data, int(state.clock_minutes)):
			return "案例事实、对话、术式或预测记录无效"
		if not case.event.is_empty():
			if events.has(case.event.event_id):
				return "事件编号重复"
			events[case.event.event_id] = case
		for id: String in case.services:
			if services.has(id):
				return "服务编号重复"
			services[id] = case.services[id]
	for action: Dictionary in state.processed_actions.values():
		var output: Dictionary = action.result
		if output.has("service_id"):
			var service: Dictionary = services.get(output.service_id, {})
			if service.is_empty() or output.get("visit_id") != service.visit_id:
				return "动作引用了未知术式服务"
			if output.has("service_result") and (service.status != "paid" or output.service_result != service.result):
				return "动作结果与已结算服务不一致"
	for npc_id: String in work.past:
		if not state.npcs.has(npc_id) or not _past(work.past[npc_id], npc_id, data, services):
			return "前世进度或证物引用无效"
	var entries: Dictionary = {}
	for entry in work.ledger:
		if not entry is Dictionary or not _text(entry.get("entry_id")) or entries.has(entry.entry_id) or not visits.has(entry.get("visit_id")) or entry.get("npc_id") != visits[entry.visit_id].npc_id or not _payment(entry.get("payment")):
			return "账目或接待引用无效"
		if not entry.get("category") in ["divination", "product", "gift"] or not _text(entry.get("reference_id")):
			return "账目分类或引用无效"
		if entry.category == "divination":
			var service: Dictionary = services.get(entry.reference_id, {})
			if service.get("status") != "paid" or service.visit_id != entry.visit_id or service.payment != entry.payment:
				return "问卜报酬与已付报价不一致"
		entries[entry.entry_id] = true
	for service: Dictionary in services.values():
		if service.status == "paid" and not entries.has("ledger_" + service.service_id):
			return "已付款的术式缺少账目"
	var effect_ids: Dictionary = {}
	for effect in work.effects:
		if not effect is Dictionary or not _text(effect.get("effect_id")) or effect_ids.has(effect.effect_id) or not events.has(effect.get("event_id")) or not effect.get("recipient") in ["A", "C"]:
			return "事件影响或接收方无效"
		var case: Dictionary = events[effect.event_id]
		if effect.get("visit_id") != case.visit_id or effect.get("npc_id") != case.npc_id or case.prediction.is_empty() or effect.get("prediction_id") != case.prediction.prediction_id or case.event.feedback.report.is_empty():
			return "事件影响缺少预测或反馈"
		effect_ids[effect.effect_id] = true
	return ""

static func wallet(value: Variant) -> bool:
	if not value is Dictionary or not value.get("items") is Dictionary:
		return false
	for item_id: String in value.items:
		if not _text(item_id) or not Catalog._integer(value.items[item_id], 0, MAX_INT):
			return false
	return true

static func _case_records(case: Dictionary, visit: Dictionary, data: Dictionary, clock: int) -> bool:
	for key in ["world_facts", "services", "event", "prediction", "purchase", "item_use"]:
		if not case.get(key) is Dictionary:
			return false
	for key in ["conversation", "branches", "hypotheses", "advice"]:
		if not case.get(key) is Array:
			return false
		for record in case[key]:
			if key == "branches":
				if not _text(record):
					return false
			elif not record is Dictionary:
				return false
	if not case.get("open_service_id") is String or not case.get("profile_id") is String or (not case.profile_id.is_empty() and not data.past_profiles.has(case.profile_id)):
		return false
	if case.has("chart") and not Catalog.valid_chart(case.chart):
		return false
	if case.has("public_npc") and (not case.public_npc is Dictionary or not _text(case.public_npc.get("name")) or not case.public_npc.get("role") is String):
		return false
	for fact in case.world_facts.values():
		if not fact is Dictionary or not _text(fact.get("text")) or not data.clues.has(fact.get("requires_clue")):
			return false
	for entry: Dictionary in case.conversation:
		if not Catalog._integer(entry.get("statement_index"), 1, visit.dialogue.size() - 1) or not entry.get("clue_ids") is Array or not entry.get("channel") in ["button", "free_text"] or not _text(entry.get("intent")):
			return false
	for note: Dictionary in case.hypotheses:
		if not _text(note.get("text"), 500) or not note.get("clue_ids") is Array:
			return false
	var open_id: String = ""
	for id: String in case.services:
		var service: Variant = case.services[id]
		if not _service(service, visit, id, data, clock):
			return false
		if service.status == "quoted":
			if not open_id.is_empty() or visit.phase == "ended":
				return false
			open_id = id
	if open_id != case.open_service_id:
		return false
	if visit.reading.has("cards") and not case.services.values().any(func(service: Dictionary) -> bool:
		return service.status == "paid" and service.method_id == "tarot" and service.result.get("medium", {}).get("cards") == visit.reading.cards
	):
		return false
	var definition: Dictionary = data.cases[case.case_id].get("event", {})
	if (not case.event.is_empty() and definition.is_empty()) or not _event(case.event, case.prediction, visit, clock, definition):
		return false
	for advice: Dictionary in case.advice:
		if case.event.is_empty() or advice.get("event_id") != case.event.event_id or not definition.advice.has(advice.get("advice_key")) or not advice.get("accepted") is bool or not _text(advice.get("text")) or not _text(advice.get("reply")) or not _text(advice.get("advice_id")):
			return false
	if not case.purchase.is_empty() and (not _text(case.purchase.get("transaction_id")) or not _text(case.purchase.get("item_id"))):
		return false
	if not case.item_use.is_empty() and (case.event.is_empty() or case.item_use.get("event_id") != case.event.event_id or not _text(case.item_use.get("transaction_id")) or not _text(case.item_use.get("item_id")) or not _text(case.item_use.get("item_use_id")) or not Catalog._integer(case.item_use.get("at"), int(visit.started_at), int(case.event.due_at) - 1)):
		return false
	if case.has("demand"):
		var demand: Variant = case.demand
		if case.event.is_empty() or not demand is Dictionary or demand.get("event_id") != case.event.event_id or demand.get("visit_id") != visit.visit_id or demand.get("effect_key") != definition.item_effect.key or not _text(demand.get("demand_id")) or not _text(demand.get("text")):
			return false
	return true

static func _service(service: Variant, visit: Dictionary, id: String, data: Dictionary, clock: int) -> bool:
	if not service is Dictionary or not _text(id) or service.get("service_id") != id or service.get("visit_id") != visit.visit_id or service.get("npc_id") != visit.npc_id:
		return false
	var method: Dictionary = data.methods.get(service.get("method_id"), {})
	if method.is_empty() or not method.options.has(service.get("option_id")) or not Catalog.valid_parameter(service.method_id, service.option_id, service.get("parameter")):
		return false
	if not _payment(service.get("payment")) or not service.get("status") in ["quoted", "paid", "cancelled"] or not service.get("result") is Dictionary or not _text(service.get("method_title")) or not _text(service.get("option_label")):
		return false
	if not Catalog._integer(service.get("quoted_at"), int(visit.started_at), clock) or not Catalog._integer(service.get("energy"), 0, MAX_INT) or not Catalog._integer(service.get("minutes"), 0, 1439):
		return false
	if service.status != "paid":
		return service.result.is_empty() and service.get("paid_at") == -1
	return Catalog._integer(service.get("paid_at"), int(service.quoted_at), clock) and _text(service.result.get("clue_id")) and _text(service.result.get("title")) and _text(service.result.get("text")) and _text(service.result.get("lead")) and OracleSaved.valid(service.result, service, data)

static func _event(event: Dictionary, prediction: Dictionary, visit: Dictionary, clock: int, definition: Dictionary) -> bool:
	if event.is_empty():
		return prediction.is_empty()
	if not _text(event.get("event_id")) or not _text(event.get("subject_id")) or not _text(event.get("target_name")) or not Catalog._integer(event.get("due_at"), int(visit.started_at) + 1, MAX_INT):
		return false
	var feedback: Variant = event.get("feedback")
	if not feedback is Dictionary or not feedback.get("mode") in ["pending", "delayed", "never"] or not feedback.get("disclosure") is Dictionary or not feedback.get("report") is Dictionary or not Catalog._integer(feedback.get("available_at"), -1, MAX_INT):
		return false
	if not event.get("evaluation") in ["pending", "aligned", "deviated", "insufficient", "condition_not_met"] or not event.get("occurrence") in ["pending", "occurred", "did_not_occur"]:
		return false
	if event.occurrence == "pending" and (event.due_at <= clock or feedback.mode != "pending" or not feedback.report.is_empty()):
		return false
	if event.occurrence != "pending":
		if int(event.due_at) > clock or event.get("resolved_at") != event.due_at or not definition.outcomes.has(event.get("outcome_id")) or not event.get("outcome") in ["met", "missed"] or not event.get("evidence") in ["sufficient", "insufficient"] or not _text(event.get("actual_action")) or feedback.mode == "pending":
			return false
	if not feedback.report.is_empty() and (feedback.mode != "delayed" or feedback.report.get("event_id") != event.event_id or not _text(feedback.report.get("text")) or not Catalog._integer(feedback.report.get("at"), int(feedback.available_at), clock)):
		return false
	if prediction.is_empty():
		return true
	if not _text(prediction.get("prediction_id")) or prediction.get("event_id") != event.event_id or prediction.get("subject_id") != event.subject_id or not _text(prediction.get("text"), 500) or not Events.CONDITIONS.has(prediction.get("condition")) or not prediction.get("expected") in ["met", "missed"]:
		return false
	return Catalog._integer(prediction.get("at"), int(visit.started_at), int(event.due_at) - 1) and Catalog._integer(prediction.get("window_start"), int(prediction.at), int(event.due_at) + 1440) and Catalog._integer(prediction.get("window_end"), int(prediction.window_start), int(event.due_at) + 1440) and prediction.get("clue_ids") is Array

static func _past(memory: Variant, npc_id: String, data: Dictionary, services: Dictionary) -> bool:
	if not memory is Dictionary or not data.past_profiles.has(memory.get("profile_id")) or not _text(memory.get("identity_id")) or not _text(memory.get("other_identity_id")) or not _text(memory.get("relation")) or not memory.get("fragments") is Dictionary:
		return false
	var profile: Dictionary = data.past_profiles[memory.profile_id]
	for id: String in memory.fragments:
		var fragment: Variant = memory.fragments[id]
		if not fragment is Dictionary or not _text(fragment.get("fragment_id")) or not _text(fragment.get("text")):
			return false
		var service: Dictionary = services.get(fragment.get("service_id"), {})
		if service.get("status") != "paid" or service.method_id != "past" or service.npc_id != npc_id or service.option_id != id or service.visit_id != fragment.get("visit_id"):
			return false
	if not memory.fragments.has("vision"):
		return false
	for key in ["interpretations", "confirmed_links", "stories"]:
		if not memory.get(key) is Array:
			return false
		for record in memory[key]:
			if not record is Dictionary or not profile.links.has(record.get("link_id")):
				return false
			if key == "interpretations" and (not record.get("status") in ["unverified", "confirmed", "disproven"] or not _text(record.get("interpretation_id"))):
				return false
	return true

static func _payment(value: Variant) -> bool:
	return value is Dictionary and value.get("kind") in ["coins", "item"] and Catalog._integer(value.get("amount"), 0, MAX_INT) and (value.kind == "coins" or (_text(value.get("item_id")) and value.amount > 0))

static func _text(value: Variant, limit: int = 10000) -> bool:
	return value is String and not value.is_empty() and value.length() <= limit

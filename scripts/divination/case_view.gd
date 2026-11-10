extends RefCounted
## Explicit projection for the player. Never return raw world, event or profile dictionaries.

const Catalog = preload("res://scripts/divination/catalog.gd")
const Events = preload("res://scripts/divination/event_rules.gd")
const OracleClues = preload("res://scripts/divination/oracle_clues.gd")
const Almanac = preload("res://scripts/divination/almanac.gd")

static func project(session, state: Dictionary, visit: Dictionary) -> Dictionary:
	var case: Dictionary = state.divination.cases[visit.visit_id]
	var clock := int(state.clock_minutes)
	var data: Dictionary = session.data
	var guest: Dictionary = session.guest_view(visit.npc_id, case.case_id, case.get("public_npc", {}))
	var active: bool = visit.visit_id == state.active_visit_id
	var view: Dictionary = {
		"case_id": case.case_id, "visit_id": visit.visit_id, "guest": guest, "active": active,
		"opening_statement": visit.dialogue.front().text if not visit.dialogue.is_empty() else "",
		"topics": [], "clues": [], "facts": [], "statements": [], "methods": [], "services": [], "quote": {},
		"hypotheses": case.hypotheses, "prediction": case.prediction, "advice": case.advice,
		"event": _event(case, clock, data), "past": _past(state, case, data),
		"purchase": case.purchase, "item_use": case.item_use, "demand": case.get("demand", {}), "feedback_options": [], "ledger": []
	}
	for clue_id: String in visit.clue_ids:
		var clue: Dictionary = data.clues[clue_id]
		view.clues.append({"clue_id": clue_id, "title": clue.title, "text": clue.text})
	for fact_id: String in case.world_facts:
		var fact: Dictionary = case.world_facts[fact_id]
		if fact.requires_clue in visit.clue_ids:
			view.facts.append({"fact_id": fact_id, "text": fact.text, "clue_id": fact.requires_clue})
	for entry: Dictionary in case.conversation:
		var statement := entry.duplicate(true)
		statement["text"] = visit.dialogue[int(entry.statement_index)].text
		view.statements.append(statement)
	for service: Dictionary in case.services.values():
		if service.status == "paid":
			view.services.append(service)
		elif service.status == "quoted":
			var preview := service.duplicate()
			preview.option_label = data.methods[service.method_id].options[service.option_id].label
			view.quote = preview
	view.services.sort_custom(_earlier_service)
	var related: Array = view.services.duplicate()
	for prior: Dictionary in state.visits:
		if prior.npc_id != visit.npc_id or int(prior.started_at) >= int(visit.started_at):
			continue
		var previous: Dictionary = state.divination.cases[prior.visit_id]
		if previous.case_id == case.case_id:
			for service: Dictionary in previous.services.values():
				if service.status == "paid":
					related.append(service)
	related.sort_custom(_earlier_service)
	view["oracle_links"] = OracleClues.compare(related)
	for entry: Dictionary in state.divination.ledger:
		if entry.visit_id == visit.visit_id:
			view.ledger.append(entry)
	if active:
		_active_details(session, state, visit, case, view)
	return view.duplicate(true)

static func _earlier_service(a: Dictionary, b: Dictionary) -> bool:
	return a.paid_at < b.paid_at if a.paid_at != b.paid_at else a.service_id < b.service_id

static func _active_details(session, state: Dictionary, visit: Dictionary, case: Dictionary, view: Dictionary) -> void:
	var data: Dictionary = session.data
	var clock := int(state.clock_minutes)
	var allowed: Dictionary = session.talks(visit, case, clock)
	for id: String in data.cases[case.case_id].topic_ids:
		var topic: Dictionary = data.topic_index[id]
		view.topics.append({"topic_id": id, "label": topic.label, "enabled": allowed.has(id)})
	var chart: Dictionary = Catalog.chart_for(case, data)
	if "birth_details" in visit.clue_ids and not chart.is_empty():
		var birth := Almanac.from_birth(chart)
		var description: String = birth.get("text", chart.birth)
		if not birth.is_empty():
			var offset := int(birth.offset)
			var zone := "UTC%s%02d:%02d" % ["+" if offset >= 0 else "-", absi(offset) / 60, absi(offset) % 60]
			description += " · " + zone
		var place: String = str(chart.get("birthplace", ""))
		if not place.is_empty():
			description += " · " + place
		view["birth"] = {"text": description}
	for id: String in data.cases[case.case_id].method_ids:
		var method: Dictionary = data.methods[id]
		var options: Array = []
		for key: String in method.options:
			var blocked: Dictionary = session._method_block(state, visit, case, id, key)
			options.append({"option_id": key, "label": method.options[key].label, "blocked": blocked.get("message", "")})
		view.methods.append({
			"method_id": id, "title": method.title, "prompt": method.prompt, "learned": id in state.divination.skills,
			"options": options, "cost": Catalog.service_cost(id, method, session.base.rules)
		})
	for prior: Dictionary in state.divination.cases.values():
		if prior.npc_id == visit.npc_id and prior.visit_id != visit.visit_id and not prior.event.is_empty() and Events.can_report(prior.event, clock):
			view.feedback_options.append({"event_id": prior.event.event_id, "title": data.cases[prior.case_id].title})
	var economy: Dictionary = data.economy
	var wallet: Dictionary = state.npcs[visit.npc_id]
	view["shop"] = {
		"product_name": economy.product_name, "price": int(economy.product_price),
		"stock": int(state.player.items.get(economy.product_id, 0)),
		"coins": wallet.coins, "payment_item_name": economy.payment_item_name,
		"payment_items": wallet.items.get(economy.payment_item_id, 0)
	}

static func _event(case: Dictionary, clock: int, data: Dictionary) -> Dictionary:
	var event: Dictionary = case.event
	if event.is_empty():
		return {}
	var status := "pending" if clock < int(event.due_at) else "awaiting_feedback"
	if not event.feedback.report.is_empty():
		status = "reported"
	var result: Dictionary = {
		"event_id": event.event_id, "subject_id": event.subject_id, "target_name": event.target_name,
		"due_at": event.due_at, "status": status, "report": event.feedback.report,
		"conditions": Events.CONDITIONS, "advice_options": []
	}
	if status == "pending":
		for key: String in data.cases[case.case_id].event.advice:
			result.advice_options.append({"advice_key": key, "text": data.cases[case.case_id].event.advice[key].text})
	return result

static func _past(state: Dictionary, case: Dictionary, data: Dictionary) -> Dictionary:
	if case.profile_id.is_empty():
		return {}
	var memory: Dictionary = state.divination.past.get(case.npc_id, {})
	if memory.is_empty():
		return {}
	var options: Array = []
	for id: String in data.past_profiles[memory.profile_id].links:
		options.append({"link_id": id, "label": data.past_profiles[memory.profile_id].links[id].label})
	return {
		"fragments": memory.fragments, "interpretations": memory.interpretations,
		"confirmed_links": memory.confirmed_links, "stories": memory.stories, "options": options
	}

static func study(session, state: Dictionary) -> Array:
	if state.is_empty():
		return []
	var rows: Array = []
	for id: String in session.data.methods:
		var method: Dictionary = session.data.methods[id]
		var learned: bool = id in state.divination.skills
		var cost: Dictionary = method.get("learning", {})
		var prerequisite: String = cost.get("requires", "")
		var ready: bool = prerequisite in state.divination.skills
		rows.append({
			"method_id": id, "title": method.title, "learned": learned, "learning": cost,
			"prerequisite": "" if prerequisite.is_empty() else session.data.methods[prerequisite].title,
			"can_learn": not learned and ready and state.active_visit_id.is_empty()
		})
	return rows.duplicate(true)

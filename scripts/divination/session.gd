extends RefCounted
## Case rules. GameState passes a candidate, advances its clock and commits it.

const Catalog = preload("res://scripts/divination/catalog.gd")
const Economy = preload("res://scripts/divination/demo_economy.gd")
const Events = preload("res://scripts/divination/event_rules.gd")
const ACTIONS := [
	"quote_service", "settle_service", "cancel_service", "learn_method", "note_hypothesis",
	"record_prediction", "give_advice", "buy_case_item", "use_case_item", "receive_feedback",
	"interpret_past", "verify_past"
]

var data: Dictionary
var base: Dictionary

func _init(catalog: Dictionary, content: Dictionary) -> void:
	data = catalog
	base = content

func initialize(state: Dictionary) -> void:
	state.schema_version = 2
	state["divination"] = {"skills": ["tarot"], "cases": {}, "past": {}, "ledger": [], "effects": []}
	Economy.initialize(state, data, base.npc.npc_id)
	for visit: Dictionary in state.visits:
		add_case(state, visit, "invitation", false)

## A can supply a new visitor ID with public details, a profile key and a game chart.
## The caller owns admission, the wallet and the visit. This function binds B records.
func add_case(state: Dictionary, visit: Dictionary, case_id: String, schedule_event: bool = true, context: Dictionary = {}) -> bool:
	var template: Dictionary = data.cases.get(case_id, {})
	if template.is_empty() or not state.npcs.has(visit.npc_id) or state.divination.cases.has(visit.visit_id):
		return false
	if not context.get("profile_id", "") is String or not context.get("subject_id", "") is String or not context.get("target_name", "") is String or not context.get("public_npc", {}) is Dictionary:
		return false
	if context.has("chart") and not Catalog.valid_chart(context.chart):
		return false
	var profile_id: String = context.get("profile_id", "")
	if profile_id.is_empty() and case_id == "archive":
		profile_id = state.divination.past.get(visit.npc_id, {}).get("profile_id", data.guests.get(visit.npc_id, {}).get("profile_id", ""))
	var memory: Dictionary = state.divination.past.get(visit.npc_id, {})
	if not profile_id.is_empty() and (not data.past_profiles.has(profile_id) or memory.get("profile_id", profile_id) != profile_id):
		return false
	var event: Dictionary = {}
	if schedule_event and template.has("event"):
		var already_scheduled := false
		for prior: Dictionary in state.divination.cases.values():
			if prior.npc_id == visit.npc_id and prior.case_id == case_id and not prior.event.is_empty():
				already_scheduled = true
				break
		if not already_scheduled:
			event = Events.create(visit, template.event)
			event.subject_id = context.get("subject_id", event.subject_id)
			event.target_name = context.get("target_name", event.target_name)
	var record: Dictionary = {
		"case_id": case_id, "visit_id": visit.visit_id, "npc_id": visit.npc_id, "profile_id": profile_id,
		"world_facts": template.world_facts.duplicate(true), "event": event, "prediction": {},
		"services": {}, "open_service_id": "", "conversation": [], "branches": [],
		"hypotheses": [], "advice": [], "purchase": {}, "item_use": {}
	}
	if context.has("chart"):
		record["chart"] = context.chart.duplicate(true)
	if context.has("public_npc"):
		record["public_npc"] = guest_view(visit.npc_id, case_id, context.public_npc)
	state.divination.cases[visit.visit_id] = record
	return true

func guest_options(state: Dictionary) -> Array:
	var guests: Array = [
		{"npc_id": base.npc.npc_id, "case_id": "invitation", "label": base.npc.name + " · 邀请案"},
		{"npc_id": base.npc.npc_id, "case_id": "archive", "label": base.npc.name + " · 旧物案"}
	]
	for npc_id: String in state.get("npcs", {}):
		var guest: Dictionary = data.guests.get(npc_id, {})
		if guest.has("fixture"):
			var label: String = "普通样例" if guest.fixture == "ordinary" else "作品参考样例"
			guests.append({"npc_id": npc_id, "case_id": "archive", "label": "%s · %s" % [guest.name, label]})
	return guests

func guest_view(npc_id: String, case_id: String, supplied: Dictionary = {}) -> Dictionary:
	var guest: Dictionary = supplied
	if guest.is_empty():
		guest = base.npc if npc_id == base.npc.npc_id else data.guests.get(npc_id, {})
	return {"npc_id": npc_id, "name": guest.get("name", "来客"), "role": guest.get("role", ""), "case_title": data.cases[case_id].title}

func opening(npc_id: String, case_id: String, has_visited: bool) -> String:
	if npc_id != base.npc.npc_id:
		return data.guests[npc_id].opening if not has_visited else "我又带来了那件旧物。上次看到的内容，我都还记得。"
	if case_id == "archive":
		return "修书时掉出一张旧借条。鱼纹看着很熟悉，我想弄清它是谁留下的。"
	if has_visited:
		return "我又来了。上次的话我记在修复笔记里，也想看看当时留下的记录。"
	return base.npc.opening + " 也许只是群发邀请，我不敢肯定。"

func talks(visit: Dictionary, case: Dictionary, clock: int) -> Dictionary:
	var allowed: Dictionary = {"clarify": {"clue_ids": [], "branch_id": ""}}
	for id: String in data.cases[case.case_id].topic_ids:
		var topic: Dictionary = data.topic_index[id]
		if topic.has("requires_clue") and not topic.requires_clue in visit.clue_ids:
			continue
		var branch: String = topic.get("branch_id", "") if _event_open(case, clock) else ""
		allowed[id] = {"clue_ids": topic.clue_ids.duplicate(), "branch_id": branch}
	return allowed

func record_talk(state: Dictionary, visit: Dictionary, action: Dictionary, response: Dictionary, new_clues: Array) -> void:
	var case: Dictionary = state.divination.cases[visit.visit_id]
	var branch: String = response.get("branch_id", "")
	if not branch.is_empty() and not branch in case.branches:
		case.branches.append(branch)
	case.conversation.append({
		"action_id": action.action_id, "at": int(state.clock_minutes),
		"channel": "button" if action.has("topic_id") else "free_text",
		"intent": response.intent, "clue_ids": new_clues, "branch_id": branch,
		"statement_index": visit.dialogue.size() - 1
	})

func handle(state: Dictionary, visit: Dictionary, action: Dictionary) -> Dictionary:
	if action.type == "learn_method":
		return _learn(state, action)
	if visit.is_empty():
		return _fail("NO_VISIT", "请先接待顾客。")
	var case: Dictionary = state.divination.cases[visit.visit_id]
	match action.type:
		"quote_service":
			return _quote(state, visit, case, action)
		"settle_service":
			return _settle(state, visit, case, action.get("service_id"))
		"cancel_service":
			if case.open_service_id.is_empty() or action.get("service_id") != case.open_service_id:
				return _fail("NO_QUOTE", "这份报价已失效。")
			cancel_open_service(case)
			return _ok("报价已撤回。")
		"reading":
			var quote := _quote(state, visit, case, {
				"action_id": action.action_id, "method_id": "tarot", "option_id": "situation", "payment": "coins"
			})
			if not quote.success:
				return quote
			return _settle(state, visit, case, case.open_service_id)
		"note_hypothesis":
			return _hypothesis(state, visit, case, action)
		"record_prediction":
			return _prediction(state, visit, case, action)
		"give_advice":
			return _advice(state, visit, case, action)
		"buy_case_item":
			return _purchase(state, visit, case, action)
		"use_case_item":
			return _use_item(state, visit, case, action)
		"receive_feedback":
			return _feedback(state, visit, action.get("event_id"))
		"interpret_past":
			return _interpret(state, visit, case, action)
		"verify_past":
			return _verify(state, visit, action)
	return _fail("UNKNOWN_ACTION", "不支持此问卜动作。")

func cancel_open_service(case: Dictionary) -> void:
	var service_id: String = case.open_service_id
	if not service_id.is_empty():
		case.services[service_id].status = "cancelled"
		case.open_service_id = ""

func paid_service(state: Dictionary, visit: Dictionary, service_id: Variant) -> Dictionary:
	if visit.is_empty() or not service_id is String:
		return {}
	var service: Dictionary = state.divination.cases[visit.visit_id].services.get(service_id, {})
	return service if service.get("status") == "paid" else {}

func _quote(state: Dictionary, visit: Dictionary, case: Dictionary, action: Dictionary) -> Dictionary:
	var method_id: Variant = action.get("method_id")
	var option_id: Variant = action.get("option_id")
	var kind: Variant = action.get("payment")
	var parameter: Variant = action.get("parameter", 0)
	if not method_id is String or not option_id is String or not kind in ["coins", "item"]:
		return _fail("INVALID_ACTION", "请选择术式、操作和报酬。")
	if not case.open_service_id.is_empty():
		return _fail("OPEN_QUOTE", "请先结算或撤回已有报价。")
	var blocked := _method_block(state, visit, case, method_id, option_id)
	if not blocked.is_empty():
		return blocked
	if not Catalog.valid_parameter(method_id, option_id, parameter):
		return _fail("INVALID_ACTION", "操作参数超出范围。")
	var costs := Catalog.service_cost(method_id, data.methods[method_id], base.rules)
	var payment: Dictionary = {"kind": kind, "amount": int(costs.coins)}
	if kind == "item":
		payment.merge({"item_id": data.economy.payment_item_id, "item_name": data.economy.payment_item_name, "amount": 2 if int(costs.coins) >= 22 else 1}, true)
	var id := _id("service", action)
	var service: Dictionary = {
		"service_id": id, "visit_id": visit.visit_id, "npc_id": visit.npc_id,
		"method_id": method_id, "method_title": data.methods[method_id].title,
		"option_id": option_id, "option_label": data.methods[method_id].options[option_id].label, "parameter": int(parameter),
		"payment": payment, "energy": int(costs.energy), "minutes": int(costs.minutes),
		"quoted_at": int(state.clock_minutes), "paid_at": -1, "status": "quoted", "result": {}
	}
	case.services[id] = service
	case.open_service_id = id
	return _ok("报价已确认，收取报酬后可揭示结果。", {"service_id": id, "visit_id": visit.visit_id})

func _settle(state: Dictionary, visit: Dictionary, case: Dictionary, id: Variant) -> Dictionary:
	if not id is String or id.is_empty() or id != case.open_service_id:
		return _fail("NO_QUOTE", "请先确认本次服务的报价。")
	var service: Dictionary = case.services[id]
	var blocked := _method_block(state, visit, case, service.method_id, service.option_id, int(service.quoted_at))
	if not blocked.is_empty():
		return blocked
	if not Economy.can_pay(state.npcs[visit.npc_id], service.payment):
		var code := "NPC_FUNDS_LOW" if service.payment.kind == "coins" else "NPC_ITEMS_LOW"
		return _fail(code, "顾客的报酬不足，结果仍未揭示。")
	blocked = _resource_block(state, service)
	if not blocked.is_empty():
		return blocked
	var result := Catalog.read_result(service, case, data)
	if result.is_empty():
		return _fail("ORACLE_INPUT_UNAVAILABLE", "当前资料无法生成结果。报价仍可撤回，未收取报酬。")
	Economy.transfer(state, visit, service.payment, "divination", id, true)
	state.player.energy -= int(service.energy)
	service.status = "paid"
	service.option_label = data.methods[service.method_id].options[service.option_id].label
	service.paid_at = int(state.clock_minutes) + int(service.minutes)
	service.result = result
	case.open_service_id = ""
	var output: Dictionary = {"service_id": id, "visit_id": visit.visit_id, "service_result": result.duplicate(true)}
	if service.method_id == "tarot" and visit.reading.is_empty():
		# Preserve the v1 public reading and legacy replay for existing callers.
		visit.reading = {
			"reading_id": "reading_" + String(visit.visit_id).trim_prefix("visit_"),
			"card_id": result.card_id, "title": result.title, "text": result.text, "cards": result.medium.cards.duplicate(true),
			"fee": int(service.payment.amount) if service.payment.kind == "coins" else 0,
			"energy_cost": int(service.energy), "minutes": int(service.minutes)
		}
		visit.phase = "reading_done"
		output["reading"] = visit.reading.duplicate(true)
	if service.method_id == "past":
		_reveal_past(state, visit, case, service)
	return _ok("报酬与术式结果已保存。", output, int(service.minutes))

func _method_block(state: Dictionary, visit: Dictionary, case: Dictionary, method_id: String, option_id: String, quoted_at: int = -1) -> Dictionary:
	if not method_id in data.cases[case.case_id].method_ids or not data.methods[method_id].options.has(option_id):
		return _fail("METHOD_NOT_APPLICABLE", "这项操作不适用于当前案例。")
	if not method_id in state.divination.skills:
		return _fail("METHOD_UNLEARNED", "请在前台研习这项术式。")
	if data.methods[method_id].get("needs_birth", false):
		if not "birth_details" in visit.clue_ids:
			return _fail("NEEDS_BIRTH", "请先向来客征求出生资料。")
		if not Catalog.birth_available(method_id, Catalog.chart_for(case, data)):
			var message := "需要完整的出生日期、时刻、时区和地点。" if method_id == "astrology" else "需要完整的出生日期、时刻和时区。"
			return _fail("INCOMPLETE_BIRTH", message)
	var clock := int(state.clock_minutes) if quoted_at < 0 else quoted_at
	if not Catalog.calendar_available(method_id, option_id, clock, case.event):
		return _fail("ORACLE_CALENDAR_RANGE", "所选日期超出本店的历表范围。")
	if method_id == "past":
		var memory: Dictionary = state.divination.past.get(visit.npc_id, {})
		var fragments: Dictionary = memory.get("fragments", {})
		if not data.past_profiles.has(case.profile_id) or memory.get("profile_id", case.profile_id) != case.profile_id or not "archive_stub" in visit.clue_ids:
			return _fail("PAST_NOT_APPLICABLE", "本次需要一件可查证的旧物，先聊聊来客带来的东西。")
		if fragments.has(option_id):
			return _fail("FRAGMENT_SEEN", "已经揭示这段片段，可在手记重读。")
		if option_id == "evidence" and (not fragments.has("vision") or memory.interpretations.is_empty()):
			return _fail("NEEDS_INTERPRETATION", "请先初见片段，并在手记留下一个待验证解释。")
	return {}

func _learn(state: Dictionary, action: Dictionary) -> Dictionary:
	var id: Variant = action.get("method_id")
	if not id is String or not data.methods.has(id):
		return _fail("INVALID_ACTION", "请选择要研习的术式。")
	if id in state.divination.skills:
		return _fail("METHOD_ALREADY_LEARNED", "已学会这项术式。")
	if not state.active_visit_id.is_empty():
		return _fail("ACTIVE_VISIT", "请先结束接待再研习。")
	var learning: Dictionary = data.methods[id].learning
	if not learning.requires in state.divination.skills:
		return _fail("SKILL_PREREQUISITE", "请先学会" + data.methods[learning.requires].title + "。")
	if int(state.player.coins) < int(learning.coins):
		return _fail("PLAYER_FUNDS_LOW", "金币不足，本次未研习。")
	var blocked := _resource_block(state, learning)
	if not blocked.is_empty():
		return blocked
	state.player.coins -= int(learning.coins)
	state.player.energy -= int(learning.energy)
	state.divination.skills.append(id)
	return _ok("已学会" + data.methods[id].title + "。", {"method_id": id}, int(learning.minutes))

func _resource_block(state: Dictionary, cost: Dictionary) -> Dictionary:
	if int(state.player.energy) < int(cost.energy):
		return _fail("ENERGY_LOW", "精力不足，请先休息。")
	if int(state.clock_minutes) % 1440 + int(cost.minutes) > int(base.rules.closing_minute):
		return _fail("NOT_ENOUGH_TIME", "今天剩余的营业时间不足。")
	return {}

func _hypothesis(state: Dictionary, visit: Dictionary, case: Dictionary, action: Dictionary) -> Dictionary:
	var text: Variant = action.get("text")
	if not _valid_text(text):
		return _fail("INVALID_INPUT", "请写下 1 至 500 字的假设。")
	var id := _id("hypothesis", action)
	case.hypotheses.append({"hypothesis_id": id, "text": text, "at": int(state.clock_minutes), "clue_ids": _known_clues(visit, case)})
	return _ok("已保存为待验证的个人假设。", {"hypothesis_id": id, "visit_id": visit.visit_id})

func _prediction(state: Dictionary, visit: Dictionary, case: Dictionary, action: Dictionary) -> Dictionary:
	var event: Dictionary = case.event
	if not _event_open(case, int(state.clock_minutes)):
		return _fail("NO_PENDING_EVENT", "本案没有可以继续提交预测的待发生事件。")
	if not case.prediction.is_empty():
		return _fail("PREDICTION_EXISTS", "本案已经交给顾客一条正式预测。")
	if visit.reading.is_empty() and not case.services.values().any(func(service: Dictionary) -> bool: return service.status == "paid"):
		return _fail("NEEDS_PAID_SERVICE", "请先完成正式问卜，再把预测交给来客。")
	var start: Variant = action.get("window_start")
	var end: Variant = action.get("window_end")
	if not _valid_text(action.get("text")) or action.get("subject_id") != event.subject_id or not action.get("expected") in ["met", "missed"] or not Events.CONDITIONS.has(action.get("condition")):
		return _fail("INVALID_PREDICTION", "请填写预测原话，并选择本案的对象、结果和条件。")
	if not Catalog._integer(start, int(state.clock_minutes), int(event.due_at) + 1440) or not Catalog._integer(end, int(start), int(event.due_at) + 1440):
		return _fail("INVALID_PREDICTION", "预测时段应从当前游戏时间之后开始，结束不晚于约见后一天。")
	var id := _id("prediction", action)
	case.prediction = {
		"prediction_id": id, "event_id": event.event_id, "subject_id": event.subject_id,
		"text": action.text, "condition": action.condition, "expected": action.expected,
		"at": int(state.clock_minutes), "window_start": int(start), "window_end": int(end),
		"clue_ids": _known_clues(visit, case)
	}
	return _ok("对外预测与原话已交给来客。", {"prediction_id": id, "visit_id": visit.visit_id})

func _known_clues(visit: Dictionary, case: Dictionary) -> Array:
	var clues: Array = visit.clue_ids.duplicate()
	for service: Dictionary in case.services.values():
		if service.status == "paid" and not service.result.clue_id in clues:
			clues.append(service.result.clue_id)
	return clues

func _advice(state: Dictionary, visit: Dictionary, case: Dictionary, action: Dictionary) -> Dictionary:
	if not _event_open(case, int(state.clock_minutes)):
		return _fail("NO_PENDING_EVENT", "本案没有还可改变行动的事件。")
	var choices: Dictionary = data.cases[case.case_id].event.advice
	var key: Variant = action.get("advice_key")
	if not key is String or not choices.has(key):
		return _fail("INVALID_ADVICE", "请选择此案支持的建议。")
	var choice: Dictionary = choices[key]
	var accepted: bool = not choice.has("requires_clue") or choice.requires_clue in visit.clue_ids
	var id := _id("advice", action)
	case.advice.append({
		"advice_id": id, "event_id": case.event.event_id, "advice_key": key,
		"text": choice.text, "accepted": accepted, "at": int(state.clock_minutes),
		"reply": "我愿意按这个计划试试。" if accepted else "我还没弄清前因后果，暂时不愿意这样做。"
	})
	if accepted and key == "attend" and not case.has("demand"):
		var effect: Dictionary = data.cases[case.case_id].event.item_effect
		case["demand"] = {
			"demand_id": "demand_" + String(case.event.event_id).trim_prefix("event_"),
			"event_id": case.event.event_id, "case_id": case.case_id, "visit_id": visit.visit_id,
			"npc_id": visit.npc_id, "advice_id": id, "effect_key": effect.key, "text": effect.need,
			"deadline": case.event.due_at
		}
	return _ok(case.advice.back().reply, {"advice_id": id, "visit_id": visit.visit_id, "accepted": accepted})

func _purchase(state: Dictionary, visit: Dictionary, case: Dictionary, action: Dictionary) -> Dictionary:
	if not case.purchase.is_empty():
		return _fail("ALREADY_PURCHASED", "本次接待已记录这笔交易。")
	var economy: Dictionary = data.economy
	if int(state.player.items.get(economy.product_id, 0)) < 1:
		return _fail("OUT_OF_STOCK", "店内暂时没有这件商品。")
	var payment: Dictionary = {"kind": "coins", "amount": int(economy.product_price)}
	if not Economy.can_pay(state.npcs[visit.npc_id], payment):
		return _fail("NPC_FUNDS_LOW", "来客金币不足，未成交。")
	var id := _id("purchase", action)
	var entry := Economy.transfer(state, visit, payment, "product", id, true)
	entry.merge({"item_id": economy.product_id, "item_name": economy.product_name, "quantity": 1})
	Economy.move_item(state.player, state.npcs[visit.npc_id], economy.product_id, 1)
	case.purchase = {"transaction_id": id, "item_id": economy.product_id, "at": int(state.clock_minutes)}
	return _ok("商品交易已单独记账。", {"transaction_id": id, "visit_id": visit.visit_id})

func _use_item(state: Dictionary, visit: Dictionary, case: Dictionary, action: Dictionary) -> Dictionary:
	if case.event.is_empty() or case.purchase.is_empty():
		return _fail("ITEM_USE_BLOCKED", "须在事件发生前使用本次购得的商品。")
	var guest: Dictionary = state.npcs[visit.npc_id]
	var item_id: String = case.purchase.item_id
	if int(guest.items.get(item_id, 0)) < 1:
		return _fail("NPC_ITEMS_LOW", "顾客没有这件商品可用。")
	var id := _id("item_use", action)
	var linked := link_item_use(state, visit, {
		"item_use_id": id, "event_id": case.event.event_id, "item_id": item_id,
		"transaction_id": case.purchase.transaction_id, "effect_key": data.cases[case.case_id].event.item_effect.key
	})
	if not linked:
		return _fail("ITEM_USE_BLOCKED", "须在事件发生前使用本次购得的商品。")
	guest.items[item_id] -= 1
	return _ok("已记录用香。照晚愿意在找不到旧入口时多停一会，向工作人员问路。", {"item_use_id": id, "visit_id": visit.visit_id})

## C calls this on the candidate in the same transaction as its inventory action.
func link_item_use(state: Dictionary, visit: Dictionary, item_use: Dictionary) -> bool:
	var case: Dictionary = state.divination.cases.get(visit.visit_id, {})
	if case.is_empty() or state.active_visit_id != visit.visit_id or not _event_open(case, int(state.clock_minutes)) or not case.item_use.is_empty():
		return false
	var required: Dictionary = data.cases[case.case_id].event.item_effect
	if item_use.get("event_id") != case.event.event_id or item_use.get("effect_key") != required.key:
		return false
	for key in ["item_use_id", "item_id", "transaction_id"]:
		if not item_use.get(key) is String or item_use[key].is_empty():
			return false
	case.item_use = {
		"item_use_id": item_use.item_use_id, "event_id": item_use.event_id, "item_id": item_use.item_id,
		"transaction_id": item_use.transaction_id, "effect_key": required.key, "at": int(state.clock_minutes)
	}
	return true

func _feedback(state: Dictionary, current: Dictionary, event_id: Variant) -> Dictionary:
	if not event_id is String:
		return _fail("INVALID_ACTION", "请选择可听取的事件反馈。")
	for case: Dictionary in state.divination.cases.values():
		if case.event.get("event_id") != event_id or case.npc_id != current.npc_id or case.visit_id == current.visit_id:
			continue
		if Events.can_report(case.event, int(state.clock_minutes)):
			var report := Events.disclose(state, case, current, data.economy)
			return _ok("来客的反馈已写入原案手记。", {"feedback": report.duplicate(true), "visit_id": current.visit_id})
		break
	return _fail("FEEDBACK_UNAVAILABLE", "这位来客还没有可听取的反馈。")

func feedback_queue(state: Dictionary) -> Array:
	var queue: Array = []
	for case: Dictionary in state.get("divination", {}).get("cases", {}).values():
		var event: Dictionary = case.event
		if event.is_empty() or event.occurrence == "pending" or not event.feedback.report.is_empty():
			continue
		queue.append({
			"npc_id": case.npc_id, "visit_id": case.visit_id, "event_id": event.event_id, "due_at": event.due_at,
			"case_id": case.case_id, "prediction_id": case.prediction.get("prediction_id", ""), "subject_id": event.subject_id,
			"available_at": event.feedback.available_at, "mode": event.feedback.mode,
			"disclosure": event.feedback.disclosure.duplicate(true)
		})
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.due_at < b.due_at if a.due_at != b.due_at else a.event_id < b.event_id)
	return queue

func _reveal_past(state: Dictionary, visit: Dictionary, case: Dictionary, service: Dictionary) -> void:
	var profile: Dictionary = data.past_profiles[case.profile_id]
	if not state.divination.past.has(visit.npc_id):
		state.divination.past[visit.npc_id] = {
			"profile_id": case.profile_id, "identity_id": profile.identity_id, "other_identity_id": profile.other_identity_id,
			"relation": profile.relation, "fragments": {}, "interpretations": [], "confirmed_links": [], "stories": []
		}
	var memory: Dictionary = state.divination.past[visit.npc_id]
	memory.fragments[service.option_id] = {
		"fragment_id": "%s_%s" % [case.profile_id, service.option_id], "service_id": service.service_id,
		"visit_id": visit.visit_id, "text": service.result.text, "at": service.paid_at
	}

func _interpret(state: Dictionary, visit: Dictionary, case: Dictionary, action: Dictionary) -> Dictionary:
	var memory: Dictionary = state.divination.past.get(visit.npc_id, {})
	if memory.is_empty() or memory.profile_id != case.profile_id:
		return _fail("NO_FRAGMENT", "请先在旧物案中看见前世片段。")
	var options: Dictionary = data.past_profiles[memory.profile_id].links
	var link_id: Variant = action.get("link_id")
	var text: Variant = action.get("text", "")
	if not link_id is String or not options.has(link_id) or not text is String or text.length() > 500:
		return _fail("INVALID_INPUT", "请选择一种解释，备注最多 500 字。")
	for prior: Dictionary in memory.interpretations:
		if prior.link_id == link_id:
			return _fail("INTERPRETATION_EXISTS", "这条解释已记在手记。")
	var id := _id("interpretation", action)
	memory.interpretations.append({
		"interpretation_id": id, "link_id": link_id, "label": options[link_id].label, "text": text,
		"visit_id": visit.visit_id, "at": int(state.clock_minutes), "status": "unverified"
	})
	return _ok("已记录为待验证解释。", {"interpretation_id": id, "visit_id": visit.visit_id})

func _verify(state: Dictionary, visit: Dictionary, action: Dictionary) -> Dictionary:
	var memory: Dictionary = state.divination.past.get(visit.npc_id, {})
	var case: Dictionary = state.divination.cases[visit.visit_id]
	if memory.is_empty() or memory.profile_id != case.profile_id or not memory.fragments.has("evidence"):
		return _fail("NEEDS_EVIDENCE", "请取得独立补证后再核实。")
	var profile: Dictionary = data.past_profiles[memory.profile_id]
	for record: Dictionary in memory.interpretations:
		if record.interpretation_id != action.get("interpretation_id"):
			continue
		if record.status != "unverified":
			return _fail("ALREADY_VERIFIED", "这条解释已核实。")
		var valid: bool = profile.links[record.link_id].valid
		record.status = "confirmed" if valid else "disproven"
		record["verified_at"] = int(state.clock_minutes)
		record["evidence_id"] = memory.fragments.evidence.fragment_id
		if valid:
			memory.confirmed_links.append({
				"link_id": record.link_id, "npc_id": visit.npc_id, "identity_id": memory.identity_id,
				"other_identity_id": memory.other_identity_id, "relation": memory.relation, "label": record.label,
				"interpretation_id": record.interpretation_id, "evidence_id": record.evidence_id
			})
			memory.stories.append({"link_id": record.link_id, "visit_id": visit.visit_id, "text": profile.story})
		return _ok("证物支持这个今生关联。" if valid else "补充证物与这条解释相矛盾。可以再提出一种解释。", {"status": record.status, "visit_id": visit.visit_id})
	return _fail("NO_INTERPRETATION", "请先选择一条已记录的解释。")

func _valid_text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 500

func _event_open(case: Dictionary, clock: int) -> bool:
	return not case.event.is_empty() and case.event.occurrence == "pending" and clock < int(case.event.due_at)

func _id(prefix: String, action: Dictionary) -> String:
	return prefix + "_" + String(action.action_id).sha256_text().left(32)

func _ok(message: String, result: Dictionary = {}, minutes: int = 0) -> Dictionary:
	return {"success": true, "message": message, "result": result, "minutes": minutes}

func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": message}

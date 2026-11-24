extends RefCounted
## Validate the v2 namespace before SaveService accepts it.

const Catalog = preload("res://scripts/divination/catalog.gd")
const Cards = preload("res://scripts/divination/oracle_cards.gd")
const Events = preload("res://scripts/divination/event_rules.gd")
const ProductRules = preload("res://scripts/divination/event_schema.gd")
const OracleSaved = preload("res://scripts/divination/oracle_saved.gd")
const GeneratedCases = preload("res://scripts/divination/generated_cases.gd")
const Shop = preload("res://scripts/shop/shop.gd")
const PastLines = preload("res://scripts/divination/past_lines.gd")
const CaseSchema = preload("res://scripts/divination/case_schema.gd")
const DeductionBoard = preload("res://scripts/divination/deduction_board.gd")
const MAX_INT := 2147483647

static func validate(state: Dictionary, data: Dictionary, visits: Dictionary, definition_override: Dictionary = {}, verified_bindings: Dictionary = {}) -> String:
	var work: Variant = state.get("divination")
	if not work is Dictionary or not work.get("skills") is Array or not work.get("cases") is Dictionary or not work.get("past") is Dictionary or not work.get("ledger") is Array or not work.get("effects") is Array:
		return "问卜存档字段不完整"
	var past_library := PastLines.load_config()
	if past_library.is_empty():
		return "问卜存档字段不完整"
	if not PastLines.progress_valid(state,past_library):
		return past_library.copy.invalid_source
	if not "tarot" in work.skills or work.cases.size() != visits.size():
		return "基础术式或接待案例缺失"
	var eventless: Array = []
	if int(state.get("schema_version", 0)) >= 5:
		if not work.get("legacy_eventless_visits") is Array:
			return "旧接待事件迁移记录缺失"
		for visit_id: Variant in work.legacy_eventless_visits:
			if not visit_id is String or visit_id in eventless or not work.cases.has(visit_id) or not work.cases[visit_id] is Dictionary or not work.cases[visit_id].get("event") is Dictionary or not work.cases[visit_id].event.is_empty():
				return "旧接待事件迁移记录无效"
			eventless.append(visit_id)
	var skills: Dictionary = {}
	for id in work.skills:
		if not id is String or not data.methods.has(id) or skills.has(id):
			return "未知或重复的已学术式"
		skills[id] = true
	var events: Dictionary = {}
	var services: Dictionary = {}
	var definitions: Dictionary = definition_override.duplicate(true) if not definition_override.is_empty() else CaseSchema.load_all(data)
	if int(state.get("schema_version",0)) >= 11 and (not work.get("settings") is Dictionary or work.settings.size()!=1 or not work.settings.get("free_question") is bool):
		return CaseSchema.load_rules().get("copy",{}).get("invalid_action","CASE_CONFIG_INVALID")
	for visit_id: String in work.cases:
		var visit: Variant = visits.get(visit_id)
		var case: Variant = work.cases[visit_id]
		if not visit is Dictionary or not case is Dictionary or case.get("visit_id") != visit_id or case.get("npc_id") != visit.npc_id or not data.cases.has(case.get("case_id")):
			return "案例未关联有效接待"
		if (int(state.get("schema_version",0)) >= 11 or case.has("board")) and not DeductionBoard.valid(state,visit,case,definitions):
			return CaseSchema.load_rules().get("copy",{}).get("invalid_action","CASE_CONFIG_INVALID")
		var template: Dictionary = data.cases[case.case_id]
		if template.has("emergent_definition_id") and not _emergent_record_matches(state,visit,case,template,definitions,verified_bindings):
			return "案例未关联有效接待"
		if template.get("generated", false):
			var inherited: Variant = case.get("inherited_clue_ids", [])
			var allowed_clues: Array = template.world_facts.values().map(func(fact: Dictionary) -> String: return fact.requires_clue)
			if not inherited is Array or inherited != GeneratedCases.inherited_clues(state, visit, case.case_id, allowed_clues) or not visit.get("clue_ids") is Array:
				return "生成案例的旧知识来源无效"
			for clue: Variant in inherited:
				if clue not in visit.clue_ids:
					return "生成案例遗漏了已经共同获知的事实"
		var prior_event := _prior_event_exists(case, visit, work.cases, visits)
		var unlocked: Array = state.get("people",{}).get("unlocked_topics",{}).get(case.npc_id,[])
		if not _case_records(case, visit, data, int(state.clock_minutes), int(state.get("schema_version", 0)), eventless, prior_event,unlocked,state):
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
		if not _effect(effect, case, state, data):
			return "事件影响缺少有效事件结果或效果来源"
		effect_ids[effect.effect_id] = true
	return ""

static func _emergent_record_matches(state: Dictionary, visit: Dictionary, case: Dictionary, template: Dictionary, definitions: Dictionary, bindings: Dictionary) -> bool:
	if int(state.get("schema_version",0))<14 or template.get("emergent_definition_id")!=case.case_id or not state.get("divination",{}).get("emergent_cases") is Dictionary:
		return false
	var arrival_id: Variant = visit.get("arrival_id")
	var binding: Variant = bindings.get(arrival_id)
	var instance: Variant = state.divination.emergent_cases.get("instances",{}).get(arrival_id)
	var definition: Variant = definitions.get(case.case_id)
	var row: Variant = state.get("people",{}).get("arrivals",{}).get(arrival_id)
	var profile: Variant = state.get("people",{}).get("profiles",{}).get(visit.npc_id)
	if not binding is Dictionary or not instance is Dictionary or not definition is Dictionary or not row is Dictionary or not profile is Dictionary or instance.get("status")!="ready":
		return false
	if binding.get("npc_id")!=visit.npc_id or binding.get("case_id")!=case.case_id or binding.get("definition_hash")!=instance.get("definition_hash") or instance.get("npc_id")!=visit.npc_id or instance.get("case_id")!=case.case_id or instance.get("definition")!=definition:
		return false
	if row.get("visit_id")!=visit.visit_id or row.get("npc_id")!=visit.npc_id or row.get("case_id")!=case.case_id or case.world_facts!=definition.get("truth") or template.world_facts!=definition.get("truth") or template.event!=definition.get("outcomes"):
		return false
	if case.get("board",{}).get("definition_id")!=case.case_id or case.get("board",{}).get("hash")!=instance.get("definition_hash") or case.event.get("subject_id")!=visit.npc_id or case.event.get("target_name")!=definition.outcomes.target_name:
		return false
	var public_npc: Variant = case.get("public_npc")
	if not public_npc is Dictionary or public_npc.get("npc_id")!=visit.npc_id or public_npc.get("name")!=profile.get("name") or public_npc.get("role")!=profile.get("role") or public_npc.get("case_title")!=template.title:
		return false
	for clue: Variant in visit.clue_ids:
		if not definition.truth.values().any(func(fact: Dictionary)->bool:return fact.requires_clue==clue) and not _has_product_clue(case,str(clue)):
			return false
	return true

static func wallet(value: Variant) -> bool:
	if not value is Dictionary or not value.get("items") is Dictionary:
		return false
	for item_id: String in value.items:
		if not _text(item_id) or not Catalog._integer(value.items[item_id], 0, MAX_INT):
			return false
	return true

static func _case_records(case: Dictionary, visit: Dictionary, data: Dictionary, clock: int, schema: int = 0, eventless: Array = [], prior_event: bool = false, unlocked: Array = [], state: Dictionary = {}) -> bool:
	if (schema >= 9 or case.has("cause")) and case.get("cause") != Catalog.case_cause(case.case_id):
		return false
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
	var template: Dictionary = data.cases[case.case_id]
	if template.get("generated", false):
		# The approved package is the canonical source. A visit cannot rewrite its
		# private facts, borrow another person's case, or acquire unrelated clues.
		if template.get("npc_id") != visit.npc_id or case.world_facts != template.world_facts or not case.profile_id.is_empty() or case.has("chart") or not case.branches.is_empty():
			return false
		if schema < 5 and not case.event.is_empty():
			return false
		if schema >= 5 and template.has("event") and case.event.is_empty() and case.visit_id not in eventless and not prior_event:
			return false
		var public_npc: Dictionary = case.get("public_npc", {})
		var expected: Dictionary = data.guests[visit.npc_id]
		if public_npc.get("name") != expected.name or public_npc.get("role") != expected.role or public_npc.get("npc_id") != visit.npc_id or public_npc.get("case_title") != template.title:
			return false
		for clue: String in visit.clue_ids:
			if not template.world_facts.values().any(func(fact: Dictionary) -> bool: return fact.requires_clue == clue) and not _has_product_clue(case,clue):
				return false
		for topic_id: String in template.topic_ids:
			var topic: Dictionary = data.topic_index[topic_id]
			if topic.has("requires_clue") and topic.clue_ids.any(func(clue: String) -> bool: return clue in visit.clue_ids) and topic.requires_clue not in visit.clue_ids and not _topic_unlocked_before(topic_id,topic,case,visit,unlocked):
				return false
		for service: Variant in case.services.values():
			if not service is Dictionary or not service.get("method_id") in template.method_ids:
				return false
	for entry: Dictionary in case.conversation:
		if not Catalog._integer(entry.get("statement_index"), 1, visit.dialogue.size() - 1) or not entry.get("clue_ids") is Array or not entry.get("channel") in ["button", "free_text"] or not _text(entry.get("intent")):
			return false
	for note: Dictionary in case.hypotheses:
		if not _text(note.get("text"), 500) or not note.get("clue_ids") is Array:
			return false
	var open_id: String = ""
	var questions: Dictionary = data.cases[case.case_id].questions
	for id: String in case.services:
		var service: Variant = case.services[id]
		if service is Dictionary and service.has("past_line") and case.get("cause") not in ["past","both"]:
			return false
		if not _service(service, visit, id, data, clock, questions):
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
	for fact_id: String in definition.get("world_facts", {}):
		if case.world_facts.has(fact_id) and case.world_facts[fact_id].has("value") and case.world_facts[fact_id].value not in definition.world_facts[fact_id].values:
			return false
	if (not case.event.is_empty() and definition.is_empty()) or not _event(case.event, case.prediction, visit, clock, definition,schema >= 5):
		return false
	for advice: Dictionary in case.advice:
		if case.event.is_empty() or advice.get("event_id") != case.event.event_id or not advice.get("advice_key") in _advice_keys(definition) or not advice.get("accepted") is bool or not _text(advice.get("text")) or not _text(advice.get("reply")) or not _text(advice.get("advice_id")):
			return false
		var profile: Dictionary = state.get("people",{}).get("profiles",{}).get(case.npc_id,{})
		if advice.has("acceptance"):
			if not ProductRules.acceptance_valid(advice.acceptance,advice,state,case,definition.advice[advice.advice_key],profile,visit.clue_ids):
				return false
		elif schema >= 8 and (profile.has("advice_preference") or profile.has("advice_preference_version")):
			return false
	if not case.purchase.is_empty() and (not _text(case.purchase.get("transaction_id")) or not _text(case.purchase.get("item_id"))):
		return false
	if not case.item_use.is_empty() and (case.event.is_empty() or case.item_use.get("event_id") != case.event.event_id or not _text(case.item_use.get("transaction_id")) or not _text(case.item_use.get("item_id")) or not _text(case.item_use.get("item_use_id")) or not Catalog._integer(case.item_use.get("at"), int(visit.started_at), int(case.event.due_at) - 1)):
		return false
	if case.has("demand"):
		var demand: Variant = case.demand
		if case.event.is_empty() or not demand is Dictionary or demand.get("event_id") != case.event.event_id or demand.get("visit_id") != visit.visit_id or demand.get("effect_key") != definition.get("item_effect", {}).get("key") or not _text(demand.get("demand_id")) or not _text(demand.get("text")):
			return false
		if demand.has("need_tags") or demand.has("source"):
			var rules := ProductRules.load_product_rules()
			if rules.is_empty() or demand.get("need_tags") != rules.need_tags_by_effect.get(demand.effect_key,[]) or demand.get("source") != {"kind":"advice_need","advice_id":demand.get("advice_id"),"event_id":case.event.event_id,"visit_id":visit.visit_id}:
				return false
	return _product_records(case,visit,state,data,clock)

static func _has_product_clue(case: Dictionary, clue: String) -> bool:
	for row: Variant in case.get("product_components",[]):
		if row is Dictionary and row.get("kind") == "clue" and row.get("effect",{}).get("clue_id") == clue:
			return true
	return false

static func _product_records(case: Dictionary, visit: Dictionary, state: Dictionary, data: Dictionary, clock: int) -> bool:
	var records: Variant = case.get("product_components",[])
	if not records is Array:
		return false
	var rules := ProductRules.load_product_rules()
	if not records.is_empty() and rules.is_empty():
		return false
	var seen := {}
	for row: Variant in records:
		if not row is Dictionary or row.size() != 9 or not _text(row.get("component_id")) or not _text(row.get("item_use_id")) or not _text(row.get("item_id")) or not row.get("transaction_id") is String or not row.get("kind") in ["event","clue","relationship"] or not row.get("effect") is Dictionary or not row.get("result") is Dictionary or not row.get("feedback_refs") is Array or not Catalog._integer(row.get("at"),int(visit.started_at),clock):
			return false
		var source_id: String = row.item_use_id+":"+row.component_id
		if seen.has(source_id) or row.effect.get("kind") != row.kind or row.result.get("source_id") != source_id:
			return false
		seen[source_id] = true
		var use: Dictionary = {}
		for entry: Variant in state.get("shop",{}).get("uses",[]):
			if entry is Dictionary and entry.get("item_use_id") == row.item_use_id:
				use = entry
				break
		if use.get("version") != 2 or use.get("visit_id") != visit.visit_id or use.get("item_id") != row.item_id or use.get("transaction_id") != row.transaction_id or use.get("at") != row.at:
			return false
		var matching := false
		for component: Variant in use.get("component_results",[]):
			if component is Dictionary and component.get("component_id") == row.component_id and component.get("kind") == row.kind and component.get("effect") == row.effect and component.get("result") == row.result:
				matching = true
		if not matching:
			return false
		if row.kind == "clue":
			var rule: Dictionary = rules.tool_clues.get(row.effect.get("clue_id"),{})
			if row.effect.size() != 3 or rule.is_empty() or row.effect.get("method_id") != rule.method_id or row.effect.method_id not in data.cases[case.case_id].method_ids or row.effect.method_id not in state.divination.skills or row.effect.clue_id not in visit.clue_ids or row.result != {"source_id":source_id,"status":"revealed","clue_id":row.effect.clue_id,"method_id":row.effect.method_id,"source_kind":"tool"} or row.feedback_refs != [{"kind":"tool_clue","source_id":source_id}]:
				return false
			for required: String in rule.requires_clues:
				if required not in visit.clue_ids:
					return false
		else:
			if row.transaction_id.is_empty() or case.event.is_empty() or row.at >= case.event.due_at or row.result.get("status") != "pending" or row.result.get("event_id") != case.event.event_id or row.result.get("effect_key") != row.effect.get("effect_key") or row.feedback_refs != [{"kind":"event_pending","source_id":case.event.event_id}]:
				return false
			if row.kind == "event":
				if row.effect.size() != 2 or row.effect.get("effect_key") != data.cases[case.case_id].event.get("item_effect",{}).get("key") or case.item_use.get("item_use_id") != row.item_use_id or case.item_use.get("component_id") != row.component_id:
					return false
			else:
				var rule: Dictionary = rules.relationship_effects.get(row.effect.get("effect_key"),{})
				var target := Events.product_relation_target(state,case)
				if row.effect.size() != 3 or rule.is_empty() or target.is_empty() or row.effect.get("delta") != rule.delta or row.result != {"source_id":source_id,"status":"pending","event_id":case.event.event_id,"effect_key":row.effect.effect_key,"selector":"current_goal","rel_id":target.relationship_id,"goal_id":target.goal_id,"subject_id":target.subject_id,"delta":int(rule.delta)}:
					return false
	var report: Dictionary = case.event.get("feedback",{}).get("report",{})
	if report.has("item_component_refs") and report.item_component_refs != Events.product_feedback_refs(state,case):
		return false
	return true

static func _topic_unlocked_before(topic_id: String, topic: Dictionary, case: Dictionary, visit: Dictionary, unlocked: Array) -> bool:
	for entry: Dictionary in unlocked:
		if entry.get("topic_id") != topic_id:
			continue
		var at := int(entry.get("at",MAX_INT))
		if at <= int(visit.started_at):
			return true
		for statement: Dictionary in case.conversation:
			if statement.get("intent") == topic_id and at <= int(statement.get("at",-1)) and topic.clue_ids.any(func(id: String) -> bool: return id in statement.get("clue_ids",[])):
				return true
	return false

static func _prior_event_exists(case: Dictionary, visit: Dictionary, cases: Dictionary, visits: Dictionary) -> bool:
	# A later reception keeps its own dialogue/services while referring to the
	# one canonical event from an earlier completed reception of this same case.
	# This is a current gameplay relation, distinct from old-save migration.
	for id: String in cases:
		if id == case.visit_id:
			continue
		var prior: Variant = cases[id]
		var source: Variant = visits.get(id)
		if not prior is Dictionary or not source is Dictionary or prior.get("npc_id") != case.npc_id or prior.get("case_id") != case.case_id or not prior.get("event") is Dictionary or prior.event.is_empty():
			continue
		if source.get("npc_id") != visit.npc_id or source.get("phase") != "ended" or not Catalog._integer(source.get("started_at"), 0, int(visit.started_at)-1) or not Catalog._integer(source.get("ended_at"), int(source.started_at), int(visit.started_at)):
			continue
		return true
	return false

static func _service(service: Variant, visit: Dictionary, id: String, data: Dictionary, clock: int, questions: Dictionary) -> bool:
	if not service is Dictionary or not _text(id) or service.get("service_id") != id or service.get("visit_id") != visit.visit_id or service.get("npc_id") != visit.npc_id:
		return false
	var method: Dictionary = data.methods.get(service.get("method_id"), {})
	if method.is_empty() or not method.options.has(service.get("option_id")) or not Catalog.valid_parameter(service.method_id, service.option_id, service.get("parameter")):
		return false
	if service.has("question_id") and (not service.question_id is String or not questions.has(service.question_id)):
		return false
	if not _payment(service.get("payment")) or not service.get("status") in ["quoted", "paid", "cancelled"] or not service.get("result") is Dictionary or not _text(service.get("method_title")) or not _text(service.get("option_label")):
		return false
	if service.has("past_line"):
		var descriptor: Variant = service.past_line
		if service.method_id != "past" or not descriptor is Dictionary:
			return false
		var library := PastLines.load_config()
		var definition: Dictionary = library.get("definitions",{}).get(str(descriptor.get("line_id",""))+"@"+str(int(descriptor.get("content_version",0))),{})
		var costs: Dictionary = definition.get("costs",{}).get(descriptor.get("cost_key",""),{})
		if costs.is_empty() or service.payment != {"kind":"coins","amount":int(costs.coins)} or service.get("energy") != costs.energy or service.get("minutes") != costs.minutes:
			return false
	elif service.method_id == "past":
		# The preserved legacy tariff is a separate saved-service shape. Merely
		# deleting modern descriptors must not reclassify a cheaper paid service.
		var legacy_cost: Dictionary = method.cost
		if service.get("energy") != legacy_cost.energy or service.get("minutes") != legacy_cost.minutes or (service.payment.kind == "coins" and service.payment.amount != legacy_cost.coins):
			return false
	if not Catalog._integer(service.get("quoted_at"), int(visit.started_at), clock) or not Catalog._integer(service.get("energy"), 0, MAX_INT) or not Catalog._integer(service.get("minutes"), 0, 1439):
		return false
	if service.status != "paid":
		return service.result.is_empty() and service.get("paid_at") == -1
	if not Catalog._integer(service.get("paid_at"), int(service.quoted_at), clock) or not _text(service.result.get("clue_id")) or not _text(service.result.get("title")) or not _text(service.result.get("text")) or not _text(service.result.get("lead")) or not OracleSaved.valid(service.result, service, data):
		return false
	if not service.has("question_id") or not Cards.is_card_method(service.method_id):
		return not service.result.has("inquiry")
	return _inquiry(service.result, service, visit.clue_ids, questions[service.question_id].references)

static func _inquiry(result: Dictionary, service: Dictionary, visible_ids: Array, references: Dictionary) -> bool:
	var inquiry: Variant = result.get("inquiry")
	if not inquiry is Dictionary or inquiry.get("question_id") != service.question_id or not result.has("medium"):
		return false
	for key in ["question", "frame", "known", "synthesis", "boundary"]:
		if not _text(inquiry.get(key)):
			return false
	var ids: Variant = inquiry.get("known_clue_ids")
	if not ids is Array or not ids.all(func(id: Variant) -> bool: return id in visible_ids and references.has(id)):
		return false
	var steps: Variant = inquiry.get("steps")
	var expected: int = result.medium.cards.size() if service.method_id == "tarot" else result.medium.cards.size() - 1
	if not steps is Array or steps.size() != expected:
		return false
	for step in steps:
		if not step is Dictionary or not _text(step.get("source")) or not _text(step.get("reason")) or not _text(step.get("check")):
			return false
	return true

static func _event(event: Dictionary, prediction: Dictionary, visit: Dictionary, clock: int, definition: Dictionary, require_pending: bool = false) -> bool:
	if event.is_empty():
		return prediction.is_empty()
	if not _text(event.get("event_id")) or not _text(event.get("subject_id")) or not _text(event.get("target_name")) or not Catalog._integer(event.get("due_at"), int(visit.started_at) + 1, MAX_INT):
		return false
	var feedback: Variant = event.get("feedback")
	if not feedback is Dictionary or not feedback.get("mode") in ["pending", "delayed", "immediate", "never"] or not feedback.get("disclosure") is Dictionary or not feedback.get("report") is Dictionary or not Catalog._integer(feedback.get("available_at"), -1, MAX_INT):
		return false
	if not event.get("evaluation") in ["pending", "aligned", "deviated", "insufficient", "condition_not_met"] or not event.get("occurrence") in ["pending", "occurred", "did_not_occur"]:
		return false
	if require_pending and feedback.report.is_empty() and (event.evaluation != "pending" or event.get("evaluated_at") != -1):
		return false
	if event.occurrence == "pending" and (event.due_at <= clock or feedback.mode != "pending" or not feedback.report.is_empty()):
		return false
	if event.has("rule_index") and (not Catalog._integer(event.rule_index, -1, MAX_INT) or (feedback.report.is_empty() and event.evaluation != "pending")):
		return false
	if event.occurrence != "pending":
		if int(event.due_at) > clock or event.get("resolved_at") != event.due_at or not definition.get("outcomes", {}).has(event.get("outcome_id")) or not _text(event.get("outcome")) or not event.get("evidence") in ["sufficient", "partial", "none", "insufficient"] or not _text(event.get("actual_action")) or feedback.mode == "pending":
			return false
		if event.outcome != definition.outcomes[event.outcome_id].outcome:
			return false
		if event.has("rule_index"):
			var rules: Array = definition.get("rules", [])
			if int(event.rule_index) < 0 or int(event.rule_index) >= rules.size() or rules[int(event.rule_index)].get("outcome") != event.outcome_id:
				return false
	if feedback.mode == "never" and (not feedback.disclosure.is_empty() or not feedback.report.is_empty()):
		return false
	if not feedback.report.is_empty() and (not feedback.mode in ["delayed", "immediate"] or feedback.report.get("event_id") != event.event_id or not _text(feedback.report.get("text")) or not Catalog._integer(feedback.report.get("at"), int(feedback.available_at), clock)):
		return false
	if not feedback.report.is_empty() and (not _text(feedback.report.get("feedback_id")) or not _text(feedback.report.get("visit_id")) or not feedback.report.get("evaluation") in ["no_prediction","pending","aligned","deviated","insufficient","condition_not_met"]):
		return false
	for disclosure: Dictionary in [feedback.disclosure, feedback.report]:
		if not disclosure.is_empty() and _evidence_key(disclosure.get("evidence", "")) != _evidence_key(event.get("evidence", "pending")):
			return false
		if event.get("evidence", "pending") != "sufficient":
			for field: String in ["occurrence","outcome","actual_action","occurred_at"]:
				if disclosure.has(field):
					return false
	if prediction.is_empty():
		return true
	var conditions: Dictionary = definition.get("prediction_conditions", Events.CONDITIONS)
	if not _text(prediction.get("prediction_id")) or prediction.get("event_id") != event.event_id or prediction.get("subject_id") != event.subject_id or not _text(prediction.get("text"), 500) or not conditions.has(prediction.get("condition")) or not prediction.get("expected") in ["met", "missed"]:
		return false
	return Catalog._integer(prediction.get("at"), int(visit.started_at), int(event.due_at) - 1) and Catalog._integer(prediction.get("window_start"), int(prediction.at), int(event.due_at) + 1440) and Catalog._integer(prediction.get("window_end"), int(prediction.window_start), int(event.due_at) + 1440) and prediction.get("clue_ids") is Array

static func _advice_keys(definition: Dictionary) -> Array:
	var result: Array = definition.get("advice", {}).keys()
	for option: Dictionary in definition.get("advice_options", []):
		var key: Variant = option.get("key", option.get("advice_key"))
		if key is String and key not in result:
			result.append(key)
	return result

static func _evidence_key(value: Variant) -> Variant:
	return "partial" if value == "insufficient" else value

static func _effect(effect: Dictionary, case: Dictionary, state: Dictionary, data: Dictionary) -> bool:
	if effect.get("visit_id") != case.visit_id or effect.get("npc_id") != case.npc_id or not effect.get("prediction_id") is String or effect.prediction_id != case.prediction.get("prediction_id", ""):
		return false
	if not effect.get("kind") in ["trust","familiarity","npc_relationship","referral","unlock_topic","reputation","review_growth","arrival_boost","traffic_boost","gift"] or not Catalog._integer(effect.get("amount"), -MAX_INT, MAX_INT):
		return false
	var recipient := "A" if effect.kind in ["trust","familiarity","npc_relationship","referral","unlock_topic"] else "C"
	if effect.get("recipient") != recipient:
		return false
	if not Catalog._integer(effect.get("starts_at"), int(case.event.due_at), int(state.clock_minutes)) or not (effect.get("expires_at") == -1 or Catalog._integer(effect.get("expires_at"), int(effect.starts_at)+1, MAX_INT)):
		return false
	var people: Dictionary = state.get("people", {})
	match effect.kind:
		"trust", "familiarity", "npc_relationship":
			if not Catalog._integer(effect.amount, -100, 100):
				return false
		"review_growth":
			if effect.amount < 0:
				return false
	match effect.kind:
		"npc_relationship":
			if not _text(effect.get("rel_id")) or not people.get("relationships", {}).has(effect.rel_id):
				return false
		"unlock_topic":
			if not _text(effect.get("topic_id")) or not data.topic_index.has(effect.topic_id):
				return false
		"referral":
			if effect.has("target_npc_id") and (not _text(effect.target_npc_id) or not people.get("profiles", {}).has(effect.target_npc_id)):
				return false
			if effect.has("template") and not _text(effect.template):
				return false
		"gift":
			var shop := Shop.load_config()
			var legacy_gift: bool = effect.get("item_id") == data.economy.get("gift_id")
			if not _text(effect.get("item_id")) or (not legacy_gift and not shop.get("items", {}).has(effect.item_id)) or not Catalog._integer(effect.amount, 1, MAX_INT):
				return false
		"arrival_boost", "traffic_boost":
			if effect.amount <= 0 or int(effect.expires_at) <= int(effect.starts_at):
				return false
	# Legacy records retain their stable kind-based IDs and already disclosed
	# prediction linkage after migration; no historical effect is reissued.
	if not effect.has("stage"):
		return effect.effect_id == "%s_%s" % [case.event.event_id,effect.kind] and not case.prediction.is_empty() and not case.event.feedback.report.is_empty()
	if effect.get("effect_source") in ["product_component","g4_reward"]:
		return _product_effect(effect,case,state)
	if not effect.stage in ["resolve","feedback"] or effect.get("outcome_id") != case.event.get("outcome_id") or not effect.get("effect_source") in ["outcome","feedback"] or not Catalog._integer(effect.get("effect_index"), 0, MAX_INT) or not Catalog._integer(effect.get("rule_index"), 0, MAX_INT) or effect.rule_index != case.event.get("rule_index"):
		return false
	if effect.stage == "feedback" and case.event.feedback.report.is_empty():
		return false
	var definition: Dictionary = data.cases[case.case_id].get("event", {})
	var source: Array = definition.get("feedback_effects", []) if effect.effect_source == "feedback" else definition.get("outcomes", {}).get(effect.outcome_id, {}).get("effects", [])
	if int(effect.effect_index) >= source.size():
		return false
	var original: Dictionary = source[int(effect.effect_index)]
	var original_stage: String = str(original.get("stage", "resolve" if effect.effect_source == "outcome" else "feedback"))
	if effect.stage != original_stage:
		return false
	if effect.stage == "resolve" and int(effect.starts_at) != int(case.event.due_at):
		return false
	if effect.stage == "feedback" and int(effect.starts_at) < int(case.event.feedback.report.get("at", MAX_INT)):
		return false
	var original_kind: String = "arrival_boost" if original.get("kind") == "traffic_boost" else str(original.get("kind", ""))
	if original_kind != effect.kind:
		return false
	# Amounts and target fields describe committed history. Their type/range and
	# references were checked above; later content balancing must not rewrite or
	# invalidate those already-consumed values.
	var expected := "%s_%s_%s_%s_%d_%s" % [case.event.event_id,effect.stage,effect.outcome_id,effect.effect_source,int(effect.effect_index),effect.kind]
	return effect.effect_id == expected

static func _product_effect(effect: Dictionary, case: Dictionary, state: Dictionary) -> bool:
	var rules := ProductRules.load_product_rules()
	if rules.is_empty() or effect.get("rule_version") != 1 or effect.get("rule_index") != case.event.get("rule_index") or effect.get("outcome_id") != case.event.outcome_id or effect.get("effect_index") != 0 or effect.get("expires_at") != -1:
		return false
	if effect.effect_source == "g4_reward":
		var profile: Dictionary = state.get("people",{}).get("profiles",{}).get(case.npc_id,{})
		var rule: Dictionary = rules.gift_rewards.get(effect.get("rule_key"),{})
		return not rule.is_empty() and profile.get("advice_preference_version") == 1 and not case.event.feedback.report.is_empty() and effect.stage == "feedback" and effect.starts_at == case.event.feedback.report.at and effect.kind == "gift" and effect.get("item_id") == rule.item_id and effect.amount == rule.qty and case.event.outcome_id in rule.outcome_ids and effect.effect_id == "%s_feedback_g4_reward_%s_gift" % [case.event.event_id,effect.rule_key]
	var target := Events.product_relation_target(state,case)
	var rule: Dictionary = rules.relationship_effects.get(effect.get("rule_key"),{})
	var advice := Events._selected_advice(case)
	if target.is_empty() or rule.is_empty() or effect.stage != "resolve" or effect.starts_at != case.event.due_at or effect.kind != "npc_relationship" or effect.get("rel_id") != target.relationship_id or effect.get("goal_id") != target.goal_id or effect.get("subject_id") != target.subject_id or effect.amount != rule.delta or effect.get("delta") != rule.delta or not advice.get("accepted",false) or advice.get("advice_key") not in rule.advice_keys or case.event.outcome not in rule.outcomes or case.event.evidence not in rule.evidence:
		return false
	for row: Dictionary in case.get("product_components",[]):
		if row.kind == "relationship" and row.item_use_id == effect.get("item_use_id") and row.component_id == effect.get("component_id") and row.transaction_id == effect.get("transaction_id") and row.result.source_id == effect.get("source_id") and row.effect.effect_key == effect.rule_key and row.result.rel_id == effect.rel_id:
			return effect.effect_id == "%s_resolve_product_%s_%s_npc_relationship" % [case.event.event_id,row.item_use_id,row.component_id]
	return false

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

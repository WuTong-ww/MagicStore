extends RefCounted
## Case rules. GameState passes a candidate, advances its clock and commits it.

const Catalog = preload("res://scripts/divination/catalog.gd")
const Cards = preload("res://scripts/divination/oracle_cards.gd")
const Economy = preload("res://scripts/divination/economy.gd")
const Events = preload("res://scripts/divination/event_rules.gd")
const GeneratedCases = preload("res://scripts/divination/generated_cases.gd")
const SnapshotCatalog = preload("res://scripts/divination/emergent_case_catalog.gd")
const EventCopy = preload("res://scripts/divination/event_copy.gd")
const ProductRules = preload("res://scripts/divination/event_schema.gd")
const PastLines = preload("res://scripts/divination/past_lines.gd")
const CaseSchema = preload("res://scripts/divination/case_schema.gd")
const DeductionBoard = preload("res://scripts/divination/deduction_board.gd")
const StoryContent = preload("res://scripts/story/story_content.gd")
const StoryProgress = preload("res://scripts/story/story_progress.gd")
const ACTIONS := [
	"quote_service", "settle_service", "cancel_service", "learn_method", "note_hypothesis",
	"record_prediction", "give_advice", "buy_case_item", "use_case_item", "receive_feedback",
	"interpret_past", "verify_past", "interpret_past_line", "verify_past_line",
	"case_question", "case_extra_question", "case_flip_card", "case_attach_evidence",
	"case_choose_answer", "case_eliminate", "case_close"
]

var data: Dictionary
var base: Dictionary
var _base_catalog: Dictionary
var board_config: Dictionary = CaseSchema.load_rules()
var case_definitions: Dictionary = {}
var verified_bindings: Dictionary = {}
var _definition_save_id := ""
var _definition_namespace_hash := ""

static func advice_style_options() -> Dictionary:
	var rules := ProductRules.load_product_rules()
	if rules.is_empty():
		return {}
	return {"styles":rules.styles.duplicate(true),"default_style":rules.default_style,"heading":rules.copy.advice_style_heading}

func _init(catalog: Dictionary, content: Dictionary) -> void:
	data = catalog
	_base_catalog = catalog.duplicate(true)
	base = content
	case_definitions = CaseSchema.load_all(catalog)

func sync_generated(state: Dictionary) -> bool:
	var projected := SnapshotCatalog.build(state,_base_catalog)
	if not projected.get("success",false):
		return false
	# Install all three verified maps together, never a half-projected Session.
	data = projected.catalog
	case_definitions = projected.definitions
	verified_bindings = projected.bindings.duplicate(true)
	_definition_save_id = str(state.get("save_id",""))
	_definition_namespace_hash = _namespace_hash(state)
	return true

func _namespace_hash(state: Dictionary) -> String:
	var work: Variant = state.get("divination")
	if not work is Dictionary or not work.get("emergent_cases") is Dictionary:
		return ""
	return CaseSchema.definition_hash(work.emergent_cases)

func definitions_for(state: Dictionary) -> Dictionary:
	if int(state.get("schema_version",0))<14:
		return CaseSchema.load_all(data)
	if _definition_save_id==str(state.get("save_id","")) and _definition_namespace_hash==_namespace_hash(state):
		return case_definitions.duplicate(true)
	# Read-only fallback for independent callers. It never swaps live data.
	var projected := SnapshotCatalog.build(state,_base_catalog)
	return projected.definitions if projected.get("success",false) else {}

func candidate_for(state: Dictionary) -> Dictionary:
	var proposed = get_script().new(_base_catalog.duplicate(true),base.duplicate(true))
	# Tests and debug flows deliberately override this field; keep exact settings.
	proposed.board_config = board_config.duplicate(true)
	if not proposed.sync_generated(state):
		return {"success":false,"error_code":"AICASE_CANDIDATE_CATALOG_INVALID"}
	return {"success":true,"session":proposed,"bindings":proposed.verified_bindings.duplicate(true)}

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
	if template.get("generated", false) and template.get("npc_id") != visit.npc_id:
		return false
	if not context.get("profile_id", "") is String or not context.get("subject_id", "") is String or not context.get("target_name", "") is String or not context.get("public_npc", {}) is Dictionary:
		return false
	if context.has("chart") and not Catalog.valid_chart(context.chart):
		return false
	var profile_id: String = context.get("profile_id", "")
	if case_id == "archive":
		var bound_profile := Catalog.bound_past_profile(state,visit.npc_id,data)
		if not bound_profile.is_empty():
			profile_id = bound_profile
		elif profile_id.is_empty():
			profile_id = data.guests.get(visit.npc_id, {}).get("profile_id", "")
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
		"cause": Catalog.case_cause(case_id),
		"world_facts": template.world_facts.duplicate(true), "event": event, "prediction": {},
		"services": {}, "open_service_id": "", "conversation": [], "branches": [],
		"hypotheses": [], "advice": [], "purchase": {}, "item_use": {}
	}
	if context.has("chart"):
		record["chart"] = context.chart.duplicate(true)
	if context.has("public_npc"):
		record["public_npc"] = guest_view(visit.npc_id, case_id, context.public_npc)
	if template.get("generated", false):
		var allowed_clues: Array = template.world_facts.values().map(func(fact: Dictionary) -> String: return fact.requires_clue)
		var inherited := GeneratedCases.inherited_clues(state, visit, case_id, allowed_clues)
		record["inherited_clue_ids"] = inherited
		for clue: String in inherited:
			if clue not in visit.clue_ids:
				visit.clue_ids.append(clue)
	state.divination.cases[visit.visit_id] = record
	if int(state.get("schema_version",0)) >= 11:
		record["board"] = {}
		if board_config.get("enabled",true) and state.get("daily_loop",{}).get("mode") == "sequential" and visit.get("intent","") != "shopping":
			for definition: Dictionary in definitions_for(state).values():
				if CaseSchema.g3_case_id(definition) == case_id:
					record.board = DeductionBoard.create(state,visit,definition)
					if int(state.get("schema_version",0)) >= 12:
						var started := StoryProgress.start(state,visit,definition.id,StoryContent.load_config())
						if not started.success:
							return false
					break
	return true

func case_board_view(state: Dictionary, visit: Dictionary) -> Dictionary:
	if visit.is_empty() or not state.get("divination",{}).get("cases",{}).has(visit.get("visit_id")):
		return {"enabled":false}
	var view := DeductionBoard.public_view(state,visit,state.divination.cases[visit.visit_id],definitions_for(state))
	if view.get("enabled",false) and state.has("story"):
		var config := StoryContent.load_config()
		view.merge(StoryProgress.board_view(state,visit,config),true)
		var replacements := StoryProgress.evidence_overrides(state,visit,config)
		for evidence: Dictionary in view.evidence:
			if replacements.has(evidence.id):
				evidence.merge(replacements[evidence.id],true)
	return view

func case_clue_overrides(state: Dictionary, visit: Dictionary) -> Dictionary:
	var replacements := {}
	var config := StoryContent.load_config()
	if config.is_empty():
		return replacements
	var definitions := definitions_for(state)
	for prior: Dictionary in state.get("visits",[]):
		if prior.npc_id!=visit.get("npc_id"):
			continue
		var overrides := StoryProgress.evidence_overrides(state,prior,config)
		var case: Dictionary = state.divination.cases.get(prior.visit_id,{})
		var definition: Dictionary = definitions.get(case.get("board",{}).get("definition_id"),{})
		for material: Dictionary in definition.get("evidence",[]):
			if overrides.has(material.id):
				for clue_id: String in material.get("legacy_clue_ids",[]):
					replacements[clue_id] = overrides[material.id].duplicate(true)
	return replacements

func guest_options(state: Dictionary) -> Array:
	var guests: Array = [
		{"npc_id": base.npc.npc_id, "case_id": "invitation", "label": base.npc.name + " · 邀请案"},
		{"npc_id": base.npc.npc_id, "case_id": "archive", "label": base.npc.name + " · 旧物案"}
	]
	for npc_id: String in state.get("npcs", {}):
		var guest: Dictionary = data.guests.get(npc_id, {})
		if guest.get("legacy_compatibility",false):
			guests.append({"npc_id": npc_id, "case_id": "archive", "label": "%s · 旧物案" % guest.name})
	return guests

func guest_view(npc_id: String, case_id: String, supplied: Dictionary = {}) -> Dictionary:
	var guest: Dictionary = supplied
	if guest.is_empty():
		guest = base.npc if npc_id == base.npc.npc_id else data.guests.get(npc_id, {})
	return {"npc_id": npc_id, "name": guest.get("name", "来客"), "role": guest.get("role", ""), "case_title": data.cases[case_id].title}

func opening(npc_id: String, case_id: String, has_visited: bool, known_clues: Array = []) -> String:
	var authored_guest: Dictionary = data.guests.get(npc_id,{})
	if authored_guest.get("story_guest",false):
		return authored_guest.get("followup",authored_guest.opening) if has_visited else authored_guest.opening
	var generated: Dictionary = data.cases.get(case_id, {})
	if generated.get("generated", false) and generated.get("npc_id") == npc_id:
		if not has_visited:
			return generated.opening
		# Creator review can miss a semantic hint in a return line. It remains
		# private until this character's actual detail/evidence was disclosed.
		for kind: String in ["detail", "hidden"]:
			if generated.world_facts.has(kind) and generated.world_facts[kind].requires_clue not in known_clues:
				return "上次聊的事，我还想接着说说。"
		return generated.followup
	if npc_id != base.npc.npc_id:
		return data.guests[npc_id].opening if not has_visited else "我又带来了那件旧物。上次看到的内容，我都还记得。"
	if case_id == "archive":
		return "修书时掉出一张旧借条。鱼纹看着很熟悉，我想弄清它是谁留下的。"
	if has_visited:
		return "我又来了。上次的话我记在修复笔记里，也想看看当时留下的记录。"
	return base.npc.opening + " 也许只是群发邀请，我不敢肯定。"

func talks(visit: Dictionary, case: Dictionary, clock: int, state: Dictionary = {}) -> Dictionary:
	var allowed: Dictionary = {"clarify": {"clue_ids": [], "branch_id": ""}}
	var unlocked: Array = state.get("people",{}).get("unlocked_topics",{}).get(visit.npc_id,[])
	for id: String in data.cases[case.case_id].topic_ids:
		var topic: Dictionary = data.topic_index[id]
		if topic.has("emergent_definition_id") and (topic.emergent_definition_id!=case.case_id or topic.get("emergent_question_id") not in case.get("board",{}).get("questions_asked",[])):
			continue
		var unlocked_here := unlocked.any(func(row: Dictionary) -> bool: return row.get("topic_id") == id)
		if topic.has("requires_clue") and not topic.requires_clue in visit.clue_ids and not unlocked_here:
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
	var story_config := StoryContent.load_config()
	if StoryProgress.prelude(state,visit,story_config).blocks_progress and action.type!="receive_feedback":
		return _fail("STORY_PRELUDE_REQUIRED",story_config.rules.copy.prelude_required)
	if action.type in DeductionBoard.ACTIONS:
		return _board_action(state,visit,case,action)
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
		"interpret_past_line", "verify_past_line":
			return _past_line_action(state,visit,case,action)
	return _fail("UNKNOWN_ACTION", "不支持此问卜动作。")

func _board_action(state: Dictionary, visit: Dictionary, case: Dictionary, action: Dictionary) -> Dictionary:
	var definitions := definitions_for(state)
	var outcome := DeductionBoard.handle(state,visit,case,action,data,definitions)
	if not outcome.success or action.type != "case_close":
		return outcome
	var definition: Dictionary = definitions[case.board.definition_id]
	var chosen: Dictionary = {}
	for advice: Dictionary in definition.advice:
		if advice.id == action.advice_id:
			chosen = advice
			break
	var prediction: Dictionary = chosen.prediction
	var predicted := _prediction(state,visit,case,{"action_id":action.action_id,"subject_id":case.event.get("subject_id"),"text":prediction.text,"condition":prediction.condition,"expected":prediction.expected,"window_start":int(case.event.get("due_at",0)),"window_end":int(case.event.get("due_at",0))+int(prediction.window_after_due_minutes)})
	if not predicted.success:
		return predicted
	var advised := _advice(state,visit,case,{"action_id":action.action_id,"advice_key":chosen.legacy_advice_key})
	if not advised.success:
		return advised
	case.board.closure["prediction_id"] = case.prediction.prediction_id
	case.board.closure["advice_record_id"] = case.advice.back().advice_id
	if state.has("story"):
		var progress := StoryProgress.on_closed(state,visit,StoryContent.load_config())
		if not progress.success:
			return progress
	visit.dialogue.append({"speaker":"player","text":chosen.text})
	visit.dialogue.append({"speaker":"npc","text":chosen.reaction,"mood":chosen.mood})
	outcome.result.merge({"prediction_id":case.prediction.prediction_id,"advice_record_id":case.advice.back().advice_id,"accepted":advised.result.accepted,"reply_text":chosen.reaction})
	return outcome

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

func _past_context(state: Dictionary, visit: Dictionary, case: Dictionary, action_id: String) -> Dictionary:
	var profile: Dictionary = state.get("people",{}).get("profiles",{}).get(visit.npc_id,{})
	var library := PastLines.load_config()
	var candidates := {}
	for definition: Dictionary in library.get("definitions",{}).values():
		for slot: Dictionary in definition.slots:
			if not candidates.has(slot.slot_id):
				candidates[slot.slot_id] = []
			for id: String in state.get("people",{}).get("profiles",{}):
				var person: Dictionary = state.people.profiles[id]
				if not person.get("met",false) or not state.npcs.has(id):
					continue
				if slot.kind == "family" and person.get("family_library_member",false):
					var family: Dictionary = state.people.families.get(person.get("family_id",""),{})
					candidates[slot.slot_id].append({"npc_id":id,"kind":"family","template_id":family.get("template_id",""),"member_key":person.get("member_key","")})
				elif slot.kind == "ordinary" and person.get("template_id") == "ordinary_v1" and not person.has("generation_id"):
					candidates[slot.slot_id].append({"npc_id":id,"kind":"ordinary"})
	return {"save_id":state.save_id,"npc_id":visit.npc_id,"visit_id":visit.visit_id,"action_id":action_id,"at":int(state.clock_minutes),"case_id":case.case_id,"cause":case.get("cause",Catalog.case_cause(case.case_id)),"is_ordinary":profile.get("template_id") == "ordinary_v1" and not profile.has("generation_id"),"npc_known":profile.get("met",false),"known_clue_ids":visit.clue_ids.duplicate(),"npc_coins":int(state.npcs[visit.npc_id].coins),"has_legacy_memory":state.divination.past.has(visit.npc_id),"slot_candidates":candidates}

func _modern_past(state: Dictionary, visit: Dictionary) -> bool:
	for instance: Dictionary in state.divination.get("past_lines",{}).get("instances",{}).values():
		if instance.bindings.values().any(func(binding: Dictionary) -> bool: return binding.npc_id == visit.npc_id):
			return true
	var profile: Dictionary = state.get("people",{}).get("profiles",{}).get(visit.npc_id,{})
	if int(state.get("schema_version",0)) < 9 or profile.get("template_id") != "ordinary_v1" or profile.has("generation_id") or state.divination.past.has(visit.npc_id):
		return false
	var library := PastLines.load_config()
	if library.is_empty() or not PastLines.progress_valid(state,library):
		return true # Route invalid sources to the strict modern failure, never fallback.
	var case: Dictionary = state.divination.cases[visit.visit_id]
	var context := _past_context(state,visit,case,"past_routing")
	return PastLines.binding_proposal(context,state.divination.past_lines,library).ok

func _past_service_plan(state: Dictionary, visit: Dictionary, case: Dictionary, option: String, action_id: String) -> Dictionary:
	var library := PastLines.load_config()
	if library.is_empty() or not PastLines.progress_valid(state,library):
		return _fail("PAST_LINE_UNAVAILABLE",library.get("copy",{}).get("invalid_source",data.methods.past.title))
	var progress: Dictionary = state.divination.get("past_lines",{}).duplicate(true)
	var context := _past_context(state,visit,case,action_id)
	var binding := PastLines.binding_proposal(context,progress,library)
	if not binding.ok:
		return _fail("PAST_LINE_UNAVAILABLE",binding.reason)
	if not binding.binding_patch.is_empty():
		progress.instances[binding.binding_patch.instance_id] = binding.binding_patch.instance.duplicate(true)
	var proposal := PastLines.service_proposal(context,progress,option,library)
	if not proposal.ok:
		return _fail("PAST_LINE_UNAVAILABLE",proposal.reason)
	return {"success":true,"binding_patch":binding.binding_patch,"descriptor":proposal.descriptor,"cost":proposal.cost,"result":proposal.result,"library":library}

func quote_preview(state: Dictionary, visit: Dictionary, method_id: String, option_id: String) -> Dictionary:
	var empty := {"available":false,"blocked":"","cost":{},"payment_kinds":[]}
	if visit.is_empty() or not state.divination.cases.has(visit.get("visit_id")) or not data.methods.has(method_id) or not data.methods[method_id].options.has(option_id):
		return empty
	var case: Dictionary = state.divination.cases[visit.visit_id]
	var blocked := _method_block(state,visit,case,method_id,option_id)
	var costs := Catalog.service_cost(method_id,data.methods[method_id],base.rules)
	var payments: Array = ["coins","item"]
	if method_id == "past" and _modern_past(state,visit):
		payments = ["coins"]
		var plan := _past_service_plan(state,visit,case,option_id,"past_preview")
		costs = plan.get("cost",{})
	return {"available":blocked.is_empty(),"blocked":blocked.get("message",""),"cost":costs.duplicate(true),"payment_kinds":payments}

func _past_line_action(state: Dictionary, visit: Dictionary, case: Dictionary, action: Dictionary) -> Dictionary:
	var library := PastLines.load_config()
	var context := _past_context(state,visit,case,action.action_id)
	if action.has("instance_id"):
		if not action.instance_id is String:
			return _fail("INVALID_ACTION",library.copy.invalid_context)
		context["instance_id"] = action.instance_id
	var progress: Dictionary = state.divination.get("past_lines",{})
	var proposal: Dictionary
	if action.type == "interpret_past_line":
		proposal = PastLines.interpretation_proposal(context,progress,{"group_id":action.get("group_id"),"option_id":action.get("option_id"),"text":action.get("text")},library)
	else:
		if not action.get("interpretation_id") is String:
			return _fail("INVALID_ACTION",library.copy.invalid_interpretation)
		proposal = PastLines.verification_proposal(context,progress,action.interpretation_id,library)
	if not proposal.ok:
		return _fail("PAST_LINE_UNAVAILABLE",proposal.reason)
	var binding := PastLines.binding_proposal(context,progress,library)
	if not binding.ok:
		return _fail("PAST_LINE_UNAVAILABLE",binding.reason)
	var instance: Dictionary = progress.instances[binding.instance_id]
	if action.type == "interpret_past_line":
		instance.interpretations[proposal.record.interpretation_id] = proposal.record.duplicate(true)
		return _ok(library.copy.unverified,{"interpretation_id":proposal.record.interpretation_id,"visit_id":visit.visit_id,"status":proposal.record.status})
	instance.interpretations[proposal.interpretation_id].merge(proposal.patch.duplicate(true),true)
	return _ok(library.copy[proposal.patch.status],{"interpretation_id":proposal.interpretation_id,"visit_id":visit.visit_id,"status":proposal.patch.status})

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
	var template: Dictionary = data.cases[case.case_id]
	var question_id: Variant = action.get("question_id", template.default_question)
	if question_id is String and question_id.is_empty() and not Cards.is_card_method(method_id):
		question_id = template.default_question
	if not question_id is String or not template.questions.has(question_id):
		return _fail("INVALID_ACTION", "请选择当前案例可以问的问题。")
	var costs := Catalog.service_cost(method_id, data.methods[method_id], base.rules)
	var past_plan := {}
	if method_id == "past" and _modern_past(state,visit):
		past_plan = _past_service_plan(state,visit,case,option_id,action.action_id)
		if not past_plan.success:
			return past_plan
		if kind != "coins":
			return _fail("INVALID_ACTION",past_plan.library.copy.invalid_context)
		costs = past_plan.cost
		var resource_block := _resource_block(state,costs)
		if not resource_block.is_empty():
			return resource_block
	if method_id == "past" and action.has("instance_id"):
		if not action.instance_id is String or past_plan.is_empty() or action.instance_id != past_plan.descriptor.instance_id:
			return _fail("INVALID_ACTION",PastLines.load_config().copy.invalid_context)
	var payment: Dictionary = {"kind": kind, "amount": int(costs.coins)}
	if kind == "item":
		payment.merge({"item_id": data.economy.payment_item_id, "item_name": data.economy.payment_item_name, "amount": 2 if int(costs.coins) >= 22 else 1}, true)
	var id := _id("service", action)
	var service: Dictionary = {
		"service_id": id, "visit_id": visit.visit_id, "npc_id": visit.npc_id,
		"method_id": method_id, "method_title": data.methods[method_id].title, "question_id": question_id,
		"option_id": option_id, "option_label": data.methods[method_id].options[option_id].label, "parameter": int(parameter),
		"payment": payment, "energy": int(costs.energy), "minutes": int(costs.minutes),
		"quoted_at": int(state.clock_minutes), "paid_at": -1, "status": "quoted", "result": {}
	}
	if not past_plan.is_empty():
		service["past_line"] = past_plan.descriptor.duplicate(true)
		if not past_plan.binding_patch.is_empty():
			state.divination.past_lines.instances[past_plan.binding_patch.instance_id] = past_plan.binding_patch.instance.duplicate(true)
	case.services[id] = service
	case.open_service_id = id
	return _ok("报价已确认，收取报酬后可揭示结果。", {"service_id": id, "visit_id": visit.visit_id})

func _settle(state: Dictionary, visit: Dictionary, case: Dictionary, id: Variant) -> Dictionary:
	if not id is String or id.is_empty() or id != case.open_service_id:
		return _fail("NO_QUOTE", "请先确认本次服务的报价。")
	var service: Dictionary = case.services[id]
	var blocked := _method_block(state, visit, case, service.method_id, service.option_id, int(service.quoted_at),not service.has("past_line"))
	if not blocked.is_empty():
		return blocked
	if not Economy.can_pay(state.npcs[visit.npc_id], service.payment):
		var code := "NPC_FUNDS_LOW" if service.payment.kind == "coins" else "NPC_ITEMS_LOW"
		return _fail(code, "顾客的报酬不足，结果仍未揭示。")
	blocked = _resource_block(state, service)
	if not blocked.is_empty():
		return blocked
	if not service.has("question_id"):
		service["question_id"] = data.cases[case.case_id].default_question
	var past_plan := {}
	if service.has("past_line"):
		past_plan = _past_service_plan(state,visit,case,service.option_id,"past_settle")
		if not past_plan.success or past_plan.descriptor != service.past_line or service.payment != {"kind":"coins","amount":past_plan.cost.coins} or service.energy != past_plan.cost.energy or service.minutes != past_plan.cost.minutes:
			return _fail("PAST_LINE_UNAVAILABLE",PastLines.load_config().copy.invalid_source)
	var result: Dictionary = past_plan.result.duplicate(true) if not past_plan.is_empty() else Catalog.read_result(service, case, data, visit.clue_ids)
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
	if not past_plan.is_empty():
		var descriptor: Dictionary = service.past_line
		var definition: Dictionary = past_plan.library.definitions[descriptor.line_id+"@"+str(int(descriptor.content_version))]
		var fragment: Dictionary = definition.fragments.filter(func(row: Dictionary) -> bool: return row.fragment_id == descriptor.fragment_id)[0]
		state.divination.past_lines.instances[descriptor.instance_id].fragments[descriptor.fragment_id] = {"fragment_record_id":"past_fragment_"+service.service_id,"fragment_id":descriptor.fragment_id,"era_id":descriptor.era_id,"kind":descriptor.kind,"service_id":service.service_id,"visit_id":visit.visit_id,"at":int(service.paid_at),"title":result.title,"text":result.text,"art_key":fragment.art_key}
	elif service.method_id == "past":
		_reveal_past(state, visit, case, service)
	return _ok("报酬与术式结果已保存。", output, int(service.minutes))

func _method_block(state: Dictionary, visit: Dictionary, case: Dictionary, method_id: String, option_id: String, quoted_at: int = -1, legacy_quote: bool = false) -> Dictionary:
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
		if case.get("cause",Catalog.case_cause(case.case_id)) == "present":
			return _fail("PAST_NOT_APPLICABLE",PastLines.load_config().copy.present)
		if not legacy_quote and _modern_past(state,visit):
			var plan := _past_service_plan(state,visit,case,option_id,"past_preview")
			return {} if plan.success else plan
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
	var board: Dictionary = case.get("board",{})
	var definition: Dictionary = definitions_for(state).get(board.get("definition_id"),{})
	var complete_board: bool = not definition.is_empty() and board.get("phase") == "closed" and DeductionBoard.complete(board,definition)
	if visit.reading.is_empty() and not case.services.values().any(func(service: Dictionary) -> bool: return service.status == "paid") and not complete_board:
		return _fail("NEEDS_PAID_SERVICE", "请先完成正式问卜，再把预测交给来客。")
	var start: Variant = action.get("window_start")
	var end: Variant = action.get("window_end")
	if not _valid_text(action.get("text")) or action.get("subject_id") != event.subject_id or not action.get("expected") in ["met", "missed"] or not Events.conditions(data.cases[case.case_id].event).has(action.get("condition")):
		return _fail("INVALID_PREDICTION", "请填写预测原话，并选择本案的对象、结果和条件。")
	var copy := EventCopy.load_config()
	var limit := int(event.due_at)+int(copy.prediction_limit_minutes)
	if not Catalog._integer(start, int(state.clock_minutes), limit) or not Catalog._integer(end, int(start), limit):
		return _fail("INVALID_PREDICTION",copy.prediction_window_error)
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
	var rules := ProductRules.load_product_rules()
	if rules.is_empty():
		return _fail("INVALID_ADVICE_RULES",EventCopy.load_config().item_not_applicable)
	var style: Variant = action.get("advice_style",rules.advice_styles.get(key,rules.default_style))
	if not style is String or not rules.styles.has(style):
		return _fail("INVALID_ADVICE_STYLE",rules.copy.invalid_style)
	var accepted: bool = not choice.has("requires_clue") or choice.requires_clue in visit.clue_ids
	var profile: Dictionary = state.get("people",{}).get("profiles",{}).get(visit.npc_id,{})
	var snapshot := {}
	if profile.has("advice_preference") or profile.has("advice_preference_version"):
		snapshot = ProductRules.acceptance_snapshot(state,case,key,style,accepted,str(choice.get("requires_clue","")),profile)
		if snapshot.is_empty():
			return _fail("INVALID_ADVICE_PREFERENCE",rules.copy.invalid_preference)
		accepted = accepted and int(snapshot.roll) < int(snapshot.probability)
	var copy := EventCopy.load_config()
	var id := _id("advice", action)
	case.advice.append({
		"advice_id": id, "event_id": case.event.event_id, "advice_key": key,
		"text": choice.text, "accepted": accepted, "at": int(state.clock_minutes),
		"reply": copy.advice_accepted if accepted else copy.advice_refused
	})
	if not snapshot.is_empty():
		case.advice.back()["acceptance"] = snapshot
	var effect: Dictionary = data.cases[case.case_id].event.get("item_effect",{})
	if accepted and key in effect.get("advice_keys",[]) and not case.has("demand"):
		case["demand"] = {
			"demand_id": "demand_" + String(case.event.event_id).trim_prefix("event_"),
			"event_id": case.event.event_id, "case_id": case.case_id, "visit_id": visit.visit_id,
			"npc_id": visit.npc_id, "advice_id": id, "effect_key": effect.key, "text": effect.need,
			"deadline": case.event.due_at
		}
		case.demand["need_tags"] = rules.need_tags_by_effect.get(effect.key,[]).duplicate()
		case.demand["source"] = {"kind":"advice_need","advice_id":id,"event_id":case.event.event_id,"visit_id":visit.visit_id}
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
	var effect: Dictionary = data.cases[case.case_id].event.get("item_effect",{})
	if effect.is_empty():
		return _fail("ITEM_USE_BLOCKED",EventCopy.load_config().item_not_applicable)
	var guest: Dictionary = state.npcs[visit.npc_id]
	var item_id: String = case.purchase.item_id
	if int(guest.items.get(item_id, 0)) < 1:
		return _fail("NPC_ITEMS_LOW", "顾客没有这件商品可用。")
	var id := _id("item_use", action)
	var linked := link_item_use(state, visit, {
		"item_use_id": id, "event_id": case.event.event_id, "item_id": item_id,
		"transaction_id": case.purchase.transaction_id, "effect_key": effect.key
	})
	if not linked:
		return _fail("ITEM_USE_BLOCKED", "须在事件发生前使用本次购得的商品。")
	guest.items[item_id] -= 1
	return _ok(EventCopy.load_config().item_recorded, {"item_use_id": id, "visit_id": visit.visit_id})

## G4 preview stays read-only; apply is called only on the shared candidate.
func preview_product_components(state: Dictionary, visit: Dictionary, components: Array, use_context: Dictionary) -> Dictionary:
	var rules := ProductRules.load_product_rules()
	var blocked := {"success":false,"error_code":"ITEM_USE_BLOCKED","message":rules.get("copy",{}).get("component_blocked",EventCopy.load_config().item_not_applicable),"components":[]}
	if rules.is_empty() or components.is_empty() or components.size() > int(rules.maximum_components):
		return blocked
	for key: Variant in use_context:
		if key not in ["item_use_id","transaction_id","item_id","at"]:
			return blocked
	for key: String in ["item_use_id","item_id"]:
		if not use_context.get(key) is String or use_context[key].is_empty():
			return blocked
	if not use_context.get("transaction_id") is String or (use_context.has("at") and use_context.at != state.clock_minutes):
		return blocked
	var ids := {}
	var clues := {}
	var event_count := 0
	var output: Array = []
	for component: Variant in components:
		if not component is Dictionary or component.size() != 2 or not component.get("component_id") is String or component.component_id.is_empty() or ids.has(component.component_id) or not component.get("effect") is Dictionary:
			return blocked
		ids[component.component_id] = true
		var effect: Dictionary = component.effect
		var kind: Variant = effect.get("kind")
		if kind not in ["event","attribute","option","patience","clue","relationship","traffic"]:
			return blocked
		if kind not in ["event","clue","relationship"]:
			continue
		if visit.is_empty() or state.get("active_visit_id","") != visit.get("visit_id"):
			return blocked
		var case: Dictionary = state.get("divination",{}).get("cases",{}).get(visit.visit_id,{})
		if case.is_empty() or not data.cases.has(case.case_id):
			return blocked
		var source_id: String = use_context.item_use_id+":"+component.component_id
		var prior: Dictionary = {}
		for row: Dictionary in case.get("product_components",[]):
			if row.item_use_id == use_context.item_use_id and row.component_id == component.component_id:
				prior = row
				break
		if not prior.is_empty():
			if prior.effect != effect or prior.item_id != use_context.item_id or prior.transaction_id != use_context.transaction_id:
				return blocked
			output.append({"component_id":prior.component_id,"kind":prior.kind,"result":prior.result.duplicate(true),"feedback_refs":prior.feedback_refs.duplicate(true)})
			continue
		var result := {"source_id":source_id}
		var refs: Array = []
		if kind == "clue":
			var rule: Dictionary = rules.tool_clues.get(effect.get("clue_id"),{})
			if effect.size() != 3 or rule.is_empty() or effect.get("method_id") != rule.method_id or not data.clues.has(effect.clue_id) or effect.method_id not in state.divination.skills or effect.method_id not in data.cases[case.case_id].method_ids or effect.clue_id in visit.clue_ids or clues.has(effect.clue_id):
				return blocked
			for required: String in rule.requires_clues:
				if required not in visit.clue_ids:
					return blocked
			clues[effect.clue_id] = true
			result.merge({"status":"revealed","clue_id":effect.clue_id,"method_id":effect.method_id,"source_kind":"tool"})
			refs.append({"kind":"tool_clue","source_id":source_id})
		else:
			if use_context.transaction_id.is_empty() or not _event_open(case,int(state.clock_minutes)):
				return blocked
			result.merge({"status":"pending","event_id":case.event.event_id,"effect_key":effect.get("effect_key","")})
			if kind == "event":
				event_count += 1
				var required: Dictionary = data.cases[case.case_id].event.get("item_effect",{})
				if effect.size() != 2 or event_count > 1 or required.is_empty() or effect.get("effect_key") != required.key or not case.item_use.is_empty():
					return blocked
			else:
				var rule: Dictionary = rules.relationship_effects.get(effect.get("effect_key"),{})
				var target := Events.product_relation_target(state,case)
				if effect.size() != 3 or rule.is_empty() or effect.get("delta") != rule.delta or target.is_empty():
					return blocked
				result.merge({"selector":"current_goal","rel_id":target.relationship_id,"goal_id":target.goal_id,"subject_id":target.subject_id,"delta":int(effect.delta)})
			refs.append({"kind":"event_pending","source_id":case.event.event_id})
		output.append({"component_id":component.component_id,"kind":kind,"result":result,"feedback_refs":refs})
	return {"success":true,"error_code":"","message":"","components":output}

func apply_product_components(state: Dictionary, visit: Dictionary, components: Array, use_context: Dictionary) -> Dictionary:
	var outcome := preview_product_components(state,visit,components,use_context)
	if not outcome.success or outcome.components.is_empty():
		return outcome
	var case: Dictionary = state.divination.cases[visit.visit_id]
	if not case.has("product_components"):
		case["product_components"] = []
	for component: Dictionary in outcome.components:
		if case.product_components.any(func(row: Dictionary) -> bool: return row.item_use_id == use_context.item_use_id and row.component_id == component.component_id):
			continue
		var effect := {}
		for wrapper: Dictionary in components:
			if wrapper.component_id == component.component_id:
				effect = wrapper.effect.duplicate(true)
				break
		if component.kind == "event":
			var linked := use_context.duplicate(true)
			linked.event_id = component.result.event_id
			linked.effect_key = component.result.effect_key
			if not link_item_use(state,visit,linked):
				return {"success":false,"error_code":"ITEM_USE_BLOCKED","message":EventCopy.load_config().item_not_applicable,"components":[]}
			case.item_use["component_id"] = component.component_id
		elif component.kind == "clue":
			visit.clue_ids.append(component.result.clue_id)
		case.product_components.append({"component_id":component.component_id,"kind":component.kind,"effect":effect,"result":component.result.duplicate(true),"feedback_refs":component.feedback_refs.duplicate(true),"item_use_id":use_context.item_use_id,"transaction_id":use_context.transaction_id,"item_id":use_context.item_id,"at":int(state.clock_minutes)})
	return outcome

## C calls this on the candidate in the same transaction as its inventory action.
func link_item_use(state: Dictionary, visit: Dictionary, item_use: Dictionary) -> bool:
	var case: Dictionary = state.divination.cases.get(visit.visit_id, {})
	if case.is_empty() or state.active_visit_id != visit.visit_id or not _event_open(case, int(state.clock_minutes)) or not case.item_use.is_empty():
		return false
	var required: Dictionary = data.cases[case.case_id].event.get("item_effect",{})
	if required.is_empty() or item_use.get("event_id") != case.event.event_id or item_use.get("effect_key") != required.key:
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
		if case.event.get("event_id") != event_id or case.npc_id != current.npc_id or (case.visit_id == current.visit_id and case.event.feedback.mode != "immediate"):
			continue
		if Events.can_report(case.event, int(state.clock_minutes)):
			var report := Events.disclose(state, case, current, data.economy,data.cases[case.case_id].event)
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
			"available_at": event.feedback.available_at if event.evidence != "none" else -1,
			"mode": event.feedback.mode if event.evidence != "none" else "never", "evidence": event.evidence,
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

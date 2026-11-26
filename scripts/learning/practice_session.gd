extends RefCounted
## Candidate-only learning leaf. Fiction scratch only. Never pass a real candidate to this module.
## Requires the isolated trusted-rules patch to DeductionBoard; no Session._board_action call.
const Panels = preload("res://scripts/learning/panel_examples.gd")
const Mechanics = preload("res://scripts/learning/method_mechanics.gd")
const Rules = preload("res://scripts/learning/learning_rules.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const Board = preload("res://scripts/divination/deduction_board.gd")
const Catalog = preload("res://scripts/learning/practice_catalog.gd")
static var _validated_runs: Dictionary = {}
const ACTION_FIELDS := {
	"case_question":["type","action_id","question_id"],
	"case_extra_question":["type","action_id","question_id"],
	"case_flip_card":["type","action_id","card_index"],
	"case_attach_evidence":["type","action_id","slot_id","evidence_id"],
	"case_choose_answer":["type","action_id","slot_id","answer_id"],
	"case_eliminate":["type","action_id","slot_id"],
	"case_close":["type","action_id","advice_id"],
	"case_preview_advice":["type","action_id","advice_id"],
	"case_key_slot":["type","action_id"],
	"case_inspect_panel":["type","action_id"]
}

static func zero_rules(config: Dictionary) -> Dictionary:
	var rules := Schema.load_rules()
	if rules.is_empty(): return {}
	for cost: Dictionary in rules.costs.values():
		cost.energy=int(config.practice.energy)
		cost.minutes=int(config.practice.world_minutes)
	return rules if Schema.validate_rules(rules) else {}

static func create(run_id: String, definition_id: String, bundle: Dictionary) -> Dictionary:
	if not Rules.identifier(run_id) or not bundle.config.lessons.has(definition_id): return {}
	var definition: Dictionary = bundle.definitions[definition_id]
	if not Catalog.validate_definition(definition,bundle.config,bundle.catalog): return {}
	var method: String = bundle.config.lessons[definition_id].method_id
	var state := {"save_id":"fiction_"+run_id,"clock_minutes":0,"player":{"energy":0},"fiction_capabilities":{method:int(bundle.config.lessons[definition_id].stage)},"divination":{"skills":["tarot"] if method=="tarot" else ["tarot",method]},"people":{}}
	var visit := {"visit_id":"fiction_"+run_id,"npc_id":"fiction_actor","started_at":0,"clue_ids":[],"dialogue":[]}
	var case := {"case_id":definition_id,"event":{},"branches":[],"conversation":[],"hypotheses":[],"prediction":{},"advice":[]}
	case["board"]=Board.create(state,visit,definition)
	return {"run_id":run_id,"method_id":method,"definition_id":definition_id,"definition_hash":Schema.definition_hash(definition),"steps":[],"fiction":{"state":state,"visit":visit,"case":case}}

static func replay(run: Dictionary, bundle: Dictionary) -> Dictionary:
	if not Rules.keys(run,["run_id","method_id","definition_id","definition_hash","steps","fiction"]) or not run.steps is Array or run.steps.size()>int(bundle.config.practice.maximum_steps): return {}
	var expected := create(str(run.run_id),str(run.definition_id),bundle)
	if expected.is_empty() or expected.method_id!=run.method_id or expected.definition_hash != run.definition_hash: return {}
	var seen := {}
	var costs := zero_rules(bundle.config)
	if costs.is_empty(): return {}
	for action: Variant in run.steps:
		if not action is Dictionary or not ACTION_FIELDS.has(action.get("type")) or not Rules.keys(action,ACTION_FIELDS[action.type]) or not Rules.action_id(action.get("action_id")) or seen.has(action.action_id): return {}
		seen[action.action_id]=true
		var scratch: Dictionary = expected.fiction
		var outcome: Dictionary
		if action.type == "case_inspect_panel":
			if expected.method_id not in ["bazi","ziwei","past"] or not scratch.case.board.mechanics.panels.is_empty() or scratch.case.board.phase == "closed": return {}
			var panel := Panels.result(expected.run_id,expected.method_id,int(bundle.config.lessons[expected.definition_id].stage),bundle)
			if panel.is_empty(): return {}
			scratch.case.board.mechanics.panels[expected.method_id] = panel
			Mechanics.record(scratch.case.board,action,expected.method_id,"panel_"+expected.method_id)
			outcome = {"success":true,"minutes":0}
		else:
			outcome = Board.handle(scratch.state,scratch.visit,scratch.case,action,bundle.catalog,bundle.definitions,costs)
		if not outcome.success or int(outcome.minutes)!=0 or int(scratch.state.player.energy)!=0 or int(scratch.state.clock_minutes)!=0 or not scratch.case.event.is_empty() or not scratch.case.prediction.is_empty() or not scratch.case.advice.is_empty(): return {}
		expected.steps.append(action.duplicate(true))
	return expected

static func valid(run: Variant, bundle: Dictionary) -> bool:
	if not run is Dictionary: return false
	# Completed notebooks are checked repeatedly by save validation and public UI.
	# Cache only exact, successfully replayed bytes plus their complete rules.
	var key := Schema.definition_hash({"run":run,"config":bundle.config,"definition":bundle.definitions.get(run.get("definition_id",""),{})})
	if _validated_runs.has(key): return true
	var expected := replay(run,bundle)
	if expected.is_empty() or expected != run: return false
	if _validated_runs.size() >= int(bundle.config.practice.maximum_steps): _validated_runs.clear()
	_validated_runs[key] = true
	return true

static func step(run: Dictionary, action: Dictionary, bundle: Dictionary) -> Dictionary:
	if not valid(run,bundle): return {}
	# Exact nested actions only; there is no client-supplied complete=true path.
	var next := run.duplicate(true)
	next.steps.append(action.duplicate(true))
	return replay(next,bundle)

static func completed(run: Dictionary, bundle: Dictionary) -> bool:
	if not valid(run,bundle): return false
	var board: Dictionary = run.fiction.case.board
	if board.phase!="closed": return false
	var correct := 0
	for slot: Dictionary in bundle.definitions[run.definition_id].deduction_slots:
		if board.answers.get(slot.id)==slot.correct_answer: correct+=1
	var lesson: Dictionary = bundle.config.lessons[run.definition_id]
	if correct < int(lesson.minimum_correct): return false
	var requirements: Dictionary = lesson.teaching_requirements
	var uses: Array = board.get("mechanics",{}).get("uses",[])
	if uses.filter(func(row: Dictionary) -> bool: return row.effect == requirements.effect).size() < int(requirements.minimum_effect_uses): return false
	var paired := 0
	for slot_id: String in board.attachments:
		var kinds := {}
		for evidence_id: String in board.attachments[slot_id]:
			var evidence := Board._evidence(board,bundle.definitions[run.definition_id],evidence_id)
			kinds[str(evidence.get("kind",evidence.get("type","")))] = true
		if kinds.size() >= 2: paired += 1
	return paired >= int(requirements.paired_evidence_slots)

static func public_view(run: Dictionary, bundle: Dictionary) -> Dictionary:
	if not valid(run,bundle): return {"enabled":false}
	var fiction: Dictionary = run.fiction
	var view := Board.public_view(fiction.state,fiction.visit,fiction.case,bundle.definitions,zero_rules(bundle.config))
	var lesson: Dictionary = bundle.config.lessons[run.definition_id]
	view["mentor"]=bundle.config.copy.mentor
	view["guest"] = {"name":bundle.config.copy.mentor}
	view["guest_information"] = bundle.config.copy.fiction_notice
	view["panel_result"] = run.fiction.case.board.mechanics.panels.get(run.method_id,{})
	if run.method_id in ["bazi","ziwei","past"] and not view.get("closed",false):
		view.method_tools.append({"action":"case_inspect_panel","params":{},"text":bundle.config.ui.copy.panel})
	view["fiction_notice"]=bundle.config.copy.fiction_notice
	view["mentor_intro"]=str(lesson.mentor_intro)+"\n"+String(bundle.config.ui.copy.requirements).format({"uses":lesson.teaching_requirements.minimum_effect_uses,"pairs":lesson.teaching_requirements.paired_evidence_slots})
	view["passed"] = completed(run,bundle)
	if view.get("closed",false):
		view["mentor_feedback"]=lesson.mentor_success if completed(run,bundle) else lesson.mentor_retry
		view["reaction"] = str(view.mentor_feedback)+"\n"+String(bundle.config.ui.copy.requirements).format({"uses":lesson.teaching_requirements.minimum_effect_uses,"pairs":lesson.teaching_requirements.paired_evidence_slots})
	return view

extends SceneTree
## AUTHORED NOT RUN. Pure kernel contracts, never a gameplay/online report.
const Kernel = preload("res://scripts/divination/emergent_case_kernel_v1.gd")
const Rules = preload("res://scripts/divination/emergent_case_rules_v1.gd")
const Strict = preload("res://scripts/divination/emergent_case_json_v1.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const Catalog = preload("res://scripts/divination/catalog.gd")
const Content = preload("res://scripts/core/content_loader.gd")
const Board = preload("res://scripts/divination/deduction_board.gd")
const Events = preload("res://scripts/divination/event_rules.gd")
var checks := 0
var failures := 0
var sequence := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("AICASE V1 KERNEL FAIL: "+label)

func run() -> void:
	var index_sha := FileAccess.get_sha256(Schema.INDEX_PATH)
	var content := Content.load_content()
	check(content.success,"real base content loads")
	if not content.success:
		finish()
		return
	var base := Catalog.load_data(content.content)
	var definitions := Schema.load_all(base)
	check(not base.is_empty() and definitions.size()==5,"unchanged real Story catalog retains exactly five fixed definitions")
	if failures:
		finish()
		return
	var base_before := base.duplicate(true)
	var definitions_before := definitions.duplicate(true)
	var schema := Schema.new()
	var loaded := Kernel.load_bundle(base.decks,schema)
	check(loaded.success,"all six independently loaded v1 wrappers pass real CaseSchema and logic anchors")
	if not loaded.success:
		finish()
		return
	var bundle: Dictionary = loaded.bundle
	var golden := Strict.new().read("res://tests/divination/fixtures/emergent_case_v1_golden.json",65536,14)
	check(golden.success and Rules.shape(golden.get("value"),["version","vectors"]) and golden.value.version==1 and golden.value.vectors is Array and golden.value.vectors.size()==6,"cross-language fixture shape is validated")
	if not golden.success or failures:
		finish()
		return
	for text: String in ["{\"a\":1,\"a\":2}","{\"a\":1,\"\\u0061\":2}","{\"a\":NaN}","{\"a\":Infinity}","{\"a\":1,}","[1,]","{\"a\":","true trailing","\"\\ud800\""]:
		check(not Strict.new().parse(text,65536,14).success,"strict JSON rejects duplicates/nonfinite/trailing/truncated/surrogate input / "+text)
	var parsed := Strict.new().parse("{\"integer\":1,\"decimal\":1.0}",65536,14)
	check(parsed.success and parsed.value.integer is int and parsed.value.decimal is float,"integer JSON tokens stay distinct from decimal tokens")
	var state := {"save_id":"save_gd_v1_golden","clock_minutes":22000,"people":{"profiles":{},"arrivals":{}},"divination":{"cases":{},"emergent_cases":{"version":1,"instances":{}}}}
	for vector: Dictionary in golden.value.vectors:
		check(Rules.shape(vector,["kind","draft_hash","save_id","arrival_id","npc_id","namespace","bound_definition_hash","fallback_kind"]),"each golden vector has strict fields")
		var checked := Kernel.validate_draft(bundle.anchors[vector.kind],bundle,base.decks,schema)
		check(checked.success and checked.hash==vector.draft_hash and checked.proof.base_routes==27,"Python/Godot wrapper hash and all 27 proof routes / "+str(vector.kind))
		var regenerated := Kernel.materialize(vector.kind,bundle,base.decks,schema)
		check(regenerated.success and regenerated.draft==bundle.anchors[vector.kind],"JSON materializer reconstructs the complete authored wrapper / "+str(vector.kind))
		if not checked.success:
			finish()
			return
		check(Kernel.instance_namespace(vector.save_id,vector.arrival_id,vector.npc_id,bundle.rules)==vector.namespace,"stable namespace agrees with Python / "+str(vector.kind))
		var selected := Kernel.fallback_for(vector.save_id,vector.arrival_id,vector.npc_id,bundle,base.decks,schema)
		check(selected.success and selected.draft.kind==vector.fallback_kind,"full SHA modulo fallback agrees with Python / "+str(vector.kind))
		var ready := Kernel.ready_record(checked,vector.save_id,vector.arrival_id,vector.npc_id,20000,{"kind":"fallback","protocol_version":1,"template_id":checked.draft.template_id},bundle,base.decks,schema)
		check(ready.success and ready.record.definition_hash==vector.bound_definition_hash and Schema.definition_hash(ready.record.definition)==ready.record.definition_hash,"bound definition hash agrees with Python and unchanged CaseSchema / "+str(vector.kind))
		if not ready.success:
			finish()
			return
		check(Kernel.validate_support(ready.record.definition,ready.record.support,bundle.rules).success,"bound saved proof remains consistent with the exact same truth and candidate IDs / "+str(vector.kind))
		for alteration: String in ["reuse","cross_slot","value"]:
			var malformed: Dictionary = ready.record.duplicate(true)
			if alteration=="reuse":
				malformed.support.proofs[1].premises = malformed.support.proofs[0].premises.duplicate()
			elif alteration=="cross_slot":
				malformed.definition.evidence[0].slot_ids = []
			else:
				malformed.definition.truth[malformed.support.facts[0].fact_key].value = "wrong"
			check(not Kernel.validate_support(malformed.definition,malformed.support,bundle.rules).success,"bound independent proof rejects "+alteration+" / "+str(vector.kind))
		state.people.profiles[vector.npc_id] = {"template_id":"ordinary_v1","source":"original"}
		state.people.arrivals[vector.arrival_id] = {"npc_id":vector.npc_id,"source":"daily_loop","daily_kind":"case","daily_loop_index":0,"case_id":ready.record.definition.id}
		state.divination.emergent_cases.instances[vector.arrival_id] = ready.record
		state.divination.cases["visit_"+str(vector.kind)] = {"case_id":ready.record.definition.id,"npc_id":vector.npc_id,"world_facts":ready.record.definition.truth.duplicate(true)}
	var state_before := state.duplicate(true)
	var result := Kernel.build(state,base,definitions,bundle,base.decks,schema)
	check(result.success,"build six saved kernel instances over the real catalog")
	check(state==state_before and base==base_before and definitions==definitions_before,"successful build changes no caller/global dictionaries")
	if not result.success:
		finish()
		return
	check(result.definitions.size()==definitions.size()+6,"six dynamic definitions are separate from the fixed index")
	for key: String in definitions:
		check(result.definitions[key]==definitions[key],"old fixed definition preserved / "+key)
	for key: String in base.cases:
		check(result.catalog.cases[key]==base.cases[key],"old G3 template preserved / "+key)
	for record: Dictionary in state.divination.emergent_cases.instances.values():
		var definition: Dictionary = record.definition
		var template: Dictionary = result.catalog.cases[definition.id]
		check(Schema.validate_definition(definition,result.catalog),"namespaced saved definition passes the unmodified common validator")
		check(template.world_facts==definition.truth and template.event==definition.outcomes and template.method_ids.size()==8 and template.topic_ids.size()==9,"G3 truth/event/services/topics framework is complete")
		var inquiry: Dictionary = template.questions[template.default_question]
		check(inquiry.angles.size()==9 and inquiry.references.size()==3 and not inquiry.frame.is_empty() and not inquiry.boundary.is_empty() and not inquiry.missing.is_empty(),"free-input/service inquiry framing is complete")
		for group: Array in definition.questions:
			for question: Dictionary in group:
				var topic: Dictionary = result.catalog.topic_index[question.legacy_topic_id]
				check(topic.reply_text==question.answer and topic.private_until_asked and topic.topic_id in template.topic_ids,"private question topic is registered, not falsely claimed to be public")
		for advice: Dictionary in definition.advice:
			_rule_route(definition,advice,result.catalog,result.definitions,false)
			_rule_route(definition,advice,result.catalog,result.definitions,true)
	var sample: Dictionary = bundle.anchors.lostitem
	for mutation: String in ["extra","truth","misleading","proof","route","decimal","nan"]:
		var bad := sample.duplicate(true)
		match mutation:
			"extra":bad["wallet"] = 500
			"truth":bad.definition.truth.where.value = "table"
			"misleading":bad.definition.evidence[5]["legacy_clue_ids"] = ["invitation_note"]
			"proof":bad.support.facts[0].evidence_id = "statement_2"
			"route":bad.definition.questions[0][0].evidence_ids = ["statement_0"]
			"decimal":bad.protocol_version = 1.0
			"nan":bad["extra"] = NAN
		check(not Kernel.validate_draft(bad,bundle,base.decks,schema).success,"strict candidate rejection / "+mutation)
	var broken_definition: Dictionary = sample.definition.duplicate(true)
	broken_definition.questions[0][0].evidence_ids = ["statement_0"]
	check(not Kernel.validate_support(broken_definition,sample.support,bundle.rules).success,"independent proof checker rejects a route even without template equality")
	var changed := bundle.duplicate(true)
	changed.rules.profiles.lostitem.title = "重新整理的蓝布袋记录"
	changed.anchors.lostitem = Rules.materialize("lostitem",changed.rules)
	check(Rules.validate_config(changed.rules,base.decks) and Kernel.materialize("lostitem",changed,base.decks,schema).success,"valid author-data edits do not require hardcoded story SHA changes")
	var bad_rules: Dictionary = bundle.rules.duplicate(true)
	bad_rules.event_blueprint.effects = [{"kind":"referral","amount":1,"target_npc_id":"npc_lin"}]
	check(not Rules.validate_config(bad_rules,base.decks),"v1 config rejects arbitrary effects")
	bad_rules = bundle.rules.duplicate(true)
	bad_rules.safety.deny_patterns = ["["]
	check(not Rules.validate_config(bad_rules,base.decks),"malformed config regex is refused without error logging")
	for mutation: String in ["owner","shopping","story","hash","truth","source","mirror","collision"]:
		var bad := state.duplicate(true)
		var local_base := base.duplicate(true)
		var arrival_id: String = golden.value.vectors[0].arrival_id
		var record: Dictionary = bad.divination.emergent_cases.instances[arrival_id]
		match mutation:
			"owner":record.npc_id = "npc_lin"
			"shopping":bad.people.arrivals[arrival_id].daily_kind = "shopping"
			"story":bad.people.arrivals[arrival_id]["story_rule_id"] = "fixed_last_pages"
			"hash":record.definition_hash = "0".repeat(64)
			"truth":record.definition.truth.values()[0].text = "changed"
			"source":record.source["api_key"] = "must_not_persist"
			"mirror":bad.divination.cases.visit_lostitem.world_facts = {}
			"collision":local_base.cases[record.definition.id] = {}
		var bad_before := bad.duplicate(true)
		var local_before := local_base.duplicate(true)
		check(not Kernel.build(bad,local_base,definitions,bundle,base.decks,schema).success,"saved invariant/collision rejection / "+mutation)
		check(bad==bad_before and local_base==local_before and definitions==definitions_before,"failed build exposes no partial mutation / "+mutation)
	check(FileAccess.get_sha256(Schema.INDEX_PATH)==index_sha and Schema.load_all(base).size()==5,"fixed index and Story five-definition contract are untouched")
	finish()

func _command(f: Dictionary, kind: String, fields: Dictionary, catalog: Dictionary, definitions: Dictionary) -> Dictionary:
	sequence += 1
	var action := {"type":kind,"action_id":"leaf_rule_"+str(sequence)}
	action.merge(fields,true)
	var result := Board.handle(f.state,f.visit,f.case,action,catalog,definitions)
	check(result.success,"actual Board rule "+kind)
	if result.success:
		f.state.clock_minutes += int(result.minutes)
	return result

func _rule_route(definition: Dictionary, advice: Dictionary, catalog: Dictionary, definitions: Dictionary, wrong: bool) -> void:
	# Explicit pure-rule fixture, not a GameState/save/player playthrough claim.
	var npc_id: String = definition.outcomes.subject_id
	var state := {"save_id":"pure_fallback_rules","clock_minutes":540,"player":{"energy":0},"people":{"profiles":{npc_id:{"familiarity":0}}},"divination":{"skills":["tarot"]}}
	var visit := {"visit_id":"visit_rules_"+str(sequence),"npc_id":npc_id,"day":0,"started_at":540,"clue_ids":[],"dialogue":[]}
	var case := {"case_id":definition.id,"npc_id":npc_id,"board":Board.create(state,visit,definition),"conversation":[],"branches":[],"hypotheses":[],"world_facts":definition.truth.duplicate(true),"event":Events.create(visit,definition.outcomes),"prediction":{},"advice":[],"item_use":{}}
	var f := {"state":state,"visit":visit,"case":case}
	for round: Array in definition.questions:
		if not _command(f,"case_question",{"question_id":round[0].id},catalog,definitions).success:
			return
	for index: int in range(3):
		if not _command(f,"case_flip_card",{"card_index":index},catalog,definitions).success:
			return
	for slot: Dictionary in definition.deduction_slots:
		if not _command(f,"case_attach_evidence",{"slot_id":slot.id,"evidence_id":slot.unlock_evidence[0]},catalog,definitions).success:
			return
		var answer: String = slot.correct_answer
		if wrong:
			for candidate: Dictionary in slot.answers:
				if candidate.id!=slot.correct_answer:
					answer = candidate.id
					break
		if not _command(f,"case_choose_answer",{"slot_id":slot.id,"answer_id":answer},catalog,definitions).success:
			return
	var closed := _command(f,"case_close",{"advice_id":advice.id},catalog,definitions)
	var rules := Schema.load_rules()
	check(closed.success and case.board.phase=="closed" and case.stars==(rules.limits.minimum_stars if wrong else rules.limits.maximum_stars),"all wrong answers still close at minimum stars / "+definition.id+" / "+advice.id+" / "+str(wrong))
	# G3 resolver receives an explicit selected-accepted advice fixture, as its
	# pure API contract requires; no paid service or transaction is fabricated.
	case.advice.append({"advice_id":"advice_rule_"+str(sequence),"advice_key":advice.legacy_advice_key,"accepted":true})
	Events._resolve(case,definition.outcomes)
	check(case.event.outcome==advice.prediction.expected and definition.outcomes.outcomes.has(case.event.outcome_id),"real G3 resolver takes the authored advice branch / "+advice.id)
	check(not Events.can_report(case.event,int(case.event.due_at)) and Events.can_report(case.event,int(case.event.feedback.available_at)),"actual G3 report gate remains delayed until the configured feedback time")

func finish() -> void:
	print("AICASE V1 KERNEL: %d checks, %d failures" % [checks,failures])
	print("SCOPE: fallback/kernel only; no GameState/Events/playthrough/provider/full evidence")
	quit(1 if failures else 0)

extends RefCounted
## Candidate-only learning leaf. Every generated practice JSON goes through the actual shared CaseSchema validator.
const Rules = preload("res://scripts/learning/learning_rules.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const INDEX := "res://data/learning/practice_index.json"
const DEFINITION_KEYS := ["id","version","title","legacy_case_id","question","truth","deduction_slots","questions","evidence","cards","advice","outcomes"]

static func fiction_catalog(definitions: Dictionary, deck_catalog: Dictionary) -> Dictionary:
	var clues := {}
	for definition: Variant in definitions.values():
		if not definition is Dictionary or not Rules.text(definition.get("title")) or not definition.get("truth") is Dictionary: return {}
		for fact: Variant in definition.truth.values():
			if not Rules.keys(fact,["value","text","requires_clue"]) or not Rules.text(fact.text) or not Rules.identifier(fact.requires_clue): return {}
			var id: String = str(fact.get("requires_clue",""))
			if id.is_empty() or clues.has(id): return {}
			clues[id]={"title":definition.title,"text":fact.text}
	return {"clues":clues,"decks":deck_catalog.get("decks",{}).duplicate(true),"topic_index":{},"cases":{}}

static func validate_definition(definition: Variant, config: Dictionary, catalog: Dictionary) -> bool:
	if not Rules.config_valid(config) or not Rules.keys(definition,DEFINITION_KEYS) or not config.lessons.has(definition.get("id")) or definition.legacy_case_id!="" or not Schema.validate_definition(definition,catalog): return false
	if definition.outcomes.subject_id!="fiction_"+definition.id or not definition.outcomes.feedback_effects.is_empty(): return false
	if not Rules.keys(definition.outcomes,["version","subject_id","target_name","minute_of_day","feedback_delay","world_facts","branch_ids","item_effect_ids","prediction_conditions","prediction_labels","advice","advice_options","outcomes","rules","feedback_effects"]): return false
	for slot: Dictionary in definition.deduction_slots:
		if not Rules.keys(slot,["id","title","answers","correct_answer","unlock_evidence"]): return false
		for answer: Dictionary in slot.answers:
			if not Rules.keys(answer,["id","text"]): return false
	for evidence: Dictionary in definition.evidence:
		var fields := ["id","text","type","source","slot_ids"]
		if evidence.has("legacy_clue_ids"): fields.append("legacy_clue_ids")
		if not Rules.keys(evidence,fields): return false
	for round_questions: Array in definition.questions:
		for question: Dictionary in round_questions:
			if not Rules.keys(question,["id","text","answer","evidence_ids","requires_familiarity"]): return false
	for card: Dictionary in definition.cards:
		if not Rules.keys(card,["deck_id","text","slot_id"]): return false
	for advice: Dictionary in definition.advice:
		if not Rules.keys(advice,["id","text","requires_deductions","legacy_advice_key","reaction","mood","prediction"]) or not Rules.keys(advice.prediction,["text","condition","expected","window_after_due_minutes"]): return false
	for outcome: Dictionary in definition.outcomes.outcomes.values():
		if not Rules.keys(outcome,["actual_action","outcome","evidence","feedback","text","delay_minutes","effects"]) or not outcome.effects.is_empty(): return false
	for fact: Dictionary in definition.truth.values():
		if not Rules.keys(fact,["value","text","requires_clue"]) or not str(fact.requires_clue).begins_with(definition.id+"_truth_"): return false
	return true

static func load_bundle(deck_catalog: Dictionary, config_path: String = Rules.PATH, index_path: String = INDEX) -> Dictionary:
	var config := Rules.load_config(config_path)
	var index: Variant = Rules.read_json(index_path)
	if config.is_empty() or not Rules.keys(index,["version","definitions"]) or not Schema.validate_index(index) or index.definitions.size()!=config.lessons.size(): return {}
	var definitions := {}
	for entry: Dictionary in index.definitions:
		if not config.lessons.has(entry.id): return {}
		var definition: Variant = Rules.read_json(entry.path)
		if not definition is Dictionary or definition.get("id")!=entry.id: return {}
		definitions[entry.id]=definition
	var catalog := fiction_catalog(definitions,deck_catalog)
	if catalog.is_empty(): return {}
	var fingerprints := {}
	for definition: Dictionary in definitions.values():
		if not validate_definition(definition,config,catalog): return {}
		# Detect an ID-only re-skin even when all clue/subject IDs were also renamed.
		var fact_texts: Array = definition.truth.values().map(func(fact:Dictionary)->String:return fact.text)
		fact_texts.sort()
		var fingerprint := Schema.definition_hash({"fiction_fact_texts":fact_texts})
		if fingerprints.has(fingerprint): return {}
		fingerprints[fingerprint]=true
	var panels := preload("res://scripts/learning/panel_examples.gd").data_for(deck_catalog,config.practice.panel_examples)
	if panels.is_empty(): return {}
	return {"config":config,"definitions":definitions,"catalog":catalog,"panel_data":panels}

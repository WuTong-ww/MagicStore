extends SceneTree
## Authored case contract, reachability and legacy content preservation.
const Catalog = preload("res://scripts/divination/catalog.gd")
var Schema: Script
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("CASE SCHEMA FAIL: " + label)

func run() -> void:
	check(FileAccess.file_exists("res://scripts/divination/case_schema.gd"), "shared case schema exists")
	check(FileAccess.file_exists("res://data/cases/index.json"), "case index exists")
	check(FileAccess.file_exists("res://data/cases/rules.json"), "board rules exist")
	check(FileAccess.file_exists("res://data/cases/fixed_invitation.json"), "first fixed case exists")
	if failures > 0:
		finish()
		return
	Schema = load("res://scripts/divination/case_schema.gd")
	var base: Dictionary = read_json("res://data/content.json")
	var catalog := Catalog.load_data(base)
	var definitions: Dictionary = Schema.load_all(catalog)
	check(definitions.keys() == ["fixed_invitation","fixed_bread","fixed_key","fixed_music_box","fixed_last_pages"], "all five authored story cases are registered")
	if not definitions.has("fixed_invitation"):
		finish()
		return
	var definition: Dictionary = definitions.fixed_invitation
	check(Schema.validate_definition(definition,catalog), "authored first case validates")
	check(definition.truth == catalog.cases.invitation.world_facts, "original world facts retained exactly")
	check(definition.outcomes == catalog.cases.invitation.event, "all G3 rules, feedback and referral effects retained exactly")
	check(definition.advice.map(func(v: Dictionary) -> String: return v.legacy_advice_key) == ["message","attend","wait"], "three public advice options map to original G3 keys")
	check(definition.cards.map(func(v: Dictionary) -> String: return v.deck_id) == ["lovers","swords_2","star","cups_6","world"], "five card identities follow fixed-case source")
	check(Schema.definition_hash(definition).length() == 64, "stable definition hash is SHA256")
	var reordered: Dictionary = {}
	var keys: Array = definition.keys()
	keys.reverse()
	for key: String in keys:
		reordered[key] = definition[key]
	check(Schema.definition_hash(definition) == Schema.definition_hash(reordered), "hash does not depend on JSON object key order")
	check_routes(definition)
	check_bad_definitions(definition,catalog)
	check_rules()
	check_index()
	finish()

func check_routes(definition: Dictionary) -> void:
	for round: Array in definition.questions:
		check(round.any(func(q: Dictionary) -> bool: return q.requires_familiarity == 0), "each round offers a zero-familiarity question")
	for first: Dictionary in definition.questions[0]:
		for second: Dictionary in definition.questions[1]:
			for third: Dictionary in definition.questions[2]:
				var available := {}
				for question: Dictionary in [first,second,third]:
					for id: String in question.evidence_ids:
						available[id] = true
				for slot: Dictionary in definition.deduction_slots:
					check(slot.unlock_evidence.any(func(id: String) -> bool: return available.has(id)), "all 27 base routes unlock / " + slot.id)
	check(definition.evidence.any(func(e: Dictionary) -> bool: return e.type == "misleading" and not e.source.is_empty()), "misleading interpretation retains its public testimony source")

func check_bad_definitions(original: Dictionary, catalog: Dictionary) -> void:
	for mutation: String in ["missing_truth","wrong_count","duplicate_question","unknown_evidence","wrong_slot","orphan_evidence","asymmetric_reference","bad_answer","duplicate_answer","unknown_card","duplicate_card","gated_round","dead_route","unknown_topic","changed_legacy_truth","changed_legacy_event","unknown_advice","duplicate_advice","bad_prediction","bad_prediction_window","unsupported_mood","empty_source","statement_promoted","misleading_promoted","no_misleading","negative_familiarity","fractional_familiarity","boolean_familiarity","boolean_version","unbounded_text","unsupported_version"]:
		var invalid := original.duplicate(true)
		match mutation:
			"missing_truth": invalid.erase("truth")
			"wrong_count": invalid.evidence.pop_back()
			"duplicate_question": invalid.questions[1][0].id = invalid.questions[0][0].id
			"unknown_evidence": invalid.questions[0][0].evidence_ids = ["absent"]
			"wrong_slot": invalid.evidence[0].slot_ids = ["absent"]
			"orphan_evidence": invalid.deduction_slots[0].unlock_evidence = [invalid.evidence[4].id]
			"asymmetric_reference": invalid.evidence[0].slot_ids.append("next_step")
			"bad_answer": invalid.deduction_slots[0].correct_answer = "absent"
			"duplicate_answer": invalid.deduction_slots[0].answers[1].id = invalid.deduction_slots[0].answers[0].id
			"unknown_card": invalid.cards[0].deck_id = "absent"
			"duplicate_card": invalid.cards[1].deck_id = invalid.cards[0].deck_id
			"gated_round":
				for question: Dictionary in invalid.questions[0]:
					question.requires_familiarity = 1
			"dead_route": invalid.questions[0][0].evidence_ids = [invalid.evidence[4].id]
			"unknown_topic": invalid.questions[0][0].legacy_topic_id = "absent"
			"changed_legacy_truth": invalid.truth.personal_invitation.value = false
			"changed_legacy_event": invalid.outcomes.feedback_effects = []
			"unknown_advice": invalid.advice[0].legacy_advice_key = "absent"
			"duplicate_advice": invalid.advice[1].legacy_advice_key = invalid.advice[0].legacy_advice_key
			"bad_prediction": invalid.advice[0].prediction.condition = "absent"
			"bad_prediction_window": invalid.advice[0].prediction.window_after_due_minutes = -1
			"unsupported_mood": invalid.advice[0].mood = "hopeful"
			"empty_source": invalid.evidence[1].source = ""
			"statement_promoted": invalid.evidence[1]["legacy_clue_ids"] = ["invitation_note"]
			"misleading_promoted": invalid.evidence[5]["legacy_clue_ids"] = ["invitation_note"]
			"no_misleading": invalid.evidence[5].type = "testimony"
			"negative_familiarity": invalid.questions[0][0].requires_familiarity = -1
			"fractional_familiarity": invalid.questions[0][0].requires_familiarity = 0.5
			"boolean_familiarity": invalid.questions[0][0].requires_familiarity = false
			"boolean_version": invalid.version = true
			"unbounded_text": invalid.questions[0][0].answer = "字".repeat(10001)
			"unsupported_version": invalid.version = 99
		check(not Schema.validate_definition(invalid,catalog), "invalid definition rejected / " + mutation)
	var fresh := original.duplicate(true)
	fresh.id = "future_case"
	fresh.erase("legacy_case_id")
	check(Schema.validate_definition(fresh,catalog), "same schema accepts a future case without a legacy binding")
	check(Schema.to_g3_template(original,catalog) == catalog.cases.invitation, "G3 adapter preserves original full legacy template")
	var wrong_referral := original.duplicate(true)
	for effect: Dictionary in wrong_referral.outcomes.feedback_effects:
		if effect.kind == "referral":
			effect.target_npc_id = "npc_changed"
	check(not Schema.validate_definition(wrong_referral,catalog), "npc_lin_friend recommendation target cannot change")

func check_rules() -> void:
	var rules: Dictionary = Schema.load_rules()
	check(not rules.is_empty() and Schema.validate_rules(rules), "rules JSON validates")
	if rules.is_empty():
		return
	check(rules.get("enabled") == true, "authored board is enabled by default")
	check(rules.costs.question.energy == 5 and rules.costs.question.minutes == 5 and rules.costs.flip_card.energy == 0 and rules.costs.flip_card.minutes == 10, "base question and card costs follow target")
	check(rules.costs.extra_question.energy == 10 and rules.costs.extra_card.energy == 10 and rules.costs.close.minutes == 10, "optional costs and closing time follow target")
	for mutation: String in ["missing_enabled","invalid_enabled","missing_cost","negative_cost","boolean_cost","fractional_count","missing_copy","unknown_skill","infinite_cost","unsupported_version"]:
		var invalid := rules.duplicate(true)
		match mutation:
			"missing_enabled": invalid.erase("enabled")
			"invalid_enabled": invalid.enabled = 1
			"missing_cost": invalid.costs.erase("question")
			"negative_cost": invalid.costs.question.energy = -1
			"boolean_cost": invalid.costs.question.energy = false
			"fractional_count": invalid.limits.base_cards = 2.5
			"missing_copy": invalid.copy.erase("closed_message")
			"unknown_skill": invalid.skills.extra_card = "absent"
			"infinite_cost": invalid.costs.close.minutes = INF
			"unsupported_version": invalid.version = 99
		check(not Schema.validate_rules(invalid), "invalid rules rejected / " + mutation)
	var disabled := rules.duplicate(true)
	disabled.enabled = false
	check(Schema.validate_rules(disabled), "board may be explicitly disabled while keeping its authored contract")

func check_index() -> void:
	var index: Dictionary = read_json("res://data/cases/index.json")
	check(Schema.validate_index(index), "case index validates")
	var invalid := index.duplicate(true)
	invalid.definitions.append(invalid.definitions[0].duplicate(true))
	check(not Schema.validate_index(invalid), "duplicate index entries rejected")
	invalid = index.duplicate(true)
	invalid.definitions[0].path = "res://data/../divination.json"
	check(not Schema.validate_index(invalid), "index rejects path traversal outside cases")

func read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func finish() -> void:
	print("CASE SCHEMA: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

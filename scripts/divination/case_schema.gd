class_name CaseSchema
extends RefCounted
## One authored contract for fixed, fallback and future generated deduction cases.
## Never preload Session: private truth and event definitions stay in data owners.
const EventSchema = preload("res://scripts/divination/event_schema.gd")
const INDEX_PATH := "res://data/cases/index.json"
const RULES_PATH := "res://data/cases/rules.json"
const MOODS_PATH := "res://data/people/character_protocol.json"
const MAX_INT := 2147483647
const MAX_TEXT := 2000
const COST_KEYS := ["question","extra_question","flip_card","extra_card","attach_evidence","choose_answer","eliminate","close"]
const LIMIT_KEYS := ["question_rounds","questions_per_round","base_cards","extra_cards","extra_questions","eliminations","minimum_stars","maximum_stars"]
const COPY_KEYS := ["unavailable","invalid_action","wrong_phase","closed","question_locked","question_asked","extra_question_used","question_recorded","card_revealed","card_already_revealed","card_limit","energy_low","skill_required","evidence_unavailable","evidence_wrong_slot","evidence_attached","slot_locked","invalid_answer","answer_selected","elimination_used","candidate_eliminated","incomplete","advice_unavailable","closed_message","familiarity_required","free_question_saved","invalid_free_question","free_question_disabled"]

static func load_all(catalog: Dictionary) -> Dictionary:
	var index: Variant = _read(INDEX_PATH)
	if not validate_index(index) or load_rules().is_empty():
		return {}
	var definitions := {}
	for entry: Dictionary in index.definitions:
		var definition: Variant = _read(entry.path)
		if not validate_definition(definition,catalog) or definition.id != entry.id:
			return {}
		definitions[entry.id] = definition
	return definitions

static func load_rules() -> Dictionary:
	var value: Variant = _read(RULES_PATH)
	return value if validate_rules(value) else {}

static func validate_index(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") is bool or value.get("version") != 1 or not value.get("definitions") is Array or value.definitions.is_empty():
		return false
	var seen := {}
	var paths := {}
	for entry: Variant in value.definitions:
		if not entry is Dictionary or not _id(entry.get("id")) or seen.has(entry.id) or not entry.get("path") is String:
			return false
		if entry.path != "res://data/cases/" + entry.id + ".json" or paths.has(entry.path):
			return false
		seen[entry.id] = true
		paths[entry.path] = true
	return true

static func validate_rules(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") is bool or value.get("version") != 1 or not value.get("enabled") is bool:
		return false
	for key: String in ["costs","limits","skills","copy"]:
		if not value.get(key) is Dictionary:
			return false
	if value.costs.size() != COST_KEYS.size() or value.limits.size() != LIMIT_KEYS.size():
		return false
	for key: String in COST_KEYS:
		var cost: Variant = value.costs.get(key)
		if not cost is Dictionary or cost.size() != 2 or not _integer(cost.get("energy"),0,100) or not _integer(cost.get("minutes"),0,1439):
			return false
	for key: String in LIMIT_KEYS:
		if not _integer(value.limits.get(key),0,MAX_INT):
			return false
	# Counts define this version's authored format; costs remain adjustable data.
	if value.limits.question_rounds != 3 or value.limits.questions_per_round != 3 or value.limits.base_cards != 3 or value.limits.extra_cards != 1 or value.limits.extra_questions != 1 or value.limits.eliminations != 1 or value.limits.minimum_stars != 1 or value.limits.maximum_stars != 3:
		return false
	if value.skills != {"extra_card":"lenormand","eliminate":"plum"}:
		return false
	for key: String in COPY_KEYS:
		if not _text(value.copy.get(key)):
			return false
	if not _text(value.copy.get("case_finish_required")):
		return false
	return true

static func validate_definition(value: Variant, catalog: Dictionary) -> bool:
	if not value is Dictionary or not _id(value.get("id")) or value.get("version") is bool or value.get("version") != 1 or not _text(value.get("title")) or not _text(value.get("question")):
		return false
	if not value.get("truth") is Dictionary or value.truth.is_empty() or not EventSchema.event_valid(value.get("outcomes")):
		return false
	if not _truth_valid(value.truth,value.outcomes,catalog):
		return false
	var legacy_id: Variant = value.get("legacy_case_id","")
	if not legacy_id is String or (not legacy_id.is_empty() and not _legacy_matches(value,catalog,legacy_id)):
		return false
	for row: Array in [["deduction_slots",3],["questions",3],["evidence",6],["cards",5]]:
		if not value.get(row[0]) is Array or value[row[0]].size() != row[1]:
			return false
	if not value.get("advice") is Array or value.advice.size() < 2 or value.advice.size() > 3:
		return false
	var slots := _slots(value.deduction_slots)
	if slots.size() != value.deduction_slots.size():
		return false
	var evidence := _evidence(value.evidence,slots,catalog)
	if evidence.size() != value.evidence.size():
		return false
	for slot: Dictionary in value.deduction_slots:
		for evidence_id: String in slot.unlock_evidence:
			if not evidence.has(evidence_id) or slot.id not in evidence[evidence_id].slot_ids:
				return false
	for entry: Dictionary in value.evidence:
		for slot_id: String in entry.slot_ids:
			if not entry.id in slots[slot_id].unlock_evidence:
				return false
	if not _questions_valid(value.questions,evidence,catalog) or not _routes_reachable(value.questions,slots):
		return false
	if not _cards_valid(value.cards,slots,catalog):
		return false
	return _advice_valid(value.advice,slots,value.outcomes)

static func _truth_valid(truth: Dictionary, event: Dictionary, catalog: Dictionary) -> bool:
	for key: Variant in truth:
		var fact: Variant = truth[key]
		if not _id(key) or not fact is Dictionary or not _text(fact.get("text")) or not fact.has("value") or not catalog.get("clues",{}).has(fact.get("requires_clue")):
			return false
		if not event.world_facts.has(key) or not fact.value in event.world_facts[key].values:
			return false
	return true

static func _legacy_matches(value: Dictionary, catalog: Dictionary, legacy_id: String) -> bool:
	var original: Variant = catalog.get("cases",{}).get(legacy_id)
	return original is Dictionary and value.truth == original.get("world_facts") and value.outcomes == original.get("event")

static func _slots(values: Array) -> Dictionary:
	var result := {}
	for slot: Variant in values:
		if not slot is Dictionary or not _id(slot.get("id")) or result.has(slot.id) or not _text(slot.get("title")) or not _strings(slot.get("unlock_evidence")):
			return {}
		if not slot.get("answers") is Array or slot.answers.size() < 3 or slot.answers.size() > 4:
			return {}
		var answers := {}
		for answer: Variant in slot.answers:
			if not answer is Dictionary or not _id(answer.get("id")) or answers.has(answer.id) or not _text(answer.get("text")):
				return {}
			answers[answer.id] = true
		if not answers.has(slot.get("correct_answer")):
			return {}
		result[slot.id] = slot
	return result

static func _evidence(values: Array, slots: Dictionary, catalog: Dictionary) -> Dictionary:
	var result := {}
	var kinds := {}
	for entry: Variant in values:
		if not entry is Dictionary or not _id(entry.get("id")) or result.has(entry.id) or not _text(entry.get("text")) or not _text(entry.get("source")) or not entry.get("type") in ["fact","testimony","misleading"] or not _references(entry.get("slot_ids"),slots):
			return {}
		if entry.has("legacy_clue_ids") and not _references(entry.legacy_clue_ids,catalog.get("clues",{})):
			return {}
		# A statement or a misleading interpretation must never disclose a fact.
		if entry.type != "fact" and not entry.get("legacy_clue_ids",[]).is_empty():
			return {}
		result[entry.id] = entry
		kinds[entry.type] = true
	return result if kinds.has("fact") and kinds.has("testimony") and kinds.has("misleading") else {}

static func _questions_valid(rounds: Array, evidence: Dictionary, catalog: Dictionary) -> bool:
	var seen := {}
	var referenced := {}
	for round: Variant in rounds:
		if not round is Array or round.size() != 3:
			return false
		var open := false
		for question: Variant in round:
			if not question is Dictionary or not _id(question.get("id")) or seen.has(question.id) or not _text(question.get("text")) or not _text(question.get("answer")) or not _references(question.get("evidence_ids"),evidence) or not _integer(question.get("requires_familiarity"),0,100):
				return false
			if question.has("legacy_topic_id") and not catalog.get("topic_index",{}).has(question.legacy_topic_id):
				return false
			seen[question.id] = true
			open = open or question.requires_familiarity == 0
			for id: String in question.evidence_ids:
				referenced[id] = true
		if not open:
			return false
	return referenced.size() == evidence.size()

static func _routes_reachable(rounds: Array, slots: Dictionary) -> bool:
	# All choices are checked, including later familiarity options. This is only
	# 27 routes in version 1 and prevents a future content edit softlocking a board.
	for first: Dictionary in rounds[0]:
		for second: Dictionary in rounds[1]:
			for third: Dictionary in rounds[2]:
				var available := {}
				for question: Dictionary in [first,second,third]:
					for id: String in question.evidence_ids:
						available[id] = true
				for slot: Dictionary in slots.values():
					if not slot.unlock_evidence.any(func(id: String) -> bool: return available.has(id)):
						return false
	return true

static func _cards_valid(values: Array, slots: Dictionary, catalog: Dictionary) -> bool:
	var deck := {}
	for entry: Dictionary in catalog.get("decks",{}).get("tarot",[]):
		deck[entry.id] = true
	var seen := {}
	for card: Variant in values:
		if not card is Dictionary or not _id(card.get("deck_id")) or seen.has(card.deck_id) or not deck.has(card.deck_id) or not _text(card.get("text")) or not slots.has(card.get("slot_id")):
			return false
		seen[card.deck_id] = true
	return true

static func _advice_valid(values: Array, slots: Dictionary, event: Dictionary) -> bool:
	var protocol: Variant = _read(MOODS_PATH)
	if not protocol is Dictionary or not protocol.get("moods") is Array:
		return false
	var seen := {}
	var mapped := {}
	for advice: Variant in values:
		if not advice is Dictionary or not _id(advice.get("id")) or seen.has(advice.id) or not _text(advice.get("text")) or not _text(advice.get("reaction")) or not advice.get("mood") in protocol.moods or not _references(advice.get("requires_deductions"),slots):
			return false
		var key: Variant = advice.get("legacy_advice_key")
		if not key is String or mapped.has(key) or not event.advice.has(key) or advice.text != event.advice[key].text:
			return false
		var prediction: Variant = advice.get("prediction")
		if not prediction is Dictionary or not _text(prediction.get("text")) or not event.prediction_conditions.has(prediction.get("condition")) or not prediction.get("expected") in ["met","missed"] or not _integer(prediction.get("window_after_due_minutes"),0,10080):
			return false
		seen[advice.id] = true
		mapped[key] = true
	return true

static func g3_case_id(definition: Dictionary) -> String:
	var legacy: String = definition.get("legacy_case_id", "")
	return legacy if not legacy.is_empty() else str(definition.get("id", ""))

static func to_g3_template(definition: Dictionary, catalog: Dictionary) -> Dictionary:
	if not validate_definition(definition,catalog):
		return {}
	var legacy_id: String = definition.get("legacy_case_id","")
	if not legacy_id.is_empty():
		return catalog.cases[legacy_id].duplicate(true)
	return {"title":definition.title,"world_facts":definition.truth.duplicate(true),"event":definition.outcomes.duplicate(true)}

static func definition_hash(definition: Dictionary) -> String:
	return JSON.stringify(_canonical(definition)).sha256_text()

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys()
		keys.sort()
		for key: Variant in keys:
			result[key] = _canonical(value[key])
		return result
	if value is Array:
		return value.map(_canonical)
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value

static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= MAX_TEXT

static func _id(value: Variant) -> bool:
	return _text(value) and value.length() <= 80 and value.is_valid_identifier() and value == value.to_lower()

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high

static func _strings(value: Variant) -> bool:
	if not value is Array or value.is_empty():
		return false
	var seen := {}
	for item: Variant in value:
		if not _id(item) or seen.has(item):
			return false
		seen[item] = true
	return true

static func _references(value: Variant, allowed: Dictionary) -> bool:
	return _strings(value) and value.all(func(id: String) -> bool: return allowed.has(id))

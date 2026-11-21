class_name EventSchema
extends RefCounted
## Immutable content contracts, including first-match reachability.
const TEMPLATES_PATH := "res://data/divination/event_templates.json"
const MAX_INT := 2147483647
const EFFECT_KINDS := ["trust","familiarity","npc_relationship","reputation","gift","referral","traffic_boost","arrival_boost","review_growth","unlock_topic"]
const EVALUATIONS := ["pending","aligned","deviated","insufficient","condition_not_met","no_prediction"]

static func _text(value: Variant) -> bool:
	return value is String and not value.is_empty()

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high

static func _strings(value: Variant, allow_empty: bool = false) -> bool:
	if not value is Array or (value.is_empty() and not allow_empty):
		return false
	var seen := {}
	for entry: Variant in value:
		if not _text(entry) or seen.has(entry):
			return false
		seen[entry] = true
	return true

static func _one_or_many(value: Variant, allowed: Array) -> bool:
	return value in allowed if value is String else _strings(value) and value.all(func(v: Variant) -> bool: return v in allowed)

static func event_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not _text(value.get("subject_id")) or not _text(value.get("target_name")) or not _integer(value.get("minute_of_day"),0,1439) or not _integer(value.get("feedback_delay"),0,10080):
		return false
	if value.has("template_id") and not _text(value.template_id):
		return false
	for key: String in ["advice","outcomes","world_facts","prediction_conditions","prediction_labels"]:
		if not value.get(key) is Dictionary:
			return false
	if value.advice.is_empty() or value.outcomes.is_empty() or not value.get("advice_options") is Array or value.advice_options.is_empty() or not value.get("rules") is Array or value.rules.is_empty() or value.rules.size() > 128:
		return false
	if not _strings(value.get("branch_ids"),true) or not _strings(value.get("item_effect_ids"),true):
		return false
	for id: Variant in value.world_facts:
		if not _text(id):
			return false
		var fact: Variant = value.world_facts[id]
		if not fact is Dictionary or not fact.get("values") is Array or fact.values.is_empty() or not fact.has("default") or not fact.default in fact.values:
			return false
		for item: Variant in fact.values:
			if not (item is String or item is bool or ((item is int or item is float) and is_finite(float(item)))):
				return false
	var advice_keys: Array = []
	for option: Variant in value.advice_options:
		if not option is Dictionary or not _text(option.get("key")) or option.key in advice_keys or not _text(option.get("label")) or not value.advice.get(option.key) is Dictionary or value.advice[option.key].get("text") != option.label:
			return false
		if option.get("requires_clue","") != value.advice[option.key].get("requires_clue","") or (option.has("requires_clue") and not _text(option.requires_clue)):
			return false
		if option.has("item_effect_keys") and not _one_or_many(option.item_effect_keys,value.item_effect_ids):
			return false
		advice_keys.append(option.key)
	if advice_keys.size() != value.advice.size():
		return false
	var item_effect: Variant = value.get("item_effect",{})
	if not item_effect is Dictionary:
		return false
	if not item_effect.is_empty() and (not item_effect.get("key") in value.item_effect_ids or not _text(item_effect.get("need")) or (item_effect.has("advice_keys") and not _one_or_many(item_effect.advice_keys,advice_keys))):
		return false
	for id: Variant in value.outcomes:
		var outcome: Variant = value.outcomes[id]
		if not _text(id) or not outcome is Dictionary or not _text(outcome.get("actual_action")) or not outcome.get("outcome") in ["met","missed"] or not outcome.get("evidence") in ["sufficient","partial","none"] or not outcome.get("feedback") in ["delayed","immediate","never"] or not outcome.get("text") is String or not _integer(outcome.get("delay_minutes"),0,10080):
			return false
		if outcome.feedback != "never" and outcome.evidence != "none" and outcome.text.is_empty():
			return false
		if outcome.feedback == "immediate" and outcome.delay_minutes != 0:
			return false
		if not _effects_valid(outcome.get("effects"),value.outcomes.keys()):
			return false
	if not _effects_valid(value.get("feedback_effects"),value.outcomes.keys()):
		return false
	if not value.prediction_conditions.has("always") or not _text(value.prediction_labels.get("met")) or not _text(value.prediction_labels.get("missed")):
		return false
	for id: Variant in value.prediction_conditions:
		if not _text(id):
			return false
		var condition: Variant = value.prediction_conditions[id]
		if not condition is Dictionary or not _text(condition.get("label")) or (condition.has("outcomes") and not _one_or_many(condition.outcomes,value.outcomes.keys())):
			return false
	var referenced := {}
	for rule: Variant in value.rules:
		if not rule is Dictionary or not rule.get("when") is Dictionary or not value.outcomes.has(rule.get("outcome")) or not _when_valid(rule.when,value,advice_keys):
			return false
		referenced[rule.outcome] = true
	return referenced.size() == value.outcomes.size() and _reachable(value,advice_keys)

static func _when_valid(when: Dictionary, definition: Dictionary, advice_keys: Array) -> bool:
	for key: Variant in when:
		if not key in ["advice","accepted","fact","branch","item_effect","relationship_min","personality_in"]:
			return false
	if when.has("advice") and not _one_or_many(when.advice,advice_keys):
		return false
	if when.has("accepted") and not when.accepted is bool:
		return false
	for row: Array in [["branch",definition.branch_ids],["item_effect",definition.item_effect_ids]]:
		if when.has(row[0]) and not _one_or_many(when[row[0]],row[1]):
			return false
	if when.has("fact"):
		if not when.fact is Dictionary or when.fact.is_empty():
			return false
		for id: Variant in when.fact:
			if not definition.world_facts.has(id) or not when.fact[id] in definition.world_facts[id].values:
				return false
	if when.has("relationship_min"):
		if not when.relationship_min is Dictionary or when.relationship_min.is_empty():
			return false
		for id: Variant in when.relationship_min:
			if not _text(id) or not _integer(when.relationship_min[id],0,100):
				return false
	return not when.has("personality_in") or _strings(when.personality_in)

static func _effects_valid(value: Variant, outcomes: Array) -> bool:
	if not value is Array:
		return false
	for effect: Variant in value:
		if not effect is Dictionary or not effect.get("kind") in EFFECT_KINDS or (effect.has("stage") and not effect.stage in ["resolve","feedback"]):
			return false
		for key: Variant in effect:
			if not key in ["kind","stage","when","amount","delta","rel_id","item_id","qty","npc_id","target_npc_id","template","minutes","topic_id"]:
				return false
		if effect.kind in ["trust","familiarity","npc_relationship","reputation","gift","traffic_boost","arrival_boost","review_growth"] and not (effect.has("amount") or effect.has("delta") or (effect.kind == "gift" and effect.has("qty"))):
			return false
		var amount: Variant = effect.get("amount",effect.get("delta",1))
		if not _integer(amount,-MAX_INT,MAX_INT):
			return false
		if effect.has("delta") and not _integer(effect.delta,-MAX_INT,MAX_INT):
			return false
		if effect.has("amount") and effect.has("delta") and effect.amount != effect.delta:
			return false
		if effect.has("qty") and (not _integer(effect.qty,1,MAX_INT) or (effect.has("amount") and effect.amount != effect.qty)):
			return false
		if effect.has("minutes") and not _integer(effect.minutes,0,MAX_INT):
			return false
		for key: String in ["npc_id","target_npc_id","template"]:
			if effect.has(key) and not _text(effect[key]):
				return false
		if effect.kind in ["trust","familiarity","npc_relationship"] and not _integer(amount,-100,100):
			return false
		if effect.kind == "review_growth" and amount < 0:
			return false
		match effect.kind:
			"npc_relationship":
				if not _text(effect.get("rel_id")) or not _integer(effect.get("delta",amount),-MAX_INT,MAX_INT):
					return false
			"gift":
				if not _text(effect.get("item_id")) or not _integer(effect.get("qty",amount),1,MAX_INT):
					return false
			"referral":
				if not _text(effect.get("npc_id")) and not _text(effect.get("target_npc_id")) and not _text(effect.get("template")):
					return false
			"traffic_boost", "arrival_boost":
				if not _integer(effect.get("minutes"),1,MAX_INT) or not _integer(amount,1,100):
					return false
			"unlock_topic":
				if not _text(effect.get("topic_id")):
					return false
		var when: Variant = effect.get("when",{})
		if not when is Dictionary:
			return false
		for key: Variant in when:
			var allowed: Array = EVALUATIONS if key == "evaluation" else (["met","missed"] if key == "outcome" else outcomes)
			if not key in ["evaluation","outcome","outcome_id"] or not _one_or_many(when[key],allowed):
				return false
	return true

static func _values(value: Variant) -> Array:
	return value if value is Array else [value]

static func _reachable(definition: Dictionary, advice_keys: Array) -> bool:
	# Each rule is a box over finite value sets. Subtract preceding rule boxes;
	# remaining pieces are witnesses of a real first-match path. Relationship
	# thresholds partition their numeric line without sampling arbitrary scores.
	var domains: Dictionary = {"advice":advice_keys+[""],"accepted":[false,true],"item_effect":[""]+definition.item_effect_ids,"personality":[""]}
	for id: String in definition.world_facts:
		domains["fact:"+id] = definition.world_facts[id].values
	for id: String in definition.branch_ids:
		domains["branch:"+id] = [false,true]
	for rule: Dictionary in definition.rules:
		for personality: String in rule.when.get("personality_in",[]):
			if personality not in domains.personality:
				domains.personality.append(personality)
		for id: String in rule.when.get("relationship_min",{}):
			var key := "relation:"+id
			if not domains.has(key):
				domains[key] = ["missing"]
			var number: int = int(rule.when.relationship_min[id])
			if number not in domains[key]:
				domains[key].append(number)
	var previous: Array = []
	var reached := {}
	for rule: Dictionary in definition.rules:
		var cube: Dictionary = domains.duplicate(true)
		var when: Dictionary = rule.when
		for key: String in ["advice","accepted","item_effect"]:
			if when.has(key):
				cube[key] = _values(when[key])
		for id: String in when.get("fact",{}):
			cube["fact:"+id] = [when.fact[id]]
		if when.has("branch"):
			for id: String in _values(when.branch):
				cube["branch:"+id] = [true]
		if when.has("personality_in"):
			cube.personality = when.personality_in
		for id: String in when.get("relationship_min",{}):
			var minimum: int = int(when.relationship_min[id])
			cube["relation:"+id] = cube["relation:"+id].filter(func(v: Variant) -> bool: return not v is String and v >= minimum)
		var physical: Array = _physical_advice(cube)
		var remainder: Array = physical.duplicate()
		for old: Dictionary in previous:
			var next: Array = []
			for piece: Dictionary in remainder:
				next.append_array(_subtract(piece,old))
			if next.size() > 4096:
				return false
			remainder = next
		if remainder.is_empty():
			return false
		for piece: Dictionary in remainder:
			for key: String in piece.advice:
				reached[key] = true
		previous.append_array(physical)
	if not advice_keys.all(func(id: String) -> bool: return reached.has(id)):
		return false
	# An accepted route alone is insufficient: refusal and missing prerequisites
	# also need a world outcome when the event clock is reached.
	var uncovered: Array = _physical_advice(domains)
	for old: Dictionary in previous:
		var next: Array = []
		for piece: Dictionary in uncovered:
			next.append_array(_subtract(piece,old))
		if next.size() > 4096:
			return false
		uncovered = next
	return uncovered.is_empty()

static func _physical_advice(cube: Dictionary) -> Array:
	# No advice is a real player path, but it cannot have been accepted. Split
	# the dependent fields before both reachability subtraction and coverage;
	# otherwise the impossible empty+accepted pair can invent a rule witness.
	var result: Array = []
	var named: Array = cube.advice.filter(func(id: String) -> bool: return not id.is_empty())
	if not named.is_empty():
		var piece := cube.duplicate(true)
		piece.advice = named
		result.append(piece)
	if "" in cube.advice and false in cube.accepted:
		var piece := cube.duplicate(true)
		piece.advice = [""]
		piece.accepted = [false]
		result.append(piece)
	return result

static func _subtract(cube: Dictionary, old: Dictionary) -> Array:
	var overlap := {}
	for key: String in cube:
		overlap[key] = cube[key].filter(func(v: Variant) -> bool: return v in old[key])
		if overlap[key].is_empty():
			return [cube]
	var remaining := cube.duplicate(true)
	var pieces: Array = []
	for key: String in cube:
		var outside: Array = remaining[key].filter(func(v: Variant) -> bool: return not v in overlap[key])
		if not outside.is_empty():
			var piece := remaining.duplicate(true)
			piece[key] = outside
			pieces.append(piece)
		remaining[key] = overlap[key]
	return pieces

static func templates_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("templates") is Dictionary or value.templates.size() != 3:
		return false
	for id: String in ["contact","visit","decision"]:
		if not event_valid(value.templates.get(id)):
			return false
	return true

static func load_templates() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEMPLATES_PATH))
	return parsed if templates_valid(parsed) else {}

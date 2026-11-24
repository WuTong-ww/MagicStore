extends RefCounted
## Leaf authored-defaults-only contract. Content and event values remain JSON.
const MAX_INT := 2147483647
const TOPICS := ["lostitem","neighbormisunderstanding","lostpet","oldphoto","anonymousgift","moving"]
const SHAPES := {
	"draft":["protocol_version","template_id","kind","definition","support"],
	"definition":["id","version","title","question","truth","deduction_slots","questions","evidence","cards","advice","outcomes"],
	"fact":["value","text","requires_clue"],"slot":["id","title","answers","correct_answer","unlock_evidence"],
	"answer":["id","text"],"question":["id","text","answer","evidence_ids","requires_familiarity","legacy_topic_id"],
	"evidence":["id","text","type","source","slot_ids","legacy_clue_ids"],
	"card":["deck_id","text","slot_id"],"advice":["id","text","requires_deductions","legacy_advice_key","reaction","mood","prediction"],
	"prediction":["text","condition","expected","window_after_due_minutes"],"support":["facts","proofs"],
	"binding":["fact_key","evidence_id","value"],"proof":["slot_id","answer_id","rule","premises"]}
const LIMITS := ["title","question","button","reply","evidence","fact","source","slot_title","answer","card","reaction","id","depth","definition_bytes","draft_bytes","instance_bytes","total_instance_bytes","instances","public_sources","public_source_text","maximum_familiarity"]
const COPY := ["answer_prefix","statement_source","misleading_source","reactions","moods","reference","frame","missing","boundary","angle","no_condition","condition_verify","condition_ask","prediction_met","prediction_missed","prediction_text_met","prediction_text_missed","tool_public_source"]

static func shape(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size()==keys.size() and keys.all(func(key:String)->bool:return value.has(key))

static func integer(value: Variant, minimum: int, maximum: int = MAX_INT) -> bool:
	return value is int and value>=minimum and value<=maximum

static func strings(value: Variant, allow_empty: bool = false) -> bool:
	return value is Array and (allow_empty or not value.is_empty()) and value.all(func(entry:Variant)->bool:return entry is String and not entry.strip_edges().is_empty())

static func unique(values: Array) -> bool:
	var seen := {}
	for entry: Variant in values:
		if seen.has(entry):
			return false
		seen[entry] = true
	return true

static func id(value: Variant, rules: Dictionary) -> bool:
	return value is String and value.length()<=rules.limits.id and RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(value)!=null

static func safe_text(value: Variant, field: String, rules: Dictionary) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length()>rules.limits[field]:
		return false
	for index: int in range(value.length()):
		if value.unicode_at(index)<32 and value.unicode_at(index) not in [9,10,13]:
			return false
	for term: String in rules.safety.deny_terms+rules.safety.fixed_character_terms:
		if value.to_lower().contains(term.to_lower()):
			return false
	for pattern: String in rules.safety.deny_patterns:
		if RegEx.create_from_string("(?i)"+pattern).search(value)!=null:
			return false
	return true

static func validate_config(rules: Variant, decks: Dictionary) -> bool:
	if not shape(rules,["protocol_version","enabled","topics","fallbacks","counts","limits","shapes","safety","protocol","event_blueprint","copy","profiles"]):
		return false
	if not integer(rules.protocol_version,1,1) or not rules.enabled is bool or rules.topics!=TOPICS or rules.shapes!=SHAPES:
		return false
	if rules.counts!={"slots":3,"evidence":6,"cards":5,"rounds":3,"questions_per_round":3,"minimum_advice":2,"maximum_advice":3} or not rules.counts is Dictionary or not rules.counts.values().all(func(v:Variant)->bool:return integer(v,1)) or not shape(rules.limits,LIMITS):
		return false
	if not rules.limits.values().all(func(v:Variant)->bool:return integer(v,1)):
		return false
	if not (rules.limits.definition_bytes<=rules.limits.draft_bytes and rules.limits.draft_bytes<=rules.limits.instance_bytes and rules.limits.instance_bytes<rules.limits.total_instance_bytes) or rules.limits.maximum_familiarity>100:
		return false
	if not shape(rules.protocol,["owner_placeholder","proof_rules","namespace_prefix","id_digest_length","source_kinds","disclosure_kinds","truth_policy"]):
		return false
	if not id(rules.protocol.owner_placeholder,rules) or rules.protocol.proof_rules!=["fact_equals"] or rules.protocol.truth_policy!="authored_defaults_only" or rules.protocol.namespace_prefix!="ec_" or not integer(rules.protocol.id_digest_length,1,64) or rules.protocol.source_kinds!=["fallback","model"] or rules.protocol.disclosure_kinds!=["feedback_report","story_disclosure"]:
		return false
	if not shape(rules.safety,["allowed_moods","deny_terms","deny_patterns","fixed_character_terms"]) or rules.safety.allowed_moods!=["neutral","smile","hesitant","surprised","sad"]:
		return false
	for key: String in ["deny_terms","deny_patterns","fixed_character_terms"]:
		if not strings(rules.safety[key]) or not unique(rules.safety[key]):
			return false
	for pattern: String in rules.safety.deny_patterns:
		var regex := RegEx.new()
		if regex.compile("(?i)"+pattern,false)!=OK:
			return false
	if not shape(rules.copy,COPY):
		return false
	for key: String in COPY:
		if key in ["reactions","moods","angle"]:
			continue
		if not safe_text(rules.copy[key],"evidence",rules):
			return false
	if not rules.copy.reactions is Array or rules.copy.reactions.size()!=rules.counts.maximum_advice or not rules.copy.reactions.all(func(v:Variant)->bool:return safe_text(v,"reaction",rules)):
		return false
	if not rules.copy.moods is Array or rules.copy.moods.size()!=rules.counts.maximum_advice or not rules.copy.moods.all(func(v:Variant)->bool:return v in rules.safety.allowed_moods):
		return false
	if not strings(rules.copy.angle) or rules.copy.angle.size()!=2 or not rules.copy.angle.all(func(v:Variant)->bool:return safe_text(v,"evidence",rules)):
		return false
	var event: Variant = rules.event_blueprint
	if not shape(event,["version","minute_of_day","feedback_delay","report_delay","prediction_window","advice_keys","outcome_ids","expected","conditions","effects"]):
		return false
	if not integer(event.version,1,1) or not integer(event.minute_of_day,0,1439) or not integer(event.feedback_delay,0,10080) or not integer(event.report_delay,0,10080) or not integer(event.prediction_window,0,10080) or event.effects!=[]:
		return false
	for key: String in ["advice_keys","outcome_ids"]:
		if not strings(event[key]) or event[key].size()!=rules.counts.maximum_advice or not unique(event[key]) or not event[key].all(func(v:Variant)->bool:return id(v,rules)):
			return false
	if not event.expected is Array or event.expected.size()!=rules.counts.maximum_advice or not event.expected.all(func(v:Variant)->bool:return v in ["met","missed"]) or event.conditions!=["if_verify","if_ask","always"]:
		return false
	if not shape(rules.profiles,TOPICS) or not rules.fallbacks is Array or rules.fallbacks.size()!=TOPICS.size() or not decks.get("tarot") is Array:
		return false
	var cards := {}
	for card: Variant in decks.tarot:
		if not card is Dictionary or not card.get("id") is String or cards.has(card.id):
			return false
		cards[card.id] = true
	var seen := {}
	for entry: Variant in rules.fallbacks:
		if not shape(entry,["id","kind","path"]) or entry.kind not in TOPICS or entry.id!="fallback_"+str(entry.kind) or entry.path!="fallback/"+str(entry.id)+".json" or seen.has(entry.kind):
			return false
		seen[entry.kind] = true
		if not _profile_valid(rules.profiles[entry.kind],rules,cards):
			return false
	return true

static func _profile_valid(profile: Variant, rules: Dictionary, cards: Dictionary) -> bool:
	if not shape(profile,["title","question","facts","statements","statement_slots","buttons","advice","reports","cards"]) or not safe_text(profile.title,"title",rules) or not safe_text(profile.question,"question",rules):
		return false
	if not profile.facts is Array or profile.facts.size()!=rules.counts.slots or not profile.statements is Array or profile.statements.size()!=rules.counts.slots:
		return false
	var facts := {}
	for fact: Variant in profile.facts:
		if not shape(fact,["id","slot_title","source","default","options"]) or not id(fact.id,rules) or facts.has(fact.id) or not fact.options is Dictionary or fact.options.size() not in [3,4] or not fact.default is String or not fact.options.has(fact.default):
			return false
		if not safe_text(fact.slot_title,"slot_title",rules) or not safe_text(fact.source,"source",rules):
			return false
		facts[fact.id] = true
		var labels := {}
		for key: Variant in fact.options:
			var option: Variant = fact.options[key]
			if not id(key,rules) or not shape(option,["label","assertion"]) or not safe_text(option.label,"answer",rules) or not safe_text(option.assertion,"fact",rules) or labels.has(option.label):
				return false
			labels[option.label] = true
	if not profile.statement_slots is Array or profile.statement_slots.size()!=profile.statements.size():
		return false
	for links: Variant in profile.statement_slots:
		if not strings(links) or not unique(links) or not links.all(func(key:Variant)->bool:return facts.has(key)):
			return false
	if not profile.cards is Array or profile.cards.size()!=rules.counts.cards:
		return false
	var seen := {}
	for card: Variant in profile.cards:
		if not shape(card,SHAPES.card) or not cards.has(card.deck_id) or seen.has(card.deck_id) or not facts.has(card.slot_id) or not safe_text(card.text,"card",rules):
			return false
		seen[card.deck_id] = true
	if not profile.buttons is Array or profile.buttons.size()!=rules.counts.rounds:
		return false
	for row: Variant in profile.buttons:
		if not row is Array or row.size()!=rules.counts.questions_per_round or not row.all(func(v:Variant)->bool:return safe_text(v,"button",rules)):
			return false
	for key: String in ["statements","advice","reports"]:
		if not profile[key] is Array or profile[key].size()!=rules.counts.maximum_advice or not profile[key].all(func(v:Variant)->bool:return safe_text(v,"evidence",rules)):
			return false
	return true

## Called only after validate_config. Arbitrary alternative truths are v2 work.
static func materialize(kind: String, rules: Dictionary, requested: Dictionary = {}) -> Dictionary:
	if kind not in rules.topics:
		return {}
	var profile: Dictionary = rules.profiles[kind]
	var values := requested.duplicate(true)
	if values.is_empty():
		for fact: Dictionary in profile.facts:
			values[fact.id] = fact.default
	var fact_ids: Array = profile.facts.map(func(fact:Dictionary)->String:return fact.id)
	if not shape(values,fact_ids):
		return {}
	for fact: Dictionary in profile.facts:
		if not values[fact.id] is String or values[fact.id]!=fact.default:
			return {}
	var evidence := []
	var truth := {}
	for fact: Dictionary in profile.facts:
		var assertion: String = fact.options[values[fact.id]].assertion
		truth[fact.id] = {"value":values[fact.id],"text":assertion,"requires_clue":"clue_"+str(fact.id)}
		evidence.append({"id":"fact_"+str(fact.id),"text":assertion,"type":"fact","source":fact.source,"slot_ids":[fact.id],"legacy_clue_ids":["clue_"+str(fact.id)]})
	for index: int in range(profile.statements.size()):
		var misleading: bool = index==profile.statements.size()-1
		evidence.append({"id":"statement_"+str(index),"text":profile.statements[index],"type":"misleading" if misleading else "testimony","source":rules.copy.misleading_source if misleading else rules.copy.statement_source,"slot_ids":profile.statement_slots[index].duplicate(true)})
	var by_id := {}
	for entry: Dictionary in evidence:
		by_id[entry.id] = entry
	var slots := []
	var questions := []
	var bindings := []
	var proofs := []
	for index: int in range(profile.facts.size()):
		var fact: Dictionary = profile.facts[index]
		var answers := []
		for key: String in fact.options:
			answers.append({"id":key,"text":fact.options[key].label})
		var unlocked := []
		for entry: Dictionary in evidence:
			if fact.id in entry.slot_ids:
				unlocked.append(entry.id)
		slots.append({"id":fact.id,"title":fact.slot_title,"answers":answers,"correct_answer":values[fact.id],"unlock_evidence":unlocked})
		var row := []
		for choice: int in range(profile.buttons[index].size()):
			var materials := ["fact_"+str(fact.id)]
			if choice!=0:
				materials.append("statement_"+str((index+choice-1)%profile.statements.size()))
			var texts: PackedStringArray = []
			for material: String in materials:
				texts.append(by_id[material].text)
			var question_id := "question_"+str(index)+"_"+str(choice)
			row.append({"id":question_id,"text":profile.buttons[index][choice],"answer":str(rules.copy.answer_prefix)+" ".join(texts),"evidence_ids":materials,"requires_familiarity":0,"legacy_topic_id":question_id})
		questions.append(row)
		bindings.append({"fact_key":fact.id,"evidence_id":"fact_"+str(fact.id),"value":values[fact.id]})
		proofs.append({"slot_id":fact.id,"answer_id":values[fact.id],"rule":"fact_equals","premises":[fact.id]})
	var advice := []
	var blueprint: Dictionary = rules.event_blueprint
	for index: int in range(blueprint.advice_keys.size()):
		var prediction: String = rules.copy.prediction_text_missed if index==blueprint.advice_keys.size()-1 else rules.copy.prediction_text_met
		var key: String = blueprint.advice_keys[index]
		advice.append({"id":key,"text":profile.advice[index],"requires_deductions":fact_ids.duplicate(),"legacy_advice_key":key,"reaction":rules.copy.reactions[index],"mood":rules.copy.moods[index],"prediction":{"text":prediction,"condition":blueprint.conditions[index],"expected":blueprint.expected[index],"window_after_due_minutes":blueprint.prediction_window}})
	return {"protocol_version":rules.protocol_version,"template_id":"fallback_"+kind,"kind":kind,"definition":{"id":"fallback_"+kind,"version":rules.protocol_version,"title":profile.title,"question":profile.question,"truth":truth,"deduction_slots":slots,"questions":questions,"evidence":evidence,"cards":profile.cards.duplicate(true),"advice":advice,"outcomes":_event(profile,values,rules)},"support":{"facts":bindings,"proofs":proofs}}

static func _event(profile: Dictionary, values: Dictionary, rules: Dictionary) -> Dictionary:
	var blueprint: Dictionary = rules.event_blueprint
	var options := []
	var advice := {}
	var outcomes := {}
	var facts := {}
	for fact: Dictionary in profile.facts:
		facts[fact.id] = {"values":fact.options.keys(),"default":values[fact.id]}
	for index: int in range(blueprint.advice_keys.size()):
		var key: String = blueprint.advice_keys[index]
		options.append({"key":key,"label":profile.advice[index]})
		advice[key] = {"text":profile.advice[index]}
		outcomes[blueprint.outcome_ids[index]] = {"actual_action":profile.advice[index],"outcome":blueprint.expected[index],"evidence":"sufficient","feedback":"delayed","delay_minutes":blueprint.report_delay,"text":profile.reports[index],"effects":[]}
	return {"version":blueprint.version,"subject_id":rules.protocol.owner_placeholder,"target_name":profile.question,"minute_of_day":blueprint.minute_of_day,"feedback_delay":blueprint.feedback_delay,"world_facts":facts,"branch_ids":[],"item_effect_ids":[],"item_effect":{},"advice_options":options,"advice":advice,"prediction_conditions":{"always":{"label":rules.copy.no_condition},"if_verify":{"label":rules.copy.condition_verify,"outcomes":[blueprint.outcome_ids[0]]},"if_ask":{"label":rules.copy.condition_ask,"outcomes":[blueprint.outcome_ids[1]]}},"prediction_labels":{"met":rules.copy.prediction_met,"missed":rules.copy.prediction_missed},"rules":[{"when":{"advice":blueprint.advice_keys[0],"accepted":true},"outcome":blueprint.outcome_ids[0]},{"when":{"advice":blueprint.advice_keys[1],"accepted":true},"outcome":blueprint.outcome_ids[1]},{"when":{},"outcome":blueprint.outcome_ids[2]}],"outcomes":outcomes,"feedback_effects":blueprint.effects.duplicate(true)}

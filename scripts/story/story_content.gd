extends RefCounted
## Authored content only. No save mutation, RNG, model requests or runtime state.
const Schema = preload("res://scripts/divination/case_schema.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const RULES_PATH := "res://data/story/rules.json"
const NPCS_PATH := "res://data/story/npcs.json"
const NOTES_PATH := "res://data/story/notes.json"
const CASE_IDS := ["fixed_invitation","fixed_bread","fixed_key","fixed_music_box","fixed_last_pages"]
const THEMES := ["contact","relation","timing","place","evidence","choice","action","boundary","obstacle"]
const COPY_KEYS := ["invalid_config","invalid_state","choice_unavailable","prelude_required","choice_saved","assembly_retry","notes_title","note_locked","ending_pending","ending_complete","story_started","rainy","rainy_arrival","ending_title","waiting_status","complete_status"]

static func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null

static func _text(value: Variant, maximum: int = 2000) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= maximum

static func _id(value: Variant) -> bool:
	return _text(value,80) and value.is_valid_identifier() and value == value.to_lower()

static func _int(value: Variant, low: int = 0, high: int = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high

static func _ids(value: Variant, allow_empty: bool = false) -> bool:
	if not value is Array or (value.is_empty() and not allow_empty):
		return false
	var seen := {}
	for id: Variant in value:
		if not _id(id) or seen.has(id):
			return false
		seen[id] = true
	return true

static func load_rules() -> Dictionary:
	var value: Variant = _read(RULES_PATH)
	return value if validate_rules(value) else {}

static func load_npcs() -> Dictionary:
	var value: Variant = _read(NPCS_PATH)
	return value.npcs if validate_npcs(value) else {}

static func load_notes() -> Dictionary:
	var value: Variant = _read(NOTES_PATH)
	return value.pages if validate_notes(value) else {}

static func load_config() -> Dictionary:
	var rules := load_rules()
	var npcs := load_npcs()
	var notes := load_notes()
	if rules.is_empty() or npcs.is_empty() or notes.is_empty() or not notes.has(rules.initial_note_id):
		return {}
	for id: String in CASE_IDS:
		var row: Dictionary = rules.cases[id]
		if not npcs.has(row.npc_id) or npcs[row.npc_id].case_id != id or (not str(row.note_id).is_empty() and not notes.has(row.note_id)):
			return {}
		for followup_id: String in row.get("followup_npc_ids",[]):
			if not npcs.has(followup_id) or not npcs[followup_id].ordinary_followup:
				return {}
	for row: Dictionary in rules.epilogues:
		if not npcs.has(row.npc_id):
			return {}
	if not notes.has(rules.final_prelude.retrieve.note_id) or not notes.has(rules.ending.note_id) or not npcs.has(rules.final_prelude.repair.npc_id):
		return {}
	for branches: Dictionary in rules.consequences.values():
		for row: Dictionary in branches.values():
			for id: String in row.trust_targets:
				if not npcs.has(id):
					return {}
	return {"version":1,"rules":rules,"npcs":npcs,"notes":notes}

static func npc_descriptor(npc_id: String) -> Dictionary:
	return load_npcs().get(npc_id,{}).duplicate(true)

static func validate_npcs(value: Variant) -> bool:
	if not value is Dictionary or not _int(value.get("version"),1,1) or not value.get("npcs") is Dictionary or value.npcs.is_empty():
		return false
	var parts := Appearance.load_config()
	if parts.is_empty():
		return false
	for id: Variant in value.npcs:
		var row: Variant = value.npcs[id]
		if not _id(id) or not row is Dictionary or row.get("npc_id") != id or not _int(row.get("age"),1,120) or not _int(row.get("coins"),0,10000):
			return false
		for key: String in ["name","role","mbti","cultural_origin","personality","speech_style","opening","followup"]:
			if not _text(row.get(key)):
				return false
		if not row.get("case_id") is String or (not row.case_id.is_empty() and row.case_id not in CASE_IDS) or not row.get("ordinary_followup") is bool:
			return false
		if not row.get("appearance") is Dictionary or row.appearance.has("preset") or not Appearance.selection_valid(row.appearance,parts):
			return false
		if row.has("preserve_existing_appearance") and not row.preserve_existing_appearance is bool:
			return false
	return value.npcs.has("npc_lin") and value.npcs.has("npc_tao_shuning") and value.npcs.npc_tao_shuning.ordinary_followup

static func validate_notes(value: Variant) -> bool:
	if not value is Dictionary or not _int(value.get("version"),1,1) or not value.get("pages") is Dictionary or value.pages.size()!=4:
		return false
	var seen := {}
	for id: Variant in value.pages:
		var row: Variant = value.pages[id]
		if not _id(id) or not row is Dictionary or not _int(row.get("page_number"),1,4) or seen.has(int(row.page_number)) or id != "note_"+str(int(row.page_number)):
			return false
		if not _text(row.get("title")) or not _text(row.get("text")) or not row.get("unlock_case_id") is String or (not row.unlock_case_id.is_empty() and row.unlock_case_id not in CASE_IDS) or not row.get("alternative_source") is String:
			return false
		seen[int(row.page_number)] = true
	return true

static func validate_rules(value: Variant) -> bool:
	if not value is Dictionary or not _int(value.get("version"),1,1) or not value.get("enabled") is bool or value.get("case_order") != CASE_IDS or not value.get("cases") is Dictionary or value.cases.size()!=CASE_IDS.size():
		return false
	if not _id(value.get("initial_note_id")) or not _int(value.get("minutes_per_day"),1,2147483647):
		return false
	for id: String in CASE_IDS:
		var row: Variant = value.cases.get(id)
		if not row is Dictionary or not _id(row.get("npc_id")) or not _int(row.get("min_day"),1,10000) or not _int(row.get("preferred_until"),0,10000) or (row.preferred_until>0 and row.preferred_until<row.min_day) or not _int(row.get("minute"),0,int(value.minutes_per_day)-1):
			return false
		if not _ids(row.get("requires_closed"),true) or not row.requires_closed.all(func(required: String)->bool: return required in CASE_IDS and required!=id) or not row.get("weather") is String or not row.get("note_id") is String:
			return false
		if not _id(row.get("best_advice_id")) or not _id(row.get("worst_advice_id")):
			return false
		if not _ids(row.get("followup_npc_ids",[]),true):
			return false
		if row.has("fragment") and (not row.fragment is Dictionary or not _id(row.fragment.get("id")) or not _text(row.fragment.get("text"))):
			return false
		var deferred: Variant = row.get("defer_disclosure_advice_ids",[])
		if not _ids(deferred,true):
			return false
		if not deferred.is_empty():
			var definition: Variant = _read("res://data/cases/"+id+".json")
			if not definition is Dictionary or not definition.get("advice") is Array:
				return false
			for advice_id: String in deferred:
				if not definition.advice.any(func(advice: Variant)->bool: return advice is Dictionary and advice.get("id")==advice_id):
					return false
	for key: String in ["invitation_fragment","final_prelude","ending","consequences","g3_copy","copy"]:
		if not value.get(key) is Dictionary:
			return false
	var fragment: Dictionary = value.invitation_fragment
	if not _id(fragment.get("id")) or fragment.get("case_id") not in CASE_IDS or not _text(fragment.get("text")):
		return false
	var prelude: Dictionary = value.final_prelude
	for key: String in ["retrieve","repair","assembly"]:
		if not prelude.get(key) is Dictionary or not _id(prelude[key].get("id")) or not _text(prelude[key].get("text")):
			return false
	for key: String in ["choice_id","note_id"]:
		if not _id(prelude.retrieve.get(key)):
			return false
	for key: String in ["choice_text","disclosure"]:
		if not _text(prelude.retrieve.get(key)):
			return false
	for key: String in ["npc_id","lin_choice_id","self_choice_id"]:
		if not _id(prelude.repair.get(key)):
			return false
	for key: String in ["lin_choice_text","self_choice_text","lin_disclosure","self_disclosure"]:
		if not _text(prelude.repair.get(key)):
			return false
	if not _int(prelude.repair.get("min_trust"),0,100) or not _int(prelude.assembly.get("energy"),0,100) or not _int(prelude.assembly.get("minutes"),0,int(value.minutes_per_day)-1) or not prelude.assembly.get("choices") is Array or prelude.assembly.choices.size()<2:
		return false
	var choices := {}
	for choice: Variant in prelude.assembly.choices:
		if not choice is Dictionary or not _id(choice.get("id")) or choices.has(choice.id) or not _text(choice.get("text")):
			return false
		choices[choice.id] = true
	if not choices.has(prelude.assembly.get("correct_choice_id")) or not _text(prelude.assembly.get("retry_text")) or not _text(prelude.assembly.get("complete_text")):
		return false
	for key: String in ["self_evidence_text","self_evidence_source","arrival_line"]:
		if not _text(prelude.get(key)):
			return false
	if not _id(prelude.get("self_evidence_id")):
		return false
	var ending: Dictionary = value.ending
	if ending.get("case_id") not in CASE_IDS or not _id(ending.get("note_id")) or not _text(ending.get("title")) or not ending.get("routes") is Dictionary or not ending.get("route_by_outcome") is Dictionary or not ending.get("delay_by_advice") is Dictionary or ending.routes.is_empty():
		return false
	for id: Variant in ending.routes:
		var route: Variant = ending.routes[id]
		if not _id(id) or not route is Dictionary or not _text(route.get("text")) or not route.get("title") is String or not route.get("waiting_text") is String or not _int(ending.delay_by_advice.get(id),0,10080):
			return false
	for id: Variant in ending.route_by_outcome:
		if not _id(id) or not ending.routes.has(ending.route_by_outcome[id]):
			return false
	for case_id: Variant in value.consequences:
		if case_id not in CASE_IDS or not value.consequences[case_id] is Dictionary:
			return false
		for advice_id: Variant in value.consequences[case_id]:
			var row: Variant = value.consequences[case_id][advice_id]
			if not _id(advice_id) or not row is Dictionary or not _int(row.get("elder_lead_delay_days"),0,10000) or not _ids(row.get("trust_targets"),true) or not _int(row.get("trust_delta"),-100,100):
				return false
	if not value.get("epilogues") is Array or value.epilogues.size()!=5:
		return false
	var seen := {}
	for row: Variant in value.epilogues:
		if not row is Dictionary or not _id(row.get("id")) or seen.has(row.id) or not _id(row.get("npc_id")) or not _text(row.get("text")):
			return false
		seen[row.id] = true
	for key: String in COPY_KEYS:
		if not _text(value.copy.get(key)):
			return false
	if not _text(value.g3_copy.get("missing")) or not _text(value.g3_copy.get("boundary")) or not value.g3_copy.get("angles") is Dictionary:
		return false
	for theme: String in THEMES:
		var pair: Variant = value.g3_copy.angles.get(theme)
		if not pair is Array or pair.size()!=2 or not pair.all(func(text: Variant)->bool: return _text(text)):
			return false
	return true

static func _put(section: Dictionary, id: String, value: Dictionary) -> bool:
	if section.has(id) and section[id]!=value:
		return false
	section[id] = value
	return true

static func install(catalog: Dictionary) -> Dictionary:
	var config := load_config()
	var index: Variant = _read(Schema.INDEX_PATH)
	if config.is_empty() or not Schema.validate_index(index):
		return {}
	var result := catalog.duplicate(true)
	for key: String in ["clues","cases","guests","topic_index","decks"]:
		if not result.get(key) is Dictionary:
			return {}
	if not result.get("topics") is Array:
		return {}
	var authored := {}
	for entry: Dictionary in index.definitions:
		var definition: Variant = _read(entry.path)
		if not definition is Dictionary or definition.get("id")!=entry.id:
			return {}
		authored[entry.id] = definition
		if entry.id == "fixed_invitation":
			continue
		if entry.id not in config.rules.cases or not definition.get("truth") is Dictionary or not definition.get("evidence") is Array or not definition.get("questions") is Array:
			return {}
		for fact: Variant in definition.truth.values():
			if not fact is Dictionary or not _id(fact.get("requires_clue")) or not _text(fact.get("text")):
				return {}
			if not _put(result.clues,fact.requires_clue,{"title":str(definition.get("title","")),"text":fact.text,"story_definition_id":entry.id,"private":true}):
				return {}
		for material: Variant in definition.evidence:
			if not material is Dictionary or not _id(material.get("id")) or not _text(material.get("text")):
				return {}
			for clue_id: Variant in material.get("legacy_clue_ids",[]):
				if not _id(clue_id) or not _put(result.clues,clue_id,{"title":material.get("source",""),"text":material.text,"story_definition_id":entry.id}):
					return {}
		for round: Variant in definition.questions:
			if not round is Array:
				return {}
			for question: Variant in round:
				if not question is Dictionary or not _id(question.get("id")) or not question.get("evidence_ids") is Array:
					return {}
				var topic := _topic(definition,question)
				if not _put(result.topic_index,topic.topic_id,topic):
					return {}
				if not result.topics.any(func(row: Dictionary)->bool: return row.topic_id==topic.topic_id):
					result.topics.append(topic)
	var definitions := Schema.load_all(result)
	if definitions.size()!=CASE_IDS.size():
		return {}
	for id: String in CASE_IDS:
		if not definitions.has(id):
			return {}
		var definition: Dictionary = definitions[id]
		var rule: Dictionary = config.rules.cases[id]
		for key: String in ["best_advice_id","worst_advice_id"]:
			if not definition.advice.any(func(row: Dictionary)->bool: return row.id==rule[key]):
				return {}
		if id == "fixed_invitation":
			continue
		var template := Schema.to_g3_template(definition,result)
		var topics: Array = []
		for round: Array in definition.questions:
			for question: Dictionary in round:
				topics.append(_topic_id(definition.id,question.id))
		var references := {}
		for material: Dictionary in definition.evidence:
			for clue_id: String in material.get("legacy_clue_ids",[]):
				references[clue_id] = material.text
		var public_question := {"label":definition.question,"frame":definition.question,"missing":config.rules.g3_copy.missing,"boundary":config.rules.g3_copy.boundary,"angles":config.rules.g3_copy.angles.duplicate(true),"references":references}
		template.merge({"topic_ids":topics,"method_ids":["tarot","lenormand","plum","yijing","xiaoliu"],"questions":{"story":public_question},"default_question":"story","story_definition_id":id})
		if not _put(result.cases,Schema.g3_case_id(definition),template):
			return {}
	for id: String in config.npcs:
		if id == "npc_lin":
			continue
		var npc: Dictionary = config.npcs[id]
		var guest := {"name":npc.name,"role":npc.role,"opening":npc.opening,"followup":npc.followup,"story_definition_id":npc.case_id,"story_guest":true}
		if not _put(result.guests,id,guest):
			return {}
	return result

static func _topic_id(case_id: String, question_id: String) -> String:
	return "story_"+case_id+"_"+question_id

static func _topic(definition: Dictionary, question: Dictionary) -> Dictionary:
	var clues: Array = []
	for material: Dictionary in definition.evidence:
		if material.id in question.evidence_ids:
			for clue_id: String in material.get("legacy_clue_ids",[]):
				if clue_id not in clues:
					clues.append(clue_id)
	return {"topic_id":_topic_id(definition.id,question.id),"label":question.text,"reply_text":question.answer,"keywords":[question.text],"clue_ids":clues,"default_mood":"neutral","story_definition_id":definition.id}

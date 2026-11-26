extends RefCounted
## Candidate-only learning leaf. Strict standalone curriculum JSON; no game save schema constant is selected here.
const PATH := "res://data/learning/courses.json"
const METHODS := ["tarot","lenormand","plum","yijing","xiaoliu","astrology","bazi","ziwei","past"]
const EFFECTS := ["observe","extra_card","eliminate","preview","free_question","key_slot","panel"]
const COPY := ["mentor","fiction_notice","mastered","legacy_mastered","initial_basic","book","tuition","practice","retry","cap_notice"]

static func keys(value: Variant, expected: Array) -> bool:
	return value is Dictionary and value.size()==expected.size() and expected.all(func(key:Variant)->bool:return value.has(key))

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value==floor(float(value)) and value>=low and value<=high

static func text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length()<=2000

static func identifier(value: Variant) -> bool:
	return text(value) and value.length()<=80 and value.is_valid_identifier() and value==value.to_lower()

static func action_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>128: return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true

static func strings(value: Variant, allow_empty: bool = false) -> bool:
	if not value is Array or (value.is_empty() and not allow_empty): return false
	var seen := {}
	for entry: Variant in value:
		if not identifier(entry) or seen.has(entry): return false
		seen[entry]=true
	return true

static func read_json(path: String) -> Variant:
	return _normalize(JSON.parse_string(FileAccess.get_file_as_string(path))) if path.ends_with(".json") and FileAccess.file_exists(path) else null

static func load_config(path: String = PATH) -> Dictionary:
	var value: Variant = read_json(path)
	return value if config_valid(value) else {}

static func config_valid(value: Variant) -> bool:
	if not keys(value,["version","debug_instant_learning","initial_basic_methods","required_practices","level_thresholds","practice","cap_policy","copy","methods","lessons","ui"]):
		return false
	if value.version is bool or value.version!=1 or not value.debug_instant_learning is bool or value.initial_basic_methods!=["tarot"] or not integer(value.required_practices,3,3):
		return false
	if not value.level_thresholds is Array or value.level_thresholds.size()!=3 or value.level_thresholds[0]!=0:
		return false
	for index: int in range(3):
		if not integer(value.level_thresholds[index],0,2147483647) or (index>0 and value.level_thresholds[index]<=value.level_thresholds[index-1]):
			return false
	if not keys(value.practice,["energy","world_minutes","maximum_steps","minimum_correct_by_stage","book_consumed","namespace","charges_at","panel_examples"]) or not integer(value.practice.energy,0,0) or not integer(value.practice.world_minutes,0,0) or not integer(value.practice.maximum_steps,13,10000) or value.practice.namespace!="fiction" or not value.practice.book_consumed is bool or value.practice.book_consumed!=false or value.practice.charges_at!="before_first_practice":
		return false
	if not keys(value.practice.panel_examples,["chart","quoted_at","parameter","options","past_profile"]): return false
	if not value.practice.minimum_correct_by_stage is Array or value.practice.minimum_correct_by_stage.size()!=3:
		return false
	for required: Variant in value.practice.minimum_correct_by_stage:
		if not integer(required,1,3): return false
	if not keys(value.cap_policy,["status","card_count","base_cards","extra_question_cap","astrology_hint_cap","preview_targets","elimination_targets"]):
		return false
	if value.cap_policy.status!="bounded_by_case_capacity" or not integer(value.cap_policy.card_count,5,5) or not integer(value.cap_policy.base_cards,3,3) or not integer(value.cap_policy.extra_question_cap,3,3) or not integer(value.cap_policy.astrology_hint_cap,3,3) or value.cap_policy.preview_targets!="distinct_advice" or value.cap_policy.elimination_targets!="distinct_slots":
		return false
	if not keys(value.copy,COPY) or not value.copy.values().all(text) or not keys(value.methods,METHODS) or not value.lessons is Dictionary or value.lessons.size()!=METHODS.size()*int(value.required_practices):
		return false
	var seen := {}
	for id: String in METHODS:
		var row: Variant = value.methods[id]
		if not keys(row,["title","prerequisite","book_id","book_price","tuition","practice_ids","gate_case","effect","uses_by_level"]): return false
		if not text(row.title) or row.book_id!="intro_"+id or not integer(row.book_price,1,100000) or not integer(row.tuition,0,100000) or not row.prerequisite is String or (not row.prerequisite.is_empty() and (row.prerequisite==id or row.prerequisite not in METHODS)) or row.effect not in EFFECTS:
			return false
		if row.gate_case!=("fixed_last_pages" if id in ["bazi","ziwei","past"] else "") or not strings(row.practice_ids) or row.practice_ids.size()!=int(value.required_practices) or (not row.uses_by_level is Array or row.uses_by_level.size()!=3 or not [0,1,2].all(func(index:int)->bool:return integer(row.uses_by_level[index],index+1,index+1))): return false
		for stage: int in range(row.practice_ids.size()):
			var case_id: String = row.practice_ids[stage]
			if case_id!="practice_"+id+"_"+str(stage+1) or seen.has(case_id): return false
			seen[case_id] = true
			var lesson: Variant = value.lessons.get(case_id)
			if not keys(lesson,["method_id","stage","title","mentor_intro","mentor_success","mentor_retry","teaching_goal","minimum_correct","teaching_requirements"]) or lesson.method_id!=id or not integer(lesson.stage,stage+1,stage+1) or not integer(lesson.minimum_correct,1,3) or lesson.minimum_correct!=value.practice.minimum_correct_by_stage[stage]: return false
			if not keys(lesson.teaching_requirements,["effect","minimum_effect_uses","paired_evidence_slots"]) or lesson.teaching_requirements.effect != row.effect or not integer(lesson.teaching_requirements.minimum_effect_uses,0,3) or not integer(lesson.teaching_requirements.paired_evidence_slots,0,2): return false
			for key: String in ["title","mentor_intro","mentor_success","mentor_retry","teaching_goal"]:
				if not text(lesson[key]): return false
		# A prerequisite cycle must never make an entire course unreachable.
		var chain := {}
		var current := id
		while not current.is_empty():
			if chain.has(current): return false
			chain[current]=true
			var node: Variant = value.methods.get(current)
			if not node is Dictionary or not node.get("prerequisite") is String or (not str(node.prerequisite).is_empty() and not value.methods.has(node.prerequisite)): return false
			current = str(node.prerequisite)
	return seen.size()==value.lessons.size() and _ui_valid(value.ui)

static func _ui_valid(ui: Variant) -> bool:
	if not keys(ui,["layout","copy","tones"]) or not keys(ui.layout,["width","height","padding","gap","font","row_height","title_width","cell_width","stamp_size"]): return false
	for item: Variant in ui.layout.values():
		if not integer(item,1,10000): return false
	if not keys(ui.tones,["favorable","neutral","difficult"]) or not ui.tones.values().all(text): return false
	return ui.copy is Dictionary and keys(ui.copy,["title","book_buy","tuition_pay","practice_start","practice_resume","practice_retry","source_legacy","source_debug","progress","yes","no","level","basic","locked","late_gate","active_visit","invalid","saved","funds_low","already","missing_book","missing_fee","practice_busy","practice_saved","close","preview","key_slot","panel","preview_result","key_result","hint_missing","debug_disabled","effect_used","completed","requirements","method_tools","key_label","buy_book_short","practice_count","panel_close"]) and ui.copy.values().all(text)


static func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: String in value: result[key] = _normalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child: Variant in value: result.append(_normalize(child))
		return result
	return int(value) if value is float and is_finite(value) and value == floor(value) else value

static func advanced_allowed(state: Dictionary, method_id: String) -> bool:
	return method_id not in ["bazi","ziwei","past"] or state.get("story",{}).get("completions",{}).has("fixed_last_pages")

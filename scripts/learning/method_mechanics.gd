extends RefCounted
## Trusted capability snapshot and bounded, observable effects. No world writes.
const Rules = preload("res://scripts/learning/learning_rules.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const Kernel = preload("res://scripts/divination/emergent_case_kernel_v1.gd")
const Cards = preload("res://scripts/divination/oracle_cards.gd")
static var _fallback_bundle: Dictionary = {}
static var _hints: Dictionary = {}
const EFFECT_METHOD := {"extra_card":"lenormand","eliminate":"plum","preview":"yijing","free_question":"xiaoliu","key_slot":"astrology"}

static func level(state: Dictionary, id: String, config: Dictionary) -> int:
	if str(state.get("save_id","")).begins_with("fiction_"):
		return clampi(int(state.get("fiction_capabilities",{}).get(id,0)),0,3)
	var learning: Variant = state.get("learning",{})
	if not learning is Dictionary: return 0
	var progress: Variant = learning.get("progress",{})
	if not progress is Dictionary or not progress.get("courses") is Dictionary: return 0
	var course: Variant = progress.courses.get(id,{})
	if not course is Dictionary or course.get("origin","unlearned") == "unlearned" or not course.get("use_refs") is Array: return 0
	var value := 1
	for index: int in range(config.level_thresholds.size()):
		if course.use_refs.size() >= int(config.level_thresholds[index]): value = index+1
	return value

static func budgets(levels: Dictionary, definition: Dictionary, config: Dictionary) -> Dictionary:
	var result := {}
	for id: String in Rules.METHODS:
		var rank := int(levels.get(id,0))
		var count := int(config.methods[id].uses_by_level[rank-1]) if rank > 0 else 0
		if id == "lenormand": count = mini(count,maxi(0,definition.cards.size()-int(config.cap_policy.base_cards)))
		if id == "yijing": count = mini(count,definition.advice.size())
		if id in ["plum","astrology"]: count = mini(count,definition.deduction_slots.size())
		result[id] = count
	return result

static func create(state: Dictionary, definition: Dictionary) -> Dictionary:
	var config := Rules.load_config()
	if config.is_empty(): return {}
	var levels := {}
	for id: String in Rules.METHODS: levels[id] = level(state,id,config)
	return {"version":1,"curriculum_version":config.version,"levels":levels,"budgets":budgets(levels,definition,config),"uses":[],"extra_question_ids":[],"previews":{},"key_slots":[],"panels":{}}

static func uses(board: Dictionary, method: String) -> int:
	var mechanic: Dictionary = board.get("mechanics",{})
	var rows: Array = mechanic.get("uses",[])
	return rows.filter(func(row: Dictionary) -> bool: return row.method_id == method).size()

static func budget(board: Dictionary, method: String, fallback: int = 0) -> int:
	return int(board.get("mechanics",{}).get("budgets",{}).get(method,fallback))

static func record(board: Dictionary, action: Dictionary, method: String, target: String, energy_saved: int = 0) -> Dictionary:
	if not board.has("mechanics") or int(board.mechanics.levels.get(method,0)) <= 0: return {}
	var config := Rules.load_config()
	var row := {"action_id":str(action.action_id),"method_id":method,"effect":str(config.methods[method].effect),"target_id":target,"energy_saved":energy_saved}
	if board.mechanics.uses.any(func(previous: Dictionary) -> bool: return previous.method_id == method and previous.target_id == target): return {}
	board.mechanics.uses.append(row)
	return row.duplicate(true)

static func annotation(definition: Dictionary, state: Dictionary = {}) -> Dictionary:
	if _hints.is_empty():
		var raw: Variant = Rules.read_json("res://data/learning/board_hints_v1.json")
		if not hint_config_valid(raw): return {}
		_hints = raw
	var data: Dictionary = _hints
	var row: Variant = data.definitions.get(definition.id,{})
	if row.is_empty(): row = _fallback_annotation(definition,state,data)
	return row if _annotation_valid(row,definition) else {}

static func _annotation_valid(row: Variant, definition: Dictionary) -> bool:
	if not Rules.keys(row,["definition_hash","advice_tones","critical_slots"]) or row.definition_hash != Schema.definition_hash(definition) or not row.advice_tones is Dictionary or not row.critical_slots is Array: return false
	var advice_ids: Array = definition.advice.map(func(advice: Dictionary) -> String: return advice.id)
	if not Rules.keys(row.advice_tones,advice_ids) or not row.advice_tones.values().all(func(tone: Variant) -> bool: return tone in ["favorable","neutral","difficult"]): return false
	var expected: Array = definition.deduction_slots.map(func(slot: Dictionary) -> String: return slot.id)
	var actual: Array = row.critical_slots.duplicate()
	expected.sort(); actual.sort()
	return expected == actual

static func hint_config_valid(data: Variant) -> bool:
	if not Rules.keys(data,["version","definitions","fallbacks"]) or data.version != 1 or not data.definitions is Dictionary or not data.fallbacks is Dictionary: return false
	for id: Variant in data.definitions:
		var row: Variant = data.definitions[id]
		if not Rules.identifier(id) or not Rules.keys(row,["definition_hash","advice_tones","critical_slots"]) or not row.definition_hash is String or row.definition_hash.length() != 64 or not row.definition_hash.is_valid_hex_number(false) or not row.advice_tones is Dictionary or not Rules.strings(row.critical_slots): return false
		if not row.advice_tones.values().all(func(tone: Variant) -> bool: return tone in ["favorable","neutral","difficult"]): return false
	for id: Variant in data.fallbacks:
		var row: Variant = data.fallbacks[id]
		if not Rules.identifier(id) or not Rules.keys(row,["advice_tones","critical_slots"]) or not row.advice_tones is Dictionary or not Rules.strings(row.critical_slots): return false
		if not row.advice_tones.values().all(func(tone: Variant) -> bool: return tone in ["favorable","neutral","difficult"]): return false
	return true

static func _fallback_annotation(definition: Dictionary, state: Dictionary, data: Dictionary) -> Dictionary:
	var instances: Variant = state.get("divination",{}).get("emergent_cases",{}).get("instances",{})
	if not instances is Dictionary: return {}
	for arrival_id: String in instances:
		var record: Variant = instances[arrival_id]
		if not record is Dictionary or record.get("case_id") != definition.id or record.get("source",{}).get("kind") != "fallback": continue
		var proof: Variant = record.get("proof",{})
		if not proof is Dictionary or not data.fallbacks.has(proof.get("template_id")): return {}
		var decks := Cards.load_decks()
		if _fallback_bundle.is_empty():
			var loaded := Kernel.load_bundle(decks,Schema.new())
			if not loaded.get("success",false): return {}
			_fallback_bundle = loaded.bundle
		var checked := Kernel.materialize(str(proof.get("kind","")),_fallback_bundle,decks,Schema.new())
		if not checked.get("success",false): return {}
		var rebound := Kernel.bind(checked,state.get("save_id"),arrival_id,record.get("npc_id"),_fallback_bundle,decks,Schema.new())
		if not rebound.get("success",false) or Schema.definition_hash(rebound.bound.definition) != Schema.definition_hash(definition): return {}
		var authored: Dictionary = data.fallbacks[proof.template_id]
		var row := {"definition_hash":Schema.definition_hash(definition),"advice_tones":{},"critical_slots":[]}
		for index: int in range(checked.draft.definition.advice.size()):
			var local_id: String = checked.draft.definition.advice[index].id
			if not authored.advice_tones.has(local_id): return {}
			row.advice_tones[definition.advice[index].id] = authored.advice_tones[local_id]
		for local_id: String in authored.critical_slots: row.critical_slots.append(str(definition.id)+"_s_"+local_id)
		return row
	return {}

static func help(state: Dictionary, visit: Dictionary, board: Dictionary, definition: Dictionary, action: Dictionary) -> Dictionary:
	var config := Rules.load_config()
	var copy: Dictionary = config.ui.copy
	if not board.has("mechanics"): return {"success":false,"error_code":"METHOD_UNAVAILABLE","message":copy.hint_missing}
	var annotation_row := annotation(definition,state)
	var method := "yijing" if action.type == "case_preview_advice" else "astrology"
	if annotation_row.is_empty() or uses(board,method) >= budget(board,method) or board.phase == "closed": return {"success":false,"error_code":"METHOD_UNAVAILABLE","message":copy.hint_missing}
	var target := ""
	var message := ""
	if method == "yijing":
		target = str(action.get("advice_id",""))
		if board.phase != "deduction" or not annotation_row.advice_tones.has(target) or board.mechanics.previews.has(target): return {"success":false,"error_code":"METHOD_TARGET_USED","message":copy.hint_missing}
		var tone: String = annotation_row.advice_tones[target]
		board.mechanics.previews[target] = tone
		message = String(copy.preview_result).format({"tone":config.ui.tones[tone]})
	else:
		for id: String in annotation_row.critical_slots:
			if id not in board.mechanics.key_slots: target = id; break
		if target.is_empty(): return {"success":false,"error_code":"METHOD_TARGET_USED","message":copy.hint_missing}
		board.mechanics.key_slots.append(target)
		for slot: Dictionary in definition.deduction_slots:
			if slot.id == target: message = String(copy.key_result).format({"slot":slot.title})
	var used := record(board,action,method,target)
	return {"success":true,"message":message,"minutes":0,"result":{"visit_id":visit.visit_id,"method_use":used,"hint":message}}

static func valid(state: Dictionary, visit: Dictionary, board: Dictionary, definition: Dictionary) -> bool:
	var value: Variant = board.get("mechanics")
	var c := Rules.load_config()
	if c.is_empty() or not Rules.keys(value,["version","curriculum_version","levels","budgets","uses","extra_question_ids","previews","key_slots","panels"]) or value.version != 1 or value.curriculum_version != c.version or not Rules.keys(value.levels,Rules.METHODS) or not value.uses is Array or not value.extra_question_ids is Array or not value.previews is Dictionary or not value.key_slots is Array or not value.panels is Dictionary: return false
	for id: String in Rules.METHODS:
		if not Rules.integer(value.levels[id],0,level(state,id,c)): return false
	if value.budgets != budgets(value.levels,definition,c): return false
	if value.extra_question_ids != board.questions_asked.slice(int(board.round)) or value.extra_question_ids.size() > maxi(1,int(value.budgets.xiaoliu)) or board.extra_question_used != (not value.extra_question_ids.is_empty()): return false
	var seen := {}
	var counts := {}
	var hint := annotation(definition,state)
	for used: Variant in value.uses:
		if not Rules.keys(used,["action_id","method_id","effect","target_id","energy_saved"]) or not Rules.action_id(used.action_id) or not Rules.METHODS.has(used.method_id) or used.effect != c.methods[used.method_id].effect or not Rules.identifier(used.target_id) or not Rules.integer(used.energy_saved,0,100): return false
		var key: String = used.method_id+":"+used.target_id
		if seen.has(key) or seen.has(used.action_id): return false
		seen[key] = true; seen[used.action_id] = true
		counts[used.method_id] = int(counts.get(used.method_id,0))+1
		var kind := ""
		match used.effect:
			"observe", "extra_card":
				if not used.target_id.begins_with("card_"): return false
				var index := int(used.target_id.trim_prefix("card_"))
				var at: int = board.flipped_indices.find(index)
				if at < 0 or (used.effect == "extra_card") != (at >= int(c.cap_policy.base_cards)): return false
				kind = "case_flip_card"
			"eliminate":
				if not board.eliminations.has(used.target_id): return false
				kind = "case_eliminate"
			"free_question":
				if used.target_id not in value.extra_question_ids or used.energy_saved != int(Schema.load_rules().costs.extra_question.energy): return false
				kind = "case_extra_question"
			"preview":
				if hint.is_empty() or not value.previews.has(used.target_id) or value.previews[used.target_id] != hint.advice_tones.get(used.target_id): return false
				kind = "case_preview_advice"
			"key_slot":
				if hint.is_empty() or used.target_id not in value.key_slots or value.key_slots != hint.critical_slots.slice(0,value.key_slots.size()): return false
				kind = "case_key_slot"
			_:
				return false
		if used.effect != "free_question" and used.energy_saved != 0: return false
		var receipt: Dictionary = state.get("processed_actions",{}).get(used.action_id,{})
		if receipt.get("action_type") != kind or receipt.get("result",{}).get("visit_id") != visit.visit_id or receipt.get("result",{}).get("method_use") != used: return false
	for id: String in counts:
		if int(counts[id]) > (definition.cards.size() if id == "tarot" else int(value.budgets[id])): return false
	if value.previews.size() != int(counts.get("yijing",0)) or value.key_slots.size() != int(counts.get("astrology",0)): return false
	return true

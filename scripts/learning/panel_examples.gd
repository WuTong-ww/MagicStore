extends RefCounted
## The existing oracle calculators, with authored fictional inputs only.
const Oracle = preload("res://scripts/divination/catalog.gd")
const Rules = preload("res://scripts/learning/learning_rules.gd")

static func valid(value: Variant) -> bool:
	if not Rules.keys(value,["chart","quoted_at","parameter","options","past_profile"]) or not Oracle.valid_chart(value.chart) or not Rules.integer(value.quoted_at,0,2147483647) or not Rules.integer(value.parameter,0,100): return false
	if not Rules.keys(value.options,["bazi","ziwei","past"]) or not Rules.keys(value.past_profile,["vision","evidence"]) or not value.past_profile.values().all(Rules.text): return false
	for id: String in value.options:
		if not value.options[id] is Array or value.options[id].size() != 3: return false
		for option: Variant in value.options[id]:
			if not option is String or option not in Oracle.METHOD_OPTIONS[id]: return false
	return true

static func data_for(deck_catalog: Dictionary, examples: Dictionary) -> Dictionary:
	if not valid(examples) or not deck_catalog.get("cases",{}).has("archive"): return {}
	return {"cases":{"archive":deck_catalog.cases.archive.duplicate(true)},"methods":deck_catalog.methods.duplicate(true),"past_profiles":{"fiction_lesson":examples.past_profile.duplicate(true)},"guests":{}}

static func result(run_id: String, method_id: String, stage: int, bundle: Dictionary) -> Dictionary:
	var example: Dictionary = bundle.config.practice.panel_examples
	if method_id not in example.options or stage < 1 or stage > 3 or bundle.get("panel_data",{}).is_empty(): return {}
	var data: Dictionary = bundle.panel_data
	var quote := {"service_id":"service_"+run_id,"quoted_at":int(example.quoted_at),"method_id":method_id,"option_id":str(example.options[method_id][stage-1]),"parameter":int(example.parameter),"question_id":str(data.cases.archive.default_question)}
	var scratch := {"case_id":"archive","npc_id":"fiction_lesson","profile_id":"fiction_lesson","chart":example.chart.duplicate(true),"event":{}}
	return Oracle.read_result(quote,scratch,data,[])

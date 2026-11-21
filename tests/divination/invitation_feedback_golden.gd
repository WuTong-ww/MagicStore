extends SceneTree
## Feedback and actual A/C consumption, captured from main before G3.
const Events = preload("res://scripts/divination/event_rules.gd")
const People = preload("res://scripts/people/people.gd")
const Shop = preload("res://scripts/shop/shop.gd")
const PATH := "res://tests/fixtures/G3/invitation_feedback_golden.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("INVITATION FEEDBACK GOLDEN FAIL: "+label)

static func fixture_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("format") != "invitation_feedback_consumption_v1" or value.get("commit") != "e27441b51a4415777971cf2d8142ce4c725437e5" or not value.get("sources") is Dictionary or not value.get("records") is Array or value.records.size() != 10:
		return false
	for path: String in ["scripts/divination/event_rules.gd","scripts/people/people.gd","data/divination.json"]:
		if not value.sources.get(path) is String or value.sources[path].length() != 64:
			return false
	for row: Variant in value.records:
		if not row is Dictionary or not row.get("input") is Dictionary or not row.get("expected") is Dictionary:
			return false
		for key: String in ["effects","referral_targets","rejected_effects"]:
			if not row.expected.get(key) is Array:
				return false
	return true

static func canonical(value: Variant) -> Variant:
	if value is float and value == floor(value):
		return int(value)
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = canonical(value[key])
		return result
	if value is Array:
		return value.map(canonical)
	return value

static func exercise(definition: Dictionary, event_script: Script, people_script: Script, input: Dictionary, legacy: bool = false) -> Dictionary:
	var visit := {"visit_id":"visit_feedback_gold","npc_id":"npc_lin","day":0,"started_at":540,"phase":"ended"}
	var current := {"visit_id":"visit_feedback_return","npc_id":"npc_lin","day":1,"started_at":2400,"phase":"talking"}
	var prediction := {"prediction_id":"prediction_feedback_gold","expected":input.expected,"condition":input.condition,"window_start":1080,"window_end":1110} if input.has_prediction else {}
	var case := {"case_id":"invitation","visit_id":visit.visit_id,"npc_id":"npc_lin","prediction":prediction,"advice":[],"branches":[],"item_use":{},"world_facts":{"changed_entrance":{"value":input.changed_entrance}},"event":event_script.create(visit,definition)}
	if not input.advice.is_empty():
		case.advice.append({"advice_id":"advice_feedback_gold","advice_key":input.advice,"accepted":true})
	event_script._resolve(case,definition)
	if legacy and not prediction.is_empty():
		event_script._evaluate(case,2400)
	var state := {"save_id":"save_feedback_gold","clock_minutes":2400,"active_visit_id":current.visit_id,"player":{"coins":40,"energy":100,"items":{}},"npcs":{"npc_lin":{"coins":60,"items":{"silver_leaf":1}}},"visits":[visit,current],"divination":{"cases":{visit.visit_id:case},"ledger":[],"effects":[]}}
	var economy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/divination.json")).economy
	var can_report: bool = event_script.can_report(case.event,2400)
	var report := {}
	if can_report:
		report = event_script.disclose(state,case,current,economy) if legacy else event_script.disclose(state,case,current,economy,definition)
	var people: Dictionary = people_script.create(state.save_id,12,2400)
	people_script.add_fixed(people,"npc_lin","林照晚","旧书修复师")
	var rejected: Array = []
	for effect: Dictionary in state.divination.effects:
		if effect.recipient == "A" and not people_script.apply_effect(people,effect):
			rejected.append(effect.kind)
	Shop.sync_effects(state,Shop.load_config())
	var effect_rows: Array = []
	for effect: Dictionary in state.divination.effects:
		effect_rows.append({"recipient":effect.recipient,"kind":effect.kind,"amount":int(effect.amount),"duration":int(effect.expires_at)-int(effect.starts_at) if int(effect.expires_at) >= 0 else 0,"item_id":effect.get("item_id","")})
	effect_rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return str(a.recipient)+str(a.kind) < str(b.recipient)+str(b.kind))
	var targets: Array = []
	for referral: Dictionary in people.referrals.values():
		targets.append(referral.target_npc_id)
	targets.sort()
	var actual := {"can_report":can_report,"evaluation":report.get("evaluation","undisclosed"),"can_review":report.get("can_review",false),"effects":effect_rows,"rejected_effects":rejected,"trust":int(people.profiles.npc_lin.trust),"familiarity":int(people.profiles.npc_lin.familiarity),"referral_targets":targets,"reputation":int(state.shop.reputation),"review_growth":int(state.shop.review_growth),"gift_player":int(state.player.items.get(economy.gift_id,0)),"gift_guest":int(state.npcs.npc_lin.items.get(economy.gift_id,0)),"gift_ledger_count":state.divination.ledger.filter(func(row: Dictionary) -> bool: return row.category == "gift").size()}
	var before := state.duplicate(true)
	var people_before := people.duplicate(true)
	if not legacy:
		if can_report:
			event_script.disclose(state,case,current,economy,definition)
		for effect: Dictionary in state.divination.effects:
			if effect.recipient == "A":
				people_script.apply_effect(people,effect)
		Shop.sync_effects(state,Shop.load_config())
	return {"actual":actual,"replay_unchanged":legacy or (state == before and people == people_before)}

func run() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	check(FileAccess.get_sha256(PATH) == "45570448f3ade3b1387a38467ef7f9a9c04ff780b23ab18f53440589f64ce6a3","captured feedback fixture bytes remain unchanged")
	check(fixture_valid(fixture),"legacy feedback fixture has provenance and ten branch records")
	if not fixture_valid(fixture):
		quit(1)
		return
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/divination.json")).cases.invitation.event
	for row: Dictionary in fixture.records:
		var result := exercise(definition,Events,People,row.input)
		check(canonical(result.actual) == canonical(row.expected),"actual main feedback and consumed consequences / "+row.input.label)
		if canonical(result.actual) != canonical(row.expected):
			printerr("FEEDBACK GOLD DIFFERENCE / "+row.input.label+" actual="+JSON.stringify(result.actual)+" expected="+JSON.stringify(row.expected))
		check(result.replay_unchanged,"feedback and consumers replay without duplicate consequences / "+row.input.label)
	print("INVITATION FEEDBACK GOLDEN: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

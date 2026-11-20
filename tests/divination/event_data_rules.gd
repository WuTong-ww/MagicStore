extends SceneTree
var Events: Script = load("res://scripts/divination/event_rules.gd")
var Schema: Script
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("EVENT DATA RULES FAIL: " + label)

func run() -> void:
	check(FileAccess.file_exists("res://scripts/divination/event_schema.gd"), "generic event schema exists")
	check(FileAccess.file_exists("res://data/divination/event_templates.json"), "three governed event templates exist")
	if failures > 0:
		finish()
		return
	Schema = load("res://scripts/divination/event_schema.gd")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/divination.json"))
	for id: String in ["invitation", "archive"]:
		check(Schema.event_valid(data.cases[id].event), "authored event validates / " + id)
	var templates: Dictionary = Schema.load_templates()
	check(templates.get("templates", {}).size() == 3, "contact, visit and decision templates validate")
	for key: String in templates.get("templates", {}):
		var definition: Dictionary = templates.templates[key]
		var case := make_case(definition)
		case.advice = [{"advice_key":definition.advice_options[0].key,"accepted":true,"advice_id":"advice_fixture"}]
		var state := make_state(case)
		Events._resolve(case, definition, state)
		state.clock_minutes = case.event.feedback.available_at
		check(Events.can_report(case.event, state.clock_minutes), "template reaches report / " + key)
		var report: Dictionary = Events.disclose(state, case, {"visit_id":"visit_report","npc_id":"npc_fixture"}, data.economy, definition)
		check(not report.is_empty() and report.get("evidence") == "sufficient", "template completes sufficient disclosure / " + key)
	var definition: Dictionary = data.cases.invitation.event.duplicate(true)
	check_validation(definition)
	check_all_conditions(definition)
	check_feedback(definition, data.economy)
	finish()

func make_case(definition: Dictionary) -> Dictionary:
	return {"case_id":"fixture","visit_id":"visit_fixture","npc_id":"npc_fixture","world_facts":{},"branches":[],"advice":[],"item_use":{},"prediction":{},"event":Events.create({"day":0,"started_at":540,"visit_id":"visit_fixture"},definition)}

func make_state(case: Dictionary) -> Dictionary:
	return {"clock_minutes":int(case.event.due_at),"divination":{"cases":{"visit_fixture":case},"effects":[]},"people":{"profiles":{"npc_fixture":{"personality_id":"reflective"}},"relationships":{"rel_fixture":{"closeness":60}}}}

func check_validation(original: Dictionary) -> void:
	var invalid := original.duplicate(true)
	invalid.rules[0].when["unknown_condition"] = true
	check(not Schema.event_valid(invalid), "unknown rule conditions are rejected")
	invalid = original.duplicate(true)
	invalid.rules[0].when.advice = "unknown_advice"
	check(not Schema.event_valid(invalid), "unknown advice references are rejected")
	invalid = original.duplicate(true)
	invalid.rules[0].when.fact = {"changed_entrance":"impossible"}
	check(not Schema.event_valid(invalid), "facts outside their declared domain are rejected")
	invalid = original.duplicate(true)
	invalid.rules.push_front({"when":{},"outcome":"sent"})
	check(not Schema.event_valid(invalid), "first-match shadowed rules are rejected")
	invalid = original.duplicate(true)
	invalid.outcomes["unreferenced"] = invalid.outcomes.sent.duplicate(true)
	check(not Schema.event_valid(invalid), "unreferenced outcomes are rejected")
	invalid = original.duplicate(true)
	invalid.outcomes.sent.effects = [{"kind":"unknown_effect","amount":1}]
	check(not Schema.event_valid(invalid), "unsupported effect kinds are rejected")
	invalid = original.duplicate(true)
	invalid.outcomes.sent.effects = [{"kind":"trust","amount":101}]
	check(not Schema.event_valid(invalid), "trust deltas outside save contract are rejected")
	invalid = original.duplicate(true)
	invalid.outcomes.sent.effects = [{"kind":"gift","item_id":"silver_leaf","qty":2,"amount":1}]
	check(not Schema.event_valid(invalid), "conflicting gift quantities are rejected")
	invalid = original.duplicate(true)
	invalid.outcomes.sent.effects = [{"kind":"trust"}]
	check(not Schema.event_valid(invalid), "numeric effects require an explicit configured delta")
	invalid = original.duplicate(true)
	invalid.outcomes.sent.effects = [{"kind":"traffic_boost","amount":101,"minutes":30}]
	check(not Schema.event_valid(invalid), "traffic amount stays within the consumer contract")
	invalid = original.duplicate(true)
	invalid.version = 99
	check(not Schema.event_valid(invalid), "unknown event content version is rejected")
	invalid = original.duplicate(true)
	invalid.advice_options[0].erase("requires_clue")
	check(not Schema.event_valid(invalid), "advice options cannot omit a compatibility prerequisite")
	invalid = original.duplicate(true)
	invalid.outcomes.sent.feedback = "immediate"
	check(not Schema.event_valid(invalid), "immediate feedback cannot carry a hidden extra delay")
	invalid = fixture_definition(original)
	invalid.rules = [{"when":{"advice":"message","accepted":true},"outcome":"sent"}]
	invalid.outcomes.erase("waited")
	check(not Schema.event_valid(invalid), "rules cover the refused-advice path as well as the accepted path")
	invalid = fixture_definition(original)
	invalid.rules = [{"when":{"advice":"message","accepted":true},"outcome":"sent"},{"when":{"advice":"message","accepted":false},"outcome":"waited"}]
	check(not Schema.event_valid(invalid), "explicit advice rules also require a no-advice outcome")
	var empty_path := fixture_definition(original)
	empty_path.outcomes["no_advice"] = empty_path.outcomes.waited.duplicate(true)
	empty_path.rules = [{"when":{"accepted":true},"outcome":"sent"},{"when":{"advice":"message","accepted":false},"outcome":"waited"},{"when":{},"outcome":"no_advice"}]
	check(Schema.event_valid(empty_path), "fallback reachable only without advice is a real reachable rule")
	invalid = fixture_definition(original)
	invalid.outcomes["phantom"] = invalid.outcomes.sent.duplicate(true)
	invalid.rules = [{"when":{"advice":"message","accepted":true},"outcome":"sent"},{"when":{"accepted":true},"outcome":"phantom"},{"when":{},"outcome":"waited"}]
	check(not Schema.event_valid(invalid), "empty advice cannot make an accepted-only shadowed rule reachable")
	invalid = fixture_definition(original)
	invalid.rules[0].when.relationship_min.rel_fixture = 101
	check(not Schema.event_valid(invalid), "relationship thresholds above the real closeness domain are rejected")
	invalid = fixture_definition(original)
	invalid.rules[0].when.relationship_min.rel_fixture = -1
	check(not Schema.event_valid(invalid), "relationship thresholds below the real closeness domain are rejected")
	invalid = original.duplicate(true)
	invalid.advice_options.append({"key":"never_reached","label":"不可达建议"})
	invalid.advice.never_reached = {"text":"不可达建议"}
	# Remove generic fallback so the new advice cannot use any outcome.
	invalid.rules = invalid.rules.filter(func(rule: Dictionary) -> bool: return rule.when.has("advice"))
	check(not Schema.event_valid(invalid), "an advice with no reachable outcome is rejected")

func fixture_definition(original: Dictionary) -> Dictionary:
	var definition := original.duplicate(true)
	definition.advice_options = [{"key":"message","label":"核对后联系"}]
	definition.advice = {"message":{"text":"核对后联系"}}
	definition.world_facts = {"ready":{"values":[true,false],"default":true}}
	definition.branch_ids = ["verified"]
	definition.item_effect_ids = ["steady"]
	definition.item_effect = {"key":"steady","need":"愿意把顾虑说清楚","advice_keys":["message"]}
	definition.rules = [{"when":{"advice":"message","accepted":true,"fact":{"ready":true},"branch":"verified","item_effect":"steady","relationship_min":{"rel_fixture":60},"personality_in":["reflective"]},"outcome":"sent"},{"when":{},"outcome":"waited"}]
	definition.outcomes = {"sent":original.outcomes.sent.duplicate(true),"waited":original.outcomes.waited.duplicate(true)}
	definition.prediction_conditions = {"always":{"label":"无附加条件"}}
	definition.feedback_effects = []
	return definition

func check_all_conditions(original: Dictionary) -> void:
	var definition := fixture_definition(original)
	check(Schema.event_valid(definition), "combined condition fixture validates")
	for changed: String in ["none","advice","accepted","fact","branch","item_effect","relationship_min","personality_in"]:
		var case := make_case(definition)
		case.advice = [{"advice_key":"message","accepted":true,"advice_id":"advice_fixture"}]
		case.world_facts = {"ready":{"value":true}}
		case.branches = ["verified"]
		case.item_use = {"effect_key":"steady","item_use_id":"use_fixture"}
		var state := make_state(case)
		match changed:
			"advice": case.advice[0].advice_key = "other"
			"accepted": case.advice[0].accepted = false
			"fact": case.world_facts.ready.value = false
			"branch": case.branches = []
			"item_effect": case.item_use.effect_key = "other"
			"relationship_min": state.people.relationships.rel_fixture.closeness = 59
			"personality_in": state.people.profiles.npc_fixture.personality_id = "outgoing"
		Events._resolve(case, definition, state)
		check(case.event.outcome_id == ("sent" if changed == "none" else "waited"), "ordered rule uses condition / " + changed)
		var resolved: Dictionary = case.event.duplicate(true)
		Events._resolve(case, definition, state)
		check(case.event == resolved, "resolved outcome remains stable / " + changed)

func check_feedback(original: Dictionary, economy: Dictionary) -> void:
	for evidence: String in ["sufficient","partial","none"]:
		var definition := original.duplicate(true)
		definition.outcomes.sent.evidence = evidence
		definition.outcomes.sent.feedback = "immediate"
		definition.outcomes.sent.delay_minutes = 0
		definition.outcomes.sent.effects = [{"kind":"trust","amount":1},{"kind":"trust","amount":2}]
		definition.feedback_effects = [{"kind":"familiarity","amount":1,"when":{"evaluation":"aligned"}}]
		var case := make_case(definition)
		case.advice = [{"advice_key":"message","accepted":true,"advice_id":"advice_fixture"}]
		case.prediction = {"prediction_id":"prediction_fixture","condition":"always","expected":"met","window_start":int(case.event.due_at)-1,"window_end":int(case.event.due_at)+500}
		var state := make_state(case)
		Events.advance(state, {"cases":{"fixture":{"event":definition}}})
		check(case.event.evaluation == "pending", "world resolution never evaluates an undisclosed prediction / " + evidence)
		check(case.event.feedback.available_at == case.event.due_at, "feedback availability ignores later forecast window / " + evidence)
		check(state.divination.effects.size() == 2 and state.divination.effects[0].effect_id != state.divination.effects[1].effect_id, "same-kind resolve effects have distinct stable IDs / " + evidence)
		Events.advance(state, {"cases":{"fixture":{"event":definition}}})
		check(state.divination.effects.size() == 2, "repeated advancement does not duplicate effects / " + evidence)
		if evidence == "none":
			check(not Events.can_report(case.event, state.clock_minutes) and case.event.feedback.disclosure.is_empty(), "none evidence cannot disclose any facts or text")
			continue
		var report: Dictionary = Events.disclose(state, case, {"visit_id":"visit_report","npc_id":"npc_fixture"}, economy, definition)
		check(not report.is_empty(), "report can be obtained / " + evidence)
		check(report.has("outcome") == (evidence == "sufficient") and report.has("actual_action") == (evidence == "sufficient"), "actual facts require sufficient evidence / " + evidence)
		check(case.event.evaluation == ("aligned" if evidence == "sufficient" else "insufficient"), "evaluation follows disclosed evidence / " + evidence)
		var count: int = state.divination.effects.size()
		Events.disclose(state, case, {"visit_id":"visit_report","npc_id":"npc_fixture"}, economy, definition)
		check(state.divination.effects.size() == count, "duplicate disclosure preserves effect count / " + evidence)
	var definition := original.duplicate(true)
	var case := make_case(definition)
	case.advice = [{"advice_key":"private","accepted":true,"advice_id":"advice_private"}]
	case.prediction = {"prediction_id":"prediction_private","condition":"always","expected":"met","window_start":0,"window_end":99999}
	var state := make_state(case)
	state.clock_minutes = 99999
	Events.advance(state, {"cases":{"fixture":{"event":definition}}})
	check(case.event.evaluation == "pending" and not Events.can_report(case.event,99999) and case.event.feedback.disclosure.is_empty(), "never feedback remains private and pending forever")
	case = make_case(original)
	case.advice = [{"advice_key":"message","accepted":true,"advice_id":"advice_legacy"}]
	case.prediction = {"prediction_id":"prediction_legacy","condition":"always","expected":"met","window_start":0,"window_end":99999}
	state = make_state(case)
	Events._resolve(case, original, state)
	case.event.erase("rule_index")
	var historical_outcome: String = case.event.outcome_id
	var historical_due: int = case.event.due_at
	state.clock_minutes = case.event.feedback.available_at
	Events.disclose(state,case,{"visit_id":"visit_legacy_report","npc_id":"npc_fixture"},economy,original)
	check(int(case.event.get("rule_index",-1)) >= 0 and state.divination.effects.all(func(entry: Dictionary) -> bool: return int(entry.rule_index) >= 0), "legacy resolved event acquires valid effect provenance when actually reported")
	check(case.event.outcome_id == historical_outcome and int(case.event.due_at) == historical_due, "legacy feedback never re-resolves the historical world outcome")

func finish() -> void:
	print("EVENT DATA RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

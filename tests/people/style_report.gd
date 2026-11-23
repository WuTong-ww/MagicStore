extends SceneTree
## Authored row/evidence fixtures only; no live economy or GUI claim.
var checks: int = 0
var failures: int = 0
var completed: bool = false

func _initialize() -> void:
	create_timer(15.0).timeout.connect(func() -> void:
		if not completed:
			printerr("STYLE REPORT FAIL: bounded target deadline exceeded")
			quit(1))
	if not FileAccess.file_exists("res://scripts/people/style_report.gd"):
		check(false,"pure style-report component exists")
		finish()
		return
	var api: GDScript = load("res://scripts/people/style_report.gd") as GDScript
	check(api != null and api.can_instantiate(),"pure component loads")
	if api == null or not api.can_instantiate():
		finish()
		return
	var rules: Dictionary = api.load_rules()
	check(api.rules_valid(rules),"production rules validate")
	if rules.is_empty():
		finish()
		return
	var fixture: GDScript = load("res://tests/people/fixtures/style_report_facts.gd") as GDScript
	check(fixture != null and fixture.can_instantiate(),"authored source-shaped fixtures load")
	if fixture == null or not fixture.can_instantiate():
		finish()
		return
	check(rules.window.latest_ended_visits == 20 and rules.titles.size() == 12,"fixed window and twelve title rules are data-driven")
	var expected: Dictionary = {"inquiry":[90,33,10,40,78,50],"commerce":[23,33,80,40,75,50],"balanced":[54,67,60,60,67,67]}
	var titles: Dictionary = {"inquiry":"open_chat","commerce":"busy_counter","balanced":"steady_pages"}
	for kind: String in expected:
		var facts: Dictionary = fixture.make_case(kind)
		var before: Dictionary = facts.duplicate(true)
		check(api.facts_valid(facts,rules),"authored facts validate / "+kind)
		var report: Dictionary = api.derive(facts,rules)
		check(report.status == "ready" and report.title.id == titles[kind],"independent title oracle / "+kind)
		for index: int in range(6):
			check(report.dimensions[index].score == expected[kind][index],"independent six-dimension score / "+kind+" / "+str(index))
		check(report.dimensions[2].status == "limited" and report.dimensions[3].status == "limited","commercial and contact scores retain proxy limitations")
		check(report.notice == "只描述本局可追溯的经营行为，不是 MBTI 或人格测验。","fixed entertainment notice does not emit personality types")
		check(report.dimensions.all(func(row: Dictionary) -> bool: return not row.basis_ids.is_empty() and row.basis_ids.all(func(id: String) -> bool: return report.evidence.has(id))),"every scored conclusion has resolvable public evidence")
		check(facts == before,"derive never mutates authored source facts")
		var reordered: Dictionary = facts.duplicate(true)
		for key: String in ["visits","talks","predictions","paid_services","trades","manual_contacts","arrival_episodes","disclosed_feedback","reviews"]:
			reordered[key].reverse()
		check(api.derive(reordered,rules) == report,"input insertion order cannot change a report")
	var facts: Dictionary = fixture.make_case("balanced")
	var report: Dictionary = api.derive(facts,rules)
	var duplicate: Dictionary = facts.duplicate(true)
	duplicate.talks.append(duplicate.talks[0].duplicate(true))
	duplicate.trades.append(duplicate.trades[0].duplicate(true))
	check(api.facts_valid(duplicate,rules) and api.derive(duplicate,rules) == report,"exact committed mirrors never inflate samples")
	duplicate.talks[-1].channel = "free_text" if duplicate.talks[0].channel == "button" else "button"
	check(not api.facts_valid(duplicate,rules),"conflicting identity mirrors fail closed")
	var hidden: Dictionary = facts.duplicate(true)
	var undisclosed: Dictionary = hidden.disclosed_feedback[0].duplicate(true)
	undisclosed.id = "unseen_feedback"
	undisclosed.disclosed = false
	undisclosed.effect_id = "unseen_effect"
	hidden.disclosed_feedback.append(undisclosed)
	check(api.derive(hidden,rules) == report,"unreported deviated world results never change the public report")
	var missing: Dictionary = facts.duplicate(true)
	missing.coverage.inquiry = {"status":"partial","missing_count":1,"baseline_at":null,"reason":"旧交谈未保存渠道。"}
	missing.talks[0].channel = "unknown"
	check(api.derive(missing,rules).dimensions[0].score == null,"missing channel coverage is observing rather than zero")
	missing = facts.duplicate(true)
	missing.coverage.rhythm.baseline_at = null
	check(api.derive(missing,rules).dimensions[4].score == null,"missing waiting baseline leaves only duration metrics")
	missing = facts.duplicate(true)
	missing.manual_contacts = []
	check(api.derive(missing,rules).dimensions[3].score == null,"zero contacts without opportunity records is not a relationship zero")
	missing = facts.duplicate(true)
	missing.disclosed_feedback = []
	missing.reviews = []
	check(api.derive(missing,rules).dimensions[5].score == null,"no disclosed review opportunity is not a false zero or hundred")
	missing = facts.duplicate(true)
	missing.predictions = []
	check(api.derive(missing,rules).dimensions[1].score == null,"no formal prediction is observing")
	var old: Dictionary = fixture.make_case("empty")
	check(api.facts_valid(old,rules),"legacy absence has an explicit valid unknown coverage projection")
	var observing: Dictionary = api.derive(old,rules)
	check(observing.status == "observing" and observing.title.id == "observing" and observing.dimensions.all(func(row: Dictionary) -> bool: return row.score == null),"legacy missing sources are never filled with zeros")
	for field: String in ["coverage","evidence","save_id"]:
		var bad: Dictionary = facts.duplicate(true)
		bad.erase(field)
		check(not api.facts_valid(bad,rules),"missing required fact field rejected / "+field)
	var bad: Dictionary = facts.duplicate(true)
	bad.talks[0].basis_id = "missing_basis"
	check(not api.facts_valid(bad,rules),"dangling basis reference rejected")
	bad = facts.duplicate(true)
	bad.talks[0].visit_id = "foreign_visit"
	check(not api.facts_valid(bad,rules),"foreign visit reference rejected")
	bad = facts.duplicate(true)
	bad.evidence.values()[0]["world_facts"] = {"hidden":true}
	check(not api.facts_valid(bad,rules),"private evidence fields cannot cross the whitelist")
	bad = facts.duplicate(true)
	bad.visits[0].ended_at = NAN
	check(not api.facts_valid(bad,rules),"nonfinite source clocks are rejected")
	check(api.derive(bad,rules).status == "invalid_sources","malformed facts cannot claim a partially valid report")
	for field: String in ["dimensions","titles","notice"]:
		var bad_rules: Dictionary = rules.duplicate(true)
		bad_rules.erase(field)
		check(not api.rules_valid(bad_rules),"missing required rules rejected / "+field)
	var bad_rules: Dictionary = rules.duplicate(true)
	bad_rules.dimensions.inquiry.op = "eval_anything"
	check(not api.rules_valid(bad_rules),"operator strings cannot execute arbitrary expressions")
	bad_rules = rules.duplicate(true)
	bad_rules.titles.pop_back()
	check(not api.rules_valid(bad_rules),"all twelve title rules are required")
	bad_rules = rules.duplicate(true)
	bad_rules.mapping.high = INF
	check(not api.rules_valid(bad_rules),"nonfinite title thresholds rejected")
	check(api.load_rules("res://data/people/missing_style_rules.json").is_empty(),"missing rules fail closed")
	finish()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("STYLE REPORT FAIL: "+label)

func finish() -> void:
	completed = true
	print("STYLE REPORT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

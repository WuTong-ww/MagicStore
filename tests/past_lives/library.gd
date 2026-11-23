extends SceneTree
## Pure authored library fixtures; no real saves, actions or GUI are claimed.

var checks: int = 0
var failures: int = 0
var api: GDScript
var sequence: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("PAST LIBRARY FAIL: " + label)

func finish() -> void:
	print("PAST LIBRARY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _initialize() -> void:
	if not FileAccess.file_exists("res://scripts/divination/past_lines.gd"):
		check(false, "pure past-line component exists")
		finish()
		return
	api = load("res://scripts/divination/past_lines.gd") as GDScript
	check(api != null, "pure module loads")
	if api == null:
		finish()
		return
	var library: Dictionary = api.load_config()
	check(not library.is_empty(), "production registry loads")
	if library.is_empty():
		finish()
		return
	check(api.config_valid(library), "production registry and definition are valid")
	check(library.binding_policy.chance_bps == 500, "production ordinary chance is five percent")
	check(library.binding_policy.minimum_npc_coins == 42, "initial affordability is forty-two")
	check(library.definitions.size() == 1, "only one authored placeholder is present")
	var definition: Dictionary = library.definitions["demo_three_eras@1"]
	check(definition.eras.size() == 3 and definition.fragments.size() == 7, "three eras have seven fragments")
	check(definition.eras[0].title == "旧渡" and definition.eras[1].title == "修桥" and definition.eras[2].title == "药圃", "the three authored atmospheres are stable")
	check(definition.eras.all(func(era: Dictionary) -> bool: return era.identities.size() == 2), "each era has exactly two historical identities")
	check(api._content_digest({"b":[true,"x"],"a":1.0}) == "63e8063d9dc6f0fd5a24b4706818a165fd57c3531b74466cf5dea62bff09b0b6", "canonical JSON has an independent literal SHA oracle")
	check(library.definition_sha256["demo_three_eras@1"] == "58607e7bfa19873ec44c0ae26456ab8a37490936e6c2d4035fa5a968152ed087", "authored definition matches independent standard JSON canonical SHA")
	test_config(library)
	test_bindings(library)
	test_progression(library)
	check(api.load_config("res://data/past_lives/missing.json").is_empty(), "missing registry fails closed")
	finish()

func context(npc: String = "npc_ordinary_4") -> Dictionary:
	return {"save_id":"save_library","npc_id":npc,"visit_id":"visit_library","action_id":"quote_binding","at":540,"cause":"both","case_id":"archive","is_ordinary":true,"npc_known":true,"known_clue_ids":["archive_stub"],"npc_coins":60,"has_legacy_memory":false,"slot_candidates":{}}

func empty_progress() -> Dictionary:
	return {"version":1,"instances":{}}

func committed(state: Dictionary, action_id: String, kind: String, result: Dictionary) -> void:
	sequence += 1
	state.processed_actions[action_id] = {"action_type":kind,"state_version":sequence,"result":result.duplicate(true)}

func refreshed(library: Dictionary) -> Dictionary:
	var result: Dictionary = library.duplicate(true)
	for key: String in result.definitions:
		result.definition_sha256[key] = api._content_digest(result.definitions[key])
	return result

func test_config(library: Dictionary) -> void:
	var bad: Dictionary = library.duplicate(true)
	bad.binding_policy.chance_bps = NAN
	check(not api.config_valid(bad), "nonfinite chance is rejected")
	bad = library.duplicate(true)
	bad.costs.vision.coins = true
	check(not api.config_valid(bad), "boolean price is rejected")
	bad = library.duplicate(true)
	bad.costs.evidence.minutes = -1
	check(not api.config_valid(bad), "negative time is rejected")
	bad = library.duplicate(true)
	bad.copy.erase("unknown_identity")
	check(not api.config_valid(bad), "missing required public copy is rejected")
	bad = library.duplicate(true)
	bad.layout.row_gap = INF
	check(not api.config_valid(bad), "nonfinite layout is rejected")
	bad = library.duplicate(true)
	bad.cause_policy.case_causes.archive = "present"
	check(not api.config_valid(bad), "archive migration cause cannot silently change to present")
	bad = library.duplicate(true)
	bad.line_paths[0] = "res://data/past_lives/../divination.json"
	check(not api.config_valid(bad), "registry traversal is rejected")
	bad = library.duplicate(true)
	bad.images.era1 = "res://assets/portraits/npc_lin_neutral.png"
	check(not api.config_valid(bad), "memory art cannot borrow an unrelated full portrait")
	bad = library.duplicate(true)
	bad.definitions["demo_three_eras@1"].fragments[1].requires_seen = ["missing_fragment"]
	check(not api.config_valid(refreshed(bad)), "missing fragment dependency is rejected after correct digest")
	bad = library.duplicate(true)
	bad.definitions["demo_three_eras@1"].fragments[0].requires_seen = ["e1e"]
	check(not api.config_valid(refreshed(bad)), "a real dependency cycle is rejected")
	bad = library.duplicate(true)
	bad.definitions["demo_three_eras@1"].fragments[1].fragment_id = "e1v"
	check(not api.config_valid(refreshed(bad)), "duplicate fragment identities are rejected")
	bad = library.duplicate(true)
	bad.definitions["demo_three_eras@1"].interpretation_groups[0].options[0].requires_evidence = ["e1echo"]
	check(not api.config_valid(refreshed(bad)), "echo cannot be the validating evidence")
	bad = library.duplicate(true)
	bad.definitions["demo_three_eras@1"].slots[1].kind = "family"
	bad.definitions["demo_three_eras@1"].slots[1].selector = {"template_id":"test_family","member_key":"companion"}
	check(api.config_valid(refreshed(bad)), "family selectors are supported without forcing a family into the demo")
	var before: Dictionary = library.duplicate(true)
	var reordered: Dictionary = library.duplicate(true)
	var original: Dictionary = reordered.definitions["demo_three_eras@1"]
	var reverse: Dictionary = {}
	var keys: Array = original.keys()
	keys.reverse()
	for key: String in keys:
		reverse[key] = original[key]
	reordered.definitions["demo_three_eras@1"] = JSON.parse_string(JSON.stringify(reverse,"\t"))
	check(api.config_valid(reordered), "object order and JSON formatting do not change content identity")
	check(library == before, "configuration validation does not mutate input")

func test_bindings(library: Dictionary) -> void:
	var ctx: Dictionary = context()
	var progress: Dictionary = empty_progress()
	var before: Dictionary = ctx.duplicate(true)
	var result: Dictionary = api.binding_proposal(ctx, progress, library)
	check(result.ok and not result.binding_patch.is_empty(), "literal golden ordinary candidate is admitted")
	if not result.ok:
		return
	check(result.binding_patch.instance.bindings.companion.npc_id == "npc_lin", "fixed companion is resolved without replacing the ordinary primary")
	check(ctx == before and progress.instances.is_empty(), "binding proposal cannot mutate its inputs")
	var again: Dictionary = api.binding_proposal(ctx, progress, library)
	check(again == result, "same independent seed domain produces identical binding")
	var reordered: Dictionary = library.duplicate(true)
	reordered.definitions["demo_three_eras@1"].slots.reverse()
	reordered = refreshed(reordered)
	var alternate: Dictionary = api.binding_proposal(ctx, progress, reordered)
	check(alternate.ok and alternate.instance_id == result.instance_id, "slot ordering cannot change stable instance IDs")
	for field: String in ["npc_known","is_ordinary"]:
		var invalid: Dictionary = ctx.duplicate(true)
		invalid[field] = false
		check(not api.binding_proposal(invalid,progress,library).ok, "unknown or ineligible NPC cannot bind")
	var invalid: Dictionary = ctx.duplicate(true)
	invalid.cause = "present"
	check(not api.binding_proposal(invalid,progress,library).ok, "present cause cannot bind a usable line")
	invalid = ctx.duplicate(true)
	invalid.known_clue_ids = []
	check(not api.binding_proposal(invalid,progress,library).ok, "missing real artifact prevents binding")
	invalid = ctx.duplicate(true)
	invalid.npc_coins = 41
	check(not api.binding_proposal(invalid,progress,library).ok, "initial forty-one coins cannot promise the seven-fragment line")
	invalid = ctx.duplicate(true)
	invalid.has_legacy_memory = true
	check(not api.binding_proposal(invalid,progress,library).ok, "existing legacy past memory is not rebound")
	progress.instances[result.instance_id] = result.binding_patch.instance.duplicate(true)
	invalid = ctx.duplicate(true)
	invalid.npc_coins = 18
	var existing: Dictionary = api.binding_proposal(invalid,progress,library)
	check(existing.ok and existing.instance_id == result.instance_id and existing.binding_patch.is_empty(), "permanent bindings do not reapply initial forty-two coin gate")
	var family: Dictionary = library.duplicate(true)
	family.definitions["demo_three_eras@1"].slots[1].kind = "family"
	family.definitions["demo_three_eras@1"].slots[1].selector = {"template_id":"test_family","member_key":"companion"}
	family = refreshed(family)
	ctx.slot_candidates = {"companion":[{"npc_id":"family_companion","kind":"family","template_id":"test_family","member_key":"companion"}]}
	var selected: Dictionary = api.binding_proposal(ctx,empty_progress(),family)
	check(selected.ok and selected.binding_patch.instance.bindings.companion.npc_id == "family_companion", "family candidate must match its stable template and member")
	ctx.slot_candidates.companion[0].member_key = "other"
	check(not api.binding_proposal(ctx,empty_progress(),family).ok, "a mismatched family member cannot fill the slot")
	seed(90210)
	var expected_random: int = randi()
	seed(90210)
	api.binding_proposal(context(),empty_progress(),library)
	check(randi() == expected_random, "binding never consumes global RNG")

func test_progression(library: Dictionary) -> void:
	var ctx: Dictionary = context()
	var progress: Dictionary = empty_progress()
	var bind: Dictionary = api.binding_proposal(ctx,progress,library)
	if not bind.ok:
		check(false,"binding prerequisite for authored progression")
		return
	var instance_id: String = bind.instance_id
	progress.instances[instance_id] = bind.binding_patch.instance.duplicate(true)
	var retired: Dictionary = library.duplicate(true)
	retired.active_versions = {}
	for kind: String in ["vision","evidence","echo"]:
		retired.costs[kind].coins = 9
	check(api.config_valid(retired),"closing active versions retains the immutable historical definition")
	check(not api.binding_proposal(ctx,empty_progress(),retired).ok,"closed active versions cannot create a new binding")
	var historical: Dictionary = api.service_proposal(ctx,progress,"vision",retired)
	check(historical.ok and historical.cost.coins == 6,"bound version-one progress uses its definition price after registry defaults change")
	var host: Dictionary = {"schema_version":9,"save_id":ctx.save_id,"clock_minutes":540,"npcs":{ctx.npc_id:{"coins":60},"npc_lin":{"coins":60}},"visits":[{"visit_id":ctx.visit_id,"npc_id":ctx.npc_id,"started_at":540}],"processed_actions":{},"divination":{"past_lines":progress,"cases":{ctx.visit_id:{"npc_id":ctx.npc_id,"profile_id":"bookbinder","cause":"both","services":{}}},"ledger":[]}}
	var hidden: Dictionary = api.public_view(progress,ctx.npc_id,{"npc_lin":"林照晚"},library)
	check(not hidden.available and hidden.title == "" and hidden.rows.is_empty(), "a binding without obtained fragments discloses no line or future rows")
	var wallet: int = 60
	var energy: int = 0
	var minutes: int = 0
	var expected_ids: Array[String] = ["e1v","e1e","e1echo","e2v","e2e","e3v","e3e"]
	for index: int in range(expected_ids.size()):
		ctx.action_id = "paid_" + str(index)
		ctx.at = 540 + minutes
		ctx.npc_coins = wallet
		var option: String = "evidence" if expected_ids[index].ends_with("e") else "vision"
		var before: Dictionary = progress.duplicate(true)
		var proposal: Dictionary = api.service_proposal(ctx,progress,option,library)
		check(proposal.ok,"literal next fragment is eligible: "+expected_ids[index])
		if not proposal.ok:
			return
		check(proposal.descriptor.fragment_id == expected_ids[index], "fragment order has an independent literal oracle")
		check(proposal.cost == {"coins":6,"energy":6,"minutes":15}, "each modern service freezes six-six-fifteen")
		check(proposal.result.medium.stage == option and proposal.result.medium.kind == "fragment", "echo keeps legacy service option stage")
		check(progress == before, "resolving a service cannot obtain a fragment")
		wallet -= 6
		energy += 6
		minutes += 15
		var d: Dictionary = proposal.descriptor
		var service_id: String = "service_"+str(index)
		host.divination.cases[ctx.visit_id].services[service_id] = {"service_id":service_id,"visit_id":ctx.visit_id,"npc_id":ctx.npc_id,"method_id":"past","option_id":option,"past_line":d.duplicate(true),"payment":{"kind":"coins","amount":6},"energy":6,"minutes":15,"quoted_at":ctx.at,"paid_at":ctx.at+15,"status":"paid","result":proposal.result.duplicate(true)}
		if index == 0:
			committed(host,"quote_binding","quote_service",{"service_id":service_id,"visit_id":ctx.visit_id})
		committed(host,ctx.action_id,"settle_service",{"service_id":service_id,"visit_id":ctx.visit_id})
		host.divination.ledger.append({"entry_id":"ledger_"+service_id,"category":"divination","reference_id":service_id,"visit_id":ctx.visit_id,"npc_id":ctx.npc_id,"at":ctx.at,"from":ctx.npc_id,"to":"player","payment":{"kind":"coins","amount":6}})
		host.clock_minutes = ctx.at+15
		host.npcs[ctx.npc_id].coins = wallet
		progress.instances[instance_id].fragments[d.fragment_id] = {"fragment_record_id":"record_"+str(index),"fragment_id":d.fragment_id,"era_id":d.era_id,"kind":d.kind,"service_id":"service_"+str(index),"visit_id":ctx.visit_id,"at":ctx.at+15,"title":proposal.result.title,"text":proposal.result.text,"art_key":library.definitions["demo_three_eras@1"].fragments[index].art_key}
		if index in [0,3,5]:
			var group: String = "g1" if index == 0 else "g2" if index == 3 else "g3"
			ctx.action_id = "interpret_"+group
			ctx.at += 15
			var unsupported: Dictionary = api.verification_proposal(ctx,progress,"missing",library)
			check(not unsupported.ok, "unknown interpretation cannot be verified")
			var wrong: Dictionary = api.interpretation_proposal(ctx,progress,{"group_id":group,"option_id":group+("_b" if group == "g2" else "_a"),"text":"先留下一个猜想。"},library)
			check(wrong.ok and wrong.record.status == "unverified", "seeing and a player's interpretation are separate")
			if not wrong.ok:
				return
			progress.instances[instance_id].interpretations[wrong.record.interpretation_id] = wrong.record
			committed(host,ctx.action_id,"interpret_past_line",{"interpretation_id":wrong.record.interpretation_id,"visit_id":ctx.visit_id})
			check(not api.verification_proposal(ctx,progress,wrong.record.interpretation_id,library).ok,"vision alone cannot verify a guess")
			var view: Dictionary = api.public_view(progress,ctx.npc_id,{"npc_lin":"林照晚"},library)
			check(view.available and view.rows.size() == 3,"first acquired fragment opens three-era public scaffold")
			check(view.rows[-1].known == (index == 5),"future eras remain unknown until acquired")
			if index == 0:
				check(view.rows[1].image_path == "" and not view.rows[1].nodes[0].has("identity_id"),"unknown era has no identity ID or image path")
				check(not JSON.stringify(view).contains("药圃") and not JSON.stringify(view).contains("era3.png"),"public data strips future text and image paths")
				check(not JSON.stringify(view.options).contains("verdict") and not JSON.stringify(view.options).contains("requires_evidence"),"public options never reveal private answers")
		if index in [1,4,6]:
			var group: String = "g1" if index == 1 else "g2" if index == 4 else "g3"
			var instance: Dictionary = progress.instances[instance_id]
			var prior_id: String = ""
			for candidate: String in instance.interpretations:
				if instance.interpretations[candidate].group_id == group:
					prior_id = candidate
			ctx.action_id = "verify_wrong_"+group
			ctx.at += 15
			var rejected: Dictionary = api.verification_proposal(ctx,progress,prior_id,library)
			check(rejected.ok and rejected.patch.status == "refuted", "actual independent evidence refutes the wrong option")
			if not rejected.ok:
				return
			instance.interpretations[prior_id].merge(rejected.patch,true)
			committed(host,ctx.action_id,"verify_past_line",{"interpretation_id":prior_id,"visit_id":ctx.visit_id,"status":"refuted"})
			ctx.action_id = "interpret_right_"+group
			var right: Dictionary = api.interpretation_proposal(ctx,progress,{"group_id":group,"option_id":group+("_a" if group == "g2" else "_b"),"text":"按证物重新解释。"},library)
			check(right.ok,"a refuted guess does not block a different supported explanation")
			if not right.ok:
				return
			instance.interpretations[right.record.interpretation_id] = right.record
			committed(host,ctx.action_id,"interpret_past_line",{"interpretation_id":right.record.interpretation_id,"visit_id":ctx.visit_id})
			ctx.action_id = "verify_right_"+group
			var verified: Dictionary = api.verification_proposal(ctx,progress,right.record.interpretation_id,library)
			check(verified.ok and verified.patch.status == "verified", "the correct option is verified only after evidence")
			if not verified.ok:
				return
			instance.interpretations[right.record.interpretation_id].merge(verified.patch,true)
			committed(host,ctx.action_id,"verify_past_line",{"interpretation_id":right.record.interpretation_id,"visit_id":ctx.visit_id,"status":"verified"})
			check(not api.verification_proposal(ctx,progress,right.record.interpretation_id,library).ok,"already verified records cannot be verified twice")
	check(wallet == 18 and energy == 42 and minutes == 105,"all seven modern fragments are reachable within the literal sixty-coin budget")
	check(not api.service_proposal(ctx,progress,"vision",library).ok,"completed vision branch cannot charge for a duplicate fragment")
	var complete: Dictionary = api.public_view(progress,ctx.npc_id,{"npc_lin":"林照晚"},library)
	check(complete.rows.all(func(row: Dictionary) -> bool: return row.known),"all three eras become known from obtained records")
	check(complete.interpretations.size() == 6,"refuted guesses remain alongside verified interpretations")
	check(JSON.stringify(complete).contains("林照晚"),"a verified relationship may show an already known present-day name")
	check(not api.public_view(progress,"unrelated",{},library).available,"unrelated NPC cannot inspect the private line")
	check(api.progress_valid(host,library),"authored completed progress has all actual-shaped service/action/visit/payment sources")
	test_public_order(progress,ctx.npc_id,library)
	check(api.progress_valid(host,retired),"closing active versions and changing new defaults never reprices saved version-one services")
	var changed_copy: Dictionary = library.duplicate(true)
	changed_copy.copy.signal_prompt = "只更改界面默认提示，不改旧服务。"
	check(api.progress_valid(host,changed_copy),"editing UI defaults cannot rewrite or invalidate a stored service result")
	var delayed: Dictionary = host.duplicate(true)
	delayed.clock_minutes += 5
	for service: Dictionary in delayed.divination.cases[ctx.visit_id].services.values():
		if service.service_id != "service_0":
			service.quoted_at += 5
		service.paid_at += 5
	for entry: Dictionary in delayed.divination.ledger:
		entry.at += 5
	for fragment: Dictionary in delayed.divination.past_lines.instances[instance_id].fragments.values():
		fragment.at += 5
	for interpretation: Dictionary in delayed.divination.past_lines.instances[instance_id].interpretations.values():
		interpretation.at += 5
		if not interpretation.verification.is_empty():
			interpretation.verification.at += 5
	check(api.progress_valid(delayed,library),"a saved quote may be paid after five actual waiting minutes")
	var wrong_payment_time: Dictionary = delayed.duplicate(true)
	wrong_payment_time.divination.ledger[0].at = 540
	check(not api.progress_valid(wrong_payment_time,library),"a delayed payment cannot borrow its earlier quote time as ledger source")
	var bad: Dictionary = host.duplicate(true)
	bad.schema_version = 8
	check(not api.progress_valid(bad,library),"pre-nine snapshots cannot carry modern line progress")
	bad = host.duplicate(true)
	bad.divination.erase("past_lines")
	check(not api.progress_valid(bad,library),"schema nine requires its progress namespace")
	check(api.progress_valid({"schema_version":8,"divination":{}},library),"legacy missing namespace remains compatible before schema nine")
	bad = host.duplicate(true)
	bad.divination.cases[ctx.visit_id].services.service_0.status = "quoted"
	check(not api.progress_valid(bad,library),"a quotation cannot prove fragment acquisition")
	bad = host.duplicate(true)
	bad.divination.ledger.remove_at(0)
	check(not api.progress_valid(bad,library),"missing actual payment provenance rejects progress")
	bad = host.duplicate(true)
	bad.divination.cases[ctx.visit_id].services.service_0.payment.amount = 23
	check(not api.progress_valid(bad,library),"modern service cannot inherit the old twenty-three coin price")
	bad = host.duplicate(true)
	bad.divination.cases[ctx.visit_id].services.service_0.npc_id = "npc_lin"
	check(not api.progress_valid(bad,library),"cross-NPC paid service reference is rejected")
	bad = host.duplicate(true)
	bad.processed_actions.verify_right_g1.result.status = "refuted"
	check(not api.progress_valid(bad,library),"verification source status cannot be swapped")
	check(not api.progress_valid({"divination":{"past_lines":{"version":1,"instances":{"forged":{}}}}},library),"source-less forged progress is rejected")

func test_public_order(progress: Dictionary,npc_id: String,library: Dictionary) -> void:
	# Projection-only authored order oracle; these renamed IDs/times are not
	# claimed as real committed source records. Use the parsed numeric domain on
	# both sides so the exact public JSON comparison isolates dictionary order.
	var authored: Dictionary = JSON.parse_string(JSON.stringify(progress,"",false,true))
	var instance: Dictionary = authored.instances.values()[0]
	var supported: Dictionary = {}
	for record: Dictionary in instance.interpretations.values():
		if record.status == "verified":
			supported[record.group_id] = record.duplicate(true)
	instance.interpretations = {}
	# Insertion order z,a,m and lexical order a,m,z both differ from the required
	# chronological order m,z,a; m/z share an exact time to test the ID tie-break.
	for spec: Dictionary in [{"id":"z_tie","group":"g3","at":555.0},{"id":"a_late","group":"g2","at":600.0},{"id":"m_tie","group":"g1","at":555.0}]:
		var record: Dictionary = supported[spec.group].duplicate(true)
		record.interpretation_id = spec.id
		record.at = spec.at
		instance.interpretations[spec.id] = record
	var before: Dictionary = api.public_view(authored,npc_id,{"npc_lin":"林照晚"},library)
	var reopened: Dictionary = JSON.parse_string(JSON.stringify(authored,"",true,true))
	var after: Dictionary = api.public_view(reopened,npc_id,{"npc_lin":"林照晚"},library)
	check(before.interpretations.map(func(row: Dictionary) -> String: return row.interpretation_id) == ["m_tie","z_tie","a_late"],"public interpretations use time then stable ID rather than insertion order")
	check(before.links.map(func(row: Dictionary) -> String: return row.label) == ["共同守渡","共同守圃","共同修桥"],"verified links follow the same stable interpretation order")
	check(JSON.stringify(before,"",true,true) == JSON.stringify(after,"",true,true),"entire public model is byte-identical after actual sorted-JSON reopening")

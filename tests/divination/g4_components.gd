extends SceneTree
## Focused G4 case authority tests. Full save transactions remain core-owned.
const Loader = preload("res://scripts/core/content_loader.gd")
const Catalog = preload("res://scripts/divination/catalog.gd")
const Session = preload("res://scripts/divination/session.gd")
const Events = preload("res://scripts/divination/event_rules.gd")
const Saved = preload("res://scripts/divination/case_save.gd")
const Rules = preload("res://scripts/divination/event_schema.gd")
const CaseView = preload("res://scripts/divination/case_view.gd")
var checks := 0
var failures := 0
var content: Dictionary
var data: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("G4 COMPONENT FAIL: "+label)

func fixture(preference: String = "concrete_steps") -> Dictionary:
	var npc := "npc_g4_fixture"
	var visit := {"visit_id":"visit_g4_fixture","npc_id":npc,"day":0,"phase":"talking","clue_ids":["invitation_note"],"dialogue":[{"speaker":"npc","text":"我想先核对已知的事情。"}],"reading":{},"started_at":540,"ended_at":-1}
	var profile := {"npc_id":npc,"name":"测试来客","role":"附近居民","met":true}
	if not preference.is_empty():
		profile.advice_preference = preference
		profile.advice_preference_version = 1
	return {"schema_version":8,"save_id":"save_g4_fixture","clock_minutes":540,"player":{"coins":40,"energy":100,"items":{}},"npcs":{npc:{"coins":60,"items":{}}},"people":{"profiles":{npc:profile},"relationships":{},"revealed_relationships":{}},"divination":{"skills":["tarot"],"cases":{},"past":{},"ledger":[],"effects":[],"legacy_eventless_visits":[]},"visits":[visit],"active_visit_id":visit.visit_id,"processed_actions":{}}

func open_case(state: Dictionary) -> RefCounted:
	var session := Session.new(data,content)
	check(session.add_case(state,state.visits[0],"invitation",true,{"public_npc":{"name":"测试来客","role":"附近居民"}}),"real Session binds the fixture case")
	return session

func run() -> void:
	if "--write-uids" in OS.get_cmdline_user_args() and not FileAccess.file_exists("res://tests/divination/g4_components.gd.uid"):
		var uid_file := FileAccess.open("res://tests/divination/g4_components.gd.uid",FileAccess.WRITE)
		uid_file.store_line(ResourceUID.id_to_text(ResourceUID.create_id()))
		uid_file.close()
	var loaded := Loader.load_content()
	check(loaded.get("success",false),"base content loads")
	if not loaded.get("success",false):
		quit(1)
		return
	content = loaded.content
	data = Catalog.load_data(content)
	check(not data.is_empty(),"production case catalog validates")
	var state := fixture()
	var session := open_case(state)
	var visit: Dictionary = state.visits[0]
	var action := {"type":"give_advice","action_id":"advice_g4_same","advice_key":"attend","advice_style":"concrete_steps"}
	var result: Dictionary = session.handle(state,visit,action)
	check(result.get("success",false),"eligible advice is recorded")
	var record: Dictionary = state.divination.cases[visit.visit_id].advice.back()
	check(record.get("acceptance") is Dictionary,"new ordinary preference decision saves probability, independent roll and source")
	if record.get("acceptance") is Dictionary:
		var snapshot: Dictionary = record.acceptance.duplicate(true)
		check(snapshot.get("preference") == "concrete_steps" and snapshot.get("style") == "concrete_steps" and snapshot.has("probability") and snapshot.has("roll") and snapshot.has("rules_version"),"accepted snapshot binds the real preference and style")
		var replay_state := fixture()
		var replay_session := open_case(replay_state)
		replay_session.handle(replay_state,replay_state.visits[0],action)
		check(replay_state.divination.cases[visit.visit_id].advice.back().acceptance == snapshot,"same save/NPC/event/advice produces the same independent decision without global RNG")
	var invalid := action.duplicate(true)
	invalid.action_id = "advice_g4_invalid"
	invalid.advice_style = "invented_style"
	var before := state.duplicate(true)
	check(not session.handle(state,visit,invalid).get("success",false) and state == before,"unknown advice style is rejected atomically")
	var gated := fixture()
	gated.visits[0].clue_ids.clear()
	var gated_session := open_case(gated)
	gated_session.handle(gated,gated.visits[0],action)
	check(not gated.divination.cases[visit.visit_id].advice.back().accepted,"preference never bypasses the old required-clue hard gate")
	var legacy := fixture("")
	var legacy_session := open_case(legacy)
	legacy_session.handle(legacy,legacy.visits[0],action)
	check(legacy.divination.cases[visit.visit_id].advice.back().accepted and not legacy.divination.cases[visit.visit_id].advice.back().has("acceptance"),"legacy people keep the exact old clue-only accepted rule")
	check(session.has_method("preview_product_components") and session.has_method("apply_product_components"),"Shop has a single preview/apply case-authority boundary")
	if session.has_method("preview_product_components"):
		var tool := [{"component_id":"primary","effect":{"kind":"clue","clue_id":"g4_tool_observation","method_id":"tarot"}}]
		var source := {"item_use_id":"item_use_g4","transaction_id":"transaction_g4","item_id":"fixture_tool"}
		before = state.duplicate(true)
		var preview: Dictionary = session.call("preview_product_components",state,visit,tool,source)
		check(preview.get("success",false) and state == before,"valid tool clue preview has no state side effects")
		var bad_tool := tool.duplicate(true)
		bad_tool[0].effect.clue_id = "venue_notice"
		check(not session.call("preview_product_components",state,visit,bad_tool,source).get("success",false) and state == before,"a catalog component cannot read an undeclared case fact")
		var bad_source := source.duplicate(true)
		bad_source.rel_id = "hidden_third_party_edge"
		check(not session.call("preview_product_components",state,visit,tool,bad_source).get("success",false),"player-supplied hidden relationship IDs never select a target")
		var applied: Dictionary = session.call("apply_product_components",state,visit,tool,source)
		check(applied.get("success",false) and "g4_tool_observation" in visit.clue_ids,"tool use reveals only the declared tool clue")
		check(applied.get("components",[]).size() == 1 and applied.components[0].result.get("source_kind") == "tool" and applied.components[0].feedback_refs[0].kind == "tool_clue","tool output has component/use provenance and never fakes an NPC report")
		record_use(state,visit,source,tool,applied)
		check(Saved._product_records(state.divination.cases[visit.visit_id],visit,state,data,int(state.clock_minutes)),"actual tool audit cross-links the committed Shop component")
		var changed := state.duplicate(true)
		changed.shop.uses[0].component_results[0].result.clue_id = "venue_notice"
		check(not Saved._product_records(changed.divination.cases[visit.visit_id],changed.visits[0],changed,data,int(changed.clock_minutes)),"forged use-to-tool provenance is rejected")
		before = state.duplicate(true)
		check(session.apply_product_components(state,visit,tool,source).success and state == before,"same component replay returns the stored result without a second clue or audit row")
		var mixed := [{"component_id":"tool2","effect":{"kind":"clue","clue_id":"g4_tool_observation","method_id":"tarot"}},{"component_id":"bad","effect":{"kind":"relationship","effect_key":"family_reconnect_support","delta":3}}]
		var untouched := fixture()
		var untouched_session := open_case(untouched)
		before = untouched.duplicate(true)
		check(not untouched_session.apply_product_components(untouched,untouched.visits[0],mixed,source).success and untouched == before,"an invalid relationship prevents every component from being applied")
	check_rules_and_relationships()
	print("G4 COMPONENTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func record_use(state: Dictionary, visit: Dictionary, source: Dictionary, wrappers: Array, applied: Dictionary) -> void:
	var rows: Array = []
	for component: Dictionary in applied.components:
		var row := component.duplicate(true)
		for wrapper: Dictionary in wrappers:
			if wrapper.component_id == row.component_id:
				row.effect = wrapper.effect.duplicate(true)
		rows.append(row)
	if not state.has("shop"):
		state.shop = {"uses":[]}
	state.shop.uses.append({"version":2,"item_use_id":source.item_use_id,"transaction_id":source.transaction_id,"item_id":source.item_id,"visit_id":visit.visit_id,"at":int(state.clock_minutes),"component_results":rows})

func check_rules_and_relationships() -> void:
	var rules := Rules.load_product_rules()
	check(not rules.is_empty(),"production probability/component JSON validates")
	check(Session.advice_style_options() == {"styles":rules.styles,"default_style":rules.default_style,"heading":rules.copy.advice_style_heading},"public advice style options expose labels and default without preference probabilities or rolls")
	var bad_rules := rules.duplicate(true)
	bad_rules.acceptance_versions["1"].probabilities.direct.listening = 10001
	check(not Rules.product_rules_valid(bad_rules),"out-of-range acceptance probability is rejected")
	var decision := fixture()
	var deciding := open_case(decision)
	deciding.handle(decision,decision.visits[0],{"type":"give_advice","action_id":"stable","advice_key":"attend"})
	var case: Dictionary = decision.divination.cases[decision.active_visit_id]
	var advice: Dictionary = case.advice.back()
	check(Rules.acceptance_valid(advice.acceptance,advice,decision,case,data.cases.invitation.event.advice.attend,decision.people.profiles[case.npc_id],decision.visits[0].clue_ids),"stored acceptance is validated against its saved rule version and source")
	var tampered: Dictionary = advice.acceptance.duplicate(true)
	tampered.roll = (int(tampered.roll)+1)%int(tampered.roll_scale)
	check(not Rules.acceptance_valid(tampered,advice,decision,case,data.cases.invitation.event.advice.attend,decision.people.profiles[case.npc_id],decision.visits[0].clue_ids),"altered acceptance roll cannot be loaded as committed history")
	var saved_decision := decision.duplicate(true)
	decision.active_visit_id = ""
	var public_view := CaseView.project(deciding,decision,decision.visits[0])
	check(not public_view.advice[0].has("acceptance") and public_view.advice[0].accepted == advice.accepted,"player case projection keeps the advice result while withholding preference, probability and roll")
	decision.active_visit_id = decision.visits[0].visit_id
	check(decision == saved_decision,"public advice projection never strips the durable acceptance audit")
	var chosen := ""
	var preference_rule: Dictionary = rules.acceptance_versions["1"]
	for index: int in range(128):
		var candidate := "preference_probe_"+str(index)
		var roll := Rules.advice_roll(candidate,case.npc_id,case.event.event_id,"attend","concrete_steps",rules.acceptance_versions["1"].seed_namespace,int(rules.acceptance_versions["1"].roll_scale))
		if roll >= int(preference_rule.probabilities.listening.concrete_steps) and roll < int(preference_rule.probabilities.concrete_steps.concrete_steps):
			chosen = candidate
			break
	check(not chosen.is_empty(),"preference comparison has a deterministic roll between the two configured probabilities")
	if not chosen.is_empty():
		var preferred := fixture("concrete_steps")
		var listening := fixture("listening")
		preferred.save_id = chosen
		listening.save_id = chosen
		var preferred_session := open_case(preferred)
		var listening_session := open_case(listening)
		var same_advice := {"type":"give_advice","action_id":"same_preference_test","advice_key":"attend","advice_style":"concrete_steps"}
		preferred_session.handle(preferred,preferred.visits[0],same_advice)
		listening_session.handle(listening,listening.visits[0],same_advice)
		var first: Dictionary = preferred.divination.cases[preferred.active_visit_id].advice[0]
		var second: Dictionary = listening.divination.cases[listening.active_visit_id].advice[0]
		check(first.acceptance.roll == second.acceptance.roll and first.accepted and not second.accepted,"the real advice action changes acceptance from stored preference probability, with identical clue gate and independent roll")
	var state := fixture("")
	var session := open_case(state)
	var visit: Dictionary = state.visits[0]
	case = state.divination.cases[visit.visit_id]
	var npc: String = visit.npc_id
	var subject: String = case.event.subject_id
	state.people.profiles[subject] = {"npc_id":subject,"name":"关系对象","role":"附近居民","met":true}
	state.people.profiles[npc].goal = {"goal_id":"goal_g4","relationship_id":"rel_g4","subject_id":subject,"status":"open"}
	state.people.relationships.rel_g4 = {"from":npc,"to":subject,"closeness":40,"changes":[]}
	var relationship := [{"component_id":"primary","effect":{"kind":"relationship","effect_key":"family_reconnect_support","delta":3}}]
	var source := {"item_use_id":"use_relation_g4","transaction_id":"sale_g4","item_id":"friendship_knot"}
	check(not session.preview_product_components(state,visit,relationship,source).success,"unrevealed goal edge cannot be selected through a product")
	state.people.revealed_relationships.rel_g4 = {"source_id":"real_statement"}
	var before := state.duplicate(true)
	var applied: Dictionary = session.apply_product_components(state,visit,relationship,source)
	check(applied.success and state.people.relationships.rel_g4.closeness == 40 and state.divination.effects.is_empty(),"legal current-goal relationship product remains pending without altering closeness")
	if not applied.success:
		return
	record_use(state,visit,source,relationship,applied)
	check(Saved._product_records(case,visit,state,data,int(state.clock_minutes)),"relationship audit binds the current-case edge and actual Shop component")
	var wrong := state.duplicate(true)
	wrong.people.relationships.rel_g4.to = "unrelated_person"
	check(not Saved._product_records(wrong.divination.cases[visit.visit_id],wrong.visits[0],wrong,data,int(wrong.clock_minutes)),"third-party endpoint substitution fails save validation")
	Events._emit_product_relationships(state,case)
	check(state.divination.effects.is_empty(),"product without accepted G3 advice cannot manufacture a relationship event")
	visit.clue_ids.append("unfinished_letter")
	session.handle(state,visit,{"type":"give_advice","action_id":"real_cooperation","advice_key":"message"})
	state.clock_minutes = int(case.event.due_at)
	Events.advance(state,data)
	var effects: Array = state.divination.effects.filter(func(effect: Dictionary) -> bool: return effect.get("effect_source") == "product_component")
	check(case.event.outcome_id == "sent" and effects.size() == 1,"real accepted cooperation and sufficient successful G3 outcome create exactly one relationship effect")
	if effects.is_empty():
		return
	check(Saved._effect(effects[0],case,state,data),"relationship effect carries valid trusted-rule and bound component provenance")
	var forged: Dictionary = effects[0].duplicate(true)
	forged.rel_id = "other_edge"
	check(not Saved._effect(forged,case,state,data),"arbitrary relationship replacement cannot load as a legal G3 effect")
	Events.advance(state,data)
	check(state.divination.effects.filter(func(effect: Dictionary) -> bool: return effect.get("effect_source") == "product_component").size() == 1,"event advancement replay never reissues the relationship effect")
	state.people.relationships.rel_g4.changes.append({"effect_id":effects[0].effect_id,"from":40,"to":43})
	state.clock_minutes = int(case.event.feedback.available_at)
	var report := Events.disclose(state,case,visit,data.economy,data.cases.invitation.event)
	check(report.get("item_component_refs",[]).size() == 1 and report.item_component_refs[0].actual_delta == 3,"only real NPC report plus applied relationship change supplies component feedback")
	check(Saved._product_records(case,visit,state,data,int(state.clock_minutes)),"reported relationship retains its original pending component receipt")
	check_gifts()

func check_gifts() -> void:
	var outcomes := {"sent":"honey_drop","arrived":"old_key","note":"blue_glass","waited":"red_thread"}
	for outcome: String in outcomes:
		var state := fixture()
		open_case(state)
		var case: Dictionary = state.divination.cases[state.active_visit_id]
		case.event.outcome_id = outcome
		case.event.rule_index = 0
		case.event.feedback.report = {"at":1260}
		state.clock_minutes = 1260
		Events._emit_product_rewards(state,case)
		var gifts: Array = state.divination.effects.filter(func(effect: Dictionary) -> bool: return effect.get("effect_source") == "g4_reward")
		check(gifts.size() == 1 and gifts[0].item_id == outcomes[outcome] and Saved._effect(gifts[0],case,state,data),"trusted feedback outcome produces its declared hidden material: "+outcome)
		Events._emit_product_rewards(state,case)
		check(state.divination.effects.size() == gifts.size(),"hidden material report replay is idempotent: "+outcome)
	var legacy := fixture("")
	open_case(legacy)
	var old_case: Dictionary = legacy.divination.cases[legacy.active_visit_id]
	old_case.event.outcome_id = "sent"
	old_case.event.rule_index = 0
	old_case.event.feedback.report = {"at":1260}
	Events._emit_product_rewards(legacy,old_case)
	check(legacy.divination.effects.is_empty(),"old profiles do not receive retroactive new hidden-material rewards")

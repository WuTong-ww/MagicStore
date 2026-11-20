extends SceneTree
const People = preload("res://scripts/people/people.gd")
const Shop = preload("res://scripts/shop/shop.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("GENERIC EFFECTS FAIL: "+label)

func effect(id: String, kind: String, recipient: String, values: Dictionary) -> Dictionary:
	var row := {"effect_id":id,"event_id":"event_effect_fixture","prediction_id":"","visit_id":"visit_fixture","npc_id":"npc_lin","subject_id":"npc_lin_friend","recipient":recipient,"kind":kind,"starts_at":600,"expires_at":-1}
	row.merge(values,true)
	return row

func run() -> void:
	var people := People.create("save_effect_fixture",123,600)
	People.add_fixed(people,"npc_lin","测试来客","测试身份")
	People.add_fixed(people,"npc_target","指定目标","测试身份")
	people.profiles.npc_lin.met = true
	people.relationships.rel_other = {"relationship_id":"rel_other","from":"npc_lin_friend","to":"npc_target","kind":"测试关系","closeness":50,"changes":[]}
	var person_effects := [
		effect("effect_trust","trust","A",{"delta":3}),
		effect("effect_familiarity","familiarity","A",{"delta":4}),
		effect("effect_relationship_one","npc_relationship","A",{"rel_id":"rel_other","delta":-7}),
		effect("effect_relationship_two","npc_relationship","A",{"rel_id":"rel_other","delta":3}),
		effect("effect_referral","referral","A",{"target_npc_id":"npc_target"}),
		effect("effect_topic","unlock_topic","A",{"topic_id":"work"})
	]
	for row: Dictionary in person_effects:
		check(People.apply_effect(people,row),"consume A effect / "+row.kind)
	check(people.profiles.npc_lin.trust == 3,"trust delta is applied")
	check(people.profiles.npc_lin.familiarity == 4,"familiarity is distinct from trust")
	check(people.relationships.rel_other.closeness == 46,"two effects on one arbitrary edge both apply")
	check(people.referrals.get("effect_referral",{}).get("target_npc_id") == "npc_target","referral honors its explicit target")
	check(people.get("unlocked_topics",{}).get("npc_lin",[]).any(func(row: Dictionary) -> bool: return row.topic_id == "work"),"topic unlock has its own source records")
	check(People.visible_relationships(people,"npc_lin_friend").is_empty() and not JSON.stringify(People.public_profile(people,"npc_lin")).contains("rel_other"),"changing hidden relationships never reveals them")
	var first := people.duplicate(true)
	for row: Dictionary in person_effects:
		check(not People.apply_effect(people,row),"replayed A effect is ignored / "+row.kind)
	check(people == first,"A effect replay changes no record")
	check(People.validate(people).is_empty(),"people state validates after generic effects")
	check(People.apply_effect(people,effect("effect_legacy_trust","trust","A",{"amount":2})) and people.profiles.npc_lin.trust == 5,"legacy trust amount remains compatible")
	check(People.apply_effect(people,effect("effect_legacy_referral","referral","A",{"amount":1})) and people.referrals.effect_legacy_referral.target_npc_id == "npc_lin_friend","legacy referral retains the existing relationship fallback")
	var config := People.load_config()
	var template_effect := effect("effect_template","referral","A",{"template":"ordinary"})
	check(People.apply_effect(people,template_effect,config),"ordinary referral template creates a stable visitor")
	var template_target: String = people.referrals.get("effect_template",{}).get("target_npc_id","")
	check(people.profiles.get(template_target,{}).get("template_id") == "ordinary_v1","template referral uses the existing ordinary content pool")
	var after_template := people.duplicate(true)
	check(not People.apply_effect(people,template_effect,config) and people == after_template,"template replay creates no extra people")
	for invalid: Dictionary in [effect("effect_unknown_template","referral","A",{"template":"missing_authored_family"}),effect("effect_self","referral","A",{"target_npc_id":"npc_lin"}),effect("effect_missing_edge","npc_relationship","A",{"rel_id":"missing","delta":2}),effect("effect_future","trust","A",{"delta":2,"starts_at":601})]:
		check(not People.apply_effect(people,invalid,config) and people == after_template,"invalid or future A effect is not consumed / "+invalid.effect_id)
	var scheduled := false
	for seed_value in range(100):
		var feedback_people := People.create("save_immediate",seed_value,600)
		People.add_fixed(feedback_people,"npc_lin","测试来客","测试身份")
		People.schedule_feedback(feedback_people,{"event_id":"event_immediate","npc_id":"npc_lin","mode":"immediate","due_at":600,"available_at":600,"disclosure":{"text":"已收到回应","evidence":"sufficient"}},config)
		if feedback_people.feedback_jobs.get("event_immediate",{}).get("state") == "scheduled":
			scheduled = int(feedback_people.feedback_jobs.event_immediate.at) > 600
			break
	check(scheduled,"immediate feedback still respects the real visitor schedule")
	var undisclosed := People.create("save_undisclosed",1,600)
	People.add_fixed(undisclosed,"npc_lin","测试来客","测试身份")
	check(People.schedule_feedback(undisclosed,{"event_id":"event_none","npc_id":"npc_lin","mode":"delayed","due_at":600,"available_at":600,"disclosure":{}},config) and undisclosed.feedback_jobs.get("event_none",{}).get("state") == "not_disclosed","empty disclosure never creates a contentless feedback visit")

	var state := {"save_id":"save_effect_fixture","clock_minutes":600,"player":{"coins":40,"energy":100,"items":{}},"visits":[],"divination":{"cases":{},"ledger":[],"effects":[]}}
	Shop.initialize(state)
	var catalog := Shop.load_config()
	var product_id := ""
	var material_id := ""
	for id: String in catalog.items:
		if catalog.items[id].kind == "product" and product_id.is_empty():
			product_id = id
		if catalog.items[id].kind == "material" and material_id.is_empty():
			material_id = id
	state.divination.effects = [
		effect("effect_reputation","reputation","C",{"amount":2}),
		effect("effect_product_gift","gift","C",{"item_id":product_id,"qty":2}),
		effect("effect_material_gift","gift","C",{"item_id":material_id,"qty":3}),
		effect("effect_traffic","traffic_boost","C",{"amount":2,"minutes":120}),
		effect("effect_review","review_growth","C",{"amount":3})
	]
	Shop.sync_effects(state,catalog)
	check(state.shop.reputation == 2,"reputation is consumed")
	check(state.player.items.get(product_id,0) == 2,"gift transfers products")
	check(state.player.items.get(material_id,0) == 3,"gift transfers materials using qty")
	check(Shop.arrival_bonus(state) == 2 and state.shop.boosts.size() == 1,"traffic_boost alias becomes a real timed boost")
	check(state.shop.review_growth == 3,"review growth is consumed")
	var transferred := state.duplicate(true)
	Shop.sync_effects(state,catalog)
	check(state == transferred,"C effect replay never transfers twice")
	check(Shop.validate(state).is_empty(),"shop state and item provenance validate")
	var legacy_id: String = catalog.legacy_gift.item_id
	state["npcs"] = {"npc_lin":{"coins":0,"items":{legacy_id:2}}}
	state.visits.append({"visit_id":"visit_fixture","npc_id":"npc_lin","phase":"talking"})
	state.divination.effects.append(effect("effect_legacy_gift","gift","C",{"item_id":legacy_id,"qty":1}))
	Shop.sync_effects(state,catalog)
	check(state.player.items.get(legacy_id,0) == 1 and state.npcs.npc_lin.items[legacy_id] == 1,"legacy gift keeps the visitor-to-player wallet transfer")
	check(state.divination.ledger.any(func(row: Dictionary) -> bool: return row.category == "gift" and row.reference_id == "effect_legacy_gift"),"legacy gift retains its separate original ledger source")
	var after_legacy := state.duplicate(true)
	Shop.sync_effects(state,catalog)
	check(state == after_legacy and Shop.validate(state).is_empty(),"legacy gift replay preserves wallets and provenance")
	state.shop.effects_applied.erase("effect_legacy_gift")
	Shop.sync_effects(state,catalog)
	check(state.player.items.get(legacy_id,0) == 1 and state.npcs.npc_lin.items[legacy_id] == 1,"old ledger transfer is recognized even without C's consumption marker")
	var before_invalid := state.duplicate(true)
	var invalid_effects := [effect("effect_bad_gift","gift","C",{"item_id":material_id,"qty":0}),effect("effect_bad_boost","traffic_boost","C",{"amount":1,"minutes":0}),effect("effect_future_c","reputation","C",{"amount":2,"starts_at":601})]
	state.divination.effects.append_array(invalid_effects)
	Shop.sync_effects(state,catalog)
	check(state.shop == before_invalid.shop and state.player == before_invalid.player,"invalid or future C effects are neither applied nor marked")
	print("GENERIC EFFECTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

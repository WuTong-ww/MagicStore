extends SceneTree
const People = preload("res://scripts/people/people.gd")
const Generated = preload("res://scripts/people/generated_person.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var config := People.load_config()
	check(config.arrival.natural_min == 1 and config.arrival.opening_guest, "normal preparation includes an opening customer")
	var invalid := config.duplicate(true)
	invalid.arrival.opening_guest = "yes"
	check(not People.config_valid(invalid), "opening policy must be boolean")
	var legacy_config := config.duplicate(true)
	legacy_config.arrival.erase("opening_guest")
	check(People.config_valid(legacy_config), "legacy configuration remains readable")
	config.arrival.family_percent = 0
	config.arrival.ordinary_return_percent = 0
	config.arrival.special_return_percent = 0
	var no_opening := config.duplicate(true)
	no_opening.arrival.opening_guest = false
	var ordinary := People.create("save_opening_rules",42,540)
	People.plan_day(ordinary,no_opening,1,0,3)
	var opening := People.create("save_opening_rules",42,540)
	People.plan_day(opening,config,1,0,3)
	check(opening.arrivals.arrival_1_0.at == 1980, "first new natural customer is scheduled exactly at next opening")
	check(opening.profiles == ordinary.profiles and opening.arrivals.arrival_1_1 == ordinary.arrivals.arrival_1_1 and opening.arrivals.arrival_1_2 == ordinary.arrivals.arrival_1_2 and opening.arrivals.arrival_1_0.intent == ordinary.arrivals.arrival_1_0.intent and opening.arrivals.arrival_1_0.urgency == ordinary.arrivals.arrival_1_0.urgency, "opening override preserves random stream for identities and all later arrivals")
	var planned_before := ordinary.duplicate(true)
	People.plan_day(ordinary,config,1,0,3)
	check(ordinary == planned_before, "existing day plan is not moved by the new policy")
	var forced_zero := People.create("save_opening_zero",42,540)
	People.plan_day(forced_zero,config,1,0,0)
	check(forced_zero.arrivals.is_empty() and forced_zero.days["1"].natural_count == 0, "explicit zero preparation keeps its original test and migration meaning")
	var day_zero := People.create("save_opening_dayzero",42,540)
	People.plan_day(day_zero,config,0,0,2)
	check(day_zero.arrivals.arrival_0_0.at >= 570, "day zero retains the existing authored opening and ordinary schedule")
	var late := People.create("save_opening_late",42,2040)
	People.plan_day(late,config,1,0,1)
	check(late.arrivals.arrival_1_0.at >= 2040, "late planning does not insert a customer into the past")
	var reserved := People.create("save_opening_reserved",42,540)
	var generation_id := "opening_reserved_person"
	var result := Generated.apply(reserved,config,generation_id,Generated.offline_bundle(generation_id),Generated.offline_provenance(generation_id),2040)
	check(result.success, "scheduled generated fixture is valid")
	var reservation: Dictionary = reserved.arrivals[result.arrival_id].duplicate(true)
	People.plan_day(reserved,config,1,0,2)
	check(reserved.arrivals[result.arrival_id] == reservation and reserved.arrivals.arrival_1_0.at == 1980 and People.validate(reserved).is_empty(), "opening guest does not move an existing generated appointment")
	var full := People.create("save_opening_full",42,540)
	People.add_fixed(full,"npc_lin","林照晚","旧书修复师")
	for index: int in range(20):
		var id := "reserved_"+str(index)
		full.arrivals[id] = {"arrival_id":id,"npc_id":"npc_lin","source":"appointment","at":1980+index,"deadline":-1,"state":"planned","intent":"divination","schedule_end":2760,"referrer_npc_id":"","case_id":"invitation","visit_id":""}
	var appointments: Dictionary = full.arrivals.duplicate(true)
	People.plan_day(full,config,1,0,4)
	check(full.arrivals == appointments and full.days["1"].natural_count == 0 and People.arrival_count_on_day(full,1) == 20 and People.validate(full).is_empty(), "full appointment day takes precedence over the opening guarantee and preserves the shared cap")
	print("OPENING GUEST RULES: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

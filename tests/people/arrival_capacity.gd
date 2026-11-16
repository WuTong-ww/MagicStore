extends SceneTree
const People = preload("res://scripts/people/people.gd")
const Generated = preload("res://scripts/people/generated_person.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func fresh() -> Dictionary:
	var result := People.create("save_capacity_fixture",17,540)
	People.add_fixed(result,"npc_lin","林照晚","旧书修复师")
	result.profiles.npc_lin.met = true
	return result

func occupy(people: Dictionary, day: int, count: int) -> void:
	for index: int in range(count):
		var id := "cap_%d_%d" % [day,index]
		people.arrivals[id] = {"arrival_id":id,"npc_id":"npc_lin","source":"fixture","at":day*1440+570+index,"deadline":-1,"state":"left","intent":"divination","schedule_end":day*1440+1320,"referrer_npc_id":"","case_id":"invitation","visit_id":""}

func run() -> void:
	var config := People.load_config()
	check(config.arrival.natural_max == 8 and config.arrival.queue_capacity == 6 and config.arrival.max_total_per_day == 20, "default arrivals and queue increase without UI configuration")
	var legacy := config.duplicate(true)
	legacy.arrival.erase("max_total_per_day")
	check(People.config_valid(legacy), "old configuration without daily cap defaults to twenty")
	var invalid := config.duplicate(true)
	invalid.arrival.max_total_per_day = 0
	check(not People.config_valid(invalid), "zero daily cap is invalid")
	invalid = config.duplicate(true)
	invalid.arrival.natural_max = 12
	check(People.config_valid(invalid), "natural configuration supports twelve")
	invalid.arrival.natural_max = 13
	check(not People.config_valid(invalid), "natural limit remains bounded at twelve")
	config.arrival.family_percent = 0
	config.arrival.ordinary_return_percent = 0
	config.arrival.special_return_percent = 0
	var mixed := fresh()
	occupy(mixed,0,5)
	var states := ["planned","queued","in_service","completed","left"]
	for index: int in range(5):
		var row: Dictionary = mixed.arrivals["cap_0_"+str(index)]
		row.state = states[index]
		row.deadline = 900 if row.state == "queued" else -1
		row.visit_id = "visit_cap_"+str(index) if row.state in ["in_service","completed"] else ""
	check(People.arrival_count_on_day(mixed,0) == 5 and People.validate(mixed).is_empty(), "all planned, waiting, serving, completed and departed arrivals count")
	var full := fresh()
	occupy(full,0,20)
	check(People.arrival_count_on_day(full,0) == 20 and People.next_available_arrival(full,config,600) == 1980, "full day moves new arrivals to next opening")
	check(People.next_available_arrival(fresh(),config,1320) == 1980, "closed hours move to the next opening")
	var schedule := {"return_schedule":{"weekdays":[2],"start":660,"end":780}}
	check(People.next_available_arrival(full,config,600,schedule) == 2100, "personal weekday and time window apply after a full day")
	schedule["cooldown_until"] = 20*1440+600
	check(People.next_available_arrival(full,config,600,schedule) == -1, "cooldown cannot escape the fourteen-day search horizon")
	var blocked := fresh()
	for day: int in range(14):
		occupy(blocked,day,20)
	check(People.next_available_arrival(blocked,config,600) == -1, "fourteen full days fail without unbounded search")
	var before := full.duplicate(true)
	check(not People.schedule_return(full,"npc_lin","return_full",600,config) and full == before, "return cannot bypass a full day")
	check(People.schedule_return(full,"npc_lin","return_tomorrow",2040,config) and People.arrival_count_on_day(full,1) == 1, "return can use a free future day")
	var referred := fresh()
	occupy(referred,0,20)
	check(People.apply_effect(referred,{"recipient":"A","effect_id":"cap_ref","event_id":"cap_event","npc_id":"npc_lin","kind":"referral"}), "known relation provides a real referral target")
	before = referred.duplicate(true)
	check(not People.schedule_referral(referred,"cap_ref",600,config) and referred == before, "referral cannot bypass a full day")
	check(People.schedule_referral(referred,"cap_ref",2040,config), "referral uses an available future day")
	var feedback_moved := false
	for index: int in range(20):
		var feedback := fresh()
		occupy(feedback,0,20)
		var event_id := "capacity_feedback_"+str(index)
		People.schedule_feedback(feedback,{"event_id":event_id,"npc_id":"npc_lin","mode":"delayed","available_at":600,"due_at":570,"case_id":"invitation"},config)
		if feedback.feedback_jobs.get(event_id,{}).get("state") == "scheduled":
			feedback_moved = int(feedback.feedback_jobs[event_id].at) >= 1440 and People.arrival_count_on_day(feedback,0) == 20 and People.validate(feedback).is_empty()
			break
	check(feedback_moved, "returning feedback respects total cap and moves to a later day")
	var booked := fresh()
	occupy(booked,0,19)
	occupy(booked,1,20)
	booked.arrivals["appointment"] = {"arrival_id":"appointment","npc_id":"npc_lin","source":"fixture","at":540,"deadline":900,"state":"queued","intent":"divination","schedule_end":1320,"referrer_npc_id":"","case_id":"invitation","visit_id":""}
	before = booked.duplicate(true)
	check(not People.book(booked,"appointment",2040,true,config) and booked == before, "agreed appointment still cannot overbook its target day")
	booked.arrivals.erase("cap_1_19")
	check(People.book(booked,"appointment",2040,true,config) and People.arrival_count_on_day(booked,0) == 20 and People.arrival_count_on_day(booked,1) == 20, "rescheduling preserves the old day reservation and occupies the new one")
	booked.arrivals.appointment.state = "left"
	check(People.arrival_count_on_day(booked,0) == 20 and People.arrival_count_on_day(booked,1) == 20 and People.validate(booked).is_empty(), "leaving cannot clear a prior appointment's counted days")
	var crowded := fresh()
	occupy(crowded,0,20)
	crowded.days.clear()
	People.plan_day(crowded,config,0,200,12,100)
	check(People.arrival_count_on_day(crowded,0) == 20 and crowded.arrivals.cap_0_0.state == "left", "clearing day plans cannot reset capacity or rewrite past arrivals")
	var high := fresh()
	People.plan_day(high,config,0,200,999,100)
	check(high.days["0"].natural_count == 12 and People.arrival_count_on_day(high,0) == 12, "forced natural preparation clamps at twelve rather than old eight")
	var constrained := fresh()
	occupy(constrained,0,12)
	People.plan_day(constrained,config,0,200,12,100)
	check(constrained.days["0"].natural_count == 8 and People.arrival_count_on_day(constrained,0) == 20, "natural arrivals share capacity with already reserved arrivals")
	var invalid_state := fresh()
	occupy(invalid_state,0,21)
	check(not People.validate(invalid_state).is_empty(), "persisted state cannot contain more than the daily total")
	var small_config := config.duplicate(true)
	small_config.arrival.max_total_per_day = 2
	var small := fresh()
	People.plan_day(small,small_config,0,0,12)
	check(People.arrival_count_on_day(small,0) == 2 and not People.schedule_return(small,"npc_lin","small_bypass",700), "legacy scheduling methods reuse the persisted configured daily limit")
	var generation_id := "capacity_generated"
	var generated_bundle := Generated.offline_bundle(generation_id)
	before = crowded.duplicate(true)
	check(not Generated.apply(crowded,config,generation_id,generated_bundle,Generated.offline_provenance(generation_id),600).success and crowded == before, "generated-person final admission cannot bypass the shared cap")
	var legacy_full := fresh()
	occupy(legacy_full,0,20)
	check(People.next_available_arrival(legacy_full,legacy,600) == 1980, "old configuration still enforces default twenty")
	print("ARRIVAL CAPACITY: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

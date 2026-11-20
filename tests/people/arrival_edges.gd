extends SceneTree

const People = preload("res://scripts/people/people.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ARRIVAL FAIL: " + label)

func _initialize() -> void:
	var config := People.load_config()
	config.arrival.family_percent = 0
	config.arrival.queue_capacity = 1
	var people := People.create("save_queue", 13, 540)
	People.plan_day(people, config, 0, 0, 2)
	var first: Dictionary = people.arrivals.arrival_0_0
	var second: Dictionary = people.arrivals.arrival_0_1
	first.at = 600
	second.at = 600
	first.schedule_end = 800
	second.schedule_end = 800
	first.urgency = 0
	second.urgency = 20
	people.profiles[second.npc_id].base_patience = 45
	People.advance(people, config, 600)
	check(first.state == "queued" and second.state == "left" and second.reason == config.arrival.overflow.reasons.full, "queue capacity and deterministic order")
	check(int(people.profiles[second.npc_id].trust) == 0, "being turned away at capacity does not create a wait penalty")
	var deadline := int(first.deadline)
	People.advance(people, config, deadline)
	var profile: Dictionary = people.profiles[first.npc_id]
	check(first.state == "left" and profile.waiting_incidents.size() == 1 and profile.trust == -1, "waiting departure records its consequence")
	var before := people.duplicate(true)
	People.advance(people, config, deadline)
	check(people == before, "refresh cannot repeat a waiting penalty")
	profile.met = true
	check(not People.schedule_return(people, first.npc_id, "too_soon", deadline + 60), "return respects cooldown")
	var later := People._next_return_slot(profile, (floori(float(profile.cooldown_until) / 1440.0) + 1) * 1440 + 600)
	check(People.schedule_return(people, first.npc_id, "return_later", later), "return remains possible after cooldown")
	var effect := {"recipient": "A", "effect_id": "effect_ref", "event_id": "event_ref", "npc_id": first.npc_id, "kind": "referral", "amount": 1}
	check(People.apply_effect(people, effect), "referral has real known target")
	var arrival_time := later + 60
	check(People.schedule_referral(people, "effect_ref", arrival_time), "referral is scheduled once")
	check(people.referrals.effect_ref.state == "scheduled", "planned referral is not yet a completed service")
	# Remove the other planned visit from this isolated scenario to focus on referral.
	people.arrivals.return_later.state = "left"
	People.advance(people, config, arrival_time)
	check(people.referrals.effect_ref.state == "arrived", "referral marks actual arrival")
	check(People.begin(people, "arrival_effect_ref", "visit_referred"), "referred guest begins reception")
	check(people.referrals.effect_ref.state == "in_service", "arrival is not mislabeled as completed")
	check(People.finish(people, "arrival_effect_ref", "visit_referred", "来客完成了咨询") and people.referrals.effect_ref.state == "completed", "referral completes only after service")
	var boundary := People.create("save_boundary", 31, 540)
	People.plan_day(boundary, config, 0, 0, 2)
	var old: Dictionary = boundary.arrivals.arrival_0_0
	var newcomer: Dictionary = boundary.arrivals.arrival_0_1
	old.at = 600
	old.schedule_end = 1000
	old.urgency = 0
	newcomer.at = 1100
	newcomer.schedule_end = 1200
	People.advance(boundary, config, 600)
	newcomer.at = old.deadline
	People.advance(boundary, config, int(old.deadline))
	check(old.state == "left" and newcomer.state == "queued", "deadline is processed before a simultaneous new arrival")
	var days := People.create("save_days", 91, 540)
	check(People.advance_with_schedule(days, config, 2 * 1440), "multi-day time advances")
	check(days.days.has("0") and days.days.has("1") and int(days.clock) == 2 * 1440, "cross-day advance plans each intervening day")
	_test_overflow_choices(config)
	var low_bias := People.create("save_low_bias", 51, 1980)
	People.plan_day(low_bias, config, 1, 0, 2)
	for id: String in low_bias.arrivals:
		var row: Dictionary = low_bias.arrivals[id]
		row.at = 2040
		row.schedule_end = 2240
		row.urgency = 20
		low_bias.profiles[row.npc_id].base_patience = 45
		low_bias.profiles[row.npc_id].return_bias = -80
	People.advance(low_bias, config, 2040)
	check(low_bias.profiles[low_bias.arrivals.arrival_1_1.npc_id].return_bias <= -80, "capacity departure never increases an already lower return bias")
	print("ARRIVAL EDGES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_overflow_choices(config: Dictionary) -> void:
	var people := People.create("save_overflow_choices", 51, 1980)
	People.plan_day(people, config, 1, 0, 4)
	var ids: Array[String] = ["arrival_1_0", "arrival_1_1", "arrival_1_2", "arrival_1_3"]
	var scores := [85, 85, 45, 25]
	for index: int in range(ids.size()):
		var row: Dictionary = people.arrivals[ids[index]]
		row.at = 2040
		row.schedule_end = 2240
		row.urgency = 0
		people.profiles[row.npc_id].base_patience = scores[index]
		people.profiles[row.npc_id].trust = 0
	var departing_profile: Dictionary = people.profiles[people.arrivals[ids[3]].npc_id]
	var return_before := int(departing_profile.return_bias)
	var expected_return_bias := maxi(int(config.arrival.overflow.return_bias_min), return_before - int(config.arrival.overflow.return_bias_penalty))
	var lost_before := int(people.stats.get("lost_customers", 0))
	check(People.advance(people, config, 2040), "simultaneous arrivals are processed by the real queue")
	check(people.arrivals[ids[0]].state == "queued" and People.visible_queue(people).size() == 1, "overflow never expands the indoor queue beyond capacity")
	check(people.arrivals[ids[1]].state == "outside" and int(people.arrivals[ids[1]].deadline) > 2040, "patient customer waits outside with a finite deadline")
	check(people.arrivals[ids[2]].state == "appointment_requested", "moderately urgent customer leaves an appointment request")
	check(people.arrivals[ids[3]].state == "left" and int(people.stats.get("lost_customers", 0)) == lost_before + 1 and int(departing_profile.return_bias) == expected_return_bias, "urgent customer leaves once, increments loss and applies the configured return-bias penalty")
	var snapshot := people.duplicate(true)
	People.advance(people, config, 2040)
	check(people == snapshot, "repeated time advancement does not repeat overflow consequences")
	check(People.validate(people).is_empty(), "outside waiting and appointment requests are valid persisted arrivals")
	var outside: Dictionary = people.arrivals[ids[1]]
	var original_deadline := int(outside.deadline)
	check(People.begin(people, ids[0], "visit_overflow_first"), "first customer begins service and opens an indoor slot")
	People.advance(people, config, 2040)
	check(outside.state == "queued" and int(outside.deadline) == original_deadline and People.visible_queue(people).size() == 1, "outside customer fills a vacant slot without refreshing patience")
	var requested: Dictionary = people.arrivals[ids[2]]
	var before_booking := people.duplicate(true)
	check(not People.book(people, requested.arrival_id, 3480, false, config) and people == before_booking, "appointment request requires the customer to agree before booking")
	check(People.book(people, requested.arrival_id, 3480, true, config) and requested.state == "planned" and requested.source == "appointment", "agreed appointment request becomes a persisted future appointment")

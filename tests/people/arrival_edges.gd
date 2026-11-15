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
	second.urgency = 0
	People.advance(people, config, 600)
	check(first.state == "queued" and second.state == "left" and second.reason == "候客区已满", "queue capacity and deterministic order")
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
	print("ARRIVAL EDGES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

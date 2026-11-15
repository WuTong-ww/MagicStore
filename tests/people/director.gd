extends SceneTree

const People = preload("res://scripts/people/people.gd")
const Director = preload("res://scripts/people/director.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DIRECTOR FAIL: " + label)

func _initialize() -> void:
	var people := People.create("save_director", 42, 540)
	People.add_fixed(people, "npc_lin", "林照晚", "旧书修复师")
	var effect := {"recipient": "A", "effect_id": "effect_ref", "event_id": "event_1", "npc_id": "npc_lin", "kind": "referral", "amount": 1}
	check(People.apply_effect(people, effect), "source event creates a real referral")
	var rows := Director.candidates(people, "npc_lin", "event_1", 1440 + 600)
	check(rows.size() == 2 and Director.public_candidates(rows)[1].size() == 2, "only public candidate fields are sent to the model")
	var before := people.duplicate(true)
	check(not Director.apply(people, "npc_lin", {"trigger_id": "event_1", "candidate_id": "invented"}, 1440 + 600) and people == before, "invented candidate changes nothing")
	check(not Director.apply(people, "npc_lin", {"trigger_id": "event_other", "candidate_id": "director_effect_ref"}, 1440 + 600), "referral cannot use a different event")
	check(Director.apply(people, "npc_lin", {"trigger_id": "event_1", "candidate_id": "director_effect_ref"}, 1440 + 600), "authorized candidate schedules a known person")
	check(people.referrals.effect_ref.state == "scheduled" and people.arrivals.arrival_effect_ref.npc_id == "npc_lin_friend", "referral retains real target and source")
	check(not Director.apply(people, "npc_lin", {"trigger_id": "event_1", "candidate_id": "director_effect_ref"}, 1440 + 600), "same event cannot schedule repeatedly")
	check(People.validate(people).is_empty(), "director record validates with A state")
	print("DIRECTOR RULES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

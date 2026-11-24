extends SceneTree
## Exercises B's real invitation and A's independent adapters; this is not
## the final C-owned GameState/save integration.

const People = preload("res://scripts/people/people.gd")
const Memory = preload("res://scripts/people/memory.gd")
var gs: Node
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("A/B HANDOFF FAIL: " + label)

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var request := {"type": kind, "action_id": gs.make_id("a_b_test")}
	request.merge(fields, true)
	var result: Dictionary = gs.execute_action(request)
	check(result.success, kind + " / " + str(result.message))
	return result

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	gs = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	gs.daily_loop_config.enabled = false
	var saves: Node = root.get_node("SaveService")
	saves.base_dir = "user://test-runs/" + gs.make_id("people_b")
	act("new_game", {"name": "A/B 隔离联调"})
	act("start_visit")
	var case: Dictionary = gs.divination_view()
	act("talk", {"text": "为什么还没回信？", "topic_id": "letter"})
	act("reading")
	act("record_prediction", {"subject_id": case.event.subject_id, "text": "她们能说上话", "condition": "always",
		"expected": "met", "window_start": case.event.due_at, "window_end": int(case.event.due_at) + 30})
	act("give_advice", {"advice_key": "message"})
	act("end_visit")
	act("next_day")
	var jobs: Array = gs.divination_feedback_queue()
	check(jobs.size() == 1 and jobs[0].mode == "delayed", "B exposes a due feedback job")
	var people := {}
	var scheduled := false
	for seed_value in range(100):
		people = People.create(gs.state.save_id, seed_value, int(gs.state.clock_minutes))
		People.add_fixed(people, "npc_lin", "林照晚", "旧书修复师")
		people.profiles.npc_lin.met = true
		if People.schedule_feedback(people, jobs[0]) and people.feedback_jobs[jobs[0].event_id].state == "scheduled":
			scheduled = true
			break
	check(scheduled, "A can schedule the B feedback without revealing it before the event")
	if not scheduled:
		quit(1)
		return
	var task: Dictionary = people.feedback_jobs[jobs[0].event_id]
	check(int(task.at) >= int(jobs[0].available_at), "A does not schedule before B's disclosure time")
	var return_visit := act("start_visit")
	act("talk", {"text": "邀请上写了什么？", "topic_id": "invitation"})
	check(People.advance(people, People.load_config(), int(gs.state.clock_minutes)), "A advances to the same game minute")
	check(People.begin(people, task.arrival_id, return_visit.result.visit_id), "A binds the actual B return visit")
	var disclosed := act("receive_feedback", {"event_id": jobs[0].event_id})
	check(People.record_disclosed_feedback(people, disclosed.result.feedback), "B disclosed report is recorded as shared A memory")
	check(not People.record_disclosed_feedback(people, disclosed.result.feedback), "the same B report cannot be recorded twice")
	check(Memory.visible(people, "npc_lin", "player").size() == 1, "player can review only the disclosed feedback")
	var effects: Array = gs.divination_effects("A")
	check(effects.any(func(effect: Dictionary) -> bool: return effect.kind == "referral" and effect.get("target_npc_id") == "npc_lin_friend" and not effect.has("template")), "B names the established friend instead of requesting an ordinary stranger")
	var profile_count: int = people.profiles.size()
	var friend_before: Dictionary = people.profiles.npc_lin_friend.duplicate(true)
	for effect: Dictionary in effects:
		check(People.apply_effect(people, effect), "apply B effect " + effect.kind)
		check(not People.apply_effect(people, effect), "B effect is not applied twice")
	check(people.profiles.npc_lin.trust == 2, "B-aligned feedback updates Lin trust")
	check(people.referrals.size() == 1 and people.referrals.values()[0].target_npc_id == "npc_lin_friend", "referral targets the established friend")
	check(people.profiles.size() == profile_count and people.profiles.npc_lin_friend == friend_before, "two-argument consumption preserves the existing friend and creates no extra visitor")
	check(People.validate(people).is_empty(), "A state remains valid after B handoff")
	print("A/B HANDOFF: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

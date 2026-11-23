extends SceneTree
## Integration checks use real GameState and SaveService with isolated storage.

const Bridge = preload("res://scripts/shop/people_bridge.gd")
const People = preload("res://scripts/people/people.gd")
const Memory = preload("res://scripts/people/memory.gd")
var gs: Node
var saves: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PEOPLE INTEGRATION: " + description)

func act(kind: String, extra: Dictionary = {}) -> Dictionary:
	var action := {"type": kind, "action_id": gs.make_id("integration_people")}
	action.merge(extra, true)
	var result: Dictionary = gs.execute_action(action)
	check(result.success, kind + " / " + str(result.get("message", "")))
	return result

func run() -> void:
	gs = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "user://test-runs/" + gs.make_id("people_integration")
	act("new_game", {"name": "人物与公共事务整合"})
	# G2 increments only the current schema destination; existing A/B/C boundaries remain.
	check(gs.state.schema_version == 8 and Bridge.validate(gs.state).is_empty(), "new integrated save validates")
	check(not gs.player_snapshot().has("people"), "public snapshot hides future arrivals and relationships")
	var queue: Array = Bridge.public_view(gs.state).queue
	check(queue.any(func(row: Dictionary) -> bool: return row.npc_id == "npc_lin"), "handwritten opening enters actual queue")
	var lin: Dictionary = queue.filter(func(row: Dictionary) -> bool: return row.npc_id == "npc_lin")[0]
	var started := act("start_arrival", {"arrival_id": lin.arrival_id})
	var visit_id: String = started.result.get("visit_id", "")
	check(gs.state.people.arrivals[lin.arrival_id].visit_id == visit_id, "queue and B case use same visit")
	var talk := act("talk", {"text": "为什么还没回信？", "topic_id": "letter"})
	check(Memory.dialogue_context(gs.state.people, "npc_lin").size() == 1, "validated dialogue becomes shared memory")
	check(People.visible_relationships(gs.state.people, "npc_lin").size() == 1, "witnessed topic reveals corresponding relationship")
	var unchanged: Dictionary = gs.snapshot()
	saves.fail_next_write = true
	var failed: Dictionary = gs.execute_action({"type": "end_visit", "action_id": "failed_finish_people"})
	check(not failed.success and gs.snapshot() == unchanged, "failed save rolls back A familiarity and queue together")
	act("end_visit")
	check(gs.state.people.arrivals[lin.arrival_id].state == "completed", "finish completes actual arrival")
	check(gs.state.people.profiles.npc_lin.familiarity == 1, "finished encounter contributes familiarity once")
	var before: Dictionary = gs.snapshot()
	act("load_game", {"save_id": before.save_id})
	check(gs.state.people == saves._normalize_numbers(before.people) and gs.state.npcs == before.npcs, "reload preserves people and wallets with canonical JSON numbers")
	var broken: Dictionary = gs.snapshot()
	broken.people.clock += 1
	check(not Bridge.validate(broken).is_empty(), "cross-module validator rejects independent A clock")
	broken = gs.snapshot()
	broken.people.arrivals[lin.arrival_id].visit_id = "visit_missing"
	check(not Bridge.validate(broken).is_empty(), "cross-module validator rejects orphan encounter")
	# A reproducible uncommon waiting branch; production code does not force arrivals.
	var waiting_id := "arrival_test_waiting"
	var waiting: Dictionary = Bridge._arrival(waiting_id, "npc_lin_friend", int(gs.state.clock_minutes) + 1, "natural", "archive")
	waiting.schedule_end = int(gs.state.clock_minutes) + 20
	waiting.intent = "shopping"
	gs.state.people.arrivals[waiting_id] = waiting
	act("wait", {"minutes": 5})
	check(gs.state.people.arrivals[waiting_id].state == "queued", "shared waiting advances incoming customer")
	var untouched_time := int(gs.state.clock_minutes)
	Bridge.public_view(gs.state)
	Bridge.public_view(gs.state)
	check(int(gs.state.clock_minutes) == untouched_time, "reading public views never advances patience")
	var booking_before: Dictionary = gs.snapshot()
	var declined: Dictionary = gs.execute_action({"type": "book_arrival", "action_id": "booking_no_consent", "arrival_id": waiting_id, "at": untouched_time + 1440, "guest_agreed": false})
	check(not declined.success and gs.snapshot() == booking_before, "appointment needs explicit guest consent")
	act("wait", {"minutes": 20})
	check(gs.state.people.arrivals[waiting_id].state == "left", "one unified clock expires queue")
	check(int(gs.state.people.clock) == int(gs.state.clock_minutes), "A projection follows shared time")
	var confirmed: Dictionary = gs.snapshot()
	act("load_game", {"save_id": confirmed.save_id})
	check(gs.state.people.arrivals[waiting_id].state == "left", "departure survives save and reload")
	check(Bridge.validate(gs.state).is_empty(), "final cross-module references remain valid")
	check(not talk.result.is_empty(), "talk result retained")
	feedback_integration()
	print("PEOPLE INTEGRATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func feedback_integration() -> void:
	act("new_game", {"name": "真实案例反馈整合"})
	# Eliminate unrelated random traffic only in this reproducible test fixture.
	for id: String in gs.state.people.arrivals.keys():
		if id != "arrival_opening_lin":
			gs.state.people.arrivals.erase(id)
	for day: Dictionary in gs.state.people.days.values():
		day.arrival_ids = []
	act("start_arrival", {"arrival_id": "arrival_opening_lin"})
	act("talk", {"text": "为什么还没回信？", "topic_id": "letter"})
	act("reading")
	var case: Dictionary = gs.divination_view()
	act("record_prediction", {"text": "两人会在约定时段见面", "subject_id": case.event.subject_id,
		"expected": "met", "condition": "always", "window_start": case.event.due_at, "window_end": int(case.event.due_at) + 30})
	act("give_advice", {"advice_key": "message"})
	# Choose a deterministic admitted feedback branch instead of depending on chance.
	gs.state.people.profiles.npc_lin.trust = 80
	for seed_value in range(100):
		var rng := People._random(seed_value + absi(String(case.event.event_id).hash()))
		if rng.randi_range(1, 100) <= 90:
			gs.state.people.seed = seed_value
			break
	act("end_visit")
	var due := int(case.event.due_at)
	while int(gs.state.clock_minutes) < due:
		act("wait", {"minutes": mini(180, due - int(gs.state.clock_minutes))})
	var jobs: Dictionary = gs.state.people.feedback_jobs
	check(jobs.has(case.event.event_id) and jobs[case.event.event_id].state == "scheduled", "real B result schedules actual A feedback")
	if not jobs.has(case.event.event_id) or jobs[case.event.event_id].state != "scheduled":
		return
	var job: Dictionary = jobs[case.event.event_id]
	check(int(job.at) >= due and int(job.at) >= int(gs.divination_feedback_queue()[0].available_at), "A feedback respects B disclosure window")
	while int(gs.state.clock_minutes) < int(job.at):
		act("wait", {"minutes": mini(180, int(job.at) - int(gs.state.clock_minutes))})
	act("start_arrival", {"arrival_id": job.arrival_id})
	var feedback := act("receive_feedback", {"event_id": case.event.event_id})
	check(gs.state.people.feedback_jobs[case.event.event_id].state == "reported", "B disclosure marks actual A feedback visit reported")
	check(Memory.dialogue_context(gs.state.people, "npc_lin").any(func(row: Dictionary) -> bool: return row.kind == "feedback"), "disclosed B report enters common A memory")
	check(gs.state.people.profiles.npc_lin.trust == 82, "B trust effect applied once to persistent A profile")
	check(gs.state.shop.reputation == 1 and gs.state.shop.boosts.size() == 1, "B reputation and timed boost applied to real C state")
	check(gs.state.people.referrals.size() == 1, "B recommendation uses an actual A relationship")
	var before: Dictionary = gs.snapshot()
	gs._commit(gs.snapshot(), {"type": "wait", "action_id": "feedback_sync_again"}, "test sync", {})
	check(gs.state.people.profiles.npc_lin.trust == 82 and gs.state.shop.reputation == 1 and gs.state.shop.boosts.size() == 1, "repeated sync does not duplicate A or C effects")
	check(gs.state.people.feedback_jobs[case.event.event_id].feedback_id == feedback.result.feedback.feedback_id, "feedback keeps shared source identifier")
	check(Bridge.validate(gs.state).is_empty(), "full feedback graph validates")
	check(not before.active_visit_id.is_empty(), "feedback encounter remains active until ended")

extends SceneTree
## Integration assertions use real GameState + SaveService in a unique test directory.
var gs: Node
var saves: Node
var failures := 0
var checks := 0
var test_dir := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)

func act(kind: String, extra: Dictionary = {}) -> Dictionary:
	var action: Dictionary = {"type": kind, "action_id": gs.make_id("test"), "expected_version": gs.state.get("state_version", 0)}
	action.merge(extra, true)
	return gs.execute_action(action)

func run() -> void:
	gs = root.get_node("GameState")
	saves = root.get_node("SaveService")
	test_dir = "user://test-runs/" + gs.make_id("run")
	saves.base_dir = test_dir
	check(act("new_game", {"name": "自动验收甲"}).success, "create save")
	var first_id: String = gs.state.save_id
	check(gs.state.player.coins == 40 and gs.state.player.energy == 100, "initial resources")
	check(gs.state.clock_minutes == 540, "unified clock starts 09:00")
	check(act("start_visit").success, "start reception")
	var visit_id: String = gs.state.active_visit_id
	var before: Dictionary = gs.snapshot()
	check(act("start_visit").success and gs.state.active_visit_id == visit_id, "reenter retains visit")
	check(gs.state.visits.size() == 1, "scene return cannot multiply visits")
	check(not act("next_day").success, "unfinished reception prevents next day")
	check(act("talk", {"text": "邀请上写了什么？"}).success, "configured question")
	check(act("talk", {"text": "关于那封回信，我想了解更多"}).success, "Chinese free input")
	var clues: int = gs.active_visit().clue_ids.size()
	check(clues > 0, "conversation discovers clue")
	check(act("talk", {"text": "关于那封回信，我想了解更多"}).success, "repeat topic permitted")
	check(gs.active_visit().clue_ids.size() == clues, "clue deduplicated")
	check(act("talk", {"text": "火星章鱼的午饭"}).success, "unknown input clarifies")
	check(str(gs.active_visit().dialogue.back().text).length() > 0, "clarification text stored")
	before = gs.snapshot()
	saves.fail_next_write = true
	check(not act("reading").success, "failed write rejects paid result")
	check(gs.snapshot() == before and gs.active_visit().reading.is_empty(), "failed payment leaves all state unchanged and card hidden")
	var payment_id: String = gs.make_id("payment")
	var result: Dictionary = act("reading", {"action_id": payment_id})
	check(result.success, "paid tarot succeeds")
	check(gs.state.player.coins == before.player.coins + 20 and gs.state.npcs.npc_lin.coins == before.npcs.npc_lin.coins - 20, "both wallets settle together")
	check(gs.state.player.energy == before.player.energy - 25 and gs.state.clock_minutes == before.clock_minutes + 30, "energy and clock settle together")
	var paid: Dictionary = gs.snapshot()
	var card: Dictionary = gs.active_visit().reading.duplicate(true)
	check(act("reading", {"action_id": payment_id, "expected_version": 0}).success, "same action replay precedes stale version")
	check(gs.snapshot() == paid, "same action replay does not mutate")
	check(act("reading").success and gs.active_visit().reading == card, "new action cannot redraw same reception")
	check(gs.state.player == paid.player and gs.state.clock_minutes == paid.clock_minutes, "repeat payment no extra cost")
	gs.state = {}
	check(act("load_game", {"save_id": first_id}).success, "load unfinished paid reception")
	check(gs.active_visit().reading == card and gs.state.active_visit_id == visit_id, "reload original visit and card")
	check(gs.active_visit().dialogue.size() >= 8, "reload dialogue history")
	check(act("reading", {"action_id": payment_id}).success and gs.active_visit().reading == card, "persisted action replay after reload")
	check(act("end_visit").success, "finish reception")
	check(not act("start_visit").success, "same-day repeat visit blocked")
	var rest_before: Dictionary = gs.snapshot()
	check(act("rest").success, "rest succeeds")
	check(gs.state.clock_minutes == rest_before.clock_minutes + 60 and gs.state.player.energy == 100, "rest uses unified clock and caps energy")
	check(act("next_day").success and gs.state.clock_minutes == 1980, "advance to next day 09:00")
	check(act("start_visit").success, "same NPC returns next day")
	check(gs.active_visit().npc_id == "npc_lin" and gs.active_visit().visit_id != visit_id, "stable identity new visit id")
	check(gs.state.visits[0].phase == "ended" and gs.state.visits[0].reading == card, "previous record available")
	var base: Dictionary = gs.snapshot()
	for resource in ["energy", "coins", "time"]:
		gs.state = base.duplicate(true)
		if resource == "energy": gs.state.player.energy = 0
		if resource == "coins": gs.state.npcs.npc_lin.coins = 0
		if resource == "time": gs.state.clock_minutes = 1440 + 1310
		before = gs.snapshot()
		check(not act("reading").success, "reject insufficient " + resource)
		check(gs.snapshot() == before, "no partial mutation for " + resource)
	gs.state = base
	check(not act("rest", {"expected_version": -1}).success, "stale action rejected")
	check(act("new_game", {"name": "自动验收乙"}).success, "new independent save")
	check(gs.state.save_id != first_id and gs.state.visits.is_empty() and gs.state.player.coins == 40, "save isolation")
	check(saves.list_saves().size() == 2, "both saves retained")
	check(act("load_game", {"save_id": first_id}).success and gs.state.visits.size() == 2, "switch restores original progress")
	before = gs.snapshot()
	check(not act("load_game", {"save_id": "missing"}).success and gs.snapshot() == before, "missing save keeps current state")
	check(not saves.read_save("../escape").success, "unsafe save id rejected")
	var bad: Dictionary = before.duplicate(true)
	bad.player.coins = -1
	check(not saves.validate_snapshot(bad).success, "negative wallet rejected")
	bad = before.duplicate(true)
	bad.active_visit_id = "orphan"
	check(not saves.validate_snapshot(bad).success, "invalid visit reference rejected")
	var primary: String = test_dir + "/" + first_id + ".json"
	var file := FileAccess.open(primary, FileAccess.WRITE)
	file.store_string("broken JSON")
	file.close()
	var damaged: Dictionary = saves.read_save(first_id)
	check(not damaged.success and damaged.backup_available, "corruption reported with explicit recovery")
	check(not saves.write_save(before).success, "damaged primary not silently overwritten")
	check(saves.read_save(first_id, true).success, "backup restoration succeeds")
	check(saves.read_save(first_id).success, "restored primary validates")
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(primary)) == OK, "test removes only isolated primary")
	check(saves.list_saves().size() == 2 and saves.read_save(first_id).backup_available, "backup-only save discoverable")
	check(saves.read_save(first_id, true).success, "recover missing primary")
	print("SMOKE RESULT: %d checks, %d failures. Isolated files: %s" % [checks, failures, ProjectSettings.globalize_path(test_dir)])
	quit(0 if failures == 0 else 1)

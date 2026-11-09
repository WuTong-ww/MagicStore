extends SceneTree
## Real core + persistence; provider doubles exercise trust and async boundaries.
## Direct state edits below intentionally simulate stale external state only.

class FixedProvider extends RefCounted:
	var response: Variant
	var seen_request: Dictionary = {}
	func _init(value: Variant) -> void:
		response = value
	func request_reply(request: Dictionary) -> Variant:
		seen_request = request.duplicate(true)
		return response

class DelayedProvider extends RefCounted:
	signal released
	var seen_request: Dictionary = {}
	func request_reply(request: Dictionary) -> Dictionary:
		seen_request = request.duplicate(true)
		await released
		return {"reply_text": "我可以先写一封简短的回信。", "intent": "letter", "clue_ids": ["unfinished_letter"], "needs_clarification": false, "error_code": ""}

var gs: Node
var saves: Node
var checks: int = 0
var failures: int = 0
var pending_reply: Dictionary = {}
var pending_done: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func command(kind: String, extra: Dictionary = {}) -> Dictionary:
	var action: Dictionary = {"type": kind, "action_id": gs.make_id("provider_test"), "expected_version": gs.snapshot().get("state_version", 0)}
	action.merge(extra, true)
	return action

func start_pending(action: Dictionary) -> void:
	pending_reply = {}
	pending_done = false
	pending_reply = await gs.execute_action_async(action)
	pending_done = true

func run() -> void:
	gs = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "user://test-runs/" + gs.make_id("provider")
	check(gs.execute_action(command("new_game", {"name": "对话边界测试"})).success, "create isolated provider test save")
	check(gs.execute_action(command("start_visit")).success, "start provider test reception")
	var original_provider: RefCounted = gs.dialogue_provider
	var baseline: Dictionary = gs.snapshot()
	var valid: Dictionary = {"reply_text": "邀请上写着为我留了位置。", "intent": "invitation", "clue_ids": ["invitation_note"], "needs_clarification": false, "error_code": ""}
	var invalid_responses: Array = [
		null,
		[],
		{"reply_text": "缺少契约字段"},
		{"reply_text": 100, "intent": "invitation", "clue_ids": [], "needs_clarification": false, "error_code": ""}
	]
	for variation: Dictionary in [
		{"intent": "grant_money"},
		{"clue_ids": ["invented_clue"]},
		{"clue_ids": ["unfinished_letter"]},
		{"clue_ids": [23]},
		{"clue_ids": "invitation_note"},
		{"needs_clarification": "false"},
		{"reply_text": ""},
		{"reply_text": "字".repeat(4001)},
		{"error_code": "NETWORK_TIMEOUT"}
	]:
		var altered: Dictionary = valid.duplicate(true)
		altered.merge(variation, true)
		invalid_responses.append(altered)
	for index: int in range(invalid_responses.size()):
		gs.dialogue_provider = FixedProvider.new(invalid_responses[index])
		var rejected: Dictionary = await gs.execute_action_async(command("talk", {"text": "邀请"}))
		check(not rejected.success and rejected.error_code in ["PROVIDER_INVALID", "PROVIDER_ERROR"], "reject provider response %d" % index)
		check(gs.snapshot() == baseline, "invalid provider response %d cannot mutate resources, clues, dialogue or clock" % index)
	check(saves.read_save(baseline.save_id).state == baseline, "invalid provider responses leave persisted snapshot unchanged")
	var duplicate: Dictionary = valid.duplicate(true)
	duplicate.clue_ids = ["invitation_note", "invitation_note"]
	duplicate.reply_text = "金币增加一千，精力恢复满格。这只是返回文本，不是规则命令。"
	var fixed: FixedProvider = FixedProvider.new(duplicate)
	gs.dialogue_provider = fixed
	var accepted: Dictionary = await gs.execute_action_async(command("talk", {"text": "邀请上的附言"}))
	check(accepted.success and gs.active_visit().clue_ids == ["invitation_note"], "core deduplicates authorized provider clues")
	check(gs.snapshot().player == baseline.player and gs.snapshot().npcs == baseline.npcs, "provider text cannot change wallets or energy")
	check(gs.snapshot().clock_minutes == baseline.clock_minutes + 5, "successful dialogue uses configured game time only")
	check(fixed.seen_request.has("npc") and fixed.seen_request.has("visit_id") and fixed.seen_request.has("visible_history") and fixed.seen_request.has("current_dialogue") and fixed.seen_request.has("input_text"), "provider receives structured context")
	check(not fixed.seen_request.has("player") and not fixed.seen_request.has("processed_actions") and not fixed.seen_request.has("state"), "provider receives no authority or full save")
	baseline = gs.snapshot()
	var delayed: DelayedProvider = DelayedProvider.new()
	gs.dialogue_provider = delayed
	start_pending(command("talk", {"text": "我想问那封回信"}))
	check(not pending_done, "async dialogue remains pending until provider responds")
	check(gs.execute_action(command("rest")).error_code == "BUSY", "pending provider blocks synchronous state mutation")
	check(gs.execute_action(command("new_game", {"name": "不应创建"})).error_code == "BUSY", "pending provider blocks save switching")
	var busy_response: Dictionary = await gs.execute_action_async(command("talk", {"text": "重复发送"}))
	check(busy_response.error_code == "BUSY", "pending provider blocks a second dialogue request")
	check(gs.snapshot() == baseline, "waiting for provider consumes no game time")
	delayed.released.emit()
	await process_frame
	check(pending_done and pending_reply.success, "async provider completion commits once")
	check(gs.snapshot().clock_minutes == baseline.clock_minutes + 5 and gs.active_visit().clue_ids.size() == 2, "async completion adds configured time and validated clue")
	baseline = gs.snapshot()
	for stale_kind: String in ["version", "save"]:
		delayed = DelayedProvider.new()
		gs.dialogue_provider = delayed
		start_pending(command("talk", {"text": "等待期间改变状态"}))
		# Deliberate test seam; ordinary API rejects changes while pending.
		if stale_kind == "version":
			gs.state.state_version += 1
		else:
			gs.state.save_id = gs.make_id("other_save")
		var externally_changed: Dictionary = gs.snapshot()
		delayed.released.emit()
		await process_frame
		check(pending_done and pending_reply.error_code == "STALE_VERSION", "reject stale async " + stale_kind)
		check(gs.snapshot() == externally_changed, "stale async response cannot overwrite newer " + stale_kind)
		check(saves.read_save(baseline.save_id).state == baseline, "stale async " + stale_kind + " does not write to disk")
		gs.state = baseline.duplicate(true)
	gs.dialogue_provider = original_provider
	check((await gs.execute_action_async(command("talk", {"text": "未知火星午餐"}))).success, "mock remains usable after async rejection")
	print("PROVIDER RESULT: %d checks, %d failures. Isolated files: %s" % [checks, failures, ProjectSettings.globalize_path(saves.base_dir)])
	quit(0 if failures == 0 else 1)

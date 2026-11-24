extends SceneTree
## Current invitation rewards and already-committed G3 ordinary referrals must
## both survive real save transactions. All files live below isolated .tools.
const People = preload("res://scripts/people/people.gd")
const EventFixture = preload("res://tests/fixtures/event_case_override.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0
var changed := 0
var original_data: Dictionary
var original_base: Dictionary
var original_cache: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("INVITATION REFERRAL FAIL: "+label)

func act(kind: String, extra: Dictionary = {}) -> Dictionary:
	var command := {"type":kind,"action_id":game.make_id("referral_test")}
	command.merge(extra,true)
	var result: Dictionary = await game.execute_action_async(command)
	check(result.get("success",false),kind+" / "+str(result.get("message","")))
	return result

func catalog(value: Dictionary) -> void:
	game._divination.data = value.duplicate(true)
	game._divination._base_catalog = value.duplicate(true)
	saves._divination_data = value.duplicate(true)

func prepare(name: String, fixture_case: String = "") -> Dictionary:
	if not (await act("new_game",{"name":name})).get("success",false):
		return {}
	if not (await act("start_visit")).get("success",false):
		return {}
	if not fixture_case.is_empty():
		EventFixture.bind(game,fixture_case)
	var view: Dictionary = game.divination_view()
	var source := {"visit_id":game.state.active_visit_id,"event_id":view.event.event_id}
	for command: Dictionary in [
		{"type":"talk","topic_id":"letter","text":"为什么还没回信？"},
		{"type":"reading"},
		{"type":"record_prediction","subject_id":view.event.subject_id,"text":"她们能在约定时间说上话","condition":"always","expected":"met","window_start":view.event.due_at,"window_end":int(view.event.due_at)+30},
		{"type":"give_advice","advice_key":"message"},
		{"type":"end_visit"},{"type":"next_day"},{"type":"start_visit"},
		{"type":"talk","topic_id":"invitation","text":"邀请上写了什么？"}
	]:
		if not (await act(command.type,command)).get("success",false):
			return {}
	return source

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	check(game.get("_divination") != null and game.content_error.is_empty(),"rule dependencies initialize")
	if failures:
		finish()
		return
	saves.base_dir = "res://.tools/invitation-referral-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func(): changed += 1)
	original_data = game._divination.data.duplicate(true)
	original_base = game._divination._base_catalog.duplicate(true)
	original_cache = saves._divination_data.duplicate(true)
	var source := await prepare("既定友人推荐事务")
	if source.is_empty():
		finish()
		return
	var before: Dictionary = game.snapshot()
	var disk_before: Dictionary = saves.read_save(before.save_id)
	var friend_before: Dictionary = before.people.profiles.npc_lin_friend.duplicate(true)
	var command := {"type":"receive_feedback","action_id":"receive_invitation_friend_once","event_id":source.event_id}
	changed = 0
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.get("success",true) and game.snapshot() == before and changed == 0,"failed feedback write changes neither model nor visible state")
	check(saves.read_save(before.save_id) == disk_before,"failed feedback leaves the durable save unchanged")
	var retried: Dictionary = await game.execute_action_async(command)
	check(retried.get("success",false) and changed == 1,"same action_id can retry after failed feedback write")
	var referrals: Array = game.state.people.referrals.values()
	check(referrals.size() == 1 and referrals[0].target_npc_id == "npc_lin_friend" and referrals[0].state == "scheduled","real saved feedback recommends the established friend")
	check(game.state.people.profiles.keys() == before.people.profiles.keys() and game.state.people.profiles.npc_lin_friend == friend_before,"recommendation preserves existing identity and creates no random stranger")
	var referral_effects: Array = game.divination_effects("A").filter(func(row: Dictionary) -> bool: return row.kind == "referral")
	check(referral_effects.size() == 1 and referral_effects[0].get("target_npc_id") == "npc_lin_friend" and not referral_effects[0].has("template"),"effect records name the stable friend")
	var committed: Dictionary = game.snapshot()
	var replayed: Dictionary = await game.execute_action_async(command)
	check(replayed.get("success",false) and game.snapshot() == committed and changed == 1,"replayed feedback does not duplicate rewards or publish another state")
	await act("load_game",{"save_id":committed.save_id})
	check(game.state.people.referrals == saves._normalize_numbers(committed.people.referrals),"friend recommendation and its identity survive disk reload")

	# Replay the previous G3 data definition only in this fixture's in-memory
	# catalogs; restore the fixed definition before reading the resulting save.
	var historical := original_data.duplicate(true)
	historical.cases["g3_historical_referral"] = historical.cases.invitation.duplicate(true)
	for effect: Dictionary in historical.cases.g3_historical_referral.event.feedback_effects:
		if effect.kind == "referral":
			effect.erase("target_npc_id")
			effect["template"] = "ordinary"
	catalog(historical)
	var old_source := await prepare("已结算普通客推荐历史","g3_historical_referral")
	if old_source.is_empty():
		finish()
		return
	var old_command := {"type":"receive_feedback","action_id":"historical_ordinary_referral","event_id":old_source.event_id}
	var old_reward: Dictionary = await game.execute_action_async(old_command)
	check(old_reward.get("success",false),"prior G3 ordinary reward commits using its historical content")
	var old_state: Dictionary = game.snapshot()
	var old_referrals: Array = old_state.people.referrals.values()
	check(old_referrals.size() == 1 and old_referrals[0].target_npc_id != "npc_lin_friend" and old_state.people.profiles[old_referrals[0].target_npc_id].template_id == "ordinary_v1","fixture contains an actually settled ordinary referral")
	var current_content := original_data.duplicate(true)
	current_content.cases["g3_historical_referral"] = current_content.cases.invitation.duplicate(true)
	catalog(current_content)
	check(saves.read_save(old_state.save_id).get("success",false),"fixed content still validates already-settled ordinary reward history")
	await act("load_game",{"save_id":old_state.save_id})
	check(game.state.people == saves._normalize_numbers(old_state.people) and game.state.divination.effects == saves._normalize_numbers(old_state.divination.effects),"loading preserves historical targets, profiles and effect IDs")
	var loaded: Dictionary = game.snapshot()
	var old_replay: Dictionary = await game.execute_action_async(old_command)
	check(old_replay.get("success",false) and game.snapshot() == loaded,"historical action replay never replaces its already-settled target")
	await act("wait",{"minutes":1})
	check(game.state.people.referrals == saves._normalize_numbers(old_state.people.referrals),"next successful action keeps the historical recommendation")
	finish()

func finish() -> void:
	if not original_data.is_empty():
		game._divination.data = original_data
		game._divination._base_catalog = original_base
		saves._divination_data = original_cache
	print("INVITATION REFERRAL: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

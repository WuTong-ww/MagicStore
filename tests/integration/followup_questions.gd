extends SceneTree
## Real authority/save checks; the provider double represents reviewed output.
class FixedProvider extends RefCounted:
	var response: Dictionary
	var calls := 0
	func request_reply(_request: Dictionary) -> Dictionary:
		calls += 1
		return response.duplicate(true)

var game: Node
var saves: Node
var checks := 0
var failures := 0
var provider := FixedProvider.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FOLLOWUP CORE: "+label)

func action(kind: String, extra: Dictionary = {}) -> Dictionary:
	var value := {"type":kind,"action_id":game.make_id("followup_core")}
	value.merge(extra,true)
	return value

func output(intent: String, text: String, questions: Variant, clues: Array = []) -> Dictionary:
	return {"intent":intent,"reply_text":text,"clue_ids":clues,"needs_clarification":false,"error_code":"","followup_questions":questions}

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/test-followup-core/"+game.make_id("run")
	game.set_people_generation_options(false)
	check(game.execute_action(action("new_game",{"name":"动态问题整合"})).success,"new isolated save")
	check(game.execute_action(action("start_visit")).success,"begin actual visit")
	var original_provider: RefCounted = game.dialogue_provider
	var first_visit: String = game.active_visit().visit_id
	check(game.conversation_questions().size() == 3,"local questions guide an initial conversation")
	check(game.conversation_questions().all(func(row: Dictionary) -> bool: return row.enabled and not row.generated and row.topic_id != "venue"),"initial questions omit locked directions and make no model claim")
	game.dialogue_provider = provider
	provider.response = output("invitation","邀请上专门写了句话，说给我留了靠窗的位置。",[
		{"topic_id":"work","text":"你最近在修什么书？"},
		{"topic_id":"letter","text":"写回信让你犹豫的是什么？"}
	],["invitation_note"])
	var command := action("talk",{"topic_id":"invitation","text":"邀请上写了什么？"})
	var before: Dictionary = game.snapshot()
	var answer: Dictionary = await game.execute_action_async(command)
	check(answer.success and answer.result.followup_questions.size() == 2,"reviewed questions persist with the actual reply")
	check(game.state.clock_minutes == before.clock_minutes+5 and game.state.player == before.player,"questions add no time, reward or energy cost of their own")
	check(game.active_visit().clue_ids == ["invitation_note"],"suggested topics do not grant their own clues")
	var buttons: Array = game.conversation_questions()
	check(buttons.size() == 3 and buttons.any(func(row: Dictionary) -> bool: return row.topic_id == "work" and row.label == "你最近在修什么书？" and row.generated),"approved wording reaches next-question buttons unchanged")
	check(buttons.any(func(row: Dictionary) -> bool: return row.topic_id == "venue" and not row.generated),"a genuinely unlocked direction can fill the third button after the response")
	check(buttons.any(func(row: Dictionary) -> bool: return row.topic_id == "venue" and row.label == "能核对下入口告示吗？"),"local fallback reads like a short player's question instead of a menu action")
	check(buttons.all(func(row: Dictionary) -> bool: return row.label.length() <= 16),"both generated and local questions stay concise")
	var committed: Dictionary = game.snapshot()
	check(saves.read_save(committed.save_id).state == committed,"questions and source action are saved atomically")
	check((await game.execute_action_async(command)).get("replayed",false) and provider.calls == 1 and game.snapshot() == committed,"replayed action never regenerates or reapplies questions")
	provider.response = output("work","纸页得一张张慢慢晾干，急不得。",[{"topic_id":"letter","text":"回信里最难开口的是什么？"}])
	saves.fail_next_write = true
	answer = await game.execute_action_async(action("talk",{"topic_id":"work","text":"最近修的书呢？"}))
	check(not answer.success and game.snapshot() == committed and game.conversation_questions() == buttons,"failed save preserves old questions, transcript and clock")
	answer = await game.execute_action_async(action("talk",{"topic_id":"work","text":"最近修的书呢？"}))
	check(answer.success and game.active_visit().followup_questions == provider.response.followup_questions,"next successful turn replaces instead of appending suggestions")
	check(game.conversation_questions().any(func(row: Dictionary) -> bool: return row.label == "回信里最难开口的是什么？" and row.generated),"new wording is available through the core projection")
	var saved_id: String = game.state.save_id
	var latest: Dictionary = game.snapshot()
	var altered := latest.duplicate(true)
	altered.visits[0].followup_questions[0].text = "篡改后的问题？"
	check(not saves.validate_snapshot(altered).success,"stored questions cannot be changed without their original action")
	altered = latest.duplicate(true)
	altered.visits[0].followup_action_id = "missing_action"
	check(not saves.validate_snapshot(altered).success,"questions need a persisted originating talk")
	altered = latest.duplicate(true)
	altered.visits[0].followup_questions = [{"topic_id":"archive","text":"能看看旧借条吗？"}]
	altered.processed_actions[altered.visits[0].followup_action_id].result.followup_questions = altered.visits[0].followup_questions.duplicate(true)
	check(not saves.validate_snapshot(altered).success,"even a matching action cannot attach another case's topic")
	check(game.execute_action(action("new_game",{"name":"隔离另一个店铺"})).success,"switch to a second save")
	check(game.execute_action(action("start_visit")).success and game.active_visit().visit_id != first_visit,"second save has a distinct visit")
	check(not game.conversation_questions().any(func(row: Dictionary) -> bool: return row.generated or row.label == "回信里最难开口的是什么？"),"new visit never inherits another visit's recommendations")
	check(game.execute_action(action("load_game",{"save_id":saved_id})).success,"load the first actual save")
	check(game.conversation_questions().any(func(row: Dictionary) -> bool: return row.generated and row.label == "回信里最难开口的是什么？"),"reload restores its own approved questions")
	before = game.snapshot()
	check(game.configure_api("http://127.0.0.1:1/v1/chat/completions","first-model","loopback-key").success and game.configure_api("http://127.0.0.1:1/v1/chat/completions","second-model","").success and game.snapshot() == before,"mid-visit model changes leave question and gameplay records untouched")
	game.dialogue_provider = provider
	provider.response = output("work","纸页要一张张慢慢晾。",[{"topic_id":"foreign_case","text":"别人的秘密是什么？"},{"topic_id":"letter","text":"http://bad.example"}])
	answer = await game.execute_action_async(action("talk",{"topic_id":"work","text":"说说修书吧。"}))
	check(answer.success and game.active_visit().followup_questions.is_empty(),"invalid suggestions are discarded without losing a valid reply")
	check(game.conversation_questions().all(func(row: Dictionary) -> bool: return not row.generated and row.enabled),"safe local directions remain usable after malformed suggestions")
	provider.response.erase("followup_questions")
	check((await game.execute_action_async(action("talk",{"topic_id":"work","text":"我在听。"}))).success,"legacy provider remains compatible")
	check(saves.read_save(saved_id).success,"all new optional records remain reloadable")
	game.dialogue_provider = original_provider
	print("FOLLOWUP CORE RESULT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

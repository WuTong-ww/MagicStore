extends SceneTree
## A real public-context mock reply drives the complete GameState/save route.
class PublicContextProvider extends RefCounted:
	const Mock = preload("res://scripts/providers/mock_dialogue_provider.gd")
	const Policy = preload("res://scripts/providers/dialogue_policy.gd")
	var delegate = Mock.new()
	var calls := 0
	var questions: Array = []
	var questions_legal := true
	var request_case := ""
	func configure(topics: Array) -> void:
		delegate.configure(topics)
	func update_topics(topics: Array) -> void:
		delegate.configure(topics)
	func request_reply(request: Dictionary) -> Dictionary:
		calls += 1
		request_case = str(request.get("case_id",""))
		var context: Dictionary = Policy.build_context(request,delegate.topics)
		for question: Dictionary in questions:
			if not context.get("question_topics",[]).any(func(row:Dictionary)->bool:return row.topic_id==question.topic_id):
				questions_legal = false
		var response: Dictionary = delegate.request_reply(request)
		response["followup_questions"] = questions.duplicate(true)
		return response
var game: Node
var saves: Node
var checks := 0
var failures := 0
var changes := 0
var sequence := 0
var provider := PublicContextProvider.new()
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STORY FOLLOWUP FAIL: "+label)
func command(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var result := {"type":kind,"action_id":"story_followup_"+str(sequence)}
	result.merge(fields,true)
	return result
func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var result: Dictionary = await game.execute_action_async(command(kind,fields))
	check(result.success,kind+" / "+str(result.get("message","")))
	return result
func visible_matches(questions: Array) -> bool:
	var rows: Array = game.conversation_questions()
	return questions.all(func(question:Dictionary)->bool:return rows.any(func(row:Dictionary)->bool:return row.generated and row.topic_id==question.topic_id and row.label==question.text))
func recorded_matches(id: String, questions: Array) -> bool:
	var visit: Dictionary = game.active_visit()
	return visit.get("followup_action_id")==id and visit.get("followup_questions")==questions and game.state.processed_actions.get(id,{}).get("result",{}).get("followup_questions")==questions
func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/story-followup-transactions/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func():changes+=1)
	if not (await act("new_game",{"name":"自由提问保存回归"})).success or not (await act("read_morning_letters")).success or not (await act("next_customer")).success:
		finish()
		return
	check(game.state.schema_version==saves.CURRENT_SCHEMA and game.case_board_view().enabled,"exercise the current-schema sequential story board")
	await act("set_free_question",{"enabled":true})
	check(game.free_question_enabled(),"saved preference enables the real free-question route")
	provider.configure(game._divination.data.topics+game.content.topics)
	game.dialogue_provider = provider
	provider.questions = [{"topic_id":"work","text":"你最近在修什么书？"},{"topic_id":"letter","text":"回信让你犹豫什么？"}]
	var first := command("talk",{"topic_id":"invitation","text":"邀请上写了什么？"})
	var before: Dictionary = game.snapshot()
	var board_before: Dictionary = before.divination.cases[before.active_visit_id].board.duplicate(true)
	var answered: Dictionary = await game.execute_action_async(first)
	check(answered.success,"real free question saves through GameState")
	if not answered.success:
		finish()
		return
	var first_questions: Array = answered.result.get("followup_questions",[])
	check(provider.questions_legal and provider.request_case=="invitation" and first_questions==provider.questions,"reviewed mock questions use only actual public-context directions")
	check(answered.result.reply_text==game._divination.data.topic_index.invitation.reply_text,"NPC answer comes from the production authored mock rather than invented world facts")
	check(recorded_matches(first.action_id,first_questions),"successful reply questions equal the persistent active-visit fields and original action result")
	check(visible_matches(first_questions),"public next-question buttons show the same persistent suggestions")
	check(game.state.divination.cases[before.active_visit_id].board==board_before,"free questions do not change deduction answers, order or board phase")
	check(game.state.clock_minutes==int(before.clock_minutes)+int(game.daily_loop_config.question_minutes),"suggestions add no time beyond the configured talk action")
	var first_committed: Dictionary = game.snapshot()
	check(saves.read_save(first_committed.save_id).get("state",{})==first_committed,"successful followup fields are present in the durable full snapshot")
	var calls := provider.calls
	var published := changes
	var replay: Dictionary = await game.execute_action_async(first)
	check(replay.success and replay.get("replayed",false) and provider.calls==calls and game.snapshot()==first_committed and changes==published,"same-ID successful replay never regenerates or republishes suggestions")
	provider.questions = [{"topic_id":"letter","text":"回信里最难开口什么？"}]
	var second := command("talk",{"topic_id":"work","text":"最近修书的工作呢？"})
	var old_buttons: Array = game.conversation_questions().duplicate(true)
	var sha := FileAccess.get_sha256(saves._path(first_committed.save_id))
	published = changes
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(second)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED","second free question reaches the real failing persistence boundary")
	check(game.snapshot()==first_committed and game.conversation_questions()==old_buttons and recorded_matches(first.action_id,first_questions) and changes==published,"failed write leaks no new transcript, followup, source action or visible state")
	check(FileAccess.get_sha256(saves._path(first_committed.save_id))==sha and saves.read_save(first_committed.save_id).get("state",{})==first_committed,"failed followup save preserves exact original bytes and durable fields")
	var retried: Dictionary = await game.execute_action_async(second)
	check(retried.success,"same failed action ID can retry the real free question")
	if not retried.success:
		finish()
		return
	var latest_questions: Array = retried.result.get("followup_questions",[])
	check(latest_questions==provider.questions and recorded_matches(second.action_id,latest_questions) and visible_matches(latest_questions),"retry replaces displayed and persisted suggestions with the same reviewed questions")
	check(changes==published+1,"successful retry publishes once")
	var latest: Dictionary = game.snapshot()
	check(saves.read_save(latest.save_id).get("state",{})==latest,"retry writes the complete new followup/source record")
	calls = provider.calls
	published = changes
	replay = await game.execute_action_async(second)
	check(replay.success and replay.get("replayed",false) and provider.calls==calls and changes==published and game.snapshot()==latest,"second replay duplicates neither provider calls nor durable or displayed questions")
	var loaded: Dictionary = await game.execute_action_async(command("load_game",{"save_id":latest.save_id}))
	check(loaded.success and game.snapshot()==latest and recorded_matches(second.action_id,latest_questions) and visible_matches(latest_questions),"real reload restores exactly the same displayed, visit and processed-action followup records")
	check(provider.questions_legal,"all provider suggestions remained legal public directions")
	finish()
func finish() -> void:
	print("STORY FOLLOWUP TRANSACTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

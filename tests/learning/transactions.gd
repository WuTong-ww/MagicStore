extends SceneTree
const Store = preload("res://scripts/learning/learning_store.gd")
const Rules = preload("res://scripts/learning/learning_rules.gd")
const Mechanics = preload("res://scripts/learning/method_mechanics.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("LEARN TRANSACTION FAIL: "+label)
func run() -> void:
	game = root.get_node("GameState"); saves = root.get_node("SaveService")
	game.configure_api("","",""); game.set_people_generation_options(false)
	saves.base_dir = "res://.tools/r3-learn/transactions/"+game.make_id("run")
	var created: Dictionary = await game.execute_action_async({"type":"new_game","name":"技法实作验证","action_id":game.make_id("new")})
	check(created.success,"actual fresh schema18 game")
	if not created.success: printerr(created); quit(1); return
	check(game.state.schema_version == 18 and game.state.learning.progress.courses.tarot.origin == "unlearned" and game.state.divination.skills == ["tarot"],"basic tarot remains available without a false mastery stamp")
	var b := Store.bundle(game._divination.data)
	for definition: Dictionary in b.definitions.values(): check(not Mechanics.annotation(definition).is_empty(),"hash-bound practice hints / "+definition.id)
	for definition: Dictionary in Schema.load_all(game._divination.data).values(): check(not Mechanics.annotation(definition).is_empty(),"hash-bound fixed hints / "+definition.id)
	var before: Dictionary = game.snapshot()
	var command := {"type":"purchase_method_book","method_id":"tarot","action_id":game.make_id("buy"),"expected_version":before.state_version}
	var path: String = saves._path(before.save_id)
	var sha := FileAccess.get_sha256(path)
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.success and failed.error_code == "SAVE_WRITE_FAILED" and game.snapshot() == before and FileAccess.get_sha256(path) == sha,"book write failure charges nothing and does not publish a book")
	saves.fail_next_write = false
	var bought: Dictionary = await game.execute_action_async(command)
	check(bought.success and game.state.player.coins == int(before.player.coins)-int(b.config.methods.tarot.book_price),"same ID retries the real book purchase once")
	if not bought.success: printerr(bought); quit(1); return
	var committed: Dictionary = game.snapshot()
	check((await game.execute_action_async(command)).get("replayed",false) and game.snapshot() == committed,"book purchase replay never charges twice")
	var fee: Dictionary = await game.execute_action_async({"type":"pay_method_tuition","method_id":"tarot","action_id":game.make_id("fee")})
	check(fee.success,"zero tuition still creates a real single receipt")
	var world := Store.world_projection(game.snapshot())
	var start: Dictionary = await game.execute_action_async({"type":"practice_start","method_id":"tarot","action_id":game.make_id("practice")})
	check(start.success and Store.world_projection(game.snapshot()) == world,"practice starts through a real commit without changing the town")
	if not start.success: printerr(start); quit(1); return
	var active: Dictionary = game.state.learning.progress.fiction.runs[game.state.learning.active_run_id]
	var definition: Dictionary = b.definitions[active.definition_id]
	var question: Dictionary = await game.execute_action_async({"type":"practice_step","run_id":active.run_id,"operation":{"type":"case_question","question_id":definition.questions[0][0].id},"action_id":game.make_id("question")})
	check(question.success and Store.world_projection(game.snapshot()) == world,"real practice question persists fiction only")
	if not question.success: printerr(question)
	check(saves.validate_snapshot(game.snapshot()).get("success",false),"course references tie back to real book, fee, start and step receipts")
	for stage: int in range(3):
		if stage > 0:
			var next: Dictionary = await game.execute_action_async({"type":"practice_start","method_id":"tarot","action_id":game.make_id("practice")})
			check(next.success,"real next lesson "+str(stage))
			if not next.success: printerr(next); quit(1); return
		active = game.state.learning.progress.fiction.runs[game.state.learning.active_run_id]
		var operations := preload("res://tests/learning/solve.gd").operations(active,b)
		check(not operations.is_empty(),"real lesson has a player-shaped solution")
		for operation: Dictionary in operations:
			var reply: Dictionary = await game.execute_action_async({"type":"practice_step","run_id":active.run_id,"operation":operation,"action_id":game.make_id("step")})
			check(reply.success and Store.world_projection(game.snapshot()) == world,"committed fictional operation preserves every world field / "+str(operation.type))
			if not reply.success: printerr(reply); quit(1); return
	check(game.state.learning.progress.courses.tarot.origin == "course" and game.state.learning.progress.courses.tarot.practice_refs.size() == 3,"three saved lessons grant actual mastery")
	check(game.state.learning.progress.courses.tarot.use_refs.is_empty(),"practice grants no real-case proficiency")
	var letters: Dictionary = await game.execute_action_async({"type":"read_morning_letters","action_id":game.make_id("letters")})
	var visit: Dictionary = await game.execute_action_async({"type":"next_customer","action_id":game.make_id("visit")})
	check(letters.success and visit.success,"real first customer after the lessons")
	var real_definition: Dictionary = Schema.load_all(game._divination.data).fixed_invitation
	for index: int in range(3):
		var answer: Dictionary = await game.execute_action_async({"type":"case_question","question_id":real_definition.questions[index][0].id,"action_id":game.make_id("ask")})
		check(answer.success,"real case question")
	for index: int in range(3):
		var card: Dictionary = await game.execute_action_async({"type":"case_flip_card","card_index":index,"action_id":game.make_id("flip")})
		check(card.success,"real card grants actual observed use")
	check(game.state.learning.progress.courses.tarot.use_refs.size() == 3 and Mechanics.level(game.state,"tarot",b.config) == 2,"three actual case uses reach level two")
	check(saves.validate_snapshot(game.snapshot()).get("success",false),"actual mastery and uses survive full save validation")
	var tampered: Dictionary = game.snapshot()
	tampered.learning.progress.courses.tarot.use_refs.append("invented_use")
	check(not saves.validate_snapshot(tampered).get("success",false),"invented proficiency is rejected")
	print("LEARN TRANSACTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

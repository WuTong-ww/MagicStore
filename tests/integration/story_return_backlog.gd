extends SceneTree
## Retain genuine interrupted story appointments; reoffer their unserved returns.
var game: Node
var saves: Node
var checks := 0
var failures := 0
var sequence := 0
var config: Dictionary
var definitions: Dictionary
var tao_rule := ""
var epilogue_rule := ""
var interrupted_tao := false
var interrupted_epilogue := false
var met_epilogue := false
var old_ids: Array = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STORY RETURN BACKLOG FAIL: "+label)
func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var command := {"type":kind,"action_id":"story_return_"+str(sequence)}
	command.merge(fields,true)
	var result: Dictionary = await game.execute_action_async(command)
	check(result.success,kind+" / "+str(result.get("message","")))
	return result
func current_has(rule_id: String) -> bool:
	return game.state.daily_loop.arrival_ids.any(func(id:String)->bool:return game.state.people.arrivals[id].get("story_rule_id")==rule_id)
func interrupt(rule_id: String) -> bool:
	for id: String in game.state.daily_loop.arrival_ids:
		if game.state.people.arrivals[id].get("story_rule_id")==rule_id:
			old_ids.append(id)
	game.daily_loop_config.enabled = false
	if not (await act("next_day")).success:
		return false
	game.daily_loop_config.enabled = true
	if not (await act("read_morning_letters")).success:
		return false
	check(current_has(rule_id),"an actually interrupted unserved return is reoffered / "+rule_id)
	return true
func solve(id: String) -> bool:
	var rules: Dictionary = config.rules
	var current: Dictionary = game.case_board_view().prelude
	for step: int in range(8):
		if not current.blocks_progress:
			break
		var options: Array = current.options.filter(func(row:Dictionary)->bool:return row.enabled)
		var choice: String = options[0].id
		if current.id==rules.final_prelude.assembly.id:
			choice = rules.final_prelude.assembly.correct_choice_id
		if not (await act("story_choice",{"choice_id":choice})).success:
			return false
		current = game.case_board_view().prelude
	for round_index: int in range(3):
		var questions: Array = game.case_board_view().questions.filter(func(row:Dictionary)->bool:return row.enabled)
		if not (await act("case_question",{"question_id":questions[0].id})).success:
			return false
	for index: int in range(3):
		if not (await act("case_flip_card",{"card_index":index})).success:
			return false
	for slot: Dictionary in game.case_board_view().slots:
		var materials: Array = game.case_board_view().evidence.filter(func(row:Dictionary)->bool:return slot.id in row.slot_ids)
		if not (await act("case_attach_evidence",{"slot_id":slot.id,"evidence_id":materials[0].id})).success:
			return false
		var correct := ""
		for authored: Dictionary in definitions[id].deduction_slots:
			if authored.id==slot.id:
				correct = authored.correct_answer
		if not (await act("case_choose_answer",{"slot_id":slot.id,"answer_id":correct})).success:
			return false
	return (await act("case_close",{"advice_id":rules.cases[id].best_advice_id})).success
func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/story-return-backlog/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var story = load("res://scripts/story/story_content.gd")
	var schema = load("res://scripts/divination/case_schema.gd")
	config = story.load_config()
	definitions = schema.load_all(game._divination.data)
	for definition_id: String in config.rules.case_order:
		for npc: String in config.rules.cases[definition_id].get("followup_npc_ids",[]):
			tao_rule = "followup_"+definition_id+"_"+npc
	epilogue_rule = config.rules.epilogues[0].id
	if not (await act("new_game",{"name":"短访积压真实模式切换"})).success:
		finish()
		return
	for day_index: int in range(14):
		if not interrupted_tao and current_has(tao_rule):
			if not await interrupt(tao_rule):
				finish()
				return
			interrupted_tao = true
		elif not interrupted_epilogue and current_has(epilogue_rule):
			if not await interrupt(epilogue_rule):
				finish()
				return
			interrupted_epilogue = true
		if game.daily_loop_view().phase=="morning" and not (await act("read_morning_letters")).success:
			finish()
			return
		while game.daily_loop_view().completed<game.daily_loop_view().total:
			if not (await act("next_customer")).success:
				finish()
				return
			var row: Dictionary = game.state.people.arrivals[game.active_visit().arrival_id]
			if row.get("story_rule_id")==epilogue_rule:
				met_epilogue = true
			var view: Dictionary = game.case_board_view()
			if view.get("enabled",false) and not await solve(view.id):
				finish()
				return
			if not (await act("end_visit")).success:
				finish()
				return
		if not (await act("close_shop")).success:
			finish()
			return
		if interrupted_tao and interrupted_epilogue:
			check(met_epilogue,"rescheduled ending return actually enters and speaks")
			var tao_count: int = game.state.people.arrivals.values().filter(func(row:Dictionary)->bool:return row.get("story_rule_id")==tao_rule and row.get("state")=="completed").size()
			check(tao_count==1,"ordinary followup actually completes once after its abandoned reservation")
			for id: String in old_ids:
				check(game.state.people.arrivals.has(id) and game.state.people.arrivals[id].state=="planned","original interrupted appointment remains in history / "+id)
			check(saves.validate_snapshot(game.snapshot()).success,"old plans and the real replacement visits validate together")
			await act("next_day")
			check(not current_has(tao_rule) and not current_has(epilogue_rule),"completed real returns never repeat")
			finish()
			return
		if not (await act("next_day")).success:
			finish()
			return
	check(false,"bounded real playthrough reaches both return interruptions")
	finish()
func finish() -> void:
	print("STORY RETURN BACKLOG: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

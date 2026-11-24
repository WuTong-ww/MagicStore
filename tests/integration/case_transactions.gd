extends SceneTree
const Schema = preload("res://scripts/divination/case_schema.gd")
var checks := 0
var failures := 0
var game: Node
var saves: Node
var changes := 0
var sequence := 0
var definition: Dictionary
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("CASE TRANSACTION FAIL: "+label)
func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var command := {"type":kind,"action_id":"case_tx_"+str(sequence)}
	command.merge(fields,true)
	var result: Dictionary = await game.execute_action_async(command)
	check(result.success,kind+" succeeds: "+str(result))
	return result
func retry(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var command := {"type":kind,"action_id":"case_retry_"+str(sequence)}
	command.merge(fields,true)
	var before: Dictionary = game.snapshot()
	var view_before: Dictionary = game.case_board_view()
	var sha := FileAccess.get_sha256(saves._path(before.save_id))
	var visible_before := changes
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED" and game.snapshot()==before and game.case_board_view()==view_before and FileAccess.get_sha256(saves._path(before.save_id))==sha,kind+" failed save leaves memory, public board and bytes unchanged: "+str(failed))
	check(changes==visible_before,kind+" failed save publishes no state change")
	var result: Dictionary = await game.execute_action_async(command)
	check(result.success,kind+" retries same ID: "+str(result))
	var committed: Dictionary = game.snapshot()
	var changes_after := changes
	var replay: Dictionary = await game.execute_action_async(command)
	check(replay.success and replay.get("replayed",false) and game.snapshot()==committed and changes==changes_after,kind+" same-ID replay cannot duplicate or publish")
	check(saves.read_save(committed.save_id).get("state",{})==committed,kind+" is durably identical")
	return result
func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/case-transactions/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func(): changes += 1)
	check(game.content_error.is_empty() and game.has_method("case_board_view"),"core and public getter initialize")
	if not game.has_method("case_board_view"):
		finish()
		return
	definition = Schema.load_all(game._divination.data).get("fixed_invitation",{})
	await branch("message","sent",true,false)
	await branch("attend","arrived",false,false)
	await branch("wait","waited",false,true)
	await wrong_route()
	finish()
func prepare(label: String, skills: bool = false) -> bool:
	if not (await act("new_game",{"name":label})).success:
		return false
	if skills:
		await act("learn_method",{"method_id":"lenormand"})
		await act("learn_method",{"method_id":"plum"})
	await act("read_morning_letters")
	var admitted: Dictionary = await act("next_customer")
	check(admitted.success and game.case_board_view().get("enabled",false),"first sequential customer has a real authored board")
	return admitted.success and game.case_board_view().get("enabled",false)
func basics(retries: bool = false, route: bool = true) -> void:
	for question_id: String in ["invitation_text","letter_written","venue_route" if route else "message_first"]:
		if retries:
			await retry("case_question",{"question_id":question_id})
		else:
			await act("case_question",{"question_id":question_id})
	var energy: int = game.state.player.energy
	var at: int = game.state.clock_minutes
	for index: int in range(3):
		if retries:
			await retry("case_flip_card",{"card_index":index})
		else:
			await act("case_flip_card",{"card_index":index})
	check(game.state.player.energy==energy and game.state.clock_minutes==at+3*int(Schema.load_rules().costs.flip_card.minutes),"three base cards cost only configured time")
func fill(retries: bool = false, wrong: bool = false) -> void:
	for slot: Dictionary in definition.deduction_slots:
		var evidence_id := ""
		for material: Dictionary in game.case_board_view().evidence:
			if slot.id in material.slot_ids:
				evidence_id = material.id
				break
		var answer_id: String = slot.answers[1].id if wrong else slot.correct_answer
		var attached := {"evidence_id":evidence_id,"slot_id":slot.id}
		var chosen := {"slot_id":slot.id,"answer_id":answer_id}
		if retries:
			await retry("case_attach_evidence",attached)
			await retry("case_choose_answer",chosen)
		else:
			await act("case_attach_evidence",attached)
			await act("case_choose_answer",chosen)
func finish_day() -> void:
	await act("end_visit")
	var safety := 0
	while game.daily_loop_view().completed < game.daily_loop_view().total and safety<8:
		safety += 1
		await act("next_customer")
		if not game.active_visit().is_empty():
			await act("end_visit")
	await act("close_shop")
	await act("next_day")
func branch(advice_id: String, outcome_id: String, retries: bool, wrong: bool) -> void:
	if not await prepare("推理事务"+advice_id,retries):
		return
	var visit_id: String = game.state.active_visit_id
	await basics(retries)
	var order: Array = game.state.divination.cases[visit_id].board.card_order.duplicate()
	if retries:
		await retry("case_extra_question",{"question_id":"invitation_assumption"})
		await retry("case_flip_card",{"card_index":3})
		await retry("set_free_question",{"enabled":true})
		check(game.free_question_enabled(),"free question is saved independently of board")
		await retry("set_free_question",{"enabled":false})
		var card_before: Dictionary = game.snapshot()
		var duplicate: Dictionary = await game.execute_action_async({"type":"case_flip_card","action_id":"case_new_id_same_card","card_index":3})
		check(not duplicate.success and game.snapshot()==card_before,"new ID cannot flip the same paid card again")
	await fill(retries,wrong)
	if retries:
		await retry("case_eliminate",{"slot_id":"sender"})
		await retry("case_choose_answer",{"slot_id":"sender","answer_id":definition.deduction_slots[0].correct_answer})
		await retry("case_close",{"advice_id":advice_id,"stars":99,"correct":true})
	else:
		await act("case_close",{"advice_id":advice_id,"stars":99,"correct":true})
	var case: Dictionary = game.state.divination.cases[visit_id]
	check(case.board.phase=="closed" and game.case_board_view().closed and case.stars==(1 if wrong else 3),"backend computes stars and wrong deductions still close")
	check(case.services.is_empty() and not case.prediction.is_empty() and case.advice.size()==1 and case.advice[0].advice_key==advice_id,"close creates real G3 prediction and advice without fabricated service")
	check(case.world_facts==game._divination.data.cases.invitation.world_facts,"questions never rewrite private world truth")
	check(game.active_visit().dialogue.back().mood==case.board.closure.mood,"reaction mood is durable dialogue")
	check(case.board.card_order==order,"all later actions preserve the original card order")
	var saved: Dictionary = game.snapshot()
	await act("load_game",{"save_id":saved.save_id})
	check(game.snapshot()==saved and game.case_board_view().stars==(1 if wrong else 3),"closed board and stars survive reload")
	var before: Dictionary = game.snapshot()
	var duplicate: Dictionary = await game.execute_action_async({"type":"case_close","action_id":"case_close_again_"+advice_id,"advice_id":advice_id})
	check(not duplicate.success and game.snapshot()==before,"different ID cannot close or reward twice")
	await finish_day()
	case = game.state.divination.cases[visit_id]
	check(case.event.occurrence!="pending" and case.event.outcome_id==outcome_id,advice_id+" reaches actual original G3 outcome "+outcome_id+": "+str(case.event))
	await act("read_morning_letters")
	check(not game.state.divination.cases[visit_id].event.feedback.report.is_empty(),"delayed original event feedback arrives through morning letter")
	if advice_id=="message":
		check(game.state.people.referrals.values().any(func(row: Dictionary)->bool: return row.target_npc_id=="npc_lin_friend"),"message outcome retains established friend referral")
func wrong_route() -> void:
	if not await prepare("错误判断仍产生后果"):
		return
	var visit_id: String = game.state.active_visit_id
	await basics(false,false)
	await fill(false,true)
	await act("case_close",{"advice_id":"attend"})
	await finish_day()
	var case: Dictionary = game.state.divination.cases[visit_id]
	check(case.stars==1 and case.event.outcome_id=="lost","wrong deductions and unconfirmed entrance continue into original lost consequence")
func finish() -> void:
	print("CASE TRANSACTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

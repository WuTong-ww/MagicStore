extends SceneTree
var game: Node
var saves: Node
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("CASE DEADLINE FAIL: "+label)
func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var command := {"type":kind,"action_id":game.make_id("deadline")}
	command.merge(fields,true)
	var response: Dictionary = await game.execute_action_async(command)
	check(response.success,kind+" / "+str(response.get("error_code","")))
	return response
func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-case-deadline/"+game.make_id("run")
	game.set_people_generation_options(false)
	await act("new_game",{"name":"事件到期边界"})
	await act("read_morning_letters")
	await act("next_customer")
	await act("set_free_question",{"enabled":true})
	var boundary: Dictionary = game.snapshot()
	var id: String = boundary.active_visit_id
	var due := int(boundary.divination.cases[id].event.due_at)
	boundary.clock_minutes = due-2
	boundary.people.clock = boundary.clock_minutes
	check(saves.write_save(boundary).success,"authored just-before-deadline snapshot fully validates")
	await act("load_game",{"save_id":boundary.save_id})
	var facts: Dictionary = game.snapshot().divination.cases[id].world_facts.duplicate(true)
	await act("talk",{"topic_id":"invitation","text":"这封邀请是怎么来的？"})
	check(int(game.snapshot().clock_minutes) == due-1 and game.snapshot().divination.cases[id].event.occurrence == "pending","free questions hold an unfinished case before its original event deadline")
	if failures:
		finish()
		return
	for round_index: int in range(3):
		var options: Array = game.case_board_view().questions.filter(func(row: Dictionary) -> bool: return row.enabled)
		await act("case_question",{"question_id":options[0].id})
	for card_index: int in range(3):
		await act("case_flip_card",{"card_index":card_index})
	var view: Dictionary = game.case_board_view()
	for slot: Dictionary in view.slots:
		var materials: Array = view.evidence.filter(func(row: Dictionary) -> bool: return slot.id in row.slot_ids)
		await act("case_attach_evidence",{"slot_id":slot.id,"evidence_id":materials[0].id})
		var open_slot: Dictionary = game.case_board_view().slots.filter(func(row: Dictionary) -> bool: return row.id == slot.id)[0]
		await act("case_choose_answer",{"slot_id":slot.id,"answer_id":open_slot.candidates[0].id})
	await act("case_close",{"advice_id":game.case_board_view().advice[0].id})
	var closed: Dictionary = game.snapshot().divination.cases[id]
	check(game.case_board_view().closed and closed.event.outcome_id == "sent" and int(closed.event.due_at) == due and closed.world_facts == facts,"closure releases the original G3 event without rewriting its deadline or truth")
	await act("end_visit")
	await act("next_customer")
	check(game.active_visit().visit_id != id,"the late reception can finish and admit the next customer")
	finish()
func finish() -> void:
	print("CASE DEADLINE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

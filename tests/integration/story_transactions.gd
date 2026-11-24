extends SceneTree
## Real low-trust preparation, then transactional prelude and delayed reunion.
var game: Node
var saves: Node
var checks := 0
var failures := 0
var sequence := 0
var changes := 0
var rules: Dictionary
var definitions: Dictionary
var saw_tao := false
var deferred_visit_id := ""
var deferred_definition_id := ""
func note_unlocked(id: String) -> bool:
	return game.story_view().notes.any(func(row:Dictionary)->bool:return row.id==id and row.unlocked)
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STORY TRANSACTIONS FAIL: "+label)
func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var command := {"type":kind,"action_id":"story_core_"+str(sequence)}
	command.merge(fields,true)
	var result: Dictionary = await game.execute_action_async(command)
	check(result.success,kind+" / "+str(result.get("message","")))
	return result
func retry(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var command := {"type":kind,"action_id":"story_core_retry_"+str(sequence)}
	command.merge(fields,true)
	var before: Dictionary = game.snapshot()
	var board: Dictionary = game.case_board_view()
	var story: Dictionary = game.story_view()
	var sha := FileAccess.get_sha256(saves._path(before.save_id))
	var count := changes
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED" and game.snapshot()==before and game.case_board_view()==board and game.story_view()==story and FileAccess.get_sha256(saves._path(before.save_id))==sha and changes==count,kind+" failed write publishes no story, note, dialogue, trust or file change")
	var result: Dictionary = await game.execute_action_async(command)
	check(result.success,kind+" same-ID retry commits / "+str(result))
	var committed: Dictionary = game.snapshot()
	var published := changes
	var replay: Dictionary = await game.execute_action_async(command)
	check(replay.success and replay.get("replayed",false) and game.snapshot()==committed and changes==published,kind+" committed replay cannot duplicate receipts or dialogue")
	check(saves.read_save(committed.save_id).get("state",{})==committed,kind+" durable state matches committed candidate")
	return result
func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/story-core-transactions/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func():changes+=1)
	var content = load("res://scripts/story/story_content.gd")
	var schema = load("res://scripts/divination/case_schema.gd")
	rules = content.load_config().rules
	definitions = schema.load_all(game._divination.data)
	var prepared: bool = await prepare_finale()
	check(prepared,"real low-trust preparation reaches the final case")
	if not prepared:
		finish()
		return
	await prelude_and_letter()
	if not failures:
		await epilogues()
	finish()
func solve(id: String, advice_id: String, wrong: bool = true, closing_retry: bool = true) -> bool:
	for round_index: int in range(3):
		var questions: Array = game.case_board_view().questions.filter(func(row:Dictionary)->bool:return row.enabled and (id!="fixed_invitation" or row.id!="venue_route"))
		if questions.is_empty() or not (await act("case_question",{"question_id":questions[0].id})).success:
			return false
	for index: int in range(3):
		if not (await act("case_flip_card",{"card_index":index})).success:
			return false
	for slot: Dictionary in game.case_board_view().slots:
		var material: Array = game.case_board_view().evidence.filter(func(row:Dictionary)->bool:return slot.id in row.slot_ids)
		if material.is_empty() or not (await act("case_attach_evidence",{"slot_id":slot.id,"evidence_id":material[0].id})).success:
			return false
		var definition: Dictionary = definitions[id]
		var correct := ""
		for candidate_slot: Dictionary in definition.deduction_slots:
			if candidate_slot.id==slot.id:
				correct = candidate_slot.correct_answer
		var current_slot: Dictionary = game.case_board_view().slots.filter(func(row:Dictionary)->bool:return row.id==slot.id)[0]
		var answer: Array = current_slot.candidates.filter(func(row:Dictionary)->bool:return row.enabled and (row.id!=correct if wrong else row.id==correct))
		check(not answer.is_empty(),"attached material opens an actual candidate")
		if answer.is_empty() or not (await act("case_choose_answer",{"slot_id":slot.id,"answer_id":answer[0].id})).success:
			return false
	var closed: Dictionary = await retry("case_close",{"advice_id":advice_id}) if closing_retry else await act("case_close",{"advice_id":advice_id})
	check(closed.success and game.case_board_view().stars==(1 if wrong else 3),"story case closes at backend-computed stars")
	return closed.success
func next_visit() -> bool:
	var result: Dictionary = await act("next_customer")
	if not result.success:
		return false
	var row: Dictionary = game.state.people.arrivals[game.active_visit().arrival_id]
	if str(row.get("story_rule_id","")).begins_with("followup_"):
		saw_tao = true
	return true
func prepare_finale() -> bool:
	if not (await act("new_game",{"name":"剧情真实事务"})).success:
		return false
	for day_index: int in range(12):
		if not (await act("read_morning_letters")).success:
			return false
		if not deferred_visit_id.is_empty():
			var deferred_case: Dictionary = game.state.divination.cases[deferred_visit_id]
			var deferred_rule: Dictionary = rules.cases[deferred_definition_id]
			if not deferred_case.event.feedback.report.is_empty():
				check(note_unlocked(deferred_rule.note_id) and game.story_view().disclosures.any(func(row:Dictionary)->bool:return row.id==deferred_rule.fragment.id),"the actual later public report unlocks the deferred half-letter and notebook page")
		while game.daily_loop_view().completed<game.daily_loop_view().total:
			if not await next_visit():
				return false
			var view: Dictionary = game.case_board_view()
			if view.get("enabled",false):
				if view.id==rules.ending.case_id:
					check(game.state.people.profiles[rules.final_prelude.repair.npc_id].trust<int(rules.final_prelude.repair.min_trust),"actual lost invitation feedback creates the low-trust repair route")
					check(game.story_view().notes.filter(func(row:Dictionary)->bool:return row.unlocked).size()==3,"three pages are public before finale and final page stays locked")
					check(saw_tao,"case3's actual following-day commission introduces the stable ordinary followup")
					return true
				var advice: String = rules.cases[view.id].worst_advice_id
				if not await solve(view.id,advice):
					return false
				if advice in rules.cases[view.id].get("defer_disclosure_advice_ids",[]):
					deferred_visit_id = game.state.active_visit_id
					deferred_definition_id = view.id
					var rule: Dictionary = rules.cases[view.id]
					check(not note_unlocked(rule.note_id) and not game.story_view().disclosures.any(func(row:Dictionary)->bool:return row.id==rule.fragment.id),"accusation closure does not obtain the half-letter before Jiang's later report")
					var forged: Dictionary = game.snapshot()
					forged.story.notes[rule.note_id] = {"source_id":"closed:"+deferred_visit_id,"unlocked_at":int(forged.clock_minutes)}
					check(not saves.validate_snapshot(forged).success,"save validation rejects a prematurely unlocked deferred notebook page")
			if not (await act("end_visit")).success:
				return false
		if not (await act("close_shop")).success:
			return false
		if not deferred_visit_id.is_empty() and game.state.divination.cases[deferred_visit_id].event.feedback.report.is_empty():
			check(not note_unlocked(rules.cases[deferred_definition_id].note_id),"even the resolved event does not disclose the half-letter before actual feedback")
		if not (await act("next_day")).success:
			return false
	check(false,"bounded real preparation reaches finale")
	return false
func prelude_and_letter() -> void:
	var blocked: Dictionary = game.snapshot()
	for kind: String in ["case_question","case_flip_card","case_close","reading","quote_service"]:
		var result: Dictionary = await game.execute_action_async({"type":kind,"action_id":"prelude_block_"+kind})
		check(not result.success and game.snapshot()==blocked,"prelude rejects backend bypass "+kind)
	var invalid: Dictionary = await game.execute_action_async({"type":"story_choice","action_id":"lin_unavailable","choice_id":rules.final_prelude.repair.lin_choice_id,"trust":99})
	check(not invalid.success and game.snapshot()==blocked,"client cannot supply trust to enable Lin repair")
	await retry("story_choice",{"choice_id":rules.final_prelude.repair.self_choice_id})
	var energy: int = game.state.player.energy
	var clock: int = game.state.clock_minutes
	var wrong: Dictionary = rules.final_prelude.assembly.choices.filter(func(row:Dictionary)->bool:return row.id!=rules.final_prelude.assembly.correct_choice_id)[0]
	await retry("story_choice",{"choice_id":wrong.id})
	check(game.case_board_view().prelude.blocks_progress and game.state.player.energy==energy and game.state.clock_minutes==clock,"wrong assembly offers a free retry without consuming evidence or time")
	await retry("story_choice",{"choice_id":rules.final_prelude.assembly.correct_choice_id})
	check(not game.case_board_view().prelude.blocks_progress,"correct assembly opens the ordinary three-slot deduction board")
	var before_reload: Dictionary = game.snapshot()
	await act("load_game",{"save_id":before_reload.save_id})
	check(game.snapshot()==before_reload,"prelude, choices and public dialogue survive real reload")
	await solve(rules.ending.case_id,"letter",true)
	var evidence: Array = game.case_board_view().evidence.filter(func(row:Dictionary)->bool:return row.id==rules.final_prelude.self_evidence_id)
	check(evidence.size()==1 and evidence[0].text==rules.final_prelude.self_evidence_text and evidence[0].source==rules.final_prelude.self_evidence_source,"low-trust route attributes cut evidence to self-assembly and never claims Lin spoke")
	check(game.story_view().ending.status=="waiting" and not game.story_view().ending.has("title") and not game.story_view().notes.filter(func(row:Dictionary)->bool:return row.id==rules.ending.note_id)[0].unlocked,"choosing letter neither completes reunion nor unlocks final note/title")
	await finish_day()
	await act("next_day")
	await act("read_morning_letters")
	var source_case: Dictionary = game.state.divination.cases[game.state.story.ending.source_visit_id]
	check(not str(source_case.event.feedback.get("report",{}).get("text","")).contains(rules.ending.routes.letter.text),"G3 letter report does not disclose the future reunion")
	check(game.state.story.ending.has("milestone_id"),"real event resolution schedules the delayed reunion")
	if not game.state.story.ending.has("milestone_id"):
		return
	var due: int = game.state.story.milestones[game.state.story.ending.milestone_id].due_at
	check(due==int(source_case.event.resolved_at)+int(rules.ending.delay_by_advice.letter),"three-day reunion uses a real delayed milestone")
	while game.daily_loop_view().completed<game.daily_loop_view().total:
		if not await next_visit():
			return
		await act("end_visit")
	await act("close_shop")
	for day_index: int in range(6):
		if game.story_view().ending.status=="complete":
			break
		await act("next_day")
		await act("read_morning_letters")
		if game.state.clock_minutes<due:
			check(not str(game.state.divination.cases[source_case.visit_id].event.feedback.report.get("text","")).contains("团圆"),"the early letter feedback contains waiting rather than a future reunion")
		check(game.state.clock_minutes>=due or game.story_view().ending.status=="waiting","normal days before milestone remain waiting")
		while game.daily_loop_view().completed<game.daily_loop_view().total:
			if not await next_visit():
				return
			await act("end_visit")
		await act("close_shop")
	check(game.story_view().ending.status=="complete" and game.story_view().notes.all(func(row:Dictionary)->bool:return row.unlocked),"actual later reunion unlocks all four pages")
	var committed: Dictionary = game.snapshot()
	await act("load_game",{"save_id":committed.save_id})
	check(game.snapshot()==committed,"reunion milestone, receipts and notebook survive reload without duplication")
func finish_day() -> void:
	await act("end_visit")
	while game.daily_loop_view().completed<game.daily_loop_view().total:
		if not await next_visit():
			return
		await act("end_visit")
	await act("close_shop")
func epilogues() -> void:
	var seen := {}
	for day_index: int in range(rules.epilogues.size()+2):
		await act("next_day")
		await act("read_morning_letters")
		while game.daily_loop_view().completed<game.daily_loop_view().total:
			if not await next_visit():
				return
			var row: Dictionary = game.state.people.arrivals[game.active_visit().arrival_id]
			for epilogue: Dictionary in rules.epilogues:
				if row.get("story_rule_id")==epilogue.id:
					check(not seen.has(epilogue.id) and game.active_visit().dialogue[0].text==epilogue.text,"each later fixed epilogue is a real public commission exactly once")
					seen[epilogue.id] = true
			await act("end_visit")
		await act("close_shop")
	check(seen.size()==rules.epilogues.size(),"all five fixed people return on later days")
func finish() -> void:
	print("STORY TRANSACTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

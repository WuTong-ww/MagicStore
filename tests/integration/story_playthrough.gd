extends SceneTree
## Two actual saved routes from a fresh game. No resources, clocks, characters,
## story completions or deductions are injected into the candidate.
var game: Node
var saves: Node
var checks := 0
var failures := 0
var sequence := 0
var route := ""
var rules: Dictionary
var definitions: Dictionary = {}
var receipt: Dictionary = {"routes":{},"fixtures":{}}
var save_root := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STORY PLAYTHROUGH FAIL: "+label)

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var action := {"type":kind,"action_id":"story_route_%s_%d" % [route,sequence]}
	action.merge(fields,true)
	var result: Dictionary = await game.execute_action_async(action)
	check(result.get("success",false),route+" "+kind+" / "+str(result.get("message","")))
	return result

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	check(game.has_method("story_view"),"story public projection is installed")
	if failures:
		finish()
		return
	rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rules.json"))
	for id: String in rules.case_order:
		definitions[id] = JSON.parse_string(FileAccess.get_file_as_string("res://data/cases/"+id+".json"))
	game.set_people_generation_options(false)
	game.configure_api("","","")
	save_root = "res://.tools/r3-story/playthrough/"+game.make_id("run")
	saves.base_dir = save_root+"/active"
	await play_route("best")
	if not failures:
		await play_route("worst")
	if not failures:
		await play_route("missing_key")
	finish()

func play_route(name: String) -> void:
	route = name
	var start_checks := checks
	if not (await act("new_game",{"name":"固定剧情验收·"+name})).get("success",false):
		return
	check(game.story_view().notes.filter(func(row: Dictionary) -> bool: return row.unlocked).size() == 1,"only notebook page1 is initially available")
	var seen: Dictionary = {}
	var ending_day := 0
	for day_index: int in range(18):
		if not (await act("read_morning_letters")).get("success",false):
			return
		var loop: Dictionary = game.daily_loop_view()
		while int(loop.completed) < int(loop.total):
			if not (await act("next_customer")).get("success",false):
				return
			var view: Dictionary = game.case_board_view()
			if view.get("enabled",false):
				if day_index == 0 and seen.is_empty():
					check(game.active_visit().npc_id == "npc_lin" and view.id == "fixed_invitation","new save first customer is Lin and invitation")
				if view.id == "fixed_bread" and route == "best":
					capture_save("case2-start")
				if view.id == "fixed_last_pages":
					check(int(game.state.clock_minutes)%1440 >= int(rules.cases.fixed_last_pages.minute),"last case really begins at the saved night minute")
					check(game.people_view().get("day",{}).get("weather") == "rainy","last case public weather is saved rain")
					if route == "best":
						capture_save("best-case5-start")
					elif route == "missing_key":
						check(not seen.has("fixed_key"),"retained legacy-mode gap leaves case3 genuinely unfinished at case5 admission")
						check(game.case_board_view().prelude.id == rules.final_prelude.retrieve.id,"missing key case offers the real trip to Shen")
						capture_save("missing-key-case5-start")
				if not await solve_board(view.id):
					return
				seen[view.id] = int(game.case_board_view().stars)
				if view.id == "fixed_last_pages" and route == "worst":
					check(game.story_view().get("ending",{}).get("status") == "waiting","letter route is genuinely waiting before its reunion")
					capture_save("letter-waiting")
			if not (await act("end_visit")).get("success",false):
				return
			loop = game.daily_loop_view()
		if not (await act("close_shop")).get("success",false):
			return
		var public_story: Dictionary = game.story_view()
		if public_story.get("ending",{}).get("status") == "complete":
			ending_day = int(loop.day)
			if route == "missing_key":
				check(seen.has("fixed_invitation") and seen.has("fixed_bread") and seen.has("fixed_music_box") and seen.has("fixed_last_pages"),"fallback route closes its four actual source cases without a fabricated key completion")
				var note_source: String = game.state.story.notes.note_2.source_id
				check(game.state.story.disclosures.get(note_source,{}).get("kind") == "retrieve","page2 really comes from the supplemental retrieval source")
			else:
				check(seen.size() == 5,"all five fixed cases were actually closed")
			check(public_story.notes.size() == 4 and public_story.notes.all(func(row: Dictionary) -> bool: return row.unlocked),"all four notebook pages unlocked after reunion")
			check(saves.validate_snapshot(game.snapshot()).get("success",false),"real ending snapshot validates")
			if route == "best":
				check(game.state.people.referrals.values().any(func(row: Dictionary) -> bool: return row.target_npc_id == "npc_lin_friend"),"original invitation names the unchanged friend referral")
				capture_save("best-ending")
			else:
				check(int(game.state.people.profiles.npc_lin.trust) < int(rules.final_prelude.repair.min_trust),"worst invitation naturally retains the low-trust repair path")
				if route == "missing_key":
					capture_save("missing-key-ending")
			break
		if route == "missing_key" and int(loop.day) == 2:
			# Exercise an actual supported mode-switch gap, preserving the saved
			# old plans/visits. No completion, clock or source bytes are fabricated.
			game.daily_loop_config.enabled = false
			for skipped_day: int in range(3):
				if not (await act("next_day")).get("success",false):
					return
			game.daily_loop_config.enabled = true
		elif not (await act("next_day")).get("success",false):
			return
	check(ending_day > 0,"route reaches a non-tragic actual reunion within bounded game days")
	receipt.routes[name] = {"save_id":game.state.save_id,"ending_day":ending_day,"case_stars":seen,"checks":checks-start_checks,"story":game.story_view()}

func solve_board(id: String) -> bool:
	var definition: Dictionary = definitions[id]
	var best: bool = route == "best" or (route == "missing_key" and id != "fixed_invitation")
	var wrong_assembly_tested := false
	for step: int in range(8):
		var prelude: Dictionary = game.case_board_view().get("prelude",{})
		if not prelude.get("blocks_progress",false):
			break
		var options: Array = prelude.options.filter(func(row: Dictionary) -> bool: return row.enabled)
		check(not options.is_empty(),"every prelude has a usable free choice")
		if options.is_empty():
			return false
		var choice_id: String = options[0].id
		if prelude.id == rules.final_prelude.repair.id:
			var wanted: String = rules.final_prelude.repair.lin_choice_id if route == "best" else rules.final_prelude.repair.self_choice_id
			if options.any(func(row: Dictionary) -> bool: return row.id == wanted):
				choice_id = wanted
		if prelude.id == rules.final_prelude.assembly.id:
			choice_id = rules.final_prelude.assembly.correct_choice_id
			if route != "best" and not wrong_assembly_tested:
				choice_id = options.filter(func(row: Dictionary) -> bool: return row.id != rules.final_prelude.assembly.correct_choice_id)[0].id
				wrong_assembly_tested = true
		if not (await act("story_choice",{"choice_id":choice_id})).get("success",false):
			return false
	check(not game.case_board_view().get("prelude",{}).get("blocks_progress",false),"prelude completes without a waiting or energy lock")
	for round_index: int in range(3):
		var options: Array = game.case_board_view().questions.filter(func(row: Dictionary) -> bool: return row.enabled)
		if not best and id == "fixed_invitation":
			options = options.filter(func(row: Dictionary) -> bool: return row.id != "venue_route")
		check(not options.is_empty(),"a base question remains available")
		if options.is_empty() or not (await act("case_question",{"question_id":options[0].id})).get("success",false):
			return false
	for card_index: int in range(3):
		if not (await act("case_flip_card",{"card_index":card_index})).get("success",false):
			return false
	for slot_index: int in range(3):
		var slot: Dictionary = game.case_board_view().slots[slot_index]
		var materials: Array = game.case_board_view().evidence.filter(func(row: Dictionary) -> bool: return slot.id in row.slot_ids)
		check(not materials.is_empty(),"base choices provide material for every deduction")
		if materials.is_empty() or not (await act("case_attach_evidence",{"slot_id":slot.id,"evidence_id":materials[0].id})).get("success",false):
			return false
		var correct: String = definition.deduction_slots[slot_index].correct_answer
		var answers: Array = game.case_board_view().slots[slot_index].candidates.filter(func(row: Dictionary) -> bool: return row.enabled and (row.id == correct if best else row.id != correct))
		if answers.is_empty() or not (await act("case_choose_answer",{"slot_id":slot.id,"answer_id":answers[0].id})).get("success",false):
			return false
	var advice_id: String = rules.cases[id].best_advice_id if best else rules.cases[id].worst_advice_id
	if not (await act("case_close",{"advice_id":advice_id})).get("success",false):
		return false
	check(int(game.case_board_view().stars) == (3 if best else 1),"actual stars reflect all correct or all wrong deductions: "+id)
	return true

func capture_save(label: String) -> void:
	var directory := save_root+"/"+label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var filename: String = game.state.save_id+".json"
	var source: String = saves.base_dir+"/"+filename
	var destination := directory+"/"+filename
	var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(destination))
	check(copied == OK and FileAccess.get_sha256(source) == FileAccess.get_sha256(destination),"review fixture copies the exact already saved bytes")
	receipt.fixtures[label] = {"base_dir":directory,"save_id":game.state.save_id,"sha256":FileAccess.get_sha256(destination),"clock_minutes":int(game.state.clock_minutes)}

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tools/r3-story"))
	var file := FileAccess.open("res://.tools/r3-story/playthrough-receipt.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"  "))
	file.close()
	print("STORY PLAYTHROUGH: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

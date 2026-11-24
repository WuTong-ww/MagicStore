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
		printerr("CASE HOST FAIL: "+label)
func command(kind: String, fields: Dictionary = {}) -> Dictionary:
	var value := {"type":kind,"action_id":game.make_id("case_host")}
	value.merge(fields,true)
	return value
func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	return await game.execute_action_async(command(kind,fields))
func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-case-host/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	check(game.has_method("case_board_view"),"host exposes the public board getter")
	check(game.has_method("free_question_enabled"),"host exposes the saved free-question setting")
	if failures:
		finish()
		return
	check((await act("new_game",{"name":"推理板主机接线"})).success,"create default save")
	check(not game.free_question_enabled(),"new saves default to button questions")
	check(not game.case_board_view().get("enabled",false),"no reception exposes no private board")
	check((await act("read_morning_letters")).success and (await act("next_customer")).success,"start the actual first ordered customer")
	check(game.case_board_view().get("enabled",false),"first invitation reception has a playable board")
	var before: Dictionary = game.snapshot()
	var premature: Dictionary = await act("end_visit")
	check(not premature.success and game.snapshot() == before,"the legacy end action cannot skip the enabled deduction case")
	if premature.success:
		finish()
		return
	var legacy_read: Dictionary = await act("reading")
	check(not legacy_read.success and game.snapshot() == before,"the legacy paid-reading route cannot replace an enabled board")
	if legacy_read.success:
		finish()
		return
	var blocked: Dictionary = await act("talk",{"topic_id":"invitation","text":"这封邀请是谁写的？"})
	check(not blocked.success and game.snapshot() == before,"default board refuses the legacy free-input route")
	var toggle := command("set_free_question",{"enabled":true})
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(toggle)
	check(not failed.success and game.snapshot() == before and not game.free_question_enabled(),"failed setting save preserves state and disabled input")
	check((await game.execute_action_async(toggle)).success and game.free_question_enabled(),"same-ID retry saves the free-question preference")
	var saved: Dictionary = game.snapshot()
	check((await game.execute_action_async(toggle)).success and game.snapshot() == saved,"preference replay does not change version or board")
	check((await act("load_game",{"save_id":saved.save_id})).success and game.snapshot() == saved and game.free_question_enabled(),"free-question preference survives actual reload")
	var invalid: Dictionary = await act("set_free_question",{"enabled":"yes"})
	check(not invalid.success and game.snapshot() == saved,"non-boolean preference is rejected atomically")
	var board: Dictionary = saved.divination.cases[saved.active_visit_id].board.duplicate(true)
	check((await act("set_free_question",{"enabled":false})).success and not game.free_question_enabled(),"free questions can be disabled again")
	check(game.snapshot().divination.cases[saved.active_visit_id].board == board,"setting changes do not reset evidence or redraw cards")
	finish()
func finish() -> void:
	print("CASE HOST: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

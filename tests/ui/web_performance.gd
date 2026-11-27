extends SceneTree
const Config = preload("res://scripts/ui/performance_config.gd")
const Packed = preload("res://scripts/ui/packed_ui_data.gd")
const Teardown = preload("res://tests/ui_teardown.gd")
var checks := 0
var failures := 0
var main: Control
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("R4 WEB PERFORMANCE FAIL: "+message)
func settle() -> void:
	for frame: int in range(16): await process_frame
	while main.busy: await process_frame
func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
func run() -> void:
	var config := Config.load_config()
	check(Config.valid(config),"runtime and measurement JSON validates")
	for change: Dictionary in [{"frames_per_page":0},{"page_samples":1.5},{"pages":["private"]},{"input_timeout_ms":-1},{"copy":{"opening_notes":""}}]:
		var malformed := config.duplicate(true)
		malformed.merge(change,true)
		check(not Config.valid(malformed),"reject malformed measurement settings")
	var malformed := config.duplicate(true)
	malformed.ui.cache_pages = "yes"
	check(not Config.valid(malformed),"optimization flags must be booleans")
	var game := root.get_node("GameState")
	var saves := root.get_node("SaveService")
	var folder: String = "res://.tools/r4-web-performance/"+game.make_id("run")
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder+"/cache.json"
	write_json(path,{"data":{"value":1}})
	var calls := [0]
	var validate := func(value: Dictionary) -> bool:
		calls[0] += 1
		return value.get("data") is Dictionary
	var first := Packed.read(path,validate,true)
	first.data.value = 99
	check(Packed.read(path,validate,true).data.value == 1,"returned nested dictionaries cannot poison the packed cache")
	check(calls[0] == 1,"immutable packed configuration validates once")
	write_json(path,{"data":{"value":2}})
	check(Packed.read(path,validate,false).data.value == 2,"native development reads fresh file data")
	var invalid_path: String = folder+"/invalid.json"
	write_json(invalid_path,{"invalid":true})
	check(Packed.read(invalid_path,validate,true).is_empty(),"invalid configuration is rejected")
	write_json(invalid_path,{"data":{"value":3}})
	check(Packed.read(invalid_path,validate,true).data.value == 3,"failed validation never poisons the cache")
	saves.base_dir = folder+"/saves"
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280,720)
	main = load("res://scenes/main.tscn").instantiate()
	main.web_ui_enabled = true
	root.add_child(main)
	await settle()
	check(config.pages.all(func(page: String) -> bool: return is_instance_valid(main._page_cache.get(page))),"opening prepares every measured page before navigation")
	var prepared_front: Control = main._page_cache.front
	check(not prepared_front.visible and prepared_front.process_mode == Node.PROCESS_MODE_DISABLED,"prepared pages stay hidden and inactive before a save commits")
	check(game.next_guest_portrait_view().is_empty(),"no saved world exposes no guest portrait projection")
	check((await main.run_action("new_game",{"name":"网页性能甲"})).get("success",false),"create isolated save with web UI behavior enabled")
	await settle()
	var first_save: String = game.snapshot().save_id
	var front: Control = main.screen
	var prepared_consultation: Control = main._page_cache.consultation
	var prepared_portraits: int = prepared_consultation.portrait_preparations
	check(prepared_portraits > 0 and not prepared_consultation.visible,"committed reservation is prepared during entry while its page stays hidden")
	check(front == prepared_front,"first committed save can use the empty opening page cache")
	main.show_screen("inventory",true)
	await settle()
	var inventory: Control = main.screen
	main.show_screen("front",true)
	await settle()
	check(main.screen == front,"returning to a page reuses its control tree")
	check(not inventory.visible and inventory.process_mode == Node.PROCESS_MODE_DISABLED,"cached hidden pages stop drawing and processing")
	check(front.visible and front.process_mode == Node.PROCESS_MODE_INHERIT,"selected page resumes ordinary processing")
	check(main.people_panel.view.is_empty(),"hidden archive has not been refreshed for unrelated game actions")
	check(main.open_story_notes(),"web notes entry opens its dedicated tab")
	await settle()
	check(main.people_window.visible and main._people_story_only and main.people_panel.view.is_empty(),"opening notes does not rebuild the unrelated people archive")
	check(game.story_view().notes[0].read,"first lazy note entry still persists its read receipt")
	var notes: Control = main.people_panel.story_notes
	var note_pages := notes.get_parent() as TabContainer
	note_pages.current_tab = 0
	await settle()
	check(not main._people_story_only and not main.people_panel.view.is_empty(),"selecting another tab fills the current archive on demand")
	main.people_window.hide()
	await settle()
	var motion: Node = main._current_motion()
	main.open_saves()
	await settle()
	check(not bool(motion.get("_active")),"modal visibility pauses the active scene motion")
	var paused_at: float = motion.motion_time_seconds
	await settle()
	check(is_equal_approx(motion.motion_time_seconds,paused_at),"background animation time remains frozen under the modal")
	main.save_window.hide()
	await settle()
	check(bool(motion.get("_active")),"closing the final modal resumes motion")
	var before: Dictionary = game.snapshot()
	var command: String = game.make_id("web_perf_atomic")
	saves.fail_next_write = true
	var failed: Dictionary = await main.run_action("set_free_question",{"enabled":game.free_question_enabled()},command)
	check(not failed.get("success",true) and game.snapshot() == before,"busy feedback never publishes an unsaved candidate")
	check(not main.busy and main.screen == front,"failed save leaves the active cached page usable")
	var committed: Dictionary = await main.run_action("set_free_question",{"enabled":game.free_question_enabled()},command)
	check(committed.get("success",false),"same failed command can be retried")
	var after: Dictionary = game.snapshot()
	check(after.state_version == before.state_version+1 and after.processed_actions.has(command),"successful retry settles exactly once")
	check(saves.read_save(first_save).get("state",{}) == after,"published state matches the completed disk write")
	var replay: Dictionary = await main.run_action("set_free_question",{"enabled":game.free_question_enabled()},command)
	check(replay.get("replayed",false) and game.snapshot() == after,"same-ID replay cannot settle twice")
	var morning_command: String = game.make_id("web_perf_morning")
	var visual_before_morning: Dictionary = game.next_guest_portrait_view()
	var preparations_before_morning: int = prepared_consultation.portrait_preparations
	saves.fail_next_write = true
	var failed_morning: Dictionary = await main.run_action("read_morning_letters",{},morning_command)
	check(not failed_morning.get("success",true) and game.next_guest_portrait_view() == visual_before_morning and prepared_consultation.portrait_preparations == preparations_before_morning,"failed morning save does not change or prepare an uncommitted guest")
	check((await main.run_action("read_morning_letters",{},morning_command)).get("success",false),"read actual morning letters before admission")
	prepared_portraits = prepared_consultation.portrait_preparations
	check(prepared_portraits > 0 and not prepared_consultation.visible,"morning preparation warms the next public portrait before navigation")
	var visual_keys: Array = game.next_guest_portrait_view().keys()
	visual_keys.sort()
	check(visual_keys == ["appearance","npc_id"],"portrait preparation exposes visual identity only, without case facts or outcomes")
	check((await main.run_action("next_customer")).get("success",false),"start the actual first guest with web UI behavior")
	await settle()
	var consultation: Control = main.screen
	check(consultation.case_board.public_view == game.case_board_view(),"first admission displays the complete committed case without a second refresh")
	check(not main.busy and not consultation.case_board.flow.primary.disabled,"first admitted visit leaves its next-step control available")
	check(consultation.portrait_preparations == prepared_portraits,"first admission reuses the already prepared public portrait")
	check(consultation.case_board.visible and not consultation.dialogue_panel.visible,"case board owns the visible dialogue")
	check(consultation.bubble_avatar_textures.is_empty() and consultation.transcript.get_parsed_text().is_empty(),"hidden legacy conversation does not allocate CPU avatar composites")
	check(consultation.guest_portrait.visible and not consultation.guest_portrait.appearance.is_empty(),"visible seated portrait is still prepared")
	check((await main.run_action("set_free_question",{"enabled":true})).get("success",false),"enable free conversation through a saved action")
	var topics: Array = game.conversation_questions()
	check(not topics.is_empty(),"free conversation exposes an actual available topic")
	if not topics.is_empty():
		var answer: Dictionary = await main.run_action("talk",{"text":str(topics[0].label),"topic_id":str(topics[0].topic_id)})
		check(answer.get("success",false),"commit an actual free conversation: "+str(answer.get("error_code","")))
	await settle()
	check(consultation.dialogue_panel.visible and not consultation.transcript.get_parsed_text().is_empty(),"visible free conversation renders its latest history on demand")
	check((await main.run_action("new_game",{"name":"网页性能乙"})).get("success",false),"create a second save")
	await settle()
	check(not is_instance_valid(front) and not is_instance_valid(inventory),"new save discards all prior cached pages")
	check(not is_instance_valid(consultation),"changing saves also discards the cached portrait and transcript")
	var second_front: Control = main.screen
	check((await main.run_action("load_game",{"save_id":first_save})).get("success",false),"reload the original save")
	await settle()
	check(not is_instance_valid(second_front) and game.snapshot().save_id == first_save,"loading a different save cannot reuse another save's page tree")
	print("R4 WEB PERFORMANCE: %d checks, %d failures"%[checks,failures])
	await Teardown.release_audio(main)
	main.queue_free()
	await process_frame
	await Teardown.drain(self)
	quit(1 if failures else 0)

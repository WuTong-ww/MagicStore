extends SceneTree
## Actual Main/consultation/notes over byte-exact saves from the legal playthrough.
const Teardown = preload("res://tests/ui_teardown.gd")
var game: Node
var saves: Node
var main: Control
var receipt: Dictionary = {}
var work_dir := ""
var checks := 0
var failures := 0
var captures := 0
var compile_only := false
var input_failed := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STORY BOARD UI FAIL: "+label)

func settle() -> void:
	for frame: int in range(14):
		await process_frame
	while is_instance_valid(main) and main.busy:
		await process_frame

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.gui_embed_subwindows = true
	var receipt_path := "res://.tools/r3-story/playthrough-receipt.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--receipt="):
			receipt_path = argument.trim_prefix("--receipt=")
		elif argument == "--compile-only":
			compile_only = true
	if not compile_only:
		receipt = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
		check(receipt.get("fixtures",{}) is Dictionary and not receipt.get("fixtures",{}).is_empty(),"legal playthrough receipt supplies saved fixtures")
	if failures:
		quit(1)
		return
	work_dir = "res://.tools/r3-story/ui-saves/"+game.make_id("run")
	var scene: PackedScene = load("res://scenes/main.tscn")
	check(scene != null,"production Main scene compiles")
	if scene == null:
		quit(1)
		return
	main = scene.instantiate()
	root.add_child(main)
	await settle()
	check(main.screen != null and main.people_panel != null,"production Main builds its screen and archive")
	if compile_only:
		await finish()
		return
	await exercise_case_two()
	if input_failed:
		await finish()
		return
	await exercise_prelude()
	if input_failed:
		await finish()
		return
	await exercise_waiting()
	await exercise_notes()
	await finish()

func load_fixture(label: String) -> bool:
	if input_failed: return false
	check(receipt.fixtures.has(label),"fixture exists / "+label)
	if not receipt.fixtures.has(label): return false
	var row: Dictionary = receipt.fixtures[label]
	var source := str(row.base_dir)+"/"+str(row.save_id)+".json"
	check(source.begins_with("res://.tools/r3-story/") and not source.contains(".."),"fixture path stays isolated / "+label)
	check(FileAccess.get_sha256(source) == str(row.sha256),"fixture matches actual-playthrough SHA / "+label)
	var folder := work_dir+"/"+label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	check(DirAccess.copy_absolute(source,folder+"/"+str(row.save_id)+".json") == OK,"copy source bytes before UI actions / "+label)
	saves.base_dir = folder
	var result: Dictionary = await main.run_action("load_game",{"save_id":row.save_id})
	check(result.get("success",false),"load through the real saved action / "+label+" / "+str(result.get("message","")))
	await settle()
	print("STORY UI LOAD ",JSON.stringify({"label":label,"result":result,"loaded_save_id":game.player_snapshot().get("save_id"),"state_version":game.player_snapshot().get("state_version"),"note2":game.story_view().notes[1].unlocked,"save_window":main.save_window.visible,"people_window":main.people_window.visible}))
	return bool(result.get("success",false))

func exercise_case_two() -> void:
	if not await load_fixture("case2-start"): return
	check(game.case_board_view().get("id") == "fixed_bread","case two is the real bread consultation")
	while game.case_board_view().phase == "questions":
		var buttons: Array = main.screen.case_board.question_buttons.get_children().filter(func(node: Node) -> bool: return not node.disabled)
		if buttons.is_empty():
			check(false,"case two offers a real question")
			return
		var previous_round: int = game.case_board_view().round
		await click(buttons[0])
		var advanced: bool = game.case_board_view().phase != "questions" or int(game.case_board_view().round) != previous_round
		check(advanced,"real question click advances its saved round")
		if not advanced: return
	for index: int in [0,2,4]:
		await click(main.screen.case_board.find_child("CaseCard_"+str(index),true,false))
	for slot: Dictionary in game.case_board_view().slots:
		var related: Array = game.case_board_view().evidence.filter(func(row: Dictionary) -> bool: return slot.id in row.slot_ids)
		check(not related.is_empty(),"public material can unlock case-two slot / "+slot.id)
		if related.is_empty(): return
		var board: Control = main.screen.case_board
		var tokens: Array = board.evidence_box.get_children().filter(func(node: Node) -> bool: return node.get("evidence_id") == related[0].id)
		board.evidence_scroll.ensure_control_visible(tokens[0])
		await settle()
		await drag(tokens[0],board.slot_nodes[slot.id])
		var shown: Dictionary = game.case_board_view().slots.filter(func(row: Dictionary) -> bool: return row.id == slot.id)[0]
		check(shown.unlocked,"actual drag unlocks case-two candidates / "+slot.id)
		check(board.slot_nodes[slot.id].find_children("CaseAnswer_*","Button",true,false).size() == shown.candidates.size(),"all public authored candidates are rendered / "+slot.id)
	check(game.case_board_view().slots.any(func(row: Dictionary) -> bool: return row.candidates.size() == 4),"case two really exercises a four-candidate slot")
	await capture_sizes("case2-deduction")

func exercise_prelude() -> void:
	if not await load_fixture("missing-key-case5-start"): return
	check(main.current_screen == "consultation" and main.screen.room_art.current_period == "night","actual case-five save uses the night consultation artwork")
	check(game.people_view().get("day",{}).get("weather") == "rainy","rain comes from the saved day")
	check(not game.story_view().notes[1].unlocked,"missing case three starts with notebook page two locked")
	check((await main.run_action("set_free_question",{"enabled":true})).get("success",false),"enable saved free-question setting for the prelude boundary")
	check(not main.screen.input.is_visible_in_tree(),"blocking prelude hides free input while keeping its saved preference")
	var before: Dictionary = game.snapshot()
	var old_text: String = main.screen.case_board.speech_label.text
	var button: Button = main.screen.case_board.question_buttons.get_child(0)
	saves.fail_next_write = true
	await click(button)
	check(not saves.fail_next_write,"the real prelude click reaches the injected failed save")
	check(game.snapshot() == before and main.screen.case_board.speech_label.text == old_text,"failed prelude save preserves state and the displayed public paragraph")
	check(not game.story_view().notes[1].unlocked,"failed retrieval cannot unlock notebook page two")
	await click(main.screen.case_board.question_buttons.get_child(0))
	check(game.story_view().notes[1].unlocked,"saved trip to Shen unlocks the actual letter page")
	var repair: Array = game.case_board_view().prelude.options
	check(repair.any(func(row: Dictionary) -> bool: return row.id == "repair_lin" and not row.enabled),"low trust disables Lin repair without fabricating her help")
	check(repair.any(func(row: Dictionary) -> bool: return row.id == "repair_self" and row.enabled),"low trust still offers self assembly")
	await capture_sizes("case5-low-trust-prelude")
	await click(choice("repair_self"))
	var energy: int = game.player_snapshot().player.energy
	var wrong_version: int = game.player_snapshot().state_version
	await click(choice("assemble_address_greeting"))
	check(game.player_snapshot().state_version > wrong_version,"wrong-order mouse click is actually saved before retry")
	check(game.case_board_view().prelude.blocks_progress and game.player_snapshot().player.energy == energy,"wrong paper order stays retryable without spending energy")
	await click(choice("assemble_greeting_address"))
	check(not game.case_board_view().prelude.blocks_progress,"saved correct assembly resumes the ordinary question board")
	check(main.screen.input.is_visible_in_tree() and main.screen.case_board.visible,"free input returns beside the board after the prelude")
	if main.screen.input.is_visible_in_tree():
		for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
			root.size = dimensions
			root.content_scale_size = dimensions
			await settle()
			var input_bounds: Rect2 = main.screen.dialogue_panel.get_global_rect()
			for card: Control in main.screen.case_board.card_nodes:
				check(not input_bounds.intersects(card.get_global_rect()),"restored free editor never covers a card / "+str(dimensions))
			check(not input_bounds.intersects(main.screen.case_board.question_buttons.get_global_rect()),"restored free editor never covers question/advice area / "+str(dimensions))
	var source_text := "\n".join(game.case_board_view().story_lines.map(func(row: Dictionary) -> String: return row.text))
	check(not source_text.contains("照晚沿着旧装订线"),"self route never displays a claim that Lin repaired the pages")

func choice(id: String) -> Button:
	var buttons: Array = main.screen.case_board.question_buttons.get_children().filter(func(node: Node) -> bool: return node.get_meta("choice_id","") == id)
	check(buttons.size() == 1,"the requested choice is publicly rendered / "+id)
	return buttons[0] if not buttons.is_empty() else null

func exercise_waiting() -> void:
	if not await load_fixture("letter-waiting"): return
	check(game.story_view().ending.status == "waiting" and not game.story_view().notes[3].unlocked,"actual letter waiting snapshot keeps page four locked")
	check(main.open_story_notes(),"Main opens the actual notes tab")
	await settle()
	var notes: Control = main.people_panel.story_notes
	check(notes.page_buttons.get_child(3).disabled,"waiting page four is not clickable")
	check(notes.ending_label.text == str(game.story_view().ending.text),"waiting displays exactly its current public ending paragraph")
	await click(notes.close_button)
	check(not main.people_window.visible,"closing notes returns to the game")

func exercise_notes() -> void:
	if not await load_fixture("missing-key-ending"): return
	check(game.story_view().notes.size() == 4 and game.story_view().notes.all(func(row: Dictionary) -> bool: return row.unlocked),"legal later fixture has all four notebook pages")
	check(main.open_story_notes(),"the archive exposes the four-page reader")
	await settle()
	var notes: Control = main.people_panel.story_notes
	var earned_title: String = str(game.story_view().ending.get("title",""))
	if not earned_title.is_empty():
		check(notes.ending_label.text.begins_with(earned_title+"\n"),"the actual completed route visibly awards its public title")
	for index: int in range(4):
		await click(notes.page_buttons.get_child(index))
		check(notes.body.text == str(game.story_view().notes[index].text) and not notes.body.text.is_empty(),"real page click reads its committed body / "+str(index+1))
	await capture_sizes("notes-page4")
	await click(notes.close_button)
	check(not main.people_window.visible,"the reader can close after the ending")

func capture_sizes(label: String) -> void:
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		if main.people_window.visible:
			main._fit_window(main.people_window,Vector2i(main.shell_config.dialogs.people[0],main.shell_config.dialogs.people[1]))
			main.people_window.popup_centered()
		await settle()
		var bounds := Rect2(Vector2.ZERO,Vector2(dimensions)).grow(1)
		if main.people_window.visible:
			var reader: Control = main.people_panel.story_notes
			var inner := Rect2(Vector2.ZERO,Vector2(main.people_window.size)).grow(1)
			if DisplayServer.get_name() != "headless":
				for control: Control in [reader.page_buttons,reader.body,reader.close_button]:
					check(inner.encloses(control.get_global_rect()),"notebook control fits its real window / "+label+" / "+str(dimensions))
		else:
			var board: Control = main.screen.case_board
			if board.advice_buttons.is_visible_in_tree() and board.utility_buttons.is_visible_in_tree():
				for advice: Node in board.advice_buttons.get_children():
					check(advice.get_global_rect().end.y <= board.utility_buttons.get_global_rect().position.y,"long advice never overlaps the utility row / "+str(dimensions))
			for control: Node in board.find_children("*","Control",true,false):
				if not control.is_visible_in_tree() or board.evidence_scroll.is_ancestor_of(control): continue
				if control is Button or control.name.begins_with("CaseSlot") or control.name == "CaseBoardPaper":
					check(bounds.encloses(control.get_global_rect()),"board control fits viewport / "+label+" / "+str(dimensions)+" / "+control.name)
			for slot: Control in board.slot_nodes.values():
				for button: Node in slot.find_children("CaseAnswer_*","Button",true,false):
					check(slot.get_global_rect().grow(1).encloses(button.get_global_rect()),"long candidates stay within their slot / "+label+" / "+str(dimensions))
		if DisplayServer.get_name() != "headless":
			await create_timer(0.2).timeout
			RenderingServer.force_draw()
			DirAccess.make_dir_recursive_absolute("res://.tools/c-ui-captures")
			var path := "res://.tools/c-ui-captures/r3-story-"+label+"-"+str(dimensions.x)+"x"+str(dimensions.y)+".png"
			check(root.get_texture().get_image().save_png(path) == OK,"save actual graphical capture / "+path)
			captures += 1

func click(control: Control) -> void:
	if input_failed: return
	check(control != null and control.is_visible_in_tree() and not control.get("disabled"),"input targets a visible enabled control")
	if control == null: return
	if DisplayServer.get_name() == "headless":
		# Headless subwindows use an OS sentinel; graphical runs test actual input.
		control.pressed.emit()
		await settle()
		return
	var acknowledgement := {"pressed":false}
	var pressed_callback := func(): acknowledgement.pressed = true
	control.pressed.connect(pressed_callback,CONNECT_ONE_SHOT)
	var point := control.get_global_rect().get_center()
	var window := control.get_window()
	if window != root:
		point += Vector2(window.position)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await process_frame
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	Input.flush_buffered_events()
	var deadline := Time.get_ticks_msec()+2500
	while not acknowledgement.pressed and Time.get_ticks_msec() < deadline:
		await process_frame
		Input.flush_buffered_events()
	check(acknowledgement.pressed,"the injected click actually emits pressed before the next operation")
	if not acknowledgement.pressed:
		input_failed = true
		if is_instance_valid(control) and control.pressed.is_connected(pressed_callback):
			control.pressed.disconnect(pressed_callback)
		return
	await settle()

func drag(source: Control, target: Control) -> void:
	if input_failed: return
	if DisplayServer.get_name() == "headless":
		target._drop_data(Vector2.ZERO,{"kind":"case_evidence","evidence_id":source.evidence_id})
		await settle()
		return
	var before_version: int = game.player_snapshot().state_version
	var origin := source.get_global_rect().get_center()
	var end := target.get_global_rect().get_center()
	var initial_motion := InputEventMouseMotion.new()
	initial_motion.position = origin
	Input.parse_input_event(initial_motion)
	var down := InputEventMouseButton.new()
	down.position = origin
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	for index: int in range(12):
		var motion := InputEventMouseMotion.new()
		motion.position = origin.lerp(end,float(index+1)/12.0)
		motion.relative = (end-origin)/12.0
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		await process_frame
	var up := InputEventMouseButton.new()
	up.position = end
	up.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	var deadline := Time.get_ticks_msec()+2500
	while int(game.player_snapshot().state_version) == before_version and Time.get_ticks_msec() < deadline:
		await process_frame
		Input.flush_buffered_events()
	check(int(game.player_snapshot().state_version) > before_version,"the real drag is saved before the next operation")
	if int(game.player_snapshot().state_version) == before_version:
		input_failed = true
		return
	await settle()

func finish() -> void:
	print("STORY BOARD UI: %d checks, %d failures, %d captures; renderer=%s"%[checks,failures,captures,DisplayServer.get_name()])
	await Teardown.release_audio(main)
	main.queue_free()
	await settle()
	await Teardown.drain(self)
	quit(1 if failures else 0)

extends SceneTree
## Draft: real UI input over legally generated isolated saves. No direct state
## fixture edits. The caller supplies finalized content IDs after root freezes
## STORY, so no frontend script needs truth/correct_answer access.
const Teardown = preload("res://tests/ui_teardown.gd")
const StoryUI = preload("res://scripts/ui/story_ui_config.gd")
var main: Control
var game: Node
var config: Dictionary
var checks := 0
var failures := 0
var first_frame := 0
var fixture_directory := ""
var ending_fixture_directory := ""
var start_save := ""
var ending_save := ""
var advice_id := ""
var choices: PackedStringArray = []
var input_failed := false
var probe_first_click := false
var logical_case_size := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STORY MOVIE FAIL: "+label)

func settle() -> void:
	for frame: int in range(12):
		await process_frame

func pause() -> void:
	await create_timer(float(config.movie.pause_seconds)).timeout

func run() -> void:
	config = StoryUI.load_config()
	check(not config.is_empty(),"validated story UI movie settings")
	check(OS.has_feature("movie") and DisplayServer.get_name() != "headless","actual Movie Maker Compatibility output")
	if failures:
		quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture-dir="): fixture_directory = argument.trim_prefix("--fixture-dir=")
		elif argument.begins_with("--ending-fixture-dir="): ending_fixture_directory = argument.trim_prefix("--ending-fixture-dir=")
		elif argument.begins_with("--start-save="): start_save = argument.trim_prefix("--start-save=")
		elif argument.begins_with("--ending-save="): ending_save = argument.trim_prefix("--ending-save=")
		elif argument.begins_with("--advice-id="): advice_id = argument.trim_prefix("--advice-id=")
		elif argument.begins_with("--choices="): choices = argument.trim_prefix("--choices=").split(",",false)
		elif argument == "--probe-first-click": probe_first_click = true
		elif argument == "--logical-case-size": logical_case_size = true
		else: check(false,"unknown movie argument / "+argument)
	check(fixture_directory.begins_with("res://.tools/r3-story/") and not fixture_directory.contains(".."),"fixture directory stays inside the isolated STORY workspace")
	if ending_fixture_directory.is_empty():
		ending_fixture_directory = fixture_directory
	check(ending_fixture_directory.begins_with("res://.tools/r3-story/") and not ending_fixture_directory.contains(".."),"ending fixture directory stays inside the isolated STORY workspace")
	check(not start_save.is_empty() and not advice_id.is_empty(),"the caller supplies a legal start save and an authored advice choice")
	if failures:
		quit(1)
		return
	root.gui_embed_subwindows = true
	root.size = Vector2i(config.movie.width,config.movie.height)
	if logical_case_size:
		var board_config: Dictionary = load("res://scripts/ui/case_board_config.gd").load_config()
		root.size = Vector2i(board_config.layout.base_width,board_config.layout.base_height)
	root.content_scale_size = root.size
	game = root.get_node("GameState")
	check(game.has_method("story_view"),"root has installed the public story getter")
	if failures:
		quit(1)
		return
	root.get_node("SaveService").base_dir = fixture_directory
	game.configure_api("","","")
	game.set_people_generation_options(false)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("load_game",{"save_id":start_save})).get("success",false),"load the legally generated case-five rain-night save")
	await settle()
	first_frame = Engine.get_frames_drawn()
	print("STORY MOVIE VIEWPORT ",JSON.stringify({"root_size":str(root.size),"content_scale_size":str(root.content_scale_size),"visible_rect":str(root.get_visible_rect()),"final_transform":str(root.get_final_transform()),"native_size":str(DisplayServer.window_get_size(root.get_window_id())),"logical_case_size":logical_case_size,"source_sha256":FileAccess.get_sha256("res://tests/integration/story_movie.gd")}))
	if failures:
		await finish()
		return
	check(main.current_screen == "consultation" and main.screen.room_art.current_period == "night","the actual saved consultation uses its night art")
	check(game.people_view().get("day",{}).get("weather") == "rainy","the save owns the rainy weather")
	for choice_id: String in choices:
		await pause()
		var buttons: Array = main.screen.case_board.question_buttons.get_children().filter(func(node: Node) -> bool: return node.get_meta("choice_id","") == choice_id and not node.disabled)
		check(buttons.size() == 1,"the scripted player choice is public and enabled / "+choice_id)
		if buttons.is_empty():
			await finish()
			return
		if probe_first_click:
			print("STORY MOVIE GEOMETRY ",JSON.stringify({"root_size":str(root.size),"content_scale_size":str(root.content_scale_size),"visible_rect":str(root.get_visible_rect()),"final_transform":str(root.get_final_transform()),"native_size":str(DisplayServer.window_get_size(root.get_window_id())),"target_rect":str(buttons[0].get_global_rect()),"window_focus":root.has_focus(),"logical_case_size":logical_case_size}))
			buttons[0].gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton:
					print("STORY MOVIE GUI ",JSON.stringify({"pressed":event.pressed,"position":str(event.position),"global":str(event.global_position),"input_mask":Input.get_mouse_button_mask()}))
			)
		var before_choice: int = game.player_snapshot().state_version
		await click(buttons[0])
		check(game.player_snapshot().state_version > before_choice,"real prelude mouse click saves its actual choice / "+choice_id)
		if probe_first_click:
			print("STORY MOVIE PROBE ",JSON.stringify({"version_before":before_choice,"version_after":game.player_snapshot().state_version,"notice":main.notice.text,"prelude":game.case_board_view().prelude}))
			await finish()
			return
		if input_failed or int(game.player_snapshot().state_version) == before_choice:
			await finish()
			return
	check(not game.case_board_view().get("prelude",{}).get("blocks_progress",false),"saved prelude choices unlock the ordinary deduction flow")
	if failures:
		await finish()
		return
	while game.case_board_view().phase == "questions":
		await pause()
		var questions: Array = main.screen.case_board.question_buttons.get_children().filter(func(node: Node) -> bool: return not node.disabled)
		if questions.is_empty():
			check(false,"a basic public question remains available")
			await finish()
			return
		var before_round := int(game.case_board_view().round)
		await click(questions[0])
		if game.case_board_view().phase == "questions" and int(game.case_board_view().round) == before_round:
			check(false,"a real question click advanced the saved question round")
			await finish()
			return
	for card_index: Variant in config.movie.card_indices:
		await pause()
		await click(main.screen.case_board.find_child("CaseCard_"+str(int(card_index)),true,false))
	var projection: Dictionary = game.case_board_view()
	for index: int in range(projection.slots.size()):
		var slot: Dictionary = projection.slots[index]
		var related: Array = projection.evidence.filter(func(row: Dictionary) -> bool: return slot.id in row.slot_ids)
		check(not related.is_empty(),"the chosen questions yielded relevant public material / "+slot.id)
		if related.is_empty():
			await finish()
			return
		var board: Control = main.screen.case_board
		var tokens: Array = board.evidence_box.get_children().filter(func(node: Node) -> bool: return node.get("evidence_id") == related[0].id)
		check(not tokens.is_empty(),"the relevant material has a real drag token")
		if tokens.is_empty():
			await finish()
			return
		board.evidence_scroll.ensure_control_visible(tokens[0])
		await settle()
		await drag(tokens[0],board.slot_nodes[slot.id])
		await pause()
		var answers: Array = board.slot_nodes[slot.id].find_children("CaseAnswer_*","Button",true,false)
		var selected_index := int(config.movie.answer_indices[index]) if index < config.movie.answer_indices.size() else 0
		check(selected_index < answers.size() and not answers[selected_index].disabled,"the authored player answer is a visible candidate")
		if selected_index >= answers.size():
			await finish()
			return
		await click(answers[selected_index])
	await pause()
	var public_advice: Array = game.case_board_view().advice
	var advice_index := -1
	for index: int in range(public_advice.size()):
		if public_advice[index].id == advice_id: advice_index = index
	check(advice_index >= 0,"the chosen advice is publicly offered")
	if advice_index < 0:
		await finish()
		return
	await click(main.screen.case_board.advice_buttons.get_child(advice_index))
	check(game.case_board_view().closed,"the advice closure is committed")
	if failures:
		await finish()
		return
	await create_timer(float(config.movie.ending_hold_seconds)).timeout
	var story: Dictionary = game.call("story_view")
	if story.notes.any(func(row: Dictionary) -> bool: return not row.unlocked):
		check(not ending_save.is_empty(),"a genuinely settled follow-up save is required before showing all four pages")
		if ending_save.is_empty():
			await finish()
			return
		main.show_notice(str(config.copy.movie_reload))
		await pause()
		root.get_node("SaveService").base_dir = ending_fixture_directory
		check((await main.run_action("load_game",{"save_id":ending_save})).get("success",false),"explicitly load the legitimate later segment from its isolated saved timepoint")
		await settle()
		main.show_notice(str(config.copy.movie_segment))
		await pause()
		story = game.call("story_view")
	check(story.notes.size() == int(config.note_count) and story.notes.all(func(row: Dictionary) -> bool: return row.unlocked),"all four page bodies have actually been unlocked")
	await click(main.find_child("Navigate_people",true,false))
	await settle()
	var reader: Control = main.people_panel.story_notes
	var tabs: TabBar = main.people_panel._people_pages.get_tab_bar()
	await click_point(Vector2(main.people_window.position)+tabs.get_global_rect().position+tabs.get_tab_rect(reader.get_index()).get_center())
	await settle()
	check(main.people_panel._people_pages.current_tab == reader.get_index(),"real tab click opens the notebook reader")
	for index: int in range(reader.page_buttons.get_child_count()):
		await pause()
		await click(reader.page_buttons.get_child(index))
		check(not reader.body.text.is_empty() and reader.body.text == str(story.notes[index].text),"a real page click displays its exact committed body / "+str(index+1))
	await click(reader.close_button)
	if main.current_screen == "consultation" and game.case_board_view().get("closed",false):
		await click(main.screen.case_board.end_button)
	check(main.current_screen == "front","closing the story still returns to the working storefront")
	while Engine.get_frames_drawn()-first_frame < int(config.movie.duration_seconds)*int(config.movie.fps):
		await process_frame
	await finish()

func click(control: Control) -> void:
	if input_failed: return
	check(control != null and control.is_visible_in_tree() and not control.get("disabled"),"real click targets a visible enabled control")
	if control != null:
		var acknowledgement := {"pressed":false}
		var pressed_callback := func(): acknowledgement.pressed = true
		control.pressed.connect(pressed_callback,CONNECT_ONE_SHOT)
		var point := control.get_global_rect().get_center()
		if control.get_window() != root:
			point += Vector2(control.get_window().position)
		await click_point(point)
		var deadline := Time.get_ticks_msec()+2500
		while not acknowledgement.pressed and Time.get_ticks_msec() < deadline:
			await process_frame
			Input.flush_buffered_events()
		check(acknowledgement.pressed,"real mouse click emits pressed before recording the next step")
		if not acknowledgement.pressed:
			input_failed = true
			if is_instance_valid(control) and control.pressed.is_connected(pressed_callback):
				control.pressed.disconnect(pressed_callback)

func click_point(point: Vector2) -> void:
	if input_failed: return
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await settle()
	while main.busy:
		await process_frame

func drag(source: Control, target: Control) -> void:
	if input_failed: return
	var before_version: int = game.player_snapshot().state_version
	var origin := source.get_global_rect().get_center()
	var end := target.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = origin
	Input.parse_input_event(move)
	var down := InputEventMouseButton.new()
	down.position = origin
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	for index: int in range(int(config.movie.drag_frames)):
		move = InputEventMouseMotion.new()
		move.position = origin.lerp(end,float(index+1)/float(config.movie.drag_frames))
		move.relative = (end-origin)/float(config.movie.drag_frames)
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(move)
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
	check(int(game.player_snapshot().state_version) > before_version,"real material drag is saved before the next recording step")
	if int(game.player_snapshot().state_version) == before_version:
		input_failed = true
		return
	await settle()
	while main.busy:
		await process_frame

func finish() -> void:
	print("STORY MOVIE: %d checks, %d failures, %d frames; real controls, not human reading duration"%[checks,failures,Engine.get_frames_drawn()-first_frame])
	await Teardown.release_audio(main)
	main.queue_free()
	await settle()
	await Teardown.drain(self)
	quit(1 if failures else 0)

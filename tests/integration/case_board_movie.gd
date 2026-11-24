extends SceneTree
## Local Movie Maker capture of real mouse clicks and a real evidence drag.
## This accelerated path demonstrates operations, not human reading duration.
const UITeardown = preload("res://tests/ui_teardown.gd")
const Config = preload("res://scripts/ui/case_board_config.gd")
var main: Control
var game: Node
var config: Dictionary
var checks := 0
var failures := 0
var started_at := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("CASE BOARD MOVIE FAIL: "+label)

func settle() -> void:
	for frame: int in range(12):
		await process_frame

func pause() -> void:
	await create_timer(float(config.layout.movie_pause_seconds)).timeout

func run() -> void:
	config = Config.load_config()
	check(not config.is_empty(),"movie uses validated UI parameters")
	check(DisplayServer.get_name() != "headless" and OS.has_feature("movie"),"capture uses the real Compatibility renderer and Movie Maker")
	if failures:
		quit(1)
		return
	root.size = Vector2i(config.layout.base_width,config.layout.base_height)
	root.content_scale_size = root.size
	game = root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/case-board-movie-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"一封邀请的推理"})).get("success",false),"create isolated saved game")
	check((await main.run_action("read_morning_letters")).get("success",false),"read saved morning letters")
	check((await main.run_action("next_customer")).get("success",false),"enter the authored case through the production UI")
	await settle()
	started_at = Engine.get_frames_drawn()
	for round_index: int in range(3):
		await pause()
		var choices: Array[Node] = main.screen.case_board.question_buttons.get_children().filter(func(node: Node) -> bool: return not node.disabled)
		check(not choices.is_empty(),"a saved basic question is playable / "+str(round_index))
		if choices.is_empty():
			await finish()
			return
		await click(choices[0])
	for card_index: int in [0,2,4]:
		await pause()
		await click(main.screen.case_board.find_child("CaseCard_"+str(card_index),true,false))
	var cards_before: Array = game.case_board_view().cards.duplicate(true)
	check((await main.run_action("load_game",{"save_id":game.player_snapshot().save_id})).get("success",false),"reload the same case between the reveal and deduction phases")
	await settle()
	check(game.case_board_view().cards == cards_before,"reloading preserves the revealed cards and anonymous backs")
	var view: Dictionary = game.case_board_view()
	for slot: Dictionary in view.slots:
		await pause()
		var related: Array = view.evidence.filter(func(row: Dictionary) -> bool: return slot.id in row.slot_ids)
		if related.is_empty():
			check(false,"related public material exists / "+slot.id)
			await finish()
			return
		var board: Control = main.screen.case_board
		var tokens: Array = board.evidence_box.get_children().filter(func(node: Node) -> bool: return node.get("evidence_id") == related[0].id)
		check(not tokens.is_empty(),"the material has a real drag token / "+slot.id)
		if tokens.is_empty():
			await finish()
			return
		board.evidence_scroll.ensure_control_visible(tokens[0])
		await settle()
		await drag(tokens[0],board.slot_nodes[slot.id])
		await pause()
		var candidates: Array[Node] = board.slot_nodes[slot.id].find_children("CaseAnswer_*","Button",true,false).filter(func(node: Node) -> bool: return not node.disabled)
		check(not candidates.is_empty(),"saved drag unlocks real candidate buttons / "+slot.id)
		if candidates.is_empty():
			await finish()
			return
		await click(candidates[0])
		if slot.id == "sender":
			await pause()
			await click(board.slot_nodes[slot.id].find_children("CaseAnswer_*","Button",true,false)[1])
			await pause()
			await click(board.slot_nodes[slot.id].find_children("CaseAnswer_*","Button",true,false)[0])
	await pause()
	var suggestions: Array[Node] = main.screen.case_board.advice_buttons.get_children().filter(func(node: Node) -> bool: return not node.disabled)
	check(not suggestions.is_empty(),"completed deductions unlock a real suggestion")
	if not suggestions.is_empty():
		await click(suggestions[0])
	check(game.case_board_view().closed,"the visible suggestion commits the saved closure")
	await create_timer(float(config.layout.movie_end_seconds)).timeout
	await finish()

func click(control: Control) -> void:
	check(control != null and control.is_visible_in_tree() and not control.get("disabled"),"recorded click targets a visible enabled control")
	if control == null:
		return
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = point
	Input.parse_input_event(up)
	await settle()
	while main.busy:
		await process_frame

func drag(source: Control, target: Control) -> void:
	var origin := source.get_global_rect().get_center()
	var destination := target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = origin
	Input.parse_input_event(motion)
	var down := InputEventMouseButton.new()
	down.position = origin
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var steps := maxi(2,int(Engine.get_physics_ticks_per_second()*float(config.layout.movie_drag_seconds)))
	for step: int in range(steps):
		var point := origin.lerp(destination,float(step+1)/float(steps))
		motion = InputEventMouseMotion.new()
		motion.position = point
		motion.relative = (destination-origin)/float(steps)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		await process_frame
	var up := InputEventMouseButton.new()
	up.position = destination
	up.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(up)
	await settle()
	while main.busy:
		await process_frame

func finish() -> void:
	print("CASE BOARD MOVIE: %d checks, %d failures, %d operation frames; accelerated real controls, not a human reading-duration measurement"%[checks,failures,Engine.get_frames_drawn()-started_at])
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

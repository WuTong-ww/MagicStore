extends SceneTree
const Teardown = preload("res://tests/ui_teardown.gd")
var checks := 0
var failures := 0
var main: Control
var game: Node
var board: Control

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("R4 FLOW FAIL: "+message)
func settle() -> void:
	for frame: int in range(16): await process_frame
	while main.busy or (is_instance_valid(board) and board._pending): await process_frame
func clarity() -> void:
	check(board.flow.primary.is_visible_in_tree(),"every step retains the primary action")
	check(not board.flow.primary.disabled or (board.flow.reason.is_visible_in_tree() and not board.flow.reason.text.is_empty()),"disabled primary states exactly what remains")
func click(button: Button) -> void:
	check(not button.disabled,"necessary choice is usable: "+button.name)
	button.pressed.emit()
	if is_instance_valid(board) and board._pending: check(board.flow.reason.visible and not board.flow.reason.text.is_empty(),"pending action keeps an explicit processing hint")
	await settle()
	if is_instance_valid(board): clarity()

func run() -> void:
	game = root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/r4-flow-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280,720)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	for action: String in ["new_game","read_morning_letters","next_customer"]:
		check((await main.run_action(action,{"name":"流程验收"} if action == "new_game" else {})).get("success",false),action)
	await settle()
	board = main.screen.case_board
	clarity()
	check(board.flow.current == 0,"opening is a separate readable step")
	check(board.flow.guide.visible and board.flow.guide_text.size.x >= float(board.config.flow.guide_width),"new-save first guide has readable paper width")
	await click(board.flow.primary)
	check(board.flow.current == 1,"primary starts questions")
	for round_index: int in range(3):
		var choices: Array = board.question_buttons.get_children().filter(func(b: Node) -> bool: return not b.disabled)
		check(not choices.is_empty(),"a necessary question is offered")
		if choices.is_empty(): break
		await click(choices[0])
		if round_index == 0: check(not board.flow.guide.visible,"a committed question consumes this step's first-time guide")
	if board.flow.current == 1: await click(board.flow.primary)
	check(board.flow.current == 2,"three committed questions open the card step")
	for index: int in range(3): await click(board.card_nodes[index])
	if board.flow.current == 2: await click(board.flow.primary)
	check(board.flow.current == 3,"three committed cards open deduction")
	check(board.public_view.get("review",[]).is_empty(),"answers remain private before closure")
	check(board.drawer_open and board.paper.is_visible_in_tree(),"start deduction primary opens the actual notebook")
	for slot: Dictionary in game.case_board_view().slots:
		var related: Array = board.public_view.evidence.filter(func(row: Dictionary) -> bool: return slot.id in row.slot_ids)
		check(not related.is_empty(),"public material can fill "+slot.id)
		if related.is_empty(): continue
		var tokens: Array = board.evidence_box.get_children().filter(func(b: Node) -> bool: return b.get("evidence_id") == related[0].id)
		await click(tokens[0])
		board.activate_slot(slot.id)
		await settle()
		clarity()
		var candidates: Array = board.slot_nodes[slot.id].find_children("CaseAnswer_*","Button",true,false).filter(func(b: Node) -> bool: return not b.disabled)
		await click(candidates[0])
	check(not board.flow.primary.disabled,"three seals enable closure")
	await click(board.flow.primary)
	check(board.flow.current == 4 and not game.case_board_view().closed,"closure first opens advice selection")
	var advice: Array = board.flow.body.find_children("CaseAdvicePaper_*","Button",true,false)
	check(advice.size() in [2,3],"two or three large advice papers")
	await click(advice[0])
	check(not game.case_board_view().closed,"selecting advice does not yet commit")
	var before: Dictionary = game.snapshot()
	root.get_node("SaveService").fail_next_write = true
	await click(board.flow.primary)
	check(game.snapshot() == before and not game.case_board_view().closed,"failed confirmation preserves deductions and advice choice")
	await click(board.flow.primary)
	check(game.case_board_view().closed,"confirmation commits closure")
	check(game.case_board_view().review.size() == 3,"only committed result reveals per-slot corrections")
	await click(board.flow.primary)
	check(board.flow.reaction_seen,"reaction precedes result")
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		await settle()
		clarity()
		if DisplayServer.get_name() != "headless":
			await process_frame
			RenderingServer.force_draw()
			DirAccess.make_dir_recursive_absolute("res://.tools/c-ui-captures")
			root.get_texture().get_image().save_png("res://.tools/c-ui-captures/r4-flow-%dx%d.png"%[dimensions.x,dimensions.y])
	print("R4 FLOW: %d checks, %d failures"%[checks,failures])
	await Teardown.release_audio(main)
	main.queue_free()
	await process_frame
	await Teardown.drain(self)
	quit(1 if failures else 0)

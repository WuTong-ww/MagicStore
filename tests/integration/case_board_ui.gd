extends SceneTree
## Exercises real controls through the committed action boundary. A lost save
## must never reveal a card, unlock a slot, or change the free-question setting.
const UITeardown = preload("res://tests/ui_teardown.gd")
const Metrics = preload("res://scripts/ui/viewport_metrics.gd")
var game: Node
var saves: Node
var main: Control
var checks := 0
var failures := 0
var captures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("CASE BOARD UI FAIL: "+label)

func settle() -> void:
	for frame: int in range(14):
		await process_frame
	while is_instance_valid(main) and (main.busy or (is_instance_valid(main.screen) and main.screen.get("case_board") != null and main.screen.case_board._pending)):
		await process_frame

func run() -> void:
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(ProjectSettings.get_setting("display/window/size/window_width_override"),ProjectSettings.get_setting("display/window/size/window_height_override"))
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/case-board-ui-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"推理板界面验收"})).get("success",false),"create isolated real save")
	check((await main.run_action("read_morning_letters")).get("success",false),"read the morning letters")
	check((await main.run_action("next_customer")).get("success",false),"enter fixed invitation consultation")
	await settle()
	var board: Control = main.screen.get("case_board")
	check(board != null and board.is_visible_in_tree(),"new consultation displays the deduction board")
	if board == null:
		await finish()
		return
	check(not main.screen.input.is_visible_in_tree(),"default consultation does not require typing")
	var opening: Label = board.flow.body.get_child(1)
	check(opening.is_visible_in_tree() and opening.text == game.case_board_view().opening_statement and opening.autowrap_mode != TextServer.AUTOWRAP_OFF,"opening guidance shows the public arrival statement with wrapping")
	check(board.find_children("CaseCard_*","Button",true,false).size() == 5,"exactly five anonymous card backs are displayed")
	for card: Node in board.card_nodes:
		check(card.get_node("CardName").text.is_empty() and not card.tooltip_text.contains("deck_id"),"an unopened card has no visible identity")
	await exercise_board(board)
	await exercise_extra_question_energy()
	await finish()

func exercise_extra_question_energy() -> void:
	check((await main.run_action("new_game",{"name":"追问精力边界"})).get("success",false),"create the extra-question energy boundary save")
	check((await main.run_action("read_morning_letters")).get("success",false),"read letters for the energy boundary")
	check((await main.run_action("next_customer")).get("success",false),"start a fresh real board for the energy boundary")
	check((await main.run_action("set_free_question",{"enabled":true})).get("success",false),"enable free conversation through its saved setting")
	var board: Control = main.screen.case_board
	board.flow.primary.pressed.emit()
	await settle()
	for index: int in range(3):
		var choices: Array = game.case_board_view().questions.filter(func(row: Dictionary) -> bool: return row.enabled)
		check((await main.run_action("case_question",{"question_id":choices[0].id})).get("success",false),"complete basic questions at the energy boundary / "+str(index))
	board.flow.primary.pressed.emit()
	await settle()
	while int(game.player_snapshot().player.energy) > 10:
		var result: Dictionary = await main.run_action("talk",{"text":"我想再确认一下。"})
		check(result.get("success",false),"a real free conversation consumes configured energy")
		if not result.get("success",false):
			return
	await settle()
	board = main.screen.case_board
	check(board.extra_button.visible,"the optional question is offered at exactly enough energy")
	board.extra_button.pressed.emit()
	await settle()
	check(board.flow.page.visible and board._extra_open and not board.cards_row.visible,"the optional question opens before the energy changes")
	check((await main.run_action("talk",{"text":"让我再听听你的想法。"})).get("success",false),"free conversation can finish while extra choices are open")
	await settle()
	check(not game.case_board_view().can_extra_question,"the committed energy is now below the extra-question cost")
	check(board.cards_row.visible and not board.question_buttons.visible,"losing extra-question eligibility restores the playable card backs")

func exercise_board(board: Control) -> void:
	board.flow.primary.pressed.emit()
	await settle()
	var config: Dictionary = board.config
	var validator: GDScript = load("res://scripts/ui/case_board_config.gd")
	check(validator.config_valid(config),"new UI JSON validates")
	for invalid: Variant in [0,-1,INF,"720"]:
		var broken := config.duplicate(true)
		broken.layout.base_height = invalid
		check(not validator.config_valid(broken),"validator rejects malformed dimensions / "+str(invalid))
	var before: Dictionary = game.snapshot()
	var first: Button = board.question_buttons.get_child(0)
	saves.fail_next_write = true
	first.pressed.emit()
	await settle()
	check(game.snapshot() == before,"failed question save preserves the entire state")
	check(board.question_buttons.get_child(0).text == first.text,"failed question keeps the same choices")
	await capture_sizes("questions")
	for round_index: int in range(3):
		var questions: Array[Node] = board.question_buttons.get_children()
		var usable: Array[Node] = questions.filter(func(node: Node) -> bool: return not node.disabled)
		check(not usable.is_empty(),"a base question is available / "+str(round_index))
		if usable.is_empty():
			return
		usable[0].pressed.emit()
		await settle()
	check(game.case_board_view().phase == "cards","three saved questions lead to the card phase")
	board.flow.primary.pressed.emit()
	await settle()
	check(board.extra_button.visible,"a one-time extra question remains an explicit optional button")
	board.extra_button.pressed.emit()
	await settle()
	var extra_choices: Array[Node] = board.flow.body.find_children("CaseExtraChoice_*","Button",true,false).filter(func(node: Node) -> bool: return not node.disabled)
	check(not extra_choices.is_empty() and not board.cards_row.visible,"extra questions display their choices without overlapping the cards")
	if not extra_choices.is_empty():
		before = game.snapshot()
		saves.fail_next_write = true
		extra_choices[0].pressed.emit()
		await settle()
		check(game.snapshot() == before and board.flow.page.visible and board._extra_open,"failed extra question keeps its choices and the committed state")
		board.flow.body.find_children("CaseExtraChoice_*","Button",true,false).filter(func(node: Node) -> bool: return not node.disabled)[0].pressed.emit()
		await settle()
		check(not board.extra_button.visible and board.cards_row.visible,"the saved extra question restores the card display and consumes its one-time offer")
	var card: Button = board.find_child("CaseCard_0",true,false)
	before = game.snapshot()
	saves.fail_next_write = true
	card.pressed.emit()
	await settle()
	check(game.snapshot() == before and not game.case_board_view().cards[0].revealed,"failed card save never reveals its identity")
	check(not card.get_meta("revealed",false),"failed card save retains the displayed anonymous back")
	for index: int in range(3):
		board.find_child("CaseCard_"+str(index),true,false).pressed.emit()
		await settle()
	check(game.case_board_view().cards.filter(func(row: Dictionary) -> bool: return row.revealed).size() == 3,"three card buttons commit exactly three reveals")
	board.flow.primary.pressed.emit()
	await settle()
	var public: Dictionary = game.case_board_view()
	var color_by_kind: Dictionary = {}
	for token: Node in board.evidence_box.get_children():
		var projected: Array = public.evidence.filter(func(row: Dictionary) -> bool: return row.id == token.evidence_id)
		if not projected.is_empty():
			var material: StyleBox = token.get_theme_stylebox("normal")
			color_by_kind[projected[0].kind] = material.texture
	check(color_by_kind.has("fact") and color_by_kind.has("testimony") and color_by_kind.fact != color_by_kind.testimony,"facts and customer statements have visibly distinct material colors")
	var first_attachment := true
	for slot: Dictionary in public.slots:
		var related: Array = public.evidence.filter(func(row: Dictionary) -> bool: return slot.id in row.slot_ids)
		check(not related.is_empty(),"base route obtains relevant material / "+slot.id)
		if related.is_empty():
			return
		var target: Control = board.slot_nodes[slot.id]
		var payload := {"kind":"case_evidence","evidence_id":related[0].id}
		check(target._can_drop_data(Vector2.ZERO,payload),"slot accepts a public evidence drag / "+slot.id)
		if first_attachment:
			before = game.snapshot()
			saves.fail_next_write = true
			target._drop_data(Vector2.ZERO,payload)
			await settle()
			check(game.snapshot() == before and not game.case_board_view().slots[0].unlocked,"failed material save does not unlock its candidates")
			first_attachment = false
		target._drop_data(Vector2.ZERO,payload)
		await settle()
		var candidates: Array = target.find_children("CaseAnswer_*","Button",true,false).filter(func(node: Node) -> bool: return not node.disabled)
		check(not candidates.is_empty(),"saved related evidence unlocks candidate controls / "+slot.id)
		if candidates.is_empty():
			return
		candidates[0].pressed.emit()
		await settle()
		check(not str(game.case_board_view().slots.filter(func(row: Dictionary) -> bool: return row.id == slot.id)[0].selected).is_empty(),"answer selection is saved / "+slot.id)
		var initial_answer: String = game.case_board_view().slots.filter(func(row: Dictionary) -> bool: return row.id == slot.id)[0].selected
		if slot.id == "sender":
			var token: Node = board.evidence_box.get_children().filter(func(node: Node) -> bool: return node.get("evidence_id") == related[0].id)[0]
			token.pressed.emit()
			target.find_children("CaseAnswer_*","Button",true,false)[1].pressed.emit()
			await settle()
			check(game.case_board_view().slots[0].selected == initial_answer,"clicking a candidate area with selected material attaches the material instead of changing the answer")
		var alternatives: Array[Node] = target.find_children("CaseAnswer_*","Button",true,false).filter(func(node: Node) -> bool: return not node.disabled)
		if alternatives.size() > 1:
			alternatives[1].pressed.emit()
			await settle()
			check(game.case_board_view().slots.filter(func(row: Dictionary) -> bool: return row.id == slot.id)[0].selected != initial_answer,"the wax seal can be changed before closure / "+slot.id)
			target.find_children("CaseAnswer_*","Button",true,false)[0].pressed.emit()
			await settle()
	await capture_sizes("deduction")
	board.flow.primary.pressed.emit()
	await settle()
	var advice: Array[Node] = board.flow.body.find_children("CaseAdvicePaper_*","Button",true,false).filter(func(node: Node) -> bool: return not node.disabled)
	check(advice.size() >= 2 and advice.size() <= 3,"completed board offers two or three real suggestions")
	if not advice.is_empty():
		advice[0].pressed.emit()
		await settle()
		before = game.snapshot()
		saves.fail_next_write = true
		board.flow.primary.pressed.emit()
		await settle()
		check(game.snapshot() == before and not game.case_board_view().closed,"failed closure save leaves deductions editable")
		board.flow.primary.pressed.emit()
		await settle()
		check(game.case_board_view().closed,"suggestion saves the completed board")
		check(board.flow.page.is_visible_in_tree() and not board.reaction_label.text.is_empty(),"saved closure displays the guest reaction before its separate result page")
		await capture_sizes("closed")
	main.open_network_settings()
	await settle()
	var toggle: CheckButton = main.find_child("FreeQuestionCheck",true,false)
	check(toggle != null,"settings include the free-question preference")
	if toggle != null:
		before = game.snapshot()
		saves.fail_next_write = true
		toggle.button_pressed = true
		check(not toggle.button_pressed,"pending setting immediately retains the committed display")
		await settle()
		check(game.snapshot() == before and not toggle.button_pressed,"failed preference save rolls the toggle back")
		toggle.button_pressed = true
		await settle()
		check(game.free_question_enabled() and main.screen.input.is_visible_in_tree(),"saved preference exposes the old editor alongside the board")
		check(board.visible,"enabling free questions keeps the deduction board available")
		var saved_cards: Array = game.case_board_view().cards.duplicate(true)
		check((await main.run_action("load_game",{"save_id":game.player_snapshot().save_id})).get("success",false),"reload the committed preference and finished case")
		await settle()
		board = main.screen.case_board
		check(game.free_question_enabled() and main.screen.input.is_visible_in_tree(),"free-question preference survives a real reload")
		check(game.case_board_view().cards == saved_cards,"UI reload preserves the same saved card projection")
		toggle.get_window().hide()
		board.flow.navigate(2)
		board.set_drawer_expanded(false,false)
		await settle()
		var editor: TextEdit = main.screen.input
		var point := editor.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		root.push_input(motion,true)
		for pressed: bool in [true,false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = point
			click.global_position = point
			click.pressed = pressed
			root.push_input(click,true)
			await process_frame
		await settle()
		check(root.gui_get_focus_owner() == editor,"the free-question editor receives a real mouse click alongside the board")
		editor.text = ""
		for character: String in "我想再确认一下。":
			var key := InputEventKey.new()
			key.pressed = true
			key.unicode = character.unicode_at(0)
			root.push_input(key,true)
			await process_frame
		check(editor.text == "我想再确认一下。","the visible free-question editor accepts real Chinese keyboard events")
		before = game.snapshot()
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		root.push_input(enter,true)
		await settle()
		check(game.snapshot().state_version > before.state_version and editor.text.is_empty(),"Enter submits free text through the saved talk action")
		check(main.screen.case_board.visible and game.case_board_view().cards == saved_cards,"free conversation keeps the completed deduction board and saved cards")

func capture_sizes(phase: String) -> void:
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		var board: Control = main.screen.case_board
		var metrics: Dictionary = Metrics.measure(board)
		var area := Rect2(Vector2.ZERO,Vector2(dimensions)).grow(1)
		var last_slot: Control = board.slot_nodes[game.case_board_view().slots.back().id]
		if board.paper.is_visible_in_tree():
			check(last_slot.get_global_rect().end.x <= board.evidence_scroll.get_global_rect().position.x,"deduction candidates remain on the left notebook page / "+phase+" / "+str(dimensions))
			check(area.encloses(Metrics.css_rect(board.evidence_scroll,metrics)),"the material scroll viewport stays inside the window / "+str(dimensions))
		for control: Node in board.find_children("*","Control",true,false):
			if control.is_visible_in_tree() and (control is Button or control.name.begins_with("CaseSlot") or control.name == "CaseBoardPaper"):
				if board.evidence_scroll.is_ancestor_of(control):
					var scroll_bounds: Rect2 = Metrics.css_rect(board.evidence_scroll,metrics)
					var bounds: Rect2 = Metrics.css_rect(control,metrics)
					check(bounds.position.x >= scroll_bounds.position.x-1 and bounds.end.x <= scroll_bounds.end.x+1,"scrolling material fits its column width / "+phase+" / "+control.name)
				else:
					check(area.encloses(Metrics.css_rect(control,metrics)),"board control stays in the CSS viewport / "+phase+" / "+str(dimensions)+" / "+control.name+" / "+str(Metrics.css_rect(control,metrics)))
		if DisplayServer.get_name() != "headless":
			await create_timer(0.25).timeout
			RenderingServer.force_draw()
			DirAccess.make_dir_recursive_absolute("res://.tools/c-ui-captures")
			var path := "res://.tools/c-ui-captures/r3-case-"+phase+"-"+str(dimensions.x)+"x"+str(dimensions.y)+".png"
			check(root.get_texture().get_image().save_png(path) == OK,"save graphical capture / "+path)
			captures += 1

func finish() -> void:
	print("CASE BOARD UI: %d checks, %d failures, %d graphical captures; renderer=%s"%[checks,failures,captures,DisplayServer.get_name()])
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

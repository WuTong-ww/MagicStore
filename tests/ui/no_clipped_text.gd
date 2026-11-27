extends SceneTree
const Teardown = preload("res://tests/ui_teardown.gd")
const Readability = preload("res://scripts/ui/readability.gd")
var checks := 0
var failures := 0
var main: Control
var game: Node
var settings: Dictionary
var captures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("R4 TEXT FAIL: "+message)
func settle() -> void:
	for frame: int in range(12): await process_frame
func audit(node: Node, context: String) -> void:
	for control: Node in node.find_children("*","Control",true,false):
		if not control.is_visible_in_tree() or not (control is Button or control is Label or control is RichTextLabel): continue
		if control.text.is_empty(): continue
		var allowed_scroll := false
		var parent: Node = control.get_parent()
		while parent != null and parent != node:
			if parent is ScrollContainer: allowed_scroll = true
			parent = parent.get_parent()
		var width: float = control.size.x
		var height: float = control.size.y
		var font: Font
		var font_size: int
		var wrapped := false
		if control is RichTextLabel:
			wrapped = control.autowrap_mode != TextServer.AUTOWRAP_OFF
			check(width > 0 and (control.scroll_active or control.get_content_height() <= height+1),context+" / rich / "+str(control.name))
			check(control.get_content_width() <= width+2,context+" / rich horizontal fit / "+str(control.name))
			continue
		font = control.get_theme_font("font")
		font_size = control.get_theme_font_size("font_size")
		wrapped = control.autowrap_mode != TextServer.AUTOWRAP_OFF
		if control is Button:
			var physical := Readability.css_scale(control)
			check(height*physical.y+1 >= float(settings.button_height) and font_size*physical.y+1 >= float(settings.button_font),context+" / CSS button minimum / "+str(control.name)+" / scale="+str(physical))
			check(not control.clip_text and control.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING,context+" / button retains full text / "+str(control.name))
			var box: StyleBox = control.get_theme_stylebox("normal")
			if box != null:
				width -= box.get_minimum_size().x
				height -= box.get_minimum_size().y
			if control.icon != null: width -= control.icon.get_width()+float(settings.horizontal_padding)
		var required: Vector2 = font.get_multiline_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,width if wrapped else -1,font_size)
		check(required.x <= width+2 and (required.y <= height+2 or (allowed_scroll and control is Label)),context+" / "+str(control.name)+" / need="+str(required)+" available="+str(Vector2(width,height)))
		if control is Label: check(not control.clip_text and control.max_lines_visible < 0,context+" / label retains all lines / "+str(control.name))

func grown(text: String) -> String:
	return text+text.left(ceili(text.length()*(float(settings.long_text_factor)-1.0)))

func keep_longest(result: Dictionary, key: String, value: Variant) -> void:
	if value is String and value.length() > str(result.get(key,"")).length(): result[key] = value

func longest_public_copy() -> Dictionary:
	var result := {}
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/rules.json"))
	for id: String in rules.case_order:
		var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cases/"+id+".json"))
		keep_longest(result,"title",definition.title)
		keep_longest(result,"opening",definition.question)
		for round_questions: Array in definition.questions:
			for question: Dictionary in round_questions:
				keep_longest(result,"question",question.text)
				keep_longest(result,"reply",question.answer)
		for advice: Dictionary in definition.advice: keep_longest(result,"advice",advice.text)
		for evidence: Dictionary in definition.evidence: keep_longest(result,"evidence",evidence.text)
		for slot: Dictionary in definition.deduction_slots:
			keep_longest(result,"slot_title",slot.title)
			for candidate: Dictionary in slot.answers: keep_longest(result,"candidate",candidate.text)
	return result

func audit_title_panels() -> void:
	for supplied: Array in settings.capture_sizes:
		root.size = Vector2i(supplied[0],supplied[1])
		await settle()
		audit(main,"title / "+str(root.size))
		main.title_control.buttons["new"].pressed.emit()
		await settle()
		audit(main,"new store form / "+str(root.size))
		main.title_control.new_cancel.pressed.emit()
		main.title_control.buttons["credits"].pressed.emit()
		await settle()
		audit(main,"credits / "+str(root.size))
		main.title_control.credits_panel.find_children("*","Button",true,false).back().pressed.emit()

func audit_long_case(dimensions: Vector2i) -> void:
	main.show_screen("consultation",true)
	await settle()
	var board: Control = main.screen.case_board
	var inflated: Dictionary = game.case_board_view().duplicate(true)
	var longest := longest_public_copy()
	inflated.title = grown(str(longest.title))
	inflated.opening_statement = grown(str(longest.opening))
	inflated.last_answer = grown(str(longest.reply))
	inflated.reaction = inflated.last_answer
	inflated.show_guide = false
	for group: String in ["questions","advice","evidence"]:
		var key: String = {"questions":"question","advice":"advice","evidence":"evidence"}[group]
		for row: Dictionary in inflated.get(group,[]): row.text = grown(str(longest[key]))
	for row: Dictionary in inflated.slots:
		row.title = grown(str(longest.slot_title))
		row.unlocked = true
		for candidate: Dictionary in row.candidates:
			candidate.text = grown(str(longest.candidate))
			candidate.enabled = true
	inflated.review = []
	for index: int in range(inflated.slots.size()):
		inflated.review.append({"title":inflated.slots[index].title,"correct":index == 0,"answer":grown(str(longest.candidate))})
	if inflated.evidence.is_empty():
		for row: Dictionary in inflated.slots:
			inflated.evidence.append({"id":"layout_"+str(row.id),"kind":"testimony","source":board.config.copy.testimony,"text":grown(str(longest.evidence)),"slot_ids":[row.id]})
	var deck: Array = load("res://scripts/divination/oracle_cards.gd").load_decks().tarot
	for index: int in range(inflated.cards.size()):
		var card: Dictionary = deck[index]
		inflated.cards[index].merge({"revealed":true,"enabled":true,"deck_id":card.id,"name":card.name,"mark":card.mark,"suit":card.suit,"text":grown(str(longest.evidence)),"face":"upright"},true)
	board.public_view_getter = func() -> Dictionary: return inflated.duplicate(true)
	for phase: String in ["questions","cards","deduction","closed"]:
		inflated.phase = phase
		inflated.closed = phase == "closed"
		board.refresh()
		if phase != "closed":
			check(not board.flow.primary.disabled,"long-copy primary can enter "+phase)
			board.flow.primary.pressed.emit()
		await settle()
		audit(main,"longest public copy x1.5 / "+phase+" / "+str(dimensions))
		if phase == "cards":
			board.card_nodes[0].pressed.emit()
			await settle()
			check(is_instance_valid(board.card_zoom),"revealed card opens its real zoom overlay")
			audit(main,"longest card zoom x1.5 / "+str(dimensions))
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			board.card_zoom._gui_input(click)
			await settle()
			check(not is_instance_valid(board.card_zoom),"zoom closes before the next phase")
		if phase == "closed":
			board.flow.primary.pressed.emit()
			await settle()
			audit(main,"longest result x1.5 / "+str(dimensions))
		if phase == "deduction":
			for row: Dictionary in inflated.slots: row.selected = row.candidates[0].id
			board.refresh()
			board.flow.primary.pressed.emit()
			await settle()
			audit(main,"longest advice x1.5 / "+str(dimensions))
func capture(label: String, dimensions: Vector2i) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("res://docs/screenshots/round4/C")
	var path := "res://docs/screenshots/round4/C/%s-%dx%d.jpg"%[label,dimensions.x,dimensions.y]
	check(root.get_texture().get_image().save_jpg(path) == OK,"capture / "+path)
	captures += 1
func run() -> void:
	settings = Readability.load_config()
	check(Readability.valid(settings),"readability JSON validates")
	game = root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/r4-text-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.gui_embed_subwindows = true
	root.size = Vector2i(settings.capture_sizes[0][0],settings.capture_sizes[0][1])
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	await audit_title_panels()
	for action: String in ["new_game","read_morning_letters","next_customer"]:
		check((await main.run_action(action,{"name":"可读性验收"} if action == "new_game" else {})).get("success",false),action)
	for supplied: Array in settings.capture_sizes:
		var dimensions := Vector2i(supplied[0],supplied[1])
		root.size = dimensions
		await settle()
		for page: String in ["exterior","front","consultation","inventory","workshop","market","gathering"]:
			main.show_screen(page,true)
			await settle()
			audit(main,page+" / "+str(dimensions))
			if page in ["front","consultation","inventory"]: await capture("case" if page == "consultation" else page,dimensions)
		main.open_story_notes()
		await settle()
		audit(main,"notes / "+str(dimensions))
		await capture("notes",dimensions)
		main.people_window.hide()
		main.open_network_settings()
		await settle()
		audit(main,"settings / "+str(dimensions))
		await capture("settings",dimensions)
		for window: Node in main.get_children():
			if window is Window and window.visible: window.hide()
		main.open_saves()
		await settle()
		audit(main,"save book / "+str(dimensions))
		main.save_window.hide()
		main.open_learning()
		await settle()
		audit(main,"learning / "+str(dimensions))
		main.learning_window.hide()
		main.show_history()
		await settle()
		audit(main,"history / "+str(dimensions))
		main.history_window.hide()
		await audit_long_case(dimensions)
	print("R4 TEXT: %d checks, %d failures, %d captures"%[checks,failures,captures])
	await Teardown.release_audio(main)
	main.queue_free()
	await settle()
	await Teardown.drain(self)
	quit(1 if failures else 0)

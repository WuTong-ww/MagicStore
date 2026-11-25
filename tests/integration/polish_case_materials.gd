extends SceneTree
## Functional baseline RED: only current Main is dynamically loaded. No future
## material script is preloaded, no private truth/correct-answer field is read.
const Teardown = preload("res://tests/ui_teardown.gd")
var checks := 0
var failures := 0
var game: Node
var saves: Node
var main: Control
var board: Control
var materials: RefCounted
var save_path := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("CASE MATERIAL FAIL: "+label)

func settle() -> void:
	for frame: int in range(16): await process_frame

func role(node: Control, expected: String, label: String) -> void:
	check(node != null and node.get_meta("material_role","") == expected,label+" consumes the real material role")

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-polish/case-material-saves/"+game.make_id("run")
	game.configure_api("","","")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"面板材质事务验收"})).get("success",false),"create through the real Main action boundary")
	check((await main.run_action("read_morning_letters")).get("success",false),"read actual default sequential letters")
	check((await main.run_action("next_customer")).get("success",false),"enter the actual fixed invitation CASE")
	await settle()
	board = main.screen.get("case_board")
	check(board != null and game.case_board_view().get("enabled",false),"actual default CASE remains enabled")
	if board == null:
		await finish()
		return
	save_path = saves._path(str(game.snapshot().save_id))
	var path := "res://scripts/ui/panel_materials.gd"
	check(ResourceLoader.exists(path),"independent material implementation exists")
	if ResourceLoader.exists(path): materials = load(path).new()
	role(board.paper,"notebook","deduction notebook")
	role(board.speech_panel,"letter","public guest letter")
	role(main.screen.drawer_panel,"notebook","legacy tools notebook")
	var nameplate: Control = board.find_child("CaseGuestNameplate",true,false)
	check(nameplate != null,"actual letter exposes its upper-left nameplate")
	if nameplate != null:
		var name_text: Label = nameplate.find_child("CaseGuestNameText",true,false)
		check(name_text != null and name_text.text == game.divination_view().get("guest",{}).get("name", ""),"nameplate renders only the already public guest name")
	for slot: Dictionary in game.case_board_view().slots:
		var control: Control = board.slot_nodes[slot.id]
		role(control,"plain","notebook inner deduction section")
		check(control.find_child("CaseDropOutline",true,false) != null,"only an empty deduction slot has a gold dashed target")
	for card: Button in board.card_nodes:
		role(card,"tarot_card","tabletop tarot hit target")
		check(card.get_theme_stylebox("normal") is StyleBoxEmpty,"tarot is not surrounded by another paper frame")
		var art: TextureRect = card.get_node("CardArt")
		check(art.material is ShaderMaterial or art.scale.y < 1.0,"actual card art has the configured tabletop flattening")
		check(card.get_children().any(func(node: Node) -> bool: return bool(node.get_meta("material_contact_shadow",false))),"actual tarot contact shadow is installed")
	if materials != null and materials.has_method("evidence_role"):
		check(materials.call("evidence_role","misleading") == "neutral" and materials.call("evidence_role","unknown") == "neutral","unknown/public misleading kinds gain no correctness marker")
	else:
		check(false,"public-only evidence classification entry exists")
	await enter_deduction()
	await finish()

func enter_deduction() -> void:
	for round: int in range(3):
		var questions: Array = game.case_board_view().get("questions",[]).filter(func(row: Dictionary) -> bool: return row.get("enabled",false))
		check(not questions.is_empty(),"a genuine public base question is available")
		if questions.is_empty(): return
		check((await main.run_action("case_question",{"question_id":questions[0].id})).get("success",false),"save actual base question")
	for index: int in range(3):
		check((await main.run_action("case_flip_card",{"card_index":index})).get("success",false),"save one actual base tarot reveal")
	await settle()
	var view: Dictionary = game.case_board_view()
	check(view.get("phase") == "deduction","actual questions and flips unlock deduction")
	for token: Control in board.evidence_box.get_children():
		if not token.get_property_list().any(func(row: Dictionary) -> bool: return row.name == "evidence_id"): continue
		var rows: Array = view.evidence.filter(func(row: Dictionary) -> bool: return row.id == token.evidence_id)
		check(not rows.is_empty(),"each displayed tag has an actual public source")
		if rows.is_empty(): continue
		var kind: String = str(rows[0].get("kind",""))
		var classification: String = kind if kind in ["fact","testimony","tool"] else "neutral"
		role(token,"evidence_"+classification,"public evidence tag")
		check(token.tooltip_text == token.text,"full public evidence tooltip survives material dressing")
		var properties: Array = token.get_property_list().map(func(row: Dictionary) -> String: return str(row.name))
		check("drag_preview_factory" in properties,"tag keeps its payload API and exposes a presentation-only preview factory")
		if "drag_preview_factory" in properties:
			var factory: Callable = token.get("drag_preview_factory")
			check(factory.is_valid(),"actual tag is wired to the material preview factory")
	var first_slot: Dictionary = view.slots[0]
	var related: Array = view.evidence.filter(func(row: Dictionary) -> bool: return first_slot.id in row.slot_ids)
	check(not related.is_empty(),"unlock uses genuine already public routing evidence")
	if related.is_empty(): return
	var target: Control = board.slot_nodes[first_slot.id]
	var payload: Dictionary = {"kind":"case_evidence","evidence_id":related[0].id}
	check(target._can_drop_data(Vector2.ZERO,payload),"existing drag/drop payload contract is retained")
	var before: Dictionary = game.snapshot()
	var original_disk: String = FileAccess.get_sha256(save_path)
	saves.fail_next_write = true
	target._drop_data(Vector2.ZERO,payload)
	await settle()
	check(game.snapshot() == before and FileAccess.get_sha256(save_path) == original_disk,"failed evidence save changes neither world nor disk")
	check(target.find_child("CaseDropOutline",true,false) != null,"failed evidence save does not erase its empty-slot outline")
	target._drop_data(Vector2.ZERO,payload)
	await settle()
	check(target.find_child("CaseDropOutline",true,false) == null,"saved evidence removes the empty-slot dashed outline")
	var candidates: Array[Node] = target.find_children("CaseAnswer_*","Button",true,false)
	check(not candidates.is_empty(),"saved evidence exposes actual candidate controls")
	if candidates.is_empty(): return
	var angles: Array = []
	for candidate: Button in candidates:
		role(candidate,"candidate","borderless answer strip")
		check(absf(rad_to_deg(candidate.rotation)) <= 1.5001,"paper angle stays in the configured small range")
		angles.append(candidate.rotation)
	check(angles.any(func(value: float) -> bool: return absf(value)>0.00001),"paper strips have actual stable presentation variation")
	before = game.snapshot()
	original_disk = FileAccess.get_sha256(save_path)
	saves.fail_next_write = true
	candidates[0].pressed.emit()
	await settle()
	check(game.snapshot() == before and FileAccess.get_sha256(save_path) == original_disk,"failed selection save changes neither world nor disk")
	check(target.find_child("CaseWaxSeal",true,false) == null,"a failed selection cannot display its red stamp")
	var current: Array[Node] = target.find_children("CaseAnswer_*","Button",true,false)
	current[0].pressed.emit()
	await settle()
	var selected: String = str(game.case_board_view().slots[0].get("selected",""))
	var stamp: Control = target.find_child("CaseWaxSeal",true,false)
	check(not selected.is_empty() and stamp is TextureRect and stamp.texture != null,"only the saved candidate receives the actual red-stamp texture")
	if stamp != null: check(stamp.get_parent() is Button,"the stamp belongs on the selected strip rather than another framed header")
	var saved: Dictionary = game.snapshot()
	original_disk = FileAccess.get_sha256(save_path)
	main.show_screen("front")
	await settle()
	main.show_screen("consultation")
	await settle()
	board = main.screen.case_board
	var rebuilt: Array[Node] = board.slot_nodes[first_slot.id].find_children("CaseAnswer_*","Button",true,false)
	check(rebuilt.size() == angles.size(),"navigation reconstructs the same actual public candidates")
	if rebuilt.size() == angles.size():
		for i: int in range(rebuilt.size()): check(is_equal_approx(rebuilt[i].rotation,float(angles[i])),"rebuild derives exactly the same local paper angle")
	check(game.snapshot() == saved and FileAccess.get_sha256(save_path) == original_disk,"presentation reconstruction leaves every saved record and byte untouched")

func finish() -> void:
	if is_instance_valid(main):
		check(await main.prepare_close_async(),"standard Main TITLE/audio/motion lifecycle shuts down")
		main.queue_free()
		await settle()
	await Teardown.drain(self)
	print("CASE MATERIALS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

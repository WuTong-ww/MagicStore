extends SceneTree
const Art = preload("res://scripts/ui/case_card_art.gd")
const Metrics = preload("res://scripts/ui/viewport_metrics.gd")
var checks := 0
var failures := 0
var board: Control
var view: Dictionary
class Host extends Control:
	var busy := false
	var shell_header: Control
	var shell_dock: Control
	func show_notice(_text: String) -> void: pass
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("R4 CARD FAIL: "+text)
func settle() -> void:
	for frame: int in range(16): await process_frame
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.tools/r4-cards")
	var path := "res://.tools/r4-cards/card_art.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"tarot":{"star":"res://assets/ui/tarot_star.png"}}))
	file.close()
	check(Art.load_index("res://.tools/r4-cards/absent.json").is_empty(),"missing interface file uses fallback")
	var index := Art.load_index(path)
	check(index.has("star") and Art.texture("star",index) != null,"existing interface file resolves real image")
	check(Art.texture("hermit",index) == null,"missing key uses fallback")
	check(Art.texture("star",{"star":"res://assets/absent.webp"}) == null,"missing image uses fallback")
	check(not Art.valid({"version":1,"tarot":{"star":"res://../secret.png"}}),"invalid art paths fail validation")
	var host := Host.new()
	root.add_child(host)
	view = {"enabled":true,"id":"test","visit_id":"test","phase":"cards","round":3,"cards":[],"slots":[],"advice":[],"questions":[],"evidence":[]}
	for i: int in range(5): view.cards.append({"index":i,"revealed":false,"enabled":true})
	board = load("res://scripts/ui/case_board.gd").new()
	board.host = host
	board.public_view_getter = func() -> Dictionary: return view.duplicate(true)
	board.command_submitter = func(_action: String, values: Dictionary) -> Dictionary:
		view.cards[int(values.card_index)].merge({"revealed":true,"enabled":false,"deck_id":"star","name":"星星","mark":"XVII","text":"这是一段保留在牌下纸条中的牌示。","face":"upright"},true)
		return {"success":true}
	host.add_child(board)
	board.card_art_index = {}
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		host.size = Vector2(dimensions)
		board.size = host.size
		await settle()
		board._layout_cards_on_table()
		await settle()
		var box := Metrics.css_rect(board.card_nodes[0].get_node("CardArt"),Metrics.measure(board))
		check(box.size.y >= 150,"table card stays at least 150 physical pixels high")
		check(absf(box.size.x/box.size.y-7.0/12.0) < 0.01,"table face keeps 7:12 ratio")
	board.card_nodes[0].pressed.emit()
	while board._pending: await process_frame
	await settle()
	check(board.card_nodes[0].get_node("CardBlankFace").visible,"missing art shows paper")
	check(board.card_nodes[0].get_node("CardName").text == "星星" and board.card_nodes[0].get_node("CardRank").text == "XVII","fallback includes card name and Roman numeral")
	check(board.card_nodes[0].get_node("CardClueStrip").visible,"successful flip displays clue strip")
	board.show_card_zoom(0)
	await settle()
	check(is_instance_valid(board.card_zoom) and board.card_zoom.face.size.y >= root.size.y*0.69,"revealed card expands to 70 percent of screen height")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	board.card_zoom._gui_input(event)
	await settle()
	check(not is_instance_valid(board.card_zoom),"click closes zoom")
	board.card_art_index = index
	board.refresh()
	check(board.card_nodes[0].get_node("CardArt").texture != null and not board.card_nodes[0].get_node("CardBlankFace").visible,"same revealed card uses B-line art when available")
	print("R4 CARDS: %d checks, %d failures"%[checks,failures])
	host.queue_free()
	await settle()
	quit(1 if failures else 0)

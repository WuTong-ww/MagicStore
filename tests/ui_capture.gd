extends SceneTree
## Deterministic UI smoke in an isolated directory. With a graphical renderer,
## also writes 1280x720 and 1920x1080 screenshots to .tools/ui-captures/.

var game: Node
var main: Control
var checks := 0
var failures := 0
var captured: PackedStringArray = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/ui-test-saves/" + game.make_id("run")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check(main.save_window.visible, "startup shows save selector")
	await capture("save-picker-1280")
	var result: Dictionary = await main.run_action("new_game", {"name": "界面验收独立存档"})
	check(result.get("success", false), "new game through UI dispatcher")
	await settle()
	check(not main.save_window.visible, "new game dismisses save selector")
	check_layout("front1280")
	await capture("front-1280")
	await main.run_action("start_visit")
	await settle()
	check(main.current_screen == "consultation", "start visit opens consultation")
	check_layout("consultation1280")
	var original_id: String = game.active_visit().get("visit_id", "")
	var before: Dictionary = game.snapshot()
	main.screen.input.text = "我想问邀请\n"
	await settle()
	check(game.snapshot() == before, "Chinese text and newline do not submit or advance clock")
	await main.screen._send_text()
	check(main.screen.input.text.is_empty(), "explicit send clears text on success")
	check(not game.active_visit().get("clue_ids", []).is_empty(), "explicit Chinese send records clue")
	await main.run_action("reading")
	await settle()
	var reading: Dictionary = game.active_visit().get("reading", {}).duplicate(true)
	check(not reading.is_empty(), "UI reading settles")
	check(main.screen.reading_button.disabled, "settled reading button prevents duplicate click")
	check(main.screen.card_title.text == reading.get("title"), "UI displays persisted card")
	check_layout("reading1280")
	await capture("consultation-1280")
	main.show_screen("front")
	await settle()
	check(game.active_visit().get("visit_id") == original_id, "return retains visit")
	await main.run_action("start_visit")
	await settle()
	check(game.active_visit().get("reading") == reading, "continue retains original reading")
	main.show_history()
	await settle()
	check(main.history_text.text.contains(reading.get("title", "")), "history includes saved card")
	main.history_window.hide()
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	await settle()
	check_layout("consultation1920")
	await capture("consultation-1920")
	main.show_screen("front")
	await settle()
	check_layout("front1920")
	await capture("front-1920")
	print("UI_SMOKE: %d checks, %d failures; captures: %s" % [checks, failures, ", ".join(captured)])
	quit(1 if failures else 0)

func settle() -> void:
	for frame in range(10):
		await process_frame

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("UI FAIL: " + description)

func check_layout(label: String) -> void:
	check(main.screen.get_combined_minimum_size().y <= main.scene_holder.size.y, label + " scene fits available height")
	check(main.screen.get_global_rect().end.y <= main.notice.get_global_rect().position.y + 1, label + " scene does not overlap footer")
	check(main.resources.get_global_rect().end.y < main.scene_holder.get_global_rect().position.y, label + " status stays above scene")
	check_buttons(main.screen, label)

func check_buttons(node: Node, label: String) -> void:
	if node is Button or node is TextEdit:
		var rect: Rect2 = node.get_global_rect()
		check(Rect2(Vector2.ZERO, main.size).encloses(rect), label + " control remains inside window: " + str(node.name))
	for child in node.get_children():
		check_buttons(child, label)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Wait for the screen fade; wall time here is presentation only.
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var directory := "res://.tools/ui-captures"
	DirAccess.make_dir_recursive_absolute(directory)
	var image: Image = root.get_texture().get_image()
	var path := directory + "/" + label + ".png"
	check(image.save_png(path) == OK, "save screenshot " + label)
	captured.append(path)

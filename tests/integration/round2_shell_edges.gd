extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
## Local async fixture: no HTTP, user saves, or external account state.
const Shell = preload("res://scripts/ui/shell_config.gd")

class HeldProvider extends RefCounted:
	signal released
	var source: RefCounted
	var pending := false
	var cancelled := false
	var cancel_count := 0
	func _init(original: RefCounted) -> void:
		source = original
	func request_reply(request: Dictionary) -> Dictionary:
		pending = true
		cancelled = false
		await released
		pending = false
		if cancelled:
			return {"reply_text":"", "intent":"clarify", "clue_ids":[], "needs_clarification":true, "error_code":"CANCELLED"}
		return source.request_reply(request)
	func cancel() -> void:
		cancel_count += 1
		cancelled = true
		if pending:
			released.emit()
	func status() -> Dictionary:
		return {"mode":"online"}

var checks := 0
var failures := 0
var game: Node
var main: Control
var talk_done := false
var talk_result: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ROUND2 SHELL EDGES FAIL: " + label)

func settle() -> void:
	for frame: int in range(12):
		await process_frame

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle()

func run() -> void:
	check_config_edges()
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	root.get_node("SaveService").base_dir = "res://.tools/round2-shell-edge-saves/" + game.make_id("run")
	game.configure_api("", "", "")
	game.set_people_generation_options(false)
	OS.set_environment("MAGIC_DEV_FIXTURES", "0")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	var empty_energy := main.find_child("EnergyText", true, false) as Label
	check(empty_energy != null and not empty_energy.is_visible_in_tree() and not main.energy_bar.is_visible_in_tree(), "empty save hides numeric energy and its bar together")
	check((await main.run_action("new_game", {"name":"界面边界回归"})).success, "create isolated save")
	await check_header()
	await check_popups()
	await check_drawer()
	await check_cancel()
	await check_header_transactions()
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	print("ROUND2 SHELL EDGES: %d checks, %d failures" % [checks, failures])
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func check_config_edges() -> void:
	var config := Shell.load_config()
	check(not config.is_empty(), "production shell configuration validates")
	var invalid := config.duplicate(true)
	invalid.status_format = "%d %d %s"
	check(not Shell.config_valid(invalid), "status format rejects wrong placeholder count")
	invalid = config.duplicate(true)
	invalid.status_format = "%s %d %s %d"
	check(not Shell.config_valid(invalid), "status format rejects wrong placeholder types")
	invalid = config.duplicate(true)
	invalid.energy_format = "%d"
	check(not Shell.config_valid(invalid), "energy format requires both numeric fields")
	invalid = config.duplicate(true)
	invalid.screen_minimum = [800.5, 600]
	check(not Shell.config_valid(invalid), "minimum dimensions reject fractional pixels")
	invalid = config.duplicate(true)
	invalid.screen_minimum = [INF, 600]
	check(not Shell.config_valid(invalid), "minimum dimensions reject infinite pixels")
	invalid = config.duplicate(true)
	invalid.layout.low_energy_ratio = 1.1
	check(not Shell.config_valid(invalid), "low energy threshold rejects ratio above one")
	for value: Variant in [15,16.5,INF]:
		invalid = config.duplicate(true)
		invalid.layout.status_size = value
		check(not Shell.config_valid(invalid), "header font rejects too-small, fractional or infinite size / " + str(value))
	invalid = config.duplicate(true)
	invalid.layout.energy_bar_height = 0
	check(not Shell.config_valid(invalid), "energy bar height rejects zero pixels")
	invalid = config.duplicate(true)
	invalid.layout.energy_gap = 1.5
	check(not Shell.config_valid(invalid), "energy stack gap rejects fractional pixels")

func check_header() -> void:
	var energy := main.find_child("EnergyText", true, false) as Label
	check(energy != null, "header has a genuine numeric energy label")
	var expected_size := int(main.shell_config.layout.status_size)
	var before: Dictionary = game.snapshot()
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(800,600)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		var header: Rect2 = main.shell_header.get_global_rect()
		check(is_equal_approx(header.size.y,float(main.shell_config.top_height)), "header retains configured height / " + str(dimensions))
		check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(header), "header fits viewport / " + str(dimensions))
		check(main.resources.get_theme_font_size("font_size") == expected_size and expected_size >= 16, "coins reputation date queue keep one readable font / " + str(dimensions))
		check(header.encloses(main.resources.get_global_rect()) and main.resources.get_visible_line_count() >= main.resources.get_line_count(), "status wraps completely within header without clipping / " + str(dimensions))
		check(main.resources.size.y + 1 >= main.resources.get_line_count() * main.resources.get_line_height(), "every status line has its full height / " + str(dimensions))
		for child: Node in main.shell_header.find_children("*","Button",true,false):
			var button := child as Button
			check(button.get_theme_font_size("font_size") == expected_size and header.encloses(button.get_global_rect()), "header actions share readable size and fit / " + button.text + " / " + str(dimensions))
		if energy != null:
			check(energy.is_visible_in_tree() and energy.text == main.shell_config.energy_format % [int(game.state.player.energy),int(game.content.rules.max_energy)], "energy text uses the actual snapshot and configured maximum / " + str(dimensions))
			check(energy.get_theme_font_size("font_size") == expected_size and header.encloses(energy.get_global_rect()) and header.encloses(main.energy_bar.get_global_rect()), "energy label and bar fit at the same font size / " + str(dimensions))
			check(energy.size.x + 1 >= energy.get_theme_font("font").get_string_size(energy.text,HORIZONTAL_ALIGNMENT_LEFT,-1,expected_size).x, "energy digits remain fully visible / " + str(dimensions))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://.tools/A3R-tail-header/captures")
			check(root.get_texture().get_image().save_png("res://.tools/A3R-tail-header/captures/header-%dx%d.png" % [dimensions.x,dimensions.y]) == OK, "capture actual header pixels / " + str(dimensions))
	check(game.snapshot() == before, "header relayout never changes saved game state")
	root.size = Vector2i(800,600)
	root.content_scale_size = root.size
	await settle()

func check_header_transactions() -> void:
	var energy := main.find_child("EnergyText", true, false) as Label
	if energy == null:
		return
	var before: Dictionary = game.snapshot()
	var old_text := energy.text
	root.get_node("SaveService").fail_next_write = true
	var failed: Dictionary = await main.run_action("reading")
	check(not failed.get("success",false) and failed.get("error_code") == "SAVE_WRITE_FAILED", "genuine energy-consuming reading reaches failed-save path")
	check(game.snapshot() == before and energy.text == old_text and int(main.energy_bar.value) == int(before.player.energy), "failed save publishes neither numeric nor bar energy")
	var result: Dictionary = await main.run_action("reading")
	check(result.get("success",false), "genuine paid reading commits normally")
	check(int(game.state.player.energy) == int(before.player.energy)-int(game.content.rules.reading_energy), "reading changes actual committed energy")
	check(energy.text == main.shell_config.energy_format % [int(game.state.player.energy),int(game.content.rules.max_energy)] and int(main.energy_bar.value) == int(game.state.player.energy), "numeric energy and bar refresh together only after commit")
	check((await main.run_action("rest")).get("success",false), "normal rest commits a different real energy value")
	check(energy.text == main.shell_config.energy_format % [int(game.state.player.energy),int(game.content.rules.max_energy)], "numeric energy follows later rest rather than a fixed sample")

func check_popups() -> void:
	var before: Dictionary = game.snapshot()
	var requested_people: Array[Vector2i] = []
	main.people_window.about_to_popup.connect(func(): requested_people.append(main.people_window.size), CONNECT_ONE_SHOT)
	main.open_people()
	await settle()
	check(main.people_window.visible, "people popup opens at minimum window size")
	check(main.people_window.size.x <= mini(root.size.x, 960) and main.people_window.size.y <= root.size.y, "people popup fits 800x600 and 960 width limit")
	check(main.people_window.position.x >= 0 and main.people_window.position.y >= 0, "people popup never starts outside viewport")
	check(requested_people.size() == 1 and requested_people[0].x <= mini(root.size.x, 960) and requested_people[0].y <= root.size.y, "requested people dimensions fit before headless OS normalization")
	main.people_window.hide()
	var requested_history: Array[Vector2i] = []
	main.history_window.about_to_popup.connect(func(): requested_history.append(main.history_window.size), CONNECT_ONE_SHOT)
	main.show_history()
	await settle()
	check(main.history_window.visible, "history popup opens at minimum window size")
	check(main.history_window.size.x <= mini(root.size.x, 960) and main.history_window.size.y <= root.size.y, "history popup fits 800x600 and 960 width limit")
	check(main.history_window.position.x >= 0 and main.history_window.position.y >= 0, "history popup never starts outside viewport")
	check(requested_history.size() == 1 and requested_history[0].x <= mini(root.size.x, 960) and requested_history[0].y <= root.size.y, "requested history dimensions fit before headless OS normalization")
	main.history_window.hide()
	check(game.snapshot() == before, "opening information popups preserves saved state")

func check_drawer() -> void:
	main.show_screen("front")
	await settle()
	var drawer: Control = main.screen.get_node("FrontDrawer")
	var before: Dictionary = game.snapshot()
	check(drawer.expanded and drawer.panel.visible, "front drawer starts expanded")
	await click(drawer.bookmark)
	await create_timer(float(drawer.config.drawer_seconds) + 0.05).timeout
	check(not drawer.expanded and not drawer.panel.visible, "real bookmark click collapses drawer")
	await click(drawer.bookmark)
	await create_timer(float(drawer.config.drawer_seconds) + 0.05).timeout
	check(drawer.expanded and drawer.panel.visible, "real bookmark click reopens drawer")
	check(game.snapshot() == before, "drawer toggles preserve saved state")

func start_talk() -> void:
	talk_done = false
	talk_result = await main.run_action("talk", {"text":"修书时怎样让自己静下来？", "topic_id":"work"})
	talk_done = true

func check_cancel() -> void:
	check((await main.run_action("start_arrival", {"arrival_id":"arrival_opening_lin"})).success, "start a genuine queued visitor")
	var cancel := main.find_child("CancelDialogue", true, false) as Button
	check(cancel != null, "cancel dialogue entry exists")
	if cancel != null:
		check(not cancel.visible, "cancel entry is hidden while idle")
	var provider := HeldProvider.new(game.dialogue_provider)
	game.dialogue_provider = provider
	var before: Dictionary = game.snapshot()
	start_talk()
	await settle()
	check(provider.pending and main.busy and not talk_done, "fixture holds an actual async talk request")
	if cancel != null:
		check(cancel.is_visible_in_tree(), "cancel entry becomes visible during talk")
		await click(cancel)
	else:
		# Always release the fixture even on RED so the test cannot hang.
		provider.cancel()
	await settle()
	check(provider.cancel_count == 1 and talk_done and talk_result.get("error_code") == "CANCELLED", "cancel button cancels provider request")
	check(game.snapshot() == before, "cancelled talk does not settle time or dialogue")
	if cancel != null:
		check(not cancel.visible, "cancel entry hides after cancellation")
	start_talk()
	await settle()
	if cancel != null:
		check(cancel.is_visible_in_tree(), "cancel entry appears again for a later talk")
	provider.released.emit()
	await settle()
	check(talk_done and talk_result.get("success", false), "later request can complete and save normally")
	if cancel != null:
		check(not cancel.visible, "cancel entry hides after successful talk")

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
	root.get_node("SaveService").base_dir = "res://.tools/round2-shell-edge-saves/" + game.make_id("run")
	game.configure_api("", "", "")
	game.set_people_generation_options(false)
	OS.set_environment("MAGIC_DEV_FIXTURES", "0")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game", {"name":"界面边界回归"})).success, "create isolated save")
	await check_popups()
	await check_drawer()
	await check_cancel()
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

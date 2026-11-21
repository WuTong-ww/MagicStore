extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
## Focused Viewport input exercises native TextEdit/Button dispatch. Unicode
## fixture keys verify committed Chinese text; this does not simulate an IME.

class FixtureProvider extends RefCounted:
	var requests: Array = []
	var fail_next := false
	func request_reply(request: Dictionary) -> Dictionary:
		requests.append(request.duplicate(true))
		var failed := fail_next
		fail_next = false
		return {"intent":"work","reply_text":"我愿意把眼前的顾虑慢慢说清楚。","clue_ids":[],"branch_id":"","needs_clarification":false,"error_code":"FIXTURE_FAILURE" if failed else ""}

class FakeHost extends Node:
	signal released
	var game: Node
	var busy := false
	var hold := false
	var calls: Array = []
	var results: Array = []
	var notices: Array = []
	func _init(game_node: Node) -> void:
		game = game_node
	func run_action(kind: String, extra: Dictionary = {}) -> Dictionary:
		if busy:
			return {"success":false,"error_code":"BUSY"}
		busy = true
		calls.append({"type":kind,"extra":extra.duplicate(true)})
		var action := {"type":kind,"action_id":game.make_id("keyboard_ui"),"expected_version":game.state.state_version}
		action.merge(extra,true)
		if hold:
			await released
		var result: Dictionary = await game.execute_action_async(action)
		results.append(result.duplicate(true))
		busy = false
		return result
	func show_notice(text: String) -> void:
		notices.append(text)
	func show_screen(_screen: String) -> void:
		pass
	func open_divination(_screen: String) -> void:
		pass
	func show_history() -> void:
		pass
	func confirm_return_visit() -> void:
		pass
	func confirm_contact_invitation() -> void:
		pass

var game: Node
var saves: Node
var main: Control
var screen: Control
var host: FakeHost
var provider: FixtureProvider
var checks := 0
var failures := 0
var captures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: "+label)

func settle() -> void:
	for frame: int in range(8):
		await process_frame

func focus_input() -> void:
	screen.input.grab_focus()
	await settle()
	check(root.gui_get_focus_owner() == screen.input,"native TextEdit owns keyboard focus")

func key_event(code: int, pressed := true, shift := false, echo := false, unicode_value := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	event.echo = echo
	event.unicode = unicode_value
	root.push_input(event,true)
	await process_frame

func type_unicode(text: String) -> void:
	for character: String in text:
		await key_event(KEY_NONE,true,false,false,character.unicode_at(0))
		await key_event(KEY_NONE,false,false,false,character.unicode_at(0))

func mouse_click(button: Button) -> void:
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		root.push_input(event,true)
		await process_frame
	await settle()

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/test-chat-keyboard-ui/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	OS.set_environment("MAGIC_DEV_FIXTURES","0")
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"键盘交谈本地回归"})).success,"create isolated keyboard UI save")
	check((await main.run_action("start_arrival",{"arrival_id":"arrival_opening_lin"})).success,"start the actual queued guest")
	screen = main.screen
	provider = FixtureProvider.new()
	game.dialogue_provider = provider
	host = FakeHost.new(game)
	root.add_child(host)
	screen.host = host
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		await focus_input()
		screen.input.text = ""
		var first_line := "中文原样：修书与日常。"
		var second_line := "第二行，保留标点。"
		await type_unicode(first_line)
		check(screen.input.text == first_line,"native Unicode key events preserve Chinese and punctuation")
		var before: Dictionary = game.snapshot()
		var call_count := host.calls.size()
		await key_event(KEY_ENTER,true,true)
		await key_event(KEY_ENTER,false,true)
		await type_unicode(second_line)
		var expected := first_line+"\n"+second_line
		check(screen.input.text == expected and screen.input.get_line_count() == 2,"focused Shift+Enter inserts a newline in the editor; actual="+JSON.stringify(screen.input.text))
		check(host.calls.size() == call_count and game.snapshot() == before,"inserting a newline neither submits nor consumes game time")
		await inspect_render(dimensions)
		await key_event(KEY_ENTER)
		await key_event(KEY_ENTER,false)
		await settle()
		check(host.calls.size() == call_count+1 and host.calls.back().extra.text == expected,"focused main Enter submits exactly the full multiline question")
		check(host.results.back().success and game.active_visit().dialogue[-2].text == expected and provider.requests.back().input_text == expected,"Chinese text and its newline reach the provider and saved transcript unchanged")
		check(int(game.state.clock_minutes) == int(before.clock_minutes)+5 and int(game.state.state_version) == int(before.state_version)+1 and screen.input.text.is_empty(),"successful Enter sends once, commits once and clears the editor")
		await focus_input()
		screen.input.text = "小键盘回车也能发送。"
		call_count = host.calls.size()
		await key_event(KEY_KP_ENTER)
		await key_event(KEY_KP_ENTER,false)
		await settle()
		check(host.calls.size() == call_count+1 and host.results.back().success and game.active_visit().dialogue[-2].text == "小键盘回车也能发送。" and screen.input.text.is_empty(),"focused keypad Enter submits once without adding a newline")

	await focus_input()
	screen.input.text = "保留前句替换部分保留后句"
	screen.input.select(0,4,0,8)
	var before: Dictionary = game.snapshot()
	var call_count := host.calls.size()
	await key_event(KEY_ENTER,true,true)
	await key_event(KEY_ENTER,false,true)
	check(screen.input.text == "保留前句\n保留后句" and screen.input.get_caret_line() == 1 and screen.input.get_caret_column() == 0,"Shift+Enter replaces the selected text and leaves the caret after the inserted newline")
	check(host.calls.size() == call_count and game.snapshot() == before,"selection replacement remains an edit without submitting")
	for invalid_text: String in [" \t ","问".repeat(501)]:
		screen.input.text = invalid_text
		var notice_count := host.notices.size()
		await key_event(KEY_ENTER)
		await key_event(KEY_ENTER,false)
		await settle()
		check(host.calls.size() == call_count and game.snapshot() == before,"blank or over-limit Enter never submits or consumes time; length="+str(invalid_text.length()))
		check(screen.input.text == invalid_text and screen.input.editable and not screen.send_button.disabled,"invalid Enter preserves the editor without inserting a newline; length="+str(invalid_text.length()))
		check(host.notices.size() == notice_count+1,"invalid Enter explains why the question was not sent; length="+str(invalid_text.length()))
	screen.input.text = "长按测试：一问只发送一次。"
	var request_count := provider.requests.size()
	host.hold = true
	await key_event(KEY_ENTER)
	check(host.calls.size() == call_count+1 and host.busy and screen.send_button.disabled and not screen.input.editable,"first Enter latches submission and disables editing while the real action is held")
	for repeat_index: int in range(3):
		await key_event(KEY_ENTER,true,false,true)
	await key_event(KEY_ENTER,false)
	await key_event(KEY_KP_ENTER)
	await key_event(KEY_KP_ENTER,false)
	await mouse_click(screen.send_button)
	check(host.calls.size() == call_count+1 and provider.requests.size() == request_count and game.snapshot() == before,"echo, release, keypad and mouse cannot duplicate a pending request")
	host.released.emit()
	await settle()
	host.hold = false
	check(provider.requests.size() == request_count+1 and int(game.state.clock_minutes) == int(before.clock_minutes)+5 and int(game.state.state_version) == int(before.state_version)+1,"held submission reaches the provider and commits exactly once")
	check(screen.input.text.is_empty() and screen.input.editable and not screen.send_button.disabled,"completion restores usable controls")

	await focus_input()
	screen.input.text = "松开按键不应提交。"
	before = game.snapshot()
	call_count = host.calls.size()
	await key_event(KEY_ENTER,true,false,true)
	await key_event(KEY_ENTER,false)
	await key_event(KEY_KP_ENTER,true,false,true)
	await key_event(KEY_KP_ENTER,false)
	check(host.calls.size() == call_count and game.snapshot() == before and screen.input.text == "松开按键不应提交。","echo and key release stay inert after the previous request has completed")
	host.busy = true
	await settle()
	await key_event(KEY_ENTER)
	await key_event(KEY_ENTER,false)
	check(host.calls.size() == call_count and game.snapshot() == before,"external host busy state also blocks keyboard submission")
	host.busy = false
	await settle()

	await focus_input()
	var retry_text := "写入失败后，这段中文仍可重试。"
	screen.input.text = retry_text
	before = game.snapshot()
	saves.fail_next_write = true
	await key_event(KEY_ENTER)
	await key_event(KEY_ENTER,false)
	await settle()
	check(not host.results.back().success and game.snapshot() == before,"real save failure rolls back dialogue, time and version")
	check(screen.input.text == retry_text and screen.input.editable and not screen.send_button.disabled,"save failure retains the exact input and restores the controls")
	provider.fail_next = true
	await focus_input()
	await key_event(KEY_KP_ENTER)
	await key_event(KEY_KP_ENTER,false)
	await settle()
	check(not host.results.back().success and game.snapshot() == before and screen.input.text == retry_text,"provider failure also preserves the typed question without consuming time")
	call_count = host.calls.size()
	await mouse_click(screen.send_button)
	check(host.calls.size() == call_count+1 and host.results.back().success and game.active_visit().dialogue[-2].text == retry_text and screen.input.text.is_empty(),"real mouse press/release can retry and save the retained Chinese input")
	check(not game.people_generation_settings().enabled and not has_http(root),"keyboard regression uses only fixture responses and isolated local saves")
	print("CHAT KEYBOARD UI: %d checks, %d failures; renderer=%s captures=%d" % [checks,failures,DisplayServer.get_name(),captures])
	await UITeardown.release_audio(main)
	main.queue_free()
	host.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(0 if failures == 0 else 1)

func inspect_render(dimensions: Vector2i) -> void:
	var viewport := Rect2(Vector2.ZERO,Vector2(root.size))
	var hint := find_hint(screen)
	check(hint != null and hint.text.contains("回车发送") and hint.text.contains("Shift+回车换行"),"keyboard instructions describe both send and newline shortcuts / "+str(dimensions))
	check(viewport.encloses(screen.input.get_global_rect()) and viewport.encloses(screen.send_button.get_global_rect()) and screen.input.size.y >= 64 and screen.input.get_theme_font_size("font_size") >= 18,"multiline editor and send button remain readable and inside the viewport / "+str(dimensions))
	check(hint != null and viewport.encloses(hint.get_global_rect()) and hint.get_minimum_size().x <= hint.size.x+1 and screen.transcript.size.y >= 100,"shortcut instructions are uncropped and leave room for the conversation / "+str(dimensions))
	if DisplayServer.get_name() != "headless":
		await create_timer(0.2).timeout
		RenderingServer.force_draw()
		DirAccess.make_dir_recursive_absolute("res://.tools/chat-keyboard-ui")
		check(root.get_texture().get_image().save_png("res://.tools/chat-keyboard-ui/keyboard-"+str(dimensions.x)+".png") == OK,"capture actual keyboard input layout")
		captures += 1

func find_hint(node: Node) -> Label:
	if node is Label and node.text.contains("Shift+回车换行"):
		return node
	for child: Node in node.get_children():
		var hint := find_hint(child)
		if hint != null:
			return hint
	return null

func has_http(node: Node) -> bool:
	return node is HTTPRequest or node.get_children().any(func(child: Node) -> bool: return has_http(child))

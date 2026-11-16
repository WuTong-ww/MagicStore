extends SceneTree
## Authored provider fixtures exercise the real saved question contract and UI.
## No external model requests, credentials or production saves are used.

class FixtureProvider extends RefCounted:
	var followups: Array = []
	func request_reply(request: Dictionary) -> Dictionary:
		var intent: String = str(request.get("topic_id","work"))
		return {"intent":intent,"reply_text":"我想按自己的节奏，把眼前的顾虑慢慢说清楚。","clue_ids":[],"branch_id":"","needs_clarification":false,"error_code":"","followup_questions":followups.duplicate(true)}

class FakeHost extends Node:
	signal released
	var game: Node
	var busy := false
	var hold := false
	var calls: Array = []
	func _init(game_node: Node) -> void:
		game = game_node
	func run_action(kind: String, extra: Dictionary = {}) -> Dictionary:
		if busy:
			return {"success":false,"error_code":"BUSY"}
		busy = true
		calls.append({"type":kind,"extra":extra.duplicate(true),"visit_id":game.active_visit().get("visit_id","")})
		var action := {"type":kind,"action_id":game.make_id("followup_ui"),"expected_version":game.state.state_version}
		action.merge(extra,true)
		if hold:
			await released
		var result: Dictionary = await game.execute_action_async(action)
		busy = false
		return result
	func show_notice(_text: String) -> void:
		pass
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

const MAX_LENGTH_QUESTIONS := [
	{"topic_id":"invitation","text":"这份邀请里你现在最想先确认什么？"},
	{"topic_id":"letter","text":"回信这件事让你最担心的是什么呢？"},
	{"topic_id":"work","text":"修书的时候你通常怎样让自己静心？"}]
var game: Node
var main: Control
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

func direct(kind: String, extra: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("followup_ui_core")}
	action.merge(extra,true)
	var result: Dictionary = game.execute_action(action)
	check(result.success,"direct "+kind+" / "+str(result.get("message","")))
	return result

func callback(button: Button) -> Callable:
	var connections: Array = button.pressed.get_connections()
	return connections[0].callable if not connections.is_empty() else Callable()

func run() -> void:
	game = root.get_node("GameState")
	root.get_node("SaveService").base_dir = "res://.tools/test-followup-ui/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	OS.set_environment("MAGIC_DEV_FIXTURES","0")
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"本轮后续问题界面"})).success,"create isolated UI save")
	check((await main.run_action("start_arrival",{"arrival_id":"arrival_opening_lin"})).success,"start actual queued visitor")
	provider = FixtureProvider.new()
	provider.followups = MAX_LENGTH_QUESTIONS.duplicate(true)
	game.dialogue_provider = provider
	check((await main.run_action("talk",{"text":"最近修复了什么书？","topic_id":"work"})).success,"save authored model-shaped followup package through the actual talk contract")
	await settle()
	var screen: Control = main.screen
	var rows: Array = game.conversation_questions()
	check(rows.size() == 3 and screen.questions.get_child_count() == 3,"consultation shows exactly the current three approved questions")
	for index: int in range(3):
		var button: Button = screen.questions.get_child(index)
		check(button.text == MAX_LENGTH_QUESTIONS[index].text and button.get_meta("topic_id","") == MAX_LENGTH_QUESTIONS[index].topic_id and button.get_meta("generated",false),"button binds current model wording and its actual authorized topic")
		check(button.get_theme_font_size("font_size") >= 18 and button.autowrap_mode != TextServer.AUTOWRAP_OFF and button.text.length() == 16,"sixteen-character boundary question retains readable font size")
	await inspect_render("short-questions")
	var host := FakeHost.new(game)
	root.add_child(host)
	screen.host = host
	var old_button: Button = screen.questions.get_child(0)
	var old_id := old_button.get_instance_id()
	var old_callback := callback(old_button)
	provider.followups[0].text = "这份邀请哪里让你犹豫？"
	check((await main.run_action("talk",{"text":"我们继续慢慢说。","topic_id":"work"})).success,"receive changed wording with the same topic ID")
	await settle()
	var replaced: Button = screen.questions.get_child(0)
	check(replaced.get_instance_id() != old_id and replaced.text == provider.followups[0].text and replaced.get_meta("topic_id") == "invitation","same-ID wording changes rebuild the visible button and bound callback")
	var before: Dictionary = game.snapshot()
	old_callback.call()
	await settle()
	check(host.calls.is_empty() and game.snapshot() == before,"old wording callback is rejected even within the same visit")
	host.hold = true
	var label: String = replaced.text
	replaced.pressed.emit()
	await settle()
	check(host.calls.size() == 1 and host.calls[0].extra == {"text":label,"topic_id":"invitation"},"click submits the current complete label and real topic ID")
	check(screen.send_button.disabled and not screen.input.editable and screen.questions.get_children().all(func(node: Node) -> bool: return node.disabled),"pending request disables question buttons and text submission")
	replaced.pressed.emit()
	await settle()
	check(host.calls.size() == 1,"repeated pressed signal cannot submit a second busy request")
	host.released.emit()
	await settle()
	check(int(game.state.clock_minutes) == int(before.clock_minutes)+5 and game.active_visit().dialogue[-2].text == label,"approved question click reaches the real saved conversation once")
	check(not screen.send_button.disabled and screen.input.editable and screen.questions.get_children().all(func(node: Node) -> bool: return not node.disabled),"question controls recover after completion")
	host.hold = false
	host.busy = true
	await settle()
	var calls_before := host.calls.size()
	screen.questions.get_child(1).pressed.emit()
	check(host.calls.size() == calls_before and screen.questions.get_children().all(func(node: Node) -> bool: return node.disabled),"external host busy state disables and guards every question")
	host.busy = false
	await settle()
	provider.followups[0] = {"topic_id":"birth","text":"愿意提供排盘资料吗？"}
	check((await main.run_action("talk",{"text":"再谈一谈眼前的想法。","topic_id":"work"})).success,"receive a changed topic ID while list length stays the same")
	await settle()
	var changed_topic: Button = screen.questions.get_child(0)
	check(changed_topic.get_meta("topic_id") == "birth" and changed_topic.text == provider.followups[0].text,"same-sized changed-ID list rebinds its button")
	host.calls.clear()
	changed_topic.pressed.emit()
	await settle()
	check(host.calls.size() == 1 and host.calls[0].extra.topic_id == "birth" and host.calls[0].extra.text == provider.followups[0].text,"changed-ID button sends its new topic instead of the previous visitor question")
	var expired_callback := callback(screen.questions.get_child(0))
	var original_visit: String = game.active_visit().visit_id
	var original_screen := screen.get_instance_id()
	direct("end_visit")
	direct("next_day")
	var next_arrival := "arrival_1_0"
	direct("start_arrival",{"arrival_id":next_arrival})
	await settle()
	check(game.active_visit().visit_id != original_visit and main.screen.get_instance_id() == original_screen,"new visit changes core state while the same consultation surface remains")
	host.calls.clear()
	before = game.snapshot()
	expired_callback.call()
	await settle()
	check(host.calls.is_empty() and game.snapshot() == before,"previous-visit callback cannot submit to a new NPC")
	rows = game.conversation_questions()
	check(rows.size() <= 3 and rows.all(func(row: Dictionary) -> bool: return row.enabled) and screen.questions.get_child_count() == rows.size(),"offline new visitor uses only current available local fallbacks")
	print("FOLLOWUP QUESTIONS UI: %d checks, %d failures; renderer=%s captures=%d" % [checks,failures,DisplayServer.get_name(),captures])
	main.queue_free()
	host.queue_free()
	await settle()
	quit(0 if failures == 0 else 1)

func inspect_render(name: String) -> void:
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		var screen: Control = main.screen
		var viewport := Rect2(Vector2.ZERO,Vector2(root.size))
		check(viewport.encloses(screen.get_global_rect()),"consultation fits viewport / "+str(dimensions))
		check(screen.transcript.size.y >= 100 and screen.transcript.get_theme_font_size("normal_font_size") >= 18,"conversation remains readable with short followup questions / "+str(dimensions))
		for button: Button in screen.questions.get_children():
			check(viewport.encloses(button.get_global_rect()) and button.size.y+1 >= button.get_combined_minimum_size().y,"wrapped question fits without cropping / "+str(dimensions))
		if DisplayServer.get_name() != "headless":
			await create_timer(0.2).timeout
			RenderingServer.force_draw()
			DirAccess.make_dir_recursive_absolute("res://.tools/followup-questions-ui")
			check(root.get_texture().get_image().save_png("res://.tools/followup-questions-ui/"+name+"-"+str(dimensions.x)+".png") == OK,"save actual short-question rendering")
			captures += 1

extends SceneTree
## Confirm real Ogg playbacks are gone before their scene can be destroyed.
const Audio = preload("res://scripts/audio/shop_audio.gd")
const MusicFixture = preload("res://tests/fixtures/music_fixture.gd")
## UNRUN MUSIC fixture amendment; retains real existing UI-Ogg shutdown checks.

class ClosingProvider extends RefCounted:
	signal replied
	var tree: SceneTree
	var source: RefCounted
	var finish_reply := false
	var pending := false
	func _init(scene_tree: SceneTree, mock: RefCounted, finish: bool) -> void:
		tree = scene_tree
		source = mock
		finish_reply = finish
	func request_reply(request: Dictionary) -> Dictionary:
		var ready_reply: Dictionary = source.request_reply(request)
		pending = true
		await replied
		pending = false
		return ready_reply if finish_reply else {"reply_text":"","intent":"clarify","clue_ids":[],"needs_clarification":true,"error_code":"CANCELLED"}
	func cancel() -> void:
		if pending:
			tree.process_frame.connect(_acknowledge,CONNECT_ONE_SHOT)
	func _acknowledge() -> void:
		replied.emit()
	func status() -> Dictionary:
		return {"mode":"online"}

var checks := 0
var failures := 0
var action_done := false
var action_result: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("AUDIO LIFECYCLE FAIL: " + label)

func pending(handles: Array[WeakRef]) -> int:
	var count := 0
	for handle: WeakRef in handles:
		if handle.get_ref() != null:
			count += 1
	return count

func run() -> void:
	var config: Dictionary = Audio.load_config()
	var invalid := config.duplicate(true)
	invalid.shutdown_timeout_seconds = 0
	check(not Audio.config_valid(invalid), "shutdown timeout must be a positive configured bound")
	invalid = config.duplicate(true)
	invalid.shutdown_poll_frames = 0.5
	check(not Audio.config_valid(invalid), "shutdown polling cadence must be a configured whole frame count")
	var audio: Node = MusicFixture.new()
	root.add_child(audio)
	var handles: Array[WeakRef] = []
	for index: int in range(audio.ui_players.size()*2):
		audio.play_ui("confirm")
		var voice: AudioStreamPlayer = audio.ui_players[(audio.next_voice+audio.ui_players.size()-1)%audio.ui_players.size()]
		check(voice.has_stream_playback(), "real Ogg voice starts / " + str(index))
		handles.append(weakref(voice.get_stream_playback()))
	audio.transition("front",540)
	check(audio.music_players[0].has_stream_playback(), "synthetic in-memory music fixture starts")
	handles.append(weakref(audio.music_players[0].get_stream_playback()))
	check(pending(handles) > 0, "regression observes live mixer-owned playback handles")
	check(audio.has_method("shutdown_async"), "audio exposes an observable shutdown lifecycle")
	if audio.has_method("shutdown_async"):
		check(await audio.shutdown_async(), "shutdown waits for actual mixer release")
		check(pending(handles) == 0, "active and previously recycled Ogg handles are all released")
		audio.play_ui("confirm")
		check(audio.ui_players.all(func(voice: AudioStreamPlayer) -> bool: return not voice.has_stream_playback()), "shutdown blocks new playback creation")
		check(await audio.shutdown_async(), "repeated shutdown is idempotent")
	else:
		# RED has no new lifecycle API. Keep old cleanup so this bounded test exits.
		audio._exit_tree()
	audio.queue_free()
	await process_frame
	if failures > 0:
		finish()
		return
	var held_audio: Node = Audio.new()
	root.add_child(held_audio)
	held_audio.play_ui("confirm")
	var retained: AudioStreamPlayback = held_audio.ui_players[0].get_stream_playback()
	held_audio.config.shutdown_timeout_seconds = 0.05
	check(not await held_audio.shutdown_async(), "an externally retained playback times out instead of pretending release")
	retained = null
	held_audio.config.shutdown_timeout_seconds = config.shutdown_timeout_seconds
	check(await held_audio.shutdown_async(), "release completes after the external holder actually relinquishes its Ref")
	held_audio.queue_free()
	await process_frame
	var game: Node = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	game.set_people_generation_options(false)
	root.get_node("SaveService").base_dir = "res://.tools/audio-close-saves/" + game.make_id("run")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check((await main.run_action("new_game",{"name":"关闭生命周期回归"})).success, "real main scene starts an action sound")
	check(not auto_accept_quit, "window close uses explicit scene lifecycle")
	check(main.has_method("prepare_close_async"), "production close exposes the same release boundary")
	if main.has_method("prepare_close_async"):
		var main_handles: Array[WeakRef] = main.presentation_audio.playback_handles()
		check(await main.prepare_close_async(), "production close preparation releases actual sounds")
		check(pending(main_handles) == 0, "production close completes only after mixer references vanish")
	main.queue_free()
	await process_frame
	await pending_close_flow(false)
	await pending_close_flow(true)
	await actual_window_close()

func start_pending_action(main: Control) -> void:
	action_done = false
	action_result = await main.run_action("talk",{"text":"修书时怎样让自己静下来？","topic_id":"work"})
	action_done = true

func pending_close_flow(finish_reply: bool) -> void:
	var game: Node = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	game.configure_api("","","")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check((await main.run_action("new_game",{"name":"异步关闭保存边界"})).success,"create actual save for pending close")
	check((await main.run_action("start_visit")).success,"start actual visit before close")
	check(await main.presentation_audio.shutdown_async(),"precondition releases real sounds before testing action completion")
	var provider := ClosingProvider.new(self,game.dialogue_provider,finish_reply)
	game.dialogue_provider = provider
	var before: Dictionary = game.snapshot()
	if finish_reply:
		saves.fail_next_write = true
	start_pending_action(main)
	await process_frame
	check(provider.pending and main.busy and not action_done,"actual async action is pending before close")
	check(await main.prepare_close_async(),"close can complete after pending operation settles")
	check(action_done and not main.busy,"close boundary waits for real run_action completion")
	# Keep a failing RED bounded without destroying an awaited UI callback.
	while not action_done:
		await process_frame
	check(action_result.get("error_code") == ("SAVE_WRITE_FAILED" if finish_reply else "CANCELLED"),"pending close observes cancellation or actual write failure")
	check(game.snapshot() == before,"closing an unsuccessful async action never commits partial state")
	main.queue_free()
	await process_frame

func actual_window_close() -> void:
	var game: Node = root.get_node("GameState")
	game.configure_api("","","")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check((await main.run_action("new_game",{"name":"实际关闭请求"})).success,"native-close fixture creates a real save")
	main.presentation_audio.play_ui("confirm")
	var handles: Array[WeakRef] = main.presentation_audio.playback_handles()
	check(pending(handles) > 0,"native close begins with real outstanding Ogg handles")
	main.tree_exiting.connect(func():
		check(pending(handles) == 0,"actual window close drains playback before the main scene exits")
		finish(),CONNECT_ONE_SHOT)
	var config: Dictionary = Audio.load_config()
	create_timer(float(config.shutdown_timeout_seconds)).timeout.connect(func():
		check(false,"actual window close must finish within its configured failure bound")
		finish())
	root.close_requested.emit()

func finish() -> void:
	print("AUDIO LIFECYCLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

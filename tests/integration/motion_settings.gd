extends SceneTree
## Main's real controls/signals with isolated preferences and a real isolated save.
const Teardown = preload("res://tests/ui_teardown.gd")
const Audio = preload("res://scripts/audio/shop_audio.gd")
var checks := 0
var failures := 0
var game: Node
var saves: Node
var original_wind: Node
var wind: Node
var original_wind_process := false
var original_save_root := ""

class ObservedWind extends "res://scripts/presentation/wind_field.gd":
	var door_calls: Array[String] = []
	func notify_door_event(id: String) -> bool:
		door_calls.append(id)
		return super.notify_door_event(id)

func _initialize() -> void:
	if not FileAccess.file_exists("res://tests/integration/motion_settings.gd.uid"):
		print("MOTION SETTINGS RESOURCE UID: ",ResourceUID.id_to_text(ResourceUID.create_id()))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MOTION SETTINGS FAIL: "+label)

func settle() -> void:
	for frame: int in range(4):
		await process_frame

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	original_save_root = saves.base_dir
	var directory := "res://.tools/art/a6/renderer-settings-fixtures/"+str(game.make_id("run"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var pref_path := directory+"/presentation.cfg"
	var prefs := ConfigFile.new()
	prefs.set_value("audio","music",0.23)
	prefs.set_value("audio","ui",0.47)
	prefs.set_value("motion","reduced_motion",false)
	check(prefs.save(pref_path) == OK,"fixture preferences are stored only under .tools")
	original_wind = root.get_node("WindField")
	original_wind_process = original_wind.is_processing()
	original_wind.set_process(false)
	root.remove_child(original_wind)
	wind = ObservedWind.new()
	wind.name = "WindField"
	wind.settings_path = pref_path
	root.add_child(wind)
	wind.set_process(false)
	saves.base_dir = directory+"/saves"
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var main = load("res://scenes/main.tscn").instantiate()
	var transitions: Array = []
	main.scene_changed.connect(func(previous: String,next: String): transitions.append([previous,next]))
	root.add_child(main)
	main.set_process(false)
	await settle()
	main.save_window.hide()
	check(transitions.is_empty(),"initial Main page establishes a silent scene baseline")
	main.presentation_audio.settings_path = pref_path
	main.presentation_audio.volumes = main.presentation_audio.read_settings()
	main.presentation_audio._apply_volume()
	var created: Dictionary = await main.run_action("new_game",{"name":"动态设置回归"})
	check(created.success,"new_game creates an isolated real save through the public action API")
	check(transitions.is_empty(),"new_game destination is silent for scene_changed")
	var save_id := str(game.player_snapshot().save_id)
	var navigate := main.find_child("Navigate_inventory",true,false) as Button
	check(navigate != null,"production navigation button is present")
	if navigate != null:
		navigate.pressed.emit()
		check(transitions == [["front","inventory"]],"actual navigation emits exactly one scene transition")
		navigate.pressed.emit()
		check(transitions.size() == 1,"same-page navigation does not duplicate scene transition")
	var loaded: Dictionary = await main.run_action("load_game",{"save_id":save_id})
	check(loaded.success and transitions.size() == 1,"load_game uses the isolated real save without replaying a scene transition")
	await check_settings(main,pref_path,directory)
	check_event_bridge(main)
	await check_close(main)
	await Teardown.release_audio(main)
	main.queue_free()
	await settle()
	await check_close_failure()
	root.remove_child(wind)
	wind.queue_free()
	root.add_child(original_wind)
	original_wind.set_process(original_wind_process)
	saves.base_dir = original_save_root
	await settle()
	print("MOTION SETTINGS: %d checks, %d failures" % [checks,failures])
	await Teardown.drain(self)
	quit(1 if failures else 0)

func check_settings(main: Control, pref_path: String, directory: String) -> void:
	var before: Dictionary = game.player_snapshot()
	main.open_network_settings()
	await settle()
	var toggle := main.find_child("ReducedMotionCheck",true,false) as CheckButton
	check(toggle != null and not toggle.button_pressed,"actual settings dialog displays the persisted reduced-motion value")
	if toggle == null:
		return
	toggle.button_pressed = true
	var stored := ConfigFile.new()
	check(stored.load(pref_path) == OK and stored.get_value("motion","reduced_motion",false) == true,"actual CheckButton toggle persists reduced motion")
	check(wind.reduced_motion and is_equal_approx(float(stored.get_value("audio","music")),0.23) and is_equal_approx(float(stored.get_value("audio","ui")),0.47),"motion preference publishes only after save and preserves both audio values")
	var ui_volume := main.find_child("Volume_ui",true,false) as HSlider
	check(ui_volume != null,"actual audio slider shares the preference dialog")
	if ui_volume != null:
		ui_volume.value = 0.31
		stored.load(pref_path)
		check(stored.get_value("motion","reduced_motion",false) == true and is_equal_approx(float(stored.get_value("audio","ui")),0.31),"actual audio slider preserves the newly saved motion section")
	var blocker := FileAccess.open(directory+"/not-a-directory",FileAccess.WRITE)
	blocker.store_string("fixture")
	blocker.close()
	wind.settings_path = directory+"/not-a-directory/preferences.cfg"
	toggle.button_pressed = false
	check(toggle.button_pressed and wind.reduced_motion,"failed settings write restores both actual control and Wind memory")
	check(main.notice.text == str(main.motion_settings.labels.save_failed),"failed settings write uses the configured Chinese notice")
	check(game.player_snapshot() == before,"success/failure preference edits do not change GameState or version")
	wind.settings_path = pref_path
	stored.load(pref_path)
	check(stored.get_value("motion","reduced_motion",false) == true and is_equal_approx(float(stored.get_value("audio","ui")),0.31),"failed preference edit leaves the previously committed file intact")
	toggle.get_window().hide()

func check_event_bridge(main: Control) -> void:
	var snapshot: Dictionary = game.player_snapshot()
	# Producer sanitization/transactions are tested separately. This is the real
	# already-sanitized GameState signal -> Main -> original Wind implementation bridge.
	var event := {"save_id":snapshot.save_id,"state_version":snapshot.state_version,
		"arrival_id":"bridge-fixture-guest","kind":"guest_entered","at":snapshot.clock_minutes,"sequence":0}
	game.presentation_events_committed.emit([event])
	check(wind.door_calls.size() == 1 and wind.get("_door_events").size() == 1,"real GameState presentation signal reaches original Wind notify once")
	var door_started: float = wind.get("_door_started")
	wind.time_seconds += 0.5
	game.presentation_events_committed.emit([event.duplicate(true)])
	check(wind.door_calls.size() == 1 and float(wind.get("_door_started")) == door_started,"replayed signal is filtered by Main before notifying or restarting Wind")
	check(game.player_snapshot() == snapshot,"presentation signal routing does not change the committed game snapshot")

func play_fixture_chime(main: Control) -> Dictionary:
	var motion: Node = main._current_motion()
	var settings: Dictionary = main.motion_settings.duplicate(true)
	settings.events.chime_audio = "res://assets/audio/ui/notify.ogg"
	var artwork: Control = main.screen.scene_visual
	motion.bind(artwork,artwork.config.scenes.S02,settings)
	motion.set_active(true)
	motion.set_process(true)
	motion.on_presentation_events([{"save_id":"close-fixture","state_version":1,"sequence":0,
		"arrival_id":"guest-close","kind":"guest_entered"}])
	var player := motion.find_child("WindChimeAudio",true,false) as AudioStreamPlayer
	check(player != null and player.playing and player.has_stream_playback(),"close fixture starts a real optional chime without claiming it as production audio")
	return {"motion":motion,"player":player}

func check_close(main: Control) -> void:
	check(await main.presentation_audio.shutdown_async(),"close fixture drains UI/Music first")
	check(main.presentation_audio.ui_players.all(func(p: AudioStreamPlayer) -> bool: return not p.has_stream_playback()) and main.presentation_audio.music_players.all(func(p: AudioStreamPlayer) -> bool: return not p.has_stream_playback()),"immediate-close precondition has no UI or Music mixer voice")
	var fixture := play_fixture_chime(main)
	var motion: Node = fixture.motion
	var player: AudioStreamPlayer = fixture.player
	check(motion.has_method("shutdown_async"),"SceneMotion exposes real weakref-draining shutdown_async")
	var handle: WeakRef = weakref(player.get_stream_playback()) if player != null and player.has_stream_playback() else null
	check(await main.prepare_close_async(),"actual Main immediate close completes successfully")
	check(handle != null and handle.get_ref() == null,"Main close returns only after the chime mixer handle is actually released")
	check(not motion.is_processing(),"Main closing stops component processing before destroying its scene")
	# RED cleanup must release the existing voice even before the new Main hook exists.
	if player != null and is_instance_valid(player):
		player.stop()
		player.stream = null
	var deadline := Time.get_ticks_usec()+int(float(Audio.load_config().shutdown_timeout_seconds)*1000000.0)
	while handle != null and handle.get_ref() != null and Time.get_ticks_usec() < deadline:
		await process_frame

func check_close_failure() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await settle()
	main.save_window.hide()
	main.show_screen("front",true)
	await main.presentation_audio.shutdown_async()
	var fixture := play_fixture_chime(main)
	var motion: Node = fixture.motion
	var player: AudioStreamPlayer = fixture.player
	if motion.has_method("shutdown_async") and player != null and player.has_stream_playback():
		var retained: AudioStreamPlayback = player.get_stream_playback()
		check(not await main.prepare_close_async(),"externally retained chime playback makes actual Main close fail within the configured bound")
		check(not main._closing and main.notice.text == str(main.presentation_audio.config.labels.shutdown_failed),"Main close failure restores closing flag and uses existing audio failure text")
		retained = null
		check(await main.prepare_close_async(),"retry close succeeds after the real playback holder releases it")
	await Teardown.release_audio(main)
	main.queue_free()
	await settle()

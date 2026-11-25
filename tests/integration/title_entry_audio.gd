extends SceneTree
const Audio = preload("res://scripts/audio/shop_audio.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TITLE ENTRY AUDIO FAIL: "+label)

func run() -> void:
	var config: Dictionary = Audio.load_config()
	check(not config.is_empty(),"current audio configuration validates")
	if config.is_empty():
		finish()
		return
	check(config.sounds.entry_chime==config.sounds.notify,"entry cue reuses the existing licensed bell resource")
	check(FileAccess.get_sha256(config.sounds.entry_chime)=="d21d0f0b782445db579d11e2506b24cd1ac9d664ee33aeaf807761aa7b6fd710","source bytes remain the already registered Kenney bong")
	var legacy: Dictionary = config.duplicate(true)
	legacy.sounds.erase("entry_chime")
	check(Audio.config_valid(legacy),"existing six-cue presentation configurations remain valid")
	for value: Variant in [true,"file:///outside.ogg","res://assets/audio/not-an-ogg.wav"]:
		var bad: Dictionary = config.duplicate(true)
		bad.sounds.entry_chime = value
		check(not Audio.config_valid(bad),"new optional cue still rejects invalid resource paths")
	var game: Node = root.get_node("GameState")
	var before: Dictionary = game.snapshot()
	var audio: Node = Audio.new()
	audio.settings_path = "res://.tools/r3-title/entry-audio/"+game.make_id("settings")+".cfg"
	root.add_child(audio)
	await process_frame
	var voice_index: int = audio.next_voice
	audio.play_ui("entry_chime")
	check(audio.next_voice==(voice_index+1)%audio.ui_players.size(),"one entry cue starts exactly one real UI voice")
	var voice: AudioStreamPlayer = audio.ui_players[voice_index]
	check(voice.stream is AudioStreamOggVorbis and voice.has_stream_playback(),"actual registered Ogg playback starts")
	var handle: WeakRef = weakref(voice.get_stream_playback())
	check(await audio.shutdown_async(),"normal shutdown waits for mixer release")
	check(handle.get_ref()==null,"the actual entry playback is released")
	check(game.snapshot()==before,"presentation cue changes no game save or narrative state")
	audio.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("TITLE ENTRY AUDIO: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

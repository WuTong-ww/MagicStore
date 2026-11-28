extends SceneTree
const Audio = preload("res://scripts/audio/shop_audio.gd")
const Catalog = preload("res://scripts/audio/ui_sound_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("R4 UI AUDIO FAIL: "+description)

func run() -> void:
	var data := Audio.load_config()
	check(not data.is_empty() and Catalog.valid(data),"real sound catalog validates")
	if data.is_empty():
		finish()
		return
	check(data.defaults.ui == 0.45 and data.ui_policy.pitch_min == 0.96 and data.ui_policy.pitch_max == 1.04,"requested default volume and pitch range")
	check(data.sound_catalog.size() == 33,"eleven purposes each have three candidates")
	for key: String in Catalog.KEYS:
		var choices := Catalog.candidates(data,key)
		check(choices.size() == 3 and choices.front() == data.sounds[key],"main plus two distinct audition candidates / "+key)
		var changed := data.duplicate(true)
		changed.sounds[key] = choices[1]
		check(Audio.config_valid(changed) and Catalog.candidates(changed,key).size() == 3,"one-line main choice changes without losing the original / "+key)
		for path: String in choices:
			check(ResourceLoader.exists(path),"candidate imported / "+path)
			if not ResourceLoader.exists(path): continue
			var stream := load(path) as AudioStream
			check(stream != null and stream.get_length() >= 0.06 and stream.get_length() <= 0.35,"real decoder confirms short duration / "+path)
			check(FileAccess.get_sha256(path) == data.sound_catalog[path].sha256,"registered bytes match / "+path)
	for field: String in ["pitch_min","pitch_max"]:
		var bad := data.duplicate(true)
		bad.ui_policy[field] = NAN
		check(not Audio.config_valid(bad),"nonfinite pitch refused")
	var bad := data.duplicate(true)
	bad.sound_catalog[data.sounds.click].metrics.onset_peak_ratio = 0.9
	check(not Audio.config_valid(bad),"sharp attack metadata refused")
	bad = data.duplicate(true)
	bad.alternatives.click = [data.sounds.click]
	check(not Audio.config_valid(bad),"missing comparison candidate refused")
	bad = data.duplicate(true)
	bad.sound_catalog[data.sounds.click].candidate = 0.5
	check(not Audio.config_valid(bad),"fractional candidate ID refused while JSON integer-valued floats remain valid")
	bad = data.duplicate(true)
	bad.sounds.click = "res://assets/audio/ui/../outside.ogg"
	check(not Audio.config_valid(bad),"unsafe sound mapping refused")
	var audio: Node = Audio.new()
	audio.settings_path = "res://.tools/r4-b/test-settings/"+str(Time.get_ticks_usec())+".cfg"
	root.add_child(audio)
	await process_frame
	var snapshot: Dictionary = root.get_node("GameState").snapshot()
	var pitches: Array = []
	for index: int in range(24):
		var voice: int = audio.next_voice
		audio.play_ui("unknown_test_key")
		var player: AudioStreamPlayer = audio.ui_players[voice]
		check(player.stream != null and player.stream.resource_path == data.sounds.click,"unknown key falls back to click")
		check(player.pitch_scale >= 0.96 and player.pitch_scale <= 1.04,"runtime pitch stays within requested range")
		pitches.append(player.pitch_scale)
	check(pitches.any(func(pitch: float) -> bool: return not is_equal_approx(pitch,pitches.front())),"independent audio randomizer varies repeated sounds")
	check(not audio.play_preview("res://not_registered.ogg"),"preview cannot load arbitrary files")
	check(audio.play_preview(data.alternatives.coin[0]),"preview can play a registered alternative")
	var preview_voice: int = posmod(audio.next_voice-1,audio.ui_players.size())
	check(is_equal_approx(audio.ui_players[preview_voice].pitch_scale,1.0),"audition comparison uses fixed pitch")
	audio.play_ui("cancel")
	var cancel_voice: int = posmod(audio.next_voice-1,audio.ui_players.size())
	check(audio.ui_players[cancel_voice].volume_db < 0,"cancel is quieter than a normal click")
	check(root.get_node("GameState").snapshot() == snapshot,"UI sounds never alter game state")
	check(await audio.shutdown_async(),"real mixer handles release on shutdown")
	check(not audio.play_preview(data.sounds.click),"shutdown prevents late preview playback")
	audio.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("R4 UI AUDIO: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

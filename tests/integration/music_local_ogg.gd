extends SceneTree
## Explicit native local opt-in only; separate from the public and synthetic tests.
## Run after local q6 encoding receipts exist, never as a public-build test.
const Audio = preload("res://scripts/audio/shop_audio.gd")
const Catalog = preload("res://scripts/audio/music_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MUSIC LOCAL OGG FAIL: "+label)

func pending(handles: Array[WeakRef]) -> int:
	var count := 0
	for handle: WeakRef in handles:
		if handle.get_ref() != null:
			count += 1
	return count

func run() -> void:
	if "--music-local-validation" not in OS.get_cmdline_user_args() or OS.has_feature("web") or OS.has_feature("webpublic"):
		printerr("Local music validation needs explicit native-only --music-local-validation.")
		quit(2)
		return
	var catalog := Catalog.load_data()
	check(not catalog.is_empty(),"catalog is valid")
	if catalog.is_empty():
		finish()
		return
	for slot: String in Catalog.SLOT_IDS:
		var track := Catalog.track_for_slot(slot,catalog)
		check(ResourceLoader.exists(str(track.runtime_path),"AudioStream"),"selected encoded runtime exists / "+slot)
	if failures > 0:
		finish()
		return
	var audio: Node = Audio.new()
	audio.settings_path = "res://.tools/music-local-validation.cfg"
	root.add_child(audio)
	for route: Dictionary in [
		{"page":"title","clock":540,"context":{}},
		{"page":"front","clock":540,"context":{}},
		{"page":"front","clock":1080,"context":{}},
		{"page":"consultation","clock":540,"context":{"case_active":true}},
		{"page":"front","clock":540,"context":{"ending_visible":true}},
		{"page":"title","clock":540,"context":{}}
	]:
		audio.transition(route.page,int(route.clock),route.context)
		await process_frame
		check(audio.active_player>=0,"selected local track starts / "+audio.current_music)
		if audio.active_player>=0:
			var player: AudioStreamPlayer = audio.music_players[audio.active_player]
			check(player.stream is AudioStreamOggVorbis and player.stream.loop and player.has_stream_playback(),"real local Vorbis playback is loop-enabled")
	await create_timer(float(catalog.crossfade_seconds)+0.1).timeout
	check(audio.music_players.filter(func(player:AudioStreamPlayer)->bool:return player.playing).size()==1,"rapid real local switches settle to one voice")
	var handles: Array[WeakRef] = audio.playback_handles()
	check(await audio.shutdown_async(),"real local Vorbis release completes")
	check(pending(handles)==0,"all current and recycled local Vorbis weak handles drain")
	audio.queue_free()
	audio = null
	await process_frame
	finish()

func finish() -> void:
	print("MUSIC LOCAL OGG: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

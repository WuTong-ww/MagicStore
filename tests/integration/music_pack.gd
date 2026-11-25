extends SceneTree
## External probe for an actual exported --main-pack; not a source-tree test.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MUSIC PACK FAIL: "+label)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["--expect-music","--expect-silent"]:
		printerr("Use one explicit exported-pack expectation.")
		quit(2)
		return
	var with_music := args[0] == "--expect-music"
	check(not FileAccess.file_exists("res://tests/integration/music_pack.gd"),"probe is external and test sources are absent from the export")
	for path: String in ["res://.runtime","res://.git","res://Cozy Tunes","res://build"]:
		check(not DirAccess.dir_exists_absolute(path),"export excludes local/private directory / "+path)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio.json"))
	check(data is Dictionary and data.get("slots",{}).size() == 5,"actual exported catalog has five scene slots")
	if data is Dictionary:
		for slot: String in data.get("slots",{}):
			var selected: String = str(data.slots[slot].track_id)
			var tracks: Array = data.get("tracks",[]).filter(func(row:Dictionary)->bool:return row.id == selected)
			check(tracks.size()==1,"exported selection resolves uniquely / "+slot)
			if tracks.size()==1:
				var path: String = tracks[0].runtime_path
				check(ResourceLoader.exists(path,"AudioStream") == with_music,"actual packed music availability / "+slot)
				if with_music:
					var stream: Resource = load(path)
					check(stream is AudioStreamOggVorbis and stream.get_length()>0,"packed local Vorbis loads / "+slot)
	if not with_music:
		check(not DirAccess.dir_exists_absolute("res://assets/audio/music"),"silent pack excludes the entire music directory")
	var audio: Node = load("res://scripts/audio/shop_audio.gd").new()
	audio.settings_path = "res://.tools/pack-probe-read-only.cfg"
	root.add_child(audio)
	await process_frame
	audio.transition("title",540)
	var deadline := Time.get_ticks_usec()+int(float(audio.config.shutdown_timeout_seconds)*1000000.0)
	while audio.fade != null and Time.get_ticks_usec()<deadline:
		await process_frame
	check(audio.fade == null,"actual packed player completes its configured fade")
	check(audio.current_music == "opening","actual packed player routes opening")
	check((audio.active_player>=0) == with_music,"actual packed playback follows music availability")
	if not with_music:
		check(audio.music_players.all(func(player:AudioStreamPlayer)->bool:return not player.playing and player.stream==null),"actual silent pack keeps both voices empty")
	check(await audio.shutdown_async(),"actual packed mixer handles release before exit")
	audio.queue_free()
	await process_frame
	print("MUSIC PACK: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

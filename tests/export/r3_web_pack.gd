extends SceneTree
const Public = preload("res://scripts/core/public_web.gd")
const Art = preload("res://scripts/shop/scene_visual.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const Fonts = preload("res://scripts/ui/font_policy.gd")
const Music = preload("res://scripts/audio/music_catalog.gd")
const Audio = preload("res://scripts/audio/shop_audio.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("R3 WEB PACK FAIL: "+label)
func run() -> void:
	var expect_music := "--expect-music" in OS.get_cmdline_user_args()
	var game: Node = root.get_node("GameState")
	check(Public.active() and not Public.load_config().is_empty(),"public feature and validated copy")
	check(game.content_error.is_empty(),"full runtime content initializes in the actual PCK")
	game.configure_network("https://example.com/unused","test_value")
	check(game.provider_status().mode == "offline" and game.connection_settings().url.is_empty(),"public build cannot enable gateway")
	game.configure_api("https://example.com/unused","test_model","test_value")
	check(game.provider_status().mode == "offline" and not game.connection_settings().key_set,"public build discards supplied API credentials")
	check(not Art.load_config().is_empty() and not Appearance.load_config().is_empty(),"dynamic scene and portrait references survive pruning")
	check(Fonts.composite() != null,"both bundled text fonts load")
	var bundle := preload("res://scripts/learning/learning_store.gd").bundle(game._divination.data)
	check(not bundle.is_empty() and bundle.definitions.size()==27,"all practice cases ship in public package")
	check(not ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"),"unused old font excluded")
	check(not FileAccess.file_exists("res://assets/ART_ASSET_MANIFEST.json"),"engineering manifest excluded")
	check(not FileAccess.file_exists("res://data/web_audio_build.json"),"private source provenance excluded from runtime")
	check(OS.has_feature("withmusic")==expect_music,"actual export feature matches expected music mode")
	var catalog := Music.load_data()
	check(not catalog.is_empty(),"packed music catalog validates")
	var paths := {}
	for slot: String in Music.SLOT_IDS:
		var track := Music.track_for_slot(slot,catalog)
		paths[str(track.runtime_path)] = true
	for path: String in paths:
		check(ResourceLoader.exists(path,"AudioStream")==expect_music,"selected packed audio availability / "+path)
		if expect_music:
			var stream: AudioStream = load(path)
			check(stream != null and stream.get_length()>0,"real Ogg stream decodes / "+path)
	if expect_music:
		var audio := Audio.new()
		audio.settings_path = "user://web-pack-audio-test.cfg"
		root.add_child(audio)
		audio.transition("front",540)
		check(audio.active_player>=0 and audio.music_players[audio.active_player].playing,"actual pack starts selected daytime music")
		var voice: int = audio.active_player
		var position: AudioStream = audio.music_players[voice].stream
		check(position is AudioStreamOggVorbis and position.loop,"packed BGM enables continuous looping")
		audio.transition("consultation",540,{"case_active":true})
		check(audio.active_player==voice and audio.music_players[voice].stream==position,"Sheep continues into reception without restarting")
		check(await audio.shutdown_async(),"packed music releases playback handles")
		audio.free()
	print("R3 WEB PACK: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

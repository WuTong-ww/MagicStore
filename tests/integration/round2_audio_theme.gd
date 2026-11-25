extends SceneTree
## UNRUN MUSIC fixture amendment.
const MusicFixture = preload("res://tests/fixtures/music_fixture.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("A3R AUDIO/THEME FAIL: " + label)

func run() -> void:
	check(FileAccess.file_exists("res://scripts/audio/shop_audio.gd"), "audio controller exists")
	check(FileAccess.file_exists("res://themes/paper.tres") and FileAccess.file_exists("res://themes/chrome.tres"), "separate paper and chrome themes exist")
	if failures > 0:
		finish()
		return
	var script: Script = load("res://scripts/audio/shop_audio.gd")
	var config: Dictionary = script.load_config()
	check(script.config_valid(config), "audio JSON validates")
	var bad := config.duplicate(true)
	bad.crossfade_seconds = -1
	check(not script.config_valid(bad), "negative fade rejected")
	bad = config.duplicate(true)
	bad.defaults.music = 3
	check(not script.config_valid(bad), "invalid volume rejected")
	check(script.music_key(config, "front", 540) == "day", "day music follows clock")
	check(script.music_key(config, "front", 1080) == "night", "night music follows clock")
	check(script.music_key(config, "consultation", 540) == "consultation", "consultation overrides clock")
	var audio: Node = MusicFixture.new()
	audio.settings_path = "res://.tools/a3r-audio-settings-" + str(Time.get_ticks_usec()) + ".cfg"
	root.add_child(audio)
	await process_frame
	check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("UI") >= 0, "music and UI use separate buses")
	var game: Node = root.get_node("GameState")
	var original: Dictionary = game.snapshot()
	check(audio.set_volume("music", 0.25) and audio.set_volume("ui", 0.75), "volume settings save successfully")
	check(game.snapshot() == original, "audio preferences never alter game save")
	check(not audio.set_volume("music", -1.0), "invalid volume update rejected")
	var reloaded: Dictionary = audio.read_settings()
	check(is_equal_approx(reloaded.music, 0.25) and is_equal_approx(reloaded.ui, 0.75), "volume persists in settings file")
	for key: String in config.sounds:
		check(ResourceLoader.exists(config.sounds[key]), "sound resource available / " + key)
		audio.play_ui(key)
	audio.transition("front", 540)
	audio.transition("front", 1080)
	check(audio.current_music == "night", "music transition records desired period even when assets unavailable")
	# Runtime music fixture is synthetic; no Cozy Tunes file is needed.
	audio.current_music = ""
	audio.transition("front", 540)
	check(audio.music_players[0].playing, "available day stream starts playing")
	audio.transition("consultation", 540, {"case_active":true})
	check(audio.music_players[0].playing and audio.music_players[1].playing, "crossfade overlaps old and new streams")
	await create_timer(float(audio.music_config.crossfade_seconds) + 0.1).timeout
	check(not audio.music_players[0].playing and audio.music_players[1].playing, "crossfade stops old stream after fade")
	var paper: Theme = load("res://themes/paper.tres")
	var chrome: Theme = load("res://themes/chrome.tres")
	check(paper.get_color("font_color", "Label") == Color("3b2a1e"), "paper uses ink text")
	var queue := ItemList.new()
	queue.theme = paper
	root.add_child(queue)
	queue.add_item("候客与预约")
	queue.select(0)
	check(queue.get_theme_color("font_selected_color").is_equal_approx(Color("3b2a1e")), "selected paper queue keeps readable ink text")
	queue.queue_free()
	check(paper.get_stylebox("panel", "PanelContainer").bg_color == Color("f3e9d6"), "paper uses parchment background")
	check(chrome.get_stylebox("panel", "PanelContainer").bg_color.is_equal_approx(Color(31.0/255.0,58.0/255.0,61.0/255.0,0.8)), "chrome uses translucent night teal")
	check(paper.get_font("normal_font", "Dialogue").resource_path.ends_with("LXGWWenKai-Regular.ttf"), "dialogue uses WenKai")
	var button_font: Font = paper.get_font("font", "Button")
	check(button_font is FontVariation and button_font.base_font.resource_path.ends_with("NotoSansSC.ttf") and button_font.variation_opentype.get(2003265652) == 400.0, "buttons use Noto Sans at regular weight")
	check(await audio.shutdown_async(), "audio releases mixer-owned handles before scene teardown")
	audio.queue_free()
	await process_frame
	finish()

func finish() -> void:
	print("A3R AUDIO/THEME: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

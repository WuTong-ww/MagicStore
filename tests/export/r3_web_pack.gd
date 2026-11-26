extends SceneTree
const Public = preload("res://scripts/core/public_web.gd")
const Art = preload("res://scripts/shop/scene_visual.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const Fonts = preload("res://scripts/ui/font_policy.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("R3 WEB PACK FAIL: "+label)
func run() -> void:
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
	for path: String in ["res://assets/audio/music/day.ogg","res://assets/audio/music/night.ogg","res://assets/audio/music/title.ogg"]:
		check(not ResourceLoader.exists(path),"public background music absent")
	print("R3 WEB PACK: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

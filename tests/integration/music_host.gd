extends SceneTree
## Formal Main integration target. Synthetic music voices; genuine saved ending.
## Direct callbacks test UI routing; they do not claim pointer or listening coverage.
const Fixture = preload("res://tests/fixtures/music_fixture.gd")
const Catalog = preload("res://scripts/audio/music_catalog.gd")
const Teardown = preload("res://tests/ui_teardown.gd")
const ENDING_FIXTURE := "res://tests/fixtures/music_ending_v15.json"
const ENDING_SHA := "7be512a2760a6275c92ea93cc1881412a2e185056040e8605b3817044811a6c1"
const ENDING_ID := "save_new_9e93d477f7652767fc41e5464fd80702a0b1eaeac265c6e041593021fafcd835"
var checks := 0
var failures := 0
var game: Node
var saves: Node
var main: Control
var base_dir := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MUSIC HOST FAIL: "+label)

func settle() -> void:
	for index: int in range(4): await process_frame

func has_property(node: Object, key: String) -> bool:
	return node.get_property_list().any(func(row: Dictionary) -> bool: return row.name == key)

func attach_fixture() -> void:
	check(await main.presentation_audio.shutdown_async(),"release previous real presentation controller")
	main.presentation_audio.queue_free()
	main.presentation_audio = Fixture.new()
	main.presentation_audio.settings_path = base_dir.path_join("presentation.cfg")
	main.add_child(main.presentation_audio)
	await settle()
	main._refresh_music()
	await settle()

func clock_slot() -> String:
	var clock: int = int(game.player_snapshot().get("clock_minutes",0))
	return Catalog.key_for("front",clock,main.presentation_audio.music_config,{})

func close_main() -> void:
	if not is_instance_valid(main): return
	check(await main.prepare_close_async(),"real Main releases title, motion and audio resources")
	main.queue_free()
	await Teardown.drain(self)
	main = null

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	base_dir = "res://.tools/r3-music/host/"+game.make_id("run")
	saves.base_dir = base_dir
	root.gui_embed_subwindows = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# This target exercises explicit actions, without running background pumps.
	main.set_process(false)
	await settle()
	check(main.has_method("_refresh_music"),"real Main installs public music routing")
	check(has_property(main,"title_visible"),"real Main exposes actual TITLE visibility")
	check(main.has_method("_music_ending_visible"),"real Main exposes actual ending visibility")
	if failures:
		await close_main()
		finish()
		return
	await attach_fixture()
	check(main.title_visible and main.title_control.art_root.is_visible_in_tree(),"startup title flag follows the actual artwork")
	check(main.presentation_audio.current_music == "opening","visible TITLE selects opening")
	main.open_saves()
	await settle()
	check(main.save_window.visible and main.title_visible and main.presentation_audio.current_music == "opening","save-book modal leaves visible TITLE music intact")
	main.save_window.hide()
	var before: Dictionary = game.snapshot()
	var cues: int = main.title_entry_cue_count
	saves.fail_next_write = true
	await main._ui_create_game("音乐宿主测试")
	await settle()
	var intent: Dictionary = main.ui_new_game_intent()
	check(not intent.is_empty() and game.snapshot() == before,"failed UI creation retains its stable intent without publishing a save")
	check(main.title_visible and not main.title_control.awaiting_note and main.title_entry_cue_count == cues,"failed save cannot show opening notes or emit the entry cue")
	check(main.presentation_audio.current_music == "opening","failed save retains actual TITLE route")
	await main._ui_create_game("音乐重试名称")
	await settle()
	check(not game.player_snapshot().is_empty() and game.snapshot().processed_actions.has(str(intent.get("id",""))),"same UI creation intent commits through real GameState")
	check(main.title_control.visible and main.title_control.awaiting_note and main.title_control.notes_panel.is_visible_in_tree(),"saved opening notebook is actually visible inside the Title host")
	check(not main.title_visible and not main.title_control.art_root.is_visible_in_tree() and main._title_blocking,"opening notebook does not pretend the hidden artwork is still TITLE")
	check(main.presentation_audio.current_music == clock_slot(),"opening notebook selects committed in-store clock music")
	check(main.title_entry_cue_count == cues+1,"successful retry emits exactly one independent entry cue")
	var first: Array = game.story_view().notes.filter(func(row: Dictionary) -> bool: return row.get("page_number") == 1 and row.get("unlocked",false))
	check(first.size() == 1 and main.title_control.opening_notes.body.text == first[0].text,"opening notebook reads the newly committed public page")
	main.title_control.opening_notes.close_button.pressed.emit()
	await settle()
	check(not main.title_control.visible and not main._title_blocking and main.presentation_audio.current_music == clock_slot(),"closing opening notes leaves real in-store music and releases the modal")
	if failures:
		await close_main()
		finish()
		return
	await check_saved_ending()
	await check_missing_music()
	await close_main()
	await check_fallback()
	await close_main()
	finish()

func check_saved_ending() -> void:
	check(FileAccess.file_exists(ENDING_FIXTURE) and FileAccess.get_sha256(ENDING_FIXTURE) == ENDING_SHA,"genuine schema15 best-ending envelope retains its exact source bytes")
	if failures: return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
	var path: String = saves._path(ENDING_ID)
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(ENDING_FIXTURE),ProjectSettings.globalize_path(path)) == OK,"copy the real ending envelope into the isolated save directory")
	var read: Dictionary = saves.read_save(ENDING_ID)
	check(read.get("success",false) and read.get("state",{}).get("schema_version") == 15,"normal validator accepts the genuine schema15 ending")
	if failures: return
	check((await main.run_action("load_game",{"save_id":ENDING_ID})).get("success",false),"load the actual completed story through GameState")
	await settle()
	var public: Dictionary = game.story_view()
	var before_read: Dictionary = game.snapshot()
	check(public.get("ending",{}).get("has_ending",false) and public.ending.get("status") == "complete","normal public getter exposes the real completed ending")
	check(not main._music_ending_visible() and main.presentation_audio.current_music == clock_slot(),"historical completion alone leaves clock music")
	check(main.open_story_notes(),"open the real saved notebook archive")
	await settle()
	var notes: Control = main.people_panel.story_notes
	var ending: RichTextLabel = notes.ending_label
	check(notes.is_visible_in_tree() and ending.is_visible_in_tree() and not ending.text.is_empty(),"ending text is actually rendered in the visible archive tab")
	check(main._music_ending_visible() and main.presentation_audio.current_music == "ending","actual visible completed ending selects ending music")
	var tabs: TabContainer = main.people_panel._people_pages
	tabs.current_tab = 0
	await settle()
	check(not notes.is_visible_in_tree() and not main._music_ending_visible() and main.presentation_audio.current_music == clock_slot(),"changing the actual archive tab returns to clock music")
	check(main.open_story_notes(),"reopen the saved ending tab")
	await settle()
	check(main.presentation_audio.current_music == "ending","reopening the rendered ending restores ending music")
	main.people_window.hide()
	await settle()
	check(not main._music_ending_visible() and main.presentation_audio.current_music == clock_slot(),"hiding the archive window returns to clock music")
	check(game.snapshot().story == before_read.story and game.snapshot().player == before_read.player,"reading updates only presentation receipts, preserving story and player state")
	check(FileAccess.get_sha256(path+".bak") == ENDING_SHA and saves.read_save(ENDING_ID).get("success",false),"first saved read receipt retains the exact legacy envelope as a recoverable backup")

func check_missing_music() -> void:
	var audio: Node = main.presentation_audio
	for row: Dictionary in audio.music_config.tracks:
		audio.missing_paths.append(str(row.runtime_path))
	audio._stop_music()
	main._refresh_music()
	await settle()
	check(audio.current_music == clock_slot() and audio.active_player == -1,"missing catalog-selected music is a normal quiet route")
	check(audio.music_players.all(func(player: AudioStreamPlayer) -> bool: return not player.playing and player.stream == null),"all missing songs leave both voices quiet without borrowing a fallback")
	check(main.presentation_audio == audio and not main._closing and not main.title_visible,"missing songs do not replace the controller or reopen TITLE")

func check_fallback() -> void:
	var before: Dictionary = game.snapshot()
	main = load("res://scenes/main.tscn").instantiate()
	main.title_config_path = base_dir.path_join("absent-title.json")
	root.add_child(main)
	main.set_process(false)
	await settle()
	await attach_fixture()
	check(is_instance_valid(main.title_error_panel) and not main.title_error_panel.is_visible_in_tree() and not main.title_visible and main.presentation_audio.current_music == clock_slot(),"existing saved game legitimately dismisses the startup fallback and keeps clock music")
	# This is actual UI visibility coverage with an existing save. Empty startup
	# fallback behavior remains covered by the dedicated TITLE targets.
	main.title_error_panel.show()
	main.set_title_blocking(true)
	await settle()
	check(is_instance_valid(main.title_error_panel) and main.title_error_panel.is_visible_in_tree() and main.title_visible,"actual invalid-config fallback is visibly TITLE")
	check(main.presentation_audio.current_music == "opening","visible Chinese fallback selects opening")
	main.title_error_panel.hide()
	await settle()
	check(not main.title_visible and main._title_blocking and main.presentation_audio.current_music == clock_slot(),"hidden fallback returns to clock music even while the modal guard remains")
	main.title_error_panel.show()
	await settle()
	check(main.title_visible and main.presentation_audio.current_music == "opening","showing the fallback reroutes without a saved action")
	check(game.snapshot() == before,"fallback visibility never changes saved state")

func finish() -> void:
	print("MUSIC HOST: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

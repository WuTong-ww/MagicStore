extends "res://tests/integration/title_ui.gd"
## UNRUN. Reuses the exact acknowledged input driver, not a second loose helper.
var operations_start_frame := 0
var movie_command_id := ""

func hold() -> void:
	await create_timer(float(config.qa.movie.hold_seconds)).timeout

func run() -> void:
	if not await setup():
		await finish()
		return
	check(OS.has_feature("movie") and DisplayServer.get_name() != "headless","actual Compatibility Movie Maker session")
	check(Config.missing_resources(config).is_empty(),"final generated dusk/real leaf/window/chime resources are ready")
	check(main.presentation_audio.config.get("sounds",{}).get(config.assets.chime_key) == config.assets.entry_chime,"entry audio source is actually wired")
	if failures:
		await finish()
		return
	root.size = Vector2i(config.qa.movie.width,config.qa.movie.height)
	root.content_scale_size = root.size
	await settle()
	operations_start_frame = Engine.get_frames_drawn()
	print("TITLE MOVIE GEOMETRY ",JSON.stringify({"root":str(root.size),"scale":str(root.content_scale_size),"native":str(DisplayServer.window_get_size(root.get_window_id())),"viewport":str(root.get_visible_rect()),"final_transform":str(root.get_final_transform()),"source_sha256":FileAccess.get_sha256("res://tests/integration/title_movie.gd")}))
	var title: Control = main.title_control
	await clear_highlights()
	check(is_zero_approx(title.window_glow.modulate.a),"real dusk window starts unlit")
	await hold()
	await hover(title.buttons["new"])
	check(title.window_glow.modulate.a > 0,"real hover lights only the independent window layer")
	await hold()
	await click(title.buttons["settings"])
	if input_failed or failures:
		await finish()
		return
	var api: Node = main.find_child("ApiUrl",true,false)
	var dialog := api.get_window() as ConfirmationDialog if api != null else null
	check(dialog != null and dialog.visible,"true click opens the existing settings window")
	if dialog == null:
		await finish()
		return
	await hold()
	await click(dialog.get_cancel_button())
	await click(title.buttons["new"])
	check(title.new_panel.visible,"true click opens a new independent game form")
	await hold()
	await click(title.new_submit)
	await wait_for(func() -> bool: return title.awaiting_note,"save completes before public opening note appears")
	if input_failed or failures:
		await finish()
		return
	var public: Dictionary = game.story_view()
	var first: Array = public.notes.filter(func(row: Dictionary) -> bool: return row.page_number == 1 and row.unlocked)
	check(first.size() == 1 and title.opening_notes.body.text == first[0].text,"movie displays exact saved public page one")
	check(public.notes.filter(func(row: Dictionary) -> bool: return not row.unlocked).all(func(row: Dictionary) -> bool: return not row.has("title") and not row.has("text")),"movie does not anticipate later notebook pages")
	check(main.title_entry_cue_count == 1,"one actual successful entry chime")
	var saved: Dictionary = game.snapshot()
	var receipts: Array = saved.processed_actions.keys().filter(func(id: String) -> bool: return saved.processed_actions[id].get("action_type") == "new_game")
	check(receipts.size() == 1,"movie owns one persisted creation command")
	if not receipts.is_empty(): movie_command_id = str(receipts[0])
	print("TITLE MOVIE SAVED ",JSON.stringify({"command_id":movie_command_id,"save_id":saved.save_id,"actual_state_version":saved.state_version,"entry_chime_count":main.title_entry_cue_count,"locked_note_count":public.notes.filter(func(row: Dictionary) -> bool: return not row.unlocked).size()}))
	await hold()
	await click(title.opening_notes.close_button)
	check(main.current_screen == "front" and main.shell_header.visible and not title.visible,"closing the committed note enters the working storefront")
	if input_failed or failures:
		await finish()
		return
	while Engine.get_frames_drawn()-operations_start_frame < int(config.qa.movie.duration_seconds)*int(config.qa.movie.fps): await process_frame
	var duration := float(Engine.get_frames_drawn()-operations_start_frame)/float(config.qa.movie.fps)
	# This is only the operations middle. Prefix/teardown are also in the AVI.
	# Final artifact acceptance requires tools/verify_title_movie.py after exit.
	print("TITLE MOVIE OPERATIONS MIDDLE ",duration," seconds; FINAL_AVI_PENDING_EXTERNAL_VERIFY; source=",FileAccess.get_sha256("res://tests/integration/title_movie.gd"))
	await finish()

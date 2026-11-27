extends SceneTree
## Draft only / UNRUN. Real GameState writes and acknowledged pointer events.
const Config = preload("res://scripts/ui/title_config.gd")
const Teardown = preload("res://tests/ui_teardown.gd")
var config: Dictionary
var main: Control
var game: Node
var checks := 0
var failures := 0
var captures := 0
var input_failed := false
var capture_enabled := false
var capture_directory := ""
var frames: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TITLE UI FAIL: "+label)

func settle() -> void:
	for index: int in range(int(config.qa.settle_frames)): await process_frame

func setup() -> bool:
	config = Config.load_config()
	check(not config.is_empty(),"strict TITLE JSON is installed")
	if config.is_empty(): return false
	if DisplayServer.get_name()=="headless":
		root.size = Vector2i(config.qa.sizes[0][0],config.qa.sizes[0][1])
		root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	game = root.get_node("GameState")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.get_node("SaveService").base_dir = "res://.tools/r3-title/ui-saves/"+game.make_id("run")
	capture_directory = "res://.tools/r3-title/captures/"+game.make_id("run")
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--capture": capture_enabled = true
		elif argument.begins_with("--capture-dir="): capture_directory = argument.trim_prefix("--capture-dir=")
		else: check(false,"known TITLE argument / "+argument)
	check(capture_directory.begins_with("res://.tools/r3-title/") and not capture_directory.contains(".."),"capture directory is isolated")
	check(game.player_snapshot().is_empty(),"fresh process starts without a fabricated or previously active game")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check(main.has_method("ui_new_game_intent"),"Main installs stable user creation intent")
	if not main.has_method("ui_new_game_intent"): return false
	check(main.title_control.visible and not main.save_window.visible and not main.shell_header.visible,"startup shows Title, without deferred saves or exposed chrome")
	if capture_enabled:
		check(DisplayServer.get_name() != "headless","captures require real Compatibility GPU")
		check(Config.missing_resources(config).is_empty(),"all final dusk/glow/wood/sign/leaf/chime resources are genuinely ready")
		check(main.presentation_audio.config.get("sounds",{}).get(config.assets.chime_key) == config.assets.entry_chime,"actual entry sound key is registered with the shared audio owner")
	return failures == 0

func run() -> void:
	if not await setup():
		await finish()
		return
	check_config_rejections()
	if failures:
		await finish()
		return
	var title: Control = main.title_control
	var original: Dictionary = game.snapshot()
	check(title.buttons.size() == 4 and not title.buttons.has("start"),"exactly four dynamic wood-sign menu entries")
	check(title.buttons["continue"].disabled,"continue is unavailable with no save or backup")
	await check_modal_keyboard("title",title.buttons["credits"])
	if input_failed or failures:
		await finish()
		return
	for dimensions: Array in config.qa.sizes:
		root.size = Vector2i(dimensions[0],dimensions[1])
		root.content_scale_size = root.size
		await settle()
		check_title_bounds()
		await clear_highlights()
		check(is_zero_approx(title.window_glow.modulate.a),"dusk starts with the actual independent light hidden")
		await capture("dusk-unlit")
		await hover(title.buttons["new"])
		check(title.window_glow.modulate.a > 0,"start hover reveals independent window glow after tween")
		await capture("hover-window-lit")
		check(game.snapshot() == original,"hover and resizing never save, tick game time or disclose a note")
	if input_failed or failures:
		await finish()
		return
	# Settings/credits are real input paths; no code calls their callbacks directly.
	await click(title.buttons["credits"])
	check(title.credits_panel.visible,"real menu click opens local credits")
	if input_failed or failures:
		await finish()
		return
	var credit_close: Button = title.credits_panel.find_children("*","Button",true,false).back()
	await click(credit_close)
	check(not title.credits_panel.visible,"real close click returns to Title")
	await click(title.buttons["settings"])
	if input_failed or failures:
		await finish()
		return
	var api: Node = main.find_child("ApiUrl",true,false)
	var dialog: ConfirmationDialog = api.get_window() as ConfirmationDialog if api != null else null
	check(dialog != null and dialog.visible,"existing settings works before a save exists")
	if dialog == null:
		await finish()
		return
	var cancel_choices: Array[Node] = dialog.find_children("*","Button",true,false).filter(func(node: Node) -> bool: return node.is_visible_in_tree() and str(node.text) == str(dialog.get_cancel_button().text))
	check(cancel_choices.size() == 1,"settings exposes one visible cancel action")
	if cancel_choices.size() != 1:
		await finish()
		return
	await click(cancel_choices[0])
	check(title.visible,"closing settings retains title without creating a game")
	await click(title.buttons["new"])
	check(title.new_panel.visible,"new day opens the dynamic store-name form")
	if input_failed or failures:
		await finish()
		return
	var files_before: Array = root.get_node("SaveService").list_saves()
	root.get_node("SaveService").fail_next_write = true
	await click(title.new_submit)
	var failed_intent: Dictionary = main.ui_new_game_intent()
	check(not failed_intent.is_empty(),"failed creation retains its stable command and original name")
	check(not root.get_node("SaveService").fail_next_write,"failure injection was actually consumed")
	check(game.snapshot() == original and root.get_node("SaveService").list_saves() == files_before,"failed write publishes no game or save")
	check(title.visible and not title.awaiting_note and not title.notes_panel.visible and main.title_entry_cue_count == 0,"failure cannot reveal note one, enter shop or play the success chime")
	check(not title.new_name.editable,"failed command name is frozen until retry or explicit cancel")
	var command_id := str(failed_intent.get("id",""))
	await check_modal_keyboard("failed",title.new_name)
	check(main.ui_new_game_intent() == failed_intent,"Tab/Enter in the failed form preserves original stable ID/name")
	await click(title.new_submit)
	await wait_for(func() -> bool: return title.awaiting_note,"successful retry reaches the saved notebook")
	for drawer: Control in main.scene_holder.find_children("*","PaperDrawer",true,false):
		check(not drawer.is_visible_in_tree(),"opening note hides the complete gameplay drawer and its bookmark")
	if input_failed or failures:
		await finish()
		return
	var saved: Dictionary = game.snapshot()
	check(saved.processed_actions.has(command_id),"success is committed under the exact retained UI command ID")
	check(saved.name == failed_intent.name and main.ui_new_game_intent().is_empty(),"first name is saved and finished intent is cleared")
	var public: Dictionary = game.story_view()
	var first: Array = public.notes.filter(func(row: Dictionary) -> bool: return row.page_number == 1 and row.unlocked)
	check(first.size() == 1 and title.opening_notes.body.text == first[0].text,"opening body equals the committed public page one")
	check(public.notes.filter(func(row: Dictionary) -> bool: return not row.unlocked).all(func(row: Dictionary) -> bool: return not row.has("text") and not row.has("title")),"future pages remain locked and unmaterialized")
	await check_modal_keyboard("note",title.opening_notes.body)
	check(title.awaiting_note,"Tab/Enter cannot dismiss or advance the saved opening from its reading anchor")
	if capture_enabled: check(main.title_entry_cue_count == 1,"one actual configured entry chime after successful save")
	for dimensions: Array in config.qa.sizes:
		root.size = Vector2i(dimensions[0],dimensions[1])
		root.content_scale_size = root.size
		await settle()
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(title.notes_panel.get_global_rect()),"saved opening note is inside the actual viewport")
		for label: Control in main.scene_holder.find_children("HotspotLabel_*","Control",true,false):
			check(not label.is_visible_in_tree() or is_zero_approx(label.modulate.a),"resizing the opening cannot reveal a background hotspot label")
		await capture("saved-note-one")
	await click(title.opening_notes.close_button)
	check(not title.visible and main.current_screen == "front" and main.shell_header.visible,"closing the saved opening enters the working front desk")
	for drawer: Control in main.scene_holder.find_children("*","PaperDrawer",true,false):
		check(drawer.is_visible_in_tree(),"closing the opening restores the gameplay drawer")
	check_restored_focus()
	var cue_before: int = main.title_entry_cue_count
	var replay: Dictionary = await main.run_action("new_game",{"name":config.copy.default_name,"action_id":"must_not_override","type":"next_day"},command_id)
	check(replay.get("replayed",false) and game.snapshot() == saved,"explicit stable tail wins and replays instead of creating/renaming/reinitializing")
	check(main.title_entry_cue_count == cue_before and not title.visible,"direct successful replay never reopens Title or repeats the creation chime")
	# A manual deferred callback now models the old early-direct-command boundary.
	main.call_deferred("_open_title_if_unresolved")
	await settle()
	check(not title.visible and not main.save_window.visible,"deferred startup cannot cover a completed direct command")
	check((await main.run_action("load_game",{"save_id":saved.save_id})).get("success",false),"legacy two-argument Main entry remains nonblocking and reachable")
	await check_save_book_entry()
	await check_exact_focus_restore()
	await finish()

func check_save_book_entry() -> void:
	# The old save-book create button is a second true UI source, not a second
	# creation implementation. It must keep the same retry/opening contract.
	if input_failed or failures: return
	var before: Dictionary = game.snapshot()
	var cue_before: int = main.title_entry_cue_count
	var drawer: Control = main.screen.get_node_or_null("FrontDrawer")
	if is_instance_valid(drawer) and drawer.expanded:
		await click(drawer.bookmark)
		check(not drawer.expanded,"close the visible notebook before using the underlying chrome")
	await click(main.open_button)
	check(main.save_window.visible,"actual chrome button opens the existing save book")
	root.get_node("SaveService").fail_next_write = true
	await click(main.save_create_button)
	var intent: Dictionary = main.ui_new_game_intent()
	check(not intent.is_empty() and not root.get_node("SaveService").fail_next_write,"save-book write failure retains and consumes the real command attempt")
	check(game.snapshot() == before and not main.title_control.visible and main.save_window.visible,"failed save-book creation leaves old game and current window visible")
	check(main.title_entry_cue_count == cue_before and not main.title_control.awaiting_note,"save-book failure cannot flash note or play entry cue")
	await click(main.save_create_button)
	await wait_for(func() -> bool: return main.title_control.awaiting_note,"save-book retry uses the same post-save opening path")
	if input_failed or failures: return
	var after: Dictionary = game.snapshot()
	check(after.save_id != before.save_id and after.processed_actions.has(str(intent.id)),"save-book retry creates one independent game under the retained command")
	var old: Dictionary = root.get_node("SaveService").read_save(str(before.save_id))
	check(old.get("success",false) and old.get("state",{}) == before,"existing saved game is preserved exactly")
	var first: Array = game.story_view().notes.filter(func(row: Dictionary) -> bool: return row.page_number == 1 and row.unlocked)
	check(first.size() == 1 and main.title_control.opening_notes.body.text == first[0].text,"save-book opening uses the newly committed public page")
	await click(main.title_control.opening_notes.close_button)
	check(main.current_screen == "front" and not main.title_control.visible,"save-book opening closes to the real front")
	if capture_enabled: check(main.title_entry_cue_count == cue_before+1,"one additional actual chime for the second distinct UI creation")

func check_config_rejections() -> void:
	var bad := config.duplicate(true)
	bad.unexpected = true
	check(not Config.config_valid(bad),"unknown top-level title data is rejected")
	bad = config.duplicate(true)
	bad.menu[1].id = bad.menu[0].id
	check(not Config.config_valid(bad),"duplicate wood-sign intents are rejected")
	bad = config.duplicate(true)
	bad.motion.zoom_seconds = NAN
	check(not Config.config_valid(bad),"nonfinite presentation timing is rejected")
	bad = config.duplicate(true)
	bad.assets.background = "res://assets/../night.png"
	check(not Config.config_valid(bad),"unsafe asset paths are rejected")
	bad = config.duplicate(true)
	bad.geometry.window_light.outer[0] = [0,0]
	check(not Config.config_valid(bad),"glow calibration outside authorized window bounds is rejected")
	bad = config.duplicate(true)
	bad.qa.maximum_jpg = 7
	check(not Config.config_valid(bad),"screenshots cannot exceed the six-frame deliverable")

func key_event(keycode: Key, shift: bool = false) -> void:
	for down: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.shift_pressed = shift
		event.pressed = down
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await settle()

func check_modal_keyboard(stage: String, anchor: Control) -> void:
	if input_failed or failures: return
	var before: Dictionary = game.snapshot()
	anchor.grab_focus()
	for index: int in range(config.menu.size()+1):
		for shift: bool in [false,true]:
			await key_event(KEY_TAB,shift)
			var focused: Control = root.gui_get_focus_owner()
			check(not is_instance_valid(focused) or not main.scene_holder.is_ancestor_of(focused),"real Tab/Shift-Tab cannot focus gameplay / "+stage)
			if failures: return
	anchor.grab_focus()
	await key_event(KEY_ENTER)
	if stage == "title":
		check(main.title_control.credits_panel.visible,"Enter on the allowed Title entry still opens credits")
		if main.title_control.credits_panel.visible:
			await click(main.title_control.credits_panel.find_children("*","Button",true,false).back())
	var nodes: Array[Node] = [main.scene_holder]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		nodes.append_array(node.get_children())
		check(not node.is_processing_input() and not node.is_processing_unhandled_input() and not node.is_processing_unhandled_key_input() and not node.is_processing_shortcut_input(),"all gameplay input callbacks remain blocked / "+stage)
		if node is Control:
			check(node.focus_mode == Control.FOCUS_NONE and node.mouse_filter == Control.MOUSE_FILTER_IGNORE,"every gameplay descendant loses focus/mouse eligibility / "+stage)
	if main.current_screen == "front" and main.screen.daily_read_button.visible:
		await ignored_gameplay_pointer(main.screen.daily_read_button)
	check(game.snapshot() == before,"Tab/Shift-Tab/Enter/pointer cannot persist an underlying action / "+stage)

func ignored_gameplay_pointer(control: Button) -> void:
	var observed := {"pressed":false}
	var callback := func(): observed.pressed = true
	control.pressed.connect(callback)
	var point := point_for(control)
	# A valid modal button at that same pixel may legitimately close a dialog.
	# Do not misreport that allowed overlay action as an underlying input leak.
	if is_instance_valid(main.title_control) and main.title_control.visible:
		for overlay: Button in main.title_control.find_children("*","Button",true,false):
			if overlay.is_visible_in_tree() and not overlay.disabled and overlay.get_global_rect().has_point(point):
				check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE,"modal covers target pixel while underlying control remains noninteractive")
				control.pressed.disconnect(callback)
				return
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await settle()
	check(not observed.pressed,"real pointer aimed at blocked morning action does not emit pressed")
	if is_instance_valid(control) and control.pressed.is_connected(callback): control.pressed.disconnect(callback)

func check_restored_focus() -> void:
	var focused: Control = root.gui_get_focus_owner()
	check(is_instance_valid(focused) and main.scene_holder.is_ancestor_of(focused) and focused.focus_mode != Control.FOCUS_NONE,"completing opening restores real gameplay keyboard focus")
	check(main._title_input_records.is_empty(),"completed modal releases every saved input guard")

func check_exact_focus_restore() -> void:
	if input_failed or failures or main.current_screen != "front": return
	var target: Button = main.screen.daily_read_button
	check(target.visible and not target.disabled,"legal morning action exists for focus restoration boundary")
	if not target.visible or target.disabled: return
	target.grab_focus()
	var prior_mouse: int = target.mouse_filter
	var prior_focus: int = target.focus_mode
	var before: Dictionary = game.snapshot()
	main.set_title_blocking(true)
	await ignored_gameplay_pointer(target)
	await key_event(KEY_TAB)
	await key_event(KEY_ENTER)
	check(game.snapshot() == before,"standalone guard suppresses underlying pointer and keyboard actions")
	main.set_title_blocking(false)
	check(target.has_focus() and target.mouse_filter == prior_mouse and target.focus_mode == prior_focus,"same living control regains exact prior focus and mouse modes")

func check_title_bounds() -> void:
	var viewport := Rect2(Vector2.ZERO,Vector2(root.size))
	for control: Control in main.title_control.buttons.values():
		check(viewport.encloses(control.get_global_rect()),"actual dynamic wood-sign text/control lies within window / "+control.name)
	check(viewport.encloses(main.title_control.title_visual.get_global_rect()),"title fits actual viewport")

func wait_for(condition: Callable, label: String) -> void:
	var deadline := Time.get_ticks_msec()+int(config.qa.input_timeout_ms)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
		Input.flush_buffered_events()
	check(condition.call(),label)
	if not condition.call(): input_failed = true

func point_for(control: Control) -> Vector2:
	var point := control.get_global_rect().get_center()
	if control.get_window() != root: point += Vector2(control.get_window().position)
	return point

func hover(control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point_for(control)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await settle()
	await create_timer(float(config.motion.light_seconds)).timeout

func clear_highlights() -> void:
	var title: Control = main.title_control
	for button: Button in title.buttons.values(): button.release_focus()
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2.ZERO
	motion.global_position = Vector2.ZERO
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await settle()
	await create_timer(float(config.motion.light_seconds)).timeout

func click(control: Button) -> void:
	if input_failed: return
	check(control != null and control.is_visible_in_tree() and not control.disabled,"pointer target is actually visible/enabled")
	if control == null or not control.is_visible_in_tree() or control.disabled:
		input_failed = true
		return
	var acknowledgement := {"pressed":false}
	var callback := func(): acknowledgement.pressed = true
	control.pressed.connect(callback,CONNECT_ONE_SHOT)
	var point := point_for(control)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await wait_for(func() -> bool: return acknowledgement.pressed,"actual mouse event emits pressed before the next step")
	if not acknowledgement.pressed and is_instance_valid(control):
		var hovered: Variant = root.call("gui_get_hovered_control") if root.has_method("gui_get_hovered_control") else null
		print("TITLE POINTER DIAGNOSTIC ",JSON.stringify({"target":str(control.get_path()),"point":str(point),"rect":str(control.get_global_rect()),"viewport":str(root.size),"mouse":str(root.get_mouse_position()),"hovered":str(hovered.get_path()) if is_instance_valid(hovered) else "none","credits":str(main.title_control.credits_panel.get_global_rect()),"overlay_size":str(main.title_control.overlay_root.size),"overlay_scale":str(main.title_control.overlay_root.scale),"target_filter":control.mouse_filter}))
	if not acknowledgement.pressed and is_instance_valid(control) and control.pressed.is_connected(callback): control.pressed.disconnect(callback)
	await wait_for(func() -> bool: return not main.busy,"actual action settles before the next step")
	await settle()

func capture(label: String) -> void:
	if not capture_enabled or input_failed or failures: return
	check(captures < int(config.qa.maximum_jpg),"six JPG hard limit")
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == root.size,"actual framebuffer dimensions match native root")
	var filename := label+"-"+str(root.size.x)+"x"+str(root.size.y)+".jpg"
	var path := capture_directory.path_join(filename)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_directory))
	check(not FileAccess.file_exists(path),"capture cannot overwrite historical evidence")
	if failures: return
	check(image.save_jpg(path,float(config.qa.jpeg_quality)) == OK,"direct quality85 JPG save")
	frames.append({"path":path,"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),"keyframe":label,"save_id":game.player_snapshot().get("save_id","")})
	captures += 1

func finish() -> void:
	if capture_enabled:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_directory))
		var receipt := FileAccess.open(capture_directory.path_join("receipt.json"),FileAccess.WRITE)
		if receipt != null: receipt.store_string(JSON.stringify({"source_sha256":FileAccess.get_sha256("res://tests/integration/title_ui.gd"),"frames":frames,"checks":checks,"failures":failures,"input_failed":input_failed},"\t",true))
	print("TITLE UI RESULT: %d checks, %d failures, %d JPG; renderer=%s" % [checks,failures,captures,DisplayServer.get_name()])
	if is_instance_valid(main):
		if main.has_method("ui_new_game_intent") and is_instance_valid(main.title_control): await main.title_control.shutdown_async()
		await Teardown.release_audio(main)
		main.queue_free()
	await Teardown.drain(self)
	quit(1 if failures else 0)

extends "res://tests/integration/title_ui.gd"
## UNRUN. Each bad case is a real on-disk file/missing file; no fake valid config.
## Optional prepare/run across separate processes proves legitimate continuation.
var failure_case := "missing"
var prepare_existing := false
var fixture_receipt := ""
var requested_save_dir := ""

func run() -> void:
	config = Config.load_config()
	check(not config.is_empty(),"the actual normal title JSON is validated before making a rejected file fixture")
	if config.is_empty():
		quit(1)
		return
	if DisplayServer.get_name()=="headless":
		root.size = Vector2i(config.qa.sizes[0][0],config.qa.sizes[0][1])
		root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	game = root.get_node("GameState")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var run_id: String = game.make_id("bad_title")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): failure_case = arg.trim_prefix("--case=")
		elif arg == "--prepare-existing": prepare_existing = true
		elif arg.begins_with("--existing-receipt="): fixture_receipt = arg.trim_prefix("--existing-receipt=")
		elif arg.begins_with("--save-dir="): requested_save_dir = arg.trim_prefix("--save-dir=")
		else: check(false,"known invalid-config argument / "+arg)
	check(failure_case in ["missing","syntax","field"],"one concrete missing/malformed/rejected field case")
	if requested_save_dir.is_empty(): requested_save_dir = "res://.tools/r3-title/invalid-config-saves/"+run_id
	check(requested_save_dir.begins_with("res://.tools/r3-title/") and not requested_save_dir.contains(".."),"bad-config saves stay isolated")
	var existing: Dictionary = {}
	if not fixture_receipt.is_empty():
		check(fixture_receipt.begins_with("res://.tools/r3-title/") and not fixture_receipt.contains(".."),"existing checkpoint receipt is local")
		var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_receipt))
		check(read is Dictionary and read.get("save_dir") is String and read.get("save_id") is String and read.get("sha256") is String,"a real previous-process checkpoint receipt is supplied")
		if read is Dictionary:
			existing = read
			requested_save_dir = str(read.get("save_dir",""))
	root.get_node("SaveService").base_dir = requested_save_dir
	check(requested_save_dir.begins_with("res://.tools/r3-title/") and not requested_save_dir.contains(".."),"receipt save directory remains inside isolated TITLE workspace")
	if failures:
		await finish()
		return
	if prepare_existing:
		await prepare_checkpoint(run_id)
		await finish()
		return
	check(game.snapshot().is_empty(),"actual startup rejection begins in a fresh process")
	var before: Dictionary = game.snapshot()
	var saves_before: Array = root.get_node("SaveService").list_saves()
	var fixture_dir: String = "res://.tools/r3-title/invalid-config-files/"+run_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_dir))
	var rejected_path: String = fixture_dir.path_join("title.json")
	if failure_case != "missing":
		var file := FileAccess.open(rejected_path,FileAccess.WRITE)
		check(file != null,"write the concrete rejected configuration file")
		if file == null:
			await finish()
			return
		if failure_case == "syntax": file.store_string("{")
		else:
			var invalid := config.duplicate(true)
			invalid.motion.zoom_seconds = -absf(float(config.motion.zoom_seconds))
			file.store_string(JSON.stringify(invalid))
		file.close()
	check(not FileAccess.file_exists(rejected_path) if failure_case == "missing" else FileAccess.file_exists(rejected_path),"fixture really is missing or present as requested")
	check(Config.load_config(rejected_path).is_empty(),"the real loader rejects the actual file")
	main = load("res://scenes/main.tscn").instantiate()
	main.title_config_path = rejected_path
	root.add_child(main)
	await settle()
	check(not main._title_available() and not is_instance_valid(main.title_control),"rejected input never creates a fake default Title")
	check(is_instance_valid(main.title_error_panel) and main.title_error_panel.is_visible_in_tree(),"Main renders a coherent unavailable panel")
	check(main.title_error_label.text == str(main.shell_config.title_unavailable) and main.title_error_label.is_visible_in_tree(),"public rejection is the independently validated Chinese Shell copy")
	check(main.save_create_button.disabled and not main.save_name.editable,"UI creation stays unavailable instead of dereferencing absent copy/layout")
	await main._ui_create_game(str(config.copy.default_name))
	check(game.snapshot() == before and root.get_node("SaveService").list_saves() == saves_before,"rejected UI entry performs no state/save action")
	check(main.ui_new_game_intent().is_empty() and main.title_entry_cue_count == 0,"rejected entry allocates no pending creation intent, note or cue")
	await click(main.find_child("TitleFallbackSettings",true,false))
	var api := main.find_child("ApiUrl",true,false)
	var settings := api.get_window() as ConfirmationDialog if api != null else null
	check(settings != null and settings.visible,"existing settings remains reachable from the unavailable panel")
	if input_failed or failures or settings == null:
		await finish()
		return
	var cancel_choices: Array[Node] = settings.find_children("*","Button",true,false).filter(func(node: Node) -> bool: return node.is_visible_in_tree() and str(node.text) == str(settings.get_cancel_button().text))
	check(cancel_choices.size() == 1,"unavailable-title settings exposes one visible cancel action")
	if cancel_choices.size() != 1:
		await finish()
		return
	await click(cancel_choices[0])
	await click(main.find_child("TitleFallbackSaves",true,false))
	check(main.save_window.visible and main.save_create_button.disabled,"existing save book is reachable without enabling rejected creation")
	if input_failed or failures:
		await finish()
		return
	if not existing.is_empty():
		var path := requested_save_dir.path_join(str(existing.save_id)+".json")
		check(FileAccess.get_sha256(path) == str(existing.sha256),"existing checkpoint is genuine unchanged transaction output")
		var index := -1
		for i: int in range(main.save_entries.size()):
			if main.save_entries[i].save_id == existing.save_id: index = i
		check(index >= 0,"legitimate existing save is actually selectable")
		if index >= 0:
			main.save_list.select(index)
			main._select_save(index)
			var loads: Array = main.save_window.find_children("*","Button",true,false).filter(func(button: Button) -> bool:
				return button.pressed.get_connections().any(func(connection: Dictionary) -> bool: return connection.callable.get_object() == main and connection.callable.get_method() == "_load_selected"))
			check(loads.size() == 1,"select the real existing load button by its actual bound callback")
			if loads.size() == 1: await click(loads[0])
			check(game.player_snapshot().get("save_id") == existing.save_id and game.player_snapshot().get("state_version") == existing.state_version,"actual continue loads latest saved progress without making a new game")
			check(main.current_screen == "consultation" and not str(existing.active_visit_id).is_empty() and game.active_visit().get("visit_id") == existing.active_visit_id,"continue preserves the legitimately saved active visit")
			check(not main.title_error_panel.visible and not main._title_blocking,"successful ordinary load dismisses error state and restores gameplay")
			check(FileAccess.get_sha256(path) == str(existing.sha256),"read-only continuation never rewrites the checkpoint")
	await finish()

func prepare_checkpoint(run_id: String) -> void:
	# A separate process prepares the slot through actual actions, then exits.
	var created: Dictionary = await game.execute_action_async({"type":"new_game","action_id":run_id,"name":config.copy.default_name})
	check(created.get("success",false),"real creation transaction prepares old-progress checkpoint")
	for kind: String in ["read_morning_letters","next_customer"]:
		check((await game.execute_action_async({"type":kind,"action_id":game.make_id("fixture"),"expected_version":game.player_snapshot().state_version})).get("success",false),"real checkpoint action / "+kind)
	if failures: return
	var save_id := str(game.player_snapshot().save_id)
	var path := requested_save_dir.path_join(save_id+".json")
	# Keep metadata outside the save directory; it must not become a fake slot.
	var receipt_path := requested_save_dir+".receipt.json"
	check(not str(game.active_visit().get("visit_id","")).is_empty(),"prepared checkpoint actually owns an active visit")
	var receipt := FileAccess.open(receipt_path,FileAccess.WRITE)
	check(receipt != null,"record real checkpoint file SHA")
	if receipt != null: receipt.store_string(JSON.stringify({"save_dir":requested_save_dir,"save_id":save_id,"state_version":game.player_snapshot().state_version,"active_visit_id":game.active_visit().get("visit_id",""),"sha256":FileAccess.get_sha256(path)},"\t",true))
	print("TITLE INVALID CONFIG FIXTURE ",receipt_path)

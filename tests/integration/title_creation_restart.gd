extends SceneTree
## AUTHORED NOT RUN. Invoke in TWO separate processes, -- --seed <run_id>, then
## -- --replay <same_run_id>. This script never launches an engine itself.
var game: Node
var saves: Node
var checks := 0
var failures := 0
var changes := 0
const COMMAND_ID := "title_restart_creation"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TITLE CREATION RESTART FAIL: "+label)

func files() -> Dictionary:
	var result := {}
	var folder := DirAccess.open(saves.base_dir)
	if folder!=null:
		for file: String in folder.get_files():
			result[file] = FileAccess.get_sha256(saves.base_dir.path_join(file))
	return result

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var args := OS.get_cmdline_user_args()
	check(args.size()==2 and args[0] in ["--seed","--replay"] and saves._safe_id(args[1]),"explicit stage and safe isolated run ID are required")
	check(saves.has_method("new_game_save_id"),"creation identity boundary exists")
	if failures:
		finish()
		return
	saves.base_dir = "res://.tools/r3-title/restart-saves/"+args[1]
	var command := {"type":"new_game","action_id":COMMAND_ID,"name":"首次进程店名"}
	if args[0]=="--seed":
		check(files().is_empty(),"seed refuses to overwrite any previous run artifacts")
		if failures:
			finish()
			return
		var first: Dictionary = await game.execute_action_async(command)
		check(first.success and first.state_version==1,"first process commits creation receipt")
		if first.success:
			var progress: Dictionary = await game.execute_action_async({"type":"set_free_question","action_id":"title_restart_progress","enabled":true})
			check(progress.success and game.state.state_version==2,"first process saves real later progress before dropping its response")
	else:
		check(game.snapshot().is_empty(),"second process starts with no current save")
		var durable: Dictionary = saves.read_save(saves.new_game_save_id(COMMAND_ID))
		check(durable.success,"second process finds the first process's durable save")
		if not durable.success:
			finish()
			return
		check(durable.state.state_version==2 and durable.state.divination.settings.free_question and durable.state.processed_actions[COMMAND_ID].state_version==1,"durable evidence contains later progress and the original creation receipt")
		var before := files()
		game.state_changed.connect(func():changes+=1)
		saves.fail_next_write = true
		command.name = "第二进程不能改名"
		var replay: Dictionary = await game.execute_action_async(command)
		check(replay.success and replay.get("replayed",false) and replay.state_version==1 and game.snapshot()==durable.state and changes==1,"second process loads latest progress and returns first receipt")
		check(files()==before and saves.fail_next_write,"cross-process retry performs no write or backup rotation")
		replay = await game.execute_action_async(command)
		check(replay.success and replay.get("replayed",false) and changes==1 and files()==before and saves.fail_next_write,"same-process repeat after recovery is also silent and read-only")
		saves.fail_next_write = false
	finish()

func finish() -> void:
	print("TITLE CREATION RESTART: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

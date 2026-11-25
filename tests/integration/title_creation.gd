extends SceneTree
## AUTHORED NOT RUN. First install this target alone to observe behavioral RED.
## All filesystem mutations below stay in this run's isolated save directory.
var game: Node
var saves: Node
var checks := 0
var failures := 0
var changes := 0
var events := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TITLE CREATION FAIL: "+label)

func files() -> Dictionary:
	var result := {}
	var folder := DirAccess.open(saves.base_dir)
	if folder != null:
		for file: String in folder.get_files():
			result[file] = FileAccess.get_sha256(saves.base_dir.path_join(file))
	return result

func act(action: Dictionary) -> Dictionary:
	return await game.execute_action_async(action)

func rejected_unchanged(action: Dictionary, label: String) -> Dictionary:
	var before: Dictionary = game.snapshot()
	var bytes := files()
	var published := changes
	saves.fail_next_write = true
	var reply := await act(action)
	check(not reply.success and game.snapshot()==before and files()==bytes and changes==published and saves.fail_next_write,label)
	saves.fail_next_write = false
	return reply

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-title/creation-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func():changes+=1)
	game.presentation_events_committed.connect(func(_rows:Array):events+=1)
	var command := {"type":"new_game","action_id":"title_creation_a","name":"首次店名"}
	var first := await act(command)
	check(first.success,"first creation succeeds")
	if not first.success:
		finish()
		return
	var initial: Dictionary = game.snapshot()
	var initial_files := files()
	var published := changes
	var case_session: Variant = game._divination
	var case_coordinator: Variant = game._case_coordinator
	var generation_epoch: int = game._generation_epoch
	saves.fail_next_write = true
	var repeated := await act({"type":"new_game","action_id":command.action_id,"name":"不得替换的名字","expected_version":-1})
	check(repeated.success and repeated.get("replayed",false) and repeated.result.save_id==first.result.save_id and game.snapshot()==initial and saves.list_saves().size()==1,"same command replays its first success instead of creating or renaming a save")
	check(files()==initial_files and changes==published and saves.fail_next_write,"same-current replay is read-only, does not publish and does not consume fail_next_write")
	check(game._divination==case_session and game._case_coordinator==case_coordinator and game._generation_epoch==generation_epoch,"same-current replay preserves the live candidate Session and both generator epochs")
	saves.fail_next_write = false
	check(saves.has_method("new_game_save_id") and saves.has_method("inspect_new_game") and saves.has_method("new_game_receipt_valid"),"creation persistence boundary is available")
	if failures:
		finish()
		return
	check(game.state.save_id==saves.new_game_save_id(command.action_id) and first.state_version==1,"stable ID and first receipt version do not depend on the current save")
	check(saves.new_game_save_id(command.action_id)=="save_new_333eb71625c07ae057d010a43e513eb8c85e2e274906e1ae27ccf3d9096dd6fd","stable creation identity matches the independent SHA256 vector")
	check(game.state.processed_actions[command.action_id]==first and first.action_type=="new_game" and first.result=={"save_id":initial.save_id},"first successful write already contains the exact creation receipt")
	repeated = await act({"type":"new_game","action_id":command.action_id,"name":42})
	check(repeated.success and repeated.get("replayed",false) and game.state.name==initial.name,"idempotency also precedes validation of a replacement payload")
	var second_command := {"type":"new_game","action_id":"title_creation_b","name":"第二档"}
	var before: Dictionary = game.snapshot()
	var before_files := files()
	published = changes
	saves.fail_next_write = true
	var failed := await act(second_command)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED" and game.snapshot()==before and files()==before_files and changes==published,"failed first write publishes and persists no candidate")
	var second := await act(second_command)
	check(second.success and second.state_version==1 and game.state.save_id==saves.new_game_save_id(second_command.action_id) and game.state.save_id!=initial.save_id,"same failed ID retries into its stable target at version one")
	if not second.success:
		finish()
		return
	var second_id: String = game.state.save_id
	check((await act({"type":"load_game","save_id":initial.save_id})).success,"load first save to make real progress")
	check((await act({"type":"set_free_question","action_id":"title_progress","enabled":true})).success,"advance the first save through a normal persisted action")
	var latest: Dictionary = game.snapshot()
	check(int(latest.state_version)>1 and latest.processed_actions[command.action_id]==first,"latest progress retains the original version-one creation receipt")
	check((await act({"type":"load_game","save_id":second_id})).success,"switch to an independent current save")
	published = changes
	before_files = files()
	saves.fail_next_write = true
	repeated = await act(command)
	check(repeated.success and repeated.get("replayed",false) and repeated.state_version==1 and game.snapshot()==latest,"cross-save replay loads latest progress while returning the original receipt")
	check(changes==published+1 and files()==before_files and saves.fail_next_write,"cross-save replay publishes one load, performs no write or creation event")
	saves.fail_next_write = false
	# A newly initialized domain node has no current save; this is not an OS restart.
	var fresh: Node = game.get_script().new()
	root.add_child(fresh)
	fresh.configure_api("","","")
	fresh.set_people_generation_options(false)
	check(fresh.snapshot().is_empty(),"independent fresh domain instance begins with no loaded save")
	before_files = files()
	saves.fail_next_write = true
	var restarted: Dictionary = await fresh.execute_action_async(command)
	check(restarted.success and restarted.get("replayed",false) and fresh.snapshot()==latest and files()==before_files and saves.fail_next_write,"fresh domain replay reads the latest durable state without fresh initialization or a write")
	saves.fail_next_write = false
	fresh.queue_free()
	await process_frame
	for bad_id: Variant in [null,true,42,"","contains space","../outside","a".repeat(129)]:
		var bad := await rejected_unchanged({"type":"new_game","action_id":bad_id,"name":"无效请求"},"explicit invalid ID is rejected without downgrade or write")
		check(bad.error_code=="INVALID_ACTION","invalid ID uses the action validation failure")
	for _index: int in range(2):
		var cli := await act({"type":"new_game","name":"兼容命令行"})
		check(cli.success and cli.state_version==1 and not cli.has("action_type") and game.state.processed_actions.is_empty(),"omitted ID retains old random CLI creation without inventing a receipt")
	check(saves.list_saves().size()==4,"two missing-ID requests create two independent random saves")
	await failed_stages(initial,command.action_id)
	# Existing artifacts are not owned by a later call, even if their bytes look
	# like a valid candidate. They must stay byteexact, never implicitly recover.
	var suffixes := [".tmp",".bak.tmp",".bak.guard.tmp",".restore.tmp",".rollback.tmp",".corrupt.fixture"]
	for index: int in range(suffixes.size()):
		var artifact_command := {"type":"new_game","action_id":"title_artifact_%d"%index,"name":"产物冲突"}
		check((await act(artifact_command)).success,"create actual isolated source for artifact variant")
		var artifact_path: String=saves._path(game.state.save_id)
		check(DirAccess.rename_absolute(artifact_path,artifact_path+suffixes[index])==OK,"move only this run's exact primary into the tested artifact path")
		await rejected_unchanged(artifact_command,"preexisting artifact is refused without deletion or overwrite / "+suffixes[index])
	check(not saves.new_game_rules_valid({}),"missing JSON copy is strictly invalid")
	var invalid_copy: Dictionary=saves.new_game_rules()
	invalid_copy.copy.config_invalid="NEW_GAME_CONFIG_INVALID"
	check(not saves.new_game_rules_valid(invalid_copy),"new technical codes are not accepted as public Chinese copy")
	check(not saves.new_game_public_message("NEW_GAME_CONFIG_INVALID").contains("NEW_GAME_") and not saves.new_game_public_message("NEW_GAME_RECEIPT_INVALID").contains("NEW_GAME_"),"new codes are localized at the response boundary")

	# Existing valid slot without a receipt must not be overwritten. Only the newly
	# introduced receipt is removed from an actual save; no historic action is erased.
	var occupied_command := {"type":"new_game","action_id":"title_occupied","name":"占用槽"}
	check((await act(occupied_command)).success,"create actual data for a valid occupied-slot fixture")
	var occupied: Dictionary = game.snapshot()
	occupied.processed_actions.erase(occupied_command.action_id)
	check(saves.write_save(occupied).success,"persist valid occupied data without a matching receipt")
	var conflict := await rejected_unchanged(occupied_command,"valid unmatched slot is never overwritten")
	check(conflict.error_code=="NEW_GAME_CONFLICT","unmatched valid slot reports conflict")
	var poisoned_command := {"type":"new_game","action_id":"title_bad_receipt","name":"损坏回执"}
	check((await act(poisoned_command)).success,"create a real source before corrupting only its creation receipt")
	var poisoned: Dictionary = game.snapshot()
	poisoned.processed_actions[poisoned_command.action_id].result.save_id = "mismatched_target"
	var payload := JSON.stringify(poisoned)
	var poisoned_file := FileAccess.open(saves._path(poisoned.save_id),FileAccess.WRITE)
	check(poisoned_file!=null,"open only isolated receipt fixture")
	if poisoned_file!=null:
		poisoned_file.store_string(JSON.stringify({"format":saves.ENVELOPE_FORMAT,"payload":payload,"sha256":payload.sha256_text()}))
		poisoned_file.close()
	var malformed := await rejected_unchanged(poisoned_command,"valid envelope with malformed receipt never permits overwrite")
	check(malformed.error_code=="SAVE_CORRUPT","receipt corruption is rejected through normal snapshot validation")
	var backup_command := {"type":"new_game","action_id":"title_backup","name":"显式恢复"}
	check((await act(backup_command)).success,"create recovery fixture through the real action")
	check((await act({"type":"set_free_question","action_id":"title_backup_one","enabled":true})).success and (await act({"type":"set_free_question","action_id":"title_backup_two","enabled":false})).success,"real actions create verified backup and guard")
	var path: String = saves._path(game.state.save_id)
	check(DirAccess.remove_absolute(path)==OK,"remove only isolated fixture primary to simulate interruption")
	var missing := await rejected_unchanged(backup_command,"backup-only target cannot be silently recreated")
	check(missing.get("backup_available",false),"backup-only failure advertises explicit recovery")
	check(DirAccess.remove_absolute(path+".bak")==OK,"remove only isolated backup to exercise guard-only recovery")
	missing = await rejected_unchanged(backup_command,"guard-only target cannot be silently recreated")
	check(missing.get("backup_available",false),"guard fallback is discoverable without restoring it")
	check((await act({"type":"load_game","save_id":saves.new_game_save_id(backup_command.action_id),"recover_backup":true})).success,"only explicit load recovery restores the existing slot")
	check((await act(backup_command)).get("replayed",false),"explicitly recovered creation receipt can replay")
	check((await act({"type":"set_free_question","action_id":"title_after_recovery","enabled":true})).success,"create a good backup before corrupting the isolated primary")
	var corrupt := FileAccess.open(path,FileAccess.WRITE)
	check(corrupt!=null,"open only isolated primary for corruption fixture")
	if corrupt!=null:
		corrupt.store_string("corrupt isolated TITLE primary")
		corrupt.close()
	var damaged := await rejected_unchanged(backup_command,"damaged primary never falls through to creation")
	check(damaged.error_code=="SAVE_CORRUPT" and damaged.get("backup_available",false),"damaged primary retains explicit backup recovery metadata")
	# Reentrant listeners must not manufacture another creation or alter the outer reply.
	var reentry_command := {"type":"new_game","action_id":"title_reentry","name":"一次创建"}
	var nested := {}
	var listener := func():nested.assign(game.execute_action(reentry_command))
	game.state_changed.connect(listener)
	published = changes
	var outer := await act(reentry_command)
	game.state_changed.disconnect(listener)
	check(outer.success and not outer.get("replayed",false) and nested.get("replayed",false) and nested.get("result")==outer.result and changes==published+1,"same-command signal reentry returns the committed receipt without publishing again")
	check(events==0,"creation and replay invent no gameplay presentation events")
	finish()

func failed_stages(snapshot: Dictionary, action_id: String) -> void:
	for stage: String in ["partial","validated"]:
		var stage_script: Script=load("res://tests/support/title_new_game_stage_failure.gd")
		check(stage_script!=null,"stage helper loads only after the creation contract exists")
		if stage_script==null:
			return
		var writer: Node=stage_script.new()
		root.add_child(writer)
		writer.base_dir=saves.base_dir.path_join("stage_"+stage)
		writer.failure_stage=stage
		for invalid: Variant in [null,[],"wrong_container"]:
			var malformed:=snapshot.duplicate(true)
			malformed.processed_actions=invalid
			check(not writer.write_new_game(malformed,action_id).success,"wrapper refuses malformed action container without script error")
		var rejected: Dictionary=writer.write_new_game(snapshot.duplicate(true),action_id)
		var folder:=DirAccess.open(writer.base_dir)
		check(not rejected.success and (folder==null or folder.get_files().is_empty()),"failed first-write stage cleans only its own previously absent tmp / "+stage)
		var retried: Dictionary=writer.write_new_game(snapshot.duplicate(true),action_id)
		check(retried.success and writer.read_save(snapshot.save_id).state==snapshot,"same action retries after the modeled real staging failure / "+stage)
		writer.queue_free()
		await process_frame

func finish() -> void:
	print("TITLE CREATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

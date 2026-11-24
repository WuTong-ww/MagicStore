extends SceneTree
## The fixture is a byte-exact real backlog run, not a relabeled current save.
const FIXTURE := "res://tests/fixtures/emergent_legacy_mode.json"
const EXPECTED_SHA := "ab4be7674a116f615a618b4b1652ed44b651f23b4e9a271f97c4efe31854b791"
var checks := 0
var failures := 0
var changes := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("AICASE MODE RECOVERY FAIL: "+label)

func run() -> void:
	var game: Node = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	check(FileAccess.get_sha256(FIXTURE)==EXPECTED_SHA,"genuine interrupted-mode envelope preserves its original captured bytes")
	if failures:
		finish()
		return
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	check(envelope.get("format")==saves.ENVELOPE_FORMAT and envelope.get("payload") is String and envelope.get("sha256")==str(envelope.get("payload","")).sha256_text(),"original envelope checksum is intact")
	var source: Dictionary = saves._normalize_numbers(JSON.parse_string(envelope.payload))
	check(source.schema_version==14 and source.daily_loop.mode=="legacy" and source.daily_loop.phase=="morning" and not source.daily_loop.planned and source.story.ending.status=="complete","real source is schema14 at the supported legacy-to-ordered restoration boundary")
	check(saves.validate_snapshot(source).success,"strict validator accepts the original real source before any migration")
	saves.base_dir = "res://.tools/r3-aicase/mode-recovery/"+game.make_id("run")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	var path: String = saves._path(source.save_id)
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE),ProjectSettings.globalize_path(path))==OK and FileAccess.get_sha256(path)==EXPECTED_SHA,"isolated writable copy starts byte-exact")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.daily_loop_config.enabled = false
	var loaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":source.save_id})
	check(loaded.success and game.state.daily_loop.mode=="legacy","real load under legacy configuration preserves the mode instead of hiding the restoration boundary")
	if not loaded.success:
		finish()
		return
	game.state_changed.connect(on_changed)
	game.daily_loop_config.enabled = true
	var before: Dictionary = game.snapshot()
	var old_instances: Dictionary = before.divination.emergent_cases.instances.duplicate(true)
	var command := {"type":"read_morning_letters","action_id":"emergent_mode_recovery_first_read"}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	var reached_write: bool = not failed.success and failed.error_code=="SAVE_WRITE_FAILED"
	check(reached_write,"mode restoration reaches the durable write rather than rejecting the valid reservation: "+str(failed.get("error_code","")))
	check(game.snapshot()==before and changes==0 and FileAccess.get_sha256(path)==EXPECTED_SHA,"failed restoration preserves mode, old roster, all facts, bytes and signals")
	if not reached_write:
		saves.fail_next_write = false
		finish()
		return
	var retried: Dictionary = await game.execute_action_async(command)
	check(retried.success and game.state.daily_loop.mode=="sequential" and game.state.daily_loop.phase=="reception","same action retry restores ordered reception and saves its real new roster")
	if not retried.success:
		finish()
		return
	var committed: Dictionary = game.snapshot()
	var id: String = committed.daily_loop.arrival_ids[0]
	var instances: Dictionary = committed.divination.emergent_cases.instances
	check(not old_instances.has(id) and instances.get(id,{}).get("status")=="reserved" and instances.size()==old_instances.size()+1,"only the actual new ordinary first slot receives a fresh reservation")
	check(old_instances.keys().all(func(key: String)->bool:return instances.get(key)==old_instances[key]),"every old ready/reserved story and its immutable definition/proof remains exact")
	var replay: Dictionary = await game.execute_action_async(command)
	check(replay.success and replay.get("replayed",false) and game.snapshot()==committed and changes==1,"successful same-ID replay cannot replan or re-reserve another person")
	var entered: Dictionary = await game.execute_action_async({"type":"next_customer","action_id":"emergent_mode_recovery_enter"})
	check(entered.success and game.case_board_view().enabled and game.active_visit().arrival_id==id,"the restored ordinary customer immediately enters a real deduction case")
	var durable: Dictionary = saves.read_save(committed.save_id)
	check(durable.success and durable.state==game.snapshot() and FileAccess.get_sha256(FIXTURE)==EXPECTED_SHA,"durable restored case exactly matches the committed live case while the genuine source fixture stays unchanged")
	finish()

func on_changed() -> void:
	changes += 1

func finish() -> void:
	print("AICASE MODE RECOVERY: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

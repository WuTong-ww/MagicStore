extends SceneTree
## Real candidate/save/action tests. Network is absent; the local definition is
## verified by the same Store/CASE schema/catalog used by the shipping save path.
const Schema = preload("res://scripts/divination/case_schema.gd")
const Copy = preload("res://scripts/divination/emergent_case_copy.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0
var sequence := 0
var changes := 0
var listener_failures := 0
var capture_root := "res://.tools/r3-aicase"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("AICASE TRANSACTION FAIL: "+label)

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var action := {"type":kind,"action_id":"emergent_transaction_%d" % sequence}
	action.merge(fields,true)
	var reply: Dictionary = await game.execute_action_async(action)
	check(reply.get("success",false),kind+" / "+str(reply.get("message","")))
	return reply

func dump(label: String, snapshot: Dictionary) -> void:
	var file := FileAccess.open(capture_root+"/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot))
	file.close()
	if snapshot.has("schema_version"):
		var source: String = saves._path(snapshot.save_id)
		var destination := capture_root+"/"+label+"-envelope.json"
		check(DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(destination))==OK and FileAccess.get_sha256(source)==FileAccess.get_sha256(destination),"capture "+label+" is a byte-exact copy of the already saved action result")

func on_changed() -> void:
	changes += 1
	if game.state.is_empty():
		return
	# A listener reads the published directory synchronously during the signal.
	var current: Dictionary = game._divination.definitions_for(game.state)
	for instance: Dictionary in game.state.divination.emergent_cases.instances.values():
		if instance.status=="ready" and (not current.has(instance.case_id) or not game._divination.data.cases.has(instance.case_id)):
			listener_failures += 1
	var view: Dictionary = game.case_board_view()
	if view.get("enabled",false) and not current.has(view.id):
		listener_failures += 1

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root))
	saves.base_dir = capture_root+"/transactions/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(on_changed)
	check(Copy.validate(Copy.load_config()),"new messages JSON has a strict validator")
	for bad: Variant in [{},{"version":true,"invalid":"a","admitted":"b"},{"version":1,"invalid":"","admitted":"b"},{"version":1,"invalid":"a","admitted":"b","extra":1}]:
		check(not Copy.validate(bad),"messages reject invalid shape/version/text")
	# Isolate the ordinary day scheduling path. Fixed-story playthrough separately
	# retains its default enabled board and all five authored cases.
	game._divination.board_config.enabled = false
	game.story_config.rules.enabled = false
	if not (await act("new_game",{"name":"普通案件事务验收"})).success:
		finish()
		return
	check(game.state.schema_version==saves.CURRENT_SCHEMA and saves.validate_snapshot(game.snapshot()).success and game.state.divination.emergent_cases=={"version":1,"instances":{}},"fresh current save has an empty namespace and retains fixed Lin first")
	await act("read_morning_letters")
	while game.daily_loop_view().completed<game.daily_loop_view().total:
		if not (await act("next_customer")).success:
			finish()
			return
		await act("end_visit")
	await act("close_shop")
	game._divination.board_config.enabled = true
	if not (await act("next_day")).success:
		finish()
		return
	var id: String = game.state.daily_loop.arrival_ids[0]
	var reservation: Dictionary = game.state.divination.emergent_cases.instances.get(id,{})
	check(reservation.get("status")=="reserved" and game.state.people.arrivals[id].case_id==game.daily_loop_config.ordinary_case_id,"only the newly planned ordinary first visitor receives a reservation")
	check(game.state.divination.emergent_cases.instances.size()==1,"shopping guests never receive cases")
	await act("read_morning_letters")
	dump("reserved-fallback",game.snapshot())
	var before: Dictionary = game.snapshot()
	var memory_hash := Schema.definition_hash({"data":game._divination.data,"definitions":game._divination.case_definitions})
	var disk_hash := FileAccess.get_sha256(saves._path(before.save_id))
	var changes_before := changes
	var command := {"type":"next_customer","action_id":"emergent_fallback_retry"}
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED","first fallback action really reaches and fails the durable write")
	check(game.snapshot()==before and FileAccess.get_sha256(saves._path(before.save_id))==disk_hash and changes==changes_before,"failed fallback changes no state, bytes or visible signal")
	check(Schema.definition_hash({"data":game._divination.data,"definitions":game._divination.case_definitions})==memory_hash,"failed candidate does not pollute the live catalog")
	var binding: Dictionary = game._case_binding(before,id)
	var held: Dictionary = game._case_coordinator.selected_for(binding)
	check(not held.is_empty() and held.source.kind=="fallback","first fully verified fallback is privately held for retry")
	# A settings reset between attempts must not pick a different truth/source.
	game.configure_api("","","")
	check(game._case_coordinator.selected_for(binding)==held,"configuration reset retains the original immutable selection")
	var retried: Dictionary = await game.execute_action_async(command)
	check(retried.success,"same action retry commits its original complete fallback")
	if not retried.success:
		finish()
		return
	var committed: Dictionary = game.snapshot()
	var record: Dictionary = committed.divination.emergent_cases.instances[id]
	check(record.definition==held.payload.definition and record.proof==held.payload.proof and record.source==held.source,"durable case exactly matches the first selected definition/proof/source")
	check(game.case_board_view().enabled and game.case_board_view().id==record.case_id and game.active_visit().dialogue[0].text==record.definition.question,"ordinary customer really opens the standard CASE board and its public question")
	check(game._case_coordinator.selected_for(binding).is_empty(),"only a successful write retires the private selection")
	var count_after := changes
	var replay: Dictionary = await game.execute_action_async(command)
	check(replay.success and replay.get("replayed",false) and game.snapshot()==committed and changes==count_after,"same action replay creates no second person, case, signal or settlement")
	check(saves.read_save(committed.save_id).state==committed,"strict re-read reproduces the same durable definition and private world facts")
	dump("opened-fallback",committed)
	var catalog_test = load("res://tests/integration/emergent_catalog_glue.gd").new()
	var catalog_result: Dictionary = catalog_test.run(saves,game._divination,committed,id)
	checks += catalog_result.checks
	for failure: String in catalog_result.failures:
		check(false,"catalog / "+failure)
	var fixture: Dictionary = {"base_dir":saves.base_dir,"save_id":committed.save_id,"sha256":FileAccess.get_sha256(saves._path(committed.save_id)),"arrival_id":id}
	dump("transaction-receipt",fixture)
	check(listener_failures==0,"all synchronous state listeners see the already published matching CASE directory")
	finish()

func finish() -> void:
	print("AICASE TRANSACTIONS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

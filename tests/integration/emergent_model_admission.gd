extends SceneTree
## Uses the real full-definition codec, coordinator, Store, catalog and save
## action. Only the HTTP node and monotonic clock come from the wire test double.
const Mock = preload("res://tests/providers/case_generation_coordinator_mock.gd")
const Codec = preload("res://scripts/divination/full_case_codec_v1.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
const Config = preload("res://scripts/providers/case_transport_config.gd")
const Guards = preload("res://tests/integration/emergent_case_entry_guards.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0
var signals := 0
var receipt: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("AICASE MODEL ADMISSION FAIL: "+label)

func load_reserved() -> bool:
	var source := "res://.tools/r3-aicase/reserved-fallback-envelope.json"
	if not FileAccess.file_exists(source):
		check(false,"run real transaction target first to capture its durable reservation")
		return false
	var outer: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	var saved: Dictionary = JSON.parse_string(outer.payload)
	saves.base_dir = "res://.tools/r3-aicase/model-admission/"+game.make_id("run")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(saves._path(saved.save_id)))==OK and FileAccess.get_sha256(source)==FileAccess.get_sha256(saves._path(saved.save_id)),"reservation source is a byte-exact real saved envelope")
	var loaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":saved.save_id})
	check(loaded.success,"real load action restores the unchanged reserved ordinary customer")
	return loaded.success

func setup_wire() -> RefCounted:
	if game._case_coordinator!=null:
		game._case_coordinator.shutdown()
	var coordinator := Mock.ControlledCoordinator.new()
	game._case_coordinator = coordinator
	coordinator.case_ready.connect(game._case_ready)
	check(coordinator.configure(game,"https://case.invalid/v1","case_model","private_test_key",Config.load_config(),game._case_runtime.policy),"real coordinator is configured with a socket-free HTTP double")
	return coordinator

func dump(label: String, snapshot: Dictionary) -> void:
	var file := FileAccess.open("res://.tools/r3-aicase/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot))
	file.close()
	if snapshot.has("schema_version"):
		var source: String = saves._path(snapshot.save_id)
		var destination := "res://.tools/r3-aicase/"+label+"-envelope.json"
		check(DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(destination))==OK and FileAccess.get_sha256(source)==FileAccess.get_sha256(destination),"capture "+label+" copies the actual saved envelope byte for byte")

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func(): signals+=1)
	if not await load_reserved():
		finish()
		return
	var id: String = game.state.daily_loop.arrival_ids[0]
	var binding: Dictionary = game._case_binding(game.state,id)
	var context: Dictionary = game.EmergentStore.context_for(game.state,id,[],game._case_runtime.policy)
	var profile: Dictionary = game.state.people.profiles[binding.npc_id]
	var public_npc := {"name":profile.name,"role":profile.role}
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/divination/fixtures/full_definition_v1_golden.json"))
	var packet: Dictionary = Mock.new().callback_packet(golden.positive[0],context,public_npc)
	check(not packet.is_empty(),"a novel full-definition fixture rebinds and passes the real codec")
	if packet.is_empty():
		finish()
		return
	var coordinator: RefCounted = setup_wire()
	check(coordinator.enqueue(binding,context,public_npc),"nonblocking model job starts for the real saved ordinary reservation")
	var wire: RefCounted = coordinator.last_provider
	check(await Mock.new().started(game,wire),"fake wire receives a real constructed model request")
	var request: Dictionary = JSON.parse_string(wire.last_http.request_body)
	var user_message: Dictionary = JSON.parse_string(request.messages[1].content)
	var sent: Dictionary = user_message.context
	check(sent.size()==3 and sent.get("public_npc")==public_npc and sent.get("public_rumors")==[] and sent.get("binding")=={"case_id":binding.case_id,"npc_id":binding.npc_id},"request context is exactly name/role, verified public rumors and two technical bindings")
	var before: Dictionary = game.snapshot()
	var old_directory := Schema.definition_hash(game._divination.data)
	var old_disk := FileAccess.get_sha256(saves._path(before.save_id))
	var old_signals := signals
	saves.fail_next_write = true
	wire.last_http.respond(Mock.new().envelope({"version":1,"definition":packet.definition,"proof":packet.proof}))
	for frame: int in range(4):
		await process_frame
	check(game.snapshot()==before and FileAccess.get_sha256(saves._path(before.save_id))==old_disk and signals==old_signals,"actual asynchronous admission reaches a failed write without publishing any state")
	check(Schema.definition_hash(game._divination.data)==old_directory,"failed asynchronous model candidate leaves the live directory unchanged")
	var chosen: Dictionary = coordinator.selected_for(binding)
	check(not chosen.is_empty() and chosen.source.kind=="model" and chosen.payload.definition==packet.definition,"first validated novel definition is held after its failed admission")
	var action_id := "case_admit_"+Schema.definition_hash(binding)
	game.configure_api("","","")
	check(coordinator.selected_for(binding)==chosen,"settings reset cannot replace the selected model definition")
	var command := {"type":"admit_generated_case","action_id":action_id,"arrival_id":id}
	var committed: Dictionary = await game.execute_action_async(command)
	check(committed.success,"same internal admission action retries and saves the complete model definition")
	if not committed.success:
		finish()
		return
	var ready: Dictionary = game.snapshot()
	var instance: Dictionary = ready.divination.emergent_cases.instances[id]
	check(instance.definition==packet.definition and instance.proof==packet.proof and instance.source.kind=="model" and instance.expected_context==context,"model facts/proof/source remain byte-canonical the selected payload")
	check(saves.validate_snapshot(ready).success and saves.read_save(ready.save_id).state==ready,"real strict saved model snapshot revalidates and reloads")
	var replay: Dictionary = await game.execute_action_async(command)
	check(replay.success and replay.get("replayed",false) and game.snapshot()==ready,"same admission ID cannot overwrite or repeat a ready case")
	dump("planned-model",ready)
	var queued := ready.duplicate(true)
	var row: Dictionary = queued.people.arrivals[id]
	row.state="queued"
	row.deadline=game.People.MAX_INT
	check(game.People._physical_arrival(queued.people,game.people_config,row,int(queued.clock_minutes)),"same physical-arrival function constructs the pre-start candidate")
	var guard_result: Dictionary = Guards.new().run(ready,queued,game._divination,game.people_config,id)
	checks+=guard_result.checks
	for failure: String in guard_result.failures:
		check(false,"entry guard / "+failure)
	var entered: Dictionary = await game.execute_action_async({"type":"next_customer","action_id":"model_actual_entry"})
	check(entered.success and game.case_board_view().enabled and game.case_board_view().id==binding.case_id,"actual next-customer action opens the saved model case")
	check(game.active_visit().dialogue[0].text==packet.definition.question,"public opening uses the new question, not the archived placeholder")
	check(game._divination.talks(game.active_visit(),game.state.divination.cases[game.state.active_visit_id],int(game.state.clock_minutes),game.state).keys()==["clarify"],"before any question, free dialogue exposes no unasked dynamic answer")
	dump("opened-model",game.snapshot())
	receipt={"base_dir":saves.base_dir,"save_id":game.state.save_id,"sha256":FileAccess.get_sha256(saves._path(game.state.save_id)),"arrival_id":id,"source":"model","network":"fake HTTP node, real codec and save path"}
	dump("model-admission-receipt",receipt)
	await hanging_fallback(context,public_npc,packet)
	finish()

func hanging_fallback(context: Dictionary, public_npc: Dictionary, packet: Dictionary) -> void:
	if not await load_reserved():
		return
	var id: String = game.state.daily_loop.arrival_ids[0]
	var binding: Dictionary = game._case_binding(game.state,id)
	var coordinator: RefCounted = setup_wire()
	check(coordinator.enqueue(binding,context,public_npc),"a second actual reservation has a deliberately hanging model request")
	var wire: RefCounted = coordinator.last_provider
	if not await Mock.new().started(game,wire):
		check(false,"hanging fake wire starts in bounded frames")
		return
	var late: Callable = wire._job.callback
	var started := Time.get_ticks_msec()
	var entered: Dictionary = await game.execute_action_async({"type":"next_customer","action_id":"model_hangs_use_fallback"})
	var elapsed := Time.get_ticks_msec()-started
	check(entered.success and elapsed<int(Config.load_config().deadline_ms),"actual next-customer saves its fallback before the hanging model deadline")
	if not entered.success:
		return
	var committed: Dictionary = game.snapshot()
	check(committed.divination.emergent_cases.instances[id].source.kind=="fallback" and coordinator.status().pending==0,"actual fallback entry cancels transport and preserves the local source")
	var old_signals := signals
	late.call(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),Mock.new().envelope({"version":1,"definition":packet.definition,"proof":packet.proof}))
	for frame: int in range(2):
		await process_frame
	check(game.snapshot()==committed and signals==old_signals,"otherwise-valid complete late model reply cannot replace the saved fallback or emit a new state")

func finish() -> void:
	print("AICASE MODEL ADMISSION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

extends SceneTree
## UNRUN draft. Fake transport only; selection/job/admission/save are real GameState.
class LocalTransport extends RefCounted:
	signal job_ready(job_id: String, token: String, bundle: Dictionary, provenance: Dictionary)
	signal job_failed(job_id: String, token: String, code: String)
	const Generated = preload("res://scripts/people/generated_person.gd")
	var requests: Array = []
	func set_dialogue_busy(_value: bool) -> void:
		pass
	func enqueue(id: String, context: Dictionary, token: String) -> bool:
		requests.append({"id":id,"token":token,"context":Generated.request_context(context).duplicate(true)})
		# A provider is untrusted and may mutate its input; its copy must not own
		# GameState's authoritative local pair.
		if context.has("birth_identities"):
			context.birth_identities.person.name = "不得反填的名字"
		return true
	func shutdown() -> void:
		pass
const Generated = preload("res://scripts/people/generated_person.gd")
const Birth = preload("res://scripts/people/birth_identity.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0
var changes := 0
var sequence := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("NAMES TRANSACTIONS FAIL: "+label)

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var action := {"type":kind,"action_id":"names_transactions_"+str(sequence)}
	action.merge(fields,true)
	var result: Dictionary = await game.execute_action_async(action)
	check(result.success,kind+" / "+str(result.get("error_code","")))
	return result

func attach_transport(target: int = 1) -> LocalTransport:
	var provider := LocalTransport.new()
	game.people_generator = provider
	game.generation_config.ready_target = target
	provider.job_ready.connect(game._person_ready)
	provider.job_failed.connect(game._person_failed)
	return provider

func find_slot() -> String:
	for attempt: int in range(16):
		var ids: Array = game._generation_slots()
		if not ids.is_empty():
			return ids[0]
		if not (await act("next_day")).success:
			return ""
	return ""

func run() -> void:
	var generated_api := Generated.new()
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-names/transaction-saves/"+game.make_id("run")
	game.daily_loop_config.enabled = false
	game.configure_api("","","")
	game.set_people_generation_options(true)
	game.state_changed.connect(func():changes+=1)
	if not (await act("new_game",{"name":"出生身份真实事务"})).success:
		finish()
		return
	check(game.state.schema_version==saves.CURRENT_SCHEMA and game.state.schema_version>=13 and game.state.people.get("birth_identity_version")==1,"fresh current schema activates future births before its first day plan")
	if game.state.people.get("birth_identity_version")!=1:
		finish()
		return
	var slot: String = await find_slot()
	check(not slot.is_empty(),"actual legacy day planning supplies a genuine future ordinary slot")
	if slot.is_empty() or not generated_api.has_method("validate_birth_identities"):
		check(false,"locked wire helpers are available")
		finish()
		return
	var provider := attach_transport()
	game.pump_background_people(false,true)
	check(provider.requests.size()==1 and game._generation_jobs.size()==1,"real background pump selects one new local pair before transport")
	if provider.requests.size()!=1:
		finish()
		return
	var request: Dictionary = provider.requests[0]
	var id: String = request.id
	var token: String = request.token
	var job: Dictionary = game._generation_jobs[id]
	var pair: Dictionary = job.get("birth_identities",{}).duplicate(true)
	check(not Generated.validate_birth_identities(pair).is_empty() and pair==request.context.get("birth_identities"),"held local pair equals the validated public request pair")
	check(pair.person.name!="不得反填的名字" and pair.person.name!=pair.contact.name,"provider-side mutation cannot alter either local preselected record")
	check(request.context.identity_hash==Generated.identity_hash(pair) and ["save_id","seed","npc_id","generation_id","profiles","truth","api_key"].all(func(key:String)->bool:return not request.context.has(key)),"request contains only public identity locks, never local binding or private state")
	var before: Dictionary = game.snapshot()
	var public: Dictionary = game.people_view()
	var path: String = saves._path(before.save_id)
	var source_sha := FileAccess.get_sha256(path)
	var published := changes
	var swapped := {"person":pair.contact.duplicate(true),"contact":pair.person.duplicate(true)}
	var forged := Generated.offline_bundle_for_identities(id,swapped)
	var forged_source := Generated.offline_provenance_for_identities(id,swapped)
	check(not forged.is_empty(),"attack bundle is internally valid for a different locally legal pair")
	game._generation_ready = [{"job_id":id,"token":token,"bundle":forged,"provenance":forged_source}]
	var command := {"type":"admit_generated_person","action_id":"admit_"+id,"job_id":id,"slot_id":slot,"expected_identities":swapped}
	var rejected: Dictionary = await game.execute_action_async(command)
	check(not rejected.success and rejected.error_code=="ADMISSION_REJECTED" and game.snapshot()==before and game.people_view()==public and changes==published and FileAccess.get_sha256(path)==source_sha,"real admission rejects self-consistent forged bundle/action identities and trusts only the held local pair")
	game._generation_ready.clear()
	provider.job_failed.emit(id,token,"REVIEW_REJECTED")
	check(game._generation_jobs.has(id) and game._generation_jobs[id].birth_identities==pair and game._generation_ready.size()==1,"review failure queues an offline fallback without replacing the job or pair")
	var ready: Dictionary = game._generation_ready[0]
	check(ready.provenance.source=="offline" and ready.bundle.version==3 and ready.bundle.person.birth_identity==pair.person and ready.bundle.contact.birth_identity==pair.contact,"offline ready bundle preserves both exact program identities")
	provider.job_failed.emit(id,token,"TIMEOUT")
	provider.job_ready.emit(id,token,forged,forged_source)
	check(game._generation_ready.size()==1 and game._generation_ready[0]==ready and provider.requests.size()==1,"duplicate failure or late forged response cannot replace the frozen ready candidate or request again")
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	print("NAMES TRANSACTION SAVE RESULT: ",JSON.stringify(failed))
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED" and game.snapshot()==before and game.people_view()==public and changes==published and FileAccess.get_sha256(path)==source_sha,"real failing admission save publishes no new name, skin, profiles, relations or plan")
	check(game._generation_jobs[id].birth_identities==pair and game._generation_ready[0]==ready,"save failure retains the same local pair and checked ready bundle")
	await game._admit_next_person()
	var committed: Dictionary = game.snapshot()
	var ids := Generated._ids(id)
	check(committed.state_version==before.state_version+1 and changes==published+1 and committed.processed_actions.has(command.action_id),"actual async admission retry writes and publishes one stable action")
	check(game._generation_jobs.is_empty() and game._generation_ready.is_empty() and provider.requests.size()==1,"successful retry retires only that job, without generating replacement identities")
	if not committed.people.profiles.has(ids.npc_id) or not committed.people.profiles.has(ids.contact_id):
		# Keep the real failure above, but never index missing data and leave the
		# SceneTree suspended forever after a failed transaction.
		finish()
		return
	for member: String in ["person","contact"]:
		var profile: Dictionary = committed.people.profiles[ids.npc_id if member=="person" else ids.contact_id]
		check(profile.birth_identity==pair[member] and profile.name==pair[member].name and profile.cultural_origin==pair[member].cultural_origin and profile.appearance.colors.skin==pair[member].skin_id,"persisted admitted identity matches the local program record / "+member)
	check(saves.read_save(committed.save_id).state==committed,"actual schema13 durable state contains both original records")
	published = changes
	var replayed: Dictionary = await game.execute_action_async(command)
	check(replayed.success and replayed.get("replayed",false) and game.snapshot()==committed and changes==published,"same-ID replay wins even after local job retirement")
	check((await act("load_game",{"save_id":committed.save_id})).success and game.snapshot()==committed,"real reload preserves the entire committed identity/provenance payload")
	provider.job_ready.emit(id,token,ready.bundle,ready.provenance)
	check(game._generation_jobs.is_empty() and game._generation_ready.is_empty(),"late response after reload/epoch reset cannot create another person")
	slot = await find_slot()
	check(not slot.is_empty(),"a second genuine slot exists for explicit cancellation coverage")
	if not slot.is_empty():
		provider = attach_transport(2)
		game.pump_background_people(false,true)
		if not provider.requests.is_empty():
			request = provider.requests[0]
			id = request.id
			token = request.token
			pair = game._generation_jobs[id].birth_identities.duplicate(true)
			provider.job_ready.emit(id,token,Generated.offline_bundle_for_identities(id,pair),Generated.offline_provenance_for_identities(id,pair))
			before = game.snapshot()
			provider.job_failed.emit(id,token,"CANCELLED")
			check(not game._generation_jobs.has(id) and game._generation_ready.is_empty() and game.snapshot()==before,"explicit cancellation retires even a ready candidate without fallback or save")
		else:
			check(false,"second transport receives the next real local job")
	game.daily_loop_config.enabled = true
	await act("new_game",{"name":"默认顺序出生策略"})
	provider = attach_transport()
	before = game.snapshot()
	game.pump_background_people(false,true)
	check(provider.requests.is_empty() and game._generation_jobs.is_empty() and game.snapshot()==before,"default sequential mode never reopens the real-time person pump")
	var ordinary: Array = game.state.people.profiles.values().filter(func(profile:Dictionary)->bool:return profile.get("origin")=="random_first" or profile.get("template_id")=="ordinary_contact_v1")
	check(not ordinary.is_empty() and ordinary.all(func(profile:Dictionary)->bool:return Birth.record_valid(profile.get("birth_identity"))),"fresh sequential day births already have records because the marker preceded plan")
	finish()

func finish() -> void:
	print("NAMES TRANSACTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

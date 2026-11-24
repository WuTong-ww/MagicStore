extends SceneTree
## UNRUN draft. Real next_day candidate rejection; no source JSON is edited.
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
		printerr("NAMES BIRTH FAILURE: "+label)

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-names/birth-failure-saves/"+game.make_id("run")
	game.daily_loop_config.enabled = false
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func():changes+=1)
	check(game.people_config.get("birth_identity") is Dictionary and not game.people_config.get("birth_identity",{}).is_empty(),"expanded real People config exposes the validated birth policy")
	if failures:
		finish()
		return
	var good: Dictionary = game.people_config.birth_identity.duplicate(true)
	for kind: String in ["bad_config","exhausted"]:
		game.people_config.birth_identity = good.duplicate(true)
		var created: Dictionary = await game.execute_action_async({"type":"new_game","action_id":"names_birth_new_"+kind,"name":"出生失败事务"})
		check(created.success and game.state.people.get("birth_identity_version")==1,"real fresh game enables births before day planning / "+kind)
		if not created.success:
			continue
		var problem := good.duplicate(true)
		if kind=="bad_config":
			problem.rules.groups.local = -1
			check(not Birth.config_valid(problem),"fixture is genuinely invalid configuration")
		else:
			# Valid supplied resolved config: its local pool has one legal name.
			# Lin already owns it, so bounded complete scanning cannot invent one.
			problem.rules.groups = {"local":1,"foreign":0,"mixed":0}
			problem.local_surnames = ["林"]
			problem.local_given_names = ["照晚"]
			check(Birth.config_valid(problem) and Birth.propose({"save_id":game.state.save_id,"seed":game.state.people.seed,"npc_id":"names_exhaustion_witness"},problem,["林照晚"]).is_empty(),"valid resolved policy really exhausts its complete pool instead of using a fake selector")
		game.people_config.birth_identity = problem
		var reached := false
		for attempt: int in range(16):
			sequence += 1
			var action := {"type":"next_day","action_id":"names_birth_failure_"+str(sequence)}
			var before: Dictionary = game.snapshot()
			var before_view: Dictionary = game.people_view()
			var path: String = saves._path(before.save_id)
			var disk_sha := FileAccess.get_sha256(path)
			var published := changes
			var result: Dictionary = await game.execute_action_async(action)
			if result.success:
				var new_ordinary: Array = game.state.people.profiles.keys().filter(func(id:Variant)->bool:return not before.people.profiles.has(id) and game.state.people.profiles[id].get("template_id") in ["ordinary_v1","ordinary_contact_v1"])
				check(new_ordinary.is_empty(),"a zero-ordinary day may advance, but never silently admits an unlocked ordinary birth / "+kind)
				continue
			reached = true
			check(game.snapshot()==before and game.people_view()==before_view and changes==published and FileAccess.get_sha256(path)==disk_sha,"actual invalid/exhausted birth candidate is rejected without any state, names, plans, display or file leak / "+kind)
			check(not game.state.processed_actions.has(action.action_id),"rejected birth action does not consume its retry ID / "+kind)
			game.people_config.birth_identity = good.duplicate(true)
			var retried: Dictionary = await game.execute_action_async(action)
			check(retried.success,"same failed action ID retries after restoring valid data / "+kind)
			if not retried.success:
				break
			var committed: Dictionary = game.snapshot()
			var births: Array = committed.people.profiles.keys().filter(func(id:Variant)->bool:return not before.people.profiles.has(id) and committed.people.profiles[id].get("template_id") in ["ordinary_v1","ordinary_contact_v1"])
			check(not births.is_empty() and births.all(func(id:Variant)->bool:return Birth.record_valid(committed.people.profiles[id].get("birth_identity"))),"successful retry commits real locked births rather than an empty day / "+kind)
			check(changes==published+1 and saves.read_save(committed.save_id).state==committed,"restored retry writes and publishes once / "+kind)
			published = changes
			var replayed: Dictionary = await game.execute_action_async(action)
			check(replayed.success and replayed.get("replayed",false) and game.snapshot()==committed and changes==published,"same-ID replay never retries selection or creates another birth / "+kind)
			var reloaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":committed.save_id})
			check(reloaded.success and game.snapshot()==committed,"real reload keeps the successfully selected identities / "+kind)
			break
		check(reached,"a real ordinary-birth day reaches the failing validation boundary / "+kind)
	game.people_config.birth_identity = good
	finish()

func finish() -> void:
	print("NAMES BIRTH FAILURES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

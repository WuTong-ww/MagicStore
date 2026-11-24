extends SceneTree
## Real new_game/save boundaries. No production save or authored fact is changed.
const Appearance = preload("res://scripts/people/appearance.gd")
const Schema = preload("res://scripts/divination/case_schema.gd")
var appearance_api := Appearance.new()
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
		printerr("LIN TRANSACTIONS FAIL: "+label)

func command(kind: String, extra: Dictionary = {}) -> Dictionary:
	sequence += 1
	var value := {"type":kind,"action_id":"lin_transactions_"+str(sequence)}
	value.merge(extra,true)
	return value

func act(kind: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = await game.execute_action_async(command(kind,extra))
	check(result.success,kind+" / "+str(result.get("message","")))
	return result

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/r3-lin/transaction-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func():changes+=1)
	check(appearance_api.has_method("fixed_npc_appearance"),"fresh appearance lookup exists")
	if failures:
		finish()
		return
	var fixed: Dictionary = appearance_api.call("fixed_npc_appearance","npc_lin")
	var definition: Dictionary = Schema.load_all(game._divination.data).fixed_invitation
	var invitation_sha := FileAccess.get_sha256("res://data/divination.json")
	var original_definition_hash := Schema.definition_hash(definition)
	if not (await act("new_game",{"name":"固定外观第一档"})).success:
		finish()
		return
	var first_id: String = game.state.save_id
	check(game.state.schema_version==saves.CURRENT_SCHEMA and game.state.people.profiles.npc_lin.appearance==fixed,"first new save durably uses the complete fixed A4 selection in the current schema")
	check(saves.read_save(first_id).state==game.snapshot(),"appearance is part of the actual full new-game write")
	if not (await act("read_morning_letters")).success or not (await act("next_customer")).success:
		finish()
		return
	check_first(definition,original_definition_hash)
	var committed: Dictionary = game.snapshot()
	var first_sha := FileAccess.get_sha256(saves._path(first_id))
	var public_before: Dictionary = game.divination_view()
	var published := changes
	var retry := command("new_game",{"name":"固定外观第二档"})
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(retry)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED","new-game appearance reaches the real failing persistence boundary")
	check(game.snapshot()==committed and game.divination_view()==public_before and changes==published,"failed new candidate never publishes its identity, face or state")
	check(saves.list_saves().size()==1 and FileAccess.get_sha256(saves._path(first_id))==first_sha,"failed new game creates no committed save and leaves the old file bytes untouched")
	var result: Dictionary = await game.execute_action_async(retry)
	check(result.success,"same failed new_game action ID may retry")
	if not result.success:
		finish()
		return
	var second_id: String = game.state.save_id
	check(second_id!=first_id and game.state.people.profiles.npc_lin.appearance==fixed and saves.list_saves().size()==2,"independent save IDs still receive the exact same authored face")
	check(changes==published+1 and saves.read_save(second_id).state==game.snapshot(),"successful new-game retry writes and publishes exactly one candidate")
	# Historical new_game currently bypasses processed_actions. Do not claim it
	# replays idempotently; exercise the normal saved action replay contract below.
	await act("read_morning_letters")
	await act("next_customer")
	check_first(definition,original_definition_hash)
	var appearance_before: Dictionary = game.state.people.profiles.npc_lin.appearance.duplicate(true)
	var action := command("set_free_question",{"enabled":true})
	committed = game.snapshot()
	var path: String = saves._path(second_id)
	var before_sha := FileAccess.get_sha256(path)
	published = changes
	saves.fail_next_write = true
	failed = await game.execute_action_async(action)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED" and game.snapshot()==committed and changes==published and FileAccess.get_sha256(path)==before_sha,"normal failed action leaks no face, preference, state or disk change")
	result = await game.execute_action_async(action)
	check(result.success and game.state.people.profiles.npc_lin.appearance==appearance_before,"normal same-ID retry commits without regenerating Lin")
	committed = game.snapshot()
	published = changes
	var replayed: Dictionary = await game.execute_action_async(action)
	check(replayed.success and replayed.get("replayed",false) and game.snapshot()==committed and changes==published,"normal same-ID replay is exact and does not publish or change the fixed face")
	check((await act("load_game",{"save_id":second_id})).success and game.snapshot()==committed,"real disk reload restores the full saved state including identical fixed parts")
	check((await act("load_game",{"save_id":first_id})).success and game.state.people.profiles.npc_lin.appearance==fixed and FileAccess.get_sha256(saves._path(first_id))==first_sha,"opening the independent first save retains its face and exact original bytes")
	check(FileAccess.get_sha256("res://data/divination.json")==invitation_sha and Schema.definition_hash(Schema.load_all(game._divination.data).fixed_invitation)==original_definition_hash,"the test and appearance actions never change invitation JSON or deduction definition")
	finish()

func check_first(definition: Dictionary, expected_hash: String) -> void:
	var visit: Dictionary = game.active_visit()
	var case: Dictionary = game.state.divination.cases[visit.visit_id]
	check(game.daily_loop_view().day==1 and visit.npc_id=="npc_lin" and visit.day==0,"both real first-day active visits belong to Lin")
	var active_id: String = game.state.daily_loop.active_arrival_id
	var active_row: Dictionary = game.state.people.arrivals.get(active_id,{})
	check(active_row.get("state")=="in_service" and active_row.get("daily_loop_index")==0 and active_row.get("npc_id")=="npc_lin","first appointment remains index zero")
	check(case.case_id=="invitation" and case.board.definition_id==definition.id and case.board.hash==expected_hash,"the actual original invitation and board definition are unchanged")
	check(case.world_facts==definition.truth and not game.case_board_view().has("truth"),"private invitation facts remain exact and absent from the public board")
	var config := Appearance.load_config()
	for mood: String in config.moods:
		var rows := Appearance.layer_records(game.state.people.profiles.npc_lin.appearance,mood,config)
		check(rows.size()==config.layer_order.size() and rows.all(func(row:Dictionary)->bool:return row.layer!="preset" and not str(row.path).contains("assets/portraits/npc_lin")),"every mood uses the same fixed A4 identity / "+mood)

func finish() -> void:
	print("LIN TRANSACTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

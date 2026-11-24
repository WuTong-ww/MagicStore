extends SceneTree
## Six bounded real saved routes maximum. No state/truth/card/energy injection.
const Schema = preload("res://scripts/divination/case_schema.gd")
var game: Node
var saves: Node
var checks := 0
var failures := 0
var sequence := 0
var changes := 0
var run_id := ""
var route_key := ""
var run_root := ""
var branch_count := 0
var retry_exercised := false
var receipt: Dictionary={"sources":{},"routes":[]}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("AICASE ROUTES FAIL: "+route_key+" / "+label)
	return ok

func action(kind: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var command := {"type":kind,"action_id":"aicase_route_%s_%s_%d" % [run_id,route_key,sequence]}
	command.merge(fields,true)
	return command

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var reply: Dictionary=await game.execute_action_async(action(kind,fields))
	check(reply.get("success",false),kind+" / "+str(reply.get("error_code",""))+" / "+str(reply.get("message","")))
	return reply

func source_meta(kind: String) -> Dictionary:
	var path := "res://.tools/r3-aicase/opened-"+kind+"-envelope.json"
	if not check(FileAccess.file_exists(path),"required original transaction envelope exists: "+path):
		return {}
	var parsed := JSON.new()
	var ok: bool=parsed.parse(FileAccess.get_file_as_string(path))==OK
	if not check(ok and parsed.data is Dictionary and parsed.data.get("payload") is String,"transaction artifact is an original save envelope"):
		return {}
	var payload := JSON.new()
	ok=payload.parse(parsed.data.payload)==OK
	if not check(ok and payload.data is Dictionary and saves._safe_id(payload.data.get("save_id")),"original envelope has a legal actual save ID"):
		return {}
	return {"kind":kind,"path":path,"sha256":FileAccess.get_sha256(path),"bytes":FileAccess.get_file_as_bytes(path).size(),"save_id":payload.data.save_id}

func load_route(meta: Dictionary, index: int) -> bool:
	route_key=meta.kind+"_advice_"+str(index)
	branch_count += 1
	if not check(branch_count<=6,"route count stays within six independent branches"):
		return false
	saves.base_dir=run_root+"/"+route_key
	var directory := ProjectSettings.globalize_path(saves.base_dir)
	if not check(DirAccess.make_dir_recursive_absolute(directory)==OK,"independent route save directory is created"):
		return false
	var target: String=saves._path(meta.save_id)
	if not check(not FileAccess.file_exists(target),"route starts without a previous writable save"):
		return false
	var source_absolute := ProjectSettings.globalize_path(meta.path)
	var target_absolute := ProjectSettings.globalize_path(target)
	if not check(DirAccess.copy_absolute(source_absolute,target_absolute)==OK,"copy the real original envelope bytes"):
		return false
	if not check(FileAccess.get_file_as_bytes(target)==FileAccess.get_file_as_bytes(meta.path) and FileAccess.get_sha256(target)==meta.sha256,"route copy is byte-for-byte identical before real load"):
		return false
	var read: Dictionary=saves.read_save(meta.save_id)
	if not check(read.get("success",false),"actual SaveService validates the copied original envelope"):
		return false
	if not (await act("load_game",{"save_id":meta.save_id})).get("success",false):
		return false
	return check(game.snapshot()==read.state and FileAccess.get_sha256(target)==meta.sha256,"current-schema load retains exact state/card order and writes no bytes")

func immutable(binding: Dictionary, record: Dictionary, visit_id: String, facts: Dictionary, order: Array) -> bool:
	var snapshot: Dictionary=game.snapshot()
	var current: Dictionary=snapshot.get("divination",{}).get("emergent_cases",{}).get("instances",{}).get(binding.arrival_id,{})
	var case: Dictionary=snapshot.get("divination",{}).get("cases",{}).get(visit_id,{})
	var valid: bool=current==record and case.get("world_facts")==facts and case.get("board",{}).get("card_order")==order
	return check(valid,"saved definition/proof/context/source/hashes, original facts and shuffled card order remain exact")

func close_with_retry(advice_id: String) -> bool:
	var command: Dictionary=action("case_close",{"advice_id":advice_id})
	var before: Dictionary=game.snapshot()
	var view: Dictionary=game.case_board_view()
	var path: String=saves._path(before.save_id)
	var sha := FileAccess.get_sha256(path)
	var catalog_hash := Schema.definition_hash({"data":game._divination.data,"definitions":game._divination.case_definitions,"bindings":game._divination.verified_bindings})
	var count := changes
	saves.fail_next_write=true
	var failed: Dictionary=await game.execute_action_async(command)
	var reached_write: bool=not failed.get("success",true) and failed.get("error_code")=="SAVE_WRITE_FAILED"
	check(reached_write,"closure reaches the actual failing durable write")
	if not reached_write:
		saves.fail_next_write=false
		return false
	if not check(game.snapshot()==before and game.case_board_view()==view and changes==count and FileAccess.get_sha256(path)==sha and Schema.definition_hash({"data":game._divination.data,"definitions":game._divination.case_definitions,"bindings":game._divination.verified_bindings})==catalog_hash,"failed closure publishes no state, board, catalog, reward or disk mutation"):
		return false
	var retried: Dictionary=await game.execute_action_async(command)
	if not check(retried.get("success",false),"same closure action ID retries successfully"):
		return false
	var committed: Dictionary=game.snapshot()
	var durable: Dictionary=saves.read_save(committed.save_id)
	if not check(changes==count+1 and durable.get("success",false) and durable.state==committed,"successful retry persists and publishes the complete closure exactly once"):
		return false
	var committed_sha := FileAccess.get_sha256(path)
	count=changes
	var replay: Dictionary=await game.execute_action_async(command)
	if not check(replay.get("success",false) and replay.get("replayed",false) and game.snapshot()==committed and changes==count and FileAccess.get_sha256(path)==committed_sha,"exact closure replay repeats no state, clock, reward, signal or write"):
		return false
	retry_exercised=true
	return true

func finish_day() -> bool:
	if not (await act("end_visit")).get("success",false):
		return false
	var loop: Dictionary=game.daily_loop_view()
	var remaining: int=int(loop.total)-int(loop.completed)
	if not check(remaining>=0 and remaining<=int(game.daily_loop_config.guests_max)-1,"remaining roster has a bounded number of shopping visitors"):
		return false
	for _index: int in range(remaining):
		var snapshot: Dictionary=game.snapshot()
		var progress: Dictionary=snapshot.daily_loop
		var id: String=progress.arrival_ids[int(progress.cursor)]
		var row: Dictionary=snapshot.people.arrivals[id]
		if not check(row.get("intent")=="shopping" and row.get("daily_kind")=="commission","every remaining visitor is the original saved shopping slot"):
			return false
		if not (await act("next_customer")).get("success",false):
			return false
		if not check(not game.case_board_view().get("enabled",false),"shopping slot does not acquire another deduction case"):
			return false
		if not (await act("end_visit")).get("success",false):
			return false
	if not check(int(game.daily_loop_view().completed)==int(game.daily_loop_view().total),"real original roster is completely served"):
		return false
	for kind: String in ["close_shop","next_day","read_morning_letters"]:
		if not (await act(kind)).get("success",false):
			return false
	return true

func play_route(meta: Dictionary, advice_id: String, wrong: bool) -> bool:
	var snapshot: Dictionary=game.snapshot()
	var visit: Dictionary=game.active_visit()
	var visit_id: String=str(visit.get("visit_id",""))
	var case: Dictionary=snapshot.get("divination",{}).get("cases",{}).get(visit_id,{})
	var arrival_id: String=str(visit.get("arrival_id",""))
	var record: Dictionary=snapshot.get("divination",{}).get("emergent_cases",{}).get("instances",{}).get(arrival_id,{})
	var definitions: Dictionary=game._divination.definitions_for(snapshot)
	var definition: Dictionary=definitions.get(case.get("board",{}).get("definition_id"),{})
	if not check(not definition.is_empty() and record.get("status")=="ready" and record.get("source",{}).get("kind")==meta.kind and game.case_board_view().get("phase")=="questions","real opened envelope owns the expected saved case at its untouched question phase"):
		return false
	if not check(definition.deduction_slots.size()==3 and definition.questions.size()==3 and case.board.questions_asked.is_empty() and case.board.flipped_indices.is_empty() and case.board.attachments.is_empty(),"input is an original unopened three-slot CASE board"):
		return false
	var binding := {"save_id":snapshot.save_id,"arrival_id":arrival_id,"npc_id":visit.npc_id,"case_id":record.case_id}
	var facts: Dictionary=case.world_facts.duplicate(true)
	var order: Array=case.board.card_order.duplicate()
	for _round: int in range(3):
		var options: Array=game.case_board_view().get("questions",[]).filter(func(row: Dictionary)->bool:return row.get("enabled",false))
		if not check(not options.is_empty(),"a real public base question is available without resource edits"):
			return false
		if not (await act("case_question",{"question_id":options[0].id})).get("success",false):
			return false
	for card_index: int in range(3):
		var cards: Array=game.case_board_view().get("cards",[]).filter(func(row: Dictionary)->bool:return row.get("index")==card_index and row.get("enabled",false) and not row.get("revealed",true))
		if not check(cards.size()==1,"the original next base card is publicly available"):
			return false
		if not (await act("case_flip_card",{"card_index":card_index})).get("success",false):
			return false
	if not immutable(binding,record,visit_id,facts,order):
		return false
	for slot: Dictionary in definition.deduction_slots:
		var materials: Array=game.case_board_view().get("evidence",[]).filter(func(row: Dictionary)->bool:return slot.id in row.get("slot_ids",[]) and (row.get("kind")=="tool" or row.id in slot.unlock_evidence))
		if not check(not materials.is_empty(),"base public questions/cards provide lawful evidence for slot "+str(slot.id)):
			return false
		if not (await act("case_attach_evidence",{"slot_id":slot.id,"evidence_id":materials[0].id})).get("success",false):
			return false
		var public_slots: Array=game.case_board_view().get("slots",[]).filter(func(row: Dictionary)->bool:return row.id==slot.id)
		if not check(public_slots.size()==1,"deduction slot remains in the real public board"):
			return false
		var answers: Array=public_slots[0].candidates.filter(func(row: Dictionary)->bool:return row.get("enabled",false) and (row.id!=slot.correct_answer if wrong else row.id==slot.correct_answer))
		if not check(not answers.is_empty(),"requested all-wrong/all-correct answer is genuinely enabled"):
			return false
		if not (await act("case_choose_answer",{"slot_id":slot.id,"answer_id":answers[0].id})).get("success",false):
			return false
	var public_advice: Array=game.case_board_view().get("advice",[])
	for expected: Dictionary in definition.advice:
		var enabled: Array=public_advice.filter(func(row: Dictionary)->bool:return row.id==expected.id and row.get("enabled",false))
		if not check(enabled.size()==1,"every authored advice must be selectable; do not substitute a different branch: "+str(expected.id)):
			return false
	if not retry_exercised:
		if not await close_with_retry(advice_id):
			return false
	elif not (await act("case_close",{"advice_id":advice_id})).get("success",false):
		return false
	var expected_stars := 1 if wrong else 3
	case=game.snapshot().divination.cases[visit_id]
	if not check(game.case_board_view().get("closed",false) and int(case.get("stars",0))==expected_stars and case.board.closure.advice_id==advice_id,"actual closure stores the requested advice and computed 1/3-star result"):
		return false
	if not immutable(binding,record,visit_id,facts,order):
		return false
	var closed: Dictionary=game.snapshot()
	if not (await act("load_game",{"save_id":closed.save_id})).get("success",false):
		return false
	if not check(game.snapshot()==closed and int(game.case_board_view().get("stars",0))==expected_stars,"real closed-board reload retains exact state and stars"):
		return false
	if not await finish_day():
		return false
	var after: Dictionary=game.snapshot()
	case=after.divination.cases[visit_id]
	var report: Dictionary=case.event.feedback.report
	if not check(case.event.occurrence!="pending" and not report.is_empty() and report.get("event_id")==case.event.event_id and report.get("feedback_id") is String and not str(report.get("text","")).is_empty(),"next morning has the actual resolved event report for this original case"):
		return false
	var sender: String=after.people.profiles[case.npc_id].name
	if not check(after.daily_loop.letters.any(func(row: Dictionary)->bool:return row.get("feedback_id")==report.get("feedback_id") and row.get("event_id")==report.get("event_id") and row.get("text")==report.get("text")) and game.daily_loop_view().get("letters",[]).any(func(row: Dictionary)->bool:return row.get("name")==sender and row.get("text")==report.get("text")),"the saved morning letter binds this exact report ID and the real public letter discloses its matching text"):
		return false
	if not immutable(binding,record,visit_id,facts,order):
		return false
	var stored: Dictionary=saves.read_save(after.save_id)
	if not check(stored.get("success",false) and stored.state==after,"report and same immutable definition/source/hashes pass real durable re-read"):
		return false
	if not (await act("load_game",{"save_id":after.save_id})).get("success",false):
		return false
	if not check(game.snapshot()==after and FileAccess.get_sha256(meta.path)==meta.sha256,"report reload is exact and original captured envelope is never modified"):
		return false
	receipt.routes.append({"route":route_key,"source_kind":meta.kind,"advice_id":advice_id,"wrong":wrong,"stars":expected_stars,"definition_id":record.case_id,"definition_hash":record.definition_hash,"payload_hash":record.payload_hash,"source":record.source.duplicate(true),"feedback_id":report.feedback_id,"save_path":saves._path(after.save_id)})
	return true

func run() -> void:
	game=root.get_node("GameState")
	saves=root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(func():changes+=1)
	run_id=game.make_id("run")
	run_root="res://.tools/r3-aicase/routes/"+run_id
	var sources: Array=[]
	for kind: String in ["fallback","model"]:
		var meta: Dictionary=source_meta(kind)
		if meta.is_empty():
			finish()
			return
		sources.append(meta)
		receipt.sources[kind]=meta.duplicate(true)
	for meta: Dictionary in sources:
		var advice_ids: Array=[]
		for index: int in range(3):
			if index>0 and index>=advice_ids.size():
				break
			var start_checks := checks
			if not await load_route(meta,index):
				finish()
				return
			var snapshot: Dictionary=game.snapshot()
			var active: Dictionary=game.active_visit()
			var case: Dictionary=snapshot.divination.cases.get(active.get("visit_id"),{})
			var definition: Dictionary=game._divination.definitions_for(snapshot).get(case.get("board",{}).get("definition_id"),{})
			if not check(definition.get("advice") is Array and definition.advice.size()>=2 and definition.advice.size()<=3,"each real saved case exposes exactly two or three authored advice choices"):
				finish()
				return
			var current_ids: Array=definition.advice.map(func(row: Dictionary)->String:return str(row.id))
			if index==0:
				advice_ids=current_ids.duplicate()
			if not check(current_ids==advice_ids,"independent routes load the identical original advice domain"):
				finish()
				return
			if not await play_route(meta,str(advice_ids[index]),branch_count==1):
				finish()
				return
			print("AICASE ROUTE DETAIL %s checks=%d stars=%d advice=%s" % [route_key,checks-start_checks,receipt.routes.back().stars,advice_ids[index]])
	check(branch_count>=4 and branch_count<=6 and receipt.routes.size()==branch_count and retry_exercised,"all two-case advice branches and one real closure failure/retry/replay complete")
	finish()

func finish() -> void:
	if not run_root.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_root))
		var output := FileAccess.open(run_root+"/receipt.json",FileAccess.WRITE)
		if output!=null:
			receipt["checks"]=checks
			receipt["failures"]=failures
			receipt["branches"]=branch_count
			receipt["retry_exercised"]=retry_exercised
			output.store_string(JSON.stringify(receipt,"\t",true,true))
			output.close()
	print("AICASE ROUTES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

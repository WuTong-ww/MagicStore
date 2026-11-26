extends SceneTree
## Only the prelearned skill is an authored historical fixture. All acquisitions
## and money/time mutations below use actual asynchronous committed actions.

class RecordingProvider extends "res://scripts/providers/mock_dialogue_provider.gd":
	var requests: Array = []
	func request_reply(request: Dictionary) -> Dictionary:
		requests.append(request.duplicate(true))
		return super.request_reply(request)

var game: Node
var saves: Node
var recorder: RecordingProvider
var checks: int = 0
var failures: int = 0
var instance_id: String = ""
var npc_id: String = "npc_o_1_0"
var paid_ids: Array = []
var folder: String
var ui_states: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("PAST TRANSACTIONS FAIL: " + label)

func finish() -> void:
	if not ui_states.is_empty():
		var path := folder+"/ui-states/capture-states.json"
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify({"version":1,"complete":failures == 0 and ui_states.size() == 4,"source":"real committed G5 transaction flow; only the prelearned skill was authored","states":ui_states},"\t",true,true))
		file.close()
		print("PAST TRANSACTIONS STATES: "+path+" sha256="+FileAccess.get_sha256(path))
	if is_instance_valid(game):
		game.queue_free()
	print("PAST TRANSACTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func act(kind: String, values: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("past_action"),"expected_version":game.state.get("state_version",0)}
	action.merge(values,true)
	# Historical G5 fixed identity uses the preserved missing-ID CLI creation path.
	# Explicit TITLE creation idempotence has its separate title_creation.gd coverage.
	if kind == "new_game":
		action.erase("action_id")
	return await game.execute_action_async(action)

func disk_sha() -> String:
	return FileAccess.get_sha256(saves._path(game.state.save_id))

func run() -> void:
	saves = root.get_node("SaveService")
	folder = "res://.tools/g5/transaction-saves/run_"+str(Time.get_ticks_usec())
	saves.base_dir = folder
	# Load after autoloads are registered, as the existing economic fixture does.
	var fixture: Script = load("res://tests/past_lives/transaction_game.gd")
	game = fixture.new()
	root.add_child(game)
	game._divination.learning_config.debug_instant_learning = true
	# This historical transaction chain exercises the real-time reception mode.
	game.daily_loop_config.enabled = false
	game.configure_api("","","")
	game.set_people_generation_options(false)
	check((await act("new_game",{"name":"三世实际事务"})).success,"real new game derives the fixed legal save domain and G1 population naturally")
	if game.state.is_empty():
		finish()
		return
	check(game.state.get("schema_version") == SaveService.CURRENT_SCHEMA,"new transaction source uses current schema")
	if not await legacy_miss_branch():
		finish()
		return
	saves.base_dir = folder
	check((await act("new_game",{"name":"三世实际事务"})).success,"main positive chain starts from its own untouched real new game after the separate compatibility case")
	var authored: Dictionary = game.snapshot()
	authored.divination.skills.append("past")
	check(preload("res://tests/fixtures/legacy_learning.gd").install(authored),"explicit synthetic legacy capability baseline")
	check(saves.write_save(authored).success,"explicit authored prelearned skill fixture validates without changing people, plans or wallets")
	check((await act("load_game",{"save_id":authored.save_id})).success,"authored learning history is actually loaded")
	recorder = RecordingProvider.new()
	recorder.configure(game._divination.data.topics+game.content.topics)
	game.dialogue_provider = recorder
	check((await act("start_visit",{"npc_id":"npc_lin","case_id":"invitation","cause":"past"})).success,"an actual present-day visit is started while a client cannot choose trusted cause")
	var before: Dictionary = game.snapshot()
	var before_sha := disk_sha()
	var present: Dictionary = await act("quote_service",{"method_id":"past","option_id":"vision","payment":"coins"})
	check(not present.success and game.snapshot() == before and disk_sha() == before_sha,"present case refuses past fragments without a charge, binding or commit")
	check((await act("end_visit")).success and (await act("next_day")).success,"real calendar actions reach the next unmodified G1 day")
	var arrivals: Array = game.state.people.arrivals.values().filter(func(row: Dictionary) -> bool: return row.npc_id == npc_id and row.state == "planned")
	check(arrivals.size() == 1,"fixed legal source really contains the golden ordinary visitor; no arrival/profile is injected")
	if arrivals.size() != 1:
		finish()
		return
	var row: Dictionary = arrivals[0]
	while int(game.state.clock_minutes) < int(row.at):
		var waited: Dictionary = await act("wait",{"minutes":mini(180,int(row.at)-int(game.state.clock_minutes))})
		check(waited.success,"real wait reaches the existing visitor time")
		if not waited.success:
			finish()
			return
	var started: Dictionary = await act("start_arrival",{"arrival_id":row.arrival_id})
	check(started.success and game.active_visit().npc_id == npc_id and game.state.npcs[npc_id].coins == 60,"real ordinary arrival starts with the actual sixty-coin wallet")
	if not started.success:
		finish()
		return
	before = game.snapshot()
	before_sha = disk_sha()
	var no_artifact: Dictionary = await act("quote_service",{"method_id":"past","option_id":"vision","payment":"coins"})
	check(not no_artifact.success and game.snapshot() == before and disk_sha() == before_sha,"missing artifact clue refuses acquisition without an implicit binding or charge")
	check((await act("talk",{"topic_id":"archive","text":"这件旧物有什么线索？"})).success and "archive_stub" in game.active_visit().clue_ids,"actual NPC dialogue discloses the required old artifact")
	check(game._divination.has_method("quote_preview"),"production exposes a read-only actual-cost preview")
	if not game._divination.has_method("quote_preview"):
		finish()
		return
	before = game.snapshot()
	before_sha = disk_sha()
	var preview: Dictionary = game._divination.quote_preview(game.state,game.active_visit(),"past","vision")
	check(preview.get("available",false) and preview.get("cost") == {"coins":6,"energy":6,"minutes":15},"modern read-only preview uses the literal six/six/fifteen fee")
	check(game.snapshot() == before and disk_sha() == before_sha and not preview.has("past_line") and not preview.has("descriptor") and not preview.has("text"),"preview cannot bind, write or disclose unpaid content")
	var foreign_quote: Dictionary = await act("quote_service",{"instance_id":"forged_foreign_line","method_id":"past","option_id":"vision","payment":"coins"})
	check(not foreign_quote.success and game.snapshot() == before and disk_sha() == before_sha,"explicit foreign quote scope cannot silently bind and quote the actor's different line")
	if foreign_quote.success:
		finish()
		return
	await first_wallet_legacy_branch(before)
	var first_quote: String = game.make_id("first_quote")
	saves.fail_next_write = true
	var failed_quote: Dictionary = await act("quote_service",{"action_id":first_quote,"method_id":"past","option_id":"vision","payment":"coins"})
	check(not failed_quote.success and failed_quote.get("error_code") == "SAVE_WRITE_FAILED" and game.snapshot() == before and disk_sha() == before_sha,"failed quote save cannot expose or retain a binding: "+JSON.stringify(failed_quote))
	var quoted: Dictionary = await act("quote_service",{"action_id":first_quote,"method_id":"past","option_id":"vision","payment":"coins"})
	check(quoted.success,"same-ID quote retry commits the eligible ordinary binding: "+JSON.stringify(quoted))
	var progress: Dictionary = game.state.divination.get("past_lines",{})
	check(progress.get("instances",{}).size() == 1,"one actual quote commits exactly one stable line instance")
	if not quoted.success or progress.get("instances",{}).size() != 1:
		finish()
		return
	instance_id = progress.instances.keys()[0]
	check(progress.instances[instance_id].fragments.is_empty() and game.state.npcs[npc_id].coins == 60,"quote-only permanently binds without obtaining a fragment or charging money")
	check(not game.divination_view().past_line.available and not game.divination_view().quote.has("past_line"),"public quotation does not disclose the line or its private descriptor")
	seal_state("unknown")
	var quoted_state: Dictionary = game.snapshot()
	check((await act("quote_service",{"action_id":first_quote,"method_id":"past","option_id":"vision","payment":"coins"})).success and game.snapshot() == quoted_state,"quote replay cannot rebind or duplicate a service")
	var first_service: String = quoted.result.service_id
	await negative_payment_branches(quoted_state,first_service)
	check((await act("wait",{"minutes":5})).success,"an actual committed quote remains payable after a real five-minute wait")
	quoted_state = game.snapshot()
	var paid_action: String = game.make_id("first_paid")
	before_sha = disk_sha()
	saves.fail_next_write = true
	var failed_paid: Dictionary = await act("settle_service",{"action_id":paid_action,"service_id":first_service})
	check(not failed_paid.success and failed_paid.get("error_code") == "SAVE_WRITE_FAILED" and game.snapshot() == quoted_state and disk_sha() == before_sha,"failed payment save leaves both money and acquired fragments untouched: "+JSON.stringify(failed_paid))
	var initial_clock: int = game.state.clock_minutes
	var initial_energy: int = game.state.player.energy
	var settled: Dictionary = await act("settle_service",{"action_id":paid_action,"service_id":first_service})
	check(settled.success,"same-ID payment retry actually obtains the first fragment")
	if not settled.success:
		finish()
		return
	paid_ids.append(first_service)
	check(game.state.npcs[npc_id].coins == 54 and game.state.clock_minutes == initial_clock+15 and game.state.player.energy == initial_energy-6,"first committed payment has the exact real wallet, time and energy deltas")
	var committed: Dictionary = game.snapshot()
	var replay: Dictionary = await act("settle_service",{"action_id":paid_action,"service_id":first_service})
	check(replay.success and replay.get("replayed",false) and game.snapshot() == committed,"paid-service replay never transfers or reveals twice")
	check((await act("load_game",{"save_id":committed.save_id})).success and game.snapshot() == committed,"the same visit and binding survive an actual mid-line reload")
	check(game.divination_view().past_line.available and game.divination_view().past_line.fragments.size() == 1,"only the acquired first fragment becomes public after commit")
	seal_state("first_vision")
	before = game.snapshot()
	before_sha = disk_sha()
	var foreign: Dictionary = await act("interpret_past_line",{"instance_id":"forged_foreign_line","group_id":"g1","option_id":"g1_a","text":"不得借用别人的前世线。"})
	check(not foreign.success and game.snapshot() == before and disk_sha() == before_sha,"an explicit foreign line scope cannot silently create an interpretation on the actor's own line")
	if foreign.success:
		finish()
		return
	before = game.snapshot()
	before_sha = disk_sha()
	var blocked_next: Dictionary = await act("quote_service",{"method_id":"past","option_id":"vision","payment":"coins"})
	check(not blocked_next.success and game.snapshot() == before and disk_sha() == before_sha,"an already bound line cannot fallback to a legacy fragment when the next modern prerequisite is missing")
	check((await committed_retry("interpret_past_line",{"group_id":"g1","option_id":"g1_a","text":"这可能是一段被误读的旧约。"})).success,"record an actual player misinterpretation independently of the fragment")
	before = game.snapshot()
	before_sha = disk_sha()
	var premature: Dictionary = await act("verify_past_line",{"interpretation_id":interpretation_id("g1","g1_a")})
	check(not premature.success and game.snapshot() == before and disk_sha() == before_sha,"a vision or player interpretation alone cannot be used as independent verification")
	check(await pay("e1e","evidence"),"the first independent evidence is obtained by a real paid service")
	var wrong_id: String = interpretation_id("g1","g1_a")
	var wrong: Dictionary = await committed_retry("verify_past_line",{"interpretation_id":wrong_id})
	check(wrong.success and game.state.divination.past_lines.instances[instance_id].interpretations[wrong_id].status == "refuted","independent evidence actually refutes the saved wrong interpretation")
	seal_state("refuted")
	check((await act("interpret_past_line",{"group_id":"g1","option_id":"g1_b","text":"证物提示了另一种关系。"})).success,"a later correct interpretation does not replace the earlier mistaken record")
	var right: Dictionary = await act("verify_past_line",{"interpretation_id":interpretation_id("g1","g1_b")})
	check(right.success,"the first era's separate correct record is actually verified")
	check(await pay("e1echo","vision"),"verified first-era evidence unlocks a real echo through the existing vision option")
	check(await pay("e2v","vision"),"the second era vision has its own committed source")
	check((await act("interpret_past_line",{"group_id":"g2","option_id":"g2_a","text":"先把修桥的线索留作解释。"})).success,"record the second-era interpretation")
	check(await pay("e2e","evidence"),"the second era evidence is independently paid")
	check((await act("verify_past_line",{"interpretation_id":interpretation_id("g2","g2_a")})).success,"second-era interpretation is actually verified")
	check(await pay("e3v","vision"),"third era vision is reached without adding a new service option")
	check((await act("interpret_past_line",{"group_id":"g3","option_id":"g3_b","text":"药圃中的记号值得核对。"})).success,"record the third-era interpretation")
	check(await pay("e3e","evidence"),"third era evidence is independently paid")
	check((await act("verify_past_line",{"interpretation_id":interpretation_id("g3","g3_b")})).success,"third-era interpretation is actually verified")
	check(paid_ids.size() == 7 and game.state.npcs[npc_id].coins == 18 and game.state.clock_minutes == initial_clock+105 and game.state.player.energy == initial_energy-42,"seven real paid fragments leave sixty coins at eighteen and cost exactly 105 minutes/42 energy")
	var line: Dictionary = game.state.divination.past_lines.instances[instance_id]
	check(line.fragments.keys().size() == 7 and line.interpretations[wrong_id].status == "refuted" and line.interpretations.size() == 4,"seven tool fragments and all four distinct player interpretations persist separately")
	check(game.divination_view().past_line.rows.all(func(era: Dictionary) -> bool: return era.known),"all three eras become known after their actual paid fragments")
	seal_state("fully_verified")
	var request_count: int = recorder.requests.size()
	game.dialogue_provider = recorder
	check((await act("talk",{"topic_id":"archive","text":"我们再核对这件旧物。"})).success,"actual dialogue can continue after the cross-era progress")
	check(recorder.requests.size() == request_count+1,"privacy assertion inspects the actual newly issued model request")
	var request_text := JSON.stringify(recorder.requests.back())
	check(not request_text.contains("past_lines") and not request_text.contains("demo_three_eras") and not request_text.contains("definition_sha256"),"modern private line/selector/content-version data never enters the model request")
	negative_sources()
	committed = game.snapshot()
	check((await act("load_game",{"save_id":committed.save_id})).success and game.snapshot() == committed,"all fragments, wrong/correct records and exact paid source receipts survive reopening")
	finish()

func committed_retry(kind: String, values: Dictionary) -> Dictionary:
	var before: Dictionary = game.snapshot()
	var sha := disk_sha()
	var payload := values.duplicate(true)
	payload["action_id"] = game.make_id("past_write_retry")
	saves.fail_next_write = true
	var failed: Dictionary = await act(kind,payload)
	check(not failed.success and failed.get("error_code") == "SAVE_WRITE_FAILED" and game.snapshot() == before and disk_sha() == sha,"failed save leaves interpretation/verification and disk unpublished / "+kind)
	var result: Dictionary = await act(kind,payload)
	check(result.success,"same-ID retry commits the exact interpretation/verification / "+kind)
	var committed: Dictionary = game.snapshot()
	var replay: Dictionary = await act(kind,payload)
	check(replay.success and replay.get("replayed",false) and replay.result == result.result and game.snapshot() == committed,"same-ID replay never duplicates an interpretation or verification / "+kind)
	return result

func first_wallet_legacy_branch(positive: Dictionary) -> void:
	# Explicit separate low-wallet eligibility input, not money injected into
	# the real sixty-coin positive chain.
	var positive_folder: String = saves.base_dir
	var path: String = saves._path(positive.save_id)
	var sha := FileAccess.get_sha256(path)
	saves.base_dir = folder+"/first-wallet-legacy"
	var source := positive.duplicate(true)
	source.npcs[npc_id].coins = 41
	check(saves.write_save(source).success and (await act("load_game",{"save_id":source.save_id})).success,"isolated first-wallet fixture lowers only the initial wallet below the modern-line gate")
	var preview: Dictionary = game._divination.quote_preview(game.state,game.active_visit(),"past","vision")
	check(preview.available and preview.cost.get("coins") == 23,"forty-one coins can still preview the original legacy service when new-line eligibility is not met")
	var quote: Dictionary = await act("quote_service",{"method_id":"past","option_id":"vision","payment":"coins"})
	check(quote.success,"forty-one-coin initial eligibility failure does not remove the legacy quotation")
	if quote.success:
		var paid: Dictionary = await act("settle_service",{"service_id":quote.result.service_id})
		check(paid.success and game.state.npcs[npc_id].coins == 18 and game.state.divination.past_lines.instances.is_empty() and game.state.divination.past.has(npc_id),"the isolated fallback really pays twenty-three and keeps only legacy memory")
	saves.base_dir = positive_folder
	check(FileAccess.get_sha256(path) == sha and (await act("load_game",{"save_id":positive.save_id})).success and game.snapshot() == positive,"return from the isolated low-wallet branch to exact original source bytes")

func negative_payment_branches(positive: Dictionary, service_id: String) -> void:
	# These isolated, explicitly authored negative inputs only lower resources.
	# The positive sixty-coin source is neither credited nor edited; every return
	# loads its original bytes from its separate storage directory.
	var positive_folder: String = saves.base_dir
	var positive_path: String = saves._path(positive.save_id)
	var positive_sha := FileAccess.get_sha256(positive_path)
	for branch: String in ["low_wallet","low_energy","late_payment"]:
		saves.base_dir = folder+"/negative-"+branch
		var fixture := positive.duplicate(true)
		if branch == "low_wallet":
			fixture.npcs[npc_id].coins = 5
		elif branch == "low_energy":
			fixture.player.energy = 5
		check(saves.write_save(fixture).success,"isolated resource-negative source validates / "+branch)
		check((await act("load_game",{"save_id":fixture.save_id})).success,"actually load the isolated resource-negative branch / "+branch)
		if branch == "late_payment":
			var remaining: int = int(game.content.rules.closing_minute)-14-int(game.state.clock_minutes)%1440
			while remaining > 0:
				var step: int = mini(180,remaining)
				var waited: Dictionary = await act("wait",{"minutes":step})
				check(waited.success,"real wait reaches the insufficient payment-time boundary")
				if not waited.success:
					break
				remaining -= step
		var before: Dictionary = game.snapshot()
		var sha := disk_sha()
		var failed: Dictionary = await act("settle_service",{"service_id":service_id})
		var code: String = {"low_wallet":"NPC_FUNDS_LOW","low_energy":"ENERGY_LOW","late_payment":"NOT_ENOUGH_TIME"}[branch]
		check(not failed.success and failed.get("error_code") == code and game.snapshot() == before and disk_sha() == sha,"insufficient resources cannot charge, reveal or publish the quoted fragment / "+branch)
		check(game.state.divination.past_lines.instances[instance_id].fragments.is_empty(),"resource failure cannot invent an acquired fragment / "+branch)
		saves.base_dir = positive_folder
		check(FileAccess.get_sha256(positive_path) == positive_sha and (await act("load_game",{"save_id":positive.save_id})).success and game.snapshot() == positive,"return to the exact unmodified positive source, without injecting money or rerolling plans / "+branch)

func seal_state(tag: String) -> void:
	var source_path: String = saves._path(game.state.save_id)
	var source_sha := FileAccess.get_sha256(source_path)
	var destination := folder+"/ui-states/"+tag+".json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder+"/ui-states"))
	var bytes := FileAccess.get_file_as_bytes(source_path)
	var file := FileAccess.open(destination,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	check(FileAccess.get_sha256(destination) == source_sha and FileAccess.get_sha256(source_path) == source_sha,"UI source is an unchanged byte copy of the actual committed envelope / "+tag)
	var envelope: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	var saved: Dictionary = JSON.parse_string(envelope.payload)
	check(envelope.payload.sha256_text() == envelope.sha256 and saves.validate_snapshot(saved).success,"sealed UI envelope retains its real checksum and current source validation / "+tag)
	ui_states.append({"tag":tag,"path":destination,"sha256":source_sha,"bytes":bytes.size(),"save_id":game.state.save_id,"visit_id":game.state.active_visit_id,"npc_id":npc_id,"state_version":game.state.state_version,"clock_minutes":game.state.clock_minutes,"public_past_line_sha256":JSON.stringify(game.divination_view().past_line,"",true,true).sha256_text()})

func interpretation_id(group: String, option: String) -> String:
	for id: String in game.state.divination.past_lines.instances[instance_id].interpretations:
		var row: Dictionary = game.state.divination.past_lines.instances[instance_id].interpretations[id]
		if row.group_id == group and row.option_id == option:
			return id
	return "missing_interpretation"

func legacy_miss_branch() -> bool:
	# A separate real source uses the same legal save domain. This actual day0
	# visitor has the independent literal roll8656, beyond the 500/10000 gate.
	saves.base_dir = folder+"/legacy-miss"
	var authored: Dictionary = game.snapshot()
	authored.divination.skills.append("past")
	check(preload("res://tests/fixtures/legacy_learning.gd").install(authored),"explicit synthetic legacy-miss capability baseline")
	check(saves.write_save(authored).success and (await act("load_game",{"save_id":authored.save_id})).success,"separate legacy-miss source has only explicitly prelearned skill history")
	var target := "npc_o_0_0"
	var arrivals: Array = game.state.people.arrivals.values().filter(func(row: Dictionary) -> bool: return row.npc_id == target and row.state == "planned")
	check(arrivals.size() == 1,"the miss visitor exists in the real unmodified first-day G1 plan")
	if arrivals.size() != 1:
		return false
	var row: Dictionary = arrivals[0]
	while int(game.state.clock_minutes) < int(row.at):
		var waited: Dictionary = await act("wait",{"minutes":mini(180,int(row.at)-int(game.state.clock_minutes))})
		if not waited.success:
			check(false,"real wait reaches the separate miss visitor")
			return false
	check((await act("start_arrival",{"arrival_id":row.arrival_id})).success,"start the actual low-probability miss visitor")
	check((await act("talk",{"topic_id":"archive","text":"这件旧物有什么线索？"})).success,"real dialogue discloses the miss visitor's artifact")
	var preview: Dictionary = game._divination.quote_preview(game.state,game.active_visit(),"past","vision")
	check(preview.available and preview.cost.get("coins") == 23,"a first-time probability miss previews the preserved legacy twenty-three-coin service")
	var quote: Dictionary = await act("quote_service",{"method_id":"past","option_id":"vision","payment":"coins"})
	check(quote.success,"a first-time probability miss still quotes the original past service")
	if not quote.success:
		return false
	var service: Dictionary = game.state.divination.cases[game.state.active_visit_id].services[quote.result.service_id]
	check(not service.has("past_line") and service.payment == {"kind":"coins","amount":23} and game.state.divination.past_lines.instances.is_empty(),"miss quotation neither binds a modern instance nor silently changes the original fee")
	var paid: Dictionary = await act("settle_service",{"service_id":quote.result.service_id})
	check(paid.success and game.state.npcs[target].coins == 37 and game.state.divination.past.has(target) and game.state.divination.past_lines.instances.is_empty(),"legacy miss payment follows the real sixty-to-thirty-seven wallet and old memory path")
	return paid.success

func pay(fragment_id: String, option: String) -> bool:
	var quote: Dictionary = await act("quote_service",{"method_id":"past","option_id":option,"payment":"coins"})
	check(quote.success,"quote actual next fragment / "+fragment_id)
	if not quote.success:
		return false
	var paid: Dictionary = await act("settle_service",{"service_id":quote.result.service_id})
	check(paid.success,"settle actual next fragment / "+fragment_id)
	if not paid.success:
		return false
	paid_ids.append(quote.result.service_id)
	var service: Dictionary = game.state.divination.cases[game.state.active_visit_id].services[quote.result.service_id]
	check(service.get("past_line",{}).get("fragment_id") == fragment_id and service.payment == {"kind":"coins","amount":6} and service.minutes == 15 and service.energy == 6,"literal fragment and frozen price match the committed service / "+fragment_id)
	return service.get("past_line",{}).get("fragment_id") == fragment_id

func negative_sources() -> void:
	var committed: Dictionary = game.snapshot()
	var broken: Dictionary = committed.duplicate(true)
	broken.divination.past_lines.instances[instance_id].fragments.erase("e1v")
	check(not saves.validate_snapshot(broken).success,"a paid modern service cannot lose its required reverse fragment source")
	broken = committed.duplicate(true)
	broken.divination.past_lines.instances[instance_id].fragments.e1e.service_id = paid_ids[0]
	check(not saves.validate_snapshot(broken).success,"independent evidence cannot borrow a vision's paid service")
	broken = committed.duplicate(true)
	broken.divination.cases[game.state.active_visit_id].services[paid_ids[0]].past_line.kind = "echo"
	check(not saves.validate_snapshot(broken).success,"a service descriptor cannot reinterpret the acquired fragment kind")
	broken = committed.duplicate(true)
	broken.divination.cases[game.state.active_visit_id].erase("cause")
	check(not saves.validate_snapshot(broken).success,"cause deletion cannot turn a modern service into a legacy oracle")
	broken = committed.duplicate(true)
	broken.divination.erase("past_lines")
	check(not saves.validate_snapshot(broken).success,"namespace deletion cannot conceal modern paid sources")
	broken = committed.duplicate(true)
	var wrong: String = interpretation_id("g1","g1_a")
	broken.divination.past_lines.instances[instance_id].interpretations[wrong].status = "verified"
	check(not saves.validate_snapshot(broken).success,"status cannot be forged independently of the actual evidence verdict")
	broken = committed.duplicate(true)
	broken.divination.past_lines.instances[instance_id].interpretations[wrong].verification.evidence_fragment_ids = ["e1echo"]
	check(not saves.validate_snapshot(broken).success,"an echo is not an independent evidence receipt")
	broken = committed.duplicate(true)
	broken.divination.past_lines.instances.clear()
	for case: Dictionary in broken.divination.cases.values():
		for service: Dictionary in case.services.values():
			service.erase("past_line")
			service.result.erase("past_line")
	for reply: Dictionary in broken.processed_actions.values():
		if reply.result.has("service_result"):
			reply.result.service_result.erase("past_line")
	# Remove interpretation actions too: this attacks the surviving paid sources,
	# not merely an orphaned new-action reference that independently looks modern.
	for id: String in broken.processed_actions.keys():
		if broken.processed_actions[id].action_type in ["interpret_past_line","verify_past_line"]:
			broken.processed_actions.erase(id)
	check(not saves.validate_snapshot(broken).success,"removing every new marker cannot downgrade seven six-coin paid fragments into untracked legacy past services")
	broken.schema_version = 8
	broken.divination.erase("past_lines")
	for case: Dictionary in broken.divination.cases.values():
		case.erase("cause")
	check(not saves.validate_snapshot(broken).success,"relabeling the same erased-source six-coin services as schema8 cannot manufacture a legitimate historical legacy tariff")
	check(game.snapshot() == committed,"all hostile-source checks mutate local copies only")

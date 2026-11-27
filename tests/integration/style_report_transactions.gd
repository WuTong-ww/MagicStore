extends SceneTree
## Source joins use real committed actions. Deliberately altered copies are
## isolated read-only adversarial source fixtures, never user/game state.
const PATH := "res://scripts/people/style_report_sources.gd"
var checks := 0
var failures := 0
var game: Node
var saves: Node
var sources: Variant
var rules: Dictionary
var finished := false
func _initialize() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		if not finished:
			printerr("STYLE TRANSACTIONS FAIL: bounded target exceeded deadline")
			quit(1)
	)
	call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("STYLE TRANSACTIONS FAIL: "+label)
func command(kind: String, fields: Dictionary = {}) -> Dictionary:
	var row := {"type":kind,"action_id":game.make_id("style_source"),"expected_version":game.state.get("state_version",0)}
	row.merge(fields,true)
	return row
func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var reply: Dictionary = await game.execute_action_async(command(kind,fields))
	check(reply.get("success",false),"real "+kind+" / "+reply.get("message",""))
	return reply
func facts() -> Dictionary:
	return sources.collect(game.snapshot(),rules)
func run() -> void:
	if not FileAccess.file_exists(PATH):
		check(false,"committed-only style report source adapter exists")
		finish()
		return
	sources = load(PATH)
	check(sources != null and sources.has_method("collect") and sources.has_method("public_report"),"frozen adapter API exists")
	var model: Variant = load("res://scripts/people/style_report.gd")
	rules = model.load_rules()
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/g6/transaction-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	if not (await act("new_game",{"name":"经营报告真实来源"})).success:
		finish()
		return
	check(model.facts_valid(facts(),rules),"new committed snapshot yields valid whitelist facts")
	check(facts().visits.is_empty() and sources.public_report(game.snapshot()).status == "observing","empty report is observing without fabricated samples")
	await act("wait",{"minutes":5})
	await act("start_arrival",{"arrival_id":"arrival_opening_lin"})
	var visit_id: String = game.state.active_visit_id
	var before: Dictionary = game.snapshot()
	var old_report: Dictionary = sources.public_report(before)
	var path: String = saves._path(before.save_id)
	var sha := FileAccess.get_sha256(path)
	var pending := command("talk",{"topic_id":"letter","text":"为什么还没回信？"})
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(pending)
	saves.fail_next_write = false
	check(not failed.success and game.snapshot() == before and FileAccess.get_sha256(path) == sha and sources.public_report(game.snapshot()) == old_report,"failed talk save publishes no report sample/state/disk mutation")
	check((await game.execute_action_async(pending)).success,"same-ID failed talk retries through real commit")
	var committed: Dictionary = game.snapshot()
	check((await game.execute_action_async(pending)).get("replayed",false) and game.snapshot() == committed,"same-ID talk replay never creates another sample")
	await act("talk",{"text":"我愿意慢慢听你说。"})
	check(facts().visits.is_empty() and facts().talks.is_empty(),"active reception remains outside the ended-visit window")
	var quote := await act("quote_service",{"method_id":"tarot","option_id":"situation","payment":"coins"})
	await act("cancel_service",{"service_id":quote.result.service_id})
	await act("reading")
	var event: Dictionary = game.divination_view().event
	var predicted := await act("record_prediction",{"subject_id":event.subject_id,"text":"先记下预测，之后以真实反馈核对。","condition":"always","expected":"missed","window_start":event.due_at,"window_end":int(event.due_at)+30})
	await act("buy_case_item")
	await act("sell_product",{"item_id":"calming_incense"})
	await act("give_advice",{"advice_key":"message"})
	await act("end_visit")
	var first := facts()
	check(model.facts_valid(first,rules),"real paid/talk/prediction/trade facts satisfy the strict pure boundary")
	check(first.visits.size() == 1 and first.talks.size() == 2 and first.talks.filter(func(row: Dictionary) -> bool: return row.channel == "free_text").size() == 1,"two successful talks preserve their actual button/free-text channels")
	check(first.predictions.size() == 1 and first.paid_services.filter(func(row: Dictionary) -> bool: return row.status == "paid").size() == 1 and first.paid_services.filter(func(row: Dictionary) -> bool: return row.status == "cancelled").size() == 1,"paid and cancelled quotations remain distinct source records")
	var paid: Dictionary = first.paid_services.filter(func(row: Dictionary) -> bool: return row.status == "paid")[0]
	check(paid.at == first.predictions[0].at and paid.order < first.predictions[0].order,"same-minute paid-before-prediction ordering comes from actual committed versions")
	check(first.trades.size() == 2 and first.trades.map(func(row: Dictionary) -> String: return row.namespace).has("shop") and first.trades.map(func(row: Dictionary) -> String: return row.namespace).has("divination"),"both real B purchase and C product sale count, not paid divination")
	check(first.disclosed_feedback.is_empty(),"resolved or pending undisclosed world data never becomes an observed mistake")
	check(first.arrival_episodes.any(func(row: Dictionary) -> bool: return row.state == "served" and row.visit_id == visit_id and row.at < first.window.started_at),"actual wait-before-service episode is included by its resolution window, not discarded because arrival preceded reception")
	var now: Dictionary = game.snapshot()
	var now_sha := FileAccess.get_sha256(path)
	var projected: Dictionary = game.people_view()
	check(projected.has("style_report") and projected.has("report") and projected.report == load("res://scripts/people/people.gd").style_report(now.people),"Bridge adds modern report while preserving the complete legacy ABI")
	check(projected.style_report.evidence.values().any(func(row: Dictionary) -> bool: return row.visit_id == visit_id and row.action_id == pending.action_id),"observing report still exposes a genuine joined talk basis for read-only history navigation")
	for ignored_index in range(3): sources.public_report(now)
	check(game.snapshot() == now and FileAccess.get_sha256(path) == now_sha,"deriving and repeatedly rendering a report never executes, saves or mutates")
	await act("load_game",{"save_id":now.save_id})
	check(facts() == first and sources.public_report(game.snapshot()) == projected.style_report,"real JSON reload preserves facts and public report exactly")
	adversarial_sources(now,first)
	await act("next_day")
	await act("start_visit")
	var feedback := await act("receive_feedback",{"event_id":event.event_id})
	await act("end_visit")
	var disclosed := facts()
	check(disclosed.disclosed_feedback.size() == 1 and disclosed.disclosed_feedback[0].evaluation == "deviated" and disclosed.disclosed_feedback[0].reviewable,"only a real disclosed deviated feedback with a valid applied review effect creates an opportunity")
	if not disclosed.disclosed_feedback.is_empty():
		var effect_id: String = disclosed.disclosed_feedback[0].effect_id
		var review_action := command("review_case",{"effect_id":effect_id})
		before = game.snapshot()
		old_report = sources.public_report(before)
		saves.fail_next_write = true
		failed = await game.execute_action_async(review_action)
		saves.fail_next_write = false
		check(not failed.success and game.snapshot() == before and sources.public_report(game.snapshot()) == old_report,"failed review save does not manufacture a reflection sample")
		check((await game.execute_action_async(review_action)).success,"real review retries once and commits")
		committed = game.snapshot()
		check((await game.execute_action_async(review_action)).get("replayed",false) and game.snapshot() == committed and facts().reviews.size() == 1,"review replay counts one real ledger/effect source")
		await act("load_game",{"save_id":committed.save_id})
		check(game.snapshot() == committed and facts().reviews.size() == 1,"review and disclosed evidence survive real disk reopening")
		var wrong := committed.duplicate(true)
		wrong.shop.reviews.clear()
		check(sources.collect(wrong,rules).reviews.is_empty(),"a ledger without its committed applied-review mirror cannot count")
	await real_manual_contacts()
	var prior: Dictionary = sources.public_report(game.snapshot())
	await act("new_game",{"name":"另一间独立店铺"})
	check(facts().visits.is_empty() and sources.public_report(game.snapshot()).evidence.is_empty() and not prior.window.visit_ids.is_empty(),"switching save identity never carries the previous report samples")
	finish()
func real_manual_contacts() -> void:
	await act("new_game",{"name":"主动联系来源隔离"})
	# Explicit authored, approved offline identity is initial setup, not a paid
	# network-generation claim. All invitation/return actions below are real.
	var generated: Variant = load("res://scripts/people/generated_person.gd")
	var case_api: Variant = load("res://scripts/divination/generated_cases.gd")
	var generation_id: String = game.make_id("person")
	var draft: Dictionary = generated.offline_bundle(generation_id)
	var candidate: Dictionary = game.snapshot()
	var installed: Dictionary = generated.apply(candidate.people,game.people_config,generation_id,draft,generated.offline_provenance(generation_id),int(candidate.clock_minutes)+30)
	check(installed.success,"approved offline authored identity setup is structurally valid")
	if not installed.success:
		return
	check(game._sync_person_variation(candidate),"authored identity setup has the current validated nationality and face-detail fields")
	candidate = saves._normalize_numbers(candidate)
	check(saves.write_save(candidate).success,"authored identity/arrival setup passes the real complete save validator")
	await act("load_game",{"save_id":candidate.save_id})
	await act("wait",{"minutes":30})
	var record: Dictionary = game.state.people.generated_people[generation_id]
	await act("start_arrival",{"arrival_id":record.arrival_id})
	await act("talk",{"topic_id":case_api.topic_id(record.npc_id,"relationship"),"text":"可以介绍一下这位熟人吗？"})
	var invitation: Dictionary = game.contact_invitation()
	check(invitation.get("npc_id") == record.contact_id,"actual disclosed relationship creates a lawful invitation target")
	var pending := command("invite_contact",{"target_npc_id":record.contact_id,"guest_agreed":true})
	var before: Dictionary = game.snapshot()
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(pending)
	saves.fail_next_write = false
	check(not failed.success and game.snapshot() == before,"failed manual invitation does not leave a source record")
	check((await game.execute_action_async(pending)).success,"manual invitation retries through the real save boundary")
	var invited: Dictionary = game.snapshot()
	check((await game.execute_action_async(pending)).get("replayed",false) and game.snapshot() == invited,"manual invitation replay never duplicates the commitment")
	var return_at: int = game.next_return_time()
	check(return_at > int(game.state.clock_minutes),"real generated encounter offers a legal future return")
	await act("end_visit",{"return_at":return_at,"guest_agreed":true})
	var collected := facts()
	check(collected.manual_contacts.size() == 2 and collected.manual_contacts.map(func(row: Dictionary) -> String: return row.kind).has("invite") and collected.manual_contacts.map(func(row: Dictionary) -> String: return row.kind).has("return"),"one ended real reception contains exactly its distinct manual invite and agreed return")
	var direct_invite: Dictionary = collected.manual_contacts.filter(func(row: Dictionary) -> bool: return row.kind == "invite")[0]
	check(direct_invite.at == null,"future appointment minute is never invented as the unrecorded invitation-action time")
	var bad: Dictionary = game.snapshot()
	bad.processed_actions.erase(pending.action_id)
	check(sources.collect(bad,rules).manual_contacts.size() == 1 and sources.collect(bad,rules).coverage.relations.status != "complete","a proposed invite without its committed action is excluded with a coverage gap")
func adversarial_sources(snapshot: Dictionary, original: Dictionary) -> void:
	var copy := snapshot.duplicate(true)
	copy.people.profiles.npc_lin.personality = "PRIVATE_PERSONALITY_SENTINEL"
	copy.divination.cases[original.visits[0].id].world_facts["private_style_sentinel"] = "UNREVEALED_WORLD_SENTINEL"
	check(sources.collect(copy,rules) == original and not JSON.stringify(original).contains("SENTINEL"),"private personality and unknown hidden world fields cannot influence the whitelist report")
	copy = snapshot.duplicate(true)
	var conversation: Dictionary = copy.divination.cases[original.visits[0].id].conversation[0]
	copy.processed_actions.erase(conversation.action_id)
	var missing: Dictionary = sources.collect(copy,rules)
	check(missing.talks.size() == original.talks.size()-1 and missing.coverage.inquiry.status != "complete","uncommitted or missing talk source is excluded and reduces coverage")
	copy = snapshot.duplicate(true)
	copy.divination.cases[original.visits[0].id].conversation[0].erase("channel")
	missing = sources.collect(copy,rules)
	check(missing.coverage.inquiry.status != "complete" and missing.talks.any(func(row: Dictionary) -> bool: return row.channel == "unknown"),"old missing channel remains unknown, never guessed from its text")
	copy = snapshot.duplicate(true)
	copy.people.erase("family_metrics")
	check(sources.collect(copy,rules).coverage.rhythm.status == "unknown" and sources.collect(copy,rules).coverage.rhythm.baseline_at == null,"old loss counter without a physical-arrival baseline stays unknown")
	copy = snapshot.duplicate(true)
	copy.shop.ledger.append(copy.shop.ledger.filter(func(row: Dictionary) -> bool: return row.category == "product")[0].duplicate(true))
	check(sources.collect(copy,rules).trades == original.trades,"an identical duplicated transaction mirror cannot add a sale")
	copy.shop.ledger.back().result.quantity += 1
	check(sources.collect(copy,rules).coverage.commerce.status != "complete","conflicting same-transaction mirrors fail closed instead of silently preferring one")
func finish() -> void:
	finished = true
	print("STYLE TRANSACTIONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

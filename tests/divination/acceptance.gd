extends SceneTree
## B1–B5. Real actions and disk persistence in an isolated save directory.

class InvalidBranchProvider extends RefCounted:
	func request_reply(_request: Dictionary) -> Dictionary:
		return {
			"reply_text": "我知道展馆入口改了。", "intent": "venue", "clue_ids": ["venue_notice"],
			"branch_id": "confirmed_venue", "needs_clarification": false, "error_code": ""
		}

var gs: Node
var saves: Node
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	gs = root.get_node("GameState")
	saves = root.get_node("SaveService")
	saves.base_dir = "user://test-runs/" + gs.make_id("divination")
	_service_and_knowledge()
	_events()
	_methods_and_past()
	_cross_reading()
	_v1_migration()
	_handoff()
	print("DIVINATION RESULT: %d checks, %d failures. Isolated saves: %s" % [checks, failures, ProjectSettings.globalize_path(saves.base_dir)])
	quit(0 if failures == 0 else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("B ACCEPTANCE FAIL: " + label)

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var action: Dictionary = {"type": kind, "action_id": gs.make_id("b_test")}
	action.merge(fields, true)
	return gs.execute_action(action)

func require_action(kind: String, fields: Dictionary = {}) -> Dictionary:
	var reply := act(kind, fields)
	check(reply.success, kind + " / " + reply.message)
	return reply.result

func fresh(name: String) -> void:
	require_action("new_game", {"name": name})

func talk(text: String, topic: String = "") -> void:
	var fields := {"text": text}
	if not topic.is_empty():
		fields["topic_id"] = topic
	require_action("talk", fields)

func quote(method_id: String, option_id: String, parameter: int = 0, payment: String = "coins") -> Dictionary:
	return act("quote_service", {"method_id": method_id, "option_id": option_id, "parameter": parameter, "payment": payment})

func read(method_id: String, option_id: String, parameter: int = 0, payment: String = "coins") -> Dictionary:
	var quoted := quote(method_id, option_id, parameter, payment)
	check(quoted.success, method_id + " / " + quoted.message)
	return require_action("settle_service", {"service_id": quoted.result.get("service_id", "")}).get("service_result", {})

func start_archive(npc_id: String) -> void:
	require_action("start_visit", {"npc_id": npc_id, "case_id": "archive"})
	talk("看看借条和旧物", "archive")

func reload_game() -> void:
	require_action("load_game", {"save_id": gs.state.save_id})

func _service_and_knowledge() -> void:
	fresh("B1 B2 服务与证据")
	require_action("start_visit")
	var before: Dictionary = gs.snapshot()
	var view: Dictionary = gs.divination_view()
	check(before.divination.skills == ["tarot"], "B3 new shop starts with tarot only")
	check(view.facts.is_empty() and view.past.is_empty() and not gs.player_snapshot().has("divination"), "B2 hidden case facts stay outside player snapshots")
	check(gs.active_visit().dialogue.front().text.contains("群发"), "B2 initial statement can conflict with world fact")
	check(quote("lenormand", "letter_birds").error_code == "METHOD_UNLEARNED", "B1 reject locked method")
	check(quote("past", "vision").error_code == "METHOD_NOT_APPLICABLE", "B1 reject method outside case")
	check(act("talk", {"text": "核对侧门", "topic_id": "venue"}).error_code == "TOPIC_NOT_AVAILABLE", "B1 button respects clue prerequisite")
	var original_provider: RefCounted = gs.dialogue_provider
	gs.dialogue_provider = InvalidBranchProvider.new()
	check(act("talk", {"text": "侧门"}).error_code == "PROVIDER_INVALID" and gs.snapshot() == before, "B1 reject model's out-of-scope branch atomically")
	gs.dialogue_provider = original_provider
	talk("邀请上写了什么？", "invitation")
	talk("请核对侧门告示")
	view = gs.divination_view()
	check(view.statements[0].channel == "button" and view.statements[1].channel == "free_text" and view.statements[1].branch_id == "confirmed_venue", "B1 both inputs produce linked effects")
	check(view.statements[0].action_id != view.statements[1].action_id and view.facts.size() == 2, "B2 only corroborated facts become visible")
	require_action("note_hypothesis", {"text": "她的旧友可能不会到场。"})
	check(gs.divination_view().facts == view.facts and gs.divination_view().hypotheses[0].clue_ids.size() == 2, "B2 hypothesis stays separate and references evidence")

	var paid_before: Dictionary = gs.snapshot()
	var quoted := quote("tarot", "situation")
	var id: String = quoted.result.get("service_id", "")
	check(quoted.success and gs.divination_view().quote.result.is_empty(), "B1 quote with hidden result")
	check(gs.state.clock_minutes == paid_before.clock_minutes and gs.state.player == paid_before.player, "B1 quoting has no cost")
	reload_game()
	check(gs.divination_view().quote.service_id == id, "B1 quote survives reload")
	var unpaid: Dictionary = gs.snapshot()
	gs.state.npcs.npc_lin.coins = 0
	var broke: Dictionary = gs.snapshot()
	check(act("settle_service", {"service_id": id}).error_code == "NPC_FUNDS_LOW" and gs.snapshot() == broke and gs.divination_view().quote.result.is_empty(), "B1 unavailable funds keep the result hidden")
	gs.state = unpaid
	saves.fail_next_write = true
	check(act("settle_service", {"service_id": id}).error_code == "SAVE_WRITE_FAILED" and gs.snapshot() == unpaid and gs.divination_view().quote.result.is_empty(), "B1 failed transaction keeps both accounts and result unchanged")
	var paid := require_action("settle_service", {"service_id": id})
	var after: Dictionary = gs.snapshot()
	check(after.player.coins == unpaid.player.coins + 20 and after.npcs.npc_lin.coins == unpaid.npcs.npc_lin.coins - 20 and after.player.energy == unpaid.player.energy - 25 and after.clock_minutes == unpaid.clock_minutes + 30, "B1 both cash accounts, energy, time settle together")
	reload_game()
	check(act("settle_service", {"service_id": id, "expected_version": 0}).result.get("service_result") == paid.get("service_result") and gs.snapshot() == after, "B1 fresh request replays the same paid result after reload")
	var item_quote := quote("tarot", "next_question", 0, "item")
	check(item_quote.success and item_quote.result.service_id != id, "B1 additional service has its own ID")
	var item_id: String = item_quote.result.service_id
	var pre_item: Dictionary = gs.snapshot()
	gs.state.npcs.npc_lin.items.bookmark = 0
	var no_items: Dictionary = gs.snapshot()
	check(act("settle_service", {"service_id": item_id}).error_code == "NPC_ITEMS_LOW" and gs.snapshot() == no_items, "B1 insufficient item balance is atomic")
	gs.state = pre_item
	require_action("settle_service", {"service_id": item_id})
	require_action("buy_case_item")
	view = gs.divination_view()
	check(view.ledger.size() == 3 and view.ledger[0].payment.kind == "coins" and view.ledger[1].payment.kind == "item" and view.ledger[2].category == "product", "B1 divination and separate purchase have distinct ledger references")
	check(gs.state.player.items.bookmark == 1 and gs.state.npcs.npc_lin.items.bookmark == 3, "B1 item payment actually transfers ownership")
	require_action("end_visit")

func _events() -> void:
	var cases := [
		{"label": "符合", "advice": "message", "expected": "met", "evaluation": "aligned", "outcome": "met"},
		{"label": "偏离", "advice": "wait", "expected": "met", "evaluation": "deviated", "outcome": "missed"},
		{"label": "证据不足且延期", "advice": "note", "expected": "met", "evaluation": "insufficient", "outcome": "missed"},
		{"label": "已发生但不反馈", "advice": "private", "expected": "met", "evaluation": "aligned", "outcome": "met"},
		{"label": "到错入口", "advice": "attend", "expected": "met", "evaluation": "deviated", "outcome": "missed"},
		{"label": "商品改变结果", "advice": "attend", "expected": "met", "evaluation": "aligned", "outcome": "met", "use": true},
		{"label": "问话改变分支", "advice": "attend", "expected": "met", "evaluation": "aligned", "outcome": "met", "venue": true},
		{"label": "同线索相反预测", "advice": "message", "expected": "missed", "evaluation": "deviated", "outcome": "met"},
		{"label": "时间窗不合", "advice": "message", "expected": "met", "evaluation": "deviated", "outcome": "met", "window_offset": 60},
		{"label": "预测条件未满足", "advice": "wait", "expected": "met", "evaluation": "condition_not_met", "outcome": "missed", "condition": "if_message"}
	]
	for row: Dictionary in cases:
		_event_case(row)

func _event_case(row: Dictionary) -> void:
	fresh("B4 " + row.label)
	require_action("start_visit")
	var view: Dictionary = gs.divination_view()
	var origin: String = view.visit_id
	var event: Dictionary = view.event
	check(event.status == "pending" and gs.divination_feedback_queue().is_empty(), "B4 event not yet due")
	var refused := require_action("give_advice", {"advice_key": "message"})
	check(not refused.get("accepted", true), "B2 advice can be refused with evidence missing")
	talk("邀请上的附言", "invitation")
	talk("那封还没寄出的回信")
	if row.get("venue", false):
		talk("核对侧门告示", "venue")
	var start := int(event.due_at) + int(row.get("window_offset", 0))
	var fields := {
		"subject_id": event.subject_id, "text": " 原话会原样保留 ", "condition": row.get("condition", "always"),
		"expected": row.expected, "window_start": start, "window_end": start + 30
	}
	check(act("record_prediction", fields).error_code == "NEEDS_PAID_SERVICE", "B2 formal forecast requires paid service")
	require_action("reading")
	require_action("record_prediction", fields)
	require_action("give_advice", {"advice_key": row.advice})
	if row.advice == "attend":
		var demands: Array = gs.divination_demands()
		check(demands.size() == 1 and demands[0].event_id == event.event_id, "B4 case demand references the event for C")
	if row.get("use", false):
		require_action("buy_case_item")
		require_action("use_case_item")
	else:
		check(gs.divination_view().ledger.size() == 1, "B1 service-only route has no sale")
	require_action("end_visit")
	require_action("next_day")
	reload_game()
	view = gs.divination_view(origin)
	var actual: Dictionary = gs.state.divination.cases[origin].event
	check(actual.evaluation == row.evaluation and actual.outcome == row.outcome, "B4 evaluated deadline / " + row.label)
	check(actual.occurrence == ("occurred" if row.outcome == "met" else "did_not_occur") and actual.evidence == ("insufficient" if row.evaluation == "insufficient" else "sufficient"), "B4 occurrence and evidence stay independent")
	check(not actual.advice_id.is_empty() and not actual.actual_action.is_empty(), "B4 executed plan has advice reference and actual action")
	check(not actual.item_use_id.is_empty() if row.get("use", false) else actual.item_use_id.is_empty(), "B4 link only the relevant product use")
	check(view.prediction.text == fields.text and view.prediction.subject_id == fields.subject_id and view.prediction.window_start == start and view.prediction.condition == fields.condition, "B2 persist original forecast fields")
	check(view.event.status == "awaiting_feedback" and view.event.report.is_empty() and not view.event.has("outcome"), "B4 no disclosure when event passes without visit feedback")
	var queue: Array = gs.divination_feedback_queue()
	check(queue.size() == 1 and queue[0].event_id == event.event_id and queue[0].prediction_id == view.prediction.prediction_id, "B4 feedback handoff has stable references")
	require_action("start_visit")
	if row.advice in ["private", "note"]:
		check(act("receive_feedback", {"event_id": event.event_id}).error_code == "FEEDBACK_UNAVAILABLE", "B4 withheld or delayed feedback is not claimable early")
	if row.advice == "private":
		check(queue[0].mode == "never" and queue[0].disclosure.is_empty() and gs.divination_effects("A").is_empty() and gs.divination_view(origin).event.report.is_empty(), "B4 occurred with no feedback and no automatic failure")
		return
	if row.advice == "note":
		check(queue[0].available_at > gs.state.clock_minutes, "B4 note outcome has a later feedback slot")
		require_action("end_visit")
		require_action("next_day")
		require_action("start_visit")
	var pending: Dictionary = gs.snapshot()
	saves.fail_next_write = true
	check(act("receive_feedback", {"event_id": event.event_id}).error_code == "SAVE_WRITE_FAILED" and gs.snapshot() == pending, "B4 report and rewards roll back together")
	var received := require_action("receive_feedback", {"event_id": event.event_id})
	check(received.get("feedback", {}).get("evaluation") == row.evaluation, "B4 disclosed evaluation matches authorized result")
	var a: Array = gs.divination_effects("A")
	var c: Array = gs.divination_effects("C")
	if row.evaluation == "aligned":
		check(a.any(func(effect: Dictionary) -> bool: return effect.kind == "trust" and effect.amount > 0), "B4 aligned proposal increases trust")
		check(c.any(func(effect: Dictionary) -> bool: return effect.kind == "arrival_boost" and effect.expires_at > effect.starts_at), "B4 temporary arrival effect reaches C with expiry")
		if row.advice == "message":
			check(a.any(func(effect: Dictionary) -> bool: return effect.kind == "referral") and c.any(func(effect: Dictionary) -> bool: return effect.kind == "reputation"), "B4 conditional referral and reputation")
			check(gs.divination_view().ledger.any(func(entry: Dictionary) -> bool: return entry.category == "gift"), "B4 extra gift has a separate ledger entry")
	elif row.evaluation == "deviated":
		check(a.size() == 1 and a[0].amount < 0 and c.size() == 1 and c[0].kind == "review_growth", "B4 failure proposes loss of trust and review")
	else:
		check(a.is_empty() and c.is_empty(), "B4 insufficient evidence or inapplicable condition gives no trust verdict")
		if row.evaluation == "insufficient":
			check(not received.feedback.has("outcome") and not received.feedback.has("occurrence"), "B4 incomplete evidence does not leak hidden truth")
	var delivered: Dictionary = gs.snapshot()
	reload_game()
	check(act("receive_feedback", {"event_id": event.event_id}).error_code == "FEEDBACK_UNAVAILABLE" and gs.snapshot() == delivered, "B4 report and effects cannot be granted twice")

func _methods_and_past() -> void:
	fresh("B3 B5 研习及前世")
	require_action("start_visit")
	var tarot := read("tarot", "situation")
	check(tarot.get("medium", {}).get("cards", []).size() == 3 and gs.active_visit().reading.get("cards") == tarot.medium.cards, "B3 tarot delivers and persists the three-card spread")
	require_action("end_visit")
	var guests: Array = gs.divination_guests()
	var ordinary: String = guests.filter(func(row: Dictionary) -> bool: return row.label.ends_with("普通样例"))[0].npc_id
	var reference: String = guests.filter(func(row: Dictionary) -> bool: return row.label.ends_with("作品参考样例"))[0].npc_id
	check(act("learn_method", {"method_id": "ziwei"}).error_code == "SKILL_PREREQUISITE", "B3 advanced prerequisite")
	for row: Array in [
		["lenormand", "letter_birds", 0, "cards", ordinary], ["plum", "number", 7, "hexagram", ordinary],
		["yijing", "release", 5, "hexagram", ordinary], ["xiaoliu", "afternoon", 0, "six_ren", ordinary],
		["astrology", "season", 0, "astrology", ordinary], ["bazi", "hour", 1, "pillars", ordinary],
		["ziwei", "career", 1, "ziwei", reference]
	]:
		require_action("next_day")
		require_action("learn_method", {"method_id": row[0]})
		start_archive(row[4])
		if row[0] in ["astrology", "bazi", "ziwei"]:
			check(quote(row[0], row[1], row[2]).error_code == "NEEDS_BIRTH" and not gs.divination_view().has("birth"), "B3 chart requires disclosed birth info")
			talk("征求出生资料", "birth")
		var result := read(row[0], row[1], row[2])
		check(result.get("medium", {}).get("kind") == row[3] and not result.get("signals", []).is_empty(), "B3 input-derived medium and traceable hints / " + row[0])
		reload_game()
		check(gs.divination_view().services[0].result == result, "B3 identical resolved medium after reload / " + row[0])
		require_action("end_visit")
	require_action("next_day")
	require_action("learn_method", {"method_id": "past"})
	start_archive("npc_lin")
	check(quote("past", "evidence").error_code == "NEEDS_INTERPRETATION", "B5 no evidence before seeing and interpreting a fragment")
	read("past", "vision")
	var wrong := require_action("interpret_past", {"link_id": "messenger", "text": "我先猜拿伞的是她。"})
	check(act("verify_past", {"interpretation_id": wrong.get("interpretation_id")}).error_code == "NEEDS_EVIDENCE", "B5 verification waits for corroboration")
	check(gs.divination_view().past.confirmed_links.is_empty() and not gs.divination_view().past.options[0].has("valid"), "B5 guess remains unverified and answer hidden")
	require_action("end_visit")
	require_action("next_day")
	reload_game()
	start_archive("npc_lin")
	check(gs.divination_view().past.fragments.has("vision") and gs.divination_view().past.interpretations[0].status == "unverified", "B5 persistent memory and guess on return and reload")
	read("past", "evidence", 0, "item")
	check(require_action("verify_past", {"interpretation_id": wrong.interpretation_id}).get("status") == "disproven", "B5 the same fragment can be misread")
	_confirm_past("binder")
	require_action("end_visit")
	for guest: Array in [[ordinary, "boat"], [reference, "garden"]]:
		require_action("next_day")
		start_archive(guest[0])
		check(gs.divination_view().past.is_empty(), "B5 visitors have independent past memory")
		read("past", "vision")
		var guess := require_action("interpret_past", {"link_id": guest[1]})
		read("past", "evidence")
		check(require_action("verify_past", {"interpretation_id": guess.interpretation_id}).get("status") == "confirmed", "B5 ordinary/reference corroboration")
		require_action("end_visit")
	reload_game()
	check(gs.state.divination.past.size() == 3 and gs.state.divination.past[reference].confirmed_links[0].identity_id == "night_gardener", "B5 three origins retain distinct stable profiles and confirmed stories")
	check(gs.state.divination.skills.size() == 9, "B3 all methods reachable with ordinary gameplay and resources")

func _confirm_past(link_id: String) -> void:
	var guess := require_action("interpret_past", {"link_id": link_id})
	check(require_action("verify_past", {"interpretation_id": guess.interpretation_id}).get("status") == "confirmed", "B5 independent evidence confirms an interpretation")
	var past: Dictionary = gs.divination_view().past
	check(past.confirmed_links.size() == 1 and past.stories.size() == 1 and not past.confirmed_links[0].relation.is_empty(), "B5 confirmed relation and subsequent story persist separately")
	check(act("verify_past", {"interpretation_id": guess.interpretation_id}).error_code == "ALREADY_VERIFIED", "B5 verified link and story are idempotent")

func _cross_reading() -> void:
	fresh("跨次接待对照")
	require_action("learn_method", {"method_id": "lenormand"})
	require_action("start_visit")
	var first_visit: String = gs.active_visit().visit_id
	read("tarot", "situation")
	require_action("end_visit")
	require_action("next_day")
	require_action("start_visit")
	read("lenormand", "key_house")
	var view: Dictionary = gs.divination_view()
	var links: Array = view.oracle_links
	var trace_ids: Array = []
	for comparison: Dictionary in links:
		for trace: Dictionary in comparison.traces:
			if not trace.visit_id in trace_ids:
				trace_ids.append(trace.visit_id)
	check(first_visit in trace_ids and view.visit_id in trace_ids, "cross-method notes retain sources across visits for the same guest and case")
	check(view.facts.is_empty(), "cross-method prompts cannot promote hidden facts")
	reload_game()
	check(gs.divination_view().oracle_links == links, "cross-method notes preserve exact evidence after reload")

func _v1_migration() -> void:
	fresh("迁移样例来源")
	require_action("start_visit")
	talk("邀请上的附言")
	require_action("reading")
	var legacy: Dictionary = gs.snapshot()
	legacy.schema_version = 1
	legacy.save_id = gs.make_id("v1_test")
	legacy.erase("divination")
	legacy.player.erase("items")
	legacy.npcs = {"npc_lin": {"coins": legacy.npcs.npc_lin.coins}}
	var card: Dictionary = gs.content.cards[0]
	var original_reading: Dictionary = legacy.visits[0].reading
	original_reading.erase("cards")
	original_reading.merge({"card_id": card.card_id, "title": card.title, "text": card.text}, true)
	for action: Dictionary in legacy.processed_actions.values():
		action.result.erase("service_id")
		action.result.erase("service_result")
		if action.result.has("reading"):
			action.result.reading = original_reading.duplicate(true)
	check(saves.write_save(legacy).success, "B1 original schema fixture writes")
	require_action("load_game", {"save_id": legacy.save_id})
	check(gs.state.schema_version == 2 and gs.state.visits == legacy.visits and gs.state.clock_minutes == legacy.clock_minutes and gs.state.active_visit_id == legacy.active_visit_id and gs.state.player.coins == legacy.player.coins and gs.state.player.energy == legacy.player.energy, "B1 migration preserves paid unfinished visit, history, clocks and balances")
	check(gs.divination_view().event.is_empty() and saves.read_save(legacy.save_id).state.schema_version == 1, "B1 load creates no retrospective event or file write")
	var before: Dictionary = gs.snapshot()
	require_action("reading")
	check(gs.snapshot() == before, "B1 migrated paid reading is still replayable for free")
	require_action("rest")
	check(saves.read_save(legacy.save_id).state.schema_version == 2, "B1 next transaction persists v2")
	require_action("load_game", {"save_id": legacy.save_id, "recover_backup": true})
	check(gs.state.visits == legacy.visits and gs.state.clock_minutes == legacy.clock_minutes, "B1 v1 backup restoration remains available")

func _handoff() -> void:
	fresh("A C 联调接口")
	var draft: Dictionary = gs.snapshot()
	var id: String = gs.make_id("visit")
	var npc_id := "npc_fixture_from_a"
	var visit: Dictionary = {
		"visit_id": id, "npc_id": npc_id, "day": 0, "phase": "talking", "clue_ids": [],
		"dialogue": [{"speaker": "npc", "text": "我想问那位朋友的事。"}], "reading": {},
		"started_at": draft.clock_minutes, "ended_at": -1
	}
	draft.npcs[npc_id] = {"coins": 60, "items": {}}
	draft.active_visit_id = id
	draft.visits.append(visit)
	var registered: bool = gs._divination.add_case(draft, visit, "invitation", true, {
		"public_npc": {"name": "第三方来客", "role": "A 组接入样例"},
		"chart": {"birth": "联调出生资料", "pillars": ["丙子", "辛卯", "庚戌", "己卯"], "sector": 2},
		"subject_id": "npc_subject", "target_name": "两位旧友是否相见"
	})
	check(registered and saves.write_save(draft).success, "B contract accepts a registered A actor and independent subject")
	reload_game()
	check(gs.divination_view().guest.name == "第三方来客" and gs.divination_view().event.subject_id == "npc_subject" and not gs.divination_view().has("birth"), "B contract projects only permitted A data")
	talk("征求出生资料", "birth")
	check(gs.divination_view().birth.text == "联调出生资料", "B contract permits A chart only after the disclosure clue")
	draft = gs.snapshot()
	var event: Dictionary = gs.divination_view().event
	var use: Dictionary = {"event_id": event.event_id, "effect_key": "stay_and_ask", "item_use_id": "use_from_c", "transaction_id": "sale_from_c", "item_id": "incense_from_c"}
	var unrelated := use.duplicate()
	unrelated.effect_key = "unrelated"
	check(not gs._divination.link_item_use(draft, visit, unrelated), "B contract rejects unrelated C product effect")
	check(gs._divination.link_item_use(draft, visit, use) and saves.write_save(draft).success, "B contract persists trusted C use without the demo sale")
	reload_game()
	check(gs.divination_view().item_use.transaction_id == "sale_from_c", "B contract retains source transaction after reload")

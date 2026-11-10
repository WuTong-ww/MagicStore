extends Node
## Sole authority for game rules. UI reads snapshots and submits commands.

signal state_changed
signal action_failed(message: String)

const ContentLoader = preload("res://scripts/core/content_loader.gd")
const MockProvider = preload("res://scripts/providers/mock_dialogue_provider.gd")
const DivinationCatalog = preload("res://scripts/divination/catalog.gd")
const DivinationSession = preload("res://scripts/divination/session.gd")
const DivinationView = preload("res://scripts/divination/case_view.gd")
const DivinationEvents = preload("res://scripts/divination/event_rules.gd")

var state: Dictionary = {}
var content: Dictionary = {}
var content_error: String = ""
var dialogue_provider: RefCounted
var _divination: DivinationSession
var _provider_pending: bool = false

func _ready() -> void:
	var loaded: Dictionary = ContentLoader.load_content()
	if not loaded.success:
		content_error = loaded.message
		push_error(content_error)
		return
	content = loaded.content
	var catalog := DivinationCatalog.load_data(content)
	if catalog.is_empty():
		content_error = "问卜案例配置无效。"
		push_error(content_error)
		return
	_divination = DivinationSession.new(catalog, content)
	dialogue_provider = MockProvider.new()
	dialogue_provider.configure(catalog.topics + content.topics)

## Engine and verification snapshot. UI must use player_snapshot and divination_view.
func snapshot() -> Dictionary:
	return state.duplicate(true)

func player_snapshot() -> Dictionary:
	var visible := state.duplicate(false)
	visible.erase("divination")
	visible.erase("processed_actions")
	return visible.duplicate(true)

func divination_view(visit_id: String = "") -> Dictionary:
	for visit: Dictionary in state.get("visits", []):
		if visit.visit_id == (state.active_visit_id if visit_id.is_empty() else visit_id):
			return DivinationView.project(_divination, state, visit)
	return {}

func divination_study() -> Array:
	return DivinationView.study(_divination, state)

func divination_guests() -> Array:
	if _divination == null:
		return []
	var rows := _divination.guest_options(state)
	var day := floori(float(state.get("clock_minutes", 0)) / 1440.0)
	for row: Dictionary in rows:
		row.merge(_divination.guest_view(row.npc_id, row.case_id))
		row["visited_today"] = state.get("visits", []).any(func(visit: Dictionary) -> bool: return visit.npc_id == row.npc_id and int(visit.day) == day)
	return rows

## Trusted A/C handoffs. Consumers deduplicate proposals by their stable effect IDs.
func divination_feedback_queue() -> Array:
	return _divination.feedback_queue(state) if _divination != null else []

func divination_effects(recipient: String) -> Array:
	var results: Array = []
	for effect: Dictionary in state.get("divination", {}).get("effects", []):
		if effect.recipient == recipient:
			results.append(effect.duplicate(true))
	return results

func divination_demands() -> Array:
	var results: Array = []
	for case: Dictionary in state.get("divination", {}).get("cases", {}).values():
		if case.has("demand"):
			results.append(case.demand.duplicate(true))
	return results

func make_id(prefix: String = "action") -> String:
	return prefix + "_" + Crypto.new().generate_random_bytes(16).hex_encode()

func active_visit() -> Dictionary:
	if state.is_empty():
		return {}
	for visit: Dictionary in state.visits:
		if visit.visit_id == state.active_visit_id:
			return visit.duplicate(true)
	return {}

func clock_text() -> String:
	if state.is_empty():
		return "尚未营业"
	var minute: int = int(state.clock_minutes) % 1440
	return "第 %d 天  %02d:%02d" % [int(state.clock_minutes / 1440) + 1, int(minute / 60), minute % 60]

## UI uses this coroutine-compatible entry. Mock returns immediately; HTTP may await.
func execute_action_async(action: Dictionary) -> Dictionary:
	if action.get("type", "") != "talk":
		return execute_action(action)
	if _provider_pending:
		return _fail("BUSY", "正在等待对话回复，请稍候。")
	var preliminary: Dictionary = _preflight(action)
	if not preliminary.is_empty():
		return preliminary
	var prepared: Dictionary = _prepare_talk(action)
	if not prepared.success:
		return prepared
	var version: int = int(state.state_version)
	var save_id: String = state.save_id
	_provider_pending = true
	var response: Variant = await dialogue_provider.request_reply(prepared.request)
	_provider_pending = false
	if state.is_empty() or state.save_id != save_id or state.state_version != version:
		return _fail("STALE_VERSION", "对话期间状态已变化，请重新发送。")
	return _complete_talk(action, prepared.input_text, response)

## Synchronous convenience for CLI tests/local mock; HTTP callers use async entry.
func execute_action(action: Dictionary) -> Dictionary:
	if _provider_pending:
		return _fail("BUSY", "正在等待对话回复，请稍候。")
	if not content_error.is_empty() or content.is_empty():
		return _fail("CONTENT_INVALID", "内容配置不可用。" + content_error)
	if not action.get("type") is String:
		return _fail("INVALID_ACTION", "动作缺少有效的 type。")
	match action.type:
		"new_game":
			return _new_game(action)
		"load_game":
			return _load_game(action)
	var preliminary: Dictionary = _preflight(action)
	if not preliminary.is_empty():
		return preliminary
	match action.type:
		"start_visit":
			return _start_visit(action)
		"talk":
			var prepared: Dictionary = _prepare_talk(action)
			if not prepared.success:
				return prepared
			return _complete_talk(action, prepared.input_text, dialogue_provider.request_reply(prepared.request))
		"reading":
			return _divination_action(action)
		"end_visit":
			return _end_visit(action)
		"rest":
			return _rest(action)
		"next_day":
			return _next_day(action)
	if action.type in DivinationSession.ACTIONS:
		return _divination_action(action)
	return _fail("UNKNOWN_ACTION", "不支持此动作。")

func _preflight(action: Dictionary) -> Dictionary:
	if not content_error.is_empty() or content.is_empty():
		return _fail("CONTENT_INVALID", "内容配置不可用。" + content_error)
	if state.is_empty():
		return _fail("NO_SAVE", "请先新建或选择存档。")
	if not action.get("type") is String or not action.get("action_id") is String or action.action_id.is_empty() or action.action_id.length() > 128:
		return _fail("INVALID_ACTION", "动作需要 type 和唯一 action_id。")
	if state.processed_actions.has(action.action_id):
		var prior: Dictionary = state.processed_actions[action.action_id].duplicate(true)
		if prior.get("action_type", action.type) != action.type:
			return _fail("ACTION_ID_REUSED", "同一个动作 ID 不能用于不同动作。")
		prior["replayed"] = true
		return prior
	# Business idempotency wins over stale versions and resource checks.
	var visit: Dictionary = active_visit()
	if action.type == "reading" and not visit.is_empty() and not visit.reading.is_empty():
		return _ok("本次接待已结算，展示原牌面。", {"reading": visit.reading, "visit_id": visit.visit_id, "replayed": true})
	if action.type == "settle_service":
		var paid := _divination.paid_service(state, visit, action.get("service_id"))
		if not paid.is_empty():
			return _ok("展示本次服务的原结果。", {"service_id": paid.service_id, "visit_id": visit.visit_id, "service_result": paid.result.duplicate(true), "replayed": true})
	if action.type == "start_visit" and not visit.is_empty():
		if action.get("npc_id", visit.npc_id) != visit.npc_id or action.get("case_id", state.divination.cases[visit.visit_id].case_id) != state.divination.cases[visit.visit_id].case_id:
			return _fail("ACTIVE_VISIT", "请先结束当前接待。")
		return _ok("继续原接待。", {"visit_id": visit.visit_id, "replayed": true})
	if action.has("expected_version"):
		if not (action.expected_version is int or action.expected_version is float) or action.expected_version != state.state_version:
			return _fail("STALE_VERSION", "画面状态已变化，请刷新后重试。")
	return {}

func _new_game(action: Dictionary) -> Dictionary:
	if not action.get("name", "新店铺") is String:
		return _fail("INVALID_NAME", "存档名称应为文本。")
	var save_name: String = action.get("name", "新店铺").strip_edges()
	if save_name.is_empty():
		save_name = "新店铺"
	if save_name.length() > 32:
		return _fail("INVALID_NAME", "存档名称最多 32 个字符。")
	var candidate: Dictionary = {
		"schema_version": 2,
		"save_id": make_id("save"),
		"name": save_name,
		"state_version": 1,
		"clock_minutes": int(content.rules.opening_minute),
		"player": {"coins": int(content.rules.starting_coins), "energy": int(content.rules.max_energy)},
		"npcs": {"npc_lin": {"coins": int(content.rules.npc_coins)}},
		"active_visit_id": "",
		"visits": [],
		"processed_actions": {}
	}
	_divination.initialize(candidate)
	var saved: Dictionary = SaveService.write_save(candidate)
	if not saved.success:
		return _fail(saved.get("error_code", "SAVE_FAILED"), "新建失败，原存档仍保留。" + saved.get("message", ""))
	state = candidate
	state_changed.emit()
	return _ok("新店铺已保存。", {"save_id": state.save_id})

func _load_game(action: Dictionary) -> Dictionary:
	if not action.get("save_id") is String or not action.get("recover_backup", false) is bool:
		return _fail("INVALID_ACTION", "请选择有效的存档。")
	var loaded: Dictionary = SaveService.read_save(action.save_id, action.get("recover_backup", false))
	if not loaded.success:
		var failure: Dictionary = _fail(loaded.get("error_code", "LOAD_FAILED"), loaded.get("message", "读取失败，当前游戏仍保留。"))
		failure["backup_available"] = loaded.get("backup_available", false)
		return failure
	state = loaded.state.duplicate(true)
	if int(state.schema_version) == 1:
		_divination.initialize(state)
	state_changed.emit()
	return _ok(loaded.get("message", "存档已载入。"), {"save_id": state.save_id})

func _start_visit(action: Dictionary) -> Dictionary:
	var npc_id: Variant = action.get("npc_id", content.npc.npc_id)
	var case_id: Variant = action.get("case_id", "invitation" if npc_id == content.npc.npc_id else "archive")
	if not npc_id is String or not case_id is String or not _divination.guest_options(state).any(func(guest: Dictionary) -> bool: return guest.npc_id == npc_id and guest.case_id == case_id):
		return _fail("INVALID_GUEST", "请选择当前来客与案例。")
	var day := floori(float(state.clock_minutes) / 1440.0)
	var has_visited := false
	for visit: Dictionary in state.visits:
		if visit.npc_id == npc_id:
			has_visited = true
			if int(visit.day) == day:
				return _fail("ALREADY_VISITED_TODAY", "这位来客今天已经来过了。")
	if int(state.clock_minutes) % 1440 >= int(content.rules.closing_minute):
		return _fail("NOT_ENOUGH_TIME", "今天已打烊，请进入下一天。")
	var candidate: Dictionary = state.duplicate(true)
	var opening := _divination.opening(npc_id, case_id, has_visited)
	var visit: Dictionary = {
		"visit_id": make_id("visit"), "npc_id": npc_id, "day": day,
		"phase": "talking", "clue_ids": [],
		"dialogue": [{"speaker": "npc", "text": opening}], "reading": {},
		"started_at": int(state.clock_minutes), "ended_at": -1
	}
	candidate.visits.append(visit)
	candidate.active_visit_id = visit.visit_id
	if not _divination.add_case(candidate, visit, case_id):
		return _fail("CASE_INVALID", "无法建立这位来客的案例。")
	return _commit(candidate, action, "接待已开始并保存。", {"visit_id": visit.visit_id})

func _prepare_talk(action: Dictionary) -> Dictionary:
	var visit: Dictionary = active_visit()
	if visit.is_empty():
		return _fail("NO_VISIT", "请先接待顾客。")
	if not action.get("text") is String:
		return _fail("INVALID_INPUT", "请输入问题。")
	var input_text: String = action.text.strip_edges()
	if input_text.is_empty() or input_text.length() > 500:
		return _fail("INVALID_INPUT", "问题需为 1 至 500 个字符。")
	if not _has_time(int(content.rules.talk_minutes)):
		return _fail("NOT_ENOUGH_TIME", "今天剩余营业时间不足以继续交谈。请先结束接待。")
	var case: Dictionary = state.divination.cases[visit.visit_id]
	var allowed := _divination.talks(visit, case, int(state.clock_minutes))
	var topic_id: Variant = action.get("topic_id", "")
	if not topic_id is String or (not topic_id.is_empty() and (topic_id == "clarify" or not allowed.has(topic_id))):
		return _fail("TOPIC_NOT_AVAILABLE", "本案尚未开放这个提问。")
	var clues: Array = []
	var branches: Array = []
	for effects: Dictionary in allowed.values():
		for clue: String in effects.clue_ids:
			if not clue in clues:
				clues.append(clue)
		if not effects.branch_id.is_empty():
			branches.append(effects.branch_id)
	# Only public NPC details, visible dialogue and prior visit summaries are shared.
	var history: Array = []
	for previous: Dictionary in state.visits:
		if previous.phase == "ended" and previous.npc_id == visit.npc_id:
			history.append({"visit_id": previous.visit_id, "day": previous.day, "dialogue": previous.dialogue.duplicate(true), "clue_ids": previous.clue_ids.duplicate()})
	return {"success": true, "input_text": input_text, "request": {
		"npc": _divination.guest_view(visit.npc_id, case.case_id, case.get("public_npc", {})), "visit_id": visit.visit_id, "case_id": case.case_id,
		"visible_history": history, "current_dialogue": visit.dialogue.duplicate(true),
		"input_text": input_text, "topic_id": topic_id, "allowed_intents": allowed.keys(),
		"allowed_clue_ids": clues, "allowed_branch_ids": branches, "allowed_effects": allowed
	}}

func _complete_talk(action: Dictionary, input_text: String, response: Variant) -> Dictionary:
	if not response is Dictionary or not response.get("reply_text") is String or not response.get("intent") is String or not response.get("clue_ids") is Array or not response.get("needs_clarification") is bool or not response.get("error_code") is String:
		return _fail("PROVIDER_INVALID", "对话返回格式无效，未消耗时间。")
	if not response.error_code.is_empty():
		return _fail("PROVIDER_ERROR", "开发对话未能完成，未消耗时间。")
	if response.reply_text.is_empty() or response.reply_text.length() > 4000:
		return _fail("PROVIDER_INVALID", "对话文本长度无效。")
	for key in response:
		if not key in ["reply_text", "intent", "clue_ids", "needs_clarification", "error_code", "branch_id"]:
			return _fail("PROVIDER_INVALID", "对话返回了案例契约之外的提案。")
	var active := active_visit()
	var case: Dictionary = state.divination.cases[active.visit_id]
	var allowed := _divination.talks(active, case, int(state.clock_minutes))
	var selected: String = action.get("topic_id", "")
	if not allowed.has(response.intent) or (not selected.is_empty() and response.intent != selected) or response.needs_clarification != (response.intent == "clarify"):
		return _fail("PROVIDER_INVALID", "对话返回了本案未授权的话题。")
	var effects: Dictionary = allowed[response.intent]
	for clue_id: Variant in response.clue_ids:
		if not clue_id is String or not clue_id in effects.clue_ids:
			return _fail("PROVIDER_INVALID", "对话返回了未授权的线索。")
	var branch: Variant = response.get("branch_id", "")
	if not branch is String or (not branch.is_empty() and (branch != effects.branch_id or not effects.clue_ids.all(func(id: String) -> bool: return id in response.clue_ids or id in active.clue_ids))):
		return _fail("PROVIDER_INVALID", "对话返回了未授权的事件分支。")
	var candidate: Dictionary = state.duplicate(true)
	var visit: Dictionary = _candidate_visit(candidate)
	var new_clues: Array = []
	for clue_id: String in response.clue_ids:
		if not clue_id in visit.clue_ids:
			visit.clue_ids.append(clue_id)
			new_clues.append(clue_id)
	visit.dialogue.append({"speaker": "player", "text": input_text})
	visit.dialogue.append({"speaker": "npc", "text": response.reply_text})
	_divination.record_talk(candidate, visit, action, response, new_clues)
	_advance(candidate, int(content.rules.talk_minutes))
	var message: String = "交谈已保存。" if new_clues.is_empty() else "获得新线索，交谈已保存。"
	return _commit(candidate, action, message, {"visit_id": visit.visit_id, "reply_text": response.reply_text, "clue_ids": new_clues, "intent": response.intent, "branch_id": branch, "needs_clarification": response.needs_clarification})

func _divination_action(action: Dictionary) -> Dictionary:
	var candidate: Dictionary = state.duplicate(true)
	var visit: Dictionary = _candidate_visit(candidate)
	var outcome := _divination.handle(candidate, visit, action)
	if not outcome.success:
		return _fail(outcome.error_code, outcome.message)
	_advance(candidate, outcome.minutes)
	return _commit(candidate, action, outcome.message, outcome.result)

func _end_visit(action: Dictionary) -> Dictionary:
	if active_visit().is_empty():
		return _fail("NO_VISIT", "没有正在进行的接待。")
	var candidate: Dictionary = state.duplicate(true)
	var visit: Dictionary = _candidate_visit(candidate)
	_divination.cancel_open_service(candidate.divination.cases[visit.visit_id])
	visit.phase = "ended"
	visit.ended_at = int(candidate.clock_minutes)
	candidate.active_visit_id = ""
	return _commit(candidate, action, "接待已结束，经历已保存。", {"visit_id": visit.visit_id})

func _rest(action: Dictionary) -> Dictionary:
	if int(state.player.energy) >= int(content.rules.max_energy):
		return _fail("ENERGY_FULL", "精力已满，无需休息。")
	if not _has_time(int(content.rules.rest_minutes)):
		return _fail("NOT_ENOUGH_TIME", "今天剩余时间不足以休息，请处理接待后进入下一天。")
	var candidate: Dictionary = state.duplicate(true)
	candidate.player.energy = mini(int(content.rules.max_energy), int(candidate.player.energy) + int(content.rules.rest_energy))
	_advance(candidate, int(content.rules.rest_minutes))
	return _commit(candidate, action, "休息已完成并保存。", {})

func _next_day(action: Dictionary) -> Dictionary:
	if not state.active_visit_id.is_empty():
		return _fail("ACTIVE_VISIT", "还有未结束的接待，请先返回咨询区处理并结束接待。")
	var candidate: Dictionary = state.duplicate(true)
	var next_opening: int = (int(candidate.clock_minutes / 1440) + 1) * 1440 + int(content.rules.opening_minute)
	_advance(candidate, next_opening - int(candidate.clock_minutes))
	candidate.player.energy = int(content.rules.max_energy)
	return _commit(candidate, action, "已进入下一天，已处理到期的案例事项。", {})

func _candidate_visit(candidate: Dictionary) -> Dictionary:
	for visit: Dictionary in candidate.visits:
		if visit.visit_id == candidate.active_visit_id:
			return visit
	return {}

func _has_time(minutes: int) -> bool:
	return int(state.clock_minutes) % 1440 + minutes <= int(content.rules.closing_minute)

func _advance(candidate: Dictionary, minutes: int) -> void:
	candidate.clock_minutes = int(candidate.clock_minutes) + minutes
	if minutes > 0:
		DivinationEvents.advance(candidate, _divination.data)

func _commit(candidate: Dictionary, action: Dictionary, message: String, result: Dictionary) -> Dictionary:
	candidate.state_version = int(state.state_version) + 1
	var reply: Dictionary = {"success": true, "error_code": "", "message": message, "state_version": candidate.state_version, "result": result, "action_type": action.type}
	candidate.processed_actions[action.action_id] = reply.duplicate(true)
	var saved: Dictionary = SaveService.write_save(candidate)
	if not saved.success:
		return _fail(saved.get("error_code", "SAVE_FAILED"), "未能保存，本次动作未生效，可重试。" + saved.get("message", ""))
	state = candidate
	state_changed.emit()
	return reply

func _ok(message: String, result: Dictionary) -> Dictionary:
	return {"success": true, "error_code": "", "message": message, "state_version": state.get("state_version", 0), "result": result}

func _fail(error_code: String, message: String) -> Dictionary:
	action_failed.emit(message)
	return {"success": false, "error_code": error_code, "message": message, "state_version": state.get("state_version", 0), "result": {}}

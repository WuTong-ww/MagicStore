extends Node
## Sole authority for game rules. UI reads snapshots and submits commands.

signal state_changed
signal action_failed(message: String)

const ContentLoader = preload("res://scripts/core/content_loader.gd")
const MockProvider = preload("res://scripts/providers/mock_dialogue_provider.gd")

var state: Dictionary = {}
var content: Dictionary = {}
var content_error: String = ""
var dialogue_provider: RefCounted
var _provider_pending: bool = false

func _ready() -> void:
	var loaded: Dictionary = ContentLoader.load_content()
	if not loaded.success:
		content_error = loaded.message
		push_error(content_error)
		return
	content = loaded.content
	dialogue_provider = MockProvider.new()
	dialogue_provider.configure(content.topics)

func snapshot() -> Dictionary:
	return state.duplicate(true)

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
			return _reading(action)
		"end_visit":
			return _end_visit(action)
		"rest":
			return _rest(action)
		"next_day":
			return _next_day(action)
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
	if action.type == "start_visit" and not visit.is_empty():
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
		"schema_version": 1,
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
	state_changed.emit()
	return _ok(loaded.get("message", "存档已载入。"), {"save_id": state.save_id})

func _start_visit(action: Dictionary) -> Dictionary:
	var day: int = int(state.clock_minutes / 1440)
	for visit: Dictionary in state.visits:
		if visit.npc_id == content.npc.npc_id and int(visit.day) == day:
			return _fail("ALREADY_VISITED_TODAY", "照晚今天已经来过了。下一天可进行开发回访演示。")
	if int(state.clock_minutes) % 1440 >= int(content.rules.closing_minute):
		return _fail("NOT_ENOUGH_TIME", "今天已打烊，请进入下一天。")
	var candidate: Dictionary = state.duplicate(true)
	var opening: String = content.npc.opening if candidate.visits.is_empty() else content.npc.returning
	var visit: Dictionary = {
		"visit_id": make_id("visit"), "npc_id": content.npc.npc_id, "day": day,
		"phase": "talking", "clue_ids": [],
		"dialogue": [{"speaker": "npc", "text": opening}], "reading": {},
		"started_at": int(state.clock_minutes), "ended_at": -1
	}
	candidate.visits.append(visit)
	candidate.active_visit_id = visit.visit_id
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
	# Only public NPC details, visible dialogue and prior visit summaries are shared.
	var history: Array = []
	for previous: Dictionary in state.visits:
		if previous.phase == "ended":
			history.append({"visit_id": previous.visit_id, "day": previous.day, "dialogue": previous.dialogue.duplicate(true), "clue_ids": previous.clue_ids.duplicate()})
	return {"success": true, "input_text": input_text, "request": {
		"npc": content.npc.duplicate(true), "visit_id": visit.visit_id,
		"visible_history": history, "current_dialogue": visit.dialogue.duplicate(true),
		"input_text": input_text
	}}

func _complete_talk(action: Dictionary, input_text: String, response: Variant) -> Dictionary:
	if not response is Dictionary or not response.get("reply_text") is String or not response.get("intent") is String or not response.get("clue_ids") is Array or not response.get("needs_clarification") is bool or not response.get("error_code") is String:
		return _fail("PROVIDER_INVALID", "对话返回格式无效，未消耗时间。")
	if not response.error_code.is_empty():
		return _fail("PROVIDER_ERROR", "开发对话未能完成，未消耗时间。")
	if response.reply_text.is_empty() or response.reply_text.length() > 4000:
		return _fail("PROVIDER_INVALID", "对话文本长度无效。")
	var allowed_clues: Array = []
	var intent_found: bool = response.intent == "clarify"
	for topic: Dictionary in content.topics:
		if topic.topic_id == response.intent:
			intent_found = true
			allowed_clues = topic.clue_ids
	if not intent_found:
		return _fail("PROVIDER_INVALID", "对话返回了未配置的话题。")
	for clue_id: Variant in response.clue_ids:
		if not clue_id is String or not content.clues.has(clue_id) or not clue_id in allowed_clues:
			return _fail("PROVIDER_INVALID", "对话返回了未授权的线索。")
	var candidate: Dictionary = state.duplicate(true)
	var visit: Dictionary = _candidate_visit(candidate)
	var new_clues: Array = []
	for clue_id: String in response.clue_ids:
		if not clue_id in visit.clue_ids:
			visit.clue_ids.append(clue_id)
			new_clues.append(clue_id)
	visit.dialogue.append({"speaker": "player", "text": input_text})
	visit.dialogue.append({"speaker": "npc", "text": response.reply_text})
	_advance(candidate, int(content.rules.talk_minutes))
	var message: String = "交谈已保存。" if new_clues.is_empty() else "获得新线索，交谈已保存。"
	return _commit(candidate, action, message, {"reply_text": response.reply_text, "clue_ids": new_clues, "needs_clarification": response.needs_clarification})

func _reading(action: Dictionary) -> Dictionary:
	var current: Dictionary = active_visit()
	if current.is_empty():
		return _fail("NO_VISIT", "请先接待顾客。")
	var rules: Dictionary = content.rules
	if int(state.npcs[current.npc_id].coins) < int(rules.reading_fee):
		return _fail("NPC_FUNDS_LOW", "顾客金币不足，本次未结算。")
	if int(state.player.energy) < int(rules.reading_energy):
		return _fail("ENERGY_LOW", "精力不足，请先休息。本次未结算。")
	if not _has_time(int(rules.reading_minutes)):
		return _fail("NOT_ENOUGH_TIME", "今天剩余营业时间不足，本次未结算。")
	var candidate: Dictionary = state.duplicate(true)
	var visit: Dictionary = _candidate_visit(candidate)
	# Stable per-visit demo draw: retry after a failed save also chooses the same card.
	var card: Dictionary = content.cards[posmod(String(visit.visit_id).hash(), content.cards.size())]
	var reading: Dictionary = {
		"reading_id": "reading_" + String(visit.visit_id).trim_prefix("visit_"),
		"card_id": card.card_id, "title": card.title, "text": card.text,
		"fee": int(rules.reading_fee), "energy_cost": int(rules.reading_energy), "minutes": int(rules.reading_minutes)
	}
	candidate.npcs[visit.npc_id].coins -= int(rules.reading_fee)
	candidate.player.coins += int(rules.reading_fee)
	candidate.player.energy -= int(rules.reading_energy)
	_advance(candidate, int(rules.reading_minutes))
	visit.reading = reading
	visit.phase = "reading_done"
	return _commit(candidate, action, "结算和牌面已保存。", {"reading": reading.duplicate(true), "visit_id": visit.visit_id})

func _end_visit(action: Dictionary) -> Dictionary:
	if active_visit().is_empty():
		return _fail("NO_VISIT", "没有正在进行的接待。")
	var candidate: Dictionary = state.duplicate(true)
	var visit: Dictionary = _candidate_visit(candidate)
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
	return _commit(candidate, action, "已进入下一天。照晚可再次来店（开发案例）。", {})

func _candidate_visit(candidate: Dictionary) -> Dictionary:
	for visit: Dictionary in candidate.visits:
		if visit.visit_id == candidate.active_visit_id:
			return visit
	return {}

func _has_time(minutes: int) -> bool:
	return int(state.clock_minutes) % 1440 + minutes <= int(content.rules.closing_minute)

func _advance(candidate: Dictionary, minutes: int) -> void:
	candidate.clock_minutes = int(candidate.clock_minutes) + minutes

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

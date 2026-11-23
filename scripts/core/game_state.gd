extends Node
## Sole authority for game rules. UI reads snapshots and submits commands.

signal state_changed
signal action_failed(message: String)
signal presentation_events_committed(events: Array)

const ContentLoader = preload("res://scripts/core/content_loader.gd")
const MockProvider = preload("res://scripts/providers/mock_dialogue_provider.gd")
const DivinationCatalog = preload("res://scripts/divination/catalog.gd")
const DivinationSession = preload("res://scripts/divination/session.gd")
const DivinationView = preload("res://scripts/divination/case_view.gd")
const DivinationEvents = preload("res://scripts/divination/event_rules.gd")
const Shop = preload("res://scripts/shop/shop.gd")
const PeopleBridge = preload("res://scripts/shop/people_bridge.gd")
const People = preload("res://scripts/people/people.gd")
const Memory = preload("res://scripts/people/memory.gd")
const HttpProvider = preload("res://scripts/providers/http_dialogue_provider.gd")
const ApiEndpoint = preload("res://scripts/providers/api_endpoint.gd")
const DialoguePolicy = preload("res://scripts/providers/dialogue_policy.gd")
const PersonProvider = preload("res://scripts/providers/http_person_provider.gd")
const GeneratedPerson = preload("res://scripts/people/generated_person.gd")
const GeneratedCases = preload("res://scripts/divination/generated_cases.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
const SHOP_ACTIONS := ["procure_item", "receive_material_gift", "gather_material", "sell_material", "register_demand", "research_recipe", "craft_item", "sell_product", "use_product", "review_case"]
const PEOPLE_ACTIONS := ["book_arrival", "save_appearance", "wait", "invite_contact"]
var shop_config: Dictionary = {}
var people_config: Dictionary = {}
var _api_url := ""
var _api_model := ""
var _api_key := ""

var state: Dictionary = {}
var content: Dictionary = {}
var content_error: String = ""
var dialogue_provider: RefCounted
var _divination: DivinationSession
var _provider_pending: bool = false
var people_generator: RefCounted
var _generation_enabled := true
var _generation_concurrency := 2
var _generation_epoch := 0
var _generation_jobs: Dictionary = {}
var _generation_ready: Array = []
var _generation_notice := ""
var _generation_retry_at := 0
var _generation_network_retry_at := 0
var _generation_attempts: Dictionary = {}
var _generation_sequence := 0
var _generation_last_pump := 0
var _gateway_url := ""
var _gateway_token := ""
var generation_config: Dictionary = {"enabled":true,"concurrency":2,"ready_target":6,"new_people_per_day":8,"max_attempts_per_day":16,"min_lead_minutes":30,"arrival_spacing_minutes":30}
var _generation_role_hints: Array = ["小剧场道具师","自行车修理师","社区厨房主理人","夜校教师","园艺师","木工学徒","公交司机","自由插画师"]

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
	shop_config = Shop.load_config()
	people_config = People.load_config()
	var generation_json := JSON.new()
	if generation_json.parse(FileAccess.get_file_as_string("res://data/people/generation.json")) == OK and generation_json.data is Dictionary:
		var configured: Dictionary = generation_json.data
		if configured.get("role_hints") is Array and not configured.role_hints.is_empty() and configured.role_hints.size() <= 30 and configured.role_hints.all(func(value: Variant) -> bool: return value is String and not value.is_empty() and value.length() <= 24):
			_generation_role_hints = configured.role_hints.duplicate()
		if configured.get("enabled") is bool and (configured.get("concurrency") is float or configured.get("concurrency") is int):
			generation_config.enabled = configured.get("enabled",true)
			for field: String in ["concurrency","ready_target","new_people_per_day","max_attempts_per_day","min_lead_minutes","arrival_spacing_minutes"]:
				if configured.get(field) is float or configured.get(field) is int:
					generation_config[field] = int(configured[field])
	generation_config.concurrency = clampi(int(generation_config.concurrency),1,3)
	generation_config.ready_target = clampi(int(generation_config.ready_target),1,12)
	generation_config.new_people_per_day = clampi(int(generation_config.new_people_per_day),1,20)
	generation_config.max_attempts_per_day = clampi(int(generation_config.max_attempts_per_day),1,40)
	generation_config.min_lead_minutes = clampi(int(generation_config.min_lead_minutes),15,180)
	generation_config.arrival_spacing_minutes = clampi(int(generation_config.arrival_spacing_minutes),15,120)
	_generation_enabled = generation_config.enabled
	_generation_concurrency = generation_config.concurrency
	if not OS.get_environment("MAGIC_GATEWAY_URL").is_empty():
		_gateway_url = OS.get_environment("MAGIC_GATEWAY_URL")
		_gateway_token = OS.get_environment("MAGIC_GATEWAY_TOKEN")
		dialogue_provider = HttpProvider.new()
		dialogue_provider.configure(self, catalog.topics + content.topics)
	_reset_people_generator()

## Engine and verification snapshot. UI must use player_snapshot and divination_view.
func snapshot() -> Dictionary:
	return state.duplicate(true)

func player_snapshot() -> Dictionary:
	var visible := state.duplicate(false)
	visible.erase("divination")
	visible.erase("processed_actions")
	visible.erase("people")
	return visible.duplicate(true)

func people_view() -> Dictionary:
	return PeopleBridge.public_view(state) if not state.is_empty() else {}

func departure_risk(minutes: int) -> int:
	if minutes <= 0 or state.is_empty():
		return 0
	var until := int(state.clock_minutes) + minutes
	var count := 0
	for row: Dictionary in state.get("people",{}).get("arrivals",{}).values():
		if row.get("state") in ["queued","outside"] and int(row.get("deadline",-1)) <= until:
			count += 1
	return count

func contact_invitation() -> Dictionary:
	return PeopleBridge.contact_invitation(state,people_config) if not state.is_empty() else {}

func shop_view() -> Dictionary:
	return Shop.view(state, shop_config) if not state.is_empty() else {}

func provider_status() -> Dictionary:
	return dialogue_provider.status() if dialogue_provider.has_method("status") else {"mode": "offline", "reason": "本地对话"}

func configure_network(url: String, token: String) -> void:
	cancel_dialogue()
	_api_url = ""
	_api_model = ""
	_api_key = ""
	_gateway_url = url.strip_edges()
	_gateway_token = token
	if url.strip_edges().is_empty():
		dialogue_provider = MockProvider.new()
		dialogue_provider.configure(_divination.data.topics + content.topics)
	else:
		dialogue_provider = HttpProvider.new()
		dialogue_provider.configure(self, _divination.data.topics + content.topics, url, token)
	_reset_people_generator()
	state_changed.emit()

func connection_settings() -> Dictionary:
	return {"url":_api_url,"model":_api_model,"key_set":not _api_key.is_empty()}

func preview_api_url(url: String) -> Dictionary:
	return ApiEndpoint.normalize_chat_url(url)

func configure_api(url: String, model: String, api_key: String) -> Dictionary:
	var normalized := preview_api_url(url)
	if not normalized.success:
		return normalized
	url = normalized.url
	model = model.strip_edges().trim_suffix("\\").strip_edges()
	for suffix: String in ["（推荐）","(推荐)","（recommended）","(recommended)"]:
		model = model.trim_suffix(suffix).strip_edges()
	api_key = api_key.strip_edges()
	if model.contains("\n") or model.contains("\r") or api_key.contains("\n") or api_key.contains("\r") or url.contains("\n") or url.contains("\r") or url.contains(" ") or url.contains("@") or url.contains("?") or url.contains("#"):
		return {"success":false,"message":"接口地址、模型名称和密钥中不能夹带换行或额外内容。"}
	if not url.is_empty() and (model.is_empty() or (api_key.is_empty() and (_api_key.is_empty() or url != _api_url))):
		return {"success":false,"message":"请填写模型名称和 API Key。"}
	cancel_dialogue()
	_api_key = api_key if not api_key.is_empty() else (_api_key if url == _api_url else "")
	_api_url = url
	_api_model = model
	if url.is_empty():
		_api_key = ""
		configure_network("", "")
	else:
		_gateway_url = ""
		_gateway_token = ""
		dialogue_provider = HttpProvider.new()
		dialogue_provider.configure_api(self,_divination.data.topics + content.topics,url,model,_api_key)
		_reset_people_generator()
		state_changed.emit()
	return {"success":true,"message":"设置好了。"}

func people_generation_settings() -> Dictionary:
	return {"enabled":_generation_enabled,"concurrency":_generation_concurrency}

func set_people_generation_options(enabled: bool, concurrency: int = 2) -> void:
	_generation_enabled = enabled
	_generation_concurrency = clampi(concurrency, 1, 3)
	_reset_people_generator()
	state_changed.emit()

func _reset_people_generator() -> void:
	_generation_epoch += 1
	if people_generator != null:
		if people_generator.has_method("shutdown"):
			people_generator.shutdown()
		else:
			people_generator.cancel_all()
	people_generator = null
	_generation_jobs.clear()
	_generation_ready.clear()
	_generation_retry_at = 0
	_generation_network_retry_at = 0
	_generation_notice = ""
	if not _generation_enabled:
		return
	if _api_url.is_empty() and _gateway_url.is_empty():
		return
	people_generator = PersonProvider.new()
	if not _api_url.is_empty():
		people_generator.configure(self,_api_url,_api_model,_api_key,_generation_concurrency)
	else:
		people_generator.configure_gateway(self,_gateway_url,_gateway_token,_generation_concurrency)
	people_generator.job_ready.connect(_person_ready)
	people_generator.job_failed.connect(_person_failed)

func people_generation_status() -> Dictionary:
	var ready_count := 0
	var upcoming := {}
	for arrival: Dictionary in state.get("people",{}).get("arrivals",{}).values():
		if arrival.get("state") in ["planned","queued","in_service"]:
			upcoming[arrival.npc_id] = true
	for profile: Dictionary in state.get("people",{}).get("profiles",{}).values():
		if profile.get("generation_member") == "person" and not profile.get("met",false) and upcoming.has(profile.npc_id):
			ready_count += 1
	return {"enabled":_generation_enabled,"configured":people_generator != null,"pending":_generation_jobs.size(),"ready":ready_count,
		"awaiting_commit":_generation_ready.size(),"concurrency":_generation_concurrency,"notice":_generation_notice}

func _person_ready(job_id: String, token: String, bundle: Dictionary, provenance: Dictionary) -> void:
	if not _generation_jobs.has(job_id) or _generation_jobs[job_id].token != token:
		return
	_generation_ready.append({"job_id":job_id,"token":token,"bundle":bundle.duplicate(true),"provenance":provenance.duplicate(true)})

func _person_failed(job_id: String, token: String, code: String) -> void:
	if not _generation_jobs.has(job_id) or _generation_jobs[job_id].token != token:
		return
	_generation_jobs.erase(job_id)
	# A rejected setting is not a rate-limit or an outage. Discard that draft
	# and refill its slot promptly with a new job, within the daily attempt
	# budget. Existing network backoff must not be shortened by a later veto.
	var delay := 1000 if code in ["INVALID_BUNDLE","REVIEW_REJECTED","ADMISSION_REJECTED","INVALID_RESPONSE"] else 30000
	_generation_network_retry_at = maxi(_generation_network_retry_at,Time.get_ticks_msec()+delay)
	_generation_notice = "新来客还没准备好，稍后再试。现有来客照常接待。"

func pump_background_people(ui_busy: bool = false, force: bool = false) -> void:
	# The main UI calls this heartbeat; headless rule tests never start network
	# work implicitly. Job results wait until no foreground action is committing.
	if people_generator == null or state.is_empty():
		return
	var now := Time.get_ticks_msec()
	var foreground := ui_busy or _provider_pending
	people_generator.set_dialogue_busy(foreground)
	if not force and now - _generation_last_pump < 250:
		return
	_generation_last_pump = now
	if foreground:
		return
	if not _generation_ready.is_empty() and now >= _generation_retry_at:
		_admit_next_person()
	if now < _generation_retry_at:
		return
	if now < _generation_network_retry_at:
		return
	var status := people_generation_status()
	var desired := int(generation_config.ready_target) - int(status.ready) - _generation_jobs.size()
	desired = mini(desired, _generation_slots().size() - _generation_jobs.size())
	var planned_today := 0
	var day := floori(float(state.clock_minutes) / 1440.0)
	for row: Dictionary in state.people.get("generated_people",{}).values():
		if floori(float(row.get("created_at",row.get("at",0))) / 1440.0) == day:
			planned_today += 1
	desired = mini(desired, int(generation_config.new_people_per_day) - planned_today - _generation_jobs.size())
	var attempt_key := "%s:%d" % [state.save_id,day]
	desired = mini(desired,int(generation_config.max_attempts_per_day)-int(_generation_attempts.get(attempt_key,0)))
	for index in range(maxi(0,desired)):
		var job_id := make_id("person")
		var token := "%s:%d" % [state.save_id,_generation_epoch]
		var avoid_names: Array = []
		for profile: Dictionary in state.people.profiles.values():
			avoid_names.append(str(profile.name))
		var themes := ["日常工作里的一个取舍", "邻里之间的一次小约定", "搬家整理时放不下的一件事", "想和熟人商量却迟迟没开口的事"]
		var theme: String = themes[_generation_sequence % themes.size()]
		var role_hint: String = _generation_role_hints[_generation_sequence % _generation_role_hints.size()]
		var context := {"generation_id":job_id,"avoid_names":avoid_names,"theme_hint":"%s。职业可以参考%s或相近工作，写出这一行自己的日常细节，不要统一成快递驿站或旧友写信。" % [theme,role_hint]}
		_generation_jobs[job_id] = {"token":token,"save_id":state.save_id}
		if not people_generator.enqueue(job_id,context,token):
			_generation_jobs.erase(job_id)
		else:
			_generation_attempts[attempt_key] = int(_generation_attempts.get(attempt_key,0))+1
			_generation_sequence += 1

func _admit_next_person() -> void:
	var row: Dictionary = _generation_ready[0]
	if not _generation_jobs.has(row.job_id) or _generation_jobs[row.job_id].token != row.token or _generation_jobs[row.job_id].save_id != state.save_id:
		_generation_ready.pop_front()
		return
	var slots := _generation_slots()
	if slots.is_empty():
		# A reviewed draft may wait for a later day, but cannot create traffic.
		return
	var action := {"type":"admit_generated_person","action_id":"admit_" + str(row.job_id),"job_id":row.job_id,"slot_id":slots[0]}
	# This internal action has no network await; admission stays atomic with
	# foreground actions while using the same authorized async command boundary.
	var committed: Dictionary = await execute_action_async(action)
	if not committed.success:
		if committed.get("error_code") == "ADMISSION_REJECTED":
			_generation_ready.pop_front()
			_person_failed(row.job_id,row.token,"ADMISSION_REJECTED")
			return
		_generation_retry_at = Time.get_ticks_msec() + 3000
		_generation_notice = "新来客尚未保存，稍后重试；店铺进度没有改变。"
		return
	_generation_ready.pop_front()
	_generation_jobs.erase(row.job_id)
	_generation_notice = "新来客已经约好到店时间，可以在候客簿中留意。"

func _generation_slots() -> Array[String]:
	var slots: Array[String] = []
	var people: Dictionary = state.get("people", {})
	for id: String in people.get("arrivals", {}):
		var arrival: Dictionary = people.arrivals[id]
		if GeneratedPerson._slot_available(people, id, int(arrival.get("at", -1))):
			slots.append(id)
	slots.sort_custom(func(a: String, b: String) -> bool:
		var first: int = people.arrivals[a].at
		var second: int = people.arrivals[b].at
		return first < second if first != second else a < b)
	return slots

func _admit_generated_person(action: Dictionary) -> Dictionary:
	var job_id: String = str(action.get("job_id", ""))
	var slot_id: String = str(action.get("slot_id", ""))
	var job: Dictionary = _generation_jobs.get(job_id, {})
	var ready: Dictionary = {}
	for row: Dictionary in _generation_ready:
		if row.job_id == job_id and row.token == job.get("token") and job.get("save_id") == state.save_id:
			ready = row
			break
	if ready.is_empty() or slot_id.is_empty() or not state.people.arrivals.has(slot_id):
		return _fail("ADMISSION_REJECTED", "人物草稿或审核来源无效。")
	var candidate := state.duplicate(true)
	var applied := GeneratedPerson.apply(candidate.people, people_config, job_id, ready.bundle, ready.provenance, int(candidate.people.arrivals[slot_id].at), slot_id)
	if not applied.get("success", false):
		return _fail("ADMISSION_REJECTED", applied.get("message", ""))
	var committed := _commit(candidate, action, "一位新来客已经约好到店时间。", applied)
	if committed.success:
		_sync_generated_catalog()
	return committed

func _sync_generated_catalog() -> void:
	if _divination == null:
		return
	_divination.sync_generated(state)
	var topics: Array = _divination.data.topics + content.topics
	if dialogue_provider.has_method("update_topics"):
		dialogue_provider.update_topics(topics)
	elif dialogue_provider is MockProvider:
		dialogue_provider.configure(topics)

func ledger_view() -> Array:
	return (state.get("shop", {}).get("ledger", []) + state.get("divination", {}).get("ledger", [])).duplicate(true)

func cancel_dialogue() -> void:
	if dialogue_provider.has_method("cancel"):
		dialogue_provider.cancel()

func divination_view(visit_id: String = "") -> Dictionary:
	for visit: Dictionary in state.get("visits", []):
		if visit.visit_id == (state.active_visit_id if visit_id.is_empty() else visit_id):
			var projected := DivinationView.project(_divination, state, visit)
			if projected.get("guest") is Dictionary:
				projected.guest["appearance"] = state.get("people",{}).get("profiles",{}).get(visit.npc_id,{}).get("appearance",{}).duplicate(true)
				projected.guest["mood"] = DialoguePolicy.mood_from_turns(visit.get("dialogue",[]))
			return projected
	return {}

## Player-facing next questions. Model text stays with its successful dialogue
## action and visit; newly unlocked directions can fill any remaining buttons.
func conversation_questions() -> Array:
	var visit := active_visit()
	if visit.is_empty():
		return []
	var case: Dictionary = state.divination.cases[visit.visit_id]
	var context := _question_context(state,visit)
	var generated: Array = DialoguePolicy.parse_questions(visit.get("followup_questions",[]),context)
	var result: Array = []
	var seen := {}
	for row: Dictionary in generated:
		result.append({"topic_id":row.topic_id,"label":row.text,"enabled":true,"generated":true})
		seen[row.topic_id] = true
	var latest: Dictionary = state.processed_actions.get(visit.get("followup_action_id",""),{}).get("result",{})
	for row: Dictionary in context.question_topics:
		var topic: Dictionary = _divination.data.topic_index[row.topic_id]
		if topic.get("requires_clue","") in latest.get("clue_ids",[]) and not seen.has(row.topic_id):
			if result.size() >= 3:
				seen.erase(result.pop_back().topic_id)
			result.push_front({"topic_id":row.topic_id,"label":_question_label(row.label),"enabled":true,"generated":false})
			seen[row.topic_id] = true
			break
	var talked := {}
	for turn: Dictionary in case.conversation:
		talked[turn.intent] = true
	var local: Array = context.question_topics.duplicate(true)
	local.sort_custom(func(left: Dictionary,right: Dictionary) -> bool:
		var left_score := (10 if talked.has(left.topic_id) else 0) + (1 if left.topic_id.contains("birth") else 0)
		var right_score := (10 if talked.has(right.topic_id) else 0) + (1 if right.topic_id.contains("birth") else 0)
		return left_score < right_score)
	for row: Dictionary in local:
		if result.size() >= 3:
			break
		if not seen.has(row.topic_id):
			result.append({"topic_id":row.topic_id,"label":_question_label(row.label),"enabled":true,"generated":false})
			seen[row.topic_id] = true
	return result

func _question_label(label: String) -> String:
	if label == "核对侧门告示":
		return "能核对下入口告示吗？"
	if label == "征求出生资料":
		return "方便说说出生时间地点吗？"
	if label == "你提到的这位熟人，能聊聊吗？":
		return "能聊聊这位熟人吗？"
	if label == "你最放不下的是哪一处？":
		return "你最放不下什么？"
	if label == "能说说具体的经过吗？":
		return "能说说经过吗？"
	if label == "有没有能核对的依据？":
		return "有依据能核对吗？"
	return label

func _question_context(snapshot_state: Dictionary, visit: Dictionary) -> Dictionary:
	var case: Dictionary = snapshot_state.divination.cases[visit.visit_id]
	var allowed: Dictionary = _divination.talks(visit,case,int(snapshot_state.clock_minutes),snapshot_state)
	var choices: Array = []
	for id: String in _divination.data.cases[case.case_id].topic_ids:
		if allowed.has(id):
			choices.append({"topic_id":id,"label":str(_divination.data.topic_index[id].label)})
	var sources: Array = []
	var same_person: Array = snapshot_state.visits.filter(func(row: Dictionary) -> bool: return row.npc_id == visit.npc_id).slice(-5)
	for previous: Dictionary in same_person:
		for turn: Dictionary in previous.dialogue.slice(-20):
			if turn.speaker == "npc":
				sources.append({"source_id":"known_statement_"+str(sources.size()),"text":str(turn.text),"kind":"statement"})
		for clue: String in previous.clue_ids:
			if _divination.data.clues.has(clue):
				sources.append({"source_id":"known_clue_"+clue,"text":str(_divination.data.clues[clue].text),"kind":"clue"})
	var guardrails: Array = ["替你留了靠窗的位置","侧门","临时入口告示","另一处档案柜编号"]
	guardrails.append_array(GeneratedCases.private_anchors(case))
	return {"question_topics":choices,"sources":sources,"_guardrails":guardrails}

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
	prepared.request["action_id"] = action.action_id
	prepared.request["request_id"] = make_id("request")
	_provider_pending = true
	if people_generator != null:
		people_generator.set_dialogue_busy(true)
	var response: Variant = await dialogue_provider.request_reply(prepared.request)
	_provider_pending = false
	if people_generator != null:
		people_generator.set_dialogue_busy(false)
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
		"delete_game":
			return _delete_game(action)
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
		"admit_generated_person":
			return _admit_generated_person(action)
	if action.type in DivinationSession.ACTIONS:
		return _divination_action(action)
	if action.type == "start_arrival":
		var candidate := state.duplicate(true)
		var proposal := action.duplicate(true)
		proposal["visit_id"] = make_id("visit")
		var outcome: Dictionary = PeopleBridge.start(candidate, proposal, _divination, people_config)
		if not outcome.success:
			return _fail(outcome.error_code, outcome.message)
		return _commit(candidate, action, outcome.message, outcome.result,outcome.get("presentation_events",[]))
	if action.type in SHOP_ACTIONS or action.type in PEOPLE_ACTIONS:
		return _shop_action(action)
	if action.type == "use_unlocked_option":
		return _use_unlocked_option(action)
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
	if not _initialize_integrated(candidate,true):
		return _fail("INVALID_APPEARANCE",Appearance.load_config().get("copy",{}).get("migration_failed",content_error))
	candidate = SaveService._normalize_numbers(candidate)
	var saved: Dictionary = SaveService.write_save(candidate)
	if not saved.success:
		return _fail(saved.get("error_code", "SAVE_FAILED"), "新建失败，原存档仍保留。" + saved.get("message", ""))
	state = candidate
	_sync_generated_catalog()
	_reset_people_generator()
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
	var loaded_candidate: Dictionary = loaded.state.duplicate(true)
	_divination.sync_generated(loaded_candidate)
	if int(loaded_candidate.schema_version) == 1:
		_divination.initialize(loaded_candidate)
	if not _initialize_integrated(loaded_candidate):
		_sync_generated_catalog()
		return _fail("INVALID_APPEARANCE",Appearance.load_config().get("copy",{}).get("migration_failed",content_error))
	state = SaveService._normalize_numbers(loaded_candidate)
	_sync_generated_catalog()
	_reset_people_generator()
	state_changed.emit()
	return _ok(loaded.get("message", "存档已载入。"), {"save_id": state.save_id})

func _delete_game(action: Dictionary) -> Dictionary:
	if not action.get("save_id") is String:
		return _fail("INVALID_SAVE_ID", "请先选择要删除的存档。")
	var was_active: bool = state.get("save_id", "") == action.save_id
	var deleted: Dictionary = SaveService.delete_save(action.save_id)
	if not deleted.success:
		return _fail(deleted.error_code, deleted.message)
	if was_active:
		state = {}
		_sync_generated_catalog()
		_reset_people_generator()
		state_changed.emit()
	return _ok(deleted.message, {"deleted_save_id":action.save_id,"active_deleted":was_active,"cleanup_pending":deleted.get("cleanup_pending",false)})

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
	var presentation_events: Array = []
	if not PeopleBridge.register_legacy_visit(candidate, visit, _divination,presentation_events,people_config):
		return _fail("FAMILY_QUOTA_UNAVAILABLE",People._family_policy(people_config).copy.ratio_unavailable)
	return _commit(candidate, action, "接待已开始并保存。", {"visit_id": visit.visit_id},presentation_events)

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
	var allowed := _divination.talks(visit, case, int(state.clock_minutes), state)
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
	history = history.slice(-5)
	var request := {
		"npc": _divination.guest_view(visit.npc_id, case.case_id, case.get("public_npc", {})), "visit_id": visit.visit_id, "case_id": case.case_id,
		"visible_history": history, "current_dialogue": visit.dialogue.duplicate(true),
		"input_text": input_text, "topic_id": topic_id, "allowed_intents": allowed.keys(),
		"allowed_clue_ids": clues, "allowed_branch_ids": branches, "allowed_effects": allowed
	}
	if state.get("people", {}).get("profiles", {}).has(visit.npc_id):
		request["known_memories"] = Memory.dialogue_context(state.people, visit.npc_id, 16)
		var persona := People.model_persona(state.people, visit.npc_id)
		request.npc.merge({"personality": persona.get("personality", ""), "speech_style": persona.get("speech_style", "")})
		for field: String in ["catchphrase","information_boundaries"]:
			if persona.has(field):
				request.npc[field] = persona[field].duplicate(true) if persona[field] is Array else persona[field]
		var family_guard := People.model_family_guard(state.people,visit.npc_id)
		if not family_guard.is_empty():
			request["_family_guard"] = family_guard
		var profile: Dictionary = state.people.profiles[visit.npc_id]
		request["relationship"] = {"familiarity":int(profile.familiarity),"trust":int(profile.trust)}
	if visit.npc_id == "npc_lin" and str(request.npc.get("speech_style", "")).is_empty():
		request.npc["speech_style"] = "说话温和，有点迟疑，愿意听人慢慢问。谈到旧书时更自在，谈到那位朋友时会斟酌措辞。用平常的口语，不堆神秘学术语。"
	request["safe_persona"] = {}
	for field: String in ["name","role","personality","speech_style"]:
		request.safe_persona[field] = str(request.npc.get(field,""))
	for field: String in ["catchphrase","information_boundaries"]:
		if request.npc.has(field):
			request.safe_persona[field] = request.npc[field].duplicate(true) if request.npc[field] is Array else request.npc[field]
	# UI labels may include developer annotations; they are not the NPC's job title.
	request.safe_persona.role = str(request.safe_persona.role).split(" · ")[0]
	var sources: Array = []
	var generated_profile: Dictionary = state.get("people",{}).get("profiles",{}).get(visit.npc_id,{})
	if generated_profile.has("generation_id"):
		# Only approved public biographical fields enter dialogue. The complete
		# creation package also holds private case facts and must stay local.
		for field: String in ["background","preferences"]:
			var value: Variant = generated_profile.get(field,"")
			var text: String = "、".join(value) if value is Array else str(value)
			if not text.is_empty():
				sources.append({"source_id":"profile:" + field,"kind":"persona","text":text,"certainty":"approved_public_profile","audience":"both"})
	if visit.npc_id == "npc_lin":
		sources.append({"source_id":"knowledge:book_repair","kind":"persona","text":"受潮的纸张处理时要轻一些，用力容易使纸页破损。纸页通常需要一张张慢慢晾干，急不得。这是旧书修复的一般经验，不代表本案那本书已经裂开或被揭开过。","certainty":"general_professional_knowledge","audience":"both"})
	var shared_clues := {}
	for previous: Dictionary in state.visits:
		if previous.npc_id != visit.npc_id:
			continue
		for id: String in previous.clue_ids:
			shared_clues[id] = true
	for id: String in shared_clues:
		var clue: Dictionary = _divination.data.clues.get(id,{})
		if not clue.is_empty():
			sources.append({"source_id":"clue:" + id,"kind":"clue","text":str(clue.text),"certainty":"disclosed_clue","audience":"both"})
	for previous: Dictionary in history:
		var turns: Array = previous.dialogue
		for index: int in range(maxi(0,turns.size()-12),turns.size()):
			if turns[index].speaker == "npc":
				sources.append({"source_id":"history:%s:%d" % [previous.visit_id,index],"kind":"history","text":str(turns[index].text).left(600),"certainty":"character_statement","audience":"both"})
	for memory: Dictionary in request.get("known_memories",[]):
		if memory.get("audience") == "both":
			sources.append({"source_id":"memory:" + str(memory.memory_id),"kind":memory.kind,"topic_id":str(memory.get("topic_id","")),"text":str(memory.text),"certainty":"shared_statement" if memory.kind in ["statement","prediction"] else "disclosed_report","audience":"both"})
	for index: int in range(maxi(0,visit.dialogue.size()-20),visit.dialogue.size()):
		if visit.dialogue[index].speaker == "npc":
			sources.append({"source_id":"history:%s:%d" % [visit.visit_id,index],"kind":"statement","text":str(visit.dialogue[index].text).left(600),"certainty":"character_statement","audience":"both"})
	request["dialogue_sources"] = sources
	if _divination.data.cases[case.case_id].get("generated",false):
		# Only our trusted gateway sees this catalog. Its classifier sees labels,
		# and only the selected authorized topic reaches the dialogue generator.
		var custom: Array = []
		for topic: Dictionary in _divination.data.topics:
			if allowed.has(topic.topic_id):
				var row := {}
				for field: String in ["topic_id","label","reply_text","keywords","clue_ids","branch_id","default_mood"]:
					if topic.has(field):
						row[field] = topic[field]
				custom.append(row)
		request["custom_topics"] = custom
	# These anchors are local-only rejection rules, never prompt content. A selected
	# topic can authorize the same wording; unknown clues cannot be volunteered.
	request["private_guardrails"] = ["替你留了靠窗的位置", "侧门", "临时入口告示", "另一处档案柜编号"]
	request.private_guardrails.append_array(GeneratedCases.private_anchors(case))
	return {"success": true, "input_text": input_text, "request": request}

func _complete_talk(action: Dictionary, input_text: String, response: Variant) -> Dictionary:
	if not response is Dictionary or not response.get("reply_text") is String or not response.get("intent") is String or not response.get("clue_ids") is Array or not response.get("needs_clarification") is bool or not response.get("error_code") is String:
		return _fail("PROVIDER_INVALID", "对话返回格式无效，未消耗时间。")
	if not response.error_code.is_empty():
		if response.error_code == "CANCELLED":
			return _fail("CANCELLED", "已取消这次对话，未消耗时间。")
		return _fail("PROVIDER_ERROR", "对话未能完成，未消耗时间。")
	if response.reply_text.is_empty() or response.reply_text.length() > 4000:
		return _fail("PROVIDER_INVALID", "对话文本长度无效。")
	for key in response:
		if not key in ["reply_text", "intent", "clue_ids", "needs_clarification", "error_code", "branch_id", "followup_questions", "mood"]:
			return _fail("PROVIDER_INVALID", "对话返回了案例契约之外的提案。")
	var mood: Variant = response.get("mood",DialoguePolicy.default_mood())
	if not DialoguePolicy.mood_valid(mood):
		return _fail("PROVIDER_INVALID", "对话返回了案例契约之外的提案。")
	var active := active_visit()
	var case: Dictionary = state.divination.cases[active.visit_id]
	var allowed := _divination.talks(active, case, int(state.clock_minutes), state)
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
	visit.dialogue.append({"speaker": "npc", "text": response.reply_text,"mood":mood})
	_divination.record_talk(candidate, visit, action, response, new_clues)
	PeopleBridge.record_talk(candidate, visit, action, response)
	PeopleBridge.observe(candidate, action, "question", response.intent, allowed.keys())
	# Async callers arrive here only after the provider await and stale-version
	# check. Nothing in this transaction's collector survives across that await.
	var presentation_events: Array = _advance(candidate, int(content.rules.talk_minutes))
	var questions: Array = DialoguePolicy.parse_questions(response.get("followup_questions",[]),_question_context(candidate,visit))
	visit["followup_questions"] = questions
	visit["followup_action_id"] = action.action_id
	var message: String = "交谈已保存。" if new_clues.is_empty() else "获得新线索，交谈已保存。"
	return _commit(candidate, action, message, {"visit_id": visit.visit_id, "reply_text": response.reply_text, "clue_ids": new_clues, "intent": response.intent, "branch_id": branch, "needs_clarification": response.needs_clarification,"followup_questions":questions,"mood":mood},presentation_events)

func _divination_action(action: Dictionary) -> Dictionary:
	var candidate: Dictionary = state.duplicate(true)
	var visit: Dictionary = _candidate_visit(candidate)
	if action.type == "give_advice" and not visit.is_empty():
		var case: Dictionary = candidate.divination.cases[visit.visit_id]
		PeopleBridge.observe(candidate, action, "advice", str(action.get("advice_key", "")), _divination.data.cases[case.case_id].get("event", {}).get("advice", {}).keys())
	elif action.type == "quote_service":
		PeopleBridge.observe(candidate, action, "service", str(action.get("method_id", "")), _divination.data.methods.keys())
	var outcome := _divination.handle(candidate, visit, action)
	if not outcome.success:
		return _fail(outcome.error_code, outcome.message)
	var presentation_events: Array = _advance(candidate, outcome.minutes)
	return _commit(candidate, action, outcome.message, outcome.result,presentation_events)

func _end_visit(action: Dictionary) -> Dictionary:
	if active_visit().is_empty():
		return _fail("NO_VISIT", "没有正在进行的接待。")
	if action.has("return_at") and (not action.get("guest_agreed",false) is bool or not action.get("guest_agreed",false) or not People._integer(action.return_at, int(state.clock_minutes)+1,2147483647) or next_return_time() == 0):
		return _fail("RETURN_NOT_AGREED", "请先交谈，并与来客确认合适的回访时间。")
	var candidate: Dictionary = state.duplicate(true)
	var visit: Dictionary = _candidate_visit(candidate)
	_divination.cancel_open_service(candidate.divination.cases[visit.visit_id])
	visit.phase = "ended"
	visit.ended_at = int(candidate.clock_minutes)
	var presentation_events: Array = PeopleBridge.finish(candidate, visit)
	candidate.active_visit_id = ""
	var output := {"visit_id": visit.visit_id}
	if action.has("return_at"):
		var arrival_id := "return_" + str(action.action_id)
		if not People.schedule_return(candidate.people,visit.npc_id,arrival_id,int(action.return_at),people_config):
			return _fail("RETURN_UNAVAILABLE", "这个时段不适合回访，请重新协商；本次接待仍保留。")
		candidate.people.arrivals[arrival_id]["agreed_return"] = true
		candidate.people.arrivals[arrival_id]["source_visit_id"] = visit.visit_id
		candidate.people.arrivals[arrival_id]["source_action_id"] = action.action_id
		output["return_appointment"] = {"arrival_id":arrival_id,"at":int(action.return_at)}
	return _commit(candidate, action, "接待已结束，回访时间也记下了。" if action.has("return_at") else "接待已结束，经历已保存。", output,presentation_events)

func next_return_time() -> int:
	var visit := active_visit()
	if visit.is_empty() or visit.dialogue.size() < 3:
		return 0
	var profile: Dictionary = state.get("people",{}).get("profiles",{}).get(visit.npc_id,{})
	if not profile.has("generation_id"):
		return 0
	var tomorrow := (floori(float(state.clock_minutes)/1440.0)+1)*1440+540
	var proposed: int = People.next_available_arrival(state.people,people_config,maxi(tomorrow,int(profile.get("cooldown_until",0))),profile)
	return maxi(0,proposed)

func _rest(action: Dictionary) -> Dictionary:
	if int(state.player.energy) >= int(content.rules.max_energy):
		return _fail("ENERGY_FULL", "精力已满，无需休息。")
	if not _has_time(int(content.rules.rest_minutes)):
		return _fail("NOT_ENOUGH_TIME", "今天剩余时间不足以休息，请处理接待后进入下一天。")
	var candidate: Dictionary = state.duplicate(true)
	candidate.player.energy = mini(int(content.rules.max_energy), int(candidate.player.energy) + int(content.rules.rest_energy))
	var presentation_events: Array = _advance(candidate, int(content.rules.rest_minutes))
	return _commit(candidate, action, "休息已完成并保存。", {},presentation_events)

func _next_day(action: Dictionary) -> Dictionary:
	if not state.active_visit_id.is_empty():
		return _fail("ACTIVE_VISIT", "还有未结束的接待，请先返回咨询区处理并结束接待。")
	var candidate: Dictionary = state.duplicate(true)
	var next_opening: int = (int(candidate.clock_minutes / 1440) + 1) * 1440 + int(content.rules.opening_minute)
	var presentation_events: Array = _advance(candidate, next_opening - int(candidate.clock_minutes))
	candidate.player.energy = int(content.rules.max_energy)
	return _commit(candidate, action, "已进入下一天，已处理到期的案例事项。", {},presentation_events)

func _candidate_visit(candidate: Dictionary) -> Dictionary:
	for visit: Dictionary in candidate.visits:
		if visit.visit_id == candidate.active_visit_id:
			return visit
	return {}

func _has_time(minutes: int) -> bool:
	return int(state.clock_minutes) % 1440 + minutes <= int(content.rules.closing_minute)

func _advance(candidate: Dictionary, minutes: int) -> Array:
	var presentation_events: Array = PeopleBridge.advance(candidate, people_config, minutes, _divination)
	Shop.sync_effects(candidate, shop_config)
	return presentation_events

func _commit(candidate: Dictionary, action: Dictionary, message: String, result: Dictionary, presentation_events: Variant = null) -> Dictionary:
	Shop.sync_effects(candidate, shop_config)
	PeopleBridge.sync(candidate, people_config, _divination)
	candidate = SaveService._normalize_numbers(candidate)
	candidate.state_version = int(state.state_version) + 1
	var reply: Dictionary = {"success": true, "error_code": "", "message": message, "state_version": candidate.state_version, "result": result, "action_type": action.type}
	candidate.processed_actions[action.action_id] = reply.duplicate(true)
	var saved: Dictionary = SaveService.write_save(candidate)
	if not saved.success:
		return _fail(saved.get("error_code", "SAVE_FAILED"), "未能保存，本次动作未生效，可重试。" + saved.get("message", ""))
	# Capture this commit's identity before state_changed: a listener may
	# synchronously commit another action while this local call is still active.
	var committed_events := _presentation_payload(candidate,presentation_events)
	state = candidate
	state_changed.emit()
	if not committed_events.is_empty():
		presentation_events_committed.emit(committed_events)
	return reply

## Whitelist only actual past transitions, never a private person or future plan.
## The returned array is local; no collector enters candidate, state or result.
func _presentation_payload(candidate: Dictionary, raw: Variant) -> Array:
	var result: Array = []
	if not raw is Array:
		return result
	var arrivals: Dictionary = candidate.get("people",{}).get("arrivals",{})
	var seen: Dictionary = {}
	for index: int in range(raw.size()):
		var event: Variant = raw[index]
		if not event is Dictionary or not event.get("arrival_id") is String or event.arrival_id.is_empty() or not arrivals.has(event.arrival_id) or not event.get("kind") in ["guest_entered","guest_left"] or not People._integer(event.get("at"),0,int(candidate.clock_minutes)):
			continue
		var arrival: Dictionary = arrivals[event.arrival_id]
		if int(event.at) < int(arrival.at):
			continue
		var key: String = str(event.arrival_id)+":"+str(event.kind)
		if seen.has(key):
			continue
		seen[key] = true
		result.append({"save_id":str(candidate.save_id),"state_version":int(candidate.state_version),"arrival_id":str(event.arrival_id),"kind":str(event.kind),"at":int(event.at),"sequence":index})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left.at < right.at if left.at != right.at else left.sequence < right.sequence)
	for index: int in range(result.size()):
		result[index].sequence = index
	return result

func _initialize_integrated(candidate: Dictionary, fresh: bool = false) -> bool:
	Shop.initialize(candidate)
	PeopleBridge.initialize(candidate, people_config, _divination,fresh)
	_migrate_arrival_schema(candidate)
	_migrate_event_schema(candidate)
	if not _migrate_appearance_schema(candidate):
		return false
	if int(candidate.schema_version) < 7:
		People.initialize_family_library(candidate.people,people_config.get("family_library",{}),"since_migration")
		candidate.schema_version = 7
	return People.validate(candidate.people).is_empty()

func _migrate_appearance_schema(candidate: Dictionary) -> bool:
	if int(candidate.schema_version) >= 6:
		return true
	var config := Appearance.load_config()
	if config.is_empty() or not GeneratedPerson.validate_people(candidate.people).is_empty():
		return false
	var people: Dictionary = candidate.people.duplicate(true)
	var selected := Appearance.normalize(people.player_appearance,config,"player")
	if selected.is_empty() or selected.has("preset"):
		return false
	people.player_appearance = selected
	var ids: Array = people.profiles.keys()
	ids.sort()
	for id: String in ids:
		var profile: Dictionary = people.profiles[id]
		var mapped := Appearance.normalize(profile.appearance,config,id)
		if mapped.is_empty() or not GeneratedPerson.migrate_appearance(profile,mapped):
			return false
	people.appearance_catalog_version = int(config.version)
	if not People.validate(people).is_empty():
		return false
	candidate.people = people
	candidate.schema_version = 6
	return true

func _migrate_arrival_schema(candidate: Dictionary) -> void:
	# Add only schema metadata. Persisted day plans and arrivals remain unchanged;
	# loading keeps the migration in memory until the next successful transaction.
	if int(candidate.schema_version) < 4:
		if not candidate.people.stats.has("lost_customers"):
			candidate.people.stats["lost_customers"] = 0
		candidate.schema_version = 4

func _migrate_event_schema(candidate: Dictionary) -> void:
	# A load changes memory only. Preserve world outcomes/effects, withdraw old
	# unreported verdicts, and mark visits that predate the generated event rules.
	# The next successfully committed action persists this metadata atomically.
	if int(candidate.schema_version) < 5:
		var eventless: Array = []
		for visit_id: String in candidate.divination.cases:
			if candidate.divination.cases[visit_id].event.is_empty():
				eventless.append(visit_id)
		eventless.sort()
		candidate.divination["legacy_eventless_visits"] = eventless
		for case: Dictionary in candidate.divination.cases.values():
			var event: Dictionary = case.get("event",{})
			if not event.is_empty() and event.get("feedback",{}).get("report",{}).is_empty():
				event.evaluation = "pending"
				event.evaluated_at = -1
		if not candidate.people.has("unlocked_topics"):
			candidate.people["unlocked_topics"] = {}
		candidate.schema_version = 5

func _shop_action(action: Dictionary) -> Dictionary:
	var candidate := state.duplicate(true)
	var outcome: Dictionary
	if action.type in PEOPLE_ACTIONS:
		outcome = PeopleBridge.handle(candidate, action, people_config)
	else:
		outcome = Shop.handle(candidate, action, shop_config)
	if not outcome.success:
		return _fail(outcome.error_code, outcome.message)
	if outcome.get("result", {}).has("item_use"):
		var use: Dictionary = outcome.result.item_use
		if not str(use.get("event_id", "")).is_empty() and not _divination.link_item_use(candidate, _candidate_visit(candidate), use):
			return _fail("ITEM_USE_BLOCKED", "商品不能用于当前事件，本次未消耗。")
	var presentation_events: Array = _advance(candidate, int(outcome.get("minutes", 0)))
	return _commit(candidate, action, outcome.message, outcome.get("result", {}),presentation_events)

func _use_unlocked_option(action: Dictionary) -> Dictionary:
	var visit := active_visit()
	if visit.is_empty() or not _has_time(5):
		return _fail("FOLLOWUP_UNAVAILABLE", "请在接待中、打烊前追问。")
	var candidate := state.duplicate(true)
	var memories := Memory.dialogue_context(candidate.people, visit.npc_id)
	if memories.is_empty():
		return _fail("FOLLOWUP_UNAVAILABLE", "先交谈了解来客，再温和追问。")
	for option: Dictionary in candidate.shop.unlocked_options:
		if option.item_use_id != action.get("item_use_id") or option.npc_id != visit.npc_id or option.get("used", false):
			continue
		var source: Dictionary = memories.back()
		var current := _candidate_visit(candidate)
		current.dialogue.append({"speaker":"player","text":"你先前提到的这件事，愿意再谈谈你的感受吗？"})
		# An intent/topic ID is not proof that its authored fact was disclosed.
		# Recall the actual mutually known words, preserving them as something
		# discussed rather than promoting a statement or prediction to world truth.
		var remembered_text: String = str(source.text).replace("\n", " ").strip_edges()
		var reply: String = "嗯，我们先前聊到过：“%s”。你慢慢问，我也愿意接着说。" % remembered_text
		current.dialogue.append({"speaker":"npc","text":reply})
		option["used"] = true
		option["action_id"] = action.action_id
		option["memory_id"] = source.memory_id
		option["source_visit_id"] = source.visit_id
		option["source_kind"] = source.kind
		var presentation_events: Array = _advance(candidate,5)
		return _commit(candidate,action,"已温和追问，原话与商品来源已保留。",{"item_use_id":option.item_use_id,"visit_id":visit.visit_id,"memory_id":source.memory_id},presentation_events)
	return _fail("FOLLOWUP_UNAVAILABLE", "当前来客没有可用的澄心晶追问。")

func _ok(message: String, result: Dictionary) -> Dictionary:
	return {"success": true, "error_code": "", "message": message, "state_version": state.get("state_version", 0), "result": result}

func _fail(error_code: String, message: String) -> Dictionary:
	action_failed.emit(message)
	return {"success": false, "error_code": error_code, "message": message, "state_version": state.get("state_version", 0), "result": {}}

extends RefCounted
## Mutates only the uncommitted candidate supplied by GameState.
const CONFIG_PATH := "res://data/daily_loop.json"
const People = preload("res://scripts/people/people.gd")
const Events = preload("res://scripts/divination/event_rules.gd")
const Memory = preload("res://scripts/people/memory.gd")
const Content = preload("res://scripts/core/content_loader.gd")
const StoryContent = preload("res://scripts/story/story_content.gd")
const StoryProgress = preload("res://scripts/story/story_progress.gd")
const CaseSchema = preload("res://scripts/divination/case_schema.gd")
const ACTIONS := ["read_morning_letters", "next_customer", "close_shop"]

static func load_config() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return value if value is Dictionary and config_valid(value) else {}

static func config_valid(value: Dictionary) -> bool:
	if value.get("version") != 1 or not value.get("enabled") is bool:
		return false
	for key: String in ["guests_min","guests_max","ordinary_index_offset","daily_energy","question_energy","question_minutes","extra_card_energy","extra_card_minutes","extra_question_energy","close_minutes","night_minute"]:
		if not People._integer(value.get(key),0,People.MAX_INT):
			return false
	var content := Content.load_content()
	var visuals: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/visuals.json"))
	if not content.success or not visuals is Dictionary or not visuals.get("scene_settings") is Dictionary:
		return false
	var rules: Dictionary = content.content.rules
	if value.guests_min < 2 or value.guests_max > 3 or value.guests_min > value.guests_max or value.daily_energy != rules.max_energy or value.night_minute < int(visuals.scene_settings.get("night_minute",rules.closing_minute)) or value.night_minute >= int(rules.closing_minute) or value.question_minutes <= 0:
		return false
	for key: String in ["question_energy","extra_card_energy","extra_question_energy"]:
		if int(value[key]) > int(value.daily_energy):
			return false
	for key: String in ["first_npc_id","first_case_id","ordinary_case_id","ordinary_case_opening","shopping_opening"]:
		if not value.get(key) is String or value[key].is_empty():
			return false
	if not value.get("monologues") is Array or value.monologues.is_empty() or not value.monologues.all(func(row: Variant) -> bool: return row is String and not row.is_empty()):
		return false
	var copy: Variant = value.get("copy")
	if not copy is Dictionary:
		return false
	for key: String in ["morning_title","letters_empty","read_letters","day_progress","next_customer","resume_visit","all_served","close_shop","next_day","closing_title","summary_format","monologue_title","status_format","guest_waiting","guest_active","invalid_config","invalid_state","morning_required","already_read","letters_read","active_visit","all_done","not_done","closed","already_closed","closing_required","legacy_disabled","next_started","basic_energy","case_preview","preview_name"]:
		if not copy.get(key) is String or copy[key].is_empty():
			return false
	if not copy.get("notes_empty") is String or copy.notes_empty.is_empty():
		return false
	return true

static func enabled(config: Dictionary) -> bool:
	return bool(config.get("enabled",false))

static func references_valid(config: Dictionary, catalog: Dictionary) -> bool:
	return catalog.get("guests",{}).has(config.get("first_npc_id")) and catalog.get("cases",{}).has(config.get("first_case_id")) and catalog.get("cases",{}).has(config.get("ordinary_case_id"))

static func initialize(state: Dictionary, sequential: bool = true) -> void:
	if state.has("daily_loop"):
		return
	var ids: Array = []
	var active_id := ""
	for row: Dictionary in state.people.arrivals.values():
		if not str(state.active_visit_id).is_empty() and row.get("visit_id") == state.active_visit_id and row.state == "in_service":
			ids.append(row.arrival_id)
			active_id = row.arrival_id
	state["daily_loop"] = {"version":1,"mode":"sequential" if sequential else "legacy","day":floori(float(state.clock_minutes)/1440.0),
		"phase":"morning" if active_id.is_empty() else "reception","planned":false,
		"arrival_ids":ids,"cursor":0,"active_arrival_id":active_id,"letters":[],"summary":{},
		"baseline":{"coins":int(state.player.coins),"reputation":int(state.shop.reputation)},"history":{}}

static func plan(state: Dictionary, config: Dictionary, people_config: Dictionary, story_mode: bool = false, catalog: Dictionary = {}) -> void:
	var loop: Dictionary = state.daily_loop
	if loop.planned:
		return
	var day: int = loop.day
	var rng := People._random(int(state.people.seed)+day*104729)
	var total := rng.randi_range(int(config.guests_min),int(config.guests_max))
	var story_config := StoryContent.load_config() if story_mode else {}
	while loop.arrival_ids.size() < total:
		var index: int = loop.arrival_ids.size()
		var first: bool = day == 0 and index == 0 and state.visits.is_empty()
		var story_proposal: Dictionary = {}
		if story_mode:
			story_proposal = StoryProgress.select_case(state,day,story_config) if index == 0 else StoryProgress.select_epilogue(state,day,index,story_config)
			var prior_weather: String = str(state.people.days.get(str(day),{}).get("weather",""))
			if not story_proposal.is_empty() and not str(story_proposal.get("weather_id","")).is_empty() and not prior_weather.is_empty() and prior_weather != story_proposal.weather_id:
				story_proposal = {}
		var npc: String
		var case_id: String
		if not story_proposal.is_empty():
			npc = story_proposal.npc_id
			if not StoryProgress.ensure_npc(state,npc,catalog,story_config,people_config):
				return
			var definition: Dictionary = CaseSchema.load_all(catalog).get(story_proposal.get("definition_id",""),{})
			case_id = CaseSchema.g3_case_id(definition) if story_proposal.kind == "case" else str(config.ordinary_case_id)
		else:
			npc = str(config.first_npc_id) if first else People._ordinary(state.people,people_config,rng,day,int(config.ordinary_index_offset)+index)
			case_id = str(config.first_case_id) if first else str(config.ordinary_case_id)
		var arrival_id := "arrival_daily_%d_%d" % [day,index]
		var intent := "divination" if index == 0 else "shopping"
		state.people.arrivals[arrival_id] = {"arrival_id":arrival_id,"npc_id":npc,"source":"fixed_story" if first else "daily_loop",
			"at":int(state.clock_minutes),"deadline":-1,"state":"planned","intent":intent,"urgency":0,
			"schedule_end":People.MAX_INT,"referrer_npc_id":"","case_id":case_id,"visit_id":"","daily_kind":"case" if index == 0 else "commission",
			"daily_loop_day":day,"daily_loop_index":index,
			"daily_opening":"" if first else config.ordinary_case_opening if index == 0 else config.shopping_opening}
		if not story_proposal.is_empty():
			var row: Dictionary = state.people.arrivals[arrival_id]
			row.source = "fixed_story"
			row.at = maxi(int(state.clock_minutes),day*1440+int(story_proposal.minute))
			row.daily_kind = story_proposal.kind
			row["story_rule_id"] = story_proposal.rule_id
			row["story_definition_id"] = story_proposal.get("definition_id","")
			if not first:
				row.daily_opening = story_config.npcs[npc].opening
			if not str(story_proposal.get("text","")).is_empty():
				row.daily_opening = story_proposal.text
			if story_proposal.kind == "epilogue":
				for epilogue: Dictionary in story_config.rules.epilogues:
					if epilogue.id == story_proposal.rule_id:
						row.daily_opening = epilogue.text
			if not str(story_proposal.get("weather_id","")).is_empty():
				state.story.days[str(day)] = {"weather_id":story_proposal.weather_id,"source_rule_id":story_proposal.rule_id}
		loop.arrival_ids.append(arrival_id)
	loop.planned = true

static func next_arrival(state: Dictionary) -> String:
	var loop: Dictionary = state.daily_loop
	return str(loop.arrival_ids[int(loop.cursor)]) if int(loop.cursor) < loop.arrival_ids.size() else ""

static func finish(state: Dictionary, visit: Dictionary) -> void:
	var loop: Dictionary = state.daily_loop
	var active: String = loop.active_arrival_id
	if active.is_empty():
		return
	var row: Dictionary = state.people.arrivals.get(active,{})
	if row.get("visit_id") == visit.visit_id and row.get("state") == "completed":
		loop.cursor = int(loop.cursor)+1
		loop.active_arrival_id = ""

static func read_letters(state: Dictionary, data: Dictionary, config: Dictionary) -> Array:
	var letters: Array = []
	var cases: Array = state.divination.cases.values()
	cases.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return str(a.visit_id) < str(b.visit_id))
	for case: Dictionary in cases:
		if not Events.can_report(case.get("event",{}),int(state.clock_minutes)):
			continue
		var original: Dictionary = {}
		for visit: Dictionary in state.visits:
			if visit.visit_id == case.visit_id:
				original = visit
		if original.is_empty() or original.phase != "ended":
			continue
		var report := Events.disclose(state,case,original,data.economy,data.cases[case.case_id].event)
		if report.is_empty():
			continue
		var name: String = state.people.profiles[case.npc_id].name
		letters.append({"name":name,"text":report.text,"event_id":report.event_id,"feedback_id":report.feedback_id})
		Memory.record(state.people,case.npc_id,{"memory_id":"memory_"+str(report.feedback_id),"visit_id":original.visit_id,
			"topic_id":"feedback_"+str(report.event_id),"kind":"feedback","audience":"both","text":str(report.text).left(500),"source_id":report.feedback_id})
	letters.append({"name":config.copy.preview_name,"text":config.copy.case_preview})
	state.daily_loop.letters = letters
	return letters

static func close(state: Dictionary, config: Dictionary) -> void:
	var loop: Dictionary = state.daily_loop
	var stars := 0
	var notes: Array = []
	var story_config := StoryContent.load_config()
	for id: String in state.get("story",{}).get("notes",{}):
		var unlocked: Dictionary = state.story.notes[id]
		if floori(float(unlocked.get("unlocked_at",-1440))/1440.0) == int(loop.day) and story_config.get("notes",{}).has(id):
			notes.append(story_config.notes[id].title)
	for id: String in loop.arrival_ids:
		var visit_id: String = state.people.arrivals[id].visit_id
		stars += int(state.divination.cases.get(visit_id,{}).get("stars",0))
	loop.summary = {"stars":stars,"coins":int(state.player.coins)-int(loop.baseline.coins),
		"reputation":int(state.shop.reputation)-int(loop.baseline.reputation),"notes":notes,
		"monologue":config.monologues[posmod(int(loop.day),config.monologues.size())]}
	loop.phase = "closing"
	loop.history[str(loop.day)] = _day_record(loop,"completed")

static func _day_record(loop: Dictionary, status: String) -> Dictionary:
	return {"status":status,"planned":loop.planned,"summary":loop.summary.duplicate(true),"cursor":int(loop.cursor),"completed":int(loop.cursor),"total":loop.arrival_ids.size(),"arrival_ids":loop.arrival_ids.duplicate()}

static func new_day(state: Dictionary, sequential: bool = true) -> void:
	var previous: Dictionary = state.daily_loop
	var history: Dictionary = state.daily_loop.history
	if not history.has(str(previous.day)) and (previous.planned or not previous.arrival_ids.is_empty()):
		history[str(previous.day)] = _day_record(previous,"interrupted")
	state.erase("daily_loop")
	initialize(state,sequential)
	state.daily_loop.history = history

static func sync_mode(state: Dictionary, sequential: bool) -> void:
	if int(state.daily_loop.day) != floori(float(state.clock_minutes)/1440.0):
		new_day(state,sequential)
	var loop: Dictionary = state.daily_loop
	# An extra legacy reception must finish before strict ordered admission resumes.
	var foreign_active: bool = not str(state.active_visit_id).is_empty() and str(loop.active_arrival_id).is_empty()
	loop.mode = "sequential" if sequential and not foreign_active else "legacy"

static func public_view(state: Dictionary, config: Dictionary) -> Dictionary:
	var view := {"enabled":enabled(config),"phase":"morning","day":1,"completed":0,"total":0,"next_guest":{},"letters":[],"summary":{},"copy":config.get("copy",{}).duplicate(true)}
	if state.is_empty() or not state.has("daily_loop"):
		return view
	var loop: Dictionary = state.daily_loop
	view.merge({"phase":loop.phase,"day":int(loop.day)+1,"completed":int(loop.cursor),"total":loop.arrival_ids.size(),"summary":loop.summary.duplicate(true)},true)
	var id := next_arrival(state)
	if not id.is_empty():
		var profile: Dictionary = state.people.profiles[state.people.arrivals[id].npc_id]
		view.next_guest = {"name":profile.name,"role":profile.role}
	for letter: Dictionary in loop.letters:
		view.letters.append({"name":letter.name,"text":letter.text})
	return view

## The table must come from the strict snapshot builder, never from saved or
## provider-supplied metadata. This guard checks that it still names this exact
## ready reservation; it does not replace the builder's codec/proof validation.
static func verified_ready_case(state: Dictionary, row: Dictionary, verified_bindings: Dictionary) -> bool:
	if not People._integer(state.get("schema_version"),14,People.MAX_INT) or not People.sequential_arrival(row) or row.get("source") != "daily_loop" or row.get("daily_loop_index") != 0 or row.has("story_rule_id") or row.has("story_definition_id"):
		return false
	var binding: Variant = verified_bindings.get(row.get("arrival_id"))
	if not binding is Dictionary or binding.size() != 3 or not binding.get("npc_id") is String or not binding.get("case_id") is String or not binding.get("definition_hash") is String:
		return false
	if binding.npc_id != row.get("npc_id") or binding.case_id != row.get("case_id") or binding.definition_hash.is_empty():
		return false
	var divination: Variant = state.get("divination")
	var people: Variant = state.get("people")
	if not divination is Dictionary or not people is Dictionary or not people.get("profiles") is Dictionary:
		return false
	var emergent_space: Variant = divination.get("emergent_cases")
	if not emergent_space is Dictionary or emergent_space.size() != 2 or emergent_space.get("version") is bool or emergent_space.get("version") != 1 or not emergent_space.get("instances") is Dictionary:
		return false
	var record: Variant = emergent_space.instances.get(row.arrival_id)
	var profile: Variant = people.profiles.get(binding.npc_id)
	if not record is Dictionary or not profile is Dictionary or record.get("status") != "ready" or record.get("day") != row.daily_loop_day or record.get("npc_id") != binding.npc_id or record.get("case_id") != binding.case_id or record.get("definition_hash") != binding.definition_hash:
		return false
	if profile.get("template_id") != "ordinary_v1" or profile.get("source") != "original" or profile.get("family_library_member",false) or not str(profile.get("family_id","")).is_empty() or profile.has("generated_bundle") or profile.has("generation_member"):
		return false
	var owner_prefix := "npc_o_%d_" % int(row.daily_loop_day)
	if not binding.npc_id.begins_with(owner_prefix) or not binding.npc_id.trim_prefix(owner_prefix).is_valid_int():
		return false
	var definition: Variant = record.get("definition")
	return definition is Dictionary and definition.get("id") == binding.case_id and definition.get("legacy_case_id","") == "" and definition.get("outcomes") is Dictionary and definition.outcomes.get("subject_id") == binding.npc_id and CaseSchema.definition_hash(definition) == binding.definition_hash

static func validate(state: Dictionary, verified_bindings: Dictionary = {}) -> String:
	var loop: Variant = state.get("daily_loop")
	var config := load_config()
	var error: String = str(config.get("copy",{}).get("invalid_state","DAILY_LOOP_CONFIG_INVALID"))
	if config.is_empty():
		return error
	if not loop is Dictionary or loop.get("version") != 1 or loop.get("mode") not in ["sequential","legacy"] or not People._integer(loop.get("day"),0,People.MAX_INT) or int(loop.day) != floori(float(state.clock_minutes)/1440.0) or loop.get("phase") not in ["morning","reception","closing"] or not loop.get("planned") is bool:
		return error
	if not loop.get("arrival_ids") is Array or loop.arrival_ids.size() > 3 or not People._integer(loop.get("cursor"),0,loop.arrival_ids.size()) or not loop.get("active_arrival_id") is String or not loop.get("letters") is Array or not loop.get("summary") is Dictionary or not loop.get("baseline") is Dictionary or not loop.get("history") is Dictionary:
		return error
	if not People._integer(loop.baseline.get("coins"),0,People.MAX_INT) or not People._integer(loop.baseline.get("reputation"),-People.MAX_INT,People.MAX_INT):
		return error
	if loop.planned and not People._integer(loop.arrival_ids.size(),int(config.guests_min),int(config.guests_max)):
		return error
	if not loop.planned and (int(loop.cursor) != 0 or loop.arrival_ids.size() > 1 or not loop.summary.is_empty()):
		return error
	if loop.mode == "sequential" and state.active_visit_id.is_empty() != str(loop.active_arrival_id).is_empty():
		return error
	if loop.phase == "morning" and (not str(loop.active_arrival_id).is_empty() or int(loop.cursor) != 0 or not loop.letters.is_empty() or not loop.summary.is_empty()):
		return error
	if loop.phase == "reception" and (not loop.summary.is_empty() or (not loop.planned and str(loop.active_arrival_id).is_empty())):
		return error
	if not loop.planned and loop.phase not in ["morning","reception"]:
		return error
	var seen := {}
	for index: int in range(loop.arrival_ids.size()):
		var id: Variant = loop.arrival_ids[index]
		var row: Dictionary = state.people.arrivals.get(id,{})
		if not id is String or seen.has(id) or row.is_empty():
			return error
		var expected_state := "completed" if index < int(loop.cursor) else "in_service" if id == loop.active_arrival_id else "planned"
		if row.state != expected_state or (not People.sequential_arrival(row) and row.state not in ["in_service","completed"]):
			return error
		seen[id] = true
	if not str(loop.active_arrival_id).is_empty():
		var row: Dictionary = state.people.arrivals.get(loop.active_arrival_id,{})
		if row.get("state") != "in_service" or row.get("visit_id") != state.active_visit_id or next_arrival(state) != loop.active_arrival_id:
			return error
	if loop.phase == "closing" and (int(loop.cursor) != loop.arrival_ids.size() or not str(loop.active_arrival_id).is_empty()):
		return error
	if loop.phase == "closing" and not _summary_valid(loop.summary):
		return error
	if not loop.summary.is_empty() and not _summary_valid(loop.summary):
		return error
	for key: Variant in loop.history:
		var record: Variant = loop.history[key]
		if not key is String or not key.is_valid_int() or int(key) < 0 or int(key) > int(loop.day) or not record is Dictionary or record.get("status") not in ["completed","interrupted"] or not record.get("planned") is bool or not People._integer(record.get("total"),0,int(config.guests_max)) or not People._integer(record.get("cursor"),0,int(record.total)) or record.get("completed") != record.cursor:
			return error
		if record.planned and int(record.total) < int(config.guests_min):
			return error
		if record.status == "completed" and (record.cursor != record.total or not _summary_valid(record.get("summary"))):
			return error
		if record.status == "interrupted" and (int(key) >= int(loop.day) or not record.get("summary") is Dictionary or not record.summary.is_empty()):
			return error
		if not record.get("arrival_ids") is Array or record.arrival_ids.size() != int(record.total):
			return error
		var history_ids := {}
		for index: int in range(record.arrival_ids.size()):
			var id: Variant = record.arrival_ids[index]
			var row: Dictionary = state.people.arrivals.get(id,{})
			var expected: String = "completed" if index < int(record.cursor) else "planned"
			if not id is String or history_ids.has(id) or row.get("state") != expected or floori(float(row.get("at",-1))/1440.0) != int(key):
				return error
			history_ids[id] = true
	if loop.phase == "closing" and loop.history.get(str(loop.day),{}).get("arrival_ids") != loop.arrival_ids:
		return error
	for row: Dictionary in state.people.arrivals.values():
		if not People.sequential_arrival(row):
			continue
		var day: int = row.daily_loop_day
		var index: int = row.daily_loop_index
		var ids: Array = loop.arrival_ids if day == int(loop.day) else loop.history.get(str(day),{}).get("arrival_ids",[])
		if index >= ids.size() or ids[index] != row.arrival_id:
			return error
		if row.has("story_rule_id") or row.has("story_definition_id"):
			if int(state.schema_version) < 12 or not StoryProgress.reservation_valid(state,row,StoryContent.load_config()):
				return error
		elif row.source == "fixed_story":
			if day != 0 or index != 0 or row.npc_id != config.first_npc_id or row.case_id != config.first_case_id:
				return error
		elif row.case_id != config.ordinary_case_id and not verified_ready_case(state,row,verified_bindings):
			return error
	for letter: Variant in loop.letters:
		if not letter is Dictionary or not letter.get("name") is String or not letter.get("text") is String or letter.text.is_empty():
			return error
		for key: Variant in letter:
			if key not in ["name","text","event_id","feedback_id"]:
				return error
		if letter.has("event_id"):
			var found := false
			for case: Dictionary in state.divination.cases.values():
				var report: Dictionary = case.get("event",{}).get("feedback",{}).get("report",{})
				if report.get("event_id") == letter.event_id and report.get("feedback_id") == letter.get("feedback_id") and report.get("text") == letter.text and state.people.profiles[case.npc_id].name == letter.name:
					found = true
			if not found:
				return error
		elif letter != {"name":config.copy.preview_name,"text":config.copy.case_preview}:
			return error
	return ""

static func _summary_valid(summary: Variant) -> bool:
	if not summary is Dictionary or summary.size() != 5 or not People._integer(summary.get("stars"),0,9) or not People._integer(summary.get("coins"),-People.MAX_INT,People.MAX_INT) or not People._integer(summary.get("reputation"),-People.MAX_INT,People.MAX_INT) or not summary.get("monologue") is String or summary.monologue.is_empty():
		return false
	return summary.get("notes") is Array and summary.notes.all(func(note: Variant) -> bool: return note is String and not note.is_empty())

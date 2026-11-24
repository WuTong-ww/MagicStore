extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STORY CONTENT FAIL: "+label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	check(FileAccess.file_exists("res://scripts/story/story_content.gd"),"authored story installer exists")
	if failures:
		finish()
		return
	var content = load("res://scripts/story/story_content.gd")
	var schema = load("res://scripts/divination/case_schema.gd")
	var catalog_script = load("res://scripts/divination/catalog.gd")
	var loader = load("res://scripts/core/content_loader.gd")
	var config: Dictionary = content.load_config()
	check(not config.is_empty(),"all three story JSON resources validate together")
	var catalog: Dictionary = catalog_script.load_data(loader.load_content().content)
	check(not catalog.is_empty(),"real catalog installs story content")
	if catalog.is_empty() or config.is_empty():
		finish()
		return
	var definitions: Dictionary = schema.load_all(catalog)
	check(definitions.size()==5,"exactly five fixed cases are installed")
	for id: String in ["fixed_invitation","fixed_bread","fixed_key","fixed_music_box","fixed_last_pages"]:
		check(definitions.has(id),"definition exists / "+id)
		if not definitions.has(id):
			continue
		var definition: Dictionary = definitions[id]
		check(schema.validate_definition(definition,catalog),"definition fully validates / "+id)
		var mapped: String = schema.g3_case_id(definition)
		check(catalog.cases.has(mapped),"G3 template exists / "+id)
		var template: Dictionary = catalog.cases.get(mapped,{})
		check(catalog_script._valid_questions(template,catalog.clues),"complete safe G3 question descriptor / "+id)
		for key: String in ["topic_ids","method_ids","world_facts","questions","default_question","event"]:
			check(template.has(key),"G3 field "+key+" / "+id)
		check(template.get("generated",false)==false,"authored template is not generated / "+id)
		for fact: Dictionary in definition.truth.values():
			check(catalog.clues.has(fact.requires_clue),"private fact has a separately registered clue / "+id)
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/divination.json"))
	check(catalog.cases.invitation==original.cases.invitation,"original invitation G3 object is byte-content equivalent")
	check(definitions.fixed_invitation.truth==original.cases.invitation.world_facts and definitions.fixed_invitation.outcomes==original.cases.invitation.event,"invitation truth/event/referral remain exact")
	check(config.notes.size()==4 and config.notes.note_1.page_number==1 and config.notes.note_4.page_number==4,"four distinct notebook pages")
	check(config.rules.cases.fixed_last_pages.requires_closed==["fixed_bread","fixed_music_box"] and config.rules.cases.fixed_last_pages.min_day==6,"finale requires cases2/4 and human day6")
	check(config.rules.final_prelude.repair.min_trust==2 and config.rules.ending.delay_by_advice.letter==4320,"repair trust and three-day letter delay are data")
	for id: String in ["fixed_bread","fixed_key","fixed_music_box"]:
		check(not config.rules.cases[id].get("fragment",{}).get("text","").is_empty(),"every route can disclose canonical story fragment / "+id)
	check(config.rules.cases.fixed_key.followup_npc_ids==["npc_tao_shuning"],"key case has an explicit ordinary followup trigger")
	check(config.rules.ending.routes.phone.title=="真正的店主" and config.rules.ending.routes.travel.title.is_empty() and config.rules.ending.routes.letter.title.is_empty(),"only the canonical best finale awards the title")
	check(not definitions.fixed_last_pages.outcomes.outcomes.letter.text.contains("团圆") and definitions.fixed_last_pages.outcomes.outcomes.letter.text.contains("还没有见面"),"letter G3 feedback does not predeclare a future reunion")
	check(config.rules.cases.fixed_music_box.get("defer_disclosure_advice_ids",[])==["accuse"],"music-box accusation waits for its real feedback before note and fragment disclosure")
	var bad_deferred: Dictionary = config.rules.duplicate(true)
	bad_deferred.cases.fixed_music_box["defer_disclosure_advice_ids"] = ["not_offered"]
	check(not content.validate_rules(bad_deferred),"deferred disclosure rejects an unknown advice reference")
	for id: String in ["npc_pieter","npc_shen_nianqiu","npc_marianne","npc_wen_qingchuan"]:
		check(config.npcs.has(id) and catalog.guests.has(id),"fixed guest installed / "+id)
		check(not config.npcs[id].appearance.has("preset"),"fixed guest uses A4 parts / "+id)
	for mutation: String in ["missing_cases","invalid_day","unknown_requirement","missing_copy","zero_trust","bad_ending_delay"]:
		var bad: Dictionary = config.rules.duplicate(true)
		match mutation:
			"missing_cases": bad.erase("cases")
			"invalid_day": bad.cases.fixed_last_pages.min_day = -1
			"unknown_requirement": bad.cases.fixed_last_pages.requires_closed = ["missing_case"]
			"missing_copy": bad.copy.erase("invalid_state")
			"zero_trust": bad.final_prelude.repair.min_trust = -1
			"bad_ending_delay": bad.ending.delay_by_advice.letter = "3 days"
		check(not content.validate_rules(bad),"bad rules rejected / "+mutation)
	var npc_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/npcs.json"))
	var bad_npc: Dictionary = npc_file.duplicate(true)
	bad_npc.npcs.npc_pieter.appearance.parts.outfit = "missing_outfit"
	check(not content.validate_npcs(bad_npc),"invalid A4 NPC selection rejected")
	var notes_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/notes.json"))
	var bad_notes: Dictionary = notes_file.duplicate(true)
	bad_notes.pages.note_2.page_number = 1
	check(not content.validate_notes(bad_notes),"duplicate notebook page number rejected")
	var installed_again: Dictionary = content.install(catalog)
	check(installed_again==catalog,"reinstall is deterministic and idempotent")
	finish()
func finish() -> void:
	print("STORY CONTENT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

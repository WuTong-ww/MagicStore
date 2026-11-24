extends SceneTree
const Progress = preload("res://scripts/story/story_progress.gd")
const Content = preload("res://scripts/story/story_content.gd")
const Catalog = preload("res://scripts/divination/catalog.gd")
const Loader = preload("res://scripts/core/content_loader.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STORY PROGRESS FAIL: "+label)
func fixture(config: Dictionary, day: int = 0) -> Dictionary:
	var state := {"schema_version":12,"save_id":"story_rules","clock_minutes":day*int(config.rules.minutes_per_day)+540,"visits":[],"active_visit_id":"","divination":{"cases":{}},"people":{"arrivals":{},"profiles":{},"effect_ids":[]},"npcs":{},"daily_loop":{"day":day,"arrival_ids":[],"active_arrival_id":"","history":{}}}
	Progress.initialize(state,config)
	return state
func _initialize() -> void:
	var config := Content.load_config()
	var catalog := Catalog.load_data(Loader.load_content().content)
	check(not config.is_empty() and not catalog.is_empty(),"real story config and complete catalog validate")
	if config.is_empty() or catalog.is_empty():
		finish()
		return
	var state := fixture(config)
	check(Progress.validate(state,catalog,config).is_empty(),"initial ledger validates")
	check(state.story.completions.is_empty() and state.story.notes.size()==1,"initialization awards only the opening notebook page")
	var old: Dictionary = state.duplicate(true)
	Progress.initialize(state,config)
	check(state==old,"initialization is idempotent")
	var view := Progress.public_view(state,config)
	check(view.enabled and view.notes.size()==4 and view.ending.status=="none","public progress exposes four page placeholders")
	for note: Dictionary in view.notes:
		if not note.unlocked:
			check(not note.has("title") and not note.has("text"),"locked page contains no future title or body")
	check(not JSON.stringify(view).contains('"truth"') and not JSON.stringify(view).contains('"correct_answer"'),"public story view contains no private case records")
	check(Progress.select_case(state,0,config).get("definition_id")=="fixed_invitation","new day1 retains original teaching visitor")
	var historic := fixture(config,2)
	historic.people.arrivals.old_bread = {"arrival_id":"old_bread","story_rule_id":"fixed_bread","state":"planned","daily_loop_day":1,"visit_id":""}
	historic.daily_loop.history["1"] = {"status":"interrupted","arrival_ids":["old_bread"]}
	check(Progress.select_case(historic,2,config).get("definition_id")=="fixed_bread","an interrupted historic planned row cannot reserve an unfinished case forever")
	historic.daily_loop.arrival_ids = ["old_bread"]
	historic.people.arrivals.old_bread.daily_loop_day = 2
	check(Progress.select_case(historic,2,config).get("definition_id","")!="fixed_bread","a current roster reservation still suppresses duplication")
	var legacy := fixture(config,1)
	legacy.visits = [{"visit_id":"legacy_invitation"}]
	legacy.divination.cases.legacy_invitation = {"case_id":"invitation","board":{}}
	check(Progress.select_case(legacy,1,config).get("definition_id")=="fixed_bread" and legacy.story.completions.is_empty(),"old unboarded invitation neither repeats nor fabricates a completion")
	var late := fixture(config,4)
	late.story.completions = {"fixed_invitation":{},"fixed_bread":{}}
	check(Progress.select_case(late,4,config).get("definition_id")=="fixed_music_box","on-time music takes priority over an overdue optional key")
	late.story.completions.fixed_music_box = {}
	check(Progress.select_case(late,5,config).get("definition_id")=="fixed_last_pages","case2 and case4 permit finale without case3")
	late.story.receipts.delay = {"kind":"lead_delay","amount":1}
	check(Progress.select_case(late,5,config).get("definition_id","")!="fixed_last_pages" and Progress.select_case(late,6,config).get("definition_id")=="fixed_last_pages","police consequence postpones earliest finale one configured day")
	for key: String in ["completions","notes","disclosures","preludes","milestones","receipts","days","ending"]:
		var bad: Dictionary = state.duplicate(true)
		bad.story[key] = null
		check(not Progress.validate(bad,catalog,config).is_empty(),"malformed "+key+" fails closed")
	var forged: Dictionary = state.duplicate(true)
	forged.story.completions.fixed_bread = {"visit_id":"unseen","closed_at":540,"stars":3,"advice_id":"leave_bread"}
	check(not Progress.validate(forged,catalog,config).is_empty(),"completion requires an actual closed board source")
	check(Progress.sync(state,catalog,config,{}).success and state==old,"empty milestone sweep is idempotent")
	finish()
func finish() -> void:
	print("STORY PROGRESS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

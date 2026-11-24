extends SceneTree
## Pure catalog composition on isolated candidates, after one real fresh save.
const Generated = preload("res://scripts/people/generated_person.gd")
const Cases = preload("res://scripts/divination/generated_cases.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("NAMES CATALOG FAIL: "+label)
func run() -> void:
	var game: Node=root.get_node("GameState")
	var saves: Node=root.get_node("SaveService")
	saves.base_dir="res://.tools/r3-names/catalog-saves/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	var created: Dictionary=await game.execute_action_async({"type":"new_game","action_id":"names_catalog_new","name":"身份案件版本回归"})
	check(created.success,"real fresh save supplies the production authored base")
	if not created.success:
		finish()
		return
	var fresh: Dictionary=game.snapshot()
	var base: Dictionary=game._divination.data.duplicate(true)
	var base_text:=JSON.stringify(base,"",true)
	for filename: String in ["person_generation.json","person_generation_v2.json","person_generation_v3.json"]:
		var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/people/fixtures/"+filename))
		var bundle: Dictionary=Generated.validate_bundle(fixture.bundle)
		var candidate:=fresh.duplicate(true)
		var expected: Dictionary={} if int(bundle.version)<3 else Generated.validate_birth_identities(fixture.context.birth_identities)
		var provenance: Dictionary={"source":"model","model":"local-fixture","draft_hash":Generated.draft_hash(bundle),"review":{"approved":true,"draft_hash":Generated.draft_hash(bundle),"contradictions":[],"unsupported_claims":[]}}
		var applied: Dictionary=Generated.apply(candidate.people,game.people_config,"names_catalog_v"+str(int(bundle.version)),bundle,provenance,570,"",expected)
		check(applied.success,"real person policy admits supported version / "+filename)
		if not applied.success:
			continue
		var candidate_text:=JSON.stringify(candidate,"",true)
		var catalog:=Cases.catalog(candidate,base)
		check(not catalog.is_empty(),"case catalog accepts the complete validated package / "+filename)
		if not catalog.is_empty():
			var main: Dictionary=catalog.cases[Cases.case_id(applied.npc_id)]
			var contact: Dictionary=catalog.cases[Cases.case_id(applied.contact_id)]
			check(main.world_facts.hidden.text==bundle.case.hidden_fact,"owner private evidence remains canonical / "+filename)
			check(not contact.world_facts.has("hidden") and not JSON.stringify(contact).contains(bundle.case.hidden_fact),"contact view does not inherit owner private evidence / "+filename)
			check(catalog.guests[applied.npc_id].name==bundle.person.name and catalog.guests[applied.contact_id].name==bundle.contact.name,"both public names survive case installation / "+filename)
		check(JSON.stringify(candidate,"",true)==candidate_text and JSON.stringify(base,"",true)==base_text,"pure catalog builder never mutates candidate or shared base / "+filename)
		for mutation: String in ["version","missing_person","extra_bundle"]:
			var bad:=candidate.duplicate(true)
			match mutation:
				"version": bad.people.profiles[applied.npc_id].generated_bundle.version=4
				"missing_person": bad.people.profiles[applied.npc_id].generated_bundle.person.erase("role")
				"extra_bundle": bad.people.profiles[applied.npc_id].generated_bundle["unknown"]=true
			check(Cases.catalog(bad,base).is_empty(),"full package validation rejects tampering / "+filename+" / "+mutation)
	check(game.snapshot()==fresh,"pure candidate checks never publish or write generated profiles")
	finish()
func finish() -> void:
	print("NAMES CATALOG: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

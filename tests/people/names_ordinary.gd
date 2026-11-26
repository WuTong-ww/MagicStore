extends SceneTree
## UNRUN draft. Actual old sampler + G4 overlay are the RNG oracle, not a clone.
const People = preload("res://scripts/people/people.gd")
const Population = preload("res://scripts/people/ordinary_content.gd")
const Birth = preload("res://scripts/people/birth_identity.gd")
const Appearance = preload("res://scripts/people/appearance.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("NAMES ORDINARY FAIL: "+label)

func old_fields(profile: Dictionary) -> Dictionary:
	var value := profile.duplicate(true)
	value.erase("name")
	value.erase("birth_identity")
	value.erase("cultural_origin")
	value.appearance.colors.erase("skin")
	value.appearance.erase("face_details")
	value.appearance.parts.erase("mouth_expr")
	return value

func run() -> void:
	var population_api := Population.new()
	var config := People.load_config()
	var names := Birth.load_config()
	check(not config.is_empty() and not names.is_empty(),"production data and pure selector are available")
	check(population_api.has_method("with_birth_identity") and population_api.has_method("birth_profile_valid"),"new overlay has a separate validation path")
	if failures:
		finish()
		return
	for seed_value: int in [11,29,97,314159]:
		var legacy := People.create("save_names_oracle_"+str(seed_value),seed_value,540)
		People.initialize_ordinary_content(legacy,config)
		var modern := legacy.duplicate(true)
		modern["birth_identity_version"] = 1
		var old_rng := People._random(seed_value)
		var new_rng := People._random(seed_value)
		var old_id := People._ordinary(legacy,config,old_rng,2,9)
		var new_id := People._ordinary(modern,config,new_rng,2,9)
		check(old_id==new_id and old_rng.state==new_rng.state,"full old sampler draw state survives identity overlay / "+str(seed_value))
		check(legacy.relationships==modern.relationships,"relationship graph and closeness remain exactly the old result / "+str(seed_value))
		var seen := {}
		for id: String in [new_id,new_id+"_friend"]:
			var old: Dictionary = legacy.profiles[id]
			var current: Dictionary = modern.profiles[id]
			check(not old.has("birth_identity") and Birth.record_valid(current.get("birth_identity"),names),"only the opted-in new birth gets a valid record / "+id)
			check(current.name==current.birth_identity.name and current.cultural_origin==current.birth_identity.cultural_origin and current.appearance.colors.skin==current.birth_identity.skin_id,"name, origin and skin match the same immutable record / "+id)
			check(old_fields(old)==old_fields(current),"all previous biography, schedule, hair, clothes and rig fields survive the new face policy / "+id)
			check(current.appearance.has("face_details") and current.appearance.parts.mouth_expr == current.appearance.face_details.lips,"only the new facial choices select a lip shape / "+id)
			check(not seen.has(current.name),"main/contact names are distinct / "+id)
			seen[current.name] = true
			var altered := current.duplicate(true)
			altered.appearance.colors.skin = "skin_01" if current.birth_identity.skin_id!="skin_01" else "skin_02"
			check(not population_api.call("birth_profile_valid",altered,names,Appearance.load_config()),"a recorded birth cannot drift to another legal skin / "+id)
			altered = current.duplicate(true)
			altered.cultural_origin = "not_the_record"
			check(not population_api.call("birth_profile_valid",altered,names,Appearance.load_config()),"a recorded birth cannot drift origin / "+id)
			check(population_api.call("birth_profile_valid",old,names,Appearance.load_config()),"old no-record profiles retain the old validation path / "+id)
		var snapshot := modern.duplicate(true)
		var rng_state := new_rng.state
		check(People._ordinary(modern,config,new_rng,2,9)==new_id and modern==snapshot and new_rng.state==rng_state,"existing main/contact are neither reselected nor redrawn")
	var mixed := People.create("save_names_existing_friend",17,540)
	People.initialize_ordinary_content(mixed,config)
	mixed["birth_identity_version"] = 1
	var friend_id := "npc_o_3_7_friend"
	People.add_fixed(mixed,friend_id,"许安","旧相识")
	var original_friend: Dictionary = mixed.profiles[friend_id].duplicate(true)
	People._ordinary(mixed,config,People._random(17),3,7)
	check(mixed.profiles[friend_id]==original_friend and not mixed.profiles[friend_id].has("birth_identity"),"even an already-existing friend with a new main ID remains byte-equivalent")
	finish()

func finish() -> void:
	print("NAMES ORDINARY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

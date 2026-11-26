extends SceneTree
const N = preload("res://scripts/people/nationality.gd")
const B = preload("res://scripts/people/birth_identity.gd")
const Person = preload("res://scripts/people/generated_person.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("NATIONALITY FAIL: "+label)

func run() -> void:
	var config := N.load_config()
	check(not config.is_empty() and N.config_valid(config),"country JSON validates")
	if config.is_empty(): quit(1); return
	var birth := B.load_config()
	for raw: Array in config.countries:
		var pool := N.pool(birth,"country_"+str(raw[0]))
		check(pool.given_names.size()*pool.surnames.size() >= 30,"country offers at least thirty distinct names / "+str(raw[0]))
		var record := {"version":1,"cultural_origin":pool.cultural_origin,"name_pool_id":pool.id,"name":str(pool.given_names[0])+"·"+str(pool.surnames[0]),"skin_id":pool.skin_ids[0]}
		check(B.record_valid(record,birth) and N.infer({"birth_identity":record}) == raw[0],"country pool and skin are validated together / "+str(raw[0]))
	for name: String in config.fixed:
		check(N.infer({"name":name}) == config.fixed[name],"fixed nationality / "+name)
	check(N.information({"name":"林照晚","role":"旧书修复师","age":26,"nationality":"local","mbti":"INFP"}) == "旧书修复师 · 26 岁 · INFP","local information omits nationality and type prefix")
	check(N.information({"name":"皮特·莫里斯","role":"面包师","age":34,"nationality":"GB","mbti":"ESFJ"}) == "面包师 · 34 岁 · 英国 · ESFJ","foreign information shows the real country")
	check(N.label({"name":"未能推断的外来居民","nationality":""}).is_empty(),"unknown legacy nationality has no placeholder")
	var seen := {}
	var foreign := birth.duplicate(true)
	foreign.rules.groups = {"local":0,"foreign":1,"mixed":0}
	for index: int in range(180):
		var record := B.propose({"save_id":"nationality_factory","seed":index,"npc_id":"npc_"+str(index)},foreign)
		check(not record.is_empty() and B.record_valid(record,foreign) and record.name_pool_id.begins_with("country_"),"factory chooses country before compatible name and skin")
		if not record.is_empty(): seen[N.infer({"birth_identity":record})] = true
	check(seen.size() == config.countries.size(),"deterministic sample reaches all thirty countries")
	var pair := {"person":B.propose({"save_id":"model_lock","seed":8,"npc_id":"p"}),"contact":B.propose({"save_id":"model_lock","seed":9,"npc_id":"c"})}
	var bundle := Person.offline_bundle_for_identities("country_model_lock",pair)
	check(not bundle.is_empty(),"offline bundle accepts program-selected country identities")
	if not bundle.is_empty():
		var tampered := bundle.duplicate(true)
		tampered.person["nationality"] = "FR"
		check(Person.validate_draft(tampered,{"birth_identities":pair,"identity_hash":Person.identity_hash(pair)}).is_empty(),"model cannot add or override nationality")
		tampered = bundle.duplicate(true)
		tampered.person.birth_identity.name_pool_id = "country_FR"
		check(Person.validate_draft(tampered,{"birth_identities":pair,"identity_hash":Person.identity_hash(pair)}).is_empty(),"model cannot switch the immutable country pool")
	var invalid := config.duplicate(true)
	invalid.iris_weights.local[0] = 0
	check(not N.config_valid(invalid),"every iris colour retains a nonzero probability")
	invalid = config.duplicate(true)
	invalid.countries.remove_at(0)
	check(not N.config_valid(invalid),"each foreign region requires six countries")
	print("NATIONALITY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

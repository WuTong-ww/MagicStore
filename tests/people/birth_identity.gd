extends SceneTree
## Draft runtime tests. Not run while the STORY/LIN engine window is frozen.
const Identity = preload("res://scripts/people/birth_identity.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("BIRTH IDENTITY FAIL: "+label)

func _initialize() -> void:
	var config := Identity.load_config()
	check(not config.is_empty() and Identity.config_valid(config),"real JSON/local references/appearance palette resolve")
	if config.is_empty():
		quit(1)
		return
	var context := {"save_id":"save_birth_fixture","seed":71,"npc_id":"npc_o_2_20001"}
	var untouched := JSON.stringify([context,config])
	var proposal := Identity.propose(context,config)
	check(not proposal.is_empty() and Identity.record_valid(proposal,config),"new selector proposes one complete valid birth record")
	if proposal.is_empty():
		quit(1)
		return
	check(proposal==Identity.propose(context,config),"same save/seed/npc preserves every selected identity field")
	var after_exclusion := Identity.propose(context,config,[proposal.name])
	check(not after_exclusion.is_empty() and after_exclusion.name!=proposal.name,"stable exclusion selects another complete full name")
	if after_exclusion.is_empty():
		quit(1)
		return
	check(after_exclusion.cultural_origin==proposal.cultural_origin and after_exclusion.name_pool_id==proposal.name_pool_id and after_exclusion.skin_id==proposal.skin_id,"collision does not reroll culture/pool/skin")
	check(after_exclusion==Identity.propose(context,config,[proposal.name,proposal.name]),"duplicate exclusions do not shift deterministic selection")
	var friend_context := context.duplicate(true)
	friend_context.npc_id += "_friend"
	var friend := Identity.propose(friend_context,config,[proposal.name])
	check(Identity.record_valid(friend,config) and friend.name!=proposal.name,"independent stable contact excludes the main person's selected name")
	for kind: String in ["local","foreign","mixed"]:
		var selected := config.duplicate(true)
		for key: String in selected.rules.groups:
			selected.rules.groups[key] = 1 if key==kind else 0
		for region: String in ["europe","africa","south_asia","latin_america","middle_east"]:
			for row: Dictionary in selected.rules.regions:
				row.weight = 1 if row.id==region else 0
			var record := Identity.propose(context,selected)
			check(Identity.record_valid(record,selected),"forced pure group/region selection is valid / "+kind+" / "+region)
			if record.is_empty():
				continue
			check(record.cultural_origin==(region if kind=="foreign" else kind),"cultural_origin follows the selected group / "+kind+" / "+region)
			if kind=="mixed":
				check(record.name_pool_id==selected.rules.mixed.pool_id_prefix+region and not record.name.contains("·"),"mixed preserves a Chinese surname followed by a regional given name / "+region)
	var base := config.duplicate(true)
	base.rules.groups = {"local":0,"foreign":1,"mixed":0}
	for row: Dictionary in base.rules.regions:
		row.weight = 1 if row.id=="europe" else 0
	var surnames: Array = base.rules.foreign_pools[0].surnames
	var given: Array = base.rules.foreign_pools[0].given_names
	var excluded: Array = []
	for surname: String in surnames:
		for first: String in given:
			excluded.append(base.rules.formats.foreign.format({"surname":surname,"given_name":first}))
	var final_name: String = excluded.pop_back()
	var remaining := Identity.propose(context,base,excluded)
	check(not remaining.is_empty() and remaining.name==final_name,"bounded stable scan finds the only nonexcluded name")
	excluded.append(final_name)
	check(Identity.propose(context,base,excluded).is_empty(),"an exhausted selected pool fails closed without switching identity origin")
	for mutation: String in ["name_suffix","cross_pool","skin","partial","version","extra","mixed_order"]:
		var bad := proposal.duplicate(true)
		match mutation:
			"name_suffix": bad.name += "附"
			"cross_pool": bad.name_pool_id = "unlisted_pool"
			"skin": bad.skin_id = "skin_99"
			"partial": bad.erase("name")
			"version": bad.version = true
			"extra": bad["origin"] = "random_first"
			"mixed_order":
				bad = {"version":1,"cultural_origin":"mixed","name_pool_id":"mixed_europe","name":"皮特·许","skin_id":"skin_01"}
		check(not Identity.record_valid(bad,config),"whole-record semantics reject invalid identity / "+mutation)
	for mutation: String in ["short_given","short_surname","duplicate","unknown_skin","bad_weight","bad_scan","bad_format"]:
		var bad := config.duplicate(true)
		match mutation:
			"short_given": bad.rules.foreign_pools[0].given_names.pop_back()
			"short_surname": bad.rules.foreign_pools[0].surnames.pop_back()
			"duplicate": bad.rules.foreign_pools[0].given_names[1] = bad.rules.foreign_pools[0].given_names[0]
			"unknown_skin": bad.rules.foreign_pools[0].skin_ids.append("skin_99")
			"bad_weight": bad.rules.groups.foreign = NAN
			"bad_scan": bad.rules.collision.max_scan_steps = 1
			"bad_format": bad.rules.formats.mixed = "{given_name}·{surname}"
		check(not Identity.config_valid(bad) and Identity.propose(context,bad).is_empty(),"bad configuration rejects before selection / "+mutation)
	check(Identity.propose({"save_id":"","seed":71,"npc_id":"npc_new"},config).is_empty(),"missing namespace fails closed")
	check(Identity.propose({"save_id":"save","seed":NAN,"npc_id":"npc_new"},config).is_empty(),"nonfinite seed fails closed")
	check(Identity.propose(context,config.rules).is_empty() and not Identity.record_valid(proposal,config.rules),"unresolved raw rules are not mistaken for a resolved selector configuration")
	var templates: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Identity.TEMPLATE_PATH))
	var nested_resolved := config.duplicate(true)
	nested_resolved.rules = config.duplicate(true)
	var nested_rejected := not Identity.config_valid(nested_resolved)
	check(nested_rejected,"a resolved configuration cannot contain another resolved rules payload")
	if nested_rejected:
		check(Identity.propose(context,nested_resolved).is_empty() and not Identity.record_valid(proposal,nested_resolved),"nested resolved configuration fails closed before rule consumers")
	check_disk_shapes(config,templates)
	check(not Identity.config_valid(config.rules,templates,{"palettes":[]}),"malformed dependency palette fails closed without calling a method on an array")
	check(JSON.stringify([context,config])==untouched,"no selector mutates context or resolved content")
	var disabled := config.duplicate(true)
	disabled.rules.enabled = false
	check(Identity.propose(context,disabled).is_empty() and Identity.record_valid(proposal,disabled),"disabled future generation still permits reading a previously valid record")
	var same_object := config.duplicate(true)
	check(Identity.config_valid(same_object),"mutable caller config starts from a validated full payload")
	same_object.rules.groups.local=-1
	check(not Identity.config_valid(same_object),"same Dictionary after nested weight mutation must be revalidated")
	same_object.rules.groups.local=config.rules.groups.local
	check(Identity.config_valid(same_object),"restored caller payload validates again")
	same_object.local_given_names[1]=same_object.local_given_names[0]
	check(not Identity.config_valid(same_object),"same Dictionary after dependency-name mutation must be rejected")
	same_object.local_given_names=config.local_given_names.duplicate(true)
	same_object.skin_palette_ids=[]
	check(not Identity.config_valid(same_object),"same Dictionary after palette dependency mutation must be rejected")
	var same_templates := templates.duplicate(true)
	var appearance_dependency: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Identity.APPEARANCE_PATH))
	check(Identity.config_valid(config.rules,same_templates,appearance_dependency),"raw rules and explicit dependencies validate before mutation")
	same_templates.ordinary_names[1]=same_templates.ordinary_names[0]
	check(not Identity.config_valid(config.rules,same_templates,appearance_dependency),"raw-rule validation cannot reuse a result after its template dependency changes")
	var unsupported:=config.duplicate(true)
	unsupported.rules.groups.local=RefCounted.new()
	check(not Identity.config_valid(unsupported),"non-JSON objects reject before fingerprint serialization")
	print("BIRTH IDENTITY: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func check_disk_shapes(config: Dictionary, templates: Dictionary) -> void:
	# Compile an isolated copy with only its disk path changed. Never replace the
	# production JSON while another engine is running UI acceptance.
	var folder := "res://.tools/r3-names/birth-shape/"+str(Time.get_ticks_usec())
	var disk_path := folder+"/name_pools.json"
	var made := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	check(made==OK,"isolated disk-shape fixture directory is available")
	if made!=OK:
		return
	var source := FileAccess.get_file_as_string("res://scripts/people/birth_identity.gd")
	var original_line := 'const CONFIG_PATH := "%s"' % Identity.CONFIG_PATH
	check(source.count(original_line)==1,"isolated loader changes exactly the config path declaration")
	if source.count(original_line)!=1:
		return
	var loader := GDScript.new()
	loader.source_code = source.replace(original_line,'const CONFIG_PATH := "%s"' % disk_path)
	var compiled := loader.reload()
	check(compiled==OK,"isolated selector loader compiles")
	if compiled!=OK:
		return
	var appearance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Identity.APPEARANCE_PATH))
	var nested := config.duplicate(true)
	nested.rules = config.duplicate(true)
	for row: Dictionary in [{"label":"raw","value":config.rules},{"label":"resolved","value":config},{"label":"nested resolved","value":nested}]:
		var output := FileAccess.open(disk_path,FileAccess.WRITE)
		check(output!=null,"isolated disk-shape fixture opens / "+row.label)
		if output==null:
			return
		output.store_string(JSON.stringify(row.value,"",true,true))
		var written := output.get_error()==OK
		output.close()
		check(written,"isolated disk-shape fixture writes / "+row.label)
		if not written:
			return
		var loaded: Dictionary = loader.call("load_config",templates,appearance)
		check(loaded==config if row.label=="raw" else loaded.is_empty(),"disk loader accepts only raw rules / "+row.label)
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(disk_path))==OK,"isolated disk-shape fixture file is removed")
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))==OK,"isolated disk-shape fixture directory is removed")

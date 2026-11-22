extends SceneTree
## Independent rule oracles; no image availability is treated as art approval.
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("APPEARANCE FAIL: "+label)

func _initialize() -> void:
	var script_path := "res://scripts/people/appearance.gd"
	check(ResourceLoader.exists(script_path),"data-driven appearance module exists")
	if not ResourceLoader.exists(script_path):
		finish()
		return
	var rules: GDScript = load(script_path)
	var config: Dictionary = rules.load_config()
	check(rules.config_valid(config),"production catalog validates without treating pending art as final")
	if config.is_empty():
		finish()
		return
	var original := config.duplicate(true)
	var a: Dictionary = rules.generate(config,"save_fixture","npc_fixture")
	check(rules.appearance_valid(a,config),"new deterministic appearance is canonical and legal")
	check(a == rules.generate(config,"save_fixture","npc_fixture"),"same save and identity regenerate exactly")
	check(a != rules.generate(config,"save_fixture","npc_other"),"independent identity does not inherit the same appearance")
	check(config == original,"generation never mutates shared catalog")
	check(not a.has("mood") and not a.parts.has("preset"),"expression is not saved as part of stable identity")
	var legacy := {"face":"face_02","hair":"hair_03","outfit":"outfit_01"}
	var mapped: Dictionary = rules.normalize(legacy,config,"old_person")
	check(rules.appearance_valid(mapped,config) and mapped.parts.face_shape == "face_02" and mapped.parts.hair_front == "hair_front_03","explicit legacy keys retain their selected shape")
	check(legacy == {"face":"face_02","hair":"hair_03","outfit":"outfit_01"},"legacy mapping does not rewrite input")
	check(rules.normalize({"face":"bad","hair":"hair_01","outfit":"outfit_01"},config).is_empty(),"unknown legacy ID rejected")
	check(rules.normalize({"preset":"portrait_lin"},config) == {"preset":"portrait_lin"},"fixed portrait remains a fixed preset")
	var invalid := a.duplicate(true)
	invalid.parts.face_shape = "../../escape"
	check(not rules.appearance_valid(invalid,config),"path injection cannot become a part ID")
	invalid = a.duplicate(true); invalid.colors.skin = "skin_unknown"
	check(not rules.appearance_valid(invalid,config),"unknown palette rejected")
	invalid = a.duplicate(true); invalid.parts["untrusted"] = "body_01"
	check(not rules.appearance_valid(invalid,config),"extra parts rejected")
	invalid = a.duplicate(true); invalid.parts.hair_front = "hair_front_12"; invalid.parts.accessory = "accessory_10"
	check(not rules.appearance_valid(invalid,config),"hat and high ponytail mutual exclusion enforced")
	var described: Dictionary = rules.map_description("短发，戴眼镜的中年居民",a,config)
	check(rules.appearance_valid(described,config) and described.parts.accessory == "accessory_01" and described.age_stage == "middle" and described.parts.features == "features_middle","visible description maps through local catalog rules")
	check(rules.map_description("npc_secret skin_99",a,config) == a,"technical tokens in text never select unlisted IDs")
	var existing: Array = []
	var silhouettes := {}
	for index: int in range(24):
		var item: Dictionary = rules.generate(config,"save_24","npc_"+str(index),existing)
		check(rules.appearance_valid(item,config),"24-person candidate legal / "+str(index))
		var silhouette := JSON.stringify([item.parts.hair_front,item.parts.hair_back,item.parts.accessory,item.colors.hair])
		check(not silhouettes.has(silhouette),"24-person primary silhouette distinct / "+str(index))
		silhouettes[silhouette] = true
		existing.append(item)
	for mood: String in config.moods:
		var records: Array = rules.layer_records(a,mood,config)
		check(records.size() == config.layer_order.size(),"ten layers retained across expression / "+mood)
		for index: int in range(records.size()):
			check(records[index].layer == config.layer_order[index] and records[index].has("available"),"path lookup preserves ordered layer and explicit availability / "+mood+"/"+str(index))
	var bad := config.duplicate(true); bad.generation.maximum_attempts = 0
	check(not rules.config_valid(bad),"unbounded/zero sampling attempt limit rejected")
	bad = config.duplicate(true); bad.palettes.skin[0].colors[0] = "invalid"
	check(not rules.config_valid(bad),"invalid gradient color rejected")
	bad = config.duplicate(true); bad.parts.face_shape[0].path = "res://../../escape.png"
	check(not rules.config_valid(bad),"unsafe asset path rejected")
	check_mouth_skin_palette(rules,config)
	check_feature_skin_palette(rules,config)
	check_actual_hair_selection(rules,config)
	finish()

func check_actual_hair_selection(rules: GDScript, config: Dictionary) -> void:
	# Independent oracle from the approved pixels: back06 is the high ponytail;
	# front12 is long face-framing hair and must not be forced by that description.
	var identity: Dictionary = rules.normalize(config.defaults,config)
	var original := identity.duplicate(true)
	var mapped: Dictionary = rules.map_description("扎着高马尾的小镇居民",identity,config)
	check(mapped.parts.hair_back == "hair_back_06" and mapped.parts.hair_front == identity.parts.hair_front,"high ponytail description selects actual approved rear hair without inventing long front hair")
	check(identity == original,"description remapping never rerolls or edits the supplied permanent identity")
	for hat: String in ["accessory_10","accessory_11","accessory_12"]:
		var stored := identity.duplicate(true)
		stored.parts.hair_back = "hair_back_06"
		stored.parts.accessory = hat
		check(rules.appearance_valid(stored,config) and rules.normalize(stored,config) == stored,"previously legal stored high-tail/hat remains structurally accepted / "+hat)
		if rules.has_method("selection_valid"):
			check(not rules.selection_valid(stored,config),"new draft rejects actual high ponytail under a closed hat / "+hat)
		else:
			check(false,"new selection compatibility boundary exists independently from stored identity validation / "+hat)
		var hat_source := identity.duplicate(true)
		hat_source.parts.accessory = hat
		var description_source := hat_source.duplicate(true)
		var with_tail: Dictionary = rules.map_description("扎着高马尾的小镇居民",hat_source,config)
		check(with_tail.parts.hair_back == "hair_back_06" and with_tail.parts.accessory == "none" and hat_source == description_source,"new high-tail description avoids a conflicting hat without mutating its source / "+hat)
	# Keep full catalog counts/IDs, but give an adult only back06 and the three hats
	# or no accessory. The hand-derived only wearable accessory is `none`.
	var focused := config.duplicate(true)
	focused.defaults.parts.hair_back = "hair_back_06"
	focused.defaults.parts.accessory = "none"
	for row: Dictionary in focused.parts.hair_back:
		if row.id != "hair_back_06":
			row.ages = ["teen"]
	for row: Dictionary in focused.parts.accessory:
		if row.id not in ["none","accessory_10","accessory_11","accessory_12"]:
			row.ages = ["teen"]
	check(rules.config_valid(focused),"adversarial new-selection fixture remains a complete valid catalog")
	for index: int in range(12):
		var generated: Dictionary = rules.generate(focused,"actual-tail-selection","person_"+str(index))
		check(generated.parts.hair_back == "hair_back_06" and generated.parts.accessory == "none","new generated person avoids real tail/hat overlap / "+str(index))
	var no_new_rules := config.duplicate(true)
	no_new_rules.erase("selection_exclusions")
	check(rules.config_valid(no_new_rules),"historical catalog without new selection-only constraints remains readable")
	for bad_rule: Variant in [null,{},[{"hair_back":"missing","accessory":"accessory_10"}],[{"hair_back":"hair_back_06"}]]:
		var invalid := config.duplicate(true)
		invalid["selection_exclusions"] = bad_rule
		check(not rules.config_valid(invalid),"selection-only rules reject malformed data without altering legacy validity")

func check_mouth_skin_palette(rules: GDScript, config: Dictionary) -> void:
	# Regression oracle: a grey lip edge follows skin at both palette extremes,
	# while the eyes retain their painted whites/iris. No artwork or state writes.
	var light: Dictionary = config.palettes.skin[0]
	var deep: Dictionary = config.palettes.skin[-1]
	check(Color(light.colors[1]).get_luminance() > Color(deep.colors[1]).get_luminance(),"palette fixture exercises genuinely light and deep skin")
	var original := config.duplicate(true)
	for skin: Dictionary in [light,deep]:
		for mouth: Dictionary in config.parts.mouth_expr:
			for mood: String in config.moods:
				var identity: Dictionary = config.defaults.duplicate(true)
				identity.parts.mouth_expr = mouth.id
				identity.colors.skin = skin.id
				var before := identity.duplicate(true)
				var by_layer := {}
				for record: Dictionary in rules.layer_records(identity,mood,config):
					by_layer[record.layer] = record
				var projected: Dictionary = by_layer.get("mouth_expr",{})
				var mapped_colors: Array = []
				for palette: Dictionary in config.palettes.get(projected.get("tint",""),[]):
					if palette.id == identity.colors.skin:
						mapped_colors = palette.colors
				check(projected.get("tint") == "skin" and projected.get("tint") == by_layer.body.tint and projected.get("tint") == by_layer.face_shape.tint and mapped_colors == skin.colors and projected.get("path") == mouth.paths[mood] and by_layer.eyes_expr.tint == "none" and identity == before,"lip edge selects actual skin gradient and keeps eyes/path/identity / "+str(skin.id)+"/"+str(mouth.id)+"/"+mood)
	check(config == original,"palette projection does not rewrite catalog or art approval")

func check_feature_skin_palette(rules: GDScript, config: Dictionary) -> void:
	# Actual v3 pilot trigger: a pale grey beauty mark looked pasted on dark skin.
	# Surface marks/wrinkles use skin; white hair belongs to its separate palette.
	var original := config.duplicate(true)
	var covered_stages := {}
	for skin: Dictionary in [config.palettes.skin[0],config.palettes.skin[-1]]:
		for feature: Dictionary in config.parts.features:
			var identity: Dictionary = config.defaults.duplicate(true)
			identity.age_stage = feature.ages[0]
			identity.parts.features = feature.id
			identity.colors.skin = skin.id
			covered_stages[identity.age_stage] = true
			var before := identity.duplicate(true)
			check(rules.appearance_valid(identity,config),"surface-feature fixture is legal for age and skin / "+str(identity.age_stage)+"/"+str(skin.id))
			for mood: String in config.moods:
				var by_layer := {}
				for record: Dictionary in rules.layer_records(identity,mood,config):
					by_layer[record.layer] = record
				var projected: Dictionary = by_layer.get("features",{})
				var mapped_colors: Array = []
				for palette: Dictionary in config.palettes.get(projected.get("tint",""),[]):
					if palette.id == identity.colors.skin:
						mapped_colors = palette.colors
				check(projected.get("id") == feature.id and projected.get("tint") == "skin" and mapped_colors == skin.colors and projected.get("path") == feature.path and by_layer.eyes_expr.tint == "none" and identity == before,"surface feature follows actual skin gradient without changing eyes/path/identity / "+str(identity.age_stage)+"/"+str(skin.id)+"/"+mood)
	check(covered_stages.size() == config.age_stages.size() and config.age_stages.all(func(stage: String) -> bool: return covered_stages.has(stage)),"all age stages covered by surface-feature palette regression")
	check(config == original,"feature projection preserves paths/status/version and every catalog field")

func finish() -> void:
	print("APPEARANCE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

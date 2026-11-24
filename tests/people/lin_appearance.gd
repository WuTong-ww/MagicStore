extends SceneTree
## Isolated LIN assertions; production execution is deferred until STORY is frozen.
const Appearance = preload("res://scripts/people/appearance.gd")
const StoryContent = preload("res://scripts/story/story_content.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("LIN APPEARANCE FAIL: "+label)

func run() -> void:
	var appearance_api := Appearance.new()
	var config := Appearance.load_config()
	var npcs := StoryContent.load_npcs()
	check(not config.is_empty() and not npcs.is_empty(),"existing catalog and story descriptor validators accept the authored selection")
	if not npcs.is_empty():
		check(npcs.npc_lin.appearance.parts.hair_back=="hair_back_10" and npcs.npc_lin.appearance.parts.outfit=="outfit_02" and npcs.npc_lin.appearance.colors.outfit=="outfit_01","Lin's authored descriptor contains the selected long hair, work apron and sage palette")
	check(appearance_api.has_method("for_display") and appearance_api.has_method("fixed_npc_appearance"),"readonly fixed appearance display boundary exists")
	if failures:
		finish()
		return
	var fixed: Dictionary = appearance_api.call("fixed_npc_appearance","npc_lin",config)
	check(fixed==Appearance.normalize(npcs.npc_lin.appearance,config) and Appearance.selection_valid(fixed,config),"fixed selection comes from validated story data")
	check(fixed.parts=={"hair_back":"hair_back_10","body":"body_01","outfit":"outfit_02","face_shape":"face_01","features":"features_adult","eyes_expr":"eyes_01","brows_expr":"brows_01","mouth_expr":"mouth_01","hair_front":"hair_front_02","accessory":"none"},"the plan's complete adult long-hair/apron selection is exact")
	check(fixed.colors=={"skin":"skin_02","hair":"hair_02","outfit":"outfit_01"} and fixed.age_stage=="adult","authored palettes and age stage are exact")
	check(npcs.npc_lin.get("preserve_existing_appearance",false),"story admission still preserves existing appearance")
	for id: String in ["portrait_lin","npc_lin"]:
		var legacy := {"preset":id}
		var before := legacy.duplicate(true)
		check(Appearance.appearance_valid(legacy,config) and Appearance.normalize(legacy,config)==legacy,"old preset remains a legal unchanged saved value / "+id)
		var shown: Dictionary = appearance_api.call("for_display",legacy,"npc_lin",config)
		check(shown==fixed and legacy==before,"legacy rendering maps without mutating its caller / "+id)
		shown.parts.hair_front = "hair_front_01"
		check(appearance_api.call("for_display",legacy,"npc_lin",config)==fixed,"returned display copies cannot poison the descriptor cache / "+id)
		for mood: String in config.moods:
			var rows := Appearance.layer_records(legacy,mood,config)
			var expected := Appearance.layer_records(fixed,mood,config)
			check(rows==expected and rows.size()==config.layer_order.size(),"all preset callers use the same complete A4 layers / "+id+" / "+mood)
			check(rows.all(func(row:Dictionary)->bool:return row.layer!="preset" and not str(row.path).contains("assets/portraits/npc_lin") and not str(row.path).contains("portrait_lin.svg")),"no legacy Lin image path is exposed / "+id+" / "+mood)
	var historical: Dictionary = Appearance.normalize(config.defaults,config)
	historical.parts.hair_back = "hair_back_06"
	historical.parts.accessory = "accessory_10"
	check(Appearance.appearance_valid(historical,config) and not Appearance.selection_valid(historical,config),"fixture represents readable old parts excluded only from new selection")
	var original := historical.duplicate(true)
	check(appearance_api.call("for_display",historical,"npc_lin",config)==historical and historical==original,"existing parts retain their exact IDs even for Lin and historical selection exclusions")
	check(appearance_api.call("for_display",{},"npc_lin",config)==fixed and appearance_api.call("for_display",{},"someone_else",config)=={},"only an unidentified Lin portrait falls back to the fixed authored appearance")
	var unrelated := config.duplicate(true)
	unrelated.presets["fixture_other"] = unrelated.presets.portrait_lin.duplicate(true)
	check(Appearance.config_valid(unrelated) and appearance_api.call("for_display",{"preset":"fixture_other"},"someone_else",unrelated)=={"preset":"fixture_other"},"unrelated legal presets retain their own rendering contract")
	var bad_config := config.duplicate(true)
	bad_config.parts.hair_back = []
	check(appearance_api.call("fixed_npc_appearance","npc_lin",bad_config)=={},"invalid authored-part lookup fails closed instead of generating a replacement")
	check(appearance_api.call("fixed_npc_appearance","missing_npc",config)=={},"unknown fixed identity does not generate a face")
	finish()

func finish() -> void:
	print("LIN APPEARANCE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

extends SceneTree
const Catalog = preload("res://scripts/audio/music_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var config := Catalog.load_data()
	check(not config.is_empty(),"production catalog remains valid")
	if not config.is_empty():
		for slot: String in ["day","deduction"]:
			check(Catalog.track_for_slot(slot,config).get("id") == "sheep","user-selected Sheep / "+slot)
		check(Catalog.key_for("consultation",540,config,{"case_active":true}) == "deduction","saved CASE keeps its routing")
		var mixed := config.duplicate(true)
		mixed.source.selection_basis = "filename_and_user_choice"
		check(Catalog.config_valid(mixed),"provenance can record the user's specific override")
		mixed.source.selection_basis = "unverified"
		check(not Catalog.config_valid(mixed),"unknown provenance remains rejected")
	print("MUSIC SHEEP: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MUSIC SHEEP FAIL: "+label)

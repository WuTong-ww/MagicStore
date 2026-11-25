extends SceneTree
## Production metadata only; no stream/resource/audio file is opened.
const Catalog = preload("res://scripts/audio/music_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MUSIC CATALOG FAIL: "+label)

func run() -> void:
	var config := Catalog.load_data()
	check(not config.is_empty(),"production metadata JSON validates without runtime music")
	if config.is_empty():
		finish()
		return
	check(config.tracks.size() == 21 and config.slots.size() == 5,"all cached tracks and exactly five slots")
	check(config.crossfade_seconds == 1.5 and config.encoding.vorbis_quality == 6,"requested defaults are data")
	check(Catalog.key_for("title",0,config) == "opening","title routes to opening")
	check(Catalog.key_for("consultation",600,config,{"case_active":true}) == "deduction","public active-case context routes deduction")
	check(Catalog.key_for("consultation",600,config,{"case_active":false}) == "day","ordinary consultation follows clock")
	check(Catalog.key_for("ending",600,config,{"ending_visible":false}) == "day","unrevealed ending does not select ending")
	check(Catalog.key_for("front",600,config,{"ending_visible":true}) == "ending","public visible ending routes ending")
	check(Catalog.key_for("front",1080,config) == "night","night boundary follows data")
	check(Catalog.key_for("front",600,config,{"truth":{"hidden":true}}).is_empty(),"private context is refused")
	var broken := config.duplicate(true)
	broken.tracks[0].runtime_path = "res://assets/audio/music/../outside.ogg"
	check(not Catalog.config_valid(broken),"unsafe runtime path refused")
	broken = config.duplicate(true)
	broken.tracks[0].duration_seconds = INF
	check(not Catalog.config_valid(broken),"nonfinite metadata duration refused")
	broken = config.duplicate(true)
	broken.slots.opening.track_id = "absent"
	check(not Catalog.config_valid(broken),"unknown selected track refused")
	broken = config.duplicate(true)
	broken.slots.opening.track_id = broken.slots.opening.candidates[0]
	check(Catalog.config_valid(broken),"one-line switch to candidate remains valid")
	check(Catalog.track_for_slot("opening",broken).id == broken.slots.opening.track_id,"track resolver follows selection")
	for track: Dictionary in config.tracks:
		broken = config.duplicate(true)
		broken.slots.opening.track_id = track.id
		check(Catalog.config_valid(broken) and Catalog.track_for_slot("opening",broken).id == track.id,"one-line selection supports every catalog track / "+track.id)
	for mutation: Dictionary in [
		{"path":["version"],"value":2},
		{"path":["enabled"],"value":"true"},
		{"path":["inventory_count"],"value":20},
		{"path":["crossfade_seconds"],"value":NAN},
		{"path":["crossfade_seconds"],"value":0},
		{"path":["encoding","codec"],"value":"copy"},
		{"path":["encoding","policy"],"value":"encoded_local"},
		{"path":["encoding","vorbis_quality"],"value":11},
		{"path":["encoding","vorbis_quality"],"value":6.5},
		{"path":["clock","day_minute"],"value":1080},
		{"path":["clock","night_minute"],"value":1440},
		{"path":["runtime_missing_behavior"],"value":"error"},
		{"path":["routing","case_pages"],"value":[]},
		{"path":["routing","page_slots","ending"],"value":"day"},
		{"path":["slots","night","label"],"value":"Night"},
		{"path":["slots","night","candidates"],"value":["missing"]},
		{"path":["slots","night","candidates"],"value":["polar_lights","polar_lights"]},
		{"path":["tracks",0,"id"],"value":"../../escape"},
		{"path":["tracks",0,"source_filename"],"value":"C:/private.ogg"},
		{"path":["tracks",0,"source_sha256"],"value":"bad"},
		{"path":["tracks",0,"duration_seconds"],"value":-1},
		{"path":["source","listening_review"],"value":"assumed"},
		{"path":["source","license","historical_local_pack_license_proven"],"value":"true"}
	]:
		broken = config.duplicate(true)
		var cursor: Variant = broken
		var path: Array = mutation.path
		for index: int in range(path.size()-1):
			cursor = cursor[path[index]]
		cursor[path.back()] = mutation.value
		check(not Catalog.config_valid(broken),"reject malformed metadata / "+str(path))
	broken = config.duplicate(true)
	broken.tracks[1] = broken.tracks[0].duplicate(true)
	check(not Catalog.config_valid(broken),"duplicate track identity refused")
	broken = config.duplicate(true)
	broken.unexpected = true
	check(not Catalog.config_valid(broken),"unknown top-level fields refused")
	check(Catalog.key_for("front",539,config)=="night" and Catalog.key_for("front",540,config)=="day" and Catalog.key_for("front",1079,config)=="day" and Catalog.key_for("front",1080,config)=="night","exact day/night boundaries")
	check(Catalog.key_for("front",540+1440,config)=="day" and Catalog.key_for("front",-1,config)=="night","clock wraps across days")
	check(Catalog.key_for("consultation",600,config,{"case_active":"true"}).is_empty(),"malformed public context refused")
	finish()

func finish() -> void:
	print("MUSIC CATALOG: %d checks, %d failures"%[checks,failures])
	quit(0 if failures == 0 else 1)

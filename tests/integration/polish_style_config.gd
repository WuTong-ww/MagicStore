extends SceneTree
const Fonts = preload("res://scripts/ui/font_policy.gd")
const Style = preload("res://scripts/ui/style_config.gd")
const Icons = preload("res://scripts/ui/icon_policy.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH CONFIG FAIL: "+label)

func run() -> void:
	var fonts := Fonts.load_config()
	var style := Style.load_config()
	var icons := Icons.load_config()
	check(not fonts.is_empty(),"authored font policy passes its real validator")
	check(not style.is_empty(),"authored style passes its real validator")
	check(not icons.is_empty(),"authored image atlas passes its real validator")
	for config: Dictionary in [fonts,style,icons]:
		var validator: Callable = Fonts.config_valid if config == fonts else Style.config_valid if config == style else Icons.config_valid
		var extra := config.duplicate(true)
		extra["unknown"] = true
		check(not validator.call(extra),"unknown top-level key is rejected")
		for version: Variant in [true,"1",null,2]:
			var changed := config.duplicate(true)
			changed.version = version
			check(not validator.call(changed),"invalid version/type is rejected")
	if not fonts.is_empty():
		for path: String in ["res://assets/fonts/../bad.ttf","user://bad.ttf","res://assets/fonts/x.woff"]:
			var changed := fonts.duplicate(true)
			changed.regular = path
			check(not Fonts.config_valid(changed),"font path traversal/external/wrong format is rejected")
		var changed := fonts.duplicate(true)
		changed.ascii_range = [32,true]
		check(not Fonts.config_valid(changed),"boolean is not a codepoint")
	if not style.is_empty():
		for value: Variant in [true,-1,0.5,INF,NAN,"18"]:
			var changed := style.duplicate(true)
			changed.metrics.font_size = value
			check(not Style.config_valid(changed),"invalid presentation metric is rejected")
		var changed := style.duplicate(true)
		changed.colors.ink = "#FFFFFF00"
		check(not Style.config_valid(changed),"alpha/unsupported color shape is rejected")
	if not icons.is_empty():
		for value: Variant in [true,-1,16,0.5,"0"]:
			var changed := icons.duplicate(true)
			changed.icons.nav_door = value
			check(not Icons.config_valid(changed),"invalid atlas index is rejected")
		var changed := icons.duplicate(true)
		changed.icons.nav_door = changed.icons.nav_counter
		check(not Icons.config_valid(changed),"duplicated atlas region is rejected")
		for id: String in Icons.IDS:
			check(Icons.texture(id) is AtlasTexture,"actual texture region exists / "+id)
	print("POLISH CONFIG: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

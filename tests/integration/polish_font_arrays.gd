extends SceneTree
const Fonts = preload("res://scripts/ui/font_policy.gd")
const Icons = preload("res://scripts/ui/icon_policy.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH NUMERIC CONFIG FAIL: "+label)

func run() -> void:
	var fonts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Fonts.PATH))
	var icons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Icons.PATH))
	check(Fonts.config_valid(fonts),"the real JSON parsed font range is valid")
	check(Icons.config_valid(icons),"the real JSON parsed icon cell dimensions are valid")
	var native := fonts.duplicate(true)
	native.ascii_range = [32,126]
	check(Fonts.config_valid(native),"native integer range remains valid")
	var cells := icons.duplicate(true)
	cells.cell_size = [32,32]
	check(Icons.config_valid(cells),"native integer cells remain valid")
	for bad: Variant in [true,false,null,"32",32.5,INF,NAN,1.0e100,-32,0]:
		var altered := fonts.duplicate(true)
		altered.ascii_range[0] = bad
		check(not Fonts.config_valid(altered),"invalid codepoint type/fraction/nonfinite/value is rejected")
		var changed := icons.duplicate(true)
		changed.cell_size[0] = bad
		check(not Icons.config_valid(changed),"invalid cell type/fraction/nonfinite/value is rejected")
	print("POLISH NUMERIC CONFIG: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

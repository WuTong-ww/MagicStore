extends SceneTree
const Arrival = preload("res://scripts/ui/arrival_ui.gd")
const Board = preload("res://scripts/ui/case_board_config.gd")
const Icons = preload("res://scripts/ui/icon_policy.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH ICONS FAIL: "+label)

func run() -> void:
	# Load the autoload-dependent Window after SceneTree initialization.
	var frame_script: Script = load("res://scripts/divination/workbench.gd")
	var arrival := Arrival.load_config()
	check(not arrival.is_empty(),"real arrival configuration remains valid")
	for row: Dictionary in arrival.get("patience_levels",[]):
		var count: Variant = row.get("icon_count",0)
		check(row.get("icon") == "patience" and (count is int or count is float) and is_finite(float(count)) and float(count) == floor(float(count)) and count >= 1 and count <= 3,"patience is an image with a separate dynamic count")
		check(not Arrival.patience_text({"patience_ratio":row.minimum_ratio,"patience_minutes":12}).contains("⌛"),"accessible patience text contains no font icon")
	var frame: Dictionary = frame_script.load_frame_config()
	check(frame.get("close_symbol") == "close","notebook close points to the image registry")
	var board := Board.load_config()
	for pair: Array in [["star","star"],["seal_mark","seal"],["ornament","ornament"]]:
		check(board.get("copy",{}).get(pair[0]) == pair[1],"CASE graphic points to the image registry / "+pair[0])
	for path: String in ["scripts/ui/main.gd","scripts/ui/shop_front.gd","scripts/ui/case_board.gd","scripts/divination/workbench.gd","scripts/divination/oracle_panels.gd"]:
		var source := FileAccess.get_file_as_string("res://"+path)
		for glyph: String in ["⌂","☏","⚒","⌛","✕","★","◆","━━━━","────────────────"]:
			check(not source.contains(glyph),"production UI no longer embeds the graphical glyph / "+path)
	for id: String in Icons.IDS:
		check(Icons.texture(id) is AtlasTexture,"the icon uses a real SVG atlas region / "+id)
	print("POLISH ICONS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

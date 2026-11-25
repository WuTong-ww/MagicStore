extends SceneTree
## The new module is deliberately not preloaded. Missing behavior is a normal
## assertion failure on the real pre-feature production UI, never a parse RED.
const UI = preload("res://scripts/ui/ui_kit.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PANEL MATERIAL FAIL: "+label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var panel := UI.panel()
	check(panel != null,"pre-existing functional panel remains available before the material module")
	var path := "res://scripts/ui/panel_materials.gd"
	var exists := ResourceLoader.exists(path)
	check(exists,"production owns a real data-driven material module instead of only flat themed frames")
	if not exists:
		check(panel.get_meta("material_role","") == "notebook","reasoning panel can identify itself as a single notebook object")
		panel.free()
		finish()
		return
	var script: GDScript = load(path)
	var api: RefCounted = script.new()
	var config: Dictionary = api.call("load_config")
	check(not config.is_empty() and api.call("config_valid",config),"production material JSON passes its strict validator even while source art is pending")
	if config.is_empty():
		panel.free()
		finish()
		return
	var original := config.duplicate(true)
	var applied: Dictionary = api.call("apply_panel",panel,"notebook")
	check(applied.get("success",false) and panel.get_meta("material_role","") == "notebook","one notebook surface attaches without replacing its existing content controls")
	var plain: StyleBox = api.call("style_for","plain")
	check(plain is StyleBoxEmpty,"internal sections are transparent and borderless instead of nested frames")
	var pending := config.duplicate(true)
	pending.assets.notebook.native_size = [0,0]
	var status: Dictionary = api.call("asset_status","notebook",pending)
	check(not status.get("ready",true),"an unknown native source size cannot be reported as selected or ready")
	check(api.call("style_for","notebook","",pending) != null,"missing/unprepared art has an honest functional fallback")
	check(api.call("evidence_role","misleading") == "neutral" and api.call("evidence_role","unknown") == "neutral","public unknown/misleading kinds do not gain a secret diagnostic color")
	check(api.call("evidence_role","testimony") == "testimony","already-public testimony stays testimony without consulting hidden facts")
	var pages: Array = api.call("content_rects",Vector2(800,500),"notebook")
	check(pages.size() == 2 and pages[0].end.x < pages[1].position.x,"notebook content guides reserve the thin central spine rather than stretching it into text")
	check(config.shadow.opacity == 0.25 and config.shadow.offset.size() == 2 and config.shadow.offset[0] == 0 and config.shadow.offset[1] == 6 and config.shadow.blur == 12 and config.backdrop.opacity == 0.15,"all shared physical shadow/backdrop values are data and match the user supplement")
	check(config.effects.paper_hover_y == -2 and config.effects.stamp_seconds == 0.2 and config.effects.candidate_degrees == 1.5,"hover, stamp and stable angle values live in JSON")
	for bad_value: Variant in [null,[],{},true,7,"materials"]:
		var bad := config.duplicate(true)
		bad.assets = bad_value
		check(not api.call("config_valid",bad),"bad material containers reject without a script crash")
	var bad := config.duplicate(true)
	bad.assets.paper_cream.path = "res://assets/ui/material_v3/unknown.png"
	check(not api.call("config_valid",bad),"unknown material paths fail closed")
	bad = config.duplicate(true)
	bad.assets.notebook.margins = [true,1,1,1]
	check(not api.call("config_valid",bad),"boolean slice margins are not pixel dimensions")
	check(config == original,"materials never mutate caller-owned config or game state")
	panel.free()
	finish()

func finish() -> void:
	print("PANEL MATERIAL: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

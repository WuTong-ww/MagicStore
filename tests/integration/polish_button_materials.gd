extends SceneTree
## RED entry preloads only current, existing production scripts. New drawing
## methods are called only after explicit has_method predicates succeed.
const Palette = preload("res://scripts/ui/palette.gd")
const Style = preload("res://scripts/ui/style_config.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH BUTTON MATERIAL FAIL: "+label)

func _initialize() -> void:
	var config: Dictionary = Style.load_config()
	check(not config.is_empty() and Style.config_valid(config),"current production style is valid before checking button material semantics")
	if config.is_empty():
		finish()
		return
	var theme := Palette.new()
	var wax: StyleBox = theme.get_stylebox("normal","WaxButton")
	var paper: StyleBox = theme.get_stylebox("normal","PaperButton")
	check(config.get("button_materials") is Dictionary,"wax/paper geometry and every new color are presentation data")
	check(wax.has_method("material_plan"),"primary button has an irregular wax seal/ridge plan instead of a flat rounded rectangle")
	check(paper.has_method("material_plan"),"secondary button has a paper-tag hole and cord plan instead of copying Button")
	if not wax.has_method("material_plan") or not paper.has_method("material_plan") or not config.get("button_materials") is Dictionary:
		finish()
		return
	var original := config.duplicate(true)
	for role: String in ["WaxButton","PaperButton"]:
		for state: String in ["normal","hover","pressed","disabled","focus"]:
			var box: StyleBox = theme.get_stylebox(state,role)
			check(box.has_method("material_plan"),"every state keeps the same material identity / "+role+"/"+state)
			if not box.has_method("material_plan"):
				continue
			check(box.get_minimum_size().is_equal_approx(Vector2(config.metrics.horizontal_padding*2,config.metrics.vertical_padding*2)),"decoration does not enlarge old content margins/minimum size / "+role+"/"+state)
			for width: int in [84,124,280]:
				var rect := Rect2(3,5,width,int(config.metrics.minimum_button_height))
				var plan: Dictionary = box.call("material_plan",rect)
				check(not plan.is_empty() and plan.get("text_free") == true,"material drawing cannot bake text, numbers or input state / "+role+"/"+state)
				if plan.is_empty():
					continue
				check(plan.fill_body == (state != "focus"),"focus is only a reusable outline over the active button state")
				var points: PackedVector2Array = plan.outline
				check(points.size() > 4 and Geometry2D.triangulate_polygon(points).size() == (points.size()-2)*3,"material outline is non-rectangular and triangulates safely / "+role)
				check(points.size() > 0 and Array(points).all(func(p: Vector2) -> bool: return p.x >= rect.position.x and p.x <= rect.end.x and p.y >= rect.position.y and p.y <= rect.end.y),"entire material remains within the old control bounds")
				if state != "focus":
					var safe: Rect2 = plan.text_safe_rect
					check([safe.position,Vector2(safe.end.x,safe.position.y),safe.end,Vector2(safe.position.x,safe.end.y)].all(func(p: Vector2) -> bool: return Geometry2D.is_point_in_polygon(p,points)),"existing label content rectangle remains inside the material silhouette")
					if role == "PaperButton":
						check(plan.cord.size() >= 3 and plan.hole_radius > 0 and plan.hole_center.x+plan.hole_radius < plan.text_safe_rect.position.x,"tag string/hole stay in the existing left padding and never overprint text")
					else:
						check(plan.ridge.size() == points.size() and plan.seal.size() > 8 and plan.seal_ridge.size() == plan.seal.size() and plan.cord.is_empty(),"primary wax has a round impressed seal and recessed material ridge rather than a paper string")
						check(Array(plan.seal).all(func(p: Vector2) -> bool: return p.x >= rect.position.x and p.x < plan.text_safe_rect.position.x and p.y >= rect.position.y and p.y <= rect.end.y),"round seal stays in redistributed old padding without covering the dynamic label")
	for bad_value: Variant in [null,{},[],true,7,"materials"]:
		var bad := config.duplicate(true)
		bad.button_materials = bad_value
		check(not Style.config_valid(bad),"invalid material containers fail closed without a drawing crash")
	var bad := config.duplicate(true)
	bad.button_materials.paper.hole_radius = 100
	check(not Style.config_valid(bad),"tag hole cannot consume text padding")
	bad = config.duplicate(true)
	bad.button_materials.wax.outline[0] = [0,2]
	check(not Style.config_valid(bad),"out-of-bounds material points reject")
	check(config == original,"drawing/validation never mutates shared style data")
	finish()

func finish() -> void:
	print("POLISH BUTTON MATERIAL: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

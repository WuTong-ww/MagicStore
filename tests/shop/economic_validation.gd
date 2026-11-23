extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("ECONOMIC VALIDATION FAIL: "+label)
func run() -> void:
	var api: Script = load("res://scripts/shop/shop.gd")
	check(api.has_method("economic_validation_valid"),"the new economic JSON has a production validator")
	if api.has_method("economic_validation_valid"):
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop/economic_validation.json"))
		check(api.call("economic_validation_valid",data),"the actual root-owned thirty-day configuration validates")
		for malformed: Variant in [true,-1,NAN,"104729"]:
			var bad: Dictionary = data.duplicate(true)
			bad.seeds[0] = malformed
			check(not api.call("economic_validation_valid",bad),"invalid deterministic seed is rejected")
		var bad: Dictionary = data.duplicate(true)
		bad.seeds[1] = bad.seeds[0]
		check(not api.call("economic_validation_valid",bad),"duplicate seeds cannot fake multi-seed coverage")
		bad = data.duplicate(true)
		bad.strategies[0].target_recipe_ids = ["invented_recipe"]
		check(not api.call("economic_validation_valid",bad),"a strategy cannot reference an unavailable recipe")
		bad = data.duplicate(true)
		bad.limits.maximum_daily_cash_gain = NAN
		check(not api.call("economic_validation_valid",bad),"nonfinite economic alarm thresholds are rejected")
		bad = data.duplicate(true)
		bad.checkpoint_day = bad.days+1
		check(not api.call("economic_validation_valid",bad),"checkpoint must occur within the actual run")
		bad = data.duplicate(true)
		bad.strategies[0].id = "skip_actions"
		check(not api.call("economic_validation_valid",bad),"unsupported strategy cannot turn real simulation into an empty day counter")
		bad = data.duplicate(true)
		bad.strategies[0].procurement_batch = 0
		check(not api.call("economic_validation_valid",bad),"procurement strategy quantities must be legal positive action quantities")
		bad = data.duplicate(true)
		bad.strategies[0].procurement_batch = 100
		check(not api.call("economic_validation_valid",bad),"a positive procurement quantity outside the real Shop action domain is still invalid")
		bad = data.duplicate(true)
		bad.strategies[0].maximum_services_per_visit = int(data.limits.maximum_actions_per_day)+1
		check(not api.call("economic_validation_valid",bad),"per-visit work cannot exceed the configuration's finite action fence")
	print("ECONOMIC VALIDATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

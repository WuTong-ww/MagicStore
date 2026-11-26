extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")

const ArrivalUI = preload("res://scripts/ui/arrival_ui.gd")
const Shop = preload("res://scripts/shop/shop.gd")
var checks := 0
var failures := 0

func settle() -> void:
	for frame: int in range(8):
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ARRIVAL UI FAIL: " + label)

func check_craft_source_costs(game: Node) -> void:
	var catalog: Dictionary = game.shop_view().catalog
	var base := {"recipe_id":"restorative_draught"}
	var variant := {"recipe_id":"restorative_draught","variant_id":"restorative_draught_mint"}
	var base_probe := craft_probe(game,catalog,base,"arrival_base_cost")
	var variant_probe := craft_probe(game,catalog,variant,"arrival_variant_cost")
	check(base_probe.outcome.get("success",false) and variant_probe.outcome.get("success",false),"both cost sources execute the real base and variant craft rules")
	if not base_probe.outcome.get("success",false) or not variant_probe.outcome.get("success",false):
		return
	check(ArrivalUI.action_minutes("craft_item",base) == int(base_probe.outcome.minutes),"base confirmation cost equals the real successful craft cost")
	check(variant_probe.outcome.result.get("variant_id") == variant.variant_id and variant_probe.outcome.result.get("quality_id") == "fine" and variant_probe.outcome.minutes != base_probe.outcome.minutes,"variant probe actually selects the distinct variant recipe and cost")
	check(ArrivalUI.action_minutes("craft_item",variant) == int(variant_probe.outcome.minutes),"variant confirmation cost equals the real successful variant craft cost")
	var untrusted := variant.duplicate(true)
	untrusted.minutes = 999999
	check(ArrivalUI.action_minutes("craft_item",untrusted) == int(variant_probe.outcome.minutes),"preview takes the selected catalog cost rather than arbitrary action minutes")
	for invalid_variant: Variant in ["clarity_crystal_resin","not_a_recipe_variant",42]:
		var invalid := {"recipe_id":"restorative_draught","variant_id":invalid_variant,"minutes":999999}
		var rejected := craft_probe(game,catalog,invalid,"arrival_invalid_"+str(invalid_variant))
		check(not rejected.outcome.get("success",false) and rejected.outcome.get("error_code") == "INVALID_VARIANT" and rejected.after == rejected.before,"real craft refuses a mismatched, unknown or malformed variant atomically / "+str(invalid_variant))
		check(ArrivalUI.action_minutes("craft_item",invalid) == 0,"invalid variant supplies no fabricated duration before the real action rejects it / "+str(invalid_variant))

func craft_probe(game: Node, catalog: Dictionary, extra: Dictionary, action_id: String) -> Dictionary:
	# Fixture copies exercise the real Shop rule without changing the live save.
	var candidate: Dictionary = game.snapshot().duplicate(true)
	candidate.active_visit_id = ""
	candidate.player.energy = int(catalog.rules.max_energy)
	candidate.shop.recipes.append("restorative_draught")
	for id: String in ["lavender","spring_water","dried_mint","glass_vial"]:
		Shop._add(candidate,id,2,"purchase","arrival_cost_fixture_"+id)
	var before := candidate.duplicate(true)
	var action := extra.duplicate(true)
	action.merge({"type":"craft_item","action_id":action_id},true)
	var debug_catalog := catalog.duplicate(true)
	debug_catalog.debug_one_click = true
	var outcome := Shop.handle(candidate,action,debug_catalog)
	return {"outcome":outcome,"before":before,"after":candidate}

func run() -> void:
	var config := ArrivalUI.load_config()
	check(not config.is_empty(), "arrival copy and thresholds have a validated data contract")
	var invalid := config.duplicate(true)
	invalid.patience_levels[1].minimum_ratio = 2.0
	check(not ArrivalUI.config_valid(invalid), "invalid patience thresholds are rejected")
	var icons := {}
	for ratio: float in [1.0, 0.5, 0.1]:
		var level := ArrivalUI.patience({"patience_ratio": ratio})
		icons[level.icon] = true
		check(not ArrivalUI.patience_text({"patience_ratio": ratio, "patience_minutes": 12}).is_empty(), "patience tier has an accessible text label")
	check(icons.size() == 3, "three distinct hourglass tiers are shown")
	check(ArrivalUI.zero_guest_day({"day": {"natural_count": 0, "arrival_ids": []}, "queue": []}), "zero-customer plan displays dedicated content")
	check(not ArrivalUI.zero_guest_day({"day": {"natural_count": 0, "arrival_ids": ["appointment"]}, "queue": []}), "a planned appointment is not labeled a zero-customer day")
	check(not ArrivalUI.zero_guest_day({"day": {"natural_count": 0, "arrival_ids": [], "arrival_count": 1}, "queue": []}), "a later generated visitor or appointment overrides the original empty plan")
	check(not ArrivalUI.zero_guest_day({}), "legacy plans without daily metadata remain safe")
	check(ArrivalUI.source_text({"source": "burst_word_of_mouth"}).contains("口碑传开"), "burst origin is human-readable")
	check(not ArrivalUI.source_text({"source": "unknown_technical_id"}).contains("unknown_technical_id"), "unknown source identifiers stay hidden")
	var game: Node = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	root.get_node("SaveService").base_dir = "res://.tools/arrival-ui-test-saves/" + game.make_id("run")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for frame: int in range(3):
		await process_frame
	var created: Dictionary = await main.run_action("new_game", {"name": "客流前台验收"})
	check(created.get("success", false), "create isolated UI save")
	var before_cost_checks: Dictionary = game.snapshot()
	check_craft_source_costs(game)
	check(game.snapshot() == before_cost_checks,"craft source-cost probes leave the live saved state unchanged")
	check(main.screen.find_child("ArrivalPatienceList", true, false) != null, "front desk shows a patience row for every queued guest")
	main.show_screen("workshop")
	await settle()
	for kind: String in ["craft_item", "research_recipe", "gather_material"]:
		var before: Dictionary = game.snapshot()
		var extra := {"recipe_id": "calming_incense"} if kind != "gather_material" else {"site_id": "riverside"}
		main.screen.act(kind, extra)
		await settle()
		var dialog := main.screen.find_child("ArrivalActionConfirmation", true, false) as ConfirmationDialog
		check(dialog != null and dialog.visible, "long action asks before spending resources / " + kind)
		if dialog != null:
			var minutes := ArrivalUI.action_minutes(kind, extra)
			check(dialog.dialog_text.contains("将有 %d 位候客可能离开" % game.departure_risk(minutes)), "confirmation shows exact departure risk / " + kind)
			check(game.snapshot() == before, "opening confirmation does not alter game state / " + kind)
			dialog.canceled.emit()
			await settle()
			check(game.snapshot() == before, "cancel leaves clock and save unchanged / " + kind)
	main.open_divination("study")
	await settle()
	var studies: Array = game.divination_study()
	var learning: Dictionary = {}
	for row: Dictionary in studies:
		if not row.learned:
			learning = row
			break
	check(not learning.is_empty(), "learning fixture has an unlearned method")
	if not learning.is_empty():
		var before: Dictionary = game.snapshot()
		main.workbench._run("learn_method", {"method_id": learning.method_id})
		await settle()
		var dialog := main.workbench.find_child("ArrivalActionConfirmation", true, false) as ConfirmationDialog
		check(dialog != null and dialog.visible, "study window uses the same pre-action confirmation")
		if dialog != null:
			dialog.canceled.emit()
			await settle()
		check(game.snapshot() == before, "canceling study preserves saved state")
	main.workbench.hide()
	main.show_screen("gathering")
	await settle()
	var clock_before := int(game.state.clock_minutes)
	main.screen.act("gather_material", {"site_id": "riverside"})
	await settle()
	var gather_dialog := main.screen.find_child("ArrivalActionConfirmation", true, false) as ConfirmationDialog
	if gather_dialog != null:
		gather_dialog.confirmed.emit()
		await settle()
	check(int(game.state.clock_minutes) == clock_before + ArrivalUI.action_minutes("gather_material", {"site_id": "riverside"}), "confirmed gather enters the shared saved action boundary")
	main.people_panel.set_view({"queue": [], "outside_queue": [{"arrival_id": "outside_fixture", "npc_id": "outside_npc", "name": "门外来客", "source": "burst_word_of_mouth", "patience_ratio": 0.5, "patience_minutes": 20}], "appointment_requests": [{"arrival_id": "request_fixture", "npc_id": "request_npc", "name": "预约来客", "source": "burst_group_referral"}]})
	check(main.people_panel.queue.item_count == 2, "outside visitors and appointment requests remain visible")
	main.people_panel._select(0)
	check(main.people_panel.start_button.disabled and not main.people_panel.book_button.disabled and main.people_panel.detail.text.contains("口碑传开"), "outside card preserves source and offers agreement instead of immediate service")
	main.people_panel._select(1)
	check(main.people_panel.start_button.disabled and not main.people_panel.book_button.disabled and main.people_panel.detail.text.contains("尚未约定时间"), "appointment request is explicitly unconfirmed")
	await UITeardown.release_audio(main)
	main.queue_free()
	await process_frame
	print("ARRIVAL UI RESULT: %d checks, %d failures" % [checks, failures])
	await UITeardown.drain(self)
	quit(0 if failures == 0 else 1)

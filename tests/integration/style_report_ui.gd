extends SceneTree
## Authored facts exercise real derive/render. The history probe uses real actions.
## This headless target never certifies graphic quality or authored economy.

const PANEL_PATH := "res://scripts/people/style_report_panel.gd"
const RULES_PATH := "res://scripts/people/style_report.gd"
const FIXTURE_PATH := "res://tests/people/fixtures/style_report_facts.gd"
var checks: int = 0
var failures: int = 0
var finished: bool = false
var panel: Control
var main: Control
var game: Node
var saves: Node
var prior_storage: String = ""
var prior_generation: bool = false
var requests: Array = []

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func() -> void:
		if not finished:
			printerr("STYLE REPORT UI FAIL: bounded target exceeded deadline")
			quit(1)
	)
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		printerr("STYLE REPORT UI FAIL: " + label)
	return value

func settle() -> void:
	await process_frame
	await process_frame

func complete() -> void:
	if is_instance_valid(main):
		await main.prepare_close_async()
		main.queue_free()
	if is_instance_valid(panel):
		panel.queue_free()
	await settle()
	if is_instance_valid(saves) and not prior_storage.is_empty():
		saves.base_dir = prior_storage
	if is_instance_valid(game):
		game.set("_generation_enabled",prior_generation)
	finished = true
	print("STYLE REPORT UI: %d checks, %d failures; authored behavior, real source navigation and virtual-window geometry only; 0 screenshots, no GPU acceptance" % [checks,failures])
	quit(0 if failures == 0 else 1)

func run() -> void:
	# Absence is an intentional semantic RED, never a missing-preload parse error.
	if not check(FileAccess.file_exists(PANEL_PATH),"modern style-report panel exists"):
		await complete()
		return
	var script: GDScript = load(PANEL_PATH) as GDScript
	if not check(script != null and script.can_instantiate(),"production report panel can instantiate"):
		await complete()
		return
	panel = script.new() as Control
	root.add_child(panel)
	if not check(panel.has_method("set_report") and panel.has_method("activate_basis") and panel.has_signal("evidence_requested"),"public report API is available"):
		await complete()
		return
	panel.connect("evidence_requested",func(visit: String,action: String): requests.append([visit,action]))
	var rules_api: GDScript = load(RULES_PATH) as GDScript
	var fixtures: GDScript = load(FIXTURE_PATH) as GDScript
	if not check(rules_api != null and fixtures != null,"shared pure derive and authored facts fixture load"):
		await complete()
		return
	var rules: Dictionary = rules_api.load_rules()
	if not check(rules_api.rules_valid(rules),"real report JSON validates before rendering"):
		await complete()
		return
	var titles: Array = []
	var baseline: Dictionary = {}
	for kind: String in ["inquiry","commerce","balanced"]:
		var facts: Dictionary = fixtures.make_case(kind)
		var report: Dictionary = rules_api.derive(facts,rules)
		if not check(report.get("status") == "ready","authored " + kind + " source rows produce a ready real report"):
			continue
		titles.append(report.title.id)
		var original: Dictionary = report.duplicate(true)
		panel.set_report(report)
		await settle()
		check(report == original,"render never changes derived public input / " + kind)
		check(text_tree(panel).contains(report.title.label) and text_tree(panel).contains(report.title.reason),"title and its explanation are visible / " + kind)
		check(text_tree(panel).contains(report.notice),"fixed non-personality notice is present / " + kind)
		check(not four_letter_type(text_tree(panel)),"no four-letter personality type appears / " + kind)
		for dimension: Dictionary in report.dimensions:
			var block: Node = panel.find_child("StyleDimension_"+dimension.id,true,false)
			if not check(block != null,"real block exists for dimension / " + dimension.id):
				continue
			var words: String = text_tree(block)
			check(words.contains(dimension.label),"dimension label is shown / " + dimension.id)
			if dimension.status == "limited":
				check(words.contains(dimension.limitation.get_slice("；",0)),"limited proxy warning remains in the compact overview / " + dimension.id)
			check(words.contains(report.ui.copy.sample_format % [dimension.sample_count,dimension.eligible_count,dimension.missing_count]),"actual sample/opportunity/missing counts displayed / " + dimension.id)
			var score: String = report.ui.copy.observing if dimension.score == null else report.ui.copy.score_format % int(dimension.score)
			check(words.contains(score),"real score or observing is displayed / " + dimension.id)
			var dimension_button: Button
			for node: Node in all_nodes(block):
				if node is Button and node.get_meta("dimension_id","") == dimension.id:
					dimension_button = node as Button
					break
			if not check(dimension_button != null,"dimension has a real details/criteria control / " + dimension.id):
				continue
			dimension_button.emit_signal("pressed")
			var details: Node = panel.find_child("StyleConclusionDetails",true,false)
			check(details != null and text_tree(details).contains(dimension.limitation),"complete limitation is visible through the real dimension control / " + dimension.id)
			for metric: String in dimension.metrics:
				check(details != null and text_tree(details).contains(report.ui.copy.metrics[dimension.id][metric]),"raw public metric is accessible through the real dimension control / " + dimension.id + "/" + metric)
		for basis_id: String in used_bases(report):
			var before_count: int = requests.size()
			check(panel.activate_basis(basis_id),"every actual conclusion basis can expand / " + basis_id)
			var detail: Node = panel.find_child("StyleEvidenceDetail",true,false)
			var row: Dictionary = report.evidence[basis_id]
			check(detail != null and text_tree(detail).contains(row.label) and text_tree(detail).contains(row.text),"expanded evidence uses only public human text / " + basis_id)
			check(requests.size() == before_count,"expanding evidence alone never navigates")
		if kind == "balanced": baseline = report.duplicate(true)
	check(titles.size() == 3 and titles[0] != titles[1] and titles[1] != titles[2] and titles[0] != titles[2],"three authored source sets retain distinct derived titles")
	if not baseline.is_empty():
		await test_navigation_and_nulls(baseline)
	var empty: Dictionary = rules_api.derive(fixtures.make_case("empty"),rules)
	panel.set_report(empty)
	await settle()
	check(empty.status == "observing" and empty.dimensions.all(func(row: Dictionary) -> bool: return row.score == null) and text_tree(panel).contains(rules.ui.copy.observing),"real empty/unknown coverage renders observing instead of six invented zeroes")
	var invalid_sources: Dictionary = rules_api.derive({},rules)
	panel.set_report(invalid_sources)
	await settle()
	check(invalid_sources.status == "invalid_sources" and panel.visible and text_tree(panel).contains(rules.ui.copy.invalid_sources),"invalid source joins are explicitly explained rather than hiding the modern report")
	await test_people_host(baseline)
	await test_real_history(baseline)
	await complete()

func test_navigation_and_nulls(report: Dictionary) -> void:
	panel.set_report(report)
	await settle()
	var count_before: int = all_nodes(panel).size()
	for iteration: int in range(3): panel.set_report(report)
	await settle()
	check(all_nodes(panel).size() == count_before,"repeated render does not accumulate controls or connections")
	var chosen: String = ""
	for basis_id: String in used_bases(report):
		if not report.evidence[basis_id].visit_id.is_empty() and not report.evidence[basis_id].action_id.is_empty():
			chosen = basis_id
			break
	if check(not chosen.is_empty(),"authored fixture includes linked history evidence"):
		panel.activate_basis(chosen)
		var open: Button = panel.find_child("StyleOpenHistory",true,false) as Button
		if check(open != null and not open.disabled,"linked evidence offers a real history navigation button"):
			var before: int = requests.size()
			open.emit_signal("pressed")
			check(requests.size() == before+1 and requests.back() == [report.evidence[chosen].visit_id,report.evidence[chosen].action_id],"one click emits exactly the public visit/action pair")
			panel.set_report({})
			open.emit_signal("pressed")
			check(requests.size() == before+1,"stale previous-save evidence callback cannot navigate")
	panel.set_report(report)
	await settle()
	var unknown_before: int = requests.size()
	check(not panel.activate_basis("arbitrary_hidden_basis") and requests.size() == unknown_before,"arbitrary evidence IDs are rejected")
	# This authored display-only edge does not claim a real waiting transaction.
	var waiting: Dictionary = report.duplicate(true)
	var waiting_basis: String = used_bases(waiting)[0]
	waiting.evidence[waiting_basis].visit_id = ""
	waiting.evidence[waiting_basis].action_id = ""
	panel.set_report(waiting)
	panel.activate_basis(waiting_basis)
	await settle()
	var open_waiting: Button = panel.find_child("StyleOpenHistory",true,false) as Button
	check((open_waiting == null or open_waiting.disabled or not open_waiting.visible) and requests.size() == unknown_before,"unlinked waiting evidence expands locally without a fabricated visit")
	var partial: Dictionary = report.duplicate(true)
	partial.dimensions[0].score = null
	partial.dimensions[0].status = "observing"
	panel.set_report(partial)
	await settle()
	var first: Node = panel.find_child("StyleDimension_"+partial.dimensions[0].id,true,false)
	check(first != null and text_tree(first).contains(report.ui.copy.observing) and not text_tree(first).contains(report.ui.copy.score_format % 0),"null score is observing rather than invented zero")

func test_people_host(report: Dictionary) -> void:
	var script: GDScript = load("res://scripts/people/people_panel.gd") as GDScript
	var people: Control = script.new() as Control
	root.add_child(people)
	people.set_view({"appearance":{},"queue":[],"profiles":{},"report":{},"style_report":report},"authored-report-save")
	await settle()
	check(people.has_method("open_style_report"),"real PeoplePanel exposes a report-page entry")
	if people.has_method("open_style_report"):
		check(people.open_style_report() and people.find_child("StyleReportPanel",true,false) != null,"modern report is hosted in actual people pages")
	people.queue_free()
	await settle()

func action(kind: String, extra: Dictionary = {}) -> Dictionary:
	var command: Dictionary = {"type":kind,"action_id":game.make_id("g6_ui"),"expected_version":game.player_snapshot().get("state_version",0)}
	command.merge(extra,true)
	var reply: Dictionary = await game.execute_action_async(command)
	check(reply.get("success",false),"real source action / " + kind + " / " + str(reply.get("message","")))
	return reply

func test_real_history(authored_report: Dictionary) -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	prior_storage = saves.base_dir
	prior_generation = game.get("_generation_enabled")
	saves.base_dir = "res://.tools/g6/ui-saves/"+game.make_id("run")
	game.set("_generation_enabled",false)
	if not (await action("new_game",{"name":"报告依据来源验收"})).get("success",false): return
	if not (await action("start_visit",{"npc_id":"npc_lin","case_id":"invitation"})).get("success",false): return
	if not (await action("talk",{"topic_id":"letter","text":"为什么没有收到回信？"})).get("success",false): return
	if not (await action("end_visit")).get("success",false): return
	var committed: Dictionary = game.snapshot()
	var report: Dictionary = game.people_view().get("style_report",{})
	var basis: Dictionary = {}
	for row: Dictionary in report.get("evidence",{}).values():
		if row.get("kind") == "talk" and not str(row.get("visit_id","")).is_empty() and not str(row.get("action_id","")).is_empty():
			basis = row
			break
	if not check(not basis.is_empty(),"observing report retains a real committed talk basis"):
		return
	var main_script: GDScript = load("res://scripts/ui/main.gd") as GDScript
	if not check(main_script != null and main_script.can_instantiate(),"real Main consumer can instantiate"):
		return
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	# Match the real capture's embedded, unscaled viewport environment.
	root.gui_embed_subwindows = true
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = root.size
	main = packed.instantiate() as Control
	root.add_child(main)
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await settle()
	# Main deliberately starts at its exclusive save chooser. Follow its real
	# load entry point, rather than invoking report controls behind that modal.
	var reopened: Dictionary = await main.run_action("load_game",{"save_id":committed.save_id})
	if not check(reopened.get("success",false) and not main.save_window.visible and game.snapshot() == committed,"real Main load entry closes the initial modal without changing the committed source"):
		return
	main.open_people()
	var host: Control = main.people_panel
	if not check(host.has_method("open_style_report") and host.open_style_report(),"real public report page opens in Main"):
		return
	var actual_panel: Control = host.find_child("StyleReportPanel",true,false) as Control
	check(actual_panel != null and actual_panel.activate_basis(basis.id),"real basis expands from the actual PeoplePanel")
	var open: Button = actual_panel.find_child("StyleOpenHistory",true,false) as Button
	if check(open != null,"real source exposes its history action"):
		open.emit_signal("pressed")
		await settle()
		check(main.history_window.visible and main.history_text.text.contains(basis.label) and main.history_text.text.contains(basis.text),"original signal opens the matching visit and places its exact public action evidence first")
	var before_text: String = main.history_text.text
	main.show_history("unknown_private_visit","arbitrary_action")
	check(main.history_text.text == before_text,"unrecognized visit/action cannot replace the authorized history selection")
	check(game.snapshot() == committed,"report rendering, evidence click and history inspection are entirely read-only")
	main.history_window.hide()
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await settle()
		main._fit_window(main.people_window,Vector2i(main.shell_config.dialogs.people[0],main.shell_config.dialogs.people[1]))
		var fitted: Vector2i = main.people_window.size
		var desired := Vector2i(main.shell_config.dialogs.people[0],main.shell_config.dialogs.people[1])
		check(fitted == desired and Vector2(main.size).x >= fitted.x and Vector2(main.size).y >= fitted.y,"real Main fit returns the configured window inside this viewport / "+str(dimensions))
		print("STYLE LAYOUT BEFORE POPUP: Main=%s fit_window=%s root_visible=%s" % [main.size,main.people_window.size,root.get_visible_rect()])
		main.open_people()
		if DisplayServer.get_name() == "headless":
			# The virtual display reports a 1x1 usable popup area, despite the
			# correct parent viewport and Main fit. Check container geometry at
			# that measured fit, never claim a native popup or GPU acceptance.
			print("HEADLESS STYLE WINDOW: popup=%s; restoring measured fit=%s for virtual container geometry only" % [main.people_window.size,fitted])
			main.people_window.size = fitted
		var public: Dictionary = game.people_view().duplicate(true)
		public["style_report"] = authored_report
		host.set_view(public,"authored-bounds-only")
		host.open_style_report()
		await settle()
		var real_report: Control = host.find_child("StyleReportPanel",true,false) as Control
		var bounds := Rect2(Vector2.ZERO,Vector2(main.people_window.size))
		print("STYLE LAYOUT DIAGNOSTIC: requested=%s root=%s scale_size=%s embed=%s Main=%s window_size=%s window_pos=%s host=%s report=%s report_window=%s" % [dimensions,root.size,root.content_scale_size,root.gui_embed_subwindows,main.size,main.people_window.size,main.people_window.position,host.size,real_report.get_global_rect(),real_report.get_window().name])
		for row: Dictionary in authored_report.dimensions:
			var card: Control = real_report.find_child("StyleDimension_"+row.id,true,false) as Control
			print("STYLE LAYOUT CARD: %s actual=%s bounds=%s" % [row.id,card.get_global_rect() if card != null else Rect2(),bounds])
			check(card != null and bounds.encloses(card.get_global_rect()),"all six real cards fit the actual people window / "+str(dimensions)+" / "+row.id)
		var notice: Control = real_report.find_child("StyleReportNotice",true,false) as Control
		print("STYLE LAYOUT NOTICE: actual=%s bounds=%s" % [notice.get_global_rect() if notice != null else Rect2(),bounds])
		check(notice != null and bounds.encloses(notice.get_global_rect()),"required fixed notice fits the real people window / "+str(dimensions))
	check(game.snapshot() == committed,"authored layout probes never overwrite the real committed report sources")

func used_bases(report: Dictionary) -> Array:
	var ids: Array = report.title.basis_ids.duplicate()
	for dimension: Dictionary in report.dimensions:
		for id: String in dimension.basis_ids:
			if id not in ids: ids.append(id)
	return ids

func all_nodes(node: Node) -> Array:
	var result: Array = [node]
	for child: Node in node.get_children(): result.append_array(all_nodes(child))
	return result

func text_tree(node: Node) -> String:
	var words: PackedStringArray = []
	for child: Node in all_nodes(node):
		if child is Label or child is Button or child is RichTextLabel: words.append(str(child.text))
	return "\n".join(words)

func four_letter_type(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("\\b[IE][NS][FT][JP]\\b")
	return pattern.search(value) != null

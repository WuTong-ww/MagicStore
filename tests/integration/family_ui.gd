extends SceneTree
## G2: real committed admissions/statements/effects, then production public UI.
## Runtime fixture settings never overwrite the disabled production registry.
const UITeardown = preload("res://tests/ui_teardown.gd")
const People = preload("res://scripts/people/people.gd")
const EventFixture = preload("res://tests/fixtures/event_case_override.gd")
const CAPTURE_BASE := "res://.tools/g2/ui-captures"
const DIMENSIONS := [Vector2i(1280,720),Vector2i(1920,1080)]
var game: Node
var saves: Node
var main: Control
var checks := 0
var failures := 0
var captures: Array = []
var commands: Array = []
var source_hashes: Dictionary = {}
var original_config: Dictionary = {}
var original_divination: Dictionary = {}
var original_divination_base: Dictionary = {}
var original_save_data: Dictionary = {}
var original_save_dir := ""
var family_id := ""
var family_members: Array = []
var relationship_ids: Array = []
var expected_closeness: Dictionary = {}
var capture_dir := ""
var last_action_id := ""
var completed := false

func _initialize() -> void:
	# A parser/failed command cannot leave an unattended GPU process waiting forever.
	create_timer(90.0).timeout.connect(func():
		if not completed:
			printerr("FAMILY UI FAIL: bounded execution deadline exceeded")
			quit(1)
	)
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAMILY UI FAIL: " + label)
	return ok

func settle() -> void:
	for frame: int in range(12):
		await process_frame

func act(kind: String, values: Dictionary = {}) -> Dictionary:
	last_action_id = game.make_id("family_ui")
	var action := {"type":kind,"action_id":last_action_id,"expected_version":game.state.get("state_version",0)}
	action.merge(values,true)
	var result: Dictionary = await game.execute_action_async(action)
	commands.append({"type":kind,"action_id":action.action_id,"success":result.get("success",false)})
	check(result.get("success",false), "committed " + kind + " / " + str(result.get("message","")))
	return result

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	original_config = game.people_config.duplicate(true)
	original_divination = game._divination.data.duplicate(true)
	original_divination_base = game._divination._base_catalog.duplicate(true)
	original_save_data = saves._divination_data.duplicate(true)
	original_save_dir = saves.base_dir
	for path: String in ["res://data/people/family_library.json","res://data/people/families/family_placeholder.json"]:
		source_hashes[path] = FileAccess.get_sha256(path)
	if not check(original_config.family_library.enabled == false and original_config.family_library.policy.trigger_percent == 0, "production family library remains disabled"):
		await finish()
		return
	configure_isolated_fixture()
	if not check(People.config_valid(game.people_config), "isolated runtime family fixture validates before creating any save"):
		await finish()
		return
	var run_id: String = game.make_id("run")
	capture_dir = CAPTURE_BASE + "/" + run_id
	saves.base_dir = "res://.tools/g2/family-ui-saves/" + run_id
	root.size = DIMENSIONS[0]
	root.content_scale_size = root.size
	# Embed the actual production Window so viewport captures include its contents.
	root.gui_embed_subwindows = true
	# Load after autoload registration, as the production UI uses GameState.
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	if not check(is_instance_valid(main.people_panel) and is_instance_valid(main.people_window) and is_instance_valid(main.save_window), "production Main exposes its real people/archive window"):
		await finish()
		return
	game.configure_api("","","")
	game.set_people_generation_options(false)
	if not (await act("new_game",{"name":"家族公开档案图形验收"})).get("success",false):
		await finish()
		return
	main.save_window.hide()
	if not await obtain_scheduled_graph():
		await finish()
		return
	if not await settle_three_real_g3_effects():
		await finish()
		return
	# Each admission is selected by the real scheduler, on a distinct day. No
	# direct met/revealed/graph assignments or private UI fixture are used here.
	var introduced: Array = []
	for member_index: int in range(3):
		var arrival_id: String = await next_unmet_arrival()
		if arrival_id.is_empty():
			await finish()
			return
		var row: Dictionary = game.state.people.arrivals[arrival_id]
		var npc_id: String = row.npc_id
		var day: int = floori(float(row.at)/1440.0)
		if not check(introduced.all(func(value: Dictionary) -> bool: return value.day != day and value.npc_id != npc_id), "new members arrive on distinct days with permanent distinct identities"):
			await finish()
			return
		if not await move_to(int(row.at)):
			await finish()
			return
		if not (await act("start_arrival",{"arrival_id":arrival_id})).get("success",false):
			await finish()
			return
		var disclosure_action: String = last_action_id
		var visit: Dictionary = game.active_visit()
		var goal: Dictionary = game.state.people.profiles[npc_id].goal
		var reveal: Dictionary = game.state.people.revealed_relationships.get(goal.relationship_id,{})
		if not check(not reveal.is_empty() and reveal.visit_id == visit.visit_id and reveal.source_id == disclosure_action and reveal.get("source_kind") == "family_opening_statement" and reveal.get("kind") == "statement" and reveal.get("statement_index") == 0 and reveal.get("statement_text") == visit.dialogue[0].text, "only a real saved opening customer statement reveals the member's own edge"):
			await finish()
			return
		check(visit.dialogue[0].text.begins_with(goal.question), "authored initial question remains the opening prefix")
		introduced.append({"npc_id":npc_id,"day":day,"visit_id":visit.visit_id,"action_id":disclosure_action,"relationship_id":goal.relationship_id})
		check(count_revealed_family_edges() == member_index+1, "one committed family statement reveals exactly one additional edge")
		if member_index == 0:
			if not await inspect_public_archive("partial",npc_id,1):
				await finish()
				return
		elif member_index == 2:
			if not await inspect_public_archive("complete",npc_id,3):
				await finish()
				return
		if not (await act("end_visit")).get("success",false):
			await finish()
			return
	if not check(introduced.size() == 3 and game.state.people.families[family_id].introduced.size() == 3, "three genuinely received members are persisted"):
		await finish()
		return
	check_final_sources()
	var before_reload: Dictionary = game.snapshot()
	if (await act("load_game",{"save_id":before_reload.save_id})).get("success",false):
		check(game.snapshot() == before_reload, "actual reload retains the graph, statements and three G3 changes")
	check(captures.size() == (0 if DisplayServer.get_name() == "headless" else 4), "headless has no graphical acceptance; GPU produces exactly four real frames")
	await finish()

func configure_isolated_fixture() -> void:
	var config: Dictionary = original_config.duplicate(true)
	config.family_library.enabled = true
	config.family_library.policy.trigger_percent = 100
	config.family_library.policy.special_actual_ratio_cap = 1.0
	config.family_library.policy.special_return_percent = 0
	config.family_library.templates[0].enabled = true
	config.family_library.templates[0].reference_note = "G2_PRIVATE_NOTE_ONLY"
	config.arrival.family_percent = 0
	config.arrival.ordinary_return_percent = 0
	config.arrival.special_return_percent = 0
	config.arrival.queue_capacity = 100
	config.arrival.max_total_per_day = 100
	config.arrival.burst.probability = 0.0
	config.arrival.expectation.min = 12
	config.arrival.expectation.max = 12
	for personality: Dictionary in config.personalities:
		personality.return_bias = 0
	config.ordinary_content.personalities = config.personalities.duplicate(true)
	game.people_config = config

func obtain_scheduled_graph() -> bool:
	var template_id: String = game.people_config.family_library.templates[0].template_id
	for attempt: int in range(8):
		for family: Dictionary in game.state.people.families.values():
			if family.template_id == template_id:
				family_id = family.family_id
				family_members = family.members.duplicate()
				relationship_ids = family.relationship_ids.duplicate()
				return check(family_members.size() == 3 and relationship_ids.size() == 3 and family.introduced.is_empty(), "actual new-game/day scheduler instantiated one complete unseen three-person graph")
		if not (await act("next_day")).get("success",false):
			return false
	return check(false, "bounded scheduled fixture could not trigger its enabled placeholder")

func settle_three_real_g3_effects() -> bool:
	var effects: Array = []
	var deltas := [2,-3,4]
	for index: int in range(relationship_ids.size()):
		var id: String = relationship_ids[index]
		effects.append({"kind":"npc_relationship","rel_id":id,"delta":deltas[index]})
		expected_closeness[id] = int(game.state.people.relationships[id].closeness)+deltas[index]
	# A data-only event-rule fixture, identical to the transaction target: the
	# outcome remains resolved by Events.advance and saved via real wait actions.
	var definition: Dictionary = EventFixture.install(game,"g3_family_ui_fixture")
	definition.outcomes.waited.effects = effects
	EventFixture.sync(game,saves)
	if not (await act("start_visit")).get("success",false):
		return false
	var visit: Dictionary = game.active_visit()
	EventFixture.bind(game,"g3_family_ui_fixture",visit.visit_id)
	var due: int = int(game.state.divination.cases[visit.visit_id].event.due_at)
	if not await move_to(due):
		return false
	for id: String in relationship_ids:
		var edge: Dictionary = game.state.people.relationships[id]
		if not check(int(edge.closeness) == expected_closeness[id] and edge.changes.size() == 1 and edge.changes[0].get("effect_id") in game.state.people.effect_ids, "a genuine resolved G3 outcome changed each declared edge exactly once"):
			return false
	if not check(count_revealed_family_edges() == 0 and family_members.all(func(id: String) -> bool: return not game.people_view().profiles.has(id)), "settling hidden effects discloses neither the family graph nor unseen profiles"):
		return false
	return (await act("end_visit")).get("success",false)

func move_to(target: int) -> bool:
	for attempt: int in range(32):
		var remaining: int = target-int(game.state.clock_minutes)
		if remaining <= 0:
			return check(remaining == 0, "bounded waits reach the actual scheduled clock exactly")
		if not (await act("wait",{"minutes":mini(180,remaining)})).get("success",false):
			return false
	return check(false, "bounded waits could not reach the requested event/arrival time")

func next_unmet_arrival() -> String:
	for day_attempt: int in range(8):
		var candidates: Array = game.state.people.arrivals.values().filter(func(row: Dictionary) -> bool:
			return row.npc_id in family_members and not game.state.people.profiles[row.npc_id].met and row.state == "planned" and row.source == "family_first" and int(row.at) >= int(game.state.clock_minutes)
		)
		candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.at < b.at if a.at != b.at else a.arrival_id < b.arrival_id)
		if not candidates.is_empty():
			return candidates[0].arrival_id
		if not (await act("next_day")).get("success",false):
			return ""
	check(false, "bounded real daily scheduling did not provide an unmet member")
	return ""

func count_revealed_family_edges() -> int:
	var count := 0
	for id: String in relationship_ids:
		count += int(game.state.people.revealed_relationships.has(id))
	return count

func inspect_public_archive(stage: String, npc_id: String, expected_reveals: int) -> bool:
	var stable: Dictionary = game.snapshot()
	var public: Dictionary = game.people_view()
	if not check(not has_private_key(public), "public projection excludes all private author/source/graph fields"):
		return false
	if not check(count_revealed_family_edges() == expected_reveals and public.profiles.has(npc_id), "archive phase reflects committed disclosure state"):
		return false
	for id: String in family_members:
		check(public.profiles.has(id) == game.state.people.profiles[id].met, "unmet family members never appear as public archive profiles")
	var visible_ids: Array = []
	for relation: Dictionary in public.profiles[npc_id].get("relationships",[]):
		visible_ids.append(relation.relationship_id)
		if not check(game.state.people.revealed_relationships.has(relation.relationship_id), "each rendered relationship has a real disclosure source"):
			return false
	for id: String in relationship_ids:
		if not game.state.people.revealed_relationships.has(id):
			check(id not in visible_ids, "unrevealed family edges stay absent from the public archive")
	for dimensions: Vector2i in DIMENSIONS:
		root.size = dimensions
		root.content_scale_size = dimensions
		main.show_screen("front")
		main.open_people()
		await settle()
		var panel: Control = main.people_panel
		var index := -1
		for option: int in range(panel.archive.item_count):
			if panel.archive.get_item_metadata(option) == npc_id:
				index = option
		if not check(index > 0, "real PeoplePanel has the permitted member in its archive picker"):
			return false
		panel.archive.select(index)
		panel.archive.item_selected.emit(index)
		await settle()
		check(panel.view == public and main.people_window.visible, "production PeoplePanel consumes only GameState.people_view")
		check(panel.detail.text.contains(public.profiles[npc_id].name), "archive selection displays the rewritten name")
		for relation: Dictionary in public.profiles[npc_id].get("relationships",[]):
			check(panel.detail.text.contains(str(relation.kind)+"："+str(relation.other_name)), "visible archive names its genuinely disclosed relation")
			if DisplayServer.get_name() != "headless":
				var text: String = str(relation.kind)+"："+str(relation.other_name)
				var character: int = panel.detail.text.find(text)+text.length()-1
				var line: int = panel.detail.get_character_line(character)
				var top: float = panel.detail.get_line_offset(line)-panel.detail.get_v_scroll_bar().value
				var height: float = panel.detail.get_theme_font("normal_font").get_height(panel.detail.get_theme_font_size("normal_font_size"))
				check(top >= 0 and top+height <= panel.detail.size.y, "disclosed relation is readable in the initial archive viewport, not only stored offscreen")
		var shown_text: String = visible_text(panel)
		for token: String in ["G2_PRIVATE_NOTE_ONLY","source_work","reference_work","reference_character","reference_note","npc_","rel_","goal_","family_"]:
			check(not shown_text.contains(token), "private source and technical identifiers are absent from visible text / "+token)
		if DisplayServer.get_name() != "headless":
			check(panel.detail.size.x > 0 and panel.detail.size.y > 0 and panel.archive_portrait.is_visible_in_tree(), "real selected archive content and portrait have visible layout")
			if panel.detail.size.x <= 0 or panel.detail.size.y <= 0 or not panel.archive_portrait.is_visible_in_tree():
				print("FAMILY UI LAYOUT: "+JSON.stringify({"detail_size":[panel.detail.size.x,panel.detail.size.y],"portrait_visible":panel.archive_portrait.visible,"portrait_in_tree":panel.archive_portrait.is_visible_in_tree(),"panel_visible":panel.is_visible_in_tree(),"window_visible":main.people_window.visible,"window_size":[main.people_window.size.x,main.people_window.size.y]}))
			check(main.people_window.size.x <= dimensions.x and main.people_window.size.y <= dimensions.y, "people window fits the actual target viewport")
		else:
			# The headless DisplayServer clamps subwindows to 1x1. Keep public
			# consumer checks, and require the unchanged layout assertions on GPU.
			check(panel.archive_portrait.visible, "headless public selection enables its authorized portrait")
			print("SKIP FAMILY UI native-window geometry: headless 1x1 subwindow; actual GPU layout required.")
		if stage == "partial":
			for id: String in family_members:
				if not game.state.people.profiles[id].met and not public.profiles[npc_id].get("relationships",[]).any(func(relation: Dictionary) -> bool: return relation.other_npc_id == id):
					check(not panel.detail.text.contains(str(game.state.people.profiles[id].name)), "undisclosed third member is absent from selected details")
		if failures > 0:
			return false
		await capture(stage,dimensions,npc_id,visible_ids.size())
		main.people_window.hide()
		check(game.snapshot() == stable, "resizing, archive selection and screenshots do not mutate the committed save")
	return failures == 0

func has_private_key(value: Variant) -> bool:
	if value is Dictionary:
		for key: Variant in value:
			if key in ["source_work","reference_work","reference_character","reference_note","template_snapshot","member_ids","edge_ids","goal_ids","families","generated_bundle"] or has_private_key(value[key]):
				return true
	elif value is Array:
		for row: Variant in value:
			if has_private_key(row):
				return true
	return false

func visible_text(node: Node) -> String:
	var text := ""
	if node is Control and not node.is_visible_in_tree():
		return text
	if node is Label or node is RichTextLabel or node is Button:
		text += str(node.text)+"\n"
	if node is ItemList:
		for index: int in range(node.item_count):
			text += node.get_item_text(index)+"\n"
	for child: Node in node.get_children():
		text += visible_text(child)
	return text

func capture(stage: String, dimensions: Vector2i, npc_id: String, visible_relations: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	if not check(image.get_size() == dimensions, "captured framebuffer has its exact target dimensions"):
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var path: String = capture_dir+"/family-"+stage+"-"+str(dimensions.x)+".png"
	if check(image.save_png(path) == OK, "save real GPU family archive screenshot"):
		captures.append({"path":path,"sha256":FileAccess.get_sha256(path),"dimensions":[dimensions.x,dimensions.y],"stage":stage,"selected_npc_id":npc_id,"visible_relationships":visible_relations})

func check_final_sources() -> void:
	check(count_revealed_family_edges() == 3, "all three declared edges have genuine saved opening sources")
	for id: String in relationship_ids:
		var edge: Dictionary = game.state.people.relationships[id]
		check(int(edge.closeness) == expected_closeness[id] and edge.changes.size() == 1, "three G3 relation changes remain exactly once after all receptions")
	for path: String in source_hashes:
		check(FileAccess.get_sha256(path) == source_hashes[path], "production disabled registry and original placeholder bytes remain unchanged")

func finish() -> void:
	if is_instance_valid(game) and not original_config.is_empty():
		game.people_config = original_config
		game._divination.data = original_divination
		game._divination._base_catalog = original_divination_base
		saves._divination_data = original_save_data
		saves.base_dir = original_save_dir
	if is_instance_valid(main):
		check(await UITeardown.release_audio(main), "production audio/motion resources are released before closing the GUI fixture")
		main.queue_free()
		await settle()
	await UITeardown.drain(self)
	if not capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_dir)
		var file := FileAccess.open(capture_dir+"/receipt.json",FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"renderer":DisplayServer.get_name(),"checks":checks,"failures":failures,"captures":captures,"commands":commands,"save_id":game.state.get("save_id",""),"family_id":family_id,"source_hashes":source_hashes,"headless_graphics_skipped":DisplayServer.get_name() == "headless"},"\t")+"\n")
			file.close()
	completed = true
	print("FAMILY UI: %d checks, %d failures, %d GPU captures; renderer=%s" % [checks,failures,captures.size(),DisplayServer.get_name()])
	quit(1 if failures else 0)

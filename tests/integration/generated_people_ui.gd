extends SceneTree
const CardChoice = preload("res://scripts/ui/card_choice.gd")
const UITeardown = preload("res://tests/ui_teardown.gd")
## Real UI actions with authored isolated fixtures; never calls an upstream API.
const Person = preload("res://scripts/people/generated_person.gd")
const Cases = preload("res://scripts/divination/generated_cases.gd")
var game: Node
var main: Control
var checks := 0
var failures := 0
var generated: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("GENERATED UI FAIL: " + message)

func settle() -> void:
	for frame in range(8):
		await process_frame

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	game.set_people_generation_options(false)
	root.get_node("SaveService").base_dir = "res://.tools/test-generated-ui/" + game.make_id("run")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"新来客界面检查"})).success,"create isolated UI save")
	for suffix: String in ["first","second"]:
		var id := "ui_generated_" + suffix
		var candidate: Dictionary = game.snapshot()
		var added: Dictionary = Person.apply(candidate.people,game.people_config,id,Person.offline_bundle(id),Person.offline_provenance(id),int(candidate.clock_minutes))
		check(added.success,"install authored new-person fixture " + suffix)
		if added.success:
			check(game._commit(candidate,{"type":"admit_generated_person","action_id":"ui_admit_"+suffix},"准备好了。",added).success,"save UI fixture through real commit")
			generated.append(added)
	game._sync_generated_catalog()
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		main.show_screen("front")
		main.open_network_settings()
		await settle()
		var settings := find_node(main,func(node: Node) -> bool: return node is ConfirmationDialog and node.title == "设置") as ConfirmationDialog
		check(settings != null and settings.size.y <= dimensions.y and settings.size.x <= dimensions.x,"settings fit " + str(dimensions) + "; actual=" + (str(settings.size) if settings != null else "missing"))
		if settings != null:
			var toggle := settings.find_child("BackgroundPeople",true,false) as CheckButton
			var parallel := settings.find_child("PeopleConcurrency",true,false) as SpinBox
			check(toggle == null and parallel == null,"background policy is absent from game settings")
			check(not JSON.stringify(game.people_view()).contains("generated_bundle"),"public status never contains a draft")
			await capture("settings-"+str(dimensions.x))
			settings.canceled.emit()
			await settle()
	for fixture: Dictionary in generated:
		root.size = Vector2i(1280,720) if generated.find(fixture) == 0 else Vector2i(1920,1080)
		root.content_scale_size = root.size
		check((await main.run_action("start_arrival",{"arrival_id":fixture.arrival_id})).success,"actual reception opens new person")
		await settle()
		var view: Dictionary = game.divination_view()
		check(view.case_id == Cases.case_id(fixture.npc_id),"UI uses this person's own case")
		check(main.screen.title.text.contains(view.guest.name),"new character name is visible")
		var choices: Array = game.conversation_questions()
		check(choices.size() <= 3 and main.screen.questions.get_child_count() == choices.size(),"current visitor exposes up to three available next questions")
		for index in range(choices.size()):
			check(main.screen.questions.get_child(index).get_meta("topic_id","") == choices[index].topic_id,"same-sized topic lists rebind to current visitor")
		var topic := Cases.topic_id(fixture.npc_id,"concern")
		check((await main.run_action("talk",{"text":"你最放不下什么？","topic_id":topic})).success,"new topic button action reaches current case")
		check((await main.run_action("talk",{"text":"能说说这位熟人吗？","topic_id":Cases.topic_id(fixture.npc_id,"relationship")})).success,"relationship disclosure reaches its own source")
		await settle()
		check(not main.screen.transcript.get_parsed_text().contains(game.state.people.profiles[fixture.npc_id].generated_bundle.case.hidden_fact),"rendered transcript does not reveal unearned secret")
		check(main.screen.return_button.visible,"generated visitor exposes return agreement after talking")
		check(main.screen.contact_button.visible,"a disclosed relationship exposes the introduction agreement")
		check(main.screen.get_combined_minimum_size().y <= main.scene_holder.size.y+1,"new relationship and return choices fit the consultation: min="+str(main.screen.get_combined_minimum_size())+" area="+str(main.scene_holder.size))
		await capture("consultation-"+str(root.size.x))
		var before: Dictionary = game.snapshot()
		main.confirm_return_visit()
		await settle()
		var confirm := find_node(main,func(node: Node) -> bool: return node is ConfirmationDialog and node.ok_button_text == "对方同意，记下来") as ConfirmationDialog
		check(confirm != null and confirm.visible,"return agreement opens before ending visit")
		if confirm != null:
			confirm.canceled.emit()
			await settle()
		check(game.snapshot() == before,"cancel return agreement preserves state")
		main.open_people()
		await settle()
		check(game.people_view().profiles[fixture.npc_id].background == game.state.people.profiles[fixture.npc_id].background,"approved biography is visible after meeting")
		var archive: CardChoice = main.people_panel.archive
		for index in range(archive.item_count):
			if archive.get_item_metadata(index) == fixture.npc_id:
				archive.select(index)
				archive.item_selected.emit(index)
		check(main.people_panel.detail.text.contains(game.state.people.profiles[fixture.npc_id].background),"known-person archive opens the actual approved biography")
		check(main.people_panel.start_button.disabled and main.people_panel.book_button.disabled,"viewing history cannot accidentally receive another queued person")
		await capture("person-"+str(generated.find(fixture)))
		main.people_window.hide()
		check((await main.run_action("end_visit")).success,"end isolated reception")
	print("GENERATED PEOPLE UI: %d checks, %d failures; renderer=%s" % [checks,failures,DisplayServer.get_name()])
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func find_node(node: Node, predicate: Callable) -> Node:
	if predicate.call(node):
		return node
	for child: Node in node.get_children():
		var found := find_node(child,predicate)
		if found != null:
			return found
	return null

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await create_timer(0.2).timeout
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("res://.tools/generated-people-ui")
	check(root.get_texture().get_image().save_png("res://.tools/generated-people-ui/"+name+".png") == OK,"save rendered UI capture")

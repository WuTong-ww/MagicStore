extends SceneTree
## No preload of the future CardChoice: baseline is a functional UI contract RED.
var checks := 0
var failures := 0
var selected_events: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH CARDS FAIL: "+label)

func run() -> void:
	var game: Node = root.get_node("GameState")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.get_node("SaveService").base_dir = "res://.tools/r3-polish/card-saves/"+game.make_id("run")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var result: Dictionary = await main.run_action("new_game",{"name":"纸卡选择验收"})
	check(result.get("success",false),"new game is created by the real saved action")
	check((await main.run_action("read_morning_letters")).get("success",false),"read the real morning letters")
	check((await main.run_action("next_customer")).get("success",false),"enter an actual visit before inspecting its history cards")
	main.open_divination("casebook")
	await process_frame
	await process_frame
	var history: Node = main.workbench.find_child("CaseHistoryPicker",true,false)
	check(history != null and not history is OptionButton,"the real history selector displays cards instead of a dropdown")
	var path := "res://scripts/ui/card_choice.gd"
	check(ResourceLoader.exists(path),"the independently testable card-choice implementation exists")
	if ResourceLoader.exists(path):
		var script: Script = load(path)
		var choice: Control = script.new()
		root.add_child(choice)
		choice.item_selected.connect(func(index: int): selected_events.append(index))
		choice.add_item("先听来客说")
		choice.add_item("再核对材料")
		choice.set_item_metadata(1,{"action":{"id":"private_metadata_only"}})
		choice.select(1)
		check(choice.item_count == 2 and choice.selected == 1 and selected_events.is_empty(),"programmatic refresh preserves selection without sending an action")
		var copy: Dictionary = choice.get_item_metadata(1)
		copy.action.id = "changed"
		check(choice.get_item_metadata(1).action.id == "private_metadata_only","metadata is copied and never displayed as a label")
		check(choice.get_item_text(1) == "再核对材料","cards display only the public label")
		var buttons: Array[Node] = choice.find_children("ChoiceCard_*","Button",true,false)
		check(buttons.size() == 2,"each choice has an actual focusable Button")
		if buttons.size() == 2:
			choice.disabled = true
			buttons[0].pressed.emit()
			check(buttons[0].disabled and selected_events.is_empty() and choice.selected == 1,"global busy lock suppresses user selection")
			choice.disabled = false
			choice.set_item_disabled(0,true)
			buttons[0].pressed.emit()
			check(selected_events.is_empty(),"disabled placeholder cannot select or submit")
			choice.set_item_disabled(0,false)
			buttons[0].pressed.emit()
			check(choice.selected == 0 and selected_events == [0],"one user button activation emits the same single index")
		choice.clear()
		check(choice.item_count == 0 and choice.selected == -1,"clear removes all cards and stale selection")
		choice.queue_free()
	check(await main.prepare_close_async(),"real Main presentation shuts down")
	main.queue_free()
	await process_frame
	await process_frame
	print("POLISH CARDS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

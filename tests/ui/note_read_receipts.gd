extends SceneTree
const Teardown = preload("res://tests/ui_teardown.gd")
var checks := 0
var failures := 0
var main: Control
var game: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("R4 NOTE RECEIPT FAIL: "+message)
func settle() -> void:
	for frame: int in range(16): await process_frame
	while main.busy: await process_frame
func run() -> void:
	game = root.get_node("GameState")
	var saves := root.get_node("SaveService")
	saves.base_dir = "res://.tools/r4-note-receipts/"+game.make_id("run")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280,720)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	check((await main.run_action("new_game",{"name":"笔记已读回执验收"})).get("success",false),"create isolated current save")
	var before: Dictionary = game.snapshot()
	var note: Dictionary = game.story_view().notes[0]
	check(note.unlocked and not note.read,"collected first page starts unread")
	saves.fail_next_write = true
	check(main.open_story_notes(),"open the real notebook")
	await settle()
	var reader: Control = main.people_panel.story_notes
	check(not saves.fail_next_write and game.snapshot() == before,"failed read save is consumed once and leaves the complete state unchanged")
	check(reader.page_buttons.get_child(0).get_node("NoteUnreadDot").visible and not game.story_view().notes[0].read,"failed read save retains unread red dot")
	reader.page_buttons.get_child(0).pressed.emit()
	await settle()
	var committed: Dictionary = game.snapshot()
	var receipt := "r4_note_"+str(before.save_id)+"_"+str(note.id)
	check(committed.processed_actions.has(receipt) and game.story_view().notes[0].read,"explicit page retry records a committed read receipt")
	check(not reader.page_buttons.get_child(0).get_node("NoteUnreadDot").visible,"only saved read clears the red dot")
	check(committed.schema_version == before.schema_version and committed.story == before.story and committed.player == before.player and committed.clock_minutes == before.clock_minutes,"read bookkeeping preserves schema, story, resources and clock")
	check(committed.state_version == before.state_version+1 and committed.processed_actions.size() == before.processed_actions.size()+1,"one successful retry commits exactly one action")
	check(saves.read_save(before.save_id).get("state",{}) == committed,"disk contains the committed read receipt")
	check((await main.run_action("load_game",{"save_id":before.save_id})).get("success",false) and game.story_view().notes[0].read,"read status survives a real reload")
	var replay: Dictionary = await main.run_action("set_free_question",{"enabled":game.free_question_enabled()},receipt)
	check(replay.get("replayed",false) and game.snapshot() == committed,"same action ID cannot write or settle reading twice")
	print("R4 NOTE RECEIPTS: %d checks, %d failures"%[checks,failures])
	await Teardown.release_audio(main)
	main.queue_free()
	await process_frame
	await Teardown.drain(self)
	quit(1 if failures else 0)

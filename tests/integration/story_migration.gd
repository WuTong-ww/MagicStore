extends SceneTree
## This byte-exact fixture was saved by the real CASE11 UI capture, not synthesized.
const FIXTURE := "res://tests/fixtures/schema11_case_active.json"
const FIXTURE_SHA := "67943ade5c2c3bde15ab370ee127a191754b353ce6dd4df04421f064500348a2"
const FIXTURE_BYTES := 38768
const FIXTURE_ID := "save_f321096919344a75c28fd769c7b58aea"
var game: Node
var saves: Node
var checks := 0
var failures := 0
var changes := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("STORY MIGRATION FAIL: "+label)
func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	saves.base_dir = "res://.tools/story-migration/"+game.make_id("run")
	game.state_changed.connect(func():changes+=1)
	check(FileAccess.file_exists(FIXTURE) and FileAccess.get_sha256(FIXTURE)==FIXTURE_SHA,"genuine CASE11 source bytes retain their recorded SHA256")
	var fixture_file := FileAccess.open(FIXTURE,FileAccess.READ)
	check(fixture_file!=null and fixture_file.get_length()==FIXTURE_BYTES,"fixture keeps the original 38768-byte envelope")
	if fixture_file!=null:
		fixture_file.close()
	if failures:
		finish()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))
	var path: String = saves._path(FIXTURE_ID)
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE),ProjectSettings.globalize_path(path))==OK,"copy original envelope into an isolated save directory")
	var original: Dictionary = saves.read_save(FIXTURE_ID)
	check(original.success,"current validator reads the genuine schema11 source")
	if not original.success:
		finish()
		return
	var old: Dictionary = original.state
	var old_board: Dictionary = old.divination.cases[old.active_visit_id].board
	check(old.schema_version==11 and not old.has("story") and old_board.phase=="cards" and old_board.definition_id=="fixed_invitation","fixture is an actual schema11 active invitation at the cards phase")
	var sha := FileAccess.get_sha256(path)
	var loaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":FIXTURE_ID})
	check(loaded.success,"load genuine CASE11 into the current game")
	if not loaded.success:
		finish()
		return
	var migrated: Dictionary = game.snapshot()
	check(migrated.schema_version==saves.CURRENT_SCHEMA and migrated.schema_version==12,"migration reaches schema12 in memory")
	for key: String in old:
		if key!="schema_version":
			check(migrated.has(key) and migrated[key]==old[key],"migration preserves the entire historical payload field / "+key)
	var historical: Dictionary = migrated.duplicate(true)
	historical.erase("story")
	historical.schema_version = old.schema_version
	check(historical==old,"removing only story and the schema bump recovers the complete original payload")
	check(migrated.keys().size()==old.keys().size()+1,"migration adds only the story namespace")
	check(migrated.story.completions.is_empty() and migrated.story.notes.size()==1,"active old board does not invent a completion or extra notebook pages")
	var notes: Array = game.story_view().notes.filter(func(row:Dictionary)->bool:return row.unlocked)
	check(notes.size()==1 and notes[0].page_number==1,"only the actual opening notebook page is public after migration")
	check(migrated.people==old.people and migrated.npcs==old.npcs,"loading injects no story identity, profile or wallet")
	var board: Dictionary = migrated.divination.cases[old.active_visit_id].board
	check(board==old_board and board.hash==old_board.hash and board.card_order==old_board.card_order,"active board definition hash, order and every saved field remain exact")
	check(game.case_board_view().enabled and game.case_board_view().phase=="cards","old active board continues on the same public cards phase")
	check(FileAccess.get_sha256(path)==sha and sha==FIXTURE_SHA and saves.read_save(FIXTURE_ID).state==old,"load writes neither original file bytes nor the durable schema11 payload")
	var available: Array = game.case_board_view().cards.filter(func(row:Dictionary)->bool:return not row.revealed and row.enabled)
	check(not available.is_empty(),"genuine migrated board has a normal legal first action")
	if available.is_empty():
		finish()
		return
	var command := {"type":"case_flip_card","action_id":"story_migration_first_saved_card","card_index":available[0].index}
	var public_before: Dictionary = game.case_board_view()
	var story_before: Dictionary = game.story_view()
	var count := changes
	saves.fail_next_write = true
	var failed: Dictionary = await game.execute_action_async(command)
	check(not failed.success and failed.error_code=="SAVE_WRITE_FAILED","first post-migration action really reaches the failing save boundary")
	check(game.snapshot()==migrated and game.case_board_view()==public_before and game.story_view()==story_before and changes==count,"failed first action publishes no migrated-card or story change")
	check(FileAccess.get_sha256(path)==sha and saves.read_save(FIXTURE_ID).state==old,"failed first action still leaves exact original schema11 bytes")
	var retried: Dictionary = await game.execute_action_async(command)
	check(retried.success,"same action ID retries the first post-migration save")
	var committed: Dictionary = game.snapshot()
	check(saves.read_save(FIXTURE_ID).success and saves.read_save(FIXTURE_ID).state==committed and committed.schema_version==12,"only the successful retry durably writes schema12")
	check(committed.divination.cases[old.active_visit_id].board.card_order==old_board.card_order and committed.divination.cases[old.active_visit_id].board.hash==old_board.hash,"first successful action retains the original saved card order and definition")
	check(committed.processed_actions.has(command.action_id) and changes==count+1,"first action is recorded and published once")
	var published := changes
	var replayed: Dictionary = await game.execute_action_async(command)
	check(replayed.success and replayed.get("replayed",false) and game.snapshot()==committed and changes==published,"first-action replay cannot redraw, advance or publish again")
	var reloaded: Dictionary = await game.execute_action_async({"type":"load_game","save_id":FIXTURE_ID})
	check(reloaded.success and game.snapshot()==committed,"actual schema12 disk reload retains the exact committed migration")
	check(FileAccess.get_sha256(FIXTURE)==FIXTURE_SHA,"checked-in genuine source fixture is never modified")
	finish()
func finish() -> void:
	print("STORY MIGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

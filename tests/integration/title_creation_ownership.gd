extends SceneTree
var checks := 0
var failures := 0
var changes := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TITLE CREATION OWNERSHIP FAIL: "+label)

func changed() -> void:
	changes += 1

func run() -> void:
	var game: Node = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	game.state_changed.connect(changed)
	var run_id: String = game.make_id("run")
	for kind: String in ["hidden","case_alias"]:
		if kind=="hidden" and not OS.has_feature("windows"):
			print("TITLE CREATION OWNERSHIP SKIP: Windows hidden-attribute fixture")
			continue
		saves.base_dir = "res://.tools/r3-title/ownership-edges/"+run_id+"/"+kind
		check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(saves.base_dir))==OK,"make isolated ownership fixture directory")
		var action_id: String = "title_temp_owner_"+kind
		var save_id: String = saves.new_game_save_id(action_id)
		var primary: String = saves._path(save_id)
		var temporary: String = primary+".tmp" if kind=="hidden" else primary.get_base_dir().path_join(primary.get_file().to_upper()+".TMP")
		check(not FileAccess.file_exists(primary) and not FileAccess.file_exists(temporary),"fixture starts without a primary or previous test artifact")
		var output: FileAccess = FileAccess.open(temporary,FileAccess.WRITE)
		check(output!=null,"create only this test's pre-existing unknown artifact")
		if output==null:
			continue
		output.store_string("pre-existing unknown content; not owned by a future new_game call")
		output.close()
		if kind=="hidden":
			check(FileAccess.set_hidden_attribute(temporary,true)==OK and FileAccess.get_hidden_attribute(temporary),"fixture has the actual Windows hidden attribute")
		var before_hash: String = FileAccess.get_sha256(temporary)
		var directory: DirAccess = DirAccess.open(saves.base_dir)
		directory.include_hidden = true
		check(directory.get_files().has(temporary.get_file()),"test observation explicitly includes hidden files")
		var before: Dictionary = game.snapshot()
		var published: int = changes
		saves.fail_next_write = true
		var inspected: Dictionary = saves.inspect_new_game(action_id)
		check(not inspected.get("success",false) or not inspected.get("empty",true),"read-only gate recognizes unknown occupied target / "+kind)
		var reply: Dictionary = await game.execute_action_async({"type":"new_game","action_id":action_id,"name":"ownership fixture"})
		check(not reply.success and reply.error_code!="SAVE_WRITE_FAILED" and saves.fail_next_write,"occupied target is rejected before attempting a write / "+kind)
		check(FileAccess.file_exists(temporary) and FileAccess.get_sha256(temporary)==before_hash,"pre-existing unknown bytes survive the failed creation / "+kind)
		check(not FileAccess.file_exists(primary) and game.snapshot()==before and changes==published,"no primary, loaded state or visible signal is created / "+kind)
		check(not str(reply.get("message","")).contains("NEW_GAME_"),"ownership rejection does not display an internal marker")
		saves.fail_next_write = false
		if kind=="hidden" and FileAccess.file_exists(temporary):
			FileAccess.set_hidden_attribute(temporary,false)
	print("TITLE CREATION OWNERSHIP: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

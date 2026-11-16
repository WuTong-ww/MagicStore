extends SceneTree
## Destructive operations are restricted to this run's .tools test directory.

var game: Node
var saves: Node
var checks := 0
var failures := 0
var test_root := ""
var save_folder := ""

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = root.get_node("GameState")
	saves = root.get_node("SaveService")
	if not saves.has_method("delete_save"):
		check(false, "SaveService provides delete_save")
		_finish()
		return
	test_root = ProjectSettings.globalize_path("res://.tools/test-save-delete/" + game.make_id("run"))
	save_folder = test_root.path_join("saves")
	check(DirAccess.make_dir_recursive_absolute(save_folder) == OK, "create isolated deletion test directory")
	saves.base_dir = save_folder
	check(act("new_game", {"name":"稍后删除的店铺"}).success, "create first real save")
	var first: String = game.state.save_id
	check(act("wait", {"minutes":1}).success and act("wait", {"minutes":1}).success, "generate actual primary, backup and guard")
	check(FileAccess.file_exists(_path(first) + ".bak") and FileAccess.file_exists(_path(first) + ".bak.guard"), "actual backups exist before deletion")
	check(act("new_game", {"name":"保留的店铺"}).success, "create another real current save")
	var second: String = game.state.save_id
	var protected_files := {
		_path(first + "_neighbor"):"prefix neighbor save must survive",
		_path(first) + ".notes":"unrelated extension must survive",
		_path(second) + ".corrupt.protected":"another save's damaged original must survive",
		test_root.path_join("outside.json"):"outside base_dir must survive"
	}
	for path: String in protected_files:
		_write_fixture(path, protected_files[path])
	var sidecars: Array[String] = [".tmp", ".restore.tmp", ".bak.tmp", ".bak.guard.tmp", ".rollback.tmp", ".corrupt.123", ".corrupt.456"]
	for suffix: String in sidecars:
		_write_fixture(_path(first) + suffix, "isolated artifact " + suffix)
	var snapshot: Dictionary = game.snapshot()
	var before_second := FileAccess.get_file_as_bytes(_path(second))
	var deleted: Dictionary = act("delete_game", {"save_id":first})
	check(deleted.success, "delete a noncurrent save")
	check(game.snapshot() == snapshot, "deleting another save preserves current in-memory state exactly")
	check(FileAccess.get_file_as_bytes(_path(second)) == before_second, "deleting another save leaves current file bytes unchanged")
	for suffix: String in ["", ".bak", ".bak.guard"] + sidecars:
		check(not FileAccess.file_exists(_path(first) + suffix), "deleted save artifact removed: " + ("primary" if suffix.is_empty() else suffix))
	for path: String in protected_files:
		check(FileAccess.get_file_as_string(path) == protected_files[path], "preserve exact unrelated file: " + path.get_file())
	check(not saves.list_saves().any(func(row: Dictionary) -> bool: return row.save_id == first), "deleted slot is absent from the save list")
	var after_delete := _folder_snapshot()
	var repeated: Dictionary = act("delete_game", {"save_id":first})
	check(repeated.success or repeated.get("error_code") == "SAVE_MISSING", "repeated deletion is harmless or reports missing")
	check(game.snapshot() == snapshot and _folder_snapshot() == after_delete, "repeated deletion cannot remove another slot")
	for invalid_id: String in ["", "..", "../outside", "..\\outside", second + "/../outside", second + ".json", "C:\\Windows", "*", second + "*"]:
		var before_invalid := _folder_snapshot()
		var rejected: Dictionary = saves.delete_save(invalid_id)
		check(not rejected.success, "invalid save ID is rejected: " + invalid_id)
		check(before_invalid == _folder_snapshot() and FileAccess.get_file_as_string(test_root.path_join("outside.json")) == protected_files[test_root.path_join("outside.json")], "invalid ID leaves all isolated and outside files unchanged")
	check(not act("delete_game", {"save_id":42}).success and game.snapshot() == snapshot, "core rejects non-text deletion ID without changing state")
	# A valid backup-only slot must be deletable even if the primary was lost.
	var orphan: String = game.make_id("save_orphan")
	_write_fixture(_path(orphan) + ".bak", "orphan backup fixture")
	_write_fixture(_path(orphan) + ".corrupt.fixture", "orphan corrupt fixture")
	check(saves.delete_save(orphan).success and not FileAccess.file_exists(_path(orphan) + ".bak") and not FileAccess.file_exists(_path(orphan) + ".corrupt.fixture"), "backup-only and damaged slots can be deleted without parsing their payload")
	var before_failure := _folder_snapshot()
	saves.fail_next_delete = true
	var failure: Dictionary = act("delete_game", {"save_id":second})
	check(not failure.success, "injected deletion failure is reported")
	check(game.snapshot() == snapshot and _folder_snapshot() == before_failure, "failed deletion preserves current state and every file byte")
	check(act("delete_game", {"save_id":second}).success, "delete current save after failure can be retried")
	check(game.snapshot().is_empty() and game.active_visit().is_empty(), "deleting current save clears loaded state and active reception")
	check(not FileAccess.file_exists(_path(second)) and not FileAccess.file_exists(_path(second) + ".corrupt.protected"), "current primary and only its damaged sidecar are removed")
	check(FileAccess.file_exists(_path(first + "_neighbor")), "neighbor prefix still survives both deletions")
	check(FileAccess.get_file_as_string(test_root.path_join("outside.json")) == "outside base_dir must survive", "parent directory sentinel survives all deletion paths")
	_finish()

func act(kind: String, fields: Dictionary = {}) -> Dictionary:
	var action := {"type":kind,"action_id":game.make_id("delete_test"),"expected_version":game.state.get("state_version", 0)}
	action.merge(fields, true)
	return game.execute_action(action)

func _path(save_id: String) -> String:
	return save_folder.path_join(save_id + ".json")

func _write_fixture(path: String, value: String) -> void:
	# This guard also protects test setup from ever touching real saves.
	if not path.begins_with(test_root + "/") and not path.begins_with(test_root + "\\"):
		check(false, "fixture remains under the resolved .tools test root")
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "create fixture: " + path.get_file())
		return
	file.store_string(value)
	file.close()

func _folder_snapshot() -> Dictionary:
	var result: Dictionary = {}
	var directory := DirAccess.open(save_folder)
	if directory != null:
		for filename: String in directory.get_files():
			result[filename] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(save_folder.path_join(filename)))
	return result

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DELETE SAVE FAIL: " + label)

func _finish() -> void:
	print("DELETE SAVE: %d checks, %d failures; isolated files: %s" % [checks, failures, test_root])
	quit(1 if failures else 0)

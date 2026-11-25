extends "res://scripts/save/save_service.gd"
## UNRUN stage-failure double. Inherits real validation and write_new_game;
## no permissive validator or production seam. Only isolated test paths.
var failure_stage := ""

func write_save(snapshot: Dictionary) -> Dictionary:
	if failure_stage.is_empty():
		return super.write_save(snapshot)
	var checked := validate_snapshot(snapshot)
	if not checked.success:
		return checked
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))!=OK:
		return _failure("SAVE_WRITE_FAILED",new_game_rules().copy.write_failed_prefix)
	var temporary := _path(snapshot.save_id)+".tmp"
	if failure_stage=="validated":
		var staged := _write_checked(temporary,snapshot)
		if not staged.success:
			return staged
	else:
		var partial := FileAccess.open(temporary,FileAccess.WRITE)
		if partial==null:
			return _failure("SAVE_WRITE_FAILED",new_game_rules().copy.write_failed_prefix)
		partial.store_string("incomplete isolated test stage")
		partial.close()
	failure_stage = ""
	return _failure("SAVE_WRITE_FAILED",new_game_rules().copy.write_failed_prefix)

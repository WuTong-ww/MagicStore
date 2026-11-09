extends SceneTree
## Invoked in two distinct OS processes, proving disk persistence across exit.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var gs: Node = root.get_node("GameState")
	var saves: Node = root.get_node("SaveService")
	saves.base_dir = "user://test-restart"
	var marker := "user://test-restart/expected.json"
	var mode := OS.get_cmdline_user_args()
	if mode.has("write"):
		for command in [{"type": "new_game", "name": "进程重启验证"}, {"type": "start_visit"}, {"type": "talk", "text": "邀请上写了什么？"}, {"type": "reading"}]:
			command["action_id"] = gs.make_id("restart")
			if not gs.execute_action(command).success:
				push_error("RESTART write failed")
				quit(1)
				return
		var file := FileAccess.open(marker, FileAccess.WRITE)
		file.store_string(JSON.stringify(gs.snapshot()))
		file.close()
		print("RESTART WRITE PASS: committed paid unfinished visit")
	else:
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(marker))
		var result: Dictionary = gs.execute_action({"type": "load_game", "save_id": expected.save_id})
		if not result.success or JSON.parse_string(JSON.stringify(gs.snapshot())) != expected:
			push_error("RESTART read differs from committed state")
			quit(1)
			return
		var prior: Dictionary = gs.snapshot()
		result = gs.execute_action({"type": "reading", "action_id": gs.make_id("retry")})
		if not result.success or gs.snapshot() != prior:
			push_error("RESTART duplicate charged or redrew")
			quit(1)
			return
		print("RESTART READ PASS: identical resources/card/dialogue/visit; repeat free")
	quit(0)

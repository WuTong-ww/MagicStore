extends SceneTree
const UITeardown = preload("res://tests/ui_teardown.gd")
## Exercises delete confirmation against isolated saves only. Player saves are never opened.

const CAPTURE_DIR := "res://.tools/c-ui-captures"
var game: Node
var saves: Node
var main: Control
var checks := 0
var failures := 0
var captures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("DELETE UI FAIL: " + label)

func settle() -> void:
	for frame in range(12):
		await process_frame

func run() -> void:
	game = root.get_node("GameState")
	# This fixture retains the pre-loop reception and transaction contract.
	game.daily_loop_config.enabled = false
	saves = root.get_node("SaveService")
	saves.base_dir = "res://.tools/c-delete-ui-test-saves/" + game.make_id("run")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	var a: Dictionary = await main.run_action("new_game", {"name": "待删除的临时店铺"})
	check(a.get("success", false), "create first isolated store")
	var first_id: String = a.result.save_id
	await main.run_action("wait", {"minutes": 1})
	var first_path: String = saves._path(first_id)
	check(FileAccess.file_exists(first_path) and FileAccess.file_exists(first_path + ".bak"), "first test save has primary and backup")
	var b: Dictionary = await main.run_action("new_game", {"name": "继续经营的临时店铺"})
	check(b.get("success", false), "create second isolated store")
	var second_id: String = b.result.save_id
	await main.run_action("wait", {"minutes": 1})
	var second_path: String = saves._path(second_id)
	var unchanged: Dictionary = game.snapshot()
	var first_hash := FileAccess.get_sha256(first_path)
	var second_hash := FileAccess.get_sha256(second_path)
	for dimensions: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		main.open_saves()
		await settle()
		if DisplayServer.get_name() != "headless":
			check(main.save_window.size.x <= dimensions.x and main.save_window.size.y <= dimensions.y, "save picker fits target resolution")
			for caption: String in ["继续所选存档", "从备份恢复…", "刷新", "删除所选存档…"]:
				var button := find_control(main.save_window, func(node: Node) -> bool: return node is Button and node.text == caption) as Button
				check(button != null and Rect2(Vector2.ZERO,Vector2(main.save_window.size)).encloses(button.get_global_rect()), "save action row fits picker / " + caption)
		check(select_save(first_id), "select noncurrent save by stable ID")
		var dialog := await request_delete()
		if dialog == null:
			continue
		check(dialog.dialog_text.contains("待删除的临时店铺"), "confirmation identifies selected store by name")
		check(dialog.dialog_text.contains("备份") and dialog.dialog_text.contains("删除"), "confirmation explains primary and backup removal")
		check(dialog.dialog_text.contains("不可") or dialog.dialog_text.contains("无法恢复"), "confirmation explains irreversible result")
		check(dialog.get_ok_button().text.contains("删除") and dialog.get_cancel_button().text == "取消", "destructive and cancel buttons are explicit")
		if DisplayServer.get_name() != "headless":
			check(dialog.size.x <= dimensions.x and dialog.size.y <= dimensions.y, "delete confirmation fits window")
		await capture("save-delete-confirm-" + str(dimensions.x))
		dialog.get_cancel_button().pressed.emit()
		await settle()
		check(not dialog.visible and game.snapshot() == unchanged, "cancel closes confirmation without changing active game")
		check(FileAccess.get_sha256(first_path) == first_hash and FileAccess.get_sha256(second_path) == second_hash, "cancel preserves both stores byte-for-byte")
	check(select_save(first_id), "reselect first store for confirmed deletion")
	var first_dialog := await request_delete()
	if first_dialog != null:
		check(select_save(second_id), "underlying selection can change without changing confirmed deletion target")
		first_dialog.get_ok_button().pressed.emit()
		await settle()
		check(not FileAccess.file_exists(first_path) and not FileAccess.file_exists(first_path + ".bak"), "confirmed deletion removes selected primary and backup")
		check(not saves.list_saves().any(func(row: Dictionary) -> bool: return row.save_id == first_id), "deleted noncurrent store disappears from save list")
		check(game.snapshot() == unchanged and FileAccess.get_sha256(second_path) == second_hash, "deleting another store preserves active store and disk contents")
	main.open_saves()
	await settle()
	check(select_save(second_id), "select active store")
	var second_dialog := await request_delete()
	if second_dialog != null:
		second_dialog.get_ok_button().pressed.emit()
		await settle()
		check(game.snapshot().is_empty(), "deleting active store clears in-memory state")
		check(not FileAccess.file_exists(second_path) and not FileAccess.file_exists(second_path + ".bak"), "active primary and backup removed")
		check(main.save_window.visible and main.save_entries.is_empty(), "no-save picker remains available")
		check(main.resources.text.contains("尚未") or main.resources.text.contains("打开存档"), "status clearly shows no current store")
		var delete_button := find_delete_button()
		check(delete_button != null and delete_button.disabled, "delete button disables when list is empty")
		await capture("save-delete-empty-1920")
	var fresh: Dictionary = await main.run_action("new_game", {"name": "删除之后的新店铺"})
	check(fresh.get("success", false) and not game.snapshot().is_empty() and not main.save_window.visible, "new store can be created immediately after deletion")
	print("SAVE DELETE UI: %d checks, %d failures, %d graphical captures" % [checks,failures,captures])
	await UITeardown.release_audio(main)
	main.queue_free()
	await settle()
	await UITeardown.drain(self)
	quit(1 if failures else 0)

func select_save(save_id: String) -> bool:
	for index in range(main.save_entries.size()):
		if main.save_entries[index].save_id == save_id:
			main.save_list.select(index)
			main.save_list.item_selected.emit(index)
			return true
	return false

func find_delete_button() -> Button:
	return find_control(main.save_window, func(node: Node) -> bool: return node is Button and node.is_visible_in_tree() and node.text.contains("删除")) as Button

func request_delete() -> ConfirmationDialog:
	var button := find_delete_button()
	check(button != null and not button.disabled, "selected store exposes deletion control")
	if button == null or button.disabled:
		return null
	button.pressed.emit()
	await settle()
	var dialog := find_control(main.save_window, func(node: Node) -> bool: return node is ConfirmationDialog and node.title == "删除存档") as ConfirmationDialog
	check(dialog != null and dialog.visible, "delete requires explicit confirmation")
	return dialog

func find_control(scope: Node, matches: Callable) -> Node:
	if matches.call(scope):
		return scope
	for child: Node in scope.get_children():
		var found := find_control(child,matches)
		if found != null:
			return found
	return null

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await create_timer(0.25).timeout
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var picture: Image = root.get_texture().get_image()
	check(picture.save_png(CAPTURE_DIR + "/" + label + ".png") == OK,"save deletion screenshot")
	captures += 1

extends SceneTree
# Missing future page module is an ordinary feature assertion, never a preload error.
const UI = preload("res://scripts/ui/ui_kit.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("NOTEBOOK PAGES FAIL: "+label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var window := Window.new()
	window.visible = false
	root.add_child(window)
	UI.paper_window(window)
	var background := window.get_node_or_null("PaperWindowBackground")
	check(background != null and background.get_meta("material_role","") == "dialogue","default paper window is a single letter material instead of an opaque nested frame")
	check(window.get_theme_stylebox("embedded_border","Window") is StyleBoxEmpty and window.get_theme_stylebox("embedded_unfocused_border","Window") is StyleBoxEmpty,"focused and unfocused embedded borders do not draw another gold frame")
	var path := "res://scripts/ui/notebook_pages.gd"
	check(ResourceLoader.exists(path),"production provides two independently scrolling notebook pages")
	if not ResourceLoader.exists(path):
		window.queue_free()
		finish()
		return
	var script: GDScript = load(path)
	var pages: Control = script.new()
	root.add_child(pages)
	pages.size = Vector2(940,480)
	await process_frame
	await process_frame
	var left: VBoxContainer = pages.get("left")
	var right: VBoxContainer = pages.get("right")
	var left_scroll: ScrollContainer = pages.get("left_scroll")
	var right_scroll: ScrollContainer = pages.get("right_scroll")
	check(left != null and right != null and left != right and left.get_parent() == left_scroll and right.get_parent() == right_scroll,"left and right content remain separate VBox roots with their own scroll viewports")
	check(left_scroll.position == Vector2(18,18) and left_scroll.size == Vector2(420,444) and right_scroll.position == Vector2(502,18) and right_scroll.size == Vector2(420,444),"940px book preserves both complete content viewports and a non-content spine gap")
	for box: VBoxContainer in [left,right]:
		var tall := Control.new()
		tall.custom_minimum_size.y = 1500
		box.add_child(tall)
	await process_frame
	await process_frame
	left_scroll.scroll_vertical = 120
	check(left_scroll.scroll_vertical > 0 and right_scroll.scroll_vertical == 0,"scrolling left never moves the right page")
	var before := pages.get_child_count()
	pages.size = Vector2(1000,550)
	await process_frame
	check(pages.get_child_count() == before and left_scroll.get_child_count() == 1 and right_scroll.get_child_count() == 1,"resize lays out existing page roots rather than rebuilding content")
	check(left_scroll.position.x+left_scroll.size.x < right_scroll.position.x and right_scroll.position.x+right_scroll.size.x <= pages.size.x,"resize retains a real excluded spine and complete right content viewport")
	pages.queue_free()
	window.queue_free()
	finish()
func finish() -> void:
	print("NOTEBOOK PAGES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

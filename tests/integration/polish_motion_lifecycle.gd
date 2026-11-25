extends SceneTree
## A hidden/unlaid-out viewport must not be inverted to initialize paper hover.
const UI = preload("res://scripts/ui/ui_kit.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH MOTION LIFECYCLE FAIL: "+label)
func run() -> void:
	var game: Node = root.get_node("GameState")
	var before: Dictionary = game.snapshot()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(100,100)
	viewport.global_canvas_transform = Transform2D(Vector2.ZERO,Vector2.ZERO,Vector2.ZERO)
	root.add_child(viewport)
	var button: Button = UI.button("初始化",func(): pass)
	viewport.add_child(button)
	await process_frame
	await process_frame
	check(button.get_meta("material_ready",false),"material binding completes even before a visible invertible viewport exists")
	check(button.position.is_equal_approx(Vector2.ZERO),"idle material does not move the layout while its viewport is singular")
	check(game.snapshot() == before,"material initialization changes no world state")
	viewport.queue_free()
	await process_frame
	print("POLISH MOTION LIFECYCLE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

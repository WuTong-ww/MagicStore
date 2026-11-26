extends Control
const UI = preload("res://scripts/ui/ui_kit.gd")
var room_art: Control
var board: Control
var host: Node

func setup(owner_host: Node) -> void:
	host = owner_host
	room_art = preload("res://scripts/shop/scene_visual.gd").new()
	add_child(room_art)
	room_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_art.setup("consultation")
	var dimmer := ColorRect.new()
	dimmer.color = preload("res://scripts/ui/panel_materials.gd").backdrop_color()
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dimmer); dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board = preload("res://scripts/ui/case_board.gd").new()
	board.name = "PracticeCaseBoard"
	board.host = owner_host
	board.public_view_getter = func() -> Dictionary: return GameState.learning_view().get("practice",{})
	board.command_submitter = Callable(owner_host,"submit_practice_operation")
	add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var copy: Dictionary = GameState.learning_view().get("copy",{})
	var close_button := UI.button(str(copy.get("close","")),func(): owner_host.close_practice())
	close_button.name = "ClosePracticeRoom"
	close_button.z_index = 1000
	add_child(close_button)
	close_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	var layout: Dictionary = GameState.learning_view().get("config",{}).get("layout",{})
	close_button.offset_left = -float(layout.cell_width)-float(layout.padding)
	close_button.offset_right = -float(layout.padding)
	close_button.offset_top = float(layout.padding)
	close_button.offset_bottom = float(layout.padding)+float(layout.row_height)
	board.refresh()

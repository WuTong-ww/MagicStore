extends PanelContainer
var board: Control
var slot_id := ""

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return is_instance_valid(board) and board.can_drop_material(slot_id,data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO,data):
		board.attach_material(slot_id,str(data.evidence_id))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		board.activate_slot(slot_id)
		accept_event()

extends Button
var item_id := ""

func _get_drag_data(_position: Vector2) -> Variant:
	if disabled: return null
	var preview := preload("res://scripts/ui/ui_kit.gd").label(text,20)
	set_drag_preview(preview)
	return {"kind":"craft_material","item_id":item_id}

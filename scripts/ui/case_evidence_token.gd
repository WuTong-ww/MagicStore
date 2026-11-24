extends Button
var evidence_id := ""
var drag_label := ""

func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled or evidence_id.is_empty():
		return null
	var preview := Label.new()
	preview.text = drag_label
	preview.modulate = modulate
	set_drag_preview(preview)
	return {"kind":"case_evidence","evidence_id":evidence_id}

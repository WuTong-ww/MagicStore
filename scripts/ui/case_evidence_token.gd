extends Button
var evidence_id := ""
var drag_label := ""
var drag_preview_factory: Callable

func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled or evidence_id.is_empty():
		return null
	var supplied: Variant = drag_preview_factory.call() if drag_preview_factory.is_valid() else null
	var preview: Control = supplied if supplied is Control else Label.new()
	if preview is Label: preview.text = drag_label
	preview.modulate = modulate
	set_drag_preview(preview)
	return {"kind":"case_evidence","evidence_id":evidence_id}

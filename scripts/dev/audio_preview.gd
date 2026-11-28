extends Control
## Standalone F6 audition; it never dispatches a game action or edits a save.
const Audio = preload("res://scripts/audio/shop_audio.gd")
const Catalog = preload("res://scripts/audio/ui_sound_catalog.gd")
var audio: Node
var caption: Label

func _ready() -> void:
	get_tree().auto_accept_quit = false
	audio = Audio.new()
	add_child(audio)
	var data: Dictionary = audio.config
	if data.is_empty() or not Catalog.valid(data):
		push_error("试听配置不可用。")
		return
	var background := ColorRect.new()
	background.color = Color("f3e9d6")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]: margins.add_theme_constant_override("margin_"+side,20)
	add_child(margins)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	margins.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",14)
	scroll.add_child(body)
	var font: Font = load("res://assets/fonts/LXGWWenKai-Regular.ttf")
	var theme_data := Theme.new()
	theme_data.default_font = font
	theme_data.default_font_size = 18
	theme_data.set_color("font_color","Label",Color("3b2a1e"))
	body.theme = theme_data
	label(body,data.ui_policy.preview_title,26)
	label(body,data.ui_policy.preview_notice)
	caption = label(body,"")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation",14)
	grid.add_theme_constant_override("v_separation",14)
	body.add_child(grid)
	for column: String in data.ui_policy.preview_columns: label(grid,column,22)
	for key: String in Catalog.KEYS:
		label(grid,str(data.ui_policy.labels[key]),22)
		for path: String in Catalog.candidates(data,key):
			var cell := VBoxContainer.new()
			cell.custom_minimum_size.x = 270
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(cell)
			var record: Dictionary = data.sound_catalog[path]
			var button := Button.new()
			button.text = record.label
			button.set_meta("preview_path",path)
			button.custom_minimum_size.y = 48
			button.pressed.connect(func():
				if audio.play_preview(path): caption.text = str(data.ui_policy.labels[key])+" · "+str(record.label))
			cell.add_child(button)
			var metrics: Dictionary = record.metrics
			var text: String = str(data.ui_policy.preview_metrics).format({"duration":snappedf(metrics.duration_ms,0.1),"centroid":roundi(metrics.centroid_hz),"onset":snappedf(metrics.onset_peak_ratio,0.01),"loudness":snappedf(metrics.lufs_short_40ms,0.1)})
			var detail := label(cell,text,16)
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			detail.custom_minimum_size.x = 270

func label(parent: Node, text: String, size: int = 18) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	parent.add_child(node)
	return node

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(audio):
		if await audio.shutdown_async(): get_tree().quit()

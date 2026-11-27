extends Control
const UI = preload("res://scripts/ui/ui_kit.gd")
const Metrics = preload("res://scripts/ui/viewport_metrics.gd")
const Layout = preload("res://scripts/ui/responsive_layout.gd")
const Art = preload("res://scripts/ui/case_card_art.gd")
var board: Control
var row: Dictionary
var image: TextureRect
var face: PanelContainer
var description: RichTextLabel

func _ready() -> void:
	name = "CaseCardZoom"
	z_index = int(board.config.card_view.zoom_z)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(board.config.colors.zoom_backdrop)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face = UI.panel("paper")
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face)
	image = TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = Art.texture(str(row.get("deck_id","")),board.card_art_index)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(image)
	if image.texture == null:
		var label := UI.label(str(row.get("mark",""))+"\n"+str(row.get("name",board.config.card_view.fallback)),int(board.config.layout.title_font))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		face.add_child(label)
		image.hide()
	description = UI.rich()
	description.fit_content = false
	description.scroll_active = true
	description.mouse_filter = Control.MOUSE_FILTER_PASS
	description.add_theme_font_size_override("normal_font_size",int(board.config.flow.font_size))
	description.text = str(row.get("name",board.config.card_view.fallback))+" · "+str(board.config.card_view.get(row.get("face","upright"),board.config.card_view.upright))+"\n"+str(row.get("text",""))+"\n"+str(board.config.card_view.close)
	add_child(description)
	get_tree().root.size_changed.connect(layout)
	layout()

func layout() -> void:
	if not is_inside_tree(): return
	var metrics := Metrics.measure(board)
	if not Metrics.valid(metrics): return
	var client: Vector2 = metrics.visible_css
	Layout.apply(self,Layout.fit_minimum(client,Rect2(Vector2.ZERO,client),metrics))
	var height: float = client.y*float(board.config.card_view.zoom_height_ratio)
	var width: float = height*float(board.config.card_view.ratio)
	var gap: float = board.config.flow.gap
	face.position = Vector2((client.x-width)*0.5,gap)
	face.size = Vector2(width,height)
	description.position = Vector2(gap,height+gap*2)
	description.size = Vector2(client.x-gap*2,maxf(1,client.y-height-gap*3))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()

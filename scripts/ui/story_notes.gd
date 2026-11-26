extends VBoxContainer
## Pure public-view reader. It has no GameState, save, clock or action access.
const UI = preload("res://scripts/ui/ui_kit.gd")
const StoryUI = preload("res://scripts/ui/story_ui_config.gd")
signal close_requested
var config: Dictionary = {}
var page_buttons: HBoxContainer
var page_title: Label
var progress_label: Label
var body: RichTextLabel
var ending_label: RichTextLabel
var close_button: Button
var _rows: Array[Dictionary] = []
var _selected_id := ""
var _identity := ""
var _enabled := false
var _ending: Dictionary = {}

func _ready() -> void:
	config = StoryUI.load_config()
	if config.is_empty():
		hide()
		return
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",int(config.layout.gap))
	add_child(UI.label(config.copy.heading,int(config.layout.heading_font)))
	progress_label = UI.label("",int(config.layout.small_font),UI.MUTED)
	add_child(progress_label)
	page_buttons = HBoxContainer.new()
	page_buttons.name = "StoryNotePages"
	page_buttons.add_theme_constant_override("separation",int(config.layout.gap))
	add_child(page_buttons)
	page_title = UI.label("",int(config.layout.body_font))
	page_title.name = "StoryNoteTitle"
	add_child(page_title)
	body = UI.rich()
	body.name = "StoryNoteBody"
	body.bbcode_enabled = false
	body.scroll_following = false
	body.custom_minimum_size.y = float(config.layout.body_minimum_height)
	body.add_theme_font_size_override("normal_font_size",int(config.layout.body_font))
	add_child(body)
	ending_label = UI.rich()
	ending_label.name = "StoryEndingPublicText"
	ending_label.bbcode_enabled = false
	ending_label.scroll_following = false
	ending_label.fit_content = true
	ending_label.custom_minimum_size.y = float(config.layout.ending_minimum_height)
	ending_label.size_flags_vertical = Control.SIZE_FILL
	ending_label.add_theme_font_size_override("normal_font_size",int(config.layout.small_font))
	add_child(ending_label)
	close_button = UI.button(config.copy.close,func(): close_requested.emit())
	close_button.name = "CloseStoryNotes"
	close_button.custom_minimum_size.y = float(config.layout.button_height)
	add_child(close_button)
	_refresh()

var _manage_visibility := true

func available() -> bool:
	return _enabled and not config.is_empty()

func set_view(value: Dictionary, identity: String = "", manage_visibility: bool = true) -> void:
	_manage_visibility = manage_visibility
	if identity != _identity:
		_identity = identity
		_selected_id = ""
		if is_instance_valid(body):
			body.text = ""
		if is_instance_valid(ending_label):
			ending_label.text = ""
	_enabled = bool(value.get("enabled",false))
	_rows.clear()
	var rows: Variant = value.get("notes",[])
	if rows is Array:
		for supplied: Variant in rows:
			if not supplied is Dictionary or not supplied.get("id") is String or not (supplied.get("page_number") is int or supplied.get("page_number") is float):
				continue
			var page := float(supplied.page_number)
			if not is_finite(page) or page <= 0 or page != floor(page):
				continue
			var row := {"id":str(supplied.id),"page_number":int(page),"unlocked":bool(supplied.get("unlocked",false))}
			# Locked text is never kept in this component, even if incorrectly supplied.
			if row.unlocked:
				if supplied.get("title") is String: row["title"] = str(supplied.title)
				if supplied.get("text") is String: row["text"] = str(supplied.text)
			_rows.append(row)
	_rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.page_number)<int(b.page_number))
	_ending = value.get("ending",{}).duplicate(true) if value.get("ending") is Dictionary else {}
	if is_node_ready():
		_refresh()

func select_page(id: String) -> void:
	_selected_id = id
	if is_node_ready():
		_render_page()

func _refresh() -> void:
	if not is_instance_valid(body):
		return
	if _manage_visibility: visible = available()
	for child: Node in page_buttons.get_children():
		page_buttons.remove_child(child)
		child.queue_free()
	if not available():
		body.text = ""
		page_title.text = ""
		ending_label.text = ""
		ending_label.hide()
		return
	for row: Dictionary in _rows:
		var button := UI.button(str(config.copy.page_number).format({"number":int(row.page_number)}),select_page.bind(str(row.id)))
		button.name = "StoryNotePage_"+str(row.page_number)
		button.custom_minimum_size = Vector2(config.layout.page_number_minimum_width,config.layout.button_height)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not row.unlocked
		button.tooltip_text = "" if row.unlocked else str(config.copy.locked)
		page_buttons.add_child(button)
	progress_label.text = str(config.copy.progress).format({"count":_rows.filter(func(row: Dictionary) -> bool: return row.unlocked).size(),"total":int(config.note_count)})
	ending_label.visible = bool(_ending.get("has_ending",false)) and _ending.get("text") is String and not str(_ending.text).is_empty()
	ending_label.text = str(_ending.get("text","")) if ending_label.visible else ""
	if ending_label.visible and _ending.get("status") == "complete" and _ending.get("title") is String and not str(_ending.title).is_empty():
		ending_label.text = str(_ending.title)+str(config.copy.line_separator)+ending_label.text
	if not _rows.any(func(row: Dictionary) -> bool: return row.id == _selected_id):
		var open: Array = _rows.filter(func(row: Dictionary) -> bool: return row.unlocked)
		_selected_id = str(open[0].id) if not open.is_empty() else (str(_rows[0].id) if not _rows.is_empty() else "")
	_render_page()

func _render_page() -> void:
	var found: Array = _rows.filter(func(row: Dictionary) -> bool: return row.id == _selected_id)
	if found.is_empty():
		page_title.text = ""
		body.text = str(config.copy.empty)
		return
	var row: Dictionary = found[0]
	var generic := str(config.copy.page_number).format({"number":int(row.page_number)})
	page_title.text = str(row.get("title",generic)) if row.unlocked else generic
	body.text = str(row.get("text",config.copy.empty)) if row.unlocked else str(config.copy.locked)
	body.scroll_to_line(0)

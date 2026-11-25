extends Control
## Content viewport only: one outer notebook material is owned by the caller.
## Independent page scroll state survives resize; no world, action or RNG access.
const Materials = preload("res://scripts/ui/panel_materials.gd")
const Style = preload("res://scripts/ui/style_config.gd")

var left: VBoxContainer
var right: VBoxContainer
var left_scroll: ScrollContainer
var right_scroll: ScrollContainer

static func minimum_book_size() -> Vector2:
	var config := Materials.load_config()
	if config.is_empty(): return Vector2.ZERO
	return Vector2(config.layout.book_minimum_size[0],config.layout.book_minimum_size[1])

static func preferred_book_size() -> Vector2:
	var config := Materials.load_config()
	if config.is_empty(): return Vector2.ZERO
	return Vector2(config.layout.book_preferred_width,config.layout.book_preferred_height).max(minimum_book_size())

func _init() -> void:
	name = "NotebookPages"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = minimum_book_size()
	left_scroll = _make_page("LeftPageRoot")
	right_scroll = _make_page("RightPageRoot")
	left = _make_content(left_scroll,"LeftPageContent")
	right = _make_content(right_scroll,"RightPageContent")

func _make_page(page_name: String) -> ScrollContainer:
	var page := ScrollContainer.new()
	page.name = page_name
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page.follow_focus = true
	page.clip_contents = true
	page.set_meta("material_page_root",true)
	Materials.apply_panel(page,"plain")
	add_child(page)
	return page

func _make_content(page: ScrollContainer, content_name: String) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.name = content_name
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := Style.load_config()
	if not style.is_empty(): content.add_theme_constant_override("separation",int(style.metrics.gap))
	page.add_child(content)
	return content

func _ready() -> void:
	resized.connect(_layout_pages)
	_layout_pages()
	_layout_pages.call_deferred()

func _layout_pages() -> void:
	if not is_instance_valid(left_scroll) or not is_instance_valid(right_scroll): return
	var guides := Materials.content_rects(size,"notebook")
	if guides.size() != 2: return
	left_scroll.position = guides[0].position
	left_scroll.size = guides[0].size
	right_scroll.position = guides[1].position
	right_scroll.size = guides[1].size

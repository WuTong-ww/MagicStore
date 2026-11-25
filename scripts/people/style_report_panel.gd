extends VBoxContainer
## Read-only consumer of the modern public report; never receives a snapshot.

const UI = preload("res://scripts/ui/ui_kit.gd")
signal evidence_requested(visit_id: String, action_id: String)

var report: Dictionary = {}
var active_basis_id: String = ""
var _details: VBoxContainer
var _copy: Dictionary = {}
var _layout: Dictionary = {}
var _groups: Dictionary = {}

func _ready() -> void:
	theme = load("res://themes/paper.tres")
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func set_report(value: Dictionary) -> void:
	active_basis_id = ""
	report = {}
	_groups = {}
	_details = null
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	visible = _valid_report(value)
	if not visible:
		return
	report = value.duplicate(true)
	_copy = report.ui.copy
	_layout = report.ui.layout
	add_theme_constant_override("separation",int(_layout.section_gap))
	custom_minimum_size.y = float(_layout.minimum_height)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",int(_layout.gap))
	add_child(heading)
	var title: Label = _label(report.title.label,int(_layout.heading_font_size))
	heading.add_child(title)
	add_child(_label(report.title.reason,int(_layout.body_font_size)))
	var window_text: String = _copy.window_format % report.window.visit_ids.size() if report.window.has("visit_ids") else _copy.unknown_value
	add_child(_label(window_text,int(_layout.small_font_size)))
	if report.status == "invalid_sources":
		add_child(_label(_copy.invalid_sources,int(_layout.body_font_size)))
	_groups["title"] = report.title.basis_ids.duplicate()
	var title_basis: Button = _button(_copy.basis_button,func(): _show_group("title"))
	title_basis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_basis)
	var grid := GridContainer.new()
	grid.name = "StyleDimensionGrid"
	grid.columns = int(_layout.columns)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",int(_layout.gap))
	grid.add_theme_constant_override("v_separation",int(_layout.gap))
	add_child(grid)
	for dimension: Dictionary in report.dimensions:
		_dimension(grid,dimension)
	var notice: Label = _label(report.notice,int(_layout.small_font_size))
	notice.name = "StyleReportNotice"
	add_child(notice)
	_details = VBoxContainer.new()
	_details.name = "StyleConclusionDetails"
	_details.add_theme_constant_override("separation",int(_layout.gap))
	_details.hide()
	add_child(_details)

func _dimension(parent: GridContainer, dimension: Dictionary) -> void:
	var card: PanelContainer = UI.panel("plain")
	card.name = "StyleDimension_"+dimension.id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var margin: MarginContainer = UI.margin(int(_layout.margin))
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",int(_layout.gap))
	margin.add_child(box)
	var score: String = _copy.observing if dimension.score == null else _copy.score_format % int(dimension.score)
	box.add_child(_label(dimension.label+" · "+score,int(_layout.title_font_size)))
	box.add_child(_label(_copy.sample_format % [dimension.sample_count,dimension.eligible_count,dimension.missing_count],int(_layout.small_font_size)))
	# Keep the two proxy warnings in the overview; full limitations and raw
	# metrics remain reachable together through the actual details control.
	if dimension.status == "limited":
		var proxy: Label = _label(dimension.limitation.get_slice("；",0),int(_layout.small_font_size))
		proxy.tooltip_text = dimension.limitation
		box.add_child(proxy)
	_groups[dimension.id] = dimension.basis_ids.duplicate()
	var button: Button = _button(_copy.basis_button,func(): _show_group(dimension.id))
	button.set_meta("dimension_id",dimension.id)
	box.add_child(button)

func _clear_details() -> void:
	active_basis_id = ""
	for child: Node in _details.get_children():
		_details.remove_child(child)
		child.queue_free()
	_details.show()

func _show_group(id: String, expanded: bool = false) -> void:
	if not _groups.has(id) or not is_instance_valid(_details):
		return
	_clear_details()
	var dimension: Dictionary = {}
	for row: Dictionary in report.dimensions:
		if row.id == id:
			dimension = row
	_details.add_child(_label(report.title.label if dimension.is_empty() else dimension.label,int(_layout.title_font_size)))
	if not dimension.is_empty():
		var metrics: Dictionary = dimension.metrics
		var labels: Dictionary = _copy.metrics[dimension.id]
		for key: String in labels:
			if metrics.has(key):
				var raw: String = _copy.unknown_value if metrics[key] == null else str(metrics[key])
				_details.add_child(_label(_copy.metric_format % [labels[key],raw],int(_layout.body_font_size)))
		_details.add_child(_label(dimension.limitation,int(_layout.small_font_size)))
	_details.add_child(_label(_copy.basis_heading,int(_layout.title_font_size)))
	var ids: Array = _groups[id]
	if ids.is_empty():
		_details.add_child(_label(_copy.empty_basis,int(_layout.body_font_size)))
	var limit: int = ids.size() if expanded else mini(ids.size(),int(_layout.basis_page_size))
	for index: int in range(limit):
		var basis_id: String = ids[index]
		var button: Button = _button(report.evidence[basis_id].label,func(): activate_basis(basis_id))
		button.set_meta("basis_id",basis_id)
		_details.add_child(button)
	if limit < ids.size():
		_details.add_child(_button(_copy.more_basis,func(): _show_group(id,true)))
	_details.add_child(_button(_copy.close_detail,func(): _details.hide()))

func activate_basis(basis_id: String) -> bool:
	if not report.get("evidence",{}).has(basis_id) or not _used_basis(basis_id) or not is_instance_valid(_details):
		return false
	_clear_details()
	active_basis_id = basis_id
	var row: Dictionary = report.evidence[basis_id]
	var detail := VBoxContainer.new()
	detail.name = "StyleEvidenceDetail"
	detail.add_theme_constant_override("separation",int(_layout.gap))
	_details.add_child(detail)
	detail.add_child(_label(_copy.detail_heading,int(_layout.title_font_size)))
	detail.add_child(_label(row.label,int(_layout.body_font_size)))
	detail.add_child(_label(row.text,int(_layout.body_font_size)))
	if not row.visit_id.is_empty() and not row.action_id.is_empty():
		var button: Button = _button(_copy.open_history,func(): _open_current_basis(basis_id))
		button.name = "StyleOpenHistory"
		detail.add_child(button)
	detail.add_child(_button(_copy.close_detail,func(): _details.hide()))
	return true

func _open_current_basis(id: String) -> void:
	# The callback can outlive a refresh until queue_free; authorize it again.
	if id != active_basis_id or not report.get("evidence",{}).has(id) or not _used_basis(id):
		return
	var row: Dictionary = report.evidence[id]
	if not row.visit_id.is_empty() and not row.action_id.is_empty():
		evidence_requested.emit(row.visit_id,row.action_id)

func _used_basis(id: String) -> bool:
	return _groups.values().any(func(ids: Array) -> bool: return id in ids)

func _label(text: String, font_size: int) -> Label:
	var node: Label = UI.label(text,font_size)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

func _button(text: String, callback: Callable) -> Button:
	var node: Button = UI.button(text,callback)
	node.custom_minimum_size.y = float(_layout.button_height)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

static func _valid_report(value: Dictionary) -> bool:
	for key: String in ["title","window","evidence","ui"]:
		if not value.get(key) is Dictionary:
			return false
	if value.get("status") not in ["ready","observing","invalid_sources"] or not value.get("notice") is String or not value.get("dimensions") is Array or value.dimensions.size() != 6 or not value.title.get("label") is String or not value.title.get("reason") is String or not value.title.get("basis_ids") is Array:
		return false
	if not value.window.get("visit_ids") is Array and not (value.status == "invalid_sources" and value.window.is_empty()):
		return false
	var copy: Variant = value.ui.get("copy")
	var layout: Variant = value.ui.get("layout")
	if not copy is Dictionary or not layout is Dictionary or not copy.get("metrics") is Dictionary:
		return false
	for key: String in ["page_title","observing","invalid_sources","score_format","sample_format","window_format","basis_heading","basis_button","detail_heading","close_detail","open_history","empty_basis","more_basis","metric_format","unknown_value"]:
		if not copy.get(key) is String:
			return false
	for key: String in ["margin","gap","section_gap","heading_font_size","title_font_size","body_font_size","small_font_size","button_height","score_bar_height","minimum_height","basis_page_size","columns","score_maximum"]:
		if not (layout.get(key) is int or layout.get(key) is float) or not is_finite(float(layout[key])) or float(layout[key]) <= 0.0:
			return false
	var ids: Dictionary = {}
	for row: Variant in value.dimensions:
		if not row is Dictionary or not row.get("id") is String or ids.has(row.id) or not row.get("label") is String or not row.get("limitation") is String or not row.get("metrics") is Dictionary or not row.get("basis_ids") is Array or not copy.metrics.get(row.id) is Dictionary:
			return false
		ids[row.id] = true
		for key: String in ["sample_count","eligible_count","missing_count"]:
			if not (row.get(key) is int or row.get(key) is float) or not is_finite(float(row[key])) or float(row[key]) < 0.0:
				return false
		if row.get("score") != null and (not (row.score is int or row.score is float) or not is_finite(float(row.score)) or float(row.score) < 0.0 or float(row.score) > float(layout.score_maximum)):
			return false
		for key: String in row.metrics:
			if not copy.metrics[row.id].get(key) is String:
				return false
		for id: Variant in row.basis_ids:
			if not id is String or not _basis_valid(value.evidence.get(id),id):
				return false
	for id: Variant in value.title.basis_ids:
		if not id is String or not _basis_valid(value.evidence.get(id),id):
			return false
	return true

static func _basis_valid(row: Variant, id: String) -> bool:
	if not row is Dictionary or row.get("id") != id:
		return false
	for key: String in ["label","text","visit_id","action_id"]:
		if not row.get(key) is String:
			return false
	return true

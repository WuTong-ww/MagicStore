extends HFlowContainer
## The same selection/metadata projection as the former dropdown, drawn as cards.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Style = preload("res://scripts/ui/style_config.gd")
signal item_selected(index: int)
var _items: Array[Dictionary] = []
var selected := -1
var item_count: int:
	get: return _items.size()
var fit_to_longest_item := false
var disabled := false:
	set(value):
		disabled = value
		_refresh()

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var config := Style.load_config()
	if not config.is_empty():
		add_theme_constant_override("h_separation",int(config.metrics.gap))
		add_theme_constant_override("v_separation",int(config.metrics.gap))

func add_item(text: String) -> void:
	var index := _items.size()
	var card := UI.button(text,_choose.bind(index))
	card.name = "ChoiceCard_"+str(index)
	card.toggle_mode = true
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var config := Style.load_config()
	if not config.is_empty(): card.custom_minimum_size.x = config.metrics.choice_minimum_width
	_items.append({"text":text,"metadata":null,"disabled":false,"button":card})
	add_child(card)
	if selected < 0: selected = 0
	_refresh()

func clear() -> void:
	for row: Dictionary in _items:
		remove_child(row.button)
		row.button.queue_free()
	_items.clear()
	selected = -1

func select(index: int) -> void:
	if index < -1 or index >= _items.size(): return
	selected = index
	_refresh()

func set_item_metadata(index: int, value: Variant) -> void:
	if index >= 0 and index < _items.size(): _items[index].metadata = _copy(value)

func get_item_metadata(index: int) -> Variant:
	return _copy(_items[index].metadata) if index >= 0 and index < _items.size() else null

func get_item_text(index: int) -> String:
	return str(_items[index].text) if index >= 0 and index < _items.size() else ""

func set_item_disabled(index: int, value: bool) -> void:
	if index >= 0 and index < _items.size():
		_items[index].disabled = value
		_refresh()

func _choose(index: int) -> void:
	if disabled or index < 0 or index >= _items.size() or _items[index].disabled: return
	select(index)
	item_selected.emit(index)

func _refresh() -> void:
	for index: int in range(_items.size()):
		var card: Button = _items[index].button
		card.disabled = disabled or bool(_items[index].disabled)
		card.set_pressed_no_signal(index == selected)
		# A history/archive may contain many cards. Build each physical object
		# once; changing selection only shows its existing committed stamp.
		if not card.has_meta("choice_material_initialized"):
			UI.Materials.apply_candidate(card,str(_items[index].text),index == selected)
			card.set_meta("choice_material_initialized",true)
		else:
			card.set_meta("material_selected",index == selected)
			var stamp := card.get_node_or_null("MaterialSelectionStamp") as Control
			if stamp != null: stamp.visible = index == selected

static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

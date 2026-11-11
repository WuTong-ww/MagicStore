extends RefCounted
## Paid media panels. A spread preview takes positions only and shows card backs.

const Wheel = preload("res://scripts/divination/chart_wheel.gd")

static func spread(parent: Container, positions: Array, cards: Array = []) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	parent.add_child(row)
	for index in range(positions.size()):
		var panel := MidnightUI.panel()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 5)
		panel.add_child(box)
		box.add_child(MidnightUI.label(positions[index], 15, MidnightUI.GOLD))
		if cards.is_empty():
			var art := MidnightUI.image("res://assets/card_back.svg")
			art.custom_minimum_size.y = 92
			box.add_child(art)
			continue
		var card: Dictionary = cards[index]
		box.add_child(MidnightUI.label("%s  %s" % [card.suit, card.mark], 14, MidnightUI.MUTED))
		var heading: String = card.name
		if not card.face.is_empty():
			heading += " · " + str(card.face)
		box.add_child(MidnightUI.label(heading, 20))
		box.add_child(MidnightUI.label(card.meaning, 15))

static func show_medium(parent: Container, medium: Dictionary) -> void:
	match medium.get("kind", ""):
		"cards":
			spread(parent, medium.cards.map(func(card: Dictionary) -> String: return card.position), medium.cards)
		"hexagram":
			_hexagrams(parent, medium)
		"astrology":
			_astrology(parent, medium)
		"pillars":
			_pillars(parent, medium)
		"ziwei":
			_ziwei(parent, medium)

static func _hexagrams(parent: Container, medium: Dictionary) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var captions := {"base": "本卦", "mutual": "互卦", "changed": "变卦"}
	for key: String in captions:
		if not medium.has(key):
			continue
		var panel := MidnightUI.panel()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(panel)
		var column := VBoxContainer.new()
		panel.add_child(column)
		var hexagram: Dictionary = medium[key]
		column.add_child(MidnightUI.label("%s · %s" % [captions[key], hexagram.name], 16, MidnightUI.GOLD))
		for index in range(5, -1, -1):
			var yang := (int(hexagram.bits) & (1 << index)) != 0
			var moving: bool = key == "base" and index + 1 in medium.moving
			var description := "%s  %d%s" % ["━━━━" if yang else "━━  ━━", index + 1, " 动" if moving else ""]
			var focused: bool = key == "base" and index + 1 == medium.get("focus", 0)
			if focused:
				description += " · 本次细看"
			column.add_child(MidnightUI.label(description, 15, MidnightUI.GOLD if moving or focused else MidnightUI.MUTED))

static func _astrology(parent: Container, medium: Dictionary) -> void:
	var wheel := Wheel.new()
	wheel.chart = medium
	parent.add_child(wheel)
	var table := GridContainer.new()
	table.columns = 2
	table.add_theme_constant_override("h_separation", 12)
	parent.add_child(table)
	table.add_child(MidnightUI.label("本命位置", 16, MidnightUI.GOLD))
	table.add_child(MidnightUI.label("行运位置", 16, MidnightUI.MUTED))
	for index in range(medium.natal.size()):
		for key in ["natal", "transits"]:
			var body: Dictionary = medium[key][index]
			var row := MidnightUI.label("%s  %s · 第 %d 宫" % [body.name, body.degree_text, body.house], 14)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			table.add_child(row)

static func _pillars(parent: Container, medium: Dictionary) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	for pillar: Dictionary in medium.pillars:
		var panel := MidnightUI.panel()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(panel)
		var column := VBoxContainer.new()
		panel.add_child(column)
		column.add_child(MidnightUI.label(pillar.name, 15, MidnightUI.GOLD if pillar.id == medium.selected else MidnightUI.MUTED))
		column.add_child(MidnightUI.label(pillar.ganzhi, 22))
		column.add_child(MidnightUI.label(pillar.god, 15))

static func _ziwei(parent: Container, medium: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	# Conventional south-up arrangement: 寅 at lower left and 巳 at upper left.
	var layout := [5, 6, 7, 8, 4, -1, -2, 9, 3, -3, -4, 10, 2, 1, 0, 11]
	for branch: int in layout:
		var panel := MidnightUI.panel()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(panel)
		var style: StyleBox = panel.get_theme_stylebox("panel").duplicate()
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_content_margin(side, 8)
		panel.add_theme_stylebox_override("panel", style)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 1)
		panel.add_child(column)
		if branch < 0:
			var center: Array = [medium.bureau_name, "%s流年" % medium.annual, "命身与十四主星", "本命与流年四化"]
			column.add_child(MidnightUI.label(center[-branch - 1], 13, MidnightUI.MUTED))
			continue
		var palace: Dictionary = medium.palaces[posmod(branch - 2, 12)]
		var color := MidnightUI.GOLD if palace.id == medium.selected else MidnightUI.MUTED
		column.add_child(MidnightUI.label("%s · %s%s" % [palace.name, palace.ganzhi, " · 身宫" if palace.body else ""], 14, color))
		column.add_child(MidnightUI.label("、".join(palace.major) if not palace.major.is_empty() else "无主星", 15))
		if not palace.natal_transforms.is_empty():
			column.add_child(MidnightUI.label("本命 " + "、".join(palace.natal_transforms), 12, MidnightUI.MUTED))
		column.add_child(MidnightUI.label("流年 " + str(palace.annual_name), 12, MidnightUI.MUTED))
		if not palace.annual_transforms.is_empty():
			column.add_child(MidnightUI.label("、".join(palace.annual_transforms), 12, color))

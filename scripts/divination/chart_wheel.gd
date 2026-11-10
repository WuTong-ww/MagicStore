extends Control

var chart: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(260, 278)
	mouse_filter = MOUSE_FILTER_IGNORE

func _draw() -> void:
	if chart.is_empty():
		return
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.44
	var first_longitude := float(chart.first_sign) * 30.0
	var muted := Color("86aeb2")
	var gold := Color("d5bd86")
	draw_arc(center, radius, 0.0, TAU, 100, muted, 1.0, true)
	draw_arc(center, radius * 0.56, 0.0, TAU, 80, muted, 1.0, true)
	draw_arc(center, radius * 0.78, 0.0, TAU, 80, muted, 1.0, true)
	for house in range(12):
		var edge := Vector2.from_angle(PI - house * TAU / 12.0)
		draw_line(center + edge * radius * 0.56, center + edge * radius, muted, 1.0, true)
		var label_at := center + Vector2.from_angle(PI - (house + 0.5) * TAU / 12.0) * radius * 1.07
		_label(label_at, str(house + 1), 13, muted)
	_ring(chart.natal, center, radius * 0.65, first_longitude, gold)
	_ring(chart.transits, center, radius * 0.87, first_longitude, muted)
	_label(center - Vector2(0, 8), "本命 · 内圈", 14, gold)
	_label(center + Vector2(0, 11), "行运 · 外圈", 14, muted)

func _ring(planets: Array, center: Vector2, radius: float, first_longitude: float, color: Color) -> void:
	for index in range(planets.size()):
		var planet: Dictionary = planets[index]
		var angle := PI - deg_to_rad(float(planet.longitude_milli) / 1000.0 - first_longitude)
		var direction := Vector2.from_angle(angle)
		var point := center + direction * radius
		draw_circle(point, 2.5, color)
		var distance := 11.0 if index % 2 == 0 else -9.0
		_label(point + direction * distance, planet.mark, 12, color)

func _label(at: Vector2, text: String, font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at + Vector2(-width * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

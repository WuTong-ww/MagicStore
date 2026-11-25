extends SceneTree
## Behavioral target: no preload or typed reference to a future POLISH helper.
var checks := 0
var failures := 0
var main: Control

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLISH STYLE FAIL: "+label)

func embedded(font: Font, seen: Array = []) -> bool:
	if font == null or font is SystemFont or font in seen:
		return false
	var next := seen.duplicate()
	next.append(font)
	if font is FontFile and font.allow_system_fallback:
		return false
	if font is FontVariation and not embedded(font.base_font,next):
		return false
	for fallback: Font in font.fallbacks:
		if not embedded(fallback,next): return false
	return font is FontFile or font is FontVariation

func mixed_face(font: Font) -> bool:
	if not embedded(font) or not font is FontVariation or not font.base_font is FontFile:
		return false
	if font.base_font.get_font_name() != "Midnight Numeric": return false
	if font.fallbacks.size() != 1 or not font.fallbacks[0] is FontFile: return false
	if not font.fallbacks[0].get_font_name().contains("WenKai"): return false
	return font.has_char(0x96F6) and font.has_char(0x5E97)

func mono(font: Font) -> bool:
	if font == null: return false
	var width := font.get_string_size("0",HORIZONTAL_ALIGNMENT_LEFT,-1,32).x
	if width <= 0: return false
	for value: String in ["1","2","3","4","5","6","7","8","9",":"]:
		if absf(font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,32).x-width) > 0.1: return false
	return true

func run() -> void:
	var game: Node = root.get_node("GameState")
	game.configure_api("","","")
	game.set_people_generation_options(false)
	root.get_node("SaveService").base_dir = "res://.tools/r3-polish/style-saves/"+game.make_id("run")
	var before: Dictionary = game.snapshot()
	var slots := {"Label":["font"],"Title":["font"],"Button":["font"],"OptionButton":["font"],"CheckButton":["font"],"CheckBox":["font"],"LineEdit":["font"],"TextEdit":["font"],"ItemList":["font"],"PopupMenu":["font"],"TabBar":["font"],"Tree":["font"],"Window":["title_font"],"ProgressBar":["font"],"RichTextLabel":["normal_font","bold_font","italics_font","bold_italics_font","mono_font"],"Dialogue":["normal_font"]}
	for name: String in ["paper","chrome","midnight"]:
		var theme: Theme = load("res://themes/"+name+".tres")
		check(mixed_face(theme.default_font),name+" default is bundled mono ASCII plus WenKai Chinese")
		for type_name: String in slots:
			for slot: String in slots[type_name]:
				var font: Font = theme.get_font(slot,type_name)
				check(mixed_face(font),name+" / "+type_name+" / "+slot+" uses explicit embedded faces")
				check(mono(font),name+" / "+type_name+" / "+slot+" uses equal-width numeric punctuation")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for page: String in ["exterior","front","consultation","inventory","workshop","market","gathering","people"]:
		var button: Button = main.find_child("Navigate_"+page,true,false)
		check(is_instance_valid(button) and button.icon is Texture2D,"navigation uses an image / "+page)
		if is_instance_valid(button):
			check(not button.text.contains("⌂") and not button.text.contains("⚒") and not button.text.contains("☏"),"navigation preserves Chinese text without glyph icons / "+page)
	check(game.snapshot() == before,"presentation-only style checks preserve the complete snapshot")
	check(await main.prepare_close_async(),"real Main presentation shuts down")
	main.queue_free()
	await process_frame
	await process_frame
	print("POLISH STYLE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

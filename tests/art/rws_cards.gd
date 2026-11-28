extends SceneTree
## Exercise the exact C-line resource contract using the pinned Godot decoder.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("RWS FAIL: "+label)

func _initialize() -> void:
	var deck: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/oracle/decks.json"))
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/oracle/card_art.json"))
	check(index is Dictionary and index.get("version") == 1 and index.get("tarot") is Dictionary and index.tarot.size() == 78,"version one / 78 IDs")
	if failures == 0:
		for card: Dictionary in deck.tarot:
			var path := "res://assets/oracle/rws/"+str(card.id)+".webp"
			check(index.tarot.get(card.id) == path,"exact deck ID mapping / "+str(card.id))
			var texture := load(path) as Texture2D
			check(texture != null and texture.get_size() == Vector2(360,617),"imported image / "+str(card.id))
			if texture != null:
				var image := texture.get_image()
				check(image != null and not image.is_empty(),"Godot decoded pixels / "+str(card.id))
	print("RWS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

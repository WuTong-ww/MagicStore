extends RefCounted
## Explicit prior-version encounter setup. Production never calls this helper.

const Catalog = preload("res://scripts/divination/catalog.gd")
const Bridge = preload("res://scripts/shop/people_bridge.gd")

static func install(game: Node, ids: Array = ["npc_demo_xu","npc_demo_ji"]) -> bool:
	var legacy: Variant = JSON.parse_string(FileAccess.get_file_as_string(Catalog.LEGACY_GUESTS_PATH))
	if not legacy is Dictionary:
		return false
	var economy: Dictionary = game._divination.data.economy
	for id: String in ids:
		if not Catalog.LEGACY_GUEST_IDS.has(id) or not legacy.get(id) is Dictionary:
			return false
		game.state.npcs[id] = {"coins":int(legacy[id].coins),"items":{economy.payment_item_id:4,economy.gift_id:1}}
	game._sync_generated_catalog()
	for id: String in ids:
		if not game._divination.data.guests.has(id):
			return false
		Bridge._import_profile(game.state.people,id,game._divination)
	return true

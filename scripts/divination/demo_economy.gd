extends RefCounted
## Local C adapter. All mutations are made on GameState's uncommitted candidate.

static func initialize(state: Dictionary, data: Dictionary, fixed_id: String) -> void:
	var economy: Dictionary = data.economy
	state.player["items"] = {economy.product_id: int(economy.starting_stock)}
	state.npcs[fixed_id]["items"] = _guest_items(economy)
	var ordinary: Array[String] = []
	for npc_id: String in data.guests:
		match data.guests[npc_id].get("fixture", ""):
			"ordinary":
				ordinary.append(npc_id)
			"reference":
				_add_guest(state, npc_id, data)
	if not ordinary.is_empty():
		ordinary.sort()
		_add_guest(state, ordinary[posmod(String(state.save_id).hash(), ordinary.size())], data)

static func _guest_items(economy: Dictionary) -> Dictionary:
	return {economy.payment_item_id: 4, economy.gift_id: 1}

static func _add_guest(state: Dictionary, npc_id: String, data: Dictionary) -> void:
	state.npcs[npc_id] = {"coins": int(data.guests[npc_id].coins), "items": _guest_items(data.economy)}

static func can_pay(wallet: Dictionary, payment: Dictionary) -> bool:
	if payment.kind == "coins":
		return int(wallet.coins) >= int(payment.amount)
	return int(wallet.items.get(payment.item_id, 0)) >= int(payment.amount)

static func transfer(state: Dictionary, visit: Dictionary, payment: Dictionary, category: String, reference_id: String, to_player: bool) -> Dictionary:
	var guest: Dictionary = state.npcs[visit.npc_id]
	var debit: Dictionary = guest if to_player else state.player
	var credit: Dictionary = state.player if to_player else guest
	var amount := int(payment.amount)
	if payment.kind == "coins":
		debit.coins -= amount
		credit.coins += amount
	else:
		move_item(debit, credit, payment.item_id, amount)
	var entry: Dictionary = {
		"entry_id": "ledger_%s" % reference_id, "category": category, "reference_id": reference_id,
		"visit_id": visit.visit_id, "npc_id": visit.npc_id, "at": int(state.clock_minutes),
		"from": visit.npc_id if to_player else "player",
		"to": "player" if to_player else visit.npc_id, "payment": payment.duplicate(true)
	}
	state.divination.ledger.append(entry)
	return entry

static func move_item(debit: Dictionary, credit: Dictionary, item_id: String, amount: int) -> void:
	debit.items[item_id] = int(debit.items.get(item_id, 0)) - amount
	credit.items[item_id] = int(credit.items.get(item_id, 0)) + amount

static func gift(state: Dictionary, visit: Dictionary, effect: Dictionary, economy: Dictionary) -> void:
	var payment: Dictionary = {"kind": "item", "item_id": economy.gift_id, "item_name": economy.gift_name, "amount": effect.amount}
	if can_pay(state.npcs[visit.npc_id], payment):
		transfer(state, visit, payment, "gift", effect.effect_id, true)

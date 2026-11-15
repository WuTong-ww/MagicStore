extends RefCounted
## Stores only witnessed information. The host must verify source IDs before
## committing; predictions and statements never become world facts here.

const KINDS := ["statement", "clue", "prediction", "feedback", "event"]
const AUDIENCES := ["player", "npc", "both"]

static func record(people: Dictionary, npc_id: String, record: Dictionary) -> bool:
	if not people.get("profiles", {}).has(npc_id) or not record is Dictionary:
		return false
	for key: String in ["memory_id", "visit_id", "topic_id", "kind", "audience", "text", "source_id"]:
		if not record.get(key) is String or record[key].strip_edges().is_empty():
			return false
	if record.kind not in KINDS or record.audience not in AUDIENCES or record.text.length() > 500:
		return false
	if not _integer(record.get("min_familiarity", 1), 0, 100) or not _integer(record.get("min_trust", 0), -100, 100) or not record.get("followup_open", true) is bool:
		return false
	var memories: Array = people.profiles[npc_id].memories
	if memories.any(func(item: Dictionary) -> bool: return item.get("memory_id") == record.memory_id):
		return false
	var stored := {
		"memory_id": record.memory_id, "visit_id": record.visit_id, "topic_id": record.topic_id,
		"kind": record.kind, "audience": record.audience, "text": record.text.strip_edges(),
		"source_id": record.source_id, "at": int(people.clock), "min_familiarity": int(record.get("min_familiarity", 1)),
		"min_trust": int(record.get("min_trust", 0)), "followup_open": record.get("followup_open", true)
	}
	memories.append(stored)
	return true

static func visible(people: Dictionary, npc_id: String, viewer: String) -> Array:
	if viewer not in ["player", "npc"] or not people.get("profiles", {}).has(npc_id):
		return []
	var result: Array = []
	for memory: Dictionary in people.profiles[npc_id].memories:
		# Older summary-only visit records were visible to the player and NPC.
		if not memory.has("memory_id"):
			continue
		if memory.get("audience") in [viewer, "both"]:
			result.append(memory.duplicate(true))
	return result

static func dialogue_context(people: Dictionary, npc_id: String, limit: int = 8) -> Array:
	# Only information shared with the player may enter the dialogue prompt.
	# NPC-only secrets stay in the trusted rules layer until explicitly revealed.
	var player_known := {}
	for memory: Dictionary in visible(people, npc_id, "player"):
		player_known[memory.memory_id] = true
	var rows: Array = []
	for memory: Dictionary in visible(people, npc_id, "npc"):
		if player_known.has(memory.memory_id):
			rows.append(memory)
	var start := maxi(0, rows.size() - clampi(limit, 0, 30))
	return rows.slice(start)

static func followups(people: Dictionary, npc_id: String, current_visit_id: String) -> Array:
	var profile: Dictionary = people.get("profiles", {}).get(npc_id, {})
	if profile.is_empty() or int(profile.get("familiarity", 0)) < 1:
		return []
	var known_npc := {}
	for memory: Dictionary in visible(people, npc_id, "npc"):
		known_npc[memory.memory_id] = true
	var result: Array = []
	var topics := {}
	var player_memories := visible(people, npc_id, "player")
	player_memories.reverse()
	for memory: Dictionary in player_memories:
		var asked_key := JSON.stringify([npc_id, current_visit_id, memory.topic_id])
		if memory.visit_id == current_visit_id or memory.kind not in ["statement", "feedback"] or not known_npc.has(memory.memory_id) or topics.has(memory.topic_id) or people.get("followups_asked", {}).has(asked_key):
			continue
		if not memory.get("followup_open", true) or int(profile.familiarity) < int(memory.get("min_familiarity", 1)) or int(profile.trust) < int(memory.get("min_trust", 0)):
			continue
		result.append({"topic_id": memory.topic_id, "memory_id": memory.memory_id,
			"label": "上次你提到过“%s”，后来怎么样？" % memory.text.left(35),
			"source_visit_id": memory.visit_id, "source_id": memory.source_id})
		topics[memory.topic_id] = true
		if result.size() >= 3:
			break
	return result

static func mark_followup_asked(people: Dictionary, npc_id: String, current_visit_id: String, memory_id: String, action_id: String) -> bool:
	if current_visit_id.is_empty() or action_id.is_empty():
		return false
	for option: Dictionary in followups(people, npc_id, current_visit_id):
		if option.memory_id == memory_id:
			var key := JSON.stringify([npc_id, current_visit_id, option.topic_id])
			people.followups_asked[key] = {"npc_id": npc_id, "visit_id": current_visit_id, "topic_id": option.topic_id, "memory_id": memory_id, "action_id": action_id, "at": int(people.clock)}
			return true
	return false

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func valid(people: Dictionary) -> bool:
	for npc_id: String in people.get("profiles", {}):
		var seen := {}
		for memory: Variant in people.profiles[npc_id].get("memories", []):
			if not memory is Dictionary:
				return false
			if not memory.has("memory_id"):
				if not memory.get("visit_id") is String or not memory.get("summary") is String:
					return false
				continue
			for key: String in ["memory_id", "visit_id", "topic_id", "kind", "audience", "text", "source_id"]:
				if not memory.get(key) is String or memory[key].is_empty():
					return false
			if memory.kind not in KINDS or memory.audience not in AUDIENCES or memory.text.length() > 500 or seen.has(memory.memory_id) or not _integer(memory.get("min_familiarity", 1), 0, 100) or not _integer(memory.get("min_trust", 0), -100, 100) or not memory.get("followup_open", true) is bool:
				return false
			seen[memory.memory_id] = true
	return true

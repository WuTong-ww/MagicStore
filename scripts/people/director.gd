extends RefCounted
## AI can select a permitted proposal; A/C validate and commit actual effects.

const People = preload("res://scripts/people/people.gd")

static func candidates(people: Dictionary, npc_id: String, trigger_id: String, proposed_at: int) -> Array:
	var rows: Array = [{"candidate_id": "no_action", "label": "暂不安排新行动", "kind": "no_action"}]
	if not people.profiles.has(npc_id) or trigger_id.is_empty() or people.director_decisions.has(trigger_id) or proposed_at <= int(people.clock):
		return rows
	if proposed_at % 1440 < 540 or proposed_at % 1440 >= 1320:
		return rows
	for referral_id: String in people.referrals:
		var referral: Dictionary = people.referrals[referral_id]
		if referral.state != "proposed" or referral.referrer_npc_id != npc_id or referral.event_id != trigger_id:
			continue
		var busy := false
		for arrival: Dictionary in people.arrivals.values():
			if arrival.npc_id == referral.target_npc_id and arrival.state in ["planned", "queued", "in_service"]:
				busy = true
				break
		if not busy:
			rows.append({"candidate_id": "director_" + referral_id, "label": "考虑介绍一位认识的人",
				"kind": "referral", "referral_id": referral_id, "at": proposed_at})
	return rows

static func public_candidates(rows: Array) -> Array:
	var result: Array = []
	for row: Dictionary in rows:
		result.append({"candidate_id": row.candidate_id, "label": row.label})
	return result

static func apply(people: Dictionary, npc_id: String, proposal: Dictionary, proposed_at: int) -> bool:
	var trigger_id: Variant = proposal.get("trigger_id")
	var candidate_id: Variant = proposal.get("candidate_id")
	if not trigger_id is String or trigger_id.is_empty() or not candidate_id is String or people.director_decisions.has(trigger_id):
		return false
	if not people.profiles.has(npc_id):
		return false
	var rows := candidates(people, npc_id, trigger_id, proposed_at)
	for row: Dictionary in rows:
		if row.candidate_id != candidate_id:
			continue
		if row.kind == "referral" and not People.schedule_referral(people, row.referral_id, int(row.at)):
			return false
		people.director_decisions[trigger_id] = {"trigger_id": trigger_id, "candidate_id": candidate_id, "npc_id": npc_id, "at": int(people.clock)}
		return true
	return false

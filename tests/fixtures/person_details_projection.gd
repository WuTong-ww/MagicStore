extends RefCounted
const Person = preload("res://scripts/people/generated_person.gd")
## Compare every old field while excluding only schema16's explicit additions.
static func before16(current: Dictionary, original: Dictionary) -> Dictionary:
	var projected := current.duplicate(true)
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/npcs.json"))
	for marker: String in ["nationality_version","face_details_version"]:
		if not original.has(marker): projected.erase(marker)
	for id: String in projected.get("profiles",{}):
		if not original.get("profiles",{}).has(id): continue
		var previous: Dictionary = original.profiles[id]
		var profile: Dictionary = projected.profiles[id]
		for field: String in ["nationality","age"]:
			if not previous.has(field): profile.erase(field)
		var fixed: Dictionary = story.npcs.get(id,{})
		if not fixed.is_empty():
			for field: String in ["age","mbti"]:
				if previous.has(field) and profile.get(field) == fixed.get(field): profile[field] = previous[field]
		if not previous.appearance.has("face_details"): profile.appearance.erase("face_details")
		if profile.has("generation_id"): profile.generation_identity_hash = Person._local_identity_hash(profile)
	return projected

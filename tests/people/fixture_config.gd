extends RefCounted
## Test-only reference family; the production config contains no sample cast.
const People = preload("res://scripts/people/people.gd")
static func reference_family() -> Dictionary:
	var config := People.load_config()
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/people/fixtures/family_reference.json"))
	if config.is_empty() or not fixture is Dictionary or not fixture.get("family") is Dictionary:
		return {}
	config.family = fixture.family.duplicate(true)
	config.arrival.family_percent = fixture.family_percent
	return config if People.config_valid(config) else {}

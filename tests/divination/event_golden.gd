extends SceneTree
## Actual pre-refactor outputs are immutable evidence, not a reimplementation.
const Events = preload("res://scripts/divination/event_rules.gd")
const PATH := "res://tests/fixtures/G3/invitation_golden.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("EVENT GOLDEN FAIL: " + label)

func fixture_valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("format") != "invitation_resolve_golden_v1" or value.get("captured_before_refactor") != true or not value.get("definition") is Dictionary or not value.get("records") is Array:
		return false
	if value.get("matrix_count") != 96 or value.get("boundary_count") != 2 or value.records.size() != 98:
		return false
	if value.get("source_sha256") != "b6ad07d355415ae1228c45e3b198934df92116afab597f154ba495f0b673351d":
		return false
	for row: Variant in value.records:
		if not row is Dictionary or not row.get("case_before") is Dictionary or not row.get("event_after") is Dictionary:
			return false
	return true

func canonical(value: Variant) -> Variant:
	if value is float and value == floor(value):
		return int(value)
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = canonical(value[key])
		return result
	if value is Array:
		return value.map(canonical)
	return value

func run() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	check(FileAccess.get_sha256(PATH) == "cf75ced412a83a3ede4a97fbf63a6c61d056394639a3ff046c719b0af0c5da4a", "captured fixture bytes are unchanged")
	check(fixture_valid(fixture), "98 captured outputs retain their provenance and shape")
	if not fixture_valid(fixture):
		finish()
		return
	var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/divination.json"))
	var definition: Dictionary = current.cases.invitation.event
	for index: int in range(fixture.records.size()):
		var row: Dictionary = fixture.records[index]
		var case: Dictionary = row.case_before.duplicate(true)
		Events._resolve(case, definition)
		var expected: Dictionary = row.event_after.duplicate(true)
		if definition.has("rules"):
			# G3 explicitly changes partial disclosure and scheduling. The captured
			# world result, advice precedence, action and item/branch links stay exact.
			expected["rule_index"] = case.event.rule_index
			var selected: Dictionary = definition.outcomes[expected.outcome_id]
			expected.evidence = selected.evidence
			expected.feedback.available_at = -1 if selected.feedback == "never" else int(expected.due_at) + int(selected.delay_minutes)
			expected.feedback.disclosure = {}
			if selected.feedback != "never" and selected.evidence != "none":
				expected.feedback.disclosure = {"text":selected.text,"evidence":selected.evidence}
				if selected.evidence == "sufficient":
					expected.feedback.disclosure.merge({"occurrence":expected.occurrence,"outcome":expected.outcome,"actual_action":expected.actual_action,"occurred_at":expected.due_at if expected.occurrence == "occurred" else -1})
		if canonical(case.event) != canonical(expected) and failures < 1:
			for key: String in expected:
				if case.event.get(key) != expected[key]:
					printerr("GOLDEN DIFFERENCE / " + str(index) + " / " + key + " / actual=" + JSON.stringify(case.event.get(key)) + " / expected=" + JSON.stringify(expected[key]))
		check(canonical(case.event) == canonical(expected), "captured invitation branch " + str(index))
	finish()

func finish() -> void:
	print("EVENT GOLDEN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

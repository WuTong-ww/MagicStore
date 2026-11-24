extends RefCounted
## Alternate G3 rules belong to a separate fixture case. Keep the production
## invitation unchanged so its authored deduction definition still validates.
const Catalog = preload("res://scripts/divination/catalog.gd")

static func install(game: Node, fixture_id: String) -> Dictionary:
	var data: Dictionary = game._divination.data.duplicate(true)
	data.cases[fixture_id] = data.cases.invitation.duplicate(true)
	game._divination.data = data
	return data.cases[fixture_id].event

static func sync(game: Node, saves: Node) -> void:
	game._divination._base_catalog = game._divination.data.duplicate(true)
	saves._divination_data = game._divination.data.duplicate(true)

static func bind(game: Node, fixture_id: String, visit_id: String = "") -> void:
	if visit_id.is_empty():
		visit_id = game.state.active_visit_id
	var case: Dictionary = game.state.divination.cases[visit_id]
	case.case_id = fixture_id
	case.cause = Catalog.case_cause(fixture_id)

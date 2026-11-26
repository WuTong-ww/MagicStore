extends RefCounted
## Authored legacy capability setup for older contract tests only.
## This is not sealed historical-save migration evidence.
static func install(state: Dictionary) -> bool:
	state.erase("learning")
	return preload("res://scripts/learning/learning_store.gd").initialize(state,false,17)

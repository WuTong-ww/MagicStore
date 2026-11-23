extends "res://scripts/core/game_state.gd"
## Test-only identity source. All game initialization, RNG, rules and writes are real.
var economic_seed := 0
var economic_strategy := ""
var economic_sequence := 0

func make_id(prefix: String = "action") -> String:
	economic_sequence += 1
	# The two strategies start in the same world. Non-save identities remain
	# strategy-specific without replacing any production RNG after creation.
	var domain: Array = [economic_seed,economic_sequence,prefix] if prefix == "save" else [economic_seed,economic_strategy,economic_sequence,prefix]
	return prefix+"_"+JSON.stringify(domain).sha256_text().left(32)

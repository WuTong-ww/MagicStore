extends "res://scripts/core/game_state.gd"
## Test-only identity source; every game rule, G1 draw and write remains real.
var fixture_sequence: int = 0

func make_id(prefix: String = "action") -> String:
	fixture_sequence += 1
	if prefix == "save":
		return "save_00000000000000000000000000000024"
	return prefix+"_past_fixture_"+str(fixture_sequence)

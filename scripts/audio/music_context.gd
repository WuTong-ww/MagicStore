extends RefCounted
## Pure routing projection; callers supply committed public views and actual UI visibility.

static func _flag(value: Variant) -> bool:
	return value is bool and value

static func project(page: String, clock_minutes: int, case_public: Dictionary = {}, story_public: Dictionary = {}, presentation: Dictionary = {}) -> Dictionary:
	var title_visible := _flag(presentation.get("title_visible",false))
	var ending: Variant = story_public.get("ending",{})
	var ending_complete: bool = ending is Dictionary and _flag(ending.get("has_ending",false)) and ending.get("status") == "complete"
	var ending_visible: bool = _flag(story_public.get("enabled",false)) and ending_complete and _flag(presentation.get("ending_visible",false))
	var music_page := "title" if title_visible else ("front" if page == "title" else page)
	return {
		"page":music_page,
		"clock_minutes":clock_minutes,
		"context":{
			"case_active":_flag(case_public.get("enabled",false)) and not _flag(case_public.get("closed",false)),
			"ending_visible":ending_visible
		}
	}

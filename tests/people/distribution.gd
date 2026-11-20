extends SceneTree

const People = preload("res://scripts/people/people.gd")
const FixtureConfig = preload("res://tests/people/fixture_config.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_invalid_configuration()
	_test_daily_distribution()
	_test_expected_components()
	_test_peak_mixture()
	_test_burst_capacity()
	_test_family_distribution()
	print("DISTRIBUTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DISTRIBUTION FAIL: " + label)

func _test_invalid_configuration() -> void:
	var config := People.load_config()
	for block: String in ["expectation", "weekday", "weather", "timing", "burst", "overflow", "patience", "distribution_targets"]:
		var missing := config.duplicate(true)
		missing.arrival.erase(block)
		check(not People.config_valid(missing), "missing arrival block is rejected: " + block)
	var invalid := config.duplicate(true)
	invalid.arrival.burst.probability = -0.1
	check(not People.config_valid(invalid), "negative burst probability is rejected")
	invalid = config.duplicate(true)
	invalid.arrival.burst.probability = 1.1
	check(not People.config_valid(invalid), "burst probability above one is rejected")
	for block: String in ["weather", "peaks", "sources"]:
		invalid = config.duplicate(true)
		var rows: Array = invalid.arrival.weather if block == "weather" else (invalid.arrival.timing.peaks if block == "peaks" else invalid.arrival.burst.sources)
		for row: Dictionary in rows:
			row.weight = 0
		check(not People.config_valid(invalid), "zero mixture weights are rejected: " + block)
	invalid = config.duplicate(true)
	invalid.arrival.expectation.base = NAN
	check(not People.config_valid(invalid), "non-finite expectation coefficient is rejected")
	invalid = config.duplicate(true)
	invalid.arrival.weather[0].modifier = INF
	check(not People.config_valid(invalid), "non-finite weather modifier is rejected")
	invalid = config.duplicate(true)
	invalid.arrival.overflow.appointment_min_score = float(invalid.arrival.overflow.outside_min_score) + 1.0
	check(not People.config_valid(invalid), "reversed overflow decision thresholds are rejected")
	invalid = config.duplicate(true)
	invalid.arrival.distribution_targets.zero_day_max = float(invalid.arrival.distribution_targets.zero_day_min) - 0.01
	check(not People.config_valid(invalid), "reversed distribution target bounds are rejected")

func _test_daily_distribution() -> void:
	var config := People.load_config()
	check(not config.is_empty(), "production arrival configuration loads")
	if config.is_empty():
		return
	var targets: Dictionary = config.arrival.get("distribution_targets", {})
	check(not targets.is_empty(), "distribution targets are configured")
	if targets.is_empty():
		return
	var samples := int(targets.samples)
	check(samples >= 2000, "distribution covers at least 2000 independent days")
	var zero_days := 0
	var overflow_days := 0
	var burst_days := 0
	var burst_sources := {}
	var weather_types := {}
	var valid_bursts := true
	var valid_plans := true
	var varied_counts := {}
	var expected_sum := 0.0
	var natural_sum := 0.0
	var squared_residual_sum := 0.0
	for index: int in range(samples):
		# Fresh shops measure the configured baseline, independent of accumulated
		# return customers, prior service and the day-zero tutorial guarantee.
		var day := index % 7 + 1
		var people := People.create("save_distribution_" + str(index), 1000 + index, day * 1440 + 540)
		People.plan_day(people, config, day)
		var plan: Dictionary = people.days[str(day)]
		var count := People.arrival_count_on_day(people, day)
		zero_days += int(count == 0)
		overflow_days += int(count > int(config.arrival.queue_capacity))
		varied_counts[count] = true
		weather_types[str(plan.get("weather", ""))] = true
		valid_plans = valid_plans and plan.has("expected") and float(plan.get("expected", -1.0)) >= 0.0 and People.validate(people).is_empty()
		var expected := float(plan.get("expected", 0.0))
		var natural := float(plan.natural_count)
		expected_sum += expected
		natural_sum += natural
		squared_residual_sum += (natural - expected) * (natural - expected)
		var clustered: Array[int] = []
		var sources := {}
		for arrival: Dictionary in people.arrivals.values():
			if str(arrival.source).begins_with("burst_"):
				clustered.append(int(arrival.at))
				sources[arrival.source] = true
				burst_sources[arrival.source] = true
		if not clustered.is_empty():
			burst_days += 1
			clustered.sort()
			valid_bursts = valid_bursts and clustered.size() >= 3 and clustered.size() <= 5 and clustered.back() - clustered.front() <= 30 and sources.size() == 1
	var zero_rate := float(zero_days) / samples
	var overflow_rate := float(overflow_days) / samples
	check(zero_rate >= float(targets.zero_day_min) and zero_rate <= float(targets.zero_day_max), "zero-customer rate %.3f is within configured [%.3f, %.3f]" % [zero_rate, float(targets.zero_day_min), float(targets.zero_day_max)])
	check(overflow_rate >= float(targets.overflow_day_min) and overflow_rate <= float(targets.overflow_day_max), "over-capacity daily rate %.3f is within configured [%.3f, %.3f]" % [overflow_rate, float(targets.overflow_day_min), float(targets.overflow_day_max)])
	check(valid_plans and weather_types.size() == 3 and not weather_types.has(""), "all plans persist valid expectations and three weather types")
	check(valid_bursts and burst_days > 0 and burst_sources.has("burst_word_of_mouth") and burst_sources.has("burst_group_referral") and burst_sources.has("burst_festival"), "all three burst sources produce groups of 3–5 arrivals within thirty minutes")
	check(varied_counts.has(0) and varied_counts.has(1) and varied_counts.has(7), "baseline includes quiet, single-guest and crowded days")
	check(absf(natural_sum / samples - expected_sum / samples) < 0.15 and absf(squared_residual_sum / samples - expected_sum / samples) < 0.3, "natural count mean and conditional variance match the configured Poisson expectation")
	var first := People.create("save_reproducible_distribution", 502, 1980)
	var second := People.create("save_reproducible_distribution", 502, 1980)
	People.plan_day(first, config, 1)
	People.plan_day(second, config, 1)
	check(first == second, "seed reproduces the complete plan, people, weather and burst")
	var before := first.duplicate(true)
	People.plan_day(first, config, 1, 500, 12, 500)
	check(first == before, "existing planned day stays byte-for-byte equivalent after changed inputs")
	print("DAILY DISTRIBUTION: %d days, zero=%d (%.2f%%), over capacity=%d (%.2f%%), bursts=%d" % [samples, zero_days, zero_rate * 100.0, overflow_days, overflow_rate * 100.0, burst_days])

func _test_peak_mixture() -> void:
	var config := People.load_config()
	if not config.arrival.has("timing"):
		check(false, "peak mixture is configured")
		return
	var near_peaks := 0
	var peak_counts := [0, 0]
	var total := 0
	var has_background := false
	for seed: int in range(200):
		var people := People.create("save_peaks_" + str(seed), 4000 + seed, 1980)
		People.plan_day(people, config, 1, 0, 12)
		for row: Dictionary in people.arrivals.values():
			if row.source != "natural":
				continue
			var minute := int(row.at) % 1440
			var near := false
			for index: int in range(config.arrival.timing.peaks.size()):
				var peak: Dictionary = config.arrival.timing.peaks[index]
				if absf(float(minute) - float(peak.mean)) <= float(peak.deviation):
					peak_counts[index] += 1
					near = true
			near_peaks += int(near)
			total += 1
			has_background = has_background or minute <= int(config.arrival.first_minute) + 30
	check(total == 2400 and float(near_peaks) / total > 0.5 and peak_counts[0] > 200 and peak_counts[1] > 200, "arrival timing concentrates at both configured peaks")
	check(has_background, "background noise still allows arrivals outside both peaks")

func _test_expected_components() -> void:
	var config := People.load_config()
	if not config.arrival.has("expectation"):
		check(false, "expectation coefficients are configured")
		return
	var valid := true
	var rules: Dictionary = config.arrival.expectation
	for seed: int in range(20):
		var day := seed % 7 + 1
		var baseline := People.create("save_expectation", 8000 + seed, day * 1440 + 540)
		var boosted := baseline.duplicate(true)
		People.plan_day(baseline, config, day, 0, 0, 0)
		People.plan_day(boosted, config, day, 20, 0, 8, 2)
		var before: Dictionary = baseline.days[str(day)]
		var after: Dictionary = boosted.days[str(day)]
		var delta := 20.0 * float(rules.reputation_coefficient) + 8.0 * float(rules.experience_coefficient) + 2.0 * float(rules.traffic_bonus_coefficient)
		valid = valid and before.has("expected") and after.has("expected") and before.get("weather") == after.get("weather") and is_equal_approx(float(after.get("expected", -1.0)) - float(before.get("expected", -1.0)), delta)
		var weather_modifier := 0.0
		for weather: Dictionary in config.arrival.weather:
			if weather.id == before.get("weather"):
				weather_modifier = float(weather.modifier)
		var weekend: bool = (day + 1) % 7 in config.arrival.weekday.weekend_days
		var weekday_modifier := float(config.arrival.weekday.weekend if weekend else config.arrival.weekday.workday)
		var baseline_expected := clampf(float(rules.base) + weekday_modifier + weather_modifier, float(rules.min), float(rules.max))
		valid = valid and is_equal_approx(float(before.get("expected", -1.0)), baseline_expected)
	check(valid, "base, reputation, experience, temporary traffic, weekday and weather use the configured additive expectation")
	config.arrival.expectation.base = 0.0
	config.arrival.weekday.workday = 0.0
	config.arrival.weekday.weekend = 0.0
	config.arrival.burst.probability = 0.0
	for weather: Dictionary in config.arrival.weather:
		weather.modifier = 0.0
	var empty := People.create("save_zero_expectation", 53, 1980)
	People.plan_day(empty, config, 1)
	check(float(empty.days["1"].expected) == 0.0 and empty.arrivals.is_empty(), "zero expectation produces a true zero-customer day without a later-day minimum")

func _test_burst_capacity() -> void:
	var config := People.load_config()
	if not config.arrival.has("burst"):
		check(false, "burst events are configured")
		return
	config.arrival.burst.probability = 1.0
	config.arrival.family_percent = 0
	config.arrival.ordinary_return_percent = 0
	config.arrival.special_return_percent = 0
	var forced := People.create("save_forced_no_burst", 94, 1980)
	People.plan_day(forced, config, 1, 0, 4)
	check(forced.arrivals.size() == 4 and forced.arrivals.values().all(func(row: Dictionary) -> bool: return row.source == "natural"), "explicit fixture counts suppress burst additions")
	config.arrival.max_total_per_day = int(config.arrival.burst.min_size) - 1
	var valid := true
	for seed: int in range(100):
		var people := People.create("save_short_burst_" + str(seed), 6000 + seed, 1980)
		People.plan_day(people, config, 1)
		valid = valid and People.arrival_count_on_day(people, 1) <= int(config.arrival.max_total_per_day) and people.arrivals.values().all(func(row: Dictionary) -> bool: return not str(row.source).begins_with("burst_"))
	check(valid, "fewer than three free daily slots cannot create a partial burst")

func _test_family_distribution() -> void:
	var config := FixtureConfig.reference_family()
	var original_total := 0
	var reference_total := 0
	var family_triggers := 0
	var service_failures := 0
	for seed in range(200):
		var people := People.create("save_dist_" + str(seed), seed, 540)
		People.plan_day(people, config, 0, 0, 2)
		var ids: Array = people.days["0"].arrival_ids.duplicate()
		ids.sort()
		for index in range(ids.size()):
			var id: String = ids[index]
			var arrival: Dictionary = people.arrivals[id]
			arrival.at = 600 + index * 5
			arrival.schedule_end = 1100
			arrival.urgency = 0
		for index in range(ids.size()):
			var id: String = ids[index]
			var minute := 600 + index * 5
			People.advance(people, config, minute)
			if not People.begin(people, id, "visit_" + id) or not People.finish(people, id, "visit_" + id, "测试接待"):
				service_failures += 1
		original_total += int(people.stats.first_original)
		reference_total += int(people.stats.first_reference)
		family_triggers += int(people.stats.family_triggers)
	check(service_failures == 0, "family fixtures are all serviceable")
	check(original_total == 400 and reference_total >= 1 and reference_total < original_total / 5 and family_triggers == reference_total, "family arrivals retain the configured rarity and service counters")
	print("FAMILY DISTRIBUTION: 200 reproducible shops, ordinary=%d, reference=%d, family triggers=%d" % [original_total, reference_total, family_triggers])

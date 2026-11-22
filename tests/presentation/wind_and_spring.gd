extends SceneTree
## Hand-derived physics, real ConfigFile persistence, and wind propagation.
const WIND_PATH := "res://scripts/presentation/wind_field.gd"
const SPRING_PATH := "res://scripts/presentation/damped_spring.gd"
const PREFS_PATH := "user://a6_core_presentation.cfg"
var checks := 0
var failures := 0
var wind_script: Script
var spring_script: Script
var settings: Dictionary = {}
var reduced_events: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("WIND/SPRING FAIL: "+label)

func near(actual: float, expected: float, tolerance: float = 0.000001) -> bool:
	return is_finite(actual) and absf(actual-expected) <= tolerance

func run() -> void:
	check(FileAccess.file_exists(WIND_PATH),"wind implementation is available")
	check(FileAccess.file_exists(SPRING_PATH),"pure spring implementation is available")
	if not FileAccess.file_exists(WIND_PATH) or not FileAccess.file_exists(SPRING_PATH):
		finish()
		return
	wind_script = load(WIND_PATH)
	spring_script = load(SPRING_PATH)
	settings = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/motion.json"))
	validation()
	wind_behavior()
	spring_behavior()
	persistence()
	finish()

func make_wind(data: Dictionary = {}) -> Node:
	var result: Node = wind_script.new()
	result.settings = (settings if data.is_empty() else data).duplicate(true)
	result.settings_path = PREFS_PATH
	root.add_child(result)
	result.set_process(false)
	return result

func simulation(k: float = 4, c: float = 4, limit: float = 20, mass: float = 1) -> Dictionary:
	return {"k":k,"c":c,"mass":mass,"max_angle_degrees":limit,"fixed_step_seconds":0.008333333333333333,"max_substeps":240}

func validation() -> void:
	check(wind_script.settings_valid(settings),"actual production motion JSON is valid")
	check(wind_script.load_settings() == settings,"public settings loader returns validated actual data")
	var cases: Array = []
	var bad := settings.duplicate(true)
	bad.wind.base = NAN; cases.append([bad,"NaN base wind"])
	bad = settings.duplicate(true); bad.wind.noise_frequency = 0; cases.append([bad,"zero noise frequency"])
	bad = settings.duplicate(true); bad.wind.gust_duration_seconds = [4,2]; cases.append([bad,"reversed gust duration"])
	bad = settings.duplicate(true); bad.wind.gust_strength = [-1,1]; cases.append([bad,"negative gust strength"])
	bad = settings.duplicate(true); bad.wind.gust_mean_seconds = 0; cases.append([bad,"zero gust interval"])
	bad = settings.duplicate(true); bad.wind.gust_jitter_seconds = 25; cases.append([bad,"overlapping unbounded slot jitter"])
	bad = settings.duplicate(true); bad.wind.door_factor = 1.1; cases.append([bad,"door factor outside unit interval"])
	bad = settings.duplicate(true); bad.wind.indoor_factor = true; cases.append([bad,"bool masquerading as numeric factor"])
	bad = settings.duplicate(true); bad.wind.gust_cache_size = 1.5; cases.append([bad,"fractional cache count"])
	bad = settings.duplicate(true); bad.defaults.reduced_motion = "false"; cases.append([bad,"nonboolean preference default"])
	bad = settings.duplicate(true); bad.settings_path = "res://save.cfg"; cases.append([bad,"production preference path outside user directory"])
	bad = settings.duplicate(true); bad.labels.reduced_motion = " "; cases.append([bad,"blank Chinese control label"])
	bad = settings.duplicate(true); bad.reduced.event_factor = INF; cases.append([bad,"infinite reduced event factor"])
	bad = settings.duplicate(true); bad.spring.fixed_step_seconds = 0; cases.append([bad,"zero simulation step"])
	bad = settings.duplicate(true); bad.spring.max_substeps = 0; cases.append([bad,"zero simulation capacity"])
	bad = settings.duplicate(true); bad.layer_defaults.pendulum.k = -1; cases.append([bad,"negative spring stiffness"])
	bad = settings.duplicate(true); bad.layer_defaults.pendulum.mass = 0; cases.append([bad,"zero pendulum mass"])
	bad = settings.duplicate(true); bad.layer_defaults.pendulum.max_angle_degrees = 4; cases.append([bad,"indoor layer angle beyond configured total limit"])
	bad = settings.duplicate(true); bad.shelf.neighbor_count = 1.5; cases.append([bad,"fractional shelf neighbor count"])
	bad = settings.duplicate(true); bad.particles.max_alive = -1; cases.append([bad,"negative particle capacity"])
	bad = settings.duplicate(true); bad.events.guest_kinds = ["guest_entered",""]; cases.append([bad,"empty event kind"])
	bad = settings.duplicate(true); bad.events.guest_kinds = []; cases.append([bad,"no configured guest event kinds"])
	bad = settings.duplicate(true); bad.events.indoor_scene_ids = "S02"; cases.append([bad,"malformed environment classification"])
	bad = settings.duplicate(true); bad.diagnostics.missing_region = ""; cases.append([bad,"missing region diagnostic"])
	for row: Array in cases:
		check(not wind_script.settings_valid(row[0]),"reject "+row[1])
	var region := {"native_size":[1672,941],"source_crop":[0,0.25,1672,940.75],"rect":[200,100,300,200],"amount":12,"lifetime_seconds":4,"color":"#C2C9BC44","size_px":2}
	var approved := settings.duplicate(true)
	approved.particles.regions.S02 = [region]
	check(wind_script.settings_valid(approved),"explicit finite native particle region can be approved")
	bad = approved.duplicate(true); bad.particles.regions.S02[0].rect[2] = 2000
	check(not wind_script.settings_valid(bad),"particle region outside crop rejected")
	bad = approved.duplicate(true); bad.particles.regions.S02[0].amount = 61
	check(not wind_script.settings_valid(bad),"particle scene total cannot exceed configured budget")
	bad = approved.duplicate(true); bad.particles.regions.S02.append(region.duplicate(true)); bad.particles.regions.S02[0].amount = 40; bad.particles.regions.S02[1].amount = 40
	check(not wind_script.settings_valid(bad),"particle budget is summed across emitters")
	bad = approved.duplicate(true); bad.particles.regions.S02[0].color = "not a color"
	check(not wind_script.settings_valid(bad),"invalid particle color rejected")
	bad = approved.duplicate(true); bad.particles.regions.S02[0].native_size[0] = 1672.5
	check(not wind_script.settings_valid(bad),"native image dimensions must be whole pixels")
	approved.particles.regions.S02[0]["gravity_px_s2"] = [0,8]
	approved.particles.regions.S02[0]["drift_px_s"] = [3,1]
	approved.particles.regions.S02[0]["opacity"] = 0.25
	check(wind_script.settings_valid(approved),"explicit particle velocity and opacity are validated")
	bad = approved.duplicate(true); bad.particles.regions.S02[0].gravity_px_s2 = [NAN,8]
	check(not wind_script.settings_valid(bad),"NaN particle gravity rejected")
	bad = approved.duplicate(true); bad.particles.regions.S02[0].drift_px_s = [3]
	check(not wind_script.settings_valid(bad),"malformed particle velocity rejected")
	bad = approved.duplicate(true); bad.particles.regions.S02[0].opacity = 2
	check(not wind_script.settings_valid(bad),"particle opacity outside unit interval rejected")

func wind_behavior() -> void:
	var flat := settings.duplicate(true)
	flat.wind.base = 2.0
	flat.wind.noise_amplitude = 0
	flat.wind.gust_strength = [0,0]
	var wind := make_wind(flat)
	check(near(wind.sample_at(7,30,0,false),2),"outdoor base wind has literal amplitude")
	check(near(wind.sample_at(7,30,0,true),0.3),"indoor uses fifteen percent of outdoor")
	check(near(wind.sample_at(7,30,0,true,1),1.2),"full door event raises indoor to sixty percent")
	check(near(wind.sample_at(7,30,0,false,0,"rainy"),3),"actual rainy weather strengthens base wind")
	check(near(wind.sample_at(7,30,0,false,0,"rain"),2),"unknown weather ID keeps neutral base")
	check(near(wind.sample_at(7,NAN,0,false),0),"invalid time returns finite still wind")
	check(near(wind.sample_at(7,30,NAN,false),0),"invalid coordinate returns finite still wind")
	wind.reduced_motion = false
	wind.time_seconds = 0
	wind.step(0.125)
	wind.step(0.375)
	check(near(wind.time_seconds,0.5),"explicit clock advances by finite deltas")
	wind.step(-1); wind.step(NAN)
	check(near(wind.time_seconds,0.5),"negative and NaN steps cannot move clock")
	check(wind.notify_door_event("fixture/door/1"),"new door event is accepted")
	check(near(wind.get_wind(0,true),1.2),"door event affects actual instance wind")
	wind.step(float(flat.wind.door_duration_seconds))
	check(not wind.notify_door_event("fixture/door/1"),"same committed door ID is not retriggered")
	check(near(wind.get_wind(0,true),0.3),"door envelope expires without retrigger")
	wind.set_weather("rainy")
	check(near(wind.get_wind(0,false),3),"weather setter reaches the instance sampler")
	wind.reduced_motion = true
	check(near(wind.get_wind(0,false),3*float(flat.reduced.wind_factor)),"reduced motion scales actual wind")
	wind.free()
	var pulse := settings.duplicate(true)
	pulse.wind.base = 0
	pulse.wind.noise_amplitude = 0
	pulse.wind.gust_mean_seconds = 25
	pulse.wind.gust_jitter_seconds = 0
	pulse.wind.gust_duration_seconds = [4,4]
	pulse.wind.gust_strength = [1,1]
	pulse.wind.propagation_seconds = 1
	wind = make_wind(pulse)
	check(near(wind.sample_at(123,0,0,false),0),"gust envelope starts at rest")
	check(near(wind.sample_at(123,1,0,false),0.5),"hand oracle: left gust at quarter duration")
	check(near(wind.sample_at(123,2,0,false),1),"hand oracle: left gust peaks at half duration")
	check(near(wind.sample_at(123,4,0,false),0),"hand oracle: gust returns to rest")
	check(near(wind.sample_at(123,0.5,1,false),0),"right side waits for propagation")
	check(near(wind.sample_at(123,3,1,false),1),"right peak arrives one second later")
	check(near(wind.sample_at(123,27,0,false),1),"next interval retains configured mean")
	wind.free()
	wind = make_wind()
	var copy := make_wind()
	var first: Array = []
	var same: Array = []
	var changed_seed := false
	for t: float in [0.25,2.0,9.0,24.5,26.0,52.0,99.0,200.0]:
		first.append(wind.sample_at(321,t,0.6,false))
		same.append(copy.sample_at(321,t,0.6,false))
		changed_seed = changed_seed or not near(first[-1],copy.sample_at(322,t,0.6,false),0.00000001)
	check(first == same,"independent instances reproduce seed and time sequence")
	check(changed_seed,"seed actually affects low-frequency and gust sequence")
	seed(944)
	var expected_random := randf()
	seed(944)
	for t: float in [1.0,33.0,100.0,999.0]:
		wind.sample_at(812,t,0.2,true)
	check(randf() == expected_random,"wind does not consume global gameplay RNG")
	wind.free(); copy.free()

func spring_behavior() -> void:
	var spring: RefCounted = spring_script.new()
	check(spring.configure(simulation()),"valid pure spring parameters are accepted")
	for key: String in ["k","c","mass","max_angle_degrees","fixed_step_seconds","max_substeps"]:
		var bad := simulation()
		bad[key] = NAN
		check(not spring.configure(bad),"reject NaN spring field / "+key)
	var bad := simulation(); bad.k = 0
	check(not spring.configure(bad),"zero stiffness cannot define a rest position")
	bad = simulation(); bad.c = -1
	check(not spring.configure(bad),"negative damping rejected")
	bad = simulation(); bad.mass = 0
	check(not spring.configure(bad),"zero mass rejected")
	bad = simulation(); bad.max_substeps = 2.5
	check(not spring.configure(bad),"fractional step budget rejected")
	spring.configure(simulation())
	spring.reset(1,0)
	for i: int in range(120):
		spring.step(1.0/120.0)
	# x''+4x'+4x=0, x(0)=1, x'(0)=0 => (1+2t) exp(-2t).
	check(near(spring.angle_degrees,0.4060058497098381,0.00000001),"critical damping matches independent analytic x(1)")
	check(near(spring.velocity_degrees,-0.5413411329464508,0.00000001),"critical damping matches independent analytic velocity")
	var other: RefCounted = spring_script.new()
	other.configure(simulation()); other.reset(1,0)
	for i: int in range(60):
		other.step(1.0/60.0)
	check(near(spring.angle_degrees,other.angle_degrees,0.000000001),"fixed-step grouping produces same trajectory")
	other.configure(simulation(8,8,20,2)); other.reset(1,0)
	other.step(1)
	check(near(other.angle_degrees,0.4060058497098381,0.00000001),"mass is part of physical coefficients")
	for coefficients: Array in [[4,2],[4,6]]:
		spring.configure(simulation(coefficients[0],coefficients[1])); spring.reset(3,0)
		for i: int in range(600):
			spring.step(1.0/120.0)
		check(absf(spring.angle_degrees)<0.1,"under/over damped spring settles within five seconds / "+str(coefficients))
	spring.configure(simulation(32,10,3)); other.configure(simulation(32,10,3))
	spring.kick_degrees(0.5); other.kick_degrees(0.25)
	spring.step(0.25); other.step(0.25)
	check(near(spring.angle_degrees*0.5,other.angle_degrees,0.000000001),"reduced event half amplitude stays half throughout unbounded motion")
	spring.kick_degrees(100)
	check(near(spring.angle_degrees,3),"event kick respects configured angle limit")
	for i: int in range(60):
		spring.step(1.0/60.0,10000)
	check(absf(spring.angle_degrees)<=3 and spring.velocity_degrees<=0,"sustained outward torque cannot escape limit")
	var before: float = spring.angle_degrees
	spring.step(NAN); spring.step(-1); spring.kick_degrees(INF)
	check(spring.angle_degrees == before,"invalid motion inputs do not poison pose")
	spring.reset()
	check(near(spring.angle_degrees,0) and near(spring.velocity_degrees,0),"reset clears pose, velocity and accumulator")
	spring.step(0.001)
	check(near(spring.angle_degrees,0),"substep remainder alone cannot move a resting spring")
	for parameters: Dictionary in [settings.layer_defaults.pendulum,settings.shelf.pendulum]:
		var actual_parameters := parameters.duplicate(true)
		actual_parameters.merge(settings.spring,true)
		spring.configure(actual_parameters)
		spring.kick_degrees(float(parameters.max_angle_degrees))
		for i: int in range(600):
			spring.step(1.0/120.0)
		check(absf(spring.angle_degrees)<float(settings.limits.settle_degrees),"actual JSON pendulum settles within the configured five second criterion")

func persistence() -> void:
	var saved := ConfigFile.new()
	saved.set_value("audio","music",0.23)
	saved.set_value("audio","ui",0.7)
	saved.set_value("motion","reduced_motion",true)
	check(saved.save(PREFS_PATH) == OK,"real preference fixture is writable in isolated user directory")
	var wind := make_wind()
	check(wind.reduced_motion,"reduced preference is restored at ready")
	reduced_events.clear()
	wind.reduced_motion_changed.connect(func(value: bool): reduced_events.append(value))
	check(wind.set_reduced_motion(false),"successful preference save is accepted")
	var actual := ConfigFile.new()
	check(actual.load(PREFS_PATH) == OK and actual.get_value("motion","reduced_motion") == false,"successful write precedes published new preference")
	check(near(actual.get_value("audio","music"),0.23) and near(actual.get_value("audio","ui"),0.7),"motion preference write preserves both audio channels")
	check(reduced_events == [false],"successful changed preference emits exactly once")
	check(wind.set_reduced_motion(false) and reduced_events == [false],"unchanged preference does not emit again")
	var audio: Node = load("res://scripts/audio/shop_audio.gd").new()
	audio.config = audio.load_config()
	audio.settings_path = PREFS_PATH
	audio.volumes = audio.read_settings()
	check(audio.set_volume("music",0.42),"existing audio saver accepts shared settings fixture")
	actual.load(PREFS_PATH)
	check(actual.get_value("motion","reduced_motion") == false,"audio preference write preserves reduced motion")
	audio.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://a6_core_directory"))
	wind.settings_path = "user://a6_core_directory"
	check(not wind.set_reduced_motion(true),"directory destination fails actual ConfigFile save")
	check(not wind.reduced_motion and reduced_events == [false],"failed persistence changes neither preference nor signal")
	wind.free()
	saved.set_value("motion","reduced_motion","yes")
	saved.save(PREFS_PATH)
	wind = make_wind()
	check(not wind.reduced_motion,"invalid stored preference uses validated default")
	wind.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))

func finish() -> void:
	print("WIND/SPRING: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

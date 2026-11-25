extends SceneTree
## Synthetic in-memory fixture only; no Cozy Tunes audio is opened by this test.
const Audio = preload("res://scripts/audio/shop_audio.gd")
const Catalog = preload("res://scripts/audio/music_catalog.gd")
const Context = preload("res://scripts/audio/music_context.gd")
const Fixture = preload("res://tests/fixtures/music_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MUSIC RUNTIME FAIL: "+label)

func alive(handles: Array[WeakRef]) -> int:
	var count := 0
	for handle: WeakRef in handles:
		if handle.get_ref() != null:
			count += 1
	return count

func slot_for(page: String, clock: int, board: Dictionary, story: Dictionary, presentation: Dictionary, catalog: Dictionary) -> String:
	var projected := Context.project(page,clock,board,story,presentation)
	return Catalog.key_for(projected.page,projected.clock_minutes,catalog,projected.context)

func await_fade(audio: Node) -> void:
	# A first-frame timer may expire before a newly created Tween is stepped.
	# Observe completion, with the existing audio lifecycle deadline as failure bound.
	var deadline := Time.get_ticks_usec() + int(float(audio.config.shutdown_timeout_seconds)*1000000.0)
	while audio.fade != null and Time.get_ticks_usec() < deadline:
		await process_frame
	check(audio.fade == null,"fade actually completes before lifecycle deadline")

func run() -> void:
	var catalog := Catalog.load_data()
	check(not catalog.is_empty() and is_equal_approx(float(catalog.crossfade_seconds),1.5),"five-slot production duration comes from catalog")
	if catalog.is_empty():
		finish()
		return
	for web: bool in [false,true]:
		for public: bool in [false,true]:
			for with_music: bool in [false,true]:
				check(Audio.policy_allows_music(web,public,with_music) == (not public and (not web or with_music)),"public deny wins over withmusic")
	var complete := {"enabled":true,"ending":{"has_ending":true,"status":"complete","text":"已经披露的结局"}}
	var waiting := {"enabled":true,"ending":{"has_ending":true,"status":"waiting","text":"已经披露的等待"}}
	check(slot_for("front",540,{},complete,{},catalog)=="day","historic completion never implies currently visible ending")
	check(slot_for("ending",540,{},waiting,{"ending_visible":true},catalog)=="day","waiting ending is not ending music")
	check(slot_for("front",540,{},complete,{"ending_visible":true},catalog)=="ending","public complete plus actual visible UI selects ending")
	check(slot_for("front",540,{},complete,{"title_visible":true,"ending_visible":true},catalog)=="opening","actual title wins")
	check(slot_for("title",540,{},complete,{},catalog)=="day","page name does not invent a missing title flag")
	check(slot_for("front",540,{},complete,{"title_visible":"true"},catalog)=="day","malformed title flag fails closed")
	check(slot_for("consultation",540,{"enabled":true,"closed":false},{},{},catalog)=="deduction","active committed public board selects deduction")
	check(slot_for("consultation",540,{"enabled":true,"closed":true},{},{},catalog)=="day","closed board falls back to clock")
	check(slot_for("consultation",540,{"enabled":false},{},{},catalog)=="day","shopping/empty consultation is not an active case")
	check(Catalog.key_for("front",540,catalog,{"truth":{"ending":true}})=="","private/unknown context rejected by catalog")
	var audio: Node = Fixture.new()
	var settings := "res://.tools/music-runtime-test-"+str(Time.get_ticks_usec())+".cfg"
	audio.settings_path = settings
	root.add_child(audio)
	await process_frame
	# Keep the actual JSON contract above at 1.5; shorten only this isolated lifecycle fixture.
	audio.music_config.crossfade_seconds = 0.03
	check(audio.music_players.size()==2,"only two music nodes exist")
	audio.transition("front",540)
	var started: int = audio.active_player
	var generation: int = audio._voice_generations[started]
	var requests: int = audio.load_requests.size()
	var epoch: int = audio._transition_epoch
	audio.transition("front",540)
	check(audio.active_player==started and audio._voice_generations[started]==generation and audio.load_requests.size()==requests and audio._transition_epoch==epoch,"same slot never reloads/restarts/resets fade")
	audio.transition("consultation",540,{"case_active":true})
	var stale_epoch: int = audio._transition_epoch
	var stale_generations: Array[int] = audio._voice_generations.duplicate()
	check(audio.music_players.all(func(player:AudioStreamPlayer)->bool:return player.playing),"crossfade briefly overlaps both voices")
	audio.transition("front",540)
	audio._finish_music_fade(stale_epoch,stale_generations)
	check(audio.active_player==started and audio.music_players[started].playing and audio._voice_generations[started]==generation,"A-B-A reuses A and stale completion cannot stop it")
	await await_fade(audio)
	check(audio.music_players[started].playing and not audio.music_players[1-started].playing and audio.music_players[1-started].stream==null,"fade retires only the old voice and releases its resource")
	for route: Dictionary in [
		{"page":"title","clock":540,"context":{}},
		{"page":"front","clock":1080,"context":{}},
		{"page":"consultation","clock":540,"context":{"case_active":true}},
		{"page":"front","clock":540,"context":{"ending_visible":true}}
	]:
		audio.transition(route.page,int(route.clock),route.context)
		check(audio.current_music==Catalog.key_for(route.page,int(route.clock),catalog,route.context),"runtime routes selected slot / "+audio.current_music)
	check(audio.music_players.size()==2,"rapid changes never allocate more voices")
	var deduction_path: String = Catalog.track_for_slot("deduction",catalog).runtime_path
	audio.missing_paths.append(deduction_path)
	audio._stop_music()
	audio.transition("consultation",540,{"case_active":true})
	check(audio.active_player==-1,"missing selected runtime does not start a fallback track")
	stale_epoch = audio._transition_epoch
	stale_generations = audio._voice_generations.duplicate()
	audio.transition("front",1080)
	audio._finish_music_fade(stale_epoch,stale_generations)
	check(audio.active_player>=0 and audio.music_players[audio.active_player].playing,"canceled missing-track fade cannot stop a newer voice")
	var ui_bus := AudioServer.get_bus_index("UI")
	var ui_db := AudioServer.get_bus_volume_db(ui_bus)
	var ui_mute := AudioServer.is_bus_mute(ui_bus)
	check(audio.set_volume("music",0.25),"existing independent music preference persists")
	check(is_equal_approx(AudioServer.get_bus_volume_db(ui_bus),ui_db) and AudioServer.is_bus_mute(ui_bus)==ui_mute,"music setting leaves SFX bus untouched")
	check(is_equal_approx(float(audio.read_settings().music),0.25),"existing presentation.cfg music setting reloads")
	requests = audio.load_requests.size()
	audio.fixture_music_allowed = false
	audio.transition("front",540)
	await await_fade(audio)
	check(audio.load_requests.size()==requests and audio.music_players.all(func(player:AudioStreamPlayer)->bool:return not player.playing and player.stream==null),"public policy never asks loader and retires current music")
	var handles: Array[WeakRef] = audio.playback_handles()
	check(await audio.shutdown_async(),"shutdown observes actual synthetic playback release")
	check(alive(handles)==0 and audio.fade==null,"shutdown retains no playback handle or fade")
	audio.transition("title",540)
	check(audio.music_players.all(func(player:AudioStreamPlayer)->bool:return not player.playing),"shutdown prevents future playback")
	check(await audio.shutdown_async(),"shutdown is idempotent")
	var released: WeakRef = weakref(audio)
	audio.queue_free()
	audio = null
	await process_frame
	check(released.get_ref()==null,"controller and children are freed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings))
	finish()

func finish() -> void:
	print("MUSIC RUNTIME: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

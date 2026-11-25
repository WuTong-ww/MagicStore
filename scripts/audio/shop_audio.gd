extends Node
## UNRUN R3-MUSIC runtime draft.
## Presentation preferences are deliberately separate from GameState and saves.
const MusicCatalog = preload("res://scripts/audio/music_catalog.gd")
const CONFIG_PATH := "res://data/ui/audio.json"
var config: Dictionary = {}
var settings_path := ""
var volumes: Dictionary = {}
var current_music := ""
var music_config: Dictionary = {}
var _requested_path := ""
var _requested_allowed := false
var _transition_epoch := 0
var _voice_generations: Array[int] = []
var _voice_paths: Array[String] = []
var music_players: Array[AudioStreamPlayer] = []
var ui_players: Array[AudioStreamPlayer] = []
var active_player := -1
var next_voice := 0
var fade: Tween
var _shutting_down := false
var _playbacks: Array[WeakRef] = []

static func config_valid(data: Dictionary) -> bool:
	if data.get("version") != 1:
		return false
	for key: String in ["day_minute", "night_minute", "minutes_per_day", "crossfade_seconds", "ui_voices", "shutdown_timeout_seconds", "shutdown_poll_frames"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value <= 0:
			return false
	if not (data.day_minute < data.night_minute and data.night_minute < data.minutes_per_day) or data.ui_voices != floor(float(data.ui_voices)):
		return false
	if data.shutdown_poll_frames != floor(float(data.shutdown_poll_frames)):
		return false
	if not data.get("silence_db") is float and not data.get("silence_db") is int:
		return false
	if not is_finite(float(data.silence_db)) or data.silence_db >= 0 or not str(data.get("settings_path", "")).begins_with("user://"):
		return false
	for group: String in ["defaults", "labels", "tracks", "sounds"]:
		if not data.get(group) is Dictionary:
			return false
	for key: String in ["music", "ui"]:
		if not _valid_volume(data.defaults.get(key)) or not data.labels.get(key) is String or data.labels[key].is_empty():
			return false
	for key: String in ["shutdown_failed","close_failed"]:
		if not data.labels.get(key) is String or data.labels[key].is_empty():
			return false
	for key: String in ["day", "night", "consultation"]:
		var row: Variant = data.tracks.get(key)
		if not row is Dictionary or not row.get("path") is String:
			return false
		if not row.path.is_empty() and not _audio_path(row.path):
			return false
		if row.path.is_empty() and row.get("status") != "missing":
			return false
	for key: String in ["click", "page", "confirm", "cancel", "coin", "notify"]:
		if not _audio_path(data.sounds.get(key)):
			return false
	if data.sounds.has("entry_chime") and not _audio_path(data.sounds.entry_chime):
		return false
	return true

static func _valid_volume(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 1

static func _audio_path(value: Variant) -> bool:
	return value is String and value.begins_with("res://assets/audio/") and value.ends_with(".ogg")

static func load_config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return parsed if parsed is Dictionary and config_valid(parsed) else {}

static func music_key(data: Dictionary, page: String, clock_minutes: int) -> String:
	if page == "consultation":
		return "consultation"
	var minute := posmod(clock_minutes, int(data.minutes_per_day))
	return "day" if minute >= data.day_minute and minute < data.night_minute else "night"

func _ready() -> void:
	config = load_config()
	music_config = MusicCatalog.load_data()
	if config.is_empty():
		return
	if settings_path.is_empty():
		settings_path = config.settings_path
	volumes = read_settings()
	for bus: String in ["Music", "UI"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	_apply_volume()
	for index: int in range(2):
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = float(config.silence_db)
		add_child(player)
		music_players.append(player)
		_voice_generations.append(0)
		_voice_paths.append("")
	for index: int in range(int(config.ui_voices)):
		var player := AudioStreamPlayer.new()
		player.bus = "UI"
		add_child(player)
		ui_players.append(player)

func read_settings() -> Dictionary:
	var data := ConfigFile.new()
	var defaults: Dictionary = config.get("defaults", {})
	var result := defaults.duplicate(true)
	if data.load(settings_path) == OK:
		for key: String in ["music", "ui"]:
			var value: Variant = data.get_value("audio", key, defaults.get(key))
			if _valid_volume(value):
				result[key] = float(value)
	return result

func set_volume(channel: String, value: float) -> bool:
	if not channel in volumes or not _valid_volume(value):
		return false
	var data := ConfigFile.new()
	# Preserve other presentation settings such as reduced motion.
	data.load(settings_path)
	for key: String in volumes:
		data.set_value("audio", key, value if key == channel else volumes[key])
	if data.save(settings_path) != OK:
		return false
	volumes[channel] = value
	_apply_volume(channel)
	return true

func _apply_volume(channel: String = "") -> void:
	for row: Array in [["music", "Music"], ["ui", "UI"]]:
		if not channel.is_empty() and row[0] != channel:
			continue
		var index := AudioServer.get_bus_index(row[1])
		if index >= 0:
			var value := float(volumes.get(row[0], 0.0))
			AudioServer.set_bus_mute(index, is_zero_approx(value))
			AudioServer.set_bus_volume_db(index, linear_to_db(value) if value > 0 else float(config.silence_db))

## UNRUN fragment for ShopAudio. Missing/forbidden assets never reach ResourceLoader.load.
static func policy_allows_music(is_web: bool, is_public: bool, with_music: bool) -> bool:
	if is_public:
		return false
	return not is_web or with_music

func _runtime_music_allowed() -> bool:
	# Public feature wins even if a mistaken export also includes withmusic.
	return policy_allows_music(OS.has_feature("web"),OS.has_feature("webpublic"),OS.has_feature("withmusic"))

func _load_music_stream(path: String) -> AudioStream:
	if not _runtime_music_allowed() or path.is_empty() or not ResourceLoader.exists(path,"AudioStream"):
		return null
	var source := ResourceLoader.load(path,"AudioStream") as AudioStream
	if source == null:
		return null
	# Mutate only this voice's private resource, never the import cache.
	var stream := source.duplicate() as AudioStream
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	return stream

func transition(page: String, clock_minutes: int, public_context: Dictionary = {}) -> void:
	if _shutting_down or config.is_empty() or music_players.is_empty():
		return
	var key := MusicCatalog.key_for(page,clock_minutes,music_config,public_context)
	var track := MusicCatalog.track_for_slot(key,music_config)
	var allowed := _runtime_music_allowed()
	var path: String = str(track.get("runtime_path","")) if allowed else ""
	if key == current_music and path == _requested_path and allowed == _requested_allowed:
		return
	current_music = key
	_requested_path = path
	_requested_allowed = allowed
	_invalidate_music_fade()
	var epoch := _transition_epoch
	var next := -1
	# A -> B -> A reuses the still-live A voice at its current gain.
	if allowed and not path.is_empty():
		for index: int in range(music_players.size()):
			if _voice_paths[index] == path and music_players[index].playing:
				next = index
				break
		if next < 0:
			var stream := _load_music_stream(path)
			if stream != null:
				next = (active_player + 1) % music_players.size()
				_release_music_voice(next)
				var player: AudioStreamPlayer = music_players[next]
				_voice_paths[next] = path
				player.stream = stream
				player.volume_db = float(config.silence_db)
				player.play()
				_remember_playback(player)
	active_player = next
	# Invalid/missing catalog is immediate silence: no guessed music defaults.
	if music_config.is_empty():
		for index: int in range(music_players.size()):
			_release_music_voice(index)
		return
	var seconds := float(music_config.crossfade_seconds)
	fade = create_tween().set_parallel(true)
	for index: int in range(music_players.size()):
		var player: AudioStreamPlayer = music_players[index]
		fade.tween_property(player,"volume_db",0.0 if index == next else float(config.silence_db),seconds)
	var generations: Array[int] = _voice_generations.duplicate()
	fade.finished.connect(_finish_music_fade.bind(epoch,generations),CONNECT_ONE_SHOT)

func _invalidate_music_fade() -> void:
	_transition_epoch += 1
	if fade != null and fade.is_valid():
		fade.kill()
	fade = null

func _release_music_voice(index: int) -> void:
	var player: AudioStreamPlayer = music_players[index]
	_remember_playback(player)
	player.stop()
	player.stream = null
	player.volume_db = float(config.silence_db)
	_voice_paths[index] = ""
	_voice_generations[index] += 1

func _finish_music_fade(epoch: int, generations: Array[int]) -> void:
	if _shutting_down or epoch != _transition_epoch:
		return
	for index: int in range(music_players.size()):
		if index != active_player and generations[index] == _voice_generations[index]:
			_release_music_voice(index)
	fade = null

func _stop_music() -> void:
	_invalidate_music_fade()
	for index: int in range(music_players.size()):
		_release_music_voice(index)
	active_player = -1
	current_music = ""
	_requested_path = ""

func _exit_tree() -> void:
	_stop_players()

func _remember_playback(player: AudioStreamPlayer) -> void:
	# Also retain weak observations of voices recycled earlier in this scene.
	# AudioServer can still own those handles after the player drops its Ref.
	_playbacks = _playbacks.filter(func(handle: WeakRef) -> bool: return handle.get_ref() != null)
	if player.has_stream_playback():
		_playbacks.append(weakref(player.get_stream_playback()))

func playback_handles() -> Array[WeakRef]:
	return _playbacks.duplicate()

func _stop_players() -> void:
	_shutting_down = true
	_invalidate_music_fade()
	for index: int in range(music_players.size()):
		_release_music_voice(index)
	for player: AudioStreamPlayer in ui_players:
		_remember_playback(player)
		player.stop()
		player.stream = null
	active_player = -1
	_requested_path = ""

func _pending_playbacks() -> int:
	# Do not hold a playback Ref in the suspended coroutine's locals. This
	# synchronous helper releases get_ref() temporaries before the next await.
	var count := 0
	for handle: WeakRef in _playbacks:
		if handle.get_ref() != null:
			count += 1
	return count

func shutdown_async() -> bool:
	_stop_players()
	if config.is_empty():
		return _pending_playbacks() == 0
	var deadline := Time.get_ticks_usec() + int(float(config.shutdown_timeout_seconds) * 1000000.0)
	while _pending_playbacks() > 0 and Time.get_ticks_usec() < deadline:
		for frame: int in range(int(config.shutdown_poll_frames)):
			await get_tree().process_frame
	# Time is only a failure bound. Success requires observed mixer release.
	return _pending_playbacks() == 0

func play_ui(key: String = "click") -> void:
	if _shutting_down or config.is_empty() or ui_players.is_empty() or not config.sounds.has(key):
		return
	var path: String = config.sounds[key]
	if not ResourceLoader.exists(path):
		return
	var player: AudioStreamPlayer = ui_players[next_voice]
	next_voice = (next_voice + 1) % ui_players.size()
	player.stream = load(path)
	player.play()
	_remember_playback(player)

func add_settings_controls(parent: VBoxContainer) -> void:
	for channel: String in ["music", "ui"]:
		var row := HBoxContainer.new()
		parent.add_child(row)
		var label := Label.new()
		label.text = config.labels[channel]
		row.add_child(label)
		var slider := HSlider.new()
		slider.name = "Volume_" + channel
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = float(volumes[channel])
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		slider.value_changed.connect(func(value: float):
			if not set_volume(channel, value):
				slider.set_value_no_signal(float(volumes[channel])))

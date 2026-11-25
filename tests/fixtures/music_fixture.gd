extends "res://scripts/audio/shop_audio.gd"
## Synthetic in-memory silence. Does not open any .ogg file or touch real music.
var load_requests: Array[String] = []
var missing_paths: Array[String] = []
var fixture_music_allowed := true

func _runtime_music_allowed() -> bool:
	return fixture_music_allowed

func _load_music_stream(path: String) -> AudioStream:
	load_requests.append(path)
	if path in missing_paths:
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = 8000
	var samples := PackedByteArray()
	samples.resize(16000)
	samples.fill(0)
	stream.data = samples
	return stream

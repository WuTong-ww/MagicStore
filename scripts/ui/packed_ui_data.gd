extends RefCounted
## Web PCK data is immutable. Never cache mutable save data or native development files.
const Runtime = preload("res://scripts/ui/performance_config.gd")
static var _documents: Dictionary = {}
static func read(path: String, validator: Callable, immutable_pack: bool) -> Dictionary:
	if immutable_pack and _documents.has(path): return _documents[path].duplicate(true)
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or not validator.call(value): return {}
	if immutable_pack: _documents[path] = value.duplicate(true)
	return value
static func load_web(path: String, validator: Callable) -> Dictionary:
	return read(path,validator,Runtime.active("cache_static_data"))

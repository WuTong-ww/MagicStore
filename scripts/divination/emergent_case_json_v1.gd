extends RefCounted
## Leaf RFC-8259 grammar gate. No permissive duplicate/trailing-comma parsing.
## Protocol v1 uses exact integer tokens; finite fractional JSON stays a float.
var _text := ""
var _at := 0
var _depth_limit := 0
var _error := ""
var _number_pattern: RegEx

func parse(text: Variant, maximum_bytes: int, maximum_depth: int) -> Dictionary:
	if not text is String or text.to_utf8_buffer().size()>maximum_bytes or maximum_depth<0:
		return {"success":false,"error_code":"JSON_INPUT_LIMIT"}
	_text = text
	_at = 0
	_depth_limit = maximum_depth
	_error = ""
	_number_pattern = RegEx.create_from_string("^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")
	var value: Variant = _value(0)
	_space()
	if _error.is_empty() and _at!=_text.length():
		_error = "JSON_TRAILING_INPUT"
	return {"success":true,"value":value} if _error.is_empty() else {"success":false,"error_code":_error}

func read(path: String, maximum_bytes: int, maximum_depth: int) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>maximum_bytes:
		return {"success":false,"error_code":"JSON_FILE_UNAVAILABLE"}
	var text := file.get_as_text().trim_prefix(String.chr(0xfeff))
	file.close()
	return parse(text,maximum_bytes,maximum_depth)

func _space() -> void:
	while _at<_text.length() and _text[_at] in [" ","\t","\r","\n"]:
		_at += 1

func _take(character: String) -> bool:
	_space()
	if _at>=_text.length() or _text[_at]!=character:
		_error = "JSON_GRAMMAR"
		return false
	_at += 1
	return true

func _value(depth: int) -> Variant:
	_space()
	if depth>_depth_limit or _at>=_text.length():
		_error = "JSON_DEPTH_OR_TRUNCATION"
		return null
	var first := _text[_at]
	if first=="{":
		return _object(depth+1)
	if first=="[":
		return _array(depth+1)
	if first=="\"":
		return _string()
	for literal: String in ["true","false","null"]:
		if _text.substr(_at,literal.length())==literal:
			_at += literal.length()
			return true if literal=="true" else false if literal=="false" else null
	var number := _number_pattern.search(_text.substr(_at))
	if number==null:
		_error = "JSON_VALUE"
		return null
	var token := number.get_string()
	_at += token.length()
	if token.contains(".") or token.to_lower().contains("e"):
		var decimal := token.to_float()
		if not is_finite(decimal):
			_error = "JSON_NONFINITE"
		return decimal
	# Integers beyond exact JSON interoperability are irrelevant to this protocol.
	if token.length()>17:
		_error = "JSON_INTEGER_RANGE"
		return null
	var integer := token.to_int()
	if absi(integer)>9007199254740991:
		_error = "JSON_INTEGER_RANGE"
	return integer

func _string() -> String:
	var start := _at
	_at += 1
	while _at<_text.length():
		var character := _text[_at]
		if _text.unicode_at(_at)<32:
			_error = "JSON_STRING_CONTROL"
			return ""
		_at += 1
		if character=="\"":
			var decoded: Variant = JSON.parse_string(_text.substr(start,_at-start))
			if not decoded is String:
				_error = "JSON_STRING"
				return ""
			return decoded
		if character=="\\":
			if _at>=_text.length():
				break
			var escape := _text[_at]
			_at += 1
			if escape=="u":
				if _at+4>_text.length():
					break
				for offset: int in range(4):
					if _text[_at+offset].to_lower() not in "0123456789abcdef":
						_error = "JSON_UNICODE_ESCAPE"
						return ""
				var code := _text.substr(_at,4).hex_to_int()
				_at += 4
				if code>=0xd800 and code<=0xdbff:
					if _at+6>_text.length() or _text.substr(_at,2)!="\\u":
						_error = "JSON_SURROGATE"
						return ""
					var low_text := _text.substr(_at+2,4)
					if not low_text.is_valid_hex_number(false) or low_text.hex_to_int()<0xdc00 or low_text.hex_to_int()>0xdfff:
						_error = "JSON_SURROGATE"
						return ""
					_at += 6
				elif code>=0xdc00 and code<=0xdfff:
					_error = "JSON_SURROGATE"
					return ""
			elif escape not in ["\"","\\","/","b","f","n","r","t"]:
				_error = "JSON_ESCAPE"
				return ""
	_error = "JSON_STRING_TRUNCATED"
	return ""

func _object(depth: int) -> Dictionary:
	_at += 1
	_space()
	var result := {}
	if _at<_text.length() and _text[_at]=="}":
		_at += 1
		return result
	while _error.is_empty():
		_space()
		if _at>=_text.length() or _text[_at]!="\"":
			_error = "JSON_OBJECT_KEY"
			break
		var key := _string()
		if result.has(key):
			_error = "JSON_DUPLICATE_KEY"
			break
		if not _error.is_empty() or not _take(":"):
			break
		result[key] = _value(depth)
		_space()
		if not _error.is_empty():
			break
		if _at<_text.length() and _text[_at]=="}":
			_at += 1
			return result
		if not _take(","):
			break
	return {}

func _array(depth: int) -> Array:
	_at += 1
	_space()
	var result := []
	if _at<_text.length() and _text[_at]=="]":
		_at += 1
		return result
	while _error.is_empty():
		result.append(_value(depth))
		_space()
		if not _error.is_empty():
			break
		if _at<_text.length() and _text[_at]=="]":
			_at += 1
			return result
		if not _take(","):
			break
	return []

static func canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		if not keys.all(func(key:Variant)->bool:return key is String):
			return ""
		keys.sort()
		var parts: PackedStringArray = []
		for key: String in keys:
			var encoded := canonical(value[key])
			if encoded.is_empty():
				return ""
			parts.append(JSON.stringify(key)+":"+encoded)
		return "{"+",".join(parts)+"}"
	if value is Array:
		var parts: PackedStringArray = []
		for item: Variant in value:
			var encoded := canonical(item)
			if encoded.is_empty():
				return ""
			parts.append(encoded)
		return "["+",".join(parts)+"]"
	if value==null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is int:
		return str(value)
	if value is String:
		return JSON.stringify(value)
	return ""

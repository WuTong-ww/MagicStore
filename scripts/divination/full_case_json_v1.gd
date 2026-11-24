extends RefCounted
## Leaf RFC-8259 grammar gate. No permissive duplicate/trailing-comma parsing.
## Whole finite JSON numbers normalize to int; fractional/non-JSON data refuses.
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
	var exact := integer_token(token)
	if not exact.get("success",false):
		_error = str(exact.get("error_code","JSON_INTEGER_TOKEN"))
		return null
	return exact.value

static func _strip_leading_zeroes(text: String) -> String:
	var index := 0
	while index<text.length() and text.unicode_at(index)==48:
		index += 1
	return text.substr(index)

## Decide mathematical integrality from decimal digits, before binary float.
## All exponent conversion is bounded by token length; result conversion only
## happens after its lexical absolute value is within the exact JSON range.
static func integer_token(token: String) -> Dictionary:
	var pattern := RegEx.create_from_string("^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$")
	var match_result := pattern.search(token)
	if match_result==null or match_result.get_start()!=0 or match_result.get_end()!=token.length():
		return {"success":false,"error_code":"JSON_NUMBER_GRAMMAR"}
	var negative: bool = token.begins_with("-")
	var parts: PackedStringArray = token.trim_prefix("-").to_lower().split("e")
	var mantissa: String = parts[0]
	var dot: int = mantissa.find(".")
	var fraction: int = mantissa.length()-dot-1 if dot>=0 else 0
	var digits: String = _strip_leading_zeroes(mantissa.replace(".",""))
	if digits.is_empty():
		return {"success":true,"value":0}
	var end: int = digits.length()
	while end>0 and digits.unicode_at(end-1)==48:
		end -= 1
	var trailing: int = digits.length()-end
	var coefficient: String = digits.substr(0,end)
	var exponent_text: String = parts[1] if parts.size()==2 else "0"
	var exponent_negative: bool = exponent_text.begins_with("-")
	var exponent_digits: String = _strip_leading_zeroes(exponent_text.trim_prefix("-").trim_prefix("+"))
	if exponent_digits.is_empty():
		exponent_digits = "0"
	var limit := "9007199254740991"
	var bound: String = str(token.length()+limit.length())
	if exponent_digits.length()>bound.length() or (exponent_digits.length()==bound.length() and exponent_digits>bound):
		return {"success":false,"error_code":"JSON_FRACTIONAL_TOKEN" if exponent_negative else "JSON_INTEGER_RANGE"}
	var exponent: int = exponent_digits.to_int()*(-1 if exponent_negative else 1)
	var shift: int = exponent-fraction+trailing
	if shift<0:
		return {"success":false,"error_code":"JSON_FRACTIONAL_TOKEN"}
	var size: int = coefficient.length()+shift
	if size>limit.length():
		return {"success":false,"error_code":"JSON_INTEGER_RANGE"}
	var exact: String = coefficient+"0".repeat(shift)
	if size==limit.length() and exact>limit:
		return {"success":false,"error_code":"JSON_INTEGER_RANGE"}
	return {"success":true,"value":exact.to_int()*(-1 if negative else 1)}

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
			parts.append(_quote(key)+":"+encoded)
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
		return _quote(value)
	return ""

## Reject Object/Callable/vector/dictionary keys and bound recursive containers.
static func normalize(value: Variant, maximum_depth: int, depth: int = 0) -> Dictionary:
	if depth>maximum_depth:
		return {"success":false}
	if value==null or value is bool:
		return {"success":true,"value":value}
	if value is int:
		return {"success":true,"value":value} if absi(value)<=9007199254740991 else {"success":false}
	if value is float:
		return {"success":true,"value":int(value)} if is_finite(value) and value==floor(value) and absf(value)<=9007199254740991.0 else {"success":false}
	if value is String:
		for i: int in range(value.length()):
			if value.unicode_at(i)>=0xd800 and value.unicode_at(i)<=0xdfff:
				return {"success":false}
		return {"success":true,"value":value}
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			var normalized := normalize(item,maximum_depth,depth+1)
			if not normalized.get("success",false):
				return {"success":false}
			result.append(normalized.value)
		return {"success":true,"value":result}
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			if not key is String:
				return {"success":false}
			var normalized := normalize(value[key],maximum_depth,depth+1)
			if not normalized.get("success",false):
				return {"success":false}
			result[key] = normalized.value
		return {"success":true,"value":result}
	return {"success":false}

static func _quote(value: String) -> String:
	var text := "\""
	for i: int in range(value.length()):
		var code: int = value.unicode_at(i)
		match code:
			34: text += "\\\""
			92: text += "\\\\"
			8: text += "\\b"
			9: text += "\\t"
			10: text += "\\n"
			12: text += "\\f"
			13: text += "\\r"
			_:
				text += ("\\u%04x" % code) if code<32 else String.chr(code)
	return text+"\""

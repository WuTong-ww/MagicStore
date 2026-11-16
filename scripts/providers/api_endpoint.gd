extends RefCounted
## Pure URL parsing. API normalization never probes a server or changes protocol.

const MAX_URL_LENGTH := 2048

static func normalize_chat_url(raw: String) -> Dictionary:
	if raw.length() > MAX_URL_LENGTH:
		return _failure("接口地址不能超过 2048 个字符。")
	# Outer ordinary spaces and Markdown escape slashes are copy formatting.
	# Other whitespace/control characters are rejected rather than hidden.
	var value := raw.trim_prefix(" ").trim_suffix(" ")
	while value.begins_with(" ") or value.ends_with(" "):
		value = value.trim_prefix(" ").trim_suffix(" ")
	if value.is_empty():
		return {"success":true,"url":"","message":""}
	var separator := value.find("://")
	if separator >= 0:
		var prefix := value.left(separator)
		while prefix.ends_with("\\"):
			prefix = prefix.trim_suffix("\\")
		if prefix.to_lower() in ["http","https"]:
			value = prefix + value.substr(separator)
	while value.ends_with("\\") or value.ends_with("/"):
		value = value.left(value.length()-1)
	var parsed := _parse_http_url(value)
	if not parsed.success:
		return _failure(parsed.message)
	var path: String = parsed.path
	if path.is_empty():
		path = "/v1/chat/completions"
	elif path.ends_with("/chat/completions"):
		pass
	elif path.ends_with("/v1/chat"):
		path += "/completions"
	elif path.ends_with("/v1"):
		path += "/chat/completions"
	else:
		return _failure("请填写根地址、以 /v1 或 /v1/chat 结尾的地址，或完整的 /chat/completions 接口。")
	var url: String = parsed.origin + path
	if url.length() > MAX_URL_LENGTH:
		return _failure("补全后的接口地址不能超过 2048 个字符。")
	return {"success":true,"url":url,"message":""}

## Transport validation also accepts existing gateway/custom paths. It does not
## append an endpoint, trim formatting, downgrade HTTPS or access the network.
static func http_url_valid(url: String) -> bool:
	return bool(_parse_http_url(url).success)

static func _parse_http_url(url: String) -> Dictionary:
	if url.is_empty() or url.length() > MAX_URL_LENGTH:
		return _failure("HTTP 地址需为 1–2048 个字符。")
	for index: int in url.length():
		var code := url.unicode_at(index)
		if code <= 32 or (code >= 127 and code <= 160) or code in [0x1680,0x180e,0x2028,0x2029,0x202f,0x205f,0x3000,0xfeff] or (code >= 0x2000 and code <= 0x200f) or (code >= 0x202a and code <= 0x202e) or (code >= 0x2060 and code <= 0x206f):
			return _failure("地址中不能包含空白或控制字符。")
	for marker: String in ["@","?","#","\\","\"","<",">","{","}","|","^","`"]:
		if url.contains(marker):
			return _failure("地址不能包含账号、查询参数、片段或未转义的特殊字符。")
	var separator := url.find("://")
	if separator < 0:
		return _failure("地址需以 http:// 或 https:// 开头。")
	var scheme := url.left(separator).to_lower()
	if scheme not in ["http","https"]:
		return _failure("接口地址仅支持 HTTP 或 HTTPS。")
	var remainder := url.substr(separator+3)
	var slash := remainder.find("/")
	var authority := remainder if slash < 0 else remainder.left(slash)
	var path := "" if slash < 0 else remainder.substr(slash)
	for index: int in path.length():
		if path[index] == "%" and (index+2 >= path.length() or not _hex_digit(path.unicode_at(index+1)) or not _hex_digit(path.unicode_at(index+2))):
			return _failure("地址中的百分号需要有效的两位十六进制转义。")
	if authority.is_empty():
		return _failure("请填写有效的主机名或 IP 地址。")
	var host := ""
	var port := ""
	if authority.begins_with("["):
		var closing := authority.find("]")
		if closing < 0:
			return _failure("IPv6 地址需要完整的方括号。")
		var address := authority.substr(1,closing-1)
		if not address.contains(":") or not address.is_valid_ip_address():
			return _failure("方括号中需要有效的 IPv6 地址。")
		host = "[" + address.to_lower() + "]"
		var suffix := authority.substr(closing+1)
		if not suffix.is_empty():
			if not suffix.begins_with(":"):
				return _failure("IPv6 地址的方括号后只能跟端口。")
			port = suffix.substr(1)
			if not _valid_port(port):
				return _failure("端口必须是 1–65535 的整数。")
	elif authority.contains("[") or authority.contains("]"):
		return _failure("IPv6 地址需要放在方括号中。")
	else:
		var colon := authority.find(":")
		host = authority if colon < 0 else authority.left(colon)
		if colon >= 0:
			port = authority.substr(colon+1)
			if not _valid_port(port):
				return _failure("端口必须是 1–65535 的整数，IPv6 地址需使用方括号。")
		if not _valid_host(host):
			return _failure("请填写有效的域名、IPv4 地址或带方括号的 IPv6 地址。")
		host = host.to_lower()
	if not port.is_empty():
		port = ":" + str(port.to_int())
	var origin := scheme + "://" + host + port
	return {"success":true,"url":origin+path,"origin":origin,"path":path,"message":""}

static func _valid_port(port: String) -> bool:
	if port.is_empty():
		return false
	for index: int in port.length():
		if port.unicode_at(index) < 48 or port.unicode_at(index) > 57:
			return false
	var significant := port
	while significant.begins_with("0") and significant.length() > 1:
		significant = significant.substr(1)
	return significant.length() <= 5 and significant.to_int() >= 1 and significant.to_int() <= 65535

static func _hex_digit(code: int) -> bool:
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 70) or (code >= 97 and code <= 102)

static func _valid_host(host: String) -> bool:
	if host.is_empty():
		return false
	var numeric := true
	for index: int in host.length():
		if host[index] != "." and (host.unicode_at(index) < 48 or host.unicode_at(index) > 57):
			numeric = false
			break
	if numeric:
		var parts := host.split(".",true)
		if parts.size() != 4:
			return false
		for part: String in parts:
			if part.is_empty() or part.length() > 3 or part.to_int() > 255:
				return false
		return true
	var domain := host.trim_suffix(".")
	if domain.is_empty() or domain.length() > 253:
		return false
	for label: String in domain.split(".",true):
		if label.is_empty() or label.length() > 63 or label.begins_with("-") or label.ends_with("-"):
			return false
		for index: int in label.length():
			var code := label.unicode_at(index)
			if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45):
				return false
	return true

static func _failure(message: String) -> Dictionary:
	return {"success":false,"url":"","message":message}

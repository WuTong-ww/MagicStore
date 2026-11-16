extends SceneTree
## Pure local URL parsing: no HTTP request, DNS lookup, API key or saved game.

const Endpoint = preload("res://scripts/providers/api_endpoint.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var valid := {
		"":"", "   ":"",
		"https://token.pjlab.org.cn":"https://token.pjlab.org.cn/v1/chat/completions",
		"http://api.test/":"http://api.test/v1/chat/completions",
		"HTTPS://API.Example.TEST/v1/":"https://api.example.test/v1/chat/completions",
		"https://api.test/v1":"https://api.test/v1/chat/completions",
		"https://api.test/v1/chat":"https://api.test/v1/chat/completions",
		"https://api.test/v1/chat/":"https://api.test/v1/chat/completions",
		"https://api.test/v1/chat/completions":"https://api.test/v1/chat/completions",
		"https://api.test/custom/chat/completions/":"https://api.test/custom/chat/completions",
		"https://api.test/chat/completions":"https://api.test/chat/completions",
		"https://api.test/api/v1":"https://api.test/api/v1/chat/completions",
		"https://api.test/proxy/team/v1/":"https://api.test/proxy/team/v1/chat/completions",
		"https://api.test/proxy/team/v1/chat":"https://api.test/proxy/team/v1/chat/completions",
		"https://api.test/API/Custom/chat/completions":"https://api.test/API/Custom/chat/completions",
		"https\\://TOKEN.PJLAB.ORG.CN/v1/chat/completions\\":"https://token.pjlab.org.cn/v1/chat/completions",
		"  HTTP\\://LOCALHOST:8080/v1\\  ":"http://localhost:8080/v1/chat/completions",
		"https://api.test/v1/chat/completions/\\///":"https://api.test/v1/chat/completions",
		"http://127.0.0.1:8765":"http://127.0.0.1:8765/v1/chat/completions",
		"http://192.168.10.22:1/v1":"http://192.168.10.22:1/v1/chat/completions",
		"http://10.0.0.12:65535/api/v1":"http://10.0.0.12:65535/api/v1/chat/completions",
		"http://0.0.0.0":"http://0.0.0.0/v1/chat/completions",
		"http://255.255.255.255":"http://255.255.255.255/v1/chat/completions",
		"http://LOCALHOST:00080/v1":"http://localhost:80/v1/chat/completions",
		"http://dev-box":"http://dev-box/v1/chat/completions",
		"https://xn--fiqs8s.example/v1":"https://xn--fiqs8s.example/v1/chat/completions",
		"https://api.example.test./v1":"https://api.example.test./v1/chat/completions",
		"http://[::1]:8765/v1":"http://[::1]:8765/v1/chat/completions",
		"HTTPS://[2001:DB8::ABCD]/v1/chat":"https://[2001:db8::abcd]/v1/chat/completions",
		"http://[::]/":"http://[::]/v1/chat/completions",
		"http://[::ffff:192.168.1.2]:8080/custom/chat/completions":"http://[::ffff:192.168.1.2]:8080/custom/chat/completions",
		"https://api.test/proxy%20name/v1":"https://api.test/proxy%20name/v1/chat/completions"
	}
	for raw: String in valid:
		var result: Dictionary = Endpoint.normalize_chat_url(raw)
		check(result.size() == 3 and result.get("success",false) and result.get("url") == valid[raw] and result.get("message") == "", "canonical known endpoint / " + raw)
	var invalid := [
		"ftp://api.test/v1", "file://api.test/v1", "//api.test/v1", "api.test/v1", "https:/api.test/v1", "https://",
		"https:///v1", "https://:443/v1", "http://api.test:0/v1", "http://api.test:65536/v1", "http://api.test:-1/v1",
		"http://api.test:+80/v1", "http://api.test:port/v1", "http://api.test:/v1", "http://api.test:80:90/v1",
		"https://user@api.test/v1", "https://user:password@api.test/v1", "https://api.test/a@b/chat/completions",
		"https://api.test/v1?key=secret", "https://api.test/v1#anchor", "https://api.test/v1?", "https://api.test/v1#",
		"https://api.test/a\\b/v1", "https://api.test/a b/v1", "https://api.test/\t/v1", "https://api.test/v1\n",
		"\thttps://api.test/v1", "https://api.test/v1\r", "https://api.test/\u200b/v1", "https://api.test/\u202e/v1",
		"https://api.test/\u00a0/v1", "https://api.test/\u3000/v1", "https://api.test/<script>/v1", "https://api.test/\"x\"/v1",
		"https://256.0.0.1/v1", "https://1.2.3.999/v1", "https://1.2.3/v1", "https://127.1/v1", "https://2130706433/v1",
		"https://1..2.3/v1", "https://1.2.3.4.5/v1", "https://api..test/v1", "https://-api.test/v1", "https://api-.test/v1",
		"https://.api.test/v1", "https://api.test../v1", "https://exa_mple.test/v1", "https://*.example.test/v1", "https://测试.example/v1",
		"http://2001:db8::1/v1", "http://[2001:db8::1/v1", "http://[]/v1", "http://[127.0.0.1]/v1", "http://[::gg]/v1",
		"http://[::1]junk/v1", "http://[::1]]/v1", "http://[::1]:/v1", "http://[::1]:65536/v1", "http://[::1]:80:90/v1",
		"http://[fe80::1%eth0]/v1", "https://api.test/%/v1", "https://api.test/%2/v1", "https://api.test/%xz/v1"
	]
	for raw: String in invalid:
		var result: Dictionary = Endpoint.normalize_chat_url(raw)
		check(not result.get("success",true) and result.get("url") == "" and not str(result.get("message","")).is_empty(), "reject invalid direct API address with a readable error / " + raw)
		check(not Endpoint.http_url_valid(raw), "transport parser rejects the same invalid HTTP structure / " + raw)
	for path: String in ["/api", "/v2", "/v1/completions", "/v1/chat/completions/extra", "/v10", "/V1", "/custom", "/api/v1/chatty"]:
		var url := "https://api.test" + path
		check(not Endpoint.normalize_chat_url(url).success, "unknown API path is not guessed / " + path)
		check(Endpoint.http_url_valid(url), "existing transport path remains structurally legal / " + path)
	for url: String in ["http://localhost:8765/v1/dialogue", "https://proxy.example/path/anything", "HTTPS://API.TEST:443/custom/", "http://[::1]:8765/health", "https://api.test/接口/route"]:
		check(Endpoint.http_url_valid(url), "shared transport validator does not append a chat path / " + url)
	check(not Endpoint.http_url_valid("") and not Endpoint.http_url_valid(" https://api.test/v1 "), "offline empty and copy formatting are normalization-only conveniences")
	check(not Endpoint.http_url_valid("https\\://api.test/v1\\"), "transport validator never silently repairs Markdown escape characters")
	var long_label := "a".repeat(64)
	check(not Endpoint.http_url_valid("https://"+long_label+".test/v1"), "DNS labels longer than 63 characters are invalid")
	var largest_domain := "a".repeat(63)+"."+"b".repeat(63)+"."+"c".repeat(63)+"."+"d".repeat(61)
	check(Endpoint.http_url_valid("https://"+largest_domain+"/v1"), "253-character DNS name is accepted")
	check(not Endpoint.http_url_valid("https://"+largest_domain+"e/v1"), "DNS name above 253 characters is rejected")
	var prefix := "https://a.test/"
	var suffix := "/chat/completions"
	var at_limit := prefix + "x".repeat(2048-prefix.length()-suffix.length()) + suffix
	check(at_limit.length() == 2048 and Endpoint.http_url_valid(at_limit) and Endpoint.normalize_chat_url(at_limit).url == at_limit, "complete 2048-character custom endpoint is preserved exactly")
	check(not Endpoint.http_url_valid(at_limit+"x") and not Endpoint.normalize_chat_url(at_limit+"x").success, "2049-character URL is rejected")
	var expansion_overflow := prefix + "x".repeat(2048-prefix.length()-3) + "/v1"
	check(expansion_overflow.length() == 2048 and Endpoint.http_url_valid(expansion_overflow) and not Endpoint.normalize_chat_url(expansion_overflow).success, "endpoint completion may not exceed the URL length limit")
	print("API ENDPOINT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("API ENDPOINT FAIL: " + label)

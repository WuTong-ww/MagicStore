"""GD/Python URL contract and dummy-key localhost transport, never public calls."""
import contextlib
import copy
import io
import json
import os
import re
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

from server.ai import api_endpoint, gateway


class ApiEndpointTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (Path(__file__).parents[1] / "http" / "api_endpoint.gd").read_text(encoding="utf-8")
        # Shared test vectors, not production-code translation or evaluation.
        cls.valid = json.loads(re.search(r"var valid := (\{.*?\n\t\})", source, re.S).group(1))
        cls.invalid = json.loads(re.search(r"var invalid := (\[.*?\n\t\])", source, re.S).group(1))

    def test_godot_canonical_url_vectors_match_python(self):
        for raw, expected in self.valid.items():
            with self.subTest(raw=raw):
                self.assertEqual(api_endpoint.normalize_chat_url(raw), {"success": True, "url": expected, "message": ""})

    def test_godot_invalid_structure_vectors_match_python(self):
        for raw in self.invalid:
            with self.subTest(raw=raw):
                normalized = api_endpoint.normalize_chat_url(raw)
                self.assertFalse(normalized["success"])
                self.assertEqual(normalized["url"], "")
                self.assertTrue(normalized["message"])
                self.assertFalse(api_endpoint.http_url_valid(raw))

    def test_transport_accepts_existing_paths_while_chat_normalization_refuses_to_guess(self):
        for path in ("/api", "/v2", "/v1/completions", "/v1/chat/completions/extra", "/v10", "/V1", "/custom", "/api/v1/chatty"):
            with self.subTest(path=path):
                url = "https://api.test" + path
                self.assertTrue(api_endpoint.http_url_valid(url))
                self.assertFalse(api_endpoint.normalize_chat_url(url)["success"])
        for url in ("http://localhost:8765/v1/dialogue", "http://[::1]:8765/health", "https://api.test/接口/route"):
            self.assertTrue(api_endpoint.http_url_valid(url))
        for raw in ("", " https://api.test/v1 ", "https\\://api.test/v1\\"):
            self.assertFalse(api_endpoint.http_url_valid(raw))

    def test_dns_and_2048_character_limits_match_godot(self):
        domain = "a" * 63 + "." + "b" * 63 + "." + "c" * 63 + "." + "d" * 61
        self.assertTrue(api_endpoint.http_url_valid("https://" + domain + "/v1"))
        self.assertFalse(api_endpoint.http_url_valid("https://" + domain + "e/v1"))
        self.assertFalse(api_endpoint.http_url_valid("https://" + "a" * 64 + ".test/v1"))
        prefix, suffix = "https://a.test/", "/chat/completions"
        maximum = prefix + "x" * (2048 - len(prefix) - len(suffix)) + suffix
        self.assertEqual(len(maximum), 2048)
        self.assertTrue(api_endpoint.http_url_valid(maximum))
        self.assertEqual(api_endpoint.normalize_chat_url(maximum)["url"], maximum)
        self.assertFalse(api_endpoint.http_url_valid(maximum + "x"))
        self.assertFalse(api_endpoint.normalize_chat_url(maximum + "x")["success"])
        expansion = prefix + "x" * (2048 - len(prefix) - 3) + "/v1"
        self.assertTrue(api_endpoint.http_url_valid(expansion))
        self.assertFalse(api_endpoint.normalize_chat_url(expansion)["success"])

    def test_non_strings_fail_without_network_or_exceptions(self):
        for raw in (None, False, 3, [], {}):
            self.assertFalse(api_endpoint.normalize_chat_url(raw)["success"])
            self.assertFalse(api_endpoint.http_url_valid(raw))

    def test_main_accepts_http_public_ipv4_and_completes_v1_without_network(self):
        environment = {"MAGIC_AI_URL": "http://203.0.113.10:3000/v1", "MAGIC_AI_KEY": "synthetic-no-public-request",
                       "MAGIC_GATEWAY_TOKEN": "synthetic-gateway-token", "MAGIC_AI_MODEL": "synthetic-model"}
        with patch.dict(os.environ, environment, clear=True), patch.object(gateway, "ThreadingHTTPServer") as server, \
                patch.object(gateway, "make_handler") as handler, contextlib.redirect_stdout(io.StringIO()):
            server.return_value.serve_forever.side_effect = KeyboardInterrupt
            gateway.main()
        config = handler.call_args.args[0]
        self.assertEqual(config["url"], "http://203.0.113.10:3000/v1/chat/completions")
        self.assertEqual(config["api_key"], "synthetic-no-public-request")
        server.return_value.server_close.assert_called_once()

    def test_main_rejects_invalid_endpoint_before_opening_a_server(self):
        for url in ("http://api.test:65536/v1", "https://user:pass@api.test/v1", "http://api.test/custom", ""):
            with self.subTest(url=url), patch.dict(os.environ, {"MAGIC_AI_URL": url, "MAGIC_AI_KEY": "dummy", "MAGIC_GATEWAY_TOKEN": "dummy"}, clear=True), \
                    patch.object(gateway, "ThreadingHTTPServer") as server, self.assertRaisesRegex(SystemExit, "MAGIC_AI_URL"):
                gateway.main()
            server.assert_not_called()

    def test_call_upstream_normalizes_actual_localhost_request_path_without_mutating_config(self):
        requests = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                return
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                requests.append({"path": self.path, "authorization": self.headers.get("Authorization"), "body": body})
                response = json.dumps({"choices": [{"message": {"content": '{"ok":true}'}, "finish_reason": "stop"}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(response)))
                self.end_headers()
                self.wfile.write(response)
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base = "http://127.0.0.1:%d" % server.server_port
            for supplied, expected in (("/v1", "/v1/chat/completions"), ("", "/v1/chat/completions"),
                                       ("/proxy/v1/", "/proxy/v1/chat/completions"),
                                       ("/custom/chat/completions", "/custom/chat/completions")):
                config = {"url": base + supplied, "api_key": "synthetic-loopback-only", "model": "synthetic-model", "timeout": 3}
                before = copy.deepcopy(config)
                self.assertEqual(gateway.call_upstream("Return JSON", {"public": "test"}, config), {"ok": True})
                self.assertEqual(config, before)
                self.assertEqual(requests[-1]["path"], expected)
                self.assertEqual(requests[-1]["authorization"], "Bearer synthetic-loopback-only")
                self.assertNotIn("synthetic-loopback-only", json.dumps(requests[-1]["body"]))
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)
        self.assertEqual(len(requests), 4)

    def test_call_upstream_rejects_missing_or_bad_url_before_transport(self):
        for url in ("", "http://api.test:0/v1", "https://api.test/unknown"):
            with self.subTest(url=url), patch.object(gateway.urllib.request, "urlopen") as transport, self.assertRaises(ValueError):
                gateway.call_upstream("Return JSON", {}, {"url": url, "api_key": "dummy", "model": "dummy", "timeout": 1})
            transport.assert_not_called()


if __name__ == "__main__":
    unittest.main()

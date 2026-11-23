"""Actual Godot HTTP wire capture. Synthetic sources, loopback, no paid APIs."""
import argparse
from collections import Counter
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[2]
FORBIDDEN = ("SyntheticOriginMark", "SyntheticCharacterMark", "OnlyInSavedFamily",
             "旧名甲", "合成屏蔽原句只作测试", "PRIVATE_EDITOR_NOTE", "UNMET_PERSON",
             "source_work", "reference_character", "reference_note", "family_members", "_family_guard")
SAFE_REPLY = "我想慢慢说清。"


class Fixture(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)
        self.captures = []
        self.errors = []
        self.counts = Counter()
        self.lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        self.connection.settimeout(3)
        try:
            raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            body = json.loads(raw)
            route = self.path.strip("/").split("/")[0]
            direct = not route.startswith("gateway")
            stage = self.headers.get("X-Magic-Dialogue-Stage", "") if direct else "gateway"
            context = json.loads(body["messages"][1]["content"]) if direct else body
            with self.server.lock:
                self.server.counts[(route, stage)] += 1
                attempt = self.server.counts[(route, stage)]
                self.server.captures.append({"route": route, "stage": stage,
                    "path": self.path, "body": body, "context": context,
                    "raw_sha256": hashlib.sha256(raw).hexdigest(),
                    "has_gateway_token": bool(self.headers.get("X-Magic-Gateway-Token")),
                    "has_bearer": self.headers.get("Authorization", "").startswith("Bearer ")})
            if route == "failure" or ((route == "retry" and stage == "generate" or route == "gateway_retry") and attempt == 1):
                return self.send_json(503, {})
            if direct:
                if stage == "classify":
                    value = {"intent": "clarify"}
                elif stage == "generate":
                    value = {"intent": "clarify", "reply_text": "OnlyInSavedFamily" if route == "source" else SAFE_REPLY,
                             "evidence_ids": [], "mood": "neutral"}
                elif stage == "review":
                    value = {"approved": True, "evidence_ids": context["candidate"]["evidence_ids"],
                             "contradictions": [], "unsupported_claims": []}
                else:
                    raise ValueError("unexpected direct HTTP stage")
                return self.send_json(200, {"choices": [{"finish_reason": "stop", "message": {"role": "assistant", "content": json.dumps(value, ensure_ascii=False)}}]})
            value = {"reply_text": "OnlyInSavedFamily" if route == "gateway_source" else SAFE_REPLY,
                     "intent": "clarify", "clue_ids": [], "needs_clarification": True,
                     "error_code": "", "branch_id": "", "mood": "neutral"}
            if route == "gateway_questions":
                value["followup_questions"] = [{"topic_id": "family_topic", "text": "旧名甲近况？"},
                                              {"topic_id": "family_topic", "text": "近况怎样了？"}]
            return self.send_json(200, value)
        except (ValueError, KeyError, TypeError, OSError, IndexError) as error:
            with self.server.lock:
                self.server.errors.append(type(error).__name__+": "+str(error))
            self.send_json(400, {"error": "FIXTURE_INVALID"})

    def send_json(self, status, value):
        raw = json.dumps(value, ensure_ascii=False).encode("utf-8")
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("X-Magic-Mode", "online")
            self.end_headers()
            self.wfile.write(raw)
        except (OSError, BrokenPipeError):
            pass


def verify_captures(fixture):
    checks = 0

    def verify(value, reason):
        nonlocal checks
        checks += 1
        if not value:
            raise AssertionError(reason)

    verify(not fixture.errors, "loopback fixture itself failed: "+str(fixture.errors))
    expected = {"direct": {"classify": 1, "generate": 1, "review": 1},
                "retry": {"classify": 1, "generate": 2, "review": 1},
                "source": {"classify": 1, "generate": 1},
                "failure": {"classify": 2}, "gateway": {"gateway": 1},
                "gateway_source": {"gateway": 1}, "gateway_retry": {"gateway": 2},
                "gateway_questions": {"gateway": 1}}
    actual = {}
    for (route, stage), count in fixture.counts.items():
        actual.setdefault(route, {})[stage] = count
    verify(actual == expected, "actual classification/generation/review/retry paths differ: "+str(actual))
    for row in fixture.captures:
        serialized = json.dumps(row["body"], ensure_ascii=False)
        for term in FORBIDDEN:
            verify(term not in serialized, "private source reached actual HTTP request: "+term)
        persona = row["context"].get("safe_persona", {})
        verify(persona.get("catchphrase") == "慢慢说清。", "rewritten voice missing from actual wire")
        verify(persona.get("information_boundaries") == ["只谈已知近况。"], "rewritten boundaries missing from actual wire")
        if row["stage"] == "gateway":
            verify(row["path"].endswith("/v1/dialogue") and row["has_gateway_token"] and not row["has_bearer"], "gateway transport authority mismatch")
        else:
            verify(row["path"].endswith("/v1/chat/completions") and row["has_bearer"] and not row["has_gateway_token"], "direct model transport authority mismatch")
            verify(row["body"].get("stream") is False, "streaming changed wire fixture semantics")
    for route, stage in [("retry", "generate"), ("gateway_retry", "gateway"), ("failure", "classify")]:
        hashes = [r["raw_sha256"] for r in fixture.captures if (r["route"], r["stage"]) == (route, stage)]
        verify(len(hashes) == 2 and hashes[0] == hashes[1], "retry changed its actual serialized body")
    return checks, actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True)
    args = parser.parse_args()
    fixture = Fixture()
    thread = threading.Thread(target=fixture.serve_forever, daemon=True)
    thread.start()
    env = os.environ.copy()
    env["MAGIC_FAMILY_HTTP_URL"] = f"http://127.0.0.1:{fixture.server_port}"
    for key in ("MAGIC_AI_KEY", "MAGIC_GATEWAY_URL", "MAGIC_GATEWAY_TOKEN", "MAGIC_GATEWAY_TIMEOUT"):
        env.pop(key, None)
    for key, folder in [("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata"), ("TEMP", "temp"), ("TMP", "temp")]:
        directory = ROOT/".tools/g2/http-env"/folder
        directory.mkdir(parents=True, exist_ok=True)
        env[key] = str(directory)
    try:
        result = subprocess.run([args.engine, "--headless", "--path", str(ROOT), "--script", "res://tests/http/family_policy.gd"],
                                env=env, capture_output=True, text=True, encoding="utf-8", timeout=35)
        print(result.stdout, end="")
        print(result.stderr, end="")
        if result.returncode or any(s in result.stdout+result.stderr for s in ("SCRIPT ERROR:", "ERROR:", "WARNING:")):
            return 1
        checks, actual = verify_captures(fixture)
        receipt = {"assertions": checks, "failures": 0, "actual_routes": actual, "captures": fixture.captures}
        (ROOT/".tools/g2/family-wire-captures.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        print(f"FAMILY HTTP WIRE: {checks} assertions, 0 failures; {len(fixture.captures)} captured requests")
        return 0
    except subprocess.TimeoutExpired:
        print("FAMILY HTTP fixture exceeded its bounded 35 second deadline.")
        return 1
    finally:
        fixture.shutdown()
        fixture.server_close()
        thread.join(timeout=3)


if __name__ == "__main__":
    raise SystemExit(main())

"""Run Godot HTTP acceptance tests against a real loopback-only fixture server."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

BODY_KEYS = {"npc", "case_id", "visit_id", "input_text", "topic_id", "allowed_effects", "current_dialogue", "visible_history", "allowed_intents", "allowed_clue_ids", "allowed_branch_ids", "known_memories", "safe_persona", "relationship", "dialogue_sources"}
NATURAL_REPLY = "邀请上专门留了句手写的话，说靠窗的位置还给我留着。看着这几个字，我觉得它不像是群发的邀请。"
NATURAL_CHAT = "不用急着把话说清楚，你愿意聊的话，我在听。"


class RecoveryState:
    lock = threading.Lock()
    calls = Counter()
    bodies = {}
    redirect_hits = 0


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        with RecoveryState.lock:
            if self.path.startswith("/api-redirect_target/"):
                RecoveryState.redirect_hits += 1
            body = json.dumps({"calls":dict(RecoveryState.calls),"body_hashes":RecoveryState.bodies,"redirect_hits":RecoveryState.redirect_hits}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        route = self.path.split("/")[1]
        if route == "api-redirect_target":
            with RecoveryState.lock:
                RecoveryState.redirect_hits += 1
        if route.startswith("api-"):
            return self.do_api(route[4:])
        core_test = route.startswith("core-")
        if core_test:
            route = route[5:]
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        valid = (not set(request) - BODY_KEYS and self.headers.get("X-Magic-Gateway-Token") == "fixture-token"
                 and bool(self.headers.get("X-Request-ID")) and bool(self.headers.get("X-Action-ID")))
        if not core_test:
            valid = valid and self.headers.get("X-Request-ID") == "req_fixture" and self.headers.get("X-Action-ID") == "action_fixture"
        if route == "no_response" and valid:
            # Keep the socket open without replying beyond the client's budget.
            time.sleep(2.0)
            self.close_connection = True
            return
        status = 200 if valid else 400
        reply = {"reply_text": "线上回复", "intent": "invitation", "clue_ids": ["invitation_note"], "needs_clarification": False, "error_code": "", "branch_id": ""}
        if route.startswith("mood_"):
            reply["mood"] = route.removeprefix("mood_")
        if route == "mood_rejected":
            status, reply = 422, {"error":"INVALID_MOOD"}
        if route.startswith("followups"):
            reply["followup_questions"] = [{"topic_id":"letter","text":"那封信后来怎样了？"},{"topic_id":"clarify","text":"继续"},{"topic_id":"forbidden","text":"隐藏资料"},{"topic_id":"invitation","text":"这个问题超过了十六个字必须被安全移除"},{"topic_id":"invitation","text":""},{"topic_id":"letter","text":"重复"},{"topic_id":"invitation","text":"再说说邀请？"},{"topic_id":"letter","text":"额外字段","extra":True}]
            if route == "followups_scalar":
                reply["followup_questions"] = "invalid optional field"
            if route == "followups_extra":
                reply["grant_money"] = 100
        if route == "unauthorized":
            status = 401
        if route == "failure":
            status = 503
        if route == "invalid":
            reply["clue_ids"] = ["forbidden_fact"]
        if route in ("delay", "cancel"):
            time.sleep(0.65)
        body = b"{invalid json" if route == "malformed" else json.dumps(reply, ensure_ascii=False).encode("utf-8")
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-Magic-Mode", "offline" if route == "offline" else "online")
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass  # Expected when testing timeout and explicit cancellation.

    def do_api(self, route):
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        messages = request.get("messages", [])
        deepseek = route == "deepseek"
        glm = route in ("glm", "glm_flash")
        qwen = route == "qwen"
        model = {"deepseek":"deepseek-v4.1-flash","glm":"glm-5.3","glm_flash":"glm-5.3-flash","qwen":"qwen3.8-27b-fp8"}.get(route,"fixture-model")
        if route == "recover_switched":
            model = "qwen3.8-27b-fp8"
            qwen = True
        expected_key = "fixture-switched-key" if route == "recover_switched" else "fixture-api-key"
        valid = (self.path.endswith("/v1/chat/completions") and self.headers.get("Authorization") == "Bearer " + expected_key
                 and not self.headers.get("X-Magic-Gateway-Token") and request.get("model") == model
                 and request.get("stream") is False and len(messages) == 2 and messages[0].get("role") == "system"
                 and messages[1].get("role") == "user" and bool(self.headers.get("X-Request-ID")))
        context = json.loads(messages[1]["content"]) if valid else {}
        serialized = json.dumps(context, ensure_ascii=False)
        valid = valid and not any(marker in serialized for marker in ("private_state", "hidden_world", "_topic_facts", "_effects", "_guardrails", "UNASKED_SECRET_FACT"))
        stage = self.headers.get("X-Magic-Dialogue-Stage")
        if route == "redirect" and valid:
            self.send_response(302)
            self.send_header("Location",f"http://127.0.0.1:{self.server.server_port}/api-redirect_target/v1/chat/completions")
            self.send_header("Content-Length","0")
            self.end_headers()
            return
        attempt = 0
        if route.startswith("recover_"):
            key = route + ":" + self.headers.get("X-Request-ID", "") + ":" + str(stage)
            with RecoveryState.lock:
                RecoveryState.calls[key] += 1
                attempt = RecoveryState.calls[key]
                RecoveryState.bodies.setdefault(key, []).append(hashlib.sha256(json.dumps(request,sort_keys=True).encode()).hexdigest())
            failure_stage = route.removeprefix("recover_") if route in ("recover_classify","recover_generate","recover_review") else "generate"
            transient = route in ("recover_classify","recover_generate","recover_review","recover_408","recover_429","recover_500","recover_502","recover_504","recover_cancel","recover_backoff","recover_budget","recover_long_after","recover_date_after","recover_permanent","recover_drop") and stage == failure_stage
            transient = transient or (route == "recover_two_stages" and stage in ("classify","review"))
            if valid and ((transient and (attempt == 1 or route == "recover_permanent")) or route == "recover_401"):
                if route == "recover_drop":
                    self.close_connection = True
                    return
                status = {"recover_408":408,"recover_500":500,"recover_502":502,"recover_504":504}.get(route,401 if route == "recover_401" else (429 if route in ("recover_429","recover_cancel","recover_backoff","recover_long_after","recover_date_after") else 503))
                self.send_response(status)
                if route in ("recover_429","recover_cancel","recover_backoff","recover_budget","recover_long_after","recover_date_after"):
                    self.send_header("Retry-After", "Wed, 01 Jan 2031 00:00:00 GMT" if route == "recover_date_after" else ("5" if route == "recover_long_after" else ("0.4" if route in ("recover_cancel","recover_backoff") else "0.06")))
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
        if deepseek:
            valid = valid and request.get("thinking") == {"type": "disabled"} and "reasoning_effort" not in request
            valid = valid and request.get("temperature") == (0.25 if stage == "generate" else 0)
        elif glm:
            valid = valid and request.get("thinking") == {"type":"enabled"} and request.get("reasoning_effort") == "low" and request.get("max_tokens") == 4096
            valid = valid and request.get("temperature") == (0.25 if stage == "generate" else 0)
        elif qwen:
            valid = valid and request.get("enable_thinking") is False and request.get("chat_template_kwargs") == {"enable_thinking":False} and "thinking" not in request and "reasoning_effort" not in request
        else:
            valid = valid and "thinking" not in request and "reasoning_effort" not in request
            valid = valid and request.get("temperature") == (0.55 if stage == "generate" else 0)
        if stage == "classify":
            valid = valid and "sources" not in context
            selected = {"intent": "clarify" if route in ("clarify", "clarify_review_reject") else "invitation"}
        elif stage == "generate":
            topic = context.get("selected_topic")
            sources = context.get("sources", [])
            valid = valid and topic in ("invitation", "clarify") and all(source.get("source_id") != "topic:letter" for source in sources)
            selected = {"intent": topic, "reply_text": NATURAL_CHAT if topic == "clarify" else NATURAL_REPLY, "evidence_ids": [] if topic == "clarify" else ["topic:invitation"]}
            if route.startswith("mood_"):
                selected["mood"] = route.removeprefix("mood_")
            if route == "invalid":
                selected["intent"] = "forbidden_fact"
            if route == "extra":
                selected["grant_money"] = 1000
            if route == "bad_ids":
                selected["evidence_ids"] = ["topic:letter"]
            if route == "hallucinated":
                selected["reply_text"] = "他昨晚向我求婚了，我已经答应。"
        elif stage == "review":
            candidate = context.get("candidate", {})
            if route.startswith("mood_"):
                valid = valid and candidate.get("mood") == route.removeprefix("mood_")
            sources = context.get("sources", [])
            valid = valid and all(source.get("source_id") != "topic:letter" for source in sources)
            selected = {"approved": route not in ("hallucinated", "review_reject", "clarify_review_reject", "recover_rejected"), "evidence_ids": candidate.get("evidence_ids", []), "contradictions": [], "unsupported_claims": ["没有来源的新事件"] if route == "hallucinated" else []}
            if route == "review_missing_ids":
                selected["evidence_ids"] = []
        else:
            valid = False
            selected = {}
        content = "not valid json" if (route in ("malformed","recover_malformed") or (route == "review_malformed" and stage == "review")) else json.dumps(selected, ensure_ascii=False)
        if route in ("fenced", "fenced_suffix"):
            content = "```json\n" + content + "\n```" + ("\nexplanation" if route == "fenced_suffix" else "")
        reply = {"choices": [{"message": {"content": None if route in ("reasoning_only","recover_reasoning") else content, "reasoning_content": json.dumps(selected, ensure_ascii=False)}, "finish_reason": "length" if route in ("length_json","recover_length") else "stop"}]}
        if route == "delay" or (route in ("cancel", "late_review") and stage == "review"):
            time.sleep(0.65)
        if route == "budget":
            time.sleep(0.13 if stage != "review" else 0.4)
        if route == "recover_budget":
            time.sleep(0.08 if stage == "generate" else 0.3)
        body = json.dumps(reply, ensure_ascii=False).encode("utf-8")
        try:
            self.send_response(503 if route == "classify_failure" and stage == "classify" else (200 if valid else 400))
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = os.environ.copy()
    env["MAGIC_HTTP_FIXTURE_URL"] = f"http://127.0.0.1:{server.server_port}"
    # Never pass an upstream model key into the game/test process.
    env.pop("MAGIC_AI_KEY", None)
    env.pop("MAGIC_GATEWAY_URL", None)
    env.pop("MAGIC_GATEWAY_TOKEN", None)
    env.pop("MAGIC_GATEWAY_TIMEOUT", None)
    try:
        for script in ("api_endpoint", "model_policy", "deadline", "provider", "game_state_http", "direct_api", "recovery", "mood"):
            try:
                result = subprocess.run([args.engine, "--headless", "--path", str(repo), "--script", f"res://tests/http/{script}.gd"], env=env, capture_output=True, text=True, encoding="utf-8", timeout=30)
            except subprocess.TimeoutExpired as error:
                for output in (error.stdout, error.stderr):
                    if output:
                        print(output.decode("utf-8", errors="replace") if isinstance(output, bytes) else output, end="")
                print("HTTP fixture exceeded the 30-second test deadline.")
                return 1
            print(result.stdout, end="")
            print(result.stderr, end="")
            exit_code = result.returncode or (1 if "SCRIPT ERROR:" in result.stderr or "ERROR:" in result.stderr else 0)
            if exit_code:
                return exit_code
        return 0
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    raise SystemExit(main())

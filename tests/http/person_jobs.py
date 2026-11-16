"""Loopback-only concurrent person-generation fixture; no real API credentials."""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import threading
import time


def bundle_for(context):
    names = context.get("existing_names", context.get("avoid_names", []))
    name = "陆听雨" if "纪寄棠" in names else "季温澜"
    contact = "程予安" if name == "季温澜" else "秦沐晴"
    return {"version": 1,
            "person": {"name": name, "role": "花店店员", "personality": "温和细心，遇到关系问题会犹豫。", "speech_style": "语气温和，习惯把话说短。", "background": "在社区花店工作，曾与朋友共同参与旧书交换。", "preferences": ["植物", "旧书"]},
            "contact": {"name": contact, "role": "插画师", "personality": "安静认真，喜欢直接说明安排。", "speech_style": "表达简洁，遇到误会愿意核对。", "background": "在附近从事插画工作，曾在社区活动中结识一位熟人。", "preferences": ["绘画", "散步"]},
            "relationship": {"kind": "朋友", "shared_history": "两人曾在社区旧书交换活动相识，后来偶有联系。"},
            "case": {"title": "迟到的问候", "opening": "我想重新和朋友联系，但又怕突然开口让人困扰。", "question": "我该怎样重新和朋友开口？", "situation": "两人最近联系减少，顾客想恢复联系。", "concern": "顾客担心自己打扰朋友。", "detail": "我写好了一张简短便笺，结尾留着两个不同的称呼。", "hidden_fact": "朋友曾托社区管理员留过一句话，希望问候时不用拘泥称呼。", "followup": "顾客可以先发一条不催促回复的问候。"}}


def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


class State:
    lock = threading.Lock()
    active = 0
    peak = 0
    calls = Counter()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        with State.lock:
            value = {"active": State.active, "peak": State.peak, "calls": dict(State.calls)}
        self.send_json(200, value)

    def do_POST(self):
        route = self.path.split("/")[1]
        stage = self.headers.get("X-Magic-Person-Stage", "")
        request = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        with State.lock:
            State.active += 1
            State.peak = max(State.peak, State.active)
            State.calls[route + ":" + stage] += 1
            attempt = State.calls[route + ":" + stage]
        try:
            if route.startswith("gateway"):
                valid = self.path.endswith("/v1/person-package") and self.headers.get("X-Magic-Gateway-Token") == "fixture-person-key"
                draft = bundle_for(request)
                digest = canonical_hash(draft)
                review = {"approved": True, "draft_hash": digest, "contradictions": [], "unsupported_claims": []}
                if route == "gateway-bad":
                    review["draft_hash"] = "0" * 64
                return self.send_json(200 if valid else 401, {"bundle": draft, "provenance": {"source": "model", "model": "fixture-person-model", "draft_hash": digest, "review": review}})
            messages = request.get("messages", [])
            family_model = {"deepseek":"deepseek-v4.1-flash","glm":"glm-5.3","glm_flash":"glm-5.3-flash","qwen":"qwen3.8-27b-fp8"}.get(route,"fixture-person-model")
            valid = self.path.endswith("/v1/chat/completions") and self.headers.get("Authorization") == "Bearer fixture-person-key" and request.get("model") == family_model and len(messages) == 2 and stage in ("generate", "review")
            if route in ("glm","glm_flash"):
                valid = valid and request.get("thinking") == {"type":"enabled"} and request.get("reasoning_effort") == "low" and request.get("max_tokens") == (6144 if stage == "generate" else 4096)
            elif route == "qwen":
                valid = valid and request.get("enable_thinking") is False and request.get("chat_template_kwargs") == {"enable_thinking":False}
            elif route == "deepseek":
                valid = valid and request.get("thinking") == {"type":"disabled"}
            context = json.loads(messages[1]["content"]) if valid else {}
            valid = valid and not any(word in json.dumps(context) for word in ("private_state", "PRIVATE_EXISTING_FACT", "api_key"))
            if not valid:
                return self.send_json(400, {"error": "INVALID_FIXTURE_REQUEST"})
            if route == "unauthorized":
                return self.send_json(401, {"error": "UNAUTHORIZED"})
            if route == "always503":
                return self.send_json(503, {"error": "BUSY"})
            if route == "retry" and stage == "generate" and attempt == 1:
                return self.send_json(429, {"error": "BUSY"}, retry_after="0.15")
            if route in ("delay", "cancel", "old"):
                time.sleep(0.5)
            else:
                time.sleep(0.05 if "纪寄棠" in context.get("existing_names", context.get("avoid_names", [])) else 0.12)
            if stage == "generate":
                value = bundle_for(context)
                if route == "invalid":
                    value["person"]["npc_id"] = "model_must_not_assign_ids"
            else:
                safe_context = context.get("context", {})
                draft = context.get("draft", context.get("candidate", {}))
                valid = draft.get("person", {}).get("name") == bundle_for(safe_context)["person"]["name"]
                value = {"approved": True, "draft_hash": context.get("draft_hash", ""), "contradictions": [], "unsupported_claims": []}
                if route == "badreview":
                    value["draft_hash"] = "0" * 64
            content = json.dumps(value, ensure_ascii=False)
            if route == "fenced":
                content = "```json\n" + content + "\n```"
            return self.send_json(200 if valid else 400, {"choices": [{"message": {"content": None if route == "reasoning_only" else content,"reasoning_content":json.dumps(value,ensure_ascii=False)}, "finish_reason": "length" if route == "truncated" else "stop"}]})
        finally:
            with State.lock:
                State.active -= 1

    def send_json(self, status, value, retry_after=""):
        body = json.dumps(value, ensure_ascii=False).encode()
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            if retry_after:
                self.send_header("Retry-After", retry_after)
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
    threading.Thread(target=server.serve_forever, daemon=True).start()
    env = os.environ.copy()
    for name in ("MAGIC_AI_KEY", "MAGIC_GATEWAY_URL", "MAGIC_GATEWAY_TOKEN", "MAGIC_LIVE_API_KEY", "MAGIC_LIVE_API_URL", "MAGIC_LIVE_MODEL"):
        env.pop(name, None)
    env["MAGIC_PERSON_FIXTURE_URL"] = f"http://127.0.0.1:{server.server_port}"
    try:
        result = subprocess.run([args.engine, "--headless", "--path", str(repo), "--script", "res://tests/http/person_jobs.gd"], env=env, capture_output=True, text=True, encoding="utf-8", timeout=30)
        print(result.stdout, end="")
        print(result.stderr, end="")
        return result.returncode or (1 if "ERROR:" in result.stderr else 0)
    except subprocess.TimeoutExpired as error:
        for output in (error.stdout, error.stderr):
            if output:
                print(output.decode("utf-8", "replace") if isinstance(output, bytes) else output, end="")
        print("Person job fixture exceeded its 30-second deadline.")
        return 1
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    raise SystemExit(main())

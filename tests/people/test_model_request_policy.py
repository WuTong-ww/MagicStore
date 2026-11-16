"""Gateway transport checks with intercepted HTTP; no upstream service calls."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[2] / "server" / "ai" / "gateway.py"
spec = importlib.util.spec_from_file_location("magic_gateway_model_policy_tests", path)
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)


class Response:
    status = 200

    def __init__(self, value):
        self.value = value

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def read(self, _limit):
        return json.dumps(self.value).encode("utf-8")


def completion(content, finish="stop"):
    return {"choices": [{"message": {"content": content, "reasoning_content": '{"injected":true}'}, "finish_reason": finish}]}


class ModelRequestPolicyTests(unittest.TestCase):
    def config(self, model="unknown-model"):
        return {"model": model, "url": "https://example.invalid/v1/chat/completions", "api_key": "fixture-model-key", "timeout": 2}

    def test_all_four_models_use_verified_options_for_every_dialogue_and_person_stage(self):
        payloads = []

        def respond(request, **kwargs):
            self.assertEqual(request.get_header("Authorization"), "Bearer fixture-model-key")
            self.assertEqual(kwargs["timeout"], 2)
            payloads.append(json.loads(request.data))
            return Response(completion('{"ok":true}'))

        context = {"sources": [{"source_id": "persona:name", "text": "林照晚"}]}
        original = json.dumps(context, ensure_ascii=False)
        with patch.object(gateway.urllib.request, "urlopen", side_effect=respond):
            for model in ("deepseek-v4.1-flash", "glm-5.3", "glm-5.3-flash", "qwen3.8-27b-fp8"):
                for stage in ("classify", "generate", "review", "person_generate", "person_review"):
                    with self.subTest(model=model, stage=stage):
                        self.assertEqual(gateway.call_upstream("JSON only", context, self.config(model), stage=stage), {"ok": True})
                        body = payloads[-1]
                        self.assertEqual(body["model"], model)
                        self.assertIs(body["stream"], False)
                        self.assertEqual(body["response_format"], {"type": "json_object"})
                        self.assertEqual(json.loads(body["messages"][1]["content"]), context)
                        self.assertNotIn("fixture-model-key", json.dumps(body))
                        person_generate = stage == "person_generate"
                        self.assertEqual(body["temperature"], 0.4 if person_generate else (0.25 if model.startswith(("deepseek", "glm")) and stage == "generate" else (0.55 if stage == "generate" else 0)))
                        if model.startswith("glm"):
                            self.assertEqual(body["thinking"], {"type": "enabled"})
                            self.assertEqual(body["reasoning_effort"], "low")
                            self.assertEqual(body["max_tokens"], 6144 if person_generate else 4096)
                        else:
                            self.assertEqual(body["max_tokens"], 2304 if person_generate else 1024)
                            if model.startswith("deepseek"):
                                self.assertEqual(body["thinking"], {"type": "disabled"})
                                self.assertNotIn("reasoning_effort", body)
                            else:
                                self.assertIs(body["enable_thinking"], False)
                                self.assertEqual(body["chat_template_kwargs"], {"enable_thinking": False})
                                self.assertNotIn("thinking", body)
        self.assertEqual(json.dumps(context, ensure_ascii=False), original)

    def test_unknown_and_older_families_keep_generic_options(self):
        policy = gateway.model_request_policy()
        for model in ("other-model", "glm-4", "qwen2.5"):
            with self.subTest(model=model):
                body = policy.build_body(model, "JSON", {}, "review")
                self.assertEqual(body["temperature"], 0)
                self.assertEqual(body["max_tokens"], 1024)
                self.assertFalse({"thinking", "reasoning_effort", "enable_thinking", "chat_template_kwargs"} & body.keys())
        legacy = policy.build_body("other-model", "JSON", {}, "general")
        self.assertEqual((legacy["temperature"], legacy["max_tokens"]), (0.2, 1000))

    def test_complete_plain_and_single_fenced_json_content_pass_actual_call_parser(self):
        for content in ('{"ok":true}', '  {"ok":true}\n', '```json\n{"ok":true}\n```', '```JSON\r\n{"ok":true}\r\n```', '```\n{"ok":true}\n```'):
            with self.subTest(content=content), patch.object(gateway.urllib.request, "urlopen", return_value=Response(completion(content))):
                self.assertEqual(gateway.call_upstream("JSON", {}, self.config()), {"ok": True})

    def test_truncation_incomplete_fences_and_explanations_cannot_reach_stage_validation(self):
        for content in ('```json\n{"ok":true}', '```python\n{"ok":true}\n```', '说明：{"ok":true}', '```json\n{"ok":true}\n```\nexplanation', '{"ok":true}{"extra":true}', '[{"ok":true}]'):
            with self.subTest(content=content), patch.object(gateway.urllib.request, "urlopen", return_value=Response(completion(content))), self.assertRaises(ValueError):
                gateway.call_upstream("JSON", {}, self.config())
        for finish in ("length", "max_tokens", "content_filter", "tool_calls", "error", None, False):
            with self.subTest(finish=finish), patch.object(gateway.urllib.request, "urlopen", return_value=Response(completion('{"ok":true}', finish))), self.assertRaisesRegex(ValueError, "did not finish"):
                gateway.call_upstream("JSON", {}, self.config())

    def test_legacy_missing_finish_reason_is_distinct_from_an_explicit_null(self):
        value = {"choices": [{"message": {"content": '{"ok":true}'}}]}
        with patch.object(gateway.urllib.request, "urlopen", return_value=Response(value)):
            self.assertEqual(gateway.call_upstream("JSON", {}, self.config()), {"ok": True})

    def test_hidden_reasoning_is_never_a_substitute_for_visible_content(self):
        for content in (None, ""):
            with self.subTest(content=content), patch.object(gateway.urllib.request, "urlopen", return_value=Response(completion(content))), self.assertRaises(ValueError):
                gateway.call_upstream("JSON", {}, self.config("glm-5.3"))


if __name__ == "__main__":
    unittest.main()

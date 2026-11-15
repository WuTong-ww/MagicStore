import importlib.util
import json
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

PATH = Path(__file__).resolve().parents[2] / "server" / "ai" / "gateway.py"
spec = importlib.util.spec_from_file_location("magic_gateway", PATH)
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)


def sample():
    return {"npc": {"name": "林照晚", "role": "旧书修复师", "hidden": "secret"},
            "case_id": "invitation", "visit_id": "visit_1", "input_text": "邀请上写了什么？",
            "topic_id": "invitation", "allowed_effects": {
                "clarify": {"clue_ids": [], "branch_id": ""},
                "invitation": {"clue_ids": ["invitation_note"], "branch_id": ""}},
            "allowed_intents": ["clarify", "invitation"], "allowed_clue_ids": ["invitation_note"], "allowed_branch_ids": [],
            "current_dialogue": [{"speaker": "npc", "text": "我想问一份邀请。"}], "visible_history": []}


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.topics = gateway.load_topics()

    def test_public_projection_and_authorized_effects(self):
        request = sample()
        context = gateway.prepare_request(request, self.topics)
        self.assertNotIn("secret", json.dumps(context, ensure_ascii=False))
        self.assertEqual(context["selected_topic"], "invitation")
        response = gateway.normalize_output({"intent": "invitation", "reply_text": "她留了一个位置。"}, request)
        self.assertEqual(response["clue_ids"], ["invitation_note"])
        self.assertFalse(response["needs_clarification"])

    def test_only_mutually_known_memories_reach_model(self):
        request = sample()
        request["known_memories"] = [
            {"audience": "both", "kind": "statement", "text": "曾谈过回信"},
            {"audience": "npc", "kind": "event", "text": "未披露的秘密"},
            {"audience": "player", "kind": "prediction", "text": "玩家私下的猜测"}]
        context = gateway.prepare_request(request, self.topics)
        self.assertEqual(context["known_memories"], [{"kind": "statement", "text": "曾谈过回信"}])
        self.assertNotIn("未披露的秘密", json.dumps(context, ensure_ascii=False))

    def test_rejects_unknown_or_wrong_selected_intent(self):
        request = sample()
        with self.assertRaises(ValueError):
            gateway.normalize_output({"intent": "letter", "reply_text": "text"}, request)
        with self.assertRaises(ValueError):
            gateway.normalize_output({"intent": "clarify", "reply_text": "text"}, request)
        with self.assertRaises(ValueError):
            gateway.prepare_request({**request, "world_facts": {"hidden": "secret"}}, self.topics)

    def test_free_text_only_receives_selected_topic_fact(self):
        request = sample()
        request["topic_id"] = ""
        request["allowed_effects"]["letter"] = {"clue_ids": ["unfinished_letter"], "branch_id": ""}
        context = gateway.prepare_request(request, self.topics)
        self.assertNotIn("reply_fact", json.dumps(context, ensure_ascii=False))
        observed = []
        def generate(data, _config):
            observed.append(data)
            return {"intent": "invitation", "reply_text": "邀请上有一句附言。"}
        result = gateway.dialogue_result(request, context, self.topics, {}, generate,
                                         lambda data, config: {"intent": "invitation"})
        self.assertEqual(result["clue_ids"], ["invitation_note"])
        self.assertEqual(result["reply_text"], self.topics["invitation"]["reply_text"])
        self.assertEqual(len(observed[0]["allowed_topics"]), 1)
        self.assertEqual(observed[0]["allowed_topics"][0]["intent"], "invitation")
        self.assertNotIn(self.topics["letter"]["reply_text"], json.dumps(observed, ensure_ascii=False))

    def test_unauthorized_extra_claim_is_not_delivered(self):
        request = sample()
        context = gateway.prepare_request(request, self.topics)
        factual = self.topics["invitation"]["reply_text"]
        result = gateway.dialogue_result(request, context, self.topics, {},
            lambda _c, _s: {"intent": "invitation", "reply_text": factual + "朋友明天一定会来。"})
        self.assertEqual(result["reply_text"], factual)
        self.assertNotIn("明天一定", result["reply_text"])

    def test_persona_prefix_cannot_carry_extra_claims(self):
        request = sample()
        context = gateway.prepare_request(request, self.topics)
        result = gateway.dialogue_result(request, context, self.topics, {},
            lambda _c, _s: {"intent": "invitation", "reply_text": "嗯，朋友明天一定会来。"})
        self.assertEqual(result["reply_text"], "嗯，" + self.topics["invitation"]["reply_text"])
        self.assertNotIn("明天一定", result["reply_text"])

    def test_followup_uses_only_shared_same_topic_memory(self):
        request = sample()
        request["input_text"] = "上次的邀请后来怎么样？"
        request["known_memories"] = [
            {"audience": "both", "kind": "statement", "topic_id": "invitation", "text": "邀请上留了位置"},
            {"audience": "npc", "kind": "event", "topic_id": "invitation", "text": "未披露的秘密"},
            {"audience": "both", "kind": "statement", "topic_id": "letter", "text": "另一件事"}]
        context = gateway.prepare_request(request, self.topics)
        result = gateway.dialogue_result(request, context, self.topics, {},
            lambda _c, _s: {"intent": "invitation", "reply_text": "嗯，其他内容"})
        self.assertIn("邀请上留了位置", result["reply_text"])
        self.assertNotIn("未披露的秘密", result["reply_text"])
        self.assertNotIn("另一件事", result["reply_text"])

        offline = gateway.offline_dialogue(request, self.topics)
        self.assertIn("邀请上留了位置", offline["reply_text"])
        self.assertNotIn("未披露的秘密", offline["reply_text"])

    def test_unambiguous_wording_corrects_unnecessary_clarification(self):
        request = sample()
        request["topic_id"] = ""
        request["input_text"] = "那封信为什么没寄出去？"
        request["allowed_effects"]["letter"] = {"clue_ids": ["unfinished_letter"], "branch_id": ""}
        context = gateway.prepare_request(request, self.topics)
        result = gateway.dialogue_result(request, context, self.topics, {},
            lambda data, _config: {"intent": data["selected_topic"], "reply_text": "其他文字"},
            lambda _data, _config: {"intent": "clarify"})
        self.assertEqual(result["intent"], "letter")
        self.assertEqual(result["clue_ids"], ["unfinished_letter"])

    def test_ambiguous_words_are_not_used_as_a_forced_topic(self):
        allowed = {"invitation": {}, "letter": {}, "clarify": {}}
        self.assertEqual(gateway.unambiguous_keyword("展览邀请和回信", allowed, self.topics), "")

    def test_offline_dialogue_uses_only_allowed_topic_or_clarifies(self):
        request = sample()
        request["topic_id"] = ""
        request["input_text"] = "那封信为什么没寄出去？"
        request["allowed_effects"]["letter"] = {"clue_ids": ["unfinished_letter"], "branch_id": ""}
        result = gateway.offline_dialogue(request, self.topics)
        self.assertEqual(result["intent"], "letter")
        self.assertEqual(result["clue_ids"], ["unfinished_letter"])
        request["input_text"] = "我想知道那件事。"
        result = gateway.offline_dialogue(request, self.topics)
        self.assertTrue(result["needs_clarification"])
        self.assertEqual(result["clue_ids"], [])

    def test_busy_and_release(self):
        limits = gateway.Limits(concurrent=1, per_minute=2)
        self.assertTrue(limits.acquire())
        self.assertFalse(limits.acquire())
        limits.release()
        self.assertTrue(limits.acquire())
        limits.release()
        self.assertFalse(limits.acquire())

    def test_generated_profile_cannot_overwrite_identity(self):
        source = {"profile": {"npc_id": "npc_1", "name": "江知夏", "role": "插画师",
                              "personality": "细心内敛", "birthday": "1998-02-03"}}
        self.assertEqual(gateway.prepare_profile(source)["npc_id"], "npc_1")
        proposal = {"background": "住在街角。", "preference": "喜欢画植物。", "speech_style": "说话温和。"}
        self.assertEqual(gateway.normalize_profile(proposal), proposal)
        with self.assertRaises(ValueError):
            gateway.normalize_profile({**proposal, "npc_id": "different"})
        with self.assertRaises(ValueError):
            gateway.prepare_profile({"profile": {**source["profile"], "hidden": "secret"}})

    def test_constrained_profile_choices_and_deterministic_fallback(self):
        options = gateway.load_profile_options()
        profile = {"npc_id": "npc_1", "name": "江知夏", "role": "插画师", "personality": "细心", "birthday": "1998-02-03"}
        choices = gateway.offline_profile_choices(profile, options)
        self.assertEqual(gateway.normalize_profile_choices(choices, options), choices)
        self.assertEqual(gateway.offline_profile_choices(profile, options), choices)
        with self.assertRaises(ValueError):
            gateway.normalize_profile_choices({**choices, "background": "unapproved"}, options)

    def test_event_proposal_only_uses_authorized_candidates_and_shared_memory(self):
        request = {"npc": {"name": "林照晚", "role": "旧书修复师", "secret": "secret"}, "case_id": "invitation", "trigger_id": "event_1",
                   "known_memories": [{"audience": "both", "kind": "feedback", "text": "已经见面"},
                                      {"audience": "npc", "kind": "event", "text": "未披露"}],
                   "candidates": [{"candidate_id": "no_action", "label": "暂不行动"}, {"candidate_id": "ref_1", "label": "考虑介绍朋友"}]}
        context = gateway.prepare_event_proposal(request)
        self.assertEqual(len(context["known_memories"]), 1)
        self.assertNotIn("未披露", json.dumps(context, ensure_ascii=False))
        self.assertEqual(gateway.normalize_event_proposal({"candidate_id": "ref_1"}, context)["trigger_id"], "event_1")
        with self.assertRaises(ValueError):
            gateway.normalize_event_proposal({"candidate_id": "invented"}, context)
        with self.assertRaises(ValueError):
            gateway.prepare_event_proposal({**request, "candidates": request["candidates"][1:]})

    def test_upstream_truncation_is_rejected(self):
        class FakeResponse:
            status = 200
            def __enter__(self):
                return self
            def __exit__(self, *_args):
                return False
            def read(self, _limit):
                return json.dumps({"choices": [{"finish_reason": "length", "message": {"content": '{"intent":"invitation"}'}}]}).encode()
        config = {"url": "https://example.invalid", "api_key": "test", "model": "test", "timeout": 3}
        with patch.object(gateway.urllib.request, "urlopen", return_value=FakeResponse()):
            with self.assertRaisesRegex(ValueError, "did not finish"):
                gateway.call_upstream("system", {}, config)
    def test_http_success_and_invalid_upstream(self):
        responses = iter([{"intent": "invitation", "reply_text": "这里有手写附言。"},
                          {"intent": "letter", "reply_text": "unapproved"}])
        options = gateway.load_profile_options()
        choice_replies = iter([{"background": "neighborhood", "preference": "plants", "speech_style": "gentle"},
                               {"background": "forged", "preference": "plants", "speech_style": "gentle"}])
        handler = gateway.make_handler({"gateway_token": "test-secret"}, self.topics, gateway.Limits(),
                                       lambda _context, _config: next(responses),
                                       lambda _context, _config: {"background": "住在街角。", "preference": "喜欢植物。", "speech_style": "说话温和。"},
                                       profile_choice_model=lambda _context, _config, _options: next(choice_replies), profile_options=options,
                                       event_model=lambda _context, _config: {"candidate_id": "invented"})
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = "http://127.0.0.1:%d/v1/dialogue" % server.server_port
        try:
            def request():
                return urllib.request.Request(url, data=json.dumps(sample()).encode(), headers={"Content-Type": "application/json", "X-Magic-Gateway-Token": "test-secret"})
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(urllib.request.Request(url, data=b"{}"), timeout=3)
            self.assertEqual(error.exception.code, 401)
            with urllib.request.urlopen(request(), timeout=3) as response:
                result = json.load(response)
                self.assertEqual(result["intent"], "invitation")
                self.assertEqual(result["clue_ids"], ["invitation_note"])
            with urllib.request.urlopen(request(), timeout=3) as response:
                fallback = json.load(response)
                self.assertEqual(response.headers.get("X-Magic-Mode"), "offline")
                self.assertEqual(fallback["intent"], "invitation")
                self.assertEqual(fallback["reply_text"], self.topics["invitation"]["reply_text"])
            profile = {"profile": {"npc_id": "npc_1", "name": "江知夏", "role": "插画师", "personality": "细心", "birthday": "1998-02-03"}}
            profile_request = urllib.request.Request(url.replace("/dialogue", "/profile"), data=json.dumps(profile).encode(), headers={"Content-Type": "application/json", "X-Magic-Gateway-Token": "test-secret"})
            with urllib.request.urlopen(profile_request, timeout=3) as response:
                self.assertEqual(json.load(response)["speech_style"], "说话温和。")
            choices_request = urllib.request.Request(url.replace("/dialogue", "/profile/choices"), data=json.dumps(profile).encode(), headers={"Content-Type": "application/json", "X-Magic-Gateway-Token": "test-secret"})
            with urllib.request.urlopen(choices_request, timeout=3) as response:
                self.assertEqual(response.headers.get("X-Magic-Mode"), "online")
                self.assertEqual(json.load(response)["background"], "neighborhood")
            with urllib.request.urlopen(choices_request, timeout=3) as response:
                self.assertEqual(response.headers.get("X-Magic-Mode"), "offline")
                self.assertIn(json.load(response)["background"], options["background"])
            event = {"npc": {"name": "林照晚", "role": "旧书修复师"}, "case_id": "invitation", "trigger_id": "event_1",
                     "candidates": [{"candidate_id": "no_action", "label": "暂不行动"}, {"candidate_id": "ref_1", "label": "考虑推荐"}]}
            event_request = urllib.request.Request(url.replace("/dialogue", "/event-proposal"), data=json.dumps(event).encode(), headers={"Content-Type": "application/json", "X-Magic-Gateway-Token": "test-secret"})
            with urllib.request.urlopen(event_request, timeout=3) as response:
                self.assertEqual(response.headers.get("X-Magic-Mode"), "offline")
                self.assertEqual(json.load(response), {"candidate_id": "no_action", "trigger_id": "event_1"})
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()

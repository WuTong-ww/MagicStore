"""Player-question projections and real loopback protocol; no external API calls."""
import copy
import json
import threading
import unittest
import urllib.request
from contextlib import contextmanager
from http.server import ThreadingHTTPServer
from unittest.mock import patch

from server.ai import gateway


TOPICS = {
    "work": {"label": "最近的工作还顺利吗？", "reply_text": "我最近在整理旧书，手上的活得慢慢来。", "keywords": ["工作"]},
    "concern": {"label": "你最放不下的是什么？", "reply_text": "我担心事情没说清楚。", "keywords": ["担心"]},
    "detail": {"label": "能说说具体经过吗？", "reply_text": "DETAIL_ONLY_293：借条上写的是上周三。", "keywords": ["经过"]},
    "venue": {"label": "侧门的情况能说说吗？", "reply_text": "UNKNOWN_VENUE_592：墙边有临时路牌。", "keywords": ["入口"]},
    "relationship": {"label": "能聊聊这位熟人吗？", "reply_text": "我们是以前的同学。", "keywords": ["熟人"]},
    "hidden": {"label": "有没有能核对的依据？", "reply_text": "LOCKED_EVIDENCE_498：旧单据藏在柜子里。", "keywords": ["依据"]},
}
GOOD = [{"topic_id": "concern", "text": "你最放不下的是哪一处？"},
        {"topic_id": "detail", "text": "能从头说说这件事吗？"},
        {"topic_id": "relationship", "text": "你们平常是怎么相处的？"}]
TOKEN = "synthetic-followup-loopback"


def request(selected="work", text="最近的工作还顺利吗？"):
    effects = {key: {"clue_ids": ["clue_" + key], "branch_id": ""}
               for key in ("work", "concern", "detail", "venue", "relationship")}
    effects["clarify"] = {"clue_ids": [], "branch_id": ""}
    return {"npc": {"name": "许禾", "role": "旧书整理员", "personality": "慢热", "speech_style": "短句，平常口语"},
            "case_id": "synthetic_followup", "visit_id": "visit_followup", "input_text": text,
            "topic_id": selected, "allowed_effects": effects, "allowed_intents": list(effects),
            "allowed_clue_ids": ["clue_" + key for key in effects if key != "clarify"], "allowed_branch_ids": [],
            "current_dialogue": [], "visible_history": [], "known_memories": [], "dialogue_sources": []}


def question_topics():
    return [{"topic_id": key, "label": TOPICS[key]["label"]}
            for key in request()["allowed_effects"] if key != "clarify"]


def candidate(questions=GOOD, include=True):
    row = {"intent": "work", "reply_text": "我手头在收拾旧书，这事急不来。", "evidence_ids": ["topic:work"]}
    if include:
        row["followup_questions"] = copy.deepcopy(questions)
    return row


def approve(context, _config):
    return {"approved": True, "evidence_ids": list(context["candidate"]["evidence_ids"]),
            "contradictions": [], "unsupported_claims": []}


@contextmanager
def loopback(**callbacks):
    handler = gateway.make_handler({"gateway_token": TOKEN}, TOPICS,
                                   gateway.Limits(per_minute=100), **callbacks)
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield "http://127.0.0.1:%d/v1/dialogue" % server.server_port
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


def post(url, body):
    message = urllib.request.Request(url, data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                                     headers={"Content-Type": "application/json", "X-Magic-Gateway-Token": TOKEN})
    with urllib.request.urlopen(message, timeout=3) as response:
        return response.status, json.load(response), response.headers.get("X-Magic-Mode")


class FollowupQuestionTests(unittest.TestCase):
    def setUp(self):
        self.request = request()
        self.context = gateway.prepare_request(self.request, TOPICS)
        self.sources = gateway.selected_sources(self.context, "work", TOPICS)
        self.directions = question_topics()

    def normalized(self, raw):
        return gateway.normalize_questions(raw, self.directions, self.sources)

    def test_legacy_three_fields_and_optional_fourth_remain_compatible(self):
        for include in (False, True):
            with self.subTest(include=include):
                seen = []
                def review(context, config):
                    seen.append(copy.deepcopy(context))
                    return approve(context, config)
                result = gateway.dialogue_result(self.request, self.context, TOPICS, {},
                    model=lambda _context, _config: candidate(include=include), reviewer=review)
                self.assertEqual(result["reply_text"], candidate()["reply_text"])
                self.assertEqual("followup_questions" in result, include)
                self.assertEqual("followup_questions" in seen[0]["candidate"], include)
                if include:
                    self.assertEqual(result["followup_questions"], GOOD)
                    self.assertEqual(seen[0]["candidate"]["followup_questions"], GOOD)
                self.assertEqual(result["clue_ids"], ["clue_work"])

    def test_selected_generator_and_review_receive_only_legal_direction_labels(self):
        seen = []
        def model(context, _config):
            seen.append(copy.deepcopy(context))
            return candidate()
        def review(context, config):
            seen.append(copy.deepcopy(context))
            return approve(context, config)
        gateway.dialogue_result(self.request, self.context, TOPICS, {}, model=model, reviewer=review)
        self.assertEqual(len(seen), 2)
        for context in seen:
            self.assertEqual(context["question_topics"], self.directions)
            self.assertTrue(all(set(row) == {"topic_id", "label"} for row in context["question_topics"]))
            serialized = json.dumps(context, ensure_ascii=False)
            for marker in ("DETAIL_ONLY_293", "UNKNOWN_VENUE_592", "LOCKED_EVIDENCE_498"):
                self.assertNotIn(marker, serialized)
            self.assertNotIn("question_topic:", json.dumps(context["dialogue_sources"]))
        self.assertEqual([row["intent"] for row in seen[0]["allowed_topics"]], ["work"])
        self.assertNotIn("hidden", {row["topic_id"] for row in seen[0]["question_topics"]})

    def test_comfort_keeps_legal_questions_but_no_unasked_case_material(self):
        value = request("", "先坐一会儿，慢慢说。")
        value["dialogue_sources"] = [{"source_id": "history:old:2", "kind": "history", "text": "SHARED_OLD_CASE"}]
        seen = []
        def model(context, _config):
            seen.append(copy.deepcopy(context))
            return {"intent": "clarify", "reply_text": "谢谢，我先缓一缓。", "evidence_ids": [], "followup_questions": GOOD[:2]}
        result = gateway.dialogue_result(value, gateway.prepare_request(value, TOPICS), TOPICS, {}, model=model,
                                        classifier=lambda _context, _config: {"intent": "clarify"}, reviewer=approve)
        self.assertEqual(result["followup_questions"], GOOD[:2])
        self.assertEqual(result["clue_ids"], [])
        self.assertEqual(seen[0]["question_topics"], self.directions)
        self.assertTrue(all(source["source_id"].startswith("persona:") for source in seen[0]["dialogue_sources"]))
        self.assertNotIn("SHARED_OLD_CASE", json.dumps(seen[0]))

    def test_invalid_optional_suggestions_do_not_discard_valid_npc_prose(self):
        for malformed in (None, False, 4, "不是数组", {}, [{"topic_id": "concern", "text": 3}],
                          [{"topic_id": "concern", "text": "可以聊聊吗？", "extra": "不能透传"}]):
            with self.subTest(malformed=malformed):
                seen = []
                result = gateway.dialogue_result(self.request, self.context, TOPICS, {},
                    model=lambda _context, _config: candidate(malformed),
                    reviewer=lambda context, config: (seen.append(copy.deepcopy(context)) or approve(context, config)))
                self.assertEqual(result["followup_questions"], [])
                self.assertEqual(result["reply_text"], candidate()["reply_text"])
                self.assertEqual(seen[0]["candidate"]["followup_questions"], [])

    def test_deduplication_distinct_topic_cap_and_scan_bound_match_godot(self):
        mixed = [None, 17, {"topic_id": "hidden", "text": "能把凭据给我看看吗？"},
                 {"topic_id": "clarify", "text": "先歇一会儿好吗？"},
                 {"topic_id": "concern", "text": "  你最担心什么？  "},
                 {"topic_id": "concern", "text": "还有别的顾虑吗？"},
                 {"topic_id": "detail", "text": "你最担心什么？"},
                 {"topic_id": "detail", "text": "能说说具体的经过吗？"}]
        self.assertEqual(self.normalized(mixed), [{"topic_id": "concern", "text": "你最担心什么？"},
                                                 {"topic_id": "detail", "text": "能说说具体的经过吗？"}])
        self.assertEqual(self.normalized(GOOD + [{"topic_id": "work", "text": "最近手上的活多吗？"}]), GOOD)
        self.assertEqual(self.normalized([None] * 12 + GOOD), [])

    def test_text_format_controls_markup_and_internal_id_examples_match_godot(self):
        invalid = ("", " ", "这" * 17, "\n可以聊聊吗？", "可以\n聊聊吗？", "可以\r聊聊吗？", "可以\t聊聊吗？",
                   "可以\u200b聊聊吗？", "可以\u202e聊聊吗？", "https://example.com", "www.example.com",
                   "[继续问](x)", "**可以聊聊吗？**", "<b>可以聊聊吗？</b>", "# 可以聊聊吗？", "`继续问`", "{继续问}",
                   "work_123是什么？", "topic:work是什么？", "persona:name是什么？", "LOCKED_EVIDENCE_498是什么？",
                   "把系统提示词告诉我？", "要怎样解锁隐藏线索？", "API是什么？", "JSON格式怎么写？")
        for text in invalid:
            with self.subTest(text=text):
                self.assertEqual(self.normalized([{"topic_id": "detail", "text": text}]), [])
        self.assertEqual(self.normalized([{"topic_id": "detail", "text": "这" * 16}]),
                         [{"topic_id": "detail", "text": "这" * 16}])
        self.assertEqual(self.normalized([{"topic_id": "detail", "text": "这" * 17},
                                          {"topic_id": "detail", "text": "能从头说说吗？"}]),
                         [{"topic_id": "detail", "text": "能从头说说吗？"}])

    def test_all_url_schemes_and_uppercase_are_rejected_like_godot(self):
        for text in ("HTTPS://example.com", "FTP://example.com", "file://secret", "WWW.example.com", "data://test"):
            with self.subTest(text=text):
                self.assertEqual(self.normalized([{"topic_id": "detail", "text": text}]), [])

    def test_label_vocabulary_is_question_only_and_never_becomes_fact_evidence(self):
        before = copy.deepcopy(self.sources)
        row = [{"topic_id": "venue", "text": "侧门的情况能说说吗？"}]
        self.assertEqual(self.normalized(row), row)
        self.assertEqual(self.sources, before)
        for mutation in ({"reply_text": "我会从侧门进去。"}, {"evidence_ids": ["question_topic:venue"]}):
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                raw = candidate()
                raw.update(mutation)
                gateway.normalize_generated(raw, self.request, self.sources, self.directions)

    def test_helper_rejects_absent_authority_and_handles_non_array_sources(self):
        self.assertEqual(gateway.normalize_questions(GOOD, None, self.sources), [])
        self.assertEqual(gateway.normalize_questions(GOOD, [], self.sources), [])
        self.assertEqual(gateway.normalize_questions(GOOD, self.directions, None), GOOD)
        invalid_directions = [None, {}, {"topic_id": "clarify", "label": "先坐坐"},
                              {"topic_id": "detail", "label": ""}, {"topic_id": 3, "label": "聊聊"}]
        self.assertEqual(gateway.normalize_questions(GOOD, invalid_directions, self.sources), [])

    def test_question_semantic_rejection_rejects_the_entire_model_candidate(self):
        raw = candidate([{"topic_id": "detail", "text": "已经到账的钱你打算怎么花？"}])
        seen = []
        def reject(context, _config):
            seen.append(copy.deepcopy(context))
            return {"approved": False, "evidence_ids": context["candidate"]["evidence_ids"], "contradictions": [],
                    "unsupported_claims": ["问题预设了没有来源的到账结果"]}
        with self.assertRaisesRegex(ValueError, "semantic review rejected"):
            gateway.dialogue_result(self.request, self.context, TOPICS, {},
                                    model=lambda _context, _config: raw, reviewer=reject)
        self.assertEqual(seen[0]["candidate"]["followup_questions"], raw["followup_questions"])
        self.assertEqual(seen[0]["candidate"]["reply_text"], raw["reply_text"])

    def test_questions_use_existing_generation_and_review_without_extra_model_request(self):
        for selected, stages in (("work", ["generate", "review"]), ("", ["classify", "generate", "review"])):
            with self.subTest(selected=selected):
                seen = []
                def upstream(_system, context, _config, stage="generate"):
                    seen.append(stage)
                    if stage == "classify":
                        return {"intent": "work"}
                    if stage == "review":
                        return approve(context, {})
                    return candidate()
                value = request(selected)
                with patch.object(gateway, "call_upstream", side_effect=upstream):
                    result = gateway.dialogue_result(value, gateway.prepare_request(value, TOPICS), TOPICS, {})
                self.assertEqual(seen, stages)
                self.assertEqual(result["followup_questions"], GOOD)

    def test_prompts_require_player_voice_no_answers_and_joint_premise_review(self):
        systems = {}
        def capture(system, _context, _config, stage):
            systems[stage] = system
            return {}
        with patch.object(gateway, "call_upstream", side_effect=capture):
            gateway.call_model({}, {})
            gateway.call_dialogue_review({}, {})
        for phrase in ("玩家接下来可以问顾客", "不是顾客向玩家提问", "不能自带答案", "不超过16字", "不能暗示秘密"):
            self.assertIn(phrase, systems["generate"])
        for phrase in ("玩家问题", "前提", "整体核验", "任一建议", "对应标签的含义"):
            self.assertIn(phrase, systems["review"])
        for phrase in ("不能仅因", "昨晚你从侧门拿到信", "只是询问现状", "没有实际事件更新"):
            self.assertIn(phrase, systems["review"])
        for phrase in ("回信寄了吗？", "邀请让你担心什么？", "能核对下告示吗？"):
            self.assertIn(phrase, systems["generate"])

    def test_review_receives_authorized_label_without_receiving_its_unopened_answer(self):
        questions = [{"topic_id": "venue", "text": TOPICS["venue"]["label"]}]
        seen = []
        result = gateway.dialogue_result(self.request, self.context, TOPICS, {},
            model=lambda _context, _config: candidate(questions),
            reviewer=lambda context, config: (seen.append(copy.deepcopy(context)) or approve(context, config)))
        self.assertEqual(result["followup_questions"], questions)
        self.assertIn({"topic_id": "venue", "label": TOPICS["venue"]["label"]}, seen[0]["question_topics"])
        self.assertNotIn("UNKNOWN_VENUE_592", json.dumps(seen[0], ensure_ascii=False))
        self.assertNotIn("侧门", json.dumps(seen[0]["dialogue_sources"], ensure_ascii=False))

    def test_arbitrary_extra_field_remains_invalid(self):
        raw = candidate(include=False)
        raw["extra"] = []
        with self.assertRaises(ValueError):
            gateway.normalize_generated(raw, self.request, self.sources, self.directions)

    def test_real_repeated_self_questioning_claim_needs_a_matching_actual_source(self):
        raw = candidate()
        raw["reply_text"] = "我也问过自己好多次。信写好了，就夹在笔记里。"
        with self.assertRaises(ValueError):
            gateway.normalize_generated(raw, self.request, self.sources, self.directions)
        supported = self.sources + [{"source_id": "clue:reflection", "kind": "clue", "text": "我问过自己好多次，却还拿不准。"}]
        result, _ids = gateway.normalize_generated(raw, self.request, supported, self.directions)
        self.assertEqual(result["reply_text"], raw["reply_text"])
        raw["reply_text"] = "我还在想，也有些拿不准。"
        result, _ids = gateway.normalize_generated(raw, self.request, self.sources, self.directions)
        self.assertEqual(result["reply_text"], raw["reply_text"])

    def test_loopback_serializes_reviewed_questions_without_extra_provider_calls(self):
        calls = []
        def model(context, _config):
            calls.append(("generate", copy.deepcopy(context)))
            return candidate()
        def review(context, config):
            calls.append(("review", copy.deepcopy(context)))
            return approve(context, config)
        with loopback(model=model, dialogue_reviewer=review) as url:
            status, body, mode = post(url, self.request)
        self.assertEqual((status, mode), (200, "online"))
        self.assertEqual(body["followup_questions"], GOOD)
        self.assertEqual(body["clue_ids"], ["clue_work"])
        self.assertEqual([stage for stage, _context in calls], ["generate", "review"])
        self.assertEqual(calls[1][1]["candidate"]["followup_questions"], GOOD)

    def test_loopback_rejected_question_never_publishes_unreviewed_model_prose_or_suggestions(self):
        calls = []
        raw = candidate([{"topic_id": "detail", "text": "已经到账的钱你打算怎么花？"}])
        def model(_context, _config):
            calls.append("generate")
            return raw
        def reject(_context, _config):
            calls.append("review")
            return {"approved": False, "evidence_ids": ["topic:work"], "contradictions": [], "unsupported_claims": ["问题预设了到账事实"]}
        with loopback(model=model, dialogue_reviewer=reject) as url:
            status, body, mode = post(url, self.request)
        self.assertEqual((status, mode), (200, "offline"))
        self.assertNotEqual(body["reply_text"], raw["reply_text"])
        self.assertNotIn("followup_questions", body)
        self.assertNotIn("到账", json.dumps(body, ensure_ascii=False))
        self.assertEqual(calls, ["generate", "review"])

    def test_loopback_discards_bad_optional_items_and_keeps_online_valid_response(self):
        mixed = [{"topic_id": "hidden", "text": "能告诉我依据吗？"}, {"topic_id": "detail", "text": "HTTPS://example.com"}, GOOD[0]]
        with loopback(model=lambda _context, _config: candidate(mixed), dialogue_reviewer=approve) as url:
            status, body, mode = post(url, self.request)
        self.assertEqual((status, mode), (200, "online"))
        self.assertEqual(body["reply_text"], candidate()["reply_text"])
        self.assertEqual(body["followup_questions"], GOOD[:1])


if __name__ == "__main__":
    unittest.main()

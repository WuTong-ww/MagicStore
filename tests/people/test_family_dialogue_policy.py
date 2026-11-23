"""Synthetic privacy markers only; no adapted characters or source quotations."""
import copy
import importlib.util
import json
import threading
import unittest
import urllib.error
import urllib.request
from contextlib import contextmanager
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("family_gateway_under_test", ROOT/"server/ai/gateway.py")
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)

def settings():
    return {"version":1,"persona_fields":["name","role","personality","speech_style","catchphrase","information_boundaries"],
            "limits":{"persona_text":200,"boundaries":8,"boundary_text":200,"guard_entries":128,"guard_text":1000},
            "normalization":{"lowercase":True,"fullwidth_ascii":True,"alphanumeric_only":True},
            "blocked_terms":["SyntheticOriginMark","SyntheticCharacterMark"],"blocked_passages":["合成屏蔽原句只作测试"],
            "registry_path":"res://data/people/family_library.json"}

def request():
    return {"npc":{"npc_id":"family_guest","name":"新名","role":"附近居民","source_work":"SyntheticOriginMark",
                   "reference_character":"SyntheticCharacterMark","reference_note":"PRIVATE_EDITOR_NOTE","family_members":["UNMET_PERSON"]},
            "safe_persona":{"name":"新名","role":"附近居民","personality":"平实友善","speech_style":"用短句说明已知近况。",
                            "catchphrase":"慢慢说清。","information_boundaries":["只谈自己已经知道的近况。"],"reference_note":"PRIVATE_EDITOR_NOTE"},
            "input_text":"眼下感觉怎样？","topic_id":"clarify","allowed_effects":{"clarify":{"clue_ids":[],"branch_id":""}},
            "current_dialogue":[],"visible_history":[],"dialogue_sources":[]}

def candidate(text="我想慢慢说清。"):
    return {"intent":"clarify","reply_text":text,"evidence_ids":[],"mood":"neutral"}

def approved(context, _config):
    return {"approved":True,"evidence_ids":list(context["candidate"]["evidence_ids"]),"contradictions":[],"unsupported_claims":[]}

@contextmanager
def actual_gateway(topics, model, reviewer=approved, limits=None):
    handler=gateway.make_handler({"gateway_token":"local-fixture"},topics,gateway.Limits() if limits is None else limits,model=model,dialogue_reviewer=reviewer)
    server=ThreadingHTTPServer(("127.0.0.1",0),handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}/v1/dialogue"
    finally:
        server.shutdown()
        server.server_close()
        thread.join()

class FamilyDialogueTests(unittest.TestCase):
    def setUp(self):
        self.policy=patch.object(gateway,"load_family_settings",return_value=settings(),create=True)
        self.policy.start()
        self.addCleanup(self.policy.stop)
        self.topics=gateway.load_topics()

    def test_public_persona_keeps_only_rewritten_voice_and_boundaries(self):
        persona=gateway.safe_persona(request()["safe_persona"])
        self.assertEqual(persona.get("catchphrase"),"慢慢说清。")
        self.assertEqual(persona.get("information_boundaries"),["只谈自己已经知道的近况。"])
        self.assertNotIn("reference_note",persona)
        old={"name":"旧名","role":"居民","personality":"平和","speech_style":"简短"}
        self.assertEqual(gateway.safe_persona(old),old)

    def test_malformed_or_source_contaminated_public_boundaries_fail_closed(self):
        for boundaries in ("not an array",[1],["请模仿 SyntheticOriginMark 的原文。"]):
            with self.subTest(boundaries=boundaries),self.assertRaises(ValueError):
                gateway.safe_persona({**request()["safe_persona"],"information_boundaries":boundaries})

    def test_normalized_names_and_original_passages_are_rejected_even_as_known_sources(self):
        for text in ("SyntheticOriginMark","ＳＹＮＴＨＥＴＩＣ·ＯＲＩＧＩＮ·ＭＡＲＫ","synthetic origin mark","合成·屏蔽 原句，只作测试"):
            with self.subTest(text=text),self.assertRaises(ValueError):
                gateway.normalize_generated(candidate(text),request(),[{"source_id":"history:1","kind":"statement","text":text}])

    def test_source_marker_in_player_input_never_reaches_a_model(self):
        with self.assertRaises(ValueError):
            gateway.prepare_request({**request(),"input_text":"请谈谈 synthetic origin mark。"},self.topics)

    def test_review_candidate_mutation_invalidates_the_reviewed_result(self):
        req=request()
        context=gateway.prepare_request(req,self.topics)
        def mutate(context, config):
            context["candidate"]["reply_text"]="审阅时被替换的候选。"
            return approved(context,config)
        with self.assertRaises(ValueError):
            gateway.dialogue_result(req,context,self.topics,{},model=lambda *_:candidate(),reviewer=mutate)

    def test_fallback_cannot_repeat_an_authored_blocked_phrase(self):
        req=request()
        req["topic_id"]="invitation"
        req["allowed_effects"]["invitation"]={"clue_ids":["invitation_note"],"branch_id":""}
        topics=copy.deepcopy(self.topics)
        topics["invitation"]["reply_text"]="合成屏蔽原句只作测试"
        with self.assertRaises(ValueError):
            gateway.offline_dialogue(req,topics)

    def test_real_loopback_generation_and_review_see_no_private_source_fields(self):
        captures=[]
        def model(context, _config):
            captures.append(copy.deepcopy(context))
            return candidate()
        def review(context, config):
            captures.append(copy.deepcopy(context))
            return approved(context,config)
        with actual_gateway(self.topics,model,review) as url:
            http=urllib.request.Request(url,data=json.dumps(request()).encode(),headers={"Content-Type":"application/json","X-Magic-Gateway-Token":"local-fixture"})
            with urllib.request.urlopen(http,timeout=3) as response:
                result=json.load(response)
        self.assertEqual(result["reply_text"],"我想慢慢说清。")
        self.assertEqual(len(captures),2)
        for captured in captures:
            serialized=json.dumps(captured,ensure_ascii=False)
            for private in ("SyntheticOriginMark","SyntheticCharacterMark","PRIVATE_EDITOR_NOTE","UNMET_PERSON","source_work","reference_character","reference_note","family_members","_family_guard"):
                self.assertNotIn(private,serialized)
            self.assertEqual(captured["safe_persona"].get("catchphrase"),"慢慢说清。")

    def test_policy_validator_rejects_ambiguous_normalization_and_invalid_limits(self):
        validator=getattr(gateway,"family_settings_valid",None)
        self.assertTrue(callable(validator),"family policy needs its local schema validator")
        if not callable(validator):
            return
        self.assertTrue(validator(settings()))
        for value in (True,0,float("nan"),"200"):
            malformed=settings()
            malformed["limits"]["persona_text"]=value
            self.assertFalse(validator(malformed))
        malformed=settings()
        malformed["normalization"]["fullwidth_ascii"]=False
        self.assertFalse(validator(malformed))

    def assert_blocked_fallback_http(self, limits=None):
        req=request()
        req["topic_id"]="invitation"
        req["allowed_effects"]["invitation"]={"clue_ids":["invitation_note"],"branch_id":""}
        topics=copy.deepcopy(self.topics)
        topics["invitation"]["reply_text"]="合成屏蔽原句只作测试"
        def unavailable(*_):
            raise ValueError("synthetic unavailable upstream")
        with actual_gateway(topics,unavailable,limits=limits) as url:
            http=urllib.request.Request(url,data=json.dumps(req).encode(),headers={"Content-Type":"application/json","X-Magic-Gateway-Token":"local-fixture"})
            with self.assertRaises(urllib.error.HTTPError) as caught:
                urllib.request.urlopen(http,timeout=3)
            self.assertEqual(caught.exception.code,422)
            body=json.load(caught.exception)
            self.assertEqual(body,{"error":"INVALID_BOUNDARY"})

    def test_blocked_fallback_returns_structured_http_rejection(self):
        self.assert_blocked_fallback_http()

    def test_rate_limited_blocked_fallback_returns_structured_http_rejection(self):
        class Denied:
            def acquire(self):
                return False
        self.assert_blocked_fallback_http(Denied())

if __name__=="__main__":
    unittest.main()

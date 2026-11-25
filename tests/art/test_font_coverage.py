# -*- coding: utf-8 -*-
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('font_coverage',ROOT/'tools/check_font_coverage.py')
coverage=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(coverage)

class FontCoverageTests(unittest.TestCase):
    def test_json_escape_recursive_and_embedded_envelope(self):
        value=json.loads('{"\\u96f6":["\\u5e97","{\\"nested\\":\\"\\\\u4eba\\"}"]}')
        found=set().union(*(coverage.harvested(v) for v in coverage.json_strings(value)))
        self.assertTrue({0x96F6,0x5E97,0x4EBA}<=found)

    def test_cjk_extensions_and_compatibility_are_not_skipped(self):
        for cp in (0x3007,0x3400,0x9FFF,0xF900,0x20BB7,0x2F800,0x30000,0x323AF):
            self.assertTrue(coverage.cjk(cp))
        self.assertFalse(coverage.cjk(ord('A')))

    def test_gd_comments_excluded_and_multiline_literals_kept(self):
        source='# "ignored"\nvar a="\\u96f6"\nvar b="""\\u5e97\ntext"""'
        values=list(coverage.gd_strings(source))
        self.assertEqual(len(values),2)
        self.assertTrue({0x96F6,0x5E97}<=set().union(*(coverage.harvested(v) for v in values)))

    def test_escape_forms_and_surrogates_cover_same_rare_character(self):
        for value in (r'\U020BB7',r'\U00020BB7',r'\u{20BB7}',r'\uD842\uDFB7'):
            self.assertIn(0x20BB7,coverage.harvested(value))

    def test_policy_rejects_extra_keys_boolean_or_path_escape(self):
        good=json.loads((ROOT/'data/ui/font_policy.json').read_text(encoding='utf-8'))
        self.assertEqual(coverage.font_policy(good),good)
        for key,value in [('unknown',0),('version',True),('regular','res://assets/fonts/../secret.ttf'),('ascii_range',[32,True])]:
            bad=dict(good);bad[key]=value
            with self.assertRaises(ValueError):coverage.font_policy(bad)

    def test_workspace_fonts_cover_all_tracked_and_new_sources(self):
        result=coverage.inspect(ROOT)
        self.assertTrue(result['success'],json.dumps(result,ensure_ascii=True))
        self.assertGreaterEqual(result['source_files'],418)
        self.assertGreaterEqual(result['counts']['fixtures_json'],18)
        self.assertGreaterEqual(result['cjk_codepoints'],1838)
        self.assertEqual(result['missing_count'],0)
        self.assertTrue(result['sources_unchanged'])
        self.assertFalse(result['payload_text_serialized'])

if __name__=='__main__':unittest.main()

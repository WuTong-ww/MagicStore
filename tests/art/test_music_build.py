# coding: utf-8
"""Synthetic bytes + fake runner only. No real music/encoder/engine is touched."""
from copy import deepcopy
from hashlib import sha256
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import json,os,sys,unittest,importlib.util,struct
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]; SCRIPT=ROOT/'tools/music_build.py'
RUNS=ROOT/'.tools/r3-music/formal-build/test-runs'; RUNS.mkdir(parents=True,exist_ok=True)
b=None
if SCRIPT.is_file():
    spec=importlib.util.spec_from_file_location('formal_music_build',SCRIPT);b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
BASE_CATALOG=json.loads('{\n  "version": 1,\n  "enabled": true,\n  "inventory_count": 21,\n  "crossfade_seconds": 1.5,\n  "clock": {\n    "day_minute": 540,\n    "night_minute": 1080,\n    "minutes_per_day": 1440,\n    "day_slot": "day",\n    "night_slot": "night"\n  },\n  "encoding": {\n    "container": "ogg",\n    "codec": "libvorbis",\n    "vorbis_quality": 6,\n    "status": "not_encoded"\n  },\n  "validation": {\n    "id_max_length": 80,\n    "quality_min": -1,\n    "quality_max": 10,\n    "filename_max_length": 255\n  },\n  "routing": {\n    "page_slots": {\n      "title": "opening",\n      "ending": "ending"\n    },\n    "case_pages": [\n      "consultation"\n    ],\n    "case_slot": "deduction",\n    "ending_slot": "ending"\n  },\n  "runtime_missing_behavior": "silence",\n  "slots": {\n    "opening": {\n      "label": "开场",\n      "track_id": "gentle_breeze",\n      "candidates": [\n        "wanderers_tale"\n      ]\n    },\n    "day": {\n      "label": "白天",\n      "track_id": "sunlight_through_leaves",\n      "candidates": [\n        "golden_gleam"\n      ]\n    },\n    "night": {\n      "label": "夜晚",\n      "track_id": "evening_harmony",\n      "candidates": [\n        "polar_lights"\n      ]\n    },\n    "deduction": {\n      "label": "案件推理",\n      "track_id": "whispering_woods",\n      "candidates": [\n        "drifting_memories"\n      ]\n    },\n    "ending": {\n      "label": "结局",\n      "track_id": "fabric_of_life",\n      "candidates": [\n        "cuddle_clouds"\n      ]\n    }\n  },\n  "tracks": [\n    {\n      "id": "chickens_in_the_meadow",\n      "source_filename": "Chickens In The Meadow.ogg",\n      "duration_seconds": 123.870975,\n      "source_sha256": "707289209a64746c43cf80fc8423b0e5cb2efb5ed5ecf2630f793df09793959a",\n      "runtime_path": "res://assets/audio/music/chickens_in_the_meadow.ogg"\n    },\n    {\n      "id": "cuddle_clouds",\n      "source_filename": "Cuddle Clouds.ogg",\n      "duration_seconds": 134.736848,\n      "source_sha256": "2c27693131f0dfd8a376dcbd2763660d7f13f71cbde47ef46f022e2d9ae2957c",\n      "runtime_path": "res://assets/audio/music/cuddle_clouds.ogg"\n    },\n    {\n      "id": "drifting_memories",\n      "source_filename": "Drifting Memories.ogg",\n      "duration_seconds": 135.263152,\n      "source_sha256": "de96baaf77c87bf9aa4a307cbbc2278c13a09b938cd8960313954a8dfcce6864",\n      "runtime_path": "res://assets/audio/music/drifting_memories.ogg"\n    },\n    {\n      "id": "ducks_in_a_pond",\n      "source_filename": "Ducks In A Pond.ogg",\n      "duration_seconds": 150.588231,\n      "source_sha256": "d9768c052bfb22483a709d7d9e742d2f201f25968519124131da3e32c961340e",\n      "runtime_path": "res://assets/audio/music/ducks_in_a_pond.ogg"\n    },\n    {\n      "id": "evening_harmony",\n      "source_filename": "Evening Harmony.ogg",\n      "duration_seconds": 132.0,\n      "source_sha256": "71701ca53aa31d375d5544e590aec818a8326765f98d884c130c7b30e09da43c",\n      "runtime_path": "res://assets/audio/music/evening_harmony.ogg"\n    },\n    {\n      "id": "fabric_of_life",\n      "source_filename": "Fabric Of Life.ogg",\n      "duration_seconds": 128.0,\n      "source_sha256": "8622ec2d6391153a52fe53cfc278a53fa62bf03a46ca6215df98a57f63f5f573",\n      "runtime_path": "res://assets/audio/music/fabric_of_life.ogg"\n    },\n    {\n      "id": "far_far_away",\n      "source_filename": "Far Far Away.ogg",\n      "duration_seconds": 147.692313,\n      "source_sha256": "442728b1fbac52fdb8549b2634d31b0fe176e2918f3051f88580033075ff2ab8",\n      "runtime_path": "res://assets/audio/music/far_far_away.ogg"\n    },\n    {\n      "id": "floating_dream",\n      "source_filename": "Floating Dream.ogg",\n      "duration_seconds": 247.619048,\n      "source_sha256": "2a72c47a37ce2595b20642dacfa76a362b46c756e0bea32e0ba84cf562335331",\n      "runtime_path": "res://assets/audio/music/floating_dream.ogg"\n    },\n    {\n      "id": "forgotten_biomes",\n      "source_filename": "Forgotten Biomes.ogg",\n      "duration_seconds": 137.678571,\n      "source_sha256": "fe83415ca737d9f49af7ba8267a630750b8243369a1ec9048851756f13b88d0c",\n      "runtime_path": "res://assets/audio/music/forgotten_biomes.ogg"\n    },\n    {\n      "id": "gentle_breeze",\n      "source_filename": "Gentle Breeze.ogg",\n      "duration_seconds": 180.0,\n      "source_sha256": "65f71595d14ed5fabb814e995fe5f8d931b061f64fbda532e7ab86d7ebfa05da",\n      "runtime_path": "res://assets/audio/music/gentle_breeze.ogg"\n    },\n    {\n      "id": "golden_gleam",\n      "source_filename": "Golden Gleam.ogg",\n      "duration_seconds": 137.777778,\n      "source_sha256": "95cfffde10308b9caee38f714b08031873e5fff098da08b60a9e011b0fbe2751",\n      "runtime_path": "res://assets/audio/music/golden_gleam.ogg"\n    },\n    {\n      "id": "pineapple_under_the_sea",\n      "source_filename": "Pineapple Under The Sea.ogg",\n      "duration_seconds": 115.2,\n      "source_sha256": "d4b72e7bfb3e9f00a5ad3fcfffce45271853a337ed64035980f7679009e179e2",\n      "runtime_path": "res://assets/audio/music/pineapple_under_the_sea.ogg"\n    },\n    {\n      "id": "polar_lights",\n      "source_filename": "Polar Lights.ogg",\n      "duration_seconds": 174.545465,\n      "source_sha256": "389d8f43b5133d32d580c9782859cc1fcf512ea960cc4c32a9ecacda1457c70d",\n      "runtime_path": "res://assets/audio/music/polar_lights.ogg"\n    },\n    {\n      "id": "sheep",\n      "source_filename": "Sheep.ogg",\n      "duration_seconds": 169.411769,\n      "source_sha256": "306ef172d216f5cebc3a2cefd7cd1df32860a32f6251b4d2737676ac80396b53",\n      "runtime_path": "res://assets/audio/music/sheep.ogg"\n    },\n    {\n      "id": "strange_worlds",\n      "source_filename": "Strange Worlds.ogg",\n      "duration_seconds": 124.137937,\n      "source_sha256": "a8208c6dac669e10fbf459730bdf5f8da59c5592c4fd2f999886a4077727a5d8",\n      "runtime_path": "res://assets/audio/music/strange_worlds.ogg"\n    },\n    {\n      "id": "sunlight_through_leaves",\n      "source_filename": "Sunlight Through Leaves.ogg",\n      "duration_seconds": 144.0,\n      "source_sha256": "f9adb44e02947ab36a34300c30243b88d1c9fa6f80d52a5f6fe7bf54561d6799",\n      "runtime_path": "res://assets/audio/music/sunlight_through_leaves.ogg"\n    },\n    {\n      "id": "wanderers_tale",\n      "source_filename": "Wanderer\'s Tale.ogg",\n      "duration_seconds": 172.631587,\n      "source_sha256": "fb8115cd63b5c9b2dde4ddd22419876937c5379584da63e0fbafece6be194558",\n      "runtime_path": "res://assets/audio/music/wanderers_tale.ogg"\n    },\n    {\n      "id": "what_clouds_are_made_of",\n      "source_filename": "What Clouds Are Made Of.ogg",\n      "duration_seconds": 187.317075,\n      "source_sha256": "0304bda09affd95428df987686f45e8dd8c28c71691d7f1124f4889b3c44573b",\n      "runtime_path": "res://assets/audio/music/what_clouds_are_made_of.ogg"\n    },\n    {\n      "id": "whispering_woods",\n      "source_filename": "Whispering Woods.ogg",\n      "duration_seconds": 133.331429,\n      "source_sha256": "93597af7f6ae1cbf6b0bf68caa931d45dc8695a3baaf5910b402336ce8a76f0a",\n      "runtime_path": "res://assets/audio/music/whispering_woods.ogg"\n    },\n    {\n      "id": "wildflowers_by_the_river",\n      "source_filename": "Wildflowers By The River.ogg",\n      "duration_seconds": 153.6,\n      "source_sha256": "9c664315fc537650555b0ed085c8ba450add182bf36ba0f5e73cc113d7a0a42a",\n      "runtime_path": "res://assets/audio/music/wildflowers_by_the_river.ogg"\n    },\n    {\n      "id": "wind_over_the_trees",\n      "source_filename": "Wind Over The Trees.ogg",\n      "duration_seconds": 155.675669,\n      "source_sha256": "a28cef3ac20bc906a4d50a405bad12dabe0365b9fb72bcb62309c1e79fe78fa5",\n      "runtime_path": "res://assets/audio/music/wind_over_the_trees.ogg"\n    }\n  ],\n  "source": {\n    "author": "Pizza Doggy",\n    "url": "https://pizzadoggy.itch.io/cozy-tunes",\n    "license": {\n      "type": "custom license",\n      "document_date": "2026-11-01",\n      "official_upload_id": "20743451",\n      "document_sha256": "6416675b7f0696a8be0a9eea57e0dd441b815ee5dce6501f6aaff43be2713e88",\n      "historical_local_pack_license_proven": false\n    },\n    "metadata_inventory_sha256": "c958dc2bcb2b7a88c707d7e324e6f8e3b884cecabb166bab50513098873a927a",\n    "selection_basis": "filename_only",\n    "listening_review": "not_performed"\n  },\n  "copy": {\n    "catalog_title": "背景音乐",\n    "missing_runtime": "本地音乐缺失时保持静音。",\n    "selection_note": "初选与候补仅按曲名意象决定，均未试听。",\n    "metadata_note": "容器时长元数据不代表循环接缝、响度或风格已经验收。",\n    "license_note": "当前官方文本是自定义许可；本地包取得时的许可版本尚未证实。"\n  }\n}\n')
def fixture_catalog():
    value=deepcopy(BASE_CATALOG)
    value['encoding'].pop('status',None);value['encoding']['policy']='local_outputs_untracked'
    for row in value['tracks']:row['duration_seconds']=1.0
    return value

class FakeRunner:
    def __init__(self,root,tag='A',fail_at=None,empty_at=None,help_text=None,version_text=None):
        self.root=root; self.tag=tag; self.calls=[]; self.jobs=0; self.fail_at=fail_at; self.empty_at=empty_at
        self.help_text='Encoder libvorbis [SYNTHETIC FAKE DECLARATION]:\n' if help_text is None else help_text
        self.version_text='ffmpeg version SYNTHETIC_FAKE\n' if version_text is None else version_text
    def __call__(self,argv):
        self.calls.append(list(argv))
        if argv[-1]=='-version': return {'exit_code':0,'stdout':self.version_text,'stderr':''}
        if 'encoder=libvorbis' in argv: return {'exit_code':0,'stdout':self.help_text,'stderr':''}
        if '-c:a' in argv and argv[argv.index('-c:a')+1]=='pcm_s16le':
            Path(argv[-1]).write_bytes(bytes(44100*2*2));return {'exit_code':0,'stdout':'SYNTHETIC fake full decoder','stderr':''}
        self.jobs+=1
        source=Path(argv[argv.index('-i')+1]).resolve(); output=Path(argv[-1]).resolve()
        assert self.root in source.parents and self.root in output.parents,'fake runner escaped synthetic fixture'
        if self.jobs==self.fail_at: return {'exit_code':9,'stdout':'synthetic job failure','stderr':'fake encoder failed'}
        output.write_bytes(b'' if self.jobs==self.empty_at else b'SYNTHETIC NON-OGG OUTPUT '+self.tag.encode()+sha256(source.read_bytes()).digest())
        return {'exit_code':0,'stdout':'fake encoder completed synthetic bytes','stderr':'no codec, format or audio quality validated'}

class BuildContracts(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(b,'MUSIC build helper is not implemented')
        self.temp=TemporaryDirectory(dir=str(RUNS)); self.root=Path(self.temp.name).resolve()
        self.assertEqual(self.root.parent,RUNS.resolve()); self.addCleanup(self.temp.cleanup)
        self.source=self.root/'synthetic-source'; self.runtime=self.root/'runtime'; self.work=self.root/'work'
        self.source.mkdir(); (self.root/'encoder').mkdir(); self.encoder=self.root/'encoder/fake.exe'; self.encoder.write_bytes(b'NOT AN EXECUTABLE: SYNTHETIC ENCODER A')
        self.catalog=fixture_catalog()
        selected={slot['track_id'] for slot in self.catalog['slots'].values()}
        for row in self.catalog['tracks']:
            if row['id'] in selected:
                payload=('SYNTHETIC INPUT, NOT MUSIC: '+row['id']).encode(); (self.source/row['source_filename']).write_bytes(payload); row['source_sha256']=sha256(payload).hexdigest()
        self.runner=FakeRunner(self.root)
        self.audio_guard=patch.object(b,'inspect_vorbis',return_value={'channels':2,'sample_rate':44100,'eos_granule':44100,'duration_seconds':1.0,'all_page_crc_valid':True,'packet_and_sequence_continuity':True,'bos_eos_valid':True});self.audio_guard.start();self.addCleanup(self.audio_guard.stop)
        self.guard=patch.object(b.subprocess,'run',side_effect=AssertionError('REAL SUBPROCESS IS FORBIDDEN IN THIS TEST'))
        self.guard.start(); self.addCleanup(self.guard.stop)
    def call(self,**kwargs):
        params={'encoder':self.encoder,'encoder_sha256':b.sha_file(self.encoder),'runner':self.runner,'apply':True,'with_music':True}
        params.update(kwargs)
        return b.build_music(self.catalog,self.source,self.runtime,self.work,**params)
    def files(self):
        return {path.name:path.read_bytes() for path in self.runtime.glob('*.ogg')} if self.runtime.exists() else {}
    def source_snapshot(self): return {path.name:(path.read_bytes(),path.stat().st_mtime_ns) for path in self.source.iterdir()}
    def establish_owned(self):
        result=self.call(); self.assertEqual(result['status'],'complete'); return self.files()

    def test_01_default_dry_run_executes_nothing_and_writes_no_runtime_or_work(self):
        before=self.source_snapshot(); result=b.build_music(self.catalog,self.source,self.runtime,self.work,runner=self.runner)
        self.assertEqual(result['status'],'dry_run'); self.assertEqual(self.runner.calls,[]); self.assertFalse(self.runtime.exists()); self.assertFalse(self.work.exists()); self.assertEqual(before,self.source_snapshot())

    def test_02_public_missing_source_is_silent_but_with_music_fails(self):
        next(self.source.iterdir()).unlink()
        self.runtime.mkdir(); old=self.runtime/'old-user-resource.ogg'; old.write_bytes(b'USER OLD RESOURCE, MUST NOT DELETE')
        silent=self.call(with_music=False); self.assertEqual(silent['status'],'silent'); self.assertEqual(silent['encoded_count'],0); self.assertEqual(self.runner.calls,[]); self.assertIs(silent.get('requires_public_export_exclusion'),True); self.assertEqual(old.read_bytes(),b'USER OLD RESOURCE, MUST NOT DELETE')
        strict=self.call(); self.assertEqual(strict['status'],'failed'); self.assertIn('requires every',strict['error']); self.assertEqual(strict['encoded_count'],0); self.assertEqual(self.runner.calls,[])

    def test_03_selected_slots_deduplicate_and_candidates_are_not_built(self):
        primary=self.catalog['slots']['opening']['track_id']; self.catalog['slots']['day']['track_id']=primary
        result=self.call(); self.assertEqual(result['status'],'complete'); self.assertEqual(len(result['selected_ids']),4); self.assertEqual(result['encoded_count'],4); self.assertEqual(self.runner.jobs,4); self.assertEqual(len(self.files()),4)

    def test_04_all_source_hashes_are_preflighted_before_any_command(self):
        selected=b.selected_tracks(self.catalog); last=selected[-1]; (self.source/last['source_filename']).write_bytes(b'SYNTHETIC WRONG HASH')
        result=self.call(); self.assertEqual(result['status'],'failed'); self.assertIn('source SHA',result['error']); self.assertEqual(self.runner.calls,[]); self.assertEqual(result['encoded_count'],0); self.assertEqual(self.files(),{})

    def test_05_encoder_hash_must_match_before_version_help_or_encode(self):
        result=self.call(encoder_sha256='0'*64); self.assertEqual(result['status'],'failed'); self.assertIn('encoder SHA',result['error']); self.assertEqual(self.runner.calls,[]); self.assertEqual(self.files(),{})

    def test_06_probe_must_declare_ffmpeg_and_exact_encoder_libvorbis(self):
        for version,help_text in [('unrelated utility','Encoder libvorbis [fake]:'),('ffmpeg version fake','note: libvorbis is mentioned but unavailable'),('ffmpeg version fake','Encoder vorbis [native]:')]:
            self.runner=FakeRunner(self.root,version_text=version,help_text=help_text)
            result=self.call(); self.assertEqual(result['status'],'failed'); self.assertEqual(self.runner.jobs,0); self.assertEqual(self.files(),{})
        self.runner=FakeRunner(self.root,help_text='Encoder libvorbis [fake]:'); self.assertEqual(self.call()['status'],'complete')

    def test_07_probe_failure_has_persisted_text_receipt(self):
        self.runner=FakeRunner(self.root,help_text='not a codec declaration')
        result=self.call(); self.assertEqual(result['status'],'failed'); self.assertIn('receipt_path',result); self.assertTrue(Path(result['receipt_path']).is_file()); self.assertEqual(len(result['commands']),2)

    def test_08_fixed_encoder_argv_and_metadata_stripping_are_recorded(self):
        result=self.call(); self.assertEqual(result['status'],'complete'); self.assertEqual(len(result['commands']),12)
        for record in [row for row in result['commands'] if '-c:a' in row['argv'] and row['argv'][row['argv'].index('-c:a')+1]=='libvorbis']:
            argv=record['argv']; self.assertIn('-nostdin',argv); self.assertIn('-n',argv)
            self.assertEqual(argv[argv.index('-c:a')+1],'libvorbis'); self.assertEqual(argv[argv.index('-q:a')+1],str(self.catalog['encoding']['vorbis_quality'])); self.assertEqual(argv[argv.index('-map_metadata')+1],'-1'); self.assertEqual(argv[argv.index('-f')+1],'ogg'); self.assertEqual(argv[argv.index('-map')+1],'0:a:0')
            self.assertEqual(record['exit_code'],0); self.assertIsInstance(record['stdout'],str); self.assertIsInstance(record['stderr'],str)
        self.assertFalse(result['all_files_atomic']); self.assertEqual(result['runner_mode'],'injected')
        for key in ['ogg_structure','channels_rate_duration_eos','decode_integrity','actual_q6_quality']: self.assertFalse(result['checks'][key])

    def test_09_all_staging_completes_before_first_publish_and_source_is_unchanged(self):
        before=self.source_snapshot(); publications=[]
        def publish(source,target):
            self.assertEqual(self.runner.jobs,5); self.assertEqual(len(list(source.parent.glob('*.ogg'))),5-len(publications)); publications.append(target.name); os.replace(source,target)
        result=self.call(publisher=publish); self.assertEqual(result['status'],'complete'); self.assertEqual(len(publications),5); self.assertEqual(result['published_count'],5); self.assertEqual(before,self.source_snapshot())

    def test_10_encode_failure_preserves_all_old_runtime_outputs(self):
        old=self.establish_owned(); self.encoder.write_bytes(b'NOT EXECUTABLE: SYNTHETIC ENCODER B'); self.runner=FakeRunner(self.root,tag='B',fail_at=2)
        result=self.call(); self.assertEqual(result['status'],'failed'); self.assertEqual(result['phase'],'encode'); self.assertEqual(self.files(),old); self.assertEqual(result['published_count'],0); self.assertTrue(Path(result['receipt_path']).is_file())

    def test_11_success_exit_with_empty_output_is_not_accepted(self):
        self.runner=FakeRunner(self.root,empty_at=2); result=self.call()
        self.assertEqual(result['status'],'failed'); self.assertIn('nonempty',result['error']); self.assertEqual(result['published_count'],0); self.assertEqual(self.files(),{})

    def test_12_unowned_existing_outputs_are_never_overwritten(self):
        self.runtime.mkdir(); row=b.selected_tracks(self.catalog)[0]; target=self.runtime/(row['id']+'.ogg'); target.write_bytes(b'USER RESOURCE, NOT HELPER OWNED')
        result=self.call(); self.assertEqual(result['status'],'failed'); self.assertIn('unowned',result['error']); self.assertEqual(target.read_bytes(),b'USER RESOURCE, NOT HELPER OWNED'); self.assertEqual(self.runner.calls,[])

    def test_13_owned_modified_output_is_not_silently_overwritten(self):
        self.establish_owned(); path=next(self.runtime.glob('*.ogg')); path.write_bytes(b'USER MODIFIED OLD OUTPUT'); self.runner=FakeRunner(self.root)
        result=self.call(); self.assertEqual(result['status'],'failed'); self.assertIn('changed outside',result['error']); self.assertEqual(self.runner.calls,[]); self.assertEqual(path.read_bytes(),b'USER MODIFIED OLD OUTPUT')

    def test_14_owned_unchanged_outputs_are_sha_verified_and_skipped(self):
        old=self.establish_owned(); self.runner=FakeRunner(self.root)
        result=self.call(); self.assertEqual(result['status'],'complete'); self.assertEqual(result['skipped_count'],5); self.assertEqual(result['encoded_count'],0); self.assertEqual(self.runner.jobs,0); self.assertEqual(self.files(),old)

    def test_15_one_line_slot_change_keeps_unselected_owned_and_unrelated_user_files(self):
        old=self.establish_owned(); self.catalog['slots']['opening']['track_id']=self.catalog['slots']['day']['track_id']; extra=self.runtime/'unrelated-user.txt'; extra.write_text('user',encoding='utf-8'); self.runner=FakeRunner(self.root)
        result=self.call(); self.assertEqual(result['status'],'complete'); self.assertEqual(result['skipped_count'],4); self.assertEqual(result['encoded_count'],0); self.assertEqual(self.files(),old); self.assertEqual(extra.read_text(encoding='utf-8'),'user')

    def test_16_publish_io_failure_is_partial_explicit_and_retryable(self):
        old=self.establish_owned(); self.encoder.write_bytes(b'SYNTHETIC ENCODER B'); self.runner=FakeRunner(self.root,tag='B'); calls=[]
        def publish(source,target):
            calls.append(target)
            if len(calls)==2: raise OSError('synthetic publication I/O failure')
            os.replace(source,target)
        result=self.call(publisher=publish)
        self.assertEqual(result['status'],'failed'); self.assertEqual(result['phase'],'publish'); self.assertFalse(result['all_files_atomic']); self.assertEqual(result['published_count'],1)
        current=self.files(); self.assertNotEqual(current[calls[0].name],old[calls[0].name]); self.assertEqual(current[calls[1].name],old[calls[1].name]); self.assertTrue(result['runtime_observation'])
        self.runner=FakeRunner(self.root,tag='B'); retried=self.call(); self.assertEqual(retried['status'],'complete'); self.assertEqual(retried['skipped_count'],1); self.assertEqual(retried['published_count'],4)

    def test_17_metadata_failure_after_rename_recovers_from_prepublication_journal(self):
        self.establish_owned(); self.encoder.write_bytes(b'SYNTHETIC ENCODER B'); self.runner=FakeRunner(self.root,tag='B'); writes=[]
        def writer(path,value):
            writes.append(path)
            if len(writes)==2: raise OSError('synthetic receipt confirmation failure')
            b.atomic_json(path,value)
        failed=self.call(metadata_writer=writer); self.assertEqual(failed['status'],'failed'); self.assertEqual(failed['phase'],'publish'); self.assertTrue(failed['runtime_observation'])
        disk=json.loads((self.work/'ownership_receipt.json').read_text(encoding='utf-8')); self.assertEqual(len(disk['pending']),1)
        self.runner=FakeRunner(self.root,tag='B'); retry=self.call(); self.assertEqual(retry['status'],'complete'); self.assertEqual(retry['skipped_count'],1)

    def test_18_unsafe_source_runtime_paths_and_overlapping_roots_are_refused(self):
        self.catalog['tracks'][0]['source_filename']='../escape.ogg'; result=self.call(); self.assertEqual(result['status'],'failed'); self.assertEqual(self.runner.calls,[])
        catalog=fixture_catalog()
        result=b.build_music(catalog,self.source,self.source,self.work,runner=self.runner,apply=True); self.assertEqual(result['status'],'failed'); self.assertIn('disjoint',result['error'])
        with self.assertRaises(b.BuildError): b.safe_child(self.runtime,'../outside.ogg')

    def test_19_existing_receipt_for_another_root_does_not_authorize_overwrite(self):
        self.establish_owned(); manifest=self.work/'ownership_receipt.json'; value=json.loads(manifest.read_text(encoding='utf-8')); value['runtime_root']=str(self.root/'other-runtime'); b.atomic_json(manifest,value); old=self.files(); self.runner=FakeRunner(self.root)
        result=self.call(); self.assertEqual(result['status'],'failed'); self.assertIn('another root',result['error']); self.assertEqual(self.files(),old); self.assertEqual(self.runner.calls,[])

    def test_20_binary_runner_logs_are_rejected_and_not_serialized_as_binary(self):
        def broken(argv): return {'exit_code':0,'stdout':b'\xff\x00BINARY','stderr':''}
        result=self.call(runner=broken); self.assertEqual(result['status'],'failed'); self.assertIn('text logs',result['error']); self.assertNotIn('BINARY',json.dumps(result)); self.assertEqual(self.files(),{})

    def test_21_helper_is_self_contained_and_fake_proofs_are_not_actual_audio(self):
        source=SCRIPT.read_text(encoding='utf-8')
        self.assertNotIn('catalog-drafts',source);self.assertNotIn('spec_from_file_location',source)
        result=self.call();self.assertEqual(result['runner_mode'],'injected')
        self.assertFalse(result['checks']['actual_q6_quality']);self.assertFalse(result['checks']['decode_integrity'])

class FormatAndStageContracts(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(b,'MUSIC helper is not implemented')
        self.temp=TemporaryDirectory(dir=str(RUNS));self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
    def test_22_encoding_policy_is_local_untracked_and_status_is_rejected(self):
        value=fixture_catalog();self.assertEqual(b.validate_catalog(value),value)
        value['encoding']['status']='encoded_local'
        with self.assertRaises(ValueError):b.validate_catalog(value)

    @staticmethod
    def crc(raw):
        value=0
        for byte in raw:
            value ^= byte<<24
            for _ in range(8):value=((value<<1)^(0x04c11db7 if value&0x80000000 else 0))&0xffffffff
        return value
    def page(self,sequence,flags,granule,packets,serial=42):
        payload=b''.join(packets);lacing=bytes(len(packet) for packet in packets)
        raw=bytearray(b'OggS'+bytes([0,flags])+struct.pack('<QII',granule,serial,sequence)+bytes(4)+bytes([len(lacing)])+lacing+payload)
        struct.pack_into('<I',raw,22,self.crc(raw));return bytes(raw)
    def ogg(self,*,eos=True,sequence=2,serial=42,continued=False,rate=44100,framing=1):
        ident=b'\x01vorbis'+struct.pack('<IBIiiiBB',0,2,rate,0,0,0,0xb8,framing)
        comment=b'\x03vorbis'+struct.pack('<I',4)+b'FAKE'+struct.pack('<I',0)+b'\x01'
        return self.page(0,3 if continued else 2,0,[ident])+self.page(1,0,0,[comment,b'\x05vorbis\x01'])+self.page(sequence,4 if eos else 0,44100,[b'\x00FAKE'],serial)
    def inspect(self,raw):
        path=self.root/'synthetic.ogg';path.write_bytes(raw);return b.inspect_vorbis(path)
    def test_23_synthetic_complete_structure_is_not_a_decode_claim(self):
        meta=self.inspect(self.ogg());self.assertEqual((meta['channels'],meta['sample_rate'],meta['eos_granule']),(2,44100,44100));self.assertTrue(meta['all_page_crc_valid']);self.assertEqual(meta['duration_seconds'],1.0)
    def test_24_crc_corruption_and_truncation_are_rejected(self):
        raw=bytearray(self.ogg());raw[-1]^=1
        for bad in (bytes(raw),self.ogg()[:-1],self.ogg()+b'garbage'):
            with self.assertRaises(ValueError):self.inspect(bad)
    def test_25_missing_eos_is_rejected(self):
        with self.assertRaises(ValueError):self.inspect(self.ogg(eos=False))
    def test_26_page_sequence_gap_is_rejected(self):
        with self.assertRaises(ValueError):self.inspect(self.ogg(sequence=3))
    def test_27_chained_stream_and_wrong_continuation_are_rejected(self):
        for bad in (self.ogg(serial=43),self.ogg(continued=True)):
            with self.assertRaises(ValueError):self.inspect(bad)
    def test_28_invalid_rate_and_framing_are_rejected(self):
        for bad in (self.ogg(rate=0),self.ogg(framing=0)):
            with self.assertRaises(ValueError):self.inspect(bad)
    def project(self):
        root=self.root/'source';(root/'assets/audio/music').mkdir(parents=True);(root/'nested/MUSIC').mkdir(parents=True);(root/'.godot').mkdir()
        (root/'project.godot').write_bytes(b'SYNTHETIC PROJECT INPUT; NOT RUN')
        (root/'assets/audio/music/local.ogg').write_bytes(b'SYNTHETIC USER MUSIC');(root/'assets/audio/music/local.ogg.import').write_bytes(b'SYNTHETIC SIDECAR');(root/'nested/MUSIC/other.ogg').write_bytes(b'SYNTHETIC OTHER');(root/'.godot/cache').write_bytes(b'PRIVATE CACHE');(root/'main.txt').write_bytes(b'PUBLIC SOURCE');return root
    def snapshot(self,root):return {p.relative_to(root).as_posix():(p.read_bytes(),p.stat().st_mtime_ns) for p in root.rglob('*') if p.is_file()}
    def test_29_public_project_stage_excludes_entire_music_and_source_is_untouched(self):
        source=self.project();before=self.snapshot(source);stage=self.root/'public';result=b.stage_project(source,stage)
        self.assertEqual(result['status'],'complete');self.assertTrue((stage/'main.txt').is_file());self.assertFalse((stage/'assets/audio/music').exists());self.assertFalse((stage/'nested/MUSIC').exists());self.assertFalse((stage/'.godot').exists());self.assertEqual(before,self.snapshot(source));self.assertFalse(result['opaque_archives_audited'])
    def test_30_local_with_music_copies_only_to_explicit_new_stage(self):
        source=self.project();before=self.snapshot(source);stage=self.root/'local';result=b.stage_project(source,stage,with_music=True)
        self.assertEqual(result['status'],'complete');self.assertEqual((stage/'assets/audio/music/local.ogg').read_bytes(),b'SYNTHETIC USER MUSIC');self.assertTrue((stage/'assets/audio/music/local.ogg.import').is_file());self.assertEqual(before,self.snapshot(source))
    def test_31_existing_stage_and_overlapping_roots_fail_without_deletion(self):
        source=self.project();stage=self.root/'existing';stage.mkdir();keep=stage/'keep';keep.write_bytes(b'USER')
        self.assertEqual(b.stage_project(source,stage)['status'],'failed');self.assertEqual(keep.read_bytes(),b'USER');self.assertEqual(b.stage_project(source,source/'nested-stage')['status'],'failed')
    def test_32_reparse_source_is_not_followed(self):
        source=self.project();(source/'linked').mkdir()
        with patch.object(b,'is_reparse',side_effect=lambda p:Path(p).name=='linked'):
            self.assertEqual(b.stage_project(source,self.root/'stage')['status'],'failed')

    def test_33_project_staging_rejects_a_music_directory_as_public_root(self):
        source=self.root/'music';source.mkdir();(source/'track.ogg').write_bytes(b'SYNTHETIC USER MUSIC')
        self.assertEqual(b.stage_project(source,self.root/'public')['status'],'failed')

    def test_34_both_stages_exclude_casefold_private_dirs_and_files(self):
        source=self.project()
        directories=['.RUNTIME','BUILD','Dist','COZY TUNES','.CODEX','.AGENTS','.AWS','.GIT','.GODOT','.TOOLS','.env.private','EXPORT_CREDENTIALS.CFG']
        files=['.runtime','.ENV','.Env.Local','export_Credentials.cfg','.GiT','.codex','.agents','.aws','Cozy Tunes','build','dist']
        protected=[]
        for name in directories:
            relative=Path('nested-private')/name/'marker';path=source/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'SYNTHETIC PRIVATE DIRECTORY');protected.append(relative)
        for name in files:
            relative=Path('private-files')/name;path=source/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'SYNTHETIC PRIVATE FILE');protected.append(relative)
        before=self.snapshot(source)
        for with_music in (False,True):
            stage=self.root/('local' if with_music else 'public');result=b.stage_project(source,stage,with_music=with_music)
            self.assertEqual(result['status'],'complete')
            for relative in protected:self.assertFalse((stage/relative).exists(),str(relative))
        self.assertEqual(before,self.snapshot(source))
    def test_35_local_only_keeps_the_canonical_music_directory(self):
        source=self.project();stage=self.root/'local';result=b.stage_project(source,stage,with_music=True)
        self.assertEqual(result['status'],'complete');self.assertTrue((stage/'assets/audio/music/local.ogg').is_file());self.assertFalse((stage/'nested/MUSIC').exists())
    def test_36_old_packed_outputs_are_not_preexport_inputs_and_gdignore_is_kept(self):
        source=self.project();(source/'old.PCK').write_bytes(b'SYNTHETIC OLD PACK');(source/'old.Zip').write_bytes(b'SYNTHETIC OLD ZIP');(source/'.gdignore').write_bytes(b'SYNTHETIC IMPORT POLICY')
        for with_music in (False,True):
            stage=self.root/('local' if with_music else 'public');result=b.stage_project(source,stage,with_music=with_music)
            self.assertEqual(result['status'],'complete');self.assertFalse((stage/'old.PCK').exists());self.assertFalse((stage/'old.Zip').exists());self.assertTrue((stage/'.gdignore').is_file())

if __name__=='__main__': unittest.main(verbosity=2)

# -*- coding: utf-8 -*-
"""POLISH adds exactly five resources without rewriting old art provenance."""
import ast
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('polish_manifest_pipeline',ROOT/'tools/art_pipeline.py')
pipeline=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(pipeline)
NEW_PATHS={
    'money_bag':'assets/ui/status_v3/money_bag.png',
    'oil_lamp':'assets/ui/status_v3/oil_lamp.png',
    'pocket_watch':'assets/ui/status_v3/pocket_watch.png',
    'reputation_star':'assets/ui/status_v3/reputation_star.svg',
    'navigation':'assets/ui/polish_icons.svg',
}
STYLE_PATH='assets/generated_scenes/v3_final/style_reference.png'
LEGACY_EXPANDED_SHA='6ae576ccf84ca152736ba3ac1e206370127d6b8beae71f8b30e0a0e9ceef7606'
TITLE_CATALOG_SHA='6b6a760a861ddd84ffa45ad0f1dcb29ceed3ac2c6a6b810bb20c8a1c935190df'
PROTECTED_FUNCTIONS={
    'expand_compact_metadata':'ede9e03d9b129b367ed858638578aa0d0f70b886dbcb99c8753d54650a8a4d13',
    'compact_portrait_metadata':'36d823ad52b785bf294f380f042507ecc9404279ed41fc0f723a3caeeba0ce19',
    'compact_formal_metadata':'de9e1b1623ce3c939271c19adcf45e98a5ea4fe756979f87b285a1364c3aa424',
    '_compact_resources':'190be6de94c1b6da9e2e490226bba2aab5de7dc3786ed0bdeaafa40fc125f79a',
    'build_compact_queue':'5122ff5f38fd0d0311639e4c06f5241ec04b738ffe9538b560ad979157dc203a',
    'validate_title_prompts':'afd7ae65c48350cb2a412052cd709420592bc41518daa5d6993cbaa2ed8660d0',
    '_title_json_object':'9190165bf9bd5d3c5024112473b2c091b58935a66fcc95c78ace1fe1538df4d8',
    'resolve_title_provenance':'26a6d1992806f0dc836a9eaf0adfb426c51c832cbb41c1df3636e9b361661173',
}

def canonical(value):
    return json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode('utf-8')

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

class PolishManifestTests(unittest.TestCase):
    def inputs(self):
        self.test_polish_provenance_has_its_own_strict_resolver_and_validator()
        path=ROOT/'data/art/polish_prompts.json'
        self.assertTrue(path.is_file(),'POLISH complete provenance must be tracked in its sidecar')
        manifest=json.loads((ROOT/'assets/ART_ASSET_MANIFEST.json').read_text(encoding='utf-8'))
        catalog=json.loads(path.read_text(encoding='utf-8'))
        paths=set(NEW_PATHS.values())|{STYLE_PATH}
        rows=[row for row in manifest['assets'] if row['path'] in paths]
        self.assertEqual(len(rows),6)
        return manifest,catalog,rows

    def temporary_workspace(self):
        base=ROOT/'.tools/r3-polish/provenance-packing/test-runs'
        base.mkdir(parents=True,exist_ok=True)
        temporary=tempfile.TemporaryDirectory(dir=base)
        self.addCleanup(temporary.cleanup)
        return Path(temporary.name)

    def write_catalog(self,workspace,catalog):
        path=workspace/'data/art/polish_prompts.json'
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes((json.dumps(catalog,ensure_ascii=False,indent=2)+'\n').encode('utf-8'))
        return path

    def test_polish_provenance_has_its_own_strict_resolver_and_validator(self):
        self.assertTrue(callable(getattr(pipeline,'resolve_polish_provenance',None)),
                        'six POLISH refs require an explicit strict workspace-bound resolver')
        self.assertTrue(callable(getattr(pipeline,'validate_polish_prompts',None)),
                        'the tracked POLISH sidecar requires its own strict validator')

    def test_all_five_actual_sources_are_registered_without_raising_the_budget(self):
        raw=(ROOT/'assets/ART_ASSET_MANIFEST.json').read_bytes()
        manifest=json.loads(raw)
        self.assertTrue(set(NEW_PATHS.values()) <= {row['path'] for row in manifest['assets']},
                        'three actual PNGs and two project-original SVGs must all have formal provenance')
        self.assertLessEqual(len(raw),500000)

    def test_full_rows_roundtrip_canonical_hash_and_no_input_mutation(self):
        manifest,catalog,rows=self.inputs();before=copy.deepcopy((manifest,catalog))
        self.assertIs(pipeline.validate_polish_prompts(catalog),catalog)
        for row in rows:
            expected=catalog['entries'][row['prompt_reference']['key']]
            full=pipeline.resolve_polish_provenance(ROOT,row)
            self.assertEqual(full,expected)
            self.assertEqual(hashlib.sha256(canonical(full)).hexdigest(),row['prompt_reference']['sha256'])
            full['prompt']='caller mutation'
            self.assertNotEqual(catalog['entries'][row['prompt_reference']['key']]['prompt'],'caller mutation')
        self.assertEqual((manifest,catalog),before)

    def test_all_old_370_expanded_records_and_top_level_metadata_are_semantically_equal(self):
        manifest,_,rows=self.inputs()
        expanded=pipeline.expand_compact_metadata(manifest)
        material_ids=('notebook','letter','paper_cream','paper_blue','paper_lilac','tag_cream','tag_blue',
                      'tag_lilac','tag_neutral','wax_seal','paper_tag','red_stamp','vine')
        material_paths={'assets/ui/material_v3/'+key+'.png' for key in material_ids}
        historical_material_rows={'assets/generated_scenes/v2/slices/S04_slot.png','assets/generated_scenes/v2/slices/S04_door_closed.png'}
        expanded['assets']=[pipeline.resolve_polish_provenance(ROOT,row) if row['path']==STYLE_PATH else
                            pipeline.resolve_material_provenance(ROOT,row) if row['path'] in historical_material_rows else row
                            for row in expanded['assets'] if row['path'] not in set(NEW_PATHS.values())|material_paths]
        self.assertEqual(len(expanded['assets']),370)
        self.assertEqual(hashlib.sha256(canonical(expanded)).hexdigest(),LEGACY_EXPANDED_SHA)
        style=next(row for row in rows if row['path']==STYLE_PATH)
        self.assertNotIn('version',style,'do not invent a version on the historical style row')
        self.assertEqual(digest(ROOT/'data/art/title_prompts.json'),TITLE_CATALOG_SHA)

    def test_five_pure_queue_apis_and_title_resolvers_are_unchanged(self):
        source=(ROOT/'tools/art_pipeline.py').read_text(encoding='utf-8')
        current={node.name:hashlib.sha256(ast.get_source_segment(source,node).encode('utf-8')).hexdigest()
                 for node in ast.parse(source).body if isinstance(node,ast.FunctionDef) and node.name in PROTECTED_FUNCTIONS}
        self.assertEqual(current,PROTECTED_FUNCTIONS)

    def test_pure_packing_has_no_sidecar_io_and_no_new_queue_items(self):
        manifest,_,_=self.inputs();before=copy.deepcopy(manifest)
        with mock.patch.object(Path,'read_text',side_effect=AssertionError('pure packing must not read sidecars')), \
             mock.patch.object(pipeline,'resolve_polish_provenance',side_effect=AssertionError('pure packing must not resolve')):
            expanded=pipeline.expand_compact_metadata(manifest)
            packed=pipeline.compact_formal_metadata(manifest)
            self.assertEqual(pipeline.expand_compact_metadata(packed),expanded)
        without=copy.deepcopy(manifest)
        without['assets']=[row for row in without['assets'] if row['path'] not in NEW_PATHS.values()]
        self.assertEqual(pipeline._compact_resources(manifest),pipeline._compact_resources(without))
        self.assertEqual(manifest,before)
        self.assertIs(pipeline.validate_compact_manifest(ROOT,manifest),manifest)

    def test_actual_file_sha_dimensions_and_honest_svg_generation_kind(self):
        _,catalog,_=self.inputs()
        for key,path in NEW_PATHS.items():
            full=catalog['entries'][key];file=ROOT/path
            self.assertEqual(full['sha256'],digest(file))
            if file.suffix=='.png':
                with Image.open(file) as image:dimensions=list(image.size)
                self.assertEqual(full['source']['generator'],'builtin_imagegen')
            else:
                element=ET.fromstring(file.read_bytes())
                dimensions=[int(element.attrib['width']),int(element.attrib['height'])]
                self.assertEqual(full['source']['generator'],'project_original_svg')
            self.assertEqual(full['dim'],dimensions)
        self.assertEqual(catalog['entries']['oil_lamp']['version'],3)
        self.assertIn('UNLIT',catalog['entries']['oil_lamp']['prompt'])

    def test_catalog_strict_shape_keys_version_and_full_row_types(self):
        _,catalog,_=self.inputs()
        for value in (None,[],True,{},dict(catalog,type='other'),dict(catalog,version=True),dict(catalog,version=1.0),dict(catalog,version=2),dict(catalog,extra=0)):
            with self.subTest(value=type(value).__name__),self.assertRaises(ValueError):pipeline.validate_polish_prompts(value)
        for mutation in ('missing','extra','prompt','source','version','dim','sha','path','group','svg_generator'):
            value=copy.deepcopy(catalog);row=value['entries']['money_bag']
            if mutation=='missing':del value['entries']['money_bag']
            elif mutation=='extra':value['entries']['other']=copy.deepcopy(row)
            elif mutation=='prompt':row['prompt']=''
            elif mutation=='source':row['source']=[]
            elif mutation=='version':row['version']=True
            elif mutation=='dim':row['dim']=[True,1]
            elif mutation=='sha':row['sha256']='bad'
            elif mutation=='path':row['path']='assets/ui/unregistered.png'
            elif mutation=='group':row['group']='runtime'
            else:value['entries']['reputation_star']['source']['generator']='builtin_imagegen'
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):pipeline.validate_polish_prompts(value)

    def test_reference_escape_hash_identity_and_key_cannot_bypass_polish_validation(self):
        _,_,rows=self.inputs();original=next(row for row in rows if row['path']==NEW_PATHS['money_bag'])
        for mutation in ('missing','key','escape','catalog','hash','extra_ref','dimension','version','file_hash','group','case','inline'):
            row=copy.deepcopy(original);ref=row['prompt_reference']
            if mutation=='missing':del row['prompt_reference']
            elif mutation=='key':ref['key']='other'
            elif mutation=='escape':ref['path']='../polish_prompts.json'
            elif mutation=='catalog':ref['path']='data/art/title_prompts.json'
            elif mutation=='hash':ref['sha256']='0'*64
            elif mutation=='extra_ref':ref['type']='arbitrary'
            elif mutation=='dimension':row['dim']=[1,1]
            elif mutation=='version':row['version']+=1
            elif mutation=='file_hash':row['sha256']='0'*64
            elif mutation=='group':row['group']='runtime'
            elif mutation=='case':row['path']=row['path'].upper()
            else:row['prompt']='conflicting inline prompt'
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):
                pipeline.validate_compact_manifest(ROOT,{'schema_version':3,'assets':[row]})

    def test_reserved_prefixes_and_polish_markers_fail_closed_when_renamed(self):
        for path in ('assets/ui/status_v3/unregistered.png','ASSETS/UI/STATUS_V3/unregistered.png',
                     'assets/ui/polish_icons_unregistered.svg','ASSETS/UI/POLISH_ICONS_unregistered.svg'):
            row={'path':path,'sha256':'0'*64,'dim':[1,1],'version':1,'group':'legacy_runtime'}
            with self.subTest(path=path),self.assertRaises(ValueError):
                pipeline.validate_compact_manifest(ROOT,{'schema_version':3,'assets':[row]})

    def test_missing_sidecar_and_duplicate_keys_fail_without_repository_fallback(self):
        _,catalog,rows=self.inputs();workspace=self.temporary_workspace()
        with self.assertRaises(ValueError):pipeline.resolve_polish_provenance(workspace,rows[0])
        path=self.write_catalog(workspace,catalog);encoded=path.read_text(encoding='utf-8')
        path.write_bytes(encoded.replace('"version": 1,','"version": 1, "version": 1,',1).encode('utf-8'))
        with self.assertRaises(ValueError):pipeline.resolve_polish_provenance(workspace,rows[0])

    def test_changed_prompt_source_or_historical_edit_fails_canonical_binding(self):
        _,catalog,rows=self.inputs();workspace=self.temporary_workspace()
        style=next(row for row in rows if row['path']==STYLE_PATH)
        for field in ('prompt','source','previous_edit'):
            changed=copy.deepcopy(catalog);full=changed['entries']['style_reference']
            if field=='prompt':full['prompt']+=' changed'
            elif field=='source':full['source']['version']+=' changed'
            else:full['previous_edit']['prompt']+=' changed'
            self.write_catalog(workspace,changed)
            with self.subTest(field=field),self.assertRaises(ValueError):pipeline.resolve_polish_provenance(workspace,style)

if __name__=='__main__':unittest.main()

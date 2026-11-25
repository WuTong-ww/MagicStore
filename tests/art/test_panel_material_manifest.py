# -*- coding: utf-8 -*-
"""Actual selected material sources plus strict, bounded provenance negatives."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
IDS=('notebook','letter','paper_cream','paper_blue','paper_lilac','tag_cream','tag_blue',
     'tag_lilac','tag_neutral','wax_seal','paper_tag','red_stamp','vine')
PATHS={'assets/ui/material_v3/'+key+'.png' for key in IDS}
LEGACY_PATHS={'assets/generated_scenes/v2/slices/S04_slot.png','assets/generated_scenes/v2/slices/S04_door_closed.png'}

def canonical(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode('utf-8')

class PanelMaterialManifestTests(unittest.TestCase):
    def implementation(self):
        spec=importlib.util.spec_from_file_location('panel_material_pipeline',ROOT/'tools/art_pipeline.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        for name in ('validate_material_prompts','resolve_material_provenance'):
            self.assertTrue(callable(getattr(module,name,None)),'materials require their own bounded '+name)
        return module

    def inputs(self):
        pipeline=self.implementation()
        path=ROOT/'data/art/polish_material_prompts.json'
        self.assertTrue(path.is_file(),'only final selected materials may be formally registered')
        manifest=json.loads((ROOT/'assets/ART_ASSET_MANIFEST.json').read_text(encoding='utf-8'))
        catalog=json.loads(path.read_text(encoding='utf-8'))
        rows=[row for row in manifest['assets'] if row['path'] in PATHS|LEGACY_PATHS]
        self.assertEqual(len(rows),15)
        return pipeline,manifest,catalog,rows

    def test_strict_material_namespace_api_exists(self):
        self.implementation()

    def test_actual_thirteen_selected_pngs_config_pins_and_unchanged_budget(self):
        pipeline,manifest,catalog,rows=self.inputs()
        self.assertLessEqual((ROOT/'assets/ART_ASSET_MANIFEST.json').stat().st_size,500000)
        self.assertIs(pipeline.validate_material_prompts(catalog),catalog)
        config=json.loads((ROOT/'data/ui/panel_materials.json').read_text(encoding='utf-8'))
        for row in rows:
            full=pipeline.resolve_material_provenance(ROOT,row)
            self.assertEqual(hashlib.sha256(canonical(full)).hexdigest(),row['prompt_reference']['sha256'])
            if row['path'] not in PATHS:continue
            key=row['prompt_reference']['key'];path=ROOT/row['path']
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),full['sha256'])
            with Image.open(path) as image:
                self.assertEqual(image.format,'PNG');self.assertEqual(list(image.size),full['dim']);image.verify()
            self.assertEqual(full['runtime_asset'],config['assets'][key])
            self.assertEqual(hashlib.sha256(canonical(config['assets'][key])).hexdigest(),full['runtime_asset_sha256'])
            self.assertIs(full['review']['opened'],True);self.assertGreaterEqual(full['review']['score'],8)
        self.assertIs(pipeline.validate_compact_manifest(ROOT,manifest),manifest)

    def test_full_rows_are_copies_and_no_input_mutation(self):
        pipeline,manifest,catalog,rows=self.inputs();before=copy.deepcopy((manifest,catalog))
        for row in rows:
            key=row['prompt_reference']['key'];bucket='legacy_entries' if row['path'] in LEGACY_PATHS else 'entries'
            full=pipeline.resolve_material_provenance(ROOT,row)
            self.assertEqual(full,catalog[bucket][key]);full['prompt']='caller mutation'
            self.assertNotEqual(pipeline.resolve_material_provenance(ROOT,row)['prompt'],'caller mutation')
        self.assertEqual((manifest,catalog),before)

    def test_bad_shapes_scores_native_size_or_margins_are_rejected(self):
        pipeline,_,catalog,_=self.inputs()
        for mutation in ('missing','extra','version','score','unopened','pending','margins','book','source','hash','history'):
            value=copy.deepcopy(catalog);row=value['entries']['letter']
            if mutation=='missing':del value['entries']['vine']
            elif mutation=='extra':value['entries']['unknown']=copy.deepcopy(row)
            elif mutation=='version':row['version']=True
            elif mutation=='score':row['review']['score']=7
            elif mutation=='unopened':row['review']['opened']=False
            elif mutation=='pending':row['runtime_asset']['native_size']=[0,0]
            elif mutation=='margins':row['runtime_asset']['margins']=[99999]*4
            elif mutation=='book':value['entries']['notebook']['runtime_asset']['book_regions']['left']=[0,0,1,1]
            elif mutation=='source':row['source']['generator']='unverified'
            elif mutation=='hash':row['runtime_asset_sha256']='0'*64
            else:value['legacy_entries']['legacy_s04_slot']['prompt']+=' changed'
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):pipeline.validate_material_prompts(value)

    def test_unknown_case_alias_escape_and_reference_identity_are_rejected(self):
        pipeline,_,_,rows=self.inputs();original=next(row for row in rows if row['path'].endswith('/letter.png'))
        for mutation in ('unknown','case','escape','catalog','key','hash','bool','inline','extra'):
            row=copy.deepcopy(original);reference=row['prompt_reference']
            if mutation=='unknown':row['path']='assets/ui/material_v3/unregistered.png'
            elif mutation=='case':row['path']=row['path'].upper()
            elif mutation=='escape':reference['path']='../polish_material_prompts.json'
            elif mutation=='catalog':reference['path']='data/art/polish_prompts.json'
            elif mutation=='key':reference['key']='other'
            elif mutation=='hash':reference['sha256']='0'*64
            elif mutation=='bool':row['dim']=[True,1]
            elif mutation=='inline':row.pop('prompt_reference')
            else:row['extra']=0
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):
                pipeline.validate_compact_manifest(ROOT,{'schema_version':3,'assets':[row]})

    def test_changed_local_runtime_authority_or_missing_sidecar_never_falls_back(self):
        pipeline,_,catalog,rows=self.inputs();row=next(row for row in rows if row['path'].endswith('/letter.png'))
        base=ROOT/'.tools/r3-polish/material-art-test-runs';base.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as directory:
            workspace=Path(directory);sidecar=workspace/'data/art/polish_material_prompts.json';sidecar.parent.mkdir(parents=True)
            sidecar.write_bytes(canonical(catalog))
            config=json.loads((ROOT/'data/ui/panel_materials.json').read_text(encoding='utf-8'))
            target=workspace/'data/ui/panel_materials.json';target.parent.mkdir(parents=True);target.write_bytes(canonical(config))
            pipeline.resolve_material_provenance(workspace,row)
            config['assets']['letter']['margins'][0]+=1;target.write_bytes(canonical(config))
            with self.assertRaises(ValueError):pipeline.resolve_material_provenance(workspace,row)
            sidecar.unlink()
            with self.assertRaises(ValueError):pipeline.resolve_material_provenance(workspace,row)

if __name__=='__main__':unittest.main()

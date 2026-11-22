"""Technical synthetic rasters only; no model calls or art approval."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class PortraitPipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = json.loads((ROOT / 'data/art/portrait_pipeline.json').read_text('utf-8'))
        # Historical synthetic eye fixtures retain their original rig and have
        # no authority to inherit a real pilot3 source-specific calibration.
        self.config['processing'].get('fine_alignment',{}).get('rules',{}).pop('eyes_01_neutral',None)
        for path in ('data/people/appearance_parts.json',):
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / path).read_bytes())

    def module(self, relative, name):
        target = ROOT / relative
        self.assertTrue(target.is_file(), 'missing real portrait processor/checker: ' + relative)
        spec = importlib.util.spec_from_file_location(name, target)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
        return module

    def image(self, relative, image):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, 'PNG')
        return path

    def eyes(self, color=(120, 120, 120, 255)):
        im = Image.new('RGBA', (768, 1024))
        draw = ImageDraw.Draw(im)
        draw.ellipse((300, 347, 330, 367), fill=color)
        draw.ellipse((430, 347, 460, 367), fill=color)
        return im

    def references(self, pipeline):
        mannequin = Image.new('RGB', (768, 1024), (255, 0, 255))
        ImageDraw.Draw(mannequin).ellipse((220, 140, 580, 610), fill=(120, 120, 120))
        base = self.image(self.config['mannequin']['path'], mannequin)
        style = self.image(self.config['style_reference']['path'], Image.new('RGB', (16, 12), (80, 90, 100)))
        original = self.image('assets/_incoming/a4_v3/test-base.png', mannequin)
        history = self.root / self.config['mannequin']['generation_receipt']
        history.parent.mkdir(parents=True, exist_ok=True)
        history.write_text('{"prompts": [{"attempt":1,"prompt":"synthetic base fixture","ref_paths":[]}]}', encoding='utf-8')
        self.config['style_reference']['sha256'] = sha(style)
        self.config['mannequin'].update(sha256=sha(base), source_path=original.relative_to(self.root).as_posix(),
                                      source_sha256=sha(original), source_native_size=[768, 1024], selected_attempt=1,
                                      generation_receipt_sha256=sha(history),
                                      transform={'method':'full_canvas_resize_translate','filter':'Lanczos','source_crop':[0,0,768,1024],
                                                 'resize_size':[768,1024],'translation_px':[0,0],'fill_rgb':[255,0,255]})
        masks = pipeline.prepare_masks(self.root, 'test1', only=['eyes_01_neutral'], config=self.config)
        return masks

    def receipt(self, pipeline):
        self.references(pipeline)
        queue = pipeline.build_queue(self.root, 'test1', only=['eyes_01_neutral'], config=self.config)
        task = queue['tasks'][0]
        raw = self.eyes().convert('RGB')
        background = Image.new('RGB', raw.size, (255, 0, 255))
        foreground = self.eyes()
        background.paste(foreground.convert('RGB'), (0, 0), foreground.getchannel('A'))
        source = self.image(task['source_destination'], background)
        refs = task['ref_paths']
        fields = {'prompt':task['arguments']['prompt'],'ref_paths':refs,
                  'reference_shas':{p:sha(self.root/p) for p in refs},
                  'sha256':sha(source),'native_size':[768,1024]}
        record = {'id':'eyes_01_neutral','status':'complete','source_path':source.relative_to(self.root).as_posix(),
                  'mask_path':task['mask_path'],'mask_sha256':task['mask_sha256'],
                  'selected_attempt':1,**fields,
                  'attempts':[{'attempt':1,'status':'complete','output_path':source.relative_to(self.root).as_posix(),**fields}]}
        return {'version':1,'style_reference':refs[2],'style_sha256':sha(self.root/refs[2]),
                'mannequin_path':refs[0],'mannequin_sha256':sha(self.root/refs[0]),'records':[record]}

    def test_real_alpha_gray_and_both_eye_anchor_rois_pass(self):
        checker = self.module('tools/check_parts.py', 'portrait_checker_test')
        path = self.image('assets/_incoming/a4_v3/eyes.png', self.eyes())
        report = checker.check_part(self.root, 'eyes_01_neutral', path.relative_to(self.root).as_posix(), self.config)
        self.assertTrue(report['passed'], report)
        self.assertGreater(report['foreground_pixels'], 64)
        self.assertEqual(len(report['roi_pixels']), 2)
        self.assertTrue(all(n >= 8 for n in report['roi_pixels']))
        self.assertFalse(report['art_passed'])

    def test_filename_and_declared_dimensions_cannot_pass_wrong_actual_pixels(self):
        checker = self.module('tools/check_parts.py', 'portrait_checker_bad_test')
        images = [Image.new('RGBA',(768,1024)), Image.new('RGBA',(768,1024),(120,120,120,255)),
                  Image.new('RGBA',(64,64),(120,120,120,255)), self.eyes((220,60,30,255)),
                  self.eyes().convert('RGB')]
        for index, im in enumerate(images):
            with self.subTest(index=index):
                path = self.image('assets/_incoming/a4_v3/eyes_01_neutral.png',im)
                self.assertFalse(checker.check_part(self.root,'eyes_01_neutral',path.relative_to(self.root).as_posix(),self.config)['passed'])
        wrong_anchor = Image.new('RGBA',(768,1024))
        ImageDraw.Draw(wrong_anchor).rectangle((280,680,490,750),fill=(120,120,120,255))
        path = self.image('assets/_incoming/a4_v3/eyes_01_neutral.png',wrong_anchor)
        self.assertFalse(checker.check_part(self.root,'eyes_01_neutral',path.relative_to(self.root).as_posix(),self.config)['passed'])

    def test_exact_catalog_139_excludes_optional_none_and_expands_only_eyes_mouth(self):
        pipeline = self.module('tools/art/portrait_pipeline.py', 'portrait_pipeline_test')
        pipeline.validate_config(self.config, self.root)
        self.assertEqual(len(self.config['assets']),139)
        self.assertEqual(len({x['id'] for x in self.config['assets']}),139)
        bad = copy.deepcopy(self.config)
        bad['assets'][0]['part_id'] = 'invented_part'
        with self.assertRaises(ValueError): pipeline.validate_config(bad,self.root)

    def test_builtin_queue_binds_real_mannequin_style_mask_shas_once_per_part(self):
        pipeline = self.module('tools/art/portrait_pipeline.py','portrait_queue_test')
        self.references(pipeline)
        queue = pipeline.build_queue(self.root,'test1',only=['eyes_01_neutral'],config=self.config)
        self.assertEqual(len(queue['tasks']),1)
        task = queue['tasks'][0]
        self.assertTrue(task['can_generate'])
        self.assertEqual(task['tool'],'image_gen.imagegen')
        self.assertEqual(task['mask_application'],'reference_only_no_dedicated_mask_api')
        self.assertEqual(len(task['ref_paths']),3)
        self.assertEqual(task['reference_shas'],{p:sha(self.root/p) for p in task['ref_paths']})
        self.assertFalse(queue['generation_performed'])
        self.assertFalse(queue['art_passed'])
        (self.root/task['mask_path']).write_bytes(b'changed mask')
        with self.assertRaises(ValueError): pipeline.build_queue(self.root,'test1',only=['eyes_01_neutral'],config=self.config)

    def test_missing_sources_templates_and_unreviewed_masks_are_honest_pending(self):
        pipeline = self.module('tools/art/portrait_pipeline.py','portrait_pending_test')
        self.assertFalse(pipeline.build_queue(self.root,'test1',only=['eyes_01_neutral'],config=self.config)['tasks'][0]['can_generate'])
        self.references(pipeline)
        no_template = copy.deepcopy(self.config); no_template['generation']['templates'].pop('part')
        pending = pipeline.build_queue(self.root,'test1',only=['eyes_01_neutral'],config=no_template)
        self.assertEqual(pending['status'],'pending_templates')
        unreviewed = pipeline.build_queue(self.root,'test1',only=['hair_front_01'],config=self.config)
        self.assertFalse(unreviewed['tasks'][0]['can_generate'])
        self.assertIn('mask_review',unreviewed['tasks'][0]['pending_reasons'])

    def test_processing_full_canvas_preserves_anchor_and_retains_real_transform(self):
        pipeline = self.module('tools/art/portrait_pipeline.py','portrait_process_test')
        generation = self.receipt(pipeline)
        result = pipeline.process_parts(self.root,generation,'test1',config=self.config)
        entry = result['entries'][0]
        self.assertTrue(entry['qa']['passed'])
        self.assertFalse(result['art_passed'])
        self.assertEqual(entry['transform']['source_crop'],[0,0,768,1024])
        self.assertEqual(entry['transform']['output_size'],[768,1024])
        self.assertEqual(entry['transform']['translation_px'],[0,0])
        self.assertEqual(entry['transform']['grayscale_method'],'mean_rgb')
        with Image.open(self.root/entry['path']) as im:
            self.assertEqual(im.size,(768,1024)); self.assertEqual(im.mode,'RGBA')
            self.assertEqual(im.getpixel((315,357)),(120,120,120,255))
            self.assertEqual(im.getpixel((0,0)),(0,0,0,0))

    def test_receipt_tampering_attempt_cap_and_preflight_no_partial_writes(self):
        pipeline = self.module('tools/art/portrait_pipeline.py','portrait_receipt_test')
        generation = self.receipt(pipeline)
        for mutation in ('source_sha','mask_sha','attempt_size','attempt_cap'):
            bad = copy.deepcopy(generation); row=bad['records'][0]
            if mutation=='source_sha': row['sha256']='0'*64
            if mutation=='mask_sha': row['mask_sha256']='0'*64
            if mutation=='attempt_size': row['attempts'][0]['native_size']=[1,1]
            if mutation=='attempt_cap': row['attempts']*=5
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):
                pipeline.process_parts(self.root,bad,'test1',config=self.config)
        self.assertFalse((self.root/'assets/_incoming/a4_v3/processed/test1/eyes_01_neutral.png').exists())

    def test_generation_receipt_requires_actual_digests_sizes_and_failed_output_evidence(self):
        pipeline = self.module('tools/art/portrait_pipeline.py','portrait_required_receipt_test')
        generation = self.receipt(pipeline)
        for field in ('sha256','native_size'):
            bad=copy.deepcopy(generation)
            bad['records'][0].pop(field)
            bad['records'][0]['attempts'][0].pop(field)
            with self.subTest(field=field),self.assertRaises(ValueError):
                pipeline.validate_generation_receipt(self.root,bad,self.config)
        bad=copy.deepcopy(generation)
        failed=copy.deepcopy(bad['records'][0]['attempts'][0])
        failed.update(attempt=2,status='failed',sha256='0'*64)
        bad['records'][0]['attempts'].append(failed)
        with self.assertRaises(ValueError): pipeline.validate_generation_receipt(self.root,bad,self.config)

    def test_cli_output_collision_is_rejected_before_any_processing_write(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_cli_test')
        generation=self.receipt(pipeline)
        config_path=self.root/'data/art/portrait_pipeline.json'
        config_path.parent.mkdir(parents=True,exist_ok=True)
        config_path.write_text(json.dumps(self.config),encoding='utf-8')
        receipt_path=self.root/'assets/_incoming/a4_v3/test-receipt.json'
        receipt_path.write_text(json.dumps(generation),encoding='utf-8')
        raw=generation['records'][0]['source_path']; original=(self.root/raw).read_bytes()
        result=subprocess.run([sys.executable,'-B',str(ROOT/'tools/art/portrait_pipeline.py'),'process','--workspace',str(self.root),
                               '--receipt',receipt_path.relative_to(self.root).as_posix(),'--revision','test1','--output',raw],capture_output=True,text=True)
        self.assertEqual(result.returncode,2,result.stdout+result.stderr)
        self.assertEqual((self.root/raw).read_bytes(),original)
        self.assertFalse((self.root/'assets/_incoming/a4_v3/processed/test1/eyes_01_neutral.png').exists())

    def test_mannequin_regeneration_has_explicit_reference_normalization(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_mannequin_test')
        generation=self.receipt(pipeline)
        pipeline.prepare_masks(self.root,'test1',only=['mannequin'],config=self.config)
        task=pipeline.build_queue(self.root,'test1',only=['mannequin'],config=self.config)['tasks'][0]
        raw=Image.new('RGB',(768,1024),(255,0,255)); draw=ImageDraw.Draw(raw)
        draw.ellipse((220,140,580,610),fill=(120,120,120));draw.rectangle((120,680,660,1023),fill=(100,100,100))
        source=self.image(task['source_destination'],raw); row=generation['records'][0]
        fields={'prompt':task['arguments']['prompt'],'ref_paths':task['ref_paths'],'reference_shas':task['reference_shas'],'sha256':sha(source),'native_size':[768,1024]}
        row.update(id='mannequin',source_path=source.relative_to(self.root).as_posix(),mask_path=task['mask_path'],mask_sha256=task['mask_sha256'],**fields)
        row['attempts']=[{'attempt':1,'status':'complete','output_path':row['source_path'],**fields}]
        result=pipeline.process_parts(self.root,generation,'test1',config=self.config)
        self.assertEqual(result['entries'][0]['transform']['translation_px'],[0,0])
        self.assertEqual(result['entries'][0]['qa']['reference_background'],'magenta')
        self.assertTrue(result['entries'][0]['qa']['passed'])
        self.assertFalse(result['art_passed'])

    def compact_portrait(self, pipeline, asset_id='eyes_01_neutral'):
        self.references(pipeline)
        config_path=self.root/'data/art/portrait_pipeline.json'
        config_path.parent.mkdir(parents=True,exist_ok=True)
        config_path.write_text(json.dumps(self.config),encoding='utf-8')
        slot=next(x for x in self.config['assets'] if x['id']==asset_id)
        prompt,params=pipeline.render_prompt(slot,self.config)
        template,template_key=pipeline._prompt_definition(slot,self.config)
        formal=self.image(slot['formal_path'],self.eyes())
        legacy=self.image('assets/portraits/npc_lin_neutral.png',Image.new('RGB',(16,12),(100,100,100)))
        row={'path':slot['formal_path'],'sha256':sha(formal),'dim':[768,1024],'group':'portraits','art_pack':'A4_v3',
             'operation':'portrait_part','portrait_asset_id':slot['id'],'part_id':slot['part_id'],'category':slot['category'],'mood':slot['mood'],
             'local_config':'data/art/portrait_pipeline.json','processing_script':'tools/art/portrait_pipeline.py',
             'prompt_template':template_key,'prompt_params':params,'actual_prompt_sha256':hashlib.sha256(prompt.encode()).hexdigest()}
        manifest={'schema_version':3,'assets':[row,{'path':legacy.relative_to(self.root).as_posix(),'sha256':sha(legacy),'dim':[16,12]}],
                  'style_profiles':{'v3':{'status':'selected','reference':self.config['style_reference'],'revision':'test1',
                                          'templates':{'portrait':'OLD COMPLETE PERSON ROOM TEMPLATE',template_key:template}}}}
        return manifest,row

    def test_compact_formal_portrait_reuses_exact_closed_smile_and_allows_style_replacement(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_exact_recipe_test')
        common=self.module('tools/art_pipeline.py','portrait_exact_common_test')
        manifest,row=self.compact_portrait(pipeline,'eyes_01_smile')
        template='{actual_prefix}ONLY TWO THIN DARK CLOSED arcs: {description}{actual_suffix}'
        params={'actual_prefix':'Literal {do_not_format} prefix. ','description':'same narrow eye family',
                'actual_suffix':' NO sclera, irises or pupils. Literal {width} suffix.'}
        actual=template.format(**params)
        row.update(prompt_template='A4_reviewed_closed_smile',prompt_params=params,
                   actual_prompt_sha256=hashlib.sha256(actual.encode()).hexdigest())
        manifest['style_profiles']['v3']['templates'][row['prompt_template']]=template
        before=(self.root/row['path']).read_bytes()
        task=common.build_queue(self.root,manifest,'v3','portraits')['tasks'][0]
        self.assertEqual(task['arguments']['prompt'],actual,'formal closed smile must never revert to the generic open-eye recipe')
        self.assertEqual(task['prompt_sha256'],row['actual_prompt_sha256'])
        self.assertEqual(task['previous_source_path'],row['path'])
        alternate=self.image('assets/styles/alternate.png',Image.new('RGB',(16,12),(40,70,90)))
        changed=common.build_queue(self.root,manifest,alternate.relative_to(self.root).as_posix(),'portraits')['tasks'][0]
        self.assertEqual(changed['arguments']['prompt'],actual)
        self.assertEqual(changed['ref_paths'][:2],task['ref_paths'][:2])
        self.assertEqual(changed['ref_paths'][2],alternate.relative_to(self.root).as_posix())
        self.assertEqual((self.root/row['path']).read_bytes(),before)

    def test_compact_formal_portrait_rejects_missing_or_tampered_exact_recipe(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_bad_recipe_test')
        common=self.module('tools/art_pipeline.py','portrait_bad_recipe_common_test')
        manifest,row=self.compact_portrait(pipeline)
        for field,value in [('prompt_template','missing_template'),('prompt_params',{'description':'tampered'}),
                            ('prompt_params',None),('actual_prompt_sha256','0'*64)]:
            bad=copy.deepcopy(manifest);bad['assets'][0][field]=value
            with self.subTest(field=field,value=value),self.assertRaisesRegex(ValueError,'portrait.*prompt|portrait.*recipe'):
                common.build_queue(self.root,bad,'v3','portraits')
        for field in ('prompt_template','prompt_params','actual_prompt_sha256'):
            bad=copy.deepcopy(manifest);del bad['assets'][0][field]
            with self.subTest(missing=field),self.assertRaisesRegex(ValueError,'portrait.*prompt|portrait.*recipe'):
                common.build_queue(self.root,bad,'v3','portraits')

    def test_output_only_shared_recipe_compresses_actual_without_changing_processing_history(self):
        p=self.module('tools/art/portrait_pipeline.py','portrait_output_encoding_test')
        generation=self.receipt(p)
        description=next(r['description'] for r in self.config['assets'] if r['id']=='eyes_01_neutral')
        template='ONLY thin dark closed lashes for {description}; no eye whites.'
        actual='Literal {width} prefix. '+template.format(description=description)+' Literal {unknown} suffix.'
        record=generation['records'][0];record['prompt']=actual;record['attempts'][0]['prompt']=actual
        receipt=p.process_parts(self.root,generation,'output-encoding',config=self.config)
        entry=receipt['entries'][0];formal=self.root/entry['formal_path'];formal.parent.mkdir(parents=True,exist_ok=True)
        formal.write_bytes((self.root/entry['path']).read_bytes())
        before=copy.deepcopy(receipt);planned=p.render_prompt(next(r for r in self.config['assets'] if r['id']==entry['id']),self.config)
        fragment=p.build_manifest_fragment(self.root,receipt,self.config,encoding_templates={'manifest_eye_smile':template})
        row=fragment['assets'][0];encoded=fragment['templates'][row['prompt_template']]
        self.assertIn('{description}',encoded)
        self.assertEqual(row['prompt_params']['actual_prefix'],'Literal {width} prefix. ')
        self.assertEqual(encoded.format(**row['prompt_params']),actual)
        self.assertEqual(row['actual_prompt_sha256'],hashlib.sha256(actual.encode()).hexdigest())
        self.assertEqual(row['processing_config_digest'],receipt['config_digest'])
        self.assertEqual(receipt,before)
        self.assertEqual(p.render_prompt(next(r for r in self.config['assets'] if r['id']==entry['id']),self.config),planned)

    def test_explicit_accessory_residue_visibility_keeps_component_and_rejects_other_source(self):
        p=self.module('tools/art/portrait_pipeline.py','portrait_accessory_visibility_test')
        row=next(r for r in self.config['assets'] if r['id']=='accessory_09')
        rule={'enabled':True,'shape':{'rect':[460,740,520,800]},'reviewed_source_sha256':'a'*64,
              'preserve_rois':[[466,750,514,787]],'expected_hidden_points':[[184,850],[500,927]],
              'audit_mask_path':'assets/_incoming/a4_v3/masks/test-accessory-residue.png'}
        self.config['processing']['processing_visibility']['rules']['accessory_09']=rule
        p.validate_config(self.config,self.root)
        image=Image.new('RGBA',(768,1024));draw=ImageDraw.Draw(image)
        draw.ellipse((476,756,504,783),fill=(120,120,120,255));draw.line((184,700,184,927),fill=(255,255,255,16))
        draw.line((184,927,650,927),fill=(255,255,255,16))
        result,_=p.apply_processing_visibility(image,row,self.config,'a'*64)
        self.assertEqual(result.crop((466,750,514,787)).tobytes(),image.crop((466,750,514,787)).tobytes())
        self.assertEqual(result.getpixel((184,850))[3],0)
        self.assertEqual(result.getpixel((500,927))[3],0)
        with self.assertRaises(ValueError):p.apply_processing_visibility(image,row,self.config,'b'*64)

    def test_output_only_middle_capture_shares_corrections_that_wrap_planned_recipe(self):
        p=self.module('tools/art/portrait_pipeline.py','portrait_output_middle_test')
        generation=self.receipt(p);slot=next(r for r in self.config['assets'] if r['id']=='eyes_01_neutral')
        planned,_=p.render_prompt(slot,self.config);base,_=p._prompt_definition(slot,self.config)
        middle='Only this exact correction with literal {width} and {description}.'
        tail=' Keep the same full canvas and all actual reference inputs.'
        actual=planned+'\nCRITICAL COMPONENT CORRECTION: '+middle+tail
        generation['records'][0]['prompt']=actual;generation['records'][0]['attempts'][0]['prompt']=actual
        receipt=p.process_parts(self.root,generation,'output-middle',config=self.config);entry=receipt['entries'][0]
        formal=self.root/entry['formal_path'];formal.parent.mkdir(parents=True,exist_ok=True);formal.write_bytes((self.root/entry['path']).read_bytes())
        template=base+'\nCRITICAL COMPONENT CORRECTION: {actual_middle}'+tail
        fragment=p.build_manifest_fragment(self.root,receipt,self.config,encoding_templates={'manifest_component_correction':template})
        row=fragment['assets'][0]
        self.assertIn('actual_middle',row['prompt_params'],'the common correction body must be shared rather than copied into every suffix')
        self.assertEqual(row['prompt_params']['actual_middle'],middle)
        self.assertNotIn('actual_suffix',row['prompt_params'])
        self.assertEqual(fragment['templates'][row['prompt_template']].format(**row['prompt_params']),actual)
        self.assertEqual(row['actual_prompt_sha256'],hashlib.sha256(actual.encode()).hexdigest())

    def test_exact_accessory_processing_mask_moves_complete_pair_without_changing_generation_guide(self):
        p=self.module('tools/art/portrait_pipeline.py','portrait_accessory_region_test')
        row=next(r for r in self.config['assets'] if r['id']=='accessory_07')
        original=p.checker.mask_image(self.config,row['region']).tobytes()
        region=copy.deepcopy(self.config['regions'][row['region']]);region['shape']={'rect':[150,535,660,930]}
        self.config['regions']['scarf_exact_translation']=region
        self.config['processing']['region_overrides'][row['id']]={
            'region':'scarf_exact_translation','reviewed_isolated':True,'reviewed_source_sha256':'c'*64,
            'isolation_evidence':'.tools/scarf-review.json','audit_mask_path':'assets/_incoming/a4_v3/masks/test-scarf.png'}
        self.config['processing']['fine_alignment']['rules'][row['id']]={
            'mode':'anchor','target_center':[400,750],'fit_rect':[150,535,660,930],
            'min_extent':[0,0],'max_extent':[500,350],'reviewed_isolated':True,
            'reviewed_source_sha256':'c'*64,'isolation_evidence':'.tools/scarf-review.json'}
        p.validate_config(self.config,self.root)
        image=Image.new('RGBA',(768,1024));ImageDraw.Draw(image).rectangle((250,540,549,839),fill=(120,120,120,255))
        moved,audit=p.align_fine_part(image,row,self.config,'c'*64)
        self.assertEqual(audit['scale'],1)
        self.assertEqual(audit['translation_px'],[0,60])
        self.assertEqual(moved.getchannel('A').getbbox(),(250,600,550,900))
        self.assertEqual(p.checker.mask_image(self.config,row['region']).tobytes(),original)
        with self.assertRaises(ValueError):p.align_fine_part(image,row,self.config,'d'*64)
    def test_compact_a4_selection_uses_only_parts_and_exact_formal_identity(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_compact_identity_test')
        common=self.module('tools/art_pipeline.py','portrait_compact_common_test')
        manifest,row=self.compact_portrait(pipeline)
        queue=common.build_queue(self.root,manifest,'v3','portraits')
        self.assertEqual([x['id'] for x in queue['tasks']],['eyes_01_neutral'])
        self.assertTrue(queue['tasks'][0]['can_generate'])
        self.assertNotIn('OLD COMPLETE PERSON',queue['tasks'][0]['arguments']['prompt'])
        for field,value in [('mood','sad'),('sha256','0'*64),('operation','portrait_part_typo')]:
            bad=copy.deepcopy(manifest);bad['assets'][0][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):
                common.build_queue(self.root,bad,'v3','portraits')
        (self.root/row['path']).unlink()
        missing=common.build_queue(self.root,manifest,'v3','portraits')
        self.assertFalse(missing['tasks'][0]['can_generate'])
        self.assertIn('previous_source',missing['tasks'][0]['pending_reasons'])

    def test_manifest_fragment_retains_actual_manual_prompt_and_rechecks_provenance(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_fragment_test')
        generation=self.receipt(pipeline)
        actual='Actual manual component edit with {literal braces}; do not substitute a planned prompt.'
        generation['records'][0]['prompt']=actual
        generation['records'][0]['attempts'][0]['prompt']=actual
        processed=pipeline.process_parts(self.root,generation,'test1',config=self.config)
        entry=processed['entries'][0]
        formal=self.root/entry['formal_path'];formal.parent.mkdir(parents=True,exist_ok=True)
        formal.write_bytes((self.root/entry['path']).read_bytes())
        fragment=pipeline.build_manifest_fragment(self.root,processed,self.config)
        row=next(x for x in fragment['assets'] if x.get('portrait_asset_id')=='eyes_01_neutral')
        self.assertEqual(fragment['templates'][row['prompt_template']].format(**row['prompt_params']),actual)
        self.assertEqual(row['source_raw_sha256'],generation['records'][0]['sha256'])
        bad=copy.deepcopy(processed);bad['entries'][0]['source_sha256']='0'*64
        with self.assertRaises(ValueError): pipeline.build_manifest_fragment(self.root,bad,self.config)

    def test_shared_prompt_roundtrip_keeps_full_catalog_manifest_under_budget(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_manifest_budget_test')
        generation=self.receipt(pipeline)
        processed=pipeline.process_parts(self.root,generation,'test1',config=self.config)
        entry=processed['entries'][0]
        formal=self.root/entry['formal_path'];formal.parent.mkdir(parents=True,exist_ok=True)
        formal.write_bytes((self.root/entry['path']).read_bytes())
        fragment=pipeline.build_manifest_fragment(self.root,processed,self.config)
        row=fragment['assets'][0]
        self.assertEqual(fragment['templates'][row['prompt_template']].format(**row['prompt_params']),generation['records'][0]['prompt'])
        # Budget-only projections reuse the real row's field lengths, never create
        # images or claim these other catalog IDs have an accepted source.
        projected=[]
        projected_templates=copy.deepcopy(fragment['templates'])
        for slot in self.config['assets']:
            candidate=copy.deepcopy(row)
            candidate.update(path=slot['formal_path'],part_id=slot['part_id'],category=slot['category'],mood=slot['mood'],portrait_asset_id=slot['id'])
            prompt,params=pipeline.render_prompt(slot,self.config)
            template,key=pipeline._prompt_definition(slot,self.config)
            for constant in ('width','height','center_x','eye_y','shoulder_y'):
                template=template.replace('{'+constant+'}',str(params[constant]))
            candidate['prompt_template']=key
            candidate['prompt_params']={k:params[k] for k in row['prompt_params']}
            self.assertEqual(template.format(**candidate['prompt_params']),prompt)
            projected_templates[key]=template
            candidate['source_raw']=self.config['source_root']+'/v3r2/'+slot['id']+'/source-attempt1.png'
            mask=self.config['source_root']+'/masks/v3r2/'+slot['region']+'.png'
            candidate['inputs']=[self.config['mannequin']['path'],mask,self.config['style_reference']['path']]
            if 'mask_path' in candidate: candidate['mask_path']=mask
            projected.append(candidate)
        target=self.root/'assets/ART_ASSET_MANIFEST.json';target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes((ROOT/'assets/ART_ASSET_MANIFEST.json').read_bytes())
        baseline=pipeline.selected_mannequin_fragment(self.root,self.config)
        budget=pipeline.manifest_budget(self.root,{'assets':baseline['assets']+projected,'templates':{**baseline['templates'],**projected_templates}},self.config)
        self.assertLessEqual(budget['proposed_bytes'],self.config['maximum_manifest_bytes'],budget)
        self.assertFalse({'width','height','center_x','eye_y','shoulder_y'} & set(row['prompt_params']))
        self.assertEqual(entry['mask_path'],row['inputs'][1])
        self.assertEqual(entry['mask_path'],row['mask_path'])
        self.assertEqual(entry['mask_sha256'],row['mask_sha256'])
        self.assertEqual(row['actual_prompt_sha256'],hashlib.sha256(generation['records'][0]['prompt'].encode('utf-8')).hexdigest())

    def test_actual_prefix_suffix_share_base_without_reformatting_literal_braces(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_actual_wrapped_prompt_test')
        generation=self.receipt(pipeline)
        self.config['processing']['fine_alignment']['rules'].pop('eyes_01_smile',None)
        second=copy.deepcopy(generation['records'][0]);second['id']='eyes_01_smile'
        generation['records'].append(second)
        actual={}
        for index,record in enumerate(generation['records']):
            slot=next(row for row in self.config['assets'] if row['id']==record['id'])
            planned,_=pipeline.render_prompt(slot,self.config)
            prefix=('Actual {width} stays literal:\n' if index==0 else 'Different {height} guard:\n')
            prompt=prefix+planned+'\nKeep {unchanged} and } literal.'
            record['prompt']=prompt;record['attempts'][0]['prompt']=prompt
            actual[record['id']]=prompt
        receipt=pipeline.process_parts(self.root,generation,'wrapped1',config=self.config)
        for entry in receipt['entries']:
            formal=self.root/entry['formal_path'];formal.parent.mkdir(parents=True,exist_ok=True)
            formal.write_bytes((self.root/entry['path']).read_bytes())
        fragment=pipeline.build_manifest_fragment(self.root,receipt,self.config)
        self.assertEqual(len({row['prompt_template'] for row in fragment['assets']}),1)
        for row in fragment['assets']:
            self.assertIn('actual_prefix',row['prompt_params'])
            self.assertIn('actual_suffix',row['prompt_params'])
            rebuilt=fragment['templates'][row['prompt_template']].format(**row['prompt_params'])
            self.assertEqual(rebuilt,actual[row['portrait_asset_id']])
            self.assertEqual(hashlib.sha256(rebuilt.encode('utf-8')).hexdigest(),row['actual_prompt_sha256'])

    def test_repeated_planned_prompt_keeps_literal_fallback(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_repeated_actual_prompt_test')
        generation=self.receipt(pipeline)
        row=generation['records'][0]
        actual=row['prompt']+'\nRepeat the complete actual instruction:\n'+row['prompt']
        row['prompt']=actual;row['attempts'][0]['prompt']=actual
        receipt=pipeline.process_parts(self.root,generation,'repeated1',config=self.config)
        entry=receipt['entries'][0];formal=self.root/entry['formal_path']
        formal.parent.mkdir(parents=True,exist_ok=True);formal.write_bytes((self.root/entry['path']).read_bytes())
        fragment=pipeline.build_manifest_fragment(self.root,receipt,self.config)
        result=fragment['assets'][0]
        self.assertTrue(result['prompt_template'].startswith('A4_actual_'))
        self.assertEqual(result['prompt_params'],{})
        self.assertEqual(fragment['templates'][result['prompt_template']].format(),actual)

    def test_source_bound_processing_region_preserves_core_and_actual_generation_guide(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_processing_region_test')
        self.references(pipeline)
        self.config['processing']['prevent_core_clipping']=True
        self.config['processing']['source_core_alpha_threshold']=128
        self.config['processing'].pop('region_overrides',None)
        slot=next(row for row in self.config['assets'] if row['id']=='hair_front_12')
        pipeline.prepare_masks(self.root,'test1',only=[slot['id']],config=self.config)
        task=pipeline.build_queue(self.root,'test1',only=[slot['id']],config=self.config,pilot=True)['tasks'][0]
        raw=Image.new('RGB',(768,1024),(255,0,255))
        ImageDraw.Draw(raw).rectangle((130,120,630,930),fill=(120,120,120))
        source=self.image(task['source_destination'],raw)
        actual={'prompt':task['arguments']['prompt'],'ref_paths':task['ref_paths'],'reference_shas':task['reference_shas'],
                'sha256':sha(source),'native_size':[768,1024]}
        record={'id':slot['id'],'status':'complete','source_path':task['source_destination'],'selected_attempt':1,
                'mask_path':task['mask_path'],'mask_sha256':task['mask_sha256'],**actual,
                'attempts':[{'attempt':1,'status':'complete','output_path':task['source_destination'],**actual}]}
        generation={'version':1,'style_reference':self.config['style_reference']['path'],'style_sha256':self.config['style_reference']['sha256'],
                    'mannequin_path':self.config['mannequin']['path'],'mannequin_sha256':self.config['mannequin']['sha256'],'records':[record]}
        with self.assertRaisesRegex(ValueError,'core.*clip'):
            pipeline.process_parts(self.root,generation,'no-region-review',config=self.config)
        self.config['regions']['hair12_processing']={'shape':{'rect':[120,70,640,955]},
            'required_rois':copy.deepcopy(self.config['regions'][slot['region']]['required_rois']),'review_status':'root_coordinates'}
        self.config['processing']['region_overrides']={slot['id']:{'region':'hair12_processing','reviewed_isolated':True,
            'reviewed_source_sha256':sha(source),'isolation_evidence':task['source_destination'],
            'audit_mask_path':'assets/_incoming/a4_v3/masks/source-specific-test/hair12.png'}}
        receipt=pipeline.process_parts(self.root,generation,'reviewed-region',config=self.config)
        entry=receipt['entries'][0];image=Image.open(self.root/entry['path'])
        self.assertEqual(image.getpixel((132,500)),(120,120,120,255))
        self.assertEqual(entry['mask_path'],task['mask_path'])
        self.assertEqual(entry['ref_paths'],task['ref_paths'])
        self.assertEqual(entry['transform']['source_core_outside_region_pixels'],0)
        override=entry['transform']['processing_region_override']
        self.assertNotEqual(override['audit_mask_path'],entry['mask_path'])
        self.assertTrue((self.root/override['audit_mask_path']).is_file())
        pipeline.validate_processing_receipt(self.root,receipt,self.config)
        formal=self.root/entry['formal_path'];formal.parent.mkdir(parents=True,exist_ok=True)
        formal.write_bytes((self.root/entry['path']).read_bytes())
        declared=pipeline.build_manifest_fragment(self.root,receipt,self.config)['assets'][0]
        self.assertEqual(declared['mask_path'],task['mask_path'])
        self.assertEqual(declared['processing_mask_path'],override['audit_mask_path'])
        self.assertEqual(declared['processing_mask_sha256'],override['mask_sha256'])
        self.assertEqual(declared['processing_config_digest'],receipt['config_digest'])
        bad=copy.deepcopy(self.config);bad['processing']['region_overrides'][slot['id']]['reviewed_source_sha256']='0'*64
        with self.assertRaises(ValueError):pipeline.process_parts(self.root,generation,'wrong-source',config=bad)
        old=copy.deepcopy(self.config);old['processing'].pop('region_overrides');old['processing'].pop('prevent_core_clipping');old['processing'].pop('source_core_alpha_threshold')
        historic,transform=pipeline.normalize_part(raw,slot,old,sha(source))
        self.assertEqual(historic.getpixel((132,500))[3],0)
        self.assertNotIn('source_core_outside_region_pixels',transform)

    def test_extra_edit_reference_is_rejected_even_for_an_earlier_attempt(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_previous_attempt_edit_test')
        generation=self.receipt(pipeline);record=generation['records'][0]
        pipeline.validate_generation_receipt(self.root,generation,self.config)
        parent=record['source_path'];path=self.config['source_root']+'/test1/eyes_01_neutral/source-attempt2.png'
        second=self.image(path,Image.open(self.root/parent))
        record.update(source_path=path,sha256=sha(second),selected_attempt=2,edit_source_path=parent)
        record['ref_paths']=record['ref_paths']+[parent]
        record['reference_shas']={**record['reference_shas'],parent:sha(self.root/parent)}
        actual={key:copy.deepcopy(record[key]) for key in ('prompt','ref_paths','reference_shas','sha256','native_size')}
        record['attempts'].append({'attempt':2,'status':'complete','output_path':path,**actual})
        with self.assertRaises(ValueError):pipeline.validate_generation_receipt(self.root,generation,self.config)
        for mutation in ('no_role','self_reference','unrelated_reference'):
            bad=copy.deepcopy(generation);row=bad['records'][0]
            if mutation=='no_role':row.pop('edit_source_path')
            else:
                other=path if mutation=='self_reference' else self.config['mannequin']['source_path']
                row['edit_source_path']=other;row['ref_paths'][-1]=other
                row['reference_shas']={ref:sha(self.root/ref) for ref in row['ref_paths']}
                row['attempts'][-1]['ref_paths']=copy.deepcopy(row['ref_paths'])
                row['attempts'][-1]['reference_shas']=copy.deepcopy(row['reference_shas'])
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):
                pipeline.validate_generation_receipt(self.root,bad,self.config)

    def test_regenerated_mannequin_and_part_do_not_overwrite_each_others_prompt(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_two_template_test')
        generation=self.receipt(pipeline)
        base=Image.open(self.root/self.config['mannequin']['path']).convert('RGB')
        ImageDraw.Draw(base).rectangle((120,680,660,1023),fill=(100,100,100))
        base_path=self.image(self.config['mannequin']['path'],base)
        original=self.image(self.config['mannequin']['source_path'],base)
        self.config['mannequin'].update(sha256=sha(base_path),source_sha256=sha(original))
        generation['mannequin_sha256']=sha(base_path)
        eye=generation['records'][0]
        eye['reference_shas'][self.config['mannequin']['path']]=sha(base_path)
        eye['attempts'][0]['reference_shas'][self.config['mannequin']['path']]=sha(base_path)
        pipeline.prepare_masks(self.root,'test1',only=['mannequin'],config=self.config)
        task=pipeline.build_queue(self.root,'test1',only=['mannequin'],config=self.config)['tasks'][0]
        source=self.image(task['source_destination'],base)
        fields={'prompt':task['arguments']['prompt'],'ref_paths':task['ref_paths'],'reference_shas':task['reference_shas'],'sha256':sha(source),'native_size':[768,1024]}
        mannequin={'id':'mannequin','status':'complete','source_path':task['source_destination'],'mask_path':task['mask_path'],'mask_sha256':task['mask_sha256'],'selected_attempt':1,**fields,
                    'attempts':[{'attempt':1,'status':'complete','output_path':task['source_destination'],**fields}]}
        generation['records'].append(mannequin)
        processed=pipeline.process_parts(self.root,generation,'test1',config=self.config)
        for entry in processed['entries']:
            formal=self.root/entry['formal_path'];formal.parent.mkdir(parents=True,exist_ok=True)
            formal.write_bytes((self.root/entry['path']).read_bytes())
        fragment=pipeline.build_manifest_fragment(self.root,processed,self.config)
        self.assertEqual(len(fragment['assets']),2)
        actual={r['id']:r['prompt'] for r in generation['records']}
        for row in fragment['assets']:
            self.assertEqual(fragment['templates'][row['prompt_template']].format(**row['prompt_params']),actual[row['portrait_asset_id']])

    def test_full_pack_has_140_unique_calls_and_parts_wait_for_new_mannequin(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_full_queue_test')
        self.references(pipeline)
        pipeline.prepare_masks(self.root,'test1',config=self.config)
        queue=pipeline.build_queue(self.root,'test1',config=self.config)
        self.assertEqual(len(queue['tasks']),140)
        self.assertEqual(len({x['id'] for x in queue['tasks']}),140)
        self.assertEqual([x['id'] for x in queue['tasks'] if x['can_generate']],['mannequin'])
        parts=[x for x in queue['tasks'] if x['id']!='mannequin']
        self.assertTrue(all('new_mannequin_review' in x['pending_reasons'] and x['depends_on'] for x in parts))
        self.assertFalse(any('npc_lin' in json.dumps(x) or 'past_life' in json.dumps(x) for x in queue['tasks']))

    def test_selected_mannequin_fragment_uses_actual_prompt_and_enforces_byte_budget(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_baseline_fragment_test')
        self.references(pipeline)
        fragment=pipeline.selected_mannequin_fragment(self.root,self.config)
        row=fragment['assets'][0]
        self.assertEqual(row['operation'],'portrait_mannequin')
        self.assertEqual(row['source_raw_native_size'],[768,1024])
        self.assertEqual(fragment['templates'][row['prompt_template']].format(**row['prompt_params']),'synthetic base fixture')
        self.assertEqual(fragment['selected_attempt'],1)
        self.assertTrue(fragment['budget']['within_limit'])
        self.assertFalse(row['is_transparent_part'])
        bad=copy.deepcopy(self.config);bad['maximum_manifest_bytes']=10
        with self.assertRaises(ValueError): pipeline.selected_mannequin_fragment(self.root,bad)

    def test_mask_revision_does_not_reset_attempt_number_or_replace_old_mask(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_mask_revision_test')
        self.config['regions']['eyes']['shape']['rect']=[272,330,495,393]
        self.references(pipeline)
        old=self.root/'assets/_incoming/a4_v3/masks/test1/eyes.png';old_bytes=old.read_bytes()
        updated=copy.deepcopy(self.config)
        updated['regions']['eyes']['shape']['rect']=[250,324,520,402]
        pipeline.prepare_masks(self.root,'v3r2',only=['eyes_01_neutral'],config=updated)
        try:
            queue=pipeline.build_queue(self.root,'pilot',only=['eyes_01_neutral'],config=updated,mask_revision='v3r2',attempt=2)
        except TypeError as error:
            self.fail('mask revision and real attempt counter must be independent: '+str(error))
        task=queue['tasks'][0]
        self.assertEqual(task['mask_path'],'assets/_incoming/a4_v3/masks/v3r2/eyes.png')
        self.assertTrue(task['source_destination'].endswith('/source-attempt2.png'))
        self.assertEqual(task['attempt_number'],2)
        self.assertEqual(task['attempts_used'],1)
        self.assertEqual(old.read_bytes(),old_bytes)
        self.assertNotEqual(task['mask_sha256'],sha(old))
        with self.assertRaises(ValueError):
            pipeline.build_queue(self.root,'pilot',only=['eyes_01_neutral'],config=updated,mask_revision='v3r2',attempt=5)

    def test_pilot_is_explicit_bounded_and_does_not_mark_provisional_mask_approved(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_pilot_test')
        self.references(pipeline)
        selection=['brows_01','mouth_01_neutral','hair_front_01','hair_back_01','features_adult','accessory_01']
        pipeline.prepare_masks(self.root,'v3r2',only=selection,config=self.config)
        try:
            queue=pipeline.build_queue(self.root,'v3r2',only=selection,config=self.config,mask_revision='v3r2',pilot=True)
        except TypeError as error:
            self.fail('six explicit calibration pilots must be queueable without approving masks: '+str(error))
        self.assertEqual(len(queue['tasks']),6)
        self.assertTrue(all(x['can_generate'] and x['pilot'] and x['mask_review_status']=='provisional' for x in queue['tasks']))
        self.assertFalse(queue['art_passed'])
        with self.assertRaises(ValueError): pipeline.build_queue(self.root,'v3r2',config=self.config,pilot=True)
        with self.assertRaises(ValueError): pipeline.build_queue(self.root,'v3r2',only=selection+['face_01'],config=self.config,pilot=True)

    def test_body_matte_drops_one_pixel_background_strip_without_moving_core(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_body_matte_test')
        self.config['processing']['processing_visibility']['rules']['body_01']['enabled']=False
        raw=Image.new('RGB',(768,1024),(255,0,255));draw=ImageDraw.Draw(raw)
        draw.rectangle((100,680,700,1023),fill=(120,120,120))
        draw.line((0,530,0,950),fill=(238,9,248))
        row=next(x for x in self.config['assets'] if x['id']=='body_01')
        output,transform=pipeline.normalize_part(raw,row,self.config)
        self.assertEqual(output.getpixel((0,800))[3],0,'near-magenta one-pixel border is disconnected from the torso')
        self.assertEqual(output.getpixel((300,800)),(120,120,120,255),'opaque body core must not be recolored or moved')
        self.assertEqual(transform['source_crop'],[0,0,768,1024])

    def test_fine_matte_keeps_single_pixel_features_and_bleeds_only_low_alpha_color(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_fine_matte_test')
        self.assertTrue(hasattr(pipeline,'clean_matte_edges'),'missing category-aware edge cleanup')
        im=Image.new('RGBA',(768,1024));draw=ImageDraw.Draw(im)
        draw.line((300,360,330,360),fill=(100,100,100,255))
        draw.line((430,360,460,360),fill=(100,100,100,255))
        im.putpixel((315,359),(255,255,255,32))
        output,audit=pipeline.clean_matte_edges(im,'eyes_expr',self.config)
        self.assertEqual(output.getpixel((315,359)),(100,100,100,32))
        self.assertEqual(sum(output.getpixel((x,360))[3]>16 for x in range(300,331)),31)
        self.assertEqual(sum(output.getpixel((x,360))[3]>16 for x in range(430,461)),31)
        self.assertEqual(audit['parameters']['erode_pixels'],0)
        self.assertGreater(audit['color_replaced_pixels'],0)

    def test_matte_parameters_reject_nan_missing_category_and_fine_erosion(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_matte_settings_test')
        self.assertEqual(self.config['processing'].get('version'),2,'new edge operation must have a versioned configuration')
        for mutation in ('nan','missing_category','fine_erosion'):
            bad=copy.deepcopy(self.config);cleanup=bad['processing']['edge_cleanup']
            if mutation=='nan':cleanup['profiles']['solid']['feather_pixels']=float('nan')
            elif mutation=='missing_category':cleanup['category_profiles'].pop('eyes_expr')
            else:cleanup['profiles']['fine']['erode_pixels']=1
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):pipeline.validate_config(bad,self.root)

    def test_solid_matte_drops_only_unseeded_islands_and_fine_keeps_them(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_seeded_component_test')
        im=Image.new('RGBA',(32,32));draw=ImageDraw.Draw(im)
        draw.rectangle((8,8,20,20),fill=(100,100,100,255))
        draw.rectangle((20,12,24,16),fill=(180,180,180,48))
        draw.rectangle((26,5,30,10),fill=(180,180,180,48))
        solid,audit=pipeline.clean_matte_edges(im,'body',self.config)
        fine,_=pipeline.clean_matte_edges(im,'eyes_expr',self.config)
        self.assertEqual(solid.getpixel((28,7))[3],0,'disconnected faint noise has no opaque seed')
        self.assertGreater(solid.getpixel((22,14))[3],0,'faint material connected to core must remain')
        self.assertEqual(solid.getpixel((14,14)),(100,100,100,255))
        self.assertEqual(fine.getpixel((28,7))[3],48,'fine profile must not remove small components')
        self.assertGreater(audit['unseeded_removed_pixels'],0)

    def test_attempt_history_is_contiguous_even_when_best_selection_precedes_failures(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_complete_attempt_history_test')
        generation=self.receipt(pipeline);row=generation['records'][0]
        second=copy.deepcopy(row['attempts'][0]);second['attempt']=2
        source=self.image('assets/_incoming/a4_v3/test1/eyes_01_neutral/source-attempt2.png',Image.open(self.root/row['source_path']))
        second['output_path']=source.relative_to(self.root).as_posix()
        failed={'attempt':3,'status':'failed','prompt':row['prompt'],'ref_paths':row['ref_paths'],
                'reference_shas':row['reference_shas'],'error':'synthetic provider failure without output'}
        row.update(selected_attempt=2,source_path=second['output_path'],attempts=[row['attempts'][0],second,failed,{**failed,'attempt':4}])
        pipeline.validate_generation_receipt(self.root,generation,self.config)
        for missing in (1,3):
            bad=copy.deepcopy(generation);bad['records'][0]['attempts']=[a for a in bad['records'][0]['attempts'] if a['attempt']!=missing]
            with self.subTest(missing=missing),self.assertRaises(ValueError):pipeline.validate_generation_receipt(self.root,bad,self.config)
        third=copy.deepcopy(second);third['attempt']=3
        source3=self.image('assets/_incoming/a4_v3/test1/eyes_01_neutral/source-attempt3.png',Image.open(source));third['output_path']=source3.relative_to(self.root).as_posix()
        bad=copy.deepcopy(generation);bad['records'][0].update(selected_attempt=3,source_path=third['output_path'],attempts=[copy.deepcopy(row['attempts'][0]),third])
        with self.assertRaises(ValueError):pipeline.validate_generation_receipt(self.root,bad,self.config)

    def test_fine_affine_contains_complete_mouth_and_rejects_unreviewed_or_whole_person(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_fine_affine_test')
        self.assertTrue(hasattr(pipeline,'align_fine_part'),'missing explicit full-canvas fine alignment')
        row=next(x for x in self.config['assets'] if x['id']=='mouth_01_neutral')
        rule=self.config['processing']['fine_alignment']['rules'][row['id']]
        source=Image.new('RGBA',(768,1024));ImageDraw.Draw(source).rectangle((299,472,470,535),fill=(120,120,120,255))
        aligned,audit=pipeline.align_fine_part(source,row,self.config,rule['reviewed_source_sha256'])
        self.assertEqual(aligned.size,(768,1024))
        self.assertGreaterEqual(audit['scale'],0.5)
        self.assertLessEqual(audit['scale'],2)
        self.assertEqual(audit['source_alpha_bbox'],[299,472,471,536])
        self.assertEqual(audit['target_center'],[384,502])
        self.assertEqual(audit['outside_mask_core_pixels'],0)
        self.assertGreater(aligned.getchannel('A').crop((326,478,430,530)).getbbox()[2],80)
        with self.assertRaises(ValueError):pipeline.align_fine_part(source,row,self.config,'0'*64)
        person=Image.new('RGBA',(768,1024));ImageDraw.Draw(person).rectangle((200,100,600,1023),fill=(120,120,120,255))
        with self.assertRaises(ValueError):pipeline.align_fine_part(person,row,self.config,rule['reviewed_source_sha256'])

    def test_fine_affine_mark_records_upscale_and_never_moves_native_main_layers(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_mark_affine_test')
        self.assertTrue(hasattr(pipeline,'align_fine_part'),'missing explicit full-canvas fine alignment')
        row=next(x for x in self.config['assets'] if x['id']=='features_adult');rule=self.config['processing']['fine_alignment']['rules'][row['id']]
        source=Image.new('RGBA',(768,1024));ImageDraw.Draw(source).rectangle((262,425,268,431),fill=(100,100,100,255))
        aligned,audit=pipeline.align_fine_part(source,row,self.config,rule['reviewed_source_sha256'])
        self.assertAlmostEqual(audit['scale'],10/7)
        self.assertEqual(audit['target_center'],[290,435])
        self.assertTrue(aligned.getchannel('A').crop((284,429,296,441)).getbbox())
        face=next(x for x in self.config['assets'] if x['id']=='face_01')
        same,unaligned=pipeline.align_fine_part(source,face,self.config,'0'*64)
        self.assertIs(same,source)
        self.assertIsNone(unaligned)
        tiny=Image.new('RGBA',(768,1024));tiny.putpixel((265,429),(100,100,100,255))
        with self.assertRaises(ValueError):pipeline.align_fine_part(tiny,row,self.config,rule['reviewed_source_sha256'])

    def test_contain_alignment_rejects_unvalidated_target_center_override(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_contain_shape_test')
        pipeline.validate_config(self.config,self.root)
        for value in (None,[384],['x',365],[float('nan'),365]):
            bad=copy.deepcopy(self.config);bad['processing']['fine_alignment']['rules']['accessory_01']['target_center']=value
            with self.subTest(value=value),self.assertRaises(ValueError):pipeline.validate_config(bad,self.root)

    def test_processing_visibility_is_body_only_and_validates_polygon_and_outfit_scope(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_visibility_settings_test')
        self.assertIn('processing_visibility',self.config['processing'],'missing reversible scoped body visibility')
        for mutation in ('enabled','polygon','outfit','category'):
            bad=copy.deepcopy(self.config);rules=bad['processing']['processing_visibility']['rules'];rule=rules['body_01']
            if mutation=='enabled':rule['enabled']='true'
            elif mutation=='polygon':rule['shape']['polygon'][0]=[99999,0]
            elif mutation=='outfit':rule['compatible_outfit_ids']=['not_a_real_outfit']
            else:rules['eyes_01_neutral']=rules.pop('body_01')
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):pipeline.validate_config(bad,self.root)

    def test_visibility_mask_is_actual_audit_artifact_and_tampering_is_rejected(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_visibility_mask_binding_test')
        # This synthetic source has no actual garment context; the real skin05
        # row-band oracle separately checks the recorded production garment.
        for key in ('audit_preserve_visible_row_band','audit_occluder_path','audit_occluder_sha256',
                    'preserve_reference_path','preserve_reference_sha256'):
            self.config['processing']['processing_visibility']['rules']['body_01'].pop(key,None)
        generation=self.receipt(pipeline)
        pipeline.prepare_masks(self.root,'test1',only=['body_01'],config=self.config)
        task=pipeline.build_queue(self.root,'test1',only=['body_01'],config=self.config)['tasks'][0]
        raw=Image.new('RGB',(768,1024),(255,0,255));draw=ImageDraw.Draw(raw)
        draw.rectangle((300,540,480,800),fill=(120,120,120));draw.rectangle((100,680,700,1023),fill=(120,120,120))
        source=self.image(task['source_destination'],raw);fields={'prompt':task['arguments']['prompt'],'ref_paths':task['ref_paths'],
            'reference_shas':task['reference_shas'],'sha256':sha(source),'native_size':[768,1024]}
        self.config['processing']['processing_visibility']['rules']['body_01']['reviewed_source_sha256']=sha(source)
        row=generation['records'][0];row.update(id='body_01',source_path=task['source_destination'],mask_path=task['mask_path'],mask_sha256=task['mask_sha256'],**fields)
        row['attempts']=[{'attempt':1,'status':'complete','output_path':row['source_path'],**fields}]
        processed=pipeline.process_parts(self.root,generation,'test1',config=self.config)
        mask=self.root/self.config['processing']['processing_visibility']['rules']['body_01']['audit_mask_path']
        self.assertTrue(mask.is_file(),'successful visibility processing must retain its actual mask, not only a declared path')
        self.assertEqual(sha(mask),processed['entries'][0]['transform']['processing_visibility']['mask_sha256'])
        pipeline.validate_processing_receipt(self.root,processed,self.config)
        mask.write_bytes(b'changed visibility mask')
        with self.assertRaises(ValueError):pipeline.validate_processing_receipt(self.root,processed,self.config)

    def test_fine_core_color_bleed_never_lightens_real_dark_detail(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_lash_color_test')
        im=Image.new('RGBA',(32,32));ImageDraw.Draw(im).rectangle((8,8,20,20),fill=(140,140,140,255))
        im.putpixel((9,7),(13,13,13,170));im.putpixel((10,7),(255,255,255,32))
        output,audit=pipeline.clean_matte_edges(im,'eyes_expr',self.config)
        self.assertEqual(output.getpixel((9,7)),(13,13,13,170),'a dark eyelash must not become pale merely because sclera is the nearest opaque seed')
        self.assertEqual(output.getpixel((10,7)),(140,140,140,32),'bright quantization fringe still needs core decontamination')
        self.assertEqual(output.getchannel('A').tobytes(),im.getchannel('A').tobytes())

    def test_short_rear_hair_visibility_is_exact_source_and_id_scoped(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_short_hair_visibility_test')
        rule=self.config['processing']['processing_visibility']['rules']['hair_back_01']
        row=next(r for r in self.config['assets'] if r['id']=='hair_back_01')
        im=Image.new('RGBA',(768,1024));draw=ImageDraw.Draw(im)
        draw.rectangle((219,106,561,481),fill=(120,120,120,255));draw.line((100,1023,664,1023),fill=(255,255,255,16))
        clipped,audit=pipeline.apply_processing_visibility(im,row,self.config,rule['reviewed_source_sha256'])
        self.assertEqual(clipped.crop((0,0,768,600)).tobytes(),im.crop((0,0,768,600)).tobytes())
        self.assertIsNone(clipped.getchannel('A').crop((0,600,768,1024)).getbbox())
        with self.assertRaises(ValueError):pipeline.apply_processing_visibility(im,row,self.config,'0'*64)
        other=next(r for r in self.config['assets'] if r['id']=='hair_back_02')
        unreviewed=copy.deepcopy(self.config)
        # This branch models an ID without its own review; a later real bob02
        # review must not give this synthetic raster authority to inherit it.
        unreviewed['processing']['processing_visibility']['rules'].pop(other['id'],None)
        unchanged,none=pipeline.apply_processing_visibility(im,other,unreviewed,rule['reviewed_source_sha256'])
        self.assertIs(unchanged,im);self.assertIsNone(none)

    def test_fresh_checkout_regeneration_needs_actual_edit_inputs_not_ignored_origin_history(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_fresh_baseline_test')
        common=self.module('tools/art_pipeline.py','portrait_fresh_compact_test')
        manifest,_=self.compact_portrait(pipeline)
        source=self.root/self.config['mannequin']['source_path'];history=self.root/self.config['mannequin']['generation_receipt']
        source_bytes=source.read_bytes();history_bytes=history.read_bytes();source.unlink();history.unlink()
        direct=pipeline.build_queue(self.root,'test1',only=['eyes_01_neutral'],config=self.config)
        self.assertTrue(direct['tasks'][0]['can_generate'],'formal rig/style/mask are the actual new edit inputs')
        self.assertEqual(direct['missing_paths'],[])
        self.assertEqual(set(direct['origin_audit']['missing_paths']),{self.config['mannequin']['source_path'],self.config['mannequin']['generation_receipt']})
        self.assertEqual(direct['origin_audit']['status'],'skipped_missing_origin_evidence')
        self.assertTrue(common.build_queue(self.root,manifest,'v3','portraits')['tasks'][0]['can_generate'])
        with self.assertRaises(ValueError):pipeline.selected_mannequin_fragment(self.root,self.config)
        source.write_bytes(source_bytes)
        self.assertTrue(pipeline.build_queue(self.root,'test1',only=['eyes_01_neutral'],config=self.config)['tasks'][0]['can_generate'])
        history.write_bytes(history_bytes);source.unlink()
        self.assertTrue(pipeline.build_queue(self.root,'test1',only=['eyes_01_neutral'],config=self.config)['tasks'][0]['can_generate'])
        source.write_bytes(source_bytes)
        for path in (source,history,self.root/self.config['mannequin']['path']):
            original=path.read_bytes();path.write_bytes(b'changed existing evidence')
            with self.subTest(path=path),self.assertRaises(ValueError):pipeline.build_queue(self.root,'test1',only=['eyes_01_neutral'],config=self.config)
            path.write_bytes(original)
        generation=self.receipt(pipeline);source.unlink();history.unlink()
        pipeline.validate_generation_receipt(self.root,generation,self.config)

    def test_detached_family_mood_queue_is_core_only_closed_lip_and_shared(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_detached_moods_test')
        self.references(pipeline)
        ids=['eyes_01_smile','eyes_01_hesitant','eyes_01_surprised','eyes_01_sad','mouth_01_smile','mouth_01_hesitant']
        pipeline.prepare_masks(self.root,'mood-guide',only=ids,config=self.config)
        queue=pipeline.build_queue(self.root,'mood-v2',only=ids,config=self.config,mask_revision='mood-guide',attempt=1,pilot=True)
        self.assertEqual([t['id'] for t in queue['tasks']],ids)
        self.assertTrue(all(t['ready'] and t['attempt_number']==1 and t['attempt_cap']==4 for t in queue['tasks']))
        for task in queue['tasks'][:4]:
            prompt=task['arguments']['prompt'].lower()
            self.assertIn('deliver only sclera/irises/pupils',prompt)
            self.assertIn('remove shaded eyelids',prompt)
            self.assertIn('skin border',prompt)
        for task in queue['tasks'][4:]:
            self.assertIn('closed-lip',task['prompt_parameters']['expression'])
            self.assertIn('no teeth or tongue',task['arguments']['prompt'].lower())
        self.assertEqual(len({t['template_key'] for t in queue['tasks'][:4]}),1)
        self.assertEqual(len({t['template_key'] for t in queue['tasks']}),2)
        for row in [x for x in self.config['assets'] if x['category']=='mouth_expr' and x['mood']=='surprised']:
            prompt,params=pipeline.render_prompt(row,self.config)
            self.assertIn('small O-shaped dark opening',params['expression'])
            self.assertNotIn('closed',params['description'].lower())
            self.assertIn('no teeth or tongue',prompt.lower())
        neutral=next(x for x in self.config['assets'] if x['id']=='mouth_01_neutral')
        self.assertEqual(pipeline.render_prompt(neutral,self.config)[1]['expression'],'a neutral expression')
        self.assertFalse(queue['art_passed'])

    def test_family_template_missing_is_pending_and_legacy_prompt_is_unchanged(self):
        pipeline=self.module('tools/art/portrait_pipeline.py','portrait_family_compat_test')
        self.assertEqual(self.config['generation'].get('template_version'),2)
        self.references(pipeline)
        bad=copy.deepcopy(self.config);bad['generation']['family_suffixes'].pop('eyes_expr')
        pending=pipeline.build_queue(self.root,'test1',only=['eyes_01_neutral'],config=bad)
        self.assertEqual(pending['status'],'pending_templates')
        self.assertEqual(pending['tasks'],[])
        no_o_shape=copy.deepcopy(self.config);no_o_shape['generation']['description_overrides'].pop('mouth_01_surprised')
        self.assertEqual(pipeline.build_queue(self.root,'test1',only=['mouth_01_surprised'],config=no_o_shape)['status'],'pending_templates')
        legacy=copy.deepcopy(self.config);legacy['generation']['template_version']=1
        legacy['generation']['template_key']='A4_v3_portrait_part'
        row=next(x for x in legacy['assets'] if x['id']=='mouth_01_smile')
        prompt,params=pipeline.render_prompt(row,legacy)
        self.assertEqual(params['expression'],'a gentle restrained smile')
        self.assertEqual(prompt,legacy['generation']['templates']['part'].format(**params))


if __name__=='__main__': unittest.main()

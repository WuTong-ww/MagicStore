"""Measure production accessory pixels and prove semantic failures are detected."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('clipping',ROOT/'tools/check_portrait_clipping.py')
checker=importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class MountedPortraits(unittest.TestCase):
    def setUp(self):
        self.config=json.loads((ROOT/'data/people/appearance_parts.json').read_text(encoding='utf-8'))

    def test_every_face_hair_accessory_and_outfit_occlusion(self):
        policy=checker.validate_rendering(self.config)
        rows,_=checker.matrix(self.config,policy)
        result=checker.audit_semantics(self.config,rows)
        self.assertEqual(result['matrix_count'],10800)
        self.assertEqual(result['outfit_count'],16)
        self.assertLessEqual(result['maximum_back_visible_fraction'],0.05)
        self.assertEqual(len(result['headphones']),6)
        self.assertEqual(result['hair_preservation_pairs'],72)

    def test_headphones_cannot_expose_skin_by_deforming_hair(self):
        value=copy.deepcopy(self.config)
        value['rendering']['accessories']['accessory_14']['hides']=[dict(mode='press',layer='hair_front',when_ids=['hair_front_01'],center_x=398,top_offset=40,top_scale=.94,end_y=500)]
        rows,_=checker.matrix(value,checker.validate_rendering(value))
        with self.assertRaisesRegex(ValueError,'HEADPHONES_CHANGED_HAIR'):
            checker.audit_semantics(value,rows)

    def test_painted_cushion_drift_is_detected(self):
        value=copy.deepcopy(self.config)
        value['anchors']['faces']['face_01']['ear_l'][0]+=30
        rows,_=checker.matrix(value,checker.validate_rendering(value))
        with self.assertRaisesRegex(ValueError,'EARCUP_TOO_FAR'):
            checker.audit_semantics(value,rows)

    def test_visible_rear_cloth_is_detected(self):
        value=copy.deepcopy(self.config)
        # A registered, nonblank painting placed in front of the head must not
        # pass merely because its render layer is labelled scarf_back.
        head=value['rendering']['attachments']['headphones']['variants']['face_01']
        value['rendering']['attachments']['scarf']['back']={k:head[k] for k in ('path','sha256')}
        rows,_=checker.matrix(value,checker.validate_rendering(value))
        with self.assertRaisesRegex(ValueError,'SCARF_BACK_VISIBLE'):
            checker.audit_semantics(value,rows)

    def test_bad_mount_metadata_is_rejected(self):
        for change in (lambda c:c['anchors']['faces']['face_01'].update(crown=[float('nan'),129]),
                       lambda c:c['rendering']['attachments']['scarf']['front'].update(knot=[460,700]),
                       lambda c:c['rendering']['attachments']['headphones']['variants'].pop('face_06'),
                       lambda c:c['rendering']['attachments']['headphones'].update(split_y=400),
                       lambda c:c['rendering']['attachments']['scarf']['back'].update(path='res://../bad.png'),
                       lambda c:c['rendering']['render_order'].reverse()):
            value=copy.deepcopy(self.config); change(value)
            with self.subTest(change=change),self.assertRaises(ValueError):
                checker.validate_rendering(value)


if __name__=='__main__':
    unittest.main()

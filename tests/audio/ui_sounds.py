"""Decode the actual shipped Ogg candidates and check the requested limits."""
from pathlib import Path
import json
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/audio'))
from analyze_ui_sounds import analyze, measure
import numpy as np

class UISounds(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads((ROOT/'data/ui/audio.json').read_text(encoding='utf-8'))

    def test_decoded_candidates(self):
        catalog = self.data['sound_catalog']
        self.assertEqual(len(catalog),33)
        for resource,row in catalog.items():
            with self.subTest(resource=resource):
                path = ROOT/resource.removeprefix('res://')
                measured = analyze(path)
                self.assertEqual(measured['sha256'],row['sha256'])
                self.assertTrue(measured['passes'])
                self.assertLess(abs(measured['lufs_short_40ms']+20),1)
                self.assertLess(measured['peak_dbfs'],0)
                self.assertEqual(row['license'],'CC0-1.0')
                for key in ['duration_ms','centroid_hz','onset_peak_ratio','tonal_frame_fraction','lufs_short_40ms']:
                    self.assertAlmostEqual(measured[key],row['metrics'][key],places=3)

    def test_buzz_is_not_accepted_as_soft_foley(self):
        rate = 44100
        t = np.arange(round(rate*.2))/rate
        tone = .2*np.sin(2*np.pi*1000*t)
        tone[:220] *= np.linspace(0,1,220)
        tone[-220:] *= np.linspace(1,0,220)
        self.assertFalse(measure(tone,rate)['passes'])

    def test_fullband_hiss_is_not_accepted(self):
        rate=44100
        noise=np.random.default_rng(431).normal(0,.05,round(rate*.2))
        self.assertFalse(measure(noise,rate)['passes'])

if __name__=='__main__':
    unittest.main()

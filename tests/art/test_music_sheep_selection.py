"""The user's specific selection stays local and is deduplicated by the builder."""
from copy import deepcopy
import json
from pathlib import Path
import unittest
from tools.music_build import validate_catalog, selected_tracks

ROOT = Path(__file__).resolve().parents[2]

class SheepSelectionTests(unittest.TestCase):
    def test_user_selection_and_single_runtime_output(self):
        config = json.loads((ROOT / 'data/audio.json').read_text(encoding='utf-8'))
        validate_catalog(config)
        self.assertEqual(config['slots']['day']['track_id'], 'sheep')
        self.assertEqual(config['slots']['deduction']['track_id'], 'sheep')
        self.assertEqual([row['id'] for row in selected_tracks(config)].count('sheep'), 1)

    def test_explicit_mixed_selection_provenance(self):
        config = json.loads((ROOT / 'data/audio.json').read_text(encoding='utf-8'))
        changed = deepcopy(config)
        changed['source']['selection_basis'] = 'filename_and_user_choice'
        validate_catalog(changed)
        changed['source']['selection_basis'] = 'unverified'
        with self.assertRaises(ValueError):
            validate_catalog(changed)

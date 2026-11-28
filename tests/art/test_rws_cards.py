"""Production deck coverage, actual decode/budget and rejection of bad indexes."""
import copy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.art.rws_cards import read, validate_index, validate_provenance


class RWSCards(unittest.TestCase):
    def setUp(self):
        self.deck = read(ROOT / "data/oracle/decks.json")
        self.index = read(ROOT / "data/oracle/card_art.json")

    def test_all_78_decoded_cards_and_budget(self):
        self.assertLessEqual(validate_index(self.index, self.deck), 4_000_000)

    def test_pinned_per_card_provenance(self):
        validate_provenance(read(ROOT / "assets/oracle/rws/provenance.json"), self.index)

    def test_invalid_indexes_rejected(self):
        for change in (lambda x: x.update(version=True), lambda x: x["tarot"].pop("fool"),
                       lambda x: x["tarot"].update(fool="res://../fool.webp"),
                       lambda x: x["tarot"].update(extra="res://assets/oracle/rws/fool.webp")):
            with self.subTest(change=change):
                value = copy.deepcopy(self.index)
                change(value)
                with self.assertRaises(ValueError):
                    validate_index(value, self.deck)


if __name__ == "__main__":
    unittest.main()

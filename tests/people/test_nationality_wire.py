"""Country pools use the same five-field immutable wire identity as legacy pools."""
import copy
import json
from pathlib import Path
import unittest
from server.ai import person_generation as policy

ROOT = Path(__file__).resolve().parents[2]

class CountryWireTests(unittest.TestCase):
    def test_all_authored_countries_and_mixed_residents(self):
        config = json.loads((ROOT/'data/people/name_pools_by_country.json').read_text(encoding='utf-8'))
        templates = json.loads((ROOT/'data/people/templates.json').read_text(encoding='utf-8'))
        old = json.loads((ROOT/'data/people/name_pools.json').read_text(encoding='utf-8'))
        for country in config['countries']:
            with self.subTest(country=country[0]):
                record = {'version':1,'cultural_origin':country[2],'name_pool_id':'country_'+country[0],
                          'name':country[3].split('|')[0]+'·'+country[4].split('|')[0], 'skin_id':country[5][0]}
                self.assertEqual(policy._birth_identity(record),record)
                mixed = copy.deepcopy(record)
                mixed.update(cultural_origin='mixed',name_pool_id='mixed_country_'+country[0],
                             name=templates['ordinary_surnames'][0]+country[3].split('|')[0],skin_id=old['mixed']['skin_ids'][0])
                self.assertEqual(policy._birth_identity(mixed),mixed)
                forged = copy.deepcopy(record)
                forged['nationality']='local'
                self.assertEqual(policy._birth_identity(forged),{})
                forged = copy.deepcopy(record)
                forged['name_pool_id']='country_ZZ'
                self.assertEqual(policy._birth_identity(forged),{})

if __name__ == '__main__': unittest.main()

"""Independent JSON checks only. This does not execute the GDScript selector."""
import copy
import itertools
import json
import math
from pathlib import Path
import unicodedata
import unittest

ROOT = next(parent for parent in Path(__file__).resolve().parents if (parent / 'project.godot').is_file())
DRAFT = ROOT / '.tools/r3-names/drafts'
DATA = ROOT / 'data/people/name_pools.json'
if not DATA.is_file():
    DATA = DRAFT / 'data/people/name_pools.json'
REGIONS = ['europe', 'africa', 'south_asia', 'latin_america', 'middle_east']


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def integer(value, minimum=0):
    return type(value) in (int, float) and math.isfinite(value) and value == int(value) and value >= minimum


def text(value):
    return (isinstance(value, str) and value and value == value.strip()
            and value == unicodedata.normalize('NFKC', value)
            and all(unicodedata.name(c, '').startswith(('CJK UNIFIED IDEOGRAPH-', 'CJK COMPATIBILITY IDEOGRAPH-')) for c in value))


def unique_names(values, minimum, forbidden):
    assert isinstance(values, list) and len(values) >= minimum
    assert len(set(values)) == len(values)
    assert all(text(value) and not any(part in value for part in forbidden) for value in values)


def spaces(rules, templates):
    local = rules['local_pool']
    yield local['id'], templates[local['surnames_source']], templates[local['given_names_source']], rules['formats'][local['format_id']]
    for row in rules['foreign_pools']:
        yield row['id'], row['surnames'], row['given_names'], rules['formats'][row['format_id']]
        yield rules['mixed']['pool_id_prefix'] + row['cultural_origin'], templates[local['surnames_source']], row['given_names'], rules['formats'][rules['mixed']['format_id']]


def validate(rules):
    templates = read(ROOT / 'data/people/templates.json')
    skins = {row['id'] for row in read(ROOT / 'data/people/appearance_parts.json')['palettes']['skin']}
    assert set(rules) == {'version', 'enabled', 'seed_namespace', 'groups', 'regions', 'local_pool', 'foreign_pools', 'mixed', 'formats', 'collision', 'validation'}
    assert integer(rules['version'], 1) and rules['version'] == 1 and type(rules['enabled']) is bool
    assert isinstance(rules['seed_namespace'], str) and rules['seed_namespace'].isascii() and rules['seed_namespace'].replace('_', '').isalnum()
    assert set(rules['groups']) == {'local', 'foreign', 'mixed'}
    assert all(integer(weight) for weight in rules['groups'].values()) and sum(rules['groups'].values()) > 0
    assert [row['id'] for row in rules['regions']] == REGIONS
    assert all(set(row) == {'id', 'weight'} and integer(row['weight']) for row in rules['regions'])
    assert sum(row['weight'] for row in rules['regions']) > 0
    bounds = rules['validation']
    assert set(bounds) == {'minimum_region_names', 'minimum_region_surnames', 'name_minimum', 'name_maximum', 'entry_pattern', 'forbidden_fragments'}
    assert integer(bounds['minimum_region_names'], 30) and integer(bounds['minimum_region_surnames'], 30)
    assert integer(bounds['name_minimum'], 2) and integer(bounds['name_maximum'], bounds['name_minimum']) and bounds['name_maximum'] <= 16
    assert bounds['entry_pattern'] == '^[\\p{Han}]+$'
    assert isinstance(bounds['forbidden_fragments'], list) and bounds['forbidden_fragments'] and all(text(value) for value in bounds['forbidden_fragments'])
    local = rules['local_pool']
    assert set(local) == {'id', 'given_names_source', 'surnames_source', 'skin_ids', 'format_id'}
    assert local['id'] == 'local' and local['given_names_source'] == 'ordinary_names' and local['surnames_source'] == 'ordinary_surnames' and local['format_id'] == 'local'
    assert set(rules['formats']) == {'local', 'foreign', 'mixed'}
    assert rules['formats'] == {'local': '{surname}{given_name}', 'foreign': '{given_name}·{surname}', 'mixed': '{surname}{given_name}'}
    assert set(rules['mixed']) == {'pool_id_prefix', 'skin_ids', 'format_id'} and rules['mixed']['pool_id_prefix'] == 'mixed_' and rules['mixed']['format_id'] == 'mixed'
    assert isinstance(rules['foreign_pools'], list) and len(rules['foreign_pools']) == 5
    assert [row['cultural_origin'] for row in rules['foreign_pools']] == REGIONS
    ids = []
    for row in rules['foreign_pools']:
        assert set(row) == {'id', 'cultural_origin', 'naming_tradition', 'given_names', 'surnames', 'skin_ids', 'format_id'}
        assert row['format_id'] == 'foreign' and row['id'].startswith(row['cultural_origin'] + '_')
        assert isinstance(row['naming_tradition'], str) and row['naming_tradition'].strip()
        unique_names(row['given_names'], bounds['minimum_region_names'], bounds['forbidden_fragments'])
        unique_names(row['surnames'], bounds['minimum_region_surnames'], bounds['forbidden_fragments'])
        ids.append(row['id'])
    assert len(set(ids)) == len(ids)
    for row in [local, rules['mixed']] + rules['foreign_pools']:
        assert isinstance(row['skin_ids'], list) and row['skin_ids'] and len(set(row['skin_ids'])) == len(row['skin_ids'])
        assert set(row['skin_ids']) <= skins
    collision = rules['collision']
    assert set(collision) == {'random_attempts', 'max_scan_steps'} and all(integer(value, 1) for value in collision.values())
    total = 0
    for _pool, surnames, names, template in spaces(rules, templates):
        unique_names(surnames, 1, bounds['forbidden_fragments'])
        unique_names(names, 1, bounds['forbidden_fragments'])
        assert collision['max_scan_steps'] >= len(surnames) * len(names)
        for surname, given in itertools.product(surnames, names):
            name = template.format(surname=surname, given_name=given)
            assert bounds['name_minimum'] <= len(name) <= bounds['name_maximum']
            assert all(c == '·' or text(c) for c in name)
            total += 1
    return total


class NamePoolDataTests(unittest.TestCase):
    def test_data_artifact_exists(self):
        self.assertTrue(DATA.is_file(), 'the isolated production-shaped names JSON is missing')

    def test_complete_rules_and_every_combination(self):
        self.assertEqual(validate(read(DATA)), 15300)

    def test_authored_weights_and_equal_foreign_regions(self):
        rules = read(DATA)
        self.assertEqual(rules['groups'], {'local': 78, 'foreign': 20, 'mixed': 2})
        self.assertEqual([row['weight'] for row in rules['regions']], [1] * 5)

    def test_local_domains_are_references_to_unchanged_existing_arrays(self):
        templates = read(ROOT / 'data/people/templates.json')
        self.assertEqual(len(templates['ordinary_surnames']), 40)
        self.assertEqual(len(templates['ordinary_names']), 120)
        self.assertNotIn('given_names', read(DATA)['local_pool'])

    def test_schema_counts_refs_and_bad_values_fail(self):
        rules = read(DATA)
        mutations = [lambda r: r['foreign_pools'][0]['given_names'].pop(),
            lambda r: r['foreign_pools'][0]['surnames'].pop(),
            lambda r: r['foreign_pools'][0]['given_names'].__setitem__(1, r['foreign_pools'][0]['given_names'][0]),
            lambda r: r['foreign_pools'][0]['given_names'].__setitem__(0, ' 玛丽'),
            lambda r: r['foreign_pools'][0]['given_names'].__setitem__(0, '玛\u200b丽'),
            lambda r: r['foreign_pools'][0]['skin_ids'].append('skin_99'),
            lambda r: r['foreign_pools'][0].__setitem__('cultural_origin', 'local'),
            lambda r: r['local_pool'].__setitem__('surnames_source', 'legacy_sampler'),
            lambda r: r['formats'].__setitem__('mixed', '{given_name}·{surname}'),
            lambda r: r['groups'].__setitem__('foreign', -1),
            lambda r: r['groups'].__setitem__('foreign', float('nan')),
            lambda r: r['groups'].update(local=0, foreign=0, mixed=0),
            lambda r: r['collision'].__setitem__('max_scan_steps', 29),
            lambda r: r['validation'].__setitem__('minimum_region_names', 1),
            lambda r: r['validation'].__setitem__('name_maximum', 99),
            lambda r: r.__setitem__('enabled', 1),
            lambda r: r.__setitem__('extra', 'not allowed')]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                changed = copy.deepcopy(rules)
                mutate(changed)
                with self.assertRaises((AssertionError, KeyError, TypeError)):
                    validate(changed)


if __name__ == '__main__':
    unittest.main()

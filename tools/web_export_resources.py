"""Exclude unused scene originals from Web output without deleting source art.

Keep dynamic JSON references plus literal script/scene/theme dependencies. Only
the generated-scene PNG families are eligible; all other assets stay untouched.
"""
import argparse
import json
import re
from pathlib import Path

RUNTIME_JSON = (
    'data/shop/visuals.json', 'data/people/appearance_parts.json',
    'data/past_lives/registry.json', 'data/ui/audio.json', 'data/ui/item_visuals.json',
)
SCENE_FAMILIES = (
    'assets/generated_scenes/v2', 'assets/generated_scenes/runtime/v2',
    'assets/generated_scenes/v3_final', 'assets/generated_scenes/runtime/v3_final',
)

def scene_exclusions(root):
    references = set()
    def visit(value):
        if isinstance(value, str) and value.startswith('res://'):
            references.add(value.removeprefix('res://'))
        elif isinstance(value, dict):
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    for relative in RUNTIME_JSON:
        visit(json.loads((root / relative).read_text(encoding='utf-8')))
    for directory in ('scripts', 'scenes', 'themes'):
        for source in (root / directory).rglob('*'):
            if source.suffix in ('.gd', '.tscn', '.tres'):
                references.update(re.findall(r'res://([^"\s\'\)]+)', source.read_text(encoding='utf-8')))
    candidates = {path.relative_to(root).as_posix()
                  for directory in SCENE_FAMILIES
                  for path in (root / directory).rglob('*.png')}
    excluded = candidates - references
    # The game loads resources from these roots. Local vendor downloads placed
    # beside the project (for example a whole music pack) are not game resources.
    # Keep them on disk, but never let all_resources add them to a public build.
    runtime_roots = {'assets', 'data', 'scenes', 'scripts', 'themes', 'shaders', '.godot'}
    for entry in root.iterdir():
        if entry.is_dir() and entry.name not in runtime_roots:
            excluded.add(entry.name + '/*')
        elif entry.is_file() and entry.name not in {'project.godot', 'export_presets.cfg'}:
            excluded.add(entry.name)
    return sorted(excluded)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    excluded = scene_exclusions(args.workspace.resolve())
    assert all(',' not in path and '"' not in path and '\n' not in path for path in excluded)
    print(','.join(excluded))

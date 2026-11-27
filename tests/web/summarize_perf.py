"""Summarize numeric Chrome benchmark receipts without treating missing runs as passes."""
import argparse
import hashlib
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path


def summarize(path):
    raw = path.read_bytes()
    rows = [json.loads(line) for line in raw.decode('utf-8').splitlines() if line.strip()]
    groups = defaultdict(list)
    for row in rows:
        for key in ('ms', 'frame_ms', 'draw_calls'):
            assert type(row[key]) in (int, float) and math.isfinite(row[key]) and row[key] >= 0
        groups[(row['kind'], row['label'])].append(row)
        groups[(row['kind'], '*')].append(row)
    result = {
        'source': str(path), 'sha256': hashlib.sha256(raw).hexdigest(),
        'rows': len(rows),
        'benchmark_completed': any(r['kind'] == 'benchmark_done' and r['success'] for r in rows),
        'failed_rows': sum(not r['success'] for r in rows), 'groups': [],
    }
    for (kind, label), values in sorted(groups.items()):
        times = sorted(row['ms'] for row in values)
        draws = sorted(row['draw_calls'] for row in values)
        result['groups'].append({
            'kind': kind, 'label': label, 'samples': len(times),
            'median_ms': statistics.median(times),
            'p95_ms': times[math.ceil(len(times)*.95)-1], 'max_ms': times[-1],
            'median_draw_calls': statistics.median(draws), 'max_draw_calls': draws[-1],
        })
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('log', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = summarize(args.log)
    if args.output:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'groups'}, ensure_ascii=False))
    for group in report['groups']:
        if group['label'] == '*':
            print(json.dumps(group, ensure_ascii=False))

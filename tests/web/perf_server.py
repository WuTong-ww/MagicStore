"""Local-only preview server; stores numeric performance receipts, never save data."""
import argparse
import functools
import http.server
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--directory', required=True)
parser.add_argument('--log', required=True)
parser.add_argument('--port', type=int, default=8834)
args = parser.parse_args()
destination = Path(args.log).resolve()
destination.parent.mkdir(parents=True, exist_ok=True)

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

    def do_POST(self):
        if self.path != '/__r4perf':
            self.send_error(404)
            return
        try:
            payload = json.loads(self.rfile.read(min(int(self.headers.get('Content-Length', 0)), 65536)))
            rows = payload if isinstance(payload, list) else [payload]
            assert 0 < len(rows) <= 128
            for row in rows:
                assert set(row) == {'kind', 'label', 'ms', 'success', 'draw_calls', 'frame_ms'}
                assert row['kind'] in {'save', 'button', 'page', 'input', 'feedback', 'input_feedback', 'component', 'panel', 'prepare', 'frame', 'benchmark_done', 'benchmark_failed'}
                assert isinstance(row['label'], str) and len(row['label']) < 80
                assert all(isinstance(row[k], (int, float)) for k in ['ms', 'draw_calls', 'frame_ms'])
            with destination.open('a', encoding='utf-8') as stream:
                for row in rows:
                    stream.write(json.dumps(row, ensure_ascii=False) + '\n')
            self.send_response(204)
            self.end_headers()
        except (ValueError, AssertionError, TypeError):
            self.send_error(400)

server = http.server.ThreadingHTTPServer(('127.0.0.1', args.port), functools.partial(Handler, directory=str(Path(args.directory).resolve())))
print(f'R4 local preview: http://127.0.0.1:{args.port}/', flush=True)
server.serve_forever()

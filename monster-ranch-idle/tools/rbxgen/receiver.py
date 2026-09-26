"""Receives what generate.luau posts from Studio: every post body is saved as art/rbxgen/_posted/<n>.json.

  python tools/rbxgen/receiver.py [PORT]     (default 38519; generate.luau's `post` URL must match)

Leave it running while Studio generates, then run assemble.py on art/rbxgen/_posted. Listens on
127.0.0.1 only.
"""

import http.server
import itertools
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "art" / "rbxgen" / "_posted"
OUT.mkdir(parents=True, exist_ok=True)
count = itertools.count(max((int(p.stem) for p in OUT.glob("*.json") if p.stem.isdigit()), default=-1) + 1)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        path = OUT / f"{next(count):05d}.json"
        path.write_bytes(body)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(path.name.encode())

    def log_message(self, *args):  # one line per chunk would bury everything else
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 38519
    print(f"receiving on 127.0.0.1:{port} -> {OUT}", flush=True)
    http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()

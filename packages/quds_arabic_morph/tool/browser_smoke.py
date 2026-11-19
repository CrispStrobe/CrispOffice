#!/usr/bin/env python3
"""Run tool/browser_smoke.dart in headless Chrome against the built worker.

    dart compile js tool/browser_smoke.dart -o <out>/smoke.js
    python3 tool/browser_smoke.py --script <out>/smoke.js --web build/web \
        --bundle <proofing-bin bundle dir> --corpus pud.txt [--chrome <binary>]

Serves the page, the compiled smoke script, the built worker/module/wasm,
the verified bundle and the corpus from one local origin, starts Chrome
headless with a fresh profile, waits for the page to POST its report and
prints it together with Chrome's peak resident memory (all its processes).
"""
from __future__ import annotations

import argparse
import http.server
import json
from pathlib import Path
import subprocess
import tempfile
import threading
import time

PAGE = b"""<!doctype html><meta charset="utf-8"><title>arabic morph smoke</title>
<script defer src="/smoke.js"></script>"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--script", type=Path, required=True)
    parser.add_argument("--web", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--chrome", default="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    result: dict = {}
    done = threading.Event()
    routes = {"/": ("text/html", lambda: PAGE), "/smoke.js": ("text/javascript", args.script.read_bytes),
              "/corpus.txt": ("text/plain; charset=utf-8", args.corpus.read_bytes)}
    for path in args.web.iterdir():
        kind = {".mjs": "text/javascript", ".wasm": "application/wasm"}.get(path.suffix)
        if kind:
            routes[f"/web/{path.name}"] = (kind, path.read_bytes)
    for path in args.bundle.iterdir():
        routes[f"/bundle/{path.name}"] = ("application/octet-stream", path.read_bytes)

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):  # noqa: N802
            route = routes.get(self.path)
            if route is None:
                self.send_error(404)
                return
            body = route[1]()
            self.send_response(200)
            self.send_header("Content-Type", route[0])
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):  # noqa: N802
            body = self.rfile.read(int(self.headers["Content-Length"]))
            result.update(json.loads(body))
            self.send_response(204)
            self.end_headers()
            done.set()

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_address[1]}/"
    with tempfile.TemporaryDirectory() as profile:
        chrome = subprocess.Popen([args.chrome, "--headless=new", f"--user-data-dir={profile}", "--no-first-run",
                                   "--disable-extensions", url],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        peak = 0
        deadline = time.time() + args.timeout
        try:
            while not done.is_set() and time.time() < deadline:
                listing = subprocess.run(["ps", "-axo", "rss=,command="], capture_output=True, text=True).stdout
                rss = [int(line.split(None, 1)[0]) for line in listing.splitlines() if profile in line]
                peak = max(peak, sum(rss))
                done.wait(0.25)
        finally:
            chrome.terminate()
            chrome.wait(10)
            server.shutdown()
    result["chrome_peak_rss_mb_all_processes"] = peak // 1024
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result.get("status") == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())

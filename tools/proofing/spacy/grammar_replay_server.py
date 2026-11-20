#!/usr/bin/env python3
"""Serve the consumed grammar panels to the on-device replay and keep its reports.

The Studio integration test `integration_test/mobile_spacy_grammar_replay_test.dart`
reads the W6, W7 and grammar v2 inputs over HTTP (they are not packaged in
the app) and uploads one report per panel. Every input is verified against
its pinned SHA-256 here *and* in the test. The retained W7 result is fetched
from its immutable Hub revision unless `--w7-recorded` names a local copy.

    python3 tools/proofing/spacy/grammar_replay_server.py --port 8765 --reports <new dir>
    adb reverse tcp:8765 tcp:8765    # Android emulator: device 127.0.0.1 -> host

Binds 127.0.0.1 only. GET /inputs/<name>; PUT /reports/<name>.json (refuses
to overwrite).
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import http.server
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[3]
W7_URL = ("https://huggingface.co/cstr/crispembed-spacy-de-core-news-sm-3.8.0/resolve/"
          "4d3f24b39c70f1f6f2b70c0eaed3c3b1dbc0af23/retained-w7-evidence/"
          "14a0da47db8e144e09e8d261f937e972f78387e3/44262982569/new-panel-result.json")
V2 = "docs/validation/native-spacy-grammar-v2-20261120"
# name -> (SHA-256, source): a repository path, "gz:" + path, or "w7".
INPUTS = {
    "w6-panel.json": ("52bede2f915db66489b45657d9b605f357d000b2024c8c734b57c10b3457a826",
                      "docs/validation/native-spacy-w6-20261117/qualification-panel.json"),
    "w6-recorded.json": ("2e85b9721368e9e69b7fbeba0ec05105190374d757068706b90f2d7e2f615d58",
                         "docs/validation/native-spacy-w6-20261117/qualification-first.json"),
    "w7-panel.json": ("92338ceb27d2877a6b0cfbfd1218440f53db6509d80571f85d34cfb0d0118ecd",
                      "docs/validation/native-spacy-macos-bundled-20261119/w7-extension-panel/panel.json"),
    "w7-recorded.json": ("a6546bb627c997a9e05771030d303cb627dded996b340e256e909ea55829cdaf", "w7"),
    "v2-protocol.json": ("6412ccf41b7398ce161db5880562badb04f6359bf0ad6c01385675bf0e2474fc",
                         f"{V2}/protocol.json"),
    "v2-panel.json": ("80997c7efbd7891e03510ff300d6d341fa29742c863f446224274be572d3c310",
                      f"{V2}/qualification-panel.json"),
    "v2-corpus.json": ("c9e037eee897f27865d5462f5ce1bc4ffb235b34adc7e1a2ecfb81cfcc9bbf9b",
                       f"{V2}/clean-corpus-gsd-test.json"),
    "v2-recorded.json": ("c3336e439c5c7fed86e6ea6ed716169c4f141659260bcc2b185e73b7472e0861",
                         f"gz:{V2}/qualification-macos.json.gz"),
}


def load(w7_recorded: Path | None) -> dict[str, bytes]:
    data = {}
    for name, (digest, source) in INPUTS.items():
        if source == "w7":
            raw = w7_recorded.read_bytes() if w7_recorded else urllib.request.urlopen(W7_URL).read()
        elif source.startswith("gz:"):
            raw = gzip.decompress((ROOT / source[3:]).read_bytes())
        else:
            raw = (ROOT / source).read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest:
            raise SystemExit(f"{name}: SHA-256 differs from the pin")
        data[name] = raw
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--reports", type=Path, required=True)
    parser.add_argument("--w7-recorded", type=Path)
    args = parser.parse_args()
    data = load(args.w7_recorded)
    args.reports.mkdir(parents=True, exist_ok=True)

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            name = self.path.removeprefix("/inputs/")
            body = data.get(name) if self.path.startswith("/inputs/") else None
            if body is None:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_PUT(self):  # noqa: N802
            name = self.path.removeprefix("/reports/")
            if not self.path.startswith("/reports/") or not re.fullmatch(r"[a-z0-9-]+\.json", name):
                self.send_error(400)
                return
            body = self.rfile.read(int(self.headers["Content-Length"]))
            try:
                with open(args.reports / name, "xb") as handle:
                    handle.write(body)
            except FileExistsError:
                self.send_error(409)
                return
            self.send_response(201)
            self.send_header("Content-Length", "0")
            self.end_headers()

    print(f"serving {len(data)} verified inputs on 127.0.0.1:{args.port}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

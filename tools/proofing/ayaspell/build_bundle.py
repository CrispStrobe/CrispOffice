#!/usr/bin/env python3
"""Build (and optionally publish) the downloadable AyaSpell Arabic bundle.

Downloads the AyaSpell Hunspell dictionary and thesaurus exactly as packaged
in LibreOffice `dictionaries` (pinned commit), verifies every byte, adds the
MPL 1.1 licence text (the licence Quds elects from the GPL/LGPL/MPL
tri-licence), a manifest and a Hugging Face card. The dictionary files are
published unmodified.

    python3 tools/proofing/ayaspell/build_bundle.py --output /tmp/ayaspell-ar
    HF_TOKEN=... python3 tools/proofing/ayaspell/build_bundle.py \\
        --output /tmp/ayaspell-ar --publish cstr/ayaspell-ar-hunspell

The bundle is downloaded by the user from inside the app; it is never part
of the application binary (docs/roadmaps/arabic-proofing.md).
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import urllib.request

COMMIT = "951bb429a4d846699b02e7adb4fc6fca128c6bae"
BASE = f"https://raw.githubusercontent.com/LibreOffice/dictionaries/{COMMIT}/ar/"
FILES = {
    "ar.aff": ("cec30b8621001e49618feb05aec1984c5fcfbf7d2ec309901d5cbf66585217a3", 86949),
    "ar.dic": ("2a3e5367f61c1583734db9d66734f5603e6be5c2d227cf5c5cd7e4ca586e34fe", 7217161),
    "th_ar.dat": ("ad5578cc74884bd9b3f296d734f96a43689406e6dec65492d1912be46e5d770b", 635325),
    "COPYING.txt": ("73480d918cd78d655508e80aa88c022cbd53634524a0f714b5f2519f2cf19124", 532),
    "AUTHORS.txt": ("bade1d2d0d47dff5956c08732cdb9c02432d9b0b8016a56e27f58b8d7e842462", 200),
    "README_ar.txt": ("5ead684ae5211ccf615686959e24bd21ef6eebbb6195997529fda08b993f615e", 420),
}
MPL = ("https://raw.githubusercontent.com/spdx/license-list-data/v3.25.0/text/MPL-1.1.txt",
       "6214f8b1300bb9f37b16ebc146f8f61af0187e0025042ff95c8b3030744a8795")


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as response:  # noqa: S310 (pinned https URLs)
        return response.read()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


CARD = """---
license: other
license_name: mpl-1.1
license_link: https://www.mozilla.org/en-US/MPL/1.1/
language:
- ar
tags:
- hunspell
- spellchecking
- arabic
---

# AyaSpell Arabic dictionary for Hunspell

The AyaSpell Arabic spelling dictionary (`ar.aff`, `ar.dic`) and Arabic
thesaurus (`th_ar.dat`, MyThes format), byte-identical to the
[LibreOffice dictionaries packaging](https://github.com/LibreOffice/dictionaries/tree/{commit}/ar)
at commit `{commit}` (AyaSpell 3.5 package). Upstream project:
[AyaSpell](http://ayaspell.sourceforge.net/) /
[linuxscout/ayaspell](https://github.com/linuxscout/ayaspell).

Authors: Mohamed Kebdani (dictionary, 2006–2008), Taha Zerrouki (thesaurus
and project, 2006–2009); OpenOffice packaging by Ahmad Farghal. See
`AUTHORS.txt` and `README_ar.txt`.

## Licence

The original files are offered under a GPL 2.0 / LGPL 2.1 / MPL 1.1
tri-licence, each "or later" (`COPYING.txt`). This distribution is provided
under the **Mozilla Public License 1.1** (`MPL-1.1.txt`); the other two
options remain available to recipients as stated in `COPYING.txt`. The files
are unmodified; their source form is this repository.

## Use

Load with any Hunspell-compatible engine, e.g. `hunspell -d ar`. Quds Office
downloads this bundle on the user's request; it is not part of the
application. `manifest.json` lists the SHA-256 of every file.
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--publish", metavar="REPO_ID", help="Hugging Face model repo to upload to (needs HF_TOKEN)")
    args = parser.parse_args()
    out = args.output
    out.mkdir(parents=True, exist_ok=True)
    manifest = {"schema": "quds.proofing.hunspell_bundle.v1", "language": "ar",
                "source": {"repository": "https://github.com/LibreOffice/dictionaries", "commit": COMMIT,
                           "path": "ar/"},
                "licence": {"elected": "MPL-1.1", "offered": "GPL-2.0-or-later OR LGPL-2.1-or-later OR MPL-1.1+"},
                "files": {}}
    for name, (expected, size) in FILES.items():
        data = fetch(BASE + name)
        if len(data) != size or sha256(data) != expected:
            print(f"{name}: unexpected bytes ({len(data)} B, sha256 {sha256(data)})", file=sys.stderr)
            return 1
        (out / name).write_bytes(data)
        manifest["files"][name] = {"sha256": sha256(data), "bytes": len(data), "origin": BASE + name}
    licence = fetch(MPL[0])
    if sha256(licence) != MPL[1]:
        print("MPL-1.1 text changed", file=sys.stderr)
        return 1
    (out / "MPL-1.1.txt").write_bytes(licence)
    manifest["files"]["MPL-1.1.txt"] = {"sha256": MPL[1], "bytes": len(licence), "origin": MPL[0]}
    card = CARD.format(commit=COMMIT).encode("utf-8")
    (out / "README.md").write_bytes(card)
    manifest["files"]["README.md"] = {"sha256": sha256(card), "bytes": len(card), "origin": "generated"}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8",
                                       newline="\n")
    print(f"bundle written to {out}")
    if args.publish:
        from huggingface_hub import HfApi
        api = HfApi()
        api.create_repo(args.publish, repo_type="model", exist_ok=True)
        commit = api.upload_folder(repo_id=args.publish, folder_path=str(out), repo_type="model",
                                   commit_message=f"AyaSpell Arabic from LibreOffice dictionaries {COMMIT[:10]}")
        print(f"published {args.publish} at {commit.oid}")
        # Read back every file at the new immutable revision.
        for name, entry in manifest["files"].items():
            data = fetch(f"https://huggingface.co/{args.publish}/resolve/{commit.oid}/{name}")
            if sha256(data) != entry["sha256"]:
                print(f"readback mismatch: {name}", file=sys.stderr)
                return 1
        manifest_bytes = (out / "manifest.json").read_bytes()
        if sha256(fetch(f"https://huggingface.co/{args.publish}/resolve/{commit.oid}/manifest.json")) != \
                sha256(manifest_bytes):
            print("readback mismatch: manifest.json", file=sys.stderr)
            return 1
        print("readback verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())

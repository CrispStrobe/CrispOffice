#!/usr/bin/env python3
"""Verify every bundled file and a bounded, source-identified lexical panel."""
import argparse
import json
from pathlib import Path
import platform
import sys
import time
import zlib

from build_packs import DEFAULT_OUTPUT, ROOT, digest, encoded, normalize, require, shard

PANEL = {
    "en": {
        "bank": {"oewn-08437235-n", "oewn-09236472-n"},
        "ice cream": {"oewn-07630109-n"},
        "colour": {"oewn-00284671-v"},
        "mice": {"oewn-02332897-n"},
    },
    "de": {
        "Bank": {"ot-10147", "ot-305"},
        "Maße": {"ot-1275", "ot-39754"},
        "Masse": {"ot-17013", "ot-1824"},
        "sich freuen": {"ot-38103", "ot-49053", "ot-52295"},
        "Jänner": {"ot-12476"},
        "Oheim": {"ot-13017"},
    },
}


def verify(root: Path) -> dict:
    reports = {}
    for locale, queries in PANEL.items():
        directory = root / locale
        manifest_bytes = (directory / "manifest.json").read_bytes()
        manifest = json.loads(manifest_bytes)
        data = {}
        expected_paths = {"manifest.json"}
        start = time.monotonic()
        for name, info in manifest["files"].items():
            compressed = info.get("compression") == "deflate-raw"
            path = name + ".deflate" if compressed else name
            expected_paths.add(path)
            value = (directory / path).read_bytes()
            if compressed:
                require(len(value) == info["compressedSize"] and digest(value) == info["compressedSha256"],
                        f"Compressed verification failed: {locale}/{path}")
                value = zlib.decompress(value, -15)
            require(len(value) == info["size"] and digest(value) == info["sha256"],
                    f"Logical verification failed: {locale}/{name}")
            if name.endswith(".json"):
                data[name] = json.loads(value)
        actual_paths = {str(p.relative_to(directory)) for p in directory.rglob("*") if p.is_file()}
        require(actual_paths == expected_paths, f"Unexpected/missing packaged files: {locale}")
        all_senses = {key: value for name, entries in data.items() if name.startswith("senses/")
                      for key, value in entries.items()}
        all_index = {key: value for name, entries in data.items() if name.startswith("index/")
                    for key, value in entries.items()}
        for name, entries in data.items():
            if name.startswith(("senses/", "index/")):
                require(all(name.split("/")[1] == shard(key) + ".json" for key in entries),
                        f"Wrong shard placement: {locale}/{name}")
        for key, entry in all_index.items():
            require(isinstance(entry["senseIds"], list) and isinstance(entry["aliases"], list),
                    "Invalid index shape")
            require(set(entry["senseIds"]) <= all_senses.keys(), "Dangling meaning membership")
            for alias in entry["aliases"]:
                require(normalize(alias["lemma"]) in all_index, "Dangling lookup alias")
        for sid, sense in all_senses.items():
            require(sid == sense["id"] and sense["source"] == manifest["source"], "Source identity mismatch")
            term_ids = set()
            for term in sense["terms"]:
                require(term["id"] not in term_ids and sid in all_index[normalize(term["text"])]["senseIds"],
                        "Lost or duplicate term membership")
                term_ids.add(term["id"])

        def lookup(query):
            entry = all_index.get(normalize(query), {"senseIds": [], "aliases": []})
            found = set(entry["senseIds"])
            for alias in entry["aliases"]:
                for sid in all_index[normalize(alias["lemma"])]["senseIds"]:
                    pos = alias.get("pos")
                    source_pos = all_senses[sid].get("pos")
                    if not pos or not source_pos or pos == source_pos or (pos == "a" and source_pos == "s"):
                        found.add(sid)
            return found

        panel = {}
        for query, expected in queries.items():
            actual = lookup(query)
            require(expected <= actual, f"Missing expected sense: {locale}/{query}: {expected - actual}")
            panel[query] = {"senseIds": sorted(actual), "minimumExpectedSenseIds": sorted(expected)}
        require(not lookup("qudszznonexistentlexicalprobe"), "Negative control unexpectedly found")
        if locale == "de":
            require(lookup("Maße").isdisjoint(lookup("Masse")), "German sharp-s conflated")
            require(any("österreichisch" in t.get("labels", []) for t in all_senses["ot-12476"]["terms"]
                        if t["text"] == "Jänner"), "Lost German regional label")
            require(any("veraltet" in t.get("labels", []) for t in all_senses["ot-13017"]["terms"]
                        if t["text"] == "Oheim (mütterliche Linie)"), "Lost German historical label")
        else:
            require(any("British spelling" in t.get("labels", []) for t in all_senses["oewn-00284671-v"]["terms"]
                        if t["text"] == "colour"), "Lost English spelling label")
            require(all(all_senses[s]["pos"] == "n" for s in lookup("mice")), "Morphology POS leaked")
        require(len(all_senses) == manifest["counts"]["meaningGroups"], "Incorrect manifest count")
        reports[locale] = {"manifestSha256": digest(manifest_bytes), "verifiedFiles": len(expected_paths),
                           "meaningGroups": len(all_senses), "indexKeys": len(all_index),
                           "packBytes": sum(p.stat().st_size for p in directory.rglob("*") if p.is_file()),
                           "validationSeconds": round(time.monotonic() - start, 3), "panel": panel,
                           "negativeControl": "qudszznonexistentlexicalprobe"}
    return {"status": "passed", "python": sys.version.split()[0], "platform": platform.platform(),
            "scope": "All packaged bytes/index memberships; bounded source-backed lexical checks. Not an independent human linguistic review.",
            "packs": reports}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packs", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--output", type=Path, default=ROOT / "packages/quds_office_engine/third_party/thesaurus/qualification.json")
    args = parser.parse_args()
    result = verify(args.packs)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({lang: {k: v for k, v in info.items() if k not in {"panel"}}
                      for lang, info in result["packs"].items()}, indent=2))

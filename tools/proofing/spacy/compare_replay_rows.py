#!/usr/bin/env python3
"""Compare two grammar replay reports row by row, every field.

Used to check that a candidate build (for example the Android library run on
the emulator) gives exactly the rows of a qualified build replayed with the
same planner source (for example the app-bundled macOS library). Only the
build digest (`library_sha256` equal to the report's own library) is
normalized, and the Mach-O `code_sha256` is dropped; every other field of
every row must be identical.

    python3 tools/proofing/spacy/compare_replay_rows.py \
        --candidate <android report.json[.gz]> --reference <macOS report.json[.gz]> \
        [--report <out.json>]
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path


def read(path: Path) -> tuple[dict, str]:
    raw = path.read_bytes()
    if path.suffix == ".gz":
        raw = gzip.decompress(raw)
    return json.loads(raw), hashlib.sha256(raw).hexdigest()


def library(report: dict) -> str:
    return report.get("library_sha256") or report["native_library_sha256"]


def normalize(value, lib: str):
    if isinstance(value, dict):
        return {k: ("<LIBRARY>" if k == "library_sha256" and v == lib else normalize(v, lib))
                for k, v in value.items() if k != "code_sha256"}
    if isinstance(value, list):
        return [normalize(v, lib) for v in value]
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    candidate, candidate_sha = read(args.candidate)
    reference, reference_sha = read(args.reference)
    a_rows, b_rows = candidate["rows"], reference["rows"]
    differences, fields = [], 0
    if len(a_rows) != len(b_rows):
        differences.append({"field": "row_count", "candidate": len(a_rows), "reference": len(b_rows)})
    else:
        for a, b in zip(a_rows, b_rows):
            if a.get("id") != b.get("id"):
                differences.append({"field": "id", "candidate": a.get("id"), "reference": b.get("id")})
                continue
            for key in sorted(set(a) | set(b)):
                fields += 1
                left = json.dumps(normalize(a.get(key), library(candidate)), sort_keys=True)
                right = json.dumps(normalize(b.get(key), library(reference)), sort_keys=True)
                if left != right:
                    differences.append({"id": a["id"], "field": key})
    result = {
        "schema": "quds.spacy.grammar.replay-row-comparison.v1",
        "candidate_report_sha256": candidate_sha,
        "candidate_library_sha256": library(candidate),
        "candidate_host": candidate.get("host"),
        "reference_report_sha256": reference_sha,
        "reference_library_sha256": library(reference),
        "reference_host": reference.get("host"),
        "rows": len(a_rows),
        "fields_compared": fields,
        "differences": differences,
        "identical": not differences,
    }
    text = json.dumps(result, indent=2) + "\n"
    if args.report:
        args.report.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if result["identical"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

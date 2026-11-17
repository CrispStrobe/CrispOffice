#!/usr/bin/env python3
"""Compare independent oracle captures byte-for-byte, failing on absent data."""

import argparse
import hashlib
import json
from pathlib import Path
import sys

from export_reference import json_bytes
from verify_reference import verify


def compare(first: Path, second: Path, cases: Path) -> dict:
    first_receipt = verify(first, cases)
    second_receipt = verify(second, cases)
    left = {str(p.relative_to(first)): p for p in first.rglob("*") if p.is_file()}
    right = {str(p.relative_to(second)): p for p in second.rglob("*") if p.is_file()}
    if set(left) != set(right):
        raise ValueError("Independent exports have different file inventories")
    differing = [name for name in sorted(left) if left[name].read_bytes() != right[name].read_bytes()]
    return {
        "schema": "crispembed.spacy.reference-repeatability.v1",
        "status": "pass" if not differing else "fail",
        "scope": "Independent Python oracle exports; no native inference qualification",
        "first_manifest_sha256": first_receipt["manifest_sha256"],
        "second_manifest_sha256": second_receipt["manifest_sha256"],
        "files_compared": len(left),
        "payload_bytes_compared": sum(p.stat().st_size for p in left.values()),
        "differing_files": differing,
        "cases": first_receipt["cases"], "tokens": first_receipt["tokens"],
        "trace_stages": first_receipt["trace_stages"], "parser_steps": first_receipt["parser_steps"],
        "comparator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--first", required=True, type=Path)
    parser.add_argument("--second", required=True, type=Path)
    parser.add_argument("--cases", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args(argv)
    try:
        result = compare(args.first, args.second, args.cases)
        if args.report:
            if args.report.exists():
                raise ValueError("Report already exists; receipts are not overwritten")
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_bytes(json_bytes(result))
    except (ValueError, OSError, KeyError, TypeError, IndexError) as error:
        print(f"Reference comparison FAILED: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())

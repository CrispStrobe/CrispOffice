#!/usr/bin/env python3
"""Recheck the bounded incoming capture without network or repository writes."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[3]
    checker = root / (
        "docs/validation/office-main-integration-20261119/review/"
        "audit_capture_ancestry.py"
    )
    expected = "4b7566a4fe6182dea7544bea442449c32e1eb169b1b4aed4b0c8d874363a79ab"
    actual = hashlib.sha256(checker.read_bytes()).hexdigest()
    if actual != expected:
        raise ValueError("The pinned ancestry checker has changed")
    subprocess.run(
        [
            sys.executable,
            str(checker),
            "--repo", str(root),
            "--head", args.head,
            "--refs", str(here / "origin-refs.txt"),
            "--upstream-refs", str(here / "upstream-refs.txt"),
            "--output", str(args.output.resolve()),
        ],
        check=True,
    )
    report = json.loads(args.output.read_text())
    return 0 if report.get("passed") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())

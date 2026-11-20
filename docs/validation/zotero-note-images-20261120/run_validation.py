#!/usr/bin/env python3
"""Use the unchanged strict Zotero runner with this increment's selections.

Source the verified Flutter/PUB_CACHE environment, then pass a cohort name,
--repo, a fresh --output directory and --expected-head. --list is read-only.
The adapter preserves every source, runtime, coverage and event-audit guard.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
RUNNER = HERE.parent / "zotero-research-materials-20261120/run_validation.py"
EXPECTED_RUNNER_SHA256 = "4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf"

if hashlib.sha256(RUNNER.read_bytes()).hexdigest() != EXPECTED_RUNNER_SHA256:
    raise RuntimeError("The historical strict runner changed; review it before qualification.")
spec = importlib.util.spec_from_file_location("zotero_strict_runner", RUNNER)
runner = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(runner)
runner.COHORTS = json.loads((HERE / "selection.json").read_text())["cohorts"]

if __name__ == "__main__":
    sys.exit(runner.main())

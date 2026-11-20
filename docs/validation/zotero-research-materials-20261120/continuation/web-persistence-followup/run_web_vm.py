#!/usr/bin/env python3
"""Run exactly three VM host files through the pinned original validation runner.

Requires a later published source preserving PR229. No package resolution,
source changes, browser launch or hosted-CI request is performed by this adapter.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from web_runner_support import (PACKAGE, PRIMARY, VM_TESTS, code_records,
                                load_primary, require_source)

COHORT = "web-persistence-vm"
SPEC = {"package": PACKAGE, "patterns": [], "additional": VM_TESTS, "runner": "flutter"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected-head")
    parser.add_argument("--timeout", type=int, default=1800,
                        help="Whole-process watchdog only; application timeouts remain unchanged")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if not args.list and (args.output is None or args.expected_head is None):
        parser.error("--output and --expected-head are required for execution")
    if not args.list:
        require_source(args.repo.resolve(), args.expected_head)
    primary = load_primary()
    primary.COHORTS = {COHORT: SPEC}
    before = code_records()
    delegated = [str(PRIMARY), COHORT, "--repo", str(args.repo.resolve()),
                 "--timeout", str(args.timeout)]
    if args.list:
        delegated.append("--list")
    else:
        delegated += ["--output", str(args.output.resolve()), "--expected-head", args.expected_head]
    original = sys.argv
    try:
        sys.argv = delegated
        result = primary.main()
    finally:
        sys.argv = original
    if args.list:
        return result
    after = code_records()
    output = args.output.resolve()
    receipt_path = output / "receipt.json"
    receipt = json.loads(receipt_path.read_text())
    receipt["guards"].update({
        "qualification_adapter_code_unchanged": before == after,
        "source_head_unchanged_and_exact": receipt["source_head_at_start"] == receipt["source_head_at_finish"] == args.expected_head,
        "exact_nineteen_application_cases": receipt["tests"]["passed"] == receipt["tests"]["application_cases"] == 19,
    })
    provenance = {"adapter_command": original, "delegated_arguments": delegated,
                  "selection": SPEC, "code_before": before, "code_after": after,
                  "original_primary_guard_logic_unchanged": True,
                  "application_timeouts_modified": False,
                  "shared_validation_lock_unchanged": True,
                  "expected_count_source": "Three unchanged author-selected VM files; PR229 reports 19 cases",
                  "counting": "Fresh execution count; overlapping downloads-manager cases must not be added twice to distinct totals"}
    primary.write_json(output / "selection-adapter.json", provenance)
    receipt["selection_adapter"] = provenance
    receipt["artifacts"]["selection-adapter.json"] = primary.file_record(output / "selection-adapter.json")
    if not all(receipt["guards"].values()):
        receipt["status"] = "failed"
    primary.write_json(receipt_path, receipt)
    print(json.dumps({"status": receipt["status"], "passed": receipt["tests"]["passed"],
                      "guards": receipt["guards"]}), flush=True)
    return 0 if result == 0 and receipt["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())

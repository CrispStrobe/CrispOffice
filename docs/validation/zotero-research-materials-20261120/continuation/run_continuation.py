#!/usr/bin/env python3
"""Add explicit continuation selections to the unchanged qualification runner.

The pinned runner retains its shared SDK lock, real Dart/Flutter execution,
strict event accounting, source/dependency/runtime input guards and timeouts.
The adapter changes only the cohort catalog and records both code identities.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys


PRIMARY_RUNNER_SHA256 = "4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf"
CONTINUATION_COHORTS = {
    "engine-proofing": {
        "package": "packages/quds_office_engine",
        "patterns": ["proofing/**/*_test.dart"],
        "additional": [],
        "runner": "dart",
    },
    "spacy": {
        "package": "packages/quds_proofing_spacy",
        "patterns": ["**/*_test.dart"],
        "additional": [],
        "runner": "dart",
    },
    "studio-integration": {
        "package": "packages/quds_office_editor/example",
        "patterns": [],
        "additional": [
            "studio_spacy_pin_test.dart",
            "studio_spacy_setup_test.dart",
            "studio_downloads_manager_test.dart",
            "studio_linguistic_analysis_test.dart",
            "studio_settings_test.dart",
            "studio_language_id_test.dart",
            "studio_comment_draft_proofing_test.dart",
            "studio_zotero_shortcuts_test.dart",
            "studio_zotero_citing_transport_test.dart",
        ],
        "runner": "flutter",
    },
}


def record(path: Path) -> dict:
    data = path.read_bytes()
    return {"path": str(path.resolve()), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cohort", choices=CONTINUATION_COHORTS)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected-head")
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if not args.list and (args.output is None or not args.expected_head):
        parser.error("--output and --expected-head are required for qualification")
    adapter = Path(__file__).resolve()
    runner = adapter.parent.parent / "run_validation.py"
    before = {"adapter": record(adapter), "primary_runner": record(runner)}
    if before["primary_runner"]["sha256"] != PRIMARY_RUNNER_SHA256:
        raise RuntimeError("The primary runner differs from the pinned qualification version")
    module_spec = importlib.util.spec_from_file_location("qualified_primary_runner", runner)
    if module_spec is None or module_spec.loader is None:
        raise RuntimeError("Cannot import the pinned primary runner")
    primary = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(primary)
    primary.COHORTS.update(CONTINUATION_COHORTS)
    delegated = [str(runner), args.cohort, "--repo", str(args.repo.resolve()), "--timeout", str(args.timeout)]
    if args.output is not None:
        delegated.extend(["--output", str(args.output.resolve())])
    if args.expected_head:
        delegated.extend(["--expected-head", args.expected_head])
    if args.list:
        delegated.append("--list")
    original_argv = sys.argv
    try:
        sys.argv = delegated
        result = primary.main()
    finally:
        sys.argv = original_argv
    if args.list:
        return result
    after = {"adapter": record(adapter), "primary_runner": record(runner)}
    unchanged = before == after
    provenance = {
        "purpose": "Qualify the reviewed spaCy, proofing and Studio publication delta",
        "cohort": args.cohort,
        "selection": CONTINUATION_COHORTS[args.cohort],
        "additive_catalog": CONTINUATION_COHORTS,
        "adapter_command": original_argv,
        "delegated_arguments": delegated,
        "code_before": before,
        "code_after": after,
        "code_unchanged": unchanged,
        "primary_runner_exit_code": result,
        "primary_test_audit_and_fingerprint_logic_unchanged": True,
        "shared_sdk_validation_lock_unchanged": True,
    }
    output = args.output.resolve()
    provenance_path = output / "selection-adapter.json"
    primary.write_json(provenance_path, provenance)
    receipt_path = output / "receipt.json"
    receipt = json.loads(receipt_path.read_text())
    receipt["selection_adapter"] = provenance
    receipt["guards"]["selection_adapter_and_primary_runner_unchanged"] = unchanged
    receipt["artifacts"][provenance_path.name] = primary.file_record(provenance_path)
    if not unchanged:
        receipt["status"] = "failed"
    primary.write_json(receipt_path, receipt)
    print(json.dumps({"continuation": args.cohort, "adapter_unchanged": unchanged, "status": receipt["status"]}), flush=True)
    return result if unchanged else 1


if __name__ == "__main__":
    sys.exit(main())

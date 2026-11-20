#!/usr/bin/env python3
"""Retain the complete nine-path PR229 delta and a bounded readiness review."""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[5]
OUT = Path(__file__).resolve().parent
BASE = "64f977ab003031d560c6564cf8895b1250d120d9"
MAIN = "dbfbbd28caa064f4850dc81860a68de14d48fb35"
AUTHOR = "fa46be92a1abb78914fb7dd7fb574bd7f50ade18"
FROZEN = "214c4ed80bef0cb871f74e90c506d508679d3d6e"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def oid(ref, path):
    result = subprocess.run(["git", "rev-parse", f"{ref}:{path}"], cwd=ROOT,
                            capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def main():
    paths = git("diff", "--name-only", BASE, MAIN).decode().splitlines()
    assert len(paths) == 9
    patch = git("diff", "--binary", BASE, MAIN)
    patch_path = OUT / "web-persistence.patch"
    patch_path.write_bytes(patch)
    numstat = [line.split("\t", 2) for line in git("diff", "--numstat", BASE, MAIN).decode().splitlines()]
    check = subprocess.run(["git", "diff", "--check", BASE, MAIN], cwd=ROOT, capture_output=True, text=True)
    rows = []
    for path in paths:
        old = oid(BASE, path)
        source = oid(MAIN, path)
        authored = oid(AUTHOR, path)
        frozen = oid(FROZEN, path)
        rows.append({"path": path, "base_blob": old, "main_blob": source,
                     "author_blob": authored, "frozen_source_blob": frozen,
                     "main_exact_author_blob": source == authored,
                     "frozen_exact_pre_merge_blob": frozen == old})
    assert all(r["main_exact_author_blob"] and r["frozen_exact_pre_merge_blob"] for r in rows)
    assert check.returncode == 0
    metadata = OUT / "pr229-metadata.json"
    report = {
        "schema": 1, "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "purpose": "Read-only assessment of later main after the frozen host/Word test source",
        "base_main": BASE, "later_main": MAIN, "author_source": AUTHOR,
        "frozen_qualification_source": FROZEN,
        "complete_delta": {"path": patch_path.name, "sha256": hashlib.sha256(patch).hexdigest(),
                           "changed_paths": len(paths), "changed_dart_paths": sum(p.endswith(".dart") for p in paths),
                           "insertions": sum(int(x[0]) for x in numstat), "deletions": sum(int(x[1]) for x in numstat),
                           "paths": rows, "git_diff_check_exit_code": check.returncode},
        "author_metadata": {"path": metadata.name, "sha256": hashlib.sha256(metadata.read_bytes()).hexdigest(),
                            "reported_browser_cases": 3, "reported_vm_cases": 19,
                            "fresh_case_total_added_by_this_review": 0,
                            "independent_event_receipt_audit_here": False},
        "behavior_review": [
            "Three new store files select real browser Cache Storage with dart.library.js_interop and a no-op store on the VM.",
            "Keys include data family, bundle id, pinned revision and filename; Cache Storage uses an encoded same-origin request path.",
            "Both hosts re-run their unchanged verified-byte constructors before activating restored bytes, and delete corrupt or incomplete stored data.",
            "Installation verifies downloaded bytes before writing; storage refusal clears partial writes and leaves an explicit session-only result.",
            "Removal invokes per-file cache deletion and clears host state; browser storage failures are handled without claiming durable persistence.",
            "The example manifest gains a direct web ^1.1.2 dependency; the imported package was already locked, but the new direct dependency still needs resolver/configuration proof.",
        ],
        "scope_limits": [
            "This source review is not fresh Chrome/VM execution or successful activation of real Wasm models.",
            "The new test uses synthetic pinned byte fixtures and actual browser Cache Storage; its morphology case checks installed status rather than loaded-model success.",
            "The three browser cases do not contain an explicit partial-file assertion, despite the PR body's broader incomplete-data coverage wording.",
            "No new native model, real user download, live account or connected service is exercised by this audit.",
        ],
        "minimum_validation_after_preservation": {
            "working_directory": "packages/quds_office_editor/example",
            "browser": ["test/studio_web_persistence_test.dart"],
            "browser_runner": "flutter test --no-pub --platform chrome --reporter json test/studio_web_persistence_test.dart",
            "vm": ["test/studio_hunspell_web_host_test.dart", "test/studio_hunspell_web_cancellation_test.dart", "test/studio_downloads_manager_test.dart"],
            "static": "Analyze the six changed Dart paths against the preserved source; use the browser-capable analyzer for JS interop. Check lock/resolved package graph changes explicitly.",
            "unaffected_receipts": "Preserve the existing core cohort receipts with source/input and conditional-import closure proofs; do not rerun unaffected Zotero, proofing, spaCy, or rendering cohorts solely for this nine-path addition.",
        },
        "disposition": "Preserve merged upstream main after frozen core validation, then run the narrow host/browser validation and dependency/static checks. Later publication audit binds the final source.",
        "github_actions_queried": False, "product_files_modified": False,
    }
    (OUT / "web-persistence-review.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"later_main": MAIN, "paths": len(paths), "dart_paths": 6,
                      "all_author_blobs_preserved": True, "fresh_tests_claimed_by_review": 0}))


if __name__ == "__main__":
    main()

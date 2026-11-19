#!/usr/bin/env python3
"""Read-only, source-pinned audit of the final concurrent-main carryforward.

This verifies Git entries and existing receipts. It runs no product tests,
network requests, GitHub Actions, or index/ref writes. INDEX is supported for
the resolved merge; pass an immutable published commit for final readback.
"""

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile


MAIN = "b655b8a37fddc874bd42a453c371eed6253e82d8"
OURS = "0e1e763b2366547f09b3d88197e31c39207db650"
ARABIC = "ba7c1e26cdc409915e04eba49dd1f1c002280cf8"
MAIL = "5569c055a021c893e941fc54d40499ad9d96a5db"
RELEASE = "docs/validation/office-main-completion-20261119/release/"
PUBLISHER = RELEASE + "publisher-main-controls/"
ARABIC_PATHS = (
    "packages/quds_office_engine/lib/src/proofing/arabic_writing_rules.dart",
    "packages/quds_office_engine/test/proofing/arabic_writing_rules_test.dart",
)
PUBLISHER_TEST = "tools/proofing/ayaspell/test_build_bundle_incoming.py"
HELPER = "tools/proofing/ayaspell/build_bundle.py"
EXPECTED_DELTA = {*ARABIC_PATHS, PUBLISHER_TEST}
RESOLVED_DOCS = {
    "docs/PROOFING.md",
    "docs/roadmaps/arabic-proofing.md",
    "docs/validation/office-main-completion-20261119/README.md",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--target", default="INDEX")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    failures = []

    def require(condition, message):
        if not condition:
            failures.append(message)

    def git(*command):
        return subprocess.check_output(
            ["git", "--no-replace-objects", "-C", str(repo), *command]
        )

    def ancestor(older, newer):
        return subprocess.run(
            ["git", "--no-replace-objects", "-C", str(repo),
             "merge-base", "--is-ancestor", older, newer],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            check=False,
        ).returncode == 0

    def entries(ref):
        result = {}
        if ref == "INDEX":
            rows = git("ls-files", "--stage", "-z")
            for row in rows.split(b"\0"):
                if not row:
                    continue
                metadata, name = row.split(b"\t", 1)
                mode, oid, stage = metadata.decode().split()
                if stage != "0":
                    raise ValueError("Unresolved index entry: " + name.decode())
                result[name.decode()] = {"mode": mode, "oid": oid}
        else:
            for row in git("ls-tree", "-r", "-z", ref).split(b"\0"):
                if not row:
                    continue
                metadata, name = row.split(b"\t", 1)
                mode, kind, oid = metadata.decode().split()
                result[name.decode()] = {"mode": mode, "oid": oid}
        return result

    def fingerprint(mapping):
        return sha(json.dumps(mapping, sort_keys=True, separators=(",", ":")).encode())

    def document(path):
        return path.startswith("docs/") or path == "README.md"

    main_entries, ours_entries, arabic_entries = (
        entries(ref) for ref in (MAIN, OURS, ARABIC)
    )
    target = args.target
    if target != "INDEX":
        target = git("rev-parse", target + "^{commit}").decode().strip()
    selected = entries(target)
    selected_fingerprint = fingerprint(selected)
    if target == "INDEX":
        parents = [git("rev-parse", "HEAD").decode().strip()]
        parents.extend(git("rev-parse", "MERGE_HEAD").decode().split())
        require(any(ancestor(MAIN, p) for p in parents), "Incoming main missing from merge parents")
        require(any(ancestor(OURS, p) for p in parents), "Our publication missing from merge parents")
        target_tree = None
    else:
        parents = git("show", "-s", "--format=%P", target).decode().split()
        require(ancestor(MAIN, target), "Incoming main is not an ancestor")
        require(ancestor(OURS, target), "Our publication is not an ancestor")
        target_tree = git("rev-parse", target + "^{tree}").decode().strip()

    def contents(path):
        return git("cat-file", "blob", selected[path]["oid"])

    def js(path):
        return json.loads(contents(path))

    def changes(left, right):
        return sorted(p for p in set(left) | set(right) if left.get(p) != right.get(p))

    delta = changes(main_entries, selected)
    code_delta = [p for p in delta if not document(p)]
    require(set(code_delta) == EXPECTED_DELTA, "Unexpected non-documentation delta from main")
    require(selected.get(HELPER) == main_entries.get(HELPER), "Publisher helper differs from main")
    require(main_entries[HELPER]["oid"] == "9257d987fc3a4307a33bc82465fcd03f777f7e28", "Unexpected main helper blob")
    for path in ARABIC_PATHS:
        require(selected.get(path) == arabic_entries.get(path), "Arabic repair differs from accepted source: " + path)

    old_test = git("cat-file", "blob", main_entries[PUBLISHER_TEST]["oid"])
    old_assertion = (
        b'        self.assertIn("Hunspell adapter and in-app download integration are planned",\n'
        b'                      " ".join(card.split()))\n'
    )
    new_assertion = b'        self.assertIn("in-app download are not implemented yet", card)\n'
    require(old_test.count(old_assertion) == 1, "Expected stale assertion not unique")
    require(contents(PUBLISHER_TEST) == old_test.replace(old_assertion, new_assertion, 1), "Publisher test change exceeds reviewed wording replacement")

    preserved_main_docs = [p for p in main_entries if document(p) and p not in RESOLVED_DOCS]
    require(all(selected.get(p) == main_entries[p] for p in preserved_main_docs), "An unrelated incoming documentation/evidence entry changed")
    preserved_own_evidence = [p for p in ours_entries if p.startswith(RELEASE)]
    require(all(selected.get(p) == ours_entries[p] for p in preserved_own_evidence), "An existing historical release artifact changed or disappeared")

    scopes = {
        "mail_core_store_transport_ui_and_protocol": lambda p: p.startswith("packages/quds_mail_") or p.startswith("third_party/enough_mail/"),
        "hunspell": lambda p: p.startswith("packages/quds_proofing_hunspell/"),
        "macos_runner_and_example_analysis": lambda p: p.startswith("packages/quds_office_editor/example/macos/") or p == "packages/quds_office_editor/example/analysis_options.yaml",
        "root_workspace_and_runtime_configs": lambda p: "/" not in p and p != "README.md",
    }
    scope_results = {}
    for label, predicate in scopes.items():
        paths = sorted(p for p in set(main_entries) | set(selected) if predicate(p))
        differences = [p for p in paths if main_entries.get(p) != selected.get(p)]
        require(not differences, "Incoming scope changed: " + label)
        scope_results[label] = {"entries": len(paths), "exact_main_entries": len(paths) - len(differences), "differences": differences}

    publisher_index = js(PUBLISHER + "index.json")
    receipt = js(PUBLISHER + "final-run/receipt.json")
    for path, metadata in publisher_index["files"].items():
        data = contents(PUBLISHER + path)
        require(len(data) == metadata["bytes"] and sha(data) == metadata["sha256"], "Publisher evidence byte/hash mismatch: " + path)
    actual_source = {p: sha(contents(p)) for p in publisher_index["final_source_sha256"]}
    require(actual_source == publisher_index["final_source_sha256"] == receipt["source_before"] == receipt["source_after"], "Publisher receipt source differs from resolved target")
    log = contents(PUBLISHER + "final-run/unittest.log")
    passed_lines = re.findall(rb"^test_[^\n]+ \.\.\. ok$", log, re.MULTILINE)
    require(len(passed_lines) == len(set(passed_lines)) == 17, "Publisher raw success count/uniqueness mismatch")
    require(re.search(rb"\nRan 17 tests in [0-9.]+s\n\nOK\n\Z", log) is not None, "Publisher raw log has no successful terminal result")
    require(receipt["tests_run"] == 17 and receipt["passed"] is True and receipt["source_unchanged"] is True, "Publisher accepted receipt not passing")
    require(all(receipt[k] == 0 for k in ("failed", "errors", "skipped", "network_attempts")), "Publisher receipt records failures/skips/network")
    require(sha(log) == receipt["raw_log_sha256"], "Publisher raw log differs from receipt")
    require(sha(contents(PUBLISHER + "run_offline_publisher_tests.py")) == receipt["script_sha256"], "Publisher driver differs from receipt")

    uid_path = "docs/validation/mail-uid-pagination-20261119/README.md"
    require(b"Final product gates have not run yet" in b" ".join(contents(uid_path).split()), "UID unrun qualification boundary missing")
    socket_path = "docs/validation/office-main-integration-20261119/socket-final/verification.json"
    socket_receipt = js(socket_path)
    require(socket_receipt["source_commit"] == "ac1e4c8c788ea608402c2260488235c0189efcba", "Unexpected Socket evidence source")
    native_archive = "docs/validation/office-current-reconciliation-20261119/native/native-qualification.tar.xz"
    with tarfile.open(fileobj=io.BytesIO(contents(native_archive)), mode="r:xz") as archive:
        native_receipt = json.load(archive.extractfile("native/verification.json"))
    require(native_receipt["source_commit"] == "c268ce3bceb05f92b7868e90ba8ce7b9a5bbbe1e", "Unexpected retained native checkpoint source")
    require(native_receipt["success"] is True and native_receipt["passed"] == 602, "Retained native checkpoint metadata mismatch")
    require(selected_fingerprint == fingerprint(entries(target)), "Resolved target entries changed during audit")

    code_report = [
        {"path": p, "main": main_entries.get(p), "resolved": selected.get(p),
         "review": "Exact accepted Arabic repair at " + ARABIC if p in ARABIC_PATHS else "Single generated-card wording assertion; 17 offline publisher controls independently recounted"}
        for p in code_delta
    ]
    report = {
        "schema": "quds.final_main_carryforward_review.v1",
        "status": "PASS" if not failures else "FAIL",
        "failures": failures,
        "auditor_sha256": sha(Path(__file__).read_bytes()),
        "target": target, "target_tree": target_tree,
        "target_entry_sha256": selected_fingerprint,
        "target_entries": len(selected), "parents": parents,
        "pins": {"incoming_main": MAIN, "our_previous_publication": OURS, "accepted_arabic_source": ARABIC, "accepted_mail_source": MAIL},
        "ancestry": "Both incoming main and our publication are present in resolved merge history/parents",
        "non_documentation_delta": code_report,
        "all_other_non_documentation_entries_exact_to_main": len([p for p in set(main_entries) | set(selected) if not document(p) and p not in EXPECTED_DELTA]),
        "incoming_scopes": scope_results,
        "incoming_documentation_and_evidence_entries_preserved": len(preserved_main_docs),
        "reviewed_documentation_resolutions": sorted(RESOLVED_DOCS),
        "our_prior_release_artifacts_preserved_exactly": len(preserved_own_evidence),
        "all_delta_paths_vs_main": delta,
        "publisher_controls": {
            "accepted_cases": 17, "suite_files": 3, "raw_unique_successes": len(passed_lines),
            "failed": 0, "errors": 0, "skipped": 0, "network_attempts": 0,
            "source_binding": "Exact resolved helper/three-test SHA-256 values; executed on resolved working-tree bytes, not relabelled as a frozen commit run",
            "source_sha256": actual_source, "evidence_index_entries_verified": len(publisher_index["files"]),
            "excluded_first_attempt": "16 passed and one stale wording assertion failed; zero accepted cases",
            "historical_seven_fresh_directory_controls": "Earlier implementation only; superseded by exact incoming main whitelist helper",
        },
        "retained_validation_boundaries": {
            "our_mail": {"source": MAIL, "application_executions": 836, "python_controls": 78, "current_aggregate_qualification": False},
            "our_arabic": {"source": ARABIC, "application_cases": 179, "test_files": 9, "current_aggregate_qualification": False, "repair_files_preserved_exactly": list(ARABIC_PATHS)},
            "incoming_socket": {"source": socket_receipt["source_commit"], "focused_cases": socket_receipt["passed"], "store_executions_from_retained_report": 199, "reported_total": 632, "current_aggregate_qualification": False, "receipt": socket_path},
            "incoming_native_checkpoint": {"source": native_receipt["source_commit"], "passed": native_receipt["passed"], "current_aggregate_qualification": False, "archive": native_archive},
            "incoming_uid_pagination": {"final_product_gates_run": False, "native_and_node_counts_are_plans": True, "record": uid_path},
            "incoming_hunspell_and_macos": "Preserved byte-for-byte from main; not tested or independently qualified by this carryforward audit",
            "historical_5033_and_5031_input_identity": "Historical source-specific audits only; no unchanged-input or runtime identity transfer to the late main aggregate",
            "no_combined_acceptance_total": "836/78, 179, 632, 602 and 17 belong to separately attributed scopes/sources and are not added together",
        },
        "product_tests_run_by_this_audit": False,
        "runtime_modified_or_claimed_current": False,
        "git_index_refs_or_worktree_source_modified": False,
        "github_actions_queried_or_awaited": False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": report["status"], "target": target, "non_documentation_delta": code_delta, "publisher_cases": 17, "failures": failures, "receipt": str(args.output)}, indent=2))
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()

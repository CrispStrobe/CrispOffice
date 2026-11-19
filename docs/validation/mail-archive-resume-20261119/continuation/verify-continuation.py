#!/usr/bin/env python3
"""Verify the published continuation and its focused local qualification.

Run from the checkout used for the focused gate, before publication and against
the fetched main merge. The historical full acceptance keeps its original
identity. This verifier permits only the four reviewed latest-main changes
and requires their fresh, source-bound qualification.
"""

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[4]
PREFIX = "docs/validation/mail-archive-resume-20261119/"
CONTINUATION = PREFIX + "continuation/"
BASELINE = "b2c05a0afa0ae606b061b13d5e50937c2a8eb1df"
SOURCE = "9b8853667b68c7bebff050e52445b47ea0bbd188"
SOURCE_TREE = "57d90e137f5b6c452a809080d4067f53c8209f09"
MAIN = "088d80905e3f76542dd9813e96584cd5c61454ff"
CHANGED = {
    "packages/quds_office_editor/example/lib/studio_downloads_manager.dart",
    "packages/quds_office_editor/example/lib/studio_spacy_host_native.dart",
    "packages/quds_office_editor/example/test/studio_downloads_manager_test.dart",
    "packages/quds_office_editor/example/test/studio_spacy_setup_test.dart",
}
TARGETS = CHANGED
TESTS = {path for path in CHANGED if "/test/" in path} | {
    "packages/quds_office_editor/example/test/studio_linguistic_analysis_test.dart"
}
INCOMING_DOCS = {
    "docs/validation/language-downloads-20261119/README.md",
    "docs/validation/language-downloads-20261119/bundled-runtime-acceptance.json",
    "docs/validation/language-downloads-20261119/bundled-runtime-native-gate.txt",
}
COMMANDS = ["format", "analysis", "whitespace", "studio-downloads-spacy"]


def require(value, message):
    if not value:
        raise RuntimeError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return digest(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", default="HEAD")
    parser.add_argument("--expected-tree")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    require(not args.output.exists(), "Retain prior verification; use a new output path")

    def git(*arguments):
        return subprocess.check_output(["git", *arguments], cwd=ROOT)

    candidate = git("rev-parse", args.candidate + "^{commit}").decode().strip()
    tree = git("rev-parse", candidate + "^{tree}").decode().strip()
    if args.expected_tree:
        require(tree == args.expected_tree, "Candidate tree differs from the expected tree")
    require(git("rev-parse", SOURCE + "^{tree}").decode().strip() == SOURCE_TREE,
            "Saved integration source tree differs")
    for ancestor in (BASELINE, SOURCE, MAIN):
        subprocess.run(["git", "merge-base", "--is-ancestor", ancestor, candidate],
                       cwd=ROOT, check=True)

    def raw(path):
        return git("show", candidate + ":" + path)

    def read(path):
        data = raw(path)
        return json.loads(gzip.decompress(data) if path.endswith(".gz") else data)

    require(digest(raw(CONTINUATION + "verify-continuation.py"))
            == digest(Path(__file__).read_bytes()), "Published verifier differs from executed code")

    changes = git("diff", "--name-only", BASELINE, candidate).decode().splitlines()
    require({path for path in changes if not path.startswith("docs/validation/")} == CHANGED,
            "Product/test delta differs from the four reviewed paths")
    allowed_existing_docs = {PREFIX + "README.md", PREFIX + "checkpoints.json"}
    require(all(path in CHANGED or path in allowed_existing_docs or path in INCOMING_DOCS
                or path.startswith(CONTINUATION) for path in changes),
            "Historical evidence or another unreviewed path changed")
    subsequent = git("diff", "--name-only", SOURCE, candidate).decode().splitlines()
    require(all(path in allowed_existing_docs or path.startswith(CONTINUATION)
                for path in subsequent), "Product changed after focused source freeze")

    entries = {}
    for item in git("ls-tree", "-rz", candidate).split(b"\0"):
        if item:
            metadata, path = item.split(b"\t", 1)
            entries[path.decode()] = tuple(metadata.decode().split())

    historical = read(CONTINUATION + "evidence-audit/published-acceptance-replay.json")
    require(historical["status"] == "passed" and not historical["failures"],
            "Historical evidence replay failed")
    require(historical["baseline_commit"] == BASELINE and not historical["tests_rerun"],
            "Historical replay scope differs")
    require(historical["auditor_sha256"] == digest(raw(
        CONTINUATION + "evidence-audit/replay_published_acceptance.py")),
        "Historical replay script differs from executed script")
    original = read(PREFIX + "acceptance.json")
    require(original["status"] == "passed" and original["test_totals"]
            == historical["test_execution_replay"], "Historical acceptance totals differ")

    review = read(CONTINUATION + "combined-resolution-source-review.json")
    require(review["status"] == "passed_source_review" and not review["findings"]
            and all(review["checks"].values()), "Merge resolution review failed")
    require(set(review["changed_paths"]) == CHANGED, "Review covers a different delta")
    require(digest(gzip.decompress(raw(CONTINUATION + "combined-resolution-source-review.diff.gz")))
            == review["patch_sha256"], "Reviewed patch bytes differ")
    for identity in review["files"].values():
        path = identity["path"]
        require(entries[path][1:] == ("blob", identity["git_blob_sha"])
                and digest(raw(path)) == identity["sha256"],
                "Candidate differs from reviewed source: " + path)
    for path in INCOMING_DOCS:
        require(entries[path][1:] == ("blob", git("rev-parse", MAIN + ":" + path).decode().strip()),
                "Incoming author validation document differs: " + path)

    focused_prefix = CONTINUATION + "focused/"
    focused_raw = raw(focused_prefix + "receipt.json")
    receipt = json.loads(focused_raw)
    require(receipt["status"] == "passed", "Focused qualification failed")
    require(receipt["source_head"] == SOURCE and receipt["source_tree"] == SOURCE_TREE,
            "Focused qualification names a different frozen source")
    for field in ("github_actions_used", "dependency_resolution_during_validation",
                  "prior_acceptance_counted_again"):
        require(receipt[field] is False, "Unexpected focused qualification claim: " + field)
    require(set(receipt["selected_test_files"]) == TESTS
            and set(receipt["analysis_and_format_targets"]) == TARGETS,
            "Focused selection differs from the reviewed scope")
    require(set(receipt["differences_from_original_accepted_source"]) == CHANGED,
            "Focused source inventory has an unexpected difference")
    require(digest(raw(focused_prefix + "executed-runner.py")) == receipt["runner_sha256"],
            "Focused runner differs from executed bytes")
    require(digest(raw("docs/validation/mail-archive-portability-20261119/run-local-validation.py"))
            == receipt["event_parser_sha256"], "Executed event parser differs")
    require([step["name"] for step in receipt["steps"]] == COMMANDS
            and receipt["required_commands_passed"] == len(COMMANDS),
            "Missing or unexpected focused commands")
    for step in receipt["steps"]:
        prefix = focused_prefix + step["name"] + "/"
        require(step["accepted"] is True and step["exit_code"] == 0
                and "interrupted_reason" not in step, "Focused command was not successful")
        require(read(prefix + "result.json") == step, "Command receipt differs")
        for stream in ("stdout", "stderr"):
            require(digest(raw(prefix + stream + ".log")) == step[stream + "_sha256"],
                    "Command log digest differs: " + prefix + stream)
    test_step = receipt["steps"][-1]
    cases_raw = raw(focused_prefix + "studio-downloads-spacy/test-cases.json")
    cases = json.loads(cases_raw)
    counts = {key: cases[key] for key in ("passed", "failed", "skipped")}
    require(digest(cases_raw) == test_step["test_cases_sha256"]
            and cases["accepted"] and counts == test_step["test_counts"]
            and counts == receipt["test_totals"] and counts["passed"] > 0
            and counts["failed"] == counts["skipped"] == 0,
            "Focused test results differ or include failures/skips")

    focused_audit_raw = raw(focused_prefix + "independent-audit.json")
    focused_audit = json.loads(focused_audit_raw)
    require(focused_audit["status"] == "passed" and not focused_audit["failures"],
            "Independent focused audit failed")
    require(focused_audit["source_head"] == SOURCE
            and focused_audit["source_tree"] == SOURCE_TREE
            and focused_audit["focused_receipt_sha256"] == digest(focused_raw)
            and focused_audit["runner_sha256"] == receipt["runner_sha256"]
            and focused_audit["event_parser_sha256"] == receipt["event_parser_sha256"]
            and focused_audit["test_counts"] == counts
            and focused_audit["distinct_test_files"] == len(TESTS)
            and focused_audit["required_commands_passed"] == len(COMMANDS),
            "Independent focused audit covers different inputs or results")
    require(focused_audit["auditor_sha256"] == digest(raw(
        focused_prefix + "audit_focused_validation.py")),
        "Published focused auditor differs from executed code")
    require(focused_audit["combined_source_review_sha256"] == digest(raw(
        CONTINUATION + "combined-resolution-source-review.json")),
        "Focused auditor covers a different source review")
    for field in ("tests_rerun_by_auditor", "github_actions_used",
                  "historical_2243_executions_included_in_these_counts",
                  "superseded_attempt_executions_included_in_these_counts"):
        require(focused_audit[field] is False, "Unexpected focused audit claim: " + field)

    runtime_snapshot = read(focused_prefix + "runtime-before.json.gz")
    flutter_configs = [Path(path) for path in runtime_snapshot
                       if path.endswith("/flutter/packages/flutter_tools/.dart_tool/package_config.json")]
    require(len(flutter_configs) == 1, "Expected one captured Flutter-tools configuration")
    configs = {"workspace": ROOT / ".dart_tool/package_config.json",
               "flutter-tools": flutter_configs[0]}
    package_roots = {}
    for origin, config_path in configs.items():
        config_bytes = config_path.read_bytes()
        config_identity = runtime_snapshot[str(config_path)]
        require(len(config_bytes) == config_identity["bytes"]
                and digest(config_bytes) == config_identity["sha256"],
                "Dependency configuration differs: " + origin)
        for package in json.loads(config_bytes)["packages"]:
            uri = urlparse(package["rootUri"])
            require(uri.scheme in ("", "file"), "Unexpected dependency URI scheme")
            directory = (Path(unquote(uri.path)) if uri.scheme == "file"
                         else config_path.parent / unquote(package["rootUri"])).resolve()
            package_roots[(origin, package["name"])] = directory

    inventories = {}
    for kind in ("source", "dependencies", "runtime"):
        before = read(focused_prefix + kind + "-before.json.gz")
        after = read(focused_prefix + kind + "-after.json.gz")
        bound = receipt["bound_inputs"][kind]
        require(before == after and bound["before_after_equal"]
                and not bound["changes"] and len(before) == bound["inputs"]
                and canonical(before) == bound["digest"], "Input inventory differs: " + kind)
        if kind == "source":
            prior = read(PREFIX + "final/source-before.json.gz")
            require({name for name in set(prior) | set(before)
                     if prior.get(name) != before.get(name)} == CHANGED,
                    "Recomputed source inventory delta differs")
        for name, identity in before.items():
            if kind == "source":
                path = ROOT / name
            elif kind == "dependencies":
                origin, package, relative = name.split("/", 2)
                path = package_roots[(origin, package)] / relative
                require(path.resolve().is_relative_to(ROOT.parent / "runtime"),
                        "Dependency path is outside the captured runtime")
            else:
                path = Path(name)
            data = path.read_bytes()
            require(len(data) == identity["bytes"] and digest(data) == identity["sha256"],
                    "Current input differs: " + name)
            if kind == "source":
                blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
                require(entries[name][1:] == ("blob", blob) and not path.is_symlink(),
                        "Candidate source Git blob differs: " + name)
                require(bool(path.stat().st_mode & 0o100) == (entries[name][0] == "100755"),
                        "Candidate source mode differs: " + name)
        inventories[kind] = {"inputs": len(before), "digest": bound["digest"],
                             "current_identity_failures": 0}
        audited = focused_audit["current_input_checks"][kind]
        require(audited["inputs"] == len(before) and audited["digest"] == bound["digest"]
                and audited["before_after_equal"]
                and audited["current_files_rehashed"] == len(before),
                "Focused auditor input binding differs: " + kind)

    reconciliation = read(CONTINUATION + "current-reference-reconciliation.json")
    require(reconciliation["checked_commit"] == SOURCE
            and reconciliation["counts"]["unaccounted"] == 0
            and all(reconciliation["checks"].values()), "Current reference reconciliation failed")
    require(reconciliation["replay_script_sha256"] == digest(raw(
        CONTINUATION + "reconcile-current-refs.py")), "Reference replay script differs")

    result = {
        "status": "passed",
        "verified_at_utc": datetime.now(timezone.utc).isoformat(),
        "candidate_commit": candidate,
        "candidate_tree": tree,
        "candidate_parents": git("show", "-s", "--format=%P", candidate).decode().split(),
        "required_ancestors": [BASELINE, SOURCE, MAIN],
        "source_freeze": SOURCE,
        "source_tree": SOURCE_TREE,
        "source_delta_from_original_acceptance": sorted(CHANGED),
        "historical_acceptance_preserved": True,
        "historical_test_executions": original["test_totals"],
        "fresh_focused_test_executions": counts,
        "focused_commands_passed": len(COMMANDS),
        "counts_kept_separate_due_to_overlap": True,
        "focused_receipt_sha256": digest(focused_raw),
        "focused_independent_audit_sha256": digest(focused_audit_raw),
        "historical_replay_sha256": digest(raw(CONTINUATION +
                                               "evidence-audit/published-acceptance-replay.json")),
        "reviewed_source_git_blobs_match": True,
        "changes_after_source_freeze_only_milestone_documentation": True,
        "input_reverification": inventories,
        "external_refs_accounted": reconciliation["external_reference_count"],
        "incoming_native_qualification_documents_match_main": True,
        "incoming_author_test_counts_added": False,
        "github_actions_used": False,
        "verifier_sha256": digest(Path(__file__).read_bytes()),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in (
        "status", "candidate_commit", "candidate_tree", "fresh_focused_test_executions",
        "focused_commands_passed", "external_refs_accounted")}))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Bind the later remote-main reconciliation without altering the earlier audit.

This reuses the frozen auditor for shared checks, then verifies the superseded
successful GUI cohort and the additional proofing selection. It runs no tests,
changes no Git state, and writes only the requested new JSON report.
"""

from __future__ import annotations

import argparse
from contextlib import redirect_stdout
from datetime import datetime, timezone
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile


PRIOR_BINDING_COMMIT = "d8be43a408473da4b45059561dbc387f5b868d5b"
BASE = Path("docs/validation/office-vba-arrays-20261119")
REQUIRED_ADDITIONAL_SUITES = {
    "editor-tests": {
        "test/word_text_proofing_pane_test.dart",
        "test/word_review_pane_test.dart",
        "test/word_text_proofing_controls_test.dart",
        "test/word_complex_script_proofing_controls_test.dart",
        "test/word_language_detection_test.dart",
    },
    "studio-theme-tests": {
        "test/studio_downloads_manager_test.dart",
        "test/studio_hunspell_setup_test.dart",
        "test/studio_spacy_setup_test.dart",
    },
    "spacy-installer-tests": {
        "test/ner_removal_test.dart",
        "test/distribution_test.dart",
        "test/bundle_test.dart",
    },
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--gui-evidence", type=Path,
                        help="Latest accepted GUI/proofing directory, relative to the repository or absolute.")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    base = repo / BASE
    output = args.output or base / "publication-binding-main.json"
    latest_gui = (args.gui_evidence if args.gui_evidence and args.gui_evidence.is_absolute()
                  else repo / args.gui_evidence if args.gui_evidence
                  else base / "incoming-main-accepted").resolve()
    if latest_gui.parent != base:
        raise SystemExit("GUI evidence must be a direct child of this validation directory.")
    if not (latest_gui / "receipt.json").is_file():
        raise SystemExit("The later main qualification is not complete; no new binding was written.")

    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("frozen_publication_binding", base / "publication-binding.py")
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    head = audit.git(repo, "rev-parse", args.head)
    starting_head = audit.git(repo, "rev-parse", "HEAD")
    blobs = audit.GitBlobs(repo)
    try:
        frozen_files = {}
        for name in ("publication-binding.py", "publication-binding.json", "publication-binding.md"):
            path = str(BASE / name)
            expected = blobs.file(PRIOR_BINDING_COMMIT, path)
            published = blobs.file(head, path)
            actual = audit.sha((repo / path).read_bytes())
            if actual != expected["sha256"] or published["sha256"] != actual:
                raise RuntimeError(f"The earlier binding was modified: {path}")
            frozen_files[path] = {**published, "frozen_commit": PRIOR_BINDING_COMMIT,
                                  "frozen_git_blob": expected["git_blob"], "unchanged": True}
        prior_binding = audit.load(base / "publication-binding.json")
        if prior_binding.get("success") is not True:
            raise RuntimeError("The frozen prior binding is not successful")

        latest_receipt = audit.require_acceptance(latest_gui)
        latest_commands = {command["name"]: command for command in latest_receipt["commands"]}
        for name, required_suites in REQUIRED_ADDITIONAL_SUITES.items():
            if name not in latest_commands:
                raise RuntimeError(f"Missing new proofing test command: {name}")
            missing = required_suites - set(latest_commands[name]["command"])
            if missing:
                raise RuntimeError(f"Missing new proofing suites in {name}: {sorted(missing)}")
        if "spacy-analysis" not in latest_commands:
            raise RuntimeError("Missing strict spaCy analysis command")

        # The frozen auditor checks every macro input and every accepted
        # artifact against the requested publication before reuse is allowed.
        # Its output remains temporary until the additional checks below pass.
        with tempfile.TemporaryDirectory(prefix="quds-main-binding-", dir=repo.parent) as temporary:
            temporary_output = Path(temporary) / "base-audit.json"
            previous_argv = sys.argv
            try:
                sys.argv = [str(base / "publication-binding.py"), "--repo", str(repo),
                            "--head", head, "--gui-evidence", str(latest_gui),
                            "--output", str(temporary_output)]
                with redirect_stdout(io.StringIO()):
                    audit.main()
            finally:
                sys.argv = previous_argv
            report = audit.load(temporary_output)

        macro_inputs, _ = audit.read_inputs(base / "engine-publication", macro=True)
        if len(macro_inputs) != 856:
            raise RuntimeError("The recorded macro input set is no longer the qualified 856 paths")
        for path, expected in macro_inputs.items():
            if report["accepted_inputs"][path]["sha256"] != expected:
                raise RuntimeError(f"A changed macro input cannot reuse acceptance: {path}")

        latest_inputs, _ = audit.read_inputs(latest_gui)
        prior_gui = base / "incoming-layout-theme-accepted"
        prior_receipt = audit.require_acceptance(prior_gui)
        prior_inputs, prior_stability = audit.read_inputs(prior_gui)
        prior_source = audit.load(prior_gui / "source-binding.json")
        gui_changes = {}
        for path, expected in prior_inputs.items():
            old_blob = blobs.file(prior_source["tested_source_head"], path)
            if old_blob["sha256"] != expected:
                raise RuntimeError(f"Earlier successful GUI input differs from its tested Git blob: {path}")
            if path not in latest_inputs:
                raise RuntimeError(f"The new GUI snapshot omits an earlier input: {path}")
            if latest_inputs[path] != expected:
                gui_changes[path] = {
                    "previous_sha256": expected,
                    "accepted_sha256": latest_inputs[path],
                    "accepted_git_blob": report["accepted_inputs"][path]["git_blob"],
                    "replacement_evidence": latest_gui.name,
                }

        prior_gui_tests = {}
        prior_test_commands = {}
        for command in prior_receipt["commands"]:
            if "test" not in command["command"]:
                continue
            package = "packages/" + command["cwd"].split("/packages/", 1)[1]
            parsed = audit.reporter_audit(prior_gui / command["stdout"], package)
            if not parsed["reporter_success"] or parsed["failed_distinct"] or parsed["error_events"]:
                raise RuntimeError(f"Earlier successful GUI reporter failed: {command['name']}")
            prior_gui_tests.update(parsed["tests"])
            prior_test_commands[command["name"]] = parsed["passed_distinct"]
        for key in prior_gui_tests:
            current = report["accepted_tests"].get(key)
            if current is None or current["result"] != "success" or current["skipped"]:
                raise RuntimeError(f"A prior successful GUI case was not requalified: {key}")

        prior_input_changes = {}
        for path, previous in prior_binding["accepted_inputs"].items():
            old_blob = blobs.file(prior_binding["publication_commit"], path)
            if old_blob["sha256"] != previous["sha256"]:
                raise RuntimeError(f"Prior binding input differs from its published Git blob: {path}")
            current = report["accepted_inputs"].get(path)
            if current is None:
                raise RuntimeError(f"The new binding omits a previously accepted source: {path}")
            if current["sha256"] != previous["sha256"]:
                if path not in gui_changes:
                    raise RuntimeError(f"Changed prior input is not requalified by the new GUI cohort: {path}")
                prior_input_changes[path] = gui_changes[path]
        for key in prior_binding["accepted_tests"]:
            current = report["accepted_tests"].get(key)
            if current is None or current["result"] != "success" or current["skipped"]:
                raise RuntimeError(f"A previously accepted test has no current passing evidence: {key}")

        report["components"]["incoming-layout-theme-accepted-historical"] = {
            "status": "Successful earlier GUI run retained and superseded by the later remote-main qualification; its tests are not counted again.",
            "tested_commit": prior_source["tested_source_head"],
            "input_stability": prior_stability,
            "artifacts": audit.artifact_audit(repo, prior_gui, "artifacts-sha256.json", blobs, head),
            "historical_source_git_blobs_verified": len(prior_inputs),
            "previous_test_commands": prior_test_commands,
            "passed_distinct": len(prior_gui_tests),
            "all_previous_gui_cases_pass_in_latest_cohort": True,
            "changed_inputs_requalified": gui_changes,
        }
        report["prior_binding"] = {
            "frozen_commit": PRIOR_BINDING_COMMIT,
            "audited_publication": prior_binding["publication_commit"],
            "files": frozen_files,
            "all_prior_binding_files_unchanged": True,
            "prior_source_git_blobs_verified": len(prior_binding["accepted_inputs"]),
            "prior_distinct_tests_retained_or_requalified": len(prior_binding["accepted_tests"]),
            "changed_prior_inputs_requalified": prior_input_changes,
            "new_repository_inputs": sorted(set(report["accepted_inputs"]) - set(prior_binding["accepted_inputs"])),
            "new_test_cases": sorted(set(report["accepted_tests"]) - set(prior_binding["accepted_tests"])),
        }
        report["macro_reuse"] = {
            "evidence": "engine-publication",
            "unchanged_recorded_repository_inputs": len(macro_inputs),
            "all_match_working_bytes_and_published_git_blobs": True,
            "distinct_cases_reused_without_rerunning": report["components"]["engine-publication"]["tests"]["passed_distinct"],
            "reason": "The complete qualified source/configuration input set remains byte-identical; the new main update changes no macro input.",
        }
        report["additional_proofing_selection"] = {
            name: sorted(paths) for name, paths in REQUIRED_ADDITIONAL_SUITES.items()
        }
        report["script_sha256"] = audit.sha(Path(__file__).read_bytes())
        report["underlying_auditor"] = {
            "path": str(BASE / "publication-binding.py"),
            "sha256": audit.sha((base / "publication-binding.py").read_bytes()),
            "frozen_commit": PRIOR_BINDING_COMMIT,
        }
        report["audited_utc"] = datetime.now(timezone.utc).isoformat()
        report["verified_artifact_manifests"] = len(report["components"])
        report["verified_artifact_files"] = sum(component["artifacts"]["verified_count"] for component in report["components"].values())
        report["artifact_files_matching_published_git_blobs"] = sum(component["artifacts"]["published_blob_count"] for component in report["components"].values())
        report["test_counting"] = "Unique repository test-file/name pairs across unchanged macro, focused DrawingML and mail acceptance plus the latest editor, Studio and spaCy/proofing reporters. Prior successful or failed GUI runs are not added again."
        report["scope"] = "The selected macro/command, focused DrawingML, native mail-store, editor, Studio and spaCy/proofing suites listed in this report. This is not a claim that all repository tests, native macOS UI or Microsoft Office interoperability were exercised."
        if audit.git(repo, "rev-parse", "HEAD") != starting_head:
            raise RuntimeError("HEAD changed during the later main binding; rerun against the new publication")
        output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        print(json.dumps({"success": True, "publication_commit": head,
                          "accepted_inputs": report["accepted_repository_input_count"],
                          "distinct_tests": report["accepted_distinct_tests"],
                          "verified_artifacts": report["verified_artifact_files"],
                          "prior_binding_unchanged": True, "report": str(output)}))
    finally:
        blobs.close()


if __name__ == "__main__":
    main()

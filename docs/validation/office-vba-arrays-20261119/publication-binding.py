#!/usr/bin/env python3
"""Independently bind the accepted local evidence to an exact Git publication.

This script only reads source, Git objects, and retained qualification evidence.
It writes the requested JSON report; it does not run tests, mutate Git, query
GitHub Actions, or change the original acceptance records.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
from urllib.parse import unquote, urlparse


BASE = Path("docs/validation/office-vba-arrays-20261119")
MAIL_DOCS = {
    "packages/quds_mail_store/CHANGELOG.md",
    "packages/quds_mail_store/README.md",
}
MAIL_BASE = "358544a48466c942873a4718a87fa9d1c2be11f7"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load(path: Path):
    return json.loads(path.read_text())


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


class GitBlobs:
    def __init__(self, repo: Path):
        self.repo = repo
        self.trees = {}
        self.blobs = {}
        self.process = subprocess.Popen(
            ["git", "-C", str(repo), "cat-file", "--batch"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        )

    def tree(self, revision: str) -> dict:
        if revision not in self.trees:
            records = {}
            raw = subprocess.check_output(["git", "-C", str(self.repo), "ls-tree", "-r", "-z", revision])
            for item in raw.split(b"\0"):
                if not item:
                    continue
                metadata, path = item.split(b"\t", 1)
                mode, kind, oid = metadata.decode().split()
                records[path.decode()] = {"mode": mode, "type": kind, "oid": oid}
            self.trees[revision] = records
        return self.trees[revision]

    def file(self, revision: str, path: str) -> dict:
        entry = self.tree(revision).get(path)
        if entry is None:
            raise RuntimeError(f"Missing published Git path: {revision}:{path}")
        if entry["type"] != "blob" or entry["mode"] == "120000":
            raise RuntimeError(f"Expected a direct file blob: {revision}:{path}")
        oid = entry["oid"]
        if oid not in self.blobs:
            self.process.stdin.write((oid + "\n").encode())
            self.process.stdin.flush()
            header = self.process.stdout.readline().decode().split()
            if len(header) != 3 or header[1] != "blob":
                raise RuntimeError(f"Unexpected Git object response: {header}")
            data = self.process.stdout.read(int(header[2]))
            if self.process.stdout.read(1) != b"\n":
                raise RuntimeError("Truncated Git object response")
            self.blobs[oid] = {"sha256": sha(data), "bytes": len(data)}
        return {"git_blob": oid, **self.blobs[oid]}

    def close(self) -> None:
        self.process.stdin.close()
        self.process.stdout.close()
        if self.process.wait() != 0:
            raise RuntimeError("git cat-file failed")


def artifact_audit(repo: Path, folder: Path, manifest_name: str, blobs: GitBlobs, head: str) -> dict:
    manifest = folder / manifest_name
    entries = load(manifest)
    manifest_relative = str(manifest.relative_to(repo))
    manifest_digest = sha(manifest.read_bytes())
    manifest_publication = {}
    if manifest_relative in blobs.tree(head):
        published_manifest = blobs.file(head, manifest_relative)
        if published_manifest["sha256"] != manifest_digest:
            raise RuntimeError(f"Artifact manifest differs from its published Git blob: {manifest_relative}")
        manifest_publication = {"git_blob": published_manifest["git_blob"], "published_blob_matches": True}
    else:
        manifest_publication = {"publication": "Not present at the audited commit; verified as a retained workspace artifact."}
    verified = {}
    for name, value in entries.items():
        path = folder / name
        if not path.resolve().is_relative_to(folder.resolve()):
            raise RuntimeError(f"Artifact escaped its evidence directory: {name}")
        data = path.read_bytes()
        expected = value["sha256"] if isinstance(value, dict) else value
        if sha(data) != expected:
            raise RuntimeError(f"Artifact hash mismatch: {path}")
        if isinstance(value, dict) and "bytes" in value and value["bytes"] != len(data):
            raise RuntimeError(f"Artifact size mismatch: {path}")
        relative = str(path.relative_to(repo))
        record = {"sha256": expected, "bytes": len(data)}
        if relative in blobs.tree(head):
            published = blobs.file(head, relative)
            record["git_blob"] = published["git_blob"]
            record["published_blob_matches"] = published["sha256"] == expected
            if not record["published_blob_matches"]:
                raise RuntimeError(f"Evidence differs from its published Git blob: {relative}")
        else:
            record["publication"] = "Not present at the audited commit; verified as a retained workspace artifact."
        verified[name] = record
    return {"manifest": manifest_relative, "manifest_sha256": manifest_digest,
            "manifest_publication": manifest_publication,
            "verified_count": len(entries), "all_hashes_match": True,
            "published_blob_count": sum("git_blob" in value for value in verified.values()),
            "files": verified}


def read_inputs(folder: Path, *, macro: bool = False) -> tuple[dict, dict]:
    before = load(folder / "inputs-before.json")
    after = load(folder / "inputs-after.json")
    if before != after:
        raise RuntimeError(f"Acceptance input snapshots changed: {folder}")
    if macro:
        sources = {path: record["sha256"] for path, record in before.items()}
    else:
        sources = {path.removeprefix("repository/"): value for path, value in before.items()
                   if path.startswith("repository/")}
    return sources, {"recorded_inputs": len(before), "repository_inputs": len(sources),
                     "before_after_identical": True,
                     "before_sha256": sha((folder / "inputs-before.json").read_bytes()),
                     "after_sha256": sha((folder / "inputs-after.json").read_bytes())}


def reporter_audit(path: Path, package: str) -> dict:
    suites, tests, completed = {}, {}, {}
    done, errors, non_json = [], [], []
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            non_json.append(line)
            continue
        kind = event.get("type")
        if kind == "suite":
            suites[event["suite"]["id"]] = event["suite"]["path"]
        elif kind == "testStart":
            tests[event["test"]["id"]] = event["test"]
        elif kind == "testDone":
            completed[event["testID"]] = event
        elif kind == "done":
            done.append(event)
        elif kind == "error":
            errors.append(event)
    visible = {}
    by_suite = Counter()
    for test_id, result in completed.items():
        test = tests[test_id]
        if result.get("hidden", False) or result.get("isHidden", False) or test.get("isHidden", False):
            continue
        suite = suites[test["suiteID"]]
        if suite.startswith("file:"):
            suite = unquote(urlparse(suite).path)
        source_root = next((name for name in ("packages", "apps", "third_party")
                            if f"/{name}/" in suite), None)
        if source_root:
            suite = source_root + "/" + suite.split(f"/{source_root}/", 1)[1]
        elif not suite.startswith(("packages/", "apps/", "third_party/")):
            suite = package + "/" + suite.removeprefix("./")
        key = suite + "::" + test["name"]
        if key in visible:
            raise RuntimeError(f"Duplicate visible suite/name pair: {key}")
        visible[key] = {"suite": suite, "name": test["name"], "result": result["result"],
                        "skipped": result.get("skipped", False)}
        by_suite[suite] += 1
    passed = sum(value["result"] == "success" and not value["skipped"] for value in visible.values())
    failed = sum(value["result"] != "success" for value in visible.values())
    skipped = sum(value["skipped"] for value in visible.values())
    return {"passed_distinct": passed, "failed_distinct": failed, "skipped_distinct": skipped,
            "reporter_success": len(done) == 1 and done[0].get("success") is True,
            "reporter_done": done, "error_events": len(errors), "non_json_lines": non_json,
            "suite_counts": dict(sorted(by_suite.items())), "tests": visible}


def require_acceptance(folder: Path) -> dict:
    receipt = load(folder / "receipt.json")
    if receipt.get("success") is not True:
        raise RuntimeError(f"No successful acceptance receipt: {folder}")
    for command in receipt.get("commands", []):
        if command["exit_code"] != 0:
            raise RuntimeError(f"Failed acceptance command: {folder}:{command['name']}")
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--gui-evidence", type=Path,
                        help="Accepted GUI evidence directory, relative to the repository or absolute.")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    base = repo / BASE
    output = args.output or base / "publication-binding.json"
    head = git(repo, "rev-parse", args.head)
    start_head = git(repo, "rev-parse", "HEAD")
    final_gui = (args.gui_evidence if args.gui_evidence and args.gui_evidence.is_absolute()
                 else repo / args.gui_evidence if args.gui_evidence
                 else base / "incoming-layout-theme-accepted").resolve()
    if final_gui.parent != base:
        raise SystemExit("GUI evidence must be a direct child of this validation directory.")
    gui_label = final_gui.name
    if not (final_gui / "receipt.json").is_file():
        raise SystemExit("Final GUI qualification is not complete; no combined acceptance report was written.")
    blobs = GitBlobs(repo)
    try:
        components = {}
        catalog = {}
        overlaps = []
        accepted_tests = {}

        def accept_inputs(label: str, sources: dict) -> None:
            for path, expected in sources.items():
                published = blobs.file(head, path)
                actual = sha((repo / path).read_bytes())
                if actual != expected or published["sha256"] != expected:
                    raise RuntimeError(f"Accepted input is not the published working source: {label}:{path}")
                if path in catalog:
                    if catalog[path]["sha256"] != expected:
                        raise RuntimeError(f"Conflicting latest accepted input: {path}")
                    overlaps.append({"path": path, "prior_evidence": list(catalog[path]["evidence"]),
                                     "additional_evidence": label, "sha256": expected})
                    catalog[path]["evidence"].append(label)
                else:
                    catalog[path] = {**published, "working_sha256": actual, "evidence": [label]}

        def accept_reporter(label: str, path: Path, package: str) -> dict:
            audit = reporter_audit(path, package)
            if not audit["reporter_success"] or audit["failed_distinct"] or audit["error_events"]:
                raise RuntimeError(f"Unsuccessful accepted reporter: {label}")
            duplicates = 0
            for key, value in audit["tests"].items():
                if key in accepted_tests:
                    if (accepted_tests[key]["result"], accepted_tests[key]["skipped"]) != (value["result"], value["skipped"]):
                        raise RuntimeError(f"Conflicting repeated test result: {key}")
                    duplicates += 1
                    accepted_tests[key]["evidence"].append(label)
                else:
                    accepted_tests[key] = {**value, "evidence": [label]}
            return {key: value for key, value in audit.items() if key != "tests"} | {
                "duplicate_tests_already_counted": duplicates, "raw_stdout_sha256": sha(path.read_bytes())}

        macro = base / "engine-publication"
        macro_label = macro.name
        macro_receipt = require_acceptance(macro)
        macro_inputs, macro_stability = read_inputs(macro, macro=True)
        accept_inputs(macro_label, macro_inputs)
        components[macro_label] = {
            "receipt_sha256": sha((macro / "receipt.json").read_bytes()),
            "tested_commit": macro_receipt["source_commit_before"], "input_stability": macro_stability,
            "artifacts": artifact_audit(repo, macro, "artifact-manifest.json", blobs, head),
            "tests": accept_reporter(macro_label, macro / "logs/macro-tests.stdout.log", "packages/quds_office_engine"),
            "checks": {name: value["success"] for name, value in macro_receipt["checks"].items()},
        }
        if not all(components[macro_label]["checks"].values()):
            raise RuntimeError("A macro acceptance check did not succeed")

        prior_macro = base / "engine-final"
        prior_macro_receipt = require_acceptance(prior_macro)
        prior_macro_inputs, prior_macro_stability = read_inputs(prior_macro, macro=True)
        macro_replacements = {}
        for path, expected in prior_macro_inputs.items():
            old_blob = blobs.file(prior_macro_receipt["source_commit_before"], path)
            if old_blob["sha256"] != expected:
                raise RuntimeError(f"Earlier macro input differs from its tested Git blob: {path}")
            if path not in macro_inputs:
                raise RuntimeError(f"Current macro qualification does not cover an earlier input: {path}")
            if macro_inputs[path] != expected:
                macro_replacements[path] = {"old_sha256": expected, "accepted_sha256": macro_inputs[path],
                                            "accepted_git_blob": catalog[path]["git_blob"],
                                            "replacement_evidence": macro_label}
        prior_macro_tests = reporter_audit(prior_macro / "logs/macro-tests.stdout.log", "packages/quds_office_engine")
        if not prior_macro_tests["reporter_success"] or prior_macro_tests["failed_distinct"] or prior_macro_tests["error_events"]:
            raise RuntimeError("Earlier macro reporter is not successful")
        for key in prior_macro_tests["tests"]:
            if key not in accepted_tests or accepted_tests[key]["result"] != "success" or accepted_tests[key]["skipped"]:
                raise RuntimeError(f"An earlier macro test was not successfully requalified: {key}")
        components["engine-final-historical"] = {
            "status": "Successful earlier macro run, superseded by qualification after the DrawingML correction; its tests are not counted again.",
            "tested_commit": prior_macro_receipt["source_commit_before"],
            "input_stability": prior_macro_stability,
            "artifacts": artifact_audit(repo, prior_macro, "artifact-manifest.json", blobs, head),
            "historical_source_git_blobs_verified": len(prior_macro_inputs),
            "passed_distinct": prior_macro_tests["passed_distinct"],
            "changed_inputs_requalified": macro_replacements,
        }

        drawingml = base / "independent-review/slide-table-color"
        drawingml_before = load(drawingml / "before-receipt.json")
        drawingml_after = load(drawingml / "after-receipt.json")
        if drawingml_after.get("success") is not True or any(command["exit_code"] != 0 for command in drawingml_after["commands"]):
            raise RuntimeError("Focused DrawingML correction checks did not succeed")
        drawingml_inputs = load(drawingml / "after-inputs-before.json")
        if drawingml_inputs != load(drawingml / "after-inputs-after.json"):
            raise RuntimeError("Focused DrawingML inputs changed during qualification")
        before_inputs = load(drawingml / "before-inputs-before.json")
        if before_inputs != load(drawingml / "before-inputs-after.json"):
            raise RuntimeError("DrawingML baseline inputs changed during reproduction")
        production = drawingml_before["production_path"]
        old_parser = blobs.file(drawingml_before["source_head"], production)
        if old_parser["sha256"] != before_inputs[production]:
            raise RuntimeError("The DrawingML failure was not reproduced against the recorded original parser")
        if {path for path in before_inputs if before_inputs[path] != drawingml_inputs[path]} != {production}:
            raise RuntimeError("The DrawingML before/after regression inputs differ beyond the parser correction")
        accept_inputs("slide-table-color", drawingml_inputs)
        drawingml_tests = accept_reporter("slide-table-color", drawingml / "after-tests.stdout.log", "packages/quds_office_engine")
        baseline_tests = reporter_audit(drawingml / "before-tests.stdout.log", "packages/quds_office_engine")
        baseline_failures = {key for key, value in baseline_tests["tests"].items() if value["result"] != "success"}
        if not baseline_failures or baseline_tests["reporter_success"]:
            raise RuntimeError("The original DrawingML failure was not captured")
        for key in baseline_failures:
            if key not in accepted_tests or accepted_tests[key]["result"] != "success" or accepted_tests[key]["skipped"]:
                raise RuntimeError(f"A DrawingML regression did not pass after correction: {key}")
        components["slide-table-color"] = {
            "artifacts": artifact_audit(repo, drawingml, "artifacts-sha256.json", blobs, head),
            "tests": drawingml_tests,
            "recorded_inputs": len(drawingml_inputs), "before_after_stable": True,
            "baseline_production_commit": drawingml_before["source_head"],
            "baseline_production_git_blob": old_parser["git_blob"],
            "baseline_production_sha256": old_parser["sha256"],
            "original_failed_tests": sorted(baseline_failures),
            "identical_regression_tests_pass_after_parser_only_change": True,
            "commands": [{"name": command["name"], "exit_code": command["exit_code"]}
                         for command in drawingml_after["commands"]],
        }

        mail = base / "incoming-mail"
        require_acceptance(mail)
        mail_inputs, mail_stability = read_inputs(mail)
        mail_binding = load(mail / "source-binding.json")
        mail_package_files = mail_binding["files"]
        for path, recorded in mail_package_files.items():
            expected = recorded["sha256"]
            if mail_inputs.get(path) != expected:
                raise RuntimeError(f"Mail source binding differs from its acceptance snapshot: {path}")
            for revision in (mail_binding["incoming_head"], MAIL_BASE):
                if blobs.file(revision, path)["sha256"] != expected:
                    raise RuntimeError(f"Mail source binding differs from its recorded Git frontier: {revision}:{path}")
        mail_diff = set(git(repo, "diff", "--name-only", MAIL_BASE, head, "--",
                            "packages/quds_mail_core", "packages/quds_mail_store").splitlines())
        if not mail_diff.issubset(MAIL_DOCS):
            raise RuntimeError(f"Unqualified mail implementation changes: {sorted(mail_diff - MAIL_DOCS)}")
        documentation_updates = {}
        for path in sorted(MAIL_DOCS & mail_inputs.keys()):
            published = blobs.file(head, path)
            if published["sha256"] != mail_inputs[path]:
                documentation_updates[path] = {
                    "tested_sha256": mail_inputs.pop(path), "published_sha256": published["sha256"],
                    "published_git_blob": published["git_blob"],
                    "classification": "Documentation-only change after the runtime acceptance; not represented as tested code.",
                    "review": "Restore API instructions, scope/qualification links, and Unreleased restoration notes; no mail implementation, test, tool, or dependency change.",
                }
        accept_inputs("incoming-mail", mail_inputs)
        accept_inputs("mail-documentation-review", {
            path: item["published_sha256"] for path, item in documentation_updates.items()
        })
        components["incoming-mail"] = {
            "receipt_sha256": sha((mail / "receipt.json").read_bytes()), "input_stability": mail_stability,
            "artifacts": artifact_audit(repo, mail, "artifacts-sha256.json", blobs, head),
            "tests": accept_reporter("incoming-mail", mail / "store-tests.stdout.log", "packages/quds_mail_store"),
            "recorded_package_files": len(mail_package_files),
            "recorded_source_git_blobs_verified": len(mail_package_files),
            "verified_mail_frontiers": [mail_binding["incoming_head"], MAIL_BASE],
            "unchanged_package_files": len(mail_package_files) - len(documentation_updates),
            "documentation_updates": documentation_updates,
            "all_tracked_mail_changes_since_accepted_frontier": sorted(mail_diff),
        }

        gui_receipt = require_acceptance(final_gui)
        expected_gui_commands = {"editor-tests", "repeated-studio-tests", "studio-theme-tests",
                                 "changed-analysis", "studio-analysis"}
        gui_commands = {command["name"]: command for command in gui_receipt["commands"]}
        if not expected_gui_commands.issubset(gui_commands):
            raise RuntimeError(f"Missing final GUI acceptance commands: {sorted(expected_gui_commands - gui_commands.keys())}")
        gui_inputs, gui_stability = read_inputs(final_gui)
        accept_inputs(gui_label, gui_inputs)
        gui_test_commands = {}
        for command in gui_receipt["commands"]:
            if "test" not in command["command"]:
                continue
            source_root = next((name for name in ("packages", "apps", "third_party")
                                if f"/{name}/" in command["cwd"]), None)
            if source_root is None:
                raise RuntimeError(f"Cannot map GUI test working directory: {command['cwd']}")
            package = source_root + "/" + command["cwd"].split(f"/{source_root}/", 1)[1]
            gui_test_commands[command["name"]] = accept_reporter(
                gui_label + "/" + command["name"],
                final_gui / command["stdout"], package,
            )
        if not gui_test_commands:
            raise RuntimeError("The final GUI acceptance contains no test commands")
        components[gui_label] = {
            "receipt_sha256": sha((final_gui / "receipt.json").read_bytes()),
            "input_stability": gui_stability,
            "artifacts": artifact_audit(repo, final_gui, "artifacts-sha256.json", blobs, head),
            "test_commands": gui_test_commands,
            "commands": [{"name": command["name"], "exit_code": command["exit_code"]}
                         for command in gui_receipt["commands"]],
        }

        historical = base / "incoming-studio"
        require_acceptance(historical)
        _, historical_stability = read_inputs(historical)
        original = load(historical / "source-binding.json")
        historical_inputs = {path: record["sha256"]
                             for group in ("frozen_engine_files", "live_repository_files")
                             for path, record in original[group].items()}
        replacements = {}
        for path, expected in historical_inputs.items():
            old_blob = blobs.file(original["tested_source_head"], path)
            if old_blob["sha256"] != expected:
                raise RuntimeError(f"Historical Studio hash differs from its tested Git blob: {path}")
            if path not in gui_inputs:
                raise RuntimeError(f"Current GUI evidence does not cover an old Studio input: {path}")
            if gui_inputs[path] != expected:
                replacements[path] = {"old_sha256": expected, "accepted_sha256": gui_inputs[path],
                                      "accepted_git_blob": catalog[path]["git_blob"],
                                      "replacement_evidence": catalog[path]["evidence"]}
        old_tests = reporter_audit(historical / "studio-tests.stdout.log", "packages/quds_office_editor/example")
        if not old_tests["reporter_success"] or old_tests["failed_distinct"] or old_tests["error_events"]:
            raise RuntimeError("Historical Studio reporter is not successful")
        if not set(old_tests["tests"]).issubset(accepted_tests):
            raise RuntimeError("Some historical Studio test names were not repeated in the accepted final run")
        if any(accepted_tests[key]["result"] != "success" or accepted_tests[key]["skipped"]
               for key in old_tests["tests"]):
            raise RuntimeError("A historical Studio case was not successfully requalified")
        components["incoming-studio-historical"] = {
            "status": "Successful earlier run, superseded by current GUI qualification; its tests are not added again.",
            "tested_commit": original["tested_source_head"], "input_stability": historical_stability,
            "artifacts": artifact_audit(repo, historical, "artifacts-sha256.json", blobs, head),
            "historical_source_git_blobs_verified": len(historical_inputs),
            "passed_distinct": old_tests["passed_distinct"], "repeated_tests_excluded_from_total": len(old_tests["tests"]),
            "changed_inputs_requalified": replacements,
        }

        for failed_gui in sorted(base.glob("incoming-layout-theme*")):
            if failed_gui == final_gui or not (failed_gui / "receipt.json").is_file():
                continue
            failed_receipt = load(failed_gui / "receipt.json")
            if failed_receipt.get("success") is not False:
                continue
            _, failed_stability = read_inputs(failed_gui)
            failed_reporter = reporter_audit(failed_gui / "editor-tests.stdout.log", "packages/quds_office_editor")
            previously_failed = {key: value for key, value in failed_reporter["tests"].items()
                                 if value["result"] != "success"}
            for key in previously_failed:
                if key not in accepted_tests or accepted_tests[key]["result"] != "success" or accepted_tests[key]["skipped"]:
                    raise RuntimeError(f"An initial GUI failure was not successfully requalified: {key}")
            failed_commands = [{"name": command["name"], "exit_code": command["exit_code"]}
                               for command in failed_receipt["commands"] if command["exit_code"] != 0]
            for command in failed_commands:
                if command["name"] not in gui_commands or gui_commands[command["name"]]["exit_code"] != 0:
                    raise RuntimeError(f"An earlier failed GUI command was not successfully requalified: {command['name']}")
            components[failed_gui.name + "-historical-failure"] = {
                "status": "Failed run retained; its tests are excluded from the accepted total and its failed cases pass in the final GUI cohort.",
                "receipt_sha256": sha((failed_gui / "receipt.json").read_bytes()),
                "input_stability": failed_stability,
                "artifacts": artifact_audit(repo, failed_gui, "artifacts-sha256.json", blobs, head),
                "original_passed": failed_reporter["passed_distinct"],
                "original_failed": failed_reporter["failed_distinct"],
                "original_failed_commands": failed_commands,
                "all_failed_commands_pass_in_accepted_cohort": True,
                "requalified_failure_keys": sorted(previously_failed),
            }

        if git(repo, "rev-parse", "HEAD") != start_head:
            raise RuntimeError("HEAD changed during binding; rerun against the new publication")
        passed = sum(value["result"] == "success" and not value["skipped"] for value in accepted_tests.values())
        artifact_count = sum(component["artifacts"]["verified_count"] for component in components.values())
        published_artifact_count = sum(component["artifacts"]["published_blob_count"] for component in components.values())
        report = {
            "success": True, "audited_utc": datetime.now(timezone.utc).isoformat(),
            "publication_commit": head, "publication_tree": git(repo, "rev-parse", f"{head}^{{tree}}"),
            "accepted_gui_evidence": str(final_gui.relative_to(repo)),
            "script_sha256": sha(Path(__file__).read_bytes()),
            "method": "Read actual blobs through git ls-tree and git cat-file --batch; compare SHA-256 with retained acceptance inputs and current working bytes.",
            "accepted_repository_input_count": len(catalog),
            "all_accepted_inputs_match_working_files_and_published_git_blobs": True,
            "verified_artifact_manifests": len(components),
            "verified_artifact_files": artifact_count,
            "artifact_files_matching_published_git_blobs": published_artifact_count,
            "accepted_distinct_tests": passed,
            "accepted_failed_distinct": sum(value["result"] != "success" for value in accepted_tests.values()),
            "accepted_skipped_distinct": sum(value["skipped"] for value in accepted_tests.values()),
            "test_counting": "Unique repository test-file/name pairs across the publication macro, focused DrawingML, mail store, editor, and repeated Studio runs; earlier development, previous macro, and old Studio runs are excluded.",
            "scope": "The macro/command, focused DrawingML, native mail-store, editor, and Studio suites listed in the reporter audits. This is not a claim that all repository tests, native macOS UI, or Microsoft Office interoperability were exercised.",
            "components": components,
            "consistent_latest_overlaps": overlaps,
            "accepted_inputs": dict(sorted(catalog.items())),
            "accepted_tests": dict(sorted(accepted_tests.items())),
            "github_actions": "Not queried or used for acceptance.",
        }
        output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        print(json.dumps({"success": True, "publication_commit": head,
                          "accepted_inputs": len(catalog), "distinct_tests": passed,
                          "report": str(output)}))
    finally:
        blobs.close()


if __name__ == "__main__":
    main()

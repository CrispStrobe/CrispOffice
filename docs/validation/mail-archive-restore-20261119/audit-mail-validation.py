#!/usr/bin/env python3
"""Independently audit accepted logs and their source/dependency/runtime inputs.

This auditor deliberately does not import the acceptance runner or its parser.
It performs no product mutation, test execution, dependency resolution or CI.
"""

import argparse
import collections
import gzip
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
from datetime import datetime, timezone
from urllib.parse import unquote, urljoin, urlparse


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def read_json(path):
    path = Path(path)
    return json.loads(gzip.decompress(path.read_bytes()) if path.suffix == ".gz" else path.read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--incoming", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo, run, incoming = args.repo.resolve(), args.run.resolve(), args.incoming.resolve()
    failures = []
    cache = {}

    def check(condition, description):
        if not condition:
            failures.append(description)

    def identity(path):
        path = Path(path)
        key = str(path)
        if key not in cache:
            size = path.stat().st_size
            sha256 = hashlib.sha256()
            blob = hashlib.sha1(b"blob " + str(size).encode() + b"\0")
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    sha256.update(chunk)
                    blob.update(chunk)
            cache[key] = {"bytes": size, "sha256": sha256.hexdigest(), "git_blob": blob.hexdigest()}
        return cache[key]

    def sha(path):
        return identity(path)["sha256"]

    def hash_matches(path, expected, description):
        if not Path(path).is_file():
            check(False, description + ": missing " + str(path))
            return False
        actual = identity(path)
        match = actual["sha256"] == expected["sha256"] and actual["bytes"] == expected["bytes"]
        check(match, description + ": identity mismatch " + str(path))
        return match

    def parse_raw_tests(path, cwd, expected):
        suites, starts, finishes = {}, {}, {}
        errors, terminal = [], []
        malformed = 0
        duplicates = []
        for line in Path(path).read_text(errors="replace").splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                malformed += bool(line.strip())
                continue
            if not isinstance(event, dict):
                malformed += 1
                continue
            kind = event.get("type")
            if kind == "suite":
                suites[event["suite"]["id"]] = event["suite"]
            elif kind == "testStart":
                item = event["test"]
                if item["id"] in starts:
                    duplicates.append(["start", item["id"]])
                starts[item["id"]] = item
            elif kind == "testDone":
                if event["testID"] in finishes:
                    duplicates.append(["finish", event["testID"]])
                finishes[event["testID"]] = event
            elif kind == "error":
                errors.append(event)
            elif kind == "done":
                terminal.append(event)
        error_ids = {event.get("testID") for event in errors}
        cases, hidden_failures = [], []
        for key, event in finishes.items():
            check(key in starts, str(path) + ": finish without start")
            if key not in starts:
                continue
            start = starts[key]
            suite = suites.get(start.get("suiteID"), {})
            name = suite.get("path")
            if name:
                parsed = urlparse(name)
                file = Path(unquote(parsed.path)) if parsed.scheme == "file" else Path(name)
                if not file.is_absolute():
                    file = Path(cwd) / file
                name = str(file.resolve().relative_to(repo))
            result = "error" if key in error_ids else event.get("result")
            case = {"file": name, "platform": suite.get("platform"), "name": start.get("name"),
                    "result": result, "skipped": bool(event.get("skipped"))}
            if event.get("hidden"):
                if result != "success" or case["skipped"]:
                    hidden_failures.append(case)
            else:
                cases.append(case)
        counts = {
            "passed": sum(c["result"] == "success" and not c["skipped"] for c in cases),
            "failed": sum(c["result"] != "success" and not c["skipped"] for c in cases),
            "skipped": sum(c["skipped"] for c in cases),
        }
        keys = [canonical([c["file"], c["platform"], c["name"]]) for c in cases]
        observed = {c["file"] for c in cases}
        missing, unexpected = sorted(set(expected) - observed), sorted(observed - set(expected))
        check(not duplicates, str(path) + ": duplicate event IDs")
        check(len(keys) == len(set(keys)), str(path) + ": duplicate case identities")
        check(set(starts) == set(finishes), str(path) + ": incomplete event lifecycle")
        check(not errors and not hidden_failures, str(path) + ": error or hidden failure events")
        check(len(terminal) == 1 and terminal[0].get("success") is True,
              str(path) + ": missing/unsuccessful final done event")
        check(not missing and not unexpected, str(path) + ": file coverage differs from selection")
        check(counts["passed"] > 0 and counts["failed"] == counts["skipped"] == 0,
              str(path) + ": unsuccessful case count")
        return {"counts": counts, "cases": cases, "keys": keys, "files": sorted(observed),
                "missing_files": missing, "unexpected_files": unexpected,
                "non_json_lines": malformed, "terminal": terminal}

    def audit_step(folder, record):
        check(record.get("exit_code") == 0 and record.get("accepted") is True,
              str(folder) + ": command did not pass")
        check(not record.get("interrupted") and not record.get("timeout"),
              str(folder) + ": incomplete command")
        check(read_json(folder / "result.json") == record, str(folder) + ": receipt/result mismatch")
        for key in ("stdout", "stderr"):
            check(sha(folder / (key + ".log")) == record[key + "_sha256"],
                  str(folder) + ": changed " + key + " log")
        command = read_json(folder / "command.json")
        for key in ("argv", "command", "cwd", "expected_test_files", "environment_overrides"):
            if key in command:
                check(command[key] == record.get(key), str(folder) + ": changed command field " + key)
        result = {"name": record["name"], "exit_code": record["exit_code"],
                  "stdout_sha256": sha(folder / "stdout.log"),
                  "stderr_sha256": sha(folder / "stderr.log")}
        keys = []
        if "test_counts" in record:
            parsed = parse_raw_tests(folder / "stdout.log", record["cwd"], record["expected_test_files"])
            recorded = read_json(folder / "test-cases.json.gz")
            check(parsed["counts"] == record["test_counts"], str(folder) + ": reported counts differ from raw logs")
            check({k: recorded[k] for k in parsed["counts"]} == parsed["counts"],
                  str(folder) + ": case artifact count mismatch")
            check(sorted(map(canonical, parsed["cases"])) == sorted(map(canonical, recorded["cases"])),
                  str(folder) + ": case artifact differs from raw logs")
            check(sha(folder / "test-cases.json.gz") == record["test_cases_sha256"],
                  str(folder) + ": case artifact hash mismatch")
            result.update(counts=parsed["counts"], files=parsed["files"],
                          independently_parsed_cases_sha256=digest(parsed["cases"]),
                          missing_files=parsed["missing_files"], unexpected_files=parsed["unexpected_files"])
            keys = parsed["keys"]
        if "expected" in record:
            observed = read_json(folder / "stdout.log")
            check(observed == record["expected"] == record.get("observed"),
                  str(folder) + ": JavaScript smoke result mismatch")
            result["verified_smoke_result"] = observed
        return result, keys

    receipt = read_json(run / "receipt.json")
    check(receipt["status"] == "passed", "mail receipt is not passed")
    frozen = receipt["source_head"]
    current_head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    check(subprocess.run(["git", "merge-base", "--is-ancestor", frozen, current_head], cwd=repo).returncode == 0,
          "current HEAD is not a descendant of the frozen mail source")
    tree = subprocess.check_output(["git", "rev-parse", frozen + "^{tree}"], cwd=repo, text=True).strip()
    check(tree == receipt["source_tree"], "frozen source tree mismatch")
    tracked = {}
    for row in subprocess.check_output(["git", "ls-tree", "-r", "-z", frozen], cwd=repo).split(b"\0"):
        if row:
            metadata, path = row.split(b"\t", 1)
            mode, kind, oid = metadata.decode().split()
            tracked[path.decode()] = (mode, kind, oid)

    config = repo / ".dart_tool/package_config.json"
    runtime_before = read_json(run / "runtime-before.json.gz")
    flutter_snapshot = next(Path(p) for p in runtime_before if p.endswith("/bin/cache/flutter_tools.snapshot"))
    flutter_root = flutter_snapshot.parents[2]
    framework = read_json(flutter_root / "bin/cache/flutter.version.json")
    check(framework["frameworkVersion"] == read_json(repo / ".fvmrc")["flutter"],
          "Flutter runtime does not match the repository pin")
    check(not (repo / "pubspec_overrides.yaml").exists(), "unexpected root dependency override")
    configurations = {"workspace": config,
                      "flutter-tools": flutter_root / "packages/flutter_tools/.dart_tool/package_config.json"}
    package_roots = {}
    for origin, filename in configurations.items():
        for package in read_json(filename)["packages"]:
            location = urljoin(filename.as_uri(), package["rootUri"])
            package_roots[(origin, package["name"])] = Path(unquote(urlparse(location).path)).resolve()

    def dependency_path(key):
        origin, package, relative = key.split("/", 2)
        return package_roots[(origin, package)] / relative

    def audit_inputs(before_path, after_path, kind, commit_check=False):
        before, after = read_json(before_path), read_json(after_path)
        check(before == after, kind + ": before/after inputs changed")
        mismatches, commit_mismatches = [], []
        for key, expected in before.items():
            path = repo / key if kind == "source" else dependency_path(key) if kind == "dependency" else Path(key)
            if not hash_matches(path, expected, kind):
                mismatches.append(key)
            if commit_check:
                meta = tracked.get(key)
                matches = meta is not None and meta[1] == "blob"
                if matches:
                    if meta[0] == "120000":
                        text = os.readlink(path).encode()
                        matches = hashlib.sha1(b"blob " + str(len(text)).encode() + b"\0" + text).hexdigest() == meta[2]
                    else:
                        matches = identity(path)["git_blob"] == meta[2]
                if not matches:
                    commit_mismatches.append(key)
        check(not commit_mismatches, kind + ": recorded inputs differ from frozen commit")
        return {"inputs": len(before), "digest": digest(before), "before_after_equal": before == after,
                "current_mismatches": mismatches, "frozen_commit_mismatches": commit_mismatches}

    bound = {}
    for kind, stem in [("source", "source"), ("dependency", "dependencies"), ("runtime", "runtime")]:
        bound[kind] = audit_inputs(run / (stem + "-before.json.gz"), run / (stem + "-after.json.gz"),
                                   kind, commit_check=kind == "source")
        check(bound[kind]["digest"] == receipt[kind + "_digest"], kind + ": receipt digest mismatch")
        check(bound[kind]["inputs"] == receipt[kind + "_inputs"], kind + ": receipt count mismatch")

    selection = read_json(run / "selection.json")
    required = {"format", "analysis", "whitespace"} | {c["name"] for c in selection["cohorts"]}
    check(required == {s["name"] for s in receipt["steps"]}, "mail required gate set mismatch")
    check(not receipt["unexecuted_cohorts"], "mail contains unexecuted cohorts")
    by_name = {step["name"]: step for step in receipt["steps"]}
    for cohort in selection["cohorts"]:
        selected = [cohort["package"] + "/" + name for name in cohort["files"]]
        check(set(selected) == set(by_name[cohort["name"]]["expected_test_files"]),
              cohort["name"] + ": selected and executed file lists differ")
    mail_steps, mail_keys = [], []
    for record in receipt["steps"]:
        result, keys = audit_step(run / record["name"], record)
        mail_steps.append(result)
        mail_keys.extend(keys)
    mail_counts = {key: sum(s.get("counts", {}).get(key, 0) for s in mail_steps)
                   for key in ("passed", "failed", "skipped")}
    check(mail_counts == receipt["test_totals"], "mail total differs from independent raw counts")
    check(len(mail_keys) == len(set(mail_keys)), "mail duplicate cases across cohorts")
    check(sha(run / "run-mail-validation.py") == sha(repo / "docs/validation/mail-archive-restore-20261119/run-mail-validation.py"),
          "retained executed mail runner differs from repository runner")
    selected_files = {c["package"] + "/" + f for c in selection["cohorts"] for f in c["files"]}
    check(len(selected_files) == receipt["unique_test_files"], "mail selected file count mismatch")

    incoming_reports, incoming_keys = [], []
    runtime_folder = incoming.parent / "runtime"
    runtime_receipt = read_json(runtime_folder / "runtime.json")
    readiness_receipt = read_json(runtime_folder / "readiness-receipt.json")
    runtime_receipt_hashes = {"runtime_receipt_sha256": sha(runtime_folder / "runtime.json"),
                              "readiness_receipt_sha256": sha(runtime_folder / "readiness-receipt.json")}
    check(runtime_receipt["status"] == readiness_receipt["status"] == "ready",
          "incoming runtime/readiness receipt is not ready")
    for executable, expected in runtime_receipt["executables_sha256"].items():
        check(sha(executable) == expected, "incoming runtime executable identity mismatch " + executable)
    for field, filename in (("lock", "pubspec.lock"), ("manifest", "pubspec.yaml")):
        check(sha(repo / filename) == readiness_receipt[field + "_before_sha256"]
              == readiness_receipt[field + "_after_sha256"],
              "incoming readiness root " + filename + " identity mismatch")
    native_receipt = readiness_receipt["native_assets"]
    check(sha(native_receipt["library"]) == native_receipt["library_sha256"],
          "incoming SQLite readiness identity mismatch")
    smokes = ("web_smoke", "web_vba_smoke", "web_vba_procedures_smoke", "web_vba_control_flow_smoke")
    incoming_required = {
        "engine": {"macros-vba", "branding-and-structure", "macos-build-script-syntax"}
                  | {name + suffix for name in smokes for suffix in ("-compile", "-node")},
        "editor": {"pdf-and-review"},
        "studio": {"desktop-ribbon-lifecycle"},
    }
    for phase in ("engine", "editor", "studio"):
        folder = incoming / phase
        item = read_json(folder / "receipt.json")
        check(item["status"] == "passed", phase + ": incoming phase not passed")
        for key, expected in runtime_receipt_hashes.items():
            check(item[key] == expected, phase + ": runtime receipt identity mismatch " + key)
        check(item["runtime_receipts_unchanged"] is True,
              phase + ": incoming runtime receipt changed during execution")
        for observed_head in (item["head_at_start"], item["head_at_finish"]):
            check(subprocess.run(["git", "merge-base", "--is-ancestor", observed_head, frozen],
                                 cwd=repo).returncode == 0,
                  phase + ": incoming source is not an ancestor of final source")
        check(sha(folder / "executed-runner.py") == item["runner_sha256"], phase + ": executed runner identity mismatch")
        check(sha(config) == item["package_config_sha256"], phase + ": package configuration identity mismatch")
        check(sha(repo / "docs/validation/mail-archive-portability-20261119/run-local-validation.py") == item["parser_sha256"],
              phase + ": parser identity mismatch")
        check(incoming_required[phase] == {step["name"] for step in item["commands"]},
              phase + ": incoming required gate set mismatch")
        check(len(item["commands"]) == len(incoming_required[phase]), phase + ": duplicate incoming gate")
        dependency = audit_inputs(folder / "dependencies-before.json.gz", folder / "dependencies-after.json.gz", "dependency")
        steps = []
        for record in item["commands"]:
            command_folder = folder / record["name"]
            result, keys = audit_step(command_folder, record)
            for stage in ("before", "after"):
                check(sha(command_folder / ("source-" + stage + ".json.gz")) == record["source_" + stage + "_sha256"],
                      str(command_folder) + ": source manifest artifact hash mismatch")
            result["source_binding"] = audit_inputs(command_folder / "source-before.json.gz",
                                                     command_folder / "source-after.json.gz", "source",
                                                     commit_check=True)
            steps.append(result)
            incoming_keys.extend(keys)
        totals = {key: sum(s.get("counts", {}).get(key, 0) for s in steps)
                  for key in ("passed", "failed", "skipped")}
        check(totals == item["test_totals"], phase + ": incoming total mismatch")
        javascript = {}
        for name, expected in item.get("javascript_sha256", {}).items():
            executed = next(step for step in item["commands"] if step["name"] == name + "-node")
            path = Path(executed["command"][-1])
            check(sha(path) == expected, phase + ": emitted JavaScript identity mismatch " + name)
            javascript[name] = expected
        incoming_reports.append({"phase": phase, "receipt_sha256": sha(folder / "receipt.json"),
                                 "head_at_start": item["head_at_start"], "head_at_finish": item["head_at_finish"],
                                 "source_commit_relationship": "Observed heads must be ancestors of final source; every recorded source input is independently required to match the final frozen Git blob and current bytes.",
                                 "counts": totals, "dependencies": dependency, "steps": steps,
                                 "javascript_sha256_verified": javascript})
    incoming_counts = {key: sum(r["counts"][key] for r in incoming_reports)
                       for key in ("passed", "failed", "skipped")}
    check(len(incoming_keys) == len(set(incoming_keys)), "incoming duplicate case identities")
    overlap = set(mail_keys) & set(incoming_keys)
    check(not overlap, "mail and incoming case counts overlap")
    incoming_files = {file for phase in incoming_reports for step in phase["steps"]
                      for file in step.get("files", [])}
    check(not selected_files & incoming_files, "mail and incoming selected files overlap")

    native_text = (repo / ".dart_tool/native_assets.yaml").read_text()
    native = json.loads(native_text[native_text.index("{"):])
    mapped = native["native-assets"]["linux_x64"]["package:sqlite3/src/ffi/libsqlite3.g.dart"]
    check(mapped[0] == "absolute", "SQLite native mapping is not absolute")
    check(sha(mapped[1]) == receipt["sqlite"]["sha256"] ==
          "0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b",
          "SQLite native asset does not match packaged accepted identity")

    screenshots = []
    expected_shots = {"archive-restore-" + stage + "-" + language + ".png"
                      for stage in ("preview", "result") for language in ("en", "de", "ar")}
    expected_shots |= {"archive-portability-desktop-en.png", "archive-portability-mobile-ar.png"}
    expected_shots |= {"archive-export-" + stage + "-" + language + ".png"
                      for stage in ("confirmation", "report") for language in ("en", "ar")}
    generated = {p.name for p in (run / "screenshots").glob("*.png")}
    check(generated == expected_shots, "screenshot capture set differs from fixture")
    fixture = "packages/quds_office_editor/example/test/studio_mail_archive_portability_visual_test.dart"
    check(fixture in selected_files, "screenshot fixture was not selected for accepted mail execution")
    for name in sorted(generated):
        path = run / "screenshots" / name
        data = path.read_bytes()
        check(data.startswith(b"\x89PNG\r\n\x1a\n"), name + ": invalid PNG signature")
        width, height = struct.unpack(">II", data[16:24])
        published = repo / "docs/validation/mail-archive-restore-20261119/screenshots" / name
        matches = published.is_file() and sha(published) == sha(path)
        check(matches, name + ": documentation capture differs from accepted run")
        screenshots.append({"file": name, "sha256": sha(path), "width": width, "height": height,
                            "published_copy_matches": matches})

    review_file = "packages/quds_mail_store/test/archive_restore_adversarial_test.dart"
    review_count = sum(json.loads(key)[0] == review_file for key in mail_keys)
    check(review_count == 15, "independent review cases not fully included in final mail cohort")
    initial_attempts = []
    for name, published_name in (("mail-final", "mail-format"), ("mail-accepted", "mail-node-selection")):
        old = incoming.parent / "attempts" / published_name
        if old != run and (old / "receipt.json").is_file():
            previous = read_json(old / "receipt.json")
            original = repo.parent / name / "receipt.json"
            original_matches = not original.is_file() or sha(original) == sha(old / "receipt.json")
            check(original_matches, published_name + ": retained initial receipt differs from execution copy")
            initial_attempts.append({"directory": str(old.relative_to(repo)), "status": previous["status"],
                                     "raw_reported_counts": previous["test_totals"],
                                     "counts_included_in_acceptance": 0,
                                     "failed_gates": [s["name"] for s in previous["steps"] if not s["accepted"]],
                                     "receipt_sha256": sha(old / "receipt.json")})

    report = {
        "status": "passed" if not failures else "failed",
        "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "auditor_sha256": sha(Path(__file__).resolve()),
        "method": "Independent JSON event parser and direct current-file hashing; no acceptance helper imports or repeated product tests.",
        "frozen_source_head": frozen, "frozen_source_tree": tree, "current_head": current_head,
        "mail_receipt_sha256": sha(run / "receipt.json"), "mail_counts": mail_counts,
        "mail_unique_test_files": len(selected_files), "mail_gates": mail_steps,
        "mail_input_identity": bound, "incoming_counts": incoming_counts,
        "incoming_unique_test_files": len(incoming_files),
        "combined_unique_test_files": len(selected_files | incoming_files),
        "accepted_gate_counts": {"mail": len(mail_steps),
                                 "incoming": sum(len(p["steps"]) for p in incoming_reports),
                                 "combined": len(mail_steps) + sum(len(p["steps"]) for p in incoming_reports)},
        "incoming_runtime_identity": {**runtime_receipt_hashes,
                                      "executables_sha256": runtime_receipt["executables_sha256"],
                                      "sqlite_sha256": native_receipt["library_sha256"],
                                      "matches_current": True,
                                      "scope": "Incoming phases retain the same prepared runtime/readiness receipts before and after each phase. Both SDK executable hashes, root manifest/lock and SQLite are rechecked here; the mail run additionally binds its full runtime file manifest before and after execution."},
        "runtime_version": {"flutter": framework["frameworkVersion"],
                            "dart": framework["dartSdkVersion"],
                            "matches_repository_pin": framework["frameworkVersion"] == read_json(repo / ".fvmrc")["flutter"]},
        "incoming_phases": incoming_reports,
        "combined_counts": {key: mail_counts[key] + incoming_counts[key] for key in mail_counts},
        "overlapping_case_identities": [json.loads(key) for key in sorted(overlap)],
        "independent_review_cases": {"count": review_count, "included_in_mail_store_cohort": review_count == 15,
                                     "added_again_to_totals": False},
        "sqlite_native_mapping": mapped,
        "screenshots": {"fixture": fixture, "fixture_sha256": sha(repo / fixture),
                        "method": "Accepted Flutter RepaintBoundary captures of the product StudioMailArchiveDialog with injected synthetic store/files; no native AppKit capture or live-account claim.",
                        "files": screenshots},
        "superseded_mail_attempts": initial_attempts,
        "failures": failures,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": report["status"], "mail": mail_counts, "incoming": incoming_counts,
                      "combined": report["combined_counts"], "failures": failures}))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())

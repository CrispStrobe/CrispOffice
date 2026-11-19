#!/usr/bin/env python3
"""Independently replay local acceptance and verify its input identities.

This script imports neither validation runner nor their test-event parsers. It
does not run tests, resolve dependencies, change product files, or query CI.
Only an explicit incoming acceptance inventory is eligible for combined totals;
development, failed, superseded and UI-focused runs never add accepted counts.
"""

from __future__ import annotations

import argparse
import ast
import collections
from datetime import datetime, timedelta, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
from urllib.parse import unquote, urljoin, urlparse


BASE = "caf378f40fd5bda50f504a6816404d01d8bbb8f8"
SCRIPT = "docs/validation/mail-archive-resume-20261119/audit-validation.py"
SOURCE_ROOTS = ("packages/", "third_party/", "apps/", "tool/", "tools/")
ROOT_INPUTS = {
    "pubspec.yaml", "pubspec.lock", "analysis_options.yaml", "melos.yaml",
    ".cursorrules", "CONTRIBUTING.md", ".fvmrc", "dart_test.yaml",
}
DOCUMENT_INPUTS = {
    "docs/validation/mail-archive-resume-20261119/run-mail-validation.py",
    "docs/validation/mail-archive-portability-20261119/run-local-validation.py",
    "docs/roadmaps/mail/archive-search.md",
}
SQLITE_SHA256 = "0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b"
SMOKE_ASSERTIONS = {
    "web_smoke": ("lateFailurePreservedBytes", "mcpInspection"),
    "web_vba_smoke": ("validationPreservedBytes", "lateFailurePreservedBytes", "mcpCompileAndRun", "numericBoundsAndPrecedence"),
    "web_vba_procedures_smoke": ("procedureScopesAndExits", "recursionRejected", "sharedWorkBudget", "numericBounds", "validationPreservedBytes", "lateFailurePreservedBytes", "mcpCompileAndRun"),
    "web_vba_control_flow_smoke": ("orderedCasesAndEagerRangeBounds", "sharedLoopWorkBudget", "staticInactiveChecks", "validationPreservedBytes", "lateFailurePreservedBytes", "mcpCompileAndRun"),
    "web_vba_arrays_smoke": ("liveArraySlotsAndIndependentControlVariables", "rangeSnapshotAndRowMajorOrder", "exactArrayAllocationAndNegativeBounds", "boundedArraysAndRangeIteration", "staticInactiveChecks", "validationPreservedBytes", "lateFailurePreservedBytes", "mcpCompileAndRun"),
}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def object_digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def read_json(path):
    path = Path(path)
    raw = path.read_bytes()
    return json.loads(gzip.decompress(raw) if path.suffix == ".gz" else raw)


class Audit:
    def __init__(self, repo):
        self.repo = repo.resolve()
        self.workspace = self.repo.parent
        self.failures = []
        self.identities = {}
        self.case_keys = []
        self.test_files = set()
        self.current_head = self.git("rev-parse", "HEAD").strip()
        self.current_tree = self.tree(self.current_head)
        self.package_roots = {}
        self.window_start = None
        self.window_end = None

    def check(self, condition, message):
        if not condition:
            self.failures.append(message)
        return bool(condition)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, text=True)

    def tree(self, commit):
        result = {}
        raw = subprocess.check_output(["git", "ls-tree", "-rz", commit], cwd=self.repo)
        for entry in raw.split(b"\0"):
            if not entry:
                continue
            meta, name = entry.split(b"\t", 1)
            mode, kind, oid = meta.decode().split()
            result[name.decode()] = (mode, kind, oid)
        return result

    def identity(self, path):
        path = Path(path)
        key = str(path)
        if key not in self.identities:
            info = path.stat()
            digest = hashlib.sha256()
            blob = hashlib.sha1(b"blob " + str(info.st_size).encode() + b"\0")
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
                    blob.update(chunk)
            self.identities[key] = {
                "sha256": digest.hexdigest(), "bytes": info.st_size,
                "git_blob": blob.hexdigest(),
            }
        return self.identities[key]

    def match(self, path, expected, label):
        path = Path(path)
        if not self.check(path.is_file(), label + ": missing file " + str(path)):
            return False
        actual = self.identity(path)
        wanted = {"sha256": expected} if isinstance(expected, str) else expected
        return self.check(
            actual["sha256"] == wanted["sha256"]
            and ("bytes" not in wanted or actual["bytes"] == wanted["bytes"]),
            label + ": changed file " + str(path),
        )

    def git_match(self, path, tree, label):
        path = Path(path)
        relative = str(path.relative_to(self.repo))
        entry = tree.get(relative)
        if not self.check(entry is not None and entry[1] == "blob", label + ": unbound input " + relative):
            return False
        mode, _, oid = entry
        if mode == "120000":
            if not self.check(path.is_symlink(), label + ": link mode changed " + relative):
                return False
            value = os.readlink(path).encode()
            actual = hashlib.sha1(b"blob " + str(len(value)).encode() + b"\0" + value).hexdigest()
        else:
            if not self.check(not path.is_symlink(), label + ": unexpected link " + relative):
                return False
            actual = self.identity(path)["git_blob"]
            self.check(bool(path.stat().st_mode & stat.S_IXUSR) == (mode == "100755"),
                       label + ": executable mode changed " + relative)
        return self.check(actual == oid, label + ": Git blob differs " + relative)

    def normalized_file(self, value, cwd):
        parsed = urlparse(value)
        path = Path(unquote(parsed.path)) if parsed.scheme == "file" else Path(value)
        if not path.is_absolute():
            path = Path(cwd) / path
        return str(path.resolve().relative_to(self.repo))

    def parse_tests(self, path, cwd, expected, expected_platform="vm"):
        """Replay test lifecycles directly, including hidden loader failures."""
        suites, starts, finishes = {}, {}, {}
        errors, terminal, anomalies, non_json = [], [], [], []
        for line_number, line in enumerate(Path(path).read_text().splitlines(), 1):
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except ValueError:
                non_json.append({"line": line_number, "text": line[:240]})
                continue
            if not isinstance(event, dict):
                anomalies.append(["non-object event", line_number])
                continue
            kind = event.get("type")
            if kind == "suite":
                item = event["suite"]
                if item["id"] in suites:
                    anomalies.append(["duplicate suite", item["id"]])
                suites[item["id"]] = item
            elif kind == "testStart":
                item = event["test"]
                if item["id"] in starts:
                    anomalies.append(["duplicate start", item["id"]])
                starts[item["id"]] = item
            elif kind == "testDone":
                if event["testID"] in finishes:
                    anomalies.append(["duplicate finish", event["testID"]])
                finishes[event["testID"]] = event
            elif kind == "error":
                errors.append(event)
            elif kind == "done":
                terminal.append(event)
        cases, hidden_failures = [], []
        for ident, finished in finishes.items():
            if ident not in starts:
                anomalies.append(["finish without start", ident])
                continue
            started = starts[ident]
            suite = suites.get(started.get("suiteID"))
            if suite is None:
                anomalies.append(["missing suite", ident])
                continue
            try:
                filename = self.normalized_file(suite["path"], cwd)
            except (KeyError, ValueError):
                anomalies.append(["invalid suite path", suite.get("path")])
                continue
            case = {
                "file": filename, "platform": suite.get("platform"),
                "name": started.get("name"), "result": finished.get("result"),
                "skipped": bool(finished.get("skipped")),
            }
            hidden = finished.get("hidden") or finished.get("isHidden") or started.get("isHidden")
            if hidden:
                if case["result"] != "success" or case["skipped"]:
                    hidden_failures.append(case)
            else:
                cases.append(case)
        counts = {
            "passed": sum(c["result"] == "success" and not c["skipped"] for c in cases),
            "failed": sum(c["result"] != "success" and not c["skipped"] for c in cases),
            "skipped": sum(c["skipped"] for c in cases),
        }
        keys = [(c["file"], c["platform"], c["name"]) for c in cases]
        present = {c["file"] for c in cases}
        missing = sorted(set(expected) - present)
        unexpected = sorted(present - set(expected))
        label = str(path)
        self.check(not anomalies, label + ": event structure anomalies " + repr(anomalies[:5]))
        self.check(not non_json, label + ": non-JSON reporter output " + repr(non_json[:3]))
        self.check(set(starts) == set(finishes), label + ": unfinished or unstarted tests")
        self.check(not errors and not hidden_failures, label + ": error/hidden failure events")
        self.check(len(terminal) == 1 and terminal[0].get("success") is True,
                   label + ": missing or unsuccessful final done event")
        self.check(len(keys) == len(set(keys)), label + ": duplicate case identities")
        self.check(all(c["platform"] == expected_platform for c in cases),
                   label + ": reporter platform differs from the required platform")
        self.check(not missing and not unexpected, label + ": selected file coverage differs")
        self.check(counts["passed"] > 0 and counts["failed"] == counts["skipped"] == 0,
                   label + ": failed, skipped or empty test run")
        self.case_keys.extend(keys)
        self.test_files.update(present)
        return {
            "counts": counts, "cases": cases, "files": sorted(present),
            "cases_sha256": object_digest(cases), "done_events": terminal,
            "missing_files": missing, "unexpected_files": unexpected,
            "error_events": len(errors), "hidden_failures": hidden_failures,
            "non_json_lines": non_json,
        }

    def configure_packages(self, flutter_root):
        configs = {
            "workspace": self.repo / ".dart_tool/package_config.json",
            "flutter-tools": flutter_root / "packages/flutter_tools/.dart_tool/package_config.json",
        }
        for origin, config in configs.items():
            for item in read_json(config)["packages"]:
                parsed = urlparse(urljoin(config.as_uri(), item["rootUri"]))
                self.package_roots[(origin, item["name"])] = Path(unquote(parsed.path)).resolve()

    def dependency_selection(self):
        expected = set()
        for (origin, package), root in self.package_roots.items():
            if root.is_relative_to(self.repo):
                continue
            paths = set(root.glob("pubspec.yaml"))
            for child in ("lib", "bin", "hook"):
                paths.update(p for p in (root / child).rglob("*") if p.is_file())
            expected.update(origin + "/" + package + "/" + str(p.relative_to(root)) for p in paths)
        return expected

    def resolve_input(self, key, kind):
        if kind == "source":
            return self.repo / key
        if kind == "dependency":
            origin, package, relative = key.split("/", 2)
            return self.package_roots[(origin, package)] / relative
        if kind == "workspace":
            return self.workspace / key
        return Path(key)

    def bind_inputs(self, before_path, after_path, kind, frozen_tree=None):
        before, after = read_json(before_path), read_json(after_path)
        label = str(before_path)
        self.check(before == after, label + ": before/after identities differ")
        self.check(bool(before), label + ": empty input manifest")
        failures_before = len(self.failures)
        git_bound, external = 0, 0
        for key, expected in before.items():
            path = self.resolve_input(key, kind)
            if not self.match(path, expected, label):
                continue
            if path.is_relative_to(self.repo) and not str(path.relative_to(self.repo)).startswith(".dart_tool/"):
                self.git_match(path, self.current_tree, label + " current")
                if frozen_tree is not None:
                    self.git_match(path, frozen_tree, label + " frozen")
                git_bound += 1
            else:
                external += 1
        return {
            "inputs": len(before), "digest": object_digest(before),
            "before_after_equal": before == after,
            "git_bound_inputs": git_bound, "external_inputs": external,
            "current_identity_failures": len(self.failures) - failures_before,
        }

    def source_selection(self):
        raw = subprocess.check_output(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=self.repo,
        )
        names = {name.decode() for name in raw.split(b"\0") if name}
        return {
            name for name in names
            if (name in ROOT_INPUTS or name in DOCUMENT_INPUTS or
                (name.startswith(SOURCE_ROOTS) and "/docs/" not in name
                 and "/doc/" not in name and not name.lower().endswith(".md")))
            and (self.repo / name).is_file()
        }

    def mail_selection(self):
        cohorts = []
        for package in ("quds_mail_core", "quds_mail_mime", "quds_mail_store"):
            vm, node = [], []
            root = self.repo / "packages" / package
            for path in sorted((root / "test").rglob("*_test.dart")):
                declaration = re.search(r"@TestOn\(['\"]([^'\"]+)['\"]\)", path.read_text()[:4000])
                platform = declaration.group(1) if declaration else "vm"
                self.check(platform in ("vm", "js", "node"), "unclassified test platform " + str(path))
                (node if platform in ("js", "node") else vm).append(str(path.relative_to(root)))
            cohorts.append({"name": package + "-vm", "package": "packages/" + package, "files": vm, "platform": "vm"})
            if package == "quds_mail_store":
                node.append("test/archive_export_manifest_test.dart")
            if node:
                cohorts.append({"name": package + "-node", "package": "packages/" + package, "files": sorted(node), "platform": "node"})
        for name, package, pattern in (
            ("mail-ui", "packages/quds_mail_ui", "*_test.dart"),
            ("studio-mail", "packages/quds_office_editor/example", "studio_mail*_test.dart"),
        ):
            files = sorted(str(p.relative_to(self.repo / package)) for p in (self.repo / package / "test").rglob(pattern))
            if name == "studio-mail":
                files.append("test/studio_saved_mail_test.dart")
            cohorts.append({"name": name, "package": package, "files": sorted(files), "platform": "flutter"})
        return cohorts

    def audit_mail(self, run, reviewed_ui):
        receipt, selection = read_json(run / "receipt.json"), read_json(run / "selection.json")
        self.check(receipt.get("status") == "passed", "mail receipt is not passed")
        frozen = receipt["source_head"]
        self.check(bool(re.fullmatch(r"[0-9a-f]{40}", frozen)), "invalid frozen mail commit")
        self.check(subprocess.run(["git", "merge-base", "--is-ancestor", frozen, self.current_head], cwd=self.repo).returncode == 0,
                   "current HEAD does not contain frozen mail source")
        frozen_tree = self.tree(frozen)
        self.check(receipt["source_tree"] == self.git("rev-parse", frozen + "^{tree}").strip(), "frozen mail tree differs")
        self.check(selection["source_head"] == frozen and selection["source_tree"] == receipt["source_tree"], "mail selection source differs")
        self.check(receipt.get("github_actions_used") is False and receipt.get("dependency_resolution_performed") is False,
                   "unexpected CI/dependency-resolution claim")
        executed_harness = self.repo / "docs/validation/mail-archive-resume-20261119/run-mail-validation.py"
        self.match(run / "run-mail-validation.py", self.identity(executed_harness), "preserved mail acceptance harness")
        runtime_before = read_json(run / "runtime-before.json.gz")
        snapshot = next(Path(p) for p in runtime_before if p.endswith("/bin/cache/flutter_tools.snapshot"))
        flutter = snapshot.parents[2]
        self.configure_packages(flutter)
        self.check(read_json(flutter / "bin/cache/flutter.version.json")["frameworkVersion"] == read_json(self.repo / ".fvmrc")["flutter"],
                   "runtime differs from Flutter pin")
        self.check(not (self.repo / "pubspec_overrides.yaml").exists(), "unexpected root dependency override")
        bound = {}
        for kind, stem in (("source", "source"), ("dependency", "dependencies"), ("runtime", "runtime")):
            bound[kind] = self.bind_inputs(run / (stem + "-before.json.gz"), run / (stem + "-after.json.gz"), kind,
                                            frozen_tree=frozen_tree if kind == "source" else None)
            self.check(bound[kind]["digest"] == receipt[kind + "_digest"], kind + " receipt digest differs")
            self.check(bound[kind]["inputs"] == receipt[kind + "_inputs"], kind + " receipt input count differs")
        self.check(set(read_json(run / "source-before.json.gz")) == self.source_selection(), "mail source input inventory is incomplete")
        self.check(set(read_json(run / "dependencies-before.json.gz")) == self.dependency_selection(),
                   "mail external dependency inventory is incomplete")
        sqlite = Path(receipt["sqlite"]["path"])
        self.check(self.identity(sqlite)["sha256"] == SQLITE_SHA256 == receipt["sqlite"]["sha256"], "SQLite native identity differs")
        self.check(receipt["sqlite"].get("fts5") is True, "SQLite FTS5 probe missing")
        expected_cohorts = self.mail_selection()
        self.check(selection["cohorts"] == expected_cohorts, "mail cohort inventory differs from independent discovery")
        required = {"analysis", "format", "whitespace"} | {g["name"] for g in expected_cohorts}
        steps = receipt["steps"]
        self.check(len(steps) == len(required) and {s["name"] for s in steps} == required, "mail required step inventory differs")
        self.check(not receipt.get("unexecuted_cohorts"), "mail has unexecuted cohorts")
        by_name = {s["name"]: s for s in steps}
        changed = sorted(p for p in self.git("diff", "--name-only", "--diff-filter=ACMR", BASE, frozen, "--", "packages").splitlines()
                         if p.endswith(".dart") and (self.repo / p).is_file())
        dart = str(flutter / "bin/cache/dart-sdk/bin/dart")
        self.check(by_name["format"]["argv"][0] == dart == by_name["analysis"]["argv"][0],
                   "mail format/analysis runtime path differs")
        self.check(selection["formatted_files"] == changed, "mail formatted file selection differs")
        self.check(by_name["format"]["argv"][1:] == ["format", "--output=none", "--set-exit-if-changed", *changed], "mail format command selection differs")
        analysis = sorted(set([
            "packages/quds_mail_core", "packages/quds_mail_mime", "packages/quds_mail_store", "packages/quds_mail_ui", *changed,
            *[str(p.relative_to(self.repo)) for p in (self.repo / "packages/quds_office_editor/example/lib").glob("studio_mail_archive*.dart")],
        ]))
        self.check(selection["analysis_targets"] == analysis, "mail analysis target inventory differs")
        self.check(by_name["analysis"]["argv"][1:] == ["analyze", "--fatal-infos", "--fatal-warnings", *analysis], "mail analysis command selection differs")
        whitespace_argv = [
            "git", "diff", "--check", BASE, "--", ".",
            ":(exclude)docs/validation/office-vba-arrays-20261119/independent-review/slide-table-color/before-source.diff",
            ":(exclude)docs/validation/office-vba-arrays-20261119/independent-review/slide-table-color/after-source.diff",
            ":(exclude)docs/validation/office-vba-arrays-20261119/incoming-layout-theme-final/braces-correction/incoming-context.diff",
            ":(exclude)packages/quds_proofing_spacy/licenses/notices/de_core_news_sm-LICENSES_SOURCES",
        ]
        self.check(by_name["whitespace"]["argv"] == whitespace_argv,
                   "mail whitespace command differs from the three raw patches and exact imported license notice")
        reports = []
        total = collections.Counter()
        for step in steps:
            folder = run / step["name"]
            self.check(read_json(folder / "result.json") == step, str(folder) + ": receipt/result mismatch")
            initial = read_json(folder / "command.json")
            self.check(all(step.get(k) == value for k, value in initial.items()), str(folder) + ": original command metadata changed")
            self.check(step.get("exit_code") == 0 and not step.get("interrupted") and step.get("accepted") is True,
                       str(folder) + ": failed/incomplete command")
            for stream in ("stdout", "stderr"):
                self.match(folder / (stream + ".log"), step[stream + "_sha256"], str(folder))
            report = {"name": step["name"], "exit_code": step.get("exit_code"), "argv": step["argv"]}
            cohort = next((c for c in expected_cohorts if c["name"] == step["name"]), None)
            if cohort:
                expected_files = [cohort["package"] + "/" + file for file in cohort["files"]]
                self.check(step["expected_test_files"] == expected_files, step["name"] + ": selected/executed files differ")
                self.check(step["cwd"] == str(self.repo / cohort["package"]), step["name"] + ": test working directory differs")
                actual_arguments = [x for x in step["argv"] if x.endswith("_test.dart")]
                self.check(actual_arguments == cohort["files"], step["name"] + ": test argument selection differs")
                if cohort["platform"] == "flutter":
                    self.check(str(Path(step["argv"][0]).resolve()) in runtime_before,
                               step["name"] + ": Flutter executable missing from runtime inputs")
                    self.check(step["argv"][1:] == ["test", "--no-pub", "--concurrency=1", "--reporter=json", *cohort["files"]],
                               step["name"] + ": Flutter test invocation differs")
                else:
                    test_cli = self.package_roots[("workspace", "test")] / "bin/test.dart"
                    compiler = "dart2js" if cohort["platform"] == "node" else "kernel"
                    self.check(step["argv"] == [
                        dart, "--disable-dart-dev", "--packages=" + str(self.repo / ".dart_tool/package_config.json"),
                        str(test_cli), "--platform=" + cohort["platform"], "--compiler=" + compiler,
                        "--concurrency=1", "--reporter=json", *cohort["files"],
                    ], step["name"] + ": Dart test runtime/platform invocation differs")
                parsed = self.parse_tests(folder / "stdout.log", step["cwd"], expected_files,
                                          "node" if cohort["platform"] == "node" else "vm")
                stored = read_json(folder / "test-cases.json.gz")
                self.check(parsed["counts"] == step["test_counts"], step["name"] + ": counts differ from raw events")
                self.check(parsed["counts"] == {k: stored[k] for k in parsed["counts"]}, step["name"] + ": stored case counts differ")
                self.check(sorted(map(canonical, parsed["cases"])) == sorted(map(canonical, stored["cases"])), step["name"] + ": stored case list differs")
                self.match(folder / "test-cases.json.gz", step["test_cases_sha256"], step["name"])
                total.update(parsed["counts"])
                report.update({k: v for k, v in parsed.items() if k != "cases"})
            else:
                self.check(step["cwd"] == str(self.repo), step["name"] + ": preflight working directory differs")
            reports.append(report)
        self.check(dict(total) == receipt["test_totals"], "mail reported totals differ from independent raw replay")
        self.check(receipt["unique_test_files"] == len({c["package"] + "/" + p for c in expected_cohorts for p in c["files"]}), "mail unique file count differs")
        self.check(receipt.get("inputs_stable") is True, "mail receipt has unstable inputs")
        images = self.audit_images(run / "screenshots", reviewed_ui)
        return {"receipt_sha256": self.identity(run / "receipt.json")["sha256"],
                "source_head": frozen, "source_tree": receipt["source_tree"], "bound_inputs": bound,
                "test_counts": dict(total), "commands": reports, "images": images}

    def audit_images(self, folder, reviewed):
        receipt = read_json(reviewed / "receipt.json")
        artifacts = read_json(reviewed / "artifacts-sha256.json")
        for name, digest in artifacts.items():
            self.match(reviewed / name, digest, "reviewed UI artifact")
        expected = {Path(name).name: digest for name, digest in artifacts.items()
                    if name.startswith("screenshots/") and name.endswith(".png")}
        self.check(set(expected) == {p.name for p in (reviewed / "screenshots").glob("*.png")},
                   "reviewed UI image inventory differs from its retained hashes")
        actual = {p.name: self.identity(p)["sha256"] for p in folder.glob("*.png")}
        self.check(actual == expected, "acceptance UI captures differ from final reviewed UI fixture outputs")
        self.check(len(expected) == receipt["visual_review"]["captured_states"], "UI capture count differs from review receipt")
        reviewed_names = receipt["visual_review"]["reviewed_files"]
        self.check(len(reviewed_names) == receipt["visual_review"]["new_resume_states_individually_reviewed"], "UI visual-review inventory differs")
        self.check(set(reviewed_names) <= set(actual), "reviewed resume images missing")
        before, after = read_json(reviewed / "inputs-before.json"), read_json(reviewed / "inputs-after.json")
        self.check(before == after, "focused UI source changed during captures")
        for name, digest in before.items():
            self.match(self.repo / name, digest, "reviewed UI input")
        return {"captured_states": len(actual), "individually_reviewed_resume_states": len(reviewed_names),
                "all_capture_hashes_match": actual == expected, "sha256": actual}

    def command(self, folder, record, name, plain_logs=False):
        """Verify the actual exit result and preserve the exact invocation."""
        label = str(folder) + "/" + name
        argv = record.get("command", record.get("argv"))
        self.check(bool(argv) and bool(record.get("cwd")), label + ": command/cwd missing")
        self.check(record.get("exit_code") == 0, label + ": nonzero or absent exit code")
        self.check(not record.get("timed_out") and not record.get("interrupted"), label + ": interrupted/timed out")
        paths = {}
        for stream in ("stdout", "stderr"):
            if isinstance(record.get(stream), dict):
                meta = record[stream]
                path = folder / meta["path"]
                self.match(path, meta, label)
            else:
                path = folder / (("" if plain_logs else name + ".") + stream + ".log")
                self.match(path, record[stream + "_sha256"], label)
            paths[stream] = path
        start = record.get("started_at_utc", record.get("started_utc"))
        finish = record.get("finished_at_utc", record.get("completed_utc"))
        self.check(bool(start), label + ": command start time is missing")
        if start:
            began = datetime.fromisoformat(start)
            ended = datetime.fromisoformat(finish) if finish else began + timedelta(seconds=record["elapsed_seconds"])
            self.check(self.window_start <= began <= ended <= self.window_end + timedelta(seconds=1),
                       label + ": command falls outside captured final incoming window")
        result = {
            "name": name, "argv": argv, "cwd": record["cwd"],
            "exit_code": record.get("exit_code"), "stdout_sha256": self.identity(paths["stdout"])["sha256"],
            "stderr_sha256": self.identity(paths["stderr"])["sha256"],
        }
        return result, paths

    def incoming_bindings(self, folder, receipt, frozen_tree):
        before = next((folder / name for name in ("source-before.json.gz", "source-before.json", "inputs-before.json") if (folder / name).is_file()), None)
        self.check(before is not None, str(folder) + ": source snapshot missing")
        result = {}
        if before is not None:
            after = before.with_name(before.name.replace("before", "after"))
            values = read_json(before)
            kind = "workspace" if all(key.startswith((self.repo.name + "/", "runtime/", "incoming-validation/")) for key in values) else "source"
            result["source"] = self.bind_inputs(before, after, kind, frozen_tree=frozen_tree)
            source_count = receipt.get("source_inputs", receipt.get("source_input_count"))
            if source_count is not None:
                self.check(result["source"]["inputs"] == source_count,
                           str(folder) + ": source input count differs")
        before = next((folder / name for name in ("dependencies-before.json.gz", "dependencies-before.json") if (folder / name).is_file()), None)
        self.check(before is not None, str(folder) + ": dependency snapshot missing")
        if before is not None:
            after = before.with_name(before.name.replace("before", "after"))
            values = read_json(before)
            kind = "workspace" if all(key.startswith((self.repo.name + "/", "runtime/")) for key in values) else "source"
            result["dependencies"] = self.bind_inputs(before, after, kind)
            dependency_count = receipt.get("dependency_inputs", receipt.get("dependency_input_count"))
            if dependency_count is not None:
                self.check(result["dependencies"]["inputs"] == dependency_count,
                           str(folder) + ": dependency input count differs")
        self.check(not receipt.get("changed_source_inputs") and not receipt.get("changed_dependency_inputs"),
                   str(folder) + ": receipt records changed inputs")
        return result

    def incoming_test_summary(self, parsed, saved, label):
        counts = parsed["counts"]
        if "passed_distinct" in saved:
            reported = {key: saved[key + "_distinct"] for key in counts}
        else:
            reported = {key: saved[key] for key in counts}
        self.check(counts == reported, label + ": reported counts differ from independent replay")
        if "tests" in saved:
            expected = sorted((Path(c["file"]).name, c["name"], c["result"], c["skipped"]) for c in parsed["cases"])
            actual = sorted((c["suite"], c["name"], c["result"], c["skipped"]) for c in saved["tests"])
            self.check(actual == expected, label + ": retained case list differs from independent replay")

    def audit_engine(self, folder, receipt):
        checks = receipt["checks"]
        expected_checks = {"macro-tests", "engine-analysis", "format", "whitespace", *SMOKE_ASSERTIONS}
        self.check(set(checks) == expected_checks, "incoming engine required command inventory differs")
        self.check(read_json(folder / "checks-progress.json") == checks, "incoming engine final checks-progress differs")
        workflow = (self.repo / ".github/workflows/office-macros.yml").read_text()
        section = workflow.split("- name: Macro and existing command regressions", 1)[1].split("- name:", 1)[0]
        selected = re.findall(r"^\s+(test/\S+_test\.dart)\s*$", section, re.MULTILINE)
        smokes = re.findall(r"dart compile js -O1 (tool/macros/(\w+)\.dart)", workflow)
        self.check(receipt["workflow_test_selection"] == selected and len(selected) == len(set(selected)),
                   "incoming engine workflow test selection differs")
        self.check(receipt["workflow_javascript_selection"] == [s[0] for s in smokes]
                   and {s[1] for s in smokes} == set(SMOKE_ASSERTIONS), "incoming engine smoke inventory differs")
        total = collections.Counter()
        commands = []
        for command_record in receipt["runtime"].values():
            detail, _ = self.command(folder, command_record, command_record["name"])
            self.check(read_json(folder / (command_record["name"] + ".json")) == command_record,
                       "incoming engine runtime command record differs")
            commands.append(detail)
        for name, check in checks.items():
            self.check(check.get("success") is True and not check.get("harness_error"), "incoming engine check failed: " + name)
            expected_commands = 2 if name in SMOKE_ASSERTIONS else 1
            self.check(len(check.get("commands", [])) == expected_commands, "incoming engine missing/extra commands: " + name)
            paths_by_name = {}
            for command_record in check.get("commands", []):
                command_name = command_record["name"]
                self.check(read_json(folder / (command_name + ".json")) == command_record,
                           "incoming engine original command record differs: " + command_name)
                detail, paths = self.command(folder, command_record, command_name)
                commands.append(detail)
                paths_by_name[command_name] = paths
                if name == "macro-tests":
                    expected_files = ["packages/quds_office_engine/" + p for p in selected]
                    arguments = [p for p in detail["argv"] if p.endswith("_test.dart")]
                    self.check(arguments == selected, "incoming engine actual test arguments differ")
                    parsed = self.parse_tests(paths["stdout"], detail["cwd"], expected_files)
                    self.incoming_test_summary(parsed, read_json(folder / "test-summary.json"), "incoming engine tests")
                    self.check(check["passed_distinct"] == parsed["counts"]["passed"], "incoming engine task counts differ")
                    detail.update({k: v for k, v in parsed.items() if k != "cases"})
                    total.update(parsed["counts"])
            if name in SMOKE_ASSERTIONS:
                self.match(Path(check["generated_javascript"]["path"]), check["generated_javascript"], "incoming compiled JavaScript")
                output = read_json(paths_by_name[name + "-run"]["stdout"])
                assertions = read_json(folder / (name + "-assertions.json"))
                self.check(assertions == check["assertions"], name + ": smoke assertion records differ")
                self.check(assertions.get("reported") == [output], name + ": raw smoke output differs")
                self.check(all(output.get(field) is True for field in SMOKE_ASSERTIONS[name]), name + ": smoke assertions failed")
                if name in ("web_vba_arrays_smoke", "web_vba_control_flow_smoke"):
                    stress = output.get("coldDepthStress")
                    self.check(isinstance(stress, str) and "32" in stress and "63" in stress, name + ": cold depth stress assertion missing")
        for name, expected in read_json(folder / "artifact-manifest.json").items():
            self.match(folder / name, expected, "incoming engine artifact")
        self.match(folder / "executed-runner.py", receipt["executed_runner"], "incoming engine executed harness")
        return {"test_counts": dict(total), "commands": commands, "javascript_programs": len(SMOKE_ASSERTIONS)}

    def audit_ui_tests(self, folder, receipt):
        detail, paths = self.command(folder, receipt, receipt["group"] + "-tests", plain_logs=True)
        selected = [p for p in detail["argv"] if p.endswith("_test.dart")]
        expected = [self.normalized_file(p, detail["cwd"]) for p in selected]
        plan = read_json(self.workspace / "runtime/incoming-test-plan.json")
        self.check(selected == plan[receipt["group"] + "_tests"], str(folder) + ": UI plan/command differs")
        parsed = self.parse_tests(paths["stdout"], detail["cwd"], expected)
        self.incoming_test_summary(parsed, receipt["test_summary"], str(folder))
        saved = read_json(folder / "test-cases.json.gz")
        retained = sorted((self.normalized_file(c["suite"], detail["cwd"]), c["name"], c["result"], c["skipped"]) for c in saved)
        expected_cases = sorted((c["file"], c["name"], c["result"], c["skipped"]) for c in parsed["cases"])
        self.check(retained == expected_cases, str(folder) + ": stored UI cases differ from raw events")
        detail.update({k: v for k, v in parsed.items() if k != "cases"})
        return {"test_counts": parsed["counts"], "commands": [detail]}

    def audit_commands(self, folder, receipt):
        reports, total = [], collections.Counter()
        names = [record["name"] for record in receipt["commands"]]
        expected_names = ["tests", "analysis", "format"] if "summary" in receipt else ["analysis", "format"]
        self.check(names == expected_names, str(folder) + ": required command set differs")
        for record in receipt["commands"]:
            detail, paths = self.command(folder, record, record["name"])
            selected = [p for p in detail["argv"] if p.endswith("_test.dart")]
            if record["name"] == "tests":
                expected = [self.normalized_file(p, detail["cwd"]) for p in selected]
                parsed = self.parse_tests(paths["stdout"], detail["cwd"], expected)
                saved = read_json(folder / "test-summary.json")
                self.incoming_test_summary(parsed, saved, str(folder))
                self.incoming_test_summary(parsed, receipt["summary"], str(folder) + ": receipt")
                detail.update({k: v for k, v in parsed.items() if k != "cases"})
                total.update(parsed["counts"])
            if "targets" in receipt:
                expected_args = ["analyze", "--fatal-infos", "--fatal-warnings"] if record["name"] == "analysis" else ["format", "--output=none", "--set-exit-if-changed"]
                self.check(detail["argv"][1:] == [*expected_args, *receipt["targets"]], str(folder) + ": scoped command targets differ")
            reports.append(detail)
        return {"test_counts": dict(total), "commands": reports}

    def audit_static(self, folder, receipt):
        names = ["macos-shell-syntax", "python-build-syntax", "license-manifest"]
        self.check([c["name"] for c in receipt["commands"]] == names,
                   "incoming static required command inventory differs")
        reports, paths_by_name = [], {}
        for record in receipt["commands"]:
            detail, paths = self.command(folder, record, record["name"])
            reports.append(detail)
            paths_by_name[record["name"]] = paths
        shell = "packages/quds_office_editor/example/tool/build_macos_app.sh"
        build = "packages/quds_proofing_spacy/tool/build.py"
        licenses = "packages/quds_proofing_spacy/licenses"
        assets = "packages/quds_office_editor/example/assets/licenses/spacy"
        self.check(reports[0]["argv"][1:] == ["-n", shell], "incoming macOS shell command differs")
        syntax = read_json(paths_by_name["python-build-syntax"]["stdout"])
        self.check(syntax == {
            "passed": True, "file": build, "ast_parsed": True,
            "bytecode_compiled_in_memory": True, "product_code_executed": False,
        }, "incoming Python syntax output differs")
        checked = read_json(paths_by_name["license-manifest"]["stdout"])
        self.check(checked.get("passed") is True and checked.get("manifest_complete") is True
                   and checked.get("product_code_executed") is False, "incoming license check failed")
        manifest = read_json(self.repo / licenses / "manifest.json")
        self.check(manifest.get("schema_version") == 1, "incoming license manifest schema differs")
        constants = {}
        for statement in ast.parse((self.repo / build).read_text(), filename=build).body:
            if isinstance(statement, ast.Assign):
                for target in statement.targets:
                    if isinstance(target, ast.Name) and target.id in ("CRISPEMBED", "PCRE2"):
                        constants[target.id] = ast.literal_eval(statement.value)
        for key, constant in (("crispembed", "CRISPEMBED"), ("pcre2", "PCRE2")):
            self.check(manifest[key] == checked[key] == constants[constant],
                       "incoming license/build source pins differ: " + key)
        notices = manifest["notices"]
        self.check({str(p.relative_to(self.repo / licenses)) for p in (self.repo / licenses).rglob("*") if p.is_file()}
                   == set(notices) | {"manifest.json"}, "incoming license manifest file inventory differs")
        expected_notices, names_to_hashes = [], collections.defaultdict(set)
        for name, value in sorted(notices.items()):
            path = self.repo / licenses / name
            self.match(path, value, "incoming retained license notice")
            identity = self.identity(path)
            expected_notices.append({"path": name, "bytes": identity["bytes"], "sha256": identity["sha256"]})
            names_to_hashes[Path(name).name].add(identity["sha256"])
        self.check(checked["verified_notices"] == expected_notices
                   and checked["verified_notice_count"] == len(expected_notices),
                   "incoming raw license verification output differs")
        expected_mirrors = []
        for path in sorted((self.repo / assets).glob("*")):
            if not path.is_file():
                continue
            identity = self.identity(path)
            self.check(identity["sha256"] in names_to_hashes[path.name], "incoming Studio license mirror differs: " + path.name)
            expected_mirrors.append({"path": str(path.relative_to(self.repo)), "bytes": identity["bytes"], "sha256": identity["sha256"]})
        self.check(bool(expected_mirrors) and checked["studio_mirrors"] == expected_mirrors
                   and checked["studio_mirror_count"] == len(expected_mirrors),
                   "incoming Studio license mirror output differs")
        original_commit = "0e03878b028ec25ed3d84a790633433eafc3bede"
        notice = licenses + "/notices/de_core_news_sm-LICENSES_SOURCES"
        original = subprocess.check_output(["git", "show", original_commit + ":" + notice], cwd=self.repo)
        current = self.identity(self.repo / notice)
        blob = hashlib.sha1(b"blob " + str(len(original)).encode() + b"\0" + original).hexdigest()
        origin_sha = hashlib.sha256(original).hexdigest()
        self.check(origin_sha == current["sha256"] and blob == current["git_blob"],
                   "imported license notice bytes differ from their original Git source")
        self.check(checked["raw_notice_provenance"] == {
            "path": notice, "origin_commit": original_commit, "origin_git_blob": blob,
            "retained_git_blob": current["git_blob"], "origin_sha256": origin_sha,
            "retained_sha256": current["sha256"], "bytes": current["bytes"],
            "exact_original_bytes_preserved": True,
        }, "incoming raw license provenance output differs")
        self.check(receipt["test_counts"] == {"passed": 0, "failed": 0, "skipped": 0},
                   "static checks must not contribute test-case counts")
        return {"test_counts": {"passed": 0, "failed": 0, "skipped": 0}, "commands": reports,
                "verified_notices": len(expected_notices), "verified_studio_mirrors": len(expected_mirrors)}

    def audit_spacy(self, folder, receipt):
        names = ["tests", "analysis", "format", "web-compile", "web-run"]
        self.check([c["name"] for c in receipt["commands"]] == names,
                   "incoming spaCy required command inventory differs")
        reports, paths_by_name = [], {}
        for record in receipt["commands"]:
            self.check(read_json(folder / (record["name"] + ".json")) == record,
                       "incoming spaCy original command record differs: " + record["name"])
            detail, paths = self.command(folder, record, record["name"])
            reports.append(detail)
            paths_by_name[record["name"]] = paths
        package = self.repo / "packages/quds_proofing_spacy"
        studio = self.repo / "packages/quds_office_editor/example"
        discovered = sorted(str(p.relative_to(package)) for p in (package / "test").rglob("*_test.dart"))
        planned = read_json(self.workspace / "runtime/incoming-test-plan.json")["spacy_tests"]
        selected = [p for p in reports[0]["argv"] if p.endswith("_test.dart")]
        self.check(discovered == planned == selected == receipt["test_selection"],
                   "incoming spaCy test inventory differs from independent discovery")
        self.check(all(c["cwd"] == str(package) for c in reports[:3])
                   and all(c["cwd"] == str(studio) for c in reports[3:]),
                   "incoming spaCy working directories differ")
        parsed = self.parse_tests(paths_by_name["tests"]["stdout"], package,
                                  ["packages/quds_proofing_spacy/" + p for p in selected])
        self.incoming_test_summary(parsed, read_json(folder / "test-summary.json"), "incoming spaCy tests")
        self.incoming_test_summary(parsed, receipt["summary"], "incoming spaCy receipt")
        reports[0].update({k: v for k, v in parsed.items() if k != "cases"})
        analysis_targets = ["lib", "test"]
        self.check(receipt["analysis_targets"] == analysis_targets
                   and read_json(self.workspace / "runtime/incoming-test-plan.json")["spacy_analysis_targets"] == analysis_targets
                   and reports[1]["argv"][1:] == ["analyze", "--fatal-infos", "--fatal-warnings", *analysis_targets],
                   "incoming spaCy strict library/test analysis command differs")
        formatted = ["lib/src/installer_io.dart", "lib/src/native_backend.dart",
                     "lib/src/native_backend_unsupported.dart", "test/ner_removal_test.dart"]
        self.check(receipt["format_targets"] == formatted
                   and reports[2]["argv"][1:] == ["format", "--output=none", "--set-exit-if-changed", *formatted],
                   "incoming spaCy format target inventory differs")
        generated = receipt["generated_javascript"]
        artifact = folder / "studio_spacy_web_import_gate.js"
        self.check(generated["path"] == str(artifact), "incoming spaCy generated JavaScript path differs")
        self.match(artifact, generated, "incoming spaCy generated JavaScript")
        self.check(reports[3]["argv"][1:] == [
            "compile", "js", "-O1", "test/studio_spacy_web_import_gate.dart", "-o", str(artifact),
        ], "incoming spaCy portable gate compile command differs")
        self.check(reports[4]["argv"][1:] == [
            "-e", "globalThis.self = globalThis; require(" + json.dumps(str(artifact)) + ");",
        ], "incoming spaCy portable gate invocation differs")
        expected_output = "Local text analysis is unavailable in this browser."
        actual_output = paths_by_name["web-run"]["stdout"].read_text().strip()
        self.check(actual_output == expected_output and receipt["web_assertion"] == {
            "required_output": expected_output, "actual_output": expected_output, "passed": True,
        }, "incoming spaCy unsupported-browser output differs")
        return {"test_counts": parsed["counts"], "commands": reports, "javascript_programs": 1,
                "portable_gate_output": actual_output}

    def audit_incoming(self, inventory_path):
        inventory = read_json(inventory_path)
        root = inventory_path.parent
        self.check(inventory.get("status") == "passed", "incoming inventory is not passed")
        groups = inventory["accepted_groups"]
        expected_groups = {
            "engine": "engine", "slide-parser": "commands",
            "editor": "ui-tests", "studio": "ui-tests",
            "editor-analysis": "commands", "studio-analysis": "commands",
            "spacy": "spacy", "static": "static",
        }
        self.check({g["name"]: g["kind"] for g in groups} == expected_groups
                   and len(groups) == len(expected_groups), "incoming required accepted group inventory differs")
        paths = {g["path"] for g in groups}
        excluded = inventory["excluded_groups"]
        self.check(not paths.intersection(g["path"] for g in excluded), "incoming accepted/excluded groups overlap")
        self.check(all(g.get("reason") for g in excluded), "incoming excluded group has no reason")
        window = root / inventory["window"]
        before, after = read_json(window / "before.json"), read_json(window / "after.json")
        self.window_start = datetime.fromisoformat(before["captured_at_utc"])
        self.window_end = datetime.fromisoformat(after["captured_at_utc"])
        self.check(self.window_start < self.window_end, "incoming capture window ordering invalid")
        self.check(after.get("success") is True, "incoming input window was not stable")
        self.check(before["environment"] == after["environment"] and before["sqlite"] == after["sqlite"], "incoming environment/native asset changed")
        self.check(before["sqlite"]["sha256"] == SQLITE_SHA256, "incoming native asset differs")
        frozen_tree = self.tree(before["head"])
        self.check(self.git("rev-parse", before["head"] + "^{tree}").strip() == before["tree"], "incoming source tree differs")
        self.check(subprocess.run(["git", "merge-base", "--is-ancestor", before["head"], self.current_head], cwd=self.repo).returncode == 0,
                   "current HEAD does not contain incoming window source")
        bound = {}
        for stem, kind in (("source", "source"), ("dependencies", "dependency"), ("runtime", "runtime"), ("harnesses", "workspace")):
            bound[stem] = self.bind_inputs(window / (stem + "-before.json.gz"), window / (stem + "-after.json.gz"), kind,
                                            frozen_tree=frozen_tree if kind == "source" else None)
            self.check(bound[stem]["inputs"] == before["counts"][stem] == after["counts"][stem], "incoming window count differs: " + stem)
        self.check(self.source_selection() - DOCUMENT_INPUTS <= set(read_json(window / "source-before.json.gz")),
                   "incoming full product source input inventory is incomplete")
        self.check(set(read_json(window / "dependencies-before.json.gz")) == self.dependency_selection(),
                   "incoming full external dependency inventory is incomplete")
        self.match(window / "executed-capture.py", before["executed_capture_sha256"], "incoming executed capture")
        self.check(before["executed_capture_sha256"] == after["executed_capture_sha256"], "incoming capture script changed")
        reports, total = [], collections.Counter()
        for group in groups:
            folder = root / group["path"]
            receipt = read_json(folder / "receipt.json")
            self.check(receipt.get("success") is True, str(folder) + ": unsuccessful group receipt")
            runner = root / group["executed_runner"]
            runner_key = str(runner.relative_to(self.workspace))
            self.check(runner_key in read_json(window / "harnesses-before.json.gz"),
                       str(folder) + ": executed harness is not bound to the final window")
            self.match(folder / "executed-runner.py", self.identity(runner), str(folder) + ": executed harness")
            if "executed_runner" in receipt:
                self.match(runner, receipt["executed_runner"], str(folder) + ": harness receipt")
            elif "executed_runner_sha256" in receipt:
                self.match(runner, receipt["executed_runner_sha256"], str(folder) + ": harness receipt")
            binding = self.incoming_bindings(folder, receipt, frozen_tree)
            if group["name"] == "static":
                detail = self.audit_static(folder, receipt)
            elif group["name"] == "spacy":
                detail = self.audit_spacy(folder, receipt)
            elif group["kind"] == "engine":
                detail = self.audit_engine(folder, receipt)
            elif group["kind"] == "ui-tests":
                detail = self.audit_ui_tests(folder, receipt)
            elif group["kind"] == "commands":
                detail = self.audit_commands(folder, receipt)
            else:
                self.check(False, "unknown incoming group kind: " + str(group["kind"]))
                continue
            total.update(detail["test_counts"])
            reports.append({"name": group["name"], "path": group["path"], "bound_inputs": binding, **detail})
        return {"inventory_sha256": self.identity(inventory_path)["sha256"], "window_inputs": bound,
                "test_counts": dict(total), "groups": reports, "excluded_groups": excluded}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--mail", type=Path, required=True)
    parser.add_argument("--reviewed-ui", type=Path, required=True)
    parser.add_argument("--incoming", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("retain the previous audit and use a new output path")
    audit = Audit(args.repo)
    report = {"audited_at_utc": datetime.now(timezone.utc).isoformat(), "current_head": audit.current_head,
              "auditor_sha256": audit.identity(Path(__file__))["sha256"], "github_actions_used": False,
              "tests_rerun": False, "development_tests_added_to_totals": False}
    try:
        script_entry = audit.current_tree.get(SCRIPT)
        report["auditor_committed_at_execution"] = script_entry is not None
        if script_entry is not None:
            audit.git_match(Path(__file__).resolve(), audit.current_tree, "auditor source")
        else:
            report["auditor_publication_note"] = "The exact auditor source and its digest are preserved with the later evidence commit."
        report["mail"] = audit.audit_mail(args.mail.resolve(), args.reviewed_ui.resolve())
        if args.incoming:
            report["incoming"] = audit.audit_incoming(args.incoming.resolve())
    except (OSError, ValueError, KeyError, StopIteration, subprocess.SubprocessError) as error:
        audit.failures.append("audit could not complete: " + repr(error))
    audit.check(audit.git("rev-parse", "HEAD").strip() == audit.current_head, "HEAD changed during audit")
    report.update(status="passed" if not audit.failures else "failed", failures=audit.failures,
                  replayed_test_executions=len(audit.case_keys),
                  distinct_case_identities=len(set(audit.case_keys)), distinct_test_files=len(audit.test_files))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"status": report["status"], "failures": audit.failures,
                      "replayed_test_executions": len(audit.case_keys), "report": str(args.output)}))
    return 0 if not audit.failures else 1


if __name__ == "__main__":
    raise SystemExit(main())

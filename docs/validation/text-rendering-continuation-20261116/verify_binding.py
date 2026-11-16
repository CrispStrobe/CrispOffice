#!/usr/bin/env python3
"""Bind completed local validation evidence to this checkout; never run tests.

Run from any directory:
  python3 docs/validation/text-rendering-continuation-20261116/verify_binding.py

Writes source-binding.json beside this script, including failures, and exits
nonzero on any mismatch. Documentation-only commits are permitted: source bytes
must match the receipts and the captured HEAD, not an assumed final commit ID.
Only local Git reads and file reads are used; there is no network or CI access.
"""

import collections
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


EVIDENCE = Path(__file__).resolve().parent
REPO = EVIDENCE.parents[2]
BASE = "0d19b16e10c6bc8492f47880321df2d9f2561223"
LOCK_SNAPSHOT = "docs/validation/text-rendering-20261116/resolved-dependencies.yaml"
IGNORED_INPUTS = {".dart_tool/package_config.json", "pubspec.lock"}
SHA256 = re.compile(r"[0-9a-f]{64}")
COMMIT = re.compile(r"[0-9a-f]{40}")
COHORT_COMMANDS = {"tests", "analyze", "format"}
POPPLER_COMMANDS = {
    "pdftoppm-version", "pdftotext-version", "source-head",
    "raster-encoded-aliases", "raster-identity-glyph-reference",
    "text-encoded-aliases", "text-word-unicode-aliases",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def git(*args, input_bytes=None, check=True):
    result = subprocess.run(
        ["git", *args], cwd=REPO, input=input_bytes, capture_output=True,
        timeout=60, env=dict(os.environ, GIT_OPTIONAL_LOCKS="0"),
    )
    if check and result.returncode:
        raise RuntimeError(
            "git " + " ".join(args) + ": "
            + result.stderr.decode("utf-8", errors="replace").strip()
        )
    return result


def git_text(*args):
    return git(*args).stdout.decode("utf-8").strip()


def safe_path(directory, name):
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts or not relative.parts:
        raise ValueError("Expected a safe relative path: " + repr(name))
    path = directory / relative
    if not path.resolve().is_relative_to(directory.resolve()):
        raise ValueError("Path resolves outside its evidence/source directory: " + name)
    return path


def tree(revision):
    result = {}
    for entry in git("ls-tree", "-rz", revision).stdout.split(b"\0"):
        if not entry:
            continue
        header, path = entry.split(b"\t", 1)
        mode, kind, oid = header.decode("ascii").split()
        result[path.decode("utf-8")] = {"mode": mode, "kind": kind, "oid": oid}
    return result


def summarize_events(raw):
    events = []
    for line in raw.decode("utf-8", errors="replace").splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict):
            events.append(event)
    starts = {
        event["test"]["id"]: event["test"]
        for event in events if event.get("type") == "testStart"
    }
    outcomes = collections.Counter()
    failures, skipped = [], []
    for event in events:
        if event.get("type") != "testDone" or event.get("hidden"):
            continue
        outcome = "skipped" if event.get("skipped") else event.get("result", "unknown")
        outcomes[outcome] += 1
        if outcome != "success":
            name = starts.get(event["testID"], {}).get("name", str(event["testID"]))
            (skipped if outcome == "skipped" else failures).append(name)
    done = [event for event in events if event.get("type") == "done"]
    return {
        "outcomes": dict(outcomes), "failures": failures, "skipped": skipped,
        "errors": [event for event in events if event.get("type") == "error"],
        "runner_success": bool(done and done[-1].get("success")),
    }


class Binder:
    def __init__(self):
        self.files = {}
        self.blobs = {}
        self.sources = {}
        self.receipts = {}
        self.head = git_text("rev-parse", "HEAD")
        self.head_tree = tree(self.head)
        self.base_tree = tree(BASE)
        self.report = {
            "schema": "quds-text-rendering-source-binding-v1",
            "started_utc": now(),
            "head": self.head,
            "tree": git_text("rev-parse", self.head + "^{tree}"),
            "branch": git_text("rev-parse", "--abbrev-ref", "HEAD"),
            "integrated_base": BASE,
            "verifier_sha256": sha(self.read(Path(__file__))),
            "checks": [],
            "mismatches": [],
            "receipts": {},
            "actual_test_outcomes": {},
            "github_actions_used": False,
            "network_used": False,
            "tests_run_by_verifier": False,
            "limits": [
                "Binds recorded local validation to bytes; does not rerun any gate.",
                "Allows a later documentation-only commit when recorded source bytes match.",
                "Ancestry concerns the saved remote observations, not live remote state.",
                "Poppler producer association uses the saved invocation and current artifacts; "
                "the producer receipt has no artifact hashes captured at generation.",
                "Poppler executable metadata may identify a launcher wrapper, not its "
                "downstream native binary; no new executable-identity claim is made.",
            ],
        }

    def read(self, path):
        path = path.resolve()
        if path not in self.files:
            self.files[path] = path.read_bytes()
        return self.files[path]

    def load(self, path):
        data = json.loads(self.read(path))
        if not isinstance(data, dict):
            raise ValueError(str(path) + " must contain a JSON object")
        return data

    def check(self, name, passed, **details):
        record = {"check": name, "passed": bool(passed), **details}
        self.report["checks"].append(record)
        if not passed:
            self.report["mismatches"].append(record)
        return bool(passed)

    def section(self, name, action):
        try:
            action()
        except Exception as exc:
            self.check(name, False, error=type(exc).__name__ + ": " + str(exc))

    def cache_blobs(self, oids):
        missing = sorted(set(oids) - self.blobs.keys())
        if not missing:
            return
        raw = git("cat-file", "--batch",
                  input_bytes=("\n".join(missing) + "\n").encode("ascii")).stdout
        offset = 0
        for oid in missing:
            end = raw.index(b"\n", offset)
            found, kind, size = raw[offset:end].decode("ascii").split()
            if found != oid or kind != "blob":
                raise ValueError("Expected Git blob " + oid)
            offset = end + 1
            size = int(size)
            self.blobs[oid] = raw[offset:offset + size]
            offset += size
            if raw[offset:offset + 1] != b"\n":
                raise ValueError("Truncated Git blob " + oid)
            offset += 1

    def recorded_file(self, directory, name, expected, size=None, decompress=False):
        data = self.read(safe_path(directory, name))
        content = gzip.decompress(data) if decompress else data
        actual = sha(content)
        valid = isinstance(expected, str) and SHA256.fullmatch(expected) is not None
        self.check(
            "file_hash", valid and actual == expected and (size is None or len(content) == size),
            path=str((directory / name).relative_to(REPO)),
            hash_bytes="decompressed gzip content" if decompress else "raw file bytes",
            expected_sha256=expected, actual_sha256=actual,
            expected_bytes=size, actual_bytes=len(content),
        )
        return content

    def expected_cohort_paths(self, cohort, tests):
        paths = set()
        packages = ["quds_office_engine", "legacy_doc_parser"]
        if cohort == "editor":
            packages.append("quds_office_editor")
        for package in packages:
            paths.update((REPO / "packages" / package / "lib").rglob("*.dart"))
        package = REPO / "packages" / ("quds_office_" + cohort)
        paths.update(safe_path(package / "test", test) for test in tests)
        paths.update((package / "test" / "support").rglob("*.dart"))
        paths.update((REPO / "packages/quds_office_editor/fonts").glob("*.ttf"))
        paths.update(REPO.glob("pubspec.*"))
        paths.update((REPO / "packages").glob("*/pubspec.yaml"))
        paths.update((REPO / "apps").glob("*/pubspec.yaml"))
        paths.add(REPO / ".dart_tool/package_config.json")
        return {str(path.relative_to(REPO)) for path in paths if path.is_file()}

    def receipt(self, cohort):
        directory = EVIDENCE / (cohort + "-final")
        receipt = self.load(directory / "receipt.json")
        self.receipts[cohort] = receipt
        self.report["receipts"][cohort] = {
            "path": str((directory / "receipt.json").relative_to(REPO)),
            "sha256": sha(self.read(directory / "receipt.json")),
            "head_before": receipt.get("head_before"),
            "head_after": receipt.get("head_after"),
            "finished_utc": receipt.get("finished_utc"),
        }
        self.check(cohort + "_complete_pass",
                   receipt.get("passed") is True and bool(receipt.get("finished_utc"))
                   and receipt.get("inputs_unchanged") is True
                   and "error" not in receipt)
        before, after = receipt.get("source_before_sha256"), receipt.get("source_after_sha256")
        self.check(cohort + "_source_stable",
                   isinstance(after, dict) and bool(after) and before == after
                   and (cohort != "poppler" or receipt.get("source_unchanged") is True))
        if not isinstance(after, dict) or not after:
            raise ValueError("Missing completed source_after_sha256")
        self.report["receipts"][cohort]["source_count"] = len(after)
        for name, digest in after.items():
            safe_path(REPO, name)
            self.sources.setdefault(name, {})[cohort] = digest
        if cohort != "poppler":
            self.check(cohort + "_identity", receipt.get("cohort") == cohort)
            expected_paths = self.expected_cohort_paths(cohort, receipt["tests"])
            self.check(cohort + "_source_inventory", expected_paths == set(after),
                       missing=sorted(expected_paths - set(after)),
                       unexpected=sorted(set(after) - expected_paths))
        commands = receipt.get("commands", [])
        expected_commands = POPPLER_COMMANDS if cohort == "poppler" else COHORT_COMMANDS
        names = [command.get("name") for command in commands]
        self.check(cohort + "_commands_complete",
                   len(names) == len(expected_commands) and set(names) == expected_commands,
                   observed=names, expected=sorted(expected_commands))
        for command in commands:
            name = command["name"]
            self.check(
                cohort + "_" + name + "_exit",
                type(command.get("exit_code")) is int and command["exit_code"] == 0
                and not command.get("timed_out", False)
                and (cohort != "poppler" or command.get("passed") is True),
                exit_code=command.get("exit_code"), timed_out=command.get("timed_out", False),
            )
            logs = {}
            for stream in ("stdout", "stderr"):
                filename = command[stream]
                logs[stream] = self.recorded_file(
                    directory, filename, command[stream + "_sha256"],
                    decompress=filename.endswith(".gz"),
                )
                if cohort != "poppler":
                    self.check(cohort + "_" + name + "_" + stream + "_gzip",
                               filename.endswith(".gz"))
            if name == "tests":
                observed = summarize_events(logs["stdout"])
                self.report["actual_test_outcomes"][cohort] = observed
                self.check(cohort + "_test_summary_matches",
                           observed == command.get("summary"), observed=observed)
                self.check(
                    cohort + "_all_observed_tests_pass",
                    observed["runner_success"] and observed["outcomes"].get("success", 0) > 0
                    and set(observed["outcomes"]) == {"success"}
                    and not observed["errors"] and not observed["failures"] and not observed["skipped"],
                )
        harness = "verify-pdf-rendering-used.py" if cohort == "poppler" else "validate-used.py"
        self.recorded_file(directory, harness, receipt.get("harness_sha256"))

    def current_sources(self):
        self.check("source_records_present", bool(self.sources))
        paths = set(self.sources)
        self.cache_blobs(
            self.head_tree[name]["oid"] for name in paths if name in self.head_tree
        )
        records = {}
        for name, expected in sorted(self.sources.items()):
            current = self.read(safe_path(REPO, name))
            digest = sha(current)
            valid = all(isinstance(value, str) and SHA256.fullmatch(value)
                        for value in expected.values())
            matches = valid and all(value == digest for value in expected.values())
            self.check("source_receipt_bytes", matches, path=name,
                       expected_sha256=expected, actual_sha256=digest)
            record = {"receipt_sha256": expected, "current_sha256": digest}
            if name in self.head_tree:
                entry = self.head_tree[name]
                committed = self.blobs[entry["oid"]]
                self.check("source_head_bytes", current == committed, path=name,
                           head_sha256=sha(committed), current_sha256=digest)
                record.update({"head_blob": entry["oid"], "head_sha256": sha(committed)})
            else:
                ignored = name in IGNORED_INPUTS and git(
                    "check-ignore", "--quiet", "--", name, check=False
                ).returncode == 0
                self.check("source_expected_ignored_input", ignored, path=name)
                record["expected_ignored_input"] = ignored
            records[name] = record
        self.check("both_ignored_inputs_bound", IGNORED_INPUTS <= paths)
        self.report["source_files"] = records

    def preserved_inputs(self):
        prefix = "packages/quds_office_editor/fonts/"
        categories = {
            "manifests": (9, lambda p: p == "pubspec.yaml" or p.endswith("/pubspec.yaml")),
            "fonts": (14, lambda p: p.startswith(prefix)
                      and Path(p).suffix.lower() in {".ttf", ".otf", ".ttc", ".woff", ".woff2"}),
            "font_notices": (2, lambda p: p.startswith(prefix) and Path(p).name.startswith("LICENSE")),
        }
        records = {}
        selected = {}
        for label, (count, predicate) in categories.items():
            baseline = {p for p in self.base_tree if predicate(p)}
            current = {p for p in self.head_tree if predicate(p)}
            self.check(label + "_inventory", baseline == current and len(baseline) == count,
                       expected_count=count, base_paths=sorted(baseline), head_paths=sorted(current))
            selected[label] = sorted(baseline | current)
        all_paths = {p for paths in selected.values() for p in paths} | {LOCK_SNAPSHOT}
        self.cache_blobs(
            mapping[p]["oid"] for mapping in (self.base_tree, self.head_tree)
            for p in all_paths if p in mapping
        )
        for label, paths in selected.items():
            records[label] = {}
            for name in paths:
                baseline = self.blobs[self.base_tree[name]["oid"]]
                committed = self.blobs[self.head_tree[name]["oid"]]
                current = self.read(safe_path(REPO, name))
                self.check(label + "_bytes", baseline == committed == current, path=name)
                records[label][name] = {
                    "base_blob": self.base_tree[name]["oid"], "head_blob": self.head_tree[name]["oid"],
                    "base_sha256": sha(baseline), "head_sha256": sha(committed),
                    "current_sha256": sha(current),
                }
        lock = self.read(REPO / "pubspec.lock")
        baseline = self.blobs[self.base_tree[LOCK_SNAPSHOT]["oid"]]
        committed = self.blobs[self.head_tree[LOCK_SNAPSHOT]["oid"]]
        self.check("root_lock_matches_committed_snapshot", lock == baseline == committed)
        records["root_lock"] = {
            "path": "pubspec.lock", "tracking": "ignored input, not a tracked Git lockfile",
            "snapshot_path": LOCK_SNAPSHOT, "snapshot_revision": BASE,
            "snapshot_blob": self.base_tree[LOCK_SNAPSHOT]["oid"],
            "current_sha256": sha(lock), "snapshot_sha256": sha(baseline),
        }
        self.report["preserved_inputs"] = records

    def runtime(self):
        directory = EVIDENCE / "runtime"
        manifest = self.load(directory / "MANIFEST.json")
        manifest_path = str((directory / "MANIFEST.json").relative_to(REPO))
        manifest_entry = self.head_tree.get(manifest_path)
        if manifest_entry is not None:
            self.cache_blobs([manifest_entry["oid"]])
        self.check(
            "runtime_manifest_matches_head",
            manifest_entry is not None
            and self.read(directory / "MANIFEST.json") == self.blobs[manifest_entry["oid"]],
            path=manifest_path,
        )
        present = {str(p.relative_to(directory)) for p in directory.rglob("*") if p.is_file()}
        self.check("runtime_bundle_inventory",
                   len(manifest) == 39 and present == set(manifest) | {"MANIFEST.json"},
                   payload_count=len(manifest), bundle_file_count=len(present),
                   missing=sorted((set(manifest) | {"MANIFEST.json"}) - present),
                   unexpected=sorted(present - (set(manifest) | {"MANIFEST.json"})))
        verified = {}
        for name, digest in sorted(manifest.items()):
            data = self.recorded_file(directory, name, digest)
            verified[name] = {"sha256": sha(data), "bytes": len(data)}
        runtime = self.load(directory / "runtime.json")
        self.check("runtime_ready", runtime.get("status") == "ready"
                   and bool(runtime.get("finished_at_utc"))
                   and runtime.get("native_binaries_rebuilt") is False
                   and runtime.get("sdk_source_changes") == [])
        for name, field in (
            ("pubspec.lock", "workspace_lock_sha256"),
            (".dart_tool/package_config.json", "workspace_package_config_sha256"),
        ):
            self.recorded_file(REPO, name, runtime.get(field))
        for command in runtime.get("commands", []):
            self.check("runtime_command_exit", command.get("exit_code") == 0,
                       command=command.get("name"))
            self.recorded_file(directory, command["name"] + ".log", command["log_sha256"])
        self.report["runtime"] = {
            "manifest_path": manifest_path,
            "manifest_head_blob": manifest_entry["oid"] if manifest_entry else None,
            "manifest_sha256": sha(self.read(directory / "MANIFEST.json")),
            "payload_count": len(manifest), "bundle_file_count": len(present),
            "files": verified, "recorded_actual_runtime": runtime.get("actual_runtime"),
            "recorded_executable_hashes": runtime.get("executable_hashes"),
            "executable_hashes_recomputed_by_this_verifier": False,
        }

    def poppler_artifacts(self):
        receipt = self.receipts["poppler"]
        directory = EVIDENCE / "poppler-final"
        before, after = receipt.get("inputs_before"), receipt.get("inputs_after")
        names = {
            "encoded-aliases.pdf", "identity-glyph-reference.pdf",
            "word-unicode-aliases.pdf", "authored-text.txt", "producer-receipt.json",
        }
        self.check("poppler_input_inventory",
                   isinstance(after, dict) and set(after) == names and before == after)
        for name in sorted(names):
            record = after[name]
            original = EVIDENCE / "engine-final"
            original_name = "receipt.json" if name == "producer-receipt.json" else "render/" + name
            self.recorded_file(original, original_name, record["sha256"], record["bytes"])
            self.recorded_file(directory, name, record["sha256"], record["bytes"])
        artifacts = receipt.get("artifacts", {})
        self.check("poppler_artifacts_recorded", bool(artifacts))
        for name, record in sorted(artifacts.items()):
            self.recorded_file(directory, name, record["sha256"], record["bytes"])
        checks = receipt.get("checks", {})
        self.check("poppler_final_checks",
                   set(checks) == {"raster", "text"}
                   and all(check.get("passed") is True for check in checks.values()))
        raster = checks["raster"]
        self.check("poppler_exact_raster_result",
                   raster.get("differing_pixels") == 0
                   and all(raster.get(key) is True for key in (
                       "same_dimensions", "expected_dimensions", "rgb_mode", "both_have_ink")))
        authored = self.read(directory / "authored-text.txt").decode("utf-8")
        text_check = checks["text"]
        for name in ("encoded-aliases", "word-unicode-aliases"):
            result = text_check["results"][name]
            raw = self.recorded_file(directory, result["text_file"], result["raw_sha256"])
            actual = raw.decode("utf-8").rstrip("\n\f")
            code_points = [f"U+{ord(char):04X}" for char in actual]
            self.check("poppler_exact_text_result",
                       bool(authored) and actual == authored and result.get("passed") is True
                       and code_points == result.get("compared_code_points")
                       and code_points == text_check.get("expected_code_points"),
                       fixture=name)
        for sample in raster["samples"].values():
            self.recorded_file(directory, sample["png"], sample["png_sha256"])
        self.report["poppler"] = {
            "artifact_count": len(artifacts), "checks": checks,
            "producer_receipt_sha256": sha(self.read(directory / "producer-receipt.json")),
        }

    def ancestry(self):
        path = EVIDENCE / "resume/remote-snapshot.json"
        snapshot = self.load(path)
        refresh_path = EVIDENCE / "incoming-refresh-before-merge.json"
        refresh = self.load(refresh_path)
        refs = snapshot["refs"]
        identity = lambda r: (r["remote"], r["ref"], r["sha"])
        self.check("ref_snapshot_inventory",
                   snapshot.get("total") == 166 and len(refs) == 166
                   and len({(r["remote"], r["ref"]) for r in refs}) == 166)
        self.check("ref_snapshot_matches_refresh",
                   refresh.get("total") == 166 and len(refresh["refs"]) == 166
                   and {identity(r) for r in refs} == {identity(r) for r in refresh["refs"]})
        cache, observed = {}, []
        for ref in refs:
            oid = ref["sha"]
            if not isinstance(oid, str) or COMMIT.fullmatch(oid) is None:
                raise ValueError("Invalid observed commit ID: " + repr(oid))
            if oid not in cache:
                result = git("merge-base", "--is-ancestor", oid, self.head, check=False)
                cache[oid] = {
                    "ancestor": result.returncode == 0, "exit_code": result.returncode,
                    "stderr": result.stderr.decode("utf-8", errors="replace").strip(),
                }
            record = {**ref, **cache[oid]}
            observed.append(record)
            self.check("observed_ref_is_ancestor", record["ancestor"],
                       remote=ref["remote"], ref=ref["ref"], sha=oid,
                       exit_code=record["exit_code"], stderr=record["stderr"])
        self.report["incoming_snapshot"] = {
            "path": str(path.relative_to(REPO)), "sha256": sha(self.read(path)),
            "recorded_at_utc": snapshot.get("recorded_at_utc"), "counts": snapshot.get("counts"),
            "ref_count": len(refs), "unique_commit_count": len(cache),
            "included_ref_count": sum(ref["ancestor"] for ref in observed),
            "refresh_path": str(refresh_path.relative_to(REPO)),
            "refresh_sha256": sha(self.read(refresh_path)),
            "observed_refs": observed,
        }
        result = git("merge-base", "--is-ancestor", BASE, self.head, check=False)
        self.check("integrated_base_is_ancestor", result.returncode == 0)

    def finish(self):
        changed = []
        for path, original in self.files.items():
            try:
                current = path.read_bytes()
                if current != original:
                    changed.append({"path": str(path.relative_to(REPO)),
                                    "before_sha256": sha(original), "after_sha256": sha(current)})
            except OSError as exc:
                changed.append({"path": str(path.relative_to(REPO)), "error": str(exc)})
        self.check("all_read_inputs_stable_during_binding", not changed, changed=changed)
        final_head = git_text("rev-parse", "HEAD")
        self.check("head_stable_during_binding", final_head == self.head,
                   head_before=self.head, head_after=final_head)
        self.report["finished_utc"] = now()
        self.report["passed"] = not self.report["mismatches"]
        self.report["check_count"] = len(self.report["checks"])
        self.report["read_file_count"] = len(self.files)
        output = EVIDENCE / "source-binding.json"
        temporary = output.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(self.report, indent=2) + "\n", encoding="utf-8")
        temporary.replace(output)
        print(json.dumps({
            "passed": self.report["passed"], "head": self.head,
            "test_outcomes": {
                cohort: summary["outcomes"]
                for cohort, summary in self.report["actual_test_outcomes"].items()
            },
            "source_files": len(self.report.get("source_files", {})),
            "observed_refs": self.report.get("incoming_snapshot", {}).get("ref_count"),
            "runtime_files": self.report.get("runtime", {}).get("bundle_file_count"),
            "mismatches": len(self.report["mismatches"]),
            "report": str(output.relative_to(REPO)),
        }))
        return 0 if self.report["passed"] else 1


def main():
    binding = Binder()
    for cohort in ("engine", "editor", "poppler"):
        binding.section(cohort + "_receipt", lambda cohort=cohort: binding.receipt(cohort))
    for name, action in (
        ("current_sources", binding.current_sources),
        ("preserved_inputs", binding.preserved_inputs),
        ("runtime", binding.runtime),
        ("poppler_artifacts", binding.poppler_artifacts),
        ("ancestry", binding.ancestry),
    ):
        binding.section(name, action)
    return binding.finish()


if __name__ == "__main__":
    sys.exit(main())


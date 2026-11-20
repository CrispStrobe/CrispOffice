#!/usr/bin/env python3
"""Run one disjoint local validation cohort with exact-input evidence.

Requires Python 3.11+, PyYAML, git, rg, and an already resolved real Dart
workspace. Source the prepared environment (FLUTTER_ROOT/PUB_CACHE) first.
This runner never resolves packages, modifies source, or contacts GitHub.

Example:
  python3 run_validation.py engine-zotero --repo /path/to/checkout \
      --output /path/to/fresh/evidence/engine-zotero

Use --list to inspect the exact selections without running tests or writing
evidence. Every normal invocation requires a fresh output directory. The
watchdog bounds the entire process; application test timeouts remain unchanged.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
from urllib.parse import unquote, urljoin, urlparse

import yaml


COHORTS = {
    "engine-zotero": {
        "package": "packages/quds_office_engine",
        "patterns": ["*zotero*_test.dart"],
        "additional": [],
        "runner": "dart",
    },
    "editor-zotero": {
        "package": "packages/quds_office_editor",
        "patterns": ["*zotero*_test.dart"],
        "additional": [],
        "runner": "flutter",
    },
    "engine-rendering": {
        "package": "packages/quds_office_engine",
        "patterns": ["slide*_test.dart"],
        "additional": ["office_pdf_export_test.dart", "word_small_caps_test.dart"],
        "runner": "dart",
    },
    "editor-rendering": {
        "package": "packages/quds_office_editor",
        "patterns": ["slide*_test.dart"],
        "additional": [
            "office_dark_slide_test.dart",
            "paint_run_text_unicode_test.dart",
            "word_small_caps_test.dart",
            "word_tab_stops_editor_test.dart",
        ],
        "runner": "flutter",
    },
    "engine-vba": {
        "package": "packages/quds_office_engine",
        "patterns": ["office_vba_*_test.dart", "office_macro_*_test.dart"],
        "additional": [],
        "runner": "dart",
    },
    "mail-host": {
        "package": "packages/quds_office_editor/example",
        "patterns": [],
        "additional": [
            "studio_mail_attachment_test.dart",
            "studio_mail_attachment_loader_test.dart",
            "studio_mail_attachment_compose_test.dart",
            "studio_mail_cloud_test.dart",
            "studio_mail_ews_test.dart",
            "studio_mail_session_test.dart",
            "studio_mail_compose_test.dart",
            "studio_mail_recipients_test.dart",
            "studio_mail_reply_test.dart",
            "studio_mail_threading_test.dart",
            "studio_mail_test.dart",
        ],
        "runner": "flutter",
    },
    "mail-mime": {
        "package": "third_party/enough_mail",
        "patterns": [],
        "additional": [
            "codecs/quoted_printable_mail_codec_test.dart",
            "message_builder_test.dart",
            "quds_portable_mime_test.dart",
            "mail/mail_send_transaction_test.dart",
            "mail/mail_submission_acceptance_test.dart",
            "smtp/smtp_transparency_test.dart",
        ],
        "runner": "dart",
    },
    "mail-transport": {
        "package": "packages/quds_mail_transport",
        "patterns": [],
        "additional": ["cloud_provider_test.dart", "ews_provider_test.dart"],
        "runner": "dart",
    },
    "engine-docx": {
        "package": "packages/quds_office_engine",
        "patterns": [],
        "additional": ["word_extended_revision_test.dart"],
        "runner": "dart",
    },
    "editor-docx": {
        "package": "packages/quds_office_editor",
        "patterns": [],
        "additional": ["word_extended_review_test.dart"],
        "runner": "flutter",
    },
}


def utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def canonical_json(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value: object) -> str:
    return hashlib.sha256(canonical_json(value)).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")


def file_record(path: Path) -> dict:
    size = path.stat().st_size
    sha = hashlib.sha256()
    blob = hashlib.sha1(f"blob {size}\0".encode())
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(chunk)
            blob.update(chunk)
    return {"bytes": size, "sha256": sha.hexdigest(), "git_blob_sha1": blob.hexdigest()}


def git(repo: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", *args], cwd=repo)


def git_head(repo: Path) -> str:
    return git(repo, "rev-parse", "HEAD").decode().strip()


def tracked_paths(repo: Path) -> set[Path]:
    return {
        repo / os.fsdecode(path)
        for path in git(repo, "ls-files", "-z").split(b"\0")
        if path
    }


def head_blobs(repo: Path, head: str) -> dict[str, str]:
    result = {}
    for entry in git(repo, "ls-tree", "-rz", "--full-tree", head).split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, kind, sha = metadata.decode().split()
        if kind == "blob":
            result[os.fsdecode(name)] = sha
    return result


def source_matches_head(repo: Path, head: str, records: dict) -> dict:
    blobs = head_blobs(repo, head)
    missing = [name for name in records if name not in blobs]
    different = [
        name for name, record in records.items()
        if name in blobs and blobs[name] != record["git_blob_sha1"]
    ]
    return {"matches": not missing and not different, "uncommitted_paths": missing, "different_paths": different}


def select_tests(repo: Path, cohort: str) -> list[Path]:
    spec = COHORTS[cohort]
    test_root = repo / spec["package"] / "test"
    selected = set()
    for pattern in spec["patterns"]:
        selected.update(test_root.glob(pattern))
    selected.update(test_root / name for name in spec["additional"])
    if not selected or any(not path.is_file() for path in selected):
        raise RuntimeError(f"Missing or empty test selection for {cohort}")
    return sorted(path.resolve() for path in selected)


def validate_disjoint_selections(repo: Path) -> dict[str, list[str]]:
    selections = {name: select_tests(repo, name) for name in COHORTS}
    owners = {}
    for name, paths in selections.items():
        for path in paths:
            if path in owners:
                raise RuntimeError(f"Cohorts overlap at {path}: {owners[path]} and {name}")
            owners[path] = name
    return {name: [str(path.relative_to(repo)) for path in paths] for name, paths in selections.items()}


def files_under(path: Path) -> set[Path]:
    if path.is_file():
        return {path}
    if not path.is_dir():
        return set()
    if shutil.which("rg"):
        process = subprocess.run(
            ["rg", "--files", "--hidden", "--no-ignore", "-0", str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if process.returncode not in (0, 1):
            raise RuntimeError(process.stderr.decode(errors="replace"))
        return {Path(os.fsdecode(item)) for item in process.stdout.split(b"\0") if item}
    return {item for item in path.rglob("*") if item.is_file()}


def declared_assets(root: Path) -> list[Path]:
    manifest = root / "pubspec.yaml"
    if not manifest.is_file():
        return []
    flutter = (yaml.safe_load(manifest.read_text()) or {}).get("flutter") or {}
    assets = [entry if isinstance(entry, str) else entry["path"] for entry in flutter.get("assets", [])]
    assets.extend(
        font["asset"]
        for family in flutter.get("fonts", [])
        for font in family.get("fonts", [])
    )
    return [(root / name).resolve() for name in assets]


class Inputs:
    def __init__(self, repo: Path, sdk: Path, cohort: str, selected: list[Path]):
        self.repo, self.sdk, self.cohort, self.selected = repo, sdk, cohort, selected
        self.config_path = repo / ".dart_tool/package_config.json"
        self.graph_path = repo / ".dart_tool/package_graph.json"
        self.config = {
            item["name"]: item
            for item in json.loads(self.config_path.read_text())["packages"]
        }
        self.graph = {
            item["name"]: item
            for item in json.loads(self.graph_path.read_text())["packages"]
        }
        self.package_name = yaml.safe_load(
            (repo / COHORTS[cohort]["package"] / "pubspec.yaml").read_text()
        )["name"]
        self.reachable = set()
        queue = [self.package_name, *self.graph[self.package_name].get("devDependencies", [])]
        # The real engine runner is package:test, resolved from this exact graph.
        if COHORTS[cohort]["runner"] == "dart":
            queue.append("test")
        while queue:
            name = queue.pop()
            if name in self.reachable:
                continue
            self.reachable.add(name)
            queue.extend(self.graph[name].get("dependencies", []))
        all_roots = {}
        for name in self.config:
            uri = urlparse(urljoin(self.config_path.as_uri(), self.config[name]["rootUri"]))
            if uri.scheme != "file":
                raise RuntimeError(f"Non-local resolved dependency: {name}")
            all_roots[name] = Path(unquote(uri.path)).resolve()
        self.roots = {name: all_roots[name] for name in self.reachable}
        # Every resolved repository package is fingerprinted, including local
        # path dependencies that are not themselves workspace members.
        self.local = {name: root for name, root in all_roots.items() if root.is_relative_to(repo)}
        self.external = {name: root for name, root in self.roots.items() if not root.is_relative_to(repo)}

    def source(self) -> dict:
        repo = self.repo
        tracked = tracked_paths(repo)
        paths = set(self.selected)
        # Capture every tracked engine/editor source and test, including their
        # fixtures and support files. Generated build/cache trees are excluded.
        relevant = [
            repo / "packages/quds_office_engine/lib",
            repo / "packages/quds_office_engine/test",
            repo / "packages/quds_office_editor/lib",
            repo / "packages/quds_office_editor/test",
        ]
        # Pure-engine small-capital PDF tests intentionally read the editor's
        # committed font assets through a relative path, outside package imports.
        for package in ("quds_office_engine", "quds_office_editor"):
            relevant.extend(declared_assets(repo / "packages" / package))
        for root in self.local.values():
            relevant.extend(root / directory for directory in ("lib", "bin", "test", "tool"))
            relevant.extend(declared_assets(root))
        relevant.append(repo / "packages/quds_office_engine/example/macros")
        relevant_names = {str(root) for root in relevant}
        relevant_prefixes = tuple(name.rstrip(os.sep) + os.sep for name in relevant_names)
        for path in tracked:
            name = str(path)
            if name in relevant_names or name.startswith(relevant_prefixes):
                paths.add(path)
        # All tracked manifests/locks make workspace resolution attribution
        # explicit. Historical evidence copies are not runtime manifests.
        for path in tracked:
            rel = path.relative_to(repo)
            if rel.parts[0] in ("docs", ".git"):
                continue
            if path.name in ("pubspec.yaml", "pubspec.lock", "analysis_options.yaml"):
                paths.add(path)
        return {str(path.relative_to(repo)): file_record(path) for path in sorted(paths)}

    def workspace(self) -> dict:
        return {
            str(path.relative_to(self.repo)): file_record(path)
            for path in [self.config_path, self.graph_path]
        }

    def dependencies(self) -> dict:
        result = {}
        for name, root in sorted(self.external.items()):
            paths = {root / "pubspec.yaml"}
            for directory in [root / "lib", root / "bin", *declared_assets(root)]:
                paths.update(files_under(directory))
            records = {str(path.relative_to(root)): file_record(path) for path in sorted(paths) if path.is_file()}
            result[name] = {
                "root": str(root),
                "file_count": len(records),
                "files": records,
                "inventory_sha256": digest(records),
            }
        return result

    def runtime(self) -> dict:
        names = [
            "bin/flutter",
            "bin/cache/flutter.version.json",
            "bin/cache/dart-sdk/bin/dart",
            "bin/cache/dart-sdk/bin/dartaotruntime",
            "bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot",
            "bin/cache/dart-sdk/bin/snapshots/analysis_server_aot.dart.snapshot",
            "bin/cache/artifacts/engine/linux-x64/flutter_tester",
            "bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill",
            "bin/cache/artifacts/engine/common/flutter_patched_sdk_product/platform_strong.dill",
            "bin/cache/flutter_tools.snapshot",
            "packages/flutter_tools/pubspec.yaml",
            "packages/flutter_tools/pubspec.lock",
        ]
        return {name: file_record(self.sdk / name) for name in names if (self.sdk / name).is_file()}

    def snapshot(self) -> dict:
        # office_pdf_export_test.dart probes these actual host fonts. Record
        # absence as well as bytes so a conditional font path is attributable.
        host_fonts = {}
        if self.cohort == "engine-rendering":
            for name in (
                "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                "/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf",
            ):
                path = Path(name)
                host_fonts[name] = {"present": path.is_file(), **(file_record(path) if path.is_file() else {})}
        return {
            "source": self.source(),
            "workspace": self.workspace(),
            "dependencies": self.dependencies(),
            "runtime": self.runtime(),
            "host_fonts": host_fonts,
        }


def audit_events(path: Path, cwd: Path) -> dict:
    """Recount actual test completions and retain every failure, including loaders."""
    events, parse_errors = [], []
    envelope_count = 0
    with path.open("r", encoding="utf-8", errors="strict") as stream:
        for number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                parse_errors.append({"line": number, "text": line.rstrip()})
                continue
            if isinstance(value, dict) and isinstance(value.get("type"), str):
                events.append(value)
            elif isinstance(value, list) and all(isinstance(item, dict) and "event" in item for item in value):
                envelope_count += 1
            else:
                parse_errors.append({"line": number, "value": value})
    starts_list = [event["test"] for event in events if event["type"] == "testStart"]
    starts = {test["id"]: test for test in starts_list}
    dones = [event for event in events if event["type"] == "testDone"]
    suite_events = [event["suite"] for event in events if event["type"] == "suite"]
    suites = {suite["id"]: suite for suite in suite_events}
    finals = [event for event in events if event["type"] == "done"]
    excluded, real = [], []
    excluded_reasons = Counter()
    missing_start_ids = []
    for done in dones:
        test = starts.get(done["testID"])
        if test is None:
            missing_start_ids.append(done["testID"])
            continue
        name = test.get("name", "")
        reason = (
            "hidden_lifecycle" if done.get("hidden") else
            "loading" if name.startswith("loading ") and test.get("url") is None else
            "group_lifecycle" if name.endswith(("(setUpAll)", "(tearDownAll)")) else
            None
        )
        if reason:
            excluded.append(done)
            excluded_reasons[reason] += 1
        else:
            real.append(done)
    skipped = [
        done for done in real
        if done.get("skipped") or starts[done["testID"]].get("metadata", {}).get("skip")
    ]
    skipped_ids = {done["testID"] for done in skipped}
    passed = [done for done in real if done["result"] == "success" and done["testID"] not in skipped_ids]
    failed = [done for done in real if done["result"] != "success" and done["testID"] not in skipped_ids]
    completion_counts = Counter(done["testID"] for done in dones)
    finished_once = (
        len(starts_list) == len(starts)
        and set(starts) == set(completion_counts)
        and all(count == 1 for count in completion_counts.values())
    )

    def resolved_suite_path(suite: dict) -> str:
        path = suite["path"]
        if path.startswith("file:"):
            return str(Path(unquote(urlparse(path).path)).resolve())
        raw = Path(path)
        return str((raw if raw.is_absolute() else cwd / raw).resolve())

    per_suite = []
    for suite in suite_events:
        ids = {key for key, test in starts.items() if test.get("suiteID") == suite["id"]}
        per_suite.append({
            "id": suite["id"],
            "path": resolved_suite_path(suite),
            "passed": sum(done["testID"] in ids for done in passed),
            "failed": sum(done["testID"] in ids for done in failed),
            "skipped": sum(done["testID"] in ids for done in skipped),
        })
    identities = Counter(
        (resolved_suite_path(suites[starts[done["testID"]]["suiteID"]]), starts[done["testID"]]["name"])
        for done in real if starts[done["testID"]].get("suiteID") in suites
    )
    diagnostics = [
        event for event in events
        if event["type"] == "print" and re.search(
            r"A Render\w+ overflowed|would not hit test on the specified widget|does not receive pointer events",
            event.get("message", ""),
        )
    ]
    return {
        "passed": len(passed), "failed": len(failed), "skipped": len(skipped),
        "application_cases": len(real), "suite_count": len(suite_events), "suites": per_suite,
        "test_start_events": len(starts_list), "test_done_events": len(dones),
        "every_started_test_finished_once": finished_once,
        "unfinished_test_ids": sorted(set(starts) - set(completion_counts)),
        "missing_start_test_ids": missing_start_ids,
        "excluded_pseudo_cases": len(excluded), "excluded_reasons": dict(excluded_reasons),
        "excluded_failures": [done for done in excluded if done["result"] != "success" or done.get("skipped")],
        "duplicate_suite_ids": len(suite_events) != len(suites),
        "duplicate_application_names": [
            {"suite": key[0], "name": key[1], "count": count}
            for key, count in identities.items() if count > 1
        ],
        "error_events": [event for event in events if event["type"] == "error"],
        "parse_errors": parse_errors, "final_events": finals,
        "layout_or_tap_diagnostics": diagnostics, "flutter_notification_envelopes": envelope_count,
    }


def changed_paths(before: dict, after: dict) -> dict:
    return {
        area: [
            key for key in sorted(set(before[area]) | set(after[area]))
            if before[area].get(key) != after[area].get(key)
        ]
        for area in before
    }


def compress_file(path: Path) -> Path:
    target = path.with_suffix(path.suffix + ".gz")
    with path.open("rb") as source, target.open("wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as destination:
            shutil.copyfileobj(source, destination)
    path.unlink()
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cohort", choices=COHORTS)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected-head", help="Optionally require this exact commit before starting.")
    parser.add_argument("--timeout", type=int, default=1800, help="Whole-process watchdog seconds; no application timeout changes.")
    parser.add_argument("--list", action="store_true", help="Print the selection and exit without running anything.")
    args = parser.parse_args()
    repo = args.repo.resolve()
    selections = validate_disjoint_selections(repo)
    if args.list:
        print(json.dumps({"cohort": args.cohort, "selected": selections[args.cohort], "all_cohort_counts": {key: len(value) for key, value in selections.items()}}, indent=2))
        return 0
    if args.output is None:
        parser.error("--output is required unless --list is used")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if not os.environ.get("FLUTTER_ROOT") or not os.environ.get("PUB_CACHE"):
        raise RuntimeError("Source the verified runtime environment with FLUTTER_ROOT and PUB_CACHE first.")
    sdk = Path(os.environ["FLUTTER_ROOT"]).resolve()
    pub_cache = Path(os.environ["PUB_CACHE"]).resolve()
    out = args.output.resolve()
    if out.exists():
        raise RuntimeError(f"Evidence directory already exists; choose a new one: {out}")
    out.mkdir(parents=True)
    # All cohorts using this runner share one lock; in particular two Flutter
    # invocations never race on the editor's non-atomic test compiler cache.
    lock = (sdk.parent / "qualified-pure-dart-validation.lock").open("a")
    print("Acquiring the shared local validation lock", flush=True)
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        initial_head = git_head(repo)
        if args.expected_head and initial_head != args.expected_head:
            raise RuntimeError(f"Expected source {args.expected_head}, found {initial_head}")
        selections = validate_disjoint_selections(repo)
        selected = select_tests(repo, args.cohort)
        inputs = Inputs(repo, sdk, args.cohort, selected)
        dart = sdk / "bin/cache/dart-sdk/bin/dart"
        spec = COHORTS[args.cohort]
        cwd = repo / spec["package"]
        files = [str(path.relative_to(cwd)) for path in selected]
        if spec["runner"] == "dart":
            test_root = inputs.roots["test"]
            command = [str(dart), f"--packages={inputs.config_path}", str(test_root / "bin/test.dart"), "--reporter", "json", "--concurrency", "1", *files]
        else:
            command = [str(sdk / "bin/flutter"), "test", "--no-pub", "--reporter", "json", "--concurrency", "1", *files]
        version_command = [str(dart), "--version"]
        dart_version = subprocess.check_output(version_command, stderr=subprocess.STDOUT, text=True).strip()
        flutter_version = json.loads((sdk / "bin/cache/flutter.version.json").read_text())
        print(f"Fingerprinting inputs for {args.cohort}: {len(files)} suites", flush=True)
        before = inputs.snapshot()
        before_matches = source_matches_head(repo, initial_head, before["source"])
        if not before_matches["matches"]:
            write_json(out / "refused-source.json", before_matches)
            raise RuntimeError("Selected source contains bytes not committed at HEAD; refusing a final qualification run.")
        started_at = utc()
        receipt = {
            "status": "running", "cohort": args.cohort, "started_at_utc": started_at,
            "source_head_at_start": initial_head, "package": spec["package"],
            "selected_files": files, "selected_repository_paths": selections[args.cohort],
            "command": command, "cwd": str(cwd), "runner": spec["runner"],
            "concurrency": 1, "watchdog_seconds": args.timeout,
            "application_timeouts_modified": False,
            "runtime": {"dart_version": dart_version, "dart_version_command": version_command, "flutter": flutter_version, "flutter_root": str(sdk), "pub_cache": str(pub_cache)},
            "validation_runner": {"path": str(Path(__file__).resolve()), **file_record(Path(__file__))},
            "no_github_ci_or_status_endpoints": True,
        }
        write_json(out / "receipt.json", receipt)
        (out / "inputs.json.gz").write_bytes(gzip.compress(canonical_json({"before": before, "reachable_packages": sorted(inputs.reachable), "scope": "Tracked libraries, binaries, tests, fixtures, tool sources and declared assets across every resolved repository package; engine macro examples; all current tracked workspace manifests, locks and analysis options; reachable external dependency libraries, binaries and declared assets; exact package configuration, listed runtime files and relevant host fonts."}) + b"\n", mtime=0))
        raw, stderr_path = out / "events.jsonl", out / "stderr.log"
        print(f"Running {args.cohort} with unchanged application timeouts", flush=True)
        start = time.monotonic()
        timed_out = False
        with raw.open("wb") as stdout, stderr_path.open("wb") as stderr:
            process = subprocess.Popen(command, cwd=cwd, env=os.environ.copy(), stdout=stdout, stderr=stderr, start_new_session=True)
            try:
                exit_code = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    exit_code = process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    exit_code = process.wait()
        elapsed = time.monotonic() - start
        print(f"Auditing events and post-run inputs for {args.cohort}", flush=True)
        audit = audit_events(raw, cwd)
        # Re-resolve graph metadata on the second pass, so an altered dependency
        # configuration cannot hide behind the initial graph's root paths.
        after_inputs = Inputs(repo, sdk, args.cohort, select_tests(repo, args.cohort))
        after = after_inputs.snapshot()
        final_head = git_head(repo)
        after_matches = source_matches_head(repo, final_head, after["source"])
        changes = changed_paths(before, after)
        expected_paths = {str(path) for path in selected}
        actual_paths = {suite["path"] for suite in audit["suites"]}
        guards = {
            **{f"{area}_unchanged": not values for area, values in changes.items()},
            "source_matches_start_commit": before_matches["matches"],
            "source_matches_finish_commit": after_matches["matches"],
            "selection_unchanged": selected == select_tests(repo, args.cohort),
            "all_requested_suites_executed_once": expected_paths == actual_paths and len(audit["suites"]) == len(selected) and not audit["duplicate_suite_ids"],
            "every_started_test_finished_once": audit["every_started_test_finished_once"],
            "unique_application_test_names": not audit["duplicate_application_names"],
            "final_event_success": len(audit["final_events"]) == 1 and audit["final_events"][0].get("success") is True,
            "no_failures_skips_or_errors": not any(audit[key] for key in ("failed", "skipped", "error_events", "excluded_failures", "parse_errors", "missing_start_test_ids", "layout_or_tap_diagnostics")),
        }
        passed = exit_code == 0 and not timed_out and audit["passed"] > 0 and all(guards.values())
        after_summary = {
            "before_sha256": {area: digest(records) for area, records in before.items()},
            "after_sha256": {area: digest(records) for area, records in after.items()},
            "changed_paths": changes,
            "source_matches_start": before_matches,
            "source_matches_finish": after_matches,
        }
        write_json(out / "input-check.json", after_summary)
        events_gz = compress_file(raw)
        stderr_gz = compress_file(stderr_path)
        receipt.update({
            "status": "passed" if passed else "failed", "finished_at_utc": utc(),
            "source_head_at_finish": final_head, "head_unchanged": initial_head == final_head,
            "exit_code": exit_code, "timed_out": timed_out, "elapsed_seconds": elapsed,
            "guards": guards, "tests": audit,
            "fingerprints": after_summary,
            "source_file_count": len(before["source"]),
            "external_dependency_file_count": sum(value["file_count"] for value in before["dependencies"].values()),
            "artifacts": {path.name: file_record(path) for path in [events_gz, stderr_gz, out / "inputs.json.gz", out / "input-check.json"]},
            "counting_scope": "Application test cases only. Loader and group-lifecycle events are excluded from the passing count but any failures in them still reject acceptance. Development runs and other cohorts are not included.",
        })
        write_json(out / "receipt.json", receipt)
        print(json.dumps({"cohort": args.cohort, "status": receipt["status"], "passed": audit["passed"], "failed": audit["failed"], "skipped": audit["skipped"], "suites": audit["suite_count"], "exit_code": exit_code, "guards": guards}), flush=True)
        return 0 if passed else 1
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()


COHORTS["spacy-package"] = {
    "package": "packages/quds_proofing_spacy",
    "patterns": ["**/*_test.dart"],
    "additional": [],
    "runner": "dart",
}

COHORTS["engine-macro-serialization"] = {
    "package": "packages/quds_office_engine",
    "patterns": [],
    "additional": [
        "office_macro_cli_test.dart",
        "office_macro_language_test.dart",
        "office_macro_runtime_test.dart",
    ],
    "runner": "dart",
}
COHORTS = {name: COHORTS[name] for name in (
    "engine-rendering", "spacy-package", "engine-macro-serialization"
)}



if __name__ == "__main__":
    sys.exit(main())

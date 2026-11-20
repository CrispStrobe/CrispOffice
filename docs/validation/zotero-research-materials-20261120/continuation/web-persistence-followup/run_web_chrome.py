#!/usr/bin/env python3
"""Run the exact three PR229 Chrome cases, retaining real JSON and exact inputs.

Does not resolve dependencies, fetch sources, install a runtime, alter tests,
or change application timeouts. Requires a published source containing PR229.
"""
from __future__ import annotations
import argparse
from collections import Counter
import fcntl
import gzip
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from web_runner_support import (BROWSER_NAMES, BROWSER_TEST, BROWSER_TEST_SHA256,
                                HERE, PACKAGE, canonical, chromium_inventory,
                                code_records, digest, git, load_primary,
                                mutable_cache_records, record, require_source,
                                sdk_web_records, tree_records, write_json)

COHORT = "web-persistence-chrome"


def snapshot(primary, repo, sdk, selected, binary):
    inputs = primary.Inputs(repo, sdk, COHORT, selected)
    value = inputs.snapshot()
    value["web_sdk_cache"] = sdk_web_records(sdk)
    value["chromium"] = chromium_inventory(binary)["files"]
    value["qualification_tools"] = code_records()
    return inputs, value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected-head")
    parser.add_argument("--chromium-manifest", type=Path, default=HERE / "chromium-baseline.json")
    parser.add_argument("--timeout", type=int, default=1800,
                        help="Whole-process watchdog only; no application timeout changes")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.list:
        print(json.dumps({"selected": [f"{PACKAGE}/{BROWSER_TEST}"], "expected_names": BROWSER_NAMES,
                          "test_sha256": BROWSER_TEST_SHA256, "platform": "chrome"}, indent=2))
        return 0
    if args.output is None or args.expected_head is None:
        parser.error("--output and --expected-head are required")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    repo = args.repo.resolve()
    require_source(repo, args.expected_head)
    for name in ("FLUTTER_ROOT", "PUB_CACHE"):
        if not os.environ.get(name):
            raise RuntimeError(f"Prepared runtime variable is absent: {name}")
    sdk = Path(os.environ["FLUTTER_ROOT"]).resolve()
    out = args.output.resolve()
    if out.exists():
        raise RuntimeError("Use a fresh evidence output directory")
    baseline_path = args.chromium_manifest.resolve()
    baseline = json.loads(baseline_path.read_text())
    binary = Path(baseline["binary"])
    primary = load_primary()
    primary.COHORTS = {COHORT: {"package": PACKAGE, "patterns": [],
                               "additional": [Path(BROWSER_TEST).name], "runner": "flutter"}}
    selected = primary.select_tests(repo, COHORT)
    if record(selected[0])["sha256"] != BROWSER_TEST_SHA256:
        raise RuntimeError("Browser test differs from the captured three-case PR229 source")
    lock = (sdk.parent / "qualified-local-validation.lock").open("a")
    print("Acquiring the shared validation lock for Chrome", flush=True)
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        require_source(repo, args.expected_head)
        current_browser = chromium_inventory(binary)
        if current_browser != baseline["inventory"]:
            raise RuntimeError("Chromium binary/support/shared-library inventory differs from the explicit pin")
        out.mkdir(parents=True)
        profile = out / "browser-profile"
        disk_cache = out / "browser-disk-cache"
        profile.mkdir()
        disk_cache.mkdir()
        launch_config = {"binary": str(binary), "binary_sha256": baseline["inventory"]["binary_sha256"],
                         "profile": str(profile), "disk_cache": str(disk_cache),
                         "launch_log": str(out / "chromium-launches.jsonl")}
        write_json(out / "chromium-launch-config.json", launch_config)
        wrapper = HERE / "chromium_wrapper.py"
        if not os.access(wrapper, os.X_OK):
            raise RuntimeError("The checked-in Chromium wrapper must be executable")
        env = os.environ.copy()
        env.update({"CHROME_EXECUTABLE": str(wrapper),
                    "QUDS_CHROMIUM_LAUNCH_CONFIG": str(out / "chromium-launch-config.json"),
                    "CI": "true", "FLUTTER_SUPPRESS_ANALYTICS": "true", "DART_SUPPRESS_ANALYTICS": "true"})
        cwd = repo / PACKAGE
        events_path = out / "events.jsonl"
        command = [str(sdk / "bin/flutter"), "test", "--no-pub", "--platform", "chrome",
                   "--reporter", "json", "--file-reporter", f"json:{events_path}",
                   "--concurrency", "1", BROWSER_TEST]
        print("Fingerprinting source, dependencies, SDK/web cache and Chromium", flush=True)
        inputs, before = snapshot(primary, repo, sdk, selected, binary)
        matches_before = primary.source_matches_head(repo, args.expected_head, before["source"])
        if not matches_before["matches"]:
            write_json(out / "refused-source.json", matches_before)
            raise RuntimeError("Uncommitted executable inputs differ from the frozen source")
        mutable_before = mutable_cache_records(repo, out)
        write_json(out / "mutable-caches-before.json", mutable_before)
        (out / "inputs.json.gz").write_bytes(gzip.compress(canonical({"before": before,
             "reachable_packages": sorted(inputs.reachable)}) + b"\n", mtime=0))
        receipt = {"status": "running", "cohort": COHORT, "started_at_utc": primary.utc(),
                   "source_head_at_start": args.expected_head, "source_tree": git(repo, "rev-parse", "HEAD^{tree}"),
                   "command": command, "cwd": str(cwd), "selected_repository_paths": [str(selected[0].relative_to(repo))],
                   "expected_case_names": BROWSER_NAMES, "application_timeouts_modified": False,
                   "whole_process_watchdog_seconds": args.timeout, "shared_sdk_validation_lock": str(sdk.parent / "qualified-local-validation.lock"),
                   "primary_runner": {"path": str(primary.__file__), **record(Path(primary.__file__))},
                   "browser_manifest": {"path": str(baseline_path), **record(baseline_path)},
                   "runtime": {"flutter": json.loads((sdk / "bin/cache/flutter.version.json").read_text()),
                               "flutter_root": str(sdk), "pub_cache": os.environ["PUB_CACHE"],
                               "chromium_binary": str(binary)},
                   "event_stream": "Official Flutter --file-reporter json; stdout and stderr also retained without filtering",
                   "github_actions_queried": False}
        write_json(out / "receipt.json", receipt)
        timed_out = False
        start = time.monotonic()
        with (out / "stdout.log").open("wb") as stdout, (out / "stderr.log").open("wb") as stderr:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
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
        print("Auditing real Chrome events and post-run inputs", flush=True)
        _, after = snapshot(primary, repo, sdk, primary.select_tests(repo, COHORT), binary)
        final_head = git(repo, "rev-parse", "HEAD")
        matches_after = primary.source_matches_head(repo, final_head, after["source"])
        changes = primary.changed_paths(before, after)
        mutable_after = mutable_cache_records(repo, out)
        write_json(out / "mutable-caches-after.json", mutable_after)
        event_written = events_path.is_file()
        audit = primary.audit_events(events_path, cwd) if event_written else None
        exact_names = Counter()
        if event_written:
            starts = {}
            for line in events_path.read_text().splitlines():
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue  # Original audit retains and rejects every parse error.
                if not isinstance(event, dict):
                    continue
                if event.get("type") == "testStart":
                    starts[event["test"]["id"]] = event["test"]["name"]
                if event.get("type") == "testDone" and not event.get("hidden"):
                    name = starts.get(event["testID"])
                    if name in BROWSER_NAMES:
                        exact_names[name] += 1
        launch_path = out / "chromium-launches.jsonl"
        launches = [json.loads(line) for line in launch_path.read_text().splitlines()] if launch_path.exists() else []
        guards = {
            **{f"{area}_unchanged": not paths for area, paths in changes.items()},
            "source_matches_start_commit": matches_before["matches"],
            "source_matches_finish_commit": matches_after["matches"],
            "source_head_unchanged_and_exact": final_head == args.expected_head,
            "selection_unchanged": selected == primary.select_tests(repo, COHORT),
            "real_json_file_reporter_stream_present": event_written,
            "pinned_chromium_launched": bool(launches) and all(x["binary_sha256"] == baseline["inventory"]["binary_sha256"] for x in launches),
            "evidence_local_browser_profile": bool(launches) and all(x["profile"] == str(profile) and x["disk_cache"] == str(disk_cache) for x in launches),
            "exact_three_expected_case_names": exact_names == Counter(BROWSER_NAMES),
        }
        if audit is not None:
            guards.update({
                "all_requested_suites_executed_once": {s["path"] for s in audit["suites"]} == {str(selected[0])} and audit["suite_count"] == 1 and not audit["duplicate_suite_ids"],
                "every_started_test_finished_once": audit["every_started_test_finished_once"],
                "unique_application_test_names": not audit["duplicate_application_names"],
                "exact_three_application_passes": audit["passed"] == audit["application_cases"] == 3,
                "final_event_success": len(audit["final_events"]) == 1 and audit["final_events"][0].get("success") is True,
                "no_failures_skips_or_errors": not any(audit[k] for k in ("failed", "skipped", "error_events", "excluded_failures", "parse_errors", "missing_start_test_ids", "layout_or_tap_diagnostics")),
            })
        passed = exit_code == 0 and not timed_out and audit is not None and all(guards.values())
        input_check = {"before_sha256": {k: digest(v) for k, v in before.items()},
                       "after_sha256": {k: digest(v) for k, v in after.items()}, "changed_paths": changes,
                       "source_matches_start": matches_before, "source_matches_finish": matches_after,
                       "mutable_cache_manifests": {"before_sha256": digest(mutable_before), "after_sha256": digest(mutable_after),
                                                   "interpretation": "Compiler output, browser profile and Cache Storage are expected mutable outputs, not immutable executable-input equality guards"}}
        write_json(out / "input-check.json", input_check)
        (out / "inputs-after.json.gz").write_bytes(gzip.compress(canonical(after) + b"\n", mtime=0))
        for path in [events_path, out / "stdout.log", out / "stderr.log"]:
            if path.exists():
                primary.compress_file(path)
        artifact_paths = sorted(p for p in out.iterdir() if p.is_file() and p.name != "receipt.json")
        receipt.update({"status": "passed" if passed else "failed", "finished_at_utc": primary.utc(),
                        "source_head_at_finish": final_head, "head_unchanged": final_head == args.expected_head,
                        "exit_code": exit_code, "timed_out": timed_out, "elapsed_seconds": elapsed,
                        "guards": guards, "tests": audit, "fingerprints": input_check,
                        "chromium_launches": launches,
                        "artifacts": {p.name: record(p) for p in artifact_paths},
                        "counting_scope": "Exactly three fresh browser application cases; lifecycle/loading cases excluded from counts but failures reject acceptance. No native or real-model qualification."})
        write_json(out / "receipt.json", receipt)
        print(json.dumps({"status": receipt["status"], "passed": audit["passed"] if audit else 0,
                          "exit_code": exit_code, "guards": guards}), flush=True)
        return 0 if passed else 1
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()


if __name__ == "__main__":
    sys.exit(main())

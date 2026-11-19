#!/usr/bin/env python3
"""Run a committed local test plan against a frozen source and pinned runtime.

The JSON plan contains `groups` with `name`, repository-relative `cwd`,
`runner` (`dart` or `flutter`), and exact cwd-relative `tests` paths. Optional
`platform` is `vm` (the default) or `node` (Dart groups only). Optional
`analysis` and `format` are lists of repository paths, or "changed". Optional
`extra_inputs` lists tracked fixtures to bind. `whitespace_preserved_inputs`
binds exact validation evidence blobs excluded from whitespace normalization.
All groups run sequentially.
This runner never installs dependencies or contacts GitHub/GitHub Actions.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import urljoin, urlsplit
from urllib.request import url2pathname


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def repository_root() -> Path:
    for candidate in Path(__file__).resolve().parents:
        if (candidate / "pubspec.yaml").is_file() and (
            candidate / "packages/quds_office_editor"
        ).is_dir():
            return candidate
    raise RuntimeError("Runner must be inside the repository")


def parse_reporter(log: Path, cwd: Path, requested: list[str]) -> dict:
    """Count completed user cases, retaining every error and protocol anomaly."""
    # Share the separately regression-tested stream/exit qualification contract.
    # Suite accounting below additionally proves that every requested file ran.
    sys.path.insert(0, str(repository_root() / "tools/mail"))
    from check_store import test_summary

    strict = test_summary(log)
    suites, started, completed, cases, errors, anomalies = {}, {}, set(), [], [], []
    excluded = Counter()
    start_events = terminal_events = 0
    reporter_success = None
    expected = {str((cwd / name).resolve()) for name in requested}
    for line_number, line in enumerate(log.read_text(errors="replace").splitlines(), 1):
        # Native build hooks may print progress immediately before a JSON event.
        # Ordinary prose is allowed, but a malformed event must not disappear.
        brace = line.find("{")
        if brace < 0:
            continue
        try:
            event = json.loads(line[brace:])
        except ValueError:
            anomalies.append({"line": line_number, "malformed_json": True})
            continue
        if not isinstance(event, dict):
            anomalies.append({"line": line_number, "non_object_event": True})
            continue
        kind = event.get("type")
        if not isinstance(kind, str):
            anomalies.append({"line": line_number, "missing_event_type": True})
            continue
        if terminal_events:
            anomalies.append({"line": line_number, "event_after_done": kind})
        if kind == "start":
            start_events += 1
            if start_events != 1:
                anomalies.append({"line": line_number, "duplicate_runner_start": True})
        elif start_events != 1:
            anomalies.append({"line": line_number, "event_without_runner_start": kind})
        try:
            if kind == "suite":
                suite = event["suite"]
                if (not isinstance(suite, dict) or type(suite.get("id")) is not int
                        or not isinstance(suite.get("path"), str)):
                    raise ValueError("Invalid suite payload")
                if suite["id"] in suites:
                    anomalies.append({"line": line_number, "duplicate_suite": suite["id"]})
                suites[suite["id"]] = str((cwd / suite["path"]).resolve())
            elif kind == "testStart":
                case = event["test"]
                if (not isinstance(case, dict) or type(case.get("id")) is not int
                        or type(case.get("suiteID")) is not int
                        or not isinstance(case.get("name"), str)):
                    raise ValueError("Invalid test start payload")
                ident = case["id"]
                if ident in started or ident in completed:
                    anomalies.append({"line": line_number, "duplicate_start": ident})
                    continue
                started[ident] = case
            elif kind == "testDone":
                ident = event["testID"]
                if (type(ident) is not int or type(event.get("skipped")) is not bool
                        or type(event.get("hidden", False)) is not bool
                        or event.get("result") not in {"success", "failure", "error"}):
                    raise ValueError("Invalid test completion payload")
                case = started.pop(ident, None)
                if case is None or ident in completed:
                    anomalies.append({"line": line_number, "unmatched_completion": ident})
                    continue
                completed.add(ident)
                name = case["name"]
                if event.get("hidden") or name.startswith("loading ") or re.search(
                    r"(?:^| )\((?:setUpAll|tearDownAll)\)$", name
                ):
                    excluded["hidden" if event.get("hidden") else "setup_loading_teardown"] += 1
                    if event.get("result") != "success" and not event.get("skipped"):
                        anomalies.append({"line": line_number, "failed_hidden_event": name})
                    continue
                suite_path = suites.get(case["suiteID"])
                if suite_path is None:
                    anomalies.append({"line": line_number, "unknown_suite": case["suiteID"]})
                result = event["result"]
                if result not in {"success", "failure", "error"}:
                    anomalies.append({"line": line_number, "unknown_result": result})
                cases.append({
                    "id": ident, "name": name, "suite": suite_path,
                    "result": result, "skipped": bool(event["skipped"]),
                })
            elif kind == "error":
                errors.append(event)
            elif kind == "done":
                terminal_events += 1
                if terminal_events != 1:
                    anomalies.append({"line": line_number, "duplicate_done": True})
                reporter_success = event["success"]
                if type(reporter_success) is not bool:
                    raise ValueError("Invalid terminal success flag")
        except (KeyError, TypeError, ValueError) as error:
            anomalies.append({"line": line_number, "malformed_event": repr(error)})
    per_suite = {}
    for case in cases:
        suite = case["suite"]
        count = per_suite.setdefault(suite, {"passed": 0, "failed": 0, "skipped": 0})
        count["passed"] += int(case["result"] == "success" and not case["skipped"])
        count["failed"] += int(case["result"] in {"error", "failure"})
        count["skipped"] += int(case["skipped"])
    observed = set(suites.values())
    return {
        "passed": sum(row["passed"] for row in per_suite.values()),
        "failed": sum(row["failed"] for row in per_suite.values()),
        "skipped": sum(row["skipped"] for row in per_suite.values()),
        "per_suite": per_suite, "excluded_events": dict(excluded),
        "reporter_success": reporter_success,
        "runner_start_events": start_events, "terminal_events": terminal_events,
        "missing_requested_suites": sorted(expected - observed),
        "unexpected_suites": sorted(observed - expected),
        "empty_requested_suites": sorted(expected - set(per_suite)),
        "unfinished_reporter_events": list(started.values()),
        "reporter_error_count": len(errors), "protocol_anomalies": anomalies,
        "strict_event_accounting": {key: value for key, value in strict.items() if key != "cases"},
        "cases": cases, "errors": errors,
    }


def reporter_passed(result: dict) -> bool:
    return (result.get("strict_event_accounting", {}).get("valid") is True
            and result.get("reporter_success") is True
            and result.get("runner_start_events") == 1 and result.get("terminal_events") == 1
            and not any(result.get(key) for key in (
        "failed", "skipped", "missing_requested_suites", "unexpected_suites",
        "empty_requested_suites", "unfinished_reporter_events",
        "reporter_error_count", "protocol_anomalies",
    )))


def resolve_test_launcher(repo: Path, runtime: Path, retained: dict) -> tuple[Path, Path]:
    """Resolve package:test only from this workspace's verified hosted cache."""
    config = (repo / ".dart_tool/package_config.json").resolve()
    packages = json.loads(config.read_text())["packages"]
    matches = [package for package in packages if package.get("name") == "test"]
    if len(matches) != 1 or not isinstance(matches[0].get("rootUri"), str):
        raise RuntimeError("Package configuration must identify exactly one test package")
    uri = urlsplit(urljoin(config.as_uri(), matches[0]["rootUri"]))
    if uri.scheme != "file" or uri.netloc or uri.query or uri.fragment:
        raise RuntimeError("The test package must use an unambiguous local file URI")
    root = Path(url2pathname(uri.path)).resolve()
    hosted = (runtime / "pub-cache/hosted/pub.dev").resolve()
    archives = json.loads((runtime / "pub-cache-receipt.json").read_text())
    versions = {
        item["version"] for item in archives
        if item.get("name") == "test" and item.get("verified") is True
        and isinstance(item.get("version"), str)
        and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][a-zA-Z0-9.-]+)?", item["version"])
    }
    if len(versions) != 1 or root.parent != hosted or root.name != "test-" + next(iter(versions)):
        raise RuntimeError("The test package root differs from its verified hosted archive")
    entrypoint = root / "bin/test.dart"
    if entrypoint.resolve() != entrypoint or not entrypoint.is_file():
        raise RuntimeError("The verified test launcher is missing or redirected")
    name = entrypoint.relative_to(runtime.resolve()).as_posix()
    if name not in retained or sha256(entrypoint) != retained[name]["sha256"]:
        raise RuntimeError("The test launcher is not bound by the retained runtime manifest")
    return config, entrypoint


def additional_runtime_inputs(
    receipt: dict, repo: Path, groups: list[dict], *, node_executable: str | None,
) -> tuple[dict[str, Path], dict[str, Path]]:
    """Bind external/native inputs and observe absent nearer native mappings."""
    recorded = receipt.get("additional_inputs", {})
    if not isinstance(recorded, dict):
        raise RuntimeError("additional_inputs must map absolute paths to SHA-256 values")
    bound = {}
    for name, expected in recorded.items():
        path = Path(name)
        if (not path.is_absolute() or not isinstance(expected, str)
                or not re.fullmatch(r"[0-9a-f]{64}", expected)
                or not path.is_file() or sha256(path) != expected):
            raise RuntimeError("Additional runtime input is missing or changed: " + name)
        bound[str(path)] = path
    if any(group.get("platform", "vm") == "node" for group in groups):
        if node_executable is None or str(Path(node_executable).resolve()) not in bound:
            raise RuntimeError("A Node group requires the actual Node executable in additional_inputs")

    manifest = repo / ".dart_tool/native_assets.yaml"
    optional = {"workspace/native_assets.yaml": manifest}
    if manifest.exists():
        if str(manifest) not in bound:
            raise RuntimeError("The workspace native-assets mapping is not bound")
        # Dart writes a JSON-compatible mapping after explanatory YAML comments.
        content = "\n".join(
            line for line in manifest.read_text().splitlines()
            if not line.lstrip().startswith("#")
        )
        mappings = json.loads(content)["native-assets"]
        for assets in mappings.values():
            for location in assets.values():
                if (not isinstance(location, list) or len(location) != 2
                        or location[0] != "absolute" or location[1] not in bound):
                    raise RuntimeError("A referenced native asset is not an absolute bound input")
    for group in groups:
        directory = (repo / group["cwd"]).resolve()
        directory.relative_to(repo)
        while directory != repo:
            candidate = directory / ".dart_tool/native_assets.yaml"
            name = "workspace/" + candidate.relative_to(repo).as_posix()
            optional[name] = candidate
            if candidate.exists() or candidate.is_symlink():
                raise RuntimeError("Package-local native-assets mapping shadows the workspace: " + str(candidate))
            directory = directory.parent
    return {"additional/" + name: path for name, path in bound.items()}, optional


def test_command(
    runtime: Path, group: dict, *, package_config: Path, test_entrypoint: Path,
) -> list[str]:
    runner = group["runner"]
    platform = group.get("platform", "vm")
    if runner not in {"dart", "flutter"} or platform not in {"vm", "node"}:
        raise ValueError("Unsupported test runner/platform")
    if runner == "flutter" and platform != "vm":
        raise ValueError("This gate supports Flutter VM tests only")
    if runner == "flutter":
        command = [str(runtime / "bin/flutter"), "test", "--no-pub"]
    else:
        command = [str(runtime / "bin/dart"), "--disable-dart-dev",
                   "--packages=" + str(package_config), str(test_entrypoint),
                   "--compiler=kernel" if platform == "vm" else "--platform=node"]
    command.extend(["--concurrency=1", "--reporter=json", *group["tests"]])
    return command


PINNED_UPSTREAM_NOTICE_BLOBS = {
    # Hunspell 1.7.2 verbatim notices, verified against its pinned release archive
    # and packages/quds_proofing_hunspell/licenses/manifest.json. Only these exact
    # blobs may preserve upstream whitespace outside captured validation evidence.
    "packages/quds_proofing_hunspell/licenses/upstream/COPYING.MPL":
        "7714141d154290f53e9e60c615a8edc9b51a8df7",
    "packages/quds_proofing_hunspell/licenses/upstream/license.hunspell":
        "fad5a162300e7d1719ff6b7ba3713aaaa501a4bc",
    "packages/quds_proofing_hunspell/licenses/upstream/license.myspell":
        "2da533075026777f93882fdeb11ff02a711d4b81",
}


def validate_whitespace_preserved_inputs(entries: object, tracked: dict) -> list[dict]:
    """Allow frozen evidence and three pinned upstream notices; no glob exclusions."""
    if not isinstance(entries, list):
        raise RuntimeError("whitespace_preserved_inputs must be an explicit list")
    validated, seen = [], set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise RuntimeError("Each whitespace exception must identify a path, blob and reason")
        path, blob, reason = (entry.get(key) for key in ("path", "git_blob", "reason"))
        if (not isinstance(path, str)
                or not re.fullmatch(r"[a-zA-Z0-9_./-]+", path)
                or Path(path).as_posix() != path or ".." in Path(path).parts
                or path in seen or path not in tracked
                or tracked[path].get("mode") not in {"100644", "100755"}):
            raise RuntimeError("Whitespace exceptions must name unique tracked regular files")
        pinned_notice = PINNED_UPSTREAM_NOTICE_BLOBS.get(path)
        if pinned_notice is not None:
            if blob != pinned_notice:
                raise RuntimeError("Pinned upstream notice bytes changed")
        elif not path.startswith("docs/validation/"):
            raise RuntimeError("Only frozen validation evidence and pinned upstream notices may preserve whitespace")
        suffix = Path(path).suffix
        if pinned_notice is None and suffix not in {".log", ".txt", ".patch"} and not (
            suffix == ".md" and "notices" in Path(path).parts
        ):
            raise RuntimeError("Only captured logs, raw patches and upstream notices may preserve whitespace")
        if (not isinstance(blob, str) or blob != tracked[path]["git_blob"]
                or not isinstance(reason, str) or not reason.strip()):
            raise RuntimeError("Whitespace exception blob changed or its preservation reason is missing")
        seen.add(path)
        validated.append({"path": path, "git_blob": blob, "reason": reason})
    return validated


def whitespace_command(base: str, head: str, preserved: list[dict]) -> list[str]:
    # Every exception is an exact validated evidence or upstream notice blob,
    # including raw patches with context spaces, bound by the source manifests.
    return ["git", "diff", "--check", base, head, "--", ".",
            *[":(exclude)" + entry["path"] for entry in preserved]]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--command-timeout", type=int, default=1800)
    args = parser.parse_args()
    repo, runtime, output = repository_root(), args.runtime.resolve(), args.output.resolve()
    if args.command_timeout <= 0:
        parser.error("--command-timeout must be positive")
    # The Mail runner already regression-tests complete process-group cleanup.
    # Reuse it for compiler/test children, including interrupted socket fixtures.
    sys.path.insert(0, str(repo / "tools/mail"))
    from check_store import execute

    plan_path = args.plan.resolve()
    if output == repo or repo in output.parents:
        raise RuntimeError("Write output outside the frozen source checkout")
    if output.exists() and any(output.iterdir()):
        raise RuntimeError("Use an empty output directory; preserve earlier attempts")
    output.mkdir(parents=True, exist_ok=True)
    checks = output / "checks"
    checks.mkdir()

    def git(*argv: str) -> str:
        return subprocess.check_output(["git", "-C", str(repo), *argv], text=True).rstrip("\n")

    def clean() -> bool:
        return not git("status", "--porcelain=v1", "--untracked-files=no")

    def relative(path: Path) -> str:
        return path.resolve().relative_to(repo).as_posix()

    head = git("rev-parse", "--verify", args.head + "^{commit}")
    base = git("rev-parse", "--verify", args.base + "^{commit}")
    if git("rev-parse", "HEAD") != head or not clean():
        raise RuntimeError("HEAD must match --head, with a clean tracked worktree and index")
    tracked = {}
    for entry in git("ls-files", "--stage", "-z").split("\0"):
        if not entry:
            continue
        metadata, path = entry.split("\t", 1)
        mode, blob, stage = metadata.split()
        if stage != "0":
            raise RuntimeError("Unmerged index entry: " + path)
        tracked[path] = {"mode": mode, "git_blob": blob}
    sparse = {row[2:] for row in git("ls-files", "-v", "-z").split("\0") if row.startswith("S ")}
    plan_name = relative(plan_path)
    runner_name = relative(Path(__file__))
    if plan_name not in tracked or runner_name not in tracked:
        raise RuntimeError("Commit both the plan and the runner before an accepted gate")
    plan = json.loads(plan_path.read_text())
    whitespace_preserved = validate_whitespace_preserved_inputs(
        plan.get("whitespace_preserved_inputs", []), tracked,
    )
    groups = plan["groups"]
    if not isinstance(groups, list) or not groups:
        raise RuntimeError("Plan must request at least one test group")
    receipt_path = runtime / "runtime.json"
    receipt = json.loads(receipt_path.read_text())
    if receipt.get("status") != "ready" or not receipt.get("archive", {}).get("verified"):
        raise RuntimeError("A verified, ready runtime receipt is required")
    if sha256(repo / "pubspec.lock") != receipt["workspace_lock_sha256"]:
        raise RuntimeError("Workspace lock differs from the verified runtime")
    sdk = runtime / "flutter"
    for recorded, expected in receipt["executables_sha256"].items():
        path = sdk / Path(recorded).relative_to(Path(receipt["sdk"]))
        if sha256(path) != expected:
            raise RuntimeError("Verified runtime executable changed: " + str(path))
    retained = json.loads((runtime / "retained-inputs.json").read_text())
    package_config, test_entrypoint = resolve_test_launcher(repo, runtime, retained)
    names, requested = set(), []
    for group in groups:
        name, cwd, runner, tests = group["name"], group["cwd"], group["runner"], group["tests"]
        if not re.fullmatch(r"[a-z0-9_-]+", name) or name in names:
            raise RuntimeError("Group names must be unique safe log filenames")
        names.add(name)
        if runner not in {"dart", "flutter"} or not tests or len(tests) != len(set(tests)):
            raise RuntimeError("Invalid runner or empty/duplicate suite list: " + name)
        test_command(runtime, group, package_config=package_config,
                     test_entrypoint=test_entrypoint)  # Validate before any gate runs.
        group_cwd = (repo / cwd).resolve()
        relative(group_cwd)
        for suite in tests:
            suite_path = (group_cwd / suite).resolve()
            path = relative(suite_path)
            if path not in tracked or not suite_path.is_file() or not path.endswith("_test.dart"):
                raise RuntimeError("Requested suite must exist in the frozen tree: " + path)
            requested.append(path)
    if len(requested) != len(set(requested)):
        raise RuntimeError("Do not double-count the same suite across groups")
    changed = [path for path in git(
        "diff", "--name-only", "--diff-filter=ACMRT", "-z", base, head
    ).split("\0") if path.endswith(".dart") and path.startswith(("packages/", "apps/"))]

    def check_paths(value: object) -> list[str]:
        paths = changed if value == "changed" else value
        if not isinstance(paths, list) or any(not isinstance(path, str) for path in paths):
            raise RuntimeError("analysis/format must be path lists or 'changed'")
        for path in paths:
            if path not in tracked or not (repo / path).is_file():
                raise RuntimeError("Check input must be a tracked file: " + path)
        return paths

    analysis = check_paths(plan.get("analysis", "changed"))
    formatting = check_paths(plan.get("format", "changed"))
    selected = {path for path in tracked if path.startswith(("packages/", "apps/", "third_party/"))}
    selected.update(path for path in tracked if "/" not in path and Path(path).suffix in {".yaml", ".lock"})
    selected.update([plan_name, runner_name, "tools/mail/check_store.py",
                     "tools/mail/check_reader.py", *requested, *analysis, *formatting])
    selected.update(plan.get("extra_inputs", []))
    selected.update(entry["path"] for entry in whitespace_preserved)
    for path in selected:
        if path not in tracked:
            raise RuntimeError("Binding input is not tracked: " + path)
        if not (repo / path).is_file() and path not in sparse:
            raise RuntimeError("Non-sparse source input is missing: " + path)
        if path in sparse and not (repo / path).is_file() and path.endswith(('.dart', '.yaml', '.lock')):
            raise RuntimeError("Executable/configuration source cannot be omitted: " + path)
    for path in git("ls-files", "--others", "--exclude-standard", "-z").split("\0"):
        if path.startswith(("packages/", "apps/", "third_party/")):
            raise RuntimeError("Untracked product input could affect the gate: " + path)

    environment_inputs = {"runtime/" + name: runtime / name for name in retained}
    environment_inputs.update({
        "workspace/pubspec.lock": repo / "pubspec.lock",
        "workspace/package_config.json": package_config,
        "sdk/flutter_tools/package_config.json": sdk / "packages/flutter_tools/.dart_tool/package_config.json",
        **{"runtime/" + name: runtime / name for name in [
            "runtime.json", "retained-inputs.json", "pub-cache-receipt.json",
            "cache-omissions.json", "archive-members.json", "env.sh", "bin/dart", "bin/flutter",
        ]},
    })
    env = dict(os.environ)
    env.update(
        PUB_CACHE=str(runtime / "pub-cache"), FLUTTER_ROOT=str(sdk), CI="true",
        DART_SUPPRESS_ANALYTICS="true", FLUTTER_SUPPRESS_ANALYTICS="true",
        DASH__SUPPRESS_ANALYTICS="true", XDG_CONFIG_HOME=str(runtime / "config"),
        XDG_CACHE_HOME=str(runtime / "cache"), XDG_DATA_HOME=str(runtime / "data"),
        TMPDIR=str(runtime / "tmp"), PATH=str(runtime / "bin") + os.pathsep + env.get("PATH", ""),
    )
    additional, optional_environment = additional_runtime_inputs(
        receipt, repo, groups, node_executable=shutil.which("node", path=env["PATH"]),
    )
    environment_inputs.update(additional)
    environment_inputs.update(optional_environment)

    def source_snapshot() -> dict:
        snapshot = {}
        for name in sorted(selected):
            path = repo / name
            snapshot[name] = {
                **tracked[name], "materialized": path.is_file(),
                "sha256": sha256(path) if path.is_file() else None,
                "sparse_omission": not path.is_file() and name in sparse,
            }
        return snapshot

    def environment_snapshot() -> dict:
        return {name: sha256(path) if path.is_file() else None for name, path in sorted(environment_inputs.items())}

    before, env_before = source_snapshot(), environment_snapshot()
    if any(value is None for name, value in env_before.items() if name not in optional_environment):
        raise RuntimeError("A runtime/dependency binding input is missing")
    for path, expected in retained.items():
        if env_before["runtime/" + path] != expected["sha256"]:
            raise RuntimeError("Retained verified runtime input changed: " + path)
    write_json(output / "source-before.json", before)
    write_json(output / "environment-before.json", env_before)
    index_tree = git("write-tree")
    record = {
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_commit": head, "source_tree": git("rev-parse", head + "^{tree}"),
        "source_base": base, "plan": plan_name, "plan_sha256": sha256(plan_path),
        "source_input_count": len(before),
        "materialized_source_inputs": sum(row["materialized"] for row in before.values()),
        "sparse_source_omissions": [name for name, row in before.items() if row["sparse_omission"]],
        "runtime_input_count": len(env_before), "runtime": receipt["runtime"],
        "workspace_lock_sha256": sha256(repo / "pubspec.lock"),
        "runtime_receipt_sha256": sha256(receipt_path),
        "test_launcher": str(test_entrypoint), "package_config": str(package_config),
        "additional_runtime_inputs": receipt.get("additional_inputs", {}),
        "whitespace_preserved_inputs": whitespace_preserved,
        "planned_groups": groups, "analysis_files": analysis, "formatted_files": formatting,
        "tracked_worktree_clean_before": True, "runs": [],
        "github_actions_queried_or_awaited": False,
    }

    def save() -> None:
        write_json(output / "verification.json", record)

    def run(name: str, command: list[str], cwd: Path, suites: list[str] | None = None) -> None:
        print("START " + name, flush=True)
        started_at = time.monotonic()
        log = checks / (name + (".jsonl" if suites is not None else ".log"))
        item = {"name": name, "command": command, "cwd": str(cwd.relative_to(repo)) or "."}
        with log.open("wb") as stream:
            try:
                item["exit_code"] = execute(command, cwd=cwd, env=env, stdout=stream,
                                            timeout=args.command_timeout)
            except (OSError, subprocess.TimeoutExpired) as error:
                item["exit_code"] = 124 if isinstance(error, subprocess.TimeoutExpired) else 127
                item["runner_error"] = repr(error)
                stream.write(("\nRUNNER ERROR: " + repr(error) + "\n").encode())
        item.update(elapsed_seconds=round(time.monotonic() - started_at, 3),
                    log=str(log.relative_to(output)), log_sha256=sha256(log))
        if suites is not None:
            parsed = parse_reporter(log, cwd, suites)
            for kind in ("cases", "errors"):
                detail = checks / (name + "-" + kind + ".json")
                write_json(detail, parsed.pop(kind))
                item[kind + "_file"] = str(detail.relative_to(output))
                item[kind + "_sha256"] = sha256(detail)
            item.update(parsed)
            item["accepted"] = item["exit_code"] == 0 and reporter_passed(parsed)
        else:
            item["accepted"] = item["exit_code"] == 0
        compressed = log.with_suffix(log.suffix + ".gz")
        compressed.write_bytes(gzip.compress(log.read_bytes(), mtime=0))
        item.update(compressed_log=str(compressed.relative_to(output)),
                    compressed_log_sha256=sha256(compressed))
        record["runs"].append(item)
        save()
        print(json.dumps({key: item[key] for key in (
            "name", "exit_code", "elapsed_seconds", "passed", "failed", "skipped", "accepted"
        ) if key in item}), flush=True)

    expected_runs = len(groups) + bool(analysis) + bool(formatting) + 1
    save()
    try:
        for group in groups:
            command = test_command(runtime, group, package_config=package_config,
                                   test_entrypoint=test_entrypoint)
            run(group["name"], command, repo / group["cwd"], group["tests"])
        if analysis:
            run("analysis", [str(runtime / "bin/dart"), "analyze", "--fatal-infos", "--fatal-warnings", *analysis], repo)
        if formatting:
            run("format", [str(runtime / "bin/dart"), "format", "--output=none", "--set-exit-if-changed", *formatting], repo)
        run("whitespace", whitespace_command(base, head, whitespace_preserved), repo)
    except BaseException as error:
        record["runner_error"] = repr(error)
    finally:
        after, env_after = source_snapshot(), environment_snapshot()
        unexpected_native_mappings = [
            str(path) for name, path in optional_environment.items()
            if name != "workspace/native_assets.yaml" and (path.exists() or path.is_symlink())
        ]
        write_json(output / "source-after.json", after)
        write_json(output / "environment-after.json", env_after)
        record.update(
            source_unchanged=before == after, environment_unchanged=env_before == env_after,
            source_mismatches=[name for name in before if before[name] != after[name]],
            environment_mismatches=[name for name in env_before if env_before[name] != env_after[name]],
            source_head_unchanged=git("rev-parse", "HEAD") == head,
            source_index_unchanged=git("write-tree") == index_tree,
            tracked_worktree_clean_after=clean(),
            unexpected_native_mappings_after=unexpected_native_mappings,
            passed=sum(row.get("passed", 0) for row in record["runs"]),
            failed=sum(row.get("failed", 0) for row in record["runs"]),
            skipped=sum(row.get("skipped", 0) for row in record["runs"]),
            finished_at_utc=datetime.now(timezone.utc).isoformat(),
        )
        record["manifest_sha256"] = {name: sha256(output / name) for name in (
            "source-before.json", "source-after.json", "environment-before.json", "environment-after.json"
        )}
        record["success"] = (
            not record.get("runner_error") and len(record["runs"]) == expected_runs
            and not unexpected_native_mappings
            and before == after and env_before == env_after
            and record["source_head_unchanged"] and record["source_index_unchanged"]
            and record["tracked_worktree_clean_after"] and all(row["accepted"] for row in record["runs"])
        )
        save()
        print(json.dumps({key: record[key] for key in ("success", "passed", "failed", "skipped")}), flush=True)
    return 0 if record["success"] else 1


if __name__ == "__main__":
    sys.exit(main())

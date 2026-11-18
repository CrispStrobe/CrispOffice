#!/usr/bin/env python3
"""Run local review gates against an explicitly frozen Git source revision.

Example, from any directory after restoring the recorded runtime:
    python path/to/run_checks.py --head FULL_COMMIT --runtime path/to/runtime

Outputs default to <runtime>/final-checks, outside the source checkout. The
runner does not install dependencies or contact GitHub/GitHub Actions.
Only one Dart/Flutter verification process should run at a time on this host.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


BASE = "39eada31155dd85d971bab71d26cda6e67cb6844"
VENDORED_IMPORT = "46d7422d5ac356c327759872ff28adcd154b75ad"
VENDORED_PATH = "third_party/enough_mail"
VISUAL_FIXTURES = ["render_comments.dart"]
ENGINE_TESTS = [
    "word_zotero_note_insertion_test.dart",
    "office_thesaurus_test.dart",
    "word_zotero_caret_test.dart",
    "word_proofing_inheritance_test.dart",
    "word_comment_proofing_styles_test.dart",
    "word_style_introduction_test.dart",
]
EDITOR_TESTS = [
    "word_draft_proofing_test.dart",
    "word_proofing_priority_test.dart",
    "word_thesaurus_review_integration_test.dart",
    "word_thesaurus_controller_test.dart",
    "word_thesaurus_dialog_test.dart",
    "word_zotero_note_target_test.dart",
    "word_zotero_notes_pane_test.dart",
    "word_text_proofing_controls_test.dart",
    "word_text_proofing_pane_test.dart",
    "word_zotero_composer_test.dart",
    "word_zotero_dialog_test.dart",
    "word_zotero_citing_dialog_test.dart",
    "word_zotero_document_actions_test.dart",
    "word_zotero_field_at_caret_test.dart",
    "word_zotero_unlink_all_test.dart",
    "word_note_numbering_test.dart",
    "word_notes_editing_test.dart",
    "word_keyboard_review_test.dart",
    "word_keyboard_context_geometry_test.dart",
    "word_keyboard_review_identity_test.dart",
    "word_live_proofing_session_test.dart",
    "word_live_review_selection_test.dart",
    "word_live_review_surface_test.dart",
    "word_review_pane_test.dart",
    "word_live_review_changes_test.dart",
    "word_incremental_proofing_test.dart",
    "word_incremental_proofing_menu_test.dart",
    "word_proofing_session_test.dart",
    "word_manual_proofing_test.dart",
    "word_proofing_dialog_test.dart",
    "word_proofing_context_test.dart",
    "word_proofing_geometry_test.dart",
    "word_proofing_navigation_test.dart",
    "word_review_dialog_test.dart",
    "word_revision_story_test.dart",
    "word_review_controller_test.dart",
    "word_input_focus_test.dart",
    "office_input_ownership_test.dart",
    "office_direction_chord_test.dart",
    "editor_test.dart",
    "report_designer_test.dart",
]
STUDIO_TESTS = [
    "studio_comment_draft_proofing_test.dart",
    "studio_comment_keyboard_review_test.dart",
    "studio_zotero_shortcuts_test.dart",
    "studio_comment_review_test.dart",
    "studio_review_pane_test.dart",
    "studio_document_comparison_test.dart",
    "widget_test.dart",
    "studio_sheet_navigation_test.dart",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def repository_root() -> Path:
    for candidate in Path(__file__).resolve().parents:
        if (candidate / "pubspec.yaml").is_file() and (
            candidate / "packages/quds_office_editor"
        ).is_dir():
            return candidate
    raise RuntimeError("Place this runner within the repository checkout")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head", required=True, help="Expected source commit")
    parser.add_argument("--base", default=BASE)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--command-timeout", type=int, default=1800)
    args = parser.parse_args()
    repo = repository_root()
    runtime = (args.runtime or repo.parent / "toolchains").resolve()
    output = (args.output or runtime / "final-checks").resolve()
    if output == repo or repo in output.parents:
        raise RuntimeError("Write check output outside the frozen checkout")
    if output.exists() and any(output.iterdir()):
        raise RuntimeError("Choose an empty output directory; preserve earlier attempts")
    output.mkdir(parents=True, exist_ok=True)
    checks = output / "checks"
    checks.mkdir()

    def git(*argv: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(repo), *argv], text=True
        ).rstrip("\n")

    def tracked_clean() -> bool:
        return not git("status", "--porcelain=v1", "--untracked-files=no")

    head = git("rev-parse", "--verify", args.head + "^{commit}")
    base = git("rev-parse", "--verify", args.base + "^{commit}")
    if git("rev-parse", "HEAD") != head:
        raise RuntimeError("HEAD differs from the supplied source commit")
    if not tracked_clean():
        raise RuntimeError("Tracked worktree and index must be clean before the gate")
    # Imported MIME fixtures contain byte-significant CRLF/trailing whitespace.
    # Preserve the complete imported tree, including notices and upstream tests,
    # rather than rewriting it to satisfy an authored-source whitespace rule.
    vendor_tree = git("rev-parse", head + ":" + VENDORED_PATH)
    if vendor_tree != git("rev-parse", VENDORED_IMPORT + ":" + VENDORED_PATH):
        raise RuntimeError("Vendored whitespace exclusion requires an exact imported tree")
    tracked = set(git("ls-files", "-z").split("\0")) - {""}
    tests = [
        "packages/quds_office_engine/test/" + name for name in ENGINE_TESTS
    ] + [
        "packages/quds_office_editor/test/" + name for name in EDITOR_TESTS
    ] + [
        "packages/quds_office_editor/example/test/" + name for name in STUDIO_TESTS
    ]
    for name in tests:
        if name not in tracked or not (repo / name).is_file():
            raise RuntimeError("Requested test must exist in the frozen tree: " + name)
    changed = [
        name
        for name in git(
            "diff", "--name-only", "--diff-filter=ACMRT", "-z", base, head
        ).split("\0")
        if name.endswith(".dart")
        and name.startswith(("packages/", "apps/"))
        and (repo / name).is_file()
    ]
    selected = set(tests)
    config_names = {
        "pubspec.yaml", "analysis_options.yaml", "dart_test.yaml", "build.yaml",
        "l10n.yaml", ".fvmrc", "melos.yaml",
    }
    for name in tracked:
        path = Path(name)
        product = name.startswith(("packages/", "apps/", "third_party/"))
        # Tests import helper sources and load fixture/assets files. Bind the
        # complete tracked product inputs, not only production Dart and fonts.
        if product or (path.name in config_names and len(path.parts) == 1):
            selected.add(name)
    selected.update(changed)
    # Bind the exact gate definition alongside the code and test inputs.
    selected.add(str(Path(__file__).resolve().relative_to(repo)))
    # Visuals are rendered separately, but their exact fixture definitions
    # belong to the same source checkpoint and final binding manifest.
    for fixture_name in VISUAL_FIXTURES:
        fixture = Path(__file__).resolve().parent / fixture_name
        name = str(fixture.relative_to(repo))
        if name not in tracked or not fixture.is_file():
            raise RuntimeError("Visual fixture must exist in the frozen tree: " + name)
        selected.add(name)
    for name in git("ls-files", "--others", "--exclude-standard", "-z").split("\0"):
        if name.startswith(("packages/", "apps/", "third_party/")):
            raise RuntimeError("Untracked product input could affect the gate: " + name)

    receipt_path = runtime / "runtime.json"
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    if receipt.get("status") != "ready" or not receipt["archive"].get("verified"):
        raise RuntimeError("A verified, ready local runtime is required")
    sdk = runtime / "flutter"
    dart = runtime / "bin/dart"
    flutter = runtime / "bin/flutter"
    environment_inputs = {
        "workspace/pubspec.lock": repo / "pubspec.lock",
        "workspace/.dart_tool/package_config.json": repo / ".dart_tool/package_config.json",
        "runtime/runtime.json": receipt_path,
        "runtime/pub-cache-receipt.json": runtime / "pub-cache-receipt.json",
        "runtime/bin/dart": dart,
        "runtime/bin/flutter": flutter,
        "sdk/dart": sdk / "bin/cache/dart-sdk/bin/dart",
        "sdk/flutter_tester": sdk / "bin/cache/artifacts/engine/linux-x64/flutter_tester",
        "sdk/flutter_tools.snapshot": sdk / "bin/cache/flutter_tools.snapshot",
        "sdk/flutter_tools/pubspec.lock": sdk / "packages/flutter_tools/pubspec.lock",
        "sdk/flutter_tools/package_config.json": sdk / "packages/flutter_tools/.dart_tool/package_config.json",
    }
    if sha256(repo / "pubspec.lock") != receipt["workspace_lock_sha256"]:
        raise RuntimeError("Workspace dependency lock differs from the verified runtime")
    # Receipts preserve the original setup paths. Resolve their SDK-relative
    # executable identities within the caller's restored runtime directory.
    recorded_sdk = Path(receipt["sdk"])
    executable_hashes = {}
    for recorded_path, expected in receipt["executables_sha256"].items():
        relative = Path(recorded_path).relative_to(recorded_sdk)
        path = sdk / relative
        executable_hashes[relative.as_posix()] = expected
        if sha256(path) != expected:
            raise RuntimeError("Runtime executable differs from its verified receipt: " + str(path))
    required_executables = {
        "bin/cache/dart-sdk/bin/dart",
        "bin/cache/artifacts/engine/linux-x64/flutter_tester",
    }
    if not required_executables.issubset(executable_hashes):
        raise RuntimeError("The verified receipt must bind Dart and Flutter tester")
    env = dict(os.environ)
    env.update(
        PUB_CACHE=str(runtime / "pub-cache"), FLUTTER_ROOT=str(sdk), CI="true",
        DART_SUPPRESS_ANALYTICS="true", FLUTTER_SUPPRESS_ANALYTICS="true",
        DASH__SUPPRESS_ANALYTICS="true", XDG_CONFIG_HOME=str(runtime / "config"),
        XDG_CACHE_HOME=str(runtime / "cache"), XDG_DATA_HOME=str(runtime / "data"),
        TMPDIR=str(runtime / "tmp"), PATH=str(runtime / "bin") + os.pathsep + env.get("PATH", ""),
    )

    def source_snapshot() -> dict[str, str | None]:
        return {
            name: sha256(repo / name) if (repo / name).is_file() else None
            for name in sorted(selected)
        }

    def environment_snapshot() -> dict[str, str | None]:
        return {
            name: sha256(path) if path.is_file() else None
            for name, path in sorted(environment_inputs.items())
        }

    before = source_snapshot()
    environment_before = environment_snapshot()
    if any(value is None for value in [*before.values(), *environment_before.values()]):
        raise RuntimeError("A source or runtime binding input is missing")
    write_json(output / "source-before.json", before)
    write_json(output / "environment-before.json", environment_before)
    record = {
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_commit": head, "source_tree": git("rev-parse", head + "^{tree}"),
        "source_base": base, "source_file_count": len(before),
        "pristine_vendor": {
            "path": VENDORED_PATH, "imported_from": VENDORED_IMPORT,
            "tree": vendor_tree, "source_tree_matches_import": True,
            "whitespace_excluded_only_after_exact_tree_verification": True,
            "all_files_still_bound_by_source_manifest": True,
        },
        "source_before_manifest": "source-before.json", "source_after_manifest": "source-after.json",
        "environment_before_manifest": "environment-before.json",
        "environment_after_manifest": "environment-after.json",
        "engine_suites": ENGINE_TESTS, "visual_fixture_definitions": VISUAL_FIXTURES,
        "editor_suites": EDITOR_TESTS, "studio_suites": STUDIO_TESTS,
        "analyzed_files": changed, "workspace_lock_sha256": sha256(repo / "pubspec.lock"),
        "runtime_receipt_sha256": sha256(receipt_path), "runtime": receipt["runtime"],
        "source_index_unchanged": True, "tracked_worktree_clean_before": True,
        "runs": [], "github_actions_queried_or_awaited": False,
    }
    index_tree = git("write-tree")

    def save() -> None:
        write_json(output / "verification.json", record)

    def run(name: str, command: list[str], cwd: Path, suites: list[str] | None = None) -> None:
        print("START " + name, flush=True)
        started = time.monotonic()
        log = checks / (name + (".jsonl" if suites is not None else ".log"))
        error = None
        with log.open("wb") as stream:
            try:
                result = subprocess.run(
                    command, cwd=cwd, env=env, stdout=stream,
                    stderr=subprocess.STDOUT, timeout=args.command_timeout,
                )
                exit_code = result.returncode
            except (OSError, subprocess.TimeoutExpired) as exception:
                exit_code = 124 if isinstance(exception, subprocess.TimeoutExpired) else 127
                error = repr(exception)
                stream.write(("\nRUNNER ERROR: " + error + "\n").encode())
        item = {
            "name": name, "command": command, "cwd": str(cwd.relative_to(repo)) or ".",
            "exit_code": exit_code, "elapsed_seconds": round(time.monotonic() - started, 3),
            "log": str(log.relative_to(output)), "log_sha256": sha256(log),
        }
        if error is not None:
            item["runner_error"] = error
        if suites is not None:
            started_cases, suite_paths, cases, errors = {}, {}, [], []
            hidden, reporter_success = 0, None
            for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                kind = event.get("type")
                if kind == "suite":
                    suite_paths[event["suite"]["id"]] = event["suite"]["path"]
                elif kind == "testStart":
                    case = event["test"]
                    started_cases[case["id"]] = {
                        "id": case["id"], "name": case["name"], "suite_id": case["suiteID"],
                        "suite": suite_paths.get(case["suiteID"]),
                    }
                elif kind == "testDone":
                    case = started_cases.pop(event["testID"], None)
                    if event.get("hidden"):
                        hidden += 1
                    elif case is not None:
                        cases.append(dict(case, result=event["result"], skipped=event["skipped"]))
                elif kind == "done":
                    reporter_success = event["success"]
                elif kind == "error":
                    errors.append(event)
            per_suite = {}
            for case in cases:
                key = Path(case["suite"]).name if case["suite"] else str(case["suite_id"])
                counts = per_suite.setdefault(key, {"passed": 0, "failed": 0, "skipped": 0})
                counts["passed"] += int(case["result"] == "success" and not case["skipped"])
                counts["failed"] += int(case["result"] in {"error", "failure"})
                counts["skipped"] += int(bool(case["skipped"]))
            missing = sorted(set(suites) - {Path(path).name for path in suite_paths.values()})
            item.update(
                passed=sum(count["passed"] for count in per_suite.values()),
                failed=sum(count["failed"] for count in per_suite.values()),
                skipped=sum(count["skipped"] for count in per_suite.values()),
                hidden_events_excluded=hidden, reporter_success=reporter_success,
                reporter_error_count=len(errors),
                per_suite=per_suite, missing_requested_suites=missing,
                empty_requested_suites=sorted(set(suites) - set(per_suite)),
                unfinished_reporter_events=list(started_cases.values()),
            )
            case_path = checks / (name + "-cases.json")
            error_path = checks / (name + "-errors.json")
            write_json(case_path, cases)
            write_json(error_path, errors)
            compressed = log.with_suffix(log.suffix + ".gz")
            compressed.write_bytes(gzip.compress(log.read_bytes(), mtime=0))
            item.update(
                case_results=str(case_path.relative_to(output)), case_results_sha256=sha256(case_path),
                errors=str(error_path.relative_to(output)), errors_sha256=sha256(error_path),
                compressed_log=str(compressed.relative_to(output)), compressed_log_sha256=sha256(compressed),
            )
        record["runs"].append(item)
        save()
        print(json.dumps({key: item[key] for key in (
            "name", "exit_code", "elapsed_seconds", "passed", "failed", "skipped"
        ) if key in item}), flush=True)

    save()
    try:
        run("engine", [str(dart), "test", "--concurrency=1", "--reporter", "json", *[
            "test/" + name for name in ENGINE_TESTS
        ]], repo / "packages/quds_office_engine", ENGINE_TESTS)
        run("editor", [str(flutter), "test", "--no-pub", "--concurrency=1", "--reporter", "json", *[
            "test/" + name for name in EDITOR_TESTS
        ]], repo / "packages/quds_office_editor", EDITOR_TESTS)
        run("studio", [str(flutter), "test", "--no-pub", "--concurrency=1", "--reporter", "json", *[
            "test/" + name for name in STUDIO_TESTS
        ]], repo / "packages/quds_office_editor/example", STUDIO_TESTS)
        if not changed:
            raise RuntimeError("No changed tracked Dart files were selected for analysis")
        run("analysis", [str(dart), "analyze", "--fatal-infos", "--fatal-warnings", *changed], repo)
        run("format", [str(dart), "format", "--output=none", "--set-exit-if-changed", *changed], repo)
        run("whitespace", [
            "git", "diff", "--check", base, head, "--", ".",
            ":(exclude)" + VENDORED_PATH,
        ], repo)
    except BaseException as exception:
        record["runner_error"] = repr(exception)
    finally:
        after = source_snapshot()
        environment_after = environment_snapshot()
        write_json(output / "source-after.json", after)
        write_json(output / "environment-after.json", environment_after)
        record.update(
            source_unchanged_during_checks=before == after,
            source_mismatches=[name for name in sorted(selected) if before[name] != after[name]],
            environment_unchanged_during_checks=environment_before == environment_after,
            environment_mismatches=[name for name in sorted(environment_inputs) if environment_before[name] != environment_after[name]],
            source_head_unchanged=git("rev-parse", "HEAD") == head,
            source_index_unchanged=git("write-tree") == index_tree,
            tracked_worktree_clean_after=tracked_clean(),
            source_manifest_sha256={part: sha256(output / ("source-" + part + ".json")) for part in ("before", "after")},
            environment_manifest_sha256={part: sha256(output / ("environment-" + part + ".json")) for part in ("before", "after")},
            passed=sum(item.get("passed", 0) for item in record["runs"]),
            failed=sum(item.get("failed", 0) for item in record["runs"]),
            skipped=sum(item.get("skipped", 0) for item in record["runs"]),
            finished_at_utc=datetime.now(timezone.utc).isoformat(),
        )
        record["success"] = (
            not record.get("runner_error") and len(record["runs"]) == 6
            and before == after and environment_before == environment_after
            and record["source_head_unchanged"] and record["source_index_unchanged"]
            and record["tracked_worktree_clean_after"]
            and all(
                item["exit_code"] == 0 and item.get("reporter_success", True) is True
                and not item.get("failed", 0) and not item.get("skipped", 0)
                and not item.get("missing_requested_suites")
                and not item.get("empty_requested_suites")
                and not item.get("reporter_error_count", 0)
                and not item.get("unfinished_reporter_events")
                for item in record["runs"]
            )
        )
        save()
        print(json.dumps({key: record[key] for key in (
            "success", "passed", "failed", "skipped", "source_file_count"
        )}), flush=True)
    return 0 if record["success"] else 1


if __name__ == "__main__":
    sys.exit(main())

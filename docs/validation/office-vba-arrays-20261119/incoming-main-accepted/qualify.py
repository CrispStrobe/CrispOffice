#!/usr/bin/env python3
"""Qualify incoming page-layout/theme changes against live workspace sources."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[4]
WORKSPACE = ROOT.parent / "flutter-validation-workspace"
RUNTIME = ROOT.parent / "runtime"
OUTPUT = Path(__file__).resolve().parent
SDK = RUNTIME / "flutter"
FLUTTER = SDK / "bin/flutter"
DART = SDK / "bin/cache/dart-sdk/bin/dart"
EDITOR = Path("packages/quds_office_editor")
STUDIO = EDITOR / "example"
SPACY = Path("packages/quds_proofing_spacy")
NEW_TESTS = [
    "test/office_chrome_theme_test.dart",
    "test/office_dark_document_test.dart",
    "test/office_dark_slide_test.dart",
    "test/word_page_layout_test.dart",
]
EXISTING_TESTS = [
    "test/embed_test.dart",
    "test/word_tab_stops_editor_test.dart",
    "test/sheet_conditional_rendering_test.dart",
    "test/word_selection_paint_test.dart",
    "test/word_header_footer_navigation_test.dart",
    "test/editor_test.dart",
]
MAIN_EDITOR_TESTS = [
    "test/word_text_proofing_pane_test.dart",
    "test/word_review_pane_test.dart",
    "test/word_text_proofing_controls_test.dart",
    "test/word_complex_script_proofing_controls_test.dart",
    "test/word_language_detection_test.dart",
]
SPACY_TESTS = [
    "test/ner_removal_test.dart",
    "test/distribution_test.dart",
    "test/bundle_test.dart",
]
REPEATED_STUDIO_TESTS = [
    "test/studio_mail_archive_restore_test.dart",
    "test/studio_mail_archive_restore_native_test.dart",
    "test/studio_mail_archive_portability_visual_test.dart",
]
STUDIO_THEME_TESTS = [
    "test/studio_layout_theme_test.dart",
    "test/studio_page_layout_dialog_test.dart",
    "test/studio_paragraph_dialog_test.dart",
    "test/studio_slide_sheet_menus_test.dart",
    "test/studio_comment_keyboard_review_test.dart",
    "test/studio_comment_review_test.dart",
    "test/studio_review_pane_test.dart",
    "test/studio_zotero_shortcuts_test.dart",
    "test/studio_file_menu_test.dart",
    "test/studio_desktop_menu_test.dart",
    "test/studio_ribbon_customization_test.dart",
    "test/studio_downloads_manager_test.dart",
    "test/studio_hunspell_setup_test.dart",
    "test/studio_spacy_setup_test.dart",
]
STUDIO_SUPPORT = ["test/support/studio_document_mode.dart"]
CHANGED_STUDIO_SOURCE = [
    "lib/studio_chrome.dart",
    "lib/crisp_office_sample.dart",
    "lib/studio_downloads_manager.dart",
    "lib/studio_spacy_host.dart",
    "lib/studio_spacy_host_native.dart",
    "lib/studio_material_theme.dart",
    "lib/studio_page_layout_dialog.dart",
    "lib/studio_paragraph_dialog.dart",
    "lib/suite_workspace.dart",
    "lib/studio_hunspell_setup.dart",
    "lib/studio_pdf_flutter_samples.dart",
    "lib/studio_pdf_toc_samples.dart",
]
CHANGED_SOURCE = [
    "lib/quds_office_editor.dart",
    "lib/src/editor_sheet/render_sheet_grid.dart",
    "lib/src/editor_slide/render_slide_stage.dart",
    "lib/src/editor_word/office_ruler.dart",
    "lib/src/editor_word/render_word_canvas.dart",
    "lib/src/embed/office_controller.dart",
    "lib/src/embed/word_review_pane.dart",
    "lib/src/embed/office_theme.dart",
    "lib/src/embed/word_page_layout.dart",
    "lib/src/ui_components/office_chrome.dart",
]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(name: str, value: object) -> None:
    (OUTPUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def members() -> list[str]:
    return [line.removeprefix("  - ").strip()
            for line in (WORKSPACE / "pubspec.yaml").read_text().splitlines()
            if line.startswith("  - ")]


def snapshot() -> dict[str, str]:
    paths = []
    for name in git("ls-files", "-z").split("\0"):
        if not name:
            continue
        path = Path(name)
        package_source = (path.parts[0] in {"packages", "third_party", "apps"}
                          and "lib" in path.parts and path.suffix == ".dart")
        configuration = path.name in {"pubspec.yaml", "analysis_options.yaml"}
        asset = name.startswith((
            "packages/quds_office_editor/fonts/",
            "packages/quds_office_editor/templates/",
            "packages/quds_office_editor/assets/",
            "packages/quds_office_editor/example/fonts/",
            "packages/quds_office_editor/example/assets/",
        ))
        editor_test_input = name.startswith((
            "packages/quds_office_editor/test/",
            "packages/quds_office_editor/example/test/",
            "packages/quds_proofing_spacy/test/",
        ))
        if package_source or configuration or asset or editor_test_input or name == "pubspec.lock":
            paths.append(ROOT / path)
    paths.extend(ROOT / EDITOR / test for test in NEW_TESTS + EXISTING_TESTS + MAIN_EDITOR_TESTS)
    paths.extend(ROOT / STUDIO / test for test in REPEATED_STUDIO_TESTS + STUDIO_THEME_TESTS + STUDIO_SUPPORT)
    paths.extend(ROOT / SPACY / test for test in SPACY_TESTS)
    paths.extend([
        WORKSPACE / "analysis_options.yaml", WORKSPACE / "pubspec.yaml",
        WORKSPACE / "pubspec.lock", WORKSPACE / ".dart_tool/package_config.json",
        WORKSPACE / ".dart_tool/package_graph.json",
        SDK / "bin/cache/flutter_tools.snapshot", SDK / "bin/cache/dart-sdk/bin/dart",
        SDK / "bin/cache/dart-sdk/version", SDK / "bin/cache/flutter.version.json",
        SDK / "bin/cache/engine.stamp",
        SDK / "bin/cache/artifacts/engine/linux-x64/flutter_tester",
    ])
    paths.extend(WORKSPACE / member / "pubspec.yaml" for member in members())
    for package in (EDITOR, STUDIO):
        plugins = WORKSPACE / package / ".flutter-plugins-dependencies"
        if plugins.is_file():
            paths.append(plugins)
    config_path = WORKSPACE / ".dart_tool/package_config.json"
    for package in json.loads(config_path.read_text())["packages"]:
        uri = urlparse(package["rootUri"])
        package_root = (Path(unquote(uri.path)) if uri.scheme == "file"
                        else config_path.parent / unquote(package["rootUri"]))
        manifest = package_root / "pubspec.yaml"
        if manifest.is_file():
            paths.append(manifest)
    result = {}
    for path in sorted(set(paths), key=str):
        if not path.is_file():
            raise RuntimeError(f"Missing recorded input: {path}")
        try:
            key = "repository/" + str(path.relative_to(ROOT))
        except ValueError:
            key = "workspace/" + str(path.relative_to(ROOT.parent))
        result[key] = digest(path)
    return result


def execute(name: str, args: list[str], cwd: Path) -> dict[str, object]:
    environment = {
        "PUB_CACHE": str(RUNTIME / "pub-cache"), "TMPDIR": str(RUNTIME / "tmp"),
        "DART_SUPPRESS_ANALYTICS": "true", "FLUTTER_SUPPRESS_ANALYTICS": "true",
        "CI": "true",
    }
    effective = {**os.environ, **environment}
    effective.pop("QUDS_MAIL_PORTABILITY_SHOTS", None)
    started = time.time()
    with (OUTPUT / f"{name}.stdout.log").open("wb") as stdout:
        with (OUTPUT / f"{name}.stderr.log").open("wb") as stderr:
            result = subprocess.run(args, cwd=cwd, env=effective,
                                    stdout=stdout, stderr=stderr, check=False)
    receipt = {
        "name": name, "command": args, "cwd": str(cwd),
        "environment_overrides": environment,
        "removed_optional_environment": ["QUDS_MAIL_PORTABILITY_SHOTS"],
        "started_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started)),
        "elapsed_seconds": time.time() - started, "exit_code": result.returncode,
        "stdout": f"{name}.stdout.log", "stderr": f"{name}.stderr.log",
        "stdout_sha256": digest(OUTPUT / f"{name}.stdout.log"),
        "stderr_sha256": digest(OUTPUT / f"{name}.stderr.log"),
    }
    write_json(f"{name}.json", receipt)
    print(json.dumps({"name": name, "exit_code": result.returncode}), flush=True)
    return receipt


def summarize(name: str) -> dict[str, object]:
    tests = {}
    finished = {}
    suites = {}
    done = []
    non_json_lines = 0
    for line in (OUTPUT / f"{name}.stdout.log").read_text().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            non_json_lines += 1
            continue
        if event.get("type") == "testStart":
            tests[event["test"]["id"]] = event["test"]
        elif event.get("type") == "testDone":
            finished[event["testID"]] = event
        elif event.get("type") == "suite":
            suites[event["suite"]["id"]] = event["suite"]
        elif event.get("type") == "done":
            done.append(event)
    visible = [
        {"test": tests[test_id], "suite": suites[tests[test_id]["suiteID"]],
         "result": result}
        for test_id, result in sorted(finished.items())
        if not result.get("hidden", False) and not result.get("isHidden", False)
        and not tests[test_id].get("isHidden", False)
    ]
    summary = {
        "visible_test_count": len(visible),
        "passed": sum(item["result"]["result"] == "success"
                      and not item["result"].get("skipped", False) for item in visible),
        "failed": sum(item["result"]["result"] != "success" for item in visible),
        "skipped": sum(item["result"].get("skipped", False) for item in visible),
        "done_events": done, "non_json_stdout_lines": non_json_lines, "tests": visible,
    }
    write_json(f"{name}-summary.json", summary)
    return summary


def main() -> None:
    engine = WORKSPACE / "packages/quds_office_engine/lib"
    if engine.resolve() != ROOT / "packages/quds_office_engine/lib":
        raise RuntimeError("This qualification requires current live engine sources.")
    before = snapshot()
    write_json("inputs-before.json", before)
    copied_manifests = {
        name: digest(ROOT / name) == digest(WORKSPACE / name)
        for name in ["pubspec.yaml", *(f"{member}/pubspec.yaml" for member in members())]
    }
    write_json("source-frontier.json", {
        "checkout_head_at_start": git("rev-parse", "HEAD"),
        "incoming_head": "9f41e0427734d815b19149eba5eabef202f78ba6",
        "retained_gui_head": "8c6acd04637ef627959fe40f518254ed538ab087",
        "previous_gui_acceptance_source": "61bb3ee42a385c5ffaffa44047693a6f378a8424",
        "reviewed_remote_main": "9f41e0427734d815b19149eba5eabef202f78ba6",
        "reviewed_planning_only_head": "9d6cd0504094632825d3a0990a37fffd5c1b2c05",
        "new_editor_tests": NEW_TESTS, "existing_editor_tests": EXISTING_TESTS,
        "repeated_studio_tests": REPEATED_STUDIO_TESTS,
        "additional_studio_tests": STUDIO_THEME_TESTS,
        "main_editor_tests": MAIN_EDITOR_TESTS,
        "spacy_installer_tests": SPACY_TESTS,
        "copied_manifests_match_repository": copied_manifests,
        "source_inputs": len(before), "engine_sources": "Current live repository source",
    })
    print(json.dumps({"recorded_inputs": len(before)}), flush=True)
    common = [str(FLUTTER), "--no-version-check", "--suppress-analytics"]
    testing = ["test", "--no-pub", "--concurrency=1", "--reporter=json"]
    commands = [execute("editor-tests", [*common, *testing, *NEW_TESTS, *EXISTING_TESTS, *MAIN_EDITOR_TESTS],
                        WORKSPACE / EDITOR)]
    commands.append(execute("repeated-studio-tests", [*common, *testing, *REPEATED_STUDIO_TESTS],
                            WORKSPACE / STUDIO))
    commands.append(execute("studio-theme-tests", [*common, *testing, *STUDIO_THEME_TESTS],
                            WORKSPACE / STUDIO))
    commands.append(execute(
        "spacy-installer-tests", [str(DART), "test", "--concurrency=1", "--reporter=json", *SPACY_TESTS],
        WORKSPACE / SPACY,
    ))
    commands.append(execute(
        "changed-analysis", [*common, "analyze", "--no-pub", "--fatal-infos",
                             *CHANGED_SOURCE, *NEW_TESTS, *MAIN_EDITOR_TESTS, "test/embed_test.dart"], WORKSPACE / EDITOR,
    ))
    commands.append(execute(
        "studio-analysis", [*common, "analyze", "--no-pub", "--fatal-infos",
                            *CHANGED_STUDIO_SOURCE, *STUDIO_THEME_TESTS, *STUDIO_SUPPORT],
        WORKSPACE / STUDIO,
    ))
    commands.append(execute(
        "spacy-analysis", [str(DART), "analyze", "--fatal-infos", "lib/src/installer_io.dart", *SPACY_TESTS],
        WORKSPACE / SPACY,
    ))
    editor = summarize("editor-tests")
    repeated = summarize("repeated-studio-tests")
    studio_theme = summarize("studio-theme-tests")
    spacy = summarize("spacy-installer-tests")
    after = snapshot()
    write_json("inputs-after.json", after)
    changed = sorted(key for key in before.keys() | after.keys()
                     if before.get(key) != after.get(key))
    stability = {"before_count": len(before), "after_count": len(after),
                 "changed": changed, "unchanged": not changed}
    write_json("input-stability.json", stability)
    success = (not changed and all(copied_manifests.values())
               and all(command["exit_code"] == 0 for command in commands)
               and all(summary["failed"] == 0 and summary["passed"] > 0
                       and len(summary["done_events"]) == 1
                       and summary["done_events"][0].get("success") is True
                       for summary in (editor, repeated, studio_theme, spacy)))
    receipt = {"success": success, "commands": commands, "input_stability": stability,
               "editor": {k: v for k, v in editor.items() if k != "tests"},
               "repeated_studio": {k: v for k, v in repeated.items() if k != "tests"},
               "studio_theme": {k: v for k, v in studio_theme.items() if k != "tests"},
               "spacy_installer": {k: v for k, v in spacy.items() if k != "tests"},
               "counting_note": "The entire prior 347-case GUI acceptance is repeated here, alongside affected language/download/removal coverage. Count repeated cases once across all retained runs, including the 18 mail UI cases. Identity is repository suite path and test name."}
    write_json("receipt.json", receipt)
    print(json.dumps({"success": success, "editor_passed": editor["passed"],
                      "repeated_studio_passed": repeated["passed"],
                      "studio_theme_passed": studio_theme["passed"],
                      "spacy_installer_passed": spacy["passed"],
                      "changed": changed}), flush=True)
    raise SystemExit(0 if success else 1)


if __name__ == "__main__":
    main()

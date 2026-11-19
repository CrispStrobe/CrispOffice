#!/usr/bin/env python3
"""Reproducible local archive qualification; no dependency resolution or CI.

Use --plan-only before the source freeze. A real run requires a clean, committed
product tree, an explicit expected HEAD, the verified runtime receipt, and the
documented temporary system-SQLite hook. Output must be a new directory outside
the repository. Failed, incomplete, skipped, or source-changing runs never pass.
"""

from __future__ import annotations

import argparse
import ctypes
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
from datetime import datetime, timezone
from urllib.parse import unquote, urlparse


BASELINE = "e00ca1495551ffaf61dd9b3ee7770f8bfde7e897"
MAIL_PACKAGES = (
    "quds_mail_core", "quds_mail_mime", "quds_mail_store", "quds_mail_transport"
)
SOURCE_ROOTS = ("packages/", "third_party/", "apps/", "tool/", "tools/")
ROOT_INPUTS = {
    "pubspec.yaml", "pubspec.lock", "analysis_options.yaml", "melos.yaml",
    ".cursorrules", "CONTRIBUTING.md", ".fvmrc", "dart_test.yaml",
}
DOCUMENT_INPUTS = {
    "docs/roadmaps/mail/archive-search.md",
    "docs/validation/mail-archive-search-20261119/README.md",
    "docs/validation/mail-archive-search-20261119/run-local-validation.py",
}
FIXTURES = (
    ("language-id", "packages/quds_language_id/test/fixtures/native_transport_fixture.cpp",
     "QUDS_LANGUAGE_ID_FIXTURE_LIBRARY"),
    ("hunspell-ownership", "packages/quds_proofing_hunspell/test/support/lifecycle_library.cpp",
     "QUDS_HUNSPELL_OWNERSHIP_LIBRARY"),
    ("hunspell-lifecycle", "packages/quds_proofing_hunspell/test/fixtures/lifecycle_hunspell.cpp",
     "QUDS_HUNSPELL_LIFECYCLE_LIBRARY"),
    ("hunspell-provider", "packages/quds_proofing_hunspell/test/support/hunspell_lifecycle_shim.cpp",
     "QUDS_HUNSPELL_PROVIDER_LIFECYCLE_LIBRARY"),
)
EXCLUSIONS = [
    {"path": "packages/quds_language_id/test/language_id_native_test.dart",
     "reason": "Needs the real external language classifier; counter fixture is lifecycle evidence only."},
    {"path": "packages/quds_arabic_morph/test/arabic_morph_native_test.dart",
     "reason": "Needs the real native analyzer and verified morphology model bundle."},
    {"path": "packages/quds_arabic_morph/test/arabic_rules_e2e_test.dart",
     "reason": "Needs the real native analyzer and verified morphology model bundle."},
    {"path": "packages/quds_arabic_morph/test/arabic_morph_live_download_test.dart",
     "reason": "Explicitly performs external model downloads."},
    {"path": "packages/quds_proofing_hunspell/test/hunspell_native_test.dart",
     "reason": "Needs a real native dictionary installation and includes live-download acceptance."},
    {"path": "packages/quds_office_editor/example/test/studio_arabic_morph_native_test.dart",
     "reason": "Needs the real native analyzer and verified morphology model bundle."},
    {"path": "packages/quds_office_editor/example/test/studio_arabic_proofing_native_test.dart",
     "reason": "Needs a real Hunspell native library and Arabic dictionary."},
]
ACCEPTANCE_LIMITS = [
    "No live IMAP, SMTP, EWS, Gmail or Microsoft 365 credentials or service requests; transport tests use injected fakes or local loopback servers.",
    "No external model or dictionary downloads, and no real language/Arabic/Hunspell model acceptance.",
    "Node tests cover declared JavaScript transport boundaries; no browser interaction, browser archive, or full web build is claimed.",
    "Linux native SQLite and actual POSIX crash tests only; no installed macOS/Windows/mobile application, signing, Keychain, or OAuth account acceptance.",
    "The system SQLite used here is recorded independently from sqlite3's default downloaded binary; packaged native binaries on other platforms are not qualified by this run.",
    "No full-repository test claim, performance benchmark, remote mailbox snapshot guarantee, compliance certification, or GitHub Actions result.",
]


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def write_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def write_manifest(path, value):
    Path(path).write_bytes(gzip.compress(encoded(value), mtime=0))


def capture(command, cwd):
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def git_paths(repo, arguments):
    raw = subprocess.check_output(["git", arguments[0], "-z", *arguments[1:]], cwd=repo)
    return [item.decode() for item in raw.split(b"\0") if item]


def is_source(name):
    return name in ROOT_INPUTS or name in DOCUMENT_INPUTS or (
        name.startswith(SOURCE_ROOTS)
        and "/docs/" not in name and "/doc/" not in name
        and not name.lower().endswith(".md")
    )


def source_manifest(repo):
    names = set(git_paths(repo, ["ls-files", "--cached", "--others", "--exclude-standard"]))
    names.update(name for name in DOCUMENT_INPUTS if (repo / name).is_file())
    return {
        name: {"bytes": (repo / name).stat().st_size, "sha256": sha(repo / name)}
        for name in sorted(names) if is_source(name) and (repo / name).is_file()
    }


def changed_dart(repo, base):
    names = set(git_paths(repo, ["diff", "--name-only", "--diff-filter=ACMR", base, "--"]))
    names.update(git_paths(repo, ["ls-files", "--others", "--exclude-standard"]))
    return sorted(name for name in names if name.endswith(".dart") and (repo / name).is_file())


def plan(repo, base):
    cohorts = []

    def add(name, package, files, kind="vm", fixture_keys=(), timeout=900):
        files = sorted(set(files))
        if not files:
            raise RuntimeError(f"Empty required cohort: {name}")
        missing = [name for name in files if not (repo / package / name).is_file()]
        if missing:
            raise RuntimeError(f"Missing required test files: {missing}")
        cohorts.append({"name": name, "package": package, "files": files,
                        "kind": kind, "fixture_keys": list(fixture_keys),
                        "timeout_seconds": timeout})

    for package in MAIL_PACKAGES:
        directory = repo / "packages" / package
        vm, javascript = [], []
        for path in sorted((directory / "test").rglob("*_test.dart")):
            header = path.read_text()[:1200]
            platform = re.search(r"@TestOn\(['\"]([^'\"]+)['\"]\)", header)
            relative = str(path.relative_to(directory))
            if platform and platform.group(1) in ("js", "node"):
                javascript.append(relative)
            elif platform and platform.group(1) == "browser":
                raise RuntimeError(f"New browser-only test requires an explicit plan: {path}")
            else:
                vm.append(relative)
        add(package + "-vm", "packages/" + package, vm)
        if javascript:
            add(package + "-node", "packages/" + package, javascript, kind="node")

    add("language-id-synthetic", "packages/quds_language_id", [
        "test/language_id_unit_test.dart", "test/language_id_native_transport_test.dart"
    ], fixture_keys=["QUDS_LANGUAGE_ID_FIXTURE_LIBRARY"])
    add("hunspell-synthetic", "packages/quds_proofing_hunspell", [
        "test/hunspell_provider_test.dart",
        "test/hunspell_installer_cancellation_test.dart",
        "test/hunspell_installer_cancellation_incoming_test.dart",
        "test/hunspell_native_lifecycle_test.dart",
        "test/native_lifecycle_test.dart", "test/provider_native_lifecycle_test.dart",
    ], fixture_keys=[item[2] for item in FIXTURES if item[0].startswith("hunspell")])
    add("arabic-morph-unit", "packages/quds_arabic_morph", [
        "test/arabic_morph_unit_test.dart"
    ])
    add("engine-language-arabic-proofing", "packages/quds_office_engine", [
        "test/office_thesaurus_test.dart", "test/word_complex_script_language_test.dart",
        "test/word_proofing_inheritance_test.dart", "test/word_proofing_language_test.dart",
        *["test/proofing/" + name + "_test.dart" for name in (
            "language_identification", "language_identification_calibration",
            "arabic_extended_rules", "arabic_grammar_rules", "arabic_writing_rules",
            "office_proofing", "office_proofing_merge", "proofing_locale",
            "proofing_report_merge", "proofing_text_ranges", "word_proofing_language",
        )],
    ])
    engine = repo / "packages/quds_office_engine"
    add("engine-incoming-macros-operations", "packages/quds_office_engine", [
        *[str(path.relative_to(engine)) for path in (engine / "test").glob("office_macro_*_test.dart")],
        "test/office_operations_test.dart", "test/office_steps_test.dart",
        "test/office_vba_integration_test.dart", "test/office_vba_language_test.dart",
        "test/word_step_atomicity_test.dart", "test/word_steps_vocabulary_test.dart",
        "test/word_structure_steps_test.dart", "test/table_grid_steps_test.dart",
        "test/word_table_grid_addressing_test.dart", "test/sheet_macro_preservation_test.dart",
    ])
    ui = repo / "packages/quds_mail_ui"
    add("mail-ui-widgets", "packages/quds_mail_ui", [
        str(path.relative_to(ui)) for path in (ui / "test").rglob("*_test.dart")
    ], kind="flutter")
    editor = repo / "packages/quds_office_editor"
    add("editor-proofing-language-widgets", "packages/quds_office_editor", [
        str(path.relative_to(editor)) for path in (editor / "test").glob("*_test.dart")
        if any(word in path.name for word in ("proofing", "language", "thesaurus", "arabic"))
    ], kind="flutter", timeout=1200)
    studio = repo / "packages/quds_office_editor/example"
    add("studio-mail-widgets", "packages/quds_office_editor/example", [
        str(path.relative_to(studio)) for path in (studio / "test").glob("*_test.dart")
        if path.name.startswith("studio_mail") or path.name == "studio_saved_mail_test.dart"
    ], kind="flutter", timeout=1200)
    add("studio-language-proofing-widgets", "packages/quds_office_editor/example", [
        "test/studio_language_id_test.dart", "test/studio_language_id_host_test.dart",
        "test/studio_arabic_morph_setup_test.dart", "test/studio_hunspell_setup_test.dart",
        "test/studio_hunspell_web_host_test.dart", "test/studio_hunspell_web_cancellation_test.dart",
        "test/studio_comment_draft_proofing_test.dart",
    ], kind="flutter", timeout=1200)

    selected = [item["package"] + "/" + path for item in cohorts for path in item["files"]]
    if len(selected) != len(set(selected)):
        raise RuntimeError("Test file appears in more than one cohort")
    excluded = {item["path"] for item in EXCLUSIONS}
    if excluded.intersection(selected):
        raise RuntimeError("A live-resource test leaked into the selected plan")
    modified = changed_dart(repo, base)
    analysis = set(modified)
    for package in (*MAIL_PACKAGES, "quds_mail_ui"):
        directory = repo / "packages" / package
        for child in ("lib", "test", "tool"):
            analysis.update(str(path.relative_to(repo)) for path in (directory / child).rglob("*.dart"))
    return {
        "baseline": capture(["git", "rev-parse", base + "^{commit}"], repo),
        "cohorts": cohorts, "test_file_count": len(selected),
        "format_files": modified, "analysis_files": sorted(analysis),
        "additional_gates": [
            {"name": "macro-web-compile", "source": "packages/quds_office_engine/tool/macros/web_smoke.dart",
             "purpose": "Compile the public macro/operations path to JavaScript with the real SDK."},
            {"name": "macro-web-node", "purpose": "Execute emitted JavaScript and require recalculation, atomic rollback and MCP inspection results."},
            {"name": "vba-web-compile", "source": "packages/quds_office_engine/tool/macros/web_vba_smoke.dart",
             "purpose": "Compile the portable Excel VBA subset to JavaScript with the real SDK."},
            {"name": "vba-web-node", "purpose": "Require numeric bounds/precedence, recalculation/style, validation/rollback byte preservation and MCP compile/playback results."},
        ],
        "excluded_files": EXCLUSIONS, "acceptance_limits": ACCEPTANCE_LIMITS,
    }


def parse_tests(path, repo):
    suites, starts, finishes, errors, done = {}, {}, {}, [], []
    non_json = 0
    for line in Path(path).read_text(errors="replace").splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            non_json += bool(line.strip())
            continue
        if not isinstance(event, dict):
            non_json += 1
            continue
        kind = event.get("type")
        if kind == "suite":
            suites[event["suite"]["id"]] = event["suite"]
        elif kind == "testStart":
            starts[event["test"]["id"]] = event["test"]
        elif kind == "testDone":
            ident = event["testID"]
            if ident in finishes:
                errors.append({"duplicate_test_done": ident})
            finishes[ident] = event
        elif kind == "error":
            errors.append(event)
        elif kind == "done":
            done.append(event)
    error_ids = {item.get("testID") for item in errors}
    cases, hidden_failures = [], []
    for ident, result in finishes.items():
        test = starts.get(ident)
        if test is None:
            errors.append({"test_done_without_start": ident})
            continue
        suite = suites.get(test.get("suiteID"), {})
        name = suite.get("path")
        if name:
            try:
                name = str(Path(name).resolve().relative_to(repo))
            except ValueError:
                pass
        status = "error" if ident in error_ids else result.get("result")
        row = {"file": name, "platform": suite.get("platform"), "name": test.get("name"),
               "result": status, "skipped": bool(result.get("skipped"))}
        if result.get("hidden"):
            if status != "success" or ident in error_ids:
                hidden_failures.append(row)
        else:
            cases.append(row)
    incomplete = [{"id": ident, "name": value.get("name")}
                  for ident, value in starts.items() if ident not in finishes]
    passed = sum(row["result"] == "success" and not row["skipped"] for row in cases)
    failed = sum(row["result"] != "success" and not row["skipped"] for row in cases)
    skipped = sum(row["skipped"] for row in cases)
    keys = [(row["file"], row["platform"], row["name"]) for row in cases]
    duplicates = len(keys) - len(set(keys))
    accepted = (len(done) == 1 and done[0].get("success") is True and passed > 0
                and failed == skipped == duplicates == 0 and not errors
                and not hidden_failures and not incomplete)
    return {"passed": passed, "failed": failed, "skipped": skipped, "cases": cases,
            "hidden_failures": hidden_failures, "incomplete": incomplete,
            "error_events": errors, "done_events": done, "duplicate_case_keys": duplicates,
            "non_json_lines": non_json, "accepted": accepted}


def package_root(config_file, item):
    uri = item["rootUri"]
    parsed = urlparse(uri)
    return Path(unquote(parsed.path)).resolve() if parsed.scheme == "file" else (
        config_file.parent / unquote(uri)
    ).resolve()


def dependency_manifest(config_file, pub_cache):
    config = json.loads(config_file.read_text())
    result = {}
    for package in config["packages"]:
        directory = package_root(config_file, package)
        if not directory.is_relative_to(pub_cache):
            continue
        files = set(directory.glob("pubspec.yaml"))
        for child in ("lib", "bin", "hook"):
            files.update(path for path in (directory / child).rglob("*") if path.is_file())
        for path in sorted(files):
            key = package["name"] + "/" + str(path.relative_to(directory))
            result[key] = {"bytes": path.stat().st_size, "sha256": sha(path)}
    return result


def sqlite_probe(path):
    library = ctypes.CDLL(str(path))
    library.sqlite3_libversion.restype = ctypes.c_char_p
    library.sqlite3_compileoption_used.argtypes = [ctypes.c_char_p]
    library.sqlite3_compileoption_used.restype = ctypes.c_int
    return {"path": str(path), "sha256": sha(path),
            "version": library.sqlite3_libversion().decode(),
            "fts5": bool(library.sqlite3_compileoption_used(b"ENABLE_FTS5"))}


class Runner:
    def __init__(self, args, selection):
        self.args, self.selection = args, selection
        self.repo, self.output = args.repo, args.output
        self.flutter = Path(os.environ["FLUTTER_ROOT"]).resolve()
        self.pub_cache = Path(os.environ["PUB_CACHE"]).resolve()
        self.dart = self.flutter / "bin/cache/dart-sdk/bin/dart"
        self.flutter_cli = self.flutter / "bin/flutter"
        self.compiler = Path(shutil.which("c++") or "/missing-cxx").resolve()
        self.node = Path(shutil.which("node") or "/missing-node").resolve()
        self.config = self.repo / ".dart_tool/package_config.json"
        packages = json.loads(self.config.read_text())["packages"]
        self.test_cli = package_root(self.config, next(p for p in packages if p["name"] == "test")) / "bin/test.dart"
        self.fixture_environment = {}
        self.steps = []
        self.receipt = {
            "schema": 1, "status": "prepared", "started_at_utc": now(),
            "github_actions_used": False, "dependency_resolution_performed": False,
            "source_baseline": selection["baseline"], "expected_head": args.expect_head,
            "selected_test_files": selection["test_file_count"],
            "excluded_files": EXCLUSIONS, "acceptance_limits": ACCEPTANCE_LIMITS,
            "steps": self.steps,
        }

    def save(self):
        write_json(self.output / "receipt.json", self.receipt)

    def preflight(self):
        if sys.platform != "linux":
            raise RuntimeError("This pinned final gate is Linux-only; qualify other native targets separately")
        for path in (self.dart, self.flutter_cli, self.compiler, self.node, self.test_cli,
                     self.args.production_manifest, self.args.runtime_receipt, self.args.sqlite_library,
                     self.repo / ".dart_tool/native_assets.yaml",
                     self.repo / "packages/quds_office_engine/tool/macros/web_smoke.dart",
                     self.repo / "packages/quds_office_engine/tool/macros/web_vba_smoke.dart",
                     self.flutter / "bin/cache/artifacts/engine/linux-x64/flutter_tester"):
            if not path.is_file():
                raise RuntimeError(f"Required runtime input is missing: {path}")
        head = capture(["git", "rev-parse", "HEAD"], self.repo)
        if head != self.args.expect_head:
            raise RuntimeError(f"HEAD does not match the frozen commit: {head}")
        dirty = git_paths(self.repo, ["diff", "--name-only", "HEAD", "--"])
        unknown = git_paths(self.repo, ["ls-files", "--others", "--exclude-standard"])
        unexpected = [name for name in (*dirty, *unknown)
                      if is_source(name) and name != "pubspec.yaml" and name not in DOCUMENT_INPUTS]
        if unexpected:
            raise RuntimeError(f"Product/test source must be committed before this gate: {unexpected}")
        production = self.args.production_manifest.read_bytes()
        committed = subprocess.check_output(["git", "show", "HEAD:pubspec.yaml"], cwd=self.repo)
        if production != committed:
            raise RuntimeError("Production root manifest does not equal the frozen commit")
        hook = ("\n# Temporary local validation hook; restore production manifest before publication.\n"
                "hooks:\n  user_defines:\n    sqlite3:\n      source: system\n      name: "
                + str(self.args.sqlite_library) + "\n").encode()
        if (self.repo / "pubspec.yaml").read_bytes() != production + hook:
            raise RuntimeError("Root manifest must differ only by the documented temporary system-SQLite hook")
        runtime = json.loads(self.args.runtime_receipt.read_text())
        if runtime.get("status") != "ready-system-sqlite" or runtime.get("archive", {}).get("verified") is not True:
            raise RuntimeError("Runtime receipt does not describe the verified official SDK/system-SQLite setup")
        for relative, expected in runtime.get("executables_sha256", {}).items():
            if sha(self.flutter / relative) != expected:
                raise RuntimeError(f"Official SDK executable identity changed: {relative}")
        locked = sha(self.repo / "pubspec.lock")
        if runtime.get("workspace_lock_sha256") != locked:
            raise RuntimeError("Resolved runtime receipt and workspace lockfile do not have the same hash")
        sqlite = sqlite_probe(self.args.sqlite_library)
        if not sqlite["fts5"]:
            raise RuntimeError("Pinned system SQLite lacks ENABLE_FTS5")
        for key in ("sha256", "version"):
            if sqlite[key] != runtime.get("system_sqlite", {}).get(key):
                raise RuntimeError("System SQLite differs from the verified setup receipt")
        self.receipt.update(
            source_head=head, source_tree=capture(["git", "rev-parse", "HEAD^{tree}"], self.repo),
            lock_sha256=locked, tested_manifest_sha256=sha(self.repo / "pubspec.yaml"),
            production_manifest_sha256=sha(self.args.production_manifest),
            temporary_hook="Documented sqlite3 user_defines source=system; not a production manifest change",
            sqlite=sqlite, runtime_receipt_sha256=sha(self.args.runtime_receipt),
            runtime_provenance={key: runtime.get(key) for key in
                                ("status", "archive", "runtime", "hosted_archives_verified")},
        )

    def runtime_manifest(self):
        paths = [Path(sys.executable).resolve(), self.dart, self.dart.with_name("dartvm"),
                 self.flutter_cli, self.compiler, self.node, self.test_cli, self.config,
                 self.repo / ".dart_tool/native_assets.yaml", self.args.sqlite_library,
                 self.args.production_manifest, self.args.runtime_receipt,
                 self.flutter / "bin/cache/flutter_tools.snapshot",
                 self.flutter / "bin/cache/flutter.version.json",
                 self.flutter / "bin/cache/artifacts/engine/linux-x64/flutter_tester",
                 self.flutter / "bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill",
                 self.flutter / "bin/cache/artifacts/engine/common/flutter_patched_sdk_product/platform_strong.dill",
                 self.flutter / "bin/cache/flutter_web_sdk/kernel/dart2js_platform.dill"]
        snapshots = self.dart.parent / "snapshots"
        for pattern in ("*kernel*", "*frontend*", "*dart2js*", "*analysis_server*"):
            paths.extend(snapshots.glob(pattern))
        paths.extend(Path(value) for value in self.fixture_environment.values())
        return {str(path.resolve()): {"bytes": path.stat().st_size, "sha256": sha(path)}
                for path in sorted(set(paths)) if path.is_file()}

    def step(self, name, command, cwd=None, kind="command", environment=None, timeout=900):
        directory = self.output / name
        directory.mkdir()
        cwd = cwd or self.repo
        overrides = {"CI": "true", "DART_SUPPRESS_ANALYTICS": "true",
                     "FLUTTER_SUPPRESS_ANALYTICS": "true", "DASH__SUPPRESS_ANALYTICS": "true",
                     **(environment or {})}
        env = os.environ.copy()
        for key in ("QUDS_ARABIC_MORPH_LIVE_DOWNLOAD", "QUDS_HUNSPELL_LIVE_DOWNLOAD"):
            env.pop(key, None)
        env.update(overrides)
        record = {"name": name, "kind": kind, "argv": list(map(str, command)), "cwd": str(cwd),
                  "environment_overrides": overrides, "timeout_seconds": timeout,
                  "started_at_utc": now()}
        write_json(directory / "command.json", record)
        print(json.dumps({"started": name}), flush=True)
        began = time.monotonic()
        process = None
        interrupted = False
        with (directory / "stdout.log").open("wb") as stdout, (directory / "stderr.log").open("wb") as stderr:
            try:
                process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stdout, stderr=stderr,
                                           start_new_session=True)
                record["exit_code"] = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                record.update(exit_code=None, timed_out=True)
            except KeyboardInterrupt:
                record.update(exit_code=None, interrupted=True)
                interrupted = True
            except OSError as error:
                record.update(exit_code=None, launch_error=str(error))
            finally:
                if process is not None and process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=5)
                    record["termination_exit_code"] = process.returncode
        record.update(finished_at_utc=now(), elapsed_seconds=round(time.monotonic() - began, 3),
                      stdout_sha256=sha(directory / "stdout.log"), stderr_sha256=sha(directory / "stderr.log"),
                      stdout_bytes=(directory / "stdout.log").stat().st_size,
                      stderr_bytes=(directory / "stderr.log").stat().st_size)
        record["accepted"] = record["exit_code"] == 0
        if kind == "tests":
            parsed = parse_tests(directory / "stdout.log", self.repo)
            write_manifest(directory / "test-cases.json.gz", parsed)
            record["test_counts"] = {key: parsed[key] for key in ("passed", "failed", "skipped")}
            record["accepted"] &= parsed["accepted"]
            record["test_cases_sha256"] = sha(directory / "test-cases.json.gz")
        elif kind in ("macro-smoke", "vba-smoke"):
            try:
                value = json.loads((directory / "stdout.log").read_text())
                expected = ({"revision": 1, "A1": 42, "A2": 84,
                             "lateFailurePreservedBytes": True, "mcpInspection": True}
                            if kind == "macro-smoke" else
                            {"language": "vba-excel", "revision": 2, "A3": 42, "B1": 84,
                             "fill": "0A141E", "validationPreservedBytes": True,
                             "lateFailurePreservedBytes": True, "mcpCompileAndRun": True,
                             "numericBoundsAndPrecedence": True})
                record["observed"] = value
                record["accepted"] &= value == expected
            except (ValueError, UnicodeError):
                record["accepted"] = False
                record["parse_error"] = "Portable smoke did not emit its required JSON result"
        write_json(directory / "result.json", record)
        self.steps.append(record)
        self.save()
        print(json.dumps({"finished": name, "exit_code": record["exit_code"],
                          "accepted": record["accepted"], "seconds": record["elapsed_seconds"],
                          "counts": record.get("test_counts")}), flush=True)
        if interrupted:
            raise KeyboardInterrupt
        if not record["accepted"] and not self.args.keep_going:
            raise RuntimeError(f"Required step failed: {name}; see its preserved stdout/stderr")
        return record

    def run(self):
        self.preflight()
        self.output.mkdir(parents=True, exist_ok=False)
        write_json(self.output / "selected-plan.json", self.selection)
        shutil.copyfile(__file__, self.output / "run-local-validation.py")
        shutil.copyfile(self.args.runtime_receipt, self.output / "runtime-setup-receipt.json")
        self.receipt.update(status="running", runner_sha256=sha(__file__),
                            plan_sha256=digest(self.selection))
        before = source_manifest(self.repo)
        dependencies_before = dependency_manifest(self.config, self.pub_cache)
        write_manifest(self.output / "source-before.json.gz", before)
        write_manifest(self.output / "dependencies-before.json.gz", dependencies_before)
        self.receipt.update(source_before_sha256=digest(before), source_file_count=len(before),
                            dependencies_before_sha256=digest(dependencies_before),
                            dependency_file_count=len(dependencies_before))
        self.save()
        runtime_before = None
        try:
            fixture_dir = self.output / "fixtures"
            fixture_dir.mkdir()
            for name, source, variable in FIXTURES:
                target = fixture_dir / (name + ".so")
                self.step("build-" + name, [self.compiler, "-std=c++17", "-shared", "-fPIC", "-O2",
                          "-pthread", self.repo / source, "-o", target], timeout=120)
                self.fixture_environment[variable] = str(target)
            runtime_before = self.runtime_manifest()
            write_manifest(self.output / "runtime-before.json.gz", runtime_before)
            self.receipt.update(runtime_before_sha256=digest(runtime_before),
                                versions={"dart": capture([str(self.dart), "--version"], self.repo),
                                          "node": capture([str(self.node), "--version"], self.repo),
                                          "compiler": capture([str(self.compiler), "--version"], self.repo),
                                          "python": sys.version})
            self.save()
            if self.selection["format_files"]:
                self.step("format-changed-dart", [self.dart, "format", "--output=none", "--set-exit-if-changed",
                          *self.selection["format_files"]])
            self.step("analyze-mail-and-changed-dart", [self.dart, "analyze", "--fatal-infos", "--fatal-warnings",
                      *self.selection["analysis_files"]])
            for cohort in self.selection["cohorts"]:
                if cohort["kind"] == "flutter":
                    command = [self.flutter_cli, "test", "--no-pub", "--concurrency=1", "--reporter=json"]
                else:
                    command = [self.dart, "--disable-dart-dev", "--packages=" + str(self.config),
                               self.test_cli, "--platform=" + ("node" if cohort["kind"] == "node" else "vm"),
                               "--compiler=" + ("dart2js" if cohort["kind"] == "node" else "kernel"),
                               "--reporter=json", "--concurrency=1"]
                self.step(cohort["name"], command + cohort["files"],
                          cwd=self.repo / cohort["package"], kind="tests",
                          environment={key: self.fixture_environment[key] for key in cohort["fixture_keys"]},
                          timeout=cohort["timeout_seconds"])
            javascript = self.output / "macro-web-smoke.js"
            self.step("macro-web-compile", [self.dart, "compile", "js", "--packages=" + str(self.config),
                      "-O1", "tool/macros/web_smoke.dart", "-o", javascript],
                      cwd=self.repo / "packages/quds_office_engine")
            self.step("macro-web-node", [self.node, "-e",
                      "globalThis.self = globalThis; require(process.argv[1])", javascript], kind="macro-smoke")
            self.receipt["macro_javascript_sha256"] = sha(javascript)
            vba_javascript = self.output / "vba-web-smoke.js"
            self.step("vba-web-compile", [self.dart, "compile", "js", "--packages=" + str(self.config),
                      "-O1", "tool/macros/web_vba_smoke.dart", "-o", vba_javascript],
                      cwd=self.repo / "packages/quds_office_engine")
            self.step("vba-web-node", [self.node, "-e",
                      "globalThis.self = globalThis; require(process.argv[1])", vba_javascript], kind="vba-smoke")
            self.receipt["vba_javascript_sha256"] = sha(vba_javascript)
            self.receipt["status"] = "passed" if all(item["accepted"] for item in self.steps) else "failed"
        except KeyboardInterrupt:
            self.receipt.update(status="interrupted", error="Operator interrupted local validation")
        except Exception as error:
            self.receipt.update(status="failed", error=f"{type(error).__name__}: {error}")
        finally:
            after = source_manifest(self.repo)
            dependencies_after = dependency_manifest(self.config, self.pub_cache)
            write_manifest(self.output / "source-after.json.gz", after)
            write_manifest(self.output / "dependencies-after.json.gz", dependencies_after)
            source_changed = sorted(name for name in set(before) | set(after) if before.get(name) != after.get(name))
            dependencies_changed = sorted(name for name in set(dependencies_before) | set(dependencies_after)
                                          if dependencies_before.get(name) != dependencies_after.get(name))
            runtime_changed = []
            if runtime_before is not None:
                runtime_after = self.runtime_manifest()
                write_manifest(self.output / "runtime-after.json.gz", runtime_after)
                runtime_changed = sorted(name for name in set(runtime_before) | set(runtime_after)
                                         if runtime_before.get(name) != runtime_after.get(name))
                self.receipt["runtime_after_sha256"] = digest(runtime_after)
            self.receipt.update(source_after_sha256=digest(after), source_changed_paths=source_changed,
                                dependencies_after_sha256=digest(dependencies_after),
                                dependencies_changed_paths=dependencies_changed,
                                runtime_changed_paths=runtime_changed, finished_at_utc=now(),
                                head_after=capture(["git", "rev-parse", "HEAD"], self.repo),
                                lock_sha256_after=sha(self.repo / "pubspec.lock"))
            self.receipt["inputs_stable"] = (
                not source_changed and not dependencies_changed and not runtime_changed
                and self.receipt["head_after"] == self.receipt["source_head"]
                and self.receipt["lock_sha256_after"] == self.receipt["lock_sha256"]
            )
            executed = {item["name"] for item in self.steps if item["kind"] == "tests"}
            self.receipt["unexecuted_cohorts"] = [item["name"] for item in self.selection["cohorts"]
                                                   if item["name"] not in executed]
            self.receipt["test_totals"] = {
                key: sum(item.get("test_counts", {}).get(key, 0) for item in self.steps)
                for key in ("passed", "failed", "skipped")
            }
            if not self.receipt["inputs_stable"] or self.receipt["unexecuted_cohorts"]:
                if self.receipt["status"] != "interrupted":
                    self.receipt["status"] = "failed"
            self.save()
            compact = {key: value for key, value in self.receipt.items() if key != "steps"}
            compact["cohorts"] = [{key: item.get(key) for key in
                                  ("name", "exit_code", "accepted", "elapsed_seconds", "test_counts",
                                   "stdout_sha256", "stderr_sha256", "test_cases_sha256")}
                                 for item in self.steps]
            compact["evidence_directory"] = str(self.output)
            compact["receipt_sha256"] = sha(self.output / "receipt.json")
            write_json(self.output / "compact-receipt.json", compact)
        print(json.dumps({"status": self.receipt["status"], "counts": self.receipt["test_totals"],
                          "inputs_stable": self.receipt["inputs_stable"],
                          "receipt": str(self.output / "compact-receipt.json")}), flush=True)
        return 0 if self.receipt["status"] == "passed" else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--base-ref", default=BASELINE)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--expect-head")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--runtime-receipt", type=Path)
    parser.add_argument("--production-manifest", type=Path)
    parser.add_argument("--sqlite-library", type=Path)
    parser.add_argument("--keep-going", action="store_true", help="Preserve all failures without retries; final status still fails")
    args = parser.parse_args()
    args.repo = args.repo.resolve()
    selection = plan(args.repo, args.base_ref)
    if args.plan_only:
        print(json.dumps(selection, indent=2, sort_keys=True))
        return 0
    for name in ("expect_head", "output", "runtime_receipt", "production_manifest", "sqlite_library"):
        if getattr(args, name) is None:
            parser.error("--" + name.replace("_", "-") + " is required for an executing run")
    for name in ("output", "runtime_receipt", "production_manifest"):
        setattr(args, name, getattr(args, name).resolve())
    # Preserve the exact absolute spelling in the temporary hook; /lib may be
    # a symlink to /usr/lib while both identify the same verified binary.
    args.sqlite_library = args.sqlite_library.absolute()
    if args.output.exists() or args.output.is_relative_to(args.repo):
        parser.error("--output must be a new directory outside the repository")
    return Runner(args, selection).run()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Local validation preflight failed: {type(error).__name__}: {error}", file=sys.stderr)
        raise SystemExit(2)

#!/usr/bin/env python3
"""Reproducible local mail portability qualification; no dependency resolution or CI.

Use --plan-only before the source freeze. An executing run requires an exact
committed HEAD, a clean checkout, verified SDK/dependency and readiness receipts,
and sqlite3's unchanged default packaged native asset. This script never edits
manifests or dependencies. Output must be a new directory outside the repository.
Failed, incomplete, skipped, undiscovered, or input-changing runs never pass.

Preparation (from the checkout, after sourcing the runtime's env.sh):
  python3 docs/validation/mail-archive-portability-20261119/run-local-validation.py --plan-only

Execution after committing the entire checkout (replace the SHA and paths):
  python3 docs/validation/mail-archive-portability-20261119/run-local-validation.py \\
    --expect-head FULL_40_CHARACTER_COMMIT_SHA --output /scratch/new-evidence \\
    --runtime-receipt /scratch/runtime/runtime.json \\
    --readiness-receipt /scratch/runtime/readiness-receipt.json

Each gate writes command.json before starting, containing its exact argv, cwd,
runtime directories, fixture variables and timeout. Reproduce that array as a
subprocess with the same environment, or rerun this harness against the same
frozen commit with a fresh output directory. No command resolves dependencies.
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


BASELINE = "81ae98688860599f118748afca19bdb2ec45da37"
SCRIPT_PATH = "docs/validation/mail-archive-portability-20261119/run-local-validation.py"
MACOS_BUILD_SCRIPT = "packages/quds_office_editor/example/tool/build_macos_app.sh"
MACOS_NATIVE_GATE = "packages/quds_office_editor/example/test/studio_macos_bundle_native_gate.dart"
SDK_ARCHIVE_SHA256 = "baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2"
SQLITE_NATIVE_SHA256 = "0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b"
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
    "docs/validation/mail-archive-portability-20261119/README.md",
    "docs/validation/office-vba-procedures-20261119/stress/procedure_depth.dart",
    SCRIPT_PATH,
}
HISTORICAL_DART_EVIDENCE = [{
    "path": "docs/validation/office-vba-procedures-20261119/stress/procedure_depth.dart",
    "reason": "Retained prior evidence from a reduced workspace. Its original formatting and package context are preserved; the root-workspace dependency lint does not apply to that archived environment. This exact file is hashed, but excluded from fresh formatting and analysis. Current package procedure suites and the procedures JavaScript smoke are executed afresh.",
}]
FIXTURES = (
    ("language-id", "packages/quds_language_id/test/fixtures/native_transport_fixture.cpp",
     "QUDS_LANGUAGE_ID_FIXTURE_LIBRARY"),
)
EXCLUSIONS = [
    {"path": "packages/quds_language_id/test/language_id_native_test.dart",
     "reason": "Incoming changes correct the real model smoke expectation. This suite requires the real native CLD3 classifier and verified model, not the allocation-counter fixture. It is formatted and analyzed, but no real-model acceptance is claimed."},
    {"path": MACOS_NATIVE_GATE,
     "reason": "Manual installed-macOS bundle gate. It is formatted and analyzed, but execution requires macOS, the built application with all four native libraries and verified CLD3 model, and installed AyaSpell/CamelMorph data. Linux validation does not qualify that bundle."},
]
ACCEPTANCE_LIMITS = [
    "No live IMAP, SMTP, EWS, Gmail or Microsoft 365 credentials or service requests; transport tests use injected fakes or local loopback servers.",
    "Language-ID synthetic unit and native transport/lifecycle checks do not qualify the real classifier or model-card accuracy; the changed real-model smoke test is explicitly excluded from execution.",
    "Node tests cover declared JavaScript boundaries and portable macro/VBA execution; no browser interaction, browser archive, or full web build is claimed.",
    "Linux native SQLite and actual POSIX crash tests only; no installed macOS/Windows/mobile application, signing, Keychain, or OAuth account acceptance.",
    "The incoming macOS build script receives bash -n syntax validation only; no macOS build, dylib loading, signing, entitlement or installed proofing-data execution is performed.",
    "The unmodified sqlite3 3.9.1 default Linux x64 packaged library is verified by its pinned SHA-256. Other native platform binaries are not qualified by this run.",
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
            header = path.read_text()[:4000]
            platform = re.search(r"@TestOn\(['\"]([^'\"]+)['\"]\)", header)
            relative = str(path.relative_to(directory))
            if platform and platform.group(1) in ("js", "node"):
                javascript.append(relative)
            elif platform and platform.group(1) not in ("vm",):
                raise RuntimeError(f"New platform expression requires an explicit plan: {path}")
            else:
                vm.append(relative)
        add(package + "-vm", "packages/" + package, vm)
        if javascript:
            add(package + "-node", "packages/" + package, javascript, kind="node")

    language = repo / "packages/quds_language_id"
    excluded = {item["path"] for item in EXCLUSIONS}
    add("language-id-synthetic", "packages/quds_language_id", [
        str(path.relative_to(language)) for path in (language / "test").rglob("*_test.dart")
        if str(path.relative_to(repo)) not in excluded
    ], fixture_keys=["QUDS_LANGUAGE_ID_FIXTURE_LIBRARY"])
    engine = repo / "packages/quds_office_engine"
    engine_tests = [str(path.relative_to(engine))
                    for path in (engine / "test").rglob("*_test.dart")
                    if path.name.startswith(("office_macro_", "office_vba_"))]
    engine_tests.extend("test/" + name for name in (
        "office_operations_test.dart", "office_steps_test.dart",
        "word_step_atomicity_test.dart", "word_steps_vocabulary_test.dart",
        "word_structure_steps_test.dart", "table_grid_steps_test.dart",
        "word_table_grid_addressing_test.dart", "sheet_macro_preservation_test.dart",
    ))
    add("engine-incoming-macros-operations", "packages/quds_office_engine", engine_tests)
    ui = repo / "packages/quds_mail_ui"
    add("mail-ui-widgets", "packages/quds_mail_ui", [
        str(path.relative_to(ui)) for path in (ui / "test").rglob("*_test.dart")
    ], kind="flutter", timeout=1200)
    studio = repo / "packages/quds_office_editor/example"
    add("studio-mail-widgets", "packages/quds_office_editor/example", [
        str(path.relative_to(studio)) for path in (studio / "test").rglob("*_test.dart")
        if path.name.startswith("studio_mail") or path.name == "studio_saved_mail_test.dart"
    ], kind="flutter", timeout=1200)

    selected = [item["package"] + "/" + path for item in cohorts for path in item["files"]]
    if len(selected) != len(set(selected)):
        raise RuntimeError("Test file appears in more than one cohort")
    if excluded.intersection(selected):
        raise RuntimeError("An explicitly excluded test leaked into the execution plan")
    modified = changed_dart(repo, base)
    preserved_evidence = {item["path"] for item in HISTORICAL_DART_EVIDENCE}
    unknown_evidence = [path for path in modified if path.startswith("docs/validation/")
                        and path not in preserved_evidence]
    if unknown_evidence:
        raise RuntimeError("Historical Dart evidence requires explicit classification: " + repr(unknown_evidence))
    product_modified = sorted(set(modified) - preserved_evidence)
    unaccounted = sorted(path for path in modified if path.endswith("_test.dart")
                         and path not in selected and path not in excluded)
    if unaccounted:
        raise RuntimeError("Changed test files require an explicit plan: " + repr(unaccounted))
    analysis = set(product_modified) | set(selected)
    for package in (*MAIL_PACKAGES, "quds_mail_ui"):
        directory = repo / "packages" / package
        for child in ("lib", "test", "tool"):
            analysis.update(str(path.relative_to(repo)) for path in (directory / child).rglob("*.dart"))
    analysis.update(str(path.relative_to(repo)) for path in (studio / "lib").rglob("*.dart")
                    if path.name.startswith(("studio_mail", "studio_saved_mail")))
    additional = [
        {"name": "macos-build-script-syntax", "source": MACOS_BUILD_SCRIPT,
         "purpose": "Parse the incoming macOS build script with bash -n without executing its build, packaging or signing commands."},
        {"name": "macro-web-compile", "source": "packages/quds_office_engine/tool/macros/web_smoke.dart",
         "purpose": "Compile the public macro/operations path with the verified SDK."},
        {"name": "macro-web-node", "purpose": "Require recalculation, atomic rollback and MCP inspection results from emitted JavaScript."},
        {"name": "vba-web-compile", "source": "packages/quds_office_engine/tool/macros/web_vba_smoke.dart",
         "purpose": "Compile the portable Excel VBA implementation with the verified SDK."},
        {"name": "vba-web-node", "purpose": "Require numeric bounds, precedence, formatting, rollback, and MCP results from emitted JavaScript."},
        {"name": "vba-procedures-web-compile", "source": "packages/quds_office_engine/tool/macros/web_vba_procedures_smoke.dart",
         "purpose": "Compile reusable VBA procedures, functions and early exits with the verified SDK."},
        {"name": "vba-procedures-web-node", "purpose": "Require isolated call scopes, exits, recursion refusal, shared work bounds, atomic rollback and MCP helper execution."},
    ]
    required = (["build-" + item[0] for item in FIXTURES]
                + (["format-changed-dart"] if product_modified else [])
                + ["analyze-mail-and-changed-dart"]
                + [item["name"] for item in cohorts]
                + [item["name"] for item in additional])
    if len(required) != len(set(required)):
        raise RuntimeError("Required gate names are not unique")
    return {
        "baseline": capture(["git", "rev-parse", base + "^{commit}"], repo),
        "cohorts": cohorts, "test_file_count": len(selected),
        "format_files": product_modified, "analysis_files": sorted(analysis),
        "retained_prior_dart_evidence": HISTORICAL_DART_EVIDENCE,
        "additional_gates": additional, "required_gates": required,
        "excluded_files": EXCLUSIONS,
        "changed_excluded_tests": sorted(excluded.intersection(modified)),
        "acceptance_limits": ACCEPTANCE_LIMITS,
    }


def parse_tests(path, repo, expected_files=(), suite_cwd=None):
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
            ident = event["test"]["id"]
            if ident in starts:
                errors.append({"duplicate_test_start": ident})
            starts[ident] = event["test"]
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
                parsed = urlparse(name)
                suite_path = Path(unquote(parsed.path)) if parsed.scheme == "file" else Path(name)
                if not suite_path.is_absolute():
                    suite_path = (suite_cwd or repo) / suite_path
                name = str(suite_path.resolve().relative_to(repo))
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
    observed_files = {row["file"] for row in cases}
    expected = set(expected_files)
    missing_files = sorted(expected - observed_files)
    unexpected_files = sorted(path for path in observed_files if path not in expected) if expected else []
    accepted = (not missing_files and not unexpected_files
                and len(done) == 1 and done[0].get("success") is True and passed > 0
                and failed == skipped == duplicates == 0 and not errors
                and not hidden_failures and not incomplete)
    return {"passed": passed, "failed": failed, "skipped": skipped, "cases": cases,
            "hidden_failures": hidden_failures, "incomplete": incomplete,
            "error_events": errors, "done_events": done, "duplicate_case_keys": duplicates,
            "non_json_lines": non_json, "expected_files": sorted(expected),
            "missing_files": missing_files, "unexpected_files": unexpected_files,
            "accepted": accepted}


def package_root(config_file, item):
    uri = item["rootUri"]
    parsed = urlparse(uri)
    return Path(unquote(parsed.path)).resolve() if parsed.scheme == "file" else (
        config_file.parent / unquote(uri)
    ).resolve()


def dependency_manifest(config_file, pub_cache, flutter, repo):
    result = {}
    configurations = {
        "workspace": config_file,
        "flutter-tools": flutter / "packages/flutter_tools/.dart_tool/package_config.json",
    }
    for origin, configuration in configurations.items():
        config = json.loads(configuration.read_text())
        for package in config["packages"]:
            directory = package_root(configuration, package)
            if directory.is_relative_to(repo):
                continue
            if not (directory.is_relative_to(pub_cache) or directory.is_relative_to(flutter)):
                raise RuntimeError("Uncaptured external package root: " + str(directory))
            files = set(directory.glob("pubspec.yaml"))
            for child in ("lib", "bin", "hook"):
                files.update(path for path in (directory / child).rglob("*") if path.is_file())
            for path in sorted(files):
                key = origin + "/" + package["name"] + "/" + str(path.relative_to(directory))
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
        self.flutter_cli = Path(shutil.which("flutter") or str(self.flutter / "bin/flutter")).absolute()
        self.compiler = Path(shutil.which("c++") or "/missing-cxx").resolve()
        self.node = Path(shutil.which("node") or "/missing-node").resolve()
        self.bash = Path(shutil.which("bash") or "/missing-bash").resolve()
        self.config = self.repo / ".dart_tool/package_config.json"
        packages = json.loads(self.config.read_text())["packages"]
        self.test_cli = package_root(self.config, next(p for p in packages if p["name"] == "test")) / "bin/test.dart"
        self.fixture_environment = {}
        self.native_paths = []
        self.sqlite_library = self.repo / ".dart_tool/lib/libsqlite3.so"
        self.steps = []
        self.receipt = {
            "schema": 2, "status": "prepared", "started_at_utc": now(),
            "github_actions_used": False, "dependency_resolution_performed": False,
            "source_baseline": selection["baseline"], "expected_head": args.expect_head,
            "selected_test_files": selection["test_file_count"],
            "excluded_files": EXCLUSIONS, "acceptance_limits": ACCEPTANCE_LIMITS,
            "retained_prior_dart_evidence": HISTORICAL_DART_EVIDENCE,
            "steps": self.steps,
        }

    def save(self):
        write_json(self.output / "receipt.json", self.receipt)

    def preflight(self):
        if sys.platform != "linux":
            raise RuntimeError("This pinned gate is Linux-only; qualify other native targets separately")
        for path in (self.dart, self.flutter_cli, self.compiler, self.node, self.bash, self.test_cli,
                     self.args.runtime_receipt, self.args.readiness_receipt,
                     self.sqlite_library, self.repo / ".dart_tool/native_assets.yaml",
                     self.repo / "packages/quds_office_engine/tool/macros/web_smoke.dart",
                     self.repo / "packages/quds_office_engine/tool/macros/web_vba_smoke.dart",
                     self.repo / "packages/quds_office_engine/tool/macros/web_vba_procedures_smoke.dart",
                     self.repo / MACOS_BUILD_SCRIPT, self.repo / MACOS_NATIVE_GATE,
                     self.flutter / "bin/cache/artifacts/engine/linux-x64/flutter_tester"):
            if not path.is_file():
                raise RuntimeError(f"Required runtime input is missing: {path}")
        if not re.fullmatch(r"[0-9a-f]{40}", self.args.expect_head):
            raise RuntimeError("--expect-head must contain a full commit SHA")
        head = capture(["git", "rev-parse", "HEAD"], self.repo)
        if head != self.args.expect_head:
            raise RuntimeError(f"HEAD does not match the frozen commit: {head}")
        subprocess.run(["git", "merge-base", "--is-ancestor", self.selection["baseline"], head],
                       cwd=self.repo, check=True)
        dirty = git_paths(self.repo, ["diff", "--name-only", "HEAD", "--"])
        unknown = git_paths(self.repo, ["ls-files", "--others", "--exclude-standard"])
        if dirty or unknown:
            raise RuntimeError("Commit the entire checkout before the gate: " + repr(sorted(set(dirty + unknown))))
        tracked = set(git_paths(self.repo, ["ls-files", "--cached"]))
        planned_inputs = (set(self.selection["format_files"]) | set(self.selection["analysis_files"])
                          | {item[1] for item in FIXTURES}
                          | {item["source"] for item in self.selection["additional_gates"] if "source" in item})
        if planned_inputs - tracked:
            raise RuntimeError("Selected inputs must be committed files: " + repr(sorted(planned_inputs - tracked)))
        if sha(__file__) != sha(self.repo / SCRIPT_PATH):
            raise RuntimeError("Executing harness differs from the frozen repository harness")
        for name in ("pubspec.yaml", "pubspec.lock", ".fvmrc"):
            if (self.repo / name).read_bytes() != subprocess.check_output(["git", "show", "HEAD:" + name], cwd=self.repo):
                raise RuntimeError("Production input differs from the frozen commit: " + name)
        runtime = json.loads(self.args.runtime_receipt.read_text())
        readiness = json.loads(self.args.readiness_receipt.read_text())
        if (runtime.get("status") != "ready"
                or runtime.get("archive", {}).get("verified") is not True
                or runtime.get("archive", {}).get("sha256") != SDK_ARCHIVE_SHA256):
            raise RuntimeError("Runtime receipt does not describe the pinned verified official SDK")
        if readiness.get("status") != "ready" or not readiness.get("runs") or any(
            run.get("exit_code") != 0 for run in readiness["runs"]
        ):
            raise RuntimeError("Readiness receipt contains incomplete or failed checks")
        pin = json.loads((self.repo / ".fvmrc").read_text())["flutter"]
        if runtime.get("runtime", {}).get("frameworkVersion") != pin:
            raise RuntimeError("The runtime does not match the repository Flutter pin")
        executables = runtime.get("executables_sha256", {})
        for key, expected in executables.items():
            path = Path(key)
            if not path.is_absolute():
                path = self.flutter / path
            path = path.resolve()
            if not path.is_relative_to(self.flutter) or sha(path) != expected:
                raise RuntimeError("Official SDK executable identity changed: " + str(path))
        required_executables = {
            self.dart.resolve(),
            (self.flutter / "bin/cache/artifacts/engine/linux-x64/flutter_tester").resolve(),
        }
        recorded_executables = {((Path(key) if Path(key).is_absolute() else self.flutter / key).resolve())
                                for key in executables}
        if not required_executables.issubset(recorded_executables):
            raise RuntimeError("Runtime receipt does not bind both SDK executables")
        locked = sha(self.repo / "pubspec.lock")
        if runtime.get("workspace_lock_sha256") != locked:
            raise RuntimeError("Resolved SDK receipt and workspace lockfile differ")
        native_manifest = self.repo / ".dart_tool/native_assets.yaml"
        mapping = json.loads("\n".join(line for line in native_manifest.read_text().splitlines()
                                     if not line.lstrip().startswith("#")))
        expected_mapping = {
            "format-version": [1, 0, 0],
            "native-assets": {"linux_x64": {
                "package:sqlite3/src/ffi/libsqlite3.g.dart": ["absolute", str(self.sqlite_library)]
            }},
        }
        if mapping != expected_mapping:
            raise RuntimeError("Native mapping is not the unchanged default sqlite3 Linux x64 output")
        sqlite = sqlite_probe(self.sqlite_library)
        recorded_native = readiness.get("native_assets", {})
        if (not sqlite["fts5"] or sqlite["sha256"] != SQLITE_NATIVE_SHA256
                or sqlite["sha256"] != recorded_native.get("library_sha256")
                or sqlite["version"] != recorded_native.get("version")
                or sha(native_manifest) != recorded_native.get("manifest_sha256")):
            raise RuntimeError("Native packaged SQLite differs from verified readiness")
        hook_library = (self.repo / ".dart_tool/hooks_runner/shared/sqlite3/build"
                        / ("download-" + SQLITE_NATIVE_SHA256[:8]) / "libsqlite3.so")
        if not hook_library.is_file() or sha(hook_library) != SQLITE_NATIVE_SHA256:
            raise RuntimeError("Cached default native hook input differs from its pinned binary")
        self.native_paths = [native_manifest, self.sqlite_library, hook_library]
        self.receipt.update(
            source_head=head, source_tree=capture(["git", "rev-parse", "HEAD^{tree}"], self.repo),
            lock_sha256=locked, production_manifest_sha256=sha(self.repo / "pubspec.yaml"),
            production_manifest_unchanged=True, sqlite=sqlite,
            native_asset_provenance="Unmodified sqlite3 3.9.1 default packaged Linux x64 build hook",
            runtime_receipt_sha256=sha(self.args.runtime_receipt),
            readiness_receipt_sha256=sha(self.args.readiness_receipt),
            runtime_provenance={key: runtime.get(key) for key in
                                ("status", "archive", "runtime", "hosted_archives_verified")},
        )

    def runtime_manifest(self):
        paths = {Path(sys.executable).resolve(), self.dart, self.dart.with_name("dartvm"),
                 self.flutter_cli, self.compiler, self.node, self.bash, self.test_cli, self.config,
                 self.args.runtime_receipt, self.args.readiness_receipt,
                 self.flutter / "packages/flutter_tools/.dart_tool/package_config.json",
                 self.flutter / "bin/cache/flutter_tools.snapshot",
                 self.flutter / "bin/cache/flutter.version.json"}
        for prefix in (
            self.dart.parent / "snapshots",
            self.dart.parent.parent / "lib",
            self.flutter / "bin/cache/artifacts/engine/linux-x64",
            self.flutter / "bin/cache/artifacts/engine/common/flutter_patched_sdk",
            self.flutter / "bin/cache/artifacts/engine/common/flutter_patched_sdk_product",
            self.flutter / "bin/cache/flutter_web_sdk/kernel",
        ):
            paths.update(path for path in prefix.rglob("*") if path.is_file())
        paths.update(self.native_paths)
        paths.update(Path(value) for value in self.fixture_environment.values())
        return {str(path.absolute()): {"bytes": path.stat().st_size, "sha256": sha(path)}
                for path in sorted(paths) if path.is_file()}

    def step(self, name, command, cwd=None, kind="command", environment=None, timeout=900,
             expected_files=()):
        directory = self.output / name
        directory.mkdir()
        cwd = cwd or self.repo
        overrides = {"CI": "true", "DART_SUPPRESS_ANALYTICS": "true",
                     "FLUTTER_SUPPRESS_ANALYTICS": "true", "DASH__SUPPRESS_ANALYTICS": "true",
                     **(environment or {})}
        env = os.environ.copy()
        for key in list(env):
            if key.startswith("QUDS_"):
                env.pop(key)
        env.update(overrides)
        record = {"name": name, "kind": kind, "argv": list(map(str, command)), "cwd": str(cwd),
                  "environment_overrides": overrides, "timeout_seconds": timeout,
                  "expected_test_files": list(expected_files),
                  "runtime_environment": {key: env.get(key) for key in
                      ("PUB_CACHE", "FLUTTER_ROOT", "TMPDIR", "XDG_CONFIG_HOME",
                       "XDG_CACHE_HOME", "XDG_DATA_HOME")},
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
            parsed = parse_tests(directory / "stdout.log", self.repo, expected_files, cwd)
            write_manifest(directory / "test-cases.json.gz", parsed)
            record["test_counts"] = {key: parsed[key] for key in ("passed", "failed", "skipped")}
            record["accepted"] &= parsed["accepted"]
            record["test_cases_sha256"] = sha(directory / "test-cases.json.gz")
            record["missing_test_files"] = parsed["missing_files"]
            record["unexpected_test_files"] = parsed["unexpected_files"]
        elif kind in ("macro-smoke", "vba-smoke", "vba-procedures-smoke"):
            try:
                value = json.loads((directory / "stdout.log").read_text())
                expected = {
                    "macro-smoke": {
                        "revision": 1, "A1": 42, "A2": 84,
                        "lateFailurePreservedBytes": True, "mcpInspection": True,
                    },
                    "vba-smoke": {
                        "language": "vba-excel", "revision": 2, "A3": 42, "B1": 84,
                        "fill": "0A141E", "validationPreservedBytes": True,
                        "lateFailurePreservedBytes": True, "mcpCompileAndRun": True,
                        "numericBoundsAndPrecedence": True,
                    },
                    "vba-procedures-smoke": {
                        "language": "vba-excel", "revision": 2, "steps": 6,
                        "byValCallerAmount": 21, "exitForCounter": 4, "formulaTotal": 126,
                        "procedureScopesAndExits": True, "recursionRejected": True,
                        "sharedWorkBudget": True, "numericBounds": True,
                        "validationPreservedBytes": True, "lateFailurePreservedBytes": True,
                        "mcpCompileAndRun": True,
                    },
                }[kind]
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
        self.output.mkdir(parents=True, exist_ok=False)
        write_json(self.output / "selected-plan.json", self.selection)
        try:
            self.preflight()
        except Exception as error:
            self.receipt.update(status="failed", phase="preflight", error=f"{type(error).__name__}: {error}",
                                finished_at_utc=now())
            self.save()
            raise
        shutil.copyfile(__file__, self.output / "run-local-validation.py")
        shutil.copyfile(self.args.runtime_receipt, self.output / "runtime-setup-receipt.json")
        shutil.copyfile(self.args.readiness_receipt, self.output / "runtime-readiness-receipt.json")
        self.receipt.update(status="running", runner_sha256=sha(__file__),
                            plan_sha256=digest(self.selection))
        before = source_manifest(self.repo)
        dependencies_before = dependency_manifest(self.config, self.pub_cache, self.flutter, self.repo)
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
            self.step("macos-build-script-syntax", [self.bash, "-n", MACOS_BUILD_SCRIPT],
                      environment={"BASH_ENV": "", "ENV": ""}, timeout=60)
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
                          timeout=cohort["timeout_seconds"],
                          expected_files=[cohort["package"] + "/" + path for path in cohort["files"]])
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
            procedures_javascript = self.output / "vba-procedures-web-smoke.js"
            self.step("vba-procedures-web-compile", [self.dart, "compile", "js", "--packages=" + str(self.config),
                      "-O1", "tool/macros/web_vba_procedures_smoke.dart", "-o", procedures_javascript],
                      cwd=self.repo / "packages/quds_office_engine")
            self.step("vba-procedures-web-node", [self.node, "-e",
                      "globalThis.self = globalThis; require(process.argv[1])", procedures_javascript],
                      kind="vba-procedures-smoke")
            self.receipt["vba_procedures_javascript_sha256"] = sha(procedures_javascript)
            self.receipt["status"] = "passed" if all(item["accepted"] for item in self.steps) else "failed"
        except KeyboardInterrupt:
            self.receipt.update(status="interrupted", error="Operator interrupted local validation")
        except Exception as error:
            self.receipt.update(status="failed", error=f"{type(error).__name__}: {error}")
        finally:
            after = source_manifest(self.repo)
            dependencies_after = dependency_manifest(self.config, self.pub_cache, self.flutter, self.repo)
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
                                tree_after=capture(["git", "rev-parse", "HEAD^{tree}"], self.repo),
                                tracked_changes_after=git_paths(self.repo, ["diff", "--name-only", "HEAD", "--"]),
                                untracked_files_after=git_paths(self.repo, ["ls-files", "--others", "--exclude-standard"]),
                                lock_sha256_after=sha(self.repo / "pubspec.lock"),
                                production_manifest_sha256_after=sha(self.repo / "pubspec.yaml"))
            self.receipt["inputs_stable"] = (
                not source_changed and not dependencies_changed and not runtime_changed
                and self.receipt["head_after"] == self.receipt["source_head"]
                and self.receipt["tree_after"] == self.receipt["source_tree"]
                and self.receipt["lock_sha256_after"] == self.receipt["lock_sha256"]
                and self.receipt["production_manifest_sha256_after"] == self.receipt["production_manifest_sha256"]
                and not self.receipt["tracked_changes_after"] and not self.receipt["untracked_files_after"]
            )
            executed = {item["name"] for item in self.steps if item["kind"] == "tests"}
            self.receipt["unexecuted_cohorts"] = [item["name"] for item in self.selection["cohorts"]
                                                   if item["name"] not in executed]
            executed_gates = {item["name"] for item in self.steps}
            self.receipt["unexecuted_gates"] = [name for name in self.selection["required_gates"]
                                                if name not in executed_gates]
            self.receipt["test_totals"] = {
                key: sum(item.get("test_counts", {}).get(key, 0) for item in self.steps)
                for key in ("passed", "failed", "skipped")
            }
            if (not self.receipt["inputs_stable"] or self.receipt["unexecuted_cohorts"]
                    or self.receipt["unexecuted_gates"]):
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
    parser.add_argument("--readiness-receipt", type=Path)
    parser.add_argument("--keep-going", action="store_true", help="Preserve all failures without retries; final status still fails")
    args = parser.parse_args()
    args.repo = args.repo.resolve()
    selection = plan(args.repo, args.base_ref)
    if args.plan_only:
        print(json.dumps(selection, indent=2, sort_keys=True))
        return 0
    for name in ("expect_head", "output", "runtime_receipt", "readiness_receipt"):
        if getattr(args, name) is None:
            parser.error("--" + name.replace("_", "-") + " is required for an executing run")
    for name in ("output", "runtime_receipt", "readiness_receipt"):
        setattr(args, name, getattr(args, name).resolve())
    if args.output.exists() or args.output.is_relative_to(args.repo):
        parser.error("--output must be a new directory outside the repository")
    return Runner(args, selection).run()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Local validation preflight failed: {type(error).__name__}: {error}", file=sys.stderr)
        raise SystemExit(2)

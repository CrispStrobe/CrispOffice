#!/usr/bin/env python3
"""Verify a committed local proofing integration without GitHub Actions.

Dependencies and the Flutter SDK must already be resolved. Existing TMPDIR,
PUB_CACHE and other caller environment settings are preserved. The German
dictionary check downloads its pinned input unless --german-wordlist is given.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[2]
ENGINE = REPO / "packages/quds_office_engine"
EDITOR = REPO / "packages/quds_office_editor"
EXAMPLE = EDITOR / "example"
HARPER = REPO / "packages/quds_proofing_harper"
COMMAND_TIMEOUT_SECONDS = 900
EDITOR_TESTS = [
    "word_proofing_session", "word_proofing_dialog", "word_proofing_correction",
    "word_proofing_geometry", "word_proofing_navigation", "word_input_focus",
    "word_proofing_context", "word_german_grammar_integration",
    "word_hyphenation_paint", "word_hyphenation_source_presentation",
    "word_hyphenation_resume", "word_hyphenation_caret",
    "platform_spelling_provider", "word_find_replace_history",
    "word_content_control_history", "word_protection_history",
    "word_operation_history", "word_note_numbering", "word_selection_paint",
    "editor", "word_small_caps", "content_revision",
    "word_zotero_backoff_session", "word_zotero_dialog_scaling",
    "word_zotero_source_identity",
]
INCOMING_ENGINE_TESTS = [
    "ods_sheet_reader", "ods_sheet_writer", "sheet_save_cache_and_freeze",
    "zotero_backoff_state", "word_zotero_source_identity",
    "zotero_client", "zotero_identity_client",
    "sfnt_cmap_validation", "pdf_actual_text_scope", "pdf_logical_text_export",
    "sheet_conditional_fidelity", "sheet_conditional_style_priority_integration",
    "sheet_rename_adversarial", "sheet_rename_fidelity",
    "odt_document_writer", "odp_presentation_writer",
]
HARPER_WEB_FILES = [
    "web/harper_worker.mjs", "web/quds_proofing_harper.js",
    "web/quds_proofing_harper_bg.wasm", "licenses/manifest.json",
    "licenses/notices-and-mpl-sources.tar.gz",
]
HARPER_CHECKS = {
    "rust-tests", "dart-analyze", "dart-native-tests", "dart-javascript-tests",
    "wasm-worker", "compile-web-transport", "web-transport", "license-policy",
    "host-packaging",
}


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=REPO, text=True).strip()


def git_paths(*args: str) -> set[str]:
    data = subprocess.check_output(["git", *args, "-z"], cwd=REPO)
    return {name.decode() for name in data.split(b"\0") if name}


def relevant_source(name: str) -> bool:
    parts = Path(name).parts
    excluded = {"build", "target", ".dart_tool", "__pycache__", "coverage",
                "failures", "doc", "docs", "evidence", "screenshots", "ephemeral"}
    if not parts or excluded.intersection(parts):
        return False
    if name in {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml"}:
        return True
    if parts[:2] == ("tools", "proofing"):
        return True
    if parts[0] not in {"packages", "apps"}:
        return False
    if parts[-1] in {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml"}:
        return True
    inputs = {"lib", "test", "tool", "native", "web", "assets", "fonts",
              "third_party", "licenses", "android", "ios", "linux", "macos",
              "windows", "bin", "fixtures", "data"}
    return bool(inputs.intersection(parts[2:])) or parts[-1].startswith(("LICENSE", "NOTICE"))


def source_hashes() -> dict[str, str | None]:
    names = git_paths("ls-files") | git_paths("ls-files", "--others", "--exclude-standard")
    if (REPO / "pubspec.lock").is_file():
        names.add("pubspec.lock")  # The workspace lock is intentionally ignored by Git.
    return {name: digest(REPO / name) if (REPO / name).is_file() else None
            for name in sorted(names) if relevant_source(name)}


def require_committed_sources() -> None:
    if git_paths("diff", "--name-only", "--diff-filter=U"):
        raise ValueError("Resolve the active merge before integration verification.")
    changed = git_paths("diff", "--name-only", "HEAD")
    changed |= git_paths("ls-files", "--others", "--exclude-standard")
    changed = sorted(name for name in changed if relevant_source(name))
    if changed:
        raise ValueError("Commit the relevant source inputs first: " + ", ".join(changed))


def safe_child(directory: Path, name: str) -> Path:
    child = (directory / name).resolve()
    if not child.is_relative_to(directory.resolve()):
        raise ValueError(f"Receipt path escapes its directory: {name}")
    return child


def compressed_manifest(output: Path, name: str, values: dict) -> dict:
    path = output / name
    data = (json.dumps(values, sort_keys=True, indent=2) + "\n").encode()
    path.write_bytes(gzip.compress(data, mtime=0))
    return {"path": name, "sha256": digest(path), "entries": len(values),
            "uncompressed_sha256": hashlib.sha256(data).hexdigest()}


def runtime_hashes(flutter: str, dart: str, node: str) -> dict[str, str]:
    flutter_root = Path(flutter).resolve().parent.parent
    paths = [Path(flutter), Path(dart), Path(node), Path(sys.executable),
             Path(dart).parent / "dartaotruntime",
             flutter_root / "bin/cache/flutter_tools.snapshot",
             flutter_root / "bin/cache/artifacts/engine/linux-x64/flutter_tester",
             flutter_root / "bin/internal/engine.version",
             REPO / ".dart_tool/package_config.json"]
    return {str(path.resolve()): digest(path) for path in paths if path.is_file()}


def test_summary(path: Path) -> dict | None:
    text = re.sub(r"\x1b\[[0-9;]*m", "", path.read_text(errors="replace"))
    matches = re.findall(r"\+(\d+)(?:\s+~(\d+))?(?:\s+-(\d+))?: All tests passed!", text)
    if not matches:
        return None
    passed, skipped, failed = matches[-1]
    return {"passed": int(passed), "skipped": int(skipped or 0), "failed": int(failed or 0)}


def child_receipt(path: Path) -> tuple[dict, dict]:
    data = json.loads(path.read_text())
    if data.get("passed") is not True and data.get("status") != "passed":
        raise ValueError(f"Child validation did not pass: {path}")
    logs = {}
    counts = {}
    for row in data.get("commands", data.get("checks", [])):
        if row.get("exit_code") != 0:
            raise ValueError(f"Nonzero child command in {path}")
        name = row["log"]
        log = safe_child(path.parent, name)
        expected = row.get("log_sha256", row.get("sha256"))
        if expected is None or digest(log) != expected:
            raise ValueError(f"Changed or missing child log: {log}")
        logs[name] = expected
        summary = test_summary(log)
        if summary:
            counts[name] = summary
    if not logs:
        raise ValueError(f"Child receipt has no command evidence: {path}")
    return data, {"receipt_sha256": digest(path), "log_sha256": logs, "test_summaries": counts}


def harper_distribution(directory: Path) -> dict:
    path = directory / "build-receipt.json"
    data = json.loads(path.read_text())
    if (data.get("schema_version", 0) < 2 or not data.get("source_sha256")
            or data.get("source_unchanged_during_build") is not True):
        raise ValueError("Rebuild Harper with the source-bound schema 2 build tool.")
    spec = importlib.util.spec_from_file_location("quds_harper_build_contract", HARPER / "tool/build.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if data["source_sha256"] != module.source_hashes():
        raise ValueError("Harper build source set or content changed; rebuild it first.")
    native = {"win32": "quds_proofing_harper.dll", "darwin": "libquds_proofing_harper.dylib"}.get(
        sys.platform, "libquds_proofing_harper.so")
    if not set(HARPER_WEB_FILES + [f"native/{native}"]).issubset(data["files"]):
        raise ValueError("Harper build must include the host native library, web runtime, notices and MPL sources.")
    for name, expected in data["files"].items():
        if digest(safe_child(directory, name)) != expected:
            raise ValueError(f"Harper built file changed: {name}")
    manifest = json.loads((directory / "licenses/manifest.json").read_text())
    if (manifest["notice_bundle_sha256"] != data["files"]["licenses/notices-and-mpl-sources.tar.gz"]
            or manifest["cargo_lock_sha256"] != digest(HARPER / "native/Cargo.lock")):
        raise ValueError("Harper license archive or lock identity does not match.")
    return data


def require_harper_validation(data: dict, build: dict) -> None:
    names = [row.get("name") for row in data.get("checks", [])]
    if (data.get("schema_version") != 2 or data.get("status") != "passed"
            or data.get("errors") != [] or data.get("license_check", {}).get("status") != "passed"
            or len(names) != len(HARPER_CHECKS) or set(names) != HARPER_CHECKS
            or data.get("source_sha256") != build["source_sha256"]
            or data.get("source_sha256_after") != build["source_sha256"]
            or data.get("source_unchanged_during_commands") is not True
            or data.get("artifacts_sha256") != build["files"]):
        raise ValueError("Harper validation must cover all nine checks and match the current stable build/source.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter", required=True, help="Prepared Flutter executable")
    parser.add_argument("--dart", required=True, help="Dart executable from that Flutter SDK")
    parser.add_argument("--node", default=shutil.which("node"))
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--german-wordlist", type=Path, help="Existing pinned word list; otherwise download it")
    parser.add_argument("--build-web", action="store_true")
    parser.add_argument("--harper-build", type=Path, help="Existing native+web Harper build; verify it and optionally install into web output")
    parser.add_argument("--harper-receipt", type=Path, help="Reuse a matching successful Harper receipt and logs instead of rerunning its checks")
    args = parser.parse_args()
    for name in ("flutter", "dart", "node"):
        value = getattr(args, name)
        executable = shutil.which(value) if value else None
        if not executable:
            parser.error(f"A usable --{name} executable is required")
        setattr(args, name, str(Path(executable).absolute()))
    if args.harper_receipt and not args.harper_build:
        parser.error("--harper-receipt requires --harper-build")
    output = args.output.resolve()
    if output == REPO or (output.is_relative_to(REPO) and relevant_source(str(output.relative_to(REPO) / "receipt.json"))):
        parser.error("Place --output outside source directories, normally under docs/validation")
    if (output / "receipt.json").exists():
        parser.error("Use a new --output directory to preserve the previous receipt and logs")
    output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment.setdefault("CI", "true")
    record = {
        "schema_version": 1, "started_at_utc": now(), "status": "running", "passed": False,
        "source_commit": git("rev-parse", "HEAD"), "commands": [], "child_receipts": {},
        "scope": "Local proofing/editor integration, incoming ODS/Zotero regressions, and optional Harper/web distribution checks.",
        "source_policy": "Tracked and untracked workspace source/test/tool/runtime inputs; excludes docs, evidence and generated build/cache outputs. The ignored root pubspec.lock is an additional exact input.",
        "environment_paths": {name: environment.get(name) for name in ("TMPDIR", "PUB_CACHE", "XDG_CONFIG_HOME")},
        "limits": [
            "No GitHub Actions are used or waited for.",
            "This is a focused regression set, not the complete repository test suite.",
            "Compiled Dart JavaScript and Wasm executed by Node do not establish browser/CSP/HTTP acceptance.",
            "A web build and asset manifest establish packaging only; no interactive browser or mobile device acceptance is claimed.",
            "The optional German correction model is not evaluated or enabled by this verifier.",
        ],
    }

    def save() -> None:
        temporary = output / "receipt.json.tmp"
        temporary.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n")
        temporary.replace(output / "receipt.json")

    def run(label: str, command: list[str], cwd: Path) -> None:
        print(f"Running {label}", flush=True)
        started = time.monotonic()
        log = output / f"{label}.log"
        code = 1
        interrupted = False
        process = None
        with log.open("wb") as stream:
            try:
                process = subprocess.Popen(command, cwd=cwd, env=environment, stdout=stream,
                                           stderr=subprocess.STDOUT, start_new_session=os.name == "posix")
                code = process.wait(timeout=COMMAND_TIMEOUT_SECONDS)
            except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
                if process is not None:
                    if os.name == "posix":
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    else:
                        process.kill()
                    process.wait()
                interrupted = isinstance(error, KeyboardInterrupt)
                code = 130 if interrupted else 124
                stream.write((f"\nVerifier: {'interrupted' if interrupted else 'command exceeded 900 seconds'}.\n").encode())
            except OSError as error:
                stream.write((f"\nVerifier could not launch command: {error}\n").encode())
        row = {"label": label, "command": command, "working_directory": str(cwd.relative_to(REPO)),
               "exit_code": code, "duration_seconds": round(time.monotonic() - started, 3),
               "log": log.name, "log_sha256": digest(log)}
        summary = test_summary(log)
        if summary:
            row["test_summary"] = summary
        record["commands"].append(row)
        save()
        print(f"{label}: exit {code}; {log}", flush=True)
        if interrupted:
            raise KeyboardInterrupt
        if code:
            print("\n".join(log.read_text(errors="replace").splitlines()[-35:]), flush=True)
            raise RuntimeError(f"{label} failed")

    def retain_child(label: str, path: Path) -> dict:
        data, evidence = child_receipt(path)
        evidence["path"] = str(path.relative_to(output))
        record["child_receipts"][label] = evidence
        save()
        return data

    before = {}
    runtime_before = {}
    success = False
    exit_code = 1
    try:
        require_committed_sources()
        before = source_hashes()
        record["source_before"] = compressed_manifest(output, "source-sha256.before.json.gz", before)
        runtime_before = runtime_hashes(args.flutter, args.dart, args.node)
        record["runtime_sha256_before"] = runtime_before
        lock = REPO / "pubspec.lock"
        if lock.is_file():
            shutil.copyfile(lock, output / "pubspec.lock")
            record["workspace_lock"] = {"path": "pubspec.lock", "sha256": digest(lock)}
        build = args.harper_build.resolve() if args.harper_build else None
        build_receipt = harper_distribution(build) if build else None
        save()
        run("flutter-version", [args.flutter, "--version", "--machine"], REPO)
        run("dart-version", [args.dart, "--version"], REPO)
        run("node-version", [args.node, "--version"], REPO)
        for label, package in (("engine", ENGINE), ("editor", EDITOR), ("example", EXAMPLE), ("harper", HARPER)):
            directories = [name for name in ("lib", "test", "tool") if (package / name).is_dir()]
            run(f"{label}-analyze", [args.dart, "analyze", "--fatal-infos", *directories], package)
        run("engine-hyphenation", [sys.executable, "tool/proofing/validate_hyphenation.py",
                                  "--dart", args.dart, "--output", str(output / "engine-hyphenation")], ENGINE)
        retain_child("engine_hyphenation", output / "engine-hyphenation/hyphenation-validation.json")
        wordlist = (["--wordlist", str(args.german_wordlist.resolve())] if args.german_wordlist
                    else ["--download-wordlist"])
        run("german-proofing", [sys.executable, "tool/proofing/verify_german.py", "--dart", args.dart,
                                "--node", args.node, "--output", str(output / "german"), *wordlist], ENGINE)
        retain_child("german", output / "german/receipt.json")
        # Source/provider contracts are useful even when optional native/Wasm
        # assets are absent. Real backend acceptance remains the separate
        # source-bound --harper-build gate below.
        run("harper-contract-tests", [args.dart, "test", "--reporter=expanded",
                                      "test/harper_provider_test.dart",
                                      "test/harper_source_text_test.dart",
                                      "test/harper_source_contract_test.dart"], HARPER)
        run("harper-source-reference", [args.node, "tool/source_projection_probe.mjs"], HARPER)
        run("incoming-engine-tests", [args.dart, "test", "--concurrency=4", "--reporter=expanded",
                                      *[f"test/{name}_test.dart" for name in INCOMING_ENGINE_TESTS]], ENGINE)
        run("editor-tests", [args.flutter, "test", "--no-pub", "--concurrency=2", "--reporter=expanded",
                             *[f"test/{name}_test.dart" for name in EDITOR_TESTS]], EDITOR)
        run("editor-ime-reattachment", [args.flutter, "test", "--no-pub", "--reporter=expanded",
                                       "test/embed_test.dart", "--plain-name",
                                       "tapping the canvas reattaches IME after another client steals it"], EDITOR)
        if build:
            if args.harper_receipt:
                old_path = args.harper_receipt.resolve()
                old, evidence = child_receipt(old_path)
                require_harper_validation(old, build_receipt)
                destination = output / "harper"
                destination.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(old_path, destination / "receipt.json")
                for name in evidence["log_sha256"]:
                    target = safe_child(destination, name)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(safe_child(old_path.parent, name), target)
                record["harper_validation_origin"] = {"mode": "retained matching source/artifacts/logs", "receipt": str(old_path)}
            else:
                run("harper-runtime", [sys.executable, "tool/verify.py", "--dart", args.dart, "--node", args.node,
                                       "--build-output", str(build), "--output", str(output / "harper")], HARPER)
                record["harper_validation_origin"] = {"mode": "fresh local commands"}
            current_harper = retain_child("harper", output / "harper/receipt.json")
            require_harper_validation(current_harper, build_receipt)
            if harper_distribution(build) != build_receipt:
                raise ValueError("Harper distribution changed during integration verification")
            shutil.copyfile(build / "build-receipt.json", output / "harper/build-receipt.json")
            record["harper_build_receipt_sha256"] = digest(build / "build-receipt.json")
        if args.build_web:
            run("example-web-build", [args.flutter, "build", "web", "--release", "--no-pub", "--no-wasm-dry-run"], EXAMPLE)
            web = EXAMPLE / "build/web"
            installed = {}
            if build:
                if harper_distribution(build) != build_receipt:
                    raise ValueError("Harper distribution changed before host installation")
                for name in HARPER_WEB_FILES + ["build-receipt.json"]:
                    relative = name.removeprefix("web/")
                    target = web / "proofing" / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(build / name, target)
                    actual = digest(target)
                    expected = (record["harper_build_receipt_sha256"] if name == "build-receipt.json"
                                else build_receipt["files"][name])
                    if actual != expected:
                        raise ValueError(f"Harper asset changed during installation: {name}")
                    installed[str(target.relative_to(web))] = actual
            files = {str(path.relative_to(web)): digest(path) for path in sorted(web.rglob("*")) if path.is_file()}
            record["web_bundle"] = {
                "directory": str(web.relative_to(REPO)), "file_count": len(files),
                "total_bytes": sum(path.stat().st_size for path in web.rglob("*") if path.is_file()),
                "manifest": compressed_manifest(output, "web-bundle-sha256.json.gz", files),
                "harper_asset_sha256": installed,
                "harper_default_worker_url": "Uri.base.resolve('proofing/harper_worker.mjs')" if build else None,
            }
        success = True
        exit_code = 0
    except KeyboardInterrupt:
        record["error"] = "Interrupted"
        exit_code = 130
    except Exception as error:
        record["error"] = f"{type(error).__name__}: {error}"
        print(record["error"], file=sys.stderr, flush=True)
    finally:
        after = source_hashes()
        runtime_after = runtime_hashes(args.flutter, args.dart, args.node)
        record["source_after"] = compressed_manifest(output, "source-sha256.after.json.gz", after)
        record["runtime_sha256_after"] = runtime_after
        record["source_commit_after"] = git("rev-parse", "HEAD")
        record["inputs_unchanged_during_validation"] = bool(before) and before == after
        record["runtime_unchanged_during_validation"] = bool(runtime_before) and runtime_before == runtime_after
        record["changed_inputs"] = sorted(name for name in before.keys() | after.keys() if before.get(name) != after.get(name))
        record["finished_at_utc"] = now()
        record["passed"] = success and record["inputs_unchanged_during_validation"] and record["runtime_unchanged_during_validation"]
        record["status"] = "passed" if record["passed"] else "failed"
        save()
    print(f"{record['status']}: {output / 'receipt.json'}", flush=True)
    return exit_code if not success else (0 if record["passed"] else 1)


if __name__ == "__main__":
    sys.exit(main())

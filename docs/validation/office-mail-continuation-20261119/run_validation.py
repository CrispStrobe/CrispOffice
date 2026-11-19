#!/usr/bin/env python3
"""Run the committed Office/Mail continuation plan without hosted CI.

The existing strict runner owns Dart reporter accounting, per-suite coverage,
analysis, formatting and source/runtime fingerprints. The existing Store driver
owns its complete VM/Node checks. This adapter binds the combined execution to
one clean source commit, preserves every raw log, and rejects skipped controls.
It does not download dependencies, query GitHub Actions or contact a mail account.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def language_id_inputs(repo: Path, runtime_receipt: dict, library: Path, fixture: Path) -> dict:
    """Bind real CLD3 and lifecycle-fixture libraries to their qualified source."""
    library = library.resolve(strict=True)
    build_receipt = library.parent.parent / "build-receipt.json"
    fixture = fixture.resolve(strict=True)
    fixture_receipt = fixture.with_suffix(".receipt.json")
    additional = runtime_receipt.get("additional_inputs", {})
    identities = {}
    for path in (library, build_receipt, fixture, fixture_receipt):
        if not path.is_file() or path.is_symlink():
            raise RuntimeError("Missing/redirected language identifier input: " + str(path))
        identities[str(path)] = digest(path)
        if additional.get(str(path)) != identities[str(path)]:
            raise RuntimeError("Language identifier input is not runtime-bound: " + str(path))
    build = json.loads(build_receipt.read_text())
    relative = library.relative_to(build_receipt.parent).as_posix()
    if not relative.startswith("native/") or build.get("files", {}).get(relative) != identities[str(library)]:
        raise RuntimeError("Language identifier library differs from its native build receipt")
    package = repo / "packages/quds_language_id"
    adapters = {path.relative_to(package).as_posix(): digest(path)
                for path in sorted((package / "native").rglob("*"))
                if path.is_file() and path.suffix in {".cpp", ".h", ".txt"}}
    manifest_path = package / "licenses/manifest.json"
    manifest = json.loads(manifest_path.read_text())
    component = manifest["component"]
    if (build.get("adapter") != adapters
            or build.get("license_manifest_sha256") != digest(manifest_path)
            or build.get("crispasr") != {"repository": component["source"], "commit": component["commit"]}
            or build.get("model") != manifest["model"]):
        raise RuntimeError("Language identifier build provenance differs from the qualified source")
    model = package / "assets" / manifest["model"]["file"]
    if model.stat().st_size != manifest["model"]["bytes"] or digest(model) != manifest["model"]["sha256"]:
        raise RuntimeError("Language identifier model differs from its pinned bytes")
    fixture_source = "packages/quds_language_id/test/fixtures/native_transport_fixture.cpp"
    fixture_build = json.loads(fixture_receipt.read_text())
    fixture_source_hash = digest(repo / fixture_source)
    if (fixture_build.get("library") != fixture.name
            or fixture_build.get("library_sha256") != identities[str(fixture)]
            or fixture_build.get("source") != fixture_source
            or fixture_build.get("source_sha256") != fixture_source_hash):
        raise RuntimeError("Language identifier fixture differs from its qualified source or build receipt")
    return {"library": str(library), "library_sha256": identities[str(library)],
            "build_receipt": str(build_receipt), "build_receipt_sha256": identities[str(build_receipt)],
            "environment": {"QUDS_LANGUAGE_ID_TEST_LIBRARY": str(library),
                            "QUDS_LANGUAGE_ID_FIXTURE_LIBRARY": str(fixture)},
            "model_sha256": manifest["model"]["sha256"], "adapter_source_files": len(adapters),
            "fixture": {"library": str(fixture), "library_sha256": identities[str(fixture)],
                        "build_receipt": str(fixture_receipt), "build_receipt_sha256": identities[str(fixture_receipt)],
                        "source": fixture_source, "source_sha256": fixture_source_hash}}


def arabic_morph_inputs(repo: Path, runtime_receipt: dict, library: Path, bundle: Path) -> dict:
    """Bind the real morphology backend and all four immutable data inputs."""
    library, bundle = library.resolve(strict=True), bundle.resolve(strict=True)
    build_receipt = library.parent.parent / "build-receipt.json"
    package = repo / "packages/quds_arabic_morph"
    catalog = package / "lib/src/morph_catalog.dart"
    definition = catalog.read_text().split("const camelMorphMsaProofingBin =", 1)[1].split("\n);", 1)[0]
    rows = re.findall(r"MorphArtifact\(\s*'([^']+)',\s*'([0-9a-f]{64})',\s*(\d+),?\s*\)", definition)
    pins = {name: {"sha256": sha, "bytes": int(size)} for name, sha, size in rows}
    expected_names = {"manifest.json", "camel_morph_msa_v1.0.proofing.cmorph", "NOTICE", "LICENSE"}
    if len(rows) != 4 or set(pins) != expected_names or {path.name for path in bundle.iterdir()} != expected_names:
        raise RuntimeError("Morphology bundle/catalog does not contain exactly the four pinned artifacts")
    additional = runtime_receipt.get("additional_inputs", {})
    identities = {}
    for path in (library, build_receipt, *(bundle / name for name in sorted(pins))):
        if not path.is_file() or path.is_symlink():
            raise RuntimeError("Missing/redirected morphology input: " + str(path))
        actual = digest(path)
        if additional.get(str(path)) != actual:
            raise RuntimeError("Morphology input is not runtime-bound: " + str(path))
        identities[str(path)] = actual
        if path.parent == bundle and (actual != pins[path.name]["sha256"] or path.stat().st_size != pins[path.name]["bytes"]):
            raise RuntimeError("Morphology bundle artifact differs from its compiled pin: " + path.name)
    build = json.loads(build_receipt.read_text())
    relative = library.relative_to(build_receipt.parent).as_posix()
    manifest_path = package / "licenses/manifest.json"
    manifest = json.loads(manifest_path.read_text())
    component = manifest["component"]
    if (not relative.startswith("native/") or build.get("files", {}).get(relative) != identities[str(library)]
            or build.get("adapter_sha256") != digest(package / "native/src/quds_arabic_morph.cpp")
            or build.get("license_manifest_sha256") != digest(manifest_path)
            or build.get("crispembed") != {"repository": component["source"], "commit": component["commit"],
                                          "pull_request": component["pull_request"]}):
        raise RuntimeError("Morphology build provenance differs from the qualified source")
    return {"library": str(library), "library_sha256": identities[str(library)],
            "build_receipt": str(build_receipt), "build_receipt_sha256": identities[str(build_receipt)],
            "bundle": str(bundle), "artifacts": pins, "catalog_sha256": digest(catalog),
            "environment": {"QUDS_ARABIC_MORPH_TEST_LIBRARY": str(library),
                            "QUDS_ARABIC_MORPH_TEST_BUNDLE": str(bundle)},
            "live_external_download_executed": False}


def runtime_extension_inputs(repo: Path, runtime: Path, receipt: dict) -> dict:
    """Bind the additive cache extension without rewriting restoration history."""
    directory = Path(__file__).resolve().parent
    profile_path = directory / "runtime-extension-locks.json"
    profile = json.loads(profile_path.read_text())
    binding = receipt.get("runtime_extension", {})
    if binding.get("status") != "ready" or receipt["workspace_lock_sha256"] != profile["target_lock_sha256"]:
        raise RuntimeError("The exact ready runtime extension is required for this lock")
    record_path = Path(binding["receipt"]).resolve(strict=True)
    if (digest(record_path) != binding["sha256"]
            or receipt["additional_inputs"].get(str(record_path)) != binding["sha256"]
            or binding["profile_sha256"] != digest(profile_path)):
        raise RuntimeError("Runtime extension receipt/profile binding changed")
    record = json.loads(record_path.read_text())
    if (record.get("status") != "ready" or record["source"] != str(repo) or record["runtime"] != str(runtime)
            or record["profile_sha256"] != digest(profile_path)
            or record["implementation_sha256"] != digest(directory / "extend_runtime.py")
            or record["base_lock_sha256"] != profile["base_lock_sha256"]
            or record["target_lock_sha256"] != profile["target_lock_sha256"]
            or record["base_archives"] != profile["base_archive_count"]
            or record["target_archives"] != profile["target_archive_count"]):
        raise RuntimeError("Runtime extension differs from its source-bound profile")
    if ([row["name"] for row in record["runs"]] != ["workspace-pub-get", "native-assets-smoke"]
            or any(row["exit_code"] != 0 for row in record["runs"])):
        raise RuntimeError("Runtime extension resolution/native smoke did not complete")
    logs = {}
    for row in record["runs"]:
        path = Path(row["log"]).resolve(strict=True)
        if digest(path) != row["log_sha256"]:
            raise RuntimeError("Runtime extension log changed: " + str(path))
        logs[str(path)] = row["log_sha256"]
    return {"receipt": str(record_path), "sha256": binding["sha256"],
            "profile_sha256": digest(profile_path), "base_archives": record["base_archives"],
            "target_archives": record["target_archives"], "logs": logs}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--web-sdk", required=True, type=Path,
                        help="Separate engine-pinned web SDK prepared by prepare_web_sdk.py")
    parser.add_argument("--language-id-library", required=True, type=Path,
                        help="Real native CLD3 library and sibling build receipt bound in runtime.json")
    parser.add_argument("--language-id-fixture-library", required=True, type=Path,
                        help="Native lifecycle fixture library and .receipt.json bound in runtime.json")
    parser.add_argument("--arabic-morph-library", required=True, type=Path,
                        help="Real native Camel Morph library and build receipt bound in runtime.json")
    parser.add_argument("--arabic-morph-bundle", required=True, type=Path,
                        help="Directory containing the four source-pinned proofing-bin bundle artifacts")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--command-timeout", type=int, default=900)
    args = parser.parse_args()
    if args.command_timeout <= 0:
        parser.error("--command-timeout must be positive")
    directory = Path(__file__).resolve().parent
    repo = directory.parents[2]
    runtime, output = args.runtime.resolve(), args.output.resolve()
    web_root = args.web_sdk.resolve()
    if output == repo or repo in output.parents:
        raise RuntimeError("Keep gate output outside the frozen source checkout")
    if output.exists() and any(output.iterdir()):
        raise RuntimeError("Choose an empty output directory; preserve prior attempts")
    output.mkdir(parents=True, exist_ok=True)

    def git(*arguments: str) -> str:
        return subprocess.check_output(
            ["git", "--no-replace-objects", "-C", str(repo), *arguments], text=True,
        ).rstrip("\n")

    def clean() -> bool:
        return not git("status", "--porcelain=v1", "--untracked-files=no")

    def untracked_product() -> list[str]:
        return [
            path for path in git("ls-files", "--others", "--exclude-standard", "-z").split("\0")
            if path.startswith(("packages/", "apps/", "third_party/"))
        ]

    head = git("rev-parse", "--verify", args.head + "^{commit}")
    base = git("rev-parse", "--verify", args.base + "^{commit}")
    if git("rev-parse", "HEAD") != head or not clean() or untracked_product():
        raise RuntimeError("Commit source, plans and harness before freezing HEAD")
    tracked = set(git("ls-files", "-z").split("\0")) - {""}
    plans = {name: directory / (name + "-plan.json") for name in ("native", "node")}
    plan_data = {name: json.loads(path.read_text()) for name, path in plans.items()}
    shared = repo / "docs/validation/document-review-notes-20261118"
    required = {
        str(path.relative_to(repo))
        for path in [Path(__file__), *plans.values(), directory / "web-sdk.json",
                     directory / "prepare_web_sdk.py", shared / "run_checks.py", shared / "test_run_checks.py"]
    }
    if not required <= tracked:
        raise RuntimeError("Commit the driver, both plans and shared runner before execution")
    changed = {
        path for path in git("diff", "--name-only", "--diff-filter=ACMRT", "-z", base, head).split("\0")
        if path.endswith(".dart") and path.startswith(("packages/", "apps/", "third_party/"))
    }
    # The shared runner's 'changed' mode covers packages/apps. Explicit lists
    # are required if this continuation also changes vendored Dart source.
    for kind in ("analysis", "format"):
        requested = plan_data["native"][kind]
        checked = changed - {p for p in changed if p.startswith("third_party/")} if requested == "changed" else set(requested)
        if changed - checked:
            raise RuntimeError(f"Changed Dart inputs missing {kind}: {sorted(changed - checked)}")
    studio_root = "packages/quds_office_editor/example"
    studio_expected = {
        "test/" + path.name for path in (repo / studio_root / "test").glob("*_test.dart")
    }
    excluded = plan_data["native"].get("excluded_studio_suites", {})
    if not isinstance(excluded, dict) or any(not reason for reason in excluded.values()):
        raise RuntimeError("Every excluded Studio suite needs an explicit boundary")
    studio_requested = {
        suite for group in plan_data["native"]["groups"] if group["cwd"] == studio_root
        for suite in group["tests"]
    }
    if studio_requested != studio_expected - set(excluded) or set(excluded) - studio_expected:
        raise RuntimeError("The plan must cover every ordinary Studio suite exactly")
    planned_suites = {
        group["cwd"] + "/" + suite
        for group in plan_data["native"]["groups"] for suite in group["tests"]
    }
    node_suites = {group["cwd"] + "/" + suite
                   for group in plan_data["node"]["groups"] for suite in group["tests"]}
    node_only = plan_data["native"].get("node_only_suites", {})
    if (not isinstance(node_only, dict) or any(not isinstance(reason, str) or not reason.strip()
                                              for reason in node_only.values())
            or set(node_only) - node_suites or set(node_only) & planned_suites):
        raise RuntimeError("Node-only suites need an explicit boundary and exact Node-only selection")
    # check_store.py discovers all Core tests on VM/Node and all top-level
    # Store tests across its VM and portable Node selections. Do not execute
    # those changed suites a second time merely to satisfy this adapter.
    core_store_suites = {
        path for path in tracked if path.endswith("_test.dart")
        and (path.startswith("packages/quds_mail_core/test/")
             or Path(path).parent.as_posix() == "packages/quds_mail_store/test")
    }
    optional_suites = {studio_root + "/" + suite for suite in excluded}
    for row in plan_data["native"].get("excluded_native_backend_suites", []):
        if not row.get("reason"):
            raise RuntimeError("Every excluded native backend suite needs an explicit boundary")
        optional_suites.add(row["path"])
    changed_suites = {path for path in changed if path.endswith("_test.dart")}
    missing_suites = changed_suites - planned_suites - optional_suites - core_store_suites - set(node_only)
    if missing_suites:
        raise RuntimeError("Changed test suites missing aggregate qualification: " + str(sorted(missing_suites)))
    receipt = json.loads((runtime / "runtime.json").read_text())
    if receipt.get("status") != "ready" or not receipt.get("archive", {}).get("verified"):
        raise RuntimeError("A verified ready runtime is required")
    if digest(repo / "pubspec.lock") != receipt["workspace_lock_sha256"]:
        raise RuntimeError("Workspace lock differs from the verified runtime")
    extension = runtime_extension_inputs(repo, runtime, receipt)
    language_id = language_id_inputs(repo, receipt, args.language_id_library, args.language_id_fixture_library)
    arabic_morph = arabic_morph_inputs(repo, receipt, args.arabic_morph_library, args.arabic_morph_bundle)
    web_identity = json.loads((directory / "web-sdk.json").read_text())
    if web_identity["engine_revision"] != receipt["runtime"]["engineRevision"]:
        raise RuntimeError("Web SDK engine does not match the verified runtime")
    web_sdk = web_root / web_identity["sdk_directory"]
    dart_link = web_root / web_identity["dart_sdk_link"]
    if dart_link.resolve() != (runtime / "flutter/bin/cache/dart-sdk").resolve():
        raise RuntimeError("Separate web SDK must reference the verified Dart SDK")
    web_archive = web_root / "flutter-web-sdk.zip"
    if (web_archive.stat().st_size != web_identity["archive_bytes"]
            or digest(web_archive) != web_identity["archive_sha256"]):
        raise RuntimeError("Web SDK archive identity differs")
    web_files = {str(path.relative_to(web_sdk)): path for path in web_sdk.rglob("*") if path.is_file()}
    if set(web_files) != set(web_identity["files"]):
        raise RuntimeError("Web SDK member list differs from the pinned component")
    for name, path in web_files.items():
        expected = web_identity["files"][name]
        if path.is_symlink() or path.stat().st_size != expected["bytes"] or digest(path) != expected["sha256"]:
            raise RuntimeError("Web SDK input differs: " + name)
    retained = json.loads((runtime / "retained-inputs.json").read_text())
    runtime_paths = {"runtime/" + name: runtime / name for name in retained}
    for name in ("runtime.json", "retained-inputs.json", "pub-cache-receipt.json", "cache-omissions.json", "archive-members.json", "env.sh", "bin/dart", "bin/flutter"):
        runtime_paths["runtime/" + name] = runtime / name
    runtime_paths.update({"additional/" + name: Path(name) for name in receipt.get("additional_inputs", {})})
    runtime_paths.update({"extension-log/" + name: Path(name) for name in extension["logs"]})
    runtime_paths["python/executable"] = Path(sys.executable).resolve()
    runtime_paths["workspace/package_config.json"] = repo / ".dart_tool/package_config.json"
    runtime_paths["workspace/package_graph.json"] = repo / ".dart_tool/package_graph.json"
    runtime_paths["sdk/flutter_tools/package_config.json"] = runtime / "flutter/packages/flutter_tools/.dart_tool/package_config.json"
    runtime_paths.update({"web-sdk/" + name: path for name, path in web_files.items()})
    runtime_paths["web-sdk/archive"] = web_archive
    source_paths = {
        name: repo / name for name in tracked
        if name.startswith(("packages/", "apps/", "third_party/", "tools/mail/", "tools/proofing/ayaspell/"))
        or ("/" not in name and Path(name).suffix in {".yaml", ".lock"}) or name == ".fvmrc"
    }
    for name in required | {n for plan in plan_data.values() for n in plan.get("extra_inputs", [])}:
        if name not in tracked:
            raise RuntimeError("Qualification input is not committed: " + name)
        source_paths[name] = repo / name

    def snapshot(paths: dict[str, Path]) -> dict[str, str]:
        return {name: digest(path) for name, path in sorted(paths.items())}

    before_source, before_runtime = snapshot(source_paths), snapshot(runtime_paths)
    for name, identity in retained.items():
        if before_runtime["runtime/" + name] != identity["sha256"]:
            raise RuntimeError("Retained runtime input changed: " + name)
    for name, expected in receipt.get("additional_inputs", {}).items():
        if before_runtime["additional/" + name] != expected:
            raise RuntimeError("Additional runtime input changed: " + name)
    write_json(output / "source-before.json", before_source)
    write_json(output / "runtime-before.json", before_runtime)
    for name in ("package_config.json", "package_graph.json"):
        shutil.copy2(repo / ".dart_tool" / name, output / name)
    env = dict(os.environ, PUB_CACHE=str(runtime / "pub-cache"), FLUTTER_ROOT=str(runtime / "flutter"),
               CI="true", DART_SUPPRESS_ANALYTICS="true", FLUTTER_SUPPRESS_ANALYTICS="true",
               DASH__SUPPRESS_ANALYTICS="true", XDG_CONFIG_HOME=str(runtime / "config"),
               XDG_CACHE_HOME=str(runtime / "cache"), XDG_DATA_HOME=str(runtime / "data"),
               TMPDIR=str(runtime / "tmp"))
    env["PATH"] = str(runtime / "bin") + os.pathsep + env.get("PATH", "")
    removed_environment = []
    for name in list(env):
        if name.startswith(("QUDS_HUNSPELL_", "QUDS_ARABIC_MORPH_", "QUDS_SHOTS_", "QUDS_LANGUAGE_ID_")):
            removed_environment.append(name)
            del env[name]
    env.update(language_id["environment"])
    env.update(arabic_morph["environment"])
    sys.path.insert(0, str(repo / "tools/mail"))
    from check_store import execute

    index_tree = git("write-tree")
    record = {
        "status": "RUNNING", "source_commit": head, "source_base": base,
        "source_tree": git("rev-parse", head + "^{tree}"), "runs": [],
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_input_count": len(source_paths), "runtime_input_count": len(runtime_paths),
        "runtime_receipt_sha256": digest(runtime / "runtime.json"),
        "runtime_extension": extension,
        "python_version": sys.version, "strict_changed_dart_inputs": sorted(changed),
        "changed_test_suites": sorted(changed_suites),
        "changed_test_suites_explicitly_excluded": sorted(changed_suites & optional_suites),
        "core_store_test_suites": sorted(core_store_suites),
        "node_only_test_suites": node_only,
        "excluded_studio_suites": excluded,
        "excluded_native_backend_suites": plan_data["native"].get("excluded_native_backend_suites", []),
        "removed_optional_native_environment_names": sorted(removed_environment),
        "language_id_native": language_id,
        "arabic_morph_native": arabic_morph,
        "web_sdk_identity_sha256": digest(directory / "web-sdk.json"),
        "web_sdk_dart_link_target": str(dart_link.resolve()),
        "historical_results_added_to_current_counts": 0,
        "github_actions_queried_or_awaited": False,
    }

    def save() -> None:
        write_json(output / "execution.json", record)

    def run(name: str, command: list[str], result: Path | None = None, *, unittest: bool = False,
            timeout_multiplier: int = 1) -> None:
        print("START " + name, flush=True)
        log = output / (name + ".log")
        timeout_seconds = args.command_timeout * timeout_multiplier
        row = {"name": name, "command": command, "log": log.name, "cwd": str(repo),
               "timeout_seconds": timeout_seconds}
        record["runs"].append(row)
        save()
        with log.open("wb") as stream:
            try:
                code = execute(command, cwd=repo, env=env, stdout=stream, timeout=timeout_seconds)
            except (OSError, subprocess.TimeoutExpired) as error:
                code = 124 if isinstance(error, subprocess.TimeoutExpired) else 127
                row["runner_error"] = repr(error)
        row.update(exit_code=code, log_sha256=digest(log), accepted=code == 0)
        if unittest:
            text = log.read_text(errors="replace")
            counts = re.findall(r"^Ran (\d+) tests? in ", text, re.MULTILINE)
            successful = re.search(r"^OK\s*$", text, re.MULTILINE) is not None
            skipped = re.search(r"\bskipped[= ]|^OK \(", text, re.MULTILINE) is not None
            row.update(python_tests=int(counts[-1]) if counts else 0, python_skips_detected=skipped)
            row["accepted"] = row["accepted"] and row["python_tests"] > 0 and successful and not skipped
        if result is not None:
            if result.is_file():
                content = json.loads(result.read_text())
                row.update(receipt=str(result.relative_to(output)), receipt_sha256=digest(result))
                row["accepted"] = row["accepted"] and (content.get("success") is True or content.get("status") == "PASS")
                if "passed" in content:
                    row["application_executions"] = content["passed"]
            else:
                row["accepted"] = False
        save()
        if not row["accepted"]:
            raise RuntimeError(name + " failed; preserve its raw evidence")

    save()
    try:
        run("shared-runner-controls", [sys.executable, "-B", str(shared / "test_run_checks.py")], unittest=True)
        run("runtime-replay-controls", [sys.executable, "-B", str(shared / "runtime/test_restore_runtime.py")], unittest=True)
        run("runtime-extension-controls", [sys.executable, "-B", str(directory / "test_extend_runtime.py")], unittest=True)
        run("publisher-offline-controls", [sys.executable, "-B", "-m", "unittest", "discover", "-s", "tools/proofing/ayaspell", "-p", "test_build_bundle*.py", "-v"], unittest=True)
        run("hunspell-packaging-controls", [sys.executable, "-B", "-m", "unittest", "discover", "-s", "packages/quds_proofing_hunspell/tool", "-p", "test_build.py", "-v"], unittest=True)
        run("core-store", [sys.executable, "-B", str(repo / "tools/mail/check_store.py"),
                           "--flutter-sdk", str(runtime / "flutter"), "--offline", "--direct-tests",
                           "--command-timeout", str(args.command_timeout), "--output", str(output / "core-store")],
            output / "core-store/receipt.json", timeout_multiplier=13)
        for name, path in plans.items():
            run(name, [sys.executable, "-B", str(shared / "run_checks.py"), "--head", head, "--base", base,
                       "--runtime", str(runtime), "--plan", str(path), "--output", str(output / name),
                       "--command-timeout", str(args.command_timeout)], output / name / "verification.json",
                timeout_multiplier=len(plan_data[name]["groups"]) + bool(plan_data[name]["analysis"])
                + bool(plan_data[name]["format"]) + 1)
        web_entry = repo / "packages/quds_office_editor/example/tool/mail_web_entry.dart"
        web_kernel = output / "mail-web.dill"
        web_js = output / "mail-web.js"
        common = [str(runtime / "bin/dart"), "compile", "js",
                  "--platform-binaries=" + str(web_sdk / "kernel"), "--invoker=flutter_tool",
                  "-Ddart.vm.product=true", "-O1"]
        run("mail-browser-frontend", [*common,
            "--packages=" + str(repo / ".dart_tool/package_config.json"),
            "--cfe-only", "-o", str(web_kernel), str(web_entry)])
        deps = web_kernel.with_suffix(web_kernel.suffix + ".deps")
        entries = set(deps.read_text().splitlines())
        required_web = [
            "packages/quds_office_editor/example/tool/mail_web_entry.dart",
            "packages/quds_office_editor/example/lib/studio_mail.dart",
            "packages/quds_office_editor/example/lib/studio_mail_web.dart",
            "packages/quds_office_editor/example/lib/studio_saved_mail.dart",
            "packages/quds_office_editor/example/lib/studio_mail_file_web.dart",
        ]
        forbidden_native = [
            "packages/quds_office_editor/example/lib/studio_mail_native.dart",
            "packages/quds_office_editor/example/lib/studio_mail_message_loader.dart",
            "packages/quds_office_editor/example/lib/studio_mail_file_native.dart",
            "third_party/enough_mail/lib/highlevel.dart",
            "third_party/enough_mail/lib/src/mail/mail_client.dart",
            "third_party/enough_mail/lib/src/private/util/client_base.dart",
        ]
        missing_web = [path for path in required_web if (repo / path).as_uri() not in entries]
        present_native = [path for path in forbidden_native if (repo / path).as_uri() in entries]
        closure = {"required_web_paths": required_web, "forbidden_native_paths": forbidden_native,
                   "missing_web_paths": missing_web, "present_native_paths": present_native,
                   "dependency_count": len(entries), "dependencies_sha256": digest(deps),
                   "passed": not missing_web and not present_native,
                   "scope": "Actual Flutter browser compiler import closure; no browser runtime execution."}
        write_json(output / "mail-browser-import-closure.json", closure)
        if not closure["passed"]:
            raise RuntimeError("Mail browser import graph selected an unexpected platform path")
        run("mail-browser-javascript", [*common, "--no-source-maps", "-o", str(web_js), str(web_kernel)])
        run("mail-browser-javascript-syntax", [receipt["node_runtime"]["path"], "--check", str(web_js)])
        web_outputs = [web_kernel, deps, web_js, web_js.with_suffix(web_js.suffix + ".deps")]
        if any(not path.is_file() or not path.stat().st_size for path in web_outputs):
            raise RuntimeError("Browser compilation did not produce all expected artifacts")
        record["browser_compilation"] = {
            "accepted": True, "browser_session_executed": False,
            "artifacts": {path.name: {"bytes": path.stat().st_size, "sha256": digest(path)} for path in web_outputs},
            "import_closure_sha256": digest(output / "mail-browser-import-closure.json"),
        }
        language_entry = repo / "packages/quds_language_id/tool/language_id_web_entry.dart"
        language_kernel = output / "language-id-web.dill"
        language_js = output / "language-id-web.js"
        run("language-id-browser-frontend", [*common,
            "--packages=" + str(repo / ".dart_tool/package_config.json"),
            "--cfe-only", "-o", str(language_kernel), str(language_entry)])
        language_deps = language_kernel.with_suffix(language_kernel.suffix + ".deps")
        language_entries = set(language_deps.read_text().splitlines())
        language_required = [
            "packages/quds_language_id/tool/language_id_web_entry.dart",
            "packages/quds_language_id/lib/quds_language_id.dart",
            "packages/quds_language_id/lib/src/cld3_language_identifier.dart",
            "packages/quds_language_id/lib/src/language_id_transport_web.dart",
        ]
        language_forbidden = [
            "packages/quds_language_id/lib/src/language_id_transport_native.dart",
            "packages/quds_language_id/lib/src/language_id_transport_stub.dart",
        ]
        language_missing = [path for path in language_required if (repo / path).as_uri() not in language_entries]
        language_present = [path for path in language_forbidden if (repo / path).as_uri() in language_entries]
        language_closure = {
            "required_web_paths": language_required, "forbidden_native_paths": language_forbidden,
            "missing_web_paths": language_missing, "present_native_paths": language_present,
            "dependency_count": len(language_entries), "dependencies_sha256": digest(language_deps),
            "passed": not language_missing and not language_present,
            "scope": "Actual browser frontend and JavaScript compilation; no browser, Worker or Wasm execution.",
        }
        write_json(output / "language-id-browser-import-closure.json", language_closure)
        if not language_closure["passed"]:
            raise RuntimeError("Language identifier browser import graph selected an unexpected platform path")
        run("language-id-browser-javascript", [*common, "--no-source-maps", "-o", str(language_js), str(language_kernel)])
        run("language-id-browser-javascript-syntax", [receipt["node_runtime"]["path"], "--check", str(language_js)])
        language_outputs = [language_kernel, language_deps, language_js, language_js.with_suffix(language_js.suffix + ".deps")]
        if any(not path.is_file() or not path.stat().st_size for path in language_outputs):
            raise RuntimeError("Language identifier browser compilation did not produce all expected artifacts")
        record["language_id_browser_compilation"] = {
            "accepted": True, "browser_session_executed": False, "worker_executed": False, "wasm_executed": False,
            "artifacts": {path.name: {"bytes": path.stat().st_size, "sha256": digest(path)} for path in language_outputs},
            "import_closure_sha256": digest(output / "language-id-browser-import-closure.json"),
        }
        record["status"] = "PASS"
    except BaseException as error:
        record.update(status="FAIL", error=repr(error))
    finally:
        after_source, after_runtime = snapshot(source_paths), snapshot(runtime_paths)
        write_json(output / "source-after.json", after_source)
        write_json(output / "runtime-after.json", after_runtime)
        record.update(
            source_unchanged=before_source == after_source, runtime_unchanged=before_runtime == after_runtime,
            source_head_unchanged=git("rev-parse", "HEAD") == head,
            source_index_unchanged=git("write-tree") == index_tree,
            tracked_worktree_clean_after=clean(), untracked_product_inputs_after=untracked_product(),
            web_sdk_dart_link_unchanged=str(dart_link.resolve()) == record["web_sdk_dart_link_target"],
            finished_at_utc=datetime.now(timezone.utc).isoformat(),
        )
        record["manifest_sha256"] = {
            name: digest(output / name) for name in (
                "source-before.json", "source-after.json", "runtime-before.json", "runtime-after.json",
                "package_config.json", "package_graph.json",
            )
        }
        if record["untracked_product_inputs_after"] or not all(record[k] for k in (
            "source_unchanged", "runtime_unchanged", "source_head_unchanged", "source_index_unchanged", "tracked_worktree_clean_after", "web_sdk_dart_link_unchanged",
        )):
            record["status"] = "FAIL"
        save()
    print(record["status"] + ": " + str(output / "execution.json"), flush=True)
    return 0 if record["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())

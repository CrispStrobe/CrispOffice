#!/usr/bin/env python3
"""Verify an already-built local Harper distribution without GitHub Actions.

The build receipt must match both the current source and every shipped file.
Native tests are always configured with the actual library, so a skipped native
backend cannot be mistaken for a successful integration check.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import time

from build import PACKAGE, NATIVE, source_hashes
from license_bundle import selection


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_distribution(directory: Path) -> dict:
    receipt = json.loads((directory / "build-receipt.json").read_text())
    if receipt.get("schema_version") != 2 or not receipt.get("source_unchanged_during_build"):
        raise ValueError("Rebuild with source stability checks before recording validation.")
    if receipt.get("source_sha256") != source_hashes():
        raise ValueError("Build source has changed. Rebuild before recording validation.")
    for name, expected in receipt["files"].items():
        if digest(directory / name) != expected:
            raise ValueError(f"Changed or incomplete built artifact: {name}")
    return receipt


def verify_licenses(directory: Path) -> dict:
    for expression, expected in {
        "MIT OR GPL-3.0-only": ["MIT"],
        "MPL-2.0 OR LGPL-2.1-or-later": ["MPL-2.0"],
        "(MIT OR Apache-2.0) AND BSD-3-Clause": ["BSD-3-Clause", "MIT"],
        "Unicode-3.0": ["Unicode-3.0"],
    }.items():
        if selection(expression) != expected:
            raise ValueError(f"Incorrect permitted license selection: {expression}")
    for expression in ("GPL-3.0-only", "AGPL-3.0-only", "LGPL-2.1-only", "MIT AND GPL-3.0-only", "Unknown"):
        try:
            selection(expression)
        except ValueError:
            pass
        else:
            raise ValueError(f"License policy accepted {expression}")
    manifest = json.loads((directory / "licenses" / "manifest.json").read_text())
    archive = directory / "licenses" / "notices-and-mpl-sources.tar.gz"
    if digest(archive) != manifest["notice_bundle_sha256"]:
        raise ValueError("Changed license archive")
    mpl_sources = 0
    with tarfile.open(archive) as bundle:
        for record in manifest["packages"]:
            if selection(record["declared_license"]) != record["selected_licenses"]:
                raise ValueError(f"Changed license selection: {record['name']}")
            if not record["notices"]:
                raise ValueError(f"Missing notices: {record['name']}")
            sources = record["notices"] + ([record["mpl_source"]] if "mpl_source" in record else [])
            if "MPL-2.0" in record["selected_licenses"]:
                if "mpl_source" not in record:
                    raise ValueError(f"Missing MPL source: {record['name']}")
                mpl_sources += 1
            for item in sources:
                member = bundle.extractfile(item["file"])
                if member is None or hashlib.sha256(member.read()).hexdigest() != item["sha256"]:
                    raise ValueError(f"Changed notice/source archive member: {item['file']}")
    return {"status": "passed", "packages": len(manifest["packages"]),
            "mpl_sources": mpl_sources, "policy_cases": 9}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-output", type=Path, default=PACKAGE / "build")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--dart", default=shutil.which("dart"))
    parser.add_argument("--node", default=shutil.which("node"))
    args = parser.parse_args()
    if not args.dart or not args.node:
        parser.error("Dart and Node are required; supply --dart and --node or put them on PATH")
    build_output = args.build_output.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    started_at = datetime.now(timezone.utc).isoformat()
    before = source_hashes()
    build_receipt = {}
    licenses = None
    records = []
    errors = []
    try:
        build_receipt = verify_distribution(build_output)
        licenses = verify_licenses(build_output)
        name = {"Windows": "quds_proofing_harper.dll", "Darwin": "libquds_proofing_harper.dylib"}.get(platform.system(), "libquds_proofing_harper.so")
        library = build_output / "native" / name
        worker = build_output / "web" / "harper_worker.mjs"
        if not library.is_file() or not worker.is_file():
            raise ValueError("Build both --native and --web before verification")
        required = {f"native/{name}", "web/harper_worker.mjs",
                    "web/quds_proofing_harper.js", "web/quds_proofing_harper_bg.wasm",
                    "licenses/manifest.json", "licenses/notices-and-mpl-sources.tar.gz"}
        if not required.issubset(build_receipt["files"]):
            raise ValueError("Build receipt omits a required runtime or license artifact")
        environment = os.environ.copy()
        environment["QUDS_HARPER_TEST_LIBRARY"] = str(library)
        environment["PATH"] = str(Path(args.node).resolve().parent) + os.pathsep + environment.get("PATH", "")
        smoke = build_output / "web_transport_smoke.js"
        commands = [
            ("rust-tests", ["cargo", "test", "--release", "--locked"], NATIVE),
            ("dart-analyze", [args.dart, "analyze", "--fatal-infos"], PACKAGE),
            ("dart-native-tests", [args.dart, "test", "--reporter", "expanded"], PACKAGE),
            ("dart-javascript-tests", [args.dart, "test", "--platform", "node", "--reporter", "expanded", "test/harper_provider_test.dart"], PACKAGE),
            ("wasm-worker", [args.node, "tool/smoke_worker.mjs", str(worker)], PACKAGE),
            ("compile-web-transport", [args.dart, "compile", "js", "-O2", "tool/web_transport_smoke.dart", "-o", str(smoke)], PACKAGE),
            ("web-transport", [args.node, "tool/run_web_transport_smoke.mjs", str(smoke), str(worker)], PACKAGE),
            ("license-policy", [sys.executable, "tool/test_license_bundle.py", "-v"], PACKAGE),
            ("host-packaging", [sys.executable, "tool/test_build_packaging.py", "-v"], PACKAGE),
        ]
        for name, command, cwd in commands:
            print(f"Running {name}", flush=True)
            started = time.monotonic()
            result = subprocess.run(command, cwd=cwd, env=environment, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True)
            log = output / f"{name}.log"
            log.write_text(result.stdout)
            records.append({"name": name, "command": command,
                            "cwd": cwd.relative_to(PACKAGE).as_posix(),
                            "exit_code": result.returncode,
                            "seconds": round(time.monotonic() - started, 3),
                            "log": log.name, "log_sha256": digest(log)})
            print(f"{name}: exit {result.returncode}", flush=True)
        verify_distribution(build_output)
    except Exception as error:
        errors.append(f"{type(error).__name__}: {error}")
    # Preserve the observed before/after state even when a command or source
    # integrity check fails. A failed run still produces an inspectable receipt.
    after = source_hashes()
    unchanged = before == after
    if not unchanged:
        errors.append("Source changed while verification commands were running")
    if (build_output / "build-receipt.json").is_file():
        shutil.copyfile(build_output / "build-receipt.json", output / "build-receipt.json")
    result = {
        "schema_version": 2,
        "started_at_utc": started_at,
        "finished_at_utc": datetime.now(timezone.utc).isoformat(),
        "status": "passed" if not errors and records and all(row["exit_code"] == 0 for row in records) else "failed",
        "source_sha256": before,
        "source_sha256_after": after,
        "source_unchanged_during_commands": unchanged,
        "artifacts_sha256": build_receipt.get("files", {}),
        "errors": errors,
        "license_check": licenses,
        "checks": records,
        "limits": [
            "Node executes the shipped Wasm worker with a Worker-message and local-file-fetch bridge; browser CSP and HTTP deployment are separate acceptance checks.",
            "This host validates the native Linux ABI only; other native targets require their own build and license-target audit.",
        ],
    }
    (output / "receipt.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": result["status"], "output": str(output), "checks": len(records)}))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())

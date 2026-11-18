#!/usr/bin/env python3
"""Restore the pinned VM test runtime for the Notes-review continuation.

Recovery implementation reconstructed after host disk exhaustion. It downloads
only the pinned official SDK and
Pub archives and never changes tracked repository inputs or contacts Actions.
Requires Python 3.12+, PyYAML, and at least 2 GiB of free disk space.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shlex
import shutil
import subprocess
import tarfile
import time
import urllib.parse
import urllib.request
import yaml

SDK_URL = "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz"
SDK_SHA256 = "baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2"
SDK_BYTES = 1581444364
LOCK_SHA256 = "35d1ef372908f4ab278973355ec6a957cd3240bea115d615056c5b9e398df974"
EXECUTABLES = {
    "bin/cache/dart-sdk/bin/dart": "01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb",
    "bin/cache/artifacts/engine/linux-x64/flutter_tester": "800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f",
}
NODE_COMPILER = "bin/cache/dart-sdk/bin/snapshots/dart2js_aot.dart.snapshot"
NODE_COMPILER_BYTES = 20827888
NODE_COMPILER_SHA256 = "29314b1f8e994436c5639a59df0243692cd83625fc587619a9c99e9a3804b1d6"
OMIT_SNAPSHOTS = {
    "analysis_server.dart.snapshot", "dartdevc.dart.snapshot",
    "dartdevc_aot.dart.snapshot", "dart2js_aot.dart.snapshot",
    "dart2wasm_product.snapshot", "dart2bytecode.dart.snapshot",
    "dds_aot.dart.snapshot",
}
OMIT_PACKAGE_DIRS = [
    "test", "tests", "test_data", "example", "examples",
    "doc", "docs", "benchmark", "benchmarks",
]


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def selected(name: str) -> bool:
    parts = PurePosixPath(name).parts
    if not parts or parts[0] != "flutter":
        return False
    if len(parts) == 1:
        return True
    if parts[1] == ".git":
        return False
    if name.startswith("flutter/bin/cache/flutter_web_sdk/"):
        return False
    if name.startswith("flutter/bin/cache/dart-sdk/bin/resources/"):
        return False
    if name.endswith(("/dartaotruntime_asan", "/dartaotruntime_msan", "/dartaotruntime_tsan")):
        return False
    if name.startswith("flutter/bin/cache/dart-sdk/bin/snapshots/") and parts[-1] in OMIT_SNAPSHOTS:
        return False
    if name.endswith("/libflutter_linux_gtk.so"):
        return False
    if parts[1] == "bin":
        if name.startswith("flutter/bin/cache/artifacts/engine/"):
            platform = parts[5] if len(parts) > 5 else ""
            if platform.startswith((
                "android", "ios", "darwin", "windows", "linux-arm64",
                "linux-x64-profile", "linux-x64-release",
            )):
                return False
        return True
    if parts[1] == "packages":
        return not (len(parts) > 3 and parts[3] in {
            "test", "test_private", "test_fixes", "example",
            "examples", "benchmark", "benchmarks",
        })
    return len(parts) == 2 and parts[1] in {
        "LICENSE", "AUTHORS", "README.md", "version", ".metadata",
        "pubspec.yaml", "pubspec.lock", "analysis_options.yaml", "flutter_console.bat",
    }


class DigestReader:
    def __init__(self, stream):
        self.stream, self.digest, self.total = stream, hashlib.sha256(), 0

    def read(self, count=-1):
        data = self.stream.read(count)
        self.digest.update(data)
        self.total += len(data)
        return data


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--runtime-root", required=True, type=Path)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--node-tests", action="store_true",
                        help="Retain the verified Dart-to-JavaScript compiler for Node test groups")
    args = parser.parse_args()
    repo, root = args.repo.resolve(), args.runtime_root.resolve()
    if repo == root or repo in root.parents or root in repo.parents:
        raise RuntimeError("Runtime and repository must be separate directories")
    if root.exists() and any(root.iterdir()):
        raise RuntimeError("Choose an empty runtime directory; preserve prior attempts")
    if sha256(repo / "pubspec.lock") != LOCK_SHA256:
        raise RuntimeError("Repository lock differs from the captured Mail-inclusive lock")
    root.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(root).free < 2 * 1024**3:
        raise RuntimeError("Need at least 2 GiB free for restoration and test artifacts")
    sdk, cache, logs = root / "flutter", root / "pub-cache", root / "logs"
    for path in [logs, cache, root / "bin", root / "tmp", root / "config", root / "data", root / "cache"]:
        path.mkdir(parents=True, exist_ok=True)
    receipt = {
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "source": str(repo), "sdk": str(sdk), "status": "restoring", "runs": [],
        "recovery_implementation": True,
        "selection": "VM Flutter tests and AOT analysis"
                     + (" and Dart-to-JavaScript Node tests" if args.node_tests else "")
                     + "; no complete web/native build toolchain",
        "workspace_lock_sha256": LOCK_SHA256,
    }

    def save():
        write_json(root / "runtime.json", receipt)

    try:
        save()
        expanded, members, last = 0, [], time.monotonic()
        print("Restoring and verifying complete official SDK stream", flush=True)
        with urllib.request.urlopen(SDK_URL, timeout=60) as response:
            reader = DigestReader(response)
            with tarfile.open(fileobj=reader, mode="r|xz") as archive:
                for member in archive:
                    if selected(member.name) or (
                        args.node_tests and member.name == "flutter/" + NODE_COMPILER
                    ):
                        expanded += member.size
                        if expanded > 1024**3 or shutil.disk_usage(root).free < 100 * 1024**2:
                            raise RuntimeError("SDK extraction reached its disk budget")
                        archive.extract(member, root, filter="data")
                        if member.isfile():
                            members.append({"path": member.name, "bytes": member.size})
                    if time.monotonic() - last > 20:
                        print(json.dumps({"downloaded_bytes": reader.total, "retained_bytes": expanded}), flush=True)
                        last = time.monotonic()
            while reader.read(8 * 1024**2):
                pass
            if reader.digest.hexdigest() != SDK_SHA256 or reader.total != SDK_BYTES:
                raise RuntimeError("Official SDK archive identity differs")
        expected_expanded = 530414490 + (NODE_COMPILER_BYTES if args.node_tests else 0)
        if expanded != expected_expanded:
            raise RuntimeError("Retained SDK selection differs from the recorded byte count")
        receipt["archive"] = {
            "url": SDK_URL, "sha256": SDK_SHA256, "bytes": SDK_BYTES,
            "verified": True, "extracted_bytes": expanded,
        }
        write_json(root / "archive-members.json", members)
        executables = dict(EXECUTABLES)
        if args.node_tests:
            executables[NODE_COMPILER] = NODE_COMPILER_SHA256
        for relative, expected in executables.items():
            if sha256(sdk / relative) != expected:
                raise RuntimeError("Verified executable differs: " + relative)
        receipt["executables_sha256"] = {str(sdk / key): value for key, value in executables.items()}
        save()

        packages = {}
        for lock in [sdk / "packages/flutter_tools/pubspec.lock", repo / "pubspec.lock"]:
            for name, item in yaml.safe_load(lock.read_text())["packages"].items():
                if item["source"] != "hosted":
                    continue
                info = item["description"]
                if info["url"] != "https://pub.dev":
                    raise RuntimeError("Unexpected dependency host")
                key = name + "-" + item["version"]
                value = {"name": name, "version": item["version"], "sha256": info["sha256"]}
                if key in packages and packages[key] != value:
                    raise RuntimeError("Conflicting package hashes")
                packages[key] = value
        if len(packages) != 176:
            raise RuntimeError("Expected the recorded set of 176 hosted archives")
        for path in [cache / "_temp", cache / "hosted/pub.dev", cache / "hosted-hashes/pub.dev"]:
            path.mkdir(parents=True, exist_ok=True)

        def fetch(pair):
            key, info = pair
            url = "https://pub.dev/api/archives/" + urllib.parse.quote(key, safe="-._+") + ".tar.gz"
            for attempt in range(3):
                try:
                    with urllib.request.urlopen(url, timeout=60) as response:
                        data = response.read()
                    break
                except Exception:
                    if attempt == 2:
                        raise
            actual = hashlib.sha256(data).hexdigest()
            if actual != info["sha256"]:
                raise RuntimeError("Package archive hash differs: " + key)
            target = cache / "hosted/pub.dev" / key
            target.mkdir()
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as bundle:
                bundle.extractall(target, filter="data")
            (cache / "hosted-hashes/pub.dev" / (key + ".sha256")).write_text(actual)
            return dict(info, url=url, bytes=len(data), verified=True)

        print("Restoring 176 hash-pinned hosted archives", flush=True)
        with ThreadPoolExecutor(max_workers=max(1, min(args.workers, 16))) as pool:
            archives = list(pool.map(fetch, sorted(packages.items())))
        write_json(root / "pub-cache-receipt.json", archives)
        receipt["hosted_archives_verified"] = len(archives)
        omissions = []
        hosted = cache / "hosted/pub.dev"
        for package in sorted(hosted.iterdir()):
            names = OMIT_PACKAGE_DIRS + (["extension"] if package.name == "drift-2.35.4" else [])
            for name in names:
                target = package / name
                if not target.is_dir():
                    continue
                files = [
                    {"path": str(path.relative_to(hosted)), "bytes": path.stat().st_size, "sha256": sha256(path)}
                    for path in sorted(target.rglob("*")) if path.is_file()
                ]
                omissions.append({
                    "path": str(target.relative_to(hosted)),
                    "bytes": sum(row["bytes"] for row in files), "files": files,
                })
                shutil.rmtree(target)
        write_json(root / "cache-omissions.json", {
            "reason": "Disk budget: author tests, examples, docs, benchmarks and Drift IDE extension omitted; runtime files and package-root notices retained.",
            "directories": omissions,
        })
        if len(omissions) != 312 or sum(row["bytes"] for row in omissions) != 197605450:
            raise RuntimeError("Dependency omission set differs from the recorded restoration")

        env = dict(os.environ, PUB_CACHE=str(cache), FLUTTER_ROOT=str(sdk), CI="true",
                   DART_SUPPRESS_ANALYTICS="true", FLUTTER_SUPPRESS_ANALYTICS="true",
                   DASH__SUPPRESS_ANALYTICS="true", XDG_CONFIG_HOME=str(root / "config"),
                   XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"),
                   TMPDIR=str(root / "tmp"))
        dart = sdk / "bin/cache/dart-sdk/bin/dart"
        flutter = root / "bin/flutter"
        flutter.write_text('#!/bin/sh\nexec "' + str(dart) + '" "' + str(sdk / "bin/cache/flutter_tools.snapshot") + '" --no-version-check "$@"\n')
        flutter.chmod(0o755)
        wrapper = root / "bin/dart"
        wrapper.write_text('#!/bin/sh\nexec "' + str(dart) + '" "$@"\n')
        wrapper.chmod(0o755)
        env["PATH"] = str(root / "bin") + os.pathsep + env.get("PATH", "")
        keys = ["PUB_CACHE", "FLUTTER_ROOT", "CI", "DART_SUPPRESS_ANALYTICS",
                "FLUTTER_SUPPRESS_ANALYTICS", "DASH__SUPPRESS_ANALYTICS",
                "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "TMPDIR"]
        (root / "env.sh").write_text(
            "\n".join("export " + key + "=" + shlex.quote(env[key]) for key in keys)
            + "\nexport PATH=" + shlex.quote(str(root / "bin")) + ':"$PATH"\n'
        )

        def run(name, command, cwd):
            log = logs / (name + ".log")
            print("START " + name, flush=True)
            with log.open("wb") as stream:
                result = subprocess.run([str(x) for x in command], cwd=cwd, env=env,
                                        stdout=stream, stderr=subprocess.STDOUT, timeout=300)
            receipt["runs"].append({
                "name": name, "command": [str(x) for x in command], "cwd": str(cwd),
                "exit_code": result.returncode, "log": str(log), "log_sha256": sha256(log),
            })
            save()
            if result.returncode:
                raise RuntimeError(name + ": " + log.read_text(errors="replace")[-8000:])
            return log

        run("flutter-tools-pub-get", [dart, "pub", "get", "--offline", "--enforce-lockfile"], sdk / "packages/flutter_tools")
        run("workspace-pub-get", [dart, "pub", "get", "--offline", "--enforce-lockfile"], repo)
        version = run("flutter-version", [flutter, "--version", "--machine"], repo)
        receipt["runtime"] = json.loads(version.read_text())
        if receipt["runtime"]["frameworkRevision"] != "737ba8f885dc774b53b442759999a312c9461e4e" or receipt["runtime"]["dartSdkVersion"] != "3.13.7":
            raise RuntimeError("Unexpected SDK runtime version")
        if sha256(repo / "pubspec.lock") != LOCK_SHA256:
            raise RuntimeError("Workspace lock changed during enforced resolution")
        receipt["workspace_package_count"] = len(json.loads((repo / ".dart_tool/package_config.json").read_text())["packages"])
        if receipt["workspace_package_count"] != 130:
            raise RuntimeError("Unexpected resolved workspace package count")
        retained = {}
        for prefix in ["flutter", "pub-cache/hosted/pub.dev"]:
            for path in sorted((root / prefix).rglob("*")):
                if path.is_file() and ".dart_tool" not in path.parts:
                    retained[str(path.relative_to(root))] = {"bytes": path.stat().st_size, "sha256": sha256(path)}
        write_json(root / "retained-inputs.json", retained)
        receipt["environment_script"] = str(root / "env.sh")
        receipt["retained_runtime_input_count"] = len(retained)
        receipt["status"] = "ready"
        (root / "runtime-ready").touch()
    except BaseException as error:
        receipt["status"], receipt["error"] = "failed", repr(error)
        raise
    finally:
        receipt["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
        save()


if __name__ == "__main__":
    main()

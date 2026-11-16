#!/usr/bin/env python3
"""Prepare an authentic Flutter 3.47.8 SDK and pinned offline Pub caches.

Run in the background in the already-working persistent shell. This helper
does not change tracked repository source or fabricate SDK version stamps.
"""
from __future__ import annotations
import argparse
import concurrent.futures
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import signal
import subprocess
import tarfile
import time
import urllib.parse
import urllib.request
import yaml

URL = "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz"
SHA256 = "baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2"
REVISION = "737ba8f885dc774b53b442759999a312c9461e4e"

def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

class DigestReader:
    def __init__(self, stream):
        self.stream = stream
        self.hash = hashlib.sha256()
        self.total = 0
    def read(self, n=-1):
        data = self.stream.read(n)
        self.hash.update(data)
        self.total += len(data)
        return data

def selected(name):
    parts = PurePosixPath(name).parts
    if not parts or parts[0] != "flutter":
        return False
    if len(parts) == 1:
        return True
    if parts[1] == ".git":
        return True
    if parts[1] == "bin":
        relative = "/".join(parts[1:])
        if relative.startswith("bin/cache/artifacts/engine/"):
            platform = parts[5] if len(parts) > 5 else ""
            if platform.startswith((
                "android", "ios", "darwin", "windows", "linux-arm64",
                "linux-x64-profile", "linux-x64-release",
            )):
                return False
        # Keep Gradle Wrapper: Flutter requires it even for pub get.
        # Keep the entire Dart SDK, including DevTools and all compilers.
        return True
    if parts[1] == "packages":
        return not (len(parts) > 3 and parts[3] in {
            "test", "test_private", "test_fixes", "example", "examples",
            "benchmark", "benchmarks",
        })
    return len(parts) == 2 and parts[1] in {
        "LICENSE", "AUTHORS", "README.md", "version", ".metadata",
        "pubspec.yaml", "pubspec.lock", "analysis_options.yaml",
        "flutter_console.bat",
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--sdk-parent", required=True, type=Path)
    parser.add_argument("--pub-cache", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--workers", type=int, default=32)
    args = parser.parse_args()
    repo, parent, cache, out = (p.resolve() for p in (
        args.repo, args.sdk_parent, args.pub_cache, args.output))
    for directory in (parent, cache, out):
        directory.mkdir(parents=True, exist_ok=True)
    sdk = parent / "flutter"
    record = {
        "started": datetime.now(timezone.utc).isoformat(),
        "sdk_archive_url": URL, "sdk_archive_sha256": SHA256,
        "repo": str(repo), "sdk_root": str(sdk), "pub_cache": str(cache),
        "commands": [], "status": "running",
    }
    def save():
        (out / "bootstrap-receipt.json").write_text(
            json.dumps(record, indent=2) + "\n")
    def run(label, argv, cwd, limit=180, extra_env=None):
        log_path = out / (label + ".log")
        print("START " + label, flush=True)
        began = time.time()
        env = {
            **os.environ, "PUB_CACHE": str(cache), "CI": "true",
            "DART_SUPPRESS_ANALYTICS": "true",
            "FLUTTER_SUPPRESS_ANALYTICS": "true",
            "FLUTTER_ROOT": str(sdk), **(extra_env or {}),
        }
        with log_path.open("wb") as log:
            proc = subprocess.Popen(
                argv, cwd=cwd, env=env, stdout=log,
                stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = proc.wait(timeout=limit)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
                code = 124
        entry = {
            "label": label, "argv": argv, "cwd": str(cwd),
            "exit_code": code, "elapsed_seconds": time.time() - began,
            "log": log_path.name, "log_sha256": sha(log_path),
        }
        record["commands"].append(entry)
        save()
        print("END " + label + " exit=" + str(code), flush=True)
        if code:
            print(log_path.read_text(errors="replace")[-10000:], flush=True)
            raise RuntimeError(label + " failed")
        return log_path

    save()
    try:
        install_receipt = out / "flutter-install-receipt.json"
        if sdk.exists():
            if not install_receipt.is_file():
                raise RuntimeError("SDK directory exists without this helper's verified receipt")
            installed = json.loads(install_receipt.read_text())
            if installed["sha256"] != SHA256:
                raise RuntimeError("Existing SDK receipt differs")
        else:
            print("STREAM_START " + URL, flush=True)
            expanded = 0
            skipped = 0
            manifest = []
            began = last = time.time()
            with urllib.request.urlopen(URL, timeout=120) as response:
                reader = DigestReader(response)
                with tarfile.open(fileobj=reader, mode="r|xz") as archive:
                    for member in archive:
                        if selected(member.name):
                            expanded += member.size
                            if expanded > 3 * 1024**3 or shutil.disk_usage(parent).free < 400 * 1024**2:
                                raise RuntimeError("Safe SDK extraction disk budget exceeded")
                            archive.extract(member, parent, filter="data")
                            if member.isfile():
                                manifest.append({"path": member.name, "bytes": member.size})
                        else:
                            skipped += 1
                        if time.time() - last >= 20:
                            print(json.dumps({
                                "downloaded_bytes": reader.total,
                                "extracted_bytes": expanded,
                                "free_bytes": shutil.disk_usage(parent).free,
                            }), flush=True)
                            last = time.time()
                while reader.read(1024 * 1024):
                    pass
                actual = reader.hash.hexdigest()
                if actual != SHA256:
                    raise RuntimeError("Official Flutter archive SHA-256 mismatch: " + actual)
            installed = {
                "url": URL, "sha256": actual, "archive_bytes": reader.total,
                "extracted_bytes": expanded, "excluded_members": skipped,
                "elapsed_seconds": time.time() - began, "files": manifest,
            }
            install_receipt.write_text(json.dumps(installed, indent=2) + "\n")
        record["sdk_install_receipt_sha256"] = sha(install_receipt)
        dart = str(sdk / "bin/cache/dart-sdk/bin/dart")
        flutter = str(sdk / "bin/flutter")
        version_log = run("flutter-version", [flutter, "--version", "--machine"], repo, 60)
        version = json.loads(version_log.read_text())
        if version["frameworkRevision"] != REVISION or version["dartSdkVersion"] != "3.13.7":
            raise RuntimeError("Unexpected actual Flutter/Dart runtime identity")
        record["actual_runtime"] = version

        project_lock = repo / "pubspec.lock"
        if not project_lock.exists():
            shutil.copyfile(
                repo / "docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock",
                project_lock)
        locks = [sdk / "packages/flutter_tools/pubspec.lock", project_lock]
        packages = {}
        for lock in locks:
            for name, item in yaml.safe_load(lock.read_text())["packages"].items():
                if item["source"] != "hosted":
                    continue
                info = item["description"]
                if info["url"] != "https://pub.dev":
                    raise RuntimeError("Unexpected hosted dependency source")
                key = name + "-" + item["version"]
                entry = {"name": name, "version": item["version"], "sha256": info["sha256"]}
                if key in packages and packages[key] != entry:
                    raise RuntimeError("Conflicting pinned package hashes")
                packages[key] = entry
        for directory in (
            cache / "_temp", cache / "hosted/pub.dev",
            cache / "hosted-hashes/pub.dev",
        ):
            directory.mkdir(parents=True, exist_ok=True)

        def fetch(pair):
            key, item = pair
            target = cache / "hosted/pub.dev" / key
            hash_file = cache / "hosted-hashes/pub.dev" / (key + ".sha256")
            result = dict(item)
            if target.is_dir() and hash_file.is_file() and hash_file.read_text().strip() == item["sha256"]:
                result.update({
                    "status": "verified-cache",
                    "verification": "existing Pub/verified archive cache hash matches pinned lock",
                })
                print("CACHE " + key, flush=True)
                return result
            url = "https://pub.dev/api/archives/" + urllib.parse.quote(key, safe="-._+") + ".tar.gz"
            result["url"] = url
            began = time.time()
            try:
                with urllib.request.urlopen(url, timeout=90) as response:
                    payload = response.read()
                actual = hashlib.sha256(payload).hexdigest()
                if actual != item["sha256"]:
                    raise RuntimeError("Pinned archive SHA-256 mismatch: " + actual)
                temporary = cache / "_temp" / ("quds-verified-" + key)
                if temporary.exists():
                    shutil.rmtree(temporary)
                temporary.mkdir()
                with tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz") as archive:
                    archive.extractall(temporary, filter="data")
                if target.exists():
                    shutil.rmtree(target)
                temporary.rename(target)
                hash_file.write_text(actual + "\n")
                result.update({
                    "status": "verified-download", "actual_sha256": actual,
                    "archive_bytes": len(payload),
                    "elapsed_seconds": time.time() - began,
                })
            except Exception as error:
                result.update({"status": "failed", "error": str(error)})
            print(json.dumps({"package": key, "status": result["status"]}), flush=True)
            return result

        # No Pub process may be writing this cache concurrently.
        began = time.time()
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            results = list(pool.map(fetch, sorted(packages.items())))
        dependency_receipt = {
            "lock_sha256": {str(lock): sha(lock) for lock in locks},
            "packages": results, "elapsed_seconds": time.time() - began,
        }
        (out / "pub-cache-receipt.json").write_text(
            json.dumps(dependency_receipt, indent=2) + "\n")
        record["pub_cache_receipt_sha256"] = sha(out / "pub-cache-receipt.json")
        failed = [item for item in results if item["status"] == "failed"]
        if failed:
            raise RuntimeError("Pinned archive prefetch failed: " + json.dumps(failed))

        run("flutter-tools-offline", [
            dart, "pub", "--suppress-analytics",
            "--directory", str(sdk / "packages/flutter_tools"),
            "get", "--example", "--offline",
        ], repo, 180)
        run("workspace-offline", [flutter, "pub", "get", "--offline"], repo, 180)
        config = repo / ".dart_tool/package_config.json"
        if not config.is_file():
            raise RuntimeError("No project package configuration after dependency resolution")
        record["project_package_config_sha256"] = sha(config)
        record["project_lock_sha256"] = sha(project_lock)
        record["project_package_count"] = len(json.loads(config.read_text())["packages"])
        record["status"] = "passed"
    except Exception as error:
        record["status"] = "failed"
        record["error"] = str(error)
    finally:
        record["finished"] = datetime.now(timezone.utc).isoformat()
        record["free_bytes"] = shutil.disk_usage(parent).free
        save()
        print("BOOTSTRAP_COMPLETE " + json.dumps({
            k: v for k, v in record.items() if k not in {"commands", "actual_runtime"}
        }), flush=True)
    return 0 if record["status"] == "passed" else 1

if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Extend the verified SDK runtime for the exact secure-storage lock profile.

The original SDK restoration profile, archive identity, omission record and
restore runs stay unchanged. Only the 18 newly locked hosted archives are
downloaded. Original receipts and generated package mappings are preserved
outside the runtime before it is marked unavailable during the extension.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.parse
import urllib.request

import yaml


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def archive_union(*locks: bytes) -> dict[str, dict]:
    result = {}
    for raw in locks:
        packages = yaml.safe_load(raw)["packages"]
        if not isinstance(packages, dict):
            raise RuntimeError("Lockfile packages must be a mapping")
        for name, item in packages.items():
            if item["source"] != "hosted":
                continue
            description, version = item["description"], item["version"]
            if (not isinstance(name, str) or not re.fullmatch(r"[a-zA-Z0-9_]+", name)
                    or not isinstance(version, str) or not re.fullmatch(r"[a-zA-Z0-9.+_-]+", version)
                    or description.get("name") != name or description.get("url") != "https://pub.dev"
                    or not re.fullmatch(r"[0-9a-f]{64}", description.get("sha256", ""))):
                raise RuntimeError("Invalid or unapproved hosted archive: " + str(name))
            key = name + "-" + version
            row = {"name": name, "version": version, "sha256": description["sha256"]}
            if key in result and result[key] != row:
                raise RuntimeError("Conflicting archive identity: " + key)
            result[key] = row
    return result


def extension_archives(base: bytes, target: bytes, sdk: bytes, profile: dict) -> tuple[dict, dict, dict]:
    for raw, key in ((base, "base_lock_sha256"), (target, "target_lock_sha256"), (sdk, "sdk_tools_lock_sha256")):
        if hashlib.sha256(raw).hexdigest() != profile[key]:
            raise RuntimeError("Lock does not match the exact extension profile: " + key)
    old, new = archive_union(base, sdk), archive_union(target, sdk)
    if len(old) != profile["base_archive_count"] or len(new) != profile["target_archive_count"]:
        raise RuntimeError("Hosted archive count differs from the exact lock profile")
    if any(new.get(name) != identity for name, identity in old.items()):
        raise RuntimeError("Extension must not remove or replace an original archive")
    additions = {name: value for name, value in new.items() if name not in old}
    expected = {row["name"] + "-" + row["version"]: row for row in profile["additions"]}
    if len(expected) != len(profile["additions"]) or additions != expected:
        raise RuntimeError("New archives differ from the explicitly pinned additions")
    return old, new, additions


def verify_inputs(runtime: Path, retained: dict, additional: dict) -> None:
    for name, row in retained.items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts or relative.as_posix() != name:
            raise RuntimeError("Unsafe retained runtime path: " + name)
        path = runtime / name
        if not path.is_file() or path.stat().st_size != row["bytes"] or digest(path) != row["sha256"]:
            raise RuntimeError("Original retained runtime input changed: " + name)
    for name, expected in additional.items():
        path = Path(name)
        if not path.is_absolute() or not path.is_file() or digest(path) != expected:
            raise RuntimeError("Original additional runtime input changed: " + name)


def merge_bindings(original: dict, refreshed: dict, generated_mapping: Path) -> dict:
    for name, value in refreshed.items():
        if name in original and original[name] != value and name != str(generated_mapping):
            raise RuntimeError("A previously bound native input changed: " + name)
    return {**original, **refreshed}


def extract_verified(archive: Path, destination: Path, expected: dict) -> None:
    if digest(archive) != expected["sha256"]:
        raise RuntimeError("Downloaded archive differs from its locked SHA-256")
    destination.mkdir()
    with tarfile.open(archive, "r:gz") as stream:
        stream.extractall(destination, filter="data")
    manifest = yaml.safe_load((destination / "pubspec.yaml").read_text())
    if manifest.get("name") != expected["name"] or str(manifest.get("version")) != expected["version"]:
        raise RuntimeError("Archive package identity differs from its lock")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True,
                        help="New empty external directory for preserved originals and staged downloads")
    parser.add_argument("--profile", type=Path, default=Path(__file__).with_name("runtime-extension-locks.json"))
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    repo, runtime, output = args.repo.resolve(), args.runtime.resolve(), args.output.resolve()
    for other in (repo, runtime):
        if output == other or other in output.parents or output in other.parents:
            raise RuntimeError("Keep extension evidence separate from source and runtime")
    if output.exists() and any(output.iterdir()):
        raise RuntimeError("Preserve prior attempts; choose a new empty extension directory")
    profile_path = args.profile.resolve()
    profile = json.loads(profile_path.read_text())
    if profile.get("schema") != 1:
        raise RuntimeError("Unsupported runtime extension profile")
    identity_path = runtime / "runtime.json"
    original = json.loads(identity_path.read_text())
    if (original.get("status") != "ready" or not original.get("archive", {}).get("verified")
            or original.get("workspace_lock_sha256") != profile["base_lock_sha256"]
            or Path(original["source"]).resolve() != repo or Path(original["sdk"]).resolve() != runtime / "flutter"
            or original["archive"]["sha256"] != profile["sdk_archive_sha256"]
            or original["archive"]["bytes"] != profile["sdk_archive_bytes"]
            or original["runtime"]["frameworkRevision"] != profile["framework_revision"]
            or original["runtime"]["dartSdkVersion"] != profile["dart_sdk_version"]):
        raise RuntimeError("Extension requires the original verified, location-bound runtime profile")
    base = subprocess.check_output(["git", "--no-replace-objects", "-C", str(repo), "show",
                                    profile["base_source_commit"] + ":pubspec.lock"])
    target = (repo / "pubspec.lock").read_bytes()
    sdk = (runtime / "flutter/packages/flutter_tools/pubspec.lock").read_bytes()
    old_archives, new_archives, additions = extension_archives(base, target, sdk, profile)
    retained = json.loads((runtime / "retained-inputs.json").read_text())
    original_additional = original.get("additional_inputs", {})
    if original["retained_runtime_input_count"] != len(retained):
        raise RuntimeError("Original retained runtime count differs")
    verify_inputs(runtime, retained, original_additional)
    previous_archives = json.loads((runtime / "pub-cache-receipt.json").read_text())
    observed = {row["name"] + "-" + row["version"]:
                {key: row[key] for key in ("name", "version", "sha256")} for row in previous_archives}
    if (observed != old_archives or len(previous_archives) != len(old_archives)
            or original["hosted_archives_verified"] != len(old_archives)
            or not all(row["verified"] is True for row in previous_archives)):
        raise RuntimeError("Original archive receipt differs from the original lock union")
    cache = runtime / "pub-cache"
    for key in additions:
        if (cache / "hosted/pub.dev" / key).exists() or (cache / "hosted-hashes/pub.dev" / (key + ".sha256")).exists():
            raise RuntimeError("New archive is already present; refusing to overwrite an earlier attempt: " + key)
    root_manifest = yaml.safe_load((repo / "pubspec.yaml").read_text())
    manifest_paths = [repo / "pubspec.yaml", repo / "pubspec.lock",
                      *(repo / path / "pubspec.yaml" for path in root_manifest["workspace"])]
    manifest_before = {str(path): digest(path) for path in manifest_paths}
    output.mkdir(parents=True, exist_ok=True)
    for folder in ("originals", "archives", "extracted", "logs"):
        (output / folder).mkdir()
    preserve = {name: runtime / name for name in (
        "runtime.json", "retained-inputs.json", "pub-cache-receipt.json", "cache-omissions.json",
        "archive-members.json", "env.sh",
    )}
    preserve.update({"workspace-" + name: repo / ".dart_tool" / name
                     for name in ("package_config.json", "package_graph.json", "native_assets.yaml")})
    preserved = {}
    for name, path in preserve.items():
        destination = output / "originals" / name
        shutil.copyfile(path, destination)
        preserved[str(destination)] = digest(destination)
    (output / "base-pubspec.lock").write_bytes(base)
    preserved[str(output / "base-pubspec.lock")] = digest(output / "base-pubspec.lock")
    record_path = output / "extension.json"
    record = {"status": "extending", "started_at_utc": datetime.now(timezone.utc).isoformat(),
              "source": str(repo), "runtime": str(runtime), "profile": str(profile_path),
              "profile_sha256": digest(profile_path), "implementation_sha256": digest(Path(__file__)),
              "base_lock_sha256": profile["base_lock_sha256"], "target_lock_sha256": profile["target_lock_sha256"],
              "preserved_originals": preserved, "base_archives": len(old_archives), "target_archives": len(new_archives),
              "new_archives": [], "runs": [], "new_archive_contents_retained_in_full": True,
              "original_sdk_provenance_and_restore_runs_preserved": True, "github_actions_queried_or_awaited": False}
    current = copy.deepcopy(original)
    current["status"] = "extending"
    current["runtime_extension"] = {"status": "extending", "receipt": str(record_path)}
    write_json(record_path, record)
    write_json(identity_path, current)
    (runtime / "runtime-ready").unlink(missing_ok=True)

    try:
        def fetch(pair):
            key, info = pair
            url = "https://pub.dev/api/archives/" + urllib.parse.quote(key, safe="-._+") + ".tar.gz"
            archive = output / "archives" / (key + ".tar.gz")
            for attempt in range(3):
                try:
                    total = 0
                    with urllib.request.urlopen(url, timeout=60) as response, archive.open("wb") as stream:
                        while chunk := response.read(1024 * 1024):
                            total += len(chunk)
                            if total > 128 * 1024 * 1024:
                                raise RuntimeError("Hosted archive exceeds extension download budget: " + key)
                            stream.write(chunk)
                    break
                except Exception:
                    if attempt == 2:
                        raise
            extract_verified(archive, output / "extracted" / key, info)
            return {**info, "url": url, "bytes": archive.stat().st_size, "verified": True,
                    "archive": str(archive), "retention": "Complete archive contents; no additional omissions"}

        print("VERIFY AND STAGE " + str(len(additions)) + " new locked archives", flush=True)
        with ThreadPoolExecutor(max_workers=max(1, min(args.workers, 8))) as pool:
            downloaded = list(pool.map(fetch, sorted(additions.items())))
        record["new_archives"] = downloaded
        write_json(record_path, record)
        for key, info in sorted(additions.items()):
            shutil.copytree(output / "extracted" / key, cache / "hosted/pub.dev" / key)
            (cache / "hosted-hashes/pub.dev" / (key + ".sha256")).write_text(info["sha256"])
        env = dict(os.environ, PUB_CACHE=str(cache), FLUTTER_ROOT=str(runtime / "flutter"), CI="true",
                   DART_SUPPRESS_ANALYTICS="true", FLUTTER_SUPPRESS_ANALYTICS="true", DASH__SUPPRESS_ANALYTICS="true",
                   XDG_CONFIG_HOME=str(runtime / "config"), XDG_CACHE_HOME=str(runtime / "cache"),
                   XDG_DATA_HOME=str(runtime / "data"), TMPDIR=str(runtime / "tmp"))
        env["PATH"] = str(runtime / "bin") + os.pathsep + env.get("PATH", "")
        dart = runtime / "flutter/bin/cache/dart-sdk/bin/dart"

        def run(name, command, cwd):
            print("START " + name, flush=True)
            log = output / "logs" / (name + ".log")
            with log.open("wb") as stream:
                result = subprocess.run([str(x) for x in command], cwd=cwd, env=env,
                                        stdout=stream, stderr=subprocess.STDOUT, timeout=300)
            record["runs"].append({"name": name, "command": [str(x) for x in command], "cwd": str(cwd),
                                   "exit_code": result.returncode, "log": str(log), "log_sha256": digest(log)})
            write_json(record_path, record)
            if result.returncode:
                raise RuntimeError(name + ": " + log.read_text(errors="replace")[-6000:])

        run("workspace-pub-get", [dart, "pub", "get", "--offline", "--enforce-lockfile"], repo)
        restoration = repo / "docs/validation/document-review-notes-20261118/runtime/restore_runtime.py"
        spec = importlib.util.spec_from_file_location("original_runtime_restorer", restoration)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with module.native_smoke_entrypoint(repo) as entrypoint:
            record["native_smoke"] = {"entrypoint": str(entrypoint), "sha256": digest(entrypoint),
                                      "owner": "quds_mail_store", "real_hook_execution": True}
            run("native-assets-smoke", [dart, "run", entrypoint], repo / "packages/quds_mail_store")
        refreshed = {}
        module.bind_test_inputs(repo, runtime, refreshed, node_tests=True)
        combined = merge_bindings(original_additional, refreshed["additional_inputs"], repo / ".dart_tool/native_assets.yaml")
        verify_inputs(runtime, retained, combined)
        if manifest_before != {str(path): digest(path) for path in manifest_paths}:
            raise RuntimeError("Source dependency manifests changed during locked extension")
        current_retained = {}
        for prefix in ("flutter", "pub-cache/hosted/pub.dev"):
            for path in sorted((runtime / prefix).rglob("*")):
                if path.is_file() and ".dart_tool" not in path.parts:
                    current_retained[str(path.relative_to(runtime))] = {"bytes": path.stat().st_size, "sha256": digest(path)}
        if any(current_retained.get(name) != row for name, row in retained.items()):
            raise RuntimeError("An original retained input changed during extension")
        if digest(runtime / "cache-omissions.json") != preserved[str(output / "originals/cache-omissions.json")]:
            raise RuntimeError("Original package omission evidence changed")
        current["workspace_packages"] = module.verified_workspace_packages(repo)
        current["workspace_package_count"] = len(current["workspace_packages"]["resolved"])
        current["workspace_lock_sha256"] = profile["target_lock_sha256"]
        current["hosted_archives_verified"] = len(new_archives)
        current["retained_runtime_input_count"] = len(current_retained)
        for key in ("native_assets", "node_runtime", "test_input_binding"):
            current[key] = refreshed[key]
        merged_archives = sorted([*previous_archives, *downloaded], key=lambda row: (row["name"], row["version"]))
        write_json(runtime / "pub-cache-receipt.json", merged_archives)
        write_json(runtime / "retained-inputs.json", current_retained)
        record.update(status="ready", finished_at_utc=datetime.now(timezone.utc).isoformat(),
                      original_retained_inputs_verified=len(retained), retained_runtime_input_count=len(current_retained),
                      workspace_packages=current["workspace_packages"], dependency_manifests_unchanged=True,
                      current_retained_manifest_sha256=digest(runtime / "retained-inputs.json"),
                      current_pub_cache_receipt_sha256=digest(runtime / "pub-cache-receipt.json"),
                      original_omission_record_unchanged=True)
        write_json(record_path, record)
        combined.update(preserved)
        combined.update({row["archive"]: row["sha256"] for row in downloaded})
        combined[str(record_path)] = digest(record_path)
        current["additional_inputs"] = combined
        current["runtime_extension"] = {"status": "ready", "receipt": str(record_path), "sha256": digest(record_path),
                                         "profile_sha256": digest(profile_path), "at_utc": record["finished_at_utc"]}
        current["status"] = "ready"
        write_json(identity_path, current)
        (runtime / "runtime-ready").touch()
        print(json.dumps({"status": "ready", "hosted_archives": len(new_archives), "new_archives": len(downloaded),
                          "retained_inputs": len(current_retained), "receipt": str(record_path)}), flush=True)
    except BaseException as error:
        record.update(status="failed", error=repr(error), finished_at_utc=datetime.now(timezone.utc).isoformat())
        write_json(record_path, record)
        current["status"] = "failed"
        current["runtime_extension"] = {"status": "failed", "receipt": str(record_path), "error": repr(error)}
        write_json(identity_path, current)
        (runtime / "runtime-ready").unlink(missing_ok=True)
        raise


if __name__ == "__main__":
    main()

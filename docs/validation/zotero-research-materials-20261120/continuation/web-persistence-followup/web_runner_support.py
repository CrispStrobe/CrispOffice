"""Shared evidence helpers; importing this module does not run a test."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
PRIMARY = HERE.parent.parent / "run_validation.py"
PRIMARY_SHA256 = "4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf"
REQUIRED_MAIN = "dbfbbd28caa064f4850dc81860a68de14d48fb35"
PACKAGE = "packages/quds_office_editor/example"
BROWSER_TEST = "test/studio_web_persistence_test.dart"
BROWSER_TEST_SHA256 = "5b95ad0aacbff2d1d639aae002c94e797322379a720bc43c292808629f41e990"
BROWSER_NAMES = [
    "a verified dictionary survives a new session and is removable",
    "stored bytes that no longer match the pins are deleted",
    "the morphology database is restored only after verification",
]
VM_TESTS = [
    "studio_hunspell_web_host_test.dart",
    "studio_hunspell_web_cancellation_test.dart",
    "studio_downloads_manager_test.dart",
]


def record(path: Path) -> dict:
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(chunk)
    return {"bytes": path.stat().st_size, "sha256": sha.hexdigest()}


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value: object) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")


def load_primary():
    if record(PRIMARY)["sha256"] != PRIMARY_SHA256:
        raise RuntimeError("The primary validation runner differs from its immutable pin")
    spec = importlib.util.spec_from_file_location("web_primary_validation", PRIMARY)
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load the original runner")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=repo, text=True).strip()


def require_source(repo: Path, expected: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", expected):
        raise RuntimeError("An exact full published source SHA is required")
    if git(repo, "rev-parse", "HEAD") != expected:
        raise RuntimeError("HEAD does not equal the requested frozen source")
    result = subprocess.run(["git", "merge-base", "--is-ancestor", REQUIRED_MAIN, expected], cwd=repo)
    if result.returncode != 0:
        raise RuntimeError("The frozen source does not preserve the captured PR229 merge")


def tree_records(roots: list[Path]) -> dict:
    """Hash regular files without following directory symlinks or modifying caches."""
    paths = set()
    for root in roots:
        if root.is_file():
            paths.add(root)
        elif root.is_dir():
            for directory, _, files in os.walk(root, followlinks=False):
                for name in files:
                    path = Path(directory) / name
                    if path.is_file():
                        paths.add(path)
    return {str(path): record(path) for path in sorted(paths)}


def chromium_inventory(binary: Path) -> dict:
    binary = binary.resolve(strict=True)
    # Call the ELF directly at execution time, avoiding /usr/bin/chromium's
    # unpinned sourced settings and old-profile crash-report cleanup.
    output = subprocess.check_output(["ldd", str(binary)], text=True)
    if "not found" in output:
        raise RuntimeError("A Chromium shared library is missing")
    libraries = {Path(p) for p in re.findall(r"(?:=>\s+|^\s*)(/\S+)", output, re.M)}
    records = tree_records([binary.parent, *sorted(libraries)])
    return {"binary": str(binary), "binary_sha256": record(binary)["sha256"],
            "files": records, "inventory_sha256": digest(records),
            "ldd_library_paths": sorted(str(p) for p in libraries)}


def code_records() -> dict:
    paths = [PRIMARY, *sorted(HERE.glob("*.py")), HERE / "chromium-baseline.json",
             HERE / "runner-support.json"]
    return {str(path): record(path) for path in paths if path.is_file()}


def sdk_web_records(sdk: Path) -> dict:
    roots = [
        sdk / "bin/cache/flutter_web_sdk",
        sdk / "bin/cache/dart-sdk/bin",
        sdk / "bin/cache/dart-sdk/lib",
        sdk / "bin/cache/flutter_tools.snapshot",
        sdk / "packages/flutter_tools/lib",
    ]
    for required in [sdk / "bin/cache/flutter_web_sdk/kernel/ddc_outline.dill",
                     sdk / "bin/cache/flutter_web_sdk/kernel/amd-canvaskit/dart_sdk.js",
                     sdk / "bin/cache/dart-sdk/bin/dart"]:
        if not required.is_file():
            raise RuntimeError(f"Required preinstalled web runtime is absent: {required}")
    roots.extend(sdk.glob("bin/cache/*stamp"))
    return tree_records(roots)


def mutable_cache_records(repo: Path, out: Path) -> dict:
    locations = {
        "workspace_dart_tool": repo / ".dart_tool",
        "studio_dart_tool": repo / PACKAGE / ".dart_tool",
        "studio_build": repo / PACKAGE / "build",
        "browser_profile": out / "browser-profile",
        "browser_disk_cache": out / "browser-disk-cache",
    }
    return {name: {"path": str(path), "present": path.exists(),
                   "files": tree_records([path])} for name, path in locations.items()}

#!/usr/bin/env python3
"""Build and assemble the pinned, daemon-free AOT runtime without Qt or HTTP.

This is an explicit developer setup action. Runtime analysis never downloads
anything. The installed worker finds its adjacent data without an RML variable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile


AOT_URL = "https://github.com/sokirko74/aot.git"
AOT_REVISION = "0d591d972c7bb2729f4764d3bc32611ea6fd142a"
NLP_BASE_REVISION = "244b3d1f9a09e4a81e75ea83c3b55b209c663503"
PACKAGE = Path(__file__).resolve().parents[1]
REPOSITORY = PACKAGE.parents[1]


def run(arguments: list[str], *, env: dict[str, str] | None = None) -> None:
    print("+ " + " ".join(arguments), flush=True)
    subprocess.run(arguments, check=True, env=env)


def git(source: Path, *arguments: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(source), *arguments], text=True
    ).strip()


def verify_source(source: Path) -> None:
    if git(source, "rev-parse", "HEAD") != AOT_REVISION:
        raise RuntimeError(f"AOT source must be pinned at {AOT_REVISION}")
    if git(source / "Source/nlp_base", "rev-parse", "HEAD") != NLP_BASE_REVISION:
        raise RuntimeError(f"nlp_base must be pinned at {NLP_BASE_REVISION}")
    for path in (source, source / "Source/nlp_base"):
        if git(path, "status", "--porcelain", "--untracked-files=no"):
            raise RuntimeError(f"Refusing to build modified tracked upstream files: {path}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assemble(source: Path, build: Path, install: Path) -> dict[str, object]:
    executable_name = "quds_aot_worker.exe" if os.name == "nt" else "quds_aot_worker"
    executable = build / "bin" / executable_name
    if not executable.is_file():
        raise RuntimeError("The build did not produce the native worker")
    install.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=install.name + "-staging-", dir=install.parent))
    backup = install.with_name(install.name + "-previous")
    try:
        (staging / "Bin").mkdir()
        shutil.copy2(executable, staging / "Bin" / executable_name)
        for path in (source / "Bin").iterdir():
            if path.is_file() and path.suffix in (".ini", ".txt", ".opt", ".base", ".xml"):
                shutil.copy2(path, staging / "Bin" / path.name)
        ignore = shutil.ignore_patterns("CMakeLists.txt", "*.log", "*.log.*", "*.new", "*.old")
        for directory in ("Dicts", "Thes"):
            shutil.copytree(source / directory, staging / directory, ignore=ignore)
        notices = staging / "notices"
        notices.mkdir()
        shutil.copy2(source / "copying", notices / "AOT-COPYING")
        nlp_license = source / "Source/nlp_base/LICENSE"
        if not nlp_license.is_file():
            nlp_license = source / "Source/nlp_base/copying"
        if nlp_license.is_file():
            shutil.copy2(nlp_license, notices / "NLP-BASE-LICENSE")
        shutil.copy2(PACKAGE / "native/NOTICE.md", notices / "QUDS-NATIVE-NOTICE.md")

        # Exercise the assembled layout with RML removed: the executable must
        # find only the data next to itself, not the build/source checkout.
        smoke_env = os.environ.copy()
        smoke_env.pop("RML", None)
        smoke = subprocess.run(
            [sys.executable, str(PACKAGE / "tool/smoke_native.py"),
             "--executable", str(staging / "Bin" / executable_name)],
            env=smoke_env, text=True, capture_output=True, timeout=180, check=True,
        )
        (staging / "smoke.json").write_text(smoke.stdout, encoding="utf-8")
        manifest: dict[str, object] = {
            "protocol": 1,
            "aot": {"repository": AOT_URL, "revision": AOT_REVISION},
            "nlp_base": {
                "repository": "https://github.com/sokirko74/nlp_base.git",
                "revision": NLP_BASE_REVISION,
            },
            "platform": platform.platform(),
            "executable": str(install / "Bin" / executable_name),
            "rmlDirectory": str(install),
            "executableSha256": sha256(staging / "Bin" / executable_name),
            "workerSourceSha256": sha256(PACKAGE / "native/worker.cpp"),
            "cmakeSourceSha256": sha256(PACKAGE / "native/CMakeLists.txt"),
            "smoke": json.loads(smoke.stdout),
            "runtimeNetwork": False,
            "licenseNotice": "notices/QUDS-NATIVE-NOTICE.md",
        }
        (staging / "manifest.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        if backup.exists():
            raise RuntimeError(f"Previous runtime backup exists; inspect before replacing: {backup}")
        if install.exists():
            if not (install / "manifest.json").is_file():
                raise RuntimeError(f"Refusing to replace an unrecognized directory: {install}")
            install.rename(backup)
        try:
            staging.rename(install)
        except BaseException:
            if backup.exists():
                backup.rename(install)
            raise
        if backup.exists():
            shutil.rmtree(backup)
        return manifest
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Use an existing, exact pinned AOT checkout with submodule")
    parser.add_argument("--build-dir", type=Path, default=REPOSITORY / ".dart_tool/quds_aot_native")
    parser.add_argument("--install", type=Path, help="Runtime destination; defaults to BUILD_DIR/runtime")
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 4))
    arguments = parser.parse_args()
    if not 1 <= arguments.jobs <= 64:
        parser.error("--jobs must be between 1 and 64")
    for command in ("git", "cmake"):
        if not shutil.which(command):
            parser.error(f"Required build tool is missing: {command}")
    if not (shutil.which("flex") or shutil.which("win_flex")):
        parser.error("Required build tool is missing: flex (win_flex on Windows)")
    if not (shutil.which("bison") or shutil.which("win_bison")):
        parser.error("Required build tool is missing: bison (win_bison on Windows)")
    cache = arguments.build_dir.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    source = arguments.source.resolve() if arguments.source else cache / "aot"
    if not source.exists():
        if arguments.source:
            parser.error("The specified --source directory does not exist")
        run(["git", "clone", "--no-checkout", "--depth", "1", AOT_URL, str(source)])
        run(["git", "-C", str(source), "fetch", "--depth", "1", "origin", AOT_REVISION])
        run(["git", "-C", str(source), "checkout", "--detach", AOT_REVISION])
        run(["git", "-C", str(source), "submodule", "update", "--init", "--depth", "1"])
    verify_source(source)
    build = cache / "build"
    install = arguments.install.resolve() if arguments.install else cache / "runtime"
    if install == source or install in source.parents or source in install.parents:
        raise RuntimeError("Runtime installation must be separate from the upstream source checkout")
    env = os.environ.copy()
    env["RML"] = str(source)
    run(["cmake", "-S", str(PACKAGE / "native"), "-B", str(build),
         "-DCMAKE_BUILD_TYPE=Release", f"-DQUDS_AOT_SOURCE={source}"], env=env)
    run(["cmake", "--build", str(build), "--config", "Release", "--target",
         "quds_aot_worker", "--parallel", str(arguments.jobs)], env=env)
    manifest = assemble(source, build, install)
    print(json.dumps(manifest, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"Native AOT build failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        raise SystemExit(2)

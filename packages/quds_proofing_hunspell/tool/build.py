#!/usr/bin/env python3
"""Build the optional Hunspell spelling backend from pinned sources.

Downloads the Hunspell 1.7.2 release tarball, verifies its SHA-256 before
extraction, builds the MIT adapter plus the unmodified Hunspell library
sources (used under their MPL 1.1 option) as a native shared library and/or
an Emscripten WebAssembly module, and writes a receipt that names and hashes
every output. Dictionaries are never built into the app; users download them.

    python3 tool/build.py --native --wasm --output build/hunspell
    python3 tool/build.py --license-bundle   # regenerate licenses/ sources tarball
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request

PACKAGE = Path(__file__).resolve().parents[1]
NATIVE = PACKAGE / "native"
LICENSES = PACKAGE / "licenses"
HUNSPELL = {
    "version": "1.7.2",
    "url": "https://github.com/hunspell/hunspell/releases/download/v1.7.2/hunspell-1.7.2.tar.gz",
    "sha256": "11ddfa39afe28c28539fe65fc4f1592d410c1e9b6dd7d8a91ca25d85e9ec65b8",
    "bytes": 1536202,
}
# Library files compiled into the backend. tools/, parsers/ and the
# command-line programs are never built.
LIBRARY_FILES = sorted([
    "affentry.cxx", "affentry.hxx", "affixmgr.cxx", "affixmgr.hxx", "atypes.hxx", "baseaffix.hxx",
    "csutil.cxx", "csutil.hxx", "filemgr.cxx", "filemgr.hxx", "hashmgr.cxx", "hashmgr.hxx",
    "htypes.hxx", "hunspell.cxx", "hunspell.h", "hunspell.hxx", "hunvisapi.h", "hunzip.cxx",
    "hunzip.hxx", "langnum.hxx", "phonet.cxx", "phonet.hxx", "replist.cxx", "replist.hxx",
    "suggestmgr.cxx", "suggestmgr.hxx", "utf_info.hxx", "w_char.hxx"])
NOTICE_FILES = ["COPYING.MPL", "license.hunspell", "license.myspell", "AUTHORS", "THANKS"]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(args, cwd=None):
    print(" ".join(str(a) for a in args), flush=True)
    subprocess.run([str(a) for a in args], cwd=cwd, check=True)


def fetch_source(work: Path) -> Path:
    """Download, verify and extract the pinned tarball. Returns the source root."""
    work.mkdir(parents=True, exist_ok=True)
    archive = work / "hunspell-1.7.2.tar.gz"
    if not archive.exists() or sha(archive.read_bytes()) != HUNSPELL["sha256"]:
        with urllib.request.urlopen(HUNSPELL["url"], timeout=120) as response:  # noqa: S310 (pinned)
            data = response.read()
        if len(data) != HUNSPELL["bytes"] or sha(data) != HUNSPELL["sha256"]:
            raise SystemExit("Hunspell tarball does not match its pin")
        archive.write_bytes(data)
    root = work / "hunspell-1.7.2"
    if root.exists():
        shutil.rmtree(root)
    with tarfile.open(archive) as tar:
        members = [m for m in tar.getmembers()
                   if m.isfile() and not m.name.startswith("/") and ".." not in Path(m.name).parts]
        tar.extractall(work, members=members, filter="data")
    return root


def license_bundle(root: Path) -> dict:
    """Deterministic tarball of the exact compiled MPL sources and notices."""
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        names = [f"src/hunspell/{name}" for name in LIBRARY_FILES] + NOTICE_FILES
        for name in names:
            data = (root / name).read_bytes()
            info = tarfile.TarInfo(f"hunspell-1.7.2/{name}")
            info.size, info.mtime, info.mode, info.uid, info.gid = len(data), 0, 0o644, 0, 0
            info.uname = info.gname = ""
            tar.addfile(info, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", mtime=0, filename="") as gz:
        gz.write(buffer.getvalue())
    target = LICENSES / "hunspell-1.7.2-library-sources.tar.gz"
    target.write_bytes(compressed.getvalue())
    for name in ("COPYING.MPL", "license.hunspell", "license.myspell"):
        shutil.copyfile(root / name, LICENSES / "upstream" / name)
    manifest = {
        "schema_version": 1,
        "policy": "MIT adapter; Hunspell library files under the MPL 1.1 option of their MPL 1.1/GPL 2.0/LGPL 2.1 "
                  "tri-licence; MySpell-derived parts under the MySpell BSD-style notice; no GPL/LGPL-only code",
        "component": {
            "name": "hunspell", "version": HUNSPELL["version"], "source": HUNSPELL["url"],
            "tarball_sha256": HUNSPELL["sha256"], "selected_license": "MPL-1.1",
            "offered_licenses": "MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later",
            "notes": [
                "phonet.cxx carries an LGPL 2.1 header whose changelog records its 2007 release by the author "
                "under the MPL/GPL/LGPL tri-licence for Hunspell; it is used under MPL 1.1 like the rest.",
                "hunvisapi.h is a generated visibility header without a notice.",
                "Compiled files are unmodified; their exact sources are in hunspell-1.7.2-library-sources.tar.gz.",
            ],
            "compiled_files": {name: sha((root / "src/hunspell" / name).read_bytes()) for name in LIBRARY_FILES},
        },
        "notices": {name: sha((root / name).read_bytes()) for name in NOTICE_FILES},
        "source_bundle": {"file": target.name, "sha256": sha(target.read_bytes())},
    }
    (LICENSES / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                                            encoding="utf-8", newline="\n")
    return manifest


def library_name() -> str:
    system = platform.system()
    return {"Darwin": "libquds_proofing_hunspell.dylib", "Windows": "quds_proofing_hunspell.dll"}.get(
        system, "libquds_proofing_hunspell.so")


def android_ndk() -> Path:
    for key in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"):
        if os.environ.get(key):
            return Path(os.environ[key])
    sdk = Path(os.environ.get("ANDROID_HOME") or Path.home() / "Library/Android/sdk")
    versions = sorted((sdk / "ndk").glob("*"), key=lambda p: [int(x) for x in p.name.split(".") if x.isdigit()])
    if not versions:
        raise SystemExit("Android NDK not found (set ANDROID_NDK_HOME)")
    return versions[-1]


def build(root: Path, output: Path, kind: str, jobs: int) -> list[Path]:
    build_dir = output / f"cmake-{kind}"
    if kind == "android":
        # arm64-v8a with static libc++, so the APK needs no libc++_shared.so.
        ndk = android_ndk()
        run(["cmake", "-S", NATIVE, "-B", build_dir, "-DCMAKE_BUILD_TYPE=Release", f"-DHUNSPELL_SOURCE_DIR={root}",
             f"-DCMAKE_TOOLCHAIN_FILE={ndk / 'build/cmake/android.toolchain.cmake'}",
             "-DANDROID_ABI=arm64-v8a", "-DANDROID_PLATFORM=android-24", "-DANDROID_STL=c++_static"])
        run(["cmake", "--build", build_dir, "--parallel", str(jobs)])
        found = [p for p in build_dir.rglob("libquds_proofing_hunspell.so") if p.is_file()]
        if len(found) != 1:
            raise SystemExit(f"expected one Android library, found {found}")
        (output / "android").mkdir(parents=True, exist_ok=True)
        target = output / "android" / "libquds_proofing_hunspell.so"
        shutil.copyfile(found[0], target)
        return [target]
    if kind == "native":
        run(["cmake", "-S", NATIVE, "-B", build_dir, "-DCMAKE_BUILD_TYPE=Release", f"-DHUNSPELL_SOURCE_DIR={root}"])
        run(["cmake", "--build", build_dir, "--config", "Release", "--parallel", str(jobs)])
        found = [p for p in build_dir.rglob(library_name()) if p.is_file()]
        if len(found) != 1:
            raise SystemExit(f"expected one {library_name()}, found {found}")
        (output / "native").mkdir(parents=True, exist_ok=True)
        target = output / "native" / library_name()
        shutil.copyfile(found[0], target)
        return [target]
    run(["emcmake", "cmake", "-S", NATIVE, "-B", build_dir, "-DCMAKE_BUILD_TYPE=Release",
         f"-DHUNSPELL_SOURCE_DIR={root}"])
    run(["cmake", "--build", build_dir, "--parallel", str(jobs)])
    (output / "web").mkdir(parents=True, exist_ok=True)
    targets = []
    for name in ("quds_proofing_hunspell.mjs", "quds_proofing_hunspell.wasm"):
        target = output / "web" / name
        shutil.copyfile(build_dir / name, target)
        targets.append(target)
    target = output / "web" / "hunspell_worker.mjs"
    shutil.copyfile(PACKAGE / "web" / "hunspell_worker.mjs", target)
    targets.append(target)
    return targets


def install_licenses(destination: Path) -> None:
    """MPL notices, the licence manifest and the exact compiled sources."""
    destination.mkdir(parents=True, exist_ok=True)
    for path in sorted((LICENSES / "upstream").iterdir()):
        shutil.copyfile(path, destination / path.name)
    for name in ("manifest.json", "hunspell-1.7.2-library-sources.tar.gz"):
        shutil.copyfile(LICENSES / name, destination / name)
    shutil.copyfile(PACKAGE / "LICENSE", destination / "LICENSE.adapter")


def install(output: Path, kind: str, destination: Path, licenses: bool) -> dict:
    """Copy one built, receipt-verified backend into a host location.

    Only files named and hashed by this build's receipt are copied, never
    stale outputs. `kind` is "native" or "web"; with `licenses`, the notices
    go to `<destination>/licenses/hunspell/` (web hosts serve them next to
    the worker; native app bundles keep code and notices apart and use
    --install-licenses instead).
    """
    destination = destination.resolve()
    if destination == (output / kind).resolve():
        raise SystemExit("Choose a host directory separate from the build output")
    receipt_path = output / "build-receipt.json"
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    names = [name for name in receipt["files"] if name.startswith(kind + "/")]
    if not names:
        raise SystemExit(f"this build has no {kind} outputs")
    for name in names:
        if sha((output / name).read_bytes()) != receipt["files"][name]:
            raise SystemExit(f"changed build artifact: {name}")
    destination.mkdir(parents=True, exist_ok=True)
    for name in names:
        shutil.copyfile(output / name, destination / Path(name).name)
    if licenses:
        install_licenses(destination / "licenses" / "hunspell")
        shutil.copyfile(receipt_path, destination / "licenses" / "hunspell" / "build-receipt.json")
    return {"kind": kind, "destination": str(destination), "files": names}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--wasm", action="store_true")
    parser.add_argument("--android", action="store_true", help="Cross-build arm64-v8a with the Android NDK")
    parser.add_argument("--license-bundle", action="store_true")
    parser.add_argument("--output", type=Path, default=PACKAGE / "build")
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--install-native", type=Path,
                        help="Copy the built library into this host directory (e.g. <App>.app/Contents/Frameworks)")
    parser.add_argument("--install-web", type=Path,
                        help="Copy the worker, module and wasm plus notices into this web asset directory "
                             "(e.g. packages/quds_office_editor/example/web/proofing)")
    parser.add_argument("--install-android", type=Path,
                        help="Copy the arm64-v8a library into this jniLibs ABI directory "
                             "(e.g. android/app/src/main/jniLibs/arm64-v8a)")
    parser.add_argument("--install-licenses", type=Path,
                        help="Copy the MPL notices, licence manifest and exact sources into this directory")
    args = parser.parse_args()
    if args.install_native and not args.native:
        parser.error("--install-native requires --native")
    if args.install_web and not args.wasm:
        parser.error("--install-web requires --wasm")
    if args.install_android and not args.android:
        parser.error("--install-android requires --android")
    output = args.output.resolve()
    root = fetch_source(output / "source")
    if args.license_bundle:
        license_bundle(root)
    outputs: list[Path] = []
    if args.native:
        outputs += build(root, output, "native", args.jobs)
    if args.wasm:
        outputs += build(root, output, "wasm", args.jobs)
    if args.android:
        outputs += build(root, output, "android", args.jobs)
    if outputs:
        manifest = json.loads((LICENSES / "manifest.json").read_text(encoding="utf-8"))
        for name, digest in manifest["component"]["compiled_files"].items():
            if sha((root / "src/hunspell" / name).read_bytes()) != digest:
                raise SystemExit(f"compiled source differs from the licence manifest: {name}")
        receipt = {"hunspell": HUNSPELL, "platform": platform.platform(),
                   "adapter_sha256": sha((NATIVE / "src/quds_hunspell.cpp").read_bytes()),
                   "license_manifest_sha256": sha((LICENSES / "manifest.json").read_bytes()),
                   "files": {p.relative_to(output).as_posix(): sha(p.read_bytes()) for p in outputs}}
        (output / "build-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                                   encoding="utf-8", newline="\n")
        print(json.dumps(receipt["files"], indent=2))
    if args.install_native:
        print(json.dumps(install(output, "native", args.install_native, licenses=False)))
    if args.install_web:
        print(json.dumps(install(output, "web", args.install_web, licenses=True)))
    if args.install_android:
        print(json.dumps(install(output, "android", args.install_android, licenses=False)))
    if args.install_licenses:
        install_licenses(args.install_licenses.resolve())
        print(json.dumps({"licenses": str(args.install_licenses.resolve())}))
    return 0


if __name__ == "__main__":
    sys.exit(main())

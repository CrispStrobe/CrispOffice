#!/usr/bin/env python3
"""Build the bundled language identifier (CLD3) from pinned sources.

Downloads exactly the CrispASR files that make up the CLD3 runtime
(crisp_lid/src/lid_cld3.{h,cpp}) and the CrispASR licence from one immutable
CrispASR commit, admits each file only when its length and SHA-256 equal the
pins below, builds the MIT adapter and GGUF shim plus that source as a native
shared library and/or an Emscripten WebAssembly module, and writes a receipt
that names and hashes every output. ggml is not built: lid_cld3 runs its
forward pass in plain C++ and only loads weights through ggml/gguf calls,
which native/shim and native/src/gguf_shim.cpp provide.

The CLD3 model (Apache-2.0, ~440 KB) is bundled with the app as
assets/cld3-f16.gguf and pinned below; --verify-model checks it, or fetches
it again from the immutable Hugging Face revision with --fetch-model.

    python3 tool/build.py --native --wasm --output build
    python3 tool/build.py --license-bundle   # regenerate licenses/
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
import urllib.request

PACKAGE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACKAGE.parents[1] / "tools" / "proofing"))
import mobile_native  # noqa: E402  (monorepo helper: iOS frameworks, Android ABIs)
NATIVE = PACKAGE / "native"
LICENSES = PACKAGE / "licenses"
CRISPASR = {
    "repository": "https://github.com/CrispStrobe/CrispASR",
    # Last change to crisp_lid/ on CrispASR main (#572).
    "commit": "19d86f9b8c6b46bb35bef789c44ea403004f807c",
}
RAW = "https://raw.githubusercontent.com/CrispStrobe/CrispASR/{commit}/{path}"
# Every file fetched from CrispASR: path -> (SHA-256, bytes). Nothing else of
# CrispASR (no ggml, no fastText backend, no dispatcher) is compiled.
SOURCES = {
    "LICENSE": ("aa918fb53ff1948e12cdae8136e045210fb6db222a1f6f0c14bad48e6de2100e", 1184),
    "crisp_lid/src/lid_cld3.cpp": ("586133c1aa1432180b052f7aa2009965029b74f43dfc41d3b511b783ceb66acd", 35792),
    "crisp_lid/src/lid_cld3.h": ("f5403cb6da0349c26d85902d8a55b22d1d0af69e4a7a0e33fc012e8ce976d8c7", 4988),
}
MODEL = {
    "repository": "https://huggingface.co/cstr/cld3-GGUF",
    "revision": "56e8a57d479faa184dceede5f985d08d9816e999",
    "file": "cld3-f16.gguf",
    "sha256": "900813b635fa7f472beac213f521d57dd12378099b0623a8a36de0310b6bf892",
    "bytes": 439712,
    "license": "Apache-2.0",
    "upstream": "https://github.com/google/cld3 (b48dc46512566f5a2d41118c8c1116c4f96dc661)",
}
MODEL_URL = "{repository}/resolve/{revision}/{file}"
# Notices shipped with the binary and the model: name -> (url, SHA-256, bytes).
NOTICE_FILES = {
    "CrispASR-LICENSE": (RAW.format(commit=CRISPASR["commit"], path="LICENSE"),
                         "aa918fb53ff1948e12cdae8136e045210fb6db222a1f6f0c14bad48e6de2100e", 1184),
    "CLD3-LICENSE": ("https://raw.githubusercontent.com/google/cld3/b48dc46512566f5a2d41118c8c1116c4f96dc661/LICENSE",
                     "c2d13ec3b431617beb314705c0f42d17ca579eed00032ed8a13dbcd23fc9bdd5", 11392),
    "cld3-GGUF-README.md": (f"{MODEL['repository']}/resolve/{MODEL['revision']}/README.md",
                            "03b940d625abc68595c4d011b0e771db8a4d07ba4f1a4048890e43c04f14f070", 8327),
}
LIBRARY = "quds_language_id"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(args, cwd=None):
    print(" ".join(str(a) for a in args), flush=True)
    subprocess.run([str(a) for a in args], cwd=cwd, check=True)


def download(url: str, digest: str, size: int, label: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as response:  # noqa: S310 (pinned)
        data = response.read(size + 1)
    if len(data) != size or sha(data) != digest:
        raise SystemExit(f"{label} does not match its pin")
    return data


def fetch_source(work: Path) -> Path:
    """Download (or reuse) and verify every pinned file. Returns the tree root."""
    root = work / f"crispasr-{CRISPASR['commit'][:12]}"
    for path, (digest, size) in SOURCES.items():
        target = root / path
        if target.exists() and target.stat().st_size == size and sha(target.read_bytes()) == digest:
            continue
        data = download(RAW.format(commit=CRISPASR["commit"], path=path), digest, size, f"CrispASR {path}")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    present = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()}
    if present != set(SOURCES):
        raise SystemExit(f"unexpected files in {root}: {sorted(present - set(SOURCES))}")
    return root


def verify_model(path: Path = PACKAGE / "assets" / MODEL["file"]) -> None:
    data = path.read_bytes()
    if len(data) != MODEL["bytes"] or sha(data) != MODEL["sha256"]:
        raise SystemExit(f"{path} differs from the pinned CLD3 model")


def fetch_model() -> None:
    data = download(MODEL_URL.format(**MODEL), MODEL["sha256"], MODEL["bytes"], "CLD3 model")
    (PACKAGE / "assets").mkdir(exist_ok=True)
    (PACKAGE / "assets" / MODEL["file"]).write_bytes(data)


def adapter_files() -> dict:
    files = {}
    for path in sorted(NATIVE.rglob("*")):
        if path.is_file() and path.suffix in (".cpp", ".h", ".txt"):
            files[path.relative_to(PACKAGE).as_posix()] = sha(path.read_bytes())
    return files


def license_bundle(root: Path) -> dict:
    """Fetch the notices and write the licence manifest."""
    for name, (url, digest, size) in NOTICE_FILES.items():
        folder = LICENSES / ("upstream" if name == "CrispASR-LICENSE" else "model")
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / name
        if not (target.exists() and sha(target.read_bytes()) == digest):
            target.write_bytes(download(url, digest, size, name))
    manifest = {
        "schema_version": 1,
        "policy": "MIT adapter and GGUF shim; MIT CrispASR CLD3 runtime (a port of Apache-2.0 google/cld3); "
                  "the bundled CLD3 model is Apache-2.0 (Google Inc.). No ggml, no GPL/LGPL code.",
        "component": {
            "name": "crispasr-crisp_lid-cld3", "source": CRISPASR["repository"], "commit": CRISPASR["commit"],
            "license": "MIT",
            "files": {path: digest for path, (digest, _) in sorted(SOURCES.items())},
        },
        "model": dict(MODEL),
        "notices": {
            name: {"path": f"{'upstream' if name == 'CrispASR-LICENSE' else 'model'}/{name}", "sha256": digest}
            for name, (_, digest, _) in sorted(NOTICE_FILES.items())
        },
    }
    (LICENSES / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                                            encoding="utf-8", newline="\n")
    return manifest


def library_name() -> str:
    system = platform.system()
    return {"Darwin": f"lib{LIBRARY}.dylib", "Windows": f"{LIBRARY}.dll"}.get(system, f"lib{LIBRARY}.so")


def build(root: Path, output: Path, kind: str, jobs: int, abis=mobile_native.ANDROID_ABIS) -> list[Path]:
    build_dir = output / f"cmake-{kind}"
    common = ["-S", NATIVE, "-B", build_dir, "-DCMAKE_BUILD_TYPE=MinSizeRel", f"-DCRISPASR_SOURCE_DIR={root}"]
    if kind == "android":
        return mobile_native.build_cmake_android(
            NATIVE, output, LIBRARY, abis, [f"-DCRISPASR_SOURCE_DIR={root}"], output, jobs, "MinSizeRel")
    if kind == "ios":
        return mobile_native.build_cmake_ios(
            NATIVE, output, LIBRARY, [f"-DCRISPASR_SOURCE_DIR={root}"], output, jobs, "MinSizeRel")
    if kind == "native":
        extra = ["-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15"] if platform.system() == "Darwin" else []
        run(["cmake", *common, *extra])
        run(["cmake", "--build", build_dir, "--config", "MinSizeRel", "--parallel", str(jobs)])
        found = [p for p in build_dir.rglob(library_name()) if p.is_file()]
        if len(found) != 1:
            raise SystemExit(f"expected one {library_name()}, found {found}")
        (output / "native").mkdir(parents=True, exist_ok=True)
        target = output / "native" / library_name()
        shutil.copyfile(found[0], target)
        return [target]
    run(["emcmake", "cmake", *common])
    run(["cmake", "--build", build_dir, "--parallel", str(jobs)])
    (output / "web").mkdir(parents=True, exist_ok=True)
    targets = []
    for name in (f"{LIBRARY}.mjs", f"{LIBRARY}.wasm"):
        target = output / "web" / name
        shutil.copyfile(build_dir / name, target)
        targets.append(target)
    target = output / "web" / "language_id_worker.mjs"
    shutil.copyfile(PACKAGE / "web" / "language_id_worker.mjs", target)
    targets.append(target)
    return targets


def install_licenses(destination: Path) -> None:
    """Code and model notices, the manifest and the adapter licence."""
    destination.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((LICENSES / "manifest.json").read_text(encoding="utf-8"))
    for name, entry in manifest["notices"].items():
        data = (LICENSES / entry["path"]).read_bytes()
        if sha(data) != entry["sha256"]:
            raise SystemExit(f"notice differs from the licence manifest: {name}")
        (destination / name).write_bytes(data)
    shutil.copyfile(LICENSES / "manifest.json", destination / "manifest.json")
    shutil.copyfile(PACKAGE / "LICENSE", destination / "LICENSE.adapter")


def install(output: Path, kind: str, destination: Path, licenses: bool) -> dict:
    """Copy one built, receipt-verified backend into a host location (only
    files named and hashed by this build's receipt, never stale outputs)."""
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
        install_licenses(destination / "licenses" / "language_id")
        shutil.copyfile(receipt_path, destination / "licenses" / "language_id" / "build-receipt.json")
    return {"kind": kind, "destination": str(destination), "files": names}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--wasm", action="store_true")
    parser.add_argument("--license-bundle", action="store_true")
    parser.add_argument("--verify-model", action="store_true", help="Check assets/cld3-f16.gguf against its pin")
    parser.add_argument("--fetch-model", action="store_true", help="Re-download the pinned model into assets/")
    parser.add_argument("--output", type=Path, default=PACKAGE / "build")
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--install-native", type=Path,
                        help="Copy the built library into this host directory (e.g. <App>.app/Contents/Frameworks)")
    parser.add_argument("--install-web", type=Path,
                        help="Copy the worker, module and wasm plus notices into this web asset directory "
                             "(e.g. packages/quds_office_editor/example/web/proofing)")
    mobile_native.add_arguments(parser)
    parser.add_argument("--install-licenses", type=Path,
                        help="Copy the code and model notices and the licence manifest into this directory")
    args = parser.parse_args()
    if args.install_native and not args.native:
        parser.error("--install-native requires --native")
    if args.install_web and not args.wasm:
        parser.error("--install-web requires --wasm")
    mobile_native.check_arguments(parser, args)
    if args.fetch_model:
        fetch_model()
    verify_model()
    output = args.output.resolve()
    needs_source = args.license_bundle or args.native or args.wasm or args.android or args.ios
    root = fetch_source(output / "source") if needs_source else None
    if args.license_bundle:
        license_bundle(root)
    outputs: list[Path] = []
    if args.native:
        outputs += build(root, output, "native", args.jobs)
    if args.wasm:
        outputs += build(root, output, "wasm", args.jobs)
    if args.android:
        outputs += build(root, output, "android", args.jobs, mobile_native.abis(args))
    if args.ios:
        outputs += build(root, output, "ios", args.jobs)
    if outputs:
        manifest = json.loads((LICENSES / "manifest.json").read_text(encoding="utf-8"))
        if manifest["component"]["commit"] != CRISPASR["commit"]:
            raise SystemExit("licence manifest names another CrispASR commit; run --license-bundle")
        for path, digest in manifest["component"]["files"].items():
            if sha((root / path).read_bytes()) != digest:
                raise SystemExit(f"compiled source differs from the licence manifest: {path}")
        if manifest["model"]["sha256"] != MODEL["sha256"]:
            raise SystemExit("licence manifest names another model; run --license-bundle")
        for name, entry in manifest["notices"].items():
            if sha((LICENSES / entry["path"]).read_bytes()) != entry["sha256"]:
                raise SystemExit(f"notice differs from the licence manifest: {name}")
        receipt = {"crispasr": CRISPASR, "model": MODEL, "platform": platform.platform(),
                   "adapter": adapter_files(),
                   "license_manifest_sha256": sha((LICENSES / "manifest.json").read_bytes()),
                   "files": {p.relative_to(output).as_posix(): sha(p.read_bytes()) for p in outputs}}
        receipt_path = output / "build-receipt.json"
        if receipt_path.exists():
            previous = json.loads(receipt_path.read_text(encoding="utf-8")).get("files", {})
            for name, digest in previous.items():
                if name not in receipt["files"] and (output / name).exists() \
                        and sha((output / name).read_bytes()) == digest:
                    receipt["files"][name] = digest
        receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                encoding="utf-8", newline="\n")
        print(json.dumps({k: (v, (output / k).stat().st_size) for k, v in receipt["files"].items()}, indent=2))
    if args.install_native:
        print(json.dumps(install(output, "native", args.install_native, licenses=False)))
    if args.install_web:
        print(json.dumps(install(output, "web", args.install_web, licenses=True)))
    for installed in mobile_native.install_from_arguments(output, args, LIBRARY):
        print(json.dumps(installed))
    if args.install_licenses:
        install_licenses(args.install_licenses.resolve())
        print(json.dumps({"licenses": str(args.install_licenses.resolve())}))
    return 0


if __name__ == "__main__":
    sys.exit(main())

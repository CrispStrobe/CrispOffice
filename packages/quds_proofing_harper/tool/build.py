#!/usr/bin/env python3
"""Build and package the optional Harper backend with checked license records."""
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

PACKAGE = Path(__file__).resolve().parents[1]
NATIVE = PACKAGE / "native"


def run(args, **kwargs):
    print(" ".join(str(arg) for arg in args), flush=True)
    subprocess.run(args, cwd=NATIVE, check=True, **kwargs)


def source_hashes() -> dict[str, str]:
    paths = [NATIVE / name for name in ("Cargo.toml", "Cargo.lock", "rust-toolchain.toml")]
    for directory in ("native/src", "lib", "test", "web", "tool", "licenses/upstream"):
        paths.extend(path for path in (PACKAGE / directory).rglob("*")
                     if path.is_file() and "__pycache__" not in path.parts)
    paths.extend((PACKAGE / name) for name in ("LICENSE", "pubspec.yaml"))
    return {path.relative_to(PACKAGE).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(paths)}


def install(output: Path, kind: str, destination: Path) -> dict:
    """Copy one complete, audited backend into a host's explicit asset location."""
    destination = destination.resolve()
    if destination == (output / kind).resolve():
        raise ValueError("Choose a host installation directory separate from the build output")
    destination.mkdir(parents=True, exist_ok=True)
    receipt = json.loads((output / "build-receipt.json").read_text())
    for name in receipt["files"]:
        if name.startswith(kind + "/"):
            path = output / name
            shutil.copyfile(path, destination / path.name)
    for name in ("manifest.json", "notices-and-mpl-sources.tar.gz"):
        target = destination / "licenses" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(output / "licenses" / name, target)
    shutil.copyfile(output / "build-receipt.json", destination / "build-receipt.json")
    return {"kind": kind, "destination": str(destination)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--web", action="store_true")
    parser.add_argument("--output", type=Path, default=PACKAGE / "build")
    parser.add_argument("--install-web", type=Path, help="Copy audited browser files and notices into this host asset directory (requires --web)")
    parser.add_argument("--install-native", type=Path, help="Copy audited library and notices into this host library directory (requires --native)")
    args = parser.parse_args()
    if not args.native and not args.web: parser.error("Select --native, --web, or both")
    if args.install_web and not args.web: parser.error("--install-web requires --web")
    if args.install_native and not args.native: parser.error("--install-native requires --native")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    target_root = Path(os.environ.get("CARGO_TARGET_DIR", NATIVE / "target"))
    if not target_root.is_absolute(): target_root = NATIVE / target_root
    target_root = target_root.resolve()
    compiler = subprocess.check_output(["rustc", "--version", "--verbose"], cwd=NATIVE, text=True)
    host = next(line.split(": ", 1)[1] for line in compiler.splitlines() if line.startswith("host: "))
    targets = []
    binaries = []
    if args.native:
        run(["cargo", "build", "--release", "--locked"])
        name = {"Windows":"quds_proofing_harper.dll", "Darwin":"libquds_proofing_harper.dylib"}.get(platform.system(), "libquds_proofing_harper.so")
        destination = output / "native" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(target_root / "release" / name, destination)
        targets.append(host)
        binaries.append(destination)
    if args.web:
        bindgen = subprocess.check_output(["wasm-bindgen", "--version"], text=True).strip()
        if bindgen != "wasm-bindgen 0.2.130":
            raise SystemExit("Install the locked glue generator: cargo install wasm-bindgen-cli --version 0.2.130 --locked")
        environment = os.environ.copy()
        environment["RUSTFLAGS"] = environment.get("RUSTFLAGS", "") + ' --cfg getrandom_backend="wasm_js"'
        run(["cargo", "build", "--release", "--locked", "--target", "wasm32-unknown-unknown"], env=environment)
        web = output / "web"
        web.mkdir(parents=True, exist_ok=True)
        run(["wasm-bindgen", str(target_root / "wasm32-unknown-unknown" / "release" / "quds_proofing_harper.wasm"),
             "--target", "web", "--out-dir", str(web), "--out-name", "quds_proofing_harper"])
        shutil.copyfile(PACKAGE / "web" / "harper_worker.mjs", web / "harper_worker.mjs")
        targets.append("wasm32-unknown-unknown")
        binaries.extend([web / "quds_proofing_harper_bg.wasm", web / "quds_proofing_harper.js", web / "harper_worker.mjs"])
    license_command = [sys.executable, str(PACKAGE / "tool" / "license_bundle.py"), "--output", str(output / "licenses")]
    for target in targets: license_command.extend(["--target", target])
    run(license_command)
    receipts = [output / "licenses" / name for name in ("manifest.json", "notices-and-mpl-sources.tar.gz")]
    receipt = {"schema_version": 2, "compiler": compiler, "targets": targets,
        "harper_version": "3.2.0", "harper_commit": "ea9ab1b8f95be99a5d4040c53be92a6c2ad7f7f3",
        "cargo_lock_sha256": hashlib.sha256((NATIVE / "Cargo.lock").read_bytes()).hexdigest(),
        "source_sha256": source_hashes(),
        "files": {path.relative_to(output).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in binaries + receipts}}
    (output / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    installed = []
    if args.install_web: installed.append(install(output, "web", args.install_web))
    if args.install_native: installed.append(install(output, "native", args.install_native))
    print(json.dumps({"status": "passed", "output": str(output), "installed": installed}))


if __name__ == "__main__":
    main()

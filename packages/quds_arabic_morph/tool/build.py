#!/usr/bin/env python3
"""Build the optional Arabic morphology backend from pinned sources.

Downloads exactly the CrispEmbed files that make up the native Camel Morph
analyzer (src/arabic_morph.cpp and the header-only helpers it includes, plus
Ryu) from one immutable CrispEmbed commit, admits each file only when its
length and SHA-256 equal the pins below, builds the MIT adapter plus those
sources as a native shared library and/or an Emscripten WebAssembly module,
and writes a receipt that names and hashes every output. The Camel Morph
database (CC BY 4.0 data) is never built into the app; users download it.

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
CRISPEMBED = {
    "repository": "https://github.com/CrispStrobe/CrispEmbed",
    "commit": "3bab324832ea911c2b1260a0d50f0ed898f47950",
    "pull_request": 261,
}
RAW = "https://raw.githubusercontent.com/CrispStrobe/CrispEmbed/{commit}/{path}"
# Every file fetched from CrispEmbed: path -> (SHA-256, bytes). Compiled
# sources and their notices; nothing else of CrispEmbed (no ggml) is used.
SOURCES = {
    "LICENSE": ("a70d0ab5fb2dbab83d1a63071776891e6dfc7ba6e3063b3940c21274c1225a3e", 4739),
    "src/arabic_morph.cpp": ("c1547caf39aab9f74834cba9c782498e876357ba07ec6487d55b928c03f35400", 139469),
    "src/arabic_morph.h": ("cb7239fd6c727fd71d6f52240c380dd0914e6fb52418a7142bb7f8f81bcb0ed7", 11823),
    "src/arabic_morph_tables.h": ("72f9bf25aaaa0aa69b0fccfde2f97e97468c0dc8a523f4e012310d9b3bb5c174", 8028),
    "src/core/env_gate.h": ("2370e31636ea25bc1e5ca63e1e606f4cd3c07c65e0f4d1347b2ec6daf57eaa0e", 3245),
    "src/core/json.h": ("7e72a6359897e9397e5bee3edf7563476fc4bd41516bf5245a16df50dc54c589", 23378),
    "src/core/json_value.h": ("f6af418a13cc5285f977fd29c5644d7fc2cf957f5c4b6d31a3bf0c33243dacf4", 9017),
    "src/core/py_str.h": ("1936161cfea194de155ec58601a0ca7f36577f3c8973231e704a6dc0fcd315e7", 12423),
    "src/core/py_str_tables.h": ("c66cdf3e8b2dc40ee2e09e8dc2411af0ad7a43dedc107ce867d939aa7d55c8e8", 33940),
    "src/core/sha256.h": ("409ab494061b042d4a84698b7bf2caf6dd68f6639cbeb532cb47a2f2337d9a6f", 5024),
    "src/core/shortest_double.c": ("9d4e8d9d2be344ba17d141378274f9a19192b49e6995a9edb1e80f589c1e71c2", 246),
    "src/core/shortest_double.h": ("51f642d86c72d730426338ede6f603697dde1da556d96b53dffec9781416c60c", 282),
    "src/core/third_party/ryu/LICENSE-Apache2": ("c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4", 11357),
    "src/core/third_party/ryu/README.md": ("8ecc8a0aec4481a424349da8267c2cf76733a9b4187a981e8154ea648cd40e5b", 792),
    "src/core/third_party/ryu/common.h": ("0bbd71d26da6193e678d0776cf418f43f287c73d6fd6725353df0aadf70f2a19", 3648),
    "src/core/third_party/ryu/d2s.c": ("d24323c7eb77d63f1e52c415212b50060b776f0883525d907d04954fcd48cf64", 17705),
    "src/core/third_party/ryu/d2s_full_table.h": ("2618f6e5fae6c4443899b184efe3d08295dd267dc9f1a994c983c7caca59ebe6", 34501),
    "src/core/third_party/ryu/d2s_intrinsics.h": ("1d05702f2edacce428223d4b43dd3095c1bd1f3ad30128ce1761d84356dddc7d", 13015),
    "src/core/third_party/ryu/d2s_small_table.h": ("54fec51f1c5eed786a8ce6de881b81582dd71f0812dcd4324b37396617bb0fa9", 7641),
    "src/core/third_party/ryu/digit_table.h": ("8b782573abc0b8554d74163ae6c02f0beb5c30d1e63eaebdb0ddf2c98d817e01", 1745),
    "src/core/third_party/ryu/ryu.h": ("b7feab0ba1df5e9ef3d602f386592ad152491405e49b408fb21c0e0e9e6bfb16", 1360),
    "tools/arabic_morph/THIRD_PARTY_NOTICES": ("6e74d4648626177a13a8b41d45f62af1a6c97b7062e55c38c52c74c28e136e21", 1710),
    "tools/arabic_morph/notices/CPython-LICENSE": ("3b2f81fe21d181c499c59a256c8e1968455d6689d269aa85373bfb6af41da3bf", 13936),
    "tools/arabic_morph/notices/Ryu-LICENSE-Apache2": ("c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4", 11357),
    "tools/arabic_morph/notices/Unicode-LICENSE.txt": ("e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96", 1995),
    "tools/arabic_morph/notices/camel_tools-LICENSE": ("7a3ef160e8957145490ff66591aa9cb8cb08601a2e9fb1673c5fb7af74c727f2", 1087),
}
# Notice files shipped with the binary, as named in licenses/upstream/.
NOTICES = {
    "CrispEmbed-LICENSE": "LICENSE",
    "THIRD_PARTY_NOTICES": "tools/arabic_morph/THIRD_PARTY_NOTICES",
    "camel_tools-LICENSE": "tools/arabic_morph/notices/camel_tools-LICENSE",
    "Ryu-LICENSE-Apache2": "tools/arabic_morph/notices/Ryu-LICENSE-Apache2",
    "Unicode-LICENSE.txt": "tools/arabic_morph/notices/Unicode-LICENSE.txt",
    "CPython-LICENSE": "tools/arabic_morph/notices/CPython-LICENSE",
}
# Attribution of the user-downloaded data (never compiled in), copied from
# the pinned proofing-bin bundle and the pinned context model bundle so hosts
# can show it on their licence page.
DATA_NOTICES = {
    "camel-morph-msa-NOTICE": ("ce2f9c051786a37e4eb72367e6a6c9ea256b702137d4187bb0bfbda38f860efd", 1799),
    "camel-morph-msa-LICENSE": ("214965747a90efe3e5268d367192bb077f1101620662cba71d59d902000b2d94", 442),
    "camel-morph-msa-disambig-NOTICE": ("12f44e5787019e5eb5595663cb7275408d961f430b74d108fa77006235e2638b", 1484),
    "camel-morph-msa-disambig-LICENSE": ("ef2c6367af269181d259bbda4b6167684f85242bb04b28923f91e2861be4c695", 363),
}
LIBRARY = "quds_arabic_morph"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(args, cwd=None):
    print(" ".join(str(a) for a in args), flush=True)
    subprocess.run([str(a) for a in args], cwd=cwd, check=True)


def fetch_source(work: Path) -> Path:
    """Download (or reuse) and verify every pinned file. Returns the tree root."""
    root = work / f"crispembed-{CRISPEMBED['commit'][:12]}"
    for path, (digest, size) in SOURCES.items():
        target = root / path
        if target.exists() and target.stat().st_size == size and sha(target.read_bytes()) == digest:
            continue
        url = RAW.format(commit=CRISPEMBED["commit"], path=path)
        with urllib.request.urlopen(url, timeout=120) as response:  # noqa: S310 (pinned)
            data = response.read(size + 1)
        if len(data) != size or sha(data) != digest:
            raise SystemExit(f"CrispEmbed file does not match its pin: {path}")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    # A tree with anything else in it (stale or planted files) is rebuilt.
    present = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()}
    if present != set(SOURCES):
        raise SystemExit(f"unexpected files in {root}: {sorted(present - set(SOURCES))}")
    return root


def license_bundle(root: Path) -> dict:
    """Copy the upstream notices and write the licence manifest."""
    upstream = LICENSES / "upstream"
    upstream.mkdir(parents=True, exist_ok=True)
    for name, source in NOTICES.items():
        shutil.copyfile(root / source, upstream / name)
    manifest = {
        "schema_version": 1,
        "policy": "MIT adapter and MIT CrispEmbed analyzer (a port of MIT camel_tools); Ryu under the Apache-2.0 "
                  "option of its Apache-2.0/BSL-1.0 dual licence; Unicode/CPython character data under their "
                  "notices. No GPL/LGPL code. The Camel Morph database (CC BY 4.0) and its context model (CC BY-SA "
                  "4.0) are user-downloaded data, never part of the binary.",
        "component": {
            "name": "crispembed-ar-morph", "source": CRISPEMBED["repository"], "commit": CRISPEMBED["commit"],
            "pull_request": CRISPEMBED["pull_request"], "license": "MIT",
            "includes": [
                "camel_tools 1.6.0 (v1.6.0, be79ca9fc493f0df795375a7255bafef246a802d), MIT, ported in arabic_morph.cpp",
                "Ryu (ulfjack/ryu 4c0618b0e44f7ef027ebae05d2cc7812048f7c8f), Apache-2.0 option, unmodified",
                "Unicode 15.0.0 general categories and CPython 3.12 str.isspace tables (generated data)",
            ],
            "files": {path: digest for path, (digest, _) in sorted(SOURCES.items())},
        },
        "notices": {name: sha((upstream / name).read_bytes()) for name in sorted(NOTICES)},
        "data_notices": {
            "bundle": "huggingface.co/cstr/camel-morph-msa-v1.0@d5364e04af7a40b0c9044ed127606e585be15272/proofing-bin",
            "license": "CC-BY-4.0",
            "model_bundle": "huggingface.co/cstr/camel-morph-msa-disambig@07fd9e65200a3ea92a081efa9b0714817178df5f"
                            "/bigram-v1",
            "model_license": "CC-BY-SA-4.0",
            "files": {name: digest for name, (digest, _) in sorted(DATA_NOTICES.items())},
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
    common = ["-S", NATIVE, "-B", build_dir, "-DCMAKE_BUILD_TYPE=Release", f"-DCRISPEMBED_SOURCE_DIR={root}"]
    if kind == "android":
        return mobile_native.build_cmake_android(
            NATIVE, output, LIBRARY, abis, [f"-DCRISPEMBED_SOURCE_DIR={root}"], output, jobs, "Release")
    if kind == "ios":
        return mobile_native.build_cmake_ios(
            NATIVE, output, LIBRARY, [f"-DCRISPEMBED_SOURCE_DIR={root}"], output, jobs, "Release")
    if kind == "native":
        extra = ["-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15"] if platform.system() == "Darwin" else []
        run(["cmake", *common, *extra])
        run(["cmake", "--build", build_dir, "--config", "Release", "--parallel", str(jobs)])
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
    target = output / "web" / "arabic_morph_worker.mjs"
    shutil.copyfile(PACKAGE / "web" / "arabic_morph_worker.mjs", target)
    targets.append(target)
    return targets


def verify_data_notices() -> None:
    for name, (digest, size) in DATA_NOTICES.items():
        data = (LICENSES / "data" / name).read_bytes()
        if len(data) != size or sha(data) != digest:
            raise SystemExit(f"data notice differs from its pin: {name}")


def install_licenses(destination: Path) -> None:
    """Code notices (MIT adapter, CrispEmbed, camel_tools, Ryu, Unicode, CPython), the manifest and the
    CC BY 4.0 attribution of the downloadable data."""
    verify_data_notices()
    destination.mkdir(parents=True, exist_ok=True)
    for path in sorted((LICENSES / "upstream").iterdir()):
        shutil.copyfile(path, destination / path.name)
    for name in DATA_NOTICES:
        shutil.copyfile(LICENSES / "data" / name, destination / name)
    shutil.copyfile(LICENSES / "manifest.json", destination / "manifest.json")
    shutil.copyfile(PACKAGE / "LICENSE", destination / "LICENSE.adapter")


def install(output: Path, kind: str, destination: Path, licenses: bool) -> dict:
    """Copy one built, receipt-verified backend into a host location.

    Only files named and hashed by this build's receipt are copied, never
    stale outputs. With `licenses`, the notices go to
    `<destination>/licenses/arabic_morph/` (web hosts serve them next to the
    worker; native app bundles keep code and notices apart and use
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
        install_licenses(destination / "licenses" / "arabic_morph")
        shutil.copyfile(receipt_path, destination / "licenses" / "arabic_morph" / "build-receipt.json")
    return {"kind": kind, "destination": str(destination), "files": names}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--wasm", action="store_true")
    parser.add_argument("--license-bundle", action="store_true")
    parser.add_argument("--output", type=Path, default=PACKAGE / "build")
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--install-native", type=Path,
                        help="Copy the built library into this host directory (e.g. <App>.app/Contents/Frameworks)")
    parser.add_argument("--install-web", type=Path,
                        help="Copy the worker, module and wasm plus notices into this web asset directory "
                             "(e.g. packages/quds_office_editor/example/web/proofing)")
    mobile_native.add_arguments(parser)
    parser.add_argument("--install-licenses", type=Path,
                        help="Copy the code notices and licence manifest into this directory")
    args = parser.parse_args()
    if args.install_native and not args.native:
        parser.error("--install-native requires --native")
    if args.install_web and not args.wasm:
        parser.error("--install-web requires --wasm")
    mobile_native.check_arguments(parser, args)
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
        if manifest["component"]["commit"] != CRISPEMBED["commit"]:
            raise SystemExit("licence manifest names another CrispEmbed commit; run --license-bundle")
        for path, digest in manifest["component"]["files"].items():
            if sha((root / path).read_bytes()) != digest:
                raise SystemExit(f"compiled source differs from the licence manifest: {path}")
        for name, digest in manifest["notices"].items():
            if sha((LICENSES / "upstream" / name).read_bytes()) != digest:
                raise SystemExit(f"notice differs from the licence manifest: {name}")
        receipt = {"crispembed": CRISPEMBED, "platform": platform.platform(),
                   "adapter_sha256": sha((NATIVE / "src/quds_arabic_morph.cpp").read_bytes()),
                   "license_manifest_sha256": sha((LICENSES / "manifest.json").read_bytes()),
                   "files": {p.relative_to(output).as_posix(): sha(p.read_bytes()) for p in outputs}}
        # Keep receipt entries of earlier builds into the same output that still verify.
        receipt_path = output / "build-receipt.json"
        if receipt_path.exists():
            previous = json.loads(receipt_path.read_text(encoding="utf-8")).get("files", {})
            for name, digest in previous.items():
                if name not in receipt["files"] and (output / name).exists() \
                        and sha((output / name).read_bytes()) == digest:
                    receipt["files"][name] = digest
        receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                encoding="utf-8", newline="\n")
        print(json.dumps(receipt["files"], indent=2))
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

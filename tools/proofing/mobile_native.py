"""Shared iOS/Android build steps for the optional native proofing backends.

Each package's `tool/build.py` imports this module (it lives in the monorepo,
next to the packages). It never downloads anything; it only wraps compiled
shared libraries for the mobile app stores:

* Android: one `lib<name>.so` per ABI (arm64-v8a for devices, x86_64 for the
  emulator), static libc++, `android/<abi>/lib<name>.so` in the build output.
  Hosts copy them to `android/app/src/main/jniLibs/<abi>/`; the app loads them
  with `DynamicLibrary.open('lib<name>.so')`.
* iOS/iPadOS: the App Store forbids loose dylibs, so each library becomes a
  dynamic framework `<name>.framework/<name>` (install name
  `@rpath/<name>.framework/<name>`), one per slice (arm64 device, arm64
  simulator), combined into `ios/<name>.xcframework`. Hosts embed it (Xcode
  "Embed & Sign" or a vendored CocoaPods framework), which signs it with the
  app's identity; the app loads `<name>.framework/<name>`.
"""
from __future__ import annotations

import os
from pathlib import Path
from xml.sax.saxutils import escape
import shutil
import subprocess

ANDROID_ABIS = ("arm64-v8a", "x86_64")
ANDROID_PLATFORM = "android-24"
# slice name -> (SDK, architectures, Info.plist platform). The simulator
# slice is universal: Xcode builds simulator apps for every architecture in
# $ARCHS (arm64 and x86_64 unless the host excludes one) and CocoaPods only
# selects a slice that contains all of them.
IOS_SLICES = {
    "ios-arm64": ("iphoneos", ("arm64",), "iPhoneOS"),
    "ios-arm64_x86_64-simulator": ("iphonesimulator", ("arm64", "x86_64"), "iPhoneSimulator"),
}
IOS_DEPLOYMENT_TARGET = "13.0"


def _run(args, cwd=None, env=None):
    print(" ".join(str(a) for a in args), flush=True)
    subprocess.run([str(a) for a in args], cwd=cwd, env=env, check=True)


def android_ndk() -> Path:
    for key in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"):
        if os.environ.get(key):
            return Path(os.environ[key])
    sdk = Path(os.environ.get("ANDROID_HOME") or Path.home() / "Library/Android/sdk")
    versions = sorted((sdk / "ndk").glob("*"), key=lambda p: [int(x) for x in p.name.split(".") if x.isdigit()])
    if not versions:
        raise SystemExit("Android NDK not found (set ANDROID_NDK_HOME)")
    return versions[-1]


def android_strip(library: Path) -> None:
    """Strip debug info and unneeded symbols (the NDK toolchain compiles with
    -g even in Release), as the Android Gradle plugin would. Doing it here
    makes the receipt name the bytes that ship: hosts may keep the library
    unstripped in the APK (keepDebugSymbols) so its digest stays exact."""
    ndk = android_ndk()
    tools = sorted((ndk / "toolchains/llvm/prebuilt").glob("*/bin/llvm-strip"))
    if not tools:
        raise SystemExit(f"no llvm-strip in {ndk}")
    _run([tools[0], "--strip-unneeded", library])


def android_cmake_args(abi: str) -> list[str]:
    """CMake arguments for one ABI with static libc++ (no libc++_shared.so)."""
    if abi not in ANDROID_ABIS:
        raise SystemExit(f"unsupported Android ABI {abi}; choose from {', '.join(ANDROID_ABIS)}")
    ndk = android_ndk()
    return [f"-DCMAKE_TOOLCHAIN_FILE={ndk / 'build/cmake/android.toolchain.cmake'}",
            f"-DANDROID_ABI={abi}", f"-DANDROID_PLATFORM={ANDROID_PLATFORM}", "-DANDROID_STL=c++_static",
            # 16 KB page alignment (required for new Play uploads since Nov 2025).
            "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384"]


def ios_cmake_args(slice_name: str, arch: str) -> list[str]:
    """One architecture of one slice (multi-architecture slices are built
    per architecture and joined with lipo, so per-arch CMake logic such as
    ggml's CPU feature selection sees exactly one target)."""
    sdk, archs, _ = IOS_SLICES[slice_name]
    if arch not in archs:
        raise SystemExit(f"{arch} is not part of {slice_name}")
    return ["-DCMAKE_SYSTEM_NAME=iOS", f"-DCMAKE_OSX_SYSROOT={sdk}", f"-DCMAKE_OSX_ARCHITECTURES={arch}",
            f"-DCMAKE_SYSTEM_PROCESSOR={'aarch64' if arch == 'arm64' else arch}",
            f"-DCMAKE_OSX_DEPLOYMENT_TARGET={IOS_DEPLOYMENT_TARGET}"]


def ios_slice_archs():
    """(slice, arch) pairs to build, in a stable order."""
    return [(name, arch) for name, (_, archs, _) in IOS_SLICES.items() for arch in archs]


def build_cmake_android(source: Path, build_root: Path, library: str, abis, defines: list[str],
                        output: Path, jobs: int, build_type: str = "Release") -> list[Path]:
    """Build lib<library>.so per ABI into output/android/<abi>/."""
    targets = []
    for abi in abis:
        build_dir = build_root / f"cmake-android-{abi}"
        _run(["cmake", "-S", source, "-B", build_dir, f"-DCMAKE_BUILD_TYPE={build_type}", *defines,
              *android_cmake_args(abi)])
        _run(["cmake", "--build", build_dir, "--parallel", str(jobs)])
        found = [p for p in build_dir.rglob(f"lib{library}.so") if p.is_file()]
        if len(found) != 1:
            raise SystemExit(f"expected one Android library for {abi}, found {found}")
        target = output / "android" / abi / f"lib{library}.so"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(found[0], target)
        android_strip(target)
        targets.append(target)
    return targets


def build_cmake_ios(source: Path, build_root: Path, library: str, defines: list[str], output: Path,
                    jobs: int, build_type: str = "Release", dylib_name: str | None = None) -> list[Path]:
    """Build the shared library for every iOS slice and write
    output/ios/<library>.xcframework. Returns every file inside it."""
    dylibs: dict[str, list[Path]] = {}
    for slice_name, arch in ios_slice_archs():
        build_dir = build_root / f"cmake-{slice_name}-{arch}"
        _run(["cmake", "-S", source, "-B", build_dir, f"-DCMAKE_BUILD_TYPE={build_type}", *defines,
              *ios_cmake_args(slice_name, arch)])
        _run(["cmake", "--build", build_dir, "--parallel", str(jobs)])
        name = dylib_name or f"lib{library}.dylib"
        found = [p for p in build_dir.rglob(name) if p.is_file() and not p.is_symlink()]
        if len(found) != 1:
            raise SystemExit(f"expected one {name} for {slice_name}/{arch}, found {found}")
        dylibs.setdefault(slice_name, []).append(found[0])
    frameworks = [make_framework(paths, library, build_root / "frameworks" / slice_name, slice_name)
                  for slice_name, paths in dylibs.items()]
    return make_xcframework(frameworks, output / "ios" / f"{library}.xcframework")


def bundle_identifier(library: str) -> str:
    return "org.quds.proofing." + library.replace("_", "-")


def make_framework(dylib, library: str, directory: Path, slice_name: str) -> Path:
    """Wrap one dylib (or per-architecture dylibs, joined with lipo) as a
    flat iOS framework with an @rpath install name."""
    _, _, plist_platform = IOS_SLICES[slice_name]
    framework = directory / f"{library}.framework"
    if framework.exists():
        shutil.rmtree(framework)
    framework.mkdir(parents=True)
    binary = framework / library
    dylibs = [dylib] if isinstance(dylib, (str, Path)) else list(dylib)
    if len(dylibs) == 1:
        shutil.copyfile(dylibs[0], binary)
    else:
        _run(["lipo", "-create", *dylibs, "-output", binary])
    os.chmod(binary, 0o755)
    _run(["install_name_tool", "-id", f"@rpath/{library}.framework/{library}", binary])
    info = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": library,
        "CFBundleIdentifier": bundle_identifier(library),
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": library,
        "CFBundlePackageType": "FMWK",
        "CFBundleShortVersionString": "1.0",
        "CFBundleSupportedPlatforms": [plist_platform],
        "CFBundleVersion": "1",
        "MinimumOSVersion": IOS_DEPLOYMENT_TARGET,
    }
    (framework / "Info.plist").write_text(_plist(info), encoding="utf-8")
    # install_name_tool invalidates the linker's signature; the host re-signs
    # with its own identity when embedding, this ad hoc one keeps it loadable.
    _run(["codesign", "--force", "--sign", "-", "--timestamp=none", binary])
    return framework


def _plist(values: dict) -> str:
    """XML property list (plistlib needs pyexpat, missing in some Pythons)."""
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
             '<plist version="1.0">', "<dict>"]
    for key in sorted(values):
        lines.append(f"\t<key>{escape(key)}</key>")
        value = values[key]
        if isinstance(value, list):
            lines.append("\t<array>")
            lines += [f"\t\t<string>{escape(item)}</string>" for item in value]
            lines.append("\t</array>")
        else:
            lines.append(f"\t<string>{escape(value)}</string>")
    return "\n".join(lines + ["</dict>", "</plist>", ""])


def make_xcframework(frameworks: list[Path], output: Path) -> list[Path]:
    if output.exists():
        shutil.rmtree(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    args = ["xcodebuild", "-create-xcframework"]
    for framework in frameworks:
        args += ["-framework", framework]
    _run([*args, "-output", output])
    return sorted(p for p in output.rglob("*") if p.is_file())


def install_android(output: Path, receipt_files: dict, destination: Path, library: str) -> list[str]:
    """Copy receipt-listed android/<abi>/lib<library>.so files into a
    jniLibs root (destination/<abi>/)."""
    names = [n for n in receipt_files if n.startswith("android/") and n.endswith(f"lib{library}.so")]
    if not names:
        raise SystemExit("this build has no Android outputs")
    for name in names:
        parts = Path(name).parts
        if len(parts) != 3:
            raise SystemExit(f"unexpected Android output layout: {name}")
        target = destination / parts[1] / parts[2]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(output / name, target)
    return names


def install_ios(output: Path, receipt_files: dict, destination: Path, library: str) -> list[str]:
    """Copy the receipt-listed xcframework into destination/<library>.xcframework."""
    prefix = f"ios/{library}.xcframework/"
    names = [n for n in receipt_files if n.startswith(prefix)]
    if not names:
        raise SystemExit("this build has no iOS outputs")
    target_root = destination / f"{library}.xcframework"
    if target_root.exists():
        shutil.rmtree(target_root)
    for name in names:
        target = target_root / name[len(prefix):]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(output / name, target)
        if os.access(output / name, os.X_OK):
            os.chmod(target, 0o755)
    return names


def add_arguments(parser) -> None:
    """The shared --android/--ios build and install flags."""
    parser.add_argument("--android", action="store_true",
                        help="Cross-build with the Android NDK (see --android-abi)")
    parser.add_argument("--android-abi", action="append", choices=ANDROID_ABIS, dest="android_abis",
                        help="Android ABI to build; repeatable (default: arm64-v8a and x86_64)")
    parser.add_argument("--ios", action="store_true",
                        help="Build an iOS XCFramework (arm64 device + arm64 simulator dynamic frameworks)")
    parser.add_argument("--install-android", type=Path,
                        help="Copy the Android libraries into a jniLibs root (one <abi>/ directory each). "
                             "A path whose last component is an ABI name receives only that ABI.")
    parser.add_argument("--install-ios", type=Path,
                        help="Copy <name>.xcframework into this host directory (e.g. ios/Frameworks)")


def check_arguments(parser, args) -> None:
    if args.install_android and not args.android:
        parser.error("--install-android requires --android")
    if args.install_ios and not args.ios:
        parser.error("--install-ios requires --ios")
    if args.android_abis and not args.android:
        parser.error("--android-abi requires --android")
    if args.install_android and args.install_android.name in ANDROID_ABIS and args.android_abis \
            and args.install_android.name not in args.android_abis:
        parser.error(f"--install-android {args.install_android.name} directory, but that ABI is not built")


def abis(args) -> tuple[str, ...]:
    return tuple(dict.fromkeys(args.android_abis)) if args.android_abis else ANDROID_ABIS


def verified_receipt_files(output: Path, prefix: str, receipt_name: str = "build-receipt.json") -> dict:
    import hashlib
    import json
    receipt = json.loads((output / receipt_name).read_text(encoding="utf-8"))
    files = {n: d for n, d in receipt["files"].items() if n.startswith(prefix)}
    if not files:
        raise SystemExit(f"this build has no {prefix.rstrip('/')} outputs")
    for name, digest in files.items():
        if hashlib.sha256((output / name).read_bytes()).hexdigest() != digest:
            raise SystemExit(f"changed build artifact: {name}")
    return files


def install_from_arguments(output: Path, args, library: str,
                           receipt_name: str = "build-receipt.json", framework: str | None = None) -> list[dict]:
    """Receipt-verified host copies for --install-android/--install-ios."""
    installed = []
    if args.install_android:
        files = verified_receipt_files(output, "android/", receipt_name)
        destination = args.install_android.resolve()
        if destination.name in ANDROID_ABIS:
            files = {n: d for n, d in files.items() if Path(n).parts[1] == destination.name}
            if not files:
                raise SystemExit(f"this build has no {destination.name} library")
            destination = destination.parent
        installed.append({"kind": "android", "destination": str(destination),
                          "files": install_android(output, files, destination, library)})
    if args.install_ios:
        files = verified_receipt_files(output, "ios/", receipt_name)
        destination = args.install_ios.resolve()
        installed.append({"kind": "ios", "destination": str(destination),
                          "files": install_ios(output, files, destination, framework or library)})
    return installed

#!/usr/bin/env python3
"""Compile the qualification runner once and bind its AOT output to inputs.

The selected source contract matches run_gector_dart.dart::_sources. This tool
does not download dependencies or change source files. Both destinations must
be fresh files outside the source tree and SDK; failed builds retain a receipt
and any partial compiler output. The caller's environment, including TMPDIR,
is inherited unchanged.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urljoin, urlparse


ENTRYPOINT = "tools/proofing/german_model/run_gector_dart.dart"
SOURCE_FILES = (
    "pubspec.yaml",
    "pubspec.lock",
    "packages/quds_proofing_gector/pubspec.yaml",
    "packages/quds_office_engine/lib/src/proofing/german_spelling.dart",
    "packages/quds_office_engine/lib/src/proofing/office_proofing.dart",
    "packages/quds_office_engine/lib/src/proofing/proofing_text_ranges.dart",
    ENTRYPOINT,
    "tools/proofing/german_model/cases.json",
    "tools/proofing/german_model/artifacts.json",
)
SOURCE_DIRECTORIES = (
    "packages/quds_proofing_gector/lib/",
    "packages/quds_office_engine/lib/src/proofing/data/",
    "packages/quds_office_engine/lib/src/opc/zip/",
)


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def file_pin(path: Path) -> dict:
    return {"file": path.name, "bytes": path.stat().st_size, "sha256": digest(path)}


def _dart_files(directory: Path, ancestors=frozenset()):
    # Like Dart's recursive Directory.listSync, follow links but not cycles.
    target = directory.resolve()
    if target in ancestors:
        return
    for entry in directory.iterdir():
        if entry.is_dir():
            yield from _dart_files(entry, ancestors | {target})
        elif entry.is_file() and entry.name.endswith(".dart"):
            yield entry


def source_snapshot(root: Path) -> dict[str, str]:
    paths = set(SOURCE_FILES)
    for directory in SOURCE_DIRECTORIES:
        paths.update(p.relative_to(root).as_posix()
                     for p in _dart_files(root / directory))
    return {name: digest(root / name) for name in sorted(paths)}


def dependency_snapshot(root: Path) -> dict:
    config = root / ".dart_tool/package_config.json"
    data = json.loads(config.read_text(encoding="utf-8"))
    packages = {}
    if data.get("configVersion") != 2:
        raise ValueError("A resolved version-2 package configuration is required.")
    for package in data["packages"]:
        name = package["name"]
        if not re.fullmatch(r"[A-Za-z0-9_]+", name) or name in packages:
            raise ValueError("Package names must be unique Dart package identifiers.")
        root_uri = urljoin(config.as_uri(), package["rootUri"])
        library_uri = urljoin(root_uri.rstrip("/") + "/", package.get("packageUri", ""))
        uri = urlparse(library_uri)
        if uri.scheme != "file" or uri.netloc not in ("", "localhost"):
            raise ValueError("Only resolved local package library directories are supported.")
        library = Path(unquote(uri.path))
        present = library.is_dir()
        files = ({p.relative_to(library).as_posix(): digest(p) for p in _dart_files(library)}
                 if present else {})
        encoded = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
        packages[name] = {"library_directory_present": present, "dart_file_count": len(files),
                          "sha256": hashlib.sha256(encoded).hexdigest()}
    return {"package_config": file_pin(config),
            "packages": dict(sorted(packages.items()))}


def sdk_files(dart: Path) -> dict[str, Path]:
    suffix = ".exe" if dart.name.endswith(".exe") else ""
    files = {
        "dart": dart,
        "dartaotruntime": dart.parent / ("dartaotruntime" + suffix),
        "gen_snapshot": dart.parent / "utils" / ("gen_snapshot" + suffix),
    }
    # Retain the compiler payloads used by current and older Dart SDK layouts.
    for relative in (
        "bin/snapshots/dartdev_aot.dart.snapshot",
        "bin/snapshots/dartdev.dart.snapshot",
        "bin/snapshots/gen_kernel_aot.dart.snapshot",
        "bin/snapshots/gen_kernel.dart.snapshot",
        "bin/dartvm",
        "bin/dartvm.exe",
        "lib/_internal/vm_platform.dill",
        "lib/_internal/vm_platform_product.dill",
        "lib/_internal/vm_platform_strong.dill",
        "version",
    ):
        path = dart.parent.parent / relative
        if path.is_file():
            files[relative] = path
    return files


def public_text(value: str, replacements: dict[Path, str]) -> str:
    for path, label in sorted(replacements.items(), key=lambda x: -len(str(x[0]))):
        value = value.replace("file://" + str(path), label).replace(str(path), label)
    # Diagnostics can also name a package cache or temporary directory.
    return re.sub(r"(?<![\w.>])(?:file://)?(?:[A-Za-z]:[\\/]|/)[^\s'\"<>]*",
                  "<host-path>", value)


def build(dart: Path, source_root: Path, output: Path, receipt: Path) -> int:
    root = source_root.resolve(strict=True)
    dart = dart.resolve(strict=True)
    sdk_root = dart.parent.parent
    if not root.is_dir() or not dart.is_file() or not os.access(dart, os.X_OK):
        raise ValueError("An existing source directory and executable Dart SDK are required.")
    for destination in (output, receipt):
        if os.path.lexists(destination):
            raise ValueError("Refusing to overwrite an existing output or receipt.")
    output, receipt = output.resolve(), receipt.resolve()
    for destination in (output, receipt):
        if destination.is_relative_to(root) or destination.is_relative_to(sdk_root):
            raise ValueError("Build destinations must be outside the source tree and SDK.")
    if output == receipt or output in receipt.parents or receipt in output.parents:
        raise ValueError("Output and receipt must be separate, non-overlapping files.")
    replacements = {root: "<source-root>", sdk_root: "<dart-sdk>",
                    output: "<output>", receipt: "<receipt>"}
    report = {
        "schema_version": 1,
        "kind": "quds-gector-dart-aot-build",
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "completed": False,
        "passed": False,
        "source_stable": False,
        "dependencies_stable": False,
        "sdk_stable": False,
        "stage": "input-admission",
        "dependency_scope": "All .dart files in every resolved package library directory; "
                            "a conservative superset of package compiler inputs.",
        "dependency_digest": "SHA256 of compact sorted JSON mapping library-relative paths "
                             "to their SHA256 digests, encoded as UTF-8.",
        "command": ["<dart>", "compile", "aot-snapshot",
                    "--packages=.dart_tool/package_config.json", ENTRYPOINT,
                    "-o", "<staged-output>"],
    }
    receipt.parent.mkdir(parents=True, exist_ok=True)
    with receipt.open("x", encoding="utf-8") as stream:
        try:
            before = source_snapshot(root)
            dependencies_before = dependency_snapshot(root)
            inputs = sdk_files(dart)
            sdk_before = {name: file_pin(path) for name, path in inputs.items()}
            report.update(source_files=before, sdk_inputs=sdk_before,
                          dependency_inputs=dependencies_before,
                          compiler={"executable": sdk_before["dart"]},
                          source_entrypoint=file_pin(root / ENTRYPOINT))
            report["stage"] = "compile"
            json.dump(report, stream, indent=2)
            stream.flush()
            output.parent.mkdir(parents=True, exist_ok=True)
            staging = Path(tempfile.mkdtemp(prefix=".gector-aot-", dir=output.parent))
            staged_output = staging / output.name
            report["staging_directory"] = staging.name
            replacements[staged_output] = "<staged-output>"
            result = subprocess.run(
                [str(dart), "compile", "aot-snapshot",
                 "--packages=.dart_tool/package_config.json", ENTRYPOINT,
                 "-o", str(staged_output)],
                cwd=root, capture_output=True, shell=False, check=False,
            )
            report["compile"] = {"returncode": result.returncode}
            for name in ("stdout", "stderr"):
                data = getattr(result, name)
                report["compile"][name + "_sha256"] = hashlib.sha256(data).hexdigest()
                report["compile"][name] = public_text(data.decode("utf-8", "replace"), replacements)
            report["stage"] = "verify-output-and-inputs"
            after = source_snapshot(root)
            dependencies_after = dependency_snapshot(root)
            sdk_after = {name: file_pin(path) for name, path in sdk_files(dart).items()}
            report.update(source_files_after=after, source_stable=before == after,
                          dependency_inputs_after=dependencies_after,
                          dependencies_stable=dependencies_before == dependencies_after,
                          sdk_inputs_after=sdk_after, sdk_stable=sdk_before == sdk_after)
            if staged_output.is_file() and not staged_output.is_symlink():
                report["runtime"] = {"executable": sdk_before["dartaotruntime"],
                                     "entrypoint": file_pin(staged_output)}
            if result.returncode != 0:
                raise RuntimeError("Dart compilation failed; compiler diagnostics are retained.")
            if not all(report[key] for key in ("source_stable", "dependencies_stable", "sdk_stable")):
                raise RuntimeError("Source, dependency or SDK inputs changed during compilation.")
            if "runtime" not in report or not staged_output.stat().st_size:
                raise RuntimeError("Compiler did not produce a nonempty regular AOT snapshot.")
            # Same-filesystem hard-link publication is atomic and never replaces
            # a destination which appeared after admission. Failure keeps staging.
            report["stage"] = "publish"
            os.link(staged_output, output)
            staged_output.unlink()
            staging.rmdir()
            del report["staging_directory"]
            report.update(completed=True, passed=True, stage="complete")
        except Exception as error:
            report["error"] = public_text(str(error), replacements)
            report["error_type"] = type(error).__name__
        finally:
            stream.seek(0)
            json.dump(report, stream, indent=2)
            stream.write("\n")
            stream.truncate()
            stream.flush()
    return 0 if report["passed"] else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("dart", "source-root", "output", "receipt"):
        parser.add_argument("--" + name, type=Path, required=True)
    arguments = parser.parse_args()
    try:
        return build(arguments.dart, arguments.source_root, arguments.output, arguments.receipt)
    except (OSError, ValueError) as error:
        print("Build admission failed: " + public_text(str(error), {}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

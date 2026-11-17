#!/usr/bin/env python3
"""Build a bounded recovery candidate; accept only the previously pinned bytes.

This script performs no model inference, qualification, benchmark, GitHub
Actions operation, remote mutation, or trust-pin update. A byte mismatch is a
recorded recovery failure. Outputs remain available for diagnosis.

The tool wheels below are explicit recovery pins, not a claim about the lost
build's unrecorded CMake/Ninja versions. Exact source hashes, semantic compiler
flags, compiler version, and final binary hashes are separate gates.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import time
from urllib.parse import urlparse

CRISP = "853a1ce6089e5d5486e37307f37051ad6a928745"
GGML = "3a27b6c665b191cb230be367db5c52d81dd3e2ac"
BASELINE = "docs/validation/german-gector/2026-11-17-native/native-build-v2.json"
BASELINE_SHA256 = "48996f283c24dbbf57590cf0314f4ec51d7e4076f4e14b9f99172e36f542dddf"
EXPECTED_CC = "cc (Debian 14.2.0-19) 14.2.0"
EXPECTED_CXX = "c++ (Debian 14.2.0-19) 14.2.0"
WHEELS = ("cmake==3.31.6", "ninja==1.11.1.3")


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def utc() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def same_or_child(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def checked_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise ValueError("Use an HTTPS Git URL without embedded credentials.")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quds-root", type=Path, required=True)
    parser.add_argument("--work-root", type=Path, required=True,
                        help="Fresh output directory, outside Quds and existing runtimes.")
    parser.add_argument("--crisp-url", default="https://github.com/CrispStrobe/CrispEmbed.git")
    parser.add_argument("--ggml-url", default="https://github.com/CrispStrobe/ggml.git")
    parser.add_argument("--jobs", type=int, choices=range(1, 5), default=2)
    args = parser.parse_args()
    quds = args.quds_root.resolve(strict=True)
    work = args.work_root.absolute()
    if work.exists() or work.is_symlink():
        raise ValueError("The work root must not exist.")
    if same_or_child(work.resolve(), quds) or same_or_child(quds, work.resolve()):
        raise ValueError("Keep native recovery outputs outside the source checkout.")
    crisp_url = checked_url(args.crisp_url)
    ggml_url = checked_url(args.ggml_url)
    baseline_path = quds / BASELINE
    if baseline_path.stat().st_size != 29775 or sha(baseline_path) != BASELINE_SHA256:
        raise ValueError("The retained native build receipt does not match its production trust pin.")
    baseline = json.loads(baseline_path.read_text())
    if baseline["ggml_revision"] != GGML or baseline["source_revision"] != "85287df43a2a3951b49e4e6865c88231b3c1eeeb":
        raise ValueError("Unexpected retained source provenance.")
    work.mkdir(parents=True)
    work = work.resolve()
    logs = work / "logs"
    logs.mkdir()
    tools = work / "tool-packages"
    source = work / "CrispEmbed"
    build = work / "build"
    receipt_path = work / "native-recovery.json"
    tmp = work / "tmp"
    tmp.mkdir()
    env = dict(os.environ)
    env.update(TMPDIR=str(tmp), PYTHONDONTWRITEBYTECODE="1",
               PIP_DISABLE_PIP_VERSION_CHECK="1", PIP_NO_INPUT="1",
               DASH__SUPPRESS_ANALYTICS="true", CI="true")
    # Avoid unrelated shell compiler flags silently changing this recovery.
    for key in ("CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "CC", "CXX"):
        env.pop(key, None)
    report = {
        "schema": "quds.gector.native-byte-recovery.v1",
        "started_at_utc": utc(), "status": "running", "commands": [],
        "method": "Fresh genuine pinned Git checkouts, pinned recovery tool wheels, retained source/flag checks, then exact binary comparison.",
        "crisp_revision": CRISP, "ggml_revision": GGML,
        "baseline_receipt": BASELINE, "baseline_receipt_sha256": BASELINE_SHA256,
        "tool_wheel_pins": list(WHEELS),
        "tool_pin_scope": "Recovery choices; original CMake/Ninja versions were not captured.",
        "python": sys.version, "platform": platform.platform(),
        "work_root": str(work), "github_actions_used": False,
        "inference_executed": False, "trust_pins_modified": False,
    }

    def save() -> None:
        temporary = receipt_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        temporary.replace(receipt_path)

    def run(label: str, argv: list[str], cwd: Path | None = None,
            timeout: int = 900) -> str:
        sequence = len(report["commands"]) + 1
        log = logs / (f"{sequence:02d}-" + label + ".log")
        row = {"label": label, "argv": argv, "cwd": str(cwd or work),
               "started_at_utc": utc(), "log": str(log.relative_to(work)),
               "status": "running"}
        report["commands"].append(row)
        save()
        print(json.dumps({"starting": label}), flush=True)
        start = time.monotonic()
        try:
            with log.open("wb") as output:
                process = subprocess.run(argv, cwd=cwd or work, env=env,
                                         stdout=output, stderr=subprocess.STDOUT,
                                         timeout=timeout, check=False)
            row.update(exit_code=process.returncode,
                       elapsed_seconds=time.monotonic() - start,
                       status="passed" if process.returncode == 0 else "failed",
                       log_sha256=sha(log), finished_at_utc=utc())
            save()
            if process.returncode:
                raise RuntimeError(f"{label} failed; see {log.name}")
            return log.read_text(errors="replace")
        except BaseException as error:
            row.update(status="failed", error=f"{type(error).__name__}: {error}",
                       elapsed_seconds=time.monotonic() - start,
                       finished_at_utc=utc())
            if log.exists():
                row["log_sha256"] = sha(log)
            save()
            raise

    def checkout(destination: Path, url: str, revision: str,
                 patterns: list[str] | None = None) -> None:
        relative = destination.relative_to(work).as_posix().replace("/", "-")
        destination.mkdir(parents=True)
        run(relative + "-init", ["git", "init", str(destination)])
        git = ["git", "-C", str(destination)]
        run(relative + "-remote", git + ["remote", "add", "origin", url])
        run(relative + "-promisor", git + ["config", "remote.origin.promisor", "true"])
        run(relative + "-filter", git + ["config", "remote.origin.partialclonefilter", "blob:none"])
        run(relative + "-abbrev", git + ["config", "core.abbrev", "7"])
        if patterns:
            run(relative + "-sparse", git + ["sparse-checkout", "set", "--no-cone", *patterns])
        run(relative + "-fetch", git + ["fetch", "--depth=1", "--filter=blob:none", "origin", revision])
        run(relative + "-checkout", git + ["checkout", "--detach", revision])
        actual = run(relative + "-revision", git + ["rev-parse", "HEAD"]).strip()
        if actual != revision:
            raise ValueError("Fetched source revision differs from the fixed pin.")

    def verify_sources() -> dict[str, str]:
        observed = {}
        for relative, expected in sorted(baseline["source_sha256"].items()):
            item = source / relative
            if item.is_symlink() or not item.is_file() or not same_or_child(item.resolve(), source):
                raise ValueError("Missing or unsafe retained source: " + relative)
            observed[relative] = sha(item)
            if observed[relative] != expected:
                raise ValueError("Source differs from retained native build: " + relative)
        return observed

    try:
        save()
        report["compiler_versions"] = {
            "cc": run("cc-version", ["cc", "--version"]).splitlines()[0],
            "cxx": run("cxx-version", ["c++", "--version"]).splitlines()[0],
            "linker": run("linker-version", ["ld", "--version"]).splitlines()[0],
        }
        if report["compiler_versions"]["cc"] != EXPECTED_CC or report["compiler_versions"]["cxx"] != EXPECTED_CXX:
            raise ValueError("The original compiler version is required for this exact-byte recovery attempt.")
        if platform.system() != "Linux" or platform.machine() != "x86_64":
            raise ValueError("The retained native binary targets Linux x86_64.")
        run("install-build-tools", [
            sys.executable, "-m", "pip", "install", "--disable-pip-version-check",
            "--no-input", "--no-cache-dir", "--only-binary=:all:", "--no-deps",
            "--target", str(tools), "--report", str(work / "tool-install.json"), *WHEELS,
        ])
        install = json.loads((work / "tool-install.json").read_text())
        versions = {item["metadata"]["name"].lower(): item["metadata"]["version"]
                    for item in install["install"]}
        if versions != {"cmake": "3.31.6", "ninja": "1.11.1.3"}:
            raise ValueError("Unexpected build tool installation.")
        report["tool_install_report_sha256"] = sha(work / "tool-install.json")
        report["tool_downloads"] = [{
            "name": item["metadata"]["name"], "version": item["metadata"]["version"],
            "download_info": item["download_info"],
        } for item in install["install"]]
        cmake = tools / "cmake/data/bin/cmake"
        ninja = tools / "ninja/data/bin/ninja"
        for tool in (cmake, ninja):
            if not tool.is_file():
                raise ValueError("Expected wheel executable is missing: " + str(tool))
        env["PATH"] = str(cmake.parent) + os.pathsep + str(ninja.parent) + os.pathsep + env.get("PATH", "")
        report["recovery_tools"] = {
            "cmake": {"version": run("cmake-version", [str(cmake), "--version"]).splitlines()[0], "sha256": sha(cmake)},
            "ninja": {"version": run("ninja-version", [str(ninja), "--version"]).strip(), "sha256": sha(ninja)},
        }
        checkout(source, crisp_url, CRISP, [
            "/AGENTS.md", "/CLAUDE.md", "/LICENSE", "/.gitmodules",
            "/src/gector.cpp", "/src/gector.h", "/src/core/",
            "/tools/gector/", "/tools/quantize.cpp", "/tests/test_gector.cpp",
            "/models/convert-gector-onnx-to-gguf.py",
        ])
        # The pinned submodule tree is genuine Git, so GGML_COMMIT is authentic.
        # No parent CMake project or unrelated submodule is initialized.
        checkout(source / "ggml", ggml_url, GGML)
        before = verify_sources()
        report["source_files_before"] = before
        report["source_files_verified"] = len(before)
        save()
        run("configure", [str(cmake), "-S", str(source / "tools/gector"),
                          "-B", str(build), "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release",
                          "-DCMAKE_MAKE_PROGRAM=" + str(ninja)])
        compiled = []
        for item in json.loads((build / "compile_commands.json").read_text()):
            arguments = item.get("arguments") or shlex.split(item["command"])
            compiled.append({
                "file": Path(item["file"]).resolve().relative_to(source).as_posix(),
                "compiler": Path(arguments[0]).name,
                "flags": [arg for arg in arguments
                          if arg.startswith(("-D", "-O", "-m", "-f", "-std="))],
            })
        compiled.sort(key=lambda item: item["file"])
        report["compiled_sources"] = compiled
        report["compiler_flags_match_retained"] = compiled == baseline["compiled_sources"]
        report["compile_commands_sha256"] = sha(build / "compile_commands.json")
        report["cmake_cache_sha256"] = sha(build / "CMakeCache.txt")
        save()
        if not report["compiler_flags_match_retained"]:
            raise ValueError("Generated compile flags/source set differ from the retained build; inspect the receipt.")
        run("compile", [str(cmake), "--build", str(build), "--parallel", str(args.jobs),
                        "--target", "crispembed-gector", "crispembed-gector-quantize"])
        after = verify_sources()
        report["source_files_after"] = after
        report["source_stable"] = before == after
        outputs = {}
        for key, filename in (("library", "libcrispembed-gector.so"),
                              ("quantizer", "crispembed-gector-quantize")):
            path = build / filename
            observed = {"file": filename, "sha256": sha(path), "size_bytes": path.stat().st_size}
            outputs[key] = {**observed, "path": str(path), "expected": baseline[key],
                            "exact_retained_bytes": observed == baseline[key]}
        report["outputs"] = outputs
        report["library_exact"] = outputs["library"]["exact_retained_bytes"]
        report["quantizer_exact"] = outputs["quantizer"]["exact_retained_bytes"]
        # Read-only diagnostics; no candidate library or quantizer is executed.
        for key in ("library", "quantizer"):
            path = Path(outputs[key]["path"])
            data = path.read_bytes()
            strings = sorted(set(match.decode("ascii")
                for match in re.findall(rb"[\x20-\x7e]{8,}", data)
                if b"/ggml/" in match or b"/src/gector" in match or b"/src/core/" in match))
            report.setdefault("embedded_source_path_strings", {})[key] = strings
            run(key + "-elf-notes", ["readelf", "-n", str(path)])
            run(key + "-elf-dynamic", ["readelf", "-d", str(path)])
        if report["library_exact"] and report["quantizer_exact"] and report["source_stable"]:
            report["status"] = "exact-native-bytes-recovered"
            run("install-exact-library", [str(cmake), "--install", str(build),
                                         "--prefix", str(work / "install")])
            result = 0
        else:
            report["status"] = "candidate-differs-from-retained-bytes"
            report["blocked"] = ("Do not use this candidate as the retained library or change trust pins. "
                                 "Original absolute source paths and unrecorded build-tool details may affect bytes.")
            result = 3
        report["finished_at_utc"] = utc()
        save()
        print(json.dumps({"status": report["status"], "receipt": str(receipt_path),
                          "library_exact": report["library_exact"],
                          "quantizer_exact": report["quantizer_exact"]}), flush=True)
        return result
    except BaseException as error:
        report.update(status="failed", error=f"{type(error).__name__}: {error}",
                      finished_at_utc=utc())
        save()
        raise


if __name__ == "__main__":
    raise SystemExit(main())

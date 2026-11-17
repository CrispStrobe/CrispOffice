#!/usr/bin/env python3
"""Reproduce the frozen native binaries using an archived relocation recipe.

This recovery-only helper preserves all production trust pins. The recipe was
already observed in PR144's runtime-recovery archive; success requires both
complete binary hashes, all original source hashes, and the compiler version.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess
import sys
import time

CRISP = "853a1ce6089e5d5486e37307f37051ad6a928745"
GGML = "3a27b6c665b191cb230be367db5c52d81dd3e2ac"
BASELINE = "docs/validation/german-gector/2026-11-17-native/native-build-v2.json"
BASELINE_SHA = "48996f283c24dbbf57590cf0314f4ec51d7e4076f4e14b9f99172e36f542dddf"
HISTORICAL_PREFIX = "/home/agent/.codex/skills/remote-skills/.quds-gector-work/worktrees/CrispEmbed"
TOOLS = ("cmake==4.4.5", "ninja==1.13.2")


def sha(path):
    with Path(path).open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def utc():
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quds-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    quds = args.quds_root.resolve(strict=True)
    out = args.output.absolute()
    if out.exists():
        raise ValueError("Use a fresh output directory; previous evidence is retained.")
    out.mkdir(parents=True)
    logs = out / "logs"
    logs.mkdir()
    tmp = out / "tmp"
    tmp.mkdir()
    source = out / "CrispEmbed"
    build = out / "build"
    report_path = out / "recovery.json"
    baseline_path = quds / BASELINE
    if sha(baseline_path) != BASELINE_SHA:
        raise ValueError("Original native build receipt drifted.")
    baseline = json.loads(baseline_path.read_text())
    env = dict(os.environ)
    env.update(TMPDIR=str(tmp), PYTHONDONTWRITEBYTECODE="1", CI="true",
               DASH__SUPPRESS_ANALYTICS="true", FLUTTER_SUPPRESS_ANALYTICS="true",
               PIP_DISABLE_PIP_VERSION_CHECK="1", PIP_NO_INPUT="1")
    for name in ("CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "CC", "CXX"):
        env.pop(name, None)
    report = {
        "schema": "quds.gector.exact-native-relocation-recovery.v1",
        "started_utc": utc(), "passed": False, "completed": False,
        "source_revision": CRISP, "ggml_revision": GGML,
        "baseline_receipt_sha256": BASELINE_SHA,
        "recipe_source_commit": "e9889e07c983ac15ff002771cf78854d1bc0d572",
        "recipe_archive": "docs/validation/office-reconciled-20261117/resume/evidence/runtime-recovery.tar.xz",
        "scope": "Exact-byte recovery, not a new runtime or model qualification.",
        "production_or_historical_pins_changed": False,
        "github_actions_used": False, "commands": [],
    }

    def save():
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    def run(label, argv, cwd=out, timeout=900):
        log = logs / (f"{len(report['commands']) + 1:02d}-{label}.log")
        row = {"label": label, "argv": list(map(str, argv)), "cwd": str(cwd),
               "started_utc": utc(), "log": str(log.relative_to(out))}
        report["commands"].append(row)
        save()
        print("START", label, flush=True)
        start = time.monotonic()
        with log.open("xb") as handle:
            p = subprocess.run(list(map(str, argv)), cwd=cwd, env=env,
                               stdout=handle, stderr=subprocess.STDOUT, timeout=timeout)
        row.update(exit_code=p.returncode, seconds=time.monotonic() - start,
                   finished_utc=utc(), log_sha256=sha(log))
        save()
        if p.returncode:
            raise RuntimeError(f"{label} failed: {log}")
        return log.read_text(errors="replace")

    def checkout(name, url, revision, patterns=None):
        path = out / name
        path.mkdir(parents=True)
        git = ["git", "-C", path]
        run(name.replace("/", "-") + "-init", git + ["init"])
        run(name.replace("/", "-") + "-remote", git + ["remote", "add", "origin", url])
        run(name.replace("/", "-") + "-abbrev", git + ["config", "core.abbrev", "7"])
        if patterns:
            run("sparse-source", git + ["sparse-checkout", "set", "--no-cone", *patterns])
        run(name.replace("/", "-") + "-fetch", git + ["fetch", "--depth=1", "--filter=blob:none", "origin", revision])
        run(name.replace("/", "-") + "-checkout", git + ["checkout", "--detach", revision])
        if run(name.replace("/", "-") + "-head", git + ["rev-parse", "HEAD"]).strip() != revision:
            raise ValueError("Checkout revision mismatch.")

    def source_inventory():
        observed = {name: sha(source / name) for name in baseline["source_sha256"]}
        if observed != baseline["source_sha256"]:
            raise ValueError("Original native source inventory drifted.")
        return observed

    try:
        report["host"] = {"platform": platform.platform(), "cpu_count": os.cpu_count(),
                          "load_average": list(os.getloadavg()), "python": sys.version}
        cc = run("compiler", ["cc", "--version"]).splitlines()[0]
        cxx = run("cxx", ["c++", "--version"]).splitlines()[0]
        if cc != "cc (Debian 14.2.0-19) 14.2.0" or cxx != "c++ (Debian 14.2.0-19) 14.2.0":
            raise ValueError("Original compiler version is unavailable.")
        report["compiler"] = {"cc": cc, "cxx": cxx}
        venv = out / "venv"
        run("venv", [sys.executable, "-m", "venv", venv])
        run("tool-install", [venv / "bin/python", "-m", "pip", "install", "--no-cache-dir",
                              "--disable-pip-version-check", "--only-binary=:all:",
                              "--report", out / "tool-install.json", *TOOLS])
        env["PATH"] = str(venv / "bin") + os.pathsep + env.get("PATH", "")
        checkout("CrispEmbed", "https://github.com/CrispStrobe/CrispEmbed.git", CRISP,
                 ["/AGENTS.md", "/CLAUDE.md", "/LICENSE", "/.gitmodules", "/src/gector.cpp",
                  "/src/gector.h", "/src/core/", "/tools/gector/", "/tools/quantize.cpp",
                  "/tests/test_gector.cpp", "/models/convert-gector-onnx-to-gguf.py"])
        checkout("CrispEmbed/ggml", "https://github.com/CrispStrobe/ggml.git", GGML)
        report["source_before"] = source_inventory()
        map_flag = f"-ffile-prefix-map={source}={HISTORICAL_PREFIX}"
        run("configure", ["cmake", "-S", source / "tools/gector", "-B", build, "-G", "Ninja",
                          "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_C_FLAGS={map_flag}",
                          f"-DCMAKE_CXX_FLAGS={map_flag}"])
        compiled = []
        for item in json.loads((build / "compile_commands.json").read_text()):
            argv = item.get("arguments") or shlex.split(item["command"])
            compiled.append({"file": Path(item["file"]).resolve().relative_to(source).as_posix(),
                             "compiler": Path(argv[0]).name,
                             "flags": [a for a in argv if a.startswith(("-D", "-O", "-m", "-f", "-std=")) and a != map_flag]})
        compiled.sort(key=lambda x: x["file"])
        report["semantic_compile_flags_match"] = compiled == baseline["compiled_sources"]
        report["declared_additional_flag"] = map_flag
        if not report["semantic_compile_flags_match"]:
            raise ValueError("Compile source or semantic flags changed beyond the exact declared relocation.")
        run("build", ["cmake", "--build", build, "--parallel", "2"])
        report["source_after"] = source_inventory()
        artifacts = {}
        for name, filename in [("library", "libcrispembed-gector.so"), ("quantizer", "crispembed-gector-quantize")]:
            path = build / filename
            pin = {"file": filename, "size_bytes": path.stat().st_size, "sha256": sha(path)}
            artifacts[name] = {**pin, "matches_original": pin == baseline[name]}
        report["artifacts"] = artifacts
        save()
        if not all(v["matches_original"] for v in artifacts.values()):
            raise ValueError("Recovered binaries differ from original bytes; preserve and qualify separately.")
        run("native-contract", ["ctest", "--test-dir", build, "--output-on-failure"])
        run("install", ["cmake", "--install", build, "--prefix", out / "install"])
        report.update(passed=True, completed=True, finished_utc=utc(),
                      all_112_original_source_hashes_match=True, actual_native_contract_passed=True)
        save()
        print(json.dumps({"passed": True, "receipt": str(report_path), "artifacts": artifacts}), flush=True)
    except BaseException as error:
        report.update(error=f"{type(error).__name__}: {error}", finished_utc=utc())
        save()
        raise


if __name__ == "__main__":
    main()

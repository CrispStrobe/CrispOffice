#!/usr/bin/env python3
"""Complete omitted development targets and independently seal a recovery build.

Preserves the failed native-recovery.json and every existing output. Compiles
crispembed-gector-run and test-gector but does not execute either. The new receipt
is a source/build seal, not inference qualification or a trust-pin amendment.
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

CRISP = "853a1ce6089e5d5486e37307f37051ad6a928745"
GGML = "3a27b6c665b191cb230be367db5c52d81dd3e2ac"
RECEIPT = "docs/validation/german-gector/2026-11-17-native/native-build-v2.json"
RECEIPT_SHA = "48996f283c24dbbf57590cf0314f4ec51d7e4076f4e14b9f99172e36f542dddf"
INVENTORY_SHA = "923301782b6d91bc1c55eb3d124b784ac91045af715b1a92996462ddb0ccaddf"


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def timestamp():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def record_file(path):
    return {"file": path.name, "size_bytes": path.stat().st_size, "sha256": digest(path)}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--quds-root", type=Path, required=True)
    p.add_argument("--recovery-root", type=Path, required=True)
    p.add_argument("--output-dir", type=Path, required=True)
    p.add_argument("--jobs", type=int, choices=range(1, 5), default=2)
    args = p.parse_args()
    quds, root = args.quds_root.resolve(strict=True), args.recovery_root.resolve(strict=True)
    out = args.output_dir.absolute()
    if out.exists() or out.is_symlink():
        raise ValueError("Use a fresh output directory; retain earlier attempts.")
    baseline_path = quds / RECEIPT
    if baseline_path.stat().st_size != 29775 or digest(baseline_path) != RECEIPT_SHA:
        raise ValueError("Retained build receipt is not authentic.")
    expected = json.loads(baseline_path.read_text())
    if expected["source_inventory_sha256"] != INVENTORY_SHA:
        raise ValueError("Unexpected retained source inventory.")
    prior_path = root / "native-recovery.json"
    prior_hash = digest(prior_path)
    prior = json.loads(prior_path.read_text())
    source, build, tools = root / "CrispEmbed", root / "build", root / "tool-packages"
    if source == out.resolve() or source in out.resolve().parents:
        raise ValueError("Keep completion evidence outside the native source tree.")
    cmake, ninja = tools / "cmake/data/bin/cmake", tools / "bin/ninja"
    for name, tool in (("cmake", cmake), ("ninja", ninja)):
        if digest(tool) != prior["recovery_tools"][name]["sha256"]:
            raise ValueError("Recovery tool changed since the preserved attempt.")
    out.mkdir(parents=True)
    out = out.resolve()
    (out / "logs").mkdir()
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", DASH__SUPPRESS_ANALYTICS="true", CI="true")
    env["PATH"] = str(cmake.parent) + os.pathsep + str(ninja.parent) + os.pathsep + env.get("PATH", "")
    report = {
        "schema": "quds.gector.native-recovery-completion.v1",
        "started_at_utc": timestamp(), "status": "running", "commands": [],
        "scope": "Compile omitted development units and seal the actual source/build closure; no inference qualification.",
        "prior_attempt": {"path": str(prior_path), "sha256": prior_hash,
                          "status": prior.get("status"), "error": prior.get("error")},
        "expected_source_revision": CRISP, "expected_ggml_revision": GGML,
        "baseline_receipt_sha256": RECEIPT_SHA, "inference_executed": False,
        "native_qualification_passed": False, "trust_pins_modified": False,
        "resources_before": {"load_average": list(os.getloadavg()),
            "disk_bytes": dict(zip(("total", "used", "free"), shutil.disk_usage(root))),
            "meminfo": Path("/proc/meminfo").read_text()},
    }

    def save():
        temporary = out / "completion.tmp"
        temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        temporary.replace(out / "completion.json")

    def run(label, argv):
        logfile = out / "logs" / (label + ".log")
        row = {"label": label, "argv": [str(x) for x in argv],
               "log": str(logfile.relative_to(out)), "started_at_utc": timestamp(),
               "status": "running"}
        report["commands"].append(row)
        save()
        start = time.monotonic()
        print(json.dumps({"starting": label}), flush=True)
        try:
            with logfile.open("wb") as f:
                result = subprocess.run(row["argv"], env=env, cwd=root,
                                        stdout=f, stderr=subprocess.STDOUT, timeout=900)
            row.update(exit_code=result.returncode, elapsed_seconds=time.monotonic()-start,
                       log_sha256=digest(logfile), finished_at_utc=timestamp(),
                       status="passed" if result.returncode == 0 else "failed")
            save()
            if result.returncode:
                raise RuntimeError(label + " failed")
            return logfile.read_text(errors="replace")
        except BaseException as error:
            row.update(status="failed", error=str(error), finished_at_utc=timestamp())
            if logfile.exists():
                row["log_sha256"] = digest(logfile)
            save()
            raise

    def sources():
        found = {}
        for name, wanted in expected["source_sha256"].items():
            path = source / name
            if path.is_symlink() or not path.is_file() or source not in path.resolve().parents:
                raise ValueError("Missing or unsafe native source: " + name)
            found[name] = digest(path)
            if found[name] != wanted:
                raise ValueError("Source drift: " + name)
        return found

    def binaries():
        return {name: record_file(build / filename) for name, filename in (
            ("library", "libcrispembed-gector.so"),
            ("quantizer", "crispembed-gector-quantize"))}

    try:
        save()
        for name, path, revision in (("crisp", source, CRISP), ("ggml", source/"ggml", GGML)):
            actual = run(name+"-revision", ["git", "-C", path, "rev-parse", "HEAD"]).strip()
            if actual != revision:
                raise ValueError("Unexpected " + name + " revision")
        cc = run("cc-version", ["cc", "--version"]).splitlines()[0]
        cxx = run("cxx-version", ["c++", "--version"]).splitlines()[0]
        if cc != "cc (Debian 14.2.0-19) 14.2.0" or cxx != "c++ (Debian 14.2.0-19) 14.2.0":
            raise ValueError("Compiler changed from the original build identity.")
        before = sources()
        before_binaries = binaries()
        report.update(source_files_before=before, binaries_before=before_binaries)
        save()
        run("compile-omitted-development-targets", [cmake, "--build", build, "--parallel",
            str(args.jobs), "--target", "crispembed-gector-run", "test-gector"])
        after = sources()
        after_binaries = binaries()
        report.update(source_files_after=after, binaries_after=after_binaries,
                      source_stable=before == after, binaries_unchanged=before_binaries == after_binaries)
        if before != after or before_binaries != after_binaries:
            raise ValueError("Existing native source or candidate bytes changed during closure completion.")
        compiled = []
        for item in json.loads((build/"compile_commands.json").read_text()):
            arguments = item.get("arguments") or shlex.split(item["command"])
            compiled.append({"file": Path(item["file"]).resolve().relative_to(source).as_posix(),
                "compiler": Path(arguments[0]).name,
                "flags": [x for x in arguments if x.startswith(("-D", "-O", "-m", "-f", "-std="))]})
        compiled.sort(key=lambda x: x["file"])
        report["compiled_sources"] = compiled
        if compiled != expected["compiled_sources"]:
            raise ValueError("Compiled source/flag contract differs from the retained build.")
        dependencies = run("ninja-dependencies", [ninja, "-C", build, "-t", "deps"])
        paths = {(source/x["file"]).resolve() for x in compiled}
        for line in dependencies.splitlines():
            if not line.startswith("    "):
                continue
            path = Path(line.strip())
            if not path.is_absolute():
                path = build/path
            if path.is_file() and source in path.resolve().parents:
                paths.add(path.resolve())
        paths.update((source/"ggml").rglob("CMakeLists.txt"))
        paths.update((source/"ggml/cmake").rglob("*.cmake"))
        paths.update(source/x for x in ("tools/gector/CMakeLists.txt", "LICENSE", "ggml/LICENSE"))
        inventory = {path.relative_to(source).as_posix(): digest(path) for path in sorted(paths)}
        comparison = {
            "missing": sorted(set(expected["source_sha256"])-set(inventory)),
            "unexpected": sorted(set(inventory)-set(expected["source_sha256"])),
            "hash_mismatches": sorted(n for n in set(inventory)&set(expected["source_sha256"])
                                     if inventory[n] != expected["source_sha256"][n]),
        }
        report.update(actual_dependency_inventory=inventory, dependency_inventory_comparison=comparison)
        save()
        if inventory != expected["source_sha256"]:
            raise ValueError("Actual source/dependency closure still differs; retain this failure.")
        inventory_hash = hashlib.sha256(json.dumps(inventory, sort_keys=True).encode()).hexdigest()
        if inventory_hash != INVENTORY_SHA:
            raise ValueError("Retained source inventory digest changed.")
        cache = {}
        for line in (build/"CMakeCache.txt").read_text().splitlines():
            match = re.match(r"([^/#][^:]*):[^=]*=(.*)", line)
            if match:
                cache[match[1]] = match[2]
        flags = {k:v for k,v in cache.items()
                 if (k.startswith(("GGML_", "CRISPEMBED_")) and v in ("ON", "OFF"))
                 or k in ("CMAKE_BUILD_TYPE", "CMAKE_CXX_STANDARD")}
        if flags != expected["cmake_flags"]:
            raise ValueError("Native CMake switches differ from retained settings.")
        seal = {
            "schema": "quds.gector.native-build.v1", "source_revision": CRISP,
            "ggml_revision": GGML, "portable": True, "cmake_flags": flags,
            "compiled_sources": compiled, "source_sha256": inventory,
            "source_inventory_sha256": inventory_hash,
            "compile_commands_sha256": digest(build/"compile_commands.json"),
            "cmake_cache_sha256": digest(build/"CMakeCache.txt"),
            "library": after_binaries["library"], "quantizer": after_binaries["quantizer"],
            "build_provenance_limit": "Current recovery build seal; not inference qualification or a trust-pin update.",
        }
        seal_path = out/"candidate-build.json"
        with seal_path.open("x") as f:
            f.write(json.dumps(seal, indent=2, sort_keys=True)+"\n")
        report["candidate_build_receipt"] = {"path":str(seal_path), "sha256":digest(seal_path)}
        report["original_binary_pins_match"] = {name: after_binaries[name] == expected[name]
                                               for name in ("library", "quantizer")}
        report["embedded_source_paths"] = {}
        for name, filename in (("library", "libcrispembed-gector.so"), ("quantizer", "crispembed-gector-quantize")):
            path = build/filename
            report["embedded_source_paths"][name] = sorted(set(m.decode("ascii")
                for m in re.findall(rb"[\x20-\x7e]{8,}", path.read_bytes())
                if b"/ggml/" in m or b"/src/gector" in m or b"/src/core/" in m))
            run(name+"-elf-notes", ["readelf", "-n", path])
            run(name+"-elf-dynamic", ["readelf", "-d", path])
        if digest(prior_path) != prior_hash:
            raise ValueError("The preserved initial attempt was modified.")
        report.update(status="candidate-source-build-sealed",
                      source_closure_passed=True, prior_attempt_preserved=True,
                      finished_at_utc=timestamp())
        save()
        print(json.dumps({"status":report["status"], "receipt":str(out/"completion.json"),
                          "candidate_build_receipt":str(seal_path),
                          "original_binary_pins_match":report["original_binary_pins_match"]}), flush=True)
        return 0
    except BaseException as error:
        report.update(status="failed", error=f"{type(error).__name__}: {error}",
                      finished_at_utc=timestamp())
        save()
        raise


if __name__ == "__main__":
    raise SystemExit(main())

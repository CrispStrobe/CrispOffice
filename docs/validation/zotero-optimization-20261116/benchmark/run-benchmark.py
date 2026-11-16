#!/usr/bin/env python3
"""Reproduce the isolated native Zotero session comparison without CI."""

import argparse
import copy
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tarfile
from urllib.parse import unquote, urljoin, urlparse


HERE = Path(__file__).resolve().parent
ENGINE_LIB = "packages/quds_office_engine/lib"
TARGET = "src/word/model/word_zotero_citing.dart"
BASELINE_REF = "428679a33381f943a8ae63117d4207f01dd15462"
OPTIMIZED_REF = "91c725feb5517db3c5f686e80662e2cb4f77f0d4"
METRICS = (
    "initialization_us",
    "get_fields_us",
    "assert_unchanged_us",
    "select_fields_five_passes_us",
)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def manifest(root):
    return {
        path.relative_to(root).as_posix(): sha256(path)
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])


def extract_engine(repo, ref, destination):
    archive = git(repo, "archive", "--format=tar", ref, ENGINE_LIB)
    prefix = ENGINE_LIB + "/"
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as tar:
        for member in tar.getmembers():
            if member.isdir():
                continue
            if not member.isfile() or not member.name.startswith(prefix):
                raise ValueError(f"Unexpected engine archive member: {member.name}")
            relative = Path(member.name[len(prefix):])
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError("Unsafe engine archive path")
            path = destination / "lib" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            source = tar.extractfile(member)
            if source is None:
                raise ValueError("Missing engine archive content")
            path.write_bytes(source.read())


def resolved_package_root(config_path, entry):
    uri = urljoin(config_path.as_uri(), entry["rootUri"])
    parsed = urlparse(uri)
    if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
        raise ValueError(f"The resolved package must be local: {entry['name']}")
    return Path(unquote(parsed.path)).resolve()


def checked_config(harness):
    proof = json.loads((HERE / "source-provenance.json").read_text())
    for name in ("pubspec.yaml", "pubspec.lock"):
        expected = proof["engine_harness_input_sha256"][name]
        if sha256(harness / name) != expected:
            raise ValueError(f"Engine harness {name} differs from the recorded input")
    config_path = harness / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text())
    packages = {entry["name"]: entry for entry in config["packages"]}
    if "quds_office_engine" not in packages or "legacy_doc_parser" not in packages:
        raise ValueError("Engine and legacy parser must exist in the resolved graph")
    for entry in config["packages"]:
        root = resolved_package_root(config_path, entry)
        library = root / entry.get("packageUri", "")
        if not library.is_dir():
            raise ValueError(f"Resolved dependency is unavailable: {entry['name']}")
        entry["rootUri"] = root.as_uri() + "/"
    parser = packages["legacy_doc_parser"]
    parser_root = resolved_package_root(config_path, parser)
    expected_parser = json.loads((HERE / "legacy-parser-lib-sha256.json").read_text())
    if manifest(parser_root / parser.get("packageUri", "")) != expected_parser:
        raise ValueError("The local legacy parser source differs from the recorded input")
    return config, proof


def summarize(baseline, optimized, source):
    if baseline["runtime"] != optimized["runtime"]:
        raise ValueError("The two benchmark processes used different Dart runtimes")
    if len(baseline["results"]) != len(optimized["results"]):
        raise ValueError("The benchmark scenarios differ")
    results = []
    for before, after in zip(baseline["results"], optimized["results"]):
        if (before["field_count"], before["note_count"]) != (
            after["field_count"], after["note_count"]
        ):
            raise ValueError("The benchmark scenario sizes differ")
        if len(before["wire_snapshot_sha256"]) != 1 or (
            before["wire_snapshot_sha256"] != after["wire_snapshot_sha256"]
        ):
            raise ValueError("Native field protocol snapshots are not identical")
        result = {
            "fields": before["field_count"],
            "notes": before["note_count"],
            "identical_wire_sha256": after["wire_snapshot_sha256"][0],
        }
        for name in METRICS:
            old = statistics.median(before[name])
            new = statistics.median(after[name])
            result[name] = {
                "baseline_median": old,
                "optimized_median": new,
                "speedup": round(old / new, 2) if new else None,
            }
        results.append(result)
    return {
        "source": source,
        "method": baseline["method"],
        "runtime": optimized["runtime"],
        "results": results,
        "scope": "Synthetic engine-only local JIT microbenchmark. Not application or live Zotero latency; no timing threshold is a regression gate.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--engine-harness", required=True, type=Path)
    parser.add_argument("--dart", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path,
                        help="New scratch directory; an existing path is refused")
    parser.add_argument("--prepare-only", action="store_true",
                        help="Verify inputs and materialize sources/configs without timing runs")
    args = parser.parse_args()
    repo = args.repo.resolve()
    harness = args.engine_harness.resolve()
    dart = args.dart.resolve()
    output = args.output.resolve()
    if not dart.is_file():
        raise ValueError("Provide an installed Dart SDK executable")
    config, proof = checked_config(harness)
    baseline_ref = git(repo, "rev-parse", BASELINE_REF).decode().strip()
    optimized_ref = git(repo, "rev-parse", OPTIMIZED_REF).decode().strip()
    if sha256(HERE / "native-benchmark.dart") != proof["fixture_sha256"]:
        raise ValueError("The benchmark fixture differs from the recorded source")
    output.mkdir(parents=True, exist_ok=False)
    optimized_package = output / "optimized-package"
    baseline_package = output / "baseline-package"
    extract_engine(repo, optimized_ref, optimized_package)
    shutil.copytree(optimized_package, baseline_package)
    (baseline_package / "lib" / TARGET).write_bytes(
        git(repo, "show", f"{baseline_ref}:{ENGINE_LIB}/{TARGET}")
    )
    libraries = {
        "baseline": manifest(baseline_package / "lib"),
        "optimized": manifest(optimized_package / "lib"),
    }
    if libraries != json.loads((HERE / "engine-lib-sha256.json").read_text()):
        raise ValueError("The materialized sources differ from the recorded source manifests")
    write_json(output / "engine-lib-sha256.json", libraries)
    source = {
        "prepared_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "baseline_target_file_ref": baseline_ref,
        "optimized_common_source_ref": optimized_ref,
        "target_file": f"{ENGINE_LIB}/{TARGET}",
        "baseline_target_sha256": libraries["baseline"][TARGET],
        "optimized_target_sha256": libraries["optimized"][TARGET],
        "engine_lib_manifest_sha256": sha256(output / "engine-lib-sha256.json"),
        "fixture_sha256": sha256(HERE / "native-benchmark.dart"),
        "harness_lock_sha256": sha256(harness / "pubspec.lock"),
        "only_differing_engine_lib_file": TARGET,
        "comparison": "Common optimized engine source with only the baseline native-session target file substituted; not two full historical repository trees.",
    }
    write_json(output / "source-provenance.json", source)
    for label, package in (("baseline", baseline_package), ("optimized", optimized_package)):
        isolated_config = copy.deepcopy(config)
        for entry in isolated_config["packages"]:
            if entry["name"] == "quds_office_engine":
                entry["rootUri"] = package.as_uri() + "/"
        write_json(output / f"{label}-package-config.json", isolated_config)
    if args.prepare_only:
        print(f"Verified recorded sources and dependency inputs in {output}")
        return
    environment = dict(os.environ, CI="true", DART_SUPPRESS_ANALYTICS="true")
    for label in ("baseline", "optimized"):
        with (output / f"{label}.json").open("w") as stdout, (
            output / f"{label}.stderr.log"
        ).open("w") as stderr:
            subprocess.run(
                [str(dart), f"--packages={output / (label + '-package-config.json')}",
                 str(HERE / "native-benchmark.dart"), label],
                cwd=output, env=environment, stdout=stdout, stderr=stderr,
                timeout=180, check=True,
            )
    summary = summarize(
        json.loads((output / "baseline.json").read_text()),
        json.loads((output / "optimized.json").read_text()),
        source,
    )
    write_json(output / "summary.json", summary)
    print(f"Completed comparison with identical protocol snapshots: {output / 'summary.json'}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Run the three provider modes serially from one sealed local AOT build.

Requires the verified GECTOR_TEST_MODEL/LIBRARY and corresponding SHA256
environment variables, FLUTTER_ROOT, and an explicit original F32 reference.
Run only after local tests and compiler activity have finished. Every output
path must be fresh; failed reports and console logs are preserved.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    args = parser.parse_args()
    root = args.repo.resolve(strict=True)
    build_dir = args.build_dir.resolve(strict=True)
    args.out.mkdir(parents=True, exist_ok=False)
    build = json.loads((build_dir / "provider-build.json").read_text())
    if not build.get("passed"):
        raise ValueError("A successful sealed provider build is required.")
    spec = importlib.util.spec_from_file_location(
        "aot_build", root / "tools/proofing/german_model/build_gector_aot.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    sdk = Path(os.environ["FLUTTER_ROOT"]) / "bin/cache/dart-sdk/bin"
    model = Path(os.environ["GECTOR_TEST_MODEL"])
    executable = build_dir / "provider.aot"
    before = module.dependency_snapshot(root)
    if before != build["dependency_inputs"]:
        raise ValueError("Resolved dependencies differ from the sealed build.")
    if module.source_snapshot(root) != build["source_files"]:
        raise ValueError("Selected sources differ from the sealed build.")
    if sha(executable) != build["runtime"]["entrypoint"]["sha256"]:
        raise ValueError("AOT bytes differ from the sealed build.")
    receipt = {
        "kind": "quds-serial-provider-modes", "started_utc": now(),
        "source_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "build_receipt_sha256": sha(build_dir / "provider-build.json"),
        "reference_sha256": sha(args.reference),
        "mode_order": ["single", "segmented", "reuse"],
        "runs": [], "passed": False,
    }
    receipt_path = args.out / "serial-receipt.json"
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    common = [
        str(sdk / "dartaotruntime"), str(executable),
        "--source-root", str(root), "--bundle-dir", str(model.parent),
        "--model", str(model), "--model-sha256", os.environ["GECTOR_TEST_MODEL_SHA256"],
        "--library", os.environ["GECTOR_TEST_LIBRARY"],
        "--library-sha256", os.environ["GECTOR_TEST_LIBRARY_SHA256"],
        "--reference", str(args.reference),
    ]
    modes = [
        ("single", []),
        ("segmented", ["--segment-target-tokens", "64", "--reuse-identical-inputs", "false"]),
        ("reuse", ["--segment-target-tokens", "64", "--reuse-identical-inputs", "true"]),
    ]
    for name, extra in modes:
        output = args.out / f"{name}.json"
        log = args.out / f"{name}.log"
        row = {"mode": name, "started_utc": now()}
        command = common + extra + ["--output", str(output)]
        row["command"] = command
        with log.open("x") as stream:
            result = subprocess.run(
                command, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                env={**os.environ, "CRISPEMBED_GECTOR": "1"}, timeout=600)
        row.update(completed_utc=now(), exit_code=result.returncode,
                   log_sha256=sha(log), receipt_sha256=sha(output) if output.is_file() else None)
        report = json.loads(output.read_text()) if output.is_file() else {}
        row["source_map_matches_build"] = report.get("source_files") == build["source_files"]
        row["runtime_matches_build"] = all(
            report.get("runtime", {}).get(key, {}).get("sha256") == build["runtime"][key]["sha256"]
            for key in ("executable", "entrypoint"))
        row["source_stable"] = report.get("source_stable") is True
        row["all_requested_checks_passed"] = report.get("all_requested_checks_passed") is True
        comparison = args.out / f"{name}-comparison.json"
        comparison_log = args.out / f"{name}-comparison.log"
        with comparison_log.open("x") as stream:
            checked = subprocess.run(
                [sys.executable, str(root / "tools/proofing/german_model/compare_guarded_provider.py"),
                 "--candidate", str(output), "--output", str(comparison)],
                cwd=root, stdout=stream, stderr=subprocess.STDOUT, timeout=60)
        row["comparison_exit_code"] = checked.returncode
        row["passed"] = result.returncode == checked.returncode == 0 and all(
            row[key] for key in ("source_map_matches_build", "runtime_matches_build",
                                "source_stable", "all_requested_checks_passed"))
        receipt["runs"].append(row)
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps({"mode": name, "passed": row["passed"], "completed_utc": row["completed_utc"]}), flush=True)
    receipt["dependencies_stable"] = module.dependency_snapshot(root) == before
    receipt["completed_utc"] = now()
    receipt["passed"] = receipt["dependencies_stable"] and all(row["passed"] for row in receipt["runs"])
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    return 0 if receipt["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

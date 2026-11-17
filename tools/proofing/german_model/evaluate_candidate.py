#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run a hash-pinned publisher reference without changing the application pin.

Supply a reviewed artifact manifest and already downloaded bundle. This tool
never downloads anything. Publisher quickstart code is executed only after all
listed files, including that code, match their reviewed size and SHA-256.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import resource
import sys
import time


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as source:
        for part in iter(lambda: source.read(1024 * 1024), b""):
            h.update(part)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--model-dir", required=True, type=Path)
    parser.add_argument("--cases", required=True, type=Path, action="append")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Preserve existing evidence; choose a new output path")
    manifest = json.loads(args.manifest.read_text())
    artifacts = manifest["files"] if isinstance(manifest, dict) else manifest
    names = [a["file"] for a in artifacts]
    if len(set(names)) != len(names) or not {"model.onnx", "quickstart.py", "LICENSE", "NOTICE"} <= set(names):
        raise ValueError("Incomplete or duplicate artifact manifest")
    for a in artifacts:
        name = a["file"]
        if Path(name).name != name or name in {".", ".."}:
            raise ValueError("Unsafe artifact path")
        p = args.model_dir / name
        if p.is_symlink() or p.stat().st_size != a["size"] or digest(p) != a["sha256"]:
            raise ValueError(f"Changed reviewed artifact: {name}")
    # Keep the publisher decoder unchanged; only bound native CPU resources.
    import onnxruntime as ort
    native_session = ort.InferenceSession

    def bounded_session(*session_args, **kwargs):
        options = ort.SessionOptions()
        options.intra_op_num_threads = 2
        options.inter_op_num_threads = 1
        options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        options.enable_cpu_mem_arena = False
        options.enable_mem_pattern = False
        kwargs["sess_options"] = options
        return native_session(*session_args, **kwargs)

    ort.InferenceSession = bounded_session
    runner = args.model_dir / "quickstart.py"
    spec = importlib.util.spec_from_file_location("pinned_publisher_reference", runner)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    begin = time.perf_counter()
    model = module.Gector(model=str(args.model_dir.resolve()))
    startup = time.perf_counter() - begin
    suites = []
    for source in args.cases:
        rows = []
        for c in json.loads(source.read_text()):
            begin = time.perf_counter()
            text, suggestions = model.correct(c["input"])
            rows.append({**c, "output": text, "suggestions": suggestions,
                         "milliseconds": (time.perf_counter() - begin) * 1000,
                         "exact": text == c.get("expected", c["input"])})
        errors = [r for r in rows if r["kind"] == "error"]
        clean = [r for r in rows if r["kind"] == "clean"]
        summary = {"errors": len(errors), "exact_errors": sum(r["exact"] for r in errors),
                   "clean": len(clean), "clean_changed": sum(r["input"] != r["output"] for r in clean)}
        suites.append({"cases_file": source.name, "cases_sha256": digest(source),
                       "summary": summary, "cases": rows})
        print(source.name, json.dumps(summary), flush=True)
    report = {"scope": "Evaluation-only unmodified publisher quickstart, including any publisher language rules; no Quds or published app guards. Not an enabled app provider.",
              "timestamp_utc": datetime.now(timezone.utc).isoformat(),
              "application_enabled": False, "evaluator_sha256": digest(Path(__file__)),
              "manifest_sha256": digest(args.manifest),
              "artifacts": artifacts, "runner_sha256": digest(runner),
              "runtime": {"python": sys.version, "platform": platform.platform(),
                          "onnxruntime": ort.__version__, "cpu_threads": 2},
              "startup_seconds": startup,
              "max_rss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * (1 if sys.platform == "darwin" else 1024),
              "suites": suites}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()

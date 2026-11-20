#!/usr/bin/env python3
"""Run the eight comparator controls without invoking Word or a native corpus."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest


def record(path):
    data = Path(path).read_bytes()
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "git_blob_sha1": hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    git = lambda *a: subprocess.check_output(["git", "-C", str(repo), *a]).decode().strip()
    assert git("rev-parse", "HEAD") == args.expected_head
    args.output.mkdir(parents=True, exist_ok=False)
    paths = ["packages/quds_office_engine/tool/fidelity/" + name for name in
             ["word_native_layout.py", "test_word_native_layout.py"]]
    before = {path: record(repo / path) for path in paths}
    for path in paths:
        assert before[path]["git_blob_sha1"] == git("rev-parse", "HEAD:" + path)
    import PIL
    pil_root = Path(PIL.__file__).parent
    runtime_paths = [Path(sys.executable).resolve()] + sorted(
        p for p in pil_root.rglob("*") if p.is_file() and "__pycache__" not in p.parts
    )
    runtime_before = {str(path): record(path) for path in runtime_paths}
    started = datetime.now(timezone.utc).isoformat()
    spec = importlib.util.spec_from_file_location("captured_word_comparator_tests", repo / paths[1])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    suite = unittest.defaultTestLoader.loadTestsFromModule(module)
    names = [case.id() for group in suite for case in group]
    assert len(names) == len(set(names)) == 8
    log = io.StringIO()
    result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite)
    (args.output / "unittest.log").write_text(log.getvalue())
    after = {path: record(repo / path) for path in paths}
    runtime_after = {str(path): record(path) for path in runtime_paths}
    assert before == after and runtime_before == runtime_after
    assert git("rev-parse", "HEAD") == args.expected_head
    accepted = result.wasSuccessful() and result.testsRun == 8 and not result.skipped
    receipt = {"status": "passed" if accepted else "failed", "source": args.expected_head,
               "started_at_utc": started, "finished_at_utc": datetime.now(timezone.utc).isoformat(),
               "tests_run": result.testsRun, "case_ids": names, "failures": len(result.failures),
               "errors": len(result.errors), "skipped": len(result.skipped),
               "source_before": before, "source_after": after, "source_matches_git": True,
               "runtime_before": runtime_before, "runtime_after": runtime_after,
               "python": sys.version, "pillow_version": PIL.__version__,
               "runner": record(__file__), "log": record(args.output / "unittest.log"),
               "scope": "Synthetic metric and corpus-validation unit controls only; no native Word export, reference replacement, or real corpus comparison."}
    (args.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"status": receipt["status"], "controls": result.testsRun}))
    return 0 if accepted else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Reproduce two existing embedding failures on the pre-GUI editor library."""

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile


OUTPUT = Path(__file__).resolve().parent
PARENT = OUTPUT.parent
spec = importlib.util.spec_from_file_location("layout_qualification", PARENT / "qualify.py")
qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)
qualification.OUTPUT = OUTPUT
ROOT = qualification.ROOT
WORKSPACE = qualification.WORKSPACE
BASE = subprocess.check_output(["git", "rev-parse", "c3eaf57c"], cwd=ROOT, text=True).strip()
FROZEN = ROOT.parent / "baseline-editor-lib-c3eaf57c"
LINK = WORKSPACE / "packages/quds_office_editor/lib"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def snapshot():
    current = qualification.snapshot()
    result = {key: value for key, value in current.items()
              if not key.startswith("repository/packages/quds_office_editor/lib/")}
    for path in FROZEN.rglob("*"):
        if path.is_file():
            result["baseline-editor-lib/" + str(path.relative_to(FROZEN))] = sha(path.read_bytes())
    return dict(sorted(result.items()))


def main():
    archive = subprocess.check_output(
        ["git", "archive", f"{BASE}:packages/quds_office_editor/lib"], cwd=ROOT)
    FROZEN.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(FROZEN, filter="data")
    original = os.readlink(LINK)
    if LINK.resolve() != ROOT / "packages/quds_office_editor/lib":
        raise RuntimeError("Unexpected editor library link target")
    LINK.unlink()
    LINK.symlink_to(FROZEN, target_is_directory=True)
    try:
        before = snapshot()
        qualification.write_json("inputs-before.json", before)
        test_path = "packages/quds_office_editor/test/embed_test.dart"
        current_test_hash = sha((ROOT / test_path).read_bytes())
        historical_test_hash = sha(subprocess.check_output(
            ["git", "show", f"{BASE}:{test_path}"], cwd=ROOT))
        qualification.write_json("source-frontier.json", {
            "baseline_commit": BASE, "editor_lib_from_git_archive": True,
            "frozen_editor_directory": str(FROZEN),
            "original_editor_link": original,
            "current_fixture_sha256": current_test_hash,
            "baseline_fixture_sha256": historical_test_hash,
            "fixture_is_identical_to_baseline": current_test_hash == historical_test_hash,
        })
        command = qualification.execute("baseline-embed-tests", [
            str(qualification.FLUTTER), "--no-version-check", "--suppress-analytics",
            "test", "--no-pub", "--concurrency=1", "--reporter=json",
            "test/embed_test.dart", "--name",
            "word editor tab key inserts a tab|QudsOfficeHost embeds a word editor with custom chrome",
        ], WORKSPACE / "packages/quds_office_editor")
        summary = qualification.summarize("baseline-embed-tests")
        after = snapshot()
        qualification.write_json("inputs-after.json", after)
        changed = sorted(key for key in before.keys() | after.keys()
                         if before.get(key) != after.get(key))
        raw = (OUTPUT / "baseline-embed-tests.stdout.log").read_text()
        proof = {
            "command": command,
            "baseline_failure_reproduced": command["exit_code"] == 1
                and summary["failed"] == 2 and "No Overlay widget found" in raw,
            "input_count": len(before), "input_changes": changed,
            "fixture_identical_to_baseline": current_test_hash == historical_test_hash,
            "summary": {key: value for key, value in summary.items() if key != "tests"},
        }
        qualification.write_json("receipt.json", proof)
        print(json.dumps({"baseline_failure_reproduced": proof["baseline_failure_reproduced"],
                          "failed": summary["failed"], "input_changes": changed}), flush=True)
        if not proof["baseline_failure_reproduced"] or changed:
            raise SystemExit(1)
    finally:
        LINK.unlink()
        LINK.symlink_to(original, target_is_directory=True)


if __name__ == "__main__":
    main()

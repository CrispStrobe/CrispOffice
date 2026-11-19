#!/usr/bin/env python3
"""Run the two offline control groups against a clean, committed source."""
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


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True).strip())
    output = args.output.resolve()
    if output == repo or repo in output.parents:
        parser.error("Write evidence outside the source checkout")
    if output.exists() and any(output.iterdir()):
        parser.error("Preserve previous attempts; select an empty output directory")

    def git(*values: str) -> str:
        return subprocess.check_output(
            ["git", "--no-replace-objects", "-C", str(repo), *values], text=True).strip()

    def clean() -> bool:
        return not git("status", "--porcelain=v1", "--untracked-files=no")

    head = git("rev-parse", "--verify", args.head + "^{commit}")
    if git("rev-parse", "HEAD") != head or not clean():
        parser.error("HEAD, tracked worktree and index must match the committed source")
    index_tree = git("write-tree")
    source_names = sorted({
        str(Path(__file__).resolve().relative_to(repo)), "tools/mail/check_store.py",
        "tools/mail/check_reader.py",
        "packages/quds_proofing_hunspell/tool/build.py",
        "packages/quds_proofing_hunspell/tool/test_build.py",
        "packages/quds_proofing_hunspell/LICENSE",
        *git("ls-files", "tools/proofing/ayaspell/*.py").splitlines(),
        *git("ls-files", "packages/quds_proofing_hunspell/licenses").splitlines(),
    })
    tracked = set(git("ls-files").splitlines())
    if not set(source_names) <= tracked:
        parser.error("Commit the complete control driver and its source inputs")
    for directory in ("tools/proofing/ayaspell", "packages/quds_proofing_hunspell/tool"):
        discovered = {str(path.relative_to(repo)) for path in (repo / directory).glob("*.py")}
        if not discovered <= tracked:
            parser.error("Untracked Python sources in a control discovery directory")
    python = Path(sys.executable).resolve()
    before = {name: {"git_blob": git("rev-parse", head + ":" + name),
                     "sha256": sha(repo / name)} for name in source_names}
    runtime_before = {"python_executable": str(python), "sha256": sha(python),
                      "version": sys.version}
    output.mkdir(parents=True, exist_ok=True)
    record = {"source_commit": head, "source_tree": index_tree,
              "started_at_utc": datetime.now(timezone.utc).isoformat(),
              "source_before": before, "runtime_before": runtime_before,
              "github_actions_queried_or_awaited": False, "runs": []}

    def save() -> None:
        (output / "verification.json").write_text(json.dumps(record, indent=2) + "\n")

    sys.path.insert(0, str(repo / "tools/mail"))
    from check_store import execute

    save()
    try:
        for name, directory, pattern in (
            ("bundle-controls", "tools/proofing/ayaspell", "test_build_bundle*.py"),
            ("packaging-controls", "packages/quds_proofing_hunspell/tool", "test_build.py"),
        ):
            command = [str(python), "-B", "-m", "unittest", "discover", "-s",
                       directory, "-p", pattern, "-v"]
            path = output / (name + ".log")
            with path.open("wb") as log:
                code = execute(command, cwd=repo, env=dict(os.environ), stdout=log, timeout=120)
            raw = path.read_text()
            identities = re.findall(r"^test\S+ \(([^\n]+)\) \.\.\. ok$", raw, re.MULTILINE)
            counts = re.findall(r"^Ran (\d+) tests? in [\d.]+s$", raw, re.MULTILINE)
            accepted = (code == 0 and len(counts) == 1 and int(counts[0]) > 0
                        and len(identities) == int(counts[0])
                        and len(set(identities)) == len(identities)
                        and raw.rstrip().endswith("\nOK"))
            record["runs"].append({"name": name, "command": command, "cwd": str(repo),
                                   "exit_code": code, "log": path.name,
                                   "log_sha256": sha(path), "case_ids": identities,
                                   "passed": len(identities), "accepted": accepted})
            save()
    except BaseException as error:
        record["runner_error"] = repr(error)
    finally:
        after = {name: {"git_blob": git("rev-parse", head + ":" + name),
                        "sha256": sha(repo / name)} for name in source_names}
        runtime_after = {"python_executable": str(python), "sha256": sha(python),
                         "version": sys.version}
        record.update(source_after=after, runtime_after=runtime_after,
                      source_unchanged=before == after, runtime_unchanged=runtime_before == runtime_after,
                      source_head_unchanged=git("rev-parse", "HEAD") == head,
                      source_index_unchanged=git("write-tree") == index_tree,
                      tracked_worktree_clean_after=clean(),
                      finished_at_utc=datetime.now(timezone.utc).isoformat())
        record["success"] = (not record.get("runner_error") and len(record["runs"]) == 2
                             and all(row["accepted"] for row in record["runs"])
                             and all(record[key] for key in ("source_unchanged", "runtime_unchanged",
                                     "source_head_unchanged", "source_index_unchanged",
                                     "tracked_worktree_clean_after")))
        record["passed"] = sum(row["passed"] for row in record["runs"])
        save()
    print(json.dumps({key: record[key] for key in ("source_commit", "success", "passed")}))
    return 0 if record["success"] else 1


if __name__ == "__main__":
    sys.exit(main())

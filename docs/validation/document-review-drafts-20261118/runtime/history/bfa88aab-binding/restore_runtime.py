#!/usr/bin/env python3
"""Restore the recorded final Linux test runtime into a fresh directory.

Prepared after the recorded run. This adapter was syntax-checked but not executed
as part of the acceptance run. It reuses the exact archived bootstrap, substituting
explicit locations and the final Mail-aware workspace lock. Requires Python 3.12+
and PyYAML. It downloads only the official SDK and hash-pinned public Pub archives.
"""
import argparse
import gzip
import hashlib
from pathlib import Path
import subprocess

SOURCE_COMMIT = "bfa88aab88a74028285619dfa07f3a81868fe59b"
SOURCE_TREE = "3418afd634efcaaa14c4712103f69ae5e817bffd"
FINAL_LOCK_SHA256 = "43261dbd4acce9c423c8f19f5c86841a9f05aff3b3b968c94a7b48f94c9f8239"
BOOTSTRAP_SHA256 = "a4522dae18494605646330bb1d099344166c80c9f54252c97889549692a9754e"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path,
                        help="Checkout of the recorded source commit (or identical tree).")
    parser.add_argument("--runtime-root", required=True, type=Path,
                        help="Fresh directory for SDK, cache, receipts, and wrappers.")
    args = parser.parse_args()
    evidence = Path(__file__).resolve().parent
    repo = args.repo.resolve()
    runtime = args.runtime_root.resolve()
    if runtime == repo or repo in runtime.parents or runtime in repo.parents:
        raise RuntimeError("The runtime directory and checkout must be separate.")
    if runtime.exists() and any(runtime.iterdir()):
        raise RuntimeError("Runtime destination must be empty; existing evidence will not be overwritten.")
    source_tree = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "HEAD^{tree}"], text=True).strip()
    if source_tree != SOURCE_TREE:
        raise RuntimeError("Checkout must have the tree of " + SOURCE_COMMIT)
    if subprocess.check_output(["git", "-C", str(repo), "diff", "--name-only", "HEAD"], text=True).strip():
        raise RuntimeError("Checkout has tracked changes; use a clean checkout.")
    lock = evidence / "workspace-pubspec.lock"
    if hashlib.sha256(lock.read_bytes()).hexdigest() != FINAL_LOCK_SHA256:
        raise RuntimeError("Saved final workspace lock hash differs.")
    original = gzip.decompress((evidence / "scripts/bootstrap_runtime.py.gz").read_bytes())
    if hashlib.sha256(original).hexdigest() != BOOTSTRAP_SHA256:
        raise RuntimeError("Archived bootstrap hash differs.")
    text = original.decode("utf-8")
    replacements = [
        ("ROOT=Path('/workspace/scratch/4a0b7fce84dc/toolchains')", "ROOT=Path(" + repr(str(runtime)) + ")", 1),
        ("REPO=ROOT.parent/'quds_office_suite'", "REPO=Path(" + repr(str(repo)) + ")", 1),
        ("REPO/'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'", "Path(" + repr(str(lock)) + ")", 2),
        ("344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130", FINAL_LOCK_SHA256, 1),
    ]
    for old, new, expected_count in replacements:
        if text.count(old) != expected_count:
            raise RuntimeError("Archived bootstrap structure differs: " + old)
        text = text.replace(old, new)
    exec(compile(text, str(evidence / "scripts/bootstrap_runtime.py.gz"), "exec"), {"__name__": "__main__"})


if __name__ == "__main__":
    main()

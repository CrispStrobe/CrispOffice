#!/usr/bin/env python3
"""Launch one hash-pinned Chromium with an evidence-local profile and cache."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import sys


def main() -> None:
    config_path = Path(os.environ["QUDS_CHROMIUM_LAUNCH_CONFIG"])
    config = json.loads(config_path.read_text())
    binary = Path(config["binary"])
    hasher = hashlib.sha256()
    with binary.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    if hasher.hexdigest() != config["binary_sha256"]:
        raise RuntimeError("Pinned Chromium binary changed before launch")
    original = sys.argv[1:]
    args = []
    skip_value = False
    for arg in original:
        if skip_value:
            skip_value = False
            continue
        if arg in ("--user-data-dir", "--disk-cache-dir"):
            skip_value = True
            continue
        if arg.startswith(("--user-data-dir=", "--disk-cache-dir=")):
            continue
        args.append(arg)
    args = [f"--user-data-dir={config['profile']}",
            f"--disk-cache-dir={config['disk_cache']}", *args]
    # The pinned Flutter SDK's headless launcher supplies --no-sandbox itself.
    # Preserve and record that flag; do not silently add any browser flags.
    entry = {"binary": str(binary), "binary_sha256": hasher.hexdigest(),
             "original_arguments": original, "executed_arguments": args,
             "no_sandbox_from_sdk": "--no-sandbox" in original,
             "profile": config["profile"], "disk_cache": config["disk_cache"]}
    with Path(config["launch_log"]).open("a") as stream:
        stream.write(json.dumps(entry, sort_keys=True) + "\n")
    os.execv(str(binary), [str(binary), *args])


if __name__ == "__main__":
    main()

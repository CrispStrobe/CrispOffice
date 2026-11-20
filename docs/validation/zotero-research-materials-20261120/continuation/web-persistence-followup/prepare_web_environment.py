#!/usr/bin/env python3
"""Read local runtime files and write adapter pins; never launch Flutter/Chrome."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from web_runner_support import (HERE, PRIMARY, PRIMARY_SHA256, chromium_inventory,
                                git, record, write_json)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--chromium", type=Path, default=Path("/usr/lib/chromium/chromium"))
    args = parser.parse_args()
    sdk = args.sdk.resolve()
    now = datetime.now(timezone.utc).isoformat()
    inventory = chromium_inventory(args.chromium)
    write_json(HERE / "chromium-baseline.json", {
        "prepared_at_utc": now, "binary": inventory["binary"], "inventory": inventory,
        "purpose": "Explicit local browser/runtime pin for future source-bound qualification",
        "browser_launched": False, "tests_started": False,
    })
    source_names = ["packages/flutter_tools/lib/src/commands/test.dart",
                    "packages/flutter_tools/lib/src/test/flutter_web_platform.dart",
                    "packages/flutter_tools/lib/src/web/chrome.dart"]
    test_source = (sdk / source_names[0]).read_text()
    chrome_source = (sdk / source_names[2]).read_text()
    support = {
        "prepared_at_utc": now, "source_head_at_preparation": git(args.repo.resolve(), "rev-parse", "HEAD"),
        "sdk": str(sdk), "sdk_version": json.loads((sdk / "bin/cache/flutter.version.json").read_text()),
        "inspected_local_sdk_sources": {name: record(sdk / name) for name in source_names},
        "supported_arguments": {
            "platform_chrome": "['tester', 'chrome']" in test_source,
            "reporter_json": "'json': 'A machine-readable format." in test_source,
            "file_reporter": "'file-reporter'" in test_source,
            "concurrency": "'concurrency'" in test_source,
        },
        "chrome_backend_is_deprecated_but_supported_by_pinned_sdk": True,
        "sdk_headless_launcher_supplies_no_sandbox": "['--no-sandbox', '--headless', '--window-size=2400,1800']" in chrome_source,
        "chromium_wrapper": "chromium_wrapper.py records and preserves SDK flags, pins the ELF, and isolates generated profile/cache locations",
        "primary_runner": {"path": str(PRIMARY), **record(PRIMARY)},
        "primary_runner_pin_matches": record(PRIMARY)["sha256"] == PRIMARY_SHA256,
        "flutter_or_browser_command_executed": False, "tests_started": False,
        "source_manifests_or_runtime_caches_modified": False,
    }
    assert all(support["supported_arguments"].values())
    assert support["sdk_headless_launcher_supplies_no_sandbox"] and support["primary_runner_pin_matches"]
    write_json(HERE / "runner-support.json", support)
    print(json.dumps({"adapter_pins_ready": True, "browser_files": len(inventory["files"]),
                      "browser_sha256": inventory["binary_sha256"], "tests_started": False}))


if __name__ == "__main__":
    main()

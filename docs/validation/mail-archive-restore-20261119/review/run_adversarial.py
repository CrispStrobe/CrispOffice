#!/usr/bin/env python3
"""Run the independent restore probes and bind their actual logs to sources."""

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
from datetime import datetime, timezone
from urllib.parse import unquote, urljoin, urlparse


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def utc():
    return datetime.now(timezone.utc).isoformat()


output = pathlib.Path(__file__).resolve().parent
root = output.parents[3]
package = root / "packages/quds_mail_store"
test = "test/archive_restore_adversarial_test.dart"
package_config = root / ".dart_tool/package_config.json"
configuration = json.loads(package_config.read_text())
test_package = next(item for item in configuration["packages"] if item["name"] == "test")
test_entrypoint = pathlib.Path(
    unquote(urlparse(urljoin(package_config.as_uri(), test_package["rootUri"])).path)
) / "bin/test.dart"
sources = sorted(
    [
        *root.glob("packages/quds_mail_core/lib/**/*.dart"),
        *root.glob("packages/quds_mail_store/lib/**/*.dart"),
        package / test,
        root / "pubspec.yaml",
        root / "pubspec.lock",
        package / "pubspec.yaml",
        pathlib.Path(__file__).resolve(),
    ]
)


def snapshot():
    return {str(path.relative_to(root)): digest(path) for path in sources}


started = utc()
before = snapshot()
commands = [
    ("format", ["dart", "format", "--output=none", "--set-exit-if-changed", test]),
    ("analysis", ["dart", "analyze", "--fatal-infos", "--fatal-warnings", test]),
    (
        "tests",
        [
            "dart",
            "--disable-dart-dev",
            "--packages=" + str(package_config),
            str(test_entrypoint),
            "--platform=vm",
            "--compiler=kernel",
            "--reporter=json",
            "--concurrency=1",
            test,
        ],
    ),
]
results = []
for name, command in commands:
    out = output / (name + ".stdout.log")
    err = output / (name + ".stderr.log")
    with out.open("wb") as stdout, err.open("wb") as stderr:
        process = subprocess.run(command, cwd=package, stdout=stdout, stderr=stderr)
    results.append(
        {
            "name": name,
            "command": command,
            "cwd": "packages/quds_mail_store",
            "exit_code": process.returncode,
            "logs": [
                {"path": str(path.name), "sha256": digest(path), "bytes": path.stat().st_size}
                for path in (out, err)
            ],
        }
    )

after = snapshot()
identities = output / "source-identities.json"
identities.write_text(json.dumps({"before": before, "after": after}, indent=2) + "\n")
names = {}
cases = []
done = None
for line in (output / "tests.stdout.log").read_text().splitlines():
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if event.get("type") == "testStart":
        names[event["test"]["id"]] = event["test"]["name"]
    if event.get("type") == "testDone" and not event.get("hidden", False):
        cases.append(
            {
                "id": event["testID"],
                "name": names.get(event["testID"]),
                "result": event["result"],
                "skipped": event.get("skipped", False),
            }
        )
    if event.get("type") == "done":
        done = event

counts = {
    "passed": sum(case["result"] == "success" and not case["skipped"] for case in cases),
    "failed": sum(case["result"] != "success" and not case["skipped"] for case in cases),
    "skipped": sum(case["skipped"] for case in cases),
}
version = subprocess.run(["dart", "--version"], capture_output=True, text=True)
dart = pathlib.Path(shutil.which("dart")).resolve()
dart_binary = dart
if dart.read_bytes()[:2] == b"#!" and os.environ.get("FLUTTER_ROOT"):
    dart_binary = pathlib.Path(os.environ["FLUTTER_ROOT"]) / "bin/cache/dart-sdk/bin/dart"
receipt = {
    "started_at_utc": started,
    "finished_at_utc": utc(),
    "scope": "Independent adversarial manifest restore cases only; source inspection is recorded separately.",
    "runtime": {
        "dart_version": (version.stdout + version.stderr).strip(),
        "dart_launcher_sha256": digest(dart),
        "dart_binary_sha256": digest(dart_binary),
        "package_config_sha256": digest(package_config),
        "test_entrypoint_sha256": digest(test_entrypoint),
        "sqlite": "Default package native asset; no temporary override supplied by this harness.",
    },
    "commands": results,
    "counts": counts,
    "cases": cases,
    "runner_done": done,
    "source_binding": {
        "manifest": identities.name,
        "manifest_sha256": digest(identities),
        "source_files": len(before),
        "before_after_equal": before == after,
        "changed_paths": [key for key in before if before[key] != after[key]],
        "scope": "All mail core and store Dart library files, executed test, root manifest/lockfile, store manifest and this harness. Dependency and full SDK qualification belongs to the root acceptance receipt.",
    },
}
accepted = (
    all(result["exit_code"] == 0 for result in results)
    and before == after
    and counts["passed"] > 0
    and counts["failed"] == 0
    and counts["skipped"] == 0
    and done is not None
    and done.get("success") is True
)
receipt["accepted"] = accepted
(output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps({"accepted": accepted, "counts": counts, "source_files": len(before)}))
raise SystemExit(0 if accepted else 1)

"""Run one source-bound acceptance cohort with the installed real SDK.

Set FLUTTER_ROOT, PUB_CACHE and writable runtime/TMPDIR locations first.
Usage: python run_acceptance.py engine --output-dir /path/to/acceptance
The engine/editor/incoming cohorts are separate, nonoverlapping test imports.
"""

import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import time

from audit_results import count, sha256


ROOT = Path(__file__).resolve().parents[3]


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sources():
    paths = subprocess.check_output(
        ["git", "ls-files", "-z", "--", "packages", "pubspec.yaml",
         "pubspec.lock", "analysis_options.yaml", "dart_test.yaml"], cwd=ROOT,
    ).decode().split("\0")
    # Prose edits after qualification do not alter executable inputs. The runner
    # and auditor live under docs, but they are executable inputs and are sealed
    # explicitly below alongside the generated dependency resolution.
    result = {p: sha256(ROOT / p) for p in sorted(set(paths))
              if p and not p.endswith(".md") and (ROOT / p).is_file()}
    for path in (ROOT / ".dart_tool/package_config.json", Path(__file__).resolve(),
                 Path(__file__).resolve().with_name("audit_results.py")):
        result[str(path.relative_to(ROOT))] = sha256(path)
    return result


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suite", choices=("engine", "editor", "incoming"))
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    sdk = Path(os.environ["FLUTTER_ROOT"])
    dart = sdk / "bin/cache/dart-sdk/bin/dart"
    package = "editor" if args.suite == "editor" else "engine"
    cwd = ROOT / "packages" / ("quds_office_" + package)
    target = "incoming_word_acceptance.dart" if args.suite == "incoming" else "vertical_table_acceptance.dart"
    if args.suite == "editor":
        command = [str(dart), str(sdk / "bin/cache/flutter_tools.snapshot"),
                   "test", "--no-pub", "--reporter=json", "--concurrency=1"]
    else:
        command = [str(dart), "--packages=" + str(ROOT / ".dart_tool/package_config.json"),
                   str(Path(os.environ["PUB_CACHE"]) / "hosted/pub.dev/test-1.31.1/bin/test.dart"),
                   "--reporter=json", "--concurrency=1"]
    command.append("tool/zotero/" + target)
    before = sources()
    before_path = output / (args.suite + "-sources-before.json")
    write(before_path, before)
    log_path = output / (args.suite + ".jsonl")
    stderr_path = log_path.with_suffix(".stderr")
    receipt = {"command": command, "cwd": str(cwd),
               "head": git("rev-parse", "HEAD"), "tree": git("rev-parse", "HEAD^{tree}"),
               "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "source_count": len(before), "source_manifest_sha256": sha256(before_path),
               "pubspec_lock_sha256": sha256(ROOT / "pubspec.lock"),
               "dart_version": subprocess.check_output([str(dart), "--version"], text=True, stderr=subprocess.STDOUT).strip(),
               "flutter_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=sdk, text=True).strip()}
    start = time.monotonic()
    with log_path.open("w") as log, stderr_path.open("w") as stderr:
        result = subprocess.run(command, cwd=cwd, stdout=log, stderr=stderr, check=False)
    after = sources()
    write(output / (args.suite + "-sources-after.json"), after)
    receipt.update(exit_code=result.returncode, seconds=round(time.monotonic() - start, 3),
                   source_stable=before == after, log_sha256=sha256(log_path),
                   stderr_sha256=sha256(stderr_path))
    try:
        receipt["acceptance"] = count(log_path)
    except (AssertionError, KeyError, ValueError) as error:
        receipt["audit_error"] = str(error)
    write(output / (args.suite + "-receipt.json"), receipt)
    print(json.dumps({k: v for k, v in receipt.items() if k != "acceptance"}, indent=2))
    if "acceptance" in receipt:
        print(json.dumps({k: receipt["acceptance"][k] for k in ("passed", "skipped", "failed", "errors")}, indent=2))
    raise SystemExit(0 if result.returncode == 0 and before == after and "acceptance" in receipt else 1)


if __name__ == "__main__":
    main()

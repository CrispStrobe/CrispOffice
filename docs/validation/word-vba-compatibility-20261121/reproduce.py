#!/usr/bin/env python3
"""Replay the local gates with real Dart dependencies and unchanged source.

Use --bootstrap with a fresh runtime and dependency-unresolved checkout, or
point --runtime at an existing runtime created by the recorded setup script.
All generated logs and binaries go to --output, outside the source checkout.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--repo", type=Path, required=True)
parser.add_argument("--runtime", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--bootstrap", action="store_true")
parser.add_argument("--cohort", choices=["compiler", "native", "feature", "mail", "final"], default="final")
parser.add_argument("--node", default=shutil.which("node"))
args = parser.parse_args()
repo, runtime, output = (p.resolve() for p in (args.repo, args.runtime, args.output))
record_dir = Path(__file__).resolve().parent
if args.bootstrap:
    subprocess.run([
        "python3", str(repo / "docs/validation/word-vba-unit-conversions-20261120/reproduce_runtime.py"),
        "--repo", str(repo), "--runtime", str(runtime),
        "--record", str(record_dir / "runtime-environment.json"),
    ], check=True)
output.mkdir(parents=True, exist_ok=False)
engine = repo / "packages/quds_office_engine"
dart = runtime / "dart-sdk/bin/dart"
package_config = repo / ".dart_tool/package_config.json"
config = json.loads(package_config.read_text())
mail = {
    "name": "quds_mail_core", "rootUri": (repo / "packages/quds_mail_core").as_uri(),
    "packageUri": "lib/", "languageVersion": "3.12",
}
config["packages"] = [p for p in config["packages"] if p["name"] != mail["name"]] + [mail]
write(package_config, config)
environment = os.environ.copy()
environment.update({
    "PUB_CACHE": str(runtime / "pub-cache"), "TMPDIR": str(runtime / "tmp"),
    "XDG_CONFIG_HOME": str(runtime / "config"), "XDG_CACHE_HOME": str(runtime / "cache"),
    "DART_SUPPRESS_ANALYTICS": "true", "QUDS_VALIDATION_ROOT": str(repo),
    "QUDS_DART_ROOT": str(runtime / "dart-sdk"),
    "PATH": str(dart.parent) + os.pathsep + environment.get("PATH", ""),
})


def inputs():
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=repo).decode().split("\0")
    prefixes = ("packages/quds_office_engine/", "packages/legacy_doc_parser/", "packages/quds_mail_core/")
    return {
        name: sha(repo / name) for name in tracked
        if name and ((name.startswith(prefixes) and not name.endswith("CHANGELOG.md"))
                     or name in ["pubspec.yaml", "pubspec.lock", "analysis_options.yaml"])
    }


def tests_summary(path):
    tests, completed, errors, done = {}, {}, [], None
    for line in path.read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        kind = event.get("type")
        if kind == "testStart":
            tests[event["test"]["id"]] = event["test"]
        elif kind == "testDone":
            completed[event["testID"]] = event
        elif kind == "error":
            errors.append(event)
        elif kind == "done":
            done = event
    visible = [v for v in completed.values() if not v.get("hidden")]
    return {
        "visible_passed": sum(v.get("result") == "success" and not v.get("skipped") for v in visible),
        "visible_failed": sum(v.get("result") != "success" and not v.get("skipped") for v in visible),
        "visible_skipped": sum(bool(v.get("skipped")) for v in visible),
        "errors": errors, "done": done,
    }


results = []


def run(label, command, cwd=engine, tests=False):
    before = inputs()
    write(output / f"{label}.inputs-before.json", before)
    write(output / f"{label}.command.json", {"command": command, "cwd": str(cwd)})
    started = time.monotonic()
    stdout, stderr = output / f"{label}.stdout", output / f"{label}.stderr"
    with stdout.open("w") as out, stderr.open("w") as err:
        process = subprocess.run(command, cwd=cwd, env=environment, stdout=out, stderr=err)
    after = inputs()
    write(output / f"{label}.inputs-after.json", after)
    result = {
        "label": label, "exit_code": process.returncode,
        "seconds": round(time.monotonic() - started, 3), "input_count": len(before),
        "changed_inputs": sorted(p for p in before.keys() | after.keys() if before.get(p) != after.get(p)),
        "stdout_sha256": sha(stdout), "stderr_sha256": sha(stderr),
    }
    if tests:
        result.update(tests_summary(stdout))
    results.append(result)
    write(output / f"{label}.result.json", result)
    write(output / "results.json", results)
    print(json.dumps(result), flush=True)
    if process.returncode or result["changed_inputs"]:
        raise SystemExit(f"Rejected {label}: command failure or changed source inputs")
    if tests and (result["visible_failed"] or result["visible_skipped"] or result["errors"]
                  or not result["done"] or result["done"].get("success") is not True):
        raise SystemExit(f"Rejected {label}: test errors, skips, or missing successful completion")


compiler = sorted(p for p in engine.glob("test/office_vba*_test.dart")
                  if "integration" not in p.name and "cli" not in p.name)
native = sorted({*engine.glob("test/office_macro*_test.dart"),
                 *engine.glob("test/office_vba*integration_test.dart"),
                 *engine.glob("test/office_vba*cli_test.dart"),
                 engine / "test/word_step_atomicity_test.dart"})
feature = [engine / "test" / name for name in [
    "office_vba_word_headers_footers_test.dart", "office_macro_word_headers_footers_test.dart",
    "office_vba_word_headers_footers_integration_test.dart",
]]
if args.cohort in ["compiler", "native", "feature", "final"]:
    selected = {"compiler": compiler, "native": native, "feature": feature, "final": native}[args.cohort]
    relative = [str(p.relative_to(engine)) for p in selected]
    write(output / "selected-tests.json", relative)
    run(args.cohort + "-tests", [str(runtime / "run-engine-tests.sh"), *relative, "--reporter", "json"], tests=True)
if args.cohort == "mail":
    run("mail-tests", [str(dart), "--old_gen_heap_size=768", f"--packages={package_config}",
                       str(runtime / "test-runner/test-runner.dill"), "--compiler", "source",
                       "--concurrency=1", "--timeout=4x", "--fail-fast", "--reporter", "json", "test"],
        cwd=repo / "packages/quds_mail_core", tests=True)
if args.cohort == "final":
    run("analysis", [str(dart), "analyze", "--fatal-infos", "packages/quds_office_engine", "packages/quds_mail_core"], cwd=repo)
    formatted = [
        "lib/src/automation/office_vba_language.dart",
        "lib/src/automation/operations/word_steps.dart",
        "lib/src/automation/operations/word_header_footer_guard.dart",
        "tool/macros/web_vba_word_headers_footers_smoke.dart",
        *[str(p.relative_to(engine)) for p in feature],
    ]
    run("format", [str(dart), "format", "--output=none", "--set-exit-if-changed", *formatted])
    encoded = base64.b64encode((engine / "example/macros/word_headers_footers.bas").read_bytes()).decode()
    define = "-DWORD_HEADERS_FOOTERS_BAS_BASE64=" + encoded
    source = "tool/macros/web_vba_word_headers_footers_smoke.dart"
    javascript = output / "headers-footers.js"
    run("portable-vm", [str(dart), f"--packages={package_config}", define, source])
    run("portable-compile-js", [str(dart), "compile", "js", f"--packages={package_config}", define, source, "-o", str(javascript)])
    if not args.node:
        raise SystemExit("Node is required for the final portable gate; pass --node")
    run("portable-js", [args.node, "-e", "globalThis.self=globalThis; require(process.argv[1]);", str(javascript)])
    vm = (output / "portable-vm.stdout").read_bytes()
    js = (output / "portable-js.stdout").read_bytes()
    if vm != js:
        raise SystemExit("VM and JavaScript receipts differ")
    write(output / "portable-parity.json", {"byte_identical": True, "sha256": hashlib.sha256(vm).hexdigest(), "receipt": json.loads(vm)})

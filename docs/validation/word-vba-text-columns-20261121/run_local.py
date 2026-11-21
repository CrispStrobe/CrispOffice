"""Run the local macro/XML regression cohort and retain source-bound receipts.

Requires the repository's pinned Dart/Flutter runtime and resolved dependencies.
Usage: python docs/validation/word-vba-text-columns-20261121/run_local.py OUTPUT
"""

import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[3]
ENGINE = ROOT / "packages/quds_office_engine"
OUTPUT = Path(sys.argv[1]).resolve()
OUTPUT.mkdir(parents=True, exist_ok=True)


def snapshot():
    paths = set()
    for directory in ("lib", "test", "tool/macros", "example/macros"):
        paths.update(
            p for p in (ENGINE / directory).rglob("*")
            if p.is_file() and p.suffix in (".dart", ".bas", ".json")
        )
    paths.update((ROOT / "pubspec.yaml", ROOT / "pubspec.lock", ENGINE / "pubspec.yaml"))
    return {
        str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(paths)
    }


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def summarize_tests(path):
    tests = {}
    finishes = {}
    final = None
    errors = []
    for line in path.read_text().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = event.get("type")
        if kind == "testStart":
            test = event["test"]
            tests[test["id"]] = test
        elif kind == "testDone":
            finishes[event["testID"]] = event
        elif kind == "done":
            final = event
        elif kind == "error":
            errors.append(event)
    visible = [
        (tests.get(test_id, {}), event)
        for test_id, event in finishes.items()
        if not event.get("hidden")
    ]
    return {
        "passed": sum(e["result"] == "success" and not e.get("skipped") for _, e in visible),
        "failed": sum(e["result"] != "success" for _, e in visible),
        "skipped": sum(bool(e.get("skipped")) for _, e in visible),
        "done": final,
        "errors": errors,
    }


targets = sorted(
    p.relative_to(ENGINE).as_posix()
    for p in (ENGINE / "test").glob("*_test.dart")
    if p.name.startswith(("office_macro", "office_vba", "office_operations", "xml_"))
    or "namespace" in p.name
    or p.name in {
        "slide_import_fidelity_test.dart", "slide_text_fidelity_test.dart",
        "sheet_import_fidelity_test.dart", "odt_section_columns_test.dart",
    }
)
before = snapshot()
with gzip.open(OUTPUT / "sources-before.json.gz", "wt") as f:
    json.dump(before, f, sort_keys=True)
write_json(OUTPUT / "targets.json", targets)
commands = [
    ("engine-analysis", ["dart", "analyze", "--fatal-infos"]),
    ("macro-xml-tests", ["dart", "run", "test:test", "--concurrency=4", "--reporter=json", *targets]),
]
results = []
for name, command in commands:
    print(f"Starting {name}: {len(targets)} test files" if name.endswith("tests") else f"Starting {name}", flush=True)
    start = time.monotonic()
    stdout = OUTPUT / f"{name}.stdout"
    stderr = OUTPUT / f"{name}.stderr"
    with stdout.open("w") as out, stderr.open("w") as err:
        result = subprocess.run(command, cwd=ENGINE, stdout=out, stderr=err)
    receipt = {
        "name": name,
        "command": command,
        "cwd": "packages/quds_office_engine",
        "exitCode": result.returncode,
        "durationSeconds": round(time.monotonic() - start, 3),
        "stdoutSha256": hashlib.sha256(stdout.read_bytes()).hexdigest(),
        "stderrSha256": hashlib.sha256(stderr.read_bytes()).hexdigest(),
    }
    if name.endswith("tests"):
        receipt["tests"] = summarize_tests(stdout)
    results.append(receipt)
    write_json(OUTPUT / f"{name}.json", receipt)
    print(json.dumps(receipt if not name.endswith("tests") else {"name": name, "exitCode": receipt["exitCode"], "tests": receipt["tests"]}), flush=True)

after = snapshot()
changed = sorted(p for p in before.keys() | after.keys() if before.get(p) != after.get(p))
write_json(OUTPUT / "summary.json", {
    "gitHead": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
    "sourceFileCount": len(before),
    "sourceChangesDuringValidation": changed,
    "targetFileCount": len(targets),
    "results": results,
})
for name, _ in commands:
    for suffix in ("stdout", "stderr"):
        path = OUTPUT / f"{name}.{suffix}"
        with path.open("rb") as source, gzip.GzipFile(str(path) + ".gz", "wb", mtime=0) as dest:
            dest.write(source.read())
print(json.dumps({"sourceChangesDuringValidation": changed, "targetFileCount": len(targets)}), flush=True)
sys.exit(0 if not changed and all(r["exitCode"] == 0 for r in results) else 1)

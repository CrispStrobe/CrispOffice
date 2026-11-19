#!/usr/bin/env python3
"""Read immutable incoming Git artifacts; do not rerun or import their harness.

This independently checks the published mail receipts, raw Dart events, and
recorded repository inputs. External dependency/runtime bytes are not available
in this workspace, so only their published before/after inventory consistency
is checked. These are author executions, never additional local passing tests.
"""

import gzip
import hashlib
import json
import struct
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote, urlparse


REPO = Path(__file__).resolve().parents[5]
OUT = Path(__file__).resolve().parent
PUBLISHED = "6275d21246040e03f6264b27171992c88d1474a2"
ACCEPTED = "0c77b3488eb534868a7f98271ba2923d06759b8d"
MAIN = "caf378f40fd5bda50f504a6816404d01d8bbb8f8"
PREFIX = "docs/validation/mail-archive-restore-20261119/"
failures = []


def git(*args):
    return subprocess.check_output(["git", *args], cwd=REPO)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def raw(path):
    return git("show", f"{PUBLISHED}:{PREFIX}{path}")


def read(path):
    data = raw(path)
    return json.loads(gzip.decompress(data) if path.endswith(".gz") else data)


def check(condition, label):
    if not condition:
        failures.append(label)
    return bool(condition)


def tree(commit):
    result = {}
    for entry in git("ls-tree", "-rz", commit).split(b"\0"):
        if entry:
            fields, path = entry.split(b"\t", 1)
            result[path.decode()] = fields.split()[2].decode()
    return result


def source_binding(inventory, trees):
    mismatches = []
    cache = {}
    process = subprocess.Popen(
        ["git", "cat-file", "--batch"], cwd=REPO,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    )
    for path, expected in inventory.items():
        objects = [mapping.get(path) for mapping in trees]
        if any(item is None for item in objects) or len(set(objects)) != 1:
            mismatches.append({"path": path, "reason": "missing or different Git blob"})
            continue
        oid = objects[0]
        if oid not in cache:
            process.stdin.write((oid + "\n").encode())
            process.stdin.flush()
            header = process.stdout.readline().decode().split()
            size = int(header[2])
            content = process.stdout.read(size)
            assert process.stdout.read(1) == b"\n"
            cache[oid] = {"bytes": size, "sha256": sha(content)}
        if cache[oid] != expected:
            mismatches.append({"path": path, "reason": "recorded hash or size mismatch"})
    process.stdin.close()
    assert process.wait() == 0
    return {"inputs": len(inventory), "unique_blobs_hashed": len(cache), "mismatches": mismatches}


def normalized_file(value, cwd):
    if value.startswith("file:"):
        value = unquote(urlparse(value).path)
    if not value.startswith("/"):
        value = str(Path(cwd) / value)
    marker = "/quds_office_suite/"
    assert marker in value, value
    return value.split(marker, 1)[1]


def parse_events(data, cwd):
    suites, tests, finishes = {}, {}, {}
    done, error_events, ignored_lines = [], [], []
    for number, line in enumerate(data.decode().splitlines(), 1):
        try:
            event = json.loads(line)
        except ValueError:
            ignored_lines.append(number)
            continue
        kind = event.get("type")
        if kind == "suite":
            item = event["suite"]
            suites[item["id"]] = item
        elif kind == "testStart":
            item = event["test"]
            check(item["id"] not in tests, f"duplicate testStart {item['id']}")
            tests[item["id"]] = item
        elif kind == "testDone":
            check(event["testID"] not in finishes, f"duplicate testDone {event['testID']}")
            finishes[event["testID"]] = event
        elif kind == "error":
            error_events.append(event)
        elif kind == "done":
            done.append(event)
    check(set(tests) == set(finishes), "started/finished test IDs differ")
    cases = []
    for test_id, result in finishes.items():
        if result.get("hidden", False):
            continue
        item = tests[test_id]
        suite = suites[item["suiteID"]]
        cases.append({
            "file": normalized_file(suite["path"], cwd),
            "name": item["name"], "platform": suite["platform"],
            "result": result["result"], "skipped": result.get("skipped", False),
        })
    counts = {"passed": 0, "failed": 0, "skipped": 0}
    for case in cases:
        category = "skipped" if case["skipped"] else "passed" if case["result"] == "success" else "failed"
        counts[category] += 1
    return {
        "cases": cases, "counts": counts, "files": sorted({x["file"] for x in cases}),
        "done": done, "error_events": error_events, "non_json_lines": ignored_lines,
    }


acceptance = read("acceptance.json")
receipts = {}
for path, expected in acceptance["receipt_sha256"].items():
    actual = sha(raw(path))
    check(actual == expected, f"receipt hash {path}")
    receipts[path] = {"expected_sha256": expected, "observed_sha256": actual}

cohorts, commands, case_keys, unique_files = [], [], set(), set()
claimed_cohorts = {x["name"]: x for x in acceptance["test_cohort_results"]}
for folder in ["final", "incoming/engine", "incoming/editor", "incoming/studio"]:
    receipt = read(folder + "/receipt.json")
    for command in receipt.get("steps", receipt.get("commands", [])):
        name = command["name"]
        path = f"{folder}/{name}"
        observed_hashes = {}
        for stream in ["stdout", "stderr"]:
            observed = sha(raw(f"{path}/{stream}.log"))
            observed_hashes[stream] = observed
            check(observed == command[f"{stream}_sha256"], f"{path} {stream} hash")
        check(command["exit_code"] == 0 and command["accepted"], f"{path} command result")
        commands.append({"path": path, "exit_code": command["exit_code"], "hashes": observed_hashes})
        if "test_counts" not in command:
            continue
        parsed = parse_events(raw(path + "/stdout.log"), command["cwd"])
        artifact = read(path + "/test-cases.json.gz")
        check(sha(raw(path + "/test-cases.json.gz")) == command["test_cases_sha256"], f"{path} cases hash")
        canonical = lambda value: json.dumps(value, sort_keys=True, separators=(",", ":"))
        check(sorted(map(canonical, parsed["cases"])) == sorted(map(canonical, artifact["cases"])), f"{path} raw event/case equality")
        check(parsed["counts"] == command["test_counts"] == claimed_cohorts[name]["counts"], f"{path} test counts")
        check(parsed["files"] == sorted(command["expected_test_files"]) == sorted(claimed_cohorts[name]["files"]), f"{path} test files")
        check(len(parsed["done"]) == 1 and parsed["done"][0].get("success") is True, f"{path} complete success event")
        check(not parsed["error_events"], f"{path} raw error events")
        for case in parsed["cases"]:
            identity = (case["file"], case["platform"], case["name"])
            check(identity not in case_keys, f"overlapping accepted case {identity}")
            case_keys.add(identity)
        unique_files.update(parsed["files"])
        cohorts.append({"name": name, "path": path, "counts": parsed["counts"], "files": len(parsed["files"]), "non_json_lines": parsed["non_json_lines"], "case_artifact_matches_raw_events": True})

inventory_checks = {}
for kind, prefix in [("source", "source"), ("dependency", "dependencies"), ("runtime", "runtime")]:
    before = read(f"final/{prefix}-before.json.gz")
    after = read(f"final/{prefix}-after.json.gz")
    equal = check(before == after, f"{kind} before/after inventory")
    inventory_checks[kind] = {"recorded_inputs": len(before), "before_after_equal": equal,
                              "external_bytes_rehashed_here": False}
    if kind == "source":
        binding = source_binding(before, [tree(ACCEPTED), tree(PUBLISHED), tree(MAIN)])
        check(not binding["mismatches"], "accepted/published/merged source inventory binding")
        inventory_checks[kind].update(binding)
        inventory_checks[kind]["repository_blobs_rehashed_here"] = True

total = {key: sum(x["counts"][key] for x in cohorts) for key in ["passed", "failed", "skipped"]}
check(total == acceptance["test_totals"], "combined totals")
check(len(unique_files) == acceptance["unique_test_files"], "combined file count")
check(len(commands) == acceptance["required_commands_passed"], "command count")
check(len(cohorts) == acceptance["test_cohorts"], "cohort count")
delta = git("diff", "--name-only", ACCEPTED, PUBLISHED).decode().splitlines()
check(all(path.startswith("docs/validation/") for path in delta), "published delta is evidence only")
merged_tree = git("rev-parse", MAIN + "^{tree}").decode().strip()
published_tree = git("rev-parse", PUBLISHED + "^{tree}").decode().strip()
check(merged_tree == published_tree, "published head/merge tree equality")
check(subprocess.run(["git", "merge-base", "--is-ancestor", PUBLISHED, MAIN], cwd=REPO).returncode == 0, "published head is merge ancestor")
author_audit = read("independent-audit.json")
publication = read("publication-check.json")
check(sha(raw("independent-audit.json")) == publication["independent_audit_sha256"], "publication/auditor hash binding")
screenshots = []
for item in author_audit["screenshots"]["files"]:
    name = item["file"]
    captured = raw("final/screenshots/" + name)
    copied = raw("screenshots/" + name)
    check(captured == copied, f"{name} published image copy")
    check(sha(captured) == item["sha256"], f"{name} image hash")
    check(captured[:8] == b"\x89PNG\r\n\x1a\n", f"{name} PNG signature")
    width, height = struct.unpack(">II", captured[16:24])
    check((width, height) == (item["width"], item["height"]), f"{name} image dimensions")
    screenshots.append({"file": name, "sha256": sha(captured), "width": width, "height": height})
report = {
    "schema": 1, "audited_at_utc": datetime.now(timezone.utc).isoformat(),
    "status": "passed" if not failures else "failed", "failures": failures,
    "method": "Independent parser/hash audit of immutable Git artifacts; no imported acceptance helpers and no product tests rerun.",
    "accepted_source": ACCEPTED, "published_mail_head": PUBLISHED, "remote_main_snapshot": MAIN,
    "published_and_merge_tree": published_tree, "receipt_hashes": receipts,
    "author_executions_verified": total, "author_unique_files_verified": len(unique_files),
    "cohorts": cohorts, "commands": commands, "inventories": inventory_checks,
    "screenshot_artifact_hashes_verified": screenshots,
    "accepted_to_published_changed_paths": len(delta),
    "accepted_to_published_only_validation": all(x.startswith("docs/validation/") for x in delta),
    "counting": "Author runs only. Adds zero to our local macro/GUI test counts. VM and Node executions have separate platform identities.",
    "limitations": [
        "Verifies recorded output and source binding, not authenticity of execution or installed-platform behavior.",
        "The author's external dependency and runtime files are unavailable here; only inventory before/after equality was rechecked.",
        "Screenshot bytes and dimensions were checked; this audit does not claim an additional visual or native-app review.",
        "Source inventory is checked against accepted mail source, published mail head and merge snapshot, not against later integrated macro/GUI source.",
        "No product tests, GitHub Actions or status checks were run by this audit.",
    ] + acceptance["limitations"],
}
(OUT / "mail-evidence-audit.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
print(json.dumps({"status": report["status"], "failures": failures, "author_executions_verified": total,
                  "author_unique_files_verified": len(unique_files), "commands": len(commands),
                  "cohorts": len(cohorts), "source_inputs_rehashed": inventory_checks["source"]["inputs"]}))

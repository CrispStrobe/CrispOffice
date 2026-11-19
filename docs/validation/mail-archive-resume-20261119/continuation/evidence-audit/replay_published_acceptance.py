#!/usr/bin/env python3
"""Replay published evidence without relying on the original execution machine.

This independently checks saved logs and immutable Git blobs. It does not rerun
the product tests or assert that the original dependency/runtime files exist now.
"""

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
from urllib.parse import unquote, urlparse

PREFIX = "docs/validation/mail-archive-resume-20261119/"
BASELINE = "b2c05a0afa0ae606b061b13d5e50937c2a8eb1df"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical_digest(value):
    return sha(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    repo = args.repo.resolve()
    failures = []
    cache = {}
    commands = []
    cohorts = []
    case_keys = []
    files = set()

    def check(ok, message):
        if not ok:
            failures.append(message)

    def git(*words):
        return subprocess.check_output(["git", *words], cwd=repo)

    def read(path):
        if path not in cache:
            cache[path] = git("show", BASELINE + ":" + path)
        return cache[path]

    def raw(path):
        return read(PREFIX + path)

    def obj(path):
        value = raw(path)
        return json.loads(gzip.decompress(value) if path.endswith(".gz") else value)

    def match(data, identity, label):
        expected = {"sha256": identity} if isinstance(identity, str) else identity
        check(sha(data) == expected["sha256"], label + ": SHA-256 differs")
        if "bytes" in expected:
            check(len(data) == expected["bytes"], label + ": byte count differs")

    def normalize(path, cwd):
        parsed = urlparse(path)
        path = unquote(parsed.path) if parsed.scheme == "file" else path
        if not path.startswith("/"):
            path = str(PurePosixPath(cwd) / path)
        return path.split("/quds_office_suite/", 1)[1]

    def replay(data, cwd, label, expected_files=None):
        suites, starts, ends = {}, {}, {}
        terminal = []
        errors = []
        anomalies = []
        for number, line in enumerate(data.decode().splitlines(), 1):
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except ValueError:
                anomalies.append([number, "invalid JSON"])
                continue
            if not isinstance(event, dict):
                anomalies.append([number, "non-object JSON"])
                continue
            kind = event.get("type")
            if kind == "suite":
                item = event["suite"]
                if item["id"] in suites:
                    anomalies.append([number, "duplicate suite"])
                suites[item["id"]] = item
            elif kind == "testStart":
                item = event["test"]
                if item["id"] in starts:
                    anomalies.append([number, "duplicate start"])
                starts[item["id"]] = item
            elif kind == "testDone":
                if event["testID"] in ends:
                    anomalies.append([number, "duplicate finish"])
                ends[event["testID"]] = event
            elif kind == "error":
                errors.append(event)
            elif kind == "done":
                terminal.append(event)
        counts = Counter(passed=0, failed=0, skipped=0)
        observed = set()
        local_keys = []
        hidden_failures = 0
        check(set(starts) == set(ends), label + ": incomplete lifecycle")
        for ident, end in ends.items():
            start = starts.get(ident)
            if not start or start.get("suiteID") not in suites:
                anomalies.append([ident, "missing start or suite"])
                continue
            hidden = end.get("hidden") or end.get("isHidden") or start.get("isHidden")
            skipped = bool(end.get("skipped"))
            passed = end.get("result") == "success" and not skipped
            if hidden:
                hidden_failures += int(not passed)
                continue
            suite = suites[start["suiteID"]]
            filename = normalize(suite["path"], cwd)
            key = (filename, suite.get("platform"), start["name"])
            local_keys.append(key)
            observed.add(filename)
            counts["skipped" if skipped else "passed" if passed else "failed"] += 1
        check(not anomalies and not errors and hidden_failures == 0,
              label + ": malformed events or explicit/hidden errors")
        check(len(terminal) == 1 and terminal[0].get("success") is True,
              label + ": missing successful done event")
        check(len(local_keys) == len(set(local_keys)), label + ": duplicate case identity")
        if expected_files is not None:
            check(observed == set(expected_files), label + ": selected file coverage differs")
        check(counts["passed"] > 0 and counts["failed"] == counts["skipped"] == 0,
              label + ": empty, failed or skipped tests")
        case_keys.extend(local_keys)
        files.update(observed)
        detail = {"name": label, "counts": dict(counts), "files": len(observed),
                  "raw_sha256": sha(data), "done_event": terminal,
                  "explicit_errors": len(errors), "hidden_failures": hidden_failures}
        cohorts.append(detail)
        return detail

    def command(folder, record, label, plain=False):
        check(record.get("exit_code") == 0, label + ": command failed")
        check(not record.get("timed_out") and not record.get("interrupted"),
              label + ": interrupted or timed out")
        check(bool(record.get("argv", record.get("command"))) and bool(record.get("cwd")),
              label + ": missing invocation")
        streams = {}
        for stream in ("stdout", "stderr"):
            meta = record.get(stream)
            if isinstance(meta, dict):
                path = folder + "/" + meta["path"]
            else:
                path = folder + "/" + ("" if plain else record["name"] + ".") + stream + ".log"
                meta = record[stream + "_sha256"]
            streams[stream] = raw(path)
            match(streams[stream], meta, path)
        commands.append({"name": label, "exit_code": record["exit_code"],
                         "stdout_sha256": sha(streams["stdout"]),
                         "stderr_sha256": sha(streams["stderr"])})
        return streams

    acceptance = obj("acceptance.json")
    original_audit = obj("independent-audit.json")
    incoming = obj("incoming/acceptance-inventory.json")
    mail = obj("final/receipt.json")
    linked = {
        "independent_audit_sha256": "independent-audit.json",
        "executed_auditor_sha256": "audit-validation.py",
        "mail_receipt_sha256": "final/receipt.json",
        "incoming_inventory_sha256": "incoming/acceptance-inventory.json",
    }
    for field, path in linked.items():
        match(raw(path), acceptance[field], field)
    check(acceptance["status"] == original_audit["status"] == "passed",
          "Accepted status differs")
    check(original_audit["failures"] == [], "Original audit recorded failures")
    check(original_audit["github_actions_used"] is False and acceptance["github_actions_used"] is False,
          "Unexpected GitHub Actions acceptance")

    for step in mail["steps"]:
        check(step.get("accepted") is True, "Mail step is not accepted: " + step["name"])
        check(obj("final/" + step["name"] + "/result.json") == step,
              "Mail step and result record disagree: " + step["name"])
        streams = command("final/" + step["name"], step, "mail/" + step["name"], plain=True)
        if step.get("test_counts"):
            parsed = replay(streams["stdout"], step["cwd"], "mail/" + step["name"], step["expected_test_files"])
            check(parsed["counts"] == step["test_counts"], "Mail replay differs from receipt")

    javascript = []
    incoming_summaries = {item["name"]: item for item in incoming["summary"]["groups"]}
    for group in incoming["accepted_groups"]:
        folder = "incoming/" + group["path"]
        receipt = obj(folder + "/receipt.json")
        summary = incoming_summaries[group["name"]]
        match(raw(folder + "/receipt.json"), summary["receipt_sha256"], group["name"] + " receipt")
        check(group["path"] == summary["path"], group["name"] + ": inventory folder differs")
        command_start, cohort_start = len(commands), len(cohorts)
        check(receipt.get("success") is True, group["name"] + ": receipt did not pass")
        if group["kind"] == "engine":
            records = list(receipt["runtime"].values())
            for name, value in receipt["checks"].items():
                check(value["success"] is True, "Engine check did not pass: " + name)
                records.extend(value["commands"])
                if "generated_javascript" in value:
                    generated = gzip.decompress(raw("incoming/generated-engine-javascript/" + name + ".js.gz"))
                    match(generated, value["generated_javascript"], "JavaScript " + name)
                    run = value["commands"][-1]
                    stdout = raw(folder + "/" + run["stdout"]["path"])
                    reported = [json.loads(line) for line in stdout.decode().splitlines() if line.strip()]
                    check(reported == value["assertions"]["reported"], name + ": assertion output differs")
                    for field in value["assertions"]["required_true_fields"]:
                        check(any(item.get(field) is True for item in reported), name + ": false assertion " + field)
                    javascript.append({"name": name, "bytes": len(generated), "sha256": sha(generated)})
        elif group["kind"] == "ui-tests":
            records = [dict(receipt, name=group["name"])]
        else:
            records = receipt["commands"]
        for record in records:
            label = group["name"] + "/" + record["name"]
            streams = command(folder, record, label, plain=group["kind"] == "ui-tests")
            argv = record.get("command", record.get("argv"))
            if any(x in argv for x in ("--reporter=json", "--reporter")):
                expected = [normalize(x, record["cwd"]) for x in argv if x.endswith("_test.dart")]
                replay(streams["stdout"], record["cwd"], label, expected)
        if group["kind"] == "spacy":
            generated = raw(folder + "/studio_spacy_web_import_gate.js")
            match(generated, receipt["generated_javascript"], "spaCy browser JavaScript")
            stdout = raw(folder + "/web-run.stdout.log").decode().strip()
            check(stdout == receipt["web_assertion"]["required_output"], "spaCy browser assertion differs")
            javascript.append({"name": "studio_spacy_web_import_gate", "bytes": len(generated), "sha256": sha(generated)})
        group_counts = Counter(passed=0, failed=0, skipped=0)
        for cohort in cohorts[cohort_start:]:
            group_counts.update(cohort["counts"])
        check(dict(group_counts) == summary["test_counts"], group["name"] + ": inventory test totals differ")
        check(len(commands) - command_start == summary["commands"], group["name"] + ": inventory command total differs")

    # Compare preserved before/after manifests. External dependency/runtime files
    # from the original machine are intentionally not assumed available now.
    inventories = []
    for folder, kinds in (("final", ("source", "dependencies", "runtime")),
                          ("incoming/final-window-v3", ("source", "dependencies", "runtime", "harnesses"))):
        for kind in kinds:
            before = obj(folder + "/" + kind + "-before.json.gz")
            after = obj(folder + "/" + kind + "-after.json.gz")
            check(before == after, folder + "/" + kind + ": before/after differ")
            binding_key = "dependency" if folder == "final" and kind == "dependencies" else kind
            binding = (acceptance["mail"]["bound_inputs"] if folder == "final"
                       else acceptance["incoming"]["window_inputs"])[binding_key]
            check(len(before) == binding["inputs"] and canonical_digest(before) == binding["digest"],
                  folder + "/" + kind + ": accepted inventory identity differs")
            source_count = 0
            if kind == "source":
                for path, identity in before.items():
                    match(read(path), identity, "Baseline source " + path)
                    source_count += 1
            elif kind == "harnesses":
                for path, identity in before.items():
                    if path.startswith("incoming-validation/"):
                        target = PREFIX + "incoming/" + path.split("/", 1)[1]
                    elif path.startswith("quds_office_suite/"):
                        target = path.split("/", 1)[1]
                    elif path == "runtime/incoming-test-plan.json":
                        target = PREFIX + "incoming/test-plan.json"
                    else:
                        failures.append("Unmapped executed harness: " + path)
                        continue
                    match(read(target), identity, "Executed harness " + path)
                    source_count += 1
            inventories.append({"folder": folder, "kind": kind, "inputs": len(before),
                                "digest": canonical_digest(before), "before_after_equal": before == after,
                                "retained_git_blobs_rehashed": source_count,
                                "external_original_files_rehashed": 0})

    images = obj("ui-review/artifacts-sha256.json")
    image_checks = []
    for path, digest in images.items():
        match(raw("ui-review/" + path), digest, "Reviewed UI artifact " + path)
        if path.startswith("screenshots/") and path.endswith(".png"):
            match(raw("final/" + path), digest, "Final UI capture " + path)
            image_checks.append({"name": path, "sha256": digest})
    check({PurePosixPath(item["name"]).name: item["sha256"] for item in image_checks}
          == original_audit["mail"]["images"]["sha256"],
          "UI captures differ from independently accepted image manifest")

    totals = Counter(passed=0, failed=0, skipped=0)
    for cohort in cohorts:
        totals.update(cohort["counts"])
    check(dict(totals) == acceptance["test_totals"], "Combined raw totals differ")
    check(len(case_keys) == len(set(case_keys)) == acceptance["distinct_case_identities"],
          "Combined distinct case count differs")
    check(len(files) == acceptance["distinct_test_files"], "Distinct test file count differs")
    check(len(cohorts) == acceptance["test_cohorts"], "Test cohort count differs")
    check(len(commands) == acceptance["required_commands_passed"], "Required command count differs")
    check(len(javascript) == acceptance["javascript_programs"], "JavaScript program count differs")
    check(len(image_checks) == acceptance["accepted_ui_images"], "UI image count differs")

    source = acceptance["source_head"]
    changes = git("diff", "--name-only", source, BASELINE).decode().splitlines()
    check(all(path.startswith("docs/validation/") for path in changes),
          "Published baseline changes product source after acceptance")
    report = {
        "status": "passed" if not failures else "failed",
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "baseline_commit": BASELINE,
        "baseline_tree": git("rev-parse", BASELINE + "^{tree}").decode().strip(),
        "accepted_source_commit": source,
        "accepted_source_tree": acceptance["source_tree"],
        "auditor_sha256": sha(Path(__file__).read_bytes()),
        "test_execution_replay": dict(totals),
        "distinct_case_identities": len(set(case_keys)),
        "distinct_test_files": len(files),
        "test_cohorts": cohorts,
        "required_commands": commands,
        "javascript_programs": javascript,
        "input_inventory_checks": inventories,
        "ui_image_checks": image_checks,
        "prior_publication_changes_only_validation_documentation": all(path.startswith("docs/validation/") for path in changes),
        "failures": failures,
        "tests_rerun": False,
        "github_actions_used": False,
        "limits": [
            "This verifies published raw evidence and immutable Git blobs; it does not rerun the historical product commands.",
            "Original dependency/runtime snapshots are mutually consistent, but the original external files are not present and were not rehashed in this continuation.",
            "UI hashes establish continuity with recorded reviewed captures; this audit does not repeat the original visual judgment.",
            "The accepted baseline predates main 9ceb994d; any subsequently changed source/test inputs need explicitly scoped qualification and must not be described as identical to this acceptance.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "tests": dict(totals), "files": len(files),
                      "commands": len(commands), "javascript": len(javascript),
                      "images": len(image_checks), "failures": failures}))
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()

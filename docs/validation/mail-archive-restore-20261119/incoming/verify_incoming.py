#!/usr/bin/env python3
"""Verify retained incoming evidence against raw logs and current source inputs."""

import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

OUT = Path(__file__).resolve().parent
REPO = OUT.parents[3]
RUNTIME = REPO.parent / "runtime"
PARSER = REPO / "docs/validation/mail-archive-portability-20261119/run-local-validation.py"
spec = importlib.util.spec_from_file_location("mail_validation", PARSER)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def zipped(path):
    return json.loads(gzip.decompress(Path(path).read_bytes()))


def main():
    rows, cases, preserved_harnesses = [], [], []
    dependencies = helper.dependency_manifest(REPO / ".dart_tool/package_config.json",
                                               RUNTIME / "pub-cache", RUNTIME / "flutter", REPO)
    for phase in ("engine", "editor", "studio"):
        d = OUT / phase
        receipt = json.loads((d / "receipt.json").read_text())
        assert receipt["status"] == "passed", phase
        assert sha(d / receipt["executed_runner"]) == receipt["runner_sha256"], phase
        assert sha(PARSER) == receipt["parser_sha256"], phase
        assert sha(RUNTIME / "runtime.json") == receipt["runtime_receipt_sha256"], phase
        assert sha(RUNTIME / "readiness-receipt.json") == receipt["readiness_receipt_sha256"], phase
        assert sha(REPO / ".dart_tool/package_config.json") == receipt["package_config_sha256"], phase
        assert zipped(d / "dependencies-before.json.gz") == dependencies, phase
        assert zipped(d / "dependencies-after.json.gz") == dependencies, phase
        for command in receipt["commands"]:
            c = d / command["name"]
            assert command["accepted"] and command["exit_code"] == 0, c
            assert sha(c / "stdout.log") == command["stdout_sha256"], c
            assert sha(c / "stderr.log") == command["stderr_sha256"], c
            assert sha(c / "source-before.json.gz") == command["source_before_sha256"], c
            assert sha(c / "source-after.json.gz") == command["source_after_sha256"], c
            before, after = zipped(c / "source-before.json.gz"), zipped(c / "source-after.json.gz")
            assert before == after, c
            for name, expected in after.items():
                current = REPO / name
                if current.is_file() and sha(current) == expected["sha256"]:
                    continue
                assert name.endswith("/incoming/run_incoming.py"), (phase, name)
                assert sha(d / receipt["executed_runner"]) == expected["sha256"], (phase, name)
                preserved_harnesses.append({"phase": phase, "path": name,
                                           "executed_copy": phase + "/" + receipt["executed_runner"],
                                           "sha256": expected["sha256"]})
            if "test_counts" in command:
                parsed = helper.parse_tests(c / "stdout.log", REPO,
                                            command["expected_test_files"], Path(command["cwd"]))
                assert parsed["accepted"] and parsed == zipped(c / "test-cases.json.gz"), c
                assert sha(c / "test-cases.json.gz") == command["test_cases_sha256"], c
                assert {k: parsed[k] for k in ("passed", "failed", "skipped")} == command["test_counts"], c
                cases.extend(parsed["cases"])
            if "expected" in command:
                assert json.loads((c / "stdout.log").read_text()) == command["expected"], c
            rows.append({"phase": phase, "name": command["name"], "accepted": command["accepted"],
                         "test_counts": command.get("test_counts"),
                         "command_result": str((c / "result.json").relative_to(OUT))})
    keys = [(case["file"], case["platform"], case["name"]) for case in cases]
    assert len(keys) == len(set(keys)), "duplicate test case"
    assert len(rows) == 13 and len(cases) == 564, "incomplete required scope"
    examples = json.loads((OUT / "engine/additional-example-inputs.json").read_text())
    for item in examples["inputs"]:
        assert item["matches_starting_commit"] and sha(REPO / item["path"]) == item["sha256"], item
    runtime = json.loads((RUNTIME / "runtime.json").read_text())
    for name, expected in runtime["executables_sha256"].items():
        assert sha(name) == expected, name
    readiness = json.loads((RUNTIME / "readiness-receipt.json").read_text())
    assert sha(readiness["native_assets"]["library"]) == readiness["native_assets"]["library_sha256"]
    summary = {
        "status": "passed", "verification_script_sha256": sha(__file__),
        "test_totals": {"passed": len(cases), "failed": 0, "skipped": 0},
        "test_file_count": len({case["file"] for case in cases}), "unique_cases": len(keys),
        "commands": rows, "required_commands_passed": len(rows), "command_failures": 0,
        "test_cohorts": 4, "additional_command_gates": 9,
        "current_head_at_summary": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
        "current_product_and_test_inputs_match": True, "current_dependencies_match": True,
        "current_sdk_executables_match": True, "current_sqlite_library_matches": True,
        "preserved_executed_harness_versions": preserved_harnesses,
        "additional_example_inputs_still_match": True,
        "qualification_limits": [
            "Focused incoming changes only; this is not a full-repository acceptance run.",
            "Fresh raw machine-reporter output supplies every counted case. The initial interrupted launcher and superseded Studio run contribute no duplicate cases.",
            "AppKit and macOS installation/signing were not exercised on this Linux host.",
            "Source snapshots bind actual working files; current product/test hashes match the qualified inputs despite unrelated integration commits during the checks.",
        ],
    }
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: summary[key] for key in ("status", "test_totals", "test_file_count", "required_commands_passed")}))


if __name__ == "__main__":
    main()

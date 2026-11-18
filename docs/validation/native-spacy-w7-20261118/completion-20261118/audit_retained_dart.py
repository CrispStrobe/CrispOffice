#!/usr/bin/env python3
"""Read-only W7 Dart receipt audit; does not load native code or run a panel."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("quds_root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.quds_root.resolve()
    evidence = Path("docs/validation/native-spacy-w7-20261118")
    resumed = evidence / "resume-20261118"
    evidence_files: dict[str, dict[str, object]] = {}
    checks: list[str] = []

    def need(condition: bool, label: str) -> None:
        if not condition:
            raise AssertionError(label)

    def read(path: Path) -> dict:
        data = (root / path).read_bytes()
        evidence_files[path.as_posix()] = {"sha256": sha(data), "bytes": len(data)}
        return json.loads(data)

    def git(*command: str) -> str:
        return subprocess.check_output(["git", "-C", str(root), *command], text=True).strip()

    def tree(ref: str) -> dict[str, str]:
        data = subprocess.check_output(["git", "-C", str(root), "ls-tree", "-rz", ref])
        return {
            entry.split(b"\t", 1)[1].decode(): entry.split(b"\t", 1)[0].split()[2].decode()
            for entry in data.split(b"\0") if entry
        }

    head_before = git("rev-parse", "HEAD")
    driver_path = Path("packages/quds_proofing_spacy/tool/consume_distribution.dart")
    driver_hash = sha((root / driver_path).read_bytes())
    expected_driver = "cecbc3a4c52dc8880c9eae7add5a925b0c74660e9d1ba1aee7aaae0ffe02cdf6"
    need(driver_hash == expected_driver, "Current driver differs from audited corrected source")
    protocol = read(evidence / "operational-protocol.json")
    protocol_hash = sha((root / evidence / "operational-protocol.json").read_bytes())
    need(protocol_hash == "60f85df220bb05ff467c6036ce465c841cff3480103720d5139af0644cfd3934", "Frozen protocol drift")
    seal_path = Path("docs/validation/native-spacy-w6-20261117/candidate-seal.json")
    seal = read(seal_path)
    restoration = read(Path("docs/validation/native-spacy-w6-20261117/source-restoration.json"))
    aliases = {r["logical_path"]: r["published_path"] for r in restoration["logical_to_published_artifact"]}
    candidate = tree(seal["candidate_commit"])
    current_tree = tree(head_before)
    sealed_rows = []
    for logical, wanted in sorted(seal["source_sha256"].items()):
        published = aliases.get(logical, logical)
        need(sha((root / published).read_bytes()) == wanted, f"Sealed current SHA drift: {logical}")
        need(current_tree[published] == candidate[published], f"Sealed git blob drift: {logical}")
        sealed_rows.append({"logical_path": logical, "published_path": published,
                            "git_blob": current_tree[published], "sha256": wanted})
    need(len(sealed_rows) == 342, "Wrong sealed source count")
    checks.append("All 342 sealed source SHA-256 identities and candidate/current Git blobs match; the one lock-file alias is the published W5 mapping.")

    sdk = read(resumed / "dart-controls/runtime-restoration.json")
    inventory = read(resumed / "dart-source-labels/current-source-inventory.json")
    controls = read(resumed / "dart-source-labels/controls.json")
    self_log_path = resumed / "dart-source-labels/self-test.log"
    self_bytes = (root / self_log_path).read_bytes()
    self_result = json.loads(self_bytes)
    evidence_files[self_log_path.as_posix()] = {"sha256": sha(self_bytes), "bytes": len(self_bytes)}
    need(sha(self_bytes) == controls["self_test_log_sha256"], "Self-test log hash mismatch")
    need(controls["exit_code"] == 0 and controls["status"] == "passed", "Self-test did not pass")
    need(controls["driver_sha256"] == driver_hash, "Self-test uses different driver")
    need(self_result["model_free_controls"] == controls["model_free_controls"] == 17, "Wrong self-test count")
    need(self_result["source_path_controls"] == 5 and self_result["loader_environment_rejection_cases"] == 8, "Missing self-test checks")
    need(self_result["source_hashes"] == inventory and len(inventory) == 38, "Self-test source inventory mismatch")
    need(self_result["native_library_loaded"] is False and self_result["native_inference_executions"] == 0, "Self-test scope drift")
    checks.append("Current-source self-test log authenticates 17 model-free controls, including 8 loader override rejections and 5 source-path controls, with 38 source/configuration identities.")

    package_files = {}
    for package in sdk["packages"]:
        for file in package["files"]:
            package_files[f'{package["name"]}/{file["path"]}'] = file["sha256"]
    library_rows = []
    for path, wanted in inventory.items():
        if path.startswith("quds_proofing_spacy/"):
            local = Path("packages") / path
            need(sha((root / local).read_bytes()) == wanted, f"Quds source drift: {path}")
            library_rows.append(path)
        elif path == "consume_distribution.dart":
            need(wanted == driver_hash, "Inventory driver mismatch")
        elif path == "package_config.json":
            need(wanted == sdk["package_config_sha256"], "Retained package configuration identity mismatch")
        else:
            need(package_files[path] == wanted, f"Restored external package identity mismatch: {path}")
    need(len(library_rows) == 14, "Wrong Quds source closure count")
    checks.append("All 14 current Quds library files and the driver match the executed inventory; 22 external Dart library source identities match the authenticated archive restoration receipt, and the package-config identity agrees.")

    reports = {}
    cases_summary = []
    pins = {
        "archive_sha256": "4e3b627a614cd21851e6e354335e2e08adeb4cedd4d7778df0cc68c1ce2edf01",
        "manifest_sha256": "e043af51e247368931f23fa0d9b931453e174f105b021fe2053e8e3029fd3d8d",
        "protocol_sha256": protocol_hash,
    }
    expected_identity = {
        "abi_version": 1, "text_abi_version": 1, "capability_mask": 15,
        "library_sha256": seal["native_library_sha256"],
        "bundle_sha256": seal["bundle_sha256"]["manifest.json"],
        "model_sha256": seal["bundle_sha256"]["model.gguf"],
        "resources_sha256": seal["bundle_sha256"]["resources.json"],
    }
    lifecycle = ["same_worker_repeat_exact", "copied_results_stable_after_disposal",
                 "returned_token_collection_immutable", "shutdown_awaited_and_idempotent",
                 "reopened_worker_repeat_exact", "loader_overrides_absent"]
    for base in ["first", "corrected-source"]:
        report_path = resumed / "dart-consumer" / f"{base}.json"
        run = read(resumed / "dart-consumer" / f"{base}-execution.json")
        report = read(report_path)
        need(evidence_files[report_path.as_posix()]["sha256"] == run["public_report_sha256"], f"Public {base} report hash mismatch")
        need(report["status"] == run["status"] == run["consumer_status"] == "passed", f"{base} status failed")
        need(run["exit_code"] == 0 and not run["external_timeout"] and run["error"] is None, f"{base} execution failed")
        run_source = subprocess.check_output(["git", "-C", str(root), "show", f'{run["source_commit"]}:{driver_path.as_posix()}'])
        need(sha(run_source) == run["driver_sha256_before"] == run["driver_sha256_after"], f"{base} source provenance mismatch")
        need(report["sources_before"] == report["sources_after"], f"{base} sources changed during execution")
        need(report["sources_before"]["consume_distribution.dart"] == sha(run_source), f"{base} reported driver differs")
        for key, value in pins.items():
            need(report[key] == value, f"{base} pin mismatch: {key}")
        need(report["native_acceptance_rerun"] is False and report["grammar_qualification_rerun"] is False, f"{base} scope drift")
        need(report["github_actions_queries_waits_reruns"] == 0 and report["typing_or_ui_activation_observed"] is False, f"{base} false scope claim")
        need(all(report[name] is True for name in lifecycle), f"{base} lifecycle assertion missing")
        need(report["unsupported_de_AT"] == "unsupported" and report["cancellation"]["status"] == "cancelled", f"{base} explicit result mismatch")
        need(report["additional_control_requests"] == 5, f"{base} wrong extra request count")
        need(report["additional_control_request_labels"] == ["same-worker-repeat", "unsupported-locale", "cancelled-caller", "disposed-worker-rejection", "reopened-worker-repeat"], f"{base} wrong extra request labels")
        need(report["cpu_preflight"]["all_processor_rows_pass"] is True, f"{base} CPU preflight failed")
        need(report["cpu_preflight"]["required_flags"] == protocol["platform"]["required_cpu_flags"], f"{base} CPU baseline drift")
        need(report["os"] == "linux" and report["cpu_preflight"]["abi"] == "linux_x64", f"{base} wrong platform")
        exec_member = next(x for x in sdk["sdk"]["members"] if x["path"] == "dart-sdk/bin/dart")
        need(report["dart_executable_sha256"] == exec_member["sha256"], f"{base} Dart executable identity mismatch")
        for phase in ["dependency_preflight", "mapped_dependencies", "dependencies_after"]:
            actual = [{key: row[key] for key in ["soname", "sha256", "bytes"]} for row in report[phase]]
            need(actual == protocol["dependencies"], f"{base} dependency drift: {phase}")
            if phase != "dependency_preflight":
                need(all(row["mapped"] for row in report[phase]), f"{base} dependency not mapped")
        need(report["completed_operational_cases"] == len(report["cases"]) == 8, f"{base} incomplete panel")
        for frozen, case in zip(protocol["cases"], report["cases"], strict=True):
            text = frozen["text"]
            encoded = text.encode("utf-8")
            utf16 = text.encode("utf-16-le")
            need(case["id"] == frozen["id"] and case["utf8_sha256"] == frozen["utf8_sha256"] == sha(encoded), f"{base} case identity mismatch")
            need(case["utf16_origin"] == 10 and case["coordinate_checks_passed"] is True, f"{base} origin assertion missing")
            result = case["result"]
            need(result["status"] == "success" and result["identity"] == expected_identity, f"{base} result identity/status mismatch")
            tokens = result["tokens"]
            need("".join(t["text"] + t["whitespace"] for t in tokens) == text, f"{base} reconstruction mismatch")
            for i, (token, absolute) in enumerate(zip(tokens, case["absolute_token_ranges"], strict=True)):
                surface = token["text"]
                sb, eb = token["start_byte"], token["end_byte"]
                sc, ec = token["start_codepoint"], token["end_codepoint"]
                su, eu = token["start_utf16"], token["end_utf16"]
                need(token["i"] == i and encoded[sb:eb].decode() == text[sc:ec] == utf16[su*2:eu*2].decode("utf-16-le") == surface, f"{base} token coordinates mismatch")
                need(len(text[:sc].encode("utf-8")) == sb and len(text[:sc].encode("utf-16-le")) // 2 == su, f"{base} token starts mismatch")
                need(absolute == {"start": 10 + su, "end": 10 + eu}, f"{base} nonzero origin mismatch")
            covered = []
            for sentence in result["sentences"]:
                a, b = sentence["start_token"], sentence["end_token"]
                need(0 <= a < b <= len(tokens), f"{base} invalid sentence token bounds")
                covered.extend(range(a, b))
                need(encoded[sentence["start_byte"]:sentence["end_byte"]].decode() == text[sentence["start_codepoint"]:sentence["end_codepoint"]] == utf16[sentence["start_utf16"]*2:sentence["end_utf16"]*2].decode("utf-16-le") == sentence["text"], f"{base} sentence coordinate mismatch")
                need(sum(tokens[i]["head"] == i for i in range(a, b)) == 1, f"{base} sentence root count")
                for i in range(a, b):
                    need(tokens[i]["is_sent_start"] == (i == a), f"{base} sentence start flags mismatch")
                    visited = set()
                    cursor = i
                    while True:
                        need(a <= cursor < b and cursor not in visited, f"{base} invalid dependency graph")
                        visited.add(cursor)
                        parent = tokens[cursor]["head"]
                        if parent == cursor:
                            break
                        cursor = parent
            need(covered == list(range(len(tokens))), f"{base} sentence coverage mismatch")
            if base == "corrected-source":
                cases_summary.append({"id": case["id"], "tokens": len(tokens), "sentences": len(result["sentences"]), "elapsed_microseconds": case["elapsed_microseconds"], "coordinates_recomputed": True})
        log_path = resumed / "dart-consumer" / f"{base}.log"
        log_bytes = (root / log_path).read_bytes()
        log = json.loads(log_bytes)
        need(log["status"] == "passed" and log["completed_operational_cases"] == 8, f"{base} console summary mismatch")
        evidence_files[log_path.as_posix()] = {"sha256": sha(log_bytes), "bytes": len(log_bytes)}
        reports[base] = {"execution_source_commit": run["source_commit"], "driver_sha256": sha(run_source), "public_report_sha256": run["public_report_sha256"], "raw_report_sha256_recorded_only": run["raw_report_sha256"], "raw_log_sha256_recorded_only": run["raw_log_sha256"], "elapsed_seconds": run["elapsed_seconds"], "report": report}
    corrected = reports["corrected-source"]["report"]
    first = reports["first"]["report"]
    need(corrected["sources_before"] == inventory, "Corrected operational sources differ from self-test inventory")
    for initial, current in zip(first["cases"], corrected["cases"], strict=True):
        need({k: v for k, v in initial.items() if k != "elapsed_microseconds"} == {k: v for k, v in current.items() if k != "elapsed_microseconds"}, "Source-label repair altered recorded operational annotations")
    for row in controls["source_label_mapping"]:
        need(first["sources_before"][row["original_label"]] == inventory[row["corrected_label"]] == row["sha256"], "Recorded source-label map mismatch")
    checks.append("Both native reports and corresponding source commits authenticate. Current corrected-source inventory equals compiled self-test inventory; all eight recorded case annotations and coordinates remain exact across the label-only repair.")
    checks.append("Recomputed complete text reconstruction, UTF-8/scalar/UTF-16 token and sentence coordinates, nonzero origin ranges, sentence partitions, one-root and acyclic same-sentence dependencies for all eight cases in both runs.")
    checks.append("Both reports preserve frozen archive/manifest/protocol/native/model pins, six exact preflight and mapped dependency hashes, CPU baseline, explicit unsupported locale and caller cancellation, disposal/reopen/copy assertions, and source stability.")
    need(head_before == git("rev-parse", "HEAD"), "Repository HEAD moved during audit")
    need(driver_hash == sha((root / driver_path).read_bytes()), "Driver changed during audit")
    for record in reports.values():
        del record["report"]
    output = {
        "schema": "quds.spacy.w7.retained_dart_audit.v1",
        "status": "passed",
        "source_commit": head_before,
        "driver_sha256": driver_hash,
        "scope": "Independent retained-report and source audit; no Dart, model, native acceptance, or W6 qualification execution.",
        "checks": checks,
        "native_inference_executions_this_audit": 0,
        "github_actions_queries_waits_reruns_dispatches": 0,
        "current_compiled_model_free_controls": 17,
        "current_operational_cases": 8,
        "additional_control_requests": 5,
        "quds_library_sources_verified": len(library_rows),
        "source_configuration_inventory_entries": len(inventory),
        "sealed_source": {"count": len(sealed_rows), "candidate_commit": seal["candidate_commit"], "unchanged": True, "inventory_sha256": sha(json.dumps(sealed_rows, sort_keys=True, separators=(",", ":")).encode()), "lock_file_mapping": aliases},
        "reports": reports,
        "cases": cases_summary,
        "current_startup_microseconds": corrected["startup_elapsed_microseconds"],
        "current_shutdown_microseconds": corrected["shutdown_elapsed_microseconds"],
        "evidence_files": evidence_files,
        "limitations": [
            "Public report hashes and source identities were independently recomputed. The earlier raw, unredacted reports/logs are not restored in this checkout; their recorded raw hashes are metadata, not newly verified bytes.",
            "Repeat, cancellation, disposal and reopen outcomes are retained harness assertions corroborated by the matching executed source; raw repeat results and in-memory sentenceEnd fields are not separately serialized for recomputation.",
            "This covers the preserved Linux x86-64/AVX2 development binary and exact six dependency hashes only; no other host or device qualification follows.",
            "Caller cancellation settles the request; physical native compute start or interruption was not observed.",
            "The Dart consumer does not replicate Python context/document RSS/FD cycles or observe Flutter UI/typing behavior.",
            "No linguistic-quality panel was rerun; W6 qualification remains consumed. Hosted distribution publication/readback and production activation remain separate work."
        ],
        "conclusion": "The retained evidence supports completion of W7's bounded Dart installed-worker consumer on current source. No actionable source defect was identified in this review. Top-level pending/uncompiled documentation is stale and should be superseded without rewriting historical receipts."
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": output["status"], "sealed_sources": len(sealed_rows), "operational_cases": len(cases_summary), "report": args.output.name}))


if __name__ == "__main__":
    main()

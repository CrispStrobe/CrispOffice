#!/usr/bin/env python3
"""Pack the final Zotero-main publication supplement without changing prior packs.

  python3 docs/validation/mail-bulk-actions-20261120/build_publication_evidence.py \
    --runtime /absolute/path/to/quds-mail-work-20261120/runtime

--inventory lists the explicit selection without writing an archive. A full
build validates fresh receipts and raw terminal results, unchanged source maps,
the one-test braces correction, both prior archive hashes, and exact PNG byte
identity. The duplicate PNG bytes remain only in the original archive. No tests
are rerun and no network access is performed.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile

import build_evidence as base


DOCS = (
    "publication-intake.md", "publication-source-applicability.json",
    "publication-reconciliation.md", "publication-reconciliation.json",
    "publication-zotero-review.md", "publication-zotero-review.json",
)
PRIOR_MANIFESTS = ("evidence-manifest.json", "evidence-final-main-manifest.json")
ZOTERO_LIBRARIES = frozenset((
    "packages/quds_office_engine/lib/src/word/model/word_zotero.dart",
    "packages/quds_office_engine/lib/src/word/model/word_zotero_citing.dart",
    "packages/quds_office_engine/lib/src/word/model/word_zotero_note.dart",
    "packages/quds_office_engine/lib/src/zotero/zotero_citing.dart",
))
PROTOCOL_TEST = "packages/quds_office_engine/test/zotero_citing_test.dart"


def inventory(repo, runtime, validation):
    rows, missing = {}, []

    def add(path, name, category, source):
        if not path.exists():
            missing.append(source)
            return
        base.require(path.is_file() and not path.is_symlink(), f"Not a regular evidence file: {source}")
        base.require(name not in rows and not Path(name).is_absolute() and ".." not in Path(name).parts,
                     f"Unsafe or duplicate member: {name}")
        rows[name] = base.Member(path, name, category, source)

    def record(name, history=False):
        add(runtime / "records" / name,
            ("history/" if history else "") + "runtime/records/" + name,
            "historical-diagnostic" if history else "publication-qualification",
            "runtime/records/" + name)

    for name in DOCS:
        add(validation / name, "validation/" + name, "publication-reconciliation",
            str((validation / name).relative_to(repo)))
    for name in PRIOR_MANIFESTS:
        add(validation / name, "baseline/" + name, "immutable-prior-manifest",
            str((validation / name).relative_to(repo)))
    for prefix, steps in (
        ("publication-editor", ("format", "analyze-notes", "analyze-citations", "tests")),
        ("publication-host", (*(f"analyze-{i}" for i in range(8)), "tests")),
        ("publication-visual", ("format", "analyze", "tests")),
    ):
        record(prefix + "-receipt.json")
        for step in steps:
            for suffix in ("log", "stderr"):
                record(f"{prefix}-{step}.{suffix}")
    record("publication-visual-inspection.json")
    for suffix in ("validation-receipt.json", "format.log", "analyze.log", "tests-vm.log"):
        record("publication-zotero-engine-" + suffix, history=True)
    for suffix in ("receipt.json", "format.log", "analyze.log", "protocol-tests-vm.log"):
        record("publication-zotero-engine-followup-" + suffix)
    for suffix in (".json", "-format.log", "-analyze.log", "-protocol-tests-vm.log", "-runner.py"):
        record("publication-zotero-engine-harness-diagnostic" + suffix, history=True)
    for name in ("run_publication_editor_validation.py", "run_publication_visual_validation.py",
                 "run_publication_zotero_engine_validation.py", "run_publication_zotero_engine_followup.py"):
        add(runtime / "records" / name, "reproduction/" + name, "runner", "runtime/records/" + name)
    for name in ("run_host_validation.py", "env.sh"):
        add(runtime / name, "reproduction/runtime/" + name, "runner-or-environment", "runtime/" + name)
    for name in ("build_evidence.py", "build_publication_evidence.py"):
        add(validation / name, "reproduction/" + name, "builder", str((validation / name).relative_to(repo)))
    for relative in base.CONFIGS:
        add(repo / relative, "configuration/" + relative, "runtime-configuration", relative)
    return sorted(rows.values(), key=lambda row: row.name), missing


def check_logs(records, commands):
    """Verify every raw-log digest supplied by the three runner schemas."""
    for command in commands:
        if "raw_log" in command:
            path = Path(command["raw_log"])
            base.require(path.parent == records, f"Raw log outside selected records: {path}")
            base.require(base.digest(path.read_bytes()) == command["log_sha256"], f"Changed raw log: {path.name}")
        for channel in ("stdout", "stderr"):
            value = command.get(channel)
            if not value:
                continue
            if isinstance(value, dict):
                path, expected = Path(value["path"]), value["sha256"]
            else:
                path, expected = records / value, command.get(channel + "_sha256")
            base.require(path.parent == records, f"Log outside selected records: {path}")
            if expected is not None:
                base.require(base.digest(path.read_bytes()) == expected, f"Changed log: {path.name}")


def check_flutter_log(path, count):
    events = []
    for line in path.read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict):
            events.append(event)
    cases = [event for event in events if event.get("type") == "testDone" and not event.get("hidden")]
    done = [event for event in events if event.get("type") == "done"]
    base.require(len(cases) == count and all(event.get("result") == "success" and not event.get("skipped")
                                           for event in cases)
                 and done and done[-1].get("success") is True
                 and not any(event.get("type") == "error" for event in events),
                 f"Raw Flutter terminal/count mismatch: {path.name}")


def check_engine(records, repo):
    initial_path = records / "publication-zotero-engine-validation-receipt.json"
    initial = base.load_json(initial_path)
    final = base.load_json(records / "publication-zotero-engine-followup-receipt.json")
    base.require(final["all_passed"] and final["source_unchanged_during_followup"]
                 and final["source_before"] == final["source_after"]
                 and all(command["exit_code"] == 0 for command in final["commands"]),
                 "Final Zotero engine followup is incomplete or failed")
    base.require(final["initial_receipt_sha256"] == base.digest(initial_path.read_bytes())
                 and initial["source_unchanged"] and initial["source_before"] == initial["source_after"],
                 "Initial engine receipt binding is invalid")
    check_logs(records, initial["commands"] + final["commands"])
    initial_tests = next(command for command in initial["commands"] if command["name"] == "tests-vm")
    final_tests = next(command for command in final["commands"] if command["name"] == "protocol-tests-vm")
    for command, count in ((initial_tests, 282), (final_tests, 48)):
        terminal = re.findall(r"\+(\d+): All tests passed!", Path(command["raw_log"]).read_text())
        base.require(command["exit_code"] == 0 and command["passed"] == count
                     and command["failed"] == command["skipped"] == 0
                     and terminal and int(terminal[-1]) == count,
                     f"Engine raw terminal/count mismatch: {command['name']}")
    changed = sorted(path for path in initial["source_after"]
                     if initial["source_after"][path] != final["source_after"].get(path))
    base.require(set(initial["source_after"]) == set(final["source_after"])
                 and changed == final["changed_inputs_since_initial"] == [PROTOCOL_TEST],
                 "Unexpected engine change between retained suites and followup")
    proof = final["exact_braces_only_proof"]
    old = subprocess.check_output(["git", "show", initial["incoming_main"] + ":" + PROTOCOL_TEST], cwd=repo)
    new = (repo / PROTOCOL_TEST).read_bytes()
    before = b"            if (requests == 1)\n              return _command('Application.getActiveDocument', []);\n"
    after = b"            if (requests == 1) {\n              return _command('Application.getActiveDocument', []);\n            }\n"
    base.require(old.count(before) == 1 and old.replace(before, after, 1) == new
                 and proof["exact_single_replacement_verified"]
                 and proof["changes_test_behavior_or_assertions"] is False
                 and base.digest(old) == proof["old_sha256"] == initial["source_after"][PROTOCOL_TEST]
                 and base.digest(new) == proof["new_sha256"] == final["source_after"][PROTOCOL_TEST],
                 "The accepted protocol test correction is not exactly two braces")
    total = final["consolidated_acceptance"]
    base.require(total["passed"] == 282 and total["failed"] == total["skipped"] == 0
                 and total["unchanged_five_suites_retained"] == 234
                 and total["corrected_protocol_suite_rerun"] == 48
                 and sum(final["retained_suite_counts"].values()) == 234
                 and len(final["retained_suite_counts"]) == 5
                 and final_tests["same_48_case_names_as_initial"],
                 "Engine consolidation does not establish the six complete 282-case suites")
    return final


def bindings(repo, runtime, validation):
    records = runtime / "records"
    prior = {}
    for name in PRIOR_MANIFESTS:
        manifest = base.load_json(validation / name)
        archive = manifest["archive"]
        archive_path = validation / archive["path"]
        base.require(archive_path.parent == validation and archive_path.is_file()
                     and base.digest(archive_path.read_bytes()) == archive["sha256"]
                     and archive_path.stat().st_size == archive["bytes"],
                     f"Immutable prior archive changed: {archive['path']}")
        prior[name] = manifest
    baseline, final_main = (prior[name] for name in PRIOR_MANIFESTS)
    editor = base.load_json(records / "publication-editor-receipt.json")
    visual = base.load_json(records / "publication-visual-receipt.json")
    for label, receipt, steps, count in (("editor", editor, 4, 114), ("visual", visual, 3, 8)):
        base.require(receipt["success"] and receipt["inputs_unchanged"]
                     and receipt["inputs"] == receipt["inputs_after"] and len(receipt["steps"]) == steps
                     and all(step["exit_code"] == 0 for step in receipt["steps"]),
                     f"Publication {label} qualification incomplete or failed")
        tests = receipt["steps"][-1]
        base.require(tests["counts"] == {"passed": count, "failed": 0, "skipped": 0}
                     and tests["terminal_done"] and tests["terminal_done"][-1]["success"],
                     f"Publication {label} receipt terminal/count mismatch")
        check_logs(records, receipt["steps"])
        check_flutter_log(records / f"publication-{label}-tests.log", count)
    hosts = base.load_json(records / "publication-host-receipt.json")
    base.require(hosts["success"] and hosts["changed_inputs"] == [] and len(hosts["checks"]) == 9
                 and len(hosts["test_suites"]) == 6 and all(step["exit_code"] == 0 for step in hosts["checks"]),
                 "Publication host qualification incomplete or failed")
    summary = hosts["checks"][-1]["summary"]
    base.require(summary["passed"] == 352 and summary["failed"] == summary["skipped"] == 0
                 and summary["done"][-1]["success"] and not summary["errors"],
                 "Publication host receipt terminal/count mismatch")
    check_logs(records, hosts["checks"])
    check_flutter_log(records / "publication-host-tests.log", 352)
    engine = check_engine(records, repo)

    inspection = base.load_json(records / "publication-visual-inspection.json")
    base.require(inspection["result"] == "PASS" and inspection["all_21_identical"]
                 and inspection["fresh_tests"] == 8, "Publication PNG inspection comparison is incomplete")
    images = visual["images"]
    base.require(len(images) == 21 and set(images) == set(inspection["images"])
                 and set(images) == {path.name for path in (records / "publication-bulk-visuals").glob("*.png")},
                 "Publication PNG inventory differs from its receipts")
    prior_members = {row["path"]: row for row in baseline["members"]}
    image_references = {}
    with tarfile.open(validation / baseline["archive"]["path"], "r:gz") as archive:
        for name, image in images.items():
            base.require(bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.png", name)), f"Unsafe PNG name: {name}")
            member = "runtime/records/bulk-visuals/" + name
            archived = archive.extractfile(member).read()
            fresh = (records / "publication-bulk-visuals" / name).read_bytes()
            check = inspection["images"][name]
            base.require(archived == fresh and base.digest(fresh) == image["sha256"]
                         == check["sha256"] == prior_members[member]["sha256"]
                         and len(fresh) == image["bytes"] == check["bytes"] == prior_members[member]["bytes"]
                         and check["identical_to_directly_inspected_image"], f"PNG byte identity failed: {name}")
            image_references[name] = {"archive": baseline["archive"]["path"], "member": member,
                                      "sha256": image["sha256"], "bytes": image["bytes"],
                                      "fresh_bytes_identical_to_archived": True}
        direct = archive.extractfile("runtime/records/visual-inspection.json").read()
        base.require(base.digest(direct) == inspection["direct_inspection_record_sha256"],
                     "Direct original visual inspection binding changed")

    applicability = base.load_json(validation / "publication-source-applicability.json")
    base.require(applicability["status"] == "PASS", "Publication source applicability is incomplete")
    base.load_json(validation / "publication-reconciliation.json")
    old_word = final_main["source_bindings"]["qualification_inputs"]["final-main-word"]
    word_changes = {
        path: {"earlier_qualified_sha256": expected, "publication_sha256": base.digest((repo / path).read_bytes())}
        for path, expected in old_word.items() if base.digest((repo / path).read_bytes()) != expected
    }
    base.require(set(word_changes) == ZOTERO_LIBRARIES, "Unexpected drift from prior Word qualification")
    scopes = {
        "unchanged-core-and-transport": baseline["source_bindings"]["qualification_inputs"]["core-and-transport"],
        "unchanged-shared-ui": baseline["source_bindings"]["qualification_inputs"]["shared-ui"],
        "unchanged-fonts": final_main["source_bindings"]["qualification_inputs"]["final-main-fonts"],
        "unchanged-prior-word-inputs": {path: expected for path, expected in old_word.items() if path not in word_changes},
        "publication-zotero-engine": engine["source_after"],
        "publication-editor": editor["inputs"],
        "publication-hosts": hosts["inputs"],
        "publication-visuals": visual["inputs"],
    }
    for label in ("publication-zotero-engine", "publication-editor", "publication-hosts", "publication-visuals"):
        base.require(ZOTERO_LIBRARIES <= scopes[label].keys(), f"Changed libraries are not bound by {label}")
    current, differences = {}, []
    for scope, inputs in scopes.items():
        for relative, expected in inputs.items():
            base.require(not Path(relative).is_absolute() and ".." not in Path(relative).parts
                         and bool(base.HEX_SHA256.fullmatch(expected)), f"Invalid source binding: {relative}")
            if relative not in current:
                path = repo / relative
                current[relative] = base.digest(path.read_bytes()) if path.is_file() else "MISSING"
            if current[relative] != expected:
                differences.append({"scope": scope, "path": relative, "expected": expected, "current": current[relative]})
    base.require(not differences, "Publication source differs from qualified inputs:\n" + json.dumps(differences, indent=2))
    git = lambda *args: subprocess.check_output(["git", *args], cwd=repo, text=True).strip()
    return {
        "head": git("rev-parse", "HEAD"), "tree": git("rev-parse", "HEAD^{tree}"),
        "prior_archives": {name: {"archive": manifest["archive"],
                                   "manifest_sha256": base.digest((validation / name).read_bytes())}
                           for name, manifest in prior.items()},
        "both_prior_archives_unchanged": True,
        "qualification_inputs": scopes, "current_sha256": dict(sorted(current.items())),
        "all_listed_current_inputs_match": True,
        "engine_consolidation": engine["consolidated_acceptance"],
        "prior_word_reconciliation": {
            "earlier_qualified_inputs": old_word, "known_zotero_library_changes": word_changes,
            "unchanged_inputs": len(old_word) - len(word_changes),
            "applicability": "The prior complete Word map remains historical. Only these four shared Zotero libraries changed; fresh six-suite engine and two-suite editor qualification covers those changes, and fresh host/visual qualification binds their consumers. Unchanged Word parser, layout, and VBA acceptance is retained under the separate publication-source-applicability review; no new full Word run is claimed.",
        },
        "reused_png_members": image_references, "png_bytes_omitted_from_this_supplement": True,
        "counting_rule": "Cohorts overlap and are not added. The 48 corrected protocol tests replace their earlier outcomes within 282, and historical analyzer/harness failures remain explicitly historical.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--inventory", action="store_true")
    args = parser.parse_args()
    base.require(args.runtime.is_absolute(), "--runtime must be an absolute path")
    runtime = args.runtime.resolve(strict=True)
    validation = Path(__file__).resolve().parent
    repo = validation.parents[2]
    selected, missing = inventory(repo, runtime, validation)
    if args.inventory:
        print(json.dumps({"members": [{"path": row.name, "source": row.source, "category": row.category} for row in selected],
                          "missing_required": missing}, indent=2))
        return
    base.require(not missing, "Missing publication evidence:\n" + "\n".join(missing))
    source = bindings(repo, runtime, validation)
    content = {row.name: row.path.read_bytes() for row in selected}
    content["source-bindings.json"] = base.json_bytes(source)
    content["EVIDENCE.md"] = (
        "# Publication reconciliation evidence\n\n"
        "This compact supplement preserves evidence.tar.gz and evidence-final-main.tar.gz unchanged. "
        "It contains fresh Zotero editor, Studio host and localized visual qualification after the final "
        "captured main advance, plus six-suite Zotero engine acceptance and source applicability.\n\n"
        "The initial engine suite run passed 282 tests while strict analysis failed on one unbraced test "
        "conditional. Its exact two-brace correction, clean full strict analysis and complete 48-case "
        "protocol rerun are preserved. The other 234 unchanged cases are retained once. An intervening "
        "receipt-parser diagnostic remains separate; no failed or interrupted result is represented as a pass.\n\n"
        "All 21 fresh PNGs are byte-identical to the individually inspected original archive members. "
        "source-bindings.json names and hashes each reusable member; no duplicate PNG bytes are included. "
        "The previous broad Word map is retained with its four known Zotero changes explicitly identified. "
        "Unchanged acceptance and new affected-scope gates are distinguished.\n\n"
        "Run the included builder from its repository location with the exact --runtime directory. "
        "Runners and package/native-asset maps are included; the genuine SDK, locked packages and native "
        "library are described by the immutable baseline runtime records and are not duplicated here.\n"
    ).encode()
    rows = [{"path": row.name, "source": row.source, "category": row.category,
             "sha256": base.digest(content[row.name]), "bytes": len(content[row.name])} for row in selected]
    for name in ("source-bindings.json", "EVIDENCE.md"):
        rows.append({"path": name, "source": "generated", "category": "generated-index",
                     "sha256": base.digest(content[name]), "bytes": len(content[name])})
    target = validation / "evidence-publication.tar.gz"
    manifest_path = validation / "evidence-publication-manifest.json"
    temporary = validation / ".evidence-publication.tar.gz.tmp"
    manifest_temporary = validation / ".evidence-publication-manifest.json.tmp"
    try:
        base.write_archive(temporary, content)
        for row in selected:
            base.require(row.path.read_bytes() == content[row.name], f"Evidence changed while packing: {row.source}")
        base.require(bindings(repo, runtime, validation) == source, "Source, PNGs or prior archive changed while packing")
        with tarfile.open(temporary, "r:gz") as archive:
            actual = {entry.name: archive.extractfile(entry).read() for entry in archive.getmembers()}
        base.require(actual == content, "Publication archive round-trip verification failed")
        manifest = {
            "schema": 1, "scope": "mail-bulk-actions-20261120 final captured Zotero-main publication supplement",
            "archive": {"path": target.name, "bytes": temporary.stat().st_size,
                        "sha256": base.digest(temporary.read_bytes())},
            "both_prior_archives_unchanged": True, "duplicate_png_bytes_omitted": True,
            "members": sorted(rows, key=lambda row: row["path"]), "member_count": len(rows),
            "categories": dict(sorted(Counter(row["category"] for row in rows).items())),
            "source_bindings": source,
            "determinism": "Sorted PAX members, fixed mode/uid/gid/mtime, gzip mtime=0 and empty filename; no generated wall-clock timestamp.",
        }
        manifest_temporary.write_bytes(base.json_bytes(manifest))
        os.replace(temporary, target)
        os.replace(manifest_temporary, manifest_path)
    finally:
        temporary.unlink(missing_ok=True)
        manifest_temporary.unlink(missing_ok=True)
    print(json.dumps({"archive": manifest["archive"], "members": len(rows),
                      "manifest": str(manifest_path), "source_bindings": len(source["current_sha256"]),
                      "both_prior_archives_unchanged": True, "png_members_reused": len(source["reused_png_members"])}, indent=2))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Bind the bounded Arabic main update and preserve prior source attribution.

Read-only Git/input review; no application tests, graph rebuild, package
resolution, native build, browser launch or remote status operations.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
PREVIOUS_SOURCE = "a45ee3bf40dbb7e64a04f879fd6d574db7cb60b1"
PREVIOUS_EVIDENCE = "a3373021b6cbe6ae333217417bd1615e88019f7d"
SOURCE = "f69e774fbb32a103260541e4a28fb17600bfc17e"
MAIN_BEFORE = "43db439e1e605d6329a6eabe6817b04ca44ba1aa"
AUTHOR = "754d30d199b6f7dfd52b2772a27cc37a3f8d3dd8"
MAIN = "098412152fa1d64796eb3fb9c06699ced0f0c44d"
HELPER_SHA = "55418e615c35d0add37b14edc2370074a288a0be6b194c7ac11d63f8175924b5"

path = HERE.parent / "evidence-audit/recheck_saved_evidence.py"
assert hashlib.sha256(path.read_bytes()).hexdigest() == HELPER_SHA
spec = importlib.util.spec_from_file_location("arabic_applicability_helpers", path)
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)


def current(path: Path) -> dict:
    return h.record(path.read_bytes())


def entries(repo: Path, ref: str) -> dict:
    result = {}
    for row in h.git(repo, "ls-tree", "-rz", ref).split(b"\0"):
        if row:
            meta, path = row.split(b"\t", 1)
            mode, kind, oid = meta.decode().split()
            result[path.decode()] = {"mode": mode, "kind": kind, "oid": oid}
    return result


def changed(first: dict, second: dict) -> list[str]:
    return sorted(path for path in first.keys() | second.keys() if first.get(path) != second.get(path))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=HERE / "applicability.json")
    args = parser.parse_args()
    repo = args.repo.resolve()
    assert h.git(repo, "rev-parse", "HEAD").decode().strip() == SOURCE
    previous, evidence, source, main_before, author = [entries(repo, ref) for ref in
        [PREVIOUS_SOURCE, PREVIOUS_EVIDENCE, SOURCE, MAIN_BEFORE, AUTHOR]]
    delta = changed(evidence, source)
    author_delta = changed(main_before, author)
    assert delta == author_delta and len(delta) == 38
    assert all(source[path] == author[path] for path in delta)
    assert h.git(repo, "show", "-s", "--format=%P", SOURCE).decode().split() == [PREVIOUS_EVIDENCE, MAIN]
    for ancestor in [PREVIOUS_SOURCE, PREVIOUS_EVIDENCE, MAIN, AUTHOR]:
        h.git(repo, "merge-base", "--is-ancestor", ancestor, SOURCE)
    delta_records = h.source_records(repo, [source[path]["oid"] for path in delta])
    for path in delta:
        assert current(repo / path) == delta_records[source[path]["oid"]], path
    prefix = "docs/validation/zotero-research-materials-20261120/"
    preserved_evidence = [path for path in evidence if path.startswith(prefix)]
    assert preserved_evidence and all(evidence[path] == source.get(path) for path in preserved_evidence)
    old_dir = HERE.parent / "publication-final"
    old_summary = h.read(old_dir / "summary.json")
    assert old_summary["status"] == "partial_browser_environment_blocked"
    assert old_summary["focused_distinct_passed_cases"] == 356 and old_summary["focused_distinct_test_files"] == 27
    old_browser = h.read(HERE.parent / "web-persistence-followup/accepted-web-chrome/receipt.json")
    assert old_browser["status"] == "failed" and old_browser["tests"]["application_cases"] == 0
    assert old_browser["source_head_at_start"] == old_browser["source_head_at_finish"] == PREVIOUS_SOURCE
    old_inventory = h.read(old_dir / "accepted-engine-rendering/inputs.json.gz")["before"]["source"]
    assert all(previous[path]["oid"] == record["git_blob_sha1"] for path, record in old_inventory.items())
    old_input_changes = sorted(path for path in old_inventory if previous.get(path) != source.get(path))
    outside_recorded = sorted(path for path in delta if path not in old_inventory)
    prior_selections = {}
    for name, folder in [
        ("final-engine-rendering", old_dir / "accepted-engine-rendering"),
        ("final-editor-rendering", old_dir / "accepted-editor-rendering"),
        ("final-web-vm", HERE.parent / "web-persistence-followup/accepted-web-vm"),
        ("final-web-chrome-blocked", HERE.parent / "web-persistence-followup/accepted-web-chrome"),
    ]:
        receipt = h.read(folder / "receipt.json")
        paths = receipt["selected_repository_paths"]
        assert all(previous[path] == source[path] for path in paths)
        prior_selections[name] = {"receipt": current(folder / "receipt.json"), "source": PREVIOUS_SOURCE,
                                  "files": len(paths), "test_file_bytes_unchanged": True,
                                  "execution_relabelled_to_new_source": False}
    unchanged_prefixes = [
        "packages/quds_office_engine/lib/src/word/", "packages/quds_office_engine/lib/src/zotero/",
        "packages/quds_office_engine/lib/src/slide/", "packages/quds_office_engine/lib/src/fonts/",
        "packages/quds_office_engine/lib/src/pdf/", "packages/quds_office_engine/lib/src/automation/",
        "packages/quds_office_editor/lib/", "packages/quds_proofing_spacy/",
        "packages/quds_mail_transport/", "third_party/enough_mail/",
        "packages/quds_office_editor/example/lib/studio_mail",
    ]
    unchanged = {}
    for prefix in unchanged_prefixes:
        paths = [path for path in previous.keys() | source.keys() if path.startswith(prefix)]
        assert paths and all(previous.get(path) == source.get(path) for path in paths), prefix
        unchanged[prefix] = len(paths)
    assert previous["pubspec.lock"] == source["pubspec.lock"]
    web_review = h.read(HERE.parent / "host-main-followup/web-persistence-review.json")
    old_web_paths = [row["path"] for row in web_review["complete_delta"]["paths"]]
    superseded_web_paths = sorted(path for path in old_web_paths if previous[path] != source[path])
    assert superseded_web_paths == ["packages/quds_arabic_morph/README.md",
                                    "packages/quds_office_editor/example/lib/studio_arabic_morph_host_web.dart"]
    patch = h.git(repo, "diff", "--full-index", PREVIOUS_EVIDENCE, SOURCE)
    (HERE / "source-delta.patch").write_bytes(patch)
    assert h.git(repo, "rev-parse", "HEAD").decode().strip() == SOURCE
    result = {
        "status": "verified_bounded_arabic_main_applicability",
        "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "previous_qualified_source": PREVIOUS_SOURCE, "previous_evidence_checkpoint": PREVIOUS_EVIDENCE,
        "source": SOURCE, "tree": h.git(repo, "rev-parse", SOURCE + "^{tree}").decode().strip(),
        "parents": [PREVIOUS_EVIDENCE, MAIN], "preserved_main": MAIN,
        "author_source": AUTHOR, "author_base": MAIN_BEFORE,
        "changed_path_count": len(delta), "changed_dart_path_count": sum(path.endswith(".dart") for path in delta),
        "exact_author_delta_paths_and_postimages": True,
        "changed_paths": {path: {"before": evidence.get(path), "after": source[path], "record": delta_records[source[path]["oid"]]} for path in delta},
        "source_delta_patch": current(HERE / "source-delta.patch"),
        "previous_recorded_source_paths": len(old_inventory),
        "unchanged_previous_recorded_inputs": len(old_inventory) - len(old_input_changes),
        "changed_previous_recorded_inputs": old_input_changes,
        "delta_paths_outside_previous_recorded_input_set": outside_recorded,
        "whole_previous_input_inventory_preserved": False,
        "previous_zotero_evidence_paths_preserved": len(preserved_evidence),
        "previous_receipts_and_reports_modified": False,
        "prior_selections": prior_selections, "unchanged_implementation_prefixes": unchanged,
        "root_lockfile_unchanged": True,
        "prior_web_equivalence_superseded_paths": superseded_web_paths,
        "fresh_native_or_browser_execution_claimed": False,
        "scope_review": [
            "New behavior belongs to optional Arabic context disambiguation, Arabic grammar reading selection, host installation/model state and the Studio Arabic settings/setup flow.",
            "The shared suite_workspace changes add the Arabic context toggle and pass grammarReading into the Arabic provider; Word, Zotero, slide rendering and Mail composition implementations remain byte-identical to the preceding source.",
            "Existing broad compile/import reachability is not a proof that every old runtime result applies unchanged. Fresh selected Arabic package, Arabic rule and Studio gates qualify the changed behavior separately.",
            "Native ABI3 and web adapter2 changes affect compatibility even without a loaded context model. VM/mock results do not establish newly compiled native or Wasm execution, real-model ranking or live downloads.",
        ],
        "counting": "Prior2386/157,3201/129,356/27 and original2886 results remain immutable and source-attributed. No older execution is counted as a fresh Arabic-source execution.",
        "browser_limit": "The failed Chrome attempt remains bound to a45 with0 application cases. The new Arabic web source receives no fresh browser pass; older PR229 nine-path author equivalence is not restated for this source.",
        "auditor_record": current(Path(__file__)), "imported_helper_sha256": HELPER_SHA,
        "product_files_modified": False, "github_actions_queried": False,
    }
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: result[key] for key in ["status", "changed_path_count", "changed_dart_path_count",
                                                  "previous_recorded_source_paths", "unchanged_previous_recorded_inputs",
                                                  "prior_web_equivalence_superseded_paths"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

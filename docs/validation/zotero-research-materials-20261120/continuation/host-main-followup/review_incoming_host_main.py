#!/usr/bin/env python3
"""Read-only source/intake audit of the bounded host-main follow-up.

No fetch, ref update, checkout, product edit, or hosted-CI query is performed.
The later web-persistence merge is recorded separately from the frozen source.
"""
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[5]
OUT = Path(__file__).resolve().parent
SOURCE = "214c4ed80bef0cb871f74e90c506d508679d3d6e"
PREVIOUS = "c05668d1470eb14eef2ac4647b4623edd818274f"
MAIN = "64f977ab003031d560c6564cf8895b1250d120d9"
LATER_MAIN = "dbfbbd28caa064f4850dc81860a68de14d48fb35"
WORD = "ab84bc1a0ff7ada1356a8fdc5cd8ebde73e842d3"
PPTX = "e7ba3544b17817fa1769688c56ed395bf627e63e"
MAIL = "177f29d3f9450a58f41189b462b0814aad37e45c"
VBA = "2f55e5359f8aa69b812cf7177a33efca904b7113"
WORD_DIR = "docs/validation/word-native-layout-20261120/"
MAIL_DIR = "docs/validation/mail-attachments-20261120/"
VBA_DIR = "docs/validation/office-vba-variant-conversions-20261120/"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def text(*args):
    return git(*args).decode().strip()


def blob(ref, path):
    return git("show", f"{ref}:{path}")


def oid(ref, path):
    p = subprocess.run(["git", "rev-parse", f"{ref}:{path}"], cwd=ROOT,
                       capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None


def ancestor(head):
    return subprocess.run(["git", "merge-base", "--is-ancestor", head, SOURCE],
                          cwd=ROOT).returncode == 0


def sha(data):
    return hashlib.sha256(data).hexdigest()


def changed(a, b, *paths):
    return text("diff", "--name-only", a, b, "--", *paths).splitlines()


def path_rows(a, b, paths):
    return [{"path": p, "before_blob": oid(a, p), "after_blob": oid(b, p)}
            for p in paths]


def main():
    snapshot = json.loads((OUT / "remote-snapshot.json").read_text())
    paths = changed(PREVIOUS, SOURCE)
    dart_paths = [p for p in paths if p.endswith(".dart")]
    acceptance = json.loads(blob(SOURCE, WORD_DIR + "acceptance.json"))
    qualification = json.loads(blob(SOURCE, WORD_DIR + "qualification-after.json"))
    before = json.loads(blob(SOURCE, WORD_DIR + "qualification-before.json"))
    artifacts = []
    for name, expected in acceptance["artifactSha256"].items():
        actual = sha(blob(SOURCE, WORD_DIR + name))
        artifacts.append({"path": WORD_DIR + name, "expected_sha256": expected,
                          "actual_sha256": actual, "matches": actual == expected})
    pages = [(c["name"], p) for c in qualification["cases"] for p in c["pages"]]
    before_pages = {(c["name"], p["page"]): p
                    for c in before["cases"] for p in c["pages"]}
    word_paths = [p for p in dart_paths if any(s in p for s in
                  ("word", "font_metrics", "host_fonts", "office_controller"))]
    word_rows = path_rows(WORD, SOURCE, word_paths)
    for row in word_rows:
        row["exact_author_blob"] = row["before_blob"] == row["after_blob"]

    mail_base = text("merge-base", SOURCE, MAIL)
    mail_changed = changed(mail_base, MAIL, "packages", "third_party")
    mail_rows = path_rows(MAIL, SOURCE, mail_changed)
    for row in mail_rows:
        row["exact_at_frozen_source"] = row["before_blob"] == row["after_blob"]
    mail_summary_path = MAIL_DIR + "independent-audit/final-main-summary.json"
    mail_summary = json.loads(blob(MAIL, mail_summary_path))
    vba_readme = blob(VBA, VBA_DIR + "README.md")

    geometries = []
    for path, marker in [
        ("packages/quds_office_editor/lib/src/editor_slide/render_slide_stage.dart", "Path _shapePath("),
        ("packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart", "static void _shapePath("),
    ]:
        code = blob(SOURCE, path).decode()
        code = code[code.index(marker):]
        pair = re.search(r"case PmlShapePreset\.pentagon:(.*?)case PmlShapePreset\.chevron:(.*?)case PmlShapePreset\.parallelogram:", code, re.S)
        assert pair
        normalize = lambda s: re.sub(r"\s+", "", s)
        same = normalize(pair.group(1)) == normalize(pair.group(2))
        geometries.append({"path": path, "pentagon_and_chevron_paths_identical": same,
                           "source_blob": oid(SOURCE, path)})

    disposition = [
        {"name": "captured main", "head": MAIN, "included": ancestor(MAIN),
         "disposition": "preserved by the frozen source merge"},
        {"name": "Word native-layout source", "head": WORD, "included": ancestor(WORD),
         "disposition": "source preserved; author strict native-fidelity target remains unmet"},
        {"name": "captured recent PPTX branch", "head": PPTX, "included": ancestor(PPTX),
         "disposition": "now included through main; supersedes its earlier deferred intake disposition"},
        {"name": "latest captured Mail", "head": MAIL, "included": ancestor(MAIL),
         "disposition": "author-qualified checkpoint, pending reconciliation with newer Word/PPTX/main; no longer classified as unfinished Mail acceptance"},
        {"name": "latest captured VBA", "head": VBA, "included": ancestor(VBA),
         "disposition": "deferred: author README still explicitly calls combined-source qualification work in progress"},
        {"name": "subsequent main web persistence", "head": LATER_MAIN, "included": ancestor(LATER_MAIN),
         "disposition": "later captured main; preserve and qualify its narrow delta after the frozen core cohorts"},
    ]
    report = {
        "schema": 1,
        "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "purpose": "Bounded incoming-source assessment, not a replacement for runtime receipts or native acceptance",
        "source_commit": SOURCE, "source_tree": text("rev-parse", SOURCE + "^{tree}"),
        "source_parents": text("show", "-s", "--format=%P", SOURCE).split(),
        "previous_publication_commit": PREVIOUS, "captured_main": MAIN,
        "remote_snapshot": {"path": "remote-snapshot.json", "sha256": sha((OUT / "remote-snapshot.json").read_bytes()),
                            "captured_at_utc": snapshot["captured_at_utc"],
                            "later_main": LATER_MAIN,
                            "qualification_cutoff_is_not_the_later_remote_snapshot": True},
        "changed_path_count": len(paths), "changed_dart_path_count": len(dart_paths),
        "changed_dart_paths": path_rows(PREVIOUS, SOURCE, dart_paths),
        "review_scope": [
            "Word font metrics, blank-paragraph styling, layout/baselines and font registration",
            "Slide picture backgrounds, geometry, numeric PDF text and picture borders",
            "Mail composer resizing/Arabic direction, Mail setup and Material theme",
            "Author qualification and exact bounded branch disposition; historical 225-PR audit is retained unchanged",
        ],
        "word_author_evidence": {
            "acceptance_path": WORD_DIR + "acceptance.json",
            "acceptance_sha256": sha(blob(SOURCE, WORD_DIR + "acceptance.json")),
            "source_commit": acceptance["sourceCommit"],
            "reconciled_source_commit": acceptance["reconciledSourceCommit"],
            "preserved_host_office_commit": acceptance["preservedHostOfficeCommit"],
            "artifact_checks": artifacts, "all_12_artifact_hashes_match": all(x["matches"] for x in artifacts),
            "reference_documents": len(qualification["cases"]), "reference_pages": len(pages),
            "strict_threshold": qualification["requiredF1StrictlyGreaterThan"], "metric": qualification["metric"],
            "pages_above_target": sum(p["passed"] for _, p in pages),
            "failed_pages": [{"case": n, "page": p["page"], "f1": p["f1"]} for n, p in pages if not p["passed"]],
            "all_page_text_and_geometry_match": all(p["textMatches"] and p["geometryMatches"] for _, p in pages),
            "all_page_counts_match": all(c["pageCountsMatch"] for c in qualification["cases"]),
            "all_pages_improved": all(p["f1"] > before_pages[(n, p["page"])]["f1"] for n, p in pages),
            "target_met": acceptance["targetMet"], "strict_gate_exit_status": acceptance["strictTargetGateExitStatus"],
            "author_local_counts_not_added_to_our_totals": {"engine": 182, "editor": 32, "python_comparator_controls": 8,
                                                          "overlapping_reconciliation_engine": 57, "overlapping_reconciliation_editor": 27},
            "source_blob_checks": word_rows,
            "shared_controller_exception": "Shared office_controller.dart also carries newer slide-transform preservation; Word metric registration is retained. Separate source-preservation audit owns its full proof.",
            "limits": [
                "Microsoft Word 16.111.1 for macOS, synthetic Latin text, four fonts/four spacing modes, 16 documents/24 pages only",
                "Calibri/Aptos were locally licensed diagnostic fonts; Arial/Times used Liberation aliases; no proprietary fonts or PDF subsets are supplied",
                "Four Arial/Times exact-spacing pages remain below the strict >95% target; targetMet=false is retained",
                "This audit checks retained bytes/claims; it does not rerun Microsoft Word, qualify Windows, arbitrary documents, other scripts, or every PDF path",
            ],
        },
        "incoming_disposition": disposition,
        "mail_followup_evidence": {
            "author_source_head": MAIL, "summary_path": mail_summary_path,
            "summary_sha256": sha(blob(MAIL, mail_summary_path)),
            "author_reported_status": mail_summary["status"],
            "author_reported_distinct_passes": mail_summary["distinct_application_passes"],
            "author_reported_failures": mail_summary["failed_application_cases"],
            "author_reported_optional_native_not_run": mail_summary["explicit_native_not_run_cases"],
            "author_reported_selected_files": mail_summary["distinct_selected_test_files"],
            "independent_raw_event_reaudit_performed_here": False,
            "comparison_base": mail_base, "product_path_comparisons": mail_rows,
            "interpretation": "The attachment/composer/model/loader/submission source and tests are already exact at the frozen source. Pending newer Mail differences include shared slide background ownership/save/copy repair and evidence, requiring reconciliation rather than an incomplete-Mail label.",
        },
        "vba_followup_evidence": {"head": VBA, "readme_path": VBA_DIR + "README.md",
                                  "readme_sha256": sha(vba_readme),
                                  "explicit_work_in_progress": b"## Work in progress" in vba_readme,
                                  "final_combined_source_gate_pending": b"not the final combined-source gate" in vba_readme},
        "known_incoming_geometry_limit": {
            "finding": "Both Flutter and PDF PmlShapePreset.pentagon paths are identical to the six-vertex notched chevron path, rather than a distinct five-sided silhouette.",
            "evidence": geometries,
            "disposition": "Retain explicit limitation; no unrelated geometry milestone or product fix added to this Zotero continuation.",
        },
        "minimum_continuation_validation": [
            "Fresh complete selected Zotero engine/editor cohorts because shared Word/controller/layout source changed",
            "Focused changed Word font/paragraph-mark/layout/serialization/controller and slide/PDF/rendering regressions on the frozen merged source",
            "Mail compose/attachment layout and Studio theme regressions covering changed host paths",
            "Eight Python comparator controls, without claiming the unavailable native Word corpus reran",
            "Static analysis for all changed Dart paths plus existing qualified scope, and explicit dependency/lock delta accounting",
            "Later PR229: browser-only persistence test on Chrome plus three existing host/cancellation/download-manager suites; verify dependency graph and preserve unaffected core receipts by source/import closure proof",
        ],
        "test_acceptance_here": "Runtime and source-preservation agents own fresh receipts; no test success is inferred from source review",
        "github_actions_queried": False, "product_files_modified": False,
    }
    assert len(paths) == 119 and len(dart_paths) == 30
    assert report["word_author_evidence"]["all_12_artifact_hashes_match"]
    assert len(pages) == 24 and sum(p["passed"] for _, p in pages) == 20
    assert ancestor(MAIN) and ancestor(WORD) and ancestor(PPTX)
    assert not ancestor(MAIL) and not ancestor(VBA) and not ancestor(LATER_MAIN)
    assert all(g["pentagon_and_chevron_paths_identical"] for g in geometries)
    (OUT / "incoming-review.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"source": SOURCE, "paths": len(paths), "dart_paths": len(dart_paths),
                      "word_artifact_hashes": len(artifacts), "native_target_met": False,
                      "pptx_included": True, "mail": "author-qualified/unreconciled", "vba": "work in progress"}))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Qualify the bounded incoming Word, slide and Mail host source delta.

This adapter supplies a disjoint catalog to the immutable primary runner.
All real test execution, event accounting, exact-input guards, timeouts and
the shared SDK validation lock remain the primary runner's implementation.
Earlier milestone and continuation results are separate evidence populations.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys


PRIMARY_RUNNER_SHA256 = "4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf"
HOST_COHORTS = {
    "engine-zotero": {
        "package": "packages/quds_office_engine",
        "patterns": ["*zotero*_test.dart"],
        "additional": [],
        "runner": "dart",
    },
    "editor-zotero": {
        "package": "packages/quds_office_editor",
        "patterns": ["*zotero*_test.dart"],
        "additional": [],
        "runner": "flutter",
    },
    "engine-rendering": {
        "package": "packages/quds_office_engine",
        "patterns": ["slide*_test.dart"],
        "additional": [
            "office_pdf_export_test.dart",
            "word_small_caps_test.dart",
            "fonts_test.dart",
            "word_pdf_test.dart",
        ],
        "runner": "dart",
    },
    "editor-rendering": {
        "package": "packages/quds_office_editor",
        "patterns": ["slide*_test.dart"],
        "additional": [
            "office_dark_slide_test.dart",
            "paint_run_text_unicode_test.dart",
            "word_small_caps_test.dart",
            "word_tab_stops_editor_test.dart",
        ],
        "runner": "flutter",
    },
    "engine-word-layout": {
        "package": "packages/quds_office_engine",
        "patterns": [],
        "additional": [
            "office_named_fonts_test.dart",
            "word_font_line_metrics_test.dart",
            "word_paragraph_mark_layout_test.dart",
            "word_layout_test.dart",
            "word_styles_layout_test.dart",
            "style_cascade_test.dart",
            "word_referenced_styles_and_breaks_test.dart",
            "word_run_measure_test.dart",
            "word_run_measure_boundaries_test.dart",
            "word_contained_text_wrap_test.dart",
            "word_frame_wrap_test.dart",
            "word_inline_picture_test.dart",
            "word_picture_distance_fidelity_test.dart",
            "word_table_nested_layout_test.dart",
            "word_table_tall_frame_layout_test.dart",
            "word_table_tall_toc_layout_test.dart",
            "word_table_picture_pagination_test.dart",
            "word_footnote_reference_test.dart",
            "word_note_numbering_test.dart",
            "word_note_script_break_test.dart",
            "word_fidelity_test.dart",
            "word_section_clone_fidelity_test.dart",
        ],
        "runner": "dart",
    },
    "editor-word-layout": {
        "package": "packages/quds_office_editor",
        "patterns": [],
        "additional": [
            "host_fonts_test.dart",
            "word_shaped_wrap_test.dart",
            "word_underline_paint_test.dart",
            "paint_font_fallback_test.dart",
            "word_hyphenation_caret_test.dart",
            "word_keyboard_context_geometry_test.dart",
            "word_selection_paint_test.dart",
            "word_proofing_geometry_test.dart",
            "word_page_layout_test.dart",
            "word_notes_editing_test.dart",
            "word_note_numbering_test.dart",
            "word_inline_picture_history_test.dart",
            "office_dark_document_test.dart",
            "office_chrome_theme_test.dart",
        ],
        "runner": "flutter",
    },
    "mail-host": {
        "package": "packages/quds_office_editor/example",
        "patterns": [],
        "additional": [
            "studio_mail_attachment_test.dart",
            "studio_mail_attachment_loader_test.dart",
            "studio_mail_attachment_compose_test.dart",
            "studio_mail_cloud_test.dart",
            "studio_mail_ews_test.dart",
            "studio_mail_session_test.dart",
            "studio_mail_compose_test.dart",
            "studio_mail_recipients_test.dart",
            "studio_mail_reply_test.dart",
            "studio_mail_threading_test.dart",
            "studio_mail_test.dart",
        ],
        "runner": "flutter",
    },
    "studio-integration": {
        "package": "packages/quds_office_editor/example",
        "patterns": [],
        "additional": [
            "studio_spacy_pin_test.dart",
            "studio_spacy_setup_test.dart",
            "studio_downloads_manager_test.dart",
            "studio_linguistic_analysis_test.dart",
            "studio_settings_test.dart",
            "studio_language_id_test.dart",
            "studio_comment_draft_proofing_test.dart",
            "studio_zotero_shortcuts_test.dart",
            "studio_zotero_citing_transport_test.dart",
            "studio_layout_theme_test.dart",
            "studio_mail_presets_test.dart",
            "studio_mail_lifecycle_test.dart",
            "studio_page_layout_dialog_test.dart",
            "studio_paragraph_dialog_test.dart",
        ],
        "runner": "flutter",
    },
}


def record(path: Path) -> dict:
    data = path.read_bytes()
    return {"path": str(path.resolve()), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cohort", choices=HOST_COHORTS)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected-head")
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if not args.list and (args.output is None or not args.expected_head):
        parser.error("--output and --expected-head are required for qualification")
    adapter = Path(__file__).resolve()
    runner = adapter.parent.parent.parent / "run_validation.py"
    before = {"adapter": record(adapter), "primary_runner": record(runner)}
    if before["primary_runner"]["sha256"] != PRIMARY_RUNNER_SHA256:
        raise RuntimeError("The primary runner differs from the pinned qualification version")
    module_spec = importlib.util.spec_from_file_location("qualified_primary_runner", runner)
    if module_spec is None or module_spec.loader is None:
        raise RuntimeError("Cannot import the pinned primary runner")
    primary = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(primary)
    primary.COHORTS = HOST_COHORTS
    delegated = [str(runner), args.cohort, "--repo", str(args.repo.resolve()), "--timeout", str(args.timeout)]
    if args.output is not None:
        delegated.extend(["--output", str(args.output.resolve())])
    if args.expected_head:
        delegated.extend(["--expected-head", args.expected_head])
    if args.list:
        delegated.append("--list")
    original_argv = sys.argv
    try:
        sys.argv = delegated
        result = primary.main()
    finally:
        sys.argv = original_argv
    if args.list:
        return result
    after = {"adapter": record(adapter), "primary_runner": record(runner)}
    unchanged = before == after
    provenance = {
        "purpose": "Qualify the bounded Word, slide and Mail host integration delta",
        "cohort": args.cohort,
        "selection": HOST_COHORTS[args.cohort],
        "selection_catalog": HOST_COHORTS,
        "adapter_command": original_argv,
        "delegated_arguments": delegated,
        "code_before": before,
        "code_after": after,
        "code_unchanged": unchanged,
        "primary_runner_exit_code": result,
        "primary_test_audit_and_fingerprint_logic_unchanged": True,
        "shared_sdk_validation_lock_unchanged": True,
        "catalog_disjointness_check_unchanged": True,
        "host_font_inputs_captured_by_original_engine_rendering_guard": True,
        "prior_milestone_and_continuation_counts_are_separate": True,
    }
    output = args.output.resolve()
    provenance_path = output / "selection-adapter.json"
    primary.write_json(provenance_path, provenance)
    receipt_path = output / "receipt.json"
    receipt = json.loads(receipt_path.read_text())
    receipt["selection_adapter"] = provenance
    receipt["guards"]["selection_adapter_and_primary_runner_unchanged"] = unchanged
    receipt["artifacts"][provenance_path.name] = primary.file_record(provenance_path)
    if not unchanged:
        receipt["status"] = "failed"
    primary.write_json(receipt_path, receipt)
    print(json.dumps({"host_followup": args.cohort, "adapter_unchanged": unchanged, "status": receipt["status"]}), flush=True)
    return result if unchanged else 1


if __name__ == "__main__":
    sys.exit(main())

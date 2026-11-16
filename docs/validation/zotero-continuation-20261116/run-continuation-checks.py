#!/usr/bin/env python3
"""Run the continued Zotero, protected-field and note-numbering qualification.

Reuse the pinned-runtime, real-source, before/after fingerprint and temporary
analyzer-graph checks from the preceding qualification. No CI or dependency
resolution is performed. See --plan for the complete command inventory.
"""

import importlib.util
from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent
SOURCE = HERE.parents[2]
PREVIOUS = HERE.parent / "zotero-citing-20261115/run-focused-checks.py"
spec = importlib.util.spec_from_file_location("zotero_qualification", PREVIOUS)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

runner.BASELINE = "dc5f93b673e6087cccc6d66b33dfbfd099668f77"
runner.ARCHIVED_DART_INPUTS = (
    "docs/validation/zotero-continuation-20261116/live-zotero/scripts/catalog-live.dart",
    "docs/validation/zotero-continuation-20261116/live-zotero/scripts/refresh-live.dart",
    "docs/validation/zotero-continuation-20261116/live-zotero/first-insertion/scripts/first-insertion.dart",
    "docs/validation/zotero-continuation-20261116/live-zotero/first-insertion/attempt-1-locator-edit/first-insertion.dart",
)
runner.ENGINE_TESTS = list(dict.fromkeys(runner.ENGINE_TESTS + [
    "word_zotero_preference_flow_test.dart",
    "word_zotero_style_preferences_review_test.dart",
    "word_zotero_rich_edit_test.dart",
    "wml_run_edit_test.dart",
    "word_revision_validation_test.dart",
    "word_revision_scaling_test.dart",
    "word_note_numbering_test.dart",
    "word_footnote_reference_test.dart",
    "word_note_bookmark_edit_test.dart",
    "note_edit_test.dart",
    "note_chrome_fidelity_test.dart",
    "word_note_script_break_test.dart",
    "note_marker_fidelity_test.dart",
    "note_marker_merge_test.dart",
    "rich_note_test.dart",
    "note_marker_legacy_fidelity_test.dart",
    "note_separator_fidelity_test.dart",
]))
runner.EDITOR_TESTS = list(dict.fromkeys(runner.EDITOR_TESTS + [
    "word_zotero_catalog_citing_test.dart",
    "word_zotero_rich_controller_test.dart",
    "word_note_numbering_test.dart",
    "word_notes_editing_test.dart",
    "word_revision_story_test.dart",
    "word_revision_rebase_test.dart",
    "word_generated_bookmark_paste_test.dart",
]))

if __name__ == "__main__":
    if "--source" not in sys.argv:
        sys.argv.extend(["--source", str(SOURCE)])
    if "--output" not in sys.argv:
        sys.argv.extend(["--output", str(HERE / "final")])
    raise SystemExit(runner.main())

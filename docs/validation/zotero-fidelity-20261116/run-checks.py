#!/usr/bin/env python3
"""Qualify saved searches, native bibliography layout and small caps locally.

Uses the existing pinned runtime, genuine locked harnesses and before/after
source fingerprinting. No dependency resolution or GitHub Actions calls.
"""
import importlib.util
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parents[2]
previous = HERE.parent / 'zotero-continuation-20261116/run-continuation-checks.py'
spec = importlib.util.spec_from_file_location('zotero_continuation', previous)
continuation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(continuation)
runner = continuation.runner
runner.BASELINE = 'b24718cc1468c34f494805eb7fb433a87f565503'
runner.ENGINE_TESTS = list(dict.fromkeys(runner.ENGINE_TESTS + [
    'zotero_saved_search_test.dart',
    'zotero_paragraph_runs_test.dart',
    'word_small_caps_test.dart',
    'word_zotero_bibliography_layout_test.dart',
]))
runner.EDITOR_TESTS = list(dict.fromkeys(runner.EDITOR_TESTS + [
    'word_zotero_saved_search_test.dart',
    'word_small_caps_test.dart',
    'word_zotero_bibliography_controller_test.dart',
]))
# This continuation changes typography/layout/PDF, not ODS. Keep its distinct
# regression cohort separate and do not count overlapping test files twice.
runner.INTEGRATION_TESTS = [
    'word_layout_test.dart',
    'word_styles_layout_test.dart',
    'office_named_fonts_test.dart',
    'word_pdf_test.dart',
    'office_pdf_export_test.dart',
    'arabic_pdf_export_test.dart',
    'style_cascade_test.dart',
    'word_style_introduction_test.dart',
    'word_referenced_styles_and_breaks_test.dart',
]
if __name__ == '__main__':
    if '--source' not in sys.argv:
        sys.argv.extend(['--source', str(SOURCE)])
    if '--output' not in sys.argv:
        sys.argv.extend(['--output', str(HERE / 'final')])
    raise SystemExit(runner.main())

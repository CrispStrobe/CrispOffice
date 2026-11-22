#!/usr/bin/env python3
"""Run affected local ODT/Zotero cohorts; never query or await GitHub Actions.

Activate the repository-pinned SDK and locked dependencies first. This runner
reuses the preceding converter gate's JSON reporter and source-stability checks,
with a selection covering the shared reader/writer and reconciled Word fields.
Run Flutter cohorts sequentially to avoid compiler resource contention.
"""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PREVIOUS = HERE.parent / 'zotero-converter-parity-20261122' / 'run_checks.py'
spec = importlib.util.spec_from_file_location('converter_gate', PREVIOUS)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

engine = ROOT / 'packages/quds_office_engine/test'
engine_suites = {
    path.name for path in engine.glob('*_test.dart')
    if path.name.startswith(('odt_', 'odf_zotero_', 'word_zotero_'))
}
engine_suites.update({
    'word_empty_formatted_run_test.dart',
    'word_extended_revision_test.dart',
    'word_field_span_test.dart',
    'word_package_preservation_test.dart',
    'word_revision_scaling_test.dart',
    'word_revision_story_test.dart',
    'word_revision_validation_test.dart',
    'word_table_grid_addressing_test.dart',
    'word_table_cell_margin_test.dart',
    'word_table_cell_margin_layout_test.dart',
})
# The original 29 editor/controller and four Studio selections include native
# opening, source-bound export, Refresh, selected-field context, undo and stale
# publication. Reuse their exact names; the changed converter regression adds
# positive bordered DOCX-to-editable-ODT round trips.
gate.COHORTS = {
    'engine': ('packages/quds_office_engine', sorted(engine_suites), False),
    'editor': gate.COHORTS['editor'],
    'studio': gate.COHORTS['studio'],
}
original_inputs = gate.inputs


def inputs():
    result = original_inputs()
    for path in [Path(__file__).resolve(), PREVIOUS]:
        result[str(path.relative_to(ROOT))] = gate.sha256(path)
    return dict(sorted(result.items()))


gate.inputs = inputs

if __name__ == '__main__':
    raise SystemExit(gate.main())

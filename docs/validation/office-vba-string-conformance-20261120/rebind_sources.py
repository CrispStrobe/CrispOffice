#!/usr/bin/env python3
"""Bind retained local receipts to the final reconciled Git source.

Run with --repo CHECKOUT --evidence-root EXTRACTED_SCRATCH_ROOT --output FILE.
The evidence archives preserve the relative scratch directory names below.
Original absolute paths in the Word receipt are remapped to the supplied roots.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--evidence-root', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = args.repo.resolve()
root = args.evidence_root.resolve()
original_root = '/workspace/scratch/f0aea33f35d2/'


def read(name):
    return json.loads((root / name).read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*parts):
    return subprocess.check_output(['git', *parts], cwd=repo, text=True).strip()


def compare(mapping, absolute=False):
    differences = []
    for name, expected in mapping.items():
        digest = expected['sha256'] if isinstance(expected, dict) else expected
        path = Path(name) if absolute else repo / name
        if absolute and name.startswith(original_root + 'quds_office_suite/'):
            path = repo / name.removeprefix(original_root + 'quds_office_suite/')
        elif absolute and name.startswith(original_root):
            path = root / name.removeprefix(original_root)
        current = sha(path) if path.is_file() else None
        if current != digest:
            differences.append({'path': name, 'qualifiedSha256': digest,
                                'currentSha256': current})
    return {'inputCount': len(mapping), 'differences': differences}


portable = compare(read('portable-final/final-source/inputs-after.json'))
assert [entry['path'] for entry in portable['differences']] == [
    '.github/workflows/office-macros.yml'
], portable
workflow_before = subprocess.check_output(
    ['git', 'show', '6b94e195ec4871d47c4ee0ffb81bcfe6ab8d7c74:.github/workflows/office-macros.yml'],
    cwd=repo)
workflow_now = (repo / '.github/workflows/office-macros.yml').read_bytes()
assert workflow_now == workflow_before.replace(
    b'          test/office_macro_runtime_test.dart\n',
    b'          test/office_macro_runtime_test.dart\n'
    b'          test/office_macro_word_revision_guard_test.dart\n')
portable['workflowDelta'] = 'Only adds the separately qualified Word guard test; portable commands unchanged.'

analysis_receipt = read('qualification/engine-analysis-final.json')
analysis = compare(read('qualification/' + analysis_receipt['inputs']))
assert not analysis['differences'], analysis

word_all = read('word-final/inputs-after.json')['sha256']
word_repo = {name: value for name, value in word_all.items()
             if name.startswith(original_root + 'quds_office_suite/')}
word = compare(word_repo, absolute=True)
assert not word['differences'], word
word['originalFullInputCount'] = len(word_all)
word['scope'] = 'Repository subset rechecked; original full runtime/package receipt remains unchanged and archived.'

presentation = {}
for gate in ['connector-engine-final', 'connector-editor-final',
             'connector-analysis-final', 'connector-format-final']:
    checked = compare(read('pptx-validation/' + gate + '.json')['source_sha256_after'])
    assert not checked['differences'], (gate, checked)
    presentation[gate] = checked

macro_receipt = read('qualification/macro-final.json')
macro_inputs = read('qualification/' + macro_receipt['inputs'])
macro_classification = read('qualification/macro-input-classification.json')
reachable = macro_classification['reachableRepositoryFiles']
macro = compare({path: macro_inputs[path] for path in reachable})
assert [entry['path'] for entry in macro['differences']] == [
    'packages/quds_office_engine/lib/src/word/model/word_revision.dart'
], macro
macro['laterDeltaQualification'] = 'Fresh 34-case Word/native gate, final whole-engine analysis, all six portable programs and 69-case VM/JS corpus.'

dark_path = 'packages/quds_office_editor/test/office_dark_slide_test.dart'
dark_initial = subprocess.check_output(
    ['git', 'show', 'a452efdadc9000c51a8e5e9ba2f16405d4979e2e:' + dark_path], cwd=repo)
assert dark_initial == (repo / dark_path).read_bytes()
source_head = git('rev-parse', 'HEAD')
source_tree = git('rev-parse', 'HEAD^{tree}')
main_head = 'f9128aba7ace7f981746b7282d463cc25a1e6d87'
subprocess.run(['git', 'merge-base', '--is-ancestor', main_head, source_head], cwd=repo, check=True)
production_delta = git('diff', '--name-only', '6b94e195ec4871d47c4ee0ffb81bcfe6ab8d7c74',
                       source_head, '--', ':(glob)packages/**/lib/**')
assert production_delta == '', production_delta

key_paths = [
    'packages/quds_office_engine/lib/src/automation/office_vba_language.dart',
    'packages/quds_office_engine/test/fixtures/vba_conformance/string_intrinsics_v1.json',
    'packages/quds_office_engine/test/office_vba_string_intrinsics_test.dart',
    'packages/quds_office_engine/test/office_vba_string_intrinsics_integration_test.dart',
    'packages/quds_office_engine/test/office_vba_conformance_test.dart',
    'packages/quds_office_engine/test/office_macro_word_revision_guard_test.dart',
    '.github/workflows/office-macros.yml', dark_path,
]
record = {
    'createdAt': datetime.now(timezone.utc).isoformat(),
    'sourceCheckpoint': source_head, 'sourceTree': source_tree,
    'reconciledMain': main_head,
    'noProductionChangeSinceFinalPortableSource': True,
    'portable': portable, 'wholeEngineAnalysis': analysis,
    'word': word, 'presentation': presentation, 'macroImportedInputs': macro,
    'originalDarkTestByteIdentical': True,
    'keyFiles': {path: {'sha256': sha(repo / path), 'gitBlob': git('hash-object', path)}
                 for path in key_paths},
    'note': 'Qualification is bound by exact file bytes. Evidence/publication-only descendants need no source rerun. No GitHub Actions queried or awaited.'
}
args.output.write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({'sourceCheckpoint': source_head, 'sourceTree': source_tree,
                  'verified': True, 'portableExpectedWorkflowDelta': 1,
                  'macroExpectedLaterWordDelta': 1}))

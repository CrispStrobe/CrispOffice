#!/usr/bin/env python3
"""Local, source-sealed deterministic/editor controls after a main refresh.

Run from the repository root with the authenticated Flutter/Dart runtime on
PATH. This runner never opens a native model or any qualification panel.
"""
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

ROOT = Path.cwd()
OUT = ROOT / 'docs/validation/native-spacy-w6-20261117/baseline-refresh-controls'
ORIGINAL_MAIN = '4b2b4e78839d2997a583b7ab1346e2fa537a8ac4'
REFRESHED_MAIN = '23f3b4204fce45d38a103e3159bdc7f1e8d37c4e'
PROOFING = 'packages/quds_office_engine/test/proofing/'
GERMAN_FILES = [
    PROOFING + name + '_test.dart' for name in [
        'german_writing_rules', 'german_grammar', 'german_noun_agreement',
        'german_agreement_context', 'german_morphology_grammar',
        'german_nominal_word_forms', 'german_literal_ranges',
        'german_context', 'german_context_completion', 'german_release_context',
        'german_verb_object_case', 'german_genitive_noun', 'german_agreement_facts',
    ]
]
EDITOR_FILES = [
    'packages/quds_office_editor/test/' + name + '_test.dart' for name in [
        'word_manual_proofing', 'word_proofing_session', 'word_proofing_correction',
    ]
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=ROOT)


def write(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def inventory(ref, paths):
    rows = git('ls-tree', '-r', ref, '--', *paths).decode().splitlines()
    result = {}
    for row in rows:
        meta, path = row.split('\t', 1)
        mode, kind, oid = meta.split()
        if kind == 'blob':
            result[path] = {'mode': mode, 'git_blob_sha1': oid}
    return result


def snapshot():
    paths = set(GERMAN_FILES + EDITOR_FILES)
    for package in ['legacy_doc_parser', 'quds_office_engine',
                    'quds_office_editor', 'quds_proofing_spacy']:
        paths.update(str(path.relative_to(ROOT)) for path in
                     (ROOT / 'packages' / package / 'lib').rglob('*') if path.is_file())
        paths.add('packages/' + package + '/pubspec.yaml')
    paths.update(['pubspec.yaml', 'pubspec.lock'])
    return {path: {'sha256': sha((ROOT / path).read_bytes()),
                   'bytes': (ROOT / path).stat().st_size} for path in sorted(paths)}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if (OUT / 'receipt.json').exists():
        raise SystemExit('Refusing to overwrite a completed control receipt.')
    closure_paths = [
        'packages/quds_office_engine/lib/src/proofing',
        'packages/quds_office_engine/lib/src/opc/zip',
        'packages/quds_office_engine/pubspec.yaml',
    ]
    original = inventory(ORIGINAL_MAIN, closure_paths)
    refreshed = inventory(REFRESHED_MAIN, closure_paths)
    if original != refreshed:
        raise SystemExit('The refreshed deterministic baseline is not byte-identical.')
    normalized_current = {}
    for path in original:
        old_bytes = git('show', ORIGINAL_MAIN + ':' + path)
        current = (ROOT / path).read_bytes()
        if path.endswith('/german_writing_rules.dart'):
            current = current.replace(b"part 'german_agreement_facts.dart';\n", b'', 1)
        normalized_current[path] = {
            'original_sha256': sha(old_bytes), 'normalized_current_sha256': sha(current),
            'matches': old_bytes == current,
        }
    if not all(row['matches'] for row in normalized_current.values()):
        raise SystemExit('Current deterministic baseline differs beyond the additive API part.')
    write('baseline-identity.json', {
        'original_main': ORIGINAL_MAIN, 'refreshed_main': REFRESHED_MAIN,
        'files': len(original), 'byte_identical_main_closure': True,
        'original_git_inventory': original, 'refreshed_git_inventory': refreshed,
        'current_normalized_baseline': normalized_current,
        'normalization': 'Remove exactly the new german_agreement_facts.dart part directive; no old function or table changes.',
    })
    before = snapshot()
    write('source-before.json', before)
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    source_head_before = git('rev-parse', 'HEAD').decode().strip()
    checks = []
    for label, files, expected_count in [
        ('german-proofing', GERMAN_FILES, None),
        ('editor-proofing', EDITOR_FILES, 75),
    ]:
        command = ['flutter', 'test', '--no-pub', *files,
                   '--reporter', 'expanded', '--concurrency', '2']
        begin = time.monotonic()
        try:
            run = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, timeout=180)
            code, raw = run.returncode, run.stdout
        except subprocess.TimeoutExpired as error:
            code, raw = 124, error.stdout or b''
        text = raw.decode(errors='replace').replace(str(ROOT) + '/', '<QUDS>/')
        text = text.replace(str(ROOT.parent) + '/', '<WORKSPACE>/')
        (OUT / (label + '.log')).write_text(text)
        matches = re.findall(r'\+(\d+): All tests passed!', text)
        count = int(matches[-1]) if matches else None
        check = {
            'id': label, 'command': command, 'exit_code': code,
            'elapsed_seconds': round(time.monotonic() - begin, 3),
            'observed_pass_count': count, 'expected_pass_count': expected_count,
            'passed': code == 0 and count is not None and
                (expected_count is None or expected_count == count),
            'log': label + '.log', 'log_sha256': sha(text.encode()),
        }
        checks.append(check)
        print(json.dumps(check), flush=True)
    after = snapshot()
    write('source-after.json', after)
    unchanged = before == after
    receipt = {
        'schema': 'quds.spacy.w6.baseline_refresh_controls.v1',
        'started_utc': started,
        'completed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'source_head_before': source_head_before,
        'source_head_after': git('rev-parse', 'HEAD').decode().strip(),
        'original_main': ORIGINAL_MAIN, 'refreshed_main': REFRESHED_MAIN,
        'baseline_closure_files': len(original),
        'baseline_semantically_changed': False,
        'source_snapshot_files': len(before), 'source_unchanged': unchanged,
        'source_before_sha256': sha((OUT / 'source-before.json').read_bytes()),
        'source_after_sha256': sha((OUT / 'source-after.json').read_bytes()),
        'baseline_identity_sha256': sha((OUT / 'baseline-identity.json').read_bytes()),
        'checks': checks,
        'passed': unchanged and all(check['passed'] for check in checks),
        'scope': 'Existing deterministic German regressions, shared-fact API controls and 75 existing editor safety regressions on refreshed main. No native grammar evaluation.',
        'qualification_panel_read_or_run': False,
        'native_acceptance_read_or_run': False,
        'native_inference_run': False,
        'github_actions_queried_or_waited': False,
    }
    write('receipt.json', receipt)
    if not receipt['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()

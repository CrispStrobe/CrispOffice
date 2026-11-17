#!/usr/bin/env python3
"""Source-sealed local controls after the semantic German baseline update.

Run at the repository root with the restored Flutter runtime on PATH. No
native inference, qualification panel, original acceptance, or CI access.
"""
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

ROOT = Path.cwd()
OUT = ROOT / 'docs/validation/native-spacy-w6-20261117/latest-baseline-controls'
PREVIOUS_MAIN = '23f3b4204fce45d38a103e3159bdc7f1e8d37c4e'
LATEST_MAIN = '6245a6956a76a38f925e1eb18851c0086730112d'
PROOFING = 'packages/quds_office_engine/test/proofing/'
GERMAN_FILES = [PROOFING + name + '_test.dart' for name in [
    'german_writing_rules', 'german_grammar', 'german_noun_agreement',
    'german_agreement_context', 'german_morphology_grammar',
    'german_nominal_word_forms', 'german_literal_ranges', 'german_context',
    'german_context_completion', 'german_release_context',
    'german_verb_object_case', 'german_genitive_noun', 'german_agreement_facts',
    'german_morphology_completion',
]]
EDITOR_FILES = ['packages/quds_office_editor/test/' + name + '_test.dart'
                for name in ['word_manual_proofing', 'word_proofing_session',
                             'word_proofing_correction']]
GRAMMAR_INTEGRATION = [
    'packages/quds_office_editor/test/word_german_grammar_integration_test.dart',
]
RUN_EDIT_FILES = ['packages/quds_office_engine/test/wml_run_edit_test.dart']
GRAMMAR_PATH = 'packages/quds_office_engine/lib/src/proofing/german_grammar.dart'
WRITING_PATH = 'packages/quds_office_engine/lib/src/proofing/german_writing_rules.dart'
EXPECTED_CHANGED = {
    GRAMMAR_PATH, WRITING_PATH,
    'packages/quds_office_engine/lib/src/proofing/german_context_grammar.dart',
    'packages/quds_office_engine/lib/src/proofing/german_literal_ranges.dart',
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=ROOT)


def write(name, value):
    with (OUT / name).open('x') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def inventory(ref, paths):
    result = {}
    for row in git('ls-tree', '-r', ref, '--', *paths).decode().splitlines():
        meta, path = row.split('\t', 1)
        mode, kind, oid = meta.split()
        if kind == 'blob':
            result[path] = {'mode': mode, 'git_blob_sha1': oid}
    return result


def marked(data, start, end):
    first = data.index(start.encode())
    last = data.index(end.encode(), first)
    return data[first:last]


def shared_chunks():
    definitions = [
        ('noun_determiner_adjective_facts', GRAMMAR_PATH,
         'final class _GermanGrammarWord {', 'bool _grammarPrepositionAmbiguous('),
        ('bounded_subject_verb_and_object_guards', GRAMMAR_PATH,
         'const _grammarAccusativeVerbs', 'bool _grammarCouldBeNominalizedAdjective('),
        ('nominalized_adjective_guard', GRAMMAR_PATH,
         'bool _grammarCouldBeNominalizedAdjective(',
         'Iterable<_GermanGrammarIssue> _grammarNounPhrase('),
        ('source_grapheme_boundaries', WRITING_PATH,
         'Set<int> _sourceGraphemeBoundaries(',
         '/// Independently authored writing checks'),
        ('all_reviewed_present_paradigms', WRITING_PATH,
         '  static const List<_GermanPresentParadigm>\n',
         '  static final Map<String, _GermanPresentParadigm> _presentByForm'),
        ('regional_form_equivalence', WRITING_PATH,
         'bool _germanFormsEquivalent(', '/// Discretionary hyphens'),
        ('paradigm_reading_and_subjunctive_behavior', WRITING_PATH,
         'class _GermanPresentParadigm {', '/// Host-authored literal terminology'),
    ]
    rows = []
    for name, path, start, end in definitions:
        previous = marked(git('show', PREVIOUS_MAIN + ':' + path), start, end)
        latest = marked(git('show', LATEST_MAIN + ':' + path), start, end)
        current = marked((ROOT / path).read_bytes(), start, end)
        rows.append({
            'id': name, 'path': path, 'start_marker': start, 'end_marker': end,
            'previous_sha256': sha(previous), 'latest_sha256': sha(latest),
            'current_sha256': sha(current), 'bytes': len(current),
            'unchanged': previous == latest == current,
        })
    return rows


def snapshot():
    paths = set(GERMAN_FILES + EDITOR_FILES + GRAMMAR_INTEGRATION + RUN_EDIT_FILES)
    for package in ['legacy_doc_parser', 'quds_office_engine',
                    'quds_office_editor', 'quds_proofing_spacy']:
        paths.update(str(path.relative_to(ROOT)) for path in
                     (ROOT / 'packages' / package / 'lib').rglob('*')
                     if path.is_file())
        paths.add('packages/' + package + '/pubspec.yaml')
    paths.update(['pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json'])
    return {path: {'sha256': sha((ROOT / path).read_bytes()),
                   'bytes': (ROOT / path).stat().st_size}
            for path in sorted(paths)}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if (OUT / 'source-before.json').exists() or (OUT / 'receipt.json').exists():
        raise SystemExit('Refusing to overwrite this separate control run.')
    closure_paths = [
        'packages/quds_office_engine/lib/src/proofing',
        'packages/quds_office_engine/lib/src/opc/zip',
        'packages/quds_office_engine/pubspec.yaml',
    ]
    previous = inventory(PREVIOUS_MAIN, closure_paths)
    latest = inventory(LATEST_MAIN, closure_paths)
    changed = {path for path in previous.keys() | latest.keys()
               if previous.get(path) != latest.get(path)}
    if changed != EXPECTED_CHANGED:
        raise SystemExit('Unexpected latest-main baseline closure changes.')
    normalized_current = {}
    for path in latest:
        target = git('show', LATEST_MAIN + ':' + path)
        current = (ROOT / path).read_bytes()
        if path == WRITING_PATH:
            directive = b"part 'german_agreement_facts.dart';\n"
            if current.count(directive) != 1:
                raise SystemExit('Expected exactly one shared-fact part directive.')
            current = current.replace(directive, b'', 1)
        normalized_current[path] = {
            'latest_main_sha256': sha(target),
            'normalized_current_sha256': sha(current), 'matches': target == current,
        }
    chunks = shared_chunks()
    if not all(row['matches'] for row in normalized_current.values()):
        raise SystemExit('Merged baseline differs beyond the additive API part.')
    if not all(row['unchanged'] for row in chunks):
        raise SystemExit('A reviewed shared agreement dependency changed.')
    write('baseline-review.json', {
        'previous_main': PREVIOUS_MAIN, 'latest_main': LATEST_MAIN,
        'baseline_semantically_changed': True, 'closure_files': len(latest),
        'changed_paths': sorted(changed),
        'unchanged_closure_files': len(latest) - len(changed),
        'previous_git_inventory': previous, 'latest_git_inventory': latest,
        'current_normalized_baseline': normalized_current,
        'normalization': 'Remove exactly the additive shared-fact part directive; all remaining latest-main bytes match.',
        'shared_agreement_dependency_chunks': chunks,
        'review': [
            'Governed noun phrases now offer bounded complete agreeing alternatives preserving competing lexical meanings, rather than only unique component replacements.',
            'Determiner endings with no plural use establish singular in governed phrases while preserving all singular genders; plural-only nouns remain plural.',
            'Bounded agreeing pronoun clauses add reviewed abstract pride/waiting prepositional objects and valid copula-head genitive attributes.',
            'Existing verb-case contexts now require finite subject agreement and share the postverbal-subject ambiguity veto.',
            'German literal ranges additionally protect quoted examples described as standing or appearing as a quotation.',
            'All generated noun data, morphology implementation, 57 verb paradigms and shared lexical/number/nominalization helpers remain unchanged.',
            'Editor complete-phrase choices apply changed words in reverse source order in one transaction; tracked insertion copies each changed word style through optional WmlRunEdit.styleSource.',
            'The spaCy rule uses the existing single-span correction path because the per-word special case applies only to de.grammar.phrase-agreement.',
        ],
        'qualification_panel_opened': False,
    })
    before = snapshot()
    write('source-before.json', before)
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    source_head_before = git('rev-parse', 'HEAD').decode().strip()
    checks = []
    for label, files, expected_count in [
        ('german-proofing', GERMAN_FILES, None),
        ('editor-proofing', EDITOR_FILES, 75),
        ('editor-grammar-integration', GRAMMAR_INTEGRATION, None),
        ('word-run-edit', RUN_EDIT_FILES, None),
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
        with (OUT / (label + '.log')).open('x') as stream:
            stream.write(text)
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
        'schema': 'quds.spacy.w6.latest_baseline_controls.v1',
        'started_utc': started,
        'completed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'source_head_before': source_head_before,
        'source_head_after': git('rev-parse', 'HEAD').decode().strip(),
        'previous_main': PREVIOUS_MAIN, 'latest_main': LATEST_MAIN,
        'baseline_semantically_changed': True,
        'baseline_closure_files': len(latest),
        'shared_agreement_dependency_chunks_unchanged': True,
        'source_snapshot_files': len(before), 'source_unchanged': unchanged,
        'source_before_sha256': sha((OUT / 'source-before.json').read_bytes()),
        'source_after_sha256': sha((OUT / 'source-after.json').read_bytes()),
        'baseline_review_sha256': sha((OUT / 'baseline-review.json').read_bytes()),
        'runner_sha256': sha(Path(__file__).read_bytes()),
        'checks': checks,
        'passed': unchanged and all(check['passed'] for check in checks),
        'scope': 'Updated deterministic German baseline and shared-fact controls, existing 75 editor safety regressions, incoming complete-phrase integration and existing run-edit regressions. No native evaluation.',
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

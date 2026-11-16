#!/usr/bin/env python3
"""Independently bind completed local qualification to a pinned Git checkout.

No commands are executed from receipts, no tests are rerun, and no network or
GitHub Actions access is performed. Run after all three qualified-* receipts
finish. A later documentation-only checkpoint can be checked with the same
command. Relative --output and --evidence paths are relative to --repo.
"""
import argparse
import collections
import datetime
import gzip
import hashlib
import io
import json
from pathlib import Path
import struct
import subprocess


COHORT_PACKAGES = {
    'engine': 'quds_office_engine',
    'editor': 'quds_office_editor',
    'harper': 'quds_proofing_harper',
}
RUNTIME_ONLY = {'pubspec.lock', '.dart_tool/package_config.json'}
FIXTURES = ('encoded-aliases.pdf', 'identity-glyph-reference.pdf',
            'word-unicode-aliases.pdf', 'authored-text.txt')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    return json.loads(path.read_bytes())


def safe_path(root, relative):
    path = Path(relative)
    if path.is_absolute() or '..' in path.parts:
        raise ValueError(f'Expected a confined relative evidence path: {relative}')
    result = root / path
    if not result.resolve().is_relative_to(root.resolve()):
        raise ValueError(f'Path escapes its evidence root: {relative}')
    return result


def summarize_events(data):
    events = []
    for line in data.decode(errors='replace').splitlines():
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if isinstance(item, dict):
            events.append(item)
    names = {e['test']['id']: e['test'].get('name', str(e['test']['id']))
             for e in events if e.get('type') == 'testStart'}
    outcomes = collections.Counter()
    failures, skipped = [], []
    for event in events:
        if event.get('type') != 'testDone' or event.get('hidden'):
            continue
        outcome = 'skipped' if event.get('skipped') else event.get('result', 'unknown')
        outcomes[outcome] += 1
        if outcome != 'success':
            target = skipped if outcome == 'skipped' else failures
            target.append(names.get(event['testID'], str(event['testID'])))
    done = [event for event in events if event.get('type') == 'done']
    return {'outcomes': dict(outcomes), 'failures': failures, 'skipped': skipped,
            'errors': [event for event in events if event.get('type') == 'error'],
            'runner_success': bool(done and done[-1].get('success'))}


def successful_summary(summary):
    return (summary.get('runner_success') is True
            and summary.get('outcomes', {}).get('success', 0) > 0
            and set(summary.get('outcomes', {})) == {'success'}
            and not summary.get('failures') and not summary.get('errors')
            and not summary.get('skipped'))


def verify_logs(directory, commands, tests=False):
    checked = []
    for command in commands:
        item = {'name': command['name'], 'exit_code': command.get('exit_code'),
                'timed_out': command.get('timed_out', False), 'logs': {}}
        for stream in ('stdout', 'stderr'):
            path = safe_path(directory, command[stream])
            content = path.read_bytes()
            raw = gzip.decompress(content) if path.suffix == '.gz' else content
            actual = sha(raw)
            item['logs'][stream] = {
                'file': command[stream], 'file_sha256': sha(content),
                'uncompressed_sha256': actual,
                'matches': actual == command[stream + '_sha256'],
            }
            if tests and command['name'] == 'tests' and stream == 'stdout':
                item['summary_recomputed'] = summarize_events(raw)
                item['summary_matches_receipt'] = (
                    item['summary_recomputed'] == command.get('summary'))
        item['passed'] = (item['exit_code'] == 0 and not item['timed_out']
                          and all(v['matches'] for v in item['logs'].values()))
        if 'summary_recomputed' in item:
            item['passed'] &= (item['summary_matches_receipt']
                               and successful_summary(item['summary_recomputed']))
        checked.append(item)
    return checked


class Checkout:
    def __init__(self, root, ref):
        self.root = root.resolve()
        self.head = self.git('rev-parse', ref).decode().strip()
        self.tree = self.git('rev-parse', self.head + '^{tree}').decode().strip()
        self.tree_entries = {}
        for entry in self.git('ls-tree', '-rz', self.head).split(b'\0'):
            if not entry:
                continue
            metadata, path = entry.split(b'\t', 1)
            mode, kind, object_sha = metadata.decode().split()
            if kind == 'blob':
                self.tree_entries[path.decode()] = object_sha
        self.blob_hashes = {}
        self.worktree_hashes = {}

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args])

    def load_blob_hashes(self, paths):
        objects = sorted({self.tree_entries[p] for p in paths
                          if p in self.tree_entries} - self.blob_hashes.keys())
        if not objects:
            return
        result = subprocess.run(
            ['git', '-C', str(self.root), 'cat-file', '--batch'],
            input=('\n'.join(objects) + '\n').encode(),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        stream = io.BytesIO(result.stdout)
        for expected in objects:
            header = stream.readline().decode().strip().split()
            if len(header) != 3 or header[0] != expected or header[1] != 'blob':
                raise ValueError(f'Unexpected git cat-file response: {header}')
            data = stream.read(int(header[2]))
            if len(data) != int(header[2]) or stream.read(1) != b'\n':
                raise ValueError('Truncated Git blob batch')
            self.blob_hashes[expected] = sha(data)

    def bind(self, expected):
        self.load_blob_hashes(expected)
        current_mismatches, tracked_mismatches = [], []
        runtime_only, untracked_unexpected = [], []
        for path, recorded in sorted(expected.items()):
            file = safe_path(self.root, path)
            actual = sha(file.read_bytes()) if file.is_file() else None
            self.worktree_hashes[path] = actual
            if actual != recorded:
                current_mismatches.append({'path': path, 'recorded': recorded,
                                           'current': actual})
            blob = self.tree_entries.get(path)
            if blob is not None:
                tracked = self.blob_hashes[blob]
                if tracked != recorded:
                    tracked_mismatches.append({'path': path, 'recorded': recorded,
                                               'head_sha256': tracked, 'blob': blob})
            elif path in RUNTIME_ONLY:
                runtime_only.append({'path': path, 'sha256': recorded,
                                     'current_matches': actual == recorded})
            else:
                untracked_unexpected.append(path)
        return {'input_count': len(expected),
                'tracked_input_count': sum(p in self.tree_entries for p in expected),
                'current_mismatches': current_mismatches,
                'head_mismatches': tracked_mismatches,
                'runtime_only_inputs': runtime_only,
                'unexpected_untracked_inputs': untracked_unexpected,
                'passed': bool(expected) and not (current_mismatches
                          or tracked_mismatches or untracked_unexpected)}


def verify_cohort(checkout, directory, cohort, receipt):
    before, after = receipt['source_before_sha256'], receipt['source_after_sha256']
    commands = receipt['commands']
    command_names = [c['name'] for c in commands]
    logs = verify_logs(directory, commands, tests=True)
    captured = directory / 'validate-used.py'
    package = COHORT_PACKAGES[cohort]
    expected_test_args = ['test/' + p for p in receipt['tests']]
    test_command = next(c for c in commands if c['name'] == 'tests')['command']
    analyzed = next(c for c in commands if c['name'] == 'analyze')['command']
    formatted = next(c for c in commands if c['name'] == 'format')['command']
    checks = {
        'receipt_passed': receipt.get('passed') is True,
        'correct_cohort': receipt.get('cohort') == cohort,
        'receipt_inputs_unchanged': receipt.get('inputs_unchanged') is True,
        'before_after_hashes_equal': before == after and bool(before),
        'commands_exactly_tests_analyze_format': command_names == ['tests', 'analyze', 'format'],
        'logs_and_test_summary_pass': all(item['passed'] for item in logs),
        'captured_harness_matches': sha(captured.read_bytes()) == receipt['harness_sha256'],
        'test_arguments_match_receipt': test_command[-len(expected_test_args):] == expected_test_args,
        'tests_bound_as_inputs': all('packages/' + package + '/test/' + p in before
                                   for p in receipt['tests']),
        'strict_analysis': '--fatal-infos' in analyzed,
        'nonmutating_format_gate': '--output=none' in formatted and '--set-exit-if-changed' in formatted,
    }
    binding = checkout.bind(before)
    summary = next(item['summary_recomputed'] for item in logs if item['name'] == 'tests')
    return {'receipt': str((directory / 'receipt.json').relative_to(checkout.root)),
            'receipt_sha256': sha((directory / 'receipt.json').read_bytes()),
            'recorded_heads': {'before': receipt['head_before'], 'after': receipt['head_after']},
            'started_utc': receipt['started_utc'], 'finished_utc': receipt['finished_utc'],
            'test_files': receipt['tests'], 'test_file_count': len(receipt['tests']),
            'summary': summary, 'harness_sha256': receipt['harness_sha256'],
            'checks': checks, 'source_binding': binding, 'commands': logs,
            'passed': all(checks.values()) and binding['passed']}


def file_manifest(directory):
    return {str(p.relative_to(directory)): {'bytes': p.stat().st_size,
            'sha256': sha(p.read_bytes())} for p in sorted(directory.rglob('*')) if p.is_file()}


def verify_poppler(checkout, evidence, qualified_engine):
    directory = evidence / 'resume-audit/poppler-recheck'
    path = directory / 'receipt.json'
    receipt = read_json(path)
    producer = read_json(directory / 'producer-receipt.json')
    artifacts = {}
    for name, expected in receipt['artifacts'].items():
        data = safe_path(directory, name).read_bytes()
        artifacts[name] = {'sha256': sha(data), 'bytes': len(data),
                           'matches': sha(data) == expected['sha256']
                                      and len(data) == expected['bytes']}
    inputs = {}
    for name, expected in receipt['inputs_before'].items():
        data = safe_path(directory, name).read_bytes()
        inputs[name] = {'copied_input_matches': sha(data) == expected['sha256']
                         and len(data) == expected['bytes']}
        if name in FIXTURES:
            fresh = qualified_engine / 'render' / name
            fresh_data = fresh.read_bytes()
            inputs[name].update({'fresh_engine_path': str(fresh.relative_to(checkout.root)),
                                 'fresh_engine_sha256': sha(fresh_data),
                                 'fresh_engine_matches_rendered_input':
                                 sha(fresh_data) == expected['sha256']})
    source = receipt['source_before_sha256']
    producer_subset = {p: producer['source_before_sha256'].get(p) for p in source}
    producer_after = {p: producer['source_after_sha256'].get(p) for p in source}
    binding = checkout.bind(source)
    lock_hash = producer['source_before_sha256']['pubspec.lock']
    saved_lock = 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
    lock_binding = checkout.bind({'pubspec.lock': lock_hash, saved_lock: lock_hash})
    logs = verify_logs(directory, receipt['commands'])
    captured_matches = (sha((directory / 'verify-pdf-rendering-used.py').read_bytes())
                        == receipt['harness_sha256'])
    png_a = (directory / 'encoded-aliases.png').read_bytes()
    png_b = (directory / 'identity-glyph-reference.png').read_bytes()
    dimensions = list(struct.unpack('>II', png_a[16:24]))
    authored = (directory / 'authored-text.txt').read_text()
    text_equal = {name: (directory / (name + '.txt')).read_text().rstrip('\n\f') == authored
                  for name in ('encoded-aliases', 'word-unicode-aliases')}
    checks = {
        'receipt_passed': receipt.get('passed') is True,
        'source_unchanged': receipt.get('source_unchanged') is True
                            and source == receipt['source_after_sha256'],
        'inputs_unchanged': receipt.get('inputs_unchanged') is True
                            and receipt['inputs_before'] == receipt['inputs_after'],
        'artifacts_match': all(x['matches'] for x in artifacts.values()),
        'inputs_match': all(x['copied_input_matches'] for x in inputs.values()),
        'fresh_engine_fixtures_equal_rendered_pdfs': all(
            inputs[name]['fresh_engine_matches_rendered_input'] for name in FIXTURES),
        'producer_receipt_passed': producer.get('passed') is True,
        'producer_before_after_equal': producer.get('inputs_unchanged') is True
                                      and producer['source_before_sha256'] == producer['source_after_sha256'],
        'producer_binds_scoped_rendering_inputs': producer_subset == source == producer_after,
        'captured_harness_matches': captured_matches,
        'command_logs_match_and_commands_passed': all(x['passed'] for x in logs),
        'raster_receipt_passed': receipt['checks']['raster'].get('passed') is True,
        'text_receipt_passed': receipt['checks']['text'].get('passed') is True,
        'rendered_png_bytes_identical': png_a == png_b,
        'rendered_dimensions_match_receipt': dimensions == receipt['checks']['raster']['expected_fixture_dimensions'],
        'text_matches_authored_scalars': all(text_equal.values()),
    }
    original_audit = read_json(evidence / 'resume-audit/receipt.json')
    audit_refs = {p: sha(safe_path(checkout.root, p).read_bytes()) == digest
                  for p, digest in original_audit['recovered_receipts'].items()}
    checks['recovered_audit_receipt_hashes_match'] = all(audit_refs.values())
    return {'receipt': str(path.relative_to(checkout.root)), 'receipt_sha256': sha(path.read_bytes()),
            'scope': receipt['scope'], 'limits': receipt['limits'],
            'attribution': 'Rebinds previously rendered artifacts and exact scoped inputs; does not rerun Poppler.',
            'recorded_metrics': receipt['checks'], 'checks': checks,
            'source_binding': binding, 'producer_lock_binding': lock_binding,
            'source_input_count': len(source), 'producer_input_lock_additional': 1,
            'artifacts': artifacts, 'input_binding': inputs, 'commands': logs,
            'recovered_audit_hash_bindings': audit_refs,
            'baseline_context': original_audit['checks']['baseline_log_integrity'],
            'passed': all(checks.values()) and binding['passed'] and lock_binding['passed']}


def verify_flutter_metrics(checkout, evidence, qualified_editor):
    directory = qualified_editor / 'render'
    alias = read_json(directory / 'shared-glyph-aliases.json')
    supplementary = read_json(directory / 'metrics.json')
    previous = evidence / 'editor-final/render'
    checks = {
        'alias_authored_scalars_preserved': alias['source_code_points'] == alias['extracted_code_points'],
        'alias_identical_subset_pixels': alias['differing_pixels'] == 0,
        'alias_has_ink_and_width': alias['ink_pixels'] > 0 and alias['width'] > 0,
        'supplementary_authored_scalars_preserved': supplementary['source_code_points'] == supplementary['extracted_code_points'],
        'supplementary_identical_subset_pixels': supplementary['direct_subset_differing_pixels'] == 0,
        'supplementary_width_matches': supplementary['reference_width'] == supplementary['subset_width'] > 0,
        'supplementary_has_ink': supplementary['subset_ink_pixels'] > 0,
        'scope_statements_retained': bool(alias.get('scope')) and bool(supplementary.get('scope')),
    }
    return {'path': str(directory.relative_to(checkout.root)),
            'shared_glyph_aliases': alias, 'supplementary_aliases': supplementary,
            'matches_prior_metrics': {
                'shared_glyph_aliases': alias == read_json(previous / 'shared-glyph-aliases.json'),
                'supplementary_aliases': supplementary == read_json(previous / 'metrics.json')},
            'artifacts': file_manifest(directory), 'checks': checks,
            'limits': 'Synthetic Latin outlines under Unicode aliases. Identical subset controls only; '
                      'the recorded Latin-reference difference is retained, not described as zero. '
                      'No original-font or cross-cmap raster parity, true emoji/CJK coverage, '
                      'shared shaping backend, Unicode conformance, or performance claim.',
            'passed': all(checks.values())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--evidence', type=Path,
                        default=Path('docs/validation/text-rendering-continuation-20261116'))
    parser.add_argument('--head', default='HEAD')
    args = parser.parse_args()
    repo = args.repo.resolve()
    evidence = args.evidence if args.evidence.is_absolute() else repo / args.evidence
    output = args.output if args.output.is_absolute() else repo / args.output
    result = {'schema': 'quds-final-source-qualification-v1',
              'checked_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'verifier_sha256': sha(Path(__file__).read_bytes()),
              'github_actions_used': False, 'passed': False}
    try:
        # Preflight every cohort before checking any qualification. Missing or
        # unfinished receipts fail closed; they are never treated as partial passes.
        receipts = {}
        for cohort in COHORT_PACKAGES:
            directory = evidence / ('qualified-' + cohort)
            receipt = read_json(directory / 'receipt.json')
            if (not receipt.get('finished_utc') or 'source_after_sha256' not in receipt
                    or [c['name'] for c in receipt.get('commands', [])]
                    != ['tests', 'analyze', 'format']):
                raise ValueError(f'{cohort} receipt is unfinished; run this verifier after all cohorts complete')
            receipts[cohort] = receipt
        checkout = Checkout(repo, args.head)
        result['head'] = checkout.head
        result['tree'] = checkout.tree
        result['cohorts'] = {
            cohort: verify_cohort(checkout, evidence / ('qualified-' + cohort), cohort, receipt)
            for cohort, receipt in receipts.items()}
        result['poppler'] = verify_poppler(checkout, evidence, evidence / 'qualified-engine')
        result['flutter_rendering'] = verify_flutter_metrics(checkout, evidence, evidence / 'qualified-editor')
        snapshot_path = evidence / 'integration-185/final-remote-snapshot.json'
        snapshot = read_json(snapshot_path)
        ancestors = set(checkout.git('rev-list', checkout.head).decode().splitlines())
        missing = [ref for ref in snapshot['refs'] if ref['sha'] not in ancestors]
        result['ancestry'] = {
            'snapshot': str(snapshot_path.relative_to(repo)),
            'snapshot_sha256': sha(snapshot_path.read_bytes()),
            'cutoff_utc': snapshot['recorded_at_utc'], 'counts': snapshot['counts'],
            'total': len(snapshot['refs']), 'included_count': len(snapshot['refs']) - len(missing),
            'missing_ancestors': missing,
            'passed': len(snapshot['refs']) == snapshot['total'] == 185 and not missing,
            'method': 'Exact pinned refs[].sha membership in git rev-list of the checked commit; no live refresh.'}
        final_changes = [path for path, before in checkout.worktree_hashes.items()
                         if sha(safe_path(repo, path).read_bytes()) != before]
        result['source_stable_during_verification'] = not final_changes
        result['changed_during_verification'] = final_changes
        result['current_checkout_head_matches_checked_commit'] = (
            checkout.git('rev-parse', 'HEAD').decode().strip() == checkout.head)
        result['current_qualified_test_total'] = sum(
            x['summary']['outcomes'].get('success', 0) for x in result['cohorts'].values())
        result['counting_scope'] = ('Three current package cohorts have distinct test files; '
                                  'historical overlapping runs and expected-failure baseline counts are not added.')
        result['passed'] = (all(x['passed'] for x in result['cohorts'].values())
                            and result['poppler']['passed'] and result['flutter_rendering']['passed']
                            and result['ancestry']['passed'] and result['source_stable_during_verification']
                            and result['current_checkout_head_matches_checked_commit'])
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        result['verification_error'] = str(error)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'passed': result['passed'], 'head': result.get('head'),
                      'test_total': result.get('current_qualified_test_total'),
                      'ancestry': result.get('ancestry', {}).get('included_count'),
                      'error': result.get('verification_error'), 'output': str(output)}))
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()

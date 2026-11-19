#!/usr/bin/env python3
"""Qualify the one-file language-ID fixture correction against a preserved run.

Requires the resolved Flutter/Dart environment used by the full run. This is an
audit continuation on the same checkout/runtime, not a substitute for full
qualification when other source or runtime inputs change. To replay elsewhere,
run the preserved run_final.py against the corrected source instead.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--previous', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--freeze', required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    previous = (args.previous or repo / 'docs/validation/mail-providers-20261119/final').resolve()
    output = (args.output or previous.parent / 'correction').resolve()
    spec = importlib.util.spec_from_file_location('previous_qualification_runner', previous / 'run_final.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    old_receipt = json.loads((previous / 'receipt.json').read_text())
    old_source = json.loads((previous / 'source-after.json').read_text())
    old_runtime = json.loads((previous / 'runtime-after.json').read_text())
    fixture_paths = [Path(path) for path in old_runtime if path.endswith('/language-id-fixture.so')]
    if len(fixture_paths) != 1:
        raise RuntimeError('Exactly one original synthetic native fixture is required')
    fixture = fixture_paths[0]
    runner = module.Runner(repo, output, fixture.parent, args.freeze)
    head = module.capture(['git', 'rev-parse', 'HEAD'], repo)
    if head != module.capture(['git', 'rev-parse', args.freeze + '^{commit}'], repo):
        raise RuntimeError('Corrected source freeze differs from HEAD')
    if old_receipt['status'] != 'failed':
        raise RuntimeError('Expected preserved original failed attempt')
    failures = [item['name'] for item in old_receipt['commands'] if not item['accepted']]
    if failures != ['language-id-synthetic']:
        raise RuntimeError('Only the diagnosed language-ID fixture gate may be replaced')
    if not all(old_receipt[key] for key in ('source_unchanged', 'runtime_unchanged',
                                           'lock_unchanged', 'source_head_unchanged', 'browser_closure_passed')):
        raise RuntimeError('Preserved original run has unrelated integrity failures')
    if module.sha(previous / 'run_final.py') != old_receipt['runner_sha256']:
        raise RuntimeError('Preserved qualification runner differs from recorded bytes')
    if output.exists() and any(output.iterdir()):
        raise RuntimeError('Correction output must be empty')
    selected = set(module.source_paths(repo))
    dirty = subprocess.check_output(['git', 'diff', '--name-only', 'HEAD', '-z'], cwd=repo).decode().split('\0')
    if selected.intersection(dirty):
        raise RuntimeError('Tracked source is dirty at corrective freeze')
    unknown = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '-z'], cwd=repo).decode().split('\0')
    if any(path.startswith(('packages/', 'third_party/', 'apps/', 'tool/', 'tools/')) and not path.endswith('.md') for path in unknown):
        raise RuntimeError('Untracked product/test files exist at corrective freeze')
    source_before = module.source_manifest(repo)
    source_delta = {
        path: {'previous': old_source.get(path), 'corrected': source_before.get(path)}
        for path in sorted(set(old_source) | set(source_before))
        if old_source.get(path) != source_before.get(path)
    }
    expected_path = 'packages/quds_language_id/test/language_id_unit_test.dart'
    if list(source_delta) != [expected_path]:
        raise RuntimeError('Correction must change only the diagnosed fixture test file')
    runtime_before = runner.runtime_manifest(fixture)
    if runtime_before != old_runtime:
        raise RuntimeError('Runtime changed since original full qualification')
    original_hash = module.sha(previous / 'receipt.json')
    output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(__file__, output / 'run_correction.py')
    runner.receipt.update(
        status='running', source_commit=head,
        source_tree=module.capture(['git', 'rev-parse', 'HEAD^{tree}'], repo),
        started_at_utc=module.now(), runner_sha256=module.sha(__file__),
        prior_runner_sha256=module.sha(previous / 'run_final.py'),
        previous_source_commit=old_receipt['source_commit'],
        previous_receipt_sha256=original_hash,
        cause='The calibrated incoming default is topK=5; a four-candidate overflow fixture had implicitly assumed topK=3.',
        correction='Set topK: 3 explicitly only in the existing malformed-candidate fixture loop; production default and guard unchanged.',
        source_file_count=len(source_before), source_before_sha256=module.manifest_digest(source_before),
        lock_sha256_before=module.sha(repo / 'pubspec.lock'),
        reused_gates=[item['name'] for item in old_receipt['commands'] if item['name'] != 'language-id-synthetic'],
        replaced_gate='language-id-synthetic')
    module.write(output / 'source-before.json', source_before)
    module.write(output / 'runtime-before.json', runtime_before)
    module.write(output / 'source-delta.json', source_delta)
    (output / 'source-diff.patch').write_bytes(subprocess.check_output([
        'git', 'diff', old_receipt['source_commit'], head, '--', expected_path], cwd=repo))
    runner.save()
    try:
        package = repo / 'packages/quds_language_id'
        runner.step('strict-corrected-format', [runner.dart, 'format', '--output=none',
            '--set-exit-if-changed', 'test/language_id_unit_test.dart'], cwd=package)
        runner.step('strict-language-id-analysis', [runner.dart, 'analyze', '--fatal-infos', '--fatal-warnings',
            'lib', 'test/language_id_unit_test.dart', 'test/language_id_native_transport_test.dart'], cwd=package)
        replacement = runner.step('language-id-synthetic', runner.test_command() + [
            'test/language_id_unit_test.dart', 'test/language_id_native_transport_test.dart'],
            cwd=package, kind='tests', environment={'QUDS_LANGUAGE_ID_FIXTURE_LIBRARY': str(fixture)})
        old_cases = json.loads((previous / 'language-id-synthetic/test-cases.json').read_text())
        new_cases = json.loads((output / 'language-id-synthetic/test-cases.json').read_text())
        case_keys = lambda cases: sorted((case['file'], case['name'], case['platform']) for case in cases['visible_cases'])
        same_cases = case_keys(old_cases) == case_keys(new_cases)
        reused = [item for item in old_receipt['commands'] if item['name'] != 'language-id-synthetic']
        counts = {key: sum(item.get('test_counts', {}).get(key, 0) for item in reused + [replacement])
                  for key in ('passed', 'failed', 'skipped')}
        runner.receipt.update(test_counts=replacement.get('test_counts'),
            combined_qualified_test_counts=counts, replacement_has_same_cases=same_cases,
            count_policy='Replace the complete old synthetic cohort with the corrected cohort once. No earlier development runs or superseded synthetic passes are added.')
    except BaseException as error:
        runner.receipt['runner_error'] = repr(error)
        raise
    finally:
        source_after = module.source_manifest(repo)
        runtime_after = runner.runtime_manifest(fixture)
        module.write(output / 'source-after.json', source_after)
        module.write(output / 'runtime-after.json', runtime_after)
        head_after = module.capture(['git', 'rev-parse', 'HEAD'], repo)
        original_unchanged = module.sha(previous / 'receipt.json') == original_hash
        accepted = (not runner.receipt.get('runner_error')
                    and len(runner.commands) == 3 and all(command['accepted'] for command in runner.commands)
                    and source_before == source_after and runtime_before == runtime_after
                    and head_after == head and original_unchanged
                    and runner.receipt.get('replacement_has_same_cases') is True)
        runner.receipt.update(status='passed' if accepted else 'failed', finished_at_utc=module.now(),
            source_after_sha256=module.manifest_digest(source_after), source_unchanged=source_before == source_after,
            runtime_unchanged=runtime_before == runtime_after, runtime_matches_previous=runtime_before == old_runtime,
            runtime_manifest_sha256=module.manifest_digest(runtime_before),
            source_head_unchanged=head_after == head, checkout_head_after=head_after,
            lock_sha256_after=module.sha(repo / 'pubspec.lock'),
            lock_unchanged=runner.receipt['lock_sha256_before'] == module.sha(repo / 'pubspec.lock'),
            previous_receipt_unchanged=original_unchanged,
            unchanged_source_except_explicit_fixture=list(source_delta) == [expected_path])
        runner.save()
        print(json.dumps({'final': runner.receipt['status'], 'counts': runner.receipt.get('test_counts'),
                          'combined_qualified_counts': runner.receipt.get('combined_qualified_test_counts'),
                          'output': str(output)}), flush=True)
    return 0 if runner.receipt['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())

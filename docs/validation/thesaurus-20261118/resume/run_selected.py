#!/usr/bin/env python3
"""Run one source-bound local cohort; source zotero-toolchain/env.sh first.

No dependency resolution, model acquisition, GitHub Actions or browser execution
is performed. Select one cohort at a time to keep Flutter SDK access sequential.
"""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urljoin, urlparse

COHORTS = {
    'engine': ('quds_office_engine', '''office_thesaurus_test.dart
        word_proofing_inheritance_test.dart word_zotero_note_insertion_test.dart
        word_zotero_caret_test.dart word_zotero_citing_test.dart
        word_zotero_preference_flow_test.dart word_zotero_style_preferences_review_test.dart
        word_zotero_scaling_test.dart'''.split()),
    'editor-zotero': ('quds_office_editor', '''word_zotero_citing_controller_test.dart
        word_zotero_citing_dialog_test.dart word_zotero_field_at_caret_test.dart
        word_notes_editing_test.dart'''.split()),
    'spacy': ('quds_proofing_spacy', '''language_catalog_test.dart bundle_test.dart
        analysis_test.dart worker_test.dart distribution_test.dart grammar_provider_test.dart'''.split()),
    'studio': ('quds_office_editor/example', '''studio_review_pane_test.dart
        studio_comment_review_test.dart studio_linguistic_analysis_test.dart
        studio_spacy_setup_test.dart studio_zotero_citing_transport_test.dart'''.split()),
}


def utc():
    return datetime.now(timezone.utc).isoformat()


def record_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return {'bytes': path.stat().st_size, 'sha256': digest.hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cohort', choices=['static', *COHORTS, 'web-import'], required=True)
    args = parser.parse_args()
    task, output = args.root.resolve(), args.output.resolve()
    repo, workspace, runtime = (task / name for name in
                                ('quds_office_suite', 'zotero-validation', 'zotero-toolchain'))
    if output.exists() and any(output.iterdir()):
        parser.error('Choose a fresh output directory; existing evidence is never overwritten.')
    output.mkdir(parents=True, exist_ok=True)
    logs = output / 'logs'
    logs.mkdir()
    sdk = runtime / 'flutter-sdk'
    dart, flutter = str(sdk / 'bin/cache/dart-sdk/bin/dart'), str(sdk / 'bin/flutter')
    config = workspace / '.dart_tool/package_config.json'
    fixture = repo / 'docs/validation/thesaurus-20261118/continuation/local/fixtures'
    targets_file = Path(__file__).with_name('dart-final-targets.json')
    audit_file = repo / 'docs/validation/zotero-citation-workflow-20261118/editor/run_editor_zotero.py'
    env = os.environ.copy()

    def git(*command):
        return subprocess.check_output(['git', *command], cwd=repo, text=True).strip()

    def snapshot():
        tracked = git('ls-files', '-z').split('\0')
        selected = {'.fvmrc', 'pubspec.yaml', 'analysis_options.yaml'}
        for name in tracked:
            parts = Path(name).parts
            if parts and parts[0] in ('packages', 'apps') and (
                any(part in ('lib', 'test', 'assets', 'fonts', 'web', 'tool', 'bin') for part in parts[2:])
                or parts[-1] in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')):
                selected.add(name)
        files = {name: repo / name for name in selected}
        files.update({str(path.relative_to(repo)): path for path in fixture.rglob('*')
                      if path.is_file() and path.suffix in ('.dart', '.py')})
        for path in (Path(__file__).resolve(), targets_file, audit_file):
            files[str(path.relative_to(repo))] = path
        files.update({'__workspace_lock__': workspace / 'pubspec.lock',
                      '__workspace_package_config__': config,
                      '__runtime_ready__': runtime / 'runtime-ready.json'})
        return {name: record_file(path) for name, path in sorted(files.items())}

    receipt = {'cohort': args.cohort, 'started_at_utc': utc(), 'source_sha': git('rev-parse', 'HEAD'),
               'runs': [], 'status': 'running', 'github_actions_used': False,
               'browser_executed': False, 'model_downloads_requested': False}

    def write():
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def run(name, command, cwd):
        print('START ' + name, flush=True)
        started = time.monotonic()
        stdout, stderr = logs / (name + '.stdout'), logs / (name + '.stderr')
        code, error = None, None
        try:
            with stdout.open('wb') as out, stderr.open('wb') as err:
                code = subprocess.run(command, cwd=cwd, env=env, stdout=out,
                                      stderr=err, timeout=900).returncode
        except (OSError, subprocess.TimeoutExpired) as exception:
            error = repr(exception)
        item = {'name': name, 'command': command, 'cwd': str(cwd), 'exit_code': code,
                'seconds': time.monotonic() - started, 'error': error,
                'stdout': str(stdout.relative_to(output)), 'stderr': str(stderr.relative_to(output)),
                'stdout_sha256': record_file(stdout)['sha256'],
                'stderr_sha256': record_file(stderr)['sha256']}
        receipt['runs'].append(item)
        write()
        print('END ' + name + ' ' + json.dumps({'exit_code': code, 'seconds': item['seconds']}), flush=True)
        return code

    before = None
    try:
        write()
        if Path(env.get('FLUTTER_ROOT', '')).resolve() != sdk:
            raise RuntimeError('Source zotero-toolchain/env.sh before running this gate.')
        before = snapshot()
        receipt['source_files'] = len(before)
        receipt['input_digest'] = hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest()
        with gzip.open(output / 'source-inputs.json.gz', 'wt') as stream:
            json.dump(before, stream, indent=2, sort_keys=True)
        if args.cohort == 'static':
            targets = json.loads(targets_file.read_text())
            if len(targets) != 58 or len(set(targets)) != 58 or any(
                Path(path).is_absolute() or '..' in Path(path).parts
                or not path.endswith('.dart') or not (repo / path).is_file() for path in targets):
                raise ValueError('Expected the 58 unique existing repository Dart targets.')
            receipt['targets'] = targets
            codes = [run('format', [dart, 'format', '--output=none', '--set-exit-if-changed', *targets], repo),
                     run('analysis', [flutter, 'analyze', '--no-pub', '--fatal-infos', *targets], repo)]
            if any(code != 0 for code in codes):
                raise RuntimeError('Static validation failed; inspect both command logs.')
        elif args.cohort == 'web-import':
            source = workspace / 'packages/quds_office_editor/example/test/studio_spacy_web_import_gate.dart'
            artifact = output / 'studio-spacy-web.js'
            if run('web-compile', [dart, 'compile', 'js', '-O1', '--csp', '--packages=' + str(config),
                                   '-o', str(artifact), str(source)], workspace) != 0:
                raise RuntimeError('Browser-safe import compilation failed.')
            receipt['artifact'] = dict(path=artifact.name, **record_file(artifact))
            if run('node-import', ['node', '-e', 'global.self=globalThis;require(process.argv[1]);',
                                   str(artifact)], workspace) != 0:
                raise RuntimeError('Browser-safe import Node check failed.')
        else:
            package, names = COHORTS[args.cohort]
            cwd = workspace / 'packages' / package
            tests = ['test/' + name for name in names]
            if args.cohort in ('engine', 'spacy'):
                packages = json.loads(config.read_text())['packages']
                test_package = next(item for item in packages if item['name'] == 'test')
                uri = urlparse(urljoin(config.as_uri(), test_package['rootUri']))
                if uri.scheme != 'file':
                    raise ValueError('The test runner must come from the resolved local cache.')
                runner = Path(unquote(uri.path)) / 'bin/test.dart'
                command = [dart, '--disable-dart-dev', '--packages=' + str(config), str(runner)]
            else:
                command = [flutter, 'test', '--no-pub']
            code = run('tests', [*command, '--concurrency=1', '--reporter', 'json', *tests], cwd)
            spec = importlib.util.spec_from_file_location('event_audit', audit_file)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            audit = module.audit_events(logs / 'tests.stdout')
            (output / 'test-audit.json').write_text(json.dumps(audit, indent=2) + '\n')
            expected = {str((cwd / path).resolve()) for path in tests}
            actual = {str((cwd / suite['path']).resolve()) for suite in audit['suites']}
            guards = {'exit_success': code == 0,
                      'all_selected_suites_executed': actual == expected and len(audit['suites']) == len(tests),
                      'nonempty_cases': audit['passed'] > 0,
                      'no_failed_or_skipped_cases': audit['failed'] == 0 and audit['skipped'] == 0,
                      'every_started_test_finished_once': audit['every_started_test_finished_once'],
                      'final_event_success': len(audit['final_events']) == 1
                                             and audit['final_events'][0].get('success') is True,
                      'clean_event_stream': not any(audit[key] for key in (
                          'error_events', 'parse_errors', 'excluded_failures', 'layout_or_tap_diagnostics'))}
            receipt['test_audit'] = {key: audit[key] for key in ('passed', 'failed', 'skipped', 'suite_count')}
            receipt['acceptance_guards'] = guards
            if not all(guards.values()):
                raise RuntimeError('Test audit failed: ' + ', '.join(key for key, ok in guards.items() if not ok))
        receipt['status'] = 'passed'
    except BaseException as error:
        receipt.update(status='failed', error=repr(error))
    finally:
        if before is not None:
            try:
                after = snapshot()
                receipt['output_digest'] = hashlib.sha256(json.dumps(after, sort_keys=True).encode()).hexdigest()
                with gzip.open(output / 'source-after.json.gz', 'wt') as stream:
                    json.dump(after, stream, indent=2, sort_keys=True)
                receipt['source_unchanged'] = before == after
                receipt['changed_inputs'] = sorted(name for name in before.keys() | after.keys()
                                                  if before.get(name) != after.get(name))
                if before != after:
                    receipt.update(status='failed', error='Source or runtime inputs changed during validation.')
            except BaseException as error:
                receipt.update(status='failed', source_unchanged=False, final_snapshot_error=repr(error))
        receipt['source_sha_after'] = git('rev-parse', 'HEAD')
        receipt['finished_at_utc'] = utc()
        write()
        print(json.dumps({'status': receipt['status'], 'error': receipt.get('error')}), flush=True)
    return 0 if receipt['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Run final ODT/ODP regression cohorts locally with source and runtime receipts."""
import argparse
import datetime
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

REPO = Path(__file__).resolve().parents[3]
OUTPUT = Path(__file__).resolve().parent / 'qualification'
RUNTIME = Path('/home/agent/.codex/skills/remote-skills/.quds-gector-work/runtime')
LOCK = REPO / 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
spec = importlib.util.spec_from_file_location(
    'prior_harness', REPO / 'docs/validation/office-fidelity-continuation-20261117/validate.py')
assert spec is not None and spec.loader is not None
prior = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prior)

ENGINE = ['odt_document_writer_test.dart', 'odt_structure_fidelity_test.dart', 'odt_table_merge_test.dart', 'odt_paragraph_properties_test.dart', 'odt_header_footer_fidelity_test.dart', 'odt_note_fidelity_test.dart', 'odt_comment_fidelity_test.dart', 'odt_list_fidelity_test.dart', 'odt_section_fidelity_test.dart', 'odf_export_text_fidelity_test.dart', 'odp_transform_fidelity_test.dart', 'odp_table_fidelity_test.dart', 'odp_presentation_writer_test.dart', 'odf_annotation_extraction_test.dart', 'odf_covered_cell_extraction_test.dart', 'office_search_fidelity_test.dart', 'word_note_numbering_test.dart']
NODE = ['odt_list_fidelity_test.dart', 'odt_section_fidelity_test.dart', 'odt_note_fidelity_test.dart', 'odt_comment_fidelity_test.dart', 'odp_transform_fidelity_test.dart', 'odt_paragraph_properties_test.dart']
COHORTS = {'odt-vm': ('quds_office_engine', ENGINE), 'odt-node': ('quds_office_engine', NODE)}

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def source_manifest():
    paths = {Path(__file__), Path(prior.__file__), LOCK, REPO / 'pubspec.lock',
             REPO / '.dart_tool/package_config.json'}
    for package in ['quds_office_engine', 'quds_office_editor', 'legacy_doc_parser',
                    'quds_proofing_harper', 'quds_proofing_gector', 'quds_reports']:
        root = REPO / 'packages' / package
        for directory in ['lib', 'assets', 'fonts', 'templates', 'third_party', 'test', 'example/fonts']:
            paths.update(prior.tree_files(root / directory))
        paths.update(root.glob('pubspec.*'))
        paths.update(root.glob('analysis_options.yaml'))
        paths.update(root.glob('dart_test.yaml'))
    paths.update(REPO.glob('pubspec.*'))
    paths.update(REPO.glob('analysis_options.yaml'))
    return {str(p.relative_to(REPO)): digest(p) for p in sorted(paths) if p.is_file()}

def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('cohort', choices=COHORTS)
    parser.add_argument('--source', required=True, help='Exact published source commit')
    args = parser.parse_args()
    package_name, tests = COHORTS[args.cohort]
    package = REPO / 'packages' / package_name
    output = OUTPUT / args.cohort
    output.mkdir(parents=True, exist_ok=False)
    flutter = RUNTIME / 'flutter-sdk'
    os.environ.update(FLUTTER_ROOT=str(flutter), PUB_CACHE=str(RUNTIME / 'pub-cache'),
                      CI='true', DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true',
                      XDG_CONFIG_HOME=str(REPO.parent / 'final-runtime/config'),
                      TMPDIR=str(REPO.parent / 'final-runtime/tmp'))
    os.environ['PATH'] = str(flutter / 'bin') + os.pathsep + os.environ['PATH']
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()
    if head != args.source or digest(REPO / 'pubspec.lock') != digest(LOCK):
        raise RuntimeError('Integrated source or enforced lock does not match')
    Path(os.environ['TMPDIR']).mkdir(parents=True, exist_ok=True)
    Path(os.environ['XDG_CONFIG_HOME']).mkdir(parents=True, exist_ok=True)
    versions = prior.version_identity(output, 'flutter', include_node=True)
    version = versions['flutter']['metadata']
    if (version.get('frameworkVersion') != '3.47.8'
            or version.get('dartSdkVersion') != '3.13.7'
            or version.get('frameworkRevision') != '737ba8f885dc774b53b442759999a312c9461e4e'):
        raise RuntimeError('Unexpected Flutter/Dart runtime identity')
    before = source_manifest()
    runtime_before = prior.runtime_identity(output / 'runtime-before.json.gz', include_node=True)
    receipt = {'started_utc': now(), 'source_commit': head, 'cohort': args.cohort,
               'tests': tests, 'test_file_count': len(tests), 'versions': versions,
               'source_before': before, 'runtime_before': runtime_before,
               'lock_sha256': digest(LOCK), 'commands': [],
               'scope': 'ODT section/list changes and adjacent ODF/ODP regression cohorts; Node repeats selected VM cases.',
               'github_actions': 'Not queried or awaited.'}
    write_json(output / 'receipt.json', receipt)
    analysis = ['lib/src/word/serial/odt_document_writer.dart'] + ['test/' + t for t in tests]
    formatting = analysis
    commands = [('analyze', ['dart', 'analyze', '--fatal-infos'] + analysis),
                ('format', ['dart', 'format', '--output=none', '--set-exit-if-changed'] + formatting)]
    test_base = (['dart', 'test', '--platform', 'node'] if args.cohort == 'odt-node'
                 else ['dart', 'test'])
    batches = [tests[i:i + 3] for i in range(0, len(tests), 3)]
    for index, batch in enumerate(batches):
        commands.append((f'test-{index + 1}', test_base + ['--concurrency=2', '--reporter=json']
                         + ['test/' + t for t in batch]))
    for name, command in commands:
        command[0] = str(Path(shutil.which(command[0])).absolute())
        start = time.monotonic()
        print(json.dumps({'cohort': args.cohort, 'command': name, 'status': 'running'}), flush=True)
        item = {'name': name, 'command': command, 'cwd': str(package), 'started_utc': now()}
        executable_before = digest(Path(command[0]))
        stdout = output / (name + '.stdout')
        stderr = output / (name + '.stderr')
        timeout = 180 if name == 'format' else 600
        with stdout.open('wb') as out, stderr.open('wb') as err:
            process = subprocess.Popen(command, cwd=package, stdout=out, stderr=err)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                code = 124
                item['timed_out'] = True
        raw = stdout.read_bytes()
        item.update(exit_code=code, finished_utc=now(), duration_seconds=time.monotonic() - start,
                    executable_before_sha256=executable_before,
                    executable_after_sha256=digest(Path(command[0])))
        for channel in ['stdout', 'stderr']:
            path = output / (name + '.' + channel)
            data = path.read_bytes()
            (output / (path.name + '.gz')).write_bytes(gzip.compress(data, mtime=0))
            item[channel] = path.name + '.gz'
            item[channel + '_sha256'] = hashlib.sha256(data).hexdigest()
            path.unlink()
        if name.startswith('test-'):
            batch = batches[int(name.split('-')[1]) - 1]
            item['tests'] = batch
            item['summary'] = prior.summarize_events(raw)
            item['event_integrity'] = prior.event_integrity(raw, package, batch)
            summary = item['summary']
            expected = []
            item['expected_skips'] = expected
            item['passed_with_recorded_scope'] = (code == 0 and item['event_integrity']['passed']
                and summary['runner_success'] and not summary['failures'] and not summary['errors']
                and summary['skipped'] == expected)
        else:
            item['passed_with_recorded_scope'] = code == 0
        receipt['commands'].append(item)
        write_json(output / 'receipt.json', receipt)
        print(json.dumps({'cohort': args.cohort, 'command': name, 'exit_code': code,
                          'summary': item.get('summary')}), flush=True)
    after = source_manifest()
    runtime_after = prior.runtime_identity(output / 'runtime-after.json.gz', include_node=True)
    receipt.update(finished_utc=now(), source_after=after, runtime_after=runtime_after,
                   source_unchanged=before == after, runtime_unchanged=runtime_before == runtime_after,
                   lock_unchanged=digest(REPO / 'pubspec.lock') == digest(LOCK),
                   head_unchanged=head == subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip())
    receipt['passed_with_recorded_scope'] = (all(c['passed_with_recorded_scope'] for c in receipt['commands'])
        and receipt['source_unchanged'] and receipt['runtime_unchanged']
        and receipt['lock_unchanged'] and receipt['head_unchanged'])
    write_json(output / 'receipt.json', receipt)
    print(json.dumps({k: receipt[k] for k in ['cohort', 'passed_with_recorded_scope', 'source_unchanged', 'runtime_unchanged']}), flush=True)
    return 0 if receipt['passed_with_recorded_scope'] else 1

if __name__ == '__main__':
    raise SystemExit(main())

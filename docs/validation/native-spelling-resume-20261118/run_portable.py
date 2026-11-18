#!/usr/bin/env python3
"""Run the pinned spelling panel and strict checks in a resolved local workspace.

The caller supplies the source repository, immutable source commit, resolved
workspace, restored Flutter SDK and output locations. This runner performs no
dependency resolution, network access, GitHub operations or product edits.
Compiled artifacts are kept separately from the compact evidence directory.
"""

import argparse
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import urllib.parse


TARGETS = [
    'packages/quds_office_engine/lib/src/proofing/german_spelling.dart',
    'packages/quds_office_engine/test/proofing/german_spelling_projection_test.dart',
    'packages/quds_office_engine/tool/check_native_spelling.dart',
    'packages/quds_office_editor/lib/src/proofing/platform_spelling_provider.dart',
    'packages/quds_office_editor/test/platform_spelling_identifiers_test.dart',
    'packages/quds_office_editor/test/platform_spelling_identifier_review_test.dart',
    'packages/quds_office_editor/test/platform_spelling_vocabulary_unicode_test.dart',
]


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def put(path, value):
    payload = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.name.endswith('.gz'):
        path.write_bytes(gzip.compress(payload, mtime=0))
    else:
        path.write_bytes(payload)


def snapshot(paths):
    return {str(path): {'sha256': sha256(path), 'bytes': path.stat().st_size}
            for path in paths}


def changed(before, after):
    return sorted(key for key in before.keys() | after.keys()
                  if before.get(key) != after.get(key))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--workspace', required=True, type=Path)
    parser.add_argument('--flutter', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--checks-output', required=True, type=Path)
    parser.add_argument('--artifacts', required=True, type=Path)
    parser.add_argument('--case-count', type=int, default=48)
    args = parser.parse_args()
    repo, workspace, flutter = (args.repo.resolve(), args.workspace.resolve(),
                                args.flutter.resolve())
    out, checks, artifacts = (args.output.resolve(), args.checks_output.resolve(),
                              args.artifacts.resolve())
    for path in (out, checks, artifacts):
        if path.exists() and any(path.iterdir()):
            raise SystemExit(f'Output must be empty to retain prior attempts: {path}')
        path.mkdir(parents=True, exist_ok=True)
    sdk = flutter / 'bin/cache/dart-sdk'
    dart, node = sdk / 'bin/dart', Path(shutil.which('node')).resolve()
    engine = workspace / 'packages/quds_office_engine'
    panel = engine / 'tool/check_native_spelling.dart'
    config = workspace / '.dart_tool/package_config.json'
    graph_path = workspace / '.dart_tool/package_graph.json'
    graph = json.loads(graph_path.read_text())
    entries = json.loads(config.read_text())['packages']
    inputs = {config, graph_path, workspace / 'pubspec.lock'}
    inputs.update(workspace / target for target in TARGETS)
    package_roots = {}
    for entry in entries:
        uri = urllib.parse.urljoin(config.as_uri(), entry['rootUri'])
        parsed = urllib.parse.urlparse(uri)
        if parsed.scheme != 'file':
            raise ValueError(f'Unsupported package URI: {uri}')
        root = Path(urllib.parse.unquote(parsed.path)).resolve()
        package_roots[entry['name']] = str(root)
        inputs.add(root / 'pubspec.yaml')
        inputs.update(path for path in (root / entry['packageUri']).rglob('*')
                      if path.suffix in ('.dart', '.yaml', '.json'))
    inputs.update(workspace.rglob('analysis_options.yaml'))
    inputs = sorted({path.resolve() for path in inputs if path.is_file()})
    runtime = {dart, node, sdk / 'version', sdk / 'revision',
               sdk / 'lib/libraries.json'}
    runtime.update(sdk / name for name in (
        'bin/dartvm', 'bin/dartaotruntime', 'bin/utils/gen_snapshot'))
    runtime.update((sdk / 'bin/snapshots').glob('*.snapshot'))
    runtime.update((sdk / 'lib').rglob('*.dart'))
    runtime.update((sdk / 'lib').rglob('*.dill'))
    runtime = sorted({path.resolve() for path in runtime if path.is_file()})

    # Bind every selected workspace input that exists in Git to an immutable
    # source blob. Config/lock files produced during restoration are recorded
    # separately rather than misrepresented as tracked source.
    tree_raw = subprocess.check_output(
        ['git', 'ls-tree', '-rz', args.source_commit], cwd=repo)
    tree = {}
    for record in tree_raw.split(b'\0'):
        if not record:
            continue
        metadata, relative = record.split(b'\t', 1)
        mode, kind, blob = metadata.decode().split()
        if kind == 'blob':
            tree[relative.decode()] = blob
    source_bound = {}
    generated_inputs = []
    for path in inputs:
        # The resolved workspace can deliberately link its library and test
        # files to the source checkout. Bind canonical paths in either root.
        if path.is_relative_to(workspace):
            relative = path.relative_to(workspace).as_posix()
        elif path.is_relative_to(repo):
            relative = path.relative_to(repo).as_posix()
        else:
            continue
        data = path.read_bytes()
        actual = hashlib.sha1(
            b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if relative in tree:
            source_bound[relative] = {
                'expected_git_blob': tree[relative], 'actual_git_blob': actual,
                'matches': actual == tree[relative], 'actual_path': str(path),
                'sha256': hashlib.sha256(data).hexdigest(),
            }
        else:
            generated_inputs.append(relative)
    source_ok = bool(source_bound) and all(
        entry['matches'] for entry in source_bound.values())
    before, runtime_before = snapshot(inputs), snapshot(runtime)
    put(out / 'inputs-before.json.gz', before)
    put(out / 'runtime-before.json.gz', runtime_before)
    put(out / 'source-binding.json', {
        'source_commit': args.source_commit, 'workspace': str(workspace),
        'tracked_input_count': len(source_bound),
        'all_tracked_inputs_match': source_ok, 'inputs': source_bound,
        'generated_workspace_inputs': generated_inputs,
    })
    put(out / 'environment.json', {
        'workspace_package_count': len(graph['packages']),
        'resolved_package_count': len(entries), 'package_roots': package_roots,
        'source_inputs': len(inputs), 'runtime_inputs': len(runtime),
        'dart': subprocess.check_output(
            [str(dart), '--version'], stderr=subprocess.STDOUT, text=True).strip(),
        'node': subprocess.check_output([str(node), '--version'], text=True).strip(),
        'environment': {key: os.environ.get(key) for key in (
            'PUB_CACHE', 'FLUTTER_ROOT', 'TMPDIR', 'XDG_CONFIG_HOME',
            'DASH__SUPPRESS_ANALYTICS', 'DART_SUPPRESS_ANALYTICS',
            'FLUTTER_SUPPRESS_ANALYTICS', 'CI')},
        'runner': {'path': str(Path(__file__).resolve()),
                   'sha256': sha256(Path(__file__).resolve())},
    })
    if not source_ok:
        raise SystemExit('Workspace input differs from requested source commit.')

    commands = {}

    def run(label, arguments, directory, destination, stdout_name=None):
        arguments = [str(argument) for argument in arguments]
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        begin = time.monotonic()
        stdout_path = destination / (stdout_name or label + '.stdout.log')
        stderr_path = destination / (label + '.stderr.log')
        with stdout_path.open('wb') as stdout, stderr_path.open('wb') as stderr:
            process = subprocess.run(arguments, cwd=directory,
                                     stdout=stdout, stderr=stderr)
        receipt = {
            'args': arguments, 'cwd': str(directory),
            'exit_code': process.returncode, 'started_at_utc': started,
            'seconds': round(time.monotonic() - begin, 3),
            'stdout': stdout_path.name, 'stderr': stderr_path.name,
        }
        commands[label] = receipt
        put(destination / (label + '.command.json'), receipt)
        print(f'{label}: exit {process.returncode}', flush=True)
        return process.returncode

    native, javascript = artifacts / 'spelling-smoke', artifacts / 'spelling-smoke.js'
    outcomes = {}
    outcomes['vm'] = run('vm', [dart, f'--packages={config}', panel],
                         engine, out, 'vm.json')
    outcomes['compile-native'] = run(
        'compile-native', [dart, 'compile', 'exe', panel, '-o', native], engine, out)
    if outcomes['compile-native'] == 0:
        outcomes['native'] = run('native', [native], engine, out, 'native.json')
    outcomes['compile-js'] = run(
        'compile-js', [dart, 'compile', 'js', '-O2', panel, '-o', javascript],
        engine, out)
    if outcomes['compile-js'] == 0:
        outcomes['js'] = run(
            'js', [node, '-e',
                   'globalThis.self = globalThis; require(process.argv[1]);',
                   javascript], engine, out, 'js.json')

    depfile = artifacts / 'spelling-smoke.js.deps'
    dependencies, uncovered = [], []
    if depfile.exists():
        shutil.copyfile(depfile, out / 'compiler-js.dependencies.txt')
        for uri in depfile.read_text().splitlines():
            parsed = urllib.parse.urlparse(uri)
            if parsed.scheme == 'file':
                path = Path(urllib.parse.unquote(parsed.path)).resolve()
            elif parsed.scheme == 'org-dartlang-sdk':
                path = (sdk / urllib.parse.unquote(parsed.path).lstrip('/')).resolve()
            else:
                uncovered.append(uri)
                continue
            dependencies.append(str(path))
            if str(path) not in before and str(path) not in runtime_before:
                uncovered.append(uri)
    coverage = {
        'scope': 'URI dependencies emitted by the JavaScript compiler; '
                 'the AOT compiler emits no dependency list in this command.',
        'dependency_file_present': depfile.exists(),
        'dependency_count': len(dependencies),
        'all_bound_before_run': bool(dependencies) and not uncovered,
        'uncovered_dependencies': uncovered,
        'sdk_uri_mapping': 'org-dartlang-sdk:///lib/... maps to SDK root/lib/...',
    }
    put(out / 'compiler-dependency-coverage.json', coverage)

    after_portable, runtime_after_portable = snapshot(inputs), snapshot(runtime)
    put(out / 'inputs-after.json.gz', after_portable)
    put(out / 'runtime-after.json.gz', runtime_after_portable)
    output_bytes, parsed_outputs, parse_errors = {}, {}, {}
    for label in ('vm', 'native', 'js'):
        path = out / (label + '.json')
        if not path.is_file():
            parse_errors[label] = 'Output is absent.'
            continue
        output_bytes[label] = path.read_bytes()
        try:
            parsed_outputs[label] = json.loads(output_bytes[label])
        except (ValueError, UnicodeError) as error:
            parse_errors[label] = str(error)
    output_summary = {}
    for label, value in parsed_outputs.items():
        cases = value.get('cases', [])
        output_summary[label] = {
            'bytes': len(output_bytes[label]),
            'sha256': hashlib.sha256(output_bytes[label]).hexdigest(),
            'case_count': value.get('caseCount'), 'failed': value.get('failed'),
            'actual_case_count': len(cases),
            'unique_case_ids': len({case['id'] for case in cases}),
            'all_accepted': all(case.get('accepted') is True for case in cases),
        }
    byte_identical = len(output_bytes) == 3 and len(set(output_bytes.values())) == 1
    structurally_identical = (len(parsed_outputs) == 3 and
                             parsed_outputs['vm'] == parsed_outputs['native'] == parsed_outputs['js'])
    accepted = (set(outcomes) == {'vm', 'compile-native', 'native', 'compile-js', 'js'}
                and all(code == 0 for code in outcomes.values())
                and byte_identical and structurally_identical
                and before == after_portable and runtime_before == runtime_after_portable
                and coverage['all_bound_before_run'] and not parse_errors
                and len(output_summary) == 3
                and all(summary['case_count'] == args.case_count
                        and summary['actual_case_count'] == args.case_count
                        and summary['unique_case_ids'] == args.case_count
                        and summary['failed'] == 0 and summary['all_accepted']
                        for summary in output_summary.values()))
    portable_result = {
        'schema': 'quds.native_spelling_resume.portable.v1',
        'status': 'passed' if accepted else 'failed',
        'source_commit': args.source_commit, 'commands': dict(commands),
        'source_inputs': len(inputs), 'runtime_inputs': len(runtime),
        'source_inputs_unchanged': before == after_portable,
        'runtime_inputs_unchanged': runtime_before == runtime_after_portable,
        'changed_inputs': changed(before, after_portable),
        'changed_runtime': changed(runtime_before, runtime_after_portable),
        'byte_identical': byte_identical,
        'structurally_identical': structurally_identical,
        'compiler_dependencies_bound_before_run': coverage['all_bound_before_run'],
        'parse_errors': parse_errors, 'outputs': output_summary,
        'compiled_artifacts': {
            path.name: {'sha256': sha256(path), 'bytes': path.stat().st_size}
            for path in (native, javascript) if path.exists()},
        'limits': [
            'Finite 48-case authored spelling panel; not a general quality estimate.',
            'JavaScript executed in Node with globalThis.self binding, not a browser.',
            'No physical native dictionary or full application build acceptance.',
            'Compiled artifacts stay in scratch; source runner is retained.',
            'No GitHub Actions, workflow, check or CI-status operation.',
        ],
    }
    put(out / 'verification.json', portable_result)

    # Strict analyzer and declared-language formatting are read-only. Their
    # guards include all resolved package libraries, SDK compiler/analyzer
    # snapshots, and exact configuration rather than just the edited files.
    put(checks / 'inputs-before.json.gz', after_portable)
    put(checks / 'runtime-before.json.gz', runtime_after_portable)
    check_outcomes = {}
    for index, target in enumerate(TARGETS):
        label = f'analyze-{index:02d}'
        check_outcomes[label] = run(
            label, [dart, f'--packages={config}', 'analyze', '--fatal-infos',
                    workspace / target],
            workspace, checks)
    check_outcomes['format'] = run(
        'format', [dart, 'format', '--output=none', '--set-exit-if-changed',
                   '--language-version=3.12', *[workspace / target for target in TARGETS]],
        workspace, checks)
    check_after, check_runtime_after = snapshot(inputs), snapshot(runtime)
    put(checks / 'inputs-after.json.gz', check_after)
    put(checks / 'runtime-after.json.gz', check_runtime_after)
    checks_passed = (all(code == 0 for code in check_outcomes.values())
                     and after_portable == check_after
                     and runtime_after_portable == check_runtime_after)
    check_result = {
        'schema': 'quds.native_spelling_resume.strict_checks.v1',
        'status': 'passed' if checks_passed else 'failed',
        'source_commit': args.source_commit,
        'source_binding': '../portable/source-binding.json',
        'targets': TARGETS, 'declared_language_version': '3.12',
        'commands': {label: commands[label] for label in check_outcomes},
        'source_inputs': len(inputs), 'runtime_inputs': len(runtime),
        'source_inputs_unchanged': after_portable == check_after,
        'runtime_inputs_unchanged': runtime_after_portable == check_runtime_after,
        'changed_inputs': changed(after_portable, check_after),
        'changed_runtime': changed(runtime_after_portable, check_runtime_after),
    }
    put(checks / 'verification.json', check_result)
    print(json.dumps({'portable': portable_result['status'],
                      'checks': check_result['status'],
                      'outputs': output_summary}, indent=2), flush=True)
    return 0 if accepted and checks_passed else 1


if __name__ == '__main__':
    raise SystemExit(main())

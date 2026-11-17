#!/usr/bin/env python3
"""Independently audit local qualification, without importing its runner.

Run after all four cohorts finish, with their runtime still materialized::

    python3 docs/validation/office-fidelity-resume-20261117/verify_receipts.py \
      --evidence /absolute/path/to/final --source <published-commit>

The requested source may be a documentation/evidence successor of the tested
commit. Every recorded tracked input must have identical bytes in both trees
and in the current checkout. Ignored activation files are checked separately.
This audit makes no network requests and does not query GitHub CI.
"""
from __future__ import annotations

import argparse
import ast
import collections
import datetime
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
from urllib.parse import unquote, urljoin, urlparse


REPO = Path(__file__).resolve().parents[3]
HARNESS = 'docs/validation/office-fidelity-continuation-20261117/validate.py'
INCOMING = 'docs/validation/office-fidelity-resume-20261117/incoming'
LOCK = 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock'
LOCK_SHA256 = '344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130'
FRAMEWORK = '737ba8f885dc774b53b442759999a312c9461e4e'
ENGINE = 'cf636b1dfb818dd6a3ff16e390e93b1a036969c8'
PINNED_EXECUTABLES = {
    'bin/cache/dart-sdk/bin/dart':
        '01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb',
    'bin/cache/artifacts/engine/linux-x64/flutter_tester':
        '800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f',
}
PACKAGES = {'engine': 'quds_office_engine', 'editor': 'quds_office_editor',
            'harper': 'quds_proofing_harper', 'node': 'quds_office_engine'}
ACTIVATION_FILES = {'.dart_tool/package_config.json', 'pubspec.lock'}
SOURCE_DIRECTORIES = ('lib', 'assets', 'fonts', 'templates', 'third_party',
                      'test/fixtures', 'test/support', 'test/goldens',
                      'example/fonts')
SDK_DIRECTORIES = ('bin/internal', 'bin/cache/dart-sdk', 'bin/cache/artifacts',
                   'packages/flutter/lib', 'packages/flutter_test/lib',
                   'packages/flutter_tools/lib', 'packages/flutter_tools/bin')


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO)


def relative_path(value):
    path = PurePosixPath(value)
    require(not path.is_absolute() and '..' not in path.parts and value,
            'Unsafe repository/evidence path: ' + repr(value))
    return str(path)


def files_under(path):
    if path.is_file():
        return {path}
    return {p for p in path.rglob('*') if p.is_file()} if path.is_dir() else set()


def package_roots(config):
    result = {}
    for item in json.loads(config.read_bytes())['packages']:
        root_url = urljoin(config.as_uri(), item['rootUri'])
        parsed = urlparse(root_url)
        require(parsed.scheme == 'file', 'Non-file package root: ' + root_url)
        root = Path(unquote(parsed.path)).resolve()
        library_url = urljoin(root.as_uri().rstrip('/') + '/',
                              item.get('packageUri', 'lib/'))
        result[item['name']] = (root, Path(unquote(urlparse(library_url).path)))
    return result


class Audit:
    """Cache identical file/blob checks across cohorts without trusting receipts."""

    def __init__(self, source):
        self.source = git('rev-parse', source + '^{commit}').decode().strip()
        self.trees = {}
        self.blobs = {}
        self.current_files = {}
        self.source_inputs = {}
        self.runtime_inputs = {}
        self.batch = subprocess.Popen(['git', 'cat-file', '--batch'], cwd=REPO,
                                      stdin=subprocess.PIPE, stdout=subprocess.PIPE)

    def close(self):
        self.batch.stdin.close()
        self.batch.stdout.close()
        self.batch.wait(timeout=10)

    def tree(self, commit):
        if commit not in self.trees:
            entries = {}
            for line in git('ls-tree', '-rz', '--full-tree', commit).split(b'\0'):
                if not line:
                    continue
                metadata, path = line.split(b'\t', 1)
                mode, kind, identifier = metadata.decode().split()
                entries[path.decode()] = (mode, kind, identifier)
            self.trees[commit] = entries
        return self.trees[commit]

    def blob(self, commit, path):
        path = relative_path(path)
        entry = self.tree(commit).get(path)
        require(entry is not None and entry[1] == 'blob',
                f'Input absent from Git tree {commit[:12]}: {path}')
        identifier = entry[2]
        if identifier not in self.blobs:
            self.batch.stdin.write((identifier + '\n').encode())
            self.batch.stdin.flush()
            header = self.batch.stdout.readline().decode().split()
            require(len(header) == 3 and header[1] == 'blob',
                    'Invalid git cat-file response for ' + identifier)
            payload = self.batch.stdout.read(int(header[2]))
            require(self.batch.stdout.read(1) == b'\n', 'Invalid Git object framing')
            self.blobs[identifier] = payload
        return self.blobs[identifier]

    def current(self, path, expected):
        path = Path(path)
        require(path.is_file(), 'Recorded input is absent: ' + str(path))
        stat = path.stat()
        signature = (stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
        previous = self.current_files.get(str(path))
        if previous is None or previous[0] != signature:
            previous = (signature, file_digest(path))
            self.current_files[str(path)] = previous
        require(previous[1] == expected, 'Current input hash differs: ' + str(path))

    def source_file(self, path, expected, tested):
        path = relative_path(path)
        require(re.fullmatch('[0-9a-f]{64}', expected), 'Invalid input SHA-256: ' + path)
        self.current(REPO / path, expected)
        if path not in ACTIVATION_FILES:
            for commit in {tested, self.source}:
                require(digest(self.blob(commit, path)) == expected,
                        f'Tested/selected Git tree differs at {commit[:12]}: {path}')
        elif path == 'pubspec.lock':
            require(expected == LOCK_SHA256, 'Ignored lockfile is not the recorded pin')
        previous = self.source_inputs.setdefault(path, expected)
        require(previous == expected, 'Cohorts used different source bytes: ' + path)


def selections(source):
    """Read literal declarations, never execute/import the qualification runner."""
    names = {}
    wanted = {'ENGINE', 'EDITOR', 'HARPER', 'NODE', 'BASELINE', 'EXPECTED_RUNTIME'}
    for node in ast.parse(source).body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id in wanted:
                    names[target.id] = ast.literal_eval(node.value)
    require(set(names) == wanted, 'Cannot identify fixed source test selections')
    for cohort in PACKAGES:
        tests = names[cohort.upper()]
        require(isinstance(tests, list) and tests and len(tests) == len(set(tests)),
                'Invalid test selection in source: ' + cohort)
        for path in tests:
            relative_path(path)
    require(names['EXPECTED_RUNTIME'] == {
        'flutter': '3.47.8', 'dart': '3.13.7', 'framework_revision': FRAMEWORK},
        'Harness runtime pin differs from the qualified runtime')
    return names


def parse_events(raw, expected_paths, platform, working_directory=REPO):
    """Reconstruct the protocol state and visible counts from actual JSON events."""
    events = []
    # NDJSON records are delimited by LF. Unicode paragraph/line separators
    # are legal literal characters inside a JSON string (for example a name).
    for number, line in enumerate(raw.decode('utf-8').split('\n'), 1):
        try:
            event = json.loads(line)
        except ValueError:
            require(not line.lstrip().startswith('{'),
                    'Malformed JSON event on line ' + str(number))
            continue  # Flutter may print an ordinary preamble before JSON events.
        require(isinstance(event, dict), 'Non-object JSON in event stream')
        events.append(event)
    require(events and events[-1].get('type') == 'done'
            and events[-1].get('success') is True, 'Missing successful terminal event')
    require(sum(e.get('type') == 'start' for e in events) == 1,
            'Expected one runner start event')
    require(sum(e.get('type') == 'done' for e in events) == 1,
            'Expected one runner terminal event')
    suites, starts, completions = {}, {}, {}
    paths = []
    for event in events:
        kind = event.get('type')
        require(kind != 'error', 'Runner error event: ' + str(event.get('error')))
        if kind == 'suite':
            suite = event['suite']
            require(suite['id'] not in suites, 'Duplicate suite identifier')
            require(suite.get('platform') == platform,
                    'Unexpected test platform: ' + repr(suite.get('platform')))
            require(suite.get('path'), 'Suite has no file path')
            path = str((Path(working_directory) / suite['path']).resolve())
            suites[suite['id']] = path
            paths.append(path)
        elif kind == 'testStart':
            test = event['test']
            require(test['id'] not in starts, 'Duplicate test start identifier')
            require(test.get('suiteID') in suites, 'Test starts in an unknown suite')
            starts[test['id']] = test
        elif kind == 'testDone':
            identifier = event['testID']
            require(identifier in starts, 'Test completion without its start')
            require(identifier not in completions, 'Duplicate test completion')
            require(event.get('result') == 'success',
                    'Test failure: ' + starts[identifier]['name'])
            require(not event.get('skipped'),
                    'Reported skip is outside this qualification: ' + starts[identifier]['name'])
            completions[identifier] = event
    require(sorted(paths) == sorted(expected_paths), 'Observed suites differ from selected files')
    require(starts and set(starts) == set(completions), 'Incomplete test starts/completions')
    by_suite = collections.Counter()
    for identifier, event in completions.items():
        if not event.get('hidden'):
            by_suite[suites[starts[identifier]['suiteID']]] += 1
    require(set(by_suite) == set(paths), 'Selected suite has no visible completed cases')
    return {'passing_tests': sum(by_suite.values()), 'test_files': len(paths),
            'reported_skips': 0, 'errors': 0, 'started_tests_including_hidden': len(starts),
            'visible_tests_by_suite': dict(sorted(by_suite.items()))}


def required_source_inputs(cohort, tests, analyzed):
    paths = {REPO / HARNESS, REPO / LOCK, REPO / 'pubspec.lock',
             REPO / '.dart_tool/package_config.json'}
    packages = ['quds_office_engine', 'legacy_doc_parser']
    if cohort == 'editor':
        packages += ['quds_office_editor', 'quds_reports']
    if cohort in {'editor', 'harper'}:
        packages.append('quds_proofing_harper')
    roots = package_roots(REPO / '.dart_tool/package_config.json')
    for name in packages:
        root = REPO / 'packages' / name
        require(name in roots and roots[name][0] == root.resolve(),
                'Activated local package points elsewhere: ' + name)
        for directory in SOURCE_DIRECTORIES:
            paths.update(files_under(root / directory))
    package = REPO / 'packages' / PACKAGES[cohort]
    paths.update(package / 'test' / path for path in tests)
    paths.update(package / path for path in analyzed)
    for directory in ('fonts', 'example/fonts'):
        paths.update(files_under(REPO / 'packages/quds_office_editor' / directory))
    paths.update(REPO.glob('pubspec.*'))
    paths.update(REPO.glob('analysis_options.yaml'))
    paths.update(REPO.glob('dart_test.yaml'))
    for parent in ('packages', 'apps'):
        for pattern in ('*/pubspec.yaml', '*/analysis_options.yaml',
                        '*/dart_test.yaml', '*/test/flutter_test_config.dart'):
            paths.update((REPO / parent).glob(pattern))
    pending = list(paths)
    visited = set()
    while pending:
        path = pending.pop()
        if path in visited or path.suffix != '.dart' or not path.is_file():
            continue
        visited.add(path)
        for directive in re.findall(r'\b(?:import|export|part)\s+[^;]+;', path.read_text()):
            for uri in re.findall(r'''['"]([^'"]+)['"]''', directive):
                if uri.startswith('package:'):
                    name, separator, remainder = uri[8:].partition('/')
                    if not separator or name not in roots:
                        continue
                    dependency = (roots[name][1] / remainder).resolve()
                elif ':' not in uri:
                    dependency = (path.parent / uri).resolve()
                else:
                    continue
                if dependency.is_relative_to(REPO) and dependency.is_file():
                    paths.add(dependency)
                    pending.append(dependency)
    return {str(path.relative_to(REPO)) for path in paths if path.is_file()}


def check_runtime(audit, folder, receipt):
    manifests = []
    for phase in ('before', 'after'):
        raw = gzip.decompress((folder / ('runtime-inputs.' + phase + '.json.gz')).read_bytes())
        manifest = json.loads(raw)
        identity = receipt['runtime_' + phase]
        require(digest(raw) == identity['runtime_input_manifest_sha256'],
                'Runtime manifest payload digest differs')
        require(len(manifest) == identity['runtime_input_count'], 'Runtime manifest count differs')
        manifests.append(manifest)
    require(manifests[0] == manifests[1], 'Runtime file manifest changed during cohort')
    require(receipt['runtime_before'] == receipt['runtime_after'], 'Runtime identity changed')
    identity = receipt['runtime_before']
    require(identity['framework_revision'] == FRAMEWORK, 'Recorded framework revision differs')
    require(identity['sdk_executables_sha256'] == PINNED_EXECUTABLES,
            'Actual SDK/engine executables differ from known genuine pins')
    root = Path(identity['environment']['FLUTTER_ROOT']).resolve()
    require(subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'],
                                    text=True).strip() == FRAMEWORK,
            'Current Flutter source checkout differs')
    require(not subprocess.check_output(['git', '-C', str(root), 'diff', 'HEAD', '--name-only']),
            'Flutter tracked sources were modified')
    manifest = manifests[0]
    for path, checksum in manifest.items():
        require(Path(path).is_absolute(), 'Runtime input is not absolute: ' + path)
        audit.current(path, checksum)
        previous = audit.runtime_inputs.setdefault(path, checksum)
        require(previous == checksum, 'Cohorts used different runtime bytes: ' + path)
    required = set()
    for directory in SDK_DIRECTORIES:
        required.update(files_under(root / directory))
    for config in (REPO / '.dart_tool/package_config.json',
                   root / 'packages/flutter_tools/.dart_tool/package_config.json'):
        required.add(config)
        for package, library in package_roots(config).values():
            if package.is_relative_to(REPO):
                continue
            for path in (library, package / 'bin', package / 'pubspec.yaml',
                         package / 'pubspec.lock'):
                required.update(files_under(path))
    snapshot = identity['environment'].get('QUDS_FLUTTER_TOOL_SNAPSHOT')
    require(snapshot, 'Compiled Flutter tool snapshot was not bound')
    required.add(Path(snapshot).resolve())
    required.update(root / path for path in PINNED_EXECUTABLES)
    missing = sorted(str(path) for path in required if str(path) not in manifest)
    require(not missing, 'Runtime manifest omitted required files: ' + repr(missing[:10]))
    for name, launcher in identity['launchers'].items():
        path = Path(launcher['path'])
        require(str(path.resolve()) == launcher['resolved_path'], 'Launcher target changed: ' + name)
        audit.current(path, launcher['sha256'])
    return len(manifest)


def check_versions(audit, folder, receipt):
    raw = {}
    for name, version in receipt['versions'].items():
        require(version['exit_code'] == 0, 'Version probe failed: ' + name)
        streams = []
        for stream in ('stdout', 'stderr'):
            payload = (folder / f'{name}-version.{stream}').read_bytes()
            require(digest(payload) == version[stream + '_sha256'], 'Version log hash differs')
            streams.append(payload)
        raw[name] = streams
        launcher = receipt['runtime_before']['launchers'][name]
        require(version['command'][0] == launcher['path'], 'Version probe used another executable')
        audit.current(launcher['path'], launcher['sha256'])
    require(set(raw) == ({'dart', 'flutter', 'node'} if receipt['cohort'] == 'node'
                         else {'dart', 'flutter'}), 'Missing/unexpected runtime version probes')
    flutter = json.loads(raw['flutter'][0])
    require(flutter == receipt['versions']['flutter']['metadata'], 'Flutter metadata differs from log')
    for key, expected in {'frameworkVersion': '3.47.8', 'dartSdkVersion': '3.13.7',
                          'frameworkRevision': FRAMEWORK, 'engineRevision': ENGINE}.items():
        require(flutter.get(key) == expected, 'Actual Flutter runtime differs: ' + key)
    dart = b''.join(raw['dart']).decode().strip()
    require(dart == receipt['versions']['dart']['version']
            and re.match(r'Dart SDK version: 3\.13\.7 \(stable\)', dart),
            'Actual Dart version differs')
    if 'node' in raw:
        require(b''.join(raw['node']).decode().strip() == receipt['versions']['node']['version'],
                'Actual Node version differs')


def check_format_scope(audit, receipt, baseline, tested):
    package_name = PACKAGES[receipt['cohort']]
    package = REPO / 'packages' / package_name
    prefix = 'packages/' + package_name + '/'
    changed = [path for path in git('diff', '--name-only', baseline, tested, '--',
                                    prefix).decode().splitlines()
               if path.endswith('.dart') and path in audit.tree(tested)]
    expected = sorted(path[len(prefix):] for path in changed)
    if not expected:
        expected = sorted({str(path.relative_to(package)) for path in (package / 'lib').rglob('*.dart')}
                          | {'test/' + path for path in receipt['tests']})
    require(receipt['analysis_paths'] == expected, 'Strict analysis omitted/changed source scope')
    exclusions = receipt['generated_format_exclusions_before']
    require(exclusions == receipt['generated_format_exclusions_after'], 'Generated exclusions changed')
    excluded = set()
    for item in exclusions:
        path = relative_path(item['path'])
        require(package_name == 'quds_office_engine'
                and path.startswith('lib/src/proofing/data/') and path.endswith('.dart'),
                'Non-generated source was excluded from formatting')
        require(path not in excluded and path in expected, 'Duplicate/irrelevant format exclusion')
        excluded.add(path)
        require(item['manifest_references'], 'Generated exclusion has no checksum manifest')
        audit.current(package / path, item['sha256'])
        for reference in item['manifest_references']:
            manifest_path = relative_path(reference['manifest'])
            require(manifest_path in {
                'packages/quds_office_engine/third_party/proofing/manifest.json',
                'packages/quds_office_engine/third_party/proofing/morphology_manifest.json'},
                'Unexpected generated-data manifest')
            payload = audit.blob(tested, manifest_path)
            require(digest(payload) == reference['manifest_sha256'], 'Generated-data manifest differs')
            expected_hash = json.loads(payload)['generated_files'][path]
            require(reference['field'] == 'generated_files' and reference['entry'] == path
                    and reference['expected_sha256'] == item['sha256'] == expected_hash,
                    'Generated-data exclusion is not checksum pinned')
    require(receipt['format_paths'] == [path for path in expected if path not in excluded],
            'Formatter does not cover the exact authored analysis scope')
    return len(excluded)


def check_cohort(audit, folder, cohort, declarations, harness):
    receipt = json.loads((folder / 'receipt.json').read_bytes())
    require(receipt['cohort'] == cohort, 'Receipt cohort does not match directory')
    tested = receipt['head_before']
    require(tested == receipt['head_after'], 'Repository HEAD changed during tests')
    require(subprocess.run(['git', 'merge-base', '--is-ancestor', tested, audit.source],
                           cwd=REPO).returncode == 0, 'Tested commit is not an ancestor of requested source')
    tests = declarations[cohort.upper()]
    require(receipt['tests'] == tests and receipt['test_file_count'] == len(tests),
            'Receipt selection differs from published harness')
    require(receipt['harness_sha256'] == receipt['harness_after_sha256'] == digest(harness)
            == digest((folder / 'validate-used.py').read_bytes()),
            'Executed harness differs from published source')
    require(receipt['source_before_sha256'] == receipt['source_after_sha256'],
            'Recorded source inputs changed')
    source = receipt['source_before_sha256']
    for path, checksum in source.items():
        audit.source_file(path, checksum, tested)
    required = required_source_inputs(cohort, tests, receipt['analysis_paths'])
    require(required <= set(source), 'Source manifest omitted required inputs: '
            + repr(sorted(required - set(source))[:10]))
    require(receipt['optional_before_sha256'] == receipt['optional_after_sha256'],
            'Optional host inputs changed')
    absent = []
    for path, checksum in receipt['optional_before_sha256'].items():
        if checksum is None:
            require(not Path(path).is_file(), 'Previously absent optional input appeared: ' + path)
            absent.append(path)
        else:
            audit.current(path, checksum)
    require(receipt['runtime_lock_before_sha256'] == receipt['runtime_lock_sha256']
            == receipt['expected_lock_sha256'] == LOCK_SHA256,
            'Dependency lock differs from the pin')
    require(digest(audit.blob(audit.source, LOCK)) == LOCK_SHA256,
            'Published dependency lock reference differs')
    runtime_count = check_runtime(audit, folder, receipt)
    check_versions(audit, folder, receipt)
    generated_count = check_format_scope(audit, receipt, declarations['BASELINE'], tested)
    planned = receipt['test_batches']
    require(planned and len(planned) == receipt['test_batch_count'], 'Invalid batch plan')
    require([path for item in planned for path in item['tests']] == tests,
            'Batches do not cover the exact selected tests once')
    names = [item['name'] for item in planned]
    require(names == [f'tests-{i + 1:02d}' for i in range(len(planned))], 'Invalid batch names')
    require([item['name'] for item in receipt['commands']] == names + ['analyze', 'format'],
            'Missing, repeated, or unexpected executed command')
    package = REPO / 'packages' / PACKAGES[cohort]
    rebuilt, artifacts = [], {}
    launchers = receipt['runtime_before']['launchers']
    for index, command in enumerate(receipt['commands']):
        name = command['name']
        require(command['exit_code'] == 0 and not command['timed_out'], 'Command failed: ' + name)
        require(command['executable_sha256'] == command['executable_after_sha256'],
                'Command executable changed: ' + name)
        audit.current(command['command'][0], command['executable_sha256'])
        require(Path(command['cwd']).resolve() == package.resolve(), 'Command ran in another package')
        streams = {}
        for stream in ('stdout', 'stderr'):
            path = folder / relative_path(command[stream])
            payload = gzip.decompress(path.read_bytes())
            require(digest(payload) == command[stream + '_sha256'], 'Command log payload hash differs')
            artifacts[path.name] = file_digest(path)
            streams[stream] = payload
        if name in names:
            selected = planned[index]['tests']
            require(command['tests'] == selected, 'Executed batch differs from plan')
            if cohort == 'editor':
                expected_command = [launchers['flutter']['path'], 'test', '--no-pub',
                                    '--dart-define=QUDS_SUBSET_RENDER_OUTPUT='
                                    + command['test_artifact_directory']]
            else:
                expected_command = [launchers['dart']['path'], 'test']
                if cohort == 'node':
                    expected_command += ['--platform', 'node']
            expected_command += ['--concurrency=2', '--reporter', 'json']
            expected_command += ['test/' + path for path in selected]
            require(command['command'] == expected_command,
                    'Test command has unexpected flags/filtering: ' + name)
            result = parse_events(streams['stdout'],
                                  [str((package / 'test' / path).resolve()) for path in selected],
                                  'node' if cohort == 'node' else 'vm', package)
            require(command['summary']['outcomes'] == {'success': result['passing_tests']},
                    'Runner summary differs from independently reconstructed count')
            rebuilt.append({'name': name, **result})
        elif name == 'analyze':
            require(command['command'] == [launchers['dart']['path'], 'analyze', '--fatal-infos']
                    + receipt['analysis_paths'], 'Strict analysis command differs')
            require(b'No issues found!' in streams['stdout'], 'Analysis log lacks success result')
        else:
            require(command['command'] == [launchers['dart']['path'], 'format', '--output=none',
                                           '--set-exit-if-changed'] + receipt['format_paths'],
                    'Strict formatter command differs')
            require(re.search(rb'Formatted \d+ files? \(0 changed\)', streams['stdout']),
                    'Formatter log does not show zero changed files')
    total = sum(item['passing_tests'] for item in rebuilt)
    require(receipt['tests_summary']['outcomes'] == {'success': total},
            'Aggregate summary differs from raw logs')
    require(receipt.get('passed') is True, 'Runner did not qualify this cohort')
    return {'passed': True, 'tested_commit': tested, 'test_files': len(tests),
            'passing_tests': total, 'reported_skips': 0, 'batches': rebuilt,
            'source_input_count': len(source), 'runtime_input_count': runtime_count,
            'generated_format_exclusions': generated_count, 'absent_optional_inputs': absent,
            'receipt_sha256': file_digest(folder / 'receipt.json'),
            'event_and_command_archives_sha256': artifacts}


def check_ancestry(audit, expected_count):
    integration = json.loads(audit.blob(audit.source, INCOMING + '/integration.json'))
    refs = []
    inventory_hashes = {}
    for remote in ('origin', 'upstream'):
        path = INCOMING + '/' + remote + '-refs.tsv'
        payload = audit.blob(audit.source, path)
        audit.current(REPO / path, digest(payload))
        inventory_hashes[path] = digest(payload)
        for line in payload.decode().splitlines():
            commit, name = line.split('\t')
            require(re.fullmatch('[0-9a-f]{40}', commit), 'Malformed captured commit')
            require(name.startswith('refs/heads/') or re.fullmatch(r'refs/pull/\d+/head', name),
                    'Unexpected captured ref: ' + name)
            refs.append((remote, name, commit))
    require(len(refs) == expected_count == integration['references'], 'Captured reference count differs')
    require(len({(remote, name) for remote, name, _ in refs}) == len(refs),
            'Duplicate captured reference names')
    commits = {item[2] for item in refs}
    require(len(commits) == integration['distinct_commits'], 'Distinct captured commit count differs')
    historical = 'docs/validation/office-fidelity-continuation-20261117'
    observations = [historical + '/' + name for name in ('incoming', 'refresh', 'final-refresh')]
    observations.append(INCOMING)
    observed_pairs = set()
    for directory in observations:
        for remote in ('origin', 'upstream'):
            path = directory + '/' + remote + '-refs.tsv'
            payload = audit.blob(audit.source, path)
            audit.current(REPO / path, digest(payload))
            inventory_hashes[path] = digest(payload)
            for line in payload.decode().splitlines():
                commit, name = line.split('\t')
                require(re.fullmatch('[0-9a-f]{40}', commit), 'Malformed historical captured commit')
                require(name.startswith('refs/heads/') or re.fullmatch(r'refs/pull/\d+/head', name),
                        'Unexpected historical captured ref: ' + name)
                observed_pairs.add((remote, name, commit))
    union_path = INCOMING + '/all-observations.json'
    union_payload = audit.blob(audit.source, union_path)
    audit.current(REPO / union_path, digest(union_payload))
    union = json.loads(union_payload)
    recorded_pairs = {(item['remote'], item['ref'], item['sha']) for item in union['references']}
    require(len(recorded_pairs) == len(union['references']) and recorded_pairs == observed_pairs,
            'Recorded all-observations union differs from original snapshots')
    all_commits = {item[2] for item in observed_pairs}
    require(union['observations'] == len(observations)
            and union['reference_revision_pairs'] == len(observed_pairs)
            and union['distinct_commits'] == len(all_commits), 'Historical union counts differ')
    missing = [commit for commit in sorted(all_commits)
               if subprocess.run(['git', 'merge-base', '--is-ancestor', commit, audit.source],
                                 cwd=REPO, capture_output=True).returncode != 0]
    require(not missing, 'Captured commits absent from source ancestry: ' + repr(missing))
    return {'references': len(refs), 'distinct_commits': len(commits), 'all_ancestors': True,
            'observations': len(observations), 'reference_revision_pairs': len(observed_pairs),
            'all_observed_distinct_commits': len(all_commits),
            'union_sha256': digest(union_payload),
            'inventories_sha256': inventory_hashes}


def self_test():
    """Defect controls for the independent event parser, using a small protocol fixture."""
    path = '/qualified/test/sample_test.dart'
    events = [
        {'type': 'start'},
        {'type': 'suite', 'suite': {'id': 0, 'platform': 'vm', 'path': path}},
        {'type': 'testStart', 'test': {'id': 1, 'suiteID': 0, 'name': 'loading'}},
        {'type': 'testDone', 'testID': 1, 'result': 'success', 'hidden': True, 'skipped': False},
        {'type': 'testStart', 'test': {'id': 2, 'suiteID': 0, 'name': 'visible case'}},
        {'type': 'testDone', 'testID': 2, 'result': 'success', 'hidden': False, 'skipped': False},
        {'type': 'done', 'success': True},
    ]
    encode = lambda items: ('\n'.join(json.dumps(item, ensure_ascii=False) for item in items)
                            + '\n').encode()
    require(parse_events(encode(events), [path], 'vm')['passing_tests'] == 1,
            'Parser counted hidden lifecycle events as tests')
    relative_events = [events[0], {**events[1], 'suite': {**events[1]['suite'],
                       'path': 'test/sample_test.dart'}}] + events[2:]
    require(parse_events(encode(relative_events), [path], 'vm', Path('/qualified'))[
                'passing_tests'] == 1, 'Relative suites were not resolved against command cwd')
    unicode_events = events[:4] + [{**events[4], 'test': {**events[4]['test'],
                      'name': 'visible \u2028 line \u2029 paragraph'}}] + events[5:]
    require(parse_events(encode(unicode_events), [path], 'vm')['passing_tests'] == 1,
            'Unicode separators in a JSON string were treated as NDJSON record boundaries')
    defects = {
        'missing_terminal': events[:-1],
        'missing_completion': events[:5] + events[6:],
        'duplicate_completion': events[:6] + [events[5]] + events[6:],
        'reported_skip': events[:5] + [{**events[5], 'skipped': True}] + events[6:],
        'hidden_failure': events[:3] + [{**events[3], 'result': 'error'}] + events[4:],
        'runner_error': events[:-1] + [{'type': 'error', 'error': 'compiler error'}] + events[-1:],
        'post_terminal_event': events + [events[5]],
        'wrong_suite': [events[0], {**events[1], 'suite': {**events[1]['suite'], 'path': '/wrong'}}]
                       + events[2:],
    }
    for name, items in defects.items():
        try:
            parse_events(encode(items), [path], 'vm')
        except AssertionError:
            continue
        raise AssertionError('Parser accepted defect control: ' + name)
    print(json.dumps({'self_test_passed': True,
                      'positive_controls': ['hidden_lifecycle_events_excluded',
                                            'relative_suite_paths',
                                            'literal_unicode_ndjson_separators'],
                      'rejected_defect_controls': list(defects)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path)
    parser.add_argument('--source', help='Saved/published source commit or documentation successor')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--expected-refs', type=int, default=232)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not args.evidence or not args.source:
        parser.error('--evidence and --source are required unless --self-test is used')
    evidence = args.evidence.resolve()
    output = (args.output or evidence / 'independent-review.json').resolve()
    report = {'started_utc': now(), 'passed': False, 'evidence_directory': str(evidence),
              'requested_source': args.source, 'audit_script_sha256': file_digest(__file__),
              'github_actions_used': False, 'cohorts': {},
              'count_scope': 'Visible successful testDone events. Reported skips are rejected. '
                             'Inherited tests that return early can still report success; '
                             'absent optional host inputs are disclosed per cohort.'}
    audit = None
    try:
        audit = Audit(args.source)
        report['source_commit'] = audit.source
        report['source_tree'] = git('rev-parse', audit.source + '^{tree}').decode().strip()
        report['current_commit'] = git('rev-parse', 'HEAD').decode().strip()
        require(subprocess.run(['git', 'merge-base', '--is-ancestor', audit.source,
                                report['current_commit']], cwd=REPO).returncode == 0,
                'Current checkout is not the requested source or its successor')
        harness = audit.blob(audit.source, HARNESS)
        declared = selections(harness)
        for cohort in PACKAGES:
            report['cohorts'][cohort] = check_cohort(audit, evidence / cohort, cohort, declared, harness)
            print(json.dumps({'cohort': cohort, 'passing_tests': report['cohorts'][cohort]['passing_tests'],
                              'passed': True}), flush=True)
        heads = {item['tested_commit'] for item in report['cohorts'].values()}
        require(len(heads) == 1, 'Final cohorts were not run at one fixed source commit')
        report['tested_commit'] = next(iter(heads))
        report['incoming'] = check_ancestry(audit, args.expected_refs)
        report['total_passing_tests'] = sum(item['passing_tests'] for item in report['cohorts'].values())
        report['total_test_files'] = sum(item['test_files'] for item in report['cohorts'].values())
        report['unique_source_input_count'] = len(audit.source_inputs)
        report['unique_runtime_input_count'] = len(audit.runtime_inputs)
        report['unique_current_file_hash_checks'] = len(audit.current_files)
        report['source_input_map_sha256'] = digest(json.dumps(audit.source_inputs, sort_keys=True).encode())
        report['runtime_input_map_sha256'] = digest(json.dumps(audit.runtime_inputs, sort_keys=True).encode())
        report['passed'] = True
    except (AssertionError, OSError, KeyError, TypeError, ValueError, subprocess.SubprocessError) as error:
        report['error'] = str(error)
    finally:
        if audit is not None:
            audit.close()
        report['finished_utc'] = now()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({key: report.get(key) for key in ('passed', 'source_commit',
                     'total_passing_tests', 'total_test_files', 'unique_source_input_count',
                     'unique_runtime_input_count', 'error')}, ensure_ascii=False))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Read-only audit of captured Git refs and recovered historical qualification.

Only immutable Git objects and the supplied reference capture are read. Product
tests are not executed. The output is not qualification of a later source tree.
Repeated --target arguments describe an anticipated graph union, not a merge.
An optional --upstream-refs capture is accounted for in its own namespace.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile

HOST = 'c63558c0b3bc713361771cc29b0d89ecf2fa09a7'
SOURCE = '9833831a013c98a8ce5c3f5e6f45de36593cb7df'
MAIN = 'b070e228a749e22cc8ce2098029a76ab5fb8eccb'
RESUME = '004b2ad6342cae7b2fe2750dbba5a9fdcebd3413'
SYNC = '10bd0cc4aa720acda4f52d0da882c57b05446435'
SYNC_SOURCE = '5c18db77505f876bf70bf7e89c49e8c3b617e0d4'
SYNC_DIR = 'docs/validation/office-main-sync-20261119/main-delta-v4/'
BASELINE = '0e84dc951e7a9e923107d7895fa457cf29a7af71'
HOST_DIR = 'docs/validation/office-main-integration-20261119/host-final/'
PROOF_PATH = 'docs/validation/thesaurus-20261118/resume/incoming-audit.json'
PROOF_INDEX = 'docs/validation/office-resume-main-20261119/reconciliation/reference-audit-anticipated-union.json'


def sha256(data):
    return hashlib.sha256(data).hexdigest()


class Audit:
    def __init__(self, repo):
        self.repo = str(repo.resolve())
        self.errors = []
        self.commands = 0

    def git(self, *args):
        self.commands += 1
        return subprocess.check_output(['git', '--no-lazy-fetch', '-C', self.repo, *args])

    def text(self, *args):
        return self.git(*args).decode().strip()

    def check(self, ok, description):
        if not ok:
            self.errors.append(description)
        return bool(ok)

    def blob(self, commit, path):
        return self.git('show', commit + ':' + path)

    def tree(self, commit, paths=None):
        raw = self.git('ls-tree', '-r', '-z', commit, '--', *(paths or []))
        result = {}
        for item in raw.split(b'\0'):
            if item:
                meta, name = item.decode().split('\t', 1)
                mode, kind, oid = meta.split()
                result[name] = {'mode': mode, 'type': kind, 'object': oid}
        return result

    def reference_capture(self, path, namespace, ancestors, equivalents):
        data = path.read_bytes()
        refs, excluded, resolved, seen = [], [], {}, set()
        for number, line in enumerate(data.decode().splitlines(), 1):
            if not line.strip():
                continue
            fields = line.split()
            if len(fields) != 2 or not re.fullmatch(r'[0-9a-f]{40}', fields[0]):
                raise ValueError(f'{namespace} capture line {number}: expected SHA and ref')
            oid, ref = fields
            self.check(ref not in seen, namespace + ' duplicate captured ref: ' + ref)
            seen.add(ref)
            if ref == 'HEAD' or ref.endswith('^{}'):
                excluded.append({'ref': ref, 'oid': oid})
                continue
            if oid not in resolved:
                resolved[oid] = self.text('rev-parse', oid + '^{commit}')
            commit = resolved[oid]
            kind = 'branch' if ref.startswith('refs/heads/') else 'pull_request' if re.fullmatch(r'refs/pull/\d+/head', ref) else 'tag' if ref.startswith('refs/tags/') else 'unknown'
            disposition = 'ancestor' if commit in ancestors else 'historical_equivalent' if commit in equivalents else 'unaccounted'
            refs.append({'ref': ref, 'object': oid, 'commit': commit, 'kind': kind, 'disposition': disposition})
            self.check(kind != 'unknown' and disposition != 'unaccounted', namespace + ' unaccounted ref: ' + ref)
        return {'namespace': namespace, 'file': path.name, 'sha256': sha256(data),
                'reference_count': len(refs),
                'reference_kinds': dict(Counter(r['kind'] for r in refs)),
                'reference_dispositions': dict(Counter(r['disposition'] for r in refs)),
                'excluded_advertisements': excluded, 'refs': refs}

    def historical(self, ancestors):
        original = json.loads(self.blob(BASELINE, PROOF_PATH))['historical_equivalence']
        prior = json.loads(self.blob(RESUME, PROOF_INDEX))['historical_equivalence_checks']
        indexed = {row['original_commit']: row for row in prior}
        self.check(len(original) == len(indexed) == 14, 'Expected 14 historical heads')
        results = []
        for row in original:
            head = row['sha']
            proof = indexed[head]
            equivalent = proof['equivalent_commit']
            entry = {'head': head, 'branch': row['branch'], 'equivalent': equivalent,
                     'equivalent_reachable': equivalent in ancestors,
                     'original_reachable': head in ancestors}
            self.check(equivalent in ancestors, 'Historical equivalent missing: ' + head)
            if row['disposition'] == 'identical_tree_already_integrated':
                a = self.text('rev-parse', head + '^{tree}')
                b = self.text('rev-parse', equivalent + '^{tree}')
                entry.update(method='complete_tree_identity', original_tree=a, equivalent_tree=b)
                entry['passed'] = a == b and equivalent in ancestors
            else:
                comparison = BASELINE if row['disposition'] == 'all_commits_patch_equivalent' else row['equivalent_commit']
                base = self.text('merge-base', head, comparison)
                paths = self.git('diff', '--no-renames', '--name-only', '-z', base, head).decode().rstrip('\0').split('\0')
                old = self.tree(head, paths)
                new = self.tree(equivalent, paths)
                checks = [{'path': p, 'old': old.get(p), 'equivalent': new.get(p),
                           'identical': old.get(p) == new.get(p)} for p in paths]
                entry.update(method='complete_delta_mode_type_blob_identity', merge_base=base,
                             comparison=comparison, files=checks)
                entry['passed'] = bool(paths) and paths != [''] and all(x['identical'] for x in checks) and equivalent in ancestors
                if 'fresh_changed_files' in row:
                    entry['passed'] &= set(paths) == set(row['fresh_changed_files'])
            self.check(entry['passed'], 'Historical proof failed: ' + head)
            results.append(entry)
        return results

    def archives(self):
        reports = []
        qualification = None
        sync_qualification = None
        selections = [(name, HOST, HOST_DIR + name + '-evidence')
                      for name in ['first-attempt', 'qualification', 'review', 'studio-mail']]
        for path in self.text('diff', '--name-only', MAIN, SYNC).splitlines():
            if path.endswith('.tar.xz'):
                selections.append(('sync/' + path.split('office-main-sync-20261119/')[1], SYNC,
                                   path.removesuffix('.tar.xz')))
        for name, source, stem in selections:
            raw = self.blob(source, stem + '.tar.xz')
            index = json.loads(self.blob(source, stem + '.index.json'))
            expected_hash = index.get('archive_sha256', index.get('sha256'))
            expected_size = index.get('archive_bytes', index.get('bytes'))
            self.check(sha256(raw) == expected_hash and len(raw) == expected_size, name + ' archive identity')
            with tarfile.open(fileobj=io.BytesIO(raw), mode='r:xz') as tar:
                members = tar.getmembers()
                self.check(all(m.isfile() for m in members), name + ' non-file member')
                contents = {m.name: tar.extractfile(m).read() for m in members if m.isfile()}
            expected = {m['path']: m for m in index['members']}
            self.check(len(contents) == len(members) == len(expected), name + ' duplicate/missing member')
            self.check(set(contents) == set(expected), name + ' exact member coverage')
            mismatches = []
            for path, item in expected.items():
                data = contents.get(path)
                if data is None or len(data) != item['bytes'] or sha256(data) != item['sha256']:
                    mismatches.append(path)
            self.check(not mismatches, name + ' member hashes')
            reports.append({'name': name, 'path': stem + '.tar.xz', 'publication_commit': source,
                            'bytes': len(raw), 'sha256': sha256(raw),
                            'member_count': len(contents), 'mismatches': mismatches,
                            'source_commit': index.get('source_commit')})
            if name == 'qualification':
                qualification = contents
            if stem == SYNC_DIR + 'final/evidence':
                sync_qualification = {k.removeprefix('raw/'): v for k, v in contents.items() if k.startswith('raw/')}
        return reports, qualification, sync_qualification

    def source_hashes(self, manifest, source):
        tree = self.tree(source)
        mismatches = []
        cache = {}
        process = subprocess.Popen(['git', '--no-lazy-fetch', '-C', self.repo, 'cat-file', '--batch'],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        try:
            for path, item in manifest.items():
                actual = tree.get(path)
                if not actual or actual['mode'] != item['mode'] or actual['object'] != item['git_blob']:
                    mismatches.append({'path': path, 'reason': 'tree entry mismatch'})
                    continue
                oid = actual['object']
                if item.get('sha256') is not None:
                    if oid not in cache:
                        process.stdin.write((oid + '\n').encode())
                        process.stdin.flush()
                        header = process.stdout.readline().decode().split()
                        if len(header) == 2 and header[1] == 'missing':
                            cache[oid] = None
                            mismatches.append({'path': path, 'reason': 'historical blob unavailable', 'blob': oid})
                            continue
                        if len(header) != 3 or header[1] != 'blob':
                            raise ValueError('Unexpected cat-file response: ' + repr(header))
                        remaining = int(header[2])
                        digest = hashlib.sha256()
                        while remaining:
                            block = process.stdout.read(min(65536, remaining))
                            if not block:
                                raise ValueError('Truncated cat-file blob')
                            digest.update(block)
                            remaining -= len(block)
                        if process.stdout.read(1) != b'\n':
                            raise ValueError('Missing cat-file delimiter')
                        cache[oid] = digest.hexdigest()
                    if cache[oid] != item['sha256']:
                        mismatches.append({'path': path, 'reason': 'SHA-256 mismatch'})
        finally:
            process.stdin.close()
            process.stdout.close()
            code = process.wait()
        self.check(code == 0 and not mismatches, 'Frozen source blob/hash verification')
        return {'source': source, 'records': len(manifest), 'distinct_blob_sha256_checks': sum(x is not None for x in cache.values()), 'mismatches': mismatches}

    def qualify(self, contents, source, publication, plan_dir, phase_plans, published):
        phases = []
        identities = {}
        frozen_manifest = None
        for phase, plan_name in phase_plans:
            receipt_bytes = contents[phase + '/verification.json']
            receipt = json.loads(receipt_bytes)
            plan_bytes = self.blob(publication, plan_dir + plan_name)
            plan = json.loads(plan_bytes)
            self.check(receipt['source_commit'] == source and receipt['success'] is True, phase + ' successful source receipt')
            self.check(receipt['source_tree'] == self.text('rev-parse', source + '^{tree}'), phase + ' source tree')
            self.check(sha256(plan_bytes) == receipt['plan_sha256'] and plan['groups'] == receipt['planned_groups'], phase + ' plan identity')
            for path, expected_hash in receipt['manifest_sha256'].items():
                self.check(sha256(contents[phase + '/' + path]) == expected_hash, phase + ' manifest: ' + path)
            source_before = json.loads(contents[phase + '/source-before.json'])
            source_after = json.loads(contents[phase + '/source-after.json'])
            environment_before = json.loads(contents[phase + '/environment-before.json'])
            environment_after = json.loads(contents[phase + '/environment-after.json'])
            self.check(source_before == source_after and environment_before == environment_after, phase + ' stable inventories')
            self.check(len(source_before) == receipt['source_input_count'] and len(environment_before) == receipt['runtime_input_count'], phase + ' inventory counts')
            if frozen_manifest is None:
                frozen_manifest = source_before
            else:
                self.check(frozen_manifest == source_before, 'Same frozen source in both phases')
            all_cases = []
            group_reports = []
            for run in receipt['runs']:
                self.check(run['exit_code'] == 0 and run['accepted'] is True, phase + '/' + run['name'] + ' exit')
                log = contents[phase + '/' + run['log']]
                self.check(sha256(log) == run['log_sha256'], run['name'] + ' log hash')
                compressed = contents[phase + '/' + run['compressed_log']]
                self.check(sha256(compressed) == run['compressed_log_sha256'] and gzip.decompress(compressed) == log, run['name'] + ' compressed log')
                if 'cases_file' not in run:
                    continue
                for key, hash_key in [('cases_file', 'cases_sha256'), ('errors_file', 'errors_sha256')]:
                    self.check(sha256(contents[phase + '/' + run[key]]) == run[hash_key], run['name'] + ' ' + key)
                self.check(json.loads(contents[phase + '/' + run['errors_file']]) == [], run['name'] + ' errors file')
                group = next(g for g in plan['groups'] if g['name'] == run['name'])
                starts, ends, suites, cases = {}, {}, {}, []
                count_events = Counter()
                for line in log.decode().splitlines():
                    event = json.loads(line)
                    kind = event['type']
                    count_events[kind] += 1
                    if kind == 'suite':
                        suite = event['suite']
                        path = suite['path']
                        if '/quds_office_suite/' in path:
                            path = path.split('/quds_office_suite/', 1)[1]
                        elif not path.startswith('packages/'):
                            path = group['cwd'] + '/' + path
                        suites[suite['id']] = path
                    elif kind == 'testStart':
                        test = event['test']
                        self.check(test['id'] not in starts, run['name'] + ' duplicate start')
                        starts[test['id']] = test
                    elif kind == 'testDone':
                        test_id = event['testID']
                        self.check(test_id in starts and test_id not in ends, run['name'] + ' unmatched/duplicate completion')
                        ends[test_id] = event
                        self.check(event['result'] == 'success' and event['skipped'] is False, run['name'] + ' failed/skipped event')
                        if not event.get('hidden', False):
                            test = starts[test_id]
                            cases.append((suites[test['suiteID']], test['name']))
                    elif kind == 'done':
                        self.check(event['success'] is True, run['name'] + ' terminal failure')
                self.check(count_events['start'] == count_events['done'] == 1 and count_events['error'] == 0, run['name'] + ' protocol/error counts')
                self.check(set(starts) == set(ends), run['name'] + ' incomplete tests')
                requested = {group['cwd'] + '/' + p for p in group['tests']}
                self.check(set(suites.values()) == requested == {p for p, _ in cases}, run['name'] + ' nonempty exact suite coverage')
                self.check(len(cases) == len(set(cases)) == run['passed'], run['name'] + ' distinct successful cases')
                all_cases.extend(cases)
                group_reports.append({'name': run['name'], 'cases': len(cases), 'suites': len(requested), 'log_sha256': sha256(log)})
            self.check(len(all_cases) == len(set(all_cases)) == receipt['passed'], phase + ' total cases')
            identities[phase] = set(all_cases)
            phases.append({'name': phase, 'executions': len(all_cases), 'distinct_suites': len({p for p, _ in all_cases}),
                           'source_records': len(source_before), 'runtime_records': len(environment_before),
                           'analysis_paths': len(receipt['analysis_files']), 'format_paths': len(receipt['formatted_files']),
                           'receipt_sha256': sha256(receipt_bytes), 'groups': group_reports})
        primary = phase_plans[0][0]
        self.check(identities['node'] <= identities[primary], 'Node identities repeat primary identities')
        source_verification = self.source_hashes(frozen_manifest, source)
        reconstructed = {primary: len(identities[primary]), 'node': len(identities['node']),
                         'executions': sum(len(s) for s in identities.values()),
                         'distinct_cases': len(set.union(*identities.values())),
                         'distinct_suites': len({p for s in identities.values() for p, _ in s})}
        self.check(published['accepted'] is True and published['executions'] == reconstructed['executions'], 'Published audit agrees with reconstruction')
        if 'distinct_cases' in published:
            self.check(published['distinct_cases'] == reconstructed['distinct_cases'], 'Published distinct count agrees')
        return {'source': source, 'counts': reconstructed, 'phases': phases, 'source_verification': source_verification,
                'runtime_scope': 'Recorded before/after inventory identity; old absolute runtime is not present or executed here.',
                'fresh_test_execution': False}

    def sync_outer(self, contents):
        execution_bytes = contents['execution.json']
        execution = json.loads(execution_bytes)
        summary = json.loads(self.blob(SYNC, SYNC_DIR + 'final/summary.json'))
        self.check(execution['status'] == 'PASS' and execution['source_commit'] == SYNC_SOURCE,
                   'Sync outer successful source receipt')
        self.check(sha256(execution_bytes) == summary['original_execution_sha256'], 'Sync original execution identity')
        for path, expected in execution['manifest_sha256'].items():
            self.check(sha256(contents[path]) == expected, 'Sync outer manifest: ' + path)
        source = json.loads(contents['source-before.json'])
        runtime = json.loads(contents['runtime-before.json'])
        inner = json.loads(contents['native/source-before.json'])
        self.check(source == json.loads(contents['source-after.json']), 'Sync outer source stable')
        self.check(runtime == json.loads(contents['runtime-after.json']), 'Sync outer runtime stable')
        self.check(len(source) == summary['source_inputs'] and len(runtime) == summary['runtime_inputs'],
                   'Sync outer inventory counts')
        self.check(all(source.get(p) == v['sha256'] for p, v in inner.items()), 'Sync inner/outer source agreement')
        extra = sorted(set(source) - set(inner))
        tree = self.tree(SYNC_SOURCE, extra)
        extra_manifest = {p: {'mode': tree[p]['mode'], 'git_blob': tree[p]['object'], 'sha256': source[p]} for p in extra}
        extra_check = self.source_hashes(extra_manifest, SYNC_SOURCE)
        for run in execution['runs']:
            self.check(run['exit_code'] == 0 and run['accepted'] is True, 'Sync outer command: ' + run['name'])
            self.check(sha256(contents[run['log']]) == run['log_sha256'], 'Sync outer log: ' + run['name'])
            if 'receipt' in run:
                self.check(sha256(contents[run['receipt']]) == run['receipt_sha256'], 'Sync nested receipt: ' + run['name'])
        controls = {}
        for name in ['bundle-controls', 'packaging-controls']:
            text = contents[name + '.log'].decode()
            cases = re.findall(r'^(test\S+ \([^\n]+\)) \.\.\. ok$', text, re.M)
            terminal = re.findall(r'^Ran (\d+) tests? in [\d.]+s$', text, re.M)
            self.check(len(terminal) == 1 and len(cases) == len(set(cases)) == int(terminal[0]) and text.rstrip().endswith('OK'),
                       'Sync Python controls: ' + name)
            controls[name] = len(cases)
        self.check(sum(controls.values()) == summary['separate_python_controls'], 'Sync separate Python total')
        compiled = []
        for path, expected in execution['browser_compile_outputs'].items():
            data = contents[path]
            self.check(len(data) == expected['bytes'] and sha256(data) == expected['sha256'], 'Sync browser compilation: ' + path)
            compiled.append({'path': path, 'bytes': len(data), 'sha256': sha256(data)})
        return {'source_records': len(source), 'runtime_records': len(runtime),
                'inner_source_records': len(inner), 'extra_source_paths': extra,
                'extra_source_verification': extra_check, 'separate_python_controls': controls,
                'compiled_outputs': compiled,
                'scope': 'Preserved historical Python controls and browser compilation; no browser session or fresh execution.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--refs', type=Path, required=True)
    parser.add_argument('--upstream-refs', type=Path, help='Optional fresh upstream capture, kept separate from fork refs')
    parser.add_argument('--target', action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    audit = Audit(args.repo)
    targets = [audit.text('rev-parse', t + '^{commit}') for t in args.target]
    ancestors = set(audit.text('rev-list', *targets).splitlines())
    main_ancestors = set(audit.text('rev-list', MAIN).splitlines())
    historical = audit.historical(ancestors)
    equivalents = {p['head'] for p in historical if p['passed']}
    fork_capture = audit.reference_capture(args.refs, 'fork', ancestors, equivalents)
    refs = fork_capture['refs']
    upstream_capture = None
    if args.upstream_refs:
        upstream_capture = audit.reference_capture(args.upstream_refs, 'upstream', ancestors, equivalents)
        prior = audit.blob(RESUME, 'docs/validation/office-resume-main-20261119/reconciliation/captured-upstream-refs-current.txt')
        prior_refs = {ref: oid for oid, ref in (line.split() for line in prior.decode().splitlines())
                      if ref != 'HEAD' and not ref.endswith('^{}')}
        current_refs = {r['ref']: r['object'] for r in upstream_capture['refs']}
        upstream_capture['prior_capture_comparison'] = {
            'prior_source_commit': RESUME, 'prior_capture_sha256': sha256(prior),
            'actual_refs_identical': current_refs == prior_refs,
            'added': sorted(set(current_refs) - set(prior_refs)),
            'removed': sorted(set(prior_refs) - set(current_refs)),
            'changed': sorted(r for r in set(current_refs) & set(prior_refs) if current_refs[r] != prior_refs[r]),
        }
    archive_report, contents, sync_contents = audit.archives()
    host_published = json.loads(audit.blob(HOST, HOST_DIR + 'host_qualification_audit.json'))
    qualification = audit.qualify(contents, SOURCE, HOST, HOST_DIR,
                                  [('main', 'plan.json'), ('node', 'node-plan.json')],
                                  {'accepted': host_published['accepted'],
                                   'executions': host_published['counts']['total_current_executions'],
                                   'distinct_cases': host_published['counts']['total_current_distinct_scenarios']})
    sync_published = json.loads(audit.blob(SYNC, SYNC_DIR + 'final/independent-summary.json'))
    sync_qualification = audit.qualify(sync_contents, SYNC_SOURCE, SYNC, SYNC_DIR,
                                      [('native', 'delta-native-plan.json'), ('node', 'delta-node-plan.json')],
                                      {'accepted': sync_published['passed'], 'executions': sync_published['application_case_executions']})
    sync_qualification['outer_receipt'] = audit.sync_outer(sync_contents)
    preservation = []
    if len(targets) == 1:
        target_tree = audit.tree(targets[0])
        for original, directory in [(HOST, HOST_DIR), (SYNC, 'docs/validation/office-main-sync-20261119/')]:
            original_tree = audit.tree(original, [directory])
            changes = [p for p, v in original_tree.items() if target_tree.get(p) != v]
            preservation.append({'source': original, 'directory': directory, 'files': len(original_tree), 'changed_or_missing': changes})
            audit.check(not changes, 'Historical evidence preservation: ' + directory)
    combined_refs = refs + (upstream_capture['refs'] if upstream_capture else [])
    report = {'schema': 2, 'audited_at_utc': datetime.now(timezone.utc).isoformat(),
              'script_sha256': sha256(Path(__file__).read_bytes()), 'targets': targets,
              'mode': 'actual_commit' if len(targets) == 1 else 'anticipated_graph_union',
              'captured_refs_sha256': fork_capture['sha256'], 'reference_count': len(refs),
              'reference_kinds': dict(Counter(r['kind'] for r in refs)),
              'reference_dispositions': dict(Counter(r['disposition'] for r in refs)),
              'excluded_advertisements': fork_capture['excluded_advertisements'],
              'upstream_capture': upstream_capture,
              'combined_reference_count': len(combined_refs),
              'combined_reference_dispositions': dict(Counter(r['disposition'] for r in combined_refs)),
              'unmerged_recent_at_captured_main': [r for r in refs if r['commit'] not in main_ancestors and r['commit'] not in equivalents],
              'historical_equivalences': historical, 'refs': refs,
              'historical_archives': archive_report, 'recovered_host_qualification': qualification,
              'recovered_sync_qualification': sync_qualification,
              'evidence_preservation': preservation, 'errors': audit.errors, 'passed': not audit.errors,
              'repository_mutations_by_auditor': 0, 'github_actions_calls': 0,
              'fresh_product_test_executions': 0, 'git_commands': audit.commands,
              'scope': 'Immutable captured fork references, optional separately named upstream capture, and recovered historical qualification; no current runtime, platform or product acceptance is implied.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['mode','targets','reference_count','reference_kinds','reference_dispositions','combined_reference_count','combined_reference_dispositions','errors','passed']}))
    print(json.dumps(qualification['counts']))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

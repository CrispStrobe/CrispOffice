#!/usr/bin/env python3
"""Verify the frozen bulk-mail evidence without extracting or changing files.

Normal mode compares receipt sources with validation.json's qualified Git
checkpoint, never the later working tree. Only the explicitly proved historical
fixture/import changes are accepted. --archive-only verifies the archive,
metadata and receipt bindings without invoking Git. Paired source manifests are
compared when recorded; single-manifest receipts retain their recorded stability
declaration. Runtime package configuration is preserved in those receipts but
is explicitly excluded from Git-source comparisons.
"""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile


WORD_BASE = '3b753b0251d5dffe1b5b3e1496748f39caba8587'
WORD_ADDITIONS = {
    'packages/quds_office_engine/test/office_vba_word_named_measurements_test.dart': 43,
    'packages/quds_office_engine/test/office_vba_word_named_measurements_integration_test.dart': 105,
}
HOST_RECEIPT = 'mail-host-validation/late-intake-initial/receipt.json'
HOST_TEST = 'packages/quds_office_editor/example/test/studio_mail_bulk_provider_test.dart'
HOST_IMPORT = "import 'package:quds_office_studio/studio_mail_workspace_strings.dart';"
RUNTIME_CONFIG = '.dart_tool/package_config.json'


class VerificationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise VerificationError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def relative_path(value):
    require(isinstance(value, str) and value and '\\' not in value,
            'Invalid relative path: ' + repr(value))
    path = PurePosixPath(value)
    require(not path.is_absolute() and '..' not in path.parts
            and path.as_posix() == value and value != '.',
            'Noncanonical relative path: ' + value)
    return value


def valid_digest(value, length=64):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{%d}' % length, value)


class GitObjects:
    def __init__(self, repo):
        self.repo = repo
        self.cache = {}
        self.env = dict(os.environ, GIT_NO_LAZY_FETCH='1', GIT_TERMINAL_PROMPT='0')

    def read(self, *args):
        result = subprocess.run(['git', '-C', str(self.repo), *args],
                                env=self.env, capture_output=True)
        require(result.returncode == 0,
                'Git object unavailable; fetch separately or use --archive-only: '
                + result.stderr.decode(errors='replace').strip())
        return result.stdout

    def blob(self, commit, path):
        key = (commit, relative_path(path))
        if key not in self.cache:
            self.cache[key] = self.read('cat-file', 'blob', commit + ':' + path)
        return self.cache[key]


def source_manifest(record):
    forms = [
        ('source_hashes_before', 'source_hashes_after'),
        ('source_before', 'source_after'),
    ]
    paired = [pair for pair in forms if any(key in record for key in pair)]
    require(len(paired) <= 1, 'Ambiguous before/after source manifests')
    if paired:
        before, after = paired[0]
        require(before in record and after in record,
                'Incomplete before/after source manifests')
        require(record[before] == record[after], 'Sources changed during a recorded run')
        sources = record[before]
        require('source_hashes' not in record, 'Ambiguous single/paired source manifests')
    else:
        sources = record.get('source_hashes')
    flags = [record[key] for key in (
        'source_hashes_unchanged', 'sources_unchanged', 'source_unchanged',
    ) if key in record]
    require(flags and all(value is True for value in flags),
            'Missing or false recorded source-stability declaration')
    require(record.get('changed_sources', []) == [], 'Receipt records changed sources')
    require(isinstance(sources, dict) and sources, 'Missing source hash map')
    for path, digest in sources.items():
        relative_path(path)
        require(valid_digest(digest), 'Invalid source SHA256: ' + path)
    if 'source_file_count' in record:
        require(record['source_file_count'] == len(sources), 'Receipt source count differs')
    return sources, bool(paired)


def insertion_count(before, after):
    """Require every original byte-line in order, permitting only inserted lines."""
    old_lines, new_lines = before.splitlines(keepends=True), after.splitlines(keepends=True)
    cursor = 0
    for line in old_lines:
        while cursor < len(new_lines) and new_lines[cursor] != line:
            cursor += 1
        require(cursor < len(new_lines), 'Historical fixture contains a removal or replacement')
        cursor += 1
    return len(new_lines) - len(old_lines)


def verify(args):
    directory = args.evidence_dir.resolve()
    validation = json.loads((directory / 'validation.json').read_bytes())
    require(validation['baseline_status'] == 'PASS', 'Baseline is not declared accepted')
    manifest_info = validation['member_manifest']
    manifest_bytes = (directory / relative_path(manifest_info['file'])).read_bytes()
    require(sha256(manifest_bytes) == manifest_info['sha256'], 'Member-manifest SHA256 differs')
    manifest = json.loads(manifest_bytes)
    app_info = validation['source_applicability']
    app_bytes = (directory / relative_path(app_info['file'])).read_bytes()
    require(sha256(app_bytes) == app_info['sha256'], 'Source-applicability SHA256 differs')
    applicability = json.loads(app_bytes)
    require(applicability['status'] == 'PASS', 'Source applicability is not declared accepted')
    qualified = validation['qualified_source']
    commit, tree = qualified['commit'], qualified['tree']
    require(valid_digest(commit, 40) and valid_digest(tree, 40), 'Invalid Git checkpoint')
    require(commit == applicability['qualified_source_commit']
            and tree == applicability['qualified_source_tree'], 'Qualified source bindings differ')

    archive_info = validation['archive']
    require(manifest['archive'] == archive_info, 'Archive declarations differ')
    archive_path = directory / relative_path(archive_info['path'])
    archive_bytes = archive_path.read_bytes()
    require(len(archive_bytes) == archive_info['bytes'], 'Archive byte length differs')
    require(sha256(archive_bytes) == archive_info['sha256'], 'Archive SHA256 differs')
    entries = manifest['members']
    require(len(entries) == manifest['member_count'] == manifest_info['members'],
            'Member count declarations differ')
    by_path, by_source = {}, {}
    for entry in entries:
        path, source = relative_path(entry['path']), relative_path(entry['source'])
        require(path not in by_path and source not in by_source, 'Duplicate archive/source mapping')
        require(valid_digest(entry['sha256']), 'Invalid member SHA256: ' + path)
        by_path[path], by_source[source] = entry, path
    payloads = {}
    # tarfile reads member streams only; no extract/extractall call is made.
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode='r:gz') as archive:
        for member in archive:
            name = relative_path(member.name)
            require(member.isfile() and name not in payloads and name in by_path,
                    'Unexpected, nonregular or duplicate archive member: ' + name)
            entry = by_path[name]
            require(member.size == entry['bytes'], 'Tar member length differs: ' + name)
            require(format(member.mode, '04o') == entry['mode'], 'Tar member mode differs: ' + name)
            stream = archive.extractfile(member)
            require(stream is not None, 'Cannot read regular archive member: ' + name)
            with stream:
                data = stream.read()
            require(len(data) == entry['bytes'] and sha256(data) == entry['sha256'],
                    'Member bytes or SHA256 differ: ' + name)
            payloads[name] = data
    require(set(payloads) == set(by_path), 'Archive member inventory differs')
    require(sum(map(len, payloads.values())) == manifest['uncompressed_member_bytes'],
            'Uncompressed member byte total differs')

    parsed = {}

    def json_member(path):
        require(path in payloads, 'Missing referenced archive member: ' + path)
        if path not in parsed:
            parsed[path] = json.loads(payloads[path])
        return parsed[path]

    def mapped_source(source):
        require(source in by_source, 'Missing source-to-member mapping: ' + source)
        return by_source[source]

    checks = applicability['receipt_checks']
    require(len(checks) == app_info['receipt_cohorts'], 'Receipt cohort count differs')
    require(len({(row['receipt'], row['name']) for row in checks}) == len(checks),
            'Duplicate receipt cohort')
    host = applicability['host_composition']
    repair = host['repair']
    require(repair['path'] == HOST_TEST and repair['inserted_line'] == HOST_IMPORT
            and repair['assertions_changed'] is False, 'Unexpected host repair exception')
    require(host['original_run_exit_code'] == 1
            and host['accepted_unique_cases'] == host['unchanged_suites_passed']
            + host['corrected_provider_suite_passed'], 'Invalid host composition')
    word = applicability['word_composition']
    word_proofs = {row['path']: row for row in word['additive_fixture_proof']}
    require(len(word['additive_fixture_proof']) == 2 and set(word_proofs) == set(WORD_ADDITIONS),
            'Unexpected Word fixture exceptions')
    for path, proof in word_proofs.items():
        require(proof['inserted_lines'] == WORD_ADDITIONS[path] and proof['removed_lines'] == 0,
                'Unexpected Word insertion/removal counts: ' + path)
    qualification = json_member('word/qualification.json')
    require(qualification['composed_acceptance']['additive_diff_against_checkpoint'] == WORD_BASE,
            'Historical Word checkpoint differs')
    old_word_names = {row['name'] for row in qualification['receipts']}
    approved = {path: proof for path, proof in word_proofs.items()}
    approved[HOST_TEST] = repair
    for path, proof in approved.items():
        require(valid_digest(proof['before_sha256']) and valid_digest(proof['after_sha256']),
                'Invalid historical SHA256 proof: ' + path)

    git = None if args.archive_only else GitObjects(args.repo.resolve())
    if git:
        require(git.read('rev-parse', commit + '^{tree}').decode().strip() == tree,
                'Qualified commit tree differs')
        require(not git.read('ls-tree', commit, '--', RUNTIME_CONFIG),
                'The excluded runtime configuration is unexpectedly tracked')
        for path, proof in approved.items():
            after = git.blob(commit, path)
            require(sha256(after) == proof['after_sha256'], 'Qualified exception SHA256 differs: ' + path)
            if path in word_proofs:
                before = git.blob(WORD_BASE, path)
                require(sha256(before) == proof['before_sha256'], 'Historical Word SHA256 differs: ' + path)
                require(insertion_count(before, after) == proof['inserted_lines'],
                        'Word insertion-only proof differs: ' + path)
            else:
                lines = after.splitlines(keepends=True)
                positions = [index for index, line in enumerate(lines)
                             if line.rstrip(b'\r\n') == HOST_IMPORT.encode()]
                require(len(positions) == 1, 'Expected exactly one added host extension import')
                before = b''.join(line for index, line in enumerate(lines) if index != positions[0])
                require(sha256(before) == proof['before_sha256'],
                        'Removing the single import does not reconstruct the historical host test')

    paired_count, source_checks, failed = 0, 0, []
    exclusions, differences = [], []
    for check in checks:
        source, name = check['receipt'], check['name']
        member = mapped_source(source)
        require(sha256(payloads[member]) == check['receipt_sha256'], 'Receipt SHA256 differs: ' + member)
        document = json_member(member)
        records = document if isinstance(document, list) else [document]
        matches = [row for row in records if row.get('name', row.get('cohort')) == name]
        require(len(matches) == 1, 'Receipt cohort missing or ambiguous: ' + source + ':' + name)
        record = matches[0]
        sources, paired = source_manifest(record)
        paired_count += int(paired)
        require(check['recorded_sources_stable'] is True
                and len(sources) == check['source_file_count'], 'Source-applicability count/stability differs')
        expected_failure = source == HOST_RECEIPT and name == 'host-tests'
        expected_exit = host['original_run_exit_code'] if expected_failure else 0
        require(record['exit_code'] == check['exit_code'] == expected_exit,
                'Unexpected receipt exit code: ' + source + ':' + name)
        if expected_failure:
            require(check['current_source_differences'] == [HOST_TEST],
                    'Expected failed host run must have exactly the proved import difference')
            failed.append(member + ':' + name)

        log = record['log']
        if PurePosixPath(log).is_absolute():
            matches = [path for original, path in by_source.items() if log.endswith('/' + original)]
            require(len(matches) == 1, 'Absolute receipt log has no unique source mapping: ' + log)
            log_member = matches[0]
        else:
            log_member = mapped_source(str(PurePosixPath(source).parent / relative_path(log)))
        if 'log_sha256' in record:
            require(sha256(payloads[log_member]) == record['log_sha256'], 'Receipt log SHA256 differs')

        declared = check['current_source_differences']
        require(len(set(declared)) == len(declared), 'Duplicate declared source differences')
        for path in declared:
            require(path in approved and path in sources
                    and sources[path] == approved[path]['before_sha256'],
                    'Unproved declared source difference: ' + path)
            require((path == HOST_TEST and expected_failure) or
                    (path in word_proofs and source.startswith('runtime/word-validation/')
                     and name in old_word_names), 'Historical exception used by an unrelated cohort')
        observed = []
        for path, digest in sources.items():
            if path == RUNTIME_CONFIG:
                exclusions.append(dict(receipt=member, cohort=name, path=path, sha256=digest))
                continue
            source_checks += 1
            if git and sha256(git.blob(commit, path)) != digest:
                observed.append(path)
        if git:
            require(sorted(observed) == sorted(declared),
                    'Qualified source differences do not match the proved exceptions: '
                    + source + ':' + name + ' ' + repr(observed))
        if declared:
            differences.append(dict(receipt=member, cohort=name, paths=declared))
    require(len(failed) == 1, 'Expected exactly one preserved failed host cohort')

    return dict(
        status='PASS', mode='archive-only' if args.archive_only else 'baseline-source',
        archive_bytes=len(archive_bytes), archive_sha256=sha256(archive_bytes),
        regular_members=len(payloads), receipt_cohorts=len(checks),
        paired_source_manifest_cohorts=paired_count,
        single_manifest_stability_declarations=len(checks) - paired_count,
        qualified_source=qualified,
        git_source_verification='SKIPPED (--archive-only)' if args.archive_only else 'PASS',
        recorded_source_hashes=source_checks,
        git_source_hash_comparisons=source_checks if git else 0,
        cached_git_blobs=len(git.cache) if git else 0,
        proved_historical_difference_cohorts=len(differences) if git else None,
        preserved_failed_receipts=failed,
        runtime_git_exclusion=dict(
            path=RUNTIME_CONFIG, receipt_occurrences=len(exclusions),
            recorded_sha256=sorted({row['sha256'] for row in exclusions}),
            note='Untracked runtime configuration is excluded only from Git comparisons; '
                 'its recorded hashes remain preserved and integrity-checked in the receipts.',
        ),
        scope='Frozen qualified baseline only; later main and working-tree changes are not qualified.',
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive-only', action='store_true', help='Do not invoke Git or qualify source blobs')
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--evidence-dir', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    try:
        result = verify(args)
    except (VerificationError, OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        print(json.dumps(dict(status='FAIL', error=str(error))), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

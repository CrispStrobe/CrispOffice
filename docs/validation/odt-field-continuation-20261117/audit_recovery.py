#!/usr/bin/env python3
"""Audit the recovered product and the two already-published evidence archives.

This verifies retained files and immutable Git objects. It does not reconstruct
the lost unpublished command logs and does not execute the product tests.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

BASELINE = 'e3a38789359adaa33b2da1345c952fa1c2d8aebb'
PRODUCT = '7147ae60770869e7471b947347d5e188a177424f'
PUBLISHED_PRODUCT = '5afff4b86523250c93d949eb6c010e49d9fabd82'
PRODUCT_TREE = '3080e51ec487a97c08696d119dbef97a442a2e67'
EXPECTED_FILES = {
    'packages/quds_office_engine/lib/src/word/serial/odt_document_writer.dart': {
        'blob': '06e7d40ce0758a7df17700b94a31e0d184534f18',
        'sha256': '157e641657998fc5be8f12a8bef362566261caa14b7898de93b182bd85841aea',
    },
    'packages/quds_office_engine/lib/src/word/serial/word_deserializer.dart': {
        'blob': '4e30fa0fef45350b6d0ad53ebf6e6a75bded48d8',
        'sha256': '5ecbcd9d94c4cceb8cd9540e5fef744626069f029cae7c52e9776d9ab83d8193',
    },
    'packages/quds_office_engine/test/odt_imported_field_fidelity_test.dart': {
        'blob': 'c1082c3340f375425d11a6b5944a46b8f1751484',
        'sha256': 'b45735984370488300d7e2bcb26ad3b31371a5c14d92bf7eb9ccc8eab63db8b3',
    },
    'packages/quds_office_engine/test/odt_page_field_fidelity_test.dart': {
        'blob': '0a4331683f037aa8a23e70b043bc6a7b8af2de62',
        'sha256': '9c3554acc4bff6fca34569161efbeee7ddb653b09d3817cf0704d06aa01e1877',
    },
}
SCOPES = [
    'packages/quds_office_engine/lib/src/proofing',
    'packages/quds_office_engine/test/proofing',
    'packages/quds_proofing_gector',
    'packages/quds_proofing_harper',
    'packages/quds_office_editor',
    'apps/quds_report_studio',
    'tools',
    'pubspec.yaml',
    'analysis_options.yaml',
]
ARCHIVES = {
    'docs/validation/german-proofing-recovery-20261117': {
        'members': 167,
        'bytes': 905740,
        'sha256': '176fe525b22833eb238f493275059c999ddf9bbb286ccb6af3538316b5f33f9f',
    },
    'docs/validation/german-proofing-recovery-20261117/delivery-main': {
        'members': 38,
        'bytes': 258100,
        'sha256': 'c35ec8d7c1b85495c948aea530522da50bd4eb7598729017e49036bb2fa88526',
    },
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument(
        '--output', type=Path,
        default=Path(__file__).resolve().with_name('recovery-audit.json'),
    )
    args = parser.parse_args()
    repo = args.repo.resolve()
    errors = []

    def check(condition, message):
        if not condition:
            errors.append(message)

    def git(*command):
        return subprocess.check_output(['git', '-C', str(repo), *command])

    def object_id(revision, path=None):
        ref = revision if path is None else f'{revision}:{path}'
        return git('rev-parse', ref).decode().strip()

    def committed_bytes(revision, path):
        return git('cat-file', 'blob', f'{revision}:{path}')

    # The connector preserves the source tree but writes new commit metadata.
    # The original commit object is not reachable on the published branch, so
    # verify its preserved payload without requiring that object in the clone.
    payload_path = Path(__file__).resolve().with_name('recovered-original-source.commit')
    commit = payload_path.read_bytes()
    commit_id = hashlib.sha1(
        b'commit ' + str(len(commit)).encode() + b'\0' + commit,
    ).hexdigest()
    headers = commit.split(b'\n\n', 1)[0].decode().splitlines()
    trees = [line[5:] for line in headers if line.startswith('tree ')]
    parents = [line[7:] for line in headers if line.startswith('parent ')]
    tree = trees[0] if len(trees) == 1 else None
    published_tree = object_id(PUBLISHED_PRODUCT + '^{tree}')
    published_parents = git('show', '-s', '--format=%P', PUBLISHED_PRODUCT).decode().strip().split()
    check(commit_id == PRODUCT, 'Recovered commit object identity')
    check(tree == PRODUCT_TREE, 'Recovered product tree identity')
    check(parents == [BASELINE], 'Recovered product parent identity')
    check(published_tree == PRODUCT_TREE, 'Published product tree identity')
    check(published_parents == [BASELINE], 'Published product parent identity')
    changed = git('diff', '--name-only', BASELINE, PRODUCT_TREE).decode().splitlines()
    check(changed == sorted(EXPECTED_FILES), 'Unexpected product/test diff paths')
    files = {}
    for path, expected in EXPECTED_FILES.items():
        blob = object_id(PRODUCT_TREE, path)
        saved = committed_bytes(PRODUCT_TREE, path)
        current = (repo / path).read_bytes()
        check(blob == expected['blob'], 'Recovered blob identity: ' + path)
        check(sha(saved) == expected['sha256'], 'Recovered SHA-256: ' + path)
        check(current == saved, 'Working source differs from qualified product: ' + path)
        files[path] = {
            'bytes': len(saved),
            'gitBlob': blob,
            'sha256': sha(saved),
            'workingTreeMatchesProduct': current == saved,
        }

    unchanged = []
    for path in SCOPES:
        before, after = object_id(BASELINE, path), object_id(PRODUCT_TREE, path)
        check(before == after, 'Changed excluded scope: ' + path)
        unchanged.append({
            'path': path, 'baselineObject': before, 'productObject': after,
            'unchanged': before == after,
        })
    aot_path = 'packages/quds_proofing_aot'
    aot_absent = all(
        not git('ls-tree', revision, '--', aot_path).strip()
        for revision in [BASELINE, PRODUCT_TREE]
    )
    check(aot_absent, 'AOT package must remain absent')

    archives = []
    for directory, expected in ARCHIVES.items():
        base = repo / directory
        index_path = directory + '/evidence-index.json'
        index_data = (base / 'evidence-index.json').read_bytes()
        check(
            index_data == committed_bytes(BASELINE, index_path),
            'Historical archive index changed: ' + directory,
        )
        index = json.loads(index_data)
        archive_path = directory + '/' + index['archive']['path']
        packed = (repo / archive_path).read_bytes()
        preserved = packed == committed_bytes(BASELINE, archive_path)
        check(preserved, 'Historical archive changed: ' + directory)
        check(len(packed) == expected['bytes'] == index['archive']['bytes'],
              'Historical archive byte count: ' + directory)
        check(sha(packed) == expected['sha256'] == index['archive']['sha256'],
              'Historical archive SHA-256: ' + directory)
        members = {}
        with tarfile.open(repo / archive_path) as archive:
            for member in archive.getmembers():
                path = PurePosixPath(member.name)
                check(member.isfile(), 'Nonregular archive member: ' + member.name)
                check(not path.is_absolute() and '..' not in path.parts,
                      'Unsafe archive member: ' + member.name)
                check(member.name not in members, 'Duplicate archive member: ' + member.name)
                if not member.isfile():
                    continue
                members[member.name] = archive.extractfile(member).read()
        check(set(members) == set(index['members']),
              'Historical archive member set: ' + directory)
        check(len(members) == expected['members'] == index['memberCount'],
              'Historical archive member count: ' + directory)
        check(sum(map(len, members.values())) == index['uncompressedBytes'],
              'Historical archive uncompressed bytes: ' + directory)
        for name, data in members.items():
            meta = index['members'].get(name)
            if meta is None:
                continue
            check(len(data) == meta['bytes'], 'Member byte count: ' + name)
            check(sha(data) == meta['sha256'], 'Member SHA-256: ' + name)
        for mirror in index.get('mirroredSummaries', []):
            member = 'evidence/' + Path(mirror).name
            mirrored_path = base / mirror if '/' in mirror else base / 'evidence' / mirror
            check(mirrored_path.read_bytes() == members[member],
                  'Historical summary mirror: ' + mirror)
        archives.append({
            'path': archive_path,
            'indexSha256': sha(index_data),
            'bytes': len(packed),
            'sha256': sha(packed),
            'verifiedMembers': len(members),
            'uncompressedBytes': sum(map(len, members.values())),
            'unchangedFromBaseline': preserved,
        })

    result = {
        'schemaVersion': 1,
        'auditedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'repository': 'CrispStrobe/quds_office_suite',
        'baseline': BASELINE,
        'recoveredProduct': PRODUCT,
        'recoveredProductTree': tree,
        'commitObjectSha1Verified': commit_id == PRODUCT,
        'originalCommitPayload': {
            'path': payload_path.name,
            'bytes': len(commit),
            'sha256': sha(commit),
            'gitObjectSha1': commit_id,
            'requiresOriginalGitObject': False,
        },
        'publishedProduct': PUBLISHED_PRODUCT,
        'publishedProductTree': published_tree,
        'publishedProductParents': published_parents,
        'publishedTreeMatchesRecoveredTree': published_tree == tree == PRODUCT_TREE,
        'productParents': parents,
        'changedPaths': changed,
        'recoveredFiles': files,
        'unchangedScopes': unchanged,
        'aotAbsentAtBaselineAndProduct': aot_absent,
        'historicalArchives': archives,
        'historicalMembersVerified': sum(item['verifiedMembers'] for item in archives),
        'scopeLimits': [
            'This audit verifies restored product bytes and already-published historical archives; it does not run or recount product tests.',
            'The original commit metadata is verified from the preserved payload; Git object queries use the identical published tree and reachable published commit, so the original unpublished commit need not exist in a fresh clone.',
            'The original unpublished continuation logs and documentation commit were lost when the execution workspace reset. This audit does not claim those files survived or reconstruct their contents.',
            'Fresh execution receipts, if present in this report directory, are separate evidence and are outside this archive audit.',
            'The working ODF guide and historical README have authorized documentation updates; archive and index immutability are checked independently of those prose files.',
        ],
        'errors': errors,
        'passed': not errors,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({
        'passed': not errors,
        'errors': errors,
        'product': PRODUCT,
        'productTree': tree,
        'publishedProduct': PUBLISHED_PRODUCT,
        'publishedTreeMatchesRecoveredTree': published_tree == tree == PRODUCT_TREE,
        'restoredFilesVerified': len(files),
        'unchangedScopesVerified': len(unchanged),
        'historicalMembersVerified': result['historicalMembersVerified'],
        'aotAbsent': aot_absent,
    }, indent=2))
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())

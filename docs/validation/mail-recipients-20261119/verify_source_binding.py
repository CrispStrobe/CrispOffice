"""Bind recorded subset results to this checkout without rerunning tests."""

import datetime
import hashlib
import json
import pathlib
import subprocess


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASELINE = '2170791c9250d72c9df31a065408365f9b50abaa'


def read(name):
    return json.loads((HERE / name).read_text())


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return path.split('/quds_office_suite/', 1)[-1]


def check(group, expected):
    rows = []
    for path, sha in expected.items():
        path = relative(path)
        actual = digest(ROOT / path)
        rows.append({'path': path, 'expectedSha256': sha,
                     'actualSha256': actual, 'matches': actual == sha})
    if not all(row['matches'] for row in rows):
        raise RuntimeError(f'Source binding changed: {group}')
    return {'group': group, 'verified': len(rows), 'files': rows}


mail = read('mail-source-harness/provenance.json')
slide = read('slide-source-harness/qualification.json')
zotero = read('zotero-source-harness/tag-catalog-qualification.json')
static = read('final-static-checks/format-final.json')
mail_sources = {row['path']: row['sha256'] for row in mail['production']}
mail_sources.update({row['source_path']: row['source_sha256']
                     for row in mail['files']})
slide_sources = dict(slide['sourceHashes'])
slide_sources.update({row['original']: row['originalSha256']
                      for row in slide['tests']})
checks = [check('mail subset production and original tests', mail_sources),
          check('slide graph and original tests', slide_sources),
          check('Zotero catalog and original test', zotero['sourceHashesBefore']),
          check('formatted changed package Dart files', static['sourceHashes'])]

protected = ['packages/quds_mail_core', 'packages/quds_mail_mime',
             'packages/quds_mail_store', 'packages/quds_mail_transport',
             'packages/quds_mail_ui', 'third_party',
             'docs/validation/mail-reply-threading-20261119']
protected_diff = git('diff', '--name-status', BASELINE, 'HEAD', '--', *protected)
if protected_diff:
    raise RuntimeError('Unexpected protected-source change: ' + protected_diff)
core_tree = git('rev-parse', 'HEAD:packages/quds_mail_core')
if core_tree != '2860c22f05dacc4cdeb18552e419c01e9d9b6862':
    raise RuntimeError('Core tree changed')

expected_evidence = {
    'mail-source-harness/test.log': read('mail-source-harness/receipt.json')['test_log_sha256'],
    'mail-source-harness/provenance.json': read('mail-source-harness/receipt.json')['provenance_sha256'],
    'slide-source-harness/tests.log': slide['logSha256'],
    'zotero-source-harness/tag-catalog-tests.jsonl': zotero['resultLogSha256'],
    'zotero-source-harness/tag-catalog-tests.stderr.log': zotero['stderrLogSha256'],
}
evidence_checks = []
for path, expected in expected_evidence.items():
    actual = digest(HERE / path)
    if actual != expected:
        raise RuntimeError('Evidence changed: ' + path)
    evidence_checks.append({'path': path, 'sha256': actual, 'matches': True})

report = {
    'recordedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'productCheckpoint': git('rev-parse', 'HEAD'),
    'productTree': git('rev-parse', 'HEAD^{tree}'),
    'baselineMain': BASELINE,
    'method': 'SHA-256 source/evidence identity and Git subtree comparison; no new tests run',
    'checks': checks,
    'evidenceChecks': evidence_checks,
    'coreTree': core_tree,
    'protectedPaths': protected,
    'protectedDiff': protected_diff,
    'allMatch': True,
    'fullWorkspaceAcceptance': False,
    'actionsQueriedOrAwaited': False,
}
(HERE / 'source-binding.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'productCheckpoint': report['productCheckpoint'],
                  'groups': [{k: row[k] for k in ['group', 'verified']}
                             for row in checks], 'allMatch': True}))

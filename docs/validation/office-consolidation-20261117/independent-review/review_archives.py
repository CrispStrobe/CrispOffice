#!/usr/bin/env python3
"""Read every evidence archive member and independently bind it to raw runs."""

import datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile


BASE = Path('/workspace/scratch/2a07827fdeed')
OUT = BASE / 'independent-review'
DOCS = BASE / 'quds_office_suite/docs/validation/office-consolidation-20261117'
QUALIFICATION = DOCS / 'qualification/qualification-f5021f1c.tar.xz'
CONSUMER = BASE / 'consumer-packaged-f5021f1c/consumer-f5021f1c.tar.xz'
SOURCE = 'f5021f1c364baf010049fda2dd4bf7f414deda79'
failures = []
checks = 0


def check(value, label, detail=None):
    global checks
    checks += 1
    if not value:
        failures.append({'check': label, 'detail': detail})


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_archive(path, expected_sha, expected_size, member_map):
    raw = path.read_bytes()
    check(sha(raw) == expected_sha, path.name + ': outer SHA256')
    check(len(raw) == expected_size, path.name + ': exact compressed bytes')
    payloads = {}
    with tarfile.open(path, 'r:xz') as archive:
        members = archive.getmembers()
        names = [m.name for m in members]
        check(len(names) == len(set(names)), path.name + ': no duplicate member names')
        check(set(names) == set(member_map), path.name + ': exact indexed membership')
        for member in members:
            name = member.name
            parsed = PurePosixPath(name)
            check(not parsed.is_absolute() and '..' not in parsed.parts,
                  path.name + ': safe relative member name', name)
            check(member.isfile() and not member.issym() and not member.islnk(),
                  path.name + ': member is regular file', name)
            data = archive.extractfile(member).read()
            expected = member_map[name]
            size = expected['bytes'] if 'bytes' in expected else expected['size']
            check(len(data) == member.size == size,
                  path.name + ': exact member bytes', name)
            check(sha(data) == expected['sha256'], path.name + ': member SHA256', name)
            payloads[name] = data
    return payloads


def main():
    index = json.loads(Path(str(QUALIFICATION) + '.index.json').read_bytes())
    member_map = {row['path']: row for row in index['members']}
    check(len(member_map) == len(index['members']) == index['member_count'] == 124,
          'qualification index exact member count')
    check(index['archive_sha256'] == '560eef7a14ebc90b011ff41a711fa5036487631461ecbecdfd41d51d251f3efc'
          and index['archive_bytes'] == 975320, 'qualification announced archive identity')
    qualified = read_archive(QUALIFICATION, index['archive_sha256'],
                             index['archive_bytes'], member_map)
    check(sum(map(len, qualified.values())) == index['uncompressed_bytes'],
          'qualification total uncompressed size')
    prefix = 'qualification-bundle/qualification/'
    archived_raw = {n.removeprefix(prefix): b for n, b in qualified.items() if n.startswith(prefix)}
    raw_root = BASE / 'qualification-final'
    actual_raw = {p.relative_to(raw_root).as_posix(): p for p in raw_root.rglob('*')
                  if p.is_file()}
    check(set(actual_raw) == set(archived_raw),
          'qualification archive contains every raw result file including process lock',
          {'missing': sorted(set(actual_raw) - set(archived_raw)),
           'extra': sorted(set(archived_raw) - set(actual_raw))})
    for relative, data in archived_raw.items():
        check(actual_raw[relative].read_bytes() == data,
              'qualification archived raw file equals independently audited live bytes', relative)
    check(qualified['qualification-bundle/plan-only/plan.json'] == archived_raw['plan.json'],
          'pre-execution plan and executed plan byte identical')
    check(qualified['qualification-bundle/harness/run_qualification.py'] == archived_raw['run-used.py'],
          'archived harness equals actual run-used snapshot')
    receipt = json.loads(archived_raw['receipt.json'])
    check(receipt['source_commit'] == SOURCE and receipt['status'] == 'passed',
          'archived qualification qualified source and completed status')
    audit = json.loads((OUT / 'qualification-audit.json').read_bytes())
    check(audit['passed'] is True and audit['source_commit'] == SOURCE,
          'independent raw qualification audit is complete and passed')
    consumer_index = json.loads((CONSUMER.parent / 'consumer-index.json').read_bytes())
    check(len(consumer_index['members']) == 384, 'consumer index exact member count')
    consumer = read_archive(
        CONSUMER, '3c5c324e79581d0eb8fff4b0c829e54947f7c60281e288e6368476c6608319fd',
        937068, consumer_index['members'])
    consumer_prefix = 'run/'
    consumer_raw = {n.removeprefix(consumer_prefix): b for n, b in consumer.items()
                    if n.startswith(consumer_prefix)}
    consumer_root = BASE / 'consumer-final-f5021f1c'
    for relative, data in consumer_raw.items():
        live = consumer_root / relative
        if relative in {'runner.stdout.log', 'runner.stderr.log'}:
            live = BASE / ('consumer-final-f5021f1c.' + relative.removeprefix('runner.'))
        check(live.read_bytes() == data,
              'consumer archived raw file equals independently audited live bytes', relative)
    consumer_audit = json.loads((OUT / 'consumer-audit.json').read_bytes())
    check(consumer_audit['passed'] is True, 'independent consumer audit passed')
    return {
        'schema': 'independent-evidence-archive-audit-v1',
        'source_commit': SOURCE,
        'qualification': {
            'archive': str(QUALIFICATION), 'sha256': sha(QUALIFICATION.read_bytes()),
            'bytes': QUALIFICATION.stat().st_size, 'members': len(qualified),
            'raw_files_bound_to_audited_run': len(archived_raw),
            'all_raw_files_included': True,
            'plan_only_and_executed_plan_identical': True,
            'run_used_and_archived_harness_identical': True,
            'raw_audit_sha256': sha((OUT / 'qualification-audit.json').read_bytes()),
        },
        'consumer': {
            'archive': str(CONSUMER), 'sha256': sha(CONSUMER.read_bytes()),
            'bytes': CONSUMER.stat().st_size, 'members': len(consumer),
            'raw_files_bound_to_audited_run': len(consumer_raw),
            'raw_audit_sha256': sha((OUT / 'consumer-audit.json').read_bytes()),
        },
        'total_verified_members': len(qualified) + len(consumer),
        'scope': 'All member names, types, sizes, and SHA256 values were independently verified. Raw run members were byte-compared with the independently audited run directories. No archive producer or qualification code was imported.',
    }


if __name__ == '__main__':
    report = {}
    try:
        report = main()
    except Exception as exc:
        failures.append({'check': 'audit execution completed',
                         'detail': type(exc).__name__ + ': ' + str(exc)})
        import traceback
        traceback.print_exc()
    report['audit_script_sha256'] = sha(Path(__file__).read_bytes())
    report['checked_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    report['checks'] = checks
    report['failures'] = failures
    report['passed'] = not failures
    (OUT / 'archive-audit.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'checks': checks, 'passed': not failures, 'failures': failures,
                      'total_verified_members': report.get('total_verified_members')}, indent=2))
    raise SystemExit(bool(failures))

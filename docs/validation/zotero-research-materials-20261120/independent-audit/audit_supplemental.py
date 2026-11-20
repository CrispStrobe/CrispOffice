#!/usr/bin/env python3
"""Read existing supplemental evidence independently; never execute Dart/tests."""
import base64
from collections import Counter
from datetime import datetime, timezone
from email import policy
from email.parser import BytesParser
from email.utils import getaddresses
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

ROOT = Path('/workspace/scratch/ee4fc9e59992')
REPO = ROOT / 'quds_office_suite'
SDK = ROOT / 'zotero-toolchain/flutter-sdk'
OUT = Path(__file__).resolve().parent
EVIDENCE = OUT.parent / 'supplemental'
FROZEN = 'f0122cb5bff5b6cf6a6f69f043545dabc2930791'
spec = importlib.util.spec_from_file_location('independent_core_auditor', OUT / 'audit_validation.py')
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


def read(name):
    return core.read_json(EVIDENCE / name)


def sha(path):
    return core.file_record(path)['sha256']


def require(condition, message):
    if not condition:
        failures.append(message)


failures = []
receipt, commands = read('receipt.json'), read('commands.json')
before, after = read('inputs-before.json.gz'), read('inputs-after.json.gz')
require(before == after, 'Supplemental input inventories differ')
require(core.digest(before) == receipt['inputInventoryBeforeSha256'], 'Before inventory digest mismatch')
require(core.digest(after) == receipt['inputInventoryAfterSha256'], 'After inventory digest mismatch')
require(receipt['sourceHead'] == receipt['sourceHeadAfter'] == FROZEN, 'Unexpected supplemental source commit')
require(receipt['passed'] and receipt['failure'] is None, 'Supplemental process receipt did not pass')
require(all(not paths for paths in receipt['changedInputs'].values()), 'Reported input drift')

blobs = {}
for entry in subprocess.check_output(['git', 'ls-tree', '-rz', '--full-tree', FROZEN], cwd=REPO).split(b'\0'):
    if entry:
        meta, name = entry.split(b'\t', 1)
        _, kind, oid = meta.decode().split()
        if kind == 'blob':
            blobs[name.decode()] = oid
counts = Counter()
for area, records in before.items():
    if area == 'dependencies':
        for name, metadata in records.items():
            dep = Path(metadata['root'])
            require(core.digest(metadata['files']) == metadata['inventory_sha256'], f'Dependency inventory digest: {name}')
            require(len(metadata['files']) == metadata['file_count'], f'Dependency file count: {name}')
            require(set(metadata['files']) == core.dependency_files(dep), f'Dependency selection incomplete: {name}')
            for relative, expected in metadata['files'].items():
                require(core.file_record(dep / relative) == expected, f'Dependency bytes differ: {name}/{relative}')
                counts['dependency_files'] += 1
        continue
    for relative, expected in records.items():
        if area == 'host_fonts':
            raise AssertionError('This supplemental run unexpectedly records host fonts; inspect before auditing')
        path = Path(relative)
        if not path.is_absolute():
            path = (SDK if area in ['runtime', 'supplemental_runtime'] else REPO) / path
        require(core.file_record(path) == expected, f'{area} bytes differ: {relative}')
        if area == 'source':
            require(blobs.get(relative) == expected['git_blob_sha1'], f'Source is not frozen blob: {relative}')
        counts[area] += 1
for name in ['run_validation.py', 'run_supplemental_validation.py', 'export_studio_mime.dart']:
    original = ROOT / 'final-validation' / name
    require(sha(original) == sha(EVIDENCE / name), f'Archived helper differs from executed helper: {name}')

required_commands = ['dart-version', 'node-version', 'vba-vm', 'vba-dart2js', 'vba-node', 'studio-mime-export']
require([command['label'] for command in commands] == required_commands, 'Command sequence differs')
require(all(command['returnCode'] == 0 for command in commands), 'A supplemental command failed')
require([{k:v for k,v in command.items() if k != 'argv'} for command in commands] == receipt['steps'], 'Recorded command steps differ')
corpus_bytes = (EVIDENCE / 'canonical-vba-corpus.json').read_bytes()
corpus = json.loads(corpus_bytes)
dart = SDK / 'bin/cache/dart-sdk/bin/dart'
node = Path(os.environ.get('CODEX_PRIMARY_RUNTIME_NODE', '/opt/codex/runtimes/codex-primary-runtime/dependencies/node/bin/node')).resolve()
definition = '-DVBA_CONFORMANCE_BASE64=' + base64.b64encode(corpus_bytes).decode('ascii')
package_config = '--packages=' + str(REPO / '.dart_tool/package_config.json')
entry = 'tool/macros/web_vba_string_conformance.dart'
engine_cwd = REPO / 'packages/quds_office_engine'
expected_commands = {
    'dart-version': ([str(dart), '--version'], REPO),
    'node-version': ([str(node), '--version'], REPO),
    'vba-vm': ([str(dart), package_config, definition, entry], engine_cwd),
    'vba-dart2js': ([str(dart), 'compile', 'js', '-O1', package_config, definition, entry, '-o', str(EVIDENCE / 'strings.js')], engine_cwd),
    'vba-node': ([str(node), '-e', 'globalThis.self = globalThis; require(process.argv[1]);', str(EVIDENCE / 'strings.js')], engine_cwd),
    'studio-mime-export': ([str(dart), package_config, str(EVIDENCE / 'export_studio_mime.dart'), str(EVIDENCE / 'mime-fixture.json'), str(EVIDENCE / 'studio-attachment.eml'), str(EVIDENCE / 'studio-envelope.json')], REPO),
}
for command in commands:
    argv, cwd = expected_commands[command['label']]
    require(command['argv'] == argv and command['cwd'] == str(cwd), f'Exact supplemental command/cwd differs: {command["label"]}')
for executable in [dart, node]:
    with executable.open('rb') as stream:
        require(stream.read(4) == b'\x7fELF', f'Native executable is not ELF: {executable}')
require(str(node) in before['supplemental_runtime'], 'Node executable not fingerprinted')
original_corpus = REPO / 'packages/quds_office_engine/test/fixtures/vba_conformance/string_intrinsics_v1.json'
require(corpus_bytes == original_corpus.read_bytes(), 'Supplied corpus differs from frozen fixture')
for label in ['vba-vm', 'vba-dart2js']:
    argv = next(command['argv'] for command in commands if command['label'] == label)
    require(argv[0] == str(SDK / 'bin/cache/dart-sdk/bin/dart'), f'{label} did not use recorded native Dart')
    definitions = [value.partition('=')[2] for value in argv if value.startswith('-DVBA_CONFORMANCE_BASE64=')]
    require(len(definitions) == 1 and base64.b64decode(definitions[0]) == corpus_bytes, f'{label} compile-time corpus differs')
vm_raw = (EVIDENCE / 'vba-vm.stdout').read_bytes()
js_raw = (EVIDENCE / 'vba-node.stdout').read_bytes()
vm, js = json.loads(vm_raw), json.loads(js_raw)
require(vm_raw == js_raw, 'VM and JS receipt bytes differ')
ids = [case['id'] for case in corpus['cases']]
require(len(ids) == len(set(ids)) == 69, 'Canonical case IDs are incomplete or duplicate')
for label, result in [('vm', vm), ('js', js)]:
    require(result['caseCount'] == 69 and [case['id'] for case in result['cases']] == ids, f'{label} omitted/reordered cases')
    for expected, actual in zip(corpus['cases'], result['cases']):
        require(actual['actual'] == expected['expected'], f'{label} case result differs: {expected["id"]}')
        if 'steps' in expected['expected']:
            require(actual['nativePlanRoundTrip'] is True, f'{label} plan round trip not verified: {expected["id"]}')
parity = read('vba-portable-parity.json')
for key, name in [('fixtureSha256', 'canonical-vba-corpus.json'), ('vmReceiptSha256', 'vba-vm.stdout'), ('javascriptReceiptSha256', 'vba-node.stdout'), ('compiledJavascriptSha256', 'strings.js')]:
    require(parity[key] == sha(EVIDENCE / name), f'Portable artifact hash mismatch: {name}')
require(parity == receipt['portableVba'], 'Portable parity artifact differs from receipt')

# Parse the actual archived wire independently. This is evidence inspection,
# not another unit-test run; no transport or Studio builder is executed here.
fixture = read('mime-fixture.json')
envelope = read('studio-envelope.json')
wire = (EVIDENCE / 'studio-attachment.eml').read_bytes()
message = BytesParser(policy=policy.default).parsebytes(wire)
inspection = read('mime-inspection.json')
require(inspection['checkCount'] == len(inspection['checks']) == 30, 'Unexpected MIME check inventory')
require(all(check['passed'] for check in inspection['checks']), 'Recorded MIME check failed')
require(len({check['name'] for check in inspection['checks']}) == 30, 'Duplicate MIME check name')
require(inspection['rawMimeSha256'] == hashlib.sha256(wire).hexdigest(), 'MIME wire checksum mismatch')
require(inspection['envelopeSha256'] == sha(EVIDENCE / 'studio-envelope.json'), 'Envelope checksum mismatch')
require(all(byte < 128 for byte in wire), 'MIME wire is not ASCII')
bare = wire.replace(b'\r\n', b'')
require(b'\r' not in bare and b'\n' not in bare, 'MIME contains bare newline')
require(message.get_content_type() == 'multipart/mixed', 'Wrong root MIME type')
require(str(message['Subject']) == fixture['subject'], 'Unicode subject differs')
groups = {kind:[address.strip() for address in fixture[kind].split(',')] for kind in ['to', 'cc', 'bcc']}
require(getaddresses(message.get_all('From', [])) == [('', fixture['from'])], 'Sender differs')
for kind in ['to', 'cc']:
    require([address for _,address in getaddresses(message.get_all(kind, []))] == groups[kind], f'Visible {kind} differs')
require(envelope['envelope'] == groups['to'] + groups['cc'] + groups['bcc'], 'Explicit envelope omits/changes recipients')
require(all(envelope[kind] == groups[kind] for kind in groups), 'Envelope group boundaries differ')
require(all(part.get('Bcc') is None for part in message.walk()), 'MIME exposes Bcc header')
require(all(address.encode() not in wire for address in groups['bcc']), 'MIME exposes private Bcc address')
require(not any(part.defects for part in message.walk()), 'MIME parser defects')
require(not any(getattr(value, 'defects', ()) for part in message.walk() for _,value in part.items()), 'MIME header parser defects')
parts = list(message.iter_parts())
require(len(parts) == 2, 'Unexpected mixed root parts')
alternative, attachment = parts
texts = list(alternative.iter_parts())
require(alternative.get_content_type() == 'multipart/alternative' and [p.get_content_type() for p in texts] == ['text/plain', 'text/html'], 'Alternative body order/type differs')
expected_plain = fixture['body'].replace('\r\n', '\n').replace('\n', '\r\n')
expected_html = '<p>' + fixture['body'].replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace('\r\n', '\n').replace('\r', '\n').replace('\n', '<br>') + '</p>'
for part, expected in zip(texts, [expected_plain, expected_html]):
    require(part.get_payload(decode=True).decode('utf-8') == expected, 'Decoded text/whitespace differs')
    require(part['Content-Transfer-Encoding'].lower() == 'quoted-printable', 'Text transport differs')
    lines = part.get_payload().splitlines()
    require(all(len(line) <= 76 and not line.endswith((' ', '\t')) for line in lines), 'Invalid quoted-printable line length/padding')
require(attachment.get_content_disposition() == 'attachment', 'Attachment disposition differs')
require(attachment.get_filename() == fixture['attachmentName'], 'Unicode filename differs')
require(attachment.get_content_type() == 'application/octet-stream' and attachment.get_content_charset() is None, 'Attachment media type/charset differs')
require(attachment.get_payload(decode=True) == base64.b64decode(fixture['attachmentBase64']), 'Binary attachment bytes differ')
require(attachment['Content-Transfer-Encoding'].lower() == 'base64' and all(len(line) <= 76 for line in attachment.get_payload().splitlines()), 'Attachment transfer lines differ')

result = {'audited_at_utc':datetime.now(timezone.utc).isoformat(), 'source_commit':FROZEN, 'status':'verified' if not failures else 'rejected', 'verified_input_counts':dict(counts), 'recorded_inputs_before_after_identical':before == after, 'portable_cases':69, 'portable_actuals_equal_canonical_expected':True if not failures else None, 'portable_receipts_byte_identical':vm_raw == js_raw, 'mime_recorded_assertions':30, 'mime_wire_independently_reparsed':True, 'additional_distinct_unit_tests':0, 'failures':failures, 'auditor_sha256':sha(Path(__file__)), 'imported_auditor_sha256':sha(OUT/'audit_validation.py'), 'receipt_sha256':sha(EVIDENCE/'receipt.json'), 'limits':['No application commands, network calls, transport sends, or tests were executed by this auditor.', 'The69 portable cases overlap the main VBA conformance unit suite; MIME assertions are supplemental receiver checks, not additional unit cases.', 'Existing-evidence auditing requires the recorded checkout, SDK and dependency filesystem layout; the separate qualification runner recreates evidence for another environment.']}
(OUT / 'supplemental-audit.json').write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
print(json.dumps(result,indent=2))
raise SystemExit(1 if failures else 0)

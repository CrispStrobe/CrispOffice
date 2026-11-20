#!/usr/bin/env python3
"""Exercise the production Studio builder and an independent Python receiver.

Requires the repository's resolved locked package configuration and its pinned
Dart runtime. No substituted libraries, network requests, or live sending.
"""

from __future__ import annotations

import argparse
import datetime as dt
import email.policy
import hashlib
import json
import pathlib
import platform
import subprocess
import sys
import time
from email.parser import BytesParser
from email.utils import getaddresses


MIB = 1024 * 1024


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_write(path: pathlib.Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def normalize_newlines(text: str) -> str:
    return text.replace('\r\n', '\n').replace('\n', '\r\n')


def source_snapshot(repo: pathlib.Path, scripts: pathlib.Path) -> dict:
    paths = set()
    for pattern in (
        'packages/quds_office_editor/example/lib/studio_mail_*.dart',
        'packages/quds_mail_core/lib/**/*.dart',
        'packages/quds_mail_mime/lib/**/*.dart',
        'third_party/enough_mail/lib/**/*.dart',
    ):
        paths.update(repo.glob(pattern))
    paths.update([repo / 'pubspec.lock', repo / '.dart_tool/package_config.json'])
    result = {
        str(path.relative_to(repo)): sha(path.read_bytes())
        for path in sorted(paths)
    }
    result.update({
        'probe/' + name: sha((scripts / name).read_bytes())
        for name in ('run_probe.py', 'attachment_mime_probe.dart')
    })
    return result


def fixtures(output: pathlib.Path) -> list[dict]:
    folder = output / 'fixtures'
    folder.mkdir(parents=True, exist_ok=True)

    def file(case: str, index: int, name: str, content: bytes, media: str) -> dict:
        path = f'{case}-{index}.bin'
        (folder / path).write_bytes(content)
        return {'path': path, 'name': name, 'length': len(content),
                'sha256': sha(content), 'mediaType': media}

    def case(id: str, body: str, files: list[dict]) -> dict:
        path = f'{id}-body.txt'
        (folder / path).write_bytes(body.encode('utf-8'))
        return {'id': id, 'subject': 'Anlage مرفق 📎', 'bodyPath': path,
                'bodyUtf8Bytes': len(body.encode('utf-8')), 'files': files}

    ordinary = 'unicode-binary'
    ordinary_files = [
        file(ordinary, 0, 'سجل "alpha"; 100%😀.pdf',
             bytes(range(256)) * 16 + b'\x7f', 'application/pdf'),
        file(ordinary, 1, 'empty.bin', b'', 'application/octet-stream'),
        file(ordinary, 2, 'legacy.txt', b'\xff\x80\x00\x0a', 'text/plain'),
        file(ordinary, 3, 'duplicate.txt', b'first\x00\xff', 'text/plain'),
        file(ordinary, 4, 'duplicate.txt', b'second\x01\xfe', 'text/plain'),
        file(ordinary, 5, '\u00e9' * 125 + 'a.pdf', b'boundary', 'application/pdf'),
    ]
    bound_files = []
    for index in range(10):
        pattern = bytes((offset * 31 + index * 17) % 256 for offset in range(256))
        bound_files.append(file(
            'maximum-bound', index, f'payload-{index}-مرفق.bin',
            pattern * (MIB // 256), 'application/octet-stream'))
    result = [
        case(ordinary,
             'Hello <reader> & "quoted"\nLine ending in space \r\n'
             'Line ending in tab\t\nمتن 😀 = 100%\nLast \t', ordinary_files),
        case('plain-control', 'Plain مرحبًا <reader> & "quoted" = ✓', []),
        case('maximum-bound', '"' * MIB, bound_files),
    ]
    json_write(folder / 'fixtures.json', result)
    return result


def require(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)


def verify_python(output: pathlib.Path, cases: list[dict]) -> list[dict]:
    reports = []
    for fixture in cases:
        id = fixture['id']
        wire = (output / f'{id}.eml').read_bytes()
        require(all(byte < 128 for byte in wire), f'{id}: ASCII-safe wire')
        require(b'hidden@example.invalid' not in wire, f'{id}: hidden recipient')
        require(b'\n' not in wire.replace(b'\r\n', b''), f'{id}: no bare LF')
        require(b'\r' not in wire.replace(b'\r\n', b''), f'{id}: no bare CR')
        maximum_line = max(map(len, wire.split(b'\r\n')))
        require(maximum_line <= 998, f'{id}: SMTP line length {maximum_line}')
        parsed = BytesParser(policy=email.policy.default).parsebytes(wire)
        defects = [type(defect).__name__ for part in parsed.walk()
                   for defect in part.defects]
        require(not defects, f'{id}: parser defects {defects}')
        for part in parsed.walk():
            require(part.get('Bcc') is None, f'{id}: Bcc header')
        require(str(parsed['Subject']) == fixture['subject'], f'{id}: subject')
        require(str(parsed['In-Reply-To']) == '<parent@example.invalid>',
                f'{id}: In-Reply-To')
        require(str(parsed['References']).split() ==
                ['<root@example.invalid>', '<parent@example.invalid>'],
                f'{id}: References')
        require(getaddresses(parsed.get_all('To', [])) ==
                [('', 'reader@example.invalid')], f'{id}: To')
        require(getaddresses(parsed.get_all('Cc', [])) ==
                [('', 'copy@example.invalid')], f'{id}: Cc')
        require(getaddresses(parsed.get_all('From', [])) ==
                [('', 'writer@example.invalid')], f'{id}: From')
        children = list(parsed.iter_parts())
        if fixture['files']:
            require(parsed.get_content_type() == 'multipart/mixed',
                    f'{id}: mixed root')
            alternative, *attachments = children
        else:
            require(parsed.get_content_type() == 'multipart/alternative',
                    f'{id}: plain alternative root')
            alternative, attachments = parsed, []
        require(alternative.get_content_type() == 'multipart/alternative',
                f'{id}: alternative child')
        body_parts = list(alternative.iter_parts())
        require([part.get_content_type() for part in body_parts] ==
                ['text/plain', 'text/html'], f'{id}: body order')
        body = (output / 'fixtures' / fixture['bodyPath']).read_bytes().decode('utf-8')
        escaped = (body.replace('&', '&amp;').replace('<', '&lt;')
                   .replace('>', '&gt;').replace('"', '&quot;')
                   .replace('\r\n', '\n').replace('\r', '\n')
                   .replace('\n', '<br>'))
        expected_bodies = [normalize_newlines(body), '<p>' + escaped + '</p>']
        for index, (part, expected) in enumerate(zip(body_parts, expected_bodies)):
            require(part['Content-Transfer-Encoding'] == 'quoted-printable',
                    f'{id}: body encoding {index}')
            require(part.get_content_charset() == 'utf-8', f'{id}: charset {index}')
            actual = part.get_payload(decode=True).decode('utf-8')
            require(actual == expected, f'{id}: exact body {index}')
            qp_lines = str(part.get_payload()).split('\r\n')
            require(all(len(line) <= 76 for line in qp_lines), f'{id}: QP width')
            require(all(not line.endswith((' ', '\t')) for line in qp_lines),
                    f'{id}: QP terminal padding')
        require(len(attachments) == len(fixture['files']), f'{id}: attachment count')
        payloads = []
        for index, (part, expected) in enumerate(zip(attachments, fixture['files'])):
            require(part.get_content_disposition() == 'attachment',
                    f'{id}: attachment disposition {index}')
            require(part.get_filename() == expected['name'], f'{id}: filename {index}')
            require(part.get_param('name') == expected['name'], f'{id}: name {index}')
            require(part.get_content_type() == expected['mediaType'],
                    f'{id}: media type {index}')
            require(part.get_content_charset() is None, f'{id}: no guessed charset {index}')
            require(part['Content-Transfer-Encoding'] == 'base64',
                    f'{id}: base64 attachment {index}')
            require(int(part.get_param('size', header='Content-Disposition')) ==
                    expected['length'], f'{id}: declared size {index}')
            payload = part.get_payload(decode=True)
            original = (output / 'fixtures' / expected['path']).read_bytes()
            require(payload == original, f'{id}: exact binary payload {index}')
            require(sha(payload) == expected['sha256'], f'{id}: payload hash {index}')
            payloads.append({'name': expected['name'], 'bytes': len(payload),
                             'sha256': sha(payload)})
        outer_base64 = ((len(wire) + 2) // 3) * 4
        # Explicit upper estimate: canonical message + one request-only Bcc field,
        # outer base64, and an intentionally generous 1 KiB JSON/SOAP allowance.
        private_wire = len(wire) + len(b'Bcc: hidden@example.invalid\r\n')
        estimated_request = ((private_wire + 2) // 3) * 4 + 1024
        require(len(wire) <= 22 * MIB, f'{id}: canonical wire bound')
        require(estimated_request <= 32 * MIB, f'{id}: cloud request estimate')
        if id == 'maximum-bound':
            require(sum(item['length'] for item in fixture['files']) == 10 * MIB,
                    'exact maximum payload')
            require(len(body.encode('utf-8')) == MIB, 'exact maximum body')
            require(len(expected_bodies[1].encode('utf-8')) == 6 * MIB + 7,
                    'maximum quote-expansion HTML size')
        reports.append({
            'id': id, 'status': 'passed', 'wireBytes': len(wire),
            'wireSha256': sha(wire), 'maximumLineBytes': maximum_line,
            'outerBase64Bytes': outer_base64,
            'privateRequestUpperEstimateBytes': estimated_request,
            'parserDefects': defects, 'attachments': payloads,
            'plainBodySha256': sha(expected_bodies[0].encode('utf-8')),
            'htmlBodySha256': sha(expected_bodies[1].encode('utf-8')),
            'bodyBytes': [len(item.encode('utf-8')) for item in expected_bodies],
            'canonicalBccAbsent': True, 'threadHeadersPreserved': True,
        })
    return reports


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=pathlib.Path, required=True)
    parser.add_argument('--dart', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    scripts = pathlib.Path(__file__).resolve().parent
    output.mkdir(parents=True, exist_ok=True)
    before = source_snapshot(repo, scripts)
    json_write(output / 'source-inputs-before.json', before)
    cases = fixtures(output)
    command = [str(args.dart.resolve()),
               f'--packages={repo}/.dart_tool/package_config.json',
               str(scripts / 'attachment_mime_probe.dart'),
               str(output / 'fixtures/fixtures.json'), str(output)]
    receipt = {
        'startedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
        'gitHead': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo,
                                            text=True).strip(),
        'gitTree': subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=repo,
                                            text=True).strip(),
        'pythonVersion': platform.python_version(),
        'dartVersion': subprocess.run([str(args.dart), '--version'], cwd=repo,
                                     text=True, capture_output=True).stdout.strip(),
        'command': command,
        'sourceFileCount': len(before),
        'status': 'running',
        'scope': 'Production builder and codec; independent Python MIME receiver. '
                 'Synthetic fixtures only. No real account or live submission.',
    }
    json_write(output / 'receipt.json', receipt)
    start = time.monotonic()
    result = subprocess.run(command, cwd=repo, capture_output=True, text=True)
    (output / 'dart-stdout.log').write_text(result.stdout)
    (output / 'dart-stderr.log').write_text(result.stderr)
    receipt['dartExitCode'] = result.returncode
    try:
        require(result.returncode == 0, 'Dart probe failed; see dart-stderr.log')
        receiver = verify_python(output, cases)
        json_write(output / 'python-receiver-results.json', receiver)
        after = source_snapshot(repo, scripts)
        json_write(output / 'source-inputs-after.json', after)
        require(before == after, 'Production/probe source changed during run')
        receipt.update(status='passed', cases=len(cases),
                       sourceUnchangedDuringRun=True,
                       pythonReceiverVerified=True,
                       dartProductionRoundtripVerified=True)
    except Exception as error:
        receipt.update(status='failed', error=f'{type(error).__name__}: {error}')
    receipt['elapsedSeconds'] = round(time.monotonic() - start, 3)
    receipt['finishedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    json_write(output / 'receipt.json', receipt)
    print(json.dumps(receipt, ensure_ascii=False, indent=2))
    return 0 if receipt['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())

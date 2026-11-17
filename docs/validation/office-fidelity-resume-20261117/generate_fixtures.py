#!/usr/bin/env python3
"""Bind test-produced and supplementary ODF packages to a qualified source."""
import argparse
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

REPO = Path(__file__).resolve().parents[3]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    engine = args.engine.resolve()
    output = args.output.resolve()
    require(not output.exists() or not any(output.iterdir()), 'Generation output must be empty')
    output.mkdir(parents=True, exist_ok=True)
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()
    engine_receipt = json.loads((engine / 'receipt.json').read_text())
    require(engine_receipt.get('passed') is True
            and engine_receipt.get('head_before') == engine_receipt.get('head_after') == source,
            'Engine receipt must qualify the current source commit')
    generator = REPO / 'docs/validation/office-fidelity-continuation-20261117/make_fixtures.dart'
    inputs = dict(engine_receipt['source_before_sha256'])
    inputs[str(generator.relative_to(REPO))] = sha(generator.read_bytes())
    inputs[str(Path(__file__).resolve().relative_to(REPO))] = sha(Path(__file__).read_bytes())

    def source_matches():
        return all((REPO / name).is_file() and sha((REPO / name).read_bytes()) == digest
                   for name, digest in inputs.items())

    require(source_matches(), 'Source inputs changed after the qualified engine run')
    report = {'started_utc': now(), 'source_commit': source,
              'engine_receipt_sha256': sha((engine / 'receipt.json').read_bytes()),
              'script_sha256': sha(Path(__file__).read_bytes()),
              'generator_sha256': sha(generator.read_bytes()),
              'source_inputs_sha256': sha(json.dumps(inputs, sort_keys=True).encode()),
              'github_actions_used': False}
    command = ['dart', 'run', str(generator), str(output / 'supplemental')]
    process = subprocess.run(command, cwd=REPO, capture_output=True, timeout=180)
    for kind, data in (('stdout', process.stdout), ('stderr', process.stderr)):
        (output / (kind + '.gz')).write_bytes(gzip.compress(data, mtime=0))
    report.update(command=command, exit_code=process.returncode,
                  stdout_sha256=sha(process.stdout), stderr_sha256=sha(process.stderr))
    fixtures = {}
    for directory in (engine / 'odf-fixtures', output / 'supplemental'):
        for path in sorted(directory.rglob('*')):
            if path.is_file() and path.suffix in ('.odt', '.odp'):
                digest = sha(path.read_bytes())
                require(path.name not in fixtures or fixtures[path.name] == digest,
                        'Conflicting ODF fixture names')
                fixtures[path.name] = digest
    head_after = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()
    report.update(finished_utc=now(), source_inputs_unchanged=source_matches(),
                  source_commit_after=head_after, fixtures_sha256=fixtures,
                  passed=process.returncode == 0 and bool(fixtures) and source_matches()
                         and source == head_after)
    (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'fixtures': len(fixtures)}), flush=True)
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()

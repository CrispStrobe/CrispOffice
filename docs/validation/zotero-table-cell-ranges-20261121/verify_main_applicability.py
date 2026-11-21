#!/usr/bin/env python3
"""Verify the one explicitly reviewed PR #290 delta against frozen qualification."""

import argparse
import gzip
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile

sys.dont_write_bytecode = True
from verify_evidence import digest, require, source_paths

QUALIFIED = 'a6095c304ad2d6935f2ae6f8b74412038d19f142'
PREVIOUS_MAIN = 'e2abbcda6d19f932bfbacc85e0dafd41a3c478f8'
INCOMING_MAIN = 'eb286fb7254d6850c9f33b46e8aa65e2ea32f7f0'
GATE = 'packages/quds_office_editor/example/test/app_store_screenshots_gate.dart'
IMAGES = {
    'docs/release/app-store-screenshots/' + name for name in (
        '01-word-english-arabic.png', '02-german-grammar.png', '03-excel.png',
        '04-powerpoint.png', '05-mail.png', '06-downloads.png',
    )
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    directory = Path(__file__).resolve().parent

    def git(*values):
        return subprocess.check_output(['git', *values], cwd=repo)

    subprocess.run([sys.executable, str(directory / 'verify_evidence.py'),
                    '--archive-only'], check=True, capture_output=True)
    index = json.loads((directory / 'evidence-index.json').read_text())
    require(index['qualified_commit'] == QUALIFIED, 'Unexpected qualified commit')
    with tarfile.open(directory / index['archive'], 'r:xz') as archive:
        frozen = json.loads(gzip.decompress(
            archive.extractfile(index['qualified_source_member']).read()
        ))
        node_source = json.loads(archive.extractfile('portable/source-before.json').read())
        require(node_source == json.loads(archive.extractfile('portable/source-after.json').read()),
                'Portable source changed during execution')
        command_members = [member for member in archive.getmembers()
                           if member.name.startswith('qualification/frozen-')
                           and member.name.endswith('/command.json')]
        require(len(command_members) == 8, 'Unexpected execution command population')
        for member in command_members:
            require(b'app_store_screenshots_gate' not in archive.extractfile(member).read(),
                    f'Gate appears in executed command: {member.name}')

    delta = set(git('diff', '--name-only', PREVIOUS_MAIN, INCOMING_MAIN).decode().splitlines())
    require(delta == IMAGES | {GATE}, 'Incoming main has an unreviewed delta')
    actual_paths = source_paths(repo)
    require(actual_paths == set(frozen), 'Recorded source path population changed')
    mismatches = []
    for path, record in frozen.items():
        source = repo / path
        data = source.read_bytes()
        if (len(data) != record['size'] or digest(data) != record['sha256']
                or bool(source.stat().st_mode & 0o111) != record['executable']):
            mismatches.append(path)
    require(mismatches == [GATE], f'Unexpected source delta: {mismatches}')
    require(len(node_source) == 356, 'Unexpected portable source population')
    for path, recorded_digest in node_source.items():
        require(path in frozen and digest((repo / path).read_bytes()) == recorded_digest
                and frozen[path]['sha256'] == recorded_digest,
                f'Portable source changed: {path}')
    require(frozen[GATE]['sha256'] == '0f6251901f611a8ce83474a0d5b8c2be7a7086dffe2ad98c1c8c2508edaccf91',
            'Unexpected original screenshot gate')

    preserved = []
    for path in sorted(delta):
        mode, kind, blob = git('ls-tree', INCOMING_MAIN, '--', path).decode().split('\t', 1)[0].split()
        require(kind == 'blob', f'Unexpected incoming object: {path}')
        expected = git('cat-file', 'blob', blob)
        current = (repo / path).read_bytes()
        require(current == expected, f'Incoming main file changed: {path}')
        require(bool((repo / path).stat().st_mode & 0o111) == (mode == '100755'),
                f'Incoming main mode changed: {path}')
        preserved.append({'path': path, 'git_blob_sha1': blob, 'mode': mode,
                          'size': len(current), 'sha256': digest(current)})

    new_gate = (repo / GATE).read_text()
    old_gate = git('show', QUALIFIED + ':' + GATE).decode()
    imports = re.compile(r'^\s*(?:import|export|part)\s+.*?;\s*$', re.M)
    require(imports.findall(old_gate) == imports.findall(new_gate), 'Gate import declarations changed')
    require(digest(new_gate.encode()) == '752600587362d2e3bc9a6c5bc2533aa643cfe4461331acec96eafbbad1819581',
            'Unexpected incoming screenshot gate')

    qualification = json.loads((directory / 'qualification.json').read_text())
    selected = qualification['selected_test_files']
    require(len(selected) == len(set(selected)) == 119, 'Unexpected selected suite population')
    require(not set(selected) & delta, 'Executed suite changed')
    inbound = []
    for path in sorted(actual_paths - {GATE}):
        if Path(path).suffix in ('.dart', '.yaml'):
            if b'app_store_screenshots_gate' in (repo / path).read_bytes():
                inbound.append(path)
    require(not inbound, f'Inbound screenshot gate reference: {inbound}')

    result = {
        'status': 'applicable-with-explicit-unexecuted-main-delta',
        'qualified_commit': QUALIFIED,
        'previous_main': PREVIOUS_MAIN,
        'incorporated_main': INCOMING_MAIN,
        'pull_request': 290,
        'qualified_source_inputs': len(frozen),
        'unchanged_recorded_inputs': len(frozen) - len(mismatches),
        'changed_recorded_inputs': mismatches,
        'all_recorded_inputs_identical': False,
        'executed_suite_files_unchanged': len(selected),
        'unchanged_portable_source_inputs': len(node_source),
        'executed_cohort_commands_without_screenshot_gate': len(command_members),
        'unique_vm_cases_retaining_applicability': 2551,
        'overlapping_node_cases_retaining_applicability': 121,
        'incoming_files_preserved_exactly': preserved,
        'gate_imports_unchanged': True,
        'inbound_gate_references_in_other_recorded_dart_yaml_sources': inbound,
        'basis': 'Only one independent, unselected screenshot gate and six documentation images changed; Zotero product, all selected suites, fixtures, manifests and locks are unchanged.',
        'scope_limit': 'No new screenshot execution or full-suite rerun is claimed. The original qualification remains bound to its original commit; this receipt establishes the reviewed delta applicability.',
    }
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in (
        'status', 'incorporated_main', 'qualified_source_inputs',
        'unchanged_recorded_inputs', 'changed_recorded_inputs',
        'executed_suite_files_unchanged', 'all_recorded_inputs_identical',
    )}, indent=2))


if __name__ == '__main__':
    main()

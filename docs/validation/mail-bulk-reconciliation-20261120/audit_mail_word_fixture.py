#!/usr/bin/env python3
"""Check that the corrected Word-only test fixture is outside the Mail inputs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urljoin, urlparse


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--mail-receipt', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    fixture = 'packages/quds_office_engine/test/word_contained_text_wrap_test.dart'
    original = json.loads((args.mail_receipt / 'source-after.json').read_text())
    cases = json.loads((args.mail_receipt / 'test-cases.json').read_text())
    entries = sorted({row['file'] for row in cases})
    configuration = repo / '.dart_tool/package_config.json'
    package_roots = {}
    for entry in json.loads(configuration.read_text())['packages']:
        root = Path(unquote(urlparse(urljoin(configuration.as_uri(), entry['rootUri'])).path)).resolve()
        package_roots[entry['name']] = root / entry.get('packageUri', 'lib/')
    pending = [repo / path for path in entries]
    visited = {}
    target_references = []
    engine_test_directory_references = []
    enumeration_lines = []
    directive = re.compile(r'\b(?:import|export|part)\s+([^;]+);', re.DOTALL)
    quoted = re.compile(r"['\"]([^'\"]+)['\"]")
    while pending:
        path = pending.pop().resolve()
        if not path.is_file() or not path.is_relative_to(repo):
            continue
        relative = str(path.relative_to(repo))
        if relative in visited:
            continue
        source = path.read_text(errors='replace')
        visited[relative] = digest(path)
        for line_number, line in enumerate(source.splitlines(), 1):
            if 'word_contained_text_wrap' in line:
                target_references.append({'file': relative, 'line': line_number, 'text': line.strip()})
            if re.search(r'quds_office_engine[/\\]+test', line):
                engine_test_directory_references.append({'file': relative, 'line': line_number, 'text': line.strip()})
            if re.search(r'\.list(?:Sync)?\s*\(', line):
                enumeration_lines.append({'file': relative, 'line': line_number, 'text': line.strip()})
        for group in directive.findall(source):
            for uri in quoted.findall(group):
                if not uri.endswith('.dart') or uri.startswith('dart:'):
                    continue
                if uri.startswith('package:'):
                    package, separator, tail = uri[8:].partition('/')
                    if separator and package in package_roots:
                        pending.append(package_roots[package] / tail)
                elif ':' not in uri:
                    pending.append(path.parent / uri)
    assert fixture not in entries and fixture not in visited
    assert not target_references and not engine_test_directory_references
    record = {
        'status': 'passed',
        'repository_head_at_audit': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
        'fixture': fixture,
        'original_sha256': original[fixture]['sha256'],
        'corrected_sha256': digest(repo / fixture),
        'mail_suite_entries': entries,
        'mail_suite_count': len(entries),
        'repo_sources_reachable_by_import_export_part': dict(sorted(visited.items())),
        'reachable_source_count': len(visited),
        'target_in_selected_mail_suites': False,
        'target_in_reachable_dart_sources': False,
        'target_name_references': target_references,
        'engine_test_directory_references': engine_test_directory_references,
        'filesystem_enumeration_lines_for_review': enumeration_lines,
        'method': 'Traverse local import/export/part URIs (including both conditional branches) from the 50 actual Mail test entry files; check target-name and engine-test-directory references. External SDK/hosted libraries are covered by the unchanged dependency seal.',
        'script_sha256': digest(__file__),
    }
    args.out.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'status': record['status'], 'mail_suites': len(entries),
                      'reachable_sources': len(visited), 'enumeration_lines': len(enumeration_lines)}, indent=2))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Describe immutable publication changes without claiming a fresh test run."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess


def git(repo, *args):
    return subprocess.check_output(['git', *args], cwd=repo)


def tree(repo, commit):
    result = {}
    for row in git(repo, 'ls-tree', '-rz', commit).split(b'\0'):
        if row:
            header, path = row.split(b'\t', 1)
            mode, kind, oid = header.decode().split()
            result[path.decode()] = {'mode': mode, 'type': kind, 'oid': oid}
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--base', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    base = git(args.repo, 'rev-parse', '--verify', args.base).decode().strip()
    candidate = git(args.repo, 'rev-parse', '--verify', args.candidate).decode().strip()
    before, after = tree(args.repo, base), tree(args.repo, candidate)
    changed = {name: {'before': before.get(name), 'after': after.get(name)}
               for name in sorted(set(before) | set(after)) if before.get(name) != after.get(name)}
    manifest_paths = [name for name in changed if Path(name).name in {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'}]
    application_paths = [name for name in changed if name.startswith(('packages/', 'third_party/', 'apps/'))
                         and not name.endswith('.md')]
    zotero_paths = [name for name in application_paths if 'zotero' in name.lower()]
    engine_production_paths = [name for name in application_paths if name.startswith('packages/quds_office_engine/lib/')]
    editor_library_paths = [name for name in application_paths if name.startswith('packages/quds_office_editor/lib/')]
    mail_paths = [name for name in application_paths if '/quds_mail_' in name or '/enough_mail/' in name or '/studio_mail_' in name]
    facts = 'packages/quds_office_engine/lib/src/proofing/german_agreement_facts.dart'
    original_facts = git(args.repo, 'show', f'{base}:{facts}')
    current_facts = git(args.repo, 'show', f'{candidate}:{facts}')
    appended_facts = current_facts.startswith(original_facts)
    assert manifest_paths == []
    assert zotero_paths == []
    assert editor_library_paths == []
    assert mail_paths == []
    assert engine_production_paths == [facts] and appended_facts
    result = {
        'status': 'reviewed_publication_delta',
        'audited_at_utc': datetime.now(timezone.utc).isoformat(),
        'base_commit': base,
        'candidate_commit': candidate,
        'candidate_tree': git(args.repo, 'rev-parse', f'{candidate}^{{tree}}').decode().strip(),
        'verifier_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'changed_path_count': len(changed),
        'changed_paths': changed,
        'application_paths': application_paths,
        'manifest_lock_analysis_changes': manifest_paths,
        'zotero_source_and_test_changes': zotero_paths,
        'editor_library_changes': editor_library_paths,
        'mail_source_and_test_changes': mail_paths,
        'engine_production_changes': engine_production_paths,
        'engine_existing_facts_bytes_preserved_as_exact_prefix': appended_facts,
        'engine_appended_fact_bytes': len(current_facts) - len(original_facts),
        'reviewed_behavior': [
            'The engine changes only append read-only German grammar fact classes; all prior bytes in that part remain identical.',
            'Studio changes add native grammar family settings and synchronize grammar provider configuration when UI language changes.',
            'The spaCy package adds optional grammar families and signature-independent Mach-O code identity support.',
            'A follow-on Studio test explicitly sets its German document language; macOS packaging fixes remain separate incoming work.',
        ],
        'fresh_gate_selection': {
            'engine-proofing': 'All 37 proofing test files, including top-level and nested paths.',
            'spacy': 'All 11 package test files.',
            'studio-integration': 'Nine explicit setup, pin, downloads, language, comment and Zotero integration files.',
            'zotero': 'All 29 engine and 43 editor Zotero test files.',
            'static': 'Strict analysis and formatting of the final changed Dart targets.',
        },
        'limits': [
            'This assessment runs no tests; fresh gate results are recorded separately.',
            'The aggregate engine import closure includes the appended German facts, so it is not byte-identical to historical acceptance.',
            'VBA, rendering, DOCX and Mail implementation/test paths are unchanged; their saved tests retain their original source attribution.',
            'Linux gates do not rerun native macOS signing, installed-application, live-account or Office interoperability acceptance.',
        ],
    }
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: result[key] for key in ['status', 'candidate_commit', 'changed_path_count',
                                                 'engine_existing_facts_bytes_preserved_as_exact_prefix']}))


if __name__ == '__main__':
    main()

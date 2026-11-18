#!/usr/bin/env python3
"""Collect four source-bound consumer gates without reusing historical outcomes."""
import argparse
import datetime
import gzip
import hashlib
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text())


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    rows = []
    for name, count in [('frame5', 5), ('retained33', 33), ('current7', 7), ('boundary5', 5)]:
        folder = root / f'consumer-{name}-{args.commit[:8]}'
        guard = read(folder / 'guard/receipt.json')
        assert guard['source_commit'] == args.commit and guard['passed']
        assert guard['child_exit_code'] == 0
        assert guard['source_bytes_match_frozen_commit_before_and_after']
        assert guard['runtime_and_workspace_unchanged']
        before = json.loads(gzip.decompress((folder / 'guard/inputs-before.json.gz').read_bytes()))
        after = json.loads(gzip.decompress((folder / 'guard/inputs-after.json.gz').read_bytes()))
        assert before == after
        path = folder / ('run/summary.json' if name == 'frame5' else 'run/receipt.json')
        report = read(path)
        if name == 'frame5':
            assert report['head_at_start'] == args.commit and report['source_inputs_unchanged']
            assert report['fixture_passes'] == report['fixture_count'] == count
            assert report['jing_valid'] == report['schema_parts'] == 20
            summary = {key: report[key] for key in ['fixture_count', 'fixture_passes', 'schema_parts', 'jing_valid', 'lxml_valid']}
        elif name in ('retained33', 'current7'):
            assert report['source_head'] == args.commit and report['passed']
            summary = report['summary']
            assert summary['fixtures'] == summary['passed'] == count and summary['failed'] == 0
            assert summary['schema_parts_passed'] == summary['schema_parts_total'] == 4 * count
        else:
            assert report['source_commit'] == args.commit and report['passed'] and report['inputs_unchanged']
            fixtures = report['fixtures']
            assert len(fixtures) == count
            variants = [value for fixture in fixtures for value in fixture['variants'].values()]
            summary = {'fixtures': count, 'passed': count,
                       'pdf_variants': sum('pdf' in variant for variant in variants),
                       'reopened_docx': sum('docx' in variant for fixture in fixtures
                                            for variant_name, variant in fixture['variants'].items()
                                            if variant_name != 'source'),
                       'schema_parts': sum(len(variant['odt']['schema_accepted_parts']) for variant in variants if 'odt' in variant)}
            assert summary['pdf_variants'] == 15 and summary['reopened_docx'] == 10 and summary['schema_parts'] == 40
        archive = folder.with_suffix('.tar.xz')
        index = archive.with_suffix('.index.json')
        manifest = read(index)
        assert manifest['readback_verified'] and sha(archive) == manifest['sha256']
        rows.append({'gate': name, 'source_commit': args.commit, 'passed': True,
                     'summary': summary, 'guard_sha256': sha(folder / 'guard/receipt.json'),
                     'report_sha256': sha(path),
                     'source_files_checked': guard['source_file_count'],
                     'runtime_files_checked': guard['runtime_and_workspace_file_count'],
                     'archive': archive.name, 'archive_sha256': manifest['sha256'],
                     'archive_bytes': manifest['bytes'], 'member_count': manifest['member_count'],
                     'index': index.name, 'index_sha256': sha(index)})
    result = {'completed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'source_commit': args.commit, 'all_passed': True, 'fixtures': 50,
              'retained_fixtures': 40, 'frame_field_fixtures': 5, 'boundary_fixtures': 5,
              'accepted_odf_xml_parts': 220, 'historical_outcomes_counted': False,
              'github_actions_queried_or_awaited': False, 'gates': rows,
              'scope': 'Bounded current-writer consumers on the pinned LibreOfficeDev26.8 runtime; arbitrary imported-document fidelity and complete DOCX field-result formatting are not qualified.',
              'schema_note': 'Official ODF1.3 schemas. Jing governs the frame/current-field groups; known lxml nested page-count disagreements remain diagnostic. Boundary controls use the retained RelaxNG checker.'}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ['source_commit', 'all_passed', 'fixtures', 'accepted_odf_xml_parts']}))


if __name__ == '__main__':
    main()

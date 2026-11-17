#!/usr/bin/env python3
"""Independently check the retained combined-boundary consumer observations."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', type=Path, required=True)
    root = parser.parse_args().evidence.resolve()
    interaction = root / 'section-explicit-page-interaction'
    receipt = json.loads((interaction / 'receipt.json').read_text())
    checks = []
    expected_pages = {
        'later-next-page': 2, 'later-continuous': 2,
        'later-odd-page': 3, 'later-even-page': 2,
    }
    for item in receipt['observations']:
        name = item['name']
        case = next(k for k in expected_pages if name.startswith(k + '.'))
        targets = [w for w in item['words'] if not w['text'].endswith('Before')]
        before = [w for w in item['words'] if w['text'].endswith('Before')]
        passed = (
            item['pages'] == expected_pages[case] and len(before) == 1
            and before[0]['page'] == 1 and abs(before[0]['xMin'] - 36) <= .4
            and len(targets) == 3
            and all(w['page'] == expected_pages[case] and abs(w['xMin'] - 318) <= .4
                    for w in targets)
            and all(a['yMin'] < b['yMin'] for a, b in zip(targets, targets[1:]))
        )
        checks.append({'variant': name, 'expected_page': expected_pages[case],
                       'expected_right_column_origin_pt': 318,
                       'horizontal_tolerance_pt': .4, 'passed': passed})
    combined = {
        'source_commit': receipt['source_commit'],
        'receipt_sha256': hashlib.sha256((interaction / 'receipt.json').read_bytes()).hexdigest(),
        'case_count': 4, 'pdf_variants': len(checks),
        'writer_inputs_unchanged': receipt['writer_sha256_before'] == receipt['writer_sha256_after'],
        'checks': checks,
        'passed': len(checks) == 12 and all(x['passed'] for x in checks),
    }
    write(interaction / 'audit.json', combined)

    exact = root / 'exact-restored-control'
    receipt = json.loads((exact / 'receipt.json').read_text())
    checks = []
    for item in receipt['observations']:
        native = item['name'].startswith('exact.source')
        fixed = item['variant'] == 'final' or native
        expected = {
            'First': (1, 'left'),
            'Second': (2, 'right' if fixed else 'left'),
            'Continuation': (3 if fixed else 2, 'left' if fixed else 'right'),
        }
        passed = item['pages'] == (3 if fixed else 2)
        positions = {}
        for text, (page, column) in expected.items():
            matches = [w for w in item['words'] if w['text'] == text]
            width = float(item['page_sizes'][page - 1][0])
            x = 72 if column == 'left' else width / 2 + 9
            good = (len(matches) == 1 and matches[0]['page'] == page
                    and abs(matches[0]['xMin'] - x) <= .4)
            passed = passed and good
            positions[text] = {'expected_page': page, 'expected_column': column,
                               'derived_origin_pt': x, 'observed': matches, 'passed': good}
        checks.append({'variant': item['variant'], 'file': item['name'],
                       'expected_pages': 3 if fixed else 2,
                       'positions': positions, 'passed': passed})
    with zipfile.ZipFile(exact / 'final/exact.source.docx') as a, \
         zipfile.ZipFile(exact / 'baseline/exact.source.docx') as b:
        source_equal = a.read('word/document.xml') == b.read('word/document.xml')
    contrast = {
        'source_head': receipt['source_head'], 'baseline_writer': receipt['baseline_writer'],
        'receipt_sha256': hashlib.sha256((exact / 'receipt.json').read_bytes()).hexdigest(),
        'native_source_document_xml_identical': source_equal,
        'geometry_scope': 'Original raw DOCX leaves page size unspecified. LibreOffice chooses '
                          'Letter while engine import chooses A4. This check derives column '
                          'origin separately from each actual page width and asserts authored '
                          'page/column order, not pixel-identical page geometry.',
        'checks': checks,
        'passed': source_equal and len(checks) == 4 and all(x['passed'] for x in checks),
    }
    write(exact / 'audit.json', contrast)
    assert combined['passed'] and combined['writer_inputs_unchanged'] and contrast['passed']
    print(json.dumps({'combined_boundary_variants': 12, 'exact_raw_source_variants': 4,
                      'passed': True}))


if __name__ == '__main__':
    main()

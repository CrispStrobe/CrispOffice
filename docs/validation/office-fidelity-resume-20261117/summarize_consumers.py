#!/usr/bin/env python3
"""Consolidate original passing fixtures and the one corrected RTL oracle.

The initial failed receipt remains intact. Only its failed RTL case may be
replaced, and the input bytes, product source and generation receipt must agree.
"""
import argparse
import hashlib
import json
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.evidence.resolve()
    paths = {name: root / relative for name, relative in {
        'initial': 'odf-consumer/receipt.json',
        'rtl': 'odf-rtl-correction/receipt.json',
        'generation': 'fixture-generation/receipt.json',
        'rotation': 'rotation-consumer/rotation-consumer-report.json',
        'rotation_runtime': 'rotation-consumer/independent-runtime-verification.json',
        'logical_pdf': 'engine/logical-render/poppler-receipt.json',
        'conditional_pdf': 'engine/conditional-render/poppler-receipt.json',
    }.items()}
    reports = {name: json.loads(path.read_text()) for name, path in paths.items()}
    original, correction = reports['initial'], reports['rtl']
    source = reports['generation']['source_commit']
    require(original['source_commit'] == correction['source_commit'] == source,
            'Product source differs between consumer runs')
    require(original['generation_receipt_sha256'] == correction['generation_receipt_sha256']
            == digest(paths['generation']), 'Generation receipt differs')
    require(original['schemas'] == correction['schemas'], 'Schemas changed during the narrow rerun')
    original_files = {item['name']: item for item in original['fixtures']}
    require(len(original_files) == len(original['fixtures']) == 27,
            'Original fixture inventory differs')
    require(original.get('passed') is False and
            {name for name, item in original_files.items() if not item['passed']}
            == {'slide-table-rtl.odp'}, 'Unexpected original failure scope')
    require(correction.get('passed') is True and len(correction['fixtures']) == 1
            and correction['selected_fixtures'] == ['slide-table-rtl.odp'],
            'Correction must qualify only the affected RTL fixture')
    require(correction['verified_fixture_inventory_sha256']
            == reports['generation']['fixtures_sha256']
            == {name: item['input_sha256'] for name, item in original_files.items()},
            'A generated package changed between runs')
    replacement = correction['fixtures'][0]
    require(replacement['name'] == 'slide-table-rtl.odp' and replacement['passed'],
            'Missing successful RTL replacement')
    require(digest(root / 'odf-consumer/slide-table-rtl.png')
            == digest(root / 'odf-rtl-correction/slide-table-rtl.png'),
            'The RTL oracle correction changed the consumer raster')
    accepted = []
    for name, item in original_files.items():
        corrected = name == replacement['name']
        chosen = replacement if corrected else item
        require(chosen['passed'] and len(chosen['schema_parts_passed']) == 4,
                'Unqualified fixture selected: ' + name)
        directory = root / ('odf-rtl-correction' if corrected else 'odf-consumer')
        for artifact, expected in chosen['artifacts_sha256'].items():
            require(digest(directory / artifact) == expected, 'Consumer artifact changed: ' + artifact)
        if 'comment_consumer' in chosen:
            require(digest(directory / 'reopened' / (Path(name).stem + '.docx'))
                    == chosen['comment_consumer']['round_trip_sha256'], 'DOCX evidence changed')
        accepted.append({'name': name, 'input_sha256': chosen['input_sha256'],
                         'receipt': 'rtl' if corrected else 'initial', 'passed': True,
                         'semantic_checks': chosen['semantic_checks'],
                         'comment_consumer': chosen.get('comment_consumer')})
    rotation = reports['rotation']
    rotation_runtime = reports['rotation_runtime']
    require(rotation_runtime['passed'] and rotation_runtime['inputs_unchanged']
            and rotation_runtime['source_head_unchanged']
            and rotation_runtime['font_inventory_unchanged']
            and rotation_runtime['expected_source_commit'] == source,
            'Rotation runtime/font binding did not pass')
    require(rotation['passed'] and not rotation['errors']
            and rotation['input_mode'] == 'generated_by_this_run'
            and rotation['source_before'] == rotation['source_after']
            and rotation['source_before']['git_head'] == source, 'Rotation source/result mismatch')
    require(len(rotation['files']) == 16, 'Rotation fixture inventory differs')
    for item in rotation['files']:
        require(len(item['xml']) == 4 and all(part['valid'] for part in item['xml']),
                'Rotation fixture schema failure')
        for suffix, key in (('.pdf', 'pdf_sha256'), ('.png', 'png_sha256')):
            require(digest(root / 'rotation-consumer' / (item['name'] + suffix)) == item[key],
                    'Rotation artifact changed: ' + item['name'] + suffix)
    logical = reports['logical_pdf']
    require(logical['passed'] and len(logical['fixtures']) == 3
            and all(item['different_pixels'] == 0 for item in logical['fixtures']),
            'Logical PDF paint comparison failed')
    for item in logical['fixtures']:
        for name, expected in item['files_sha256'].items():
            require(digest(root / 'engine/logical-render' / name) == expected,
                    'Logical PDF evidence changed: ' + name)
    conditional = reports['conditional_pdf']
    require(conditional['status'] == 'passed', 'Conditional-style PDF check failed')
    result = {
        'passed': True, 'product_source': source, 'script_sha256': digest(Path(__file__)),
        'receipts_sha256': {name: digest(path) for name, path in paths.items()},
        'general_fixtures': accepted, 'general_fixture_count': len(accepted),
        'rotation_fixture_count': len(rotation['files']),
        'named_odf_fixture_count': len(accepted) + len(rotation['files']),
        'xml_part_validations': 4 * (len(accepted) + len(rotation['files'])),
        'rotation_color_geometry_checks': sum(len(item['colors']) for item in rotation['files']),
        'rotation_bound_input_count': rotation_runtime['input_count'],
        'rotation_bound_font_count': rotation_runtime['fonts_count'],
        'logical_pdf_differing_pixels': {item['name']: item['different_pixels'] for item in logical['fixtures']},
        'conditional_pdf_passed': True,
        'initial_consumer_attempt_passed': False,
        'corrected_fixture': replacement['name'],
        'rtl_consumer_raster_unchanged': True,
        'correction_scope': 'Verifier-only Arabic word identity correction; fresh RTL render and exact full input inventory check. Other 26 passing fixtures retained.',
        'github_actions_used': False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({key: result[key] for key in ('passed', 'named_odf_fixture_count',
                                                  'xml_part_validations', 'rotation_color_geometry_checks')}))


if __name__ == '__main__':
    main()

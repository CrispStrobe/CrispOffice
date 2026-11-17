#!/usr/bin/env python3
"""Read-only independent reconstruction of the retained consumer evidence.

No production/consumer commands or schema validation are rerun. Existing bytes,
receipt composition, source objects and current recorded inputs are audited.
"""
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
import gzip
import hashlib
import json
import subprocess
import xml.etree.ElementTree as ET

BASE = Path('/workspace/scratch/25fc1d269a82')
REPO = BASE / 'quds_office_suite'
EVIDENCE = BASE / 'validation-resume/final'
DOCS = BASE / 'work-evidence/docs/validation/office-fidelity-resume-20261117'
SOURCE = '07481e944799e282f15e6286192b926cff1165df'
CHECKER = '86242782115fa3433f03d00f3f98c08b890904b9'
PARTS = {'content.xml', 'styles.xml', 'meta.xml', 'META-INF/manifest.xml'}
CHECKED = set()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def require(value, message):
    if not value:
        raise AssertionError(message)


def check_file(path, expected):
    require(digest(path) == expected, 'Changed file: ' + str(path))
    CHECKED.add(str(Path(path)))


def load(relative):
    return json.loads((EVIDENCE / relative).read_text())


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])


def check_blob(commit, name, expected):
    require(sha(git('show', commit + ':' + name)) == expected,
            'Recorded source differs from Git object: ' + name)


def main():
    paths = {
        'initial': 'odf-consumer/receipt.json',
        'rtl': 'odf-rtl-correction/receipt.json',
        'generation': 'fixture-generation/receipt.json',
        'rotation': 'rotation-consumer/rotation-consumer-report.json',
        'rotation_runtime': 'rotation-consumer/independent-runtime-verification.json',
        'logical_pdf': 'engine/logical-render/poppler-receipt.json',
        'conditional_pdf': 'engine/conditional-render/poppler-receipt.json',
    }
    reports = {key: load(path) for key, path in paths.items()}
    summary = json.loads((DOCS / 'consumer-qualification.json').read_text())
    report_hashes = {key: digest(EVIDENCE / path) for key, path in paths.items()}
    require(summary['receipts_sha256'] == report_hashes, 'Summary receipt bindings differ')
    require(summary['script_sha256'] == digest(DOCS / 'summarize_consumers.py'),
            'Summary script identity differs')
    require(summary['product_source'] == SOURCE and summary['passed'], 'Summary source/status')
    original, correction, generation = (reports[k] for k in ('initial', 'rtl', 'generation'))
    require(original['source_commit'] == correction['source_commit']
            == generation['source_commit'] == generation['source_commit_after'] == SOURCE,
            'Different product sources')
    require(generation['passed'] and generation['source_inputs_unchanged']
            and generation['exit_code'] == 0, 'Unqualified generation')
    require(original['generation_receipt_sha256'] == correction['generation_receipt_sha256']
            == report_hashes['generation'], 'Generation receipt mismatch')
    require(original['schemas'] == correction['schemas'], 'Rerun schema drift')
    require(correction['verifier_head'] == CHECKER and correction['source_ancestor_of_verifier_head'],
            'Unexpected correction verifier')
    require(subprocess.run(['git', '-C', str(REPO), 'merge-base', '--is-ancestor', SOURCE, CHECKER],
                           capture_output=True).returncode == 0, 'Verifier ancestry')
    changed = git('diff', '--name-only', SOURCE, CHECKER).decode().splitlines()
    require(all(path.startswith('docs/validation/office-fidelity-resume-20261117/')
                for path in changed), 'Correction changed production source')
    verifier_path = 'docs/validation/office-fidelity-resume-20261117/verify_consumers.py'
    check_blob(SOURCE, verifier_path, original['script_sha256'])
    check_blob(CHECKER, verifier_path, correction['script_sha256'])
    for name, expected in original['schemas'].items():
        check_file(BASE / 'validation-resume/schemas' / name, expected)

    engine = load('engine/receipt.json')
    require(generation['engine_receipt_sha256'] == digest(EVIDENCE / 'engine/receipt.json')
            and engine['passed'] and engine['head_before'] == engine['head_after'] == SOURCE,
            'Generation did not use final engine receipt')
    source_inputs = dict(engine['source_before_sha256'])
    generator = 'docs/validation/office-fidelity-continuation-20261117/make_fixtures.dart'
    wrapper = 'docs/validation/office-fidelity-resume-20261117/generate_fixtures.py'
    source_inputs.update({generator: generation['generator_sha256'], wrapper: generation['script_sha256']})
    require(sha(json.dumps(source_inputs, sort_keys=True).encode()) == generation['source_inputs_sha256'],
            'Generation input closure digest differs')
    for name, expected in source_inputs.items():
        check_file(REPO / name, expected)
    check_blob(SOURCE, generator, generation['generator_sha256'])
    check_blob(SOURCE, wrapper, generation['script_sha256'])
    for kind in ('stdout', 'stderr'):
        require(sha(gzip.decompress((EVIDENCE / f'fixture-generation/{kind}.gz').read_bytes()))
                == generation[kind + '_sha256'], 'Generation log differs')

    inventory = {}
    for directory in (EVIDENCE / 'engine/odf-fixtures', EVIDENCE / 'fixture-generation/supplemental'):
        for path in directory.rglob('*'):
            if path.is_file() and path.suffix in ('.odp', '.odt'):
                actual = digest(path)
                require(path.name not in inventory or inventory[path.name] == actual, 'Conflicting fixture')
                inventory[path.name] = actual
    require(inventory == generation['fixtures_sha256']
            == correction['verified_fixture_inventory_sha256'] and len(inventory) == 27,
            'Full fixture inventory mismatch')
    original_by_name = {item['name']: item for item in original['fixtures']}
    require(len(original_by_name) == len(original['fixtures']) == 27 and original['passed'] is False,
            'Original fixture count/status')
    require([name for name, item in original_by_name.items() if not item['passed']]
            == ['slide-table-rtl.odp'], 'Original failure differs')
    require(original_by_name['slide-table-rtl.odp']['error'] == 'RTL fixture lost a cell word',
            'Original failure was not the observed extraction oracle')
    require({name: item['input_sha256'] for name, item in original_by_name.items()} == inventory,
            'Original package hashes differ')
    require(correction['passed'] and len(correction['fixtures']) == 1
            and correction['selected_fixtures'] == ['slide-table-rtl.odp'], 'Narrow rerun scope')
    replacement = correction['fixtures'][0]
    require(replacement['name'] == 'slide-table-rtl.odp'
            and replacement['input_sha256'] == inventory[replacement['name']], 'Replacement input differs')
    accepted = []
    for name, item in original_by_name.items():
        corrected = name == replacement['name']
        chosen = replacement if corrected else item
        directory = EVIDENCE / ('odf-rtl-correction' if corrected else 'odf-consumer')
        require(chosen['passed'] and set(chosen['schema_parts_passed']) == PARTS
                and len(chosen['schema_parts_passed']) == 4, 'Unqualified accepted fixture')
        check_file(chosen['source_path'], inventory[name])
        for artifact, expected in chosen['artifacts_sha256'].items():
            check_file(directory / artifact, expected)
        if 'comment_consumer' in chosen:
            check_file(directory / 'reopened' / (Path(name).stem + '.docx'),
                       chosen['comment_consumer']['round_trip_sha256'])
        accepted.append({'name': name, 'input_sha256': chosen['input_sha256'],
                         'receipt': 'rtl' if corrected else 'initial', 'passed': True,
                         'semantic_checks': chosen['semantic_checks'],
                         'comment_consumer': chosen.get('comment_consumer')})
    require(summary['general_fixtures'] == accepted, 'Summary changes accepted evidence')
    rtl_png = digest(EVIDENCE / 'odf-consumer/slide-table-rtl.png')
    require(rtl_png == digest(EVIDENCE / 'odf-rtl-correction/slide-table-rtl.png'), 'RTL raster changed')
    raw_bbox = ET.parse(EVIDENCE / 'odf-rtl-correction/slide-table-rtl.bbox.html')
    raw_words = [{'text': ''.join(node.itertext()), **{k: float(v) for k, v in node.attrib.items()}}
                 for node in raw_bbox.iter() if node.tag.split('}')[-1] == 'word']
    require(raw_words == replacement['semantic_checks']['raw_words'] and len(raw_words) == 2,
            'RTL raw word inventory mismatch')
    matches = {}
    for role, label in {'first': 'الأول', 'second': 'الثاني'}.items():
        matches[role] = [word for word in raw_words if Counter(word['text']) == Counter(label)]
        require(len(matches[role]) == 1, 'RTL character inventory changed')
    require(matches['first'][0]['xMin'] > matches['second'][0]['xMax'], 'RTL cells are misplaced')

    rotation = reports['rotation']
    runtime = reports['rotation_runtime']
    before_path = EVIDENCE / 'rotation-consumer/independent-inputs-before.json.gz'
    after_path = EVIDENCE / 'rotation-consumer/independent-inputs-after.json.gz'
    before, after = [json.loads(gzip.decompress(path.read_bytes())) for path in (before_path, after_path)]
    require(before == after and before['git_head'] == SOURCE and before['tracked_status'] == '',
            'Rotation input/source snapshots differ')
    require(len(before['files']) == runtime['input_count'] == 6730
            and len(before['font_paths']) == len(set(before['font_paths'])) == runtime['fonts_count'] == 557,
            'Rotation runtime count differs')
    require(runtime['passed'] and runtime['exit_code'] == 0 and runtime['expected_source_commit'] == SOURCE,
            'Rotation runtime failed')
    require(all(str(Path(path).resolve()) in before['files'] for path in before['font_paths']),
            'Font absent from hash inventory')
    def check_entry(entry):
        path, expected = entry
        require(digest(path) == expected, 'Rotation input changed now: ' + path)
        return path
    with ThreadPoolExecutor(max_workers=4) as pool:
        for path in pool.map(check_entry, before['files'].items()):
            CHECKED.add(path)
    require(rotation['passed'] and not rotation['errors'] and rotation['input_mode'] == 'generated_by_this_run'
            and rotation['source_before'] == rotation['source_after']
            and rotation['source_before']['git_head'] == SOURCE, 'Rotation source/status')
    for name, item in rotation['source_before']['files'].items():
        require(item['matches_head'] and item['sha256'] == item['head_sha256'], 'Rotation source binding')
        check_blob(SOURCE, name, item['sha256'])
        check_file(REPO / name, item['sha256'])
    require(rotation['schemas_sha256'] == original['schemas'], 'Rotation schemas differ')
    rotation_names = [item['name'] + '.odp' for item in rotation['files']]
    require(len(rotation_names) == len(set(rotation_names)) == 16
            and not set(rotation_names) & set(inventory), 'Rotation fixtures are not distinct')
    geometry_count = 0
    for item in rotation['files']:
        require({part['part'] for part in item['xml']} == PARTS and len(item['xml']) == 4
                and all(part['valid'] and part['errors'] == '' for part in item['xml']), 'Rotation XML receipt')
        for suffix, key in (('.odp', 'input_sha256'), ('.pdf', 'pdf_sha256'), ('.png', 'png_sha256')):
            directory = EVIDENCE / 'rotation-consumer' / ('fixtures' if suffix == '.odp' else '')
            check_file(directory / (item['name'] + suffix), item[key])
        for color in item['colors'].values():
            require(color['pixels'] > 0 and color['maximum_bound_error_pt'] <= 1.5, 'Geometry receipt failed')
            actual = max(abs(a - b) for a, b in zip(color['bounds_pt'], color['expected_bounds_pt']))
            require(abs(actual - color['maximum_bound_error_pt']) < 1e-10, 'Geometry arithmetic differs')
            geometry_count += 1
    require(geometry_count == 33, 'Geometry count')

    logical = reports['logical_pdf']
    require(logical['passed'] and len(logical['fixtures']) == 3
            and len({item['name'] for item in logical['fixtures']}) == 3, 'Logical receipt')
    for item in logical['fixtures']:
        require(item['different_pixels'] == 0 and item['raster_equal']
                and all(value > 0 for value in item['nonwhite_pixels']), 'Logical pixel result')
        for name, expected in item['files_sha256'].items():
            check_file(EVIDENCE / 'engine/logical-render' / name, expected)
        name = item['name']
        require((EVIDENCE / f'engine/logical-render/{name}.png').read_bytes()
                == (EVIDENCE / f'engine/logical-render/{name}-paint-control.png').read_bytes(),
                'Logical PNGs differ in bytes')
    conditional = reports['conditional_pdf']
    require(conditional['status'] == 'passed' and conditional['pdf_unchanged']
            and conditional['overridden_red_pixels'] == 0 and conditional['cell_value_present']
            and conditional['nonwhite_pixels'] > 0
            and all(value > 0 for value in conditional['exact_color_pixels'].values()), 'Conditional result')
    for name, expected in [('conditional-styles.pdf', conditional['input_pdf_sha256']),
                           (conditional['raster_file'], conditional['raster_sha256']),
                           (conditional['raw_text_file'], conditional['raw_text_sha256'])]:
        check_file(EVIDENCE / 'engine/conditional-render' / name, expected)
    for command in conditional['commands']:
        require(command['exit_code'] == 0, 'Conditional command failed')
        for kind in ('stdout', 'stderr'):
            check_file(EVIDENCE / 'engine/conditional-render' / command[kind + '_file'],
                       command[kind + '_sha256'])
    require(conditional['expected_cell_value'] in conditional['raw_extracted_text'], 'Conditional extraction')
    require(summary['general_fixture_count'] == 27 and summary['rotation_fixture_count'] == 16
            and summary['named_odf_fixture_count'] == 43 and summary['xml_part_validations'] == 172
            and summary['rotation_color_geometry_checks'] == 33
            and summary['rotation_bound_input_count'] == 6730 and summary['rotation_bound_font_count'] == 557,
            'Summary counts differ')
    require(summary['initial_consumer_attempt_passed'] is False and summary['rtl_consumer_raster_unchanged']
            and summary['corrected_fixture'] == 'slide-table-rtl.odp' and summary['conditional_pdf_passed'],
            'Summary hides original failure or changes accepted status')
    require(summary['logical_pdf_differing_pixels']
            == {item['name']: 0 for item in logical['fixtures']}, 'Logical summary differs')

    report = {
        'reviewer': '/root/runtime', 'reviewed_at_utc': datetime.now(timezone.utc).isoformat(),
        'passed': True, 'blocking_findings': [], 'product_source': SOURCE,
        'verifier_correction_commit': CHECKER, 'review_method':
        'Independent read-only reconstruction; no rendering, consumer commands, schema checks or product tests rerun.',
        'audit_script_sha256': digest(Path(__file__)),
        'summary_script_sha256': digest(DOCS / 'summarize_consumers.py'),
        'summary_json_sha256': digest(DOCS / 'consumer-qualification.json'),
        'receipts_sha256': report_hashes,
        'reconstructed': {
            'original_named_fixtures': 27, 'original_passes': 26, 'original_failures': ['slide-table-rtl.odp'],
            'accepted_replacement_fixtures': 1, 'all_generated_inputs_unchanged': 27,
            'rtl_original_and_corrected_png_sha256': rtl_png,
            'rtl_first_word_left_edge': matches['first'][0]['xMin'],
            'rtl_second_word_right_edge': matches['second'][0]['xMax'],
            'rotation_named_fixtures': 16, 'rotation_xml_parts': 64, 'rotation_color_geometry_checks': geometry_count,
            'rotation_unchanged_current_inputs': 6730, 'rotation_hashed_font_files': 557,
            'rotation_manifest_sha256': {'before': digest(before_path), 'after': digest(after_path)},
            'distinct_accepted_odf_fixtures': 43, 'accepted_xml_parts': 172,
            'logical_pdf_comparisons_with_bit_identical_pngs': 3, 'conditional_pdf_receipt_and_files_match': True,
            'generation_source_inputs_rechecked': len(source_inputs),
            'distinct_current_file_hash_checks': len(CHECKED),
        },
        'source_binding': {
            'generation_uses_final_passed_engine_receipt': True,
            'generators_and_checkers_match_recorded_git_objects': True,
            'correction_commit_changes_only_validation_documentation': True,
            'full_27_package_inventory_matches_original_generation_and_correction': True,
            'rotation_before_after_manifests_identical_and_current': True,
            'original_failed_receipt_preserved_sha256': report_hashes['initial'],
        },
        'review_notes': [
            'The accepted 172 XML parts are 43 distinct fixture packages times four parts. The four repeated RTL validations are not counted again.',
            'The corrected RTL oracle uses exact, distinct Unicode character inventories and raw coordinates for these two named fixture words. It does not assert general Arabic extraction order or general shaping parity.',
            'Retained schema/consumer receipts support covered fixtures only. Some general fixtures have no additional semantic oracle; comment DOCX import limitations remain explicit in the summary.',
            'The composition helper trusts the recorded conditional status and rotation runtime counts. This review independently checked their raw artifact hashes, manifest counts, current inputs and source bindings.',
            'The original failure is a verifier string-order mismatch. Input package and RTL raster bytes are unchanged across the correction.',
            'No remaining production-code blocker was found in this evidence review. It does not broaden the earlier implementation or selected-test coverage claims.',
        ],
        'github_actions_used': False,
    }
    destination = BASE / 'review-temp/consumer-review.json'
    destination.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({'passed': True, 'report': str(destination), 'sha256': digest(destination),
                      'checked_current_files': len(CHECKED), 'fixtures': 43, 'xml_parts': 172}))


if __name__ == '__main__':
    main()

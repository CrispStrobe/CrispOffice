#!/usr/bin/env python3
"""Audit fresh local receipts, exact source/runtime inputs and remote ancestry.

This reuses the preceding independent auditor's log/source/runtime checks, not
the qualification runner. It does not rerun tests or access GitHub Actions.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import subprocess

from PIL import Image, ImageChops

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
BASELINE = '74b6b39e7941ab351133023b4165cbd6101d2877'
PREVIOUS = HERE.parent / 'office-continuation-20261117' / 'verify_final.py'
spec = importlib.util.spec_from_file_location('previous_independent_auditor', PREVIOUS)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
audit.HERE = HERE
audit.REPO = REPO
audit.BASELINE = BASELINE
audit.EXPECTED_TESTS = json.loads((HERE / 'cohorts.json').read_bytes())
require = audit.require
sha = audit.sha


def read_json(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == '.gz' else data)


def external_file(directory, name, expected_sha256, tree):
    require(isinstance(name, str) and Path(name).name == name,
            'External artifact path escapes its directory: ' + repr(name))
    path = directory / name
    require(sha(path.read_bytes()) == expected_sha256,
            'External artifact hash mismatch: ' + str(path))
    audit.verify_committed(path, tree)
    return path


def external_receipt(directory, filename, script, tree, *, boolean_pass=False):
    path = directory / filename
    receipt = read_json(path)
    audit.verify_committed(path, tree)
    audit.verify_committed(script, tree)
    require(receipt.get('script_sha256') == sha(script.read_bytes()),
            'External verification script differs from its receipt: ' + str(script))
    require((receipt.get('passed') is True) if boolean_pass
            else receipt.get('status') == 'passed',
            'External verification receipt did not pass: ' + str(path))
    require(receipt.get('github_actions_used') is False,
            'External verification receipt lacks its no-Actions declaration')
    started = receipt.get('started_at_utc', receipt.get('started_utc'))
    finished = receipt.get('finished_at_utc', receipt.get('finished_utc'))
    require(started and finished and datetime.fromisoformat(finished) >= datetime.fromisoformat(started),
            'External verification receipt is incomplete: ' + str(path))
    return receipt


def saved_raster(path, expected_dimensions):
    with Image.open(path) as original:
        require(list(original.size) == expected_dimensions,
                'Saved raster has unexpected dimensions: ' + str(path))
        image = original.convert('RGB')
    colors = image.getcolors(maxcolors=image.width * image.height)
    require(colors is not None, 'Saved raster histogram exceeded its pixel bound')
    histogram = {color: count for count, color in colors}
    nonwhite = image.width * image.height - histogram.get((255, 255, 255), 0)
    require(nonwhite > 0, 'Saved raster is empty: ' + str(path))
    return image, histogram, nonwhite


def verify_logical_pdf_artifacts(tree):
    directory = HERE / 'engine/logical-render'
    script = PREVIOUS.parent / 'verify_pdf_visuals.py'
    receipt = external_receipt(directory, 'poppler-receipt.json', script, tree,
                               boolean_pass=True)
    require(receipt.get('dpi') == 120, 'Logical PDF raster DPI changed')
    dimensions = {'word-logical-source': [993, 1404],
                  'worksheet-logical-source': [993, 1404],
                  'rotated-slide-logical-source': [1200, 675]}
    fixtures = receipt['fixtures']
    require(len(fixtures) == 3 and {item['name'] for item in fixtures} == set(dimensions),
            'Logical PDF fixture inventory differs')
    checked = []
    expected_commands = []
    for fixture in fixtures:
        name = fixture['name']
        files = {name + suffix for suffix in [
            '.pdf', '-paint-control.pdf', '.png', '-paint-control.png',
            '-source.txt', '-poppler-raw.txt']}
        require(set(fixture['files_sha256']) == files,
                'Logical PDF fixture hash coverage differs: ' + name)
        for filename, expected in fixture['files_sha256'].items():
            external_file(directory, filename, expected, tree)
        require(fixture['size_pixels'] == dimensions[name],
                'Logical PDF receipt dimensions differ: ' + name)
        images = []
        ink = []
        for suffix in ['', '-paint-control']:
            image, _, nonwhite = saved_raster(directory / (name + suffix + '.png'), dimensions[name])
            images.append(image)
            ink.append(nonwhite)
            pdf = directory / (name + suffix + '.pdf')
            expected_commands.extend([
                ['pdfinfo', str(pdf)],
                ['pdftoppm', '-r', '120', '-singlefile', '-png', str(pdf), str(pdf.with_suffix(''))]])
        difference = ImageChops.difference(*images)
        histogram = difference.getcolors(maxcolors=difference.width * difference.height)
        require(histogram is not None, 'Logical difference histogram exceeded its bound')
        differing = sum(count for count, color in histogram if color != (0, 0, 0))
        require(fixture['nonwhite_pixels'] == ink
                and fixture['different_pixels'] == differing == 0
                and fixture.get('raster_equal') is True,
                'Logical PDF raster receipt does not match the saved images: ' + name)
        raw = (directory / (name + '-poppler-raw.txt')).read_text()
        source = (directory / (name + '-source.txt')).read_text()
        require(raw == fixture['poppler_raw_text'] and source == fixture['source_text']
                and fixture['external_text_matches_source_exactly'] is (raw == source),
                'Logical PDF text receipt differs from its saved text: ' + name)
        expected_commands.append(['pdftotext', '-raw', str(directory / (name + '.pdf')), '-'])
        checked.append({'name': name, 'dimensions': dimensions[name], 'nonwhite_pixels': ink,
                        'different_pixels': differing,
                        'external_text_matches_source_exactly': raw == source})
    require(receipt['commands'] == expected_commands,
            'Logical PDF command arguments differ from the recorded fixture paths')
    return {'passed': True, 'fixtures': checked, 'file_hashes_checked': 18,
            'saved_rasters_recomputed': True}


def load_external_verifier(script, module_name):
    module_spec = importlib.util.spec_from_file_location(module_name, script)
    module = importlib.util.module_from_spec(module_spec)
    # Execute the already hash-checked source without creating bytecode files.
    exec(compile(script.read_bytes(), str(script), 'exec'), module.__dict__)
    return module


def verify_conditional_artifacts(tree):
    directory = HERE / 'engine/conditional-render'
    script = HERE / 'verify_conditional_pdf.py'
    receipt = external_receipt(directory, 'poppler-receipt.json', script, tree)
    module = load_external_verifier(script, 'committed_conditional_verifier')
    fixture_test = REPO / 'packages/quds_office_engine/test/sheet_conditional_rendering_test.dart'
    audit.verify_committed(fixture_test, tree)
    require(receipt['fixture_test_sha256'] == sha(fixture_test.read_bytes()),
            'Conditional fixture test differs from external receipt')
    pdf = external_file(directory, 'conditional-styles.pdf', receipt['input_pdf_sha256'], tree)
    require(receipt['raster_file'] == 'conditional-styles-poppler.png'
            and receipt['raw_text_file'] == 'conditional-styles-poppler-raw.txt',
            'Conditional artifact filenames differ')
    raster = external_file(directory, receipt['raster_file'], receipt['raster_sha256'], tree)
    text_path = external_file(directory, receipt['raw_text_file'], receipt['raw_text_sha256'], tree)
    require(set(receipt['tools']) == {'pdfinfo', 'pdftoppm', 'pdftotext'},
            'Conditional verifier tool inventory differs')
    for name, identity in receipt['tools'].items():
        actual = module.tool_identity(name)  # Reads paths/hashes; launches no process.
        require(actual == {key: identity[key] for key in actual},
                'Conditional Poppler launcher/executable identity changed: ' + name)
    launch = {name: item['launcher'] for name, item in receipt['tools'].items()}
    stem = directory / 'conditional-styles-poppler'
    commands = [(name + '-version', [launch[name], '-v'], True)
                for name in ['pdfinfo', 'pdftoppm', 'pdftotext']]
    commands.extend([
        ('pdfinfo', [launch['pdfinfo'], str(pdf)], False),
        ('pdftoppm', [launch['pdftoppm'], '-r', '144', '-singlefile', '-png', str(pdf), str(stem)], False),
        ('pdftotext', [launch['pdftotext'], '-raw', str(pdf), '-'], False)])
    require(len(receipt['commands']) == len(commands), 'Conditional command count differs')
    output = {}
    for recorded, (label, argv, version) in zip(receipt['commands'], commands):
        require(recorded['argv'] == argv and recorded['exit_code'] == 0,
                'Conditional command failed or used different arguments: ' + label)
        channels = {}
        for channel in ['stdout', 'stderr']:
            filename = label + '.' + channel + '.log'
            require(recorded[channel + '_file'] == filename, 'Conditional log filename differs')
            log = external_file(directory, filename, recorded[channel + '_sha256'], tree)
            channels[channel] = log.read_bytes()
        require(version or not channels['stderr'].strip(),
                'Conditional PDF tool emitted diagnostics: ' + label)
        if version:
            name = label.removesuffix('-version')
            require(receipt['tools'][name]['version']
                    == (channels['stdout'] + channels['stderr']).decode().strip(),
                    'Conditional tool version differs from its saved log')
        output[label] = channels['stdout']
    info = output['pdfinfo'].decode()
    pages = re.search(r'^Pages:\s+(\d+)\s*$', info, re.MULTILINE)
    size = re.search(r'^Page size:\s+([\d.]+) x ([\d.]+) pts', info, re.MULTILINE)
    rotation = re.search(r'^Page rot:\s+(-?\d+)\s*$', info, re.MULTILINE)
    require(pages and int(pages[1]) == 1 and size and rotation and int(rotation[1]) == 0,
            'Conditional saved PDF geometry is unexpected')
    points = [float(size[1]), float(size[2])]
    expected = [math.ceil(value * 144 / 72) for value in points]
    require(receipt['dpi'] == 144 and receipt['pages'] == 1
            and receipt['page_points'] == points
            and receipt['expected_raster_dimensions'] == expected == [1191, 1684]
            and receipt['actual_raster_dimensions'] == expected,
            'Conditional raster dimensions do not match PDF geometry')
    _, histogram, nonwhite = saved_raster(raster, expected)
    counts = {name: histogram.get(tuple(bytes.fromhex(name)), 0) for name in ['123456', 'ABCDEF']}
    require(receipt['nonwhite_pixels'] == nonwhite
            and receipt['exact_color_pixels'] == counts and all(counts.values())
            and receipt['overridden_red_pixels'] == histogram.get((255, 0, 0), 0) == 0,
            'Conditional raster color counts differ from receipt')
    raw = text_path.read_bytes()
    require(raw == output['pdftotext'] and receipt['raw_extracted_text'] == raw.decode()
            and re.search(r'(?<!\S)8(?!\S)', raw.decode()) is not None
            and receipt['expected_cell_value'] == '8'
            and receipt.get('cell_value_present') is True and receipt.get('pdf_unchanged') is True,
            'Conditional extracted-text evidence or positive flags differ')
    return {'passed': True, 'dimensions': expected, 'nonwhite_pixels': nonwhite,
            'exact_color_pixels': counts, 'overridden_red_pixels': 0,
            'commands_checked': len(commands), 'saved_raster_recomputed': True,
            'cell_value_present': True, 'rendering_parity_claimed': False}


def verify_odf_artifacts(tree):
    directory = HERE / 'engine/odf-fixtures'
    script = HERE / 'verify_odf_fixtures.py'
    receipt = external_receipt(directory, 'external-xml-receipt.json', script, tree)
    module = load_external_verifier(script, 'committed_odf_verifier')
    expected = {
        'word-text.odt': {'mime': 'application/vnd.oasis.opendocument.text',
                          'paragraphs': ['  A\tB  C\nD ']},
        'slide-text.odp': {'mime': 'application/vnd.oasis.opendocument.presentation',
                           'paragraphs': [' Head\tA  B ', '', 'Tail ', '  Cell\tend ', '  Note\tend ']},
        'word-indents.odt': {'mime': 'application/vnd.oasis.opendocument.text',
                             'paragraphs': ['Body'], 'indent': '-18.00pt'}}
    require(module.EXPECTED == expected, 'Committed ODF verifier fixture contract changed')
    fixtures = receipt['fixtures']
    require(len(fixtures) == 3 and {item['file'] for item in fixtures} == set(expected),
            'ODF fixture inventory differs')
    for fixture in fixtures:
        path = external_file(directory, fixture['file'], fixture['sha256'], tree)
        for flag in ['first_member_uncompressed_mimetype', 'xml_well_formed',
                     'paragraph_text_matches', 'input_unchanged']:
            require(fixture.get(flag) is True, 'ODF receipt lacks a positive check: ' + flag)
        # This committed Python verifier only reads ZIP/XML/text; it does not
        # launch a test, regenerate a fixture, or write a verification receipt.
        recomputed = module.verify_fixture(path, expected[fixture['file']])
        require(fixture == recomputed,
                'ODF ZIP/XML/text hashes or semantic fields differ: ' + fixture['file'])
    return {'passed': True, 'fixtures': [item['file'] for item in fixtures],
            'xml_members_recomputed': 12, 'paragraph_text_recomputed': True,
            'hanging_indent': '-18.00pt', 'schema_conformance_claimed': False}


def verify_external_artifacts(tree):
    return {'logical_pdf': verify_logical_pdf_artifacts(tree),
            'conditional_pdf': verify_conditional_artifacts(tree),
            'odf': verify_odf_artifacts(tree)}


def verify_inventory(head, tree):
    directory = HERE / 'incoming'
    stored = read_json(directory / 'sha256.json')
    for name, expected in stored.items():
        path = directory / name
        require(path.resolve().is_relative_to(directory), 'Inventory path escapes directory')
        raw = path.read_bytes()
        require(len(raw) == expected['bytes'] and sha(raw) == expected['sha256'],
                'Stored inventory hash mismatch: ' + name)
        audit.verify_committed(path, tree)
    audit.verify_committed(directory / 'sha256.json', tree)
    captured = read_json(directory / 'captured-sha256.json')
    for name, expected in captured.items():
        if name in {'README.md', 'inventory.json'}:
            raw = gzip.decompress((directory / 'snapshot-originals' / (name + '.gz')).read_bytes())
        elif name.startswith('raw/'):
            raw = gzip.decompress((directory / (name + '.gz')).read_bytes())
        else:
            raw = (directory / name).read_bytes()
        require(len(raw) == expected['bytes'] and sha(raw) == expected['sha256'],
                'Captured inventory payload changed: ' + name)
    inventory = read_json(directory / 'inventory.json')
    original = read_json(directory / 'snapshot-originals/inventory.json.gz')
    routed = json.loads(json.dumps(inventory))
    routed.pop('raw_storage')
    for observation in routed['observations']:
        observation['file'] = observation['file'].removesuffix('.gz')
    require(routed == original, 'Normalized inventory changed beyond compressed-file routing')
    reconstructed = {}
    pages = {}
    for observation in inventory['observations']:
        key = observation['key']
        if key == 'fork-metadata':
            continue
        source, kind, page = key.split('-')
        rows = read_json(directory / observation['file'])
        require(len(rows) == observation['count'], 'Inventory page count changed: ' + key)
        pages.setdefault((source, kind), []).append((int(page), len(rows)))
        for row in rows:
            if kind == 'branches':
                ref, commit = 'refs/heads/' + row['name'], row['commit']['sha']
            else:
                ref, commit = 'refs/pull/' + str(row['number']) + '/head', row['head']['sha']
            identity = (source, ref)
            require(identity not in reconstructed, 'Duplicated raw reference: ' + repr(identity))
            reconstructed[identity] = commit
    for identity, observations in pages.items():
        observations.sort()
        require([number for number, _ in observations] == list(range(1, len(observations) + 1)),
                'Nonconsecutive inventory pages: ' + repr(identity))
        require(observations[-1][1] == 0, 'Collection lacks its terminal empty page')
    refs = inventory['refs']
    normalized = {(row['source'], row['ref']): row['sha'] for row in refs}
    require(len(normalized) == len(refs) == inventory['reference_count'] == 204,
            'Reference count/identity mismatch')
    require(normalized == reconstructed, 'Normalized refs differ from captured API pages')
    commits = set(normalized.values())
    require(len(commits) == inventory['distinct_head_commits'] == 137,
            'Distinct head count mismatch')
    for commit in sorted(commits):
        require(subprocess.run(['git', 'merge-base', '--is-ancestor', commit, head], cwd=REPO).returncode == 0,
                'Pinned incoming head is absent from final ancestry: ' + commit)
    counts = Counter(row['source'] + '_' + ('branches' if row['kind'] == 'branch' else 'pulls')
                     for row in refs)
    require(dict(counts) == inventory['counts'], 'Reference category counts differ')
    return {'references': len(refs), 'distinct_heads': len(commits), 'counts': dict(counts),
            'observation_started_at': inventory['observation_started_at'],
            'observation_completed_at': inventory['observation_completed_at'],
            'all_included_by_ancestry': True, 'captured_payload_hashes_verified': len(captured)}


def verify_refresh(head, tree):
    directory = HERE / 'final-refresh'
    inventory = read_json(directory / 'inventory.json')
    audit.verify_committed(directory / 'inventory.json', tree)
    reconstructed = {}
    for observation in inventory['captured']:
        path = directory / observation['file']
        raw = path.read_bytes()
        require(sha(raw) == observation['sha256'], 'Refresh raw observation changed')
        audit.verify_committed(path, tree)
        for line in raw.decode().splitlines():
            commit, ref = line.split()
            key = (observation['source'], ref)
            require(key not in reconstructed, 'Duplicate refreshed reference')
            reconstructed[key] = commit
    refs = inventory['refs']
    normalized = {(row['source'], row['ref']): row['sha'] for row in refs}
    require(reconstructed == normalized and len(normalized) == len(refs) == 206,
            'Refreshed reference identities/count differ')
    require(len(set(normalized.values())) == inventory['distinct_heads'] == 138,
            'Refreshed distinct head count differs')
    original = read_json(HERE / 'incoming/inventory.json')['refs']
    union = {(row['source'], row['ref'], row['sha']) for row in original + refs}
    heads = {row[2] for row in union}
    require(len(union) == inventory['union_reference_revision_pairs'] == 213,
            'Union reference/revision count differs')
    require(len(heads) == inventory['union_distinct_heads'] == 142,
            'Union commit count differs')
    for commit in sorted(heads):
        require(subprocess.run(['git', 'merge-base', '--is-ancestor', commit, head], cwd=REPO).returncode == 0,
                'A captured original/refreshed head is absent: ' + commit)
    return {'references': len(refs), 'distinct_heads': len(set(normalized.values())),
            'union_reference_revision_pairs': len(union), 'union_distinct_heads': len(heads),
            'observed_at_utc': [item['observed_at_utc'] for item in inventory['captured']],
            'all_original_and_refreshed_heads_included': True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--head', required=True)
    parser.add_argument('--branch', default='codex/text-rendering-20261116')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = {'started_utc': datetime.now(timezone.utc).isoformat(), 'head': args.head,
              'branch': args.branch, 'github_actions_used': False}
    try:
        require(audit.git('rev-parse', 'HEAD') == args.head, 'Checkout is not the requested head')
        require(not audit.git('status', '--porcelain', '--untracked-files=no'), 'Tracked checkout is dirty')
        advertised = audit.git('ls-remote', 'origin', 'refs/heads/' + args.branch).split()
        require(advertised == [args.head, 'refs/heads/' + args.branch],
                'Advertised remote branch differs from the requested head')
        tree = audit.tree_entries(args.head)
        for path in [Path(__file__), PREVIOUS, HERE / 'cohorts.json', HERE / 'validate.py']:
            audit.verify_committed(path, tree)
        runtime = audit.runtime_audit(tree)
        cohorts = {name: audit.cohort_audit(name, args.head, tree, runtime)
                   for name in audit.EXPECTED_TESTS}
        # The inherited auditor covers render/logical-render. Bind the new
        # fixture directories and their independent verification receipts too.
        for name in ['conditional-render', 'odf-fixtures']:
            directory = HERE / 'engine' / name
            require(directory.is_dir(), 'Missing new fixture directory: ' + name)
            for path in sorted(directory.rglob('*')):
                if path.is_file():
                    cohorts['engine']['artifacts'][str(path.relative_to(HERE / 'engine'))] = audit.verify_committed(path, tree)
        report['external_artifacts'] = verify_external_artifacts(tree)
        report['runtime'] = runtime
        report['cohorts'] = cohorts
        report['incoming'] = verify_inventory(args.head, tree)
        report['final_refresh'] = verify_refresh(args.head, tree)
        report['total_passed_tests'] = sum(item['passed_tests'] for item in cohorts.values())
        report['total_test_files'] = sum(item['test_files'] for item in cohorts.values())
        report['remote_head'] = args.head
        report['remote_tree'] = audit.git('rev-parse', args.head + '^{tree}')
        report['passed'] = True
    except Exception as error:
        report['passed'] = False
        report['error'] = str(error)
    report['finished_utc'] = datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items()
                      if key not in {'runtime', 'cohorts'}}))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()

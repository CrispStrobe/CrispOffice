#!/usr/bin/env python3
"""Independent consumer evidence audit. Does not import any producer harness."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import tarfile
import zipfile

from lxml import etree
from PIL import Image


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


class Audit:
    def __init__(self):
        self.checks = []

    def check(self, name, passed, detail=None):
        self.checks.append({'name': name, 'passed': bool(passed), 'detail': detail})

    def equal(self, name, actual, expected):
        self.check(name, actual == expected,
                   None if actual == expected else {'actual': actual, 'expected': expected})

    def close(self, name, actual, expected, tolerance=0.4):
        self.check(name, abs(actual - expected) <= tolerance,
                   {'measured': actual, 'expected': expected, 'tolerance': tolerance})


NS = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
      'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'}
W = '{' + NS['w'] + '}'
PARSER = etree.XMLParser(resolve_entities=False, no_network=True)


def xml(data):
    return etree.fromstring(data, parser=PARSER)


def word_at(words, target, *, suffix=False):
    found = [item for item in words
             if item['text'] == target or suffix and item['text'].endswith(target)]
    if len(found) != 1:
        raise ValueError(f'Expected one PDF token for {target!r}, found {len(found)}')
    return found[0]


def containing(doc, tag, word):
    nodes = doc.xpath(f'//w:{tag}[.//w:t[text()=$word]]', namespaces=NS, word=word)
    if len(nodes) != 1:
        raise ValueError(f'Expected one DOCX {tag} for {word!r}, found {len(nodes)}')
    return nodes[0]


def attr(node, name, default=None):
    return default if node is None else node.get(W + name, default)


def border_values(properties, container):
    results = {}
    for side, alternative in [('top', 'top'), ('bottom', 'bottom'),
                              ('left', 'start'), ('right', 'end')]:
        element = properties.find(f'w:{container}/w:{side}', namespaces=NS)
        if element is None:
            element = properties.find(f'w:{container}/w:{alternative}', namespaces=NS)
        results[side] = {'kind': attr(element, 'val'), 'color': attr(element, 'color'),
                         'size': attr(element, 'sz')}
    return results


def pixel_count(image, bounds, predicate):
    # Saved raster commands use 96 dpi. Coordinates are PDF points.
    scale = 96 / 72
    rectangle = (max(0, math.floor(bounds[0] * scale)),
                 max(0, math.floor(bounds[1] * scale)),
                 min(image.width, math.ceil(bounds[2] * scale)),
                 min(image.height, math.ceil(bounds[3] * scale)))
    pixels = list(image.crop(rectangle).getdata())
    return sum(predicate(pixel) for pixel in pixels), len(pixels)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--index', type=Path, required=True)
    parser.add_argument('--prior-archive', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    audit = Audit()
    root = args.root
    receipt = json.loads((root / 'receipt.json').read_text())
    index = json.loads(args.index.read_text())
    archive = args.index.parent / index['archive']['file']
    archive_hash = file_sha(archive)
    audit.equal('archive:known-sha256', archive_hash,
                '3c5c324e79581d0eb8fff4b0c829e54947f7c60281e288e6368476c6608319fd')
    audit.equal('archive:index-sha256', archive_hash, index['archive']['sha256'])
    audit.equal('archive:bytes', archive.stat().st_size, 937068)
    with tarfile.open(archive) as saved:
        members = saved.getmembers()
        names = [item.name for item in members]
        audit.equal('archive:member-count', len(members), 384)
        audit.equal('archive:no-duplicates', len(names), len(set(names)))
        audit.equal('archive:exact-index', sorted(names), sorted(index['members']))
        for member in members:
            name = member.name
            safe = not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts
            audit.check('archive:safe:' + name, safe and member.isfile())
            if not safe or not member.isfile():
                continue
            data = saved.extractfile(member).read()
            expected = index['members'][name]
            audit.equal('archive:hash:' + name, sha(data), expected['sha256'])
            audit.equal('archive:size:' + name, len(data), expected['size'])
        audit.equal('archive:live-receipt', saved.extractfile('run/receipt.json').read(),
                    (root / 'receipt.json').read_bytes())
        audit.equal('archive:live-inputs', saved.extractfile('run/inputs.json.gz').read(),
                    (root / 'inputs.json.gz').read_bytes())

    fixtures = json.loads((root / 'fixtures/fixtures.json').read_text())
    with tarfile.open(args.prior_archive) as previous:
        names = [m.name for m in previous.getmembers() if m.name.endswith('fixtures/fixtures.json')]
        if len(names) != 1:
            raise ValueError(f'Ambiguous previous fixture specification: {names}')
        prior = json.load(previous.extractfile(names[0]))
    audit.equal('fixtures:historical-count', len(prior), 26)
    audit.equal('fixtures:historical-specifications-preserved', fixtures[:26], prior)
    audit.equal('fixtures:count', len(fixtures), 29)
    audit.equal('fixtures:exact-receipt-set', sorted(f['name'] for f in fixtures),
                sorted(f['name'] for f in receipt['fixtures']))
    audit.equal('source:head', receipt['source_head'], 'f5021f1c364baf010049fda2dd4bf7f414deda79')
    audit.equal('source:tree', receipt['source_tree'], 'afd7a513dfa91472f58c27ead4d8be3f4b75c262')
    inputs = json.loads(gzip.decompress((root / 'inputs.json.gz').read_bytes()))
    after = json.loads(gzip.decompress((root / 'inputs-after.json.gz').read_bytes()))
    audit.equal('inputs:before-after', inputs, after)
    for group, count in [('source', 400), ('runtime', 10420)]:
        audit.equal('inputs:count:' + group, len(inputs[group]), count)
        changed = []
        for name, expected in inputs[group].items():
            path = Path(name)
            if not path.is_file() or file_sha(path) != expected:
                changed.append(name)
        audit.equal('inputs:current:' + group, changed, [])
    for name, expected in receipt['output_hashes'].items():
        audit.equal('outputs:hash:' + name, file_sha(root / name), expected)
    audit.equal('commands:failures', [c['label'] for c in receipt['commands'] if c['exit_code']], [])

    schema_path = next(Path(p) for p in inputs['runtime'] if p.endswith('/OpenDocument-v1.3-schema.rng'))
    manifest_path = next(Path(p) for p in inputs['runtime'] if p.endswith('/OpenDocument-v1.3-manifest-schema.rng'))
    general_schema = etree.RelaxNG(etree.parse(str(schema_path), PARSER))
    manifest_schema = etree.RelaxNG(etree.parse(str(manifest_path), PARSER))
    measured = {}
    reports = {f['name']: f for f in receipt['fixtures']}
    schema_parts = 0
    for spec in fixtures:
        name = spec['name']
        report = reports[name]
        prefix = name + ':'
        with zipfile.ZipFile(root / 'fixtures' / spec['file']) as odt:
            for part in ['content.xml', 'styles.xml', 'meta.xml', 'META-INF/manifest.xml']:
                document = xml(odt.read(part))
                schema = manifest_schema if part.startswith('META-INF/') else general_schema
                okay = schema.validate(document)
                audit.check(prefix + 'schema:' + part, okay,
                            None if okay else str(schema.error_log))
                schema_parts += int(okay)
        bbox = etree.parse(str(root / 'converted' / (name + '.bbox.xhtml')), PARSER)
        pages = bbox.xpath('//*[local-name()="page"]')
        sizes = [[float(p.get('width')), float(p.get('height'))] for p in pages]
        audit.equal(prefix + 'page-count', len(sizes), len(spec['page_sizes_pt']))
        for i, (actual, expected) in enumerate(zip(sizes, spec['page_sizes_pt'])):
            for axis in range(2):
                audit.close(prefix + f'page-{i + 1}-{axis}', actual[axis], expected[axis], 0.05)
        audit.equal(prefix + 'reported-page-sizes', sizes, report['semantics']['page_sizes_pt'])
        words = []
        for page_number, page in enumerate(pages, 1):
            for word in page.xpath('.//*[local-name()="word"]'):
                words.append({'page': page_number, 'text': ''.join(word.itertext()),
                              **{k: float(word.get(k)) for k in ['xMin', 'yMin', 'xMax', 'yMax']}})
        selected = {word: word_at(words, word) for word in spec['word_pages']}
        for word, page in spec['word_pages'].items():
            audit.equal(prefix + 'word-page:' + word, selected[word]['page'], page)
        audit.equal(prefix + 'reported-word-locations', selected, report['semantics']['word_locations'])
        for a, b in spec.get('same_x', []):
            audit.close(prefix + 'same-x:' + a + ':' + b,
                        word_at(words, a)['xMin'], word_at(words, b)['xMin'])
        for a, b in spec.get('indented', []):
            audit.check(prefix + 'indent:' + b,
                        word_at(words, b)['xMin'] > word_at(words, a)['xMin'] + 1)
        ordered = [word_at(words, word) for word in spec.get('vertical_order', [])]
        audit.check(prefix + 'vertical-order', all((a['page'], a['yMin']) < (b['page'], b['yMin'])
                                                  for a, b in zip(ordered, ordered[1:])))
        for word, label in spec.get('labels', {}).items():
            target = word_at(words, word)
            left = [item for item in words if item['page'] == target['page']
                    and abs(item['yMin'] - target['yMin']) < 1
                    and item['xMax'] <= target['xMin']]
            found = max(left, key=lambda item: item['xMax'])['text'] if left else None
            audit.equal(prefix + 'label:' + word, found, label)
        if 'line_step' in spec:
            line = spec['line_step']; a, b = [word_at(words, w) for w in line['words']]
            audit.close(prefix + 'line-step', b['yMin'] - a['yMin'], line['points'])
        for key, edge in [('left_edge', 'xMin'), ('right_edge', 'xMax')]:
            if key in spec:
                for word in spec[key]['words']:
                    audit.close(prefix + key + ':' + word, word_at(words, word)[edge], spec[key]['points'])
        measured[name] = {'page_sizes': sizes, 'words': words}
        if 'same_layout_as' in spec:
            audit.equal(prefix + 'same-layout', measured[name], measured[spec['same_layout_as']])

        with zipfile.ZipFile(root / 'converted' / (name + '.docx')) as docx:
            doc = xml(docx.read('word/document.xml'))
            types = [attr(node.find('w:type', NS), 'val', 'nextPage')
                     for node in doc.xpath('//w:sectPr', namespaces=NS)]
            audit.equal(prefix + 'reported-section-types', types, report['semantics']['reopened_section_types'])
            if 'reopened_section_type' in spec:
                audit.check(prefix + 'section-parity', spec['reopened_section_type'] in types)
            if 'reopened_frame' in spec:
                expected = spec['reopened_frame']
                anchor = doc.xpath('//wp:anchor[.//w:t[text()=$word]]', namespaces=NS, word=expected['word'])[0]
                geometry = [float(anchor.find('wp:positionH/wp:posOffset', NS).text) / 12700,
                            float(anchor.find('wp:positionV/wp:posOffset', NS).text) / 12700,
                            float(anchor.find('wp:extent', NS).get('cx')) / 12700,
                            float(anchor.find('wp:extent', NS).get('cy')) / 12700]
                for i, expected_value in enumerate(expected['geometry_pt']):
                    audit.close(prefix + 'frame:' + str(i), geometry[i], expected_value, 0.1)
                audit.equal(prefix + 'reported-frame', geometry, report['semantics']['reopened_frame_geometry_pt'])
            for word, expected in spec.get('paragraph_decorations', {}).items():
                properties = containing(doc, 'p', word).find('w:pPr', NS)
                audit.equal(prefix + 'paragraph-fill:' + word,
                            attr(properties.find('w:shd', NS), 'fill'), expected['fill'])
                for side, border in border_values(properties, 'pBdr').items():
                    wanted = {'kind': 'single', 'color': expected['border'], 'size': '4'} if expected['border'] else dict.fromkeys(['kind', 'color', 'size'])
                    audit.equal(prefix + 'paragraph-border:' + word + ':' + side, border, wanted)
            for word, expected in spec.get('paragraph_tabs', {}).items():
                paragraph = containing(doc, 'p', word)
                tabs = [node for node in paragraph.findall('w:pPr/w:tabs/w:tab', NS)
                        if attr(node, 'val') != 'clear']
                audit.equal(prefix + 'tab-count:' + word, len(tabs), 1)
                tab = tabs[0]
                actual = {'position_pt': int(attr(tab, 'pos')) / 20,
                          'alignment': attr(tab, 'val'), 'leader': attr(tab, 'leader', 'none')}
                audit.equal(prefix + 'tab-properties:' + word, actual, expected)
                audit.equal(prefix + 'reported-tab:' + word, actual,
                            report['semantics']['reopened_paragraph_tabs'][word]['reopened_tab'])
                if expected['leader'] == 'none':
                    location = word_at(words, word)
                    edge = location['xMin'] if expected['alignment'] == 'left' else location['xMax'] if expected['alignment'] == 'right' else (location['xMin'] + location['xMax']) / 2
                    audit.close(prefix + 'tab-geometry:' + word, edge,
                                spec['tab_page_left_pt'] + expected['position_pt'], spec['tab_geometry_tolerance_pt'])
            for expected in spec.get('minimum_table_rows', []):
                row = containing(doc, 'tr', expected['first_word'])
                height = row.find('w:trPr/w:trHeight', NS)
                audit.equal(prefix + 'row-height:' + expected['first_word'], int(attr(height, 'val')) / 20, expected['height_pt'])
                audit.equal(prefix + 'row-rule:' + expected['first_word'], attr(height, 'hRule'), 'atLeast')
            for expected in spec.get('minimum_row_geometry', []):
                delta = word_at(words, expected['next'])['yMin'] - word_at(words, expected['first'])['yMin']
                audit.check(prefix + 'row-space:' + expected['first'], delta >= expected['min_delta_pt'], delta)
            for word, expected in spec.get('cell_decorations', {}).items():
                properties = containing(doc, 'tc', word).find('w:tcPr', NS)
                audit.equal(prefix + 'cell-fill:' + word, attr(properties.find('w:shd', NS), 'fill'), expected['fill'])
                for side, border in border_values(properties, 'tcBorders').items():
                    wanted = {'kind': 'single', 'color': '000000', 'size': '4'} if expected['borders'] else dict.fromkeys(['kind', 'color', 'size'])
                    audit.equal(prefix + 'cell-border:' + word + ':' + side, border, wanted)
            if 'styled_footer' in spec:
                expected = spec['styled_footer']
                footer_parts = [p for p in docx.namelist() if p.startswith('word/footer') and p.endswith('.xml')]
                footers = [xml(docx.read(p)) for p in footer_parts]
                instructions = [t.text or '' for footer in footers for t in footer.findall('.//w:instrText', NS)]
                audit.check(prefix + 'real-PAGE-field', any(t.strip() == 'PAGE' for t in instructions), instructions)
                runs = [run for footer in footers for run in footer.findall('.//w:r', NS)
                        if run.findall('.//w:t', NS)]
                audit.check(prefix + 'footer-text-runs', len(runs) >= 2)
                for i, run in enumerate(runs):
                    properties = run.find('w:rPr', NS)
                    bold = properties.find('w:b', NS)
                    audit.check(prefix + 'footer-bold:' + str(i), bold is not None and attr(bold, 'val', '1') not in ['0', 'false'])
                    audit.equal(prefix + 'footer-color:' + str(i), attr(properties.find('w:color', NS), 'val'), expected['color'])
                    audit.equal(prefix + 'footer-size:' + str(i), int(attr(properties.find('w:sz', NS), 'val')), expected['font_size_half_points'])
                for page_number in expected['page_numbers']:
                    tokens = [w['text'] for w in words if w['page'] == page_number
                              and w['yMin'] > sizes[page_number - 1][1] - 70]
                    audit.equal(prefix + 'footer-page:' + str(page_number), tokens,
                                [str(page_number)] + expected['suffix'].split())

        image = Image.open(root / 'rasters' / (name + '.png')).convert('RGB')
        for word, expected in {**spec.get('paragraph_decorations', {}), **spec.get('cell_decorations', {})}.items():
            position = word_at(words, word)
            rgb = tuple(bytes.fromhex(expected['fill'])) if expected['fill'] else (255, 255, 255)
            bounds = [position['xMin'], position['yMin'], position['xMax'] + 12, position['yMax']]
            count, total = pixel_count(image, bounds, lambda p: all(abs(a - b) <= 16 for a, b in zip(p, rgb)))
            audit.check(prefix + 'raster-fill:' + word, count > total * 0.4,
                        {'target_rgb': rgb, 'matching': count, 'total': total})
        if 'leader_raster_groups' in spec:
            groups = spec['leader_raster_groups']
            for kind in ['dotted', 'hyphen', 'underscore', 'plain']:
                position = word_at(words, groups[kind], suffix=True)
                count, total = pixel_count(image, [groups['gap_left_pt'], position['yMin'] - 1,
                                                   groups['gap_right_pt'], position['yMax'] + 3],
                                           lambda p: max(p) < 80)
                audit.check(prefix + 'raster-leader:' + kind, count == 0 if kind == 'plain' else count > 20,
                            {'dark_pixels': count, 'sampled_pixels': total})
        if 'red_picture' in spec:
            pixels = [(i % image.width, i // image.width) for i, p in enumerate(image.getdata())
                      if p[0] > 180 and p[1] < 100 and p[2] < 100]
            audit.check(prefix + 'red-picture-present', len(pixels) > 100)
            bounds = [min(p[0] for p in pixels), min(p[1] for p in pixels),
                      max(p[0] for p in pixels), max(p[1] for p in pixels)]
            measured_picture = [bounds[0] * .75, (bounds[2] - bounds[0]) * .75,
                                (bounds[3] - bounds[1]) * .75]
            for actual, key in zip(measured_picture, ['left_pt', 'width_pt', 'height_pt']):
                audit.close(prefix + 'red-picture:' + key, actual, spec['red_picture'][key], 1.1)
        if 'styled_footer' in spec:
            count = sum(p[2] > 150 and p[0] < 100 and p[1] < 100 for p in image.getdata())
            audit.check(prefix + 'blue-footer-visible', count > 100, count)

    audit.equal('schema:validated-parts', schema_parts, 116)
    audit.equal('receipt:summary', receipt['summary'],
                {'fixtures': 29, 'passed': 29, 'failed': 0, 'schema_parts_passed': 116, 'schema_parts_total': 116})
    failures = [row for row in audit.checks if not row['passed']]
    report = {'generated_utc': datetime.now(timezone.utc).isoformat(),
              'source_commit': receipt['source_head'], 'source_tree': receipt['source_tree'],
              'audit_implementation_sha256': file_sha(Path(__file__)),
              'scope': 'Independent archive/hash verification, ODF schema revalidation, raw Poppler geometry and DOCX structure reconstruction, plus independent raster controls. No consumer checker was imported.',
              'archive_sha256': archive_hash, 'archive_members': 384,
              'fixtures': 29, 'schema_parts': schema_parts, 'input_counts': {'source': 400, 'runtime': 10420},
              'checks': audit.checks, 'failed_checks': failures,
              'passed': not failures}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': not failures, 'checks': len(audit.checks), 'failures': failures}, ensure_ascii=False))
    raise SystemExit(0 if not failures else 1)


if __name__ == '__main__':
    main()

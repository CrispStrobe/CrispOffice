#!/usr/bin/env python3
"""Measure new column boundaries with independent LibreOffice consumers.

The same authored models are saved as direct ODT, native reference DOCX, and
DOCX-imported ODT. All fifteen inputs are rendered to PDF; the ten ODT inputs
are also reopened as DOCX. Two following paragraphs must share the destination
column, preventing natural section balancing from imitating the authored break.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

from lxml import etree

HERE = Path(__file__).resolve().parent
NS = {
    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
}
PARSER = etree.XMLParser(resolve_entities=False, no_network=True)
SCHEMAS = {
    'OpenDocument-v1.3-schema.rng': '40bad03efdbb02825230d357da0aa6ac679934c5bf56c6281752c0c24d58e4e6',
    'OpenDocument-v1.3-manifest-schema.rng': '8aee71f03484be112af972d622cc9031280c007b0a454ae8815e8e333c9bdd17',
}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def snapshot(repo, workspace, dart, schemas):
    paths = subprocess.check_output(
        ['git', 'ls-files', '-z', 'packages/quds_office_engine/lib',
         'packages/legacy_doc_parser/lib'], cwd=repo,
    ).decode().split('\0')
    files = [repo / p for p in paths if p]
    files.extend([Path(__file__).resolve(), HERE / 'make_boundary_fixtures.dart',
                  workspace / 'pubspec.lock', workspace / '.dart_tool/package_config.json',
                  dart, dart.parent / 'dartaotruntime', Path(etree.__file__)])
    files.extend(schemas / name for name in SCHEMAS)
    for tool in ('soffice', 'pdftotext'):
        files.append(Path(shutil.which(tool)).resolve())
    return {str(p): digest(p) for p in sorted(set(files))}


def xml_part(package, path):
    with zipfile.ZipFile(package) as archive:
        require(archive.testzip() is None, f'Invalid ZIP CRC: {package}')
        return etree.fromstring(archive.read(path), PARSER)


def bookmark_selection(document, name):
    starts = document.xpath('//w:bookmarkStart[@w:name=$name]', namespaces=NS, name=name)
    require(len(starts) == 1, f'Expected one start for bookmark {name}')
    identifier = starts[0].get('{' + NS['w'] + '}id')
    ends = document.xpath('//w:bookmarkEnd[@w:id=$id]', namespaces=NS, id=identifier)
    require(len(ends) == 1, f'Expected one end for bookmark {name}')
    active = False
    selected = []
    for node in document.iter():
        if node is starts[0]:
            active = True
        elif node is ends[0]:
            require(active, f'Reversed bookmark {name}')
            return ''.join(selected)
        elif active and node.tag == '{' + NS['w'] + '}t':
            selected.append(node.text or '')
    raise AssertionError(f'Unterminated bookmark {name}')


def check_docx(path, spec):
    doc = xml_part(path, 'word/document.xml')
    words = doc.xpath('//w:t/text()', namespaces=NS)
    labels = [spec['before'], spec['target'], *spec['followers']]
    flattened = ''.join(words)
    for label in labels:
        require(flattened.count(label) == 1, f'{path.name}: ambiguous label {label}')
    require([flattened.index(label) for label in labels] ==
            sorted(flattened.index(label) for label in labels),
            f'{path.name}: source label order changed')
    selection = bookmark_selection(doc, spec['bookmark'])
    require(selection == spec['target'], f'{path.name}: bookmark text is {selection!r}')
    return {'bookmark_text': selection, 'labels_in_source_order': labels}


def check_odt(path, spec, schemas):
    checked_parts = []
    for part in ('content.xml', 'styles.xml', 'meta.xml', 'META-INF/manifest.xml'):
        schema = schemas[1 if part.startswith('META-INF/') else 0]
        require(schema.validate(xml_part(path, part)),
                f'{path.name}:{part}: ODF schema rejection: {schema.error_log}')
        checked_parts.append(part)
    doc = xml_part(path, 'content.xml')
    start = doc.xpath('//text:bookmark-start[@text:name=$name]',
                      namespaces=NS, name=spec['bookmark'])
    end = doc.xpath('//text:bookmark-end[@text:name=$name]',
                    namespaces=NS, name=spec['bookmark'])
    require(len(start) == len(end) == 1, f'{path.name}: bookmark endpoints changed')
    prefix, destination = start[0].getparent(), end[0].getparent()
    if spec['explicit_page_break']:
        require(prefix is destination, f'{path.name}: native page-break precedence changed')
    else:
        require(prefix is not destination, f'{path.name}: source prefix was coalesced')
        require(''.join(prefix.itertext()) == '', f'{path.name}: prefix is not empty')
    require(''.join(destination.itertext()) == spec['target'],
            f'{path.name}: target moved relative to bookmark')
    def break_before(paragraph):
        style_name = paragraph.get('{' + NS['text'] + '}style-name')
        styles = doc.xpath('//style:style[@style:name=$name]', namespaces=NS, name=style_name)
        require(len(styles) == 1, f'{path.name}: paragraph style is ambiguous')
        return styles[0].xpath('style:paragraph-properties/@fo:break-before', namespaces=NS)
    expected = [] if spec['section_kind'] == 'continuous' else ['page']
    destination_expected = ['page'] if spec['explicit_page_break'] else ['column']
    require(break_before(prefix) == expected, f'{path.name}: page/section boundary changed')
    require(break_before(destination) == destination_expected,
            f'{path.name}: authored break precedence changed')
    return {'prefix_break': expected, 'destination_break': destination_expected,
            'bookmark_crosses_authored_column_break': not spec['explicit_page_break'],
            'schema_accepted_parts': checked_parts}


def check_pdf(path, spec):
    doc = etree.parse(str(path), PARSER)
    pages = doc.xpath('//*[local-name()="page"]')
    require(len(pages) == spec['target_page'], f'{path.name}: unexpected page count {len(pages)}')
    words = []
    for index, page in enumerate(pages, 1):
        for actual, expected in zip((float(page.get('width')), float(page.get('height'))),
                                    spec['page_size_pt']):
            require(abs(actual - expected) < .2, f'{path.name}: page geometry changed')
        words.extend({'page': index, 'text': ''.join(w.itertext()),
                      **{k: float(w.get(k)) for k in ('xMin', 'xMax', 'yMin', 'yMax')}}
                     for w in page.xpath('.//*[local-name()="word"]'))
    measured = {}
    for label in [spec['before'], spec['target'], *spec['followers']]:
        matches = [word for word in words if word['text'] == label]
        require(len(matches) == 1, f'{path.name}: expected one PDF token {label}')
        measured[label] = matches[0]
    before = measured[spec['before']]
    require(before['page'] == 1 and abs(before['xMin'] - spec['left_margin_pt']) <= .4,
            f'{path.name}: preceding content moved')
    # Derive the right-column origin from authored physical geometry.
    usable = spec['page_size_pt'][0] - spec['left_margin_pt'] - spec['right_margin_pt']
    column_width = (usable - spec['column_gap_pt']) / spec['column_count']
    right = spec['left_margin_pt'] + column_width + spec['column_gap_pt']
    expected_x = spec['left_margin_pt'] if spec['target_column'] == 'left' else right
    destination = [measured[label] for label in [spec['target'], *spec['followers']]]
    for word in destination:
        require(word['page'] == spec['target_page'], f'{path.name}: {word["text"]} is on wrong page')
        require(abs(word['xMin'] - expected_x) <= .4,
                f'{path.name}: {word["text"]} x={word["xMin"]}, expected {spec["target_column"]} column {expected_x}')
    require(all(a['yMin'] < b['yMin'] for a, b in zip(destination, destination[1:])),
            f'{path.name}: following paragraphs do not stay below target in one column')
    return {'page_count': len(pages), 'expected_column_origin_pt': expected_x,
            'target_column': spec['target_column'],
            'horizontal_tolerance_pt': .4, 'locations': measured}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--dart', type=Path, required=True)
    parser.add_argument('--schemas', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    repo, workspace, dart, output, schema_dir = [p.resolve() for p in
                                               (args.repo, args.workspace, args.dart,
                                                args.output, args.schemas)]
    for name, expected in SCHEMAS.items():
        require(digest(schema_dir / name) == expected, f'Official schema bytes differ: {name}')
    schemas = [etree.RelaxNG(etree.parse(str(schema_dir / name), PARSER)) for name in SCHEMAS]
    require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo).decode().strip() == args.commit,
            'Current HEAD does not match requested frozen source')
    output.mkdir(parents=True, exist_ok=False)
    for name in ('logs', 'fixtures', 'pdf', 'reopened', 'profiles'):
        (output / name).mkdir()
    receipt = {'started_at_utc': datetime.now(timezone.utc).isoformat(),
               'source_commit': args.commit, 'commands': [], 'fixtures': [], 'passed': False}
    before = snapshot(repo, workspace, dart, schema_dir)
    write_json(output / 'inputs-before.json', before)
    env = dict(os.environ, DART_SUPPRESS_ANALYTICS='true', CI='true',
               TMPDIR=str(workspace / 'tmp'), XDG_CONFIG_HOME=str(workspace / 'config'))
    def run(label, command):
        with (output / 'logs' / (label + '.stdout')).open('w') as out, \
             (output / 'logs' / (label + '.stderr')).open('w') as err:
            result = subprocess.run([str(c) for c in command], cwd=workspace, env=env,
                                    stdout=out, stderr=err, timeout=300)
        receipt['commands'].append({'label': label, 'argv': [str(c) for c in command],
                                    'exit_code': result.returncode})
        require(result.returncode == 0, f'Command failed: {label}')
    try:
        run('dart-version', [dart, '--version'])
        run('soffice-version', ['soffice', '--version'])
        run('pdftotext-version', ['pdftotext', '-v'])
        run('fixtures', [dart, '--packages=' + str(workspace / '.dart_tool/package_config.json'),
                         HERE / 'make_boundary_fixtures.dart', output / 'fixtures'])
        specs = json.loads((output / 'fixtures/fixtures.json').read_text())
        require(len(specs) == 5, 'Expected five independently specified boundary cases')
        odts = sorted((output / 'fixtures').glob('*.odt'))
        inputs = sorted([*odts, *(output / 'fixtures').glob('*.source.docx')])
        run('render-pdf', ['soffice', '-env:UserInstallation=' + (output / 'profiles/pdf').as_uri(),
                           '--headless', '--norestore', '--convert-to',
                           'pdf:writer_pdf_Export:{"IsSkipEmptyPages":{"type":"boolean","value":"false"}}',
                           '--outdir', output / 'pdf', *inputs])
        run('reopen-docx', ['soffice', '-env:UserInstallation=' + (output / 'profiles/docx').as_uri(),
                            '--headless', '--norestore', '--convert-to', 'docx:Office Open XML Text',
                            '--outdir', output / 'reopened', *odts])
        for spec in specs:
            case = {'name': spec['name'], 'variants': {}}
            for variant in ('direct', 'imported', 'source'):
                stem = spec['name'] + '.' + variant
                bbox = output / 'pdf' / (stem + '.bbox.xhtml')
                run('bbox-' + stem, ['pdftotext', '-bbox', output / 'pdf' / (stem + '.pdf'), bbox])
                package = (output / 'fixtures' if variant == 'source' else output / 'reopened') / (stem + '.docx')
                row = {'pdf': check_pdf(bbox, spec), 'docx': check_docx(package, spec)}
                if variant != 'source':
                    row['odt'] = check_odt(output / 'fixtures' / (stem + '.odt'), spec, schemas)
                case['variants'][variant] = row
            receipt['fixtures'].append(case)
        receipt['passed'] = True
    except Exception as error:
        receipt['error'] = f'{type(error).__name__}: {error}'
        raise
    finally:
        after = snapshot(repo, workspace, dart, schema_dir)
        write_json(output / 'inputs-after.json', after)
        receipt['inputs_unchanged'] = before == after
        receipt['passed'] = receipt['passed'] and receipt['inputs_unchanged']
        receipt['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        receipt['output_sha256'] = {str(p.relative_to(output)): digest(p)
                                    for p in sorted(output.rglob('*')) if p.is_file()
                                    and 'profiles' not in p.relative_to(output).parts}
        write_json(output / 'receipt.json', receipt)
    require(receipt['passed'], 'Consumer validation failed')
    print(json.dumps({'passed': True, 'fixtures': len(receipt['fixtures']),
                      'pdf_variants': sum(len(f['variants']) for f in receipt['fixtures']),
                      'reopened_docx': len(odts), 'inputs_unchanged': receipt['inputs_unchanged']}))


if __name__ == '__main__':
    main()

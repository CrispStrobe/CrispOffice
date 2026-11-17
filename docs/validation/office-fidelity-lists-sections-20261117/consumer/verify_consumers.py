#!/usr/bin/env python3
"""Generate source-bound ODT fixtures and check independent office consumers.

The expected geometry and visible labels are authored in make_fixtures.dart.
Every output directory must be fresh. No GitHub CI interfaces are used.
"""
from __future__ import annotations

import argparse
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import zipfile
from urllib.parse import unquote, urljoin, urlparse

from lxml import etree
from PIL import Image

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
NS = {
    'x': 'http://www.w3.org/1999/xhtml',
    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
}
SCHEMAS = {
    'OpenDocument-v1.3-schema.rng': '40bad03efdbb02825230d357da0aa6ac679934c5bf56c6281752c0c24d58e4e6',
    'OpenDocument-v1.3-manifest-schema.rng': '8aee71f03484be112af972d622cc9031280c007b0a454ae8815e8e333c9bdd17',
}


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as source:
        while chunk := source.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def json_write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def all_files(directory):
    return [p for p in Path(directory).rglob('*') if p.is_file()]


def configured_packages(repo):
    config = repo / '.dart_tool/package_config.json'
    result = {}
    for package in json.loads(config.read_text())['packages']:
        require(package['name'] not in result, 'Duplicate package mapping: ' + package['name'])
        parsed = urlparse(urljoin(config.as_uri(), package['rootUri']))
        require(parsed.scheme == 'file', 'Non-file activated package root.')
        root = Path(unquote(parsed.path)).resolve()
        library_url = urljoin(root.as_uri().rstrip('/') + '/', package.get('packageUri', 'lib/'))
        result[package['name']] = (root, Path(unquote(urlparse(library_url).path)))
    for name in ('quds_office_engine', 'legacy_doc_parser'):
        require(name in result and result[name][0] == (repo / 'packages' / name).resolve(),
                'Activated package does not resolve to selected source checkout: ' + name)
    return result


def source_inputs(repo):
    configured_packages(repo)
    files = []
    for package in ('quds_office_engine', 'legacy_doc_parser'):
        files += all_files(repo / 'packages' / package / 'lib')
        files.append(repo / 'packages' / package / 'pubspec.yaml')
    files += [repo / 'pubspec.yaml', repo / 'pubspec.lock',
              repo / '.dart_tool/package_config.json', HERE / 'make_fixtures.dart',
              Path(__file__).resolve()]
    return sorted(set(files))


def runtime_inputs(dart, schemas, repo):
    root = Path(os.environ['CODEX_PRIMARY_RUNTIME_ROOT']) / 'dependencies'
    files = all_files(root / 'native/libreoffice-headless')
    files += all_files(root / 'native/poppler')
    files += all_files(dart.parent.parent)
    for tool in ('soffice', 'pdftotext', 'pdftoppm', 'pdfinfo', 'fc-list'):
        path = Path(shutil.which(tool))
        files += [path, path.resolve()]
    fonts = subprocess.check_output(['fc-list', '--format=%{file}\n']).decode().splitlines()
    files += [Path(p) for p in fonts]
    files += [schemas / name for name in SCHEMAS]
    files += all_files(Path(etree.__file__).parent)
    files += all_files(Path(Image.__file__).parent)
    for package_root, library in configured_packages(repo).values():
        if package_root.is_relative_to(repo):
            continue
        files += all_files(library)
        files += all_files(package_root / 'bin')
        files += [package_root / 'pubspec.yaml', package_root / 'pubspec.lock']
    return sorted(set(p for p in files if p.is_file() and '__pycache__' not in p.parts))


def snapshot(paths):
    return {str(path): digest(path) for path in paths}


def page_words(path):
    root = etree.parse(str(path))
    result = []
    for page in root.xpath('//x:page', namespaces=NS):
        words = [dict(text=w.text or '', **{k: float(v) for k, v in w.attrib.items()})
                 for w in page.xpath('.//x:word', namespaces=NS)]
        result.append({'width': float(page.get('width')), 'height': float(page.get('height')),
                       'words': words})
    return result


def check_fixture(spec, output):
    name = spec['name']
    pages = page_words(output / 'converted' / (name + '.bbox.xhtml'))
    expected_pages = spec['page_sizes_pt']
    require(len(pages) == len(expected_pages), f'{name}: expected {len(expected_pages)} pages, got {len(pages)}')
    for index, (page, expected) in enumerate(zip(pages, expected_pages), 1):
        require(abs(page['width'] - expected[0]) <= .2 and abs(page['height'] - expected[1]) <= .2,
                f'{name}: page {index} dimensions {page["width"]}x{page["height"]}, expected {expected}')
    locations = {}
    for word, page_number in spec['word_pages'].items():
        matches = [(index, value) for index, page in enumerate(pages, 1)
                   for value in page['words'] if value['text'] == word]
        require(len(matches) == 1, f'{name}: expected one occurrence of {word}, got {len(matches)}')
        require(matches[0][0] == page_number,
                f'{name}: {word} is on page {matches[0][0]}, expected {page_number}')
        locations[word] = dict(page=page_number, **matches[0][1])
    for first, second in spec.get('same_x', []):
        require(abs(locations[first]['xMin'] - locations[second]['xMin']) <= .3,
                f'{name}: sibling indentation changed for {first}, {second}')
    for parent, child in spec.get('indented', []):
        require(locations[child]['xMin'] - locations[parent]['xMin'] >= 10,
                f'{name}: {child} is not indented beyond {parent}')
    order = spec.get('vertical_order', [])
    for first, second in zip(order, order[1:]):
        require((locations[first]['page'], locations[first]['yMin']) <
                (locations[second]['page'], locations[second]['yMin']),
                f'{name}: visible order changed for {first}, {second}')
    layout_text = (output / 'converted' / (name + '.txt')).read_text()
    for word, label in spec.get('labels', {}).items():
        require(re.search(r'^\s*' + re.escape(label) + r'\s+' + re.escape(word) + r'\s*$',
                          layout_text, flags=re.MULTILINE) is not None,
                f'{name}: visible marker for {word} is not {label!r}')
    if 'line_step' in spec:
        first, second = spec['line_step']['words']
        delta = locations[second]['yMin'] - locations[first]['yMin']
        require(abs(delta - spec['line_step']['points']) <= .15,
                f'{name}: line step is {delta}, expected {spec["line_step"]["points"]}')
    if 'right_edge' in spec:
        for word in spec['right_edge']['words']:
            require(abs(locations[word]['xMax'] - spec['right_edge']['points']) <= .3,
                    f'{name}: right edge for {word} is {locations[word]["xMax"]}')
    if 'left_edge' in spec:
        for word in spec['left_edge']['words']:
            require(abs(locations[word]['xMin'] - spec['left_edge']['points']) <= .3,
                    f'{name}: left edge for {word} is {locations[word]["xMin"]}')
    if 'same_layout_as' in spec:
        reference = page_words(output / 'converted' / (spec['same_layout_as'] + '.bbox.xhtml'))
        for word, location in locations.items():
            matches = [(index, value) for index, page in enumerate(reference, 1)
                       for value in page['words'] if value['text'] == word]
            require(len(matches) == 1 and matches[0][0] == location['page'],
                    f'{name}: layout control has an ambiguous location for {word}')
            require(all(abs(location[key] - matches[0][1][key]) <= .1
                        for key in ('xMin', 'xMax', 'yMin', 'yMax')),
                    f'{name}: empty continuous section moved {word}')
    section_types = []
    with zipfile.ZipFile(output / 'converted' / (name + '.docx')) as archive:
        require(archive.testzip() is None, f'{name}: reopened DOCX CRC failure')
        document = etree.fromstring(archive.read('word/document.xml'))
        section_types = document.xpath('//w:sectPr/w:type/@w:val', namespaces=NS)
    if 'reopened_section_type' in spec:
        require(spec['reopened_section_type'] in section_types,
                f'{name}: DOCX import lost {spec["reopened_section_type"]} section type: {section_types}')
    return {'page_sizes_pt': [[page['width'], page['height']] for page in pages],
            'word_locations': locations, 'labels': spec.get('labels', {}),
            'reopened_section_types': section_types,
            'scope': spec.get('scope', 'Exact fixture geometry and visible text/labels.')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--schemas', type=Path, required=True)
    parser.add_argument('--dart', type=Path, required=True)
    parser.add_argument('--repo', type=Path, default=REPO)
    args = parser.parse_args()
    output, schemas, dart, repo = (p.resolve() for p in (args.output, args.schemas, args.dart, args.repo))
    require(not output.exists(), 'Output directory must be fresh.')
    output.mkdir(parents=True)
    (output / 'logs').mkdir()
    (output / 'converted').mkdir()
    (output / 'rasters').mkdir()
    (output / 'tmp').mkdir()
    environment = dict(os.environ, TMPDIR=str(output / 'tmp'), DART_SUPPRESS_ANALYTICS='true',
                       FLUTTER_SUPPRESS_ANALYTICS='true', CI='true')
    commands = []
    receipt = {'started_at_utc': now(), 'source_root': str(repo),
               'source_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo).decode().strip(),
               'scope': 'Source-generated ODT sections and lists; official OASIS ODF1.3 schema plus LibreOffice PDF/DOCX and Poppler text.',
               'github_actions_queried_or_awaited': False, 'fixtures': [], 'commands': commands}
    def run(argv, label, *, cwd=repo, timeout=60):
        started = time.monotonic()
        result = subprocess.run([str(x) for x in argv], cwd=cwd, env=environment,
                                capture_output=True, timeout=timeout)
        (output / 'logs' / (label + '.stdout.log')).write_bytes(result.stdout)
        (output / 'logs' / (label + '.stderr.log')).write_bytes(result.stderr)
        command = {'argv': [str(x) for x in argv], 'cwd': str(cwd), 'exit_code': result.returncode,
                   'duration_seconds': round(time.monotonic() - started, 3), 'label': label}
        commands.append(command)
        require(result.returncode == 0, label + ' failed: ' + result.stderr.decode(errors='replace'))
        return (result.stdout + result.stderr).decode(errors='replace')

    try:
        for name, expected in SCHEMAS.items():
            require(digest(schemas / name) == expected, 'Unexpected official schema bytes: ' + name)
        source_before = snapshot(source_inputs(repo))
        runtime_before = snapshot(runtime_inputs(dart, schemas, repo))
        receipt['input_counts'] = {'source': len(source_before), 'runtime': len(runtime_before)}
        with gzip.GzipFile(filename=str(output / 'inputs.json.gz'), mode='wb', mtime=0) as target:
            target.write(json.dumps({'source': source_before, 'runtime': runtime_before}, indent=2).encode())
        receipt['versions'] = {tool: run([tool, argument], tool + '-version')
                               for tool, argument in [('soffice', '--version'), ('pdftotext', '-v'), ('pdfinfo', '-v'), ('pdftoppm', '-v')]}
        receipt['versions']['dart'] = run([dart, '--version'], 'dart-version')
        run([dart, '--packages=' + str(repo / '.dart_tool/package_config.json'),
             HERE / 'make_fixtures.dart', output / 'fixtures'], 'generate-fixtures')
        specs = json.loads((output / 'fixtures/fixtures.json').read_text())
        require(len({s['name'] for s in specs}) == len(specs), 'Duplicate fixture names.')
        inventory = snapshot(all_files(output / 'fixtures'))
        receipt['fixture_inventory'] = inventory
        schema = etree.RelaxNG(etree.parse(str(schemas / 'OpenDocument-v1.3-schema.rng')))
        manifest_schema = etree.RelaxNG(etree.parse(str(schemas / 'OpenDocument-v1.3-manifest-schema.rng')))
        schema_results = {}
        for spec in specs:
            passed_parts, failures = [], []
            with zipfile.ZipFile(output / 'fixtures' / spec['file']) as archive:
                require(archive.testzip() is None, spec['name'] + ' ZIP CRC failure')
                for part in ('content.xml', 'styles.xml', 'meta.xml', 'META-INF/manifest.xml'):
                    validator = manifest_schema if part.startswith('META-INF') else schema
                    if validator.validate(etree.fromstring(archive.read(part))):
                        passed_parts.append(part)
                    else:
                        failures.append({'part': part, 'errors': str(validator.error_log)})
            schema_results[spec['name']] = {'passed_parts': passed_parts, 'failures': failures}
        inputs = [output / 'fixtures' / s['file'] for s in specs]
        run(['soffice', '-env:UserInstallation=' + (output / 'profile-pdf').as_uri(), '--headless',
             '--convert-to', 'pdf:writer_pdf_Export:{"IsSkipEmptyPages":{"type":"boolean","value":"false"}}',
             '--outdir', output / 'converted', *inputs], 'libreoffice-pdf')
        run(['soffice', '-env:UserInstallation=' + (output / 'profile-docx').as_uri(), '--headless',
             '--convert-to', 'docx', '--outdir', output / 'converted', *inputs], 'libreoffice-docx')
        for spec in specs:
            name = spec['name']
            result = {'name': name, 'schema': schema_results[name]}
            receipt['fixtures'].append(result)
            try:
                pdf = output / 'converted' / (name + '.pdf')
                require(pdf.is_file(), name + ': LibreOffice did not produce a PDF')
                require((output / 'converted' / (name + '.docx')).is_file(), name + ': no DOCX')
                run(['pdftotext', '-layout', pdf, output / 'converted' / (name + '.txt')], name + '-text')
                run(['pdftotext', '-bbox', pdf, output / 'converted' / (name + '.bbox.xhtml')], name + '-bbox')
                result['semantics'] = check_fixture(spec, output)
                require(not schema_results[name]['failures'], name + ': schema failures')
                result['passed'] = True
            except Exception as error:
                result.update(passed=False, error=str(error))
            # Render one relevant page per fixture for inspection, even on failures.
            page = min(max(spec['word_pages'].values(), default=1), len(page_words(output / 'converted' / (name + '.bbox.xhtml'))))
            run(['pdftoppm', '-f', str(page), '-singlefile', '-r', '96', '-png',
                 output / 'converted' / (name + '.pdf'), output / 'rasters' / name], name + '-raster')
        receipt['source_unchanged'] = source_before == snapshot(source_inputs(repo))
        receipt['runtime_unchanged'] = runtime_before == snapshot(runtime_inputs(dart, schemas, repo))
        receipt['fixtures_unchanged'] = inventory == snapshot(all_files(output / 'fixtures'))
        receipt['passed'] = all(f['passed'] for f in receipt['fixtures']) and all(
            receipt[key] for key in ('source_unchanged', 'runtime_unchanged', 'fixtures_unchanged'))
        receipt['summary'] = {'fixtures': len(specs), 'passed': sum(f['passed'] for f in receipt['fixtures']),
                              'failed': sum(not f['passed'] for f in receipt['fixtures']),
                              'schema_parts_passed': sum(len(s['passed_parts']) for s in schema_results.values()),
                              'schema_parts_total': 4 * len(specs)}
    except Exception as error:
        receipt.update(passed=False, fatal_error=repr(error))
    finally:
        receipt['finished_at_utc'] = now()
        receipt['output_hashes'] = {str(path.relative_to(output)): digest(path)
            for folder in ('fixtures', 'logs', 'converted', 'rasters')
            for path in all_files(output / folder)}
        if (output / 'inputs.json.gz').exists():
            receipt['inputs_sha256'] = digest(output / 'inputs.json.gz')
        json_write(output / 'receipt.json', receipt)
    print(json.dumps({k: receipt.get(k) for k in ('passed', 'summary', 'fatal_error')}, indent=2))
    for result in receipt['fixtures']:
        if not result.get('passed'):
            print(result['name'] + ': ' + result.get('error', 'failed'))
    return 0 if receipt.get('passed') else 1


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Five current-contract consumers, retaining strict frame-bookmark failures."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import zipfile

import fitz
from lxml import etree

PARSER = argparse.ArgumentParser(description=__doc__)
PARSER.add_argument('--repo', type=Path, required=True)
PARSER.add_argument('--package-config', type=Path, required=True)
PARSER.add_argument('--jing', type=Path, required=True)
PARSER.add_argument('--schemas', type=Path, required=True)
PARSER.add_argument('--output', type=Path, required=True)
PARSER.add_argument('--generator', type=Path, default=Path(__file__).with_name('make_fixtures.dart'))
ARGS = PARSER.parse_args()
REPO = ARGS.repo.resolve()
OUTPUT = ARGS.output.resolve()
SCHEMAS = ARGS.schemas.resolve()
JING = ARGS.jing.resolve()
GENERATOR = ARGS.generator.resolve()
CONFIG = ARGS.package_config.resolve()
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    'xlink': 'http://www.w3.org/1999/xlink',
    'x': 'http://www.w3.org/1999/xhtml',
    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    'pr': 'http://schemas.openxmlformats.org/package/2006/relationships',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
    'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
}
W = '{' + NS['w'] + '}'
PINNED_SCHEMAS = {
    'OpenDocument-v1.3-schema.rng': '40bad03efdbb02825230d357da0aa6ac679934c5bf56c6281752c0c24d58e4e6',
    'OpenDocument-v1.3-manifest-schema.rng': '8aee71f03484be112af972d622cc9031280c007b0a454ae8815e8e333c9bdd17',
}

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()

def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')

def require(condition, message):
    if not condition:
        raise AssertionError(message)

def command(args, cwd=REPO, timeout=60):
    args = [str(a) for a in args]
    started = now()
    then = time.monotonic()
    try:
        completed = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        record = {'args': args, 'cwd': str(cwd), 'started_at_utc': started,
                  'finished_at_utc': now(), 'elapsed_seconds': time.monotonic() - then,
                  'exit_code': completed.returncode, 'stdout': completed.stdout,
                  'stderr': completed.stderr}
    except subprocess.TimeoutExpired as error:
        record = {'args': args, 'cwd': str(cwd), 'started_at_utc': started,
                  'finished_at_utc': now(), 'elapsed_seconds': time.monotonic() - then,
                  'exit_code': None, 'timeout': timeout,
                  'stdout': str(error.stdout), 'stderr': str(error.stderr)}
    commands.append(record)
    write_json(OUTPUT / 'commands.json', commands)
    return record

def source_inputs():
    paths = {GENERATOR, Path(__file__).resolve(), CONFIG, JING}
    for relative in ['packages/quds_office_engine/lib', 'packages/legacy_doc_parser/lib']:
        paths.update((REPO / relative).rglob('*.dart'))
    for relative in ['pubspec.yaml', 'pubspec.lock']:
        if (REPO / relative).is_file():
            paths.add(REPO / relative)
    # Seal the actual library roots selected by the package config, including
    # shadow-workspace packages if the runtime was recovered in an isolated copy.
    config = json.loads(CONFIG.read_text())
    for package in config['packages']:
        root_uri = urllib.parse.urljoin(CONFIG.as_uri(), package['rootUri'])
        library_uri = urllib.parse.urljoin(root_uri.rstrip('/') + '/', package.get('packageUri', 'lib/'))
        parsed = urllib.parse.urlparse(library_uri)
        if parsed.scheme == 'file':
            paths.update(Path(urllib.parse.unquote(parsed.path)).rglob('*.dart'))
    paths.update(SCHEMAS / name for name in PINNED_SCHEMAS)
    return {str(path): sha(path) for path in sorted(paths)}

def bookmark_text(root):
    opened, found = {}, {}
    def visit(node):
        if node is not root and node.tag == W + 'txbxContent':
            return
        if node.tag == W + 'bookmarkStart':
            opened[node.get(W + 'id')] = (node.get(W + 'name'), [])
        elif node.tag == W + 'bookmarkEnd':
            value = opened.pop(node.get(W + 'id'), None)
            if value:
                found[value[0]] = ''.join(value[1])
        elif node.tag == W + 't':
            for _, text in opened.values():
                text.append(node.text or '')
        for child in node:
            visit(child)
    visit(root)
    return found

def odf_text(node):
    if node.tag == '{%s}s' % NS['text']:
        return ' ' * int(node.get('{%s}c' % NS['text'], '1'))
    if node.tag == '{%s}tab' % NS['text']:
        return '\t'
    if node.tag == '{%s}line-break' % NS['text']:
        return '\n'
    return (node.text or '') + ''.join(odf_text(child) + (child.tail or '') for child in node)

def checks(spec, source, docx, pages, pdf_path):
    name = spec['name']
    require(len(pages) == spec['pages'], f'{name}: PDF page count {len(pages)}')
    words = [word for page in pages for word in page['words']]
    labels = [word['text'] for word in words]
    for label in spec.get('visible_words', []):
        require(labels.count(label) == 1, f'{name}: visible {label}: {labels.count(label)}')
    if 'page_words' in spec:
        all_labels = {word for group in spec['page_words'] for word in group}
        for page, expected in zip(pages, spec['page_words']):
            actual = [word['text'] for word in page['words']]
            require([word for word in actual if word in all_labels] == expected,
                    f'{name}: header/body/footer words {actual}')
    content = source['content.xml']
    native = content.xpath('//text:page-number|//text:page-count|//text:date|//text:time|//text:title', namespaces=NS)
    details = {'pdf_pages': len(pages)}
    if 'native_field_count' in spec:
        require(len(native) == spec['native_field_count'], f'{name}: unsafe native field')
        details['native_field_count'] = len(native)

    if 'source_fields' in spec:
        styles = {node.get('{%s}name' % NS['style']): node
                  for node in content.xpath('//style:style', namespaces=NS)}
        for element, cache in spec['source_fields'].items():
            fields = content.xpath('//text:' + element, namespaces=NS)
            require(len(fields) == 1 and fields[0].text == cache,
                    f'{name}: source {element} cache')
            field = fields[0]
            require(len(field) == 0, f'{name}: field contains non-text children')
            span = field.getparent()
            style = styles[span.get('{%s}style-name' % NS['text'])]
            properties = style.find('style:text-properties', NS)
            require(properties.get('{%s}font-weight' % NS['fo']) == 'bold', f'{name}: source bold')
            require(properties.get('{%s}color' % NS['fo']) == '#' + spec['source_color'],
                    f'{name}: source color')
            require(span.getparent().tag == '{%s}a' % NS['text'], f'{name}: source hyperlink')
        for field_type, cache in spec.get('cached_field_fallbacks', {}).items():
            require(not content.xpath('//text:' + field_type.lower(), namespaces=NS),
                    f'{name}: unsupported {field_type} became native')
            links = content.xpath('//text:a[@xlink:href=$target]', namespaces=NS,
                                  target='https://example.test/' + field_type.lower())
            require(len(links) == 1 and odf_text(links[0]) == cache,
                    f'{name}: {field_type} source fallback cache')
            spans = links[0].xpath('./text:span', namespaces=NS)
            require(len(spans) == 1, f'{name}: {field_type} source fallback span')
            properties = styles[spans[0].get('{%s}style-name' % NS['text'])].find('style:text-properties', NS)
            require(properties.get('{%s}font-weight' % NS['fo']) == 'bold',
                    f'{name}: {field_type} source fallback bold')
            require(properties.get('{%s}color' % NS['fo']) == '#' + spec['source_color'],
                    f'{name}: {field_type} source fallback color')
        source_links = content.xpath('//text:a/@xlink:href', namespaces=NS)
        require(sorted(source_links) == sorted(spec['links']), f'{name}: source links')
        document = docx['word/document.xml']
        instructions = [''.join(node.itertext()).strip()
                        for node in document.xpath('//w:instrText', namespaces=NS)]
        for field_type in spec['field_types']:
            require(re.search(r'\b' + field_type + r'\b', ' '.join(instructions).upper()),
                    f'{name}: DOCX lost {field_type}: {instructions}')
        for field_type, cache in spec.get('cached_field_fallbacks', {}).items():
            require(not re.search(r'\b' + field_type + r'\b', ' '.join(instructions).upper()),
                    f'{name}: DOCX invented {field_type}: {instructions}')
            require(cache in ''.join(document.xpath('//w:t/text()', namespaces=NS)),
                    f'{name}: DOCX lost {field_type} fallback')
        targets = []
        for path, xml in docx.items():
            if path.endswith('.rels'):
                targets.extend(xml.xpath('//pr:Relationship/@Target', namespaces=NS))
        require(set(spec['links']).issubset(targets), f'{name}: DOCX hyperlinks')

        # Inspect the actually rendered field value, after LibreOffice refresh,
        # rather than demanding that a page count still equal the authored cache.
        rendered_fields = {}
        with fitz.open(pdf_path) as pdf:
            lines = [line for page in pdf for block in page.get_text('dict')['blocks']
                     for line in block.get('lines', [])]
            pdf_links = [link.get('uri') for page in pdf for link in page.get_links() if link.get('uri')]
            for field_type in [*spec['field_types'], *spec.get('cached_field_fallbacks', {})]:
                matching = [line for line in lines
                            if ''.join(s['text'] for s in line['spans']).startswith(field_type + 'Label ')]
                require(len(matching) == 1, f'{name}: PDF label {field_type}')
                styled = [s for s in matching[0]['spans'] if s['color'] == int(spec['source_color'], 16)]
                require(styled and all(s['flags'] & 16 for s in styled),
                        f'{name}: rendered {field_type} lost bold/color')
                require(''.join(s['text'] for s in styled).strip(), f'{name}: empty rendered {field_type}')
                if field_type in spec.get('cached_field_fallbacks', {}):
                    require(''.join(s['text'] for s in styled) == spec['cached_field_fallbacks'][field_type],
                            f'{name}: rendered {field_type} fallback changed')
                rendered_fields[field_type] = [
                    {key: span[key] for key in ['text', 'font', 'size', 'color', 'flags', 'bbox']}
                    for span in styled]
            require(set(spec['links']).issubset(pdf_links), f'{name}: PDF hyperlinks')
        details.update(source_caches=spec['source_fields'], cached_fallbacks=spec.get('cached_field_fallbacks', {}),
                       reopened_field_instructions=instructions,
                       reopened_hyperlinks=[v for v in targets if v.startswith('https://example.test/')],
                       rendered_fields=rendered_fields, pdf_hyperlinks=pdf_links,
                       limitation='Native values refresh. DOCX result-run formatting is not asserted; actual PDF formatting is asserted.')

    if 'frame_geometry' in spec:
        geometry = spec['frame_geometry']
        frames = content.xpath('//draw:frame[draw:text-box//text:bookmark-start[@text:name=$name]]',
                               namespaces=NS, name=geometry['bookmark'])
        require(len(frames) == 1, f'{name}: missing source frame bookmark')
        frame = frames[0]
        require(frame.get('{%s}anchor-type' % NS['text']) == 'paragraph',
                f'{name}: changed frame anchor')
        for attribute in ['x', 'y', 'width', 'height']:
            require(frame.get('{%s}%s' % (NS['svg'], attribute)) == f"{geometry[attribute + '_pt']:.2f}pt",
                    f'{name}: source frame {attribute}')
        style_name = frame.get('{%s}style-name' % NS['draw'])
        styles = [node for root in [content, source['styles.xml']]
                  for node in root.xpath('//style:style[@style:name=$name]', namespaces=NS, name=style_name)]
        require(len(styles) == 1, f'{name}: ambiguous frame style')
        properties = styles[0].find('style:graphic-properties', NS)
        require(properties is not None, f'{name}: missing frame graphic properties')
        require(properties.get('{%s}horizontal-rel' % NS['style']) == 'page'
                and properties.get('{%s}vertical-rel' % NS['style']) == 'page',
                f'{name}: frame geometry is not page-relative')
        details['source_frame_geometry'] = geometry

    if 'bookmark_text' in spec:
        ranges = {}
        for path, xml in docx.items():
            if path == 'word/document.xml' or re.match(r'word/header\d+\.xml$', path):
                ranges.update(bookmark_text(xml))
                for frame in xml.xpath('//w:txbxContent', namespaces=NS):
                    ranges.update(bookmark_text(frame))
        for bookmark, expected in spec['bookmark_text'].items():
            require(ranges.get(bookmark) == expected,
                    f'{name}: {bookmark} selected {ranges.get(bookmark)!r}; expected {expected!r}')
        details['reopened_bookmark_text'] = ranges

    if 'source_native_fields_by_paragraph' in spec:
        paragraphs = content.xpath('/office:document-content/office:body/office:text/text:section/text:p', namespaces=NS)
        actual = [len(p.xpath('.//text:page-number', namespaces=NS)) for p in paragraphs]
        require(actual == spec['source_native_fields_by_paragraph'], f'{name}: field/column order {actual}')
        left = [word for word in words if word['text'] == '1']
        right = [word for word in words if word['text'] == spec['right_column_label']]
        require(len(left) == len(right) == 1, f'{name}: field/column label {labels}')
        separation = right[0]['xMin'] - left[0]['xMin']
        require(separation >= spec['minimum_column_separation_pt'], f'{name}: columns collapsed')
        require(abs(right[0]['yMin'] - left[0]['yMin']) < 5, f'{name}: column tops differ')
        details['rendered_column_positions'] = {'left': left[0], 'right': right[0], 'separation_pt': separation}
    return details

require(not OUTPUT.exists(), 'Output directory must be fresh; never overwrite evidence')
for name, expected in PINNED_SCHEMAS.items():
    require(sha(SCHEMAS / name) == expected, f'Unexpected schema bytes: {name}')
OUTPUT.mkdir(parents=True)
commands = []
started = now()
before = source_inputs()
write_json(OUTPUT / 'source-inputs-before.json', before)
head_result = command(['git', 'rev-parse', 'HEAD'], timeout=30)
identity = {'started_at_utc': started, 'head_at_start': head_result['stdout'].strip(),
            'harness_revision': 'gector-office-resume-current-contract-1',
            'raw_continuity': 'Fresh run against sealed inputs; historical recovery evidence remains unchanged.',
            'jing_source': 'https://repo.maven.apache.org/maven2/org/relaxng/jing/20241231/jing-20241231.jar',
            'jing_sha256': sha(JING), 'python': sys.version,
            'lxml': etree.LXML_VERSION, 'libxml2': etree.LIBXML_VERSION,
            'pymupdf': fitz.version,
            'schema_sha256': {name: sha(SCHEMAS / name) for name in PINNED_SCHEMAS}}
for tool, options in [('dart', ['--version']), ('java', ['-version']),
                      ('soffice', ['--version']), ('pdftotext', ['-v'])]:
    found = shutil.which(tool)
    require(found is not None, f'Missing tool: {tool}')
    path = Path(found).resolve()
    result = command([tool, *options], timeout=30)
    identity[tool] = {'path': str(path), 'sha256': sha(path), 'version_stdout': result['stdout'],
                      'version_stderr': result['stderr'], 'version_exit_code': result['exit_code']}
runtime_root = Path(os.environ.get('CODEX_PRIMARY_RUNTIME_ROOT', '/opt/codex/runtimes/codex-primary-runtime'))
identity['libreoffice_binaries'] = {
    str(path): sha(path) for path in (runtime_root / 'dependencies/native/libreoffice-headless').rglob('soffice.bin')}
write_json(OUTPUT / 'identity.json', identity)
generated = OUTPUT / 'generated'
generated.mkdir()
result = command(['dart', '--packages=' + str(CONFIG), str(GENERATOR), str(generated)], timeout=90)
require(result['exit_code'] == 0, 'Dart fixture generation failed')
specs = json.loads((generated / 'fixtures.json').read_text())
require([s['name'] for s in specs] == [
    'native-fields', 'malformed-fields', 'header-variants', 'bookmark-ranges', 'empty-field-column'],
    'Unexpected fixture cohort')
converted = OUTPUT / 'converted'
converted.mkdir()
schema_results, fixture_results = [], []
validators = {name: etree.RelaxNG(etree.parse(str(SCHEMAS / name))) for name in PINNED_SCHEMAS}
profile = OUTPUT / 'lo-profile'
for spec in specs:
    name = spec['name']
    source = {}
    try:
        with zipfile.ZipFile(generated / (name + '.odt')) as package:
            for part in ['content.xml', 'styles.xml', 'meta.xml', 'META-INF/manifest.xml']:
                data = package.read(part)
                xml_path = OUTPUT / 'xml' / name / part
                xml_path.parent.mkdir(parents=True, exist_ok=True)
                xml_path.write_bytes(data)
                xml = etree.fromstring(data)
                source[part] = xml
                schema_name = ('OpenDocument-v1.3-manifest-schema.rng'
                               if 'manifest' in part else 'OpenDocument-v1.3-schema.rng')
                validator = validators[schema_name]
                lxml_valid = validator.validate(xml)
                jing = command(['java', '-jar', JING, '-i', SCHEMAS / schema_name, xml_path], timeout=30)
                schema_results.append({'fixture': name, 'part': part, 'sha256': hashlib.sha256(data).hexdigest(),
                                       'jing_valid': jing['exit_code'] == 0, 'jing_errors': jing['stdout'] + jing['stderr'],
                                       'lxml_valid': lxml_valid, 'lxml_errors': [str(e) for e in validator.error_log]})
        for kind in ['pdf', 'docx:Office Open XML Text']:
            result = command(['soffice', '-env:UserInstallation=' + profile.as_uri(), '--headless',
                              '--convert-to', kind, '--outdir', converted, generated / (name + '.odt')], timeout=45)
            require(result['exit_code'] == 0, f'{name}: conversion failed: {kind}')
        for extension in ['pdf', 'docx']:
            require((converted / (name + '.' + extension)).is_file(), f'{name}: missing {extension}')
        bbox = converted / (name + '.bbox.xhtml')
        require(command(['pdftotext', '-bbox', converted / (name + '.pdf'), bbox], timeout=30)['exit_code'] == 0,
                f'{name}: PDF text extraction failed')
        tree = etree.parse(str(bbox))
        pages = [
            {'width': float(page.get('width')), 'height': float(page.get('height')),
             'words': [dict(text=node.text or '', **{key: float(value) for key, value in node.attrib.items()})
                       for node in page.xpath('.//x:word', namespaces=NS)]}
            for page in tree.xpath('//x:page', namespaces=NS)]
        docx = {}
        with zipfile.ZipFile(converted / (name + '.docx')) as package:
            for part in package.namelist():
                if part.endswith(('.xml', '.rels')):
                    docx[part] = etree.fromstring(package.read(part))
        details = checks(spec, source, docx, pages, converted / (name + '.pdf'))
        fixture_results.append({'name': name, 'pass': True, 'checks': details, 'pages': pages})
    except Exception as error:
        fixture_results.append({'name': name, 'pass': False, 'error_type': type(error).__name__, 'error': str(error)})
    write_json(OUTPUT / 'schema-results.json', schema_results)
    write_json(OUTPUT / 'fixture-results.json', fixture_results)
    print(name, fixture_results[-1]['pass'], fixture_results[-1].get('error', ''), flush=True)
after = source_inputs()
write_json(OUTPUT / 'source-inputs-after.json', after)
summary = {'started_at_utc': started, 'completed_at_utc': now(), 'head_at_start': identity['head_at_start'],
           'harness_revision': identity['harness_revision'], 'source_inputs_unchanged': before == after,
           'source_input_count': len(before), 'fixture_count': len(fixture_results),
           'fixture_passes': sum(r['pass'] for r in fixture_results), 'schema_parts': len(schema_results),
           'jing_valid': sum(r['jing_valid'] for r in schema_results),
           'lxml_valid': sum(r['lxml_valid'] for r in schema_results),
           'scope': 'Five final-writer generated packages in one installed headless LibreOffice build; no arbitrary imported ODF fidelity claim.',
           'validator_note': 'Jing -i is the RelaxNG acceptance check. The lxml nested page-count disagreement is retained diagnostically.'}
write_json(OUTPUT / 'summary.json', summary)
print(json.dumps(summary, indent=2), flush=True)
raise SystemExit(0 if before == after and len(schema_results) == 20
                 and all(r['jing_valid'] for r in schema_results)
                 and len(fixture_results) == 5 and all(r['pass'] for r in fixture_results) else 1)

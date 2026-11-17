#!/usr/bin/env python3
"""Bounded diagnosis only: retain the strict frame-bookmark consumer failure."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
import zipfile

import fitz
from lxml import etree

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--original', type=Path, required=True, help='Final-writer bookmark-ranges.odt from the strict run')
parser.add_argument('--output', type=Path, required=True, help='Fresh diagnostic output directory')
parser.add_argument('--jing', type=Path, required=True)
parser.add_argument('--schemas', type=Path, required=True)
args = parser.parse_args()
OUT = args.output.resolve()
ORIGINAL = args.original.resolve()
JING = args.jing.resolve()
SCHEMAS = args.schemas.resolve()
if OUT.exists():
    raise SystemExit('Output must be fresh; do not overwrite the strict run')
OUT.mkdir(parents=True)
for name in ['inputs', 'roundtrip', 'docx', 'pdf', 'xml']:
    (OUT / name).mkdir()
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
}
TEXT = '{' + NS['text'] + '}'
DRAW = '{' + NS['draw'] + '}'
STYLE = '{' + NS['style'] + '}'
W = '{' + NS['w'] + '}'
commands = []

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')

def command(argv, timeout=45):
    argv = [str(v) for v in argv]
    start = now()
    clock = time.monotonic()
    completed = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    result = {'args': argv, 'started_at_utc': start, 'completed_at_utc': now(),
              'elapsed_seconds': time.monotonic() - clock, 'exit_code': completed.returncode,
              'stdout': completed.stdout, 'stderr': completed.stderr}
    commands.append(result)
    write('commands.json', commands)
    return result

def plain_control(name, as_character=False):
    # Independent ODF strings: no production writer/helper is used.
    attrs = ' '.join('xmlns:' + prefix + '="' + uri + '"' for prefix, uri in NS.items() if prefix != 'w')
    if as_character:
        frame_attrs = 'text:anchor-type="as-char" svg:width="210pt" svg:height="60pt"'
    else:
        frame_attrs = ('text:anchor-type="paragraph" draw:style-name="PlainFrame" '
                       'svg:x="36pt" svg:y="190pt" svg:width="210pt" svg:height="60pt"')
    content = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<office:document-content ' + attrs + ' office:version="1.3">'
        '<office:automatic-styles>'
        '<style:style style:name="PlainFrame" style:family="graphic">'
        '<style:graphic-properties style:horizontal-pos="from-left" style:horizontal-rel="page" '
        'style:vertical-pos="from-top" style:vertical-rel="page" style:wrap="none"/>'
        '</style:style></office:automatic-styles><office:body><office:text>'
        '<text:p><text:bookmark-start text:name="BodyControl"/>BodyControlText'
        '<text:bookmark-end text:name="BodyControl"/></text:p>'
        '<table:table table:name="PlainTable"><table:table-column/><table:table-row>'
        '<table:table-cell><text:p><text:bookmark-start text:name="TableControl"/>TableControlText'
        '<text:bookmark-end text:name="TableControl"/></text:p></table:table-cell>'
        '</table:table-row></table:table>'
        '<text:p><draw:frame draw:name="PlainFrameObject" ' + frame_attrs + '>'
        '<draw:text-box><text:p>'
        '<text:bookmark-start text:name="FrameControl"/>FrameControlText'
        '<text:bookmark-end text:name="FrameControl"/></text:p></draw:text-box>'
        '</draw:frame></text:p><text:p>AfterControl</text:p>'
        '</office:text></office:body></office:document-content>'
    )
    styles = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<office:document-styles ' + attrs + ' office:version="1.3"><office:styles>'
        '<style:default-style style:family="paragraph"><style:paragraph-properties '
        'fo:margin-top="0pt" fo:margin-bottom="8pt"/><style:text-properties fo:font-size="11pt"/>'
        '</style:default-style></office:styles><office:automatic-styles>'
        '<style:page-layout style:name="PlainPage"><style:page-layout-properties '
        'fo:page-width="420pt" fo:page-height="420pt" fo:margin-left="36pt" fo:margin-right="36pt" '
        'fo:margin-top="54pt" fo:margin-bottom="54pt"/></style:page-layout>'
        '</office:automatic-styles><office:master-styles>'
        '<style:master-page style:name="Standard" style:page-layout-name="PlainPage"/>'
        '</office:master-styles></office:document-styles>'
    )
    meta = ('<?xml version="1.0" encoding="UTF-8"?><office:document-meta '
            + attrs + ' office:version="1.3"><office:meta/></office:document-meta>')
    manifest = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" '
        'manifest:version="1.3"><manifest:file-entry manifest:full-path="/" '
        'manifest:media-type="application/vnd.oasis.opendocument.text" manifest:version="1.3"/>'
        '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>'
        '<manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>'
        '<manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>'
        '</manifest:manifest>'
    )
    path = OUT / 'inputs' / (name + '.odt')
    with zipfile.ZipFile(path, 'w') as package:
        package.writestr('mimetype', 'application/vnd.oasis.opendocument.text',
                         compress_type=zipfile.ZIP_STORED)
        for part, text in [('content.xml', content), ('styles.xml', styles),
                           ('meta.xml', meta), ('META-INF/manifest.xml', manifest)]:
            package.writestr(part, text.encode(), compress_type=zipfile.ZIP_DEFLATED)
    return path

def odf_range_text(root):
    opened, found = {}, {}
    def append(text):
        for chars in opened.values():
            chars.append(text)
    def visit(node, in_paragraph=False):
        if node is not root and node.tag == DRAW + 'text-box':
            return
        paragraph = in_paragraph or node.tag in [TEXT + 'p', TEXT + 'h']
        name = node.get(TEXT + 'name')
        if node.tag == TEXT + 'bookmark-start':
            opened[name] = []
        elif node.tag == TEXT + 'bookmark-end':
            if name in opened:
                found[name] = ''.join(opened.pop(name))
        elif node.tag == TEXT + 'bookmark':
            found[name] = ''
        if paragraph:
            if node.tag == TEXT + 's':
                append(' ' * int(node.get(TEXT + 'c', '1')))
            elif node.tag == TEXT + 'tab':
                append('\t')
            elif node.tag == TEXT + 'line-break':
                append('\n')
            if node.text:
                append(node.text)
        for child in node:
            visit(child, paragraph)
            if paragraph and child.tail:
                append(child.tail)
    visit(root)
    return found

def odf_summary(path, stage):
    summary = {'sha256': sha(path), 'markers': [], 'stories': [], 'parts': {}}
    with zipfile.ZipFile(path) as package:
        for part in ['content.xml', 'styles.xml']:
            data = package.read(part)
            root = etree.fromstring(data)
            saved = OUT / 'xml' / stage / part
            saved.parent.mkdir(parents=True, exist_ok=True)
            saved.write_bytes(data)
            summary['parts'][part] = hashlib.sha256(data).hexdigest()
            for marker in root.xpath('//text:bookmark|//text:bookmark-start|//text:bookmark-end', namespaces=NS):
                frames = marker.xpath('ancestor::draw:text-box', namespaces=NS)
                summary['markers'].append({
                    'part': part, 'kind': etree.QName(marker).localname, 'name': marker.get(TEXT + 'name'),
                    'inside_frame': bool(frames), 'path': marker.getroottree().getpath(marker)})
            stories = root.xpath('//office:body/office:text|//style:header|//style:header-left|'
                                 '//style:header-first|//style:footer|//style:footer-left|'
                                 '//style:footer-first|//draw:text-box', namespaces=NS)
            for story in stories:
                summary['stories'].append({
                    'part': part, 'kind': etree.QName(story).localname,
                    'path': story.getroottree().getpath(story),
                    'range_text': odf_range_text(story),
                    'paragraph_text': [''.join(p.itertext()) for p in story.xpath('.//text:p', namespaces=NS)]})
    return summary

def word_range_text(root):
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
            for _, chars in opened.values():
                chars.append(node.text or '')
        for child in node:
            visit(child)
    visit(root)
    return found

def word_summary(path):
    result = {'sha256': sha(path), 'markers': [], 'stories': []}
    with zipfile.ZipFile(path) as package:
        for part in package.namelist():
            if not part.startswith('word/') or not part.endswith('.xml'):
                continue
            root = etree.fromstring(package.read(part))
            starts = root.xpath('//w:bookmarkStart', namespaces=NS)
            boxes = root.xpath('//w:txbxContent', namespaces=NS)
            for node in starts:
                result['markers'].append({
                    'part': part, 'name': node.get(W + 'name'), 'id': node.get(W + 'id'),
                    'inside_frame': bool(node.xpath('ancestor::w:txbxContent', namespaces=NS)),
                    'path': node.getroottree().getpath(node)})
            if starts or boxes:
                result['stories'].append({'part': part, 'kind': 'part', 'range_text': word_range_text(root)})
                for box in boxes:
                    result['stories'].append({
                        'part': part, 'kind': 'txbxContent', 'path': box.getroottree().getpath(box),
                        'text': ''.join(box.xpath('.//w:t/text()', namespaces=NS)),
                        'range_text': word_range_text(box)})
    return result

def input_schema(path):
    results = []
    with zipfile.ZipFile(path) as package:
        for part in ['content.xml', 'styles.xml', 'meta.xml', 'META-INF/manifest.xml']:
            data = package.read(part)
            target = OUT / 'xml' / ('schema-' + path.stem) / part
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            schema_name = ('OpenDocument-v1.3-manifest-schema.rng'
                           if 'manifest' in part else 'OpenDocument-v1.3-schema.rng')
            result = command(['java', '-jar', JING, '-i', SCHEMAS / schema_name, target])
            results.append({'part': part, 'valid': result['exit_code'] == 0,
                            'errors': result['stdout'] + result['stderr']})
    return results

def selected(summary, name):
    return [{'part': story['part'], 'kind': story['kind'], 'text': story['range_text'][name]}
            for story in summary['stories'] if name in story['range_text']]

start = now()
original_copy = OUT / 'inputs/writer-final.odt'
shutil.copyfile(ORIGINAL, original_copy)
cases = [
    ('writer-final', original_copy, 'FrameMark', 'FrameBookmark'),
    ('plain-paragraph', plain_control('plain-paragraph'), 'FrameControl', 'FrameControlText'),
    ('plain-as-character', plain_control('plain-as-character', True), 'FrameControl', 'FrameControlText'),
]
identity = {'started_at_utc': start, 'script_sha256': sha(Path(__file__)),
            'original_path': str(ORIGINAL), 'original_sha256': sha(ORIGINAL),
            'jing_sha256': sha(JING),
            'schema_sha256': {p.name: sha(p) for p in SCHEMAS.glob('*.rng')},
            'libreoffice': command(['soffice', '--version']),
            'purpose': 'Diagnostic A/B only; the original strict FrameMark failure remains unchanged.'}
write('identity.json', identity)
profile = OUT / 'lo-profile'
results = []
for name, source_path, bookmark, text in cases:
    result = {'name': name, 'source_path': str(source_path)}
    try:
        result['schema'] = input_schema(source_path)
        result['source_schema_valid'] = all(row['valid'] for row in result['schema'])
        result['source'] = odf_summary(source_path, 'source-' + name)
        for kind, folder in [('odt:writer8', 'roundtrip'), ('docx:Office Open XML Text', 'docx'), ('pdf', 'pdf')]:
            converted = command(['soffice', '-env:UserInstallation=' + profile.as_uri(),
                                 '--headless', '--convert-to', kind, '--outdir', OUT / folder, source_path])
            if converted['exit_code'] != 0:
                raise RuntimeError('LibreOffice conversion failed: ' + kind)
        roundtrip = OUT / 'roundtrip' / (name + '.odt')
        docx = OUT / 'docx' / (name + '.docx')
        pdf_path = OUT / 'pdf' / (name + '.pdf')
        result['roundtrip_odt'] = odf_summary(roundtrip, 'roundtrip-' + name)
        result['docx'] = word_summary(docx)
        with fitz.open(pdf_path) as pdf:
            result['pdf'] = {'sha256': sha(pdf_path), 'pages': len(pdf),
                             'page_text': [page.get_text() for page in pdf]}
        result['frame_bookmark'] = {
            'name': bookmark, 'expected_text': text,
            'source_selection': selected(result['source'], bookmark),
            'roundtrip_odt_selection': selected(result['roundtrip_odt'], bookmark),
            'docx_selection': selected(result['docx'], bookmark),
            'visible_in_pdf': text in '\n'.join(result['pdf']['page_text'])}
        result['completed'] = True
    except Exception as error:
        result['completed'] = False
        result['error_type'] = type(error).__name__
        result['error'] = str(error)
    results.append(result)
    write('results.json', results)
    print(name, json.dumps(result.get('frame_bookmark', {'error': result.get('error')})), flush=True)
summary = {
    'started_at_utc': start, 'completed_at_utc': now(), 'cases': len(results),
    'completed': sum(r.get('completed', False) for r in results),
    'input_schema_valid': sum(r.get('source_schema_valid', False) for r in results),
    'original_source_unchanged': sha(ORIGINAL) == identity['original_sha256'],
    'frame_bookmarks': {r['name']: r.get('frame_bookmark') for r in results},
    'classification': 'Diagnosis only. No relaxation or reclassification of the original strict consumer check.'}
write('summary.json', summary)
print(json.dumps(summary, indent=2), flush=True)
raise SystemExit(0 if summary['completed'] == 3 and summary['input_schema_valid'] == 3
                 and summary['original_source_unchanged'] else 1)

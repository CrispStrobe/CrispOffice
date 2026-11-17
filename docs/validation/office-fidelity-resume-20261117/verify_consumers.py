#!/usr/bin/env python3
"""Check saved ODF fixtures against OASIS schemas and LibreOffice/Poppler.

Inputs are source-generated packages, not hand-rewritten XML. Run after the
selected test cohorts and make_fixtures.dart, passing their output directories.
The official schemas are downloaded separately and identified in the receipt.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

from lxml import etree
from PIL import Image

REPO = Path(__file__).resolve().parents[3]
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    'xhtml': 'http://www.w3.org/1999/xhtml',
}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def words(path):
    root = etree.parse(str(path))
    return [dict(text=word.text or '', **{k: float(v) for k, v in word.attrib.items()})
            for word in root.xpath('//xhtml:word', namespaces=NS)]


def check_semantics(name, content, text, bbox, raster):
    """Independent observable assertions for the inherited consumer fixtures."""
    checks = {}
    normalized = ' '.join(text.split())
    if name == 'word-paragraph-layout':
        found = words(bbox)
        exact_y = [w['yMin'] for w in found if w['text'] == 'Exact']
        minimum_y = [w['yMin'] for w in found if w['text'] == 'Minimum']
        require(len(exact_y) == 3, 'Exact-spacing fixture lost a line')
        exact_steps = [b - a for a, b in zip(exact_y, exact_y[1:])]
        require(all(abs(step - 18) < .12 for step in exact_steps),
                'Exact line spacing is not 18 points: ' + repr(exact_steps))
        require(len(minimum_y) == 2 and minimum_y[1] - minimum_y[0] >= 23.9,
                'Minimum line spacing is below 24 points')
        require('Blue report header' in normalized and 'Second header line' in normalized
                and 'Green footer' in normalized, 'Styled header/footer text was lost')
        checks.update(exact_line_steps_pt=exact_steps,
                      minimum_line_step_pt=minimum_y[1] - minimum_y[0],
                      header_footer_text=True)
    if name == 'word-note-stories':
        expected = ['Blue footnote body', 'Second footnote line', 'Footnote cell A',
                    'Footnote cell B', 'Second footnote body', 'Custom-mark note body',
                    'Empty-reference note body', 'Explicit custom-mark body',
                    'Endnote body on final page', 'Custom endnote body']
        for phrase in expected:
            require(phrase in normalized, 'Consumer lost note text: ' + phrase)
        require(normalized.count('Blue footnote body') == 1,
                'Repeated reference duplicated the first note body')
        notes = content.xpath('//text:note', namespaces=NS)
        require(len(notes) == 7, 'Unexpected number of emitted note definitions')
        ids = [n.get('{' + NS['text'] + '}id') for n in notes]
        require(len(ids) == len(set(ids)), 'Duplicate note identifiers')
        references = content.xpath('//text:note-ref/@text:ref-name', namespaces=NS)
        require(set(references) <= set(ids), 'Unresolved repeated note reference')
        checks.update(note_definitions=len(notes), resolving_repeated_references=len(references),
                      preserved_phrases=expected)
    if name == 'word-note-recursion':
        require('A links to' in normalized and 'B links to' in normalized,
                'Recursive note fallback lost visible body text')
        require(not content.xpath('//text:note-body//text:note', namespaces=NS),
                'Recursive notes expanded inside note bodies')
        checks['bounded_note_expansion'] = True
    if name == 'word-covered-notes':
        require('Visible merged anchor' in normalized and 'Visible note body' in normalized,
                'Visible merged-table or note text was lost')
        require('HIDDEN_NOTE_BODY' not in normalized,
                'Hidden continuation note leaked into consumer output')
        require(len(content.xpath('//text:note', namespaces=NS)) == 1,
                'Hidden continuation consumed a note definition')
        checks['visible_note_only'] = True
    if name == 'word-list-integration':
        for phrase in ('Numbered item 1', 'Numbered item 2', 'Numbered item 3',
                       'Bullet item 1', 'Bullet item 2'):
            require(phrase in normalized, 'Consumer lost list item: ' + phrase)
        require(not content.xpath('//@*[namespace-uri()="urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0"]'),
                'Fixture contains a redundant extension attribute')
        checks['list_items_visible'] = True
    if name == 'slide-table-colors':
        for phrase in ('White', 'Red', 'Default'):
            require(phrase in normalized, 'Consumer lost table row/cell: ' + phrase)
        with Image.open(raster) as img:
            pixels = list(img.convert('RGB').getdata())
        blue = sum(r < 80 and 60 < g < 130 and 120 < b < 190 for r, g, b in pixels)
        red = sum(r > 100 and g < 70 and b < 90 for r, g, b in pixels)
        require(blue > 1000 and red > 5, 'Authored table fill or font color disappeared')
        checks.update(blue_fill_pixels=blue, red_text_pixels=red, all_cells_visible=True)
    if name == 'slide-table-rtl':
        found = words(bbox)
        # Poppler's raw word strings preserve Arabic code points; word order is
        # determined from coordinates rather than the extractor's bidi ordering.
        first = [w for w in found if w['text'] == 'الأول']
        second = [w for w in found if w['text'] == 'الثاني']
        require(len(first) == len(second) == 1, 'RTL fixture lost a cell word')
        require(first[0]['xMin'] > second[0]['xMin'], 'RTL logical first cell is not on the right')
        checks.update(first_cell_x=first[0]['xMin'], second_cell_x=second[0]['xMin'])
    return checks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', action='append', type=Path, required=True)
    parser.add_argument('--schemas', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--generation', type=Path, required=True,
                        help='Receipt binding freshly generated input packages to source')
    args = parser.parse_args()
    output = args.output.resolve()
    require(not output.exists() or not any(output.iterdir()),
            'Consumer output must be empty; previous files cannot qualify')
    output.mkdir(parents=True, exist_ok=True)
    main_schema = args.schemas / 'OpenDocument-v1.3-schema.rng'
    manifest_schema = args.schemas / 'OpenDocument-v1.3-manifest-schema.rng'
    validators = {'document': etree.RelaxNG(etree.parse(str(main_schema))),
                  'manifest': etree.RelaxNG(etree.parse(str(manifest_schema)))}
    fixtures = {}
    for directory in args.input:
        for path in sorted(directory.resolve().rglob('*')):
            if path.suffix in ('.odt', '.odp') and path.is_file():
                if path.name in fixtures:
                    require(digest(path) == digest(fixtures[path.name]), 'Conflicting fixture names: ' + path.name)
                fixtures[path.name] = path
    require(fixtures, 'No generated ODF fixtures found')
    source_commit = subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()
    generation = json.loads(args.generation.read_text())
    require(generation.get('source_commit') == source_commit and generation.get('passed') is True,
            'Fixture generation does not qualify the current source commit')
    require({name: digest(path) for name, path in fixtures.items()}
            == generation.get('fixtures_sha256'), 'Fixture inventory differs from generation receipt')
    report = {'started_utc': now(), 'source_commit': subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
        'script_sha256': digest(__file__), 'github_actions_used': False,
        'schemas': {path.name: digest(path) for path in (main_schema, manifest_schema)},
        'generation_receipt_sha256': digest(args.generation),
        'tools': {}, 'fixtures': [], 'commands': []}

    def run(command, label, timeout=120):
        process = subprocess.run(command, capture_output=True, timeout=timeout)
        (output / (label + '.stdout')).write_bytes(process.stdout)
        (output / (label + '.stderr')).write_bytes(process.stderr)
        report['commands'].append({'command': command, 'exit_code': process.returncode,
                                   'stdout': label + '.stdout', 'stderr': label + '.stderr'})
        require(process.returncode == 0, 'Consumer command failed: ' + label)
        return process

    for tool, arguments in (('soffice', ['--version']), ('pdftotext', ['-v']),
                            ('pdftoppm', ['-v'])):
        executable = shutil.which(tool)
        require(executable is not None, 'Missing consumer tool: ' + tool)
        result = run([executable] + arguments, tool + '-version')
        report['tools'][tool] = {'path': executable, 'launcher_sha256': digest(executable),
                                 'version': (result.stdout + result.stderr).decode().strip()}
    for filename, source in sorted(fixtures.items()):
        item = {'name': filename, 'source_path': str(source), 'input_sha256': digest(source)}
        try:
            with zipfile.ZipFile(source) as archive:
                require(archive.testzip() is None, 'ZIP CRC check failed')
                first = archive.infolist()[0]
                require(first.filename == 'mimetype' and first.compress_type == zipfile.ZIP_STORED,
                        'First ZIP entry is not the stored ODF mimetype')
                mime = ('application/vnd.oasis.opendocument.text' if source.suffix == '.odt'
                        else 'application/vnd.oasis.opendocument.presentation')
                require(archive.read('mimetype').decode() == mime,
                        'ODF mimetype does not match its file extension')
                parts = {}
                for name in ('content.xml', 'styles.xml', 'meta.xml', 'META-INF/manifest.xml'):
                    document = etree.fromstring(archive.read(name))
                    validator = validators['manifest' if name.startswith('META-INF') else 'document']
                    require(validator.validate(document), name + ': ' + str(validator.error_log))
                    parts[name] = document
                item['schema_parts_passed'] = list(parts)
            stem = source.stem
            profile = output / ('profile-' + stem)
            run(['soffice', '-env:UserInstallation=' + profile.as_uri(), '--headless',
                 '--convert-to', 'pdf', '--outdir', str(output), str(source)], stem + '-import')
            pdf = output / (stem + '.pdf')
            require(pdf.is_file() and pdf.stat().st_size > 0, 'LibreOffice did not produce a PDF')
            txt = output / (stem + '.txt')
            bbox = output / (stem + '.bbox.html')
            run(['pdftotext', '-layout', str(pdf), str(txt)], stem + '-text')
            run(['pdftotext', '-bbox', str(pdf), str(bbox)], stem + '-bbox')
            raster = output / (stem + '.png')
            run(['pdftoppm', '-r', '72', '-f', '1', '-singlefile', '-png', str(pdf),
                 str(output / stem)], stem + '-raster')
            item['semantic_checks'] = check_semantics(stem, parts['content.xml'],
                                                      txt.read_text(), bbox, raster)
            item['artifacts_sha256'] = {p.name: digest(p) for p in (pdf, txt, bbox, raster)}
            item['passed'] = True
            # Profiles are disposable caches, not evidence or source inputs.
            shutil.rmtree(profile, ignore_errors=True)
        except (AssertionError, OSError, subprocess.TimeoutExpired, etree.Error) as error:
            item.update(passed=False, error=str(error))
        report['fixtures'].append(item)
        (output / 'receipt.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
        print(json.dumps({'fixture': filename, 'passed': item['passed'],
                          'error': item.get('error')}, ensure_ascii=False), flush=True)
    report.update(finished_utc=now(), passed=all(item['passed'] for item in report['fixtures']))
    (output / 'receipt.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()

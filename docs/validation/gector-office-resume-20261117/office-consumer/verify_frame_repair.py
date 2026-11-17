#!/usr/bin/env python3
"""Require the bookmark repair, exact frame geometry, and stable surrounding text."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import zipfile

from lxml import etree

NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'x': 'http://www.w3.org/1999/xhtml',
    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
    'v': 'urn:schemas-microsoft-com:vml',
}
STYLE_NAME = '{%s}name' % NS['style']
W = '{' + NS['w'] + '}'


def require(value, message):
    if not value:
        raise AssertionError(message)


def read_json(path):
    return json.loads(path.read_text())


def package_parts(path):
    with zipfile.ZipFile(path) as package:
        return {name: package.read(name) for name in package.namelist()}


def xml(data):
    return etree.fromstring(data)


def canonical(root):
    return etree.tostring(root, method='c14n')


def pdf_words(path):
    tree = etree.parse(str(path))
    words = []
    for page_index, page in enumerate(tree.xpath('//x:page', namespaces=NS)):
        for node in page.xpath('.//x:word', namespaces=NS):
            words.append({'page': page_index + 1, 'text': node.text or '',
                          **{key: float(node.get(key))
                             for key in ['xMin', 'yMin', 'xMax', 'yMax']}})
    return sorted(words, key=lambda item: (item['page'], item['text'], item['xMin'], item['yMin']))


def bookmark_ranges(root):
    opened, ranges = {}, {}

    def visit(node):
        if node is not root and node.tag == W + 'txbxContent':
            return
        if node.tag == W + 'bookmarkStart':
            opened[node.get(W + 'id')] = (node.get(W + 'name'), [])
        elif node.tag == W + 'bookmarkEnd':
            value = opened.pop(node.get(W + 'id'), None)
            if value:
                ranges[value[0]] = ''.join(value[1])
        elif node.tag == W + 't':
            for _, text in opened.values():
                text.append(node.text or '')
        for child in node:
            visit(child)

    visit(root)
    return ranges


def docx_frame(path):
    document = xml(package_parts(path)['word/document.xml'])
    boxes = document.xpath('//w:txbxContent', namespaces=NS)
    boxes = [box for box in boxes
             if ''.join(box.xpath('.//w:t/text()', namespaces=NS)) == 'FrameBookmark']
    require(boxes, 'DOCX has no frame containing the exact visible label')
    observations = []
    for box in boxes:
        anchors = box.xpath('ancestor::wp:anchor', namespaces=NS)
        shapes = box.xpath('ancestor::v:shape|ancestor::v:rect', namespaces=NS)
        if anchors:
            anchor = anchors[-1]
            horizontal = anchor.find('wp:positionH', NS)
            vertical = anchor.find('wp:positionV', NS)
            extent = anchor.find('wp:extent', NS)
            require(horizontal is not None and vertical is not None and extent is not None,
                    'DOCX frame has incomplete anchored geometry')
            placement = {
                'kind': 'DrawingML',
                'horizontal_relative_to': horizontal.get('relativeFrom'),
                'vertical_relative_to': vertical.get('relativeFrom'),
                'x_pt': int(horizontal.find('wp:posOffset', NS).text) / 12700,
                'y_pt': int(vertical.find('wp:posOffset', NS).text) / 12700,
                'width_pt': int(extent.get('cx')) / 12700,
                'height_pt': int(extent.get('cy')) / 12700,
            }
        elif shapes:
            style = dict(piece.strip().split(':', 1) for piece in shapes[-1].get('style', '').split(';') if ':' in piece)

            def points(name):
                value = style[name].strip()
                require(re.fullmatch(r'-?\d+(?:\.\d+)?pt', value),
                        'Unexpected VML length: ' + value)
                return float(value[:-2])

            placement = {
                'kind': 'VML',
                'horizontal_relative_to': style.get('mso-position-horizontal-relative'),
                'vertical_relative_to': style.get('mso-position-vertical-relative'),
                'x_pt': points('margin-left'), 'y_pt': points('margin-top'),
                'width_pt': points('width'), 'height_pt': points('height'),
            }
        else:
            raise AssertionError('DOCX frame has no independently readable placement')
        observations.append({'ranges': bookmark_ranges(box), 'placement': placement})
    return observations


def verify(before, after):
    summaries = {label: read_json(path / 'summary.json')
                 for label, path in [('before', before), ('after', after)]}
    for label, summary in summaries.items():
        require(summary['source_inputs_unchanged'], label + ': source changed during run')
        require(summary['schema_parts'] == summary['jing_valid'] == 20,
                label + ': ODF schema qualification incomplete')
    failures = [result for result in read_json(before / 'fixture-results.json') if not result['pass']]
    require(len(failures) == 1 and failures[0]['name'] == 'bookmark-ranges'
            and "FrameMark selected None" in failures[0]['error'],
            'Before control must fail only at the missing frame bookmark')
    require(summaries['after']['fixture_passes'] == summaries['after']['fixture_count'] == 5,
            'After run did not pass all five strict fixtures')

    parts_before = package_parts(before / 'generated/bookmark-ranges.odt')
    parts_after = package_parts(after / 'generated/bookmark-ranges.odt')
    require(set(parts_before) == set(parts_after), 'ODT package members changed')
    for name in parts_before.keys() - {'content.xml', 'styles.xml'}:
        require(parts_before[name] == parts_after[name], 'Unexpected package change: ' + name)
    expected_content = xml(parts_before['content.xml'])
    expected_styles = xml(parts_before['styles.xml'])
    frame_styles = expected_content.xpath('./office:automatic-styles/style:style[@style:name="SectionFrame"]', namespaces=NS)
    require(len(frame_styles) == 1, 'Before control must contain one automatic frame style')
    frame_style = frame_styles[0]
    frame_style.getparent().remove(frame_style)
    common_styles = expected_styles.find('office:styles', NS)
    require(common_styles is not None, 'Missing common styles container')
    common_styles.append(copy.deepcopy(frame_style))
    require(canonical(expected_content) == canonical(xml(parts_after['content.xml'])),
            'Content changed beyond removal of the automatic graphic style')
    require(canonical(expected_styles) == canonical(xml(parts_after['styles.xml'])),
            'Styles changed beyond moving the same graphic style to common styles')

    previous_words = pdf_words(before / 'converted/bookmark-ranges.bbox.xhtml')
    current_words = pdf_words(after / 'converted/bookmark-ranges.bbox.xhtml')
    require(len(previous_words) == len(current_words), 'Visible word count changed')
    max_drift = 0.0
    frame_label = None
    for previous, current in zip(previous_words, current_words):
        require((previous['page'], previous['text']) == (current['page'], current['text']),
                'Visible text or page ownership changed')
        if current['text'] == 'FrameBookmark':
            frame_label = {'before': previous, 'after': current,
                           'delta_pt': {key: current[key] - previous[key]
                                        for key in ['xMin', 'yMin', 'xMax', 'yMax']}}
            # The proper Writer frame has different internal text metrics from
            # the preceding generic-shape import. Record that difference; the
            # frame's authored box and surrounding text are the invariants.
            require(current['xMin'] >= 35.9 and current['xMax'] <= 246.1
                    and current['yMin'] >= 189.9 and current['yMax'] <= 225.1,
                    'Frame text is outside the authored page-relative box')
        else:
            max_drift = max(max_drift, *(abs(previous[key] - current[key])
                                        for key in ['xMin', 'yMin', 'xMax', 'yMax']))
    require(frame_label is not None, 'Missing rendered frame text')
    require(max_drift <= 0.05, 'Surrounding text moved')

    frames = {'before': docx_frame(before / 'converted/bookmark-ranges.docx'),
              'after': docx_frame(after / 'converted/bookmark-ranges.docx')}
    require(all(frame['ranges'].get('FrameMark') is None for frame in frames['before']),
            'Before DOCX control unexpectedly retained the frame bookmark')
    require(any(frame['ranges'].get('FrameMark') == 'FrameBookmark' for frame in frames['after']),
            'After DOCX does not retain the exact bookmark selection')
    for frame in frames['after']:
        placement = frame['placement']
        require(placement['horizontal_relative_to'] == placement['vertical_relative_to'] == 'page',
                'Frame coordinates are no longer page-relative')
        for key, expected in [('x_pt', 36), ('y_pt', 190), ('width_pt', 210), ('height_pt', 35)]:
            require(abs(placement[key] - expected) <= 0.1, 'DOCX frame geometry changed: ' + key)

    return {'pass': True, 'schema_parts_per_run': 20, 'after_fixture_passes': 5,
            'only_package_change': 'SectionFrame moves from content automatic styles to common styles',
            'visible_words': current_words, 'maximum_surrounding_text_coordinate_drift_pt': max_drift,
            'frame_label_geometry': frame_label,
            'frame_docx': frames,
            'inputs': {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                       for folder in [before, after]
                       for path in sorted(folder.rglob('*'))
                       if path.is_file() and 'lo-profile' not in path.parts}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    require(not args.output.exists(), 'Comparison output must be fresh')
    try:
        result = verify(args.before.resolve(), args.after.resolve())
    except Exception as error:
        result = {'pass': False, 'error_type': type(error).__name__, 'error': str(error)}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'inputs'}, indent=2))
    raise SystemExit(0 if result['pass'] else 1)


if __name__ == '__main__':
    main()

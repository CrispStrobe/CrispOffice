"""Independent PDF/DOCX checks for section columns and paragraph keep state."""
from __future__ import annotations

import zipfile
from lxml import etree
from check_recovery_fixtures import W, NS, _resolved_properties, _value, require


def check_second_wave(spec, output, pages):
    if not any(key in spec for key in ('column_geometry', 'keep_together')):
        return {}
    name = spec['name']
    with zipfile.ZipFile(output / 'converted' / (name + '.docx')) as archive:
        document = etree.fromstring(archive.read('word/document.xml'))
        style_root = etree.fromstring(archive.read('word/styles.xml'))
    styles = {s.get('{%s}styleId' % W): s for s in style_root.findall('w:style', NS)}
    defaults = style_root.find('w:docDefaults/w:pPrDefault/w:pPr', NS)
    result = {}
    if 'column_geometry' in spec:
        expected = spec['column_geometry']
        columns = document.xpath('//w:sectPr/w:cols', namespaces=NS)
        matched = [c for c in columns if int(_value(c, 'num') or '1') == expected['count']]
        require(bool(matched), name + ': authored column count lost in reopened DOCX')
        gap_twips = round(expected['gap_pt'] * 20)
        require(any(int(_value(c, 'space') or '0') == gap_twips for c in matched),
                name + ': authored column gap lost in reopened DOCX')
        positions = {}
        for word, x in expected['words'].items():
            matches = [w for page in pages for w in page['words'] if w['text'] == word]
            require(len(matches) == 1, name + ': missing/duplicate rendered word ' + word)
            observed = matches[0]
            require(abs(observed['xMin'] - x) <= .4,
                    name + ': ' + word + ' at ' + str(observed['xMin']) + ', expected ' + str(x))
            positions[word] = observed
        require(positions['RightFollower']['yMin'] > positions['RightColumn']['yMin'],
                name + ': following plain paragraph did not stay below the explicit column break')
        result['independent_columns_and_break'] = {
            'count': expected['count'], 'gap_twips': gap_twips,
            'positions': positions, 'horizontal_tolerance_pt': .4,
        }
    if 'keep_together' in spec:
        checked = {}
        for word, expected in spec['keep_together'].items():
            paragraphs = document.xpath('//w:p[.//w:t[text()=$word]]', namespaces=NS, word=word)
            require(len(paragraphs) == 1, name + ': missing/ambiguous reopened paragraph ' + word)
            props = _resolved_properties(paragraphs[0], styles, 'pPr', defaults=defaults)
            keep = props.get('keepLines')
            observed = keep is not None and _value(keep) not in ('0', 'false', 'off')
            require(observed == expected,
                    name + ': keep-together for ' + word + ' is ' + str(observed) + ', expected ' + str(expected))
            checked[word] = {'expected': expected, 'observed': observed, 'serialized_value': _value(keep)}
        result['independent_keep_together'] = checked
    return result

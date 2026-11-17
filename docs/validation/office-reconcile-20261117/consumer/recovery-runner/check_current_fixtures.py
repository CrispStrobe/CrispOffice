"""Independent consumer checks for newly reconciled custom tabs and tables."""
from __future__ import annotations

import zipfile

from lxml import etree

from check_recovery_fixtures import W, NS, _resolved_properties, _value, require


def check_current(spec, output, pages):
    if not any(key in spec for key in ('tab_positions', 'minimum_row', 'invalid_cells')):
        return {}
    name = spec['name']
    with zipfile.ZipFile(output / 'converted' / (name + '.docx')) as archive:
        document = etree.fromstring(archive.read('word/document.xml'))
        style_root = etree.fromstring(archive.read('word/styles.xml'))
        styles = {s.get('{%s}styleId' % W): s for s in style_root.findall('w:style', NS)}
        result = {}
        if 'tab_positions' in spec:
            checked = {}
            for word, expected in spec['tab_positions'].items():
                paragraphs = document.xpath('//w:p[.//w:t[text()=$word]]', namespaces=NS, word=word)
                require(len(paragraphs) == 1, name + ': missing reopened tab paragraph ' + word)
                props = _resolved_properties(paragraphs[0], styles, 'pPr')
                tabs = props.get('tabs')
                require(tabs is not None, name + ': missing reopened custom tabs')
                values = [{'position_twips': int(_value(tab, 'pos')), 'alignment': _value(tab)}
                          for tab in tabs if _value(tab) != 'clear']
                require({'position_twips': round(expected['position_pt'] * 20), 'alignment': 'left'} in values,
                        name + ': wrong reopened custom tab: ' + str(values))
                matches = [w for page in pages for w in page['words'] if w['text'] == word]
                require(len(matches) == 1, name + ': missing rendered tab word ' + word)
                observed = matches[0]['xMin']
                require(abs(observed - expected['page_left_pt']) <= .4,
                        name + ': tab word at ' + str(observed) + ', expected ' + str(expected['page_left_pt']))
                checked[word] = {'tabs': values, 'rendered_left_pt': observed, 'tolerance_pt': .4}
            result['independent_custom_tab_positions'] = checked
        if 'minimum_row' in spec:
            rows = document.xpath('//w:tr', namespaces=NS)
            require(len(rows) == 1, name + ': expected one reopened table row')
            height = rows[0].find('w:trPr/w:trHeight', NS)
            require(height is not None and _value(height, 'hRule') in (None, 'atLeast'),
                    name + ': reopened row is fixed-height')
            minimum = int(_value(height)) / 20
            require(minimum >= spec['minimum_row']['minimum_pt'], name + ': minimum row height lost')
            words = spec['minimum_row']['words']
            locations = []
            for word in words:
                matches = [w for page in pages for w in page['words'] if w['text'] == word]
                require(len(matches) == 1, name + ': multiline cell content clipped or duplicated: ' + word)
                locations.append(matches[0])
            extent = max(w['yMax'] for w in locations) - min(w['yMin'] for w in locations)
            require(extent > spec['minimum_row']['minimum_pt'] + 15,
                    name + ': row did not grow around all three lines')
            fills = rows[0].xpath('./w:tc/w:tcPr/w:shd/@w:fill', namespaces=NS)
            require(fills == ['CCEEFF'], name + ': valid authored cell fill lost: ' + str(fills))
            result['independent_minimum_row'] = {'reopened_minimum_pt': minimum,
                'height_rule': _value(height, 'hRule') or 'atLeast (default)',
                'rendered_text_extent_pt': extent, 'words': words, 'cell_fills': fills}
        if 'invalid_cells' in spec:
            cells = document.xpath('//w:tc', namespaces=NS)
            require(len(cells) == len(spec['invalid_cells']), name + ': invalid properties lost cells')
            bidi = document.xpath('//w:tblPr/w:bidiVisual', namespaces=NS)
            require(all(_value(value) in ('0', 'false', 'off') for value in bidi),
                    name + ': logical end border cannot be treated as right in a bidi table')
            checked = []
            for cell, word in zip(cells, spec['invalid_cells']):
                require(word in ''.join(cell.xpath('.//w:t/text()', namespaces=NS)), name + ': lost authored cell text')
                fills = cell.xpath('./w:tcPr/w:shd/@w:fill', namespaces=NS)
                require(all(fill.upper() in ('AUTO', 'FFFFFF') for fill in fills), name + ': invalid fill became a visible color')
                right = cell.find('w:tcPr/w:tcBorders/w:right', NS)
                # LibreOffice emits the OOXML logical end border. In this
                # explicitly non-bidi table it is the authored right edge.
                if right is None:
                    right = cell.find('w:tcPr/w:tcBorders/w:end', NS)
                require(right is not None and _value(right) == 'single', name + ': valid border lost with invalid fill')
                require(_value(right, 'sz') == '4' and _value(right, 'color') == '000000',
                        name + ': authored half-point black border changed')
                checked.append({'word': word, 'fills': fills, 'right_border': _value(right),
                                'serialized_edge': etree.QName(right).localname,
                                'border_size_eighth_points': _value(right, 'sz'),
                                'border_color': _value(right, 'color')})
            result['independent_invalid_property_preservation'] = checked
        return result

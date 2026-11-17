"""Independent PDF and LibreOffice-reopened DOCX recovery assertions."""
from __future__ import annotations
import re
import zipfile
from lxml import etree
from PIL import Image

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W}

def require(condition, message):
    if not condition:
        raise AssertionError(message)

def _value(element, name='val'):
    return None if element is None else element.get('{%s}%s' % (W, name))

def _properties(node):
    return {} if node is None else {etree.QName(c).localname: c for c in node}

def _style_chain(style_id, styles, seen=None):
    seen = set() if seen is None else seen
    if not style_id or style_id in seen or style_id not in styles:
        return []
    seen.add(style_id)
    style = styles[style_id]
    return _style_chain(_value(style.find('w:basedOn', NS)), styles, seen) + [style]

def _resolved_properties(paragraph, styles, kind, run=None, defaults=None):
    result = _properties(defaults)
    pstyle = _value(paragraph.find('w:pPr/w:pStyle', NS))
    if pstyle is None:
        pstyle = next((key for key, value in styles.items()
            if value.get('{%s}type' % W) == 'paragraph'
            and value.get('{%s}default' % W) == '1'), None)
    for style in _style_chain(pstyle, styles):
        result.update(_properties(style.find('w:' + kind, NS)))
    if run is None:
        result.update(_properties(paragraph.find('w:' + kind, NS)))
    else:
        for style in _style_chain(_value(run.find('w:rPr/w:rStyle', NS)), styles):
            result.update(_properties(style.find('w:rPr', NS)))
        result.update(_properties(run.find('w:rPr', NS)))
    return result

def check_reopened(spec, output, pages):
    name = spec['name']
    if not ('paragraph_decorations' in spec or 'styled_footer' in spec):
        return {}
    result = {}
    with zipfile.ZipFile(output / 'converted' / (name + '.docx')) as archive:
        document = etree.fromstring(archive.read('word/document.xml'))
        style_root = etree.fromstring(archive.read('word/styles.xml'))
        styles = {s.get('{%s}styleId' % W): s for s in style_root.findall('w:style', NS)}
        if 'paragraph_decorations' in spec:
            checked = {}
            for word, expected in spec['paragraph_decorations'].items():
                paragraphs = document.xpath('//w:p[.//w:t[text()=$word]]', namespaces=NS, word=word)
                require(len(paragraphs) == 1, name + ': ambiguous reopened paragraph ' + word)
                props = _resolved_properties(paragraphs[0], styles, 'pPr')
                fill = _value(props.get('shd'), 'fill')
                fill = fill.upper() if fill else None
                borders = props.get('pBdr')
                sides = {} if borders is None else {
                    etree.QName(side).localname: dict(kind=_value(side), color=_value(side, 'color'), size=_value(side, 'sz'))
                    for side in borders
                }
                if expected['fill'] is None:
                    require(fill in (None, 'AUTO', 'FFFFFF'), name + ': plain paragraph inherited custom fill ' + str(fill))
                else:
                    require(fill == expected['fill'], name + ': reopened fill for ' + word + ' is ' + str(fill))
                if expected['border'] is None:
                    require(all(side['kind'] in (None, 'nil', 'none') for side in sides.values()),
                            name + ': plain paragraph inherited borders')
                else:
                    for edge in ('top', 'bottom', 'left', 'right'):
                        side = sides.get(edge)
                        require(side is not None and side['kind'] == 'single'
                                and (side['color'] or '').upper() == expected['border']
                                and side['size'] == '4',
                                name + ': reopened border for ' + word + '/' + edge + ' is ' + str(side))
                checked[word] = {'fill': fill, 'borders': sides}
            result['reopened_paragraph_decorations'] = checked
        if 'styled_footer' in spec:
            expected = spec['styled_footer']
            sequence = expected['suffix'].split()
            checked_pages = []
            for number, page in zip(expected['page_numbers'], pages):
                tokens = [word['text'] for word in page['words']]
                needle = [str(number), *sequence]
                matches = [start for start in range(len(tokens) - len(needle) + 1)
                           if tokens[start:start + len(needle)] == needle]
                require(len(matches) == 1, name + ': missing actual page field + suffix on page ' + str(number))
                checked_pages.append({'page': number, 'tokens': needle,
                                      'locations': page['words'][matches[0]:matches[0] + len(needle)]})
            candidates = []
            for path in archive.namelist():
                if re.fullmatch(r'word/footer\d+\.xml', path):
                    root = etree.fromstring(archive.read(path))
                    for paragraph in root.xpath('//w:p', namespaces=NS):
                        text = ' '.join(''.join(paragraph.xpath('.//w:t/text()', namespaces=NS)).split())
                        if expected['suffix'] in text:
                            candidates.append((path, paragraph))
            require(candidates, name + ': reopened footer lost its title suffix')
            checked_runs = []
            defaults = style_root.find('w:docDefaults/w:rPrDefault/w:rPr', NS)
            for path, paragraph in candidates:
                instructions = paragraph.xpath('.//w:instrText/text() | .//w:fldSimple/@w:instr', namespaces=NS)
                require(any(re.search(r'\bPAGE\b', value) for value in instructions),
                        name + ': reopened footer contains cached text instead of a PAGE field')
                runs = [run for run in paragraph.xpath('.//w:r', namespaces=NS)
                        if ''.join(run.xpath('.//w:t/text()', namespaces=NS)).strip()]
                require(runs, name + ': reopened footer has no visible styled runs')
                for run in runs:
                    props = _resolved_properties(paragraph, styles, 'rPr', run, defaults)
                    bold = props.get('b')
                    bvalue = _value(bold)
                    observed = {'text': ''.join(run.xpath('.//w:t/text()', namespaces=NS)),
                                'bold': bold is not None and bvalue not in ('0', 'false', 'off'),
                                'color': _value(props.get('color')), 'size_half_points': _value(props.get('sz'))}
                    require(observed['bold'] == expected['bold'], name + ': reopened footer lost bold: ' + str(observed))
                    require((observed['color'] or '').upper() == expected['color'], name + ': reopened footer lost blue: ' + str(observed))
                    require(observed['size_half_points'] == str(expected['font_size_half_points']),
                            name + ': reopened footer lost 14pt size: ' + str(observed))
                    checked_runs.append({'part': path, **observed})
            result['live_footer_pages'] = checked_pages
            result['reopened_footer_runs'] = checked_runs
    return result

def check_raster(spec, raster, page, semantics):
    if not ('paragraph_decorations' in spec or 'styled_footer' in spec):
        return {}
    measured = {}
    with Image.open(raster) as image:
        image = image.convert('RGB')
        def count(bounds, target, tolerance=20):
            x1, y1, x2, y2 = bounds
            crop = image.crop((max(0, int(x1 / .75)), max(0, int(y1 / .75)),
                               min(image.width, int(x2 / .75) + 1), min(image.height, int(y2 / .75) + 1)))
            return sum(all(abs(value - expected) <= tolerance for value, expected in zip(pixel, target))
                       for pixel in crop.getdata())
        if 'paragraph_decorations' in spec:
            for word, expected in spec['paragraph_decorations'].items():
                if expected['fill'] is None:
                    continue
                location = semantics['word_locations'][word]
                color = tuple(int(expected['fill'][index:index + 2], 16) for index in (0, 2, 4))
                bounds = [location['xMin'], location['yMin'], min(location['xMax'] + 120, 364), location['yMax']]
                pixels = count(bounds, color)
                require(pixels >= 60, spec['name'] + ': authored background missing around ' + word)
                measured[word] = {'fill_rgb': color, 'matching_pixels': pixels, 'bounds_pt': bounds}
        if 'styled_footer' in spec:
            locations = semantics['live_footer_pages'][page - 1]['locations']
            bounds = [min(w['xMin'] for w in locations), min(w['yMin'] for w in locations),
                      max(w['xMax'] for w in locations), max(w['yMax'] for w in locations)]
            pixels = count(bounds, (0, 0, 255))
            require(pixels >= 30, spec['name'] + ': footer does not visibly render blue')
            measured['footer'] = {'matching_blue_pixels': pixels, 'bounds_pt': bounds, 'page': page}
    return measured

#!/usr/bin/env python3
"""Isolate cmap-dependent FreeType rasterization without changing glyph data.

Diagnostic-only Python tooling; no dependency is added to Quds. The actual
Flutter pipeline is qualified separately. This probe never claims that
Matplotlib's FreeType configuration is identical to Flutter's.
"""

import hashlib
import importlib.metadata
import json
import sys
from pathlib import Path

import matplotlib.ft2font as ft
import numpy as np
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable


def digest(data):
    return hashlib.sha256(data).hexdigest()


def cmap_variant(source_path, target_path, mapping):
    font = TTFont(source_path, lazy=True, recalcTimestamp=False)
    table = newTable('cmap')
    table.tableVersion = 0
    table.tables = []
    for fmt, enc, values in [
        (4, 1, {cp: gid for cp, gid in mapping.items() if cp < 0xFFFF}),
        (12, 10, mapping),
    ]:
        if fmt == 12 and max(mapping) < 0xFFFF:
            continue
        subtable = CmapSubtable.newSubtable(fmt)
        subtable.platformID = 3
        subtable.platEncID = enc
        subtable.language = 0
        subtable.cmap = values
        table.tables.append(subtable)
    font['cmap'] = table
    font.save(target_path)


def raster(path, code_point, flags):
    font = ft.FT2Font(str(path), hinting_factor=1)
    font.set_size(64, 72)
    font.set_text(chr(code_point), flags=flags)
    font.draw_glyphs_to_bitmap()
    pixels = np.array(font.get_image())
    return {
        'width_and_height_26_6': list(font.get_width_height()),
        'bitmap_shape': list(pixels.shape),
        'nonzero_pixels': int(np.count_nonzero(pixels)),
        'bitmap_sha256': digest(pixels.tobytes()),
    }


def main():
    source_path = Path(sys.argv[1]).resolve()
    output = Path(sys.argv[2]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = TTFont(source_path, lazy=True)
    cmap = source.getBestCmap()
    variants = {
        'full': (source_path, {cp: cp for cp in [65, 66, 67, 90]}),
        'latin_cmap': (
            output / 'full-glyphs-latin-cmap.ttf',
            {65: 65, 66: 66, 67: 67, 90: 90},
        ),
        'alias_cmap': (
            output / 'full-glyphs-alias-cmap.ttf',
            {65: 65, 66: 0x1F600, 67: 0x20000, 90: 90},
        ),
    }
    table_checks = {}
    for name, (path, code_points) in variants.items():
        if name != 'full':
            cmap_variant(source_path, path, {
                output_cp: cmap[input_cp]
                for input_cp, output_cp in code_points.items()
            })
        variant = TTFont(path, lazy=True)
        changed_tables = [
            tag for tag in source.reader.keys()
            if source.reader[tag] != variant.reader[tag]
        ]
        assert set(changed_tables) <= {'head', 'cmap'}, changed_tables
        table_checks[name] = {
            'changed_tables': changed_tables,
            'glyf_identical': source.reader['glyf'] == variant.reader['glyf'],
            'hmtx_identical': source.reader['hmtx'] == variant.reader['hmtx'],
            'font_sha256': digest(path.read_bytes()),
            'cmap': {f'U+{cp:X}': f'U+{out:X}' for cp, out in code_points.items()},
        }
    modes = {
        'native': ft.LoadFlags.NO_AUTOHINT,
        'light': ft.LoadFlags.TARGET_LIGHT,
        'auto_light': ft.LoadFlags.FORCE_AUTOHINT | ft.LoadFlags.TARGET_LIGHT,
        'unhinted': ft.LoadFlags.NO_HINTING,
    }
    results = {}
    for mode, flags in modes.items():
        results[mode] = {}
        for cp in [65, 66, 67, 90]:
            samples = {
                name: raster(path, code_points[cp], flags)
                for name, (path, code_points) in variants.items()
            }
            reference = samples['full']
            for sample in samples.values():
                sample['equal_to_full'] = (
                    sample['bitmap_shape'] == reference['bitmap_shape']
                    and sample['bitmap_sha256'] == reference['bitmap_sha256']
                )
            results[mode][chr(cp)] = samples
    controls = all(
        sample['equal_to_full']
        for mode in ['native', 'unhinted']
        for samples in results[mode].values()
        for sample in samples.values()
    )
    changed = any(
        not samples['latin_cmap']['equal_to_full']
        for samples in results['auto_light'].values()
    )
    assert controls, 'Expected native and unhinted cmap-only controls to match'
    assert changed, 'Expected cmap-sensitive auto-hinting in this runtime'
    report = {
        'scope': 'FreeType diagnostic; not a claim about Flutter hint settings',
        'source_font': str(source_path),
        'source_sha256': digest(source_path.read_bytes()),
        'font_size_points': 64,
        'dpi': 72,
        'hinting_factor': 1,
        'runtime': {
            'python': sys.version,
            'fonttools': importlib.metadata.version('fonttools'),
            'matplotlib': importlib.metadata.version('matplotlib'),
            'freetype': ft.__freetype_version__,
        },
        'table_checks': table_checks,
        'native_and_unhinted_controls_equal': controls,
        'cmap_only_change_affects_auto_hinting': changed,
        'results': results,
    }
    (output / 'cmap-autohint-receipt.json').write_text(
        json.dumps(report, indent=2) + '\n', encoding='utf-8'
    )
    print(json.dumps({
        'receipt': str(output / 'cmap-autohint-receipt.json'),
        'native_and_unhinted_controls_equal': controls,
        'cmap_only_change_affects_auto_hinting': changed,
    }))


if __name__ == '__main__':
    main()

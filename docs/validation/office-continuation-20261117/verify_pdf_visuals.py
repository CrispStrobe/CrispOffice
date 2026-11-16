#!/usr/bin/env python3
"""Compare emitted PDF fixtures with controls that omit ActualText wrappers.

The Dart regression produces each PDF/control pair and asserts Quds extraction.
This independent Poppler gate checks one-page raster equality. External text
extraction is recorded verbatim, including differences from the source text.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess

from PIL import Image, ImageChops

FIXTURES = ('word-logical-source', 'worksheet-logical-source',
            'rotated-slide-logical-source')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def execute(command):
    result = subprocess.run(command, capture_output=True, check=True)
    if result.stderr.strip():
        raise RuntimeError('Unexpected tool diagnostic: ' + result.stderr.decode(errors='replace'))
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True, type=Path)
    args = parser.parse_args()
    directory = args.directory.resolve()
    report = {'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'script_sha256': digest(Path(__file__)), 'dpi': 120,
              'scope': 'Three one-page fixtures, identical painted PDF content with and without ActualText wrappers.',
              'text_scope': 'Raw external extraction is observational; exact authored-text equality is not the raster gate.',
              'render_policy': 'Reject diagnostics, unequal image dimensions, and empty rasters before comparing pixels.',
              'commands': [], 'fixtures': [], 'github_actions_used': False}
    for tool in ('pdfinfo', 'pdftoppm', 'pdftotext'):
        result = subprocess.run([tool, '-v'], capture_output=True, check=True)
        report[tool + '_version'] = (result.stdout + result.stderr).decode().strip()
    for name in FIXTURES:
        pdfs = [directory / (name + suffix + '.pdf')
                for suffix in ('', '-paint-control')]
        for pdf in pdfs:
            command = ['pdfinfo', str(pdf)]
            info = execute(command).decode()
            report['commands'].append(command)
            match = re.search(r'^Pages:\s+(\d+)\s*$', info, re.MULTILINE)
            if not match or int(match[1]) != 1:
                raise RuntimeError('Fixture must have exactly one page: ' + str(pdf))
            command = ['pdftoppm', '-r', '120', '-singlefile', '-png',
                       str(pdf), str(pdf.with_suffix(''))]
            execute(command)
            report['commands'].append(command)
        images = [Image.open(p.with_suffix('.png')).convert('RGB') for p in pdfs]
        if images[0].size != images[1].size:
            raise RuntimeError('Raster dimensions differ: ' + name)
        ink_pixels = [sum(pixel != (255, 255, 255) for pixel in image.getdata())
                      for image in images]
        if not all(ink_pixels):
            raise RuntimeError('Fixture raster must contain visible content: ' + name)
        difference = ImageChops.difference(*images)
        different_pixels = sum(pixel != (0, 0, 0) for pixel in difference.getdata())
        command = ['pdftotext', '-raw', str(pdfs[0]), '-']
        raw_text = execute(command)
        report['commands'].append(command)
        text_path = directory / (name + '-poppler-raw.txt')
        text_path.write_bytes(raw_text)
        source_path = directory / (name + '-source.txt')
        source = source_path.read_text()
        report['fixtures'].append({
            'name': name, 'size_pixels': list(images[0].size),
            'nonwhite_pixels': ink_pixels,
            'different_pixels': different_pixels,
            'raster_equal': different_pixels == 0,
            'source_text': source, 'poppler_raw_text': raw_text.decode(),
            'external_text_matches_source_exactly': raw_text.decode() == source,
            'files_sha256': {p.name: digest(p) for p in
                             [*pdfs, *(p.with_suffix('.png') for p in pdfs),
                              source_path, text_path]},
        })
    report['passed'] = all(item['raster_equal'] for item in report['fixtures'])
    report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (directory / 'poppler-receipt.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({'passed': report['passed'], 'fixtures': [
        {key: item[key] for key in ('name', 'different_pixels', 'external_text_matches_source_exactly')}
        for item in report['fixtures']]}))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()

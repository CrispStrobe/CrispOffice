#!/usr/bin/env python3
"""Audit recovered source-bound regression and independent PDF evidence."""
import argparse
import datetime
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    evidence = repo / 'docs/validation/text-rendering-continuation-20261116'
    baseline_path = evidence / 'baseline/receipt.json'
    engine_path = evidence / 'engine-attempt1/receipt.json'
    poppler_path = evidence / 'poppler/receipt.json'
    baseline = json.loads(baseline_path.read_text())
    engine = json.loads(engine_path.read_text())
    poppler = json.loads(poppler_path.read_text())
    result = {
        'schema': 'quds-recovered-evidence-audit-v1',
        'checked_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'current_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo).decode().strip(),
        'recovered_receipts': {str(p.relative_to(repo)): sha(p.read_bytes())
                               for p in (baseline_path, engine_path, poppler_path)},
        'limits': 'Checks recovered receipt/log/fixture integrity and binds source hashes; does not claim the old engine gate covers changed incoming ODS sources.',
        'checks': {},
    }
    checks = result['checks']
    checks['harness_integrity'] = {}
    for name, receipt, script, captured in (
        ('baseline', baseline, 'validate_baseline.py', None),
        ('engine', engine, 'validate.py', 'engine-attempt1/validate-used.py'),
        ('poppler', poppler, 'verify_pdf_rendering.py', 'poppler/verify-pdf-rendering-used.py'),
    ):
        checks['harness_integrity'][name] = {
            'current_script': script,
            'current_script_matches': sha((evidence / script).read_bytes()) == receipt['harness_sha256'],
            'captured_script': captured,
            'captured_script_matches': (sha((evidence / captured).read_bytes()) == receipt['harness_sha256']
                                        if captured is not None else None),
        }
    spec = importlib.util.spec_from_file_location('validation', evidence / 'validate.py')
    validation = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validation)
    for name, receipt in [('baseline', baseline), ('engine-attempt1', engine), ('poppler', poppler)]:
        entries = []
        for command in receipt['commands']:
            item = {'name': command['name'], 'exit_code': command['exit_code']}
            for stream in ('stdout', 'stderr'):
                path = evidence / name / command[stream]
                data = path.read_bytes()
                if path.suffix == '.gz':
                    data = gzip.decompress(data)
                item[stream + '_matches'] = sha(data) == command[stream + '_sha256']
                if command['name'] == 'tests' and stream == 'stdout':
                    summary = validation.summarize_events(data)
                    item['test_summary_matches'] = summary == command['summary']
                    item['outcomes'] = summary['outcomes']
                    item['runner_success'] = summary['runner_success']
            entries.append(item)
        checks[name + '_log_integrity'] = entries

    baseline_hashes = {}
    names = list(baseline['source_sha256'])
    requests = ''.join(baseline['baseline_commit'] + ':' + name + '\n' for name in names)
    objects = subprocess.run(['git', 'cat-file', '--batch'], cwd=repo, input=requests.encode(),
                             stdout=subprocess.PIPE, check=True).stdout
    cursor = 0
    for name in names:
        newline = objects.index(b'\n', cursor)
        header = objects[cursor:newline].split()
        if len(header) != 3 or header[1] != b'blob':
            raise ValueError('Missing baseline blob: ' + name)
        length = int(header[2])
        cursor = newline + 1
        data = objects[cursor:cursor + length]
        cursor += length + 1
        baseline_hashes[name] = sha(data) == baseline['source_sha256'][name]
    saved_lock_path = Path('docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock')
    saved_lock_hash = sha((repo / saved_lock_path).read_bytes())
    checks['baseline_source'] = {
        'commit': baseline['baseline_commit'],
        'checked_paths': len(baseline_hashes),
        'mismatches': [name for name, matches in baseline_hashes.items() if not matches],
        'unchanged_during_original_run': baseline['source_unchanged'],
        'probe_hashes_match_current': {name: sha((repo / name).read_bytes()) == digest
                                     for name, digest in baseline['probe_sha256'].items()},
        'recorded_lock_sha256': baseline['lock_sha256'],
        'lock_hash_matches_current': (sha((repo / 'pubspec.lock').read_bytes()) == baseline['lock_sha256']
                                      if (repo / 'pubspec.lock').is_file() else None),
        'committed_saved_lock': {'path': str(saved_lock_path), 'sha256': saved_lock_hash,
                                'matches_recorded': saved_lock_hash == baseline['lock_sha256']},
    }
    for name, receipt in [('engine', engine), ('poppler', poppler)]:
        expected = receipt['source_after_sha256']
        mismatches = []
        missing = []
        for path, digest in expected.items():
            local = repo / path
            if not local.is_file():
                missing.append(path)
            elif sha(local.read_bytes()) != digest:
                mismatches.append(path)
        checks[name + '_current_source_binding'] = {
            'recorded_paths': len(expected),
            'before_after_match': receipt['source_before_sha256'] == expected,
            'current_mismatches': mismatches,
            'current_missing': missing,
            'original_passed': receipt['passed'],
        }
    checks['poppler_artifact_integrity'] = {
        name: sha((evidence / 'poppler' / name).read_bytes()) == item['sha256']
        and (evidence / 'poppler' / name).stat().st_size == item['bytes']
        for name, item in poppler['artifacts'].items()
    }
    fixture_matches = {}
    for name, item in poppler['inputs_before'].items():
        path = engine_path if name == 'producer-receipt.json' else evidence / 'engine-attempt1/render' / name
        fixture_matches[name] = sha(path.read_bytes()) == item['sha256']
    checks['poppler_input_producer_binding'] = fixture_matches
    checks['poppler_inputs_unchanged'] = poppler['inputs_before'] == poppler['inputs_after']
    checks['poppler_recomputed'] = {
        'raster': None,
        'text': None,
    }
    spec = importlib.util.spec_from_file_location('pdf_verification', evidence / 'verify_pdf_rendering.py')
    pdf = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pdf)
    # Comparison computes a difference image. Use existing bytes only here;
    # preserve all recovered evidence and run the renderer separately.
    from PIL import Image, ImageChops
    with Image.open(evidence / 'poppler/encoded-aliases.png') as encoded:
        with Image.open(evidence / 'poppler/identity-glyph-reference.png') as legacy:
            a, b = encoded.convert('RGB'), legacy.convert('RGB')
            difference = ImageChops.difference(a, b)
            rgb = a.tobytes()
            raster = {'dimensions': list(a.size), 'same_dimensions': a.size == b.size,
                      'rgb_sha256': sha(rgb),
                      'nonwhite_ink_pixels': sum(rgb[i:i+3] != b'\xff\xff\xff' for i in range(0, len(rgb), 3)),
                      'difference_bbox': difference.getbbox(),
                      'identical_rgb': a.tobytes() == b.tobytes()}
    checks['poppler_recomputed']['raster'] = raster
    authored = (evidence / 'poppler/authored-text.txt').read_bytes().decode('utf-8')
    checks['poppler_recomputed']['text'] = pdf.compare_text(evidence / 'poppler', authored)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=True) + '\n')
    print(json.dumps({'output': str(args.output), 'baseline_sources': checks['baseline_source']['checked_paths'],
                      'baseline_source_mismatches': checks['baseline_source']['mismatches'],
                      'engine_source_binding': checks['engine_current_source_binding'],
                      'poppler_source_binding': checks['poppler_current_source_binding'],
                      'all_poppler_artifacts_match': all(checks['poppler_artifact_integrity'].values()),
                      'all_poppler_producer_inputs_match': all(fixture_matches.values()),
                      'raster': raster, 'text_passed': checks['poppler_recomputed']['text']['passed']}))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Read-only artifact/row audit; does not invoke Dart or native inference."""
import base64
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone
import zlib

sys.dont_write_bytecode = True
ROOT = Path('/home/agent/.codex/skills/remote-skills/.quds-gector-work/worktrees/quds_office_suite')
WORK = ROOT.parent.parent
OUT = Path('/workspace/scratch/c4115a2a85e2/segmentation-validation/incremental-quality-final-v2')
RESULT = OUT.parent / 'incremental-quality-independent-audit.json'
PACK = WORK / 'assets/native-development-pack-v1'
DART = WORK / 'runtime/flutter-sdk/bin/cache/dart-sdk/bin/dart'
SOURCE_REVISION = 'd092d50a844b5cfcc31bb6c39220704b4ff11cf5'
LANES = ['writing_only', 'deterministic', 'model_only', 'combined']
failures = []
check_count = 0

def sha(data):
    return hashlib.sha256(data).hexdigest()

def file_pin(path):
    data = path.read_bytes()
    return {'file': path.name, 'bytes': len(data), 'sha256': sha(data)}

def check(ok, label):
    global check_count
    check_count += 1
    if not ok:
        failures.append(label)

def eq(actual, expected, label):
    check(actual == expected, label)

def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])

def conflicts(a, b):
    if a['start'] == a['end']:
        return b['start'] <= a['start'] <= b['end']
    if b['start'] == b['end']:
        return a['start'] <= b['start'] <= a['end']
    return a['start'] < b['end'] and b['start'] < a['end']

def projection(case, results, label):
    statuses = [r['status'] for r in results]
    complete = 'success' in statuses and all(s in ('success', 'unsupported') for s in statuses)
    accepted, skipped, displayed = [], [], []
    encoded = case['input'].encode('utf-16-le')
    for r in results:
        if r['status'] != 'success':
            eq(r['findings'], [], label + ':unsuccessful-empty')
            continue
        displayed.extend(r['findings'])
        for f in r['findings']:
            eq(f['provider_id'], r['provider_id'], label + ':finding-provider')
            start, end = f['start'] - case['start_offset'], f['end'] - case['start_offset']
            check(0 <= start <= end <= len(encoded) // 2, label + ':utf16-range')
            original = encoded[start * 2:end * 2].decode('utf-16-le')
            eq(original, f['original'], label + ':utf16-original')
            for replacement in f['replacements']:
                replacement.encode('utf-16-le')
            reason = ('incomplete-report' if not complete else
                      'no-replacement-advisory' if not f['replacements'] else
                      'overlap-with-earlier-projection' if any(conflicts(f, prev) for prev in accepted) else None)
            if reason:
                skipped.append({**f, 'reason': reason})
            else:
                accepted.append(f)
    displayed.sort(key=lambda f: (f['start'], f['end']))
    corrected = None
    if complete:
        corrected_bytes = encoded
        for f in sorted(accepted, key=lambda f: -f['start']):
            start, end = f['start'] - case['start_offset'], f['end'] - case['start_offset']
            corrected_bytes = (corrected_bytes[:start * 2] + f['replacements'][0].encode('utf-16-le')
                               + corrected_bytes[end * 2:])
        corrected = corrected_bytes.decode('utf-16-le')
    return {
        'complete': complete,
        'clean_report': complete and not displayed,
        'flagged': bool(displayed),
        'corrected': corrected,
        'changed': corrected is not None and corrected != case['input'],
        'exact_expected': complete and corrected == case['expected'],
        'results': results,
        'displayed_findings': displayed,
        'projected_findings': [{**f, 'replacement_index': 0} for f in accepted],
        'skipped_findings': skipped,
    }

def merge_results(primary, secondary):
    merged = copy.deepcopy(primary)
    accepted = [f for r in primary if r['status'] == 'success' for f in r['findings']]
    for r in secondary:
        kept = []
        for f in r['findings']:
            if not any(conflicts(f, prev) for prev in accepted):
                accepted.append(f)
                kept.append(f)
        merged.append({**r, 'findings': kept})
    return merged

def summarize(rows, languages=True):
    result = {'case_count': len(rows), 'error_count': sum(c['kind'] == 'error' for c in rows),
              'clean_count': sum(c['kind'] == 'clean' for c in rows), 'lanes': {}}
    def ids(predicate):
        return [c['id'] for c in rows if predicate(c)]
    def unsupported(o):
        return bool(o['results']) and all(r['status'] == 'unsupported' for r in o['results'])
    def failed(o):
        return any(r['status'] in ('failed', 'unavailable') for r in o['results'])
    for lane in LANES:
        def get(c):
            return c['outcomes'][lane]
        predicates = {
            'completed': lambda c: get(c)['complete'],
            'completed_error': lambda c: c['kind'] == 'error' and get(c)['complete'],
            'completed_clean': lambda c: c['kind'] == 'clean' and get(c)['complete'],
            'exact_error': lambda c: c['kind'] == 'error' and get(c)['exact_expected'],
            'changed_nonexact_error': lambda c: c['kind'] == 'error' and get(c)['changed'] and not get(c)['exact_expected'],
            'changed_clean': lambda c: c['kind'] == 'clean' and get(c)['changed'],
            'flagged_clean': lambda c: c['kind'] == 'clean' and get(c)['flagged'],
            'unchanged_clean': lambda c: c['kind'] == 'clean' and get(c)['complete'] and not get(c)['changed'],
            'unflagged_clean': lambda c: c['kind'] == 'clean' and get(c)['clean_report'],
            'unsupported_only': lambda c: unsupported(get(c)),
            'incomplete': lambda c: not get(c)['complete'],
            'operational_failure': lambda c: failed(get(c)),
        }
        metrics = {k + '_ids': ids(fn) for k, fn in predicates.items()}
        metrics.update({k + '_count': len(metrics[k + '_ids']) for k in predicates})
        result['lanes'][lane] = metrics
    def comparable(c):
        return all(c['outcomes'][lane]['complete'] for lane in ('deterministic', 'model_only', 'combined'))
    def det(c, key): return c['outcomes']['deterministic'][key]
    def comb(c, key): return c['outcomes']['combined'][key]
    def model(c, key): return c['outcomes']['model_only'][key]
    predicates = {
        'comparable': comparable,
        'not_comparable': lambda c: not comparable(c),
        'added_exact_error': lambda c: comparable(c) and c['kind'] == 'error' and not det(c, 'exact_expected') and comb(c, 'exact_expected'),
        'lost_exact_error': lambda c: comparable(c) and c['kind'] == 'error' and det(c, 'exact_expected') and not comb(c, 'exact_expected'),
        'model_unique_exact_error': lambda c: comparable(c) and c['kind'] == 'error' and model(c, 'exact_expected') and not det(c, 'exact_expected'),
        'new_changed_clean': lambda c: comparable(c) and c['kind'] == 'clean' and not det(c, 'changed') and comb(c, 'changed'),
        'new_flagged_clean': lambda c: comparable(c) and c['kind'] == 'clean' and not det(c, 'flagged') and comb(c, 'flagged'),
        'model_changed_clean': lambda c: c['kind'] == 'clean' and model(c, 'changed'),
    }
    result['incremental'] = {k + '_ids': ids(fn) for k, fn in predicates.items()}
    result['incremental'].update({key + '_count': sum(len(c[key + 's']) for c in rows)
                                  for key in ('accepted_model_finding', 'suppressed_model_finding')})
    result['operational_passed'] = all(not failed(o) and (o['complete'] or unsupported(o)) for c in rows for o in c['outcomes'].values())
    if languages:
        result['by_language'] = {language: summarize([c for c in rows if c['language'] == language], False)
                                 for language in dict.fromkeys(c['language'] for c in rows)}
    return result

def compact_summary(summary):
    return {
        'case_count': summary['case_count'], 'error_count': summary['error_count'], 'clean_count': summary['clean_count'],
        'lanes': {lane: {k: v for k, v in metrics.items() if k.endswith('_count') or k in (
            'exact_error_ids', 'changed_nonexact_error_ids', 'changed_clean_ids', 'flagged_clean_ids',
            'unsupported_only_ids', 'operational_failure_ids')}
                  for lane, metrics in summary['lanes'].items()},
        'incremental': {k: v for k, v in summary['incremental'].items() if k not in ('comparable_ids', 'not_comparable_ids')},
        'comparable_count': len(summary['incremental']['comparable_ids']),
        'not_comparable_ids': summary['incremental']['not_comparable_ids'],
        'operational_passed': summary['operational_passed'],
    }

build_file = OUT / 'incremental-quality-build.json'
build = json.loads(build_file.read_text())
spec = importlib.util.spec_from_file_location('audited_aot_builder', ROOT / 'tools/proofing/german_model/build_gector_aot.py')
builder = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = builder
spec.loader.exec_module(builder)
actual_sources = builder.source_snapshot(ROOT, target='incremental-quality')
actual_dependencies = builder.dependency_snapshot(ROOT)
actual_sdk = {name: file_pin(path) for name, path in builder.sdk_files(DART).items()}
actual_runtime = {'executable': file_pin(DART.parent / 'dartaotruntime'), 'entrypoint': file_pin(OUT / 'incremental-quality.aot')}
for key in ('completed', 'passed', 'source_stable', 'dependencies_stable', 'sdk_stable'):
    eq(build[key], True, 'build:' + key)
eq(build['target'], 'incremental-quality', 'build:target')
eq(build['source_files'], actual_sources, 'build:actual-source-map')
eq(build['source_files_after'], actual_sources, 'build:actual-source-map-after')
eq(build['dependency_inputs'], actual_dependencies, 'build:actual-dependencies')
eq(build['dependency_inputs_after'], actual_dependencies, 'build:actual-dependencies-after')
eq(build['sdk_inputs'], actual_sdk, 'build:actual-sdk')
eq(build['sdk_inputs_after'], actual_sdk, 'build:actual-sdk-after')
eq(build['runtime'], actual_runtime, 'build:actual-runtime')
eq(build['compiler']['executable'], file_pin(DART), 'build:actual-compiler')
eq(build['source_entrypoint'], file_pin(ROOT / 'tools/proofing/german_model/run_incremental_quality.dart'), 'build:actual-source-entrypoint')
tracked_source_count = 0
revision_paths = set(git('ls-tree', '-r', '--name-only', SOURCE_REVISION).decode().splitlines())
generated_source_inputs = []
for name, digest in actual_sources.items():
    if name in revision_paths:
        eq(sha(git('show', SOURCE_REVISION + ':' + name)), digest, 'source-revision:' + name)
        tracked_source_count += 1
    else:
        generated_source_inputs.append(name)

pack_process = subprocess.run([sys.executable, str(ROOT / 'tools/proofing/german_model/build_native_pack.py'),
                               'verify', '--pack', str(PACK)], capture_output=True, text=True, check=True)
pack = json.loads(pack_process.stdout)
eq(pack['verified'], True, 'pack:verified')
model_dir = Path(pack['model_directory'])
corpus_checks = {}
run_audits = {}
for filename in ('frozen-30-quality.json', 'prospective-76-quality.json'):
    path = OUT / filename
    report = json.loads(path.read_text())
    prefix = filename + ':'
    for key in ('completed', 'operational_passed', 'source_stable', 'status_contract_passed', 'live_native_provider'):
        eq(report[key], True, prefix + key)
    for key, actual in actual_runtime.items():
        eq(report['runtime'][key], actual, prefix + 'runtime-' + key)
    eq(report['runtime']['product_mode'], True, prefix + 'product-mode')
    eq(report['runtime']['native_threads'], 2, prefix + 'native-threads')
    eq(report['runtime']['warmups_per_case'], 0, prefix + 'warmups')
    eq(report['runtime']['checks_per_case'], 1, prefix + 'checks-per-case')
    for key in ('source_files', 'source_files_after'):
        eq({k: v for k, v in report[key].items() if k != 'declared-corpus'}, actual_sources, prefix + key)
    corpus_name = ('tools/proofing/german_model/cases.json' if filename.startswith('frozen') else
                   'tools/proofing/german_model/prospective_cases_20261117.json')
    corpus = ROOT / corpus_name
    corpus_digest = sha(corpus.read_bytes())
    eq(report['cases_sha256'], corpus_digest, prefix + 'actual-corpus-hash')
    eq(report['source_files']['declared-corpus'], corpus_digest, prefix + 'declared-corpus-hash')
    eq(report['source_files_after']['declared-corpus'], corpus_digest, prefix + 'declared-corpus-hash-after')
    eq(report['corpus_file'], corpus.name, prefix + 'corpus-filename')
    if filename.startswith('prospective'):
        freeze = git('show', '60c550b4:' + corpus_name)
        eq(freeze, corpus.read_bytes(), prefix + 'byte-identical-to-60c550b4')
        corpus_checks['prospective_freeze'] = {'revision': '60c550b4', 'sha256': sha(freeze),
                                               'byte_identical': freeze == corpus.read_bytes()}
    normalized = []
    for c in json.loads(corpus.read_text()):
        row = dict(c)
        for optional_key in ('category', 'pair_id'):
            if row.get(optional_key) is None:
                row.pop(optional_key, None)
        row.setdefault('expected', row['input'])
        row.setdefault('locale', 'de-DE')
        row['language'] = row['locale']
        row.setdefault('expected_model_status', 'success' if row['language'] == 'de-DE' else 'unsupported')
        normalized.append(row)
    eq(report['declared_cases'], normalized, prefix + 'normalized-declared-cases')
    eq(len({c['id'] for c in report['cases']}), len(report['cases']), prefix + 'unique-rows')
    eq([c['id'] for c in report['cases']], [c['id'] for c in normalized], prefix + 'complete-ordered-coverage')
    actual_model = file_pin(model_dir / pack['model']['file'])
    eq({k: report['model'][k] for k in ('file', 'bytes', 'sha256')}, actual_model, prefix + 'actual-model')
    for key in ('revision', 'source_model_sha256'):
        eq(report['model'][key], pack['model'][key], prefix + 'model-' + key)
    eq(report['native_library_sha256'], file_pin(Path(pack['library']))['sha256'], prefix + 'actual-native-library')
    eq({name: sha((model_dir / name).read_bytes()) for name in report['bundle_assets']}, report['bundle_assets'], prefix + 'actual-bundle-assets')
    eq(len(report['bundle_assets']), 13, prefix + 'bundle-asset-count')
    recomputed_rows = []
    precedence_rows = []
    for declared, case in zip(normalized, report['cases']):
        label = prefix + case['id']
        eq({key: case[key] for key in declared}, declared, label + ':corpus-row-binding')
        eq(case['start_offset'], 37, label + ':request-offset')
        eq(list(case['outcomes']), LANES, label + ':four-lanes')
        det = case['outcomes']['deterministic']['results']
        model = case['outcomes']['model_only']['results']
        eq([r['provider_id'] for r in det], ['german-spelling', 'german-writing'], label + ':det-provider-order')
        eq([r['provider_id'] for r in model], ['gector-de'], label + ':model-provider')
        eq(case['outcomes']['writing_only']['results'], [det[1]], label + ':same-writing-result')
        merged = merge_results(det, model)
        eq(case['outcomes']['combined']['results'], merged, label + ':deterministic-precedence-merge')
        row = {**case, 'outcomes': {}}
        for lane in LANES:
            results = merged if lane == 'combined' else case['outcomes'][lane]['results']
            row['outcomes'][lane] = projection(case, results, label + ':' + lane)
            eq(row['outcomes'][lane], case['outcomes'][lane], label + ':' + lane + ':projection')
        accepted = [f for r in merged if r['provider_id'] == 'gector-de' for f in r['findings']]
        suppressed = [f for f in row['outcomes']['model_only']['displayed_findings'] if f not in accepted]
        eq(case['accepted_model_findings'], accepted, label + ':accepted-model-findings')
        eq(case['suppressed_model_findings'], suppressed, label + ':suppressed-model-findings')
        row['accepted_model_findings'], row['suppressed_model_findings'] = accepted, suppressed
        expected_statuses = {'german-spelling': 'success', 'german-writing': 'success', 'gector-de': declared['expected_model_status']}
        eq(case['expected_statuses'], expected_statuses, label + ':expected-provider-statuses')
        eq({r['provider_id']: r['status'] for r in det + model}, expected_statuses, label + ':actual-provider-statuses')
        eq(case['status_contract_passed'], True, label + ':status-contract')
        if accepted or suppressed:
            precedence_rows.append({'id': case['id'], 'accepted': len(accepted), 'suppressed': len(suppressed)})
        recomputed_rows.append(row)
    recomputed = summarize(recomputed_rows)
    eq(recomputed, report['summary'], prefix + 'all-summary-fields-independently-recomputed')
    changed_examples = []
    for case in recomputed_rows:
        combined = case['outcomes']['combined']
        if combined['changed'] and not combined['exact_expected']:
            changed_examples.append({'id': case['id'], 'kind': case['kind'], 'language': case['language'],
                                     'input': case['input'], 'expected': case['expected'],
                                     'outputs': {lane: case['outcomes'][lane]['corrected'] for lane in LANES},
                                     'combined_edits': combined['projected_findings'],
                                     'accepted_model': case['accepted_model_findings'],
                                     'suppressed_model': case['suppressed_model_findings']})
    run_audits[filename] = {'receipt': file_pin(path), 'corpus': file_pin(corpus),
                           'case_count': len(recomputed_rows), 'lane_projection_count': 4 * len(recomputed_rows),
                           'de_DE': compact_summary(recomputed['by_language']['de-DE']),
                           'regional_cohorts': {lang: compact_summary(metrics) for lang, metrics in recomputed['by_language'].items() if lang != 'de-DE'},
                           'model_precedence_rows': precedence_rows, 'changed_nonexact_examples': changed_examples}

engine = ROOT / 'packages/quds_office_engine'
lexicon_sets = {}
for group in ('standard', 'common', 'swiss'):
    words = set()
    for path in (engine / 'lib/src/proofing/data').glob('german_' + group + '_*.dart'):
        content = path.read_text().split('<String>[', 1)[1].split('];', 1)[0]
        for chunk in content.split(','):
            encoded = ''.join(re.findall(r"'([A-Za-z0-9+/=]+)'", chunk))
            if encoded:
                words.update(zlib.decompress(base64.b64decode(encoded), -15).decode().splitlines())
    lexicon_sets[group] = words
standard = lexicon_sets['standard'] | lexicon_sets['common']
manifest = json.loads((engine / 'third_party/proofing/manifest.json').read_text())
for key, words in (('standard', standard), ('swiss_additions', lexicon_sets['swiss'])):
    eq(len(words), manifest['data'][key + '_count'], 'lexicon:' + key + '-count')
    eq(sha(('\n'.join(sorted(words)) + '\n').encode()), manifest['data'][key + '_sha256'], 'lexicon:' + key + '-hash')
lexicon_words = ('Hof', 'Hofe', 'Hofs', 'Das', 'das', 'Grüezi', 'Grütze', 'André',
                 'gelest', 'gelesen', 'genest', 'geschreibt', 'geschrieben', 'beschreibt',
                 'gefindet', 'gefunden', 'befindet')
word_evidence = {word: {'standard': word in standard, 'swiss_additions': word in lexicon_sets['swiss']}
                 for word in lexicon_words}

audit = {
    'schema_version': 1, 'kind': 'independent-incremental-quality-artifact-row-audit',
    'timestamp_utc': datetime.now(timezone.utc).isoformat(),
    'passed': not failures, 'checks': check_count, 'failures': failures,
    'scope': 'Read-only artifact hashing, UTF-16 edit reconstruction, merge/status/summary recomputation and source diagnosis. No Dart or native inference executed.',
    'audited_head': git('rev-parse', 'HEAD').decode().strip(),
    'frozen_source_revision': SOURCE_REVISION,
    'source_binding': {'selected_source_count': len(actual_sources), 'tracked_selected_source_count_matching_frozen_revision': tracked_source_count,
                       'generated_source_inputs_bound_by_actual_file_hash': generated_source_inputs,
                       'run_declared_corpus_excluded_for_build_map_comparison': True,
                       'build_receipt': file_pin(build_file), 'build_and_both_run_maps_match_actual': not any('source' in f for f in failures)},
    'actual_runtime': actual_runtime,
    'dependency_binding': {'package_count': len(actual_dependencies['packages']),
                           'dart_file_count': sum(p['dart_file_count'] for p in actual_dependencies['packages'].values()),
                           'before_after_and_actual_match': not any('dependencies' in f for f in failures)},
    'sdk_binding': {'pin_count': len(actual_sdk), 'before_after_and_actual_match': not any('sdk' in f for f in failures)},
    'pack_binding': {'verified': pack['verified'], 'manifest_sha256': pack['manifest_sha256'], 'sizes': pack['sizes'],
                     'model_sha256': pack['model']['sha256'], 'native_library_sha256': pack['library_sha256']},
    'corpus_binding': corpus_checks,
    'runs': run_audits,
    'lexicon_diagnosis': {'decoded_counts': {group: len(words) for group, words in lexicon_sets.items()},
                         'membership': word_evidence,
                         'provider_source': 'packages/quds_office_engine/lib/src/proofing/german_spelling.dart',
                         'generator_source': 'packages/quds_office_engine/tool/proofing/generate_german_lexicon.py'},
    'interpretation': [
        'Prospective de-DE exact corrections: writing 14/32, deterministic 14/32, model 12/32, combined 19/32; five added exact fixes, zero lost exact fixes, zero additional changed or flagged clean cases.',
        'The model relative-subject dass-to-das edit is accepted, not suppressed. A disjoint spelling Hof-to-Hofe proposal makes its combined output nonexact.',
        'Hofe is a grammatical dative alternative; flagging the already valid Hof as an unknown word remains a detection false positive and an unnecessary clean-input change. Exact-match scoring deliberately does not award this alternative.',
        'Frozen quoted Das is incorrectly flagged by spelling: _isSentenceInitial only treats . ! ? and newline as boundaries, then reaches the preceding word across the colon and opening quote; titlecase fallback is therefore disabled.',
        'The frozen de-CH clean-swiss-name row changes the greeting Gruezi (Grüezi) to Grütze; the proper name André is unchanged. This regional control is excluded from de-DE quality counts, and the model reports unsupported.',
        'Other changed-nonexact rows reveal spelling candidate ordering that is not syntactically aware (gelest/genest, geschreibt/beschreibt, gefindet/befindet) and a writing-rule adjective change that retains the wrong accusative article.',
        'The quality runs use one native request per input with no warmup and default single-sequence decoding. Their timings are diagnostic, not a latency benchmark.',
        'Both panels are authored synthetic examples. The 76-case corpus was frozen before these measured outputs, but is now an observed regression panel; no representative accuracy or training-disjointness claim follows.'
    ],
    'audit_script': file_pin(Path(__file__)),
}
RESULT.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'passed': audit['passed'], 'checks': check_count, 'failures': failures,
                  'output': str(RESULT), 'sha256': sha(RESULT.read_bytes()),
                  'de_DE_exact': {name: {lane: run['de_DE']['lanes'][lane]['exact_error_count'] for lane in LANES}
                                  for name, run in run_audits.items()},
                  'lexicon_membership': word_evidence}, ensure_ascii=False))
raise SystemExit(0 if not failures else 1)

#!/usr/bin/env python3
"""Read-only audit of retained qualification data; does not run inference."""
from pathlib import Path
from urllib.parse import urljoin, urlparse, unquote
from datetime import datetime, timezone
import hashlib
import gzip
import json
import math
import os
import re
import statistics
import subprocess
import unicodedata

ROOT = Path('/home/agent/.codex/skills/remote-skills/.quds-gector-work/worktrees/quds_office_suite')
WORK = ROOT.parent.parent
OUT = Path('/workspace/scratch/c4115a2a85e2/segmentation-validation')
SDK = WORK / 'runtime/flutter-sdk/bin/cache/dart-sdk'
PACK = WORK / 'assets/native-development-pack-v1'
DOCS = ROOT / 'docs/validation/german-gector/2026-11-17-long-input'
IMPLEMENTATION = 'd092d50a844b5cfcc31bb6c39220704b4ff11cf5'
checks = []

def digest(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def pin(path):
    p = Path(path)
    return {'file': p.name, 'bytes': p.stat().st_size, 'sha256': digest(p)}

def load(path):
    return json.loads(Path(path).read_text())

def check(name, passed, detail=None):
    row = {'check': name, 'passed': bool(passed)}
    if detail is not None:
        row['detail'] = detail
    checks.append(row)

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def tree_files(path, ancestors=frozenset()):
    resolved = path.resolve()
    if resolved in ancestors:
        return
    for p in path.iterdir():
        if p.is_dir():
            yield from tree_files(p, ancestors | {resolved})
        elif p.is_file() and p.name.endswith('.dart'):
            yield p

build_path = OUT / 'guarded-provider-v3-build.json'
build = load(build_path)
runs = {m: load(OUT / f'provider-{m}-v3.json') for m in ['single', 'segmented']}
previous_path = ROOT / 'docs/validation/german-gector/2026-11-17-continuation/provider-aot-v3.json'
previous = load(previous_path)
historical_path = ROOT / 'docs/validation/german-gector/2026-11-17-native-dart/provider-aot-v1.json'
historical = load(historical_path)
cases_path = ROOT / 'tools/proofing/german_model/cases.json'
frozen_cases = load(cases_path)
reference_path = WORK / 'assets/reference-f32/reference.json'
reference = load(reference_path)
pack = load(PACK / 'pack.json')
model_dir = PACK / pack['model']['directory']
native_path = PACK / pack['native']['path']
head = git('rev-parse', 'HEAD').decode().strip()
changes = git('diff', '--name-only', f'{IMPLEMENTATION}..{head}').decode().splitlines()
check('HEAD differs from implementation only in validation documentation',
      all(p.startswith('docs/validation/german-gector/') for p in changes), changes)
check('build completed successfully', all(build[k] is True for k in
      ['completed', 'passed', 'source_stable', 'dependencies_stable', 'sdk_stable'])
      and build['stage'] == 'complete' and build['compile']['returncode'] == 0)
check('build source maps stable', build['source_files'] == build['source_files_after'])
check('build dependency maps stable', build['dependency_inputs'] == build['dependency_inputs_after'])
check('build SDK maps stable', build['sdk_inputs'] == build['sdk_inputs_after'])
fixed = {
    'pubspec.yaml', 'pubspec.lock', 'packages/quds_proofing_gector/pubspec.yaml',
    'packages/quds_office_engine/lib/src/proofing/german_spelling.dart',
    'packages/quds_office_engine/lib/src/proofing/office_proofing.dart',
    'packages/quds_office_engine/lib/src/proofing/proofing_text_ranges.dart',
    'tools/proofing/german_model/run_gector_dart.dart',
    'tools/proofing/german_model/cases.json', 'tools/proofing/german_model/artifacts.json',
}
for directory in ['packages/quds_proofing_gector/lib',
                  'packages/quds_office_engine/lib/src/proofing/data',
                  'packages/quds_office_engine/lib/src/opc/zip']:
    fixed.update(p.relative_to(ROOT).as_posix() for p in tree_files(ROOT / directory))
actual_sources = {p: digest(ROOT / p) for p in sorted(fixed)}
source_errors = [p for p in sorted(set(actual_sources) | set(build['source_files']))
                 if actual_sources.get(p) != build['source_files'].get(p)]
check('all expected source files and actual hashes equal build source map', not source_errors,
      {'file_count': len(actual_sources), 'mismatches': source_errors})
git_source_errors = []
resolved_source_files = []
for p, sha in actual_sources.items():
    tracked = subprocess.run(['git','cat-file','-e',f'{IMPLEMENTATION}:{p}'],cwd=ROOT,
                             stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode == 0
    if tracked:
        committed = hashlib.sha256(git('show', f'{IMPLEMENTATION}:{p}')).hexdigest()
        if committed != sha:
            git_source_errors.append(p)
    elif p == 'pubspec.lock':
        preserved = gzip.decompress((DOCS/'resolved-pubspec.lock.gz').read_bytes())
        if hashlib.sha256(preserved).hexdigest() != sha:
            git_source_errors.append(p)
        resolved_source_files.append(p)
    else:
        git_source_errors.append(p)
check('source-map files equal implementation or preserved resolved lock', not git_source_errors,
      {'mismatches':git_source_errors,'untracked_resolved_inputs':resolved_source_files})
check('source entrypoint pin equals actual', build['source_entrypoint'] ==
      pin(ROOT / 'tools/proofing/german_model/run_gector_dart.dart'))
sdk_paths = {k: SDK / ({'dart': 'bin/dart', 'dartaotruntime': 'bin/dartaotruntime',
                       'gen_snapshot': 'bin/utils/gen_snapshot'}.get(k, k))
             for k in build['sdk_inputs']}
actual_sdk = {k: pin(p) for k, p in sdk_paths.items()}
check('all SDK inputs match actual files', actual_sdk == build['sdk_inputs'],
      {'count': len(actual_sdk), 'mismatches': [k for k in actual_sdk
       if actual_sdk[k] != build['sdk_inputs'][k]]})
check('compiler pin matches actual Dart executable', build['compiler']['executable'] == actual_sdk['dart'])
actual_runtime = {'executable': pin(SDK / 'bin/dartaotruntime'),
                  'entrypoint': pin(OUT / 'guarded-provider-v3.aot')}
check('compiled AOT and runtime pins match actual', build['runtime'] == actual_runtime, actual_runtime)
cfg_path = ROOT / '.dart_tool/package_config.json'
cfg = load(cfg_path)
actual_dependencies = {}
dependency_locations = {}
for pkg in cfg['packages']:
    root_uri = urljoin(cfg_path.as_uri(), pkg['rootUri'])
    lib_uri = urljoin(root_uri.rstrip('/') + '/', pkg.get('packageUri', ''))
    parsed = urlparse(lib_uri)
    if parsed.scheme != 'file' or parsed.netloc not in ('', 'localhost'):
        raise ValueError('Unexpected non-file dependency location')
    directory = Path(unquote(parsed.path))
    files = {p.relative_to(directory).as_posix(): digest(p) for p in tree_files(directory)} if directory.is_dir() else {}
    sha = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    actual_dependencies[pkg['name']] = {'library_directory_present': directory.is_dir(),
                                       'dart_file_count': len(files), 'sha256': sha}
    dependency_locations[pkg['name']] = str(directory)
dependency_snapshot = {'package_config': pin(cfg_path), 'packages': dict(sorted(actual_dependencies.items()))}
check('all resolved package library hashes equal build dependency map',
      dependency_snapshot == build['dependency_inputs'],
      {'package_count': len(actual_dependencies),
       'dart_file_count': sum(p['dart_file_count'] for p in actual_dependencies.values()),
       'mismatches': [k for k in set(actual_dependencies) | set(build['dependency_inputs']['packages'])
                      if actual_dependencies.get(k) != build['dependency_inputs']['packages'].get(k)],
       'package_config_matches': dependency_snapshot['package_config'] == build['dependency_inputs']['package_config']})
check('preserved provider-build receipt is exact', digest(DOCS / 'provider-build.json') == digest(build_path))
pack_errors = []
for entry in pack['files']:
    f = PACK / entry['path']
    if f.is_symlink() or not f.is_file() or f.stat().st_size != entry['bytes'] or digest(f) != entry['sha256']:
        pack_errors.append(entry['path'])
actual_pack_files = {p.relative_to(PACK).as_posix() for p in PACK.rglob('*') if p.is_file()}
expected_pack_files = {'pack.json', *(e['path'] for e in pack['files'])}
check('all native development pack payload files match manifest', not pack_errors,
      {'payload_count': len(pack['files']), 'mismatches': pack_errors})
check('pack contains exactly manifest and declared payload', actual_pack_files == expected_pack_files)
pack_sizes = {'file_count': len(actual_pack_files), 'manifest_bytes': (PACK/'pack.json').stat().st_size,
              'payload_bytes': sum((PACK/e['path']).stat().st_size for e in pack['files'])}
pack_sizes['total_bytes'] = pack_sizes['manifest_bytes'] + pack_sizes['payload_bytes']
check('pack size accounting matches actual', pack_sizes == pack['sizes'], pack_sizes)
pack_verification = load(OUT / 'final-pack-verification.json')
check('saved pack verification refers to actual manifest and library',
      pack_verification['verified'] is True and pack_verification['manifest_sha256'] == digest(PACK/'pack.json')
      and pack_verification['library_sha256'] == digest(native_path)
      and pack_verification['model'] == pack['model'] and pack_verification['sizes'] == pack_sizes)
native_dependencies = []
ldd_text = subprocess.check_output(['ldd', str(native_path)], text=True)
for entry in pack['native']['system_dependencies']:
    match = re.search(r'(?:^|\n)\s*' + re.escape(entry['soname']) + r'\s+=>\s+(\S+)', ldd_text)
    if match:
        path = Path(match.group(1))
    else:
        match = re.search(r'(?:^|\n)\s*(/\S*/' + re.escape(entry['soname']) + r')\s', ldd_text)
        path = Path(match.group(1)) if match else None
    native_dependencies.append({'soname': entry['soname'], 'actual_path': str(path) if path else None,
                                'matches': path is not None and digest(path) == entry['sha256']})
check('actual dynamic system dependencies match pack recorded pins',
      all(e['matches'] for e in native_dependencies), native_dependencies)

# Independent scalar-based WordPiece counting for the retained inputs. All
# examined source characters are ordinary German, ASCII controls, and emoji;
# no Unicode-version-dependent exotic categories are needed for this panel.
tokenizer_json = load(model_dir / 'tokenizer.json')
vocabulary = tokenizer_json['model']['vocab']
rules = load(model_dir / 'language-rules.json')
strip = rules.get('stripTerminators', '.!?') if rules['stripTrailingTerminator'] else ''
glued = set((rules.get('elision') or rules).get('nonElidingArticles', []))
word_pattern = re.compile(r"\w+(?:'\w+)?|[^\w\s]")
special_pattern = re.compile(r'\[(?:PAD|UNK|CLS|SEP|MASK)\]')
specials = {'[PAD]', '[UNK]', '[CLS]', '[SEP]', '[MASK]'}

def is_chinese(c):
    cp = ord(c)
    return any(a <= cp <= b for a, b in [(0x4e00,0x9fff),(0x3400,0x4dbf),(0xf900,0xfaff),
        (0x20000,0x2a6df),(0x2a700,0x2b73f),(0x2b740,0x2b81f),(0x2b820,0x2ceaf),(0x2f800,0x2fa1f)])

def preordinary(s):
    normalized = []
    for c in s:
        if ord(c) in (0,0xfffd) or (unicodedata.category(c).startswith('C') and c not in '\t\n\r'):
            continue
        normalized.append(' ' if c.isspace() else f' {c} ' if is_chinese(c) else c)
    tokens = []
    current = ''
    for c in ''.join(normalized):
        cp = ord(c)
        punct = 33<=cp<=47 or 58<=cp<=64 or 91<=cp<=96 or 123<=cp<=126 or unicodedata.category(c).startswith('P')
        if c == ' ' or punct:
            if current: tokens.append(current)
            current = ''
            if punct: tokens.append(c)
        else: current += c
    if current: tokens.append(current)
    return tokens

def pretokenize(s):
    result = []
    cursor = 0
    for match in special_pattern.finditer(s):
        result.extend(preordinary(s[cursor:match.start()]))
        result.append(match.group())
        cursor = match.end()
    result.extend(preordinary(s[cursor:]))
    return result

def pieces(token):
    if token in specials: return 1
    if len(token) > 100: return 1
    count = 0
    start = 0
    while start < len(token):
        for end in range(len(token), start, -1):
            if ('' if start == 0 else '##') + token[start:end] in vocabulary:
                count += 1
                start = end
                break
        else: return 1
    return count

def token_count(text):
    trimmed = text.rstrip()
    core = trimmed[:-1] if trimmed and trimmed[-1] in strip else text
    words = word_pattern.findall(core.replace('’', "'"))
    split = []
    for word in words:
        if "'" in word and word.split("'",1)[0].lower() in glued:
            split.extend(word.split("'",1))
        else: split.append(word)
    return 2 + sum(pieces(t) for word in split for t in pretokenize(word))

def utf16(s):
    return s.encode('utf-16-le')

def source_slice(s,a,b):
    return utf16(s)[a*2:b*2].decode('utf-16-le')

def stats(samples):
    return {'median_ms': statistics.median(samples),
            'p95_ms': sorted(samples)[math.ceil(len(samples)*.95)-1],
            'maximum_ms': max(samples)}

def validate_outcome(row, label):
    raw = utf16(row['input'])
    replacement = raw
    bound = len(raw)//2
    valid = True
    prev_end = -1
    for f in row['findings']:
        a,b = f['start']-row['start_offset'],f['end']-row['start_offset']
        valid &= 0 <= a <= b <= bound and a >= prev_end
        try: valid &= source_slice(row['input'],a,b) == f['original']
        except UnicodeDecodeError: valid = False
        prev_end = b
    for f in reversed(row['findings']):
        a,b = f['start']-row['start_offset'],f['end']-row['start_offset']
        replacement = replacement[:a*2] + utf16(f['replacement']) + replacement[b*2:]
    valid &= replacement == utf16(row['corrected'])
    if row['status'] != 'success':
        valid &= not row['findings'] and row['corrected'] == row['input']
    check(label+' valid UTF-16 source-bound findings and corrected reconstruction',valid)

case_lookup = {c['id']: c for c in frozen_cases}
outcome_fields = ['id','input','language','start_offset','status','message','corrected','findings']
run_summaries = {}
for mode, run in runs.items():
    prefix = mode + ': '
    check(prefix+'source maps match actual build inputs',run['source_files']==actual_sources and run['source_stable'] is True)
    check(prefix+'runtime pins match actual built program',all(run['runtime'][k]==v for k,v in actual_runtime.items()))
    check(prefix+'product runtime and repeats',run['runtime']['product_mode'] is True and
          run['runtime']['native_threads']==2 and run['runtime']['warmups_per_input']==1 and run['runtime']['repeats_per_input']==3)
    check(prefix+'reference and frozen corpus hashes',run['reference_sha256']==digest(reference_path)
          and run['cases_sha256']==digest(cases_path))
    check(prefix+'native and model pins match actual',run['native_library_sha256']==digest(native_path)
          and run['model']['sha256']==digest(model_dir/pack['model']['file'])
          and run['model']['bytes']==pack['model']['size_bytes']
          and run['model']['source_model_sha256']==pack['model']['source_model_sha256']
          and run['model']['revision']==pack['model']['revision'])
    asset_errors=[name for name,sha in run['bundle_assets'].items() if digest(model_dir/name)!=sha]
    expected_assets={e['file'] for e in load(ROOT/'tools/proofing/german_model/artifacts.json') if e['file']!='model.onnx'} | {pack['model']['file']}
    check(prefix+'all runtime bundle assets match actual',not asset_errors,{'count':len(run['bundle_assets']),'mismatches':asset_errors})
    check(prefix+'runtime bundle asset set is complete',set(run['bundle_assets'])==expected_assets)
    check(prefix+'complete requested checks passed',all(run[k] is True for k in ['completed','operational_passed','all_requested_checks_passed']))
    differences=[]
    for section in ['cases','controls','long_complete_check_probes']:
        base={c['id']:c for c in previous[section]}
        current={c['id']:c for c in run[section]}
        check(prefix+section+' retains all prior IDs',set(base)==set(current))
        for ident,row in current.items():
            changed=[k for k in outcome_fields if row.get(k)!=base[ident].get(k)]
            if changed:differences.append({'section':section,'id':ident,'fields':changed})
    check(prefix+'all frozen outcomes match prior continuation',not differences,differences)
    all_rows=[]
    for section in ['cases','controls','long_complete_check_probes','segmented_long_complete_check_probes','segmentation_controls']:
        for row in run.get(section,[]):
            all_rows.append((section,row))
            label=prefix+section+'/'+row['id']
            validate_outcome(row,label)
            if 'initial_segments' in row:
                segments=row['initial_segments']
                cursor=0
                total=0
                actual=[]
                valid=True
                for segment in segments:
                    a,b=segment['start'],segment['end']
                    valid &= a==cursor and b>=a
                    piece=source_slice(row['input'],a,b)
                    count=token_count(piece)
                    valid &= count==segment['tokens'] and count<=512
                    actual.append({'start':a,'end':b,'tokens':count})
                    total+=count
                    cursor=b
                units=len(utf16(row['input']))//2
                logical=token_count(row['input'])
                valid &= cursor==units==row['source_code_units'] and row['source_coverage_complete'] is True
                valid &= len(segments)==row['initial_segment_count'] and total==row['initial_model_tokens_total']
                valid &= logical==row['tokens_first_pass']
                if mode=='segmented':valid &= len(segments)<=32 and total<=4096 and units<=32768
                check(label+' independently counted tokens and exact UTF-16 partition',valid,
                      {'logical_tokens':logical,'initial_model_tokens':total,'segments':len(segments),'source_code_units':units})
                if len(segments)>1:
                    boundaries=[s['end'] for s in segments[:-1]]
                    valid=all(source_slice(row['input'],0,b).rstrip().endswith(('.', '!', '?')) for b in boundaries)
                    # Retained long controls contain paired single backticks;
                    # no recorded boundary may enter that protected range.
                    for boundary in boundaries:
                        valid &= source_slice(row['input'],0,boundary).count('`')%2==0
                    for finding in row['findings']:
                        a,b=finding['start']-row['start_offset'],finding['end']-row['start_offset']
                        valid &= sum(s['start']<=a<=b<=s['end'] for s in segments)==1
                    check(label+' boundaries preserve sentences/protected code and own each edit once',valid)
            if 'timing' in row:
                samples=row['timing']['samples_ms']
                valid=len(samples)==3 and all(isinstance(x,(int,float)) and math.isfinite(x) and x>=0 for x in samples)
                valid &= stats(samples)=={k:row['timing'][k] for k in ['median_ms','p95_ms','maximum_ms']}
                valid &= row['elapsed_ms']==samples[0]
                check(label+' timing recomputation',valid)
                warm=row['warmup']
                validate_outcome(warm,label+' warmup')
                check(label+' retained warmup outcome matches first timed outcome',all(warm[k]==row[k] for k in outcome_fields if k!='id')
                      and row['stable_repeats'] is True)
    frozen_valid=len(run['cases'])==30
    for row in run['cases']:
        case=case_lookup[row['id']]
        expected=case.get('expected',case['input'])
        locale=case.get('locale','de-DE')
        frozen_valid &= row['input']==case['input'] and row['kind']==case['kind'] and row['language']==locale
        frozen_valid &= row['expected']==expected and row['matches_expected']==(row['corrected']==expected)
        frozen_valid &= row['status']==('success' if locale=='de-DE' else 'unsupported')
    check(prefix+'all cases agree with immutable corpus and explicit locale policy',frozen_valid)
    short=[v for row in run['cases'] if row['status']=='success' and row['tokens_first_pass']<=64 for v in row['timing']['samples_ms']]
    short.extend(next(r for r in run['long_complete_check_probes'] if r['token_budget']==64)['timing']['samples_ms'])
    short_stats=stats(short)
    check(prefix+'short-input aggregation recomputes exactly',run['warm_checks_up_to_64_wordpieces']=={'samples_ms':short,**short_stats},
          {'count':len(short),**short_stats})
    budget=run['engineering_budgets']
    check(prefix+'engineering flags match their actual scope',
          budget['p95_at_most_500_ms']==(short_stats['p95_ms']<=500)
          and budget['peak_rss_at_most_768_mib']==(run['peak_process_rss_bytes']<=768*1024*1024)
          and budget['gguf_at_most_160_mib']==(run['model']['bytes']<=160*1024*1024))
    errors=[r for r in run['cases'] if r['kind']=='error' and r['language']=='de-DE']
    clean=[r for r in run['cases'] if r['kind']=='clean' and r['language']=='de-DE']
    run_summaries[mode]={'cases':len(run['cases']),'error_cases':len(errors),
       'exact_error_corrections':[r['id'] for r in errors if r['corrected']==r['expected']],
       'supported_clean':len(clean),'unchanged_clean':sum(r['corrected']==r['input'] for r in clean),
       'unsupported':sum(r['status']=='unsupported' for r in run['cases']),
       'operational_controls':len(run['controls']),'control_passes':sum(r['passed'] is True for r in run['controls']),
       'short_timing':short_stats,'short_samples':len(short),'setup_ms':run['setup_ms'],
       'peak_process_rss_bytes':run['peak_process_rss_bytes'],'peak_process_rss_mib':run['peak_process_rss_bytes']/2**20,
       'structural_probes':[{k:r[k] for k in ['id','tokens_first_pass','initial_model_tokens_total','initial_segment_count','source_code_units','timing']}
           for r in run['long_complete_check_probes']+run.get('segmented_long_complete_check_probes',[])]}
    comp=load(OUT/f'provider-{mode}-v3-comparison.json')
    check(prefix+'strict comparison is passed and candidate hash matches',comp['candidate_sha256']==digest(OUT/f'provider-{mode}-v3.json')
          and all(comp[k] is True for k in ['evidence_valid','operational_passed','guarded_nonregression_passed','passed'])
          and not comp['evidence_errors'] and all(comp['gates'].values()))
    check(prefix+'strict comparison hashes actual historical baseline and corpus',
          comp['frozen_baseline_sha256']==comp['baseline_sha256']==digest(historical_path)
          and comp['cases_sha256']==digest(cases_path))
    old_exact={r['id'] for r in historical['cases'] if r['kind']=='error' and r['status']=='success' and r['corrected']==r['expected']}
    new_exact=set(run_summaries[mode]['exact_error_corrections'])
    check(prefix+'historical correction improvement recomputes',len(old_exact)==5 and len(new_exact)==6
          and new_exact-old_exact==set(comp['added_exact_fixes'])=={'verb-wir'} and old_exact<=new_exact
          and not comp['lost_exact_fixes'])

seg=runs['segmented']
seg_controls={r['id']:r for r in seg['segmentation_controls']}
expected_ids={'segmented-late-correction-utf16-offset','segmented-protected-code',
 'segmented-late-capacity-fails-whole-request','segmented-total-token-cap-fails-whole-request',
 'segmented-segment-cap-fails-whole-request','segmented-text-cap-fails-whole-request'}
check('all six named segmentation controls are present',set(seg_controls)==expected_ids and seg['segmentation_operational_passed'] is True)
control_details=[]
for ident,row in seg_controls.items():
    valid=row['passed'] is True and row['status']==row['expected_status'] and row['corrected']==row['expected']
    valid &= row['findings']==row.get('expected_findings',row['findings'])
    if row['status']=='success':
        valid &= row['planning_admitted'] is True and row['source_coverage_complete'] is True
    else:
        valid &= row['planning_admitted'] is False and row['planning_rejection'] in row['message']
        valid &= not row['findings'] and row['corrected']==row['input']
        valid &= all(k not in row for k in ['source_coverage_complete','initial_segments','initial_segment_count'])
    check(ident+' status, expectation, atomic publication and admission evidence',valid)
    control_details.append({k:row[k] for k in ['id','status','passed','planning_admitted','planning_rejection','findings'] if k in row})
late=seg_controls['segmented-late-correction-utf16-offset']
local=len(utf16(late['input'].rsplit('geht',1)[0]))//2
check('late correction has independently calculated absolute UTF-16 coordinates',
      late['findings']==[{'start':137+local,'end':137+local+4,'original':'geht','replacement':'gehst','rule_id':'gector.de.grammar'}]
      and local>512 and late['input'].startswith('😀 '), {'start':137+local,'end':137+local+4,'local_utf16':local})
failed_capacity=seg_controls['segmented-late-capacity-fails-whole-request']
check('late oversized sentence independently exceeds hard sequence cap',token_count(failed_capacity['input'].split('. ',1)[1])==602)
total_control=seg_controls['segmented-total-token-cap-fails-whole-request']
sentences=total_control['input'].split('. ')
sentence_tokens=[token_count(s if s.endswith('.') else s+'.') for s in sentences]
check('total-token control fits individual sequences but exceeds aggregate cap',
      max(sentence_tokens)<=512 and sum(sentence_tokens)>4096,
      {'sentences':len(sentence_tokens),'tokens_each':sorted(set(sentence_tokens)),'sum':sum(sentence_tokens)})
segment_control=seg_controls['segmented-segment-cap-fails-whole-request']
check('segment-cap control requires 33 target-sized groups within other initial bounds',
      segment_control['input'].count('Das Haus ist schön.')==396 and len(utf16(segment_control['input']))//2<32768
      and 33*61<=4096, {'sentences':segment_control['input'].count('Das Haus ist schön.'),'groups_at_12_sentences':33,'initial_tokens':2013})
text_control=seg_controls['segmented-text-cap-fails-whole-request']
check('text-cap control is exactly one UTF-16 unit over limit',len(utf16(text_control['input']))//2==32769)
check('short segmented path preserves single-sequence partitions',all(
    a['input']==b['input'] and a['initial_segments']==b['initial_segments']
    for a,b in zip(runs['single']['cases'],runs['segmented']['cases'])))

receipt_files={p.name:pin(p) for p in [build_path,OUT/'guarded-provider-v3.aot',
    OUT/'provider-single-v3.json',OUT/'provider-segmented-v3.json',
    OUT/'provider-single-v3-comparison.json',OUT/'provider-segmented-v3-comparison.json',
    previous_path,historical_path,reference_path,PACK/'pack.json']}
peer_path=Path('/workspace/scratch/c4115a2a85e2/incoming-audit/final-regression-ancestry-audit.json')
peer=load(peer_path)
check('independent regression/ancestry audit reports no discrepancy',
      peer['all_checks_passed'] is True and peer['source_commit']==IMPLEMENTATION
      and peer['regression_total']==873 and peer['distinct_test_total_including_unchanged_python_tooling']==924)
report={'schema_version':1,'kind':'quds-gector-independent-final-evidence-audit',
 'timestamp_utc':datetime.now(timezone.utc).isoformat(),'implementation_commit':IMPLEMENTATION,
 'observed_head':head,'method':'Read actual source, SDK, dependency, native pack and AOT files; independently recompute SHA-256 pins, WordPiece counts, UTF-16 source edits, partitions, statistics and retained outcomes. No inference, compiler, tests or GitHub Actions invoked.',
 'passed':all(c['passed'] for c in checks),'checks_passed':sum(c['passed'] for c in checks),'checks_total':len(checks),
 'failures':[c for c in checks if not c['passed']],'receipt_files':receipt_files,
 'source_file_count':len(actual_sources),'dependency_package_count':len(actual_dependencies),
 'dependency_dart_file_count':sum(p['dart_file_count'] for p in actual_dependencies.values()),
 'sdk_file_count':len(actual_sdk),'source_files':actual_sources,'run_summaries':run_summaries,
 'regression_ancestry_audit':{'path':str(peer_path),**pin(peer_path),
     'auditor':'/root/incoming_audit','source_map_files':peer['source_map']['file_count'],
     'final_regressions':peer['regression_total'],'distinct_tests_including_preserved_tooling':peer['distinct_test_total_including_unchanged_python_tooling'],
     'captured_branches':peer['ancestry']['branch_count'],'captured_pr_heads':peer['ancestry']['pr_head_count'],
     'all_checks_passed':peer['all_checks_passed']},
 'segmentation_controls':control_details,'checks':checks,
 'limits':[
  'All frozen outcomes are compared with the previous continuation 6/18 result; strict historical comparison files use an older 5/18 baseline.',
  'The second and third timed outcomes are not stored individually. Their durations are retained, but exact repeated outcome stability is producer-reported; the warmup and first timed outcomes are independently checked.',
  'Three samples per structural probe make nearest-rank p95 the maximum sample. These are local engineering observations, not target-device or representative quality qualification.',
  'The 500 ms flag applies only to the declared <=64 logical-token short aggregate. The 256-token and extended 636/1276-token segmented probes do not meet that budget; no long-text speedup is established.',
  'Saved initial_segments are an independently generated preflight plan, not a native execution trace. Complete success/atomic-result behavior is supported by source review, native controls and separately retained tests.',
  '64 tokens is a soft grouping target. Intact unsplittable sentences may reach the hard 512-token sequence limit; limits are 32 segments, 4096 initial tokens, 32768 UTF-16 units, 5 passes per segment and 20480 total forwarded tokens.',
  'Cancellation is checked between native calls; a running native FFI forward is not interruptible. Full native forward token counts and per-segment latency samples are not emitted by this runner.',
  'Regression counts and captured ancestry are audited separately by incoming_audit and are not implied by the native receipt itself.',
 ]}
destination=OUT/'independent-final-evidence-audit.json'
destination.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'output':str(destination),'passed':report['passed'],'checks_passed':report['checks_passed'],
                  'checks_total':report['checks_total'],'failures':report['failures'],
                  'source_files':len(actual_sources),'packages':len(actual_dependencies),
                  'dependency_dart_files':report['dependency_dart_file_count'],'sdk_files':len(actual_sdk),
                  'summaries':run_summaries},ensure_ascii=False,indent=2))

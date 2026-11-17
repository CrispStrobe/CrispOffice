#!/usr/bin/env python3
"""Independent, read-only evidence audit; never executes product tests or consumers.

Reconstructs outcomes from raw JSON events and measurements from saved artifacts.
Does not import either qualification or consumer runner implementation.
"""
from __future__ import annotations
import collections
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import urllib.parse
import zipfile
from lxml import etree as E
from PIL import Image

BASE = Path('/workspace/scratch/f911bf3b5689')
REPO = BASE / 'quds_office_suite'
QUAL = BASE / 'runtime-recovery/qualification-966196f3'
CONS = BASE / 'runtime-recovery/consumer-recovery/final-966196f3'
OUT = BASE / 'runtime-recovery/final-review'
FROZEN = '966196f386ec1776c836664b3eb7c93e8e92605c'
TREE = '4287330a433e915d58ca779adfacb75942c6ab04'
PACKAGES = {'engine': 'quds_office_engine', 'editor': 'quds_office_editor',
            'harper': 'quds_proofing_harper', 'gector': 'quds_proofing_gector'}
REPORT = {'source_commit': FROZEN, 'source_tree': TREE, 'checks': 0, 'failures': [],
          'pending': [], 'scope': 'Read-only independent reconstruction of saved evidence; no product test or office conversion reruns.'}

def check(value, message):
    REPORT['checks'] += 1
    if not value:
        REPORT['failures'].append(message)
    return value

def sha(data):
    return hashlib.sha256(data).hexdigest()

HASH_CACHE = {}
def digest(path, links=False):
    path = Path(path)
    if links and path.is_symlink():
        return sha(os.readlink(path).encode())
    if not path.exists():
        return None
    st = path.stat()
    key = (str(path), st.st_size, st.st_mtime_ns)
    if key not in HASH_CACHE:
        with path.open('rb') as source:
            HASH_CACHE[key] = hashlib.file_digest(source, 'sha256').hexdigest()
    return HASH_CACHE[key]

def read_json(path):
    path = Path(path)
    return json.loads(gzip.decompress(path.read_bytes()) if path.suffix == '.gz' else path.read_bytes())

def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args])

def compare_hashes(values, label, links=False):
    for name, expected in values.items():
        check(digest(name, links) == expected, label + ': current bytes differ: ' + name)
    return len(values)

def normal_path(path, cwd):
    if path.startswith('file:'):
        path = urllib.parse.unquote(urllib.parse.urlsplit(path).path)
    p = Path(path)
    return str((p if p.is_absolute() else Path(cwd) / p).resolve())

def parse_events(raw, cwd, selected, label):
    starts, ends, suites, terminal, errors, lines = {}, {}, {}, [], [], []
    suite_counts = []
    for line in raw.decode().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            if line.strip():
                lines.append(line)
            continue
        kind = event.get('type')
        if kind == 'suite':
            item = event['suite']
            check(item['id'] not in suites, label + ': duplicate suite ID')
            suites[item['id']] = normal_path(item['path'], cwd)
        elif kind == 'testStart':
            item = event['test']
            check(item['id'] not in starts, label + ': duplicate test start')
            starts[item['id']] = item
        elif kind == 'testDone':
            check(event['testID'] not in ends, label + ': duplicate test completion')
            ends[event['testID']] = event
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            terminal.append(event)
        elif kind == 'allSuites':
            suite_counts.append(event['count'])
    check(not errors, label + ': raw error events')
    check(len(terminal) == 1 and terminal[0]['success'] is True, label + ': missing/failed final runner event')
    check(set(starts) == set(ends), label + ': unmatched start/completion IDs')
    check(len(suites) == len(set(suites.values())), label + ': duplicate suite execution')
    check(set(suites.values()) == selected, label + ': raw suite set differs from planned explicit files')
    check(not suite_counts or set(suite_counts) == {len(selected)}, label + ': allSuites count differs')
    cases = []
    for test_id, end in ends.items():
        if end.get('hidden'):
            check(end['result'] == 'success', label + ': hidden load/setup failure')
            continue
        start = starts.get(test_id)
        if not check(start is not None, label + ': case lacks start'):
            continue
        check(start['suiteID'] in suites, label + ': case refers to unknown suite')
        outcome = 'skipped' if end.get('skipped') else end['result']
        cases.append({'test_id': test_id, 'suite_id': start['suiteID'], 'name': start['name'],
                      'resolved_suite_path': suites[start['suiteID']], 'outcome': outcome})
    return cases, {'files': len(suites), 'raw_outcomes': dict(collections.Counter(c['outcome'] for c in cases)),
                   'non_json_lines': len(lines), 'raw_error_events': len(errors), 'terminal_success': len(terminal) == 1 and terminal[0]['success']}

def check_qualification():
    receipt, plan = read_json(QUAL / 'receipt.json'), read_json(QUAL / 'plan.json')
    check(receipt['source_commit'] == FROZEN == plan['source_commit'], 'qualification frozen commit')
    check(receipt['source_tree'] == TREE == git('rev-parse', FROZEN + '^{tree}').decode().strip(), 'qualification frozen tree')
    check(digest(QUAL / 'plan.json') == receipt['plan_sha256'], 'qualification plan hash')
    check(digest(QUAL / 'run-used.py') == receipt['runner_sha256'], 'qualification runner hash')
    historical = REPO / 'docs/validation/office-continuation-20261117/resumption/qualification-preflight-b32dee6f.tar.xz'
    check(digest(historical) == '38b96302069d2ea970d0002a761d114eee7df4776ac540ca550278b6840895ec', 'original qualification archive hash')
    with tarfile.open(historical) as archive:
        original_bytes = archive.extractfile('qualification/run-b32dee6f-1/plan.json').read()
    check(sha(original_bytes) == plan['preserved_prior_coverage']['plan_sha256'], 'original plan byte identity')
    original = json.loads(original_bytes)
    old = {(v['kind'], t) for v in original['cohorts'].values() for t in v['tests']}
    primary = [(v['kind'], t) for v in plan['cohorts'].values() for t in v['tests']]
    check(len(old) == 174 and len(primary) == len(set(primary)) == 180, 'primary suite cardinality/disjointness')
    check(old <= set(primary), 'original 174 suite coverage lost')
    check(set(primary) - old == {tuple(v) for v in plan['preserved_prior_coverage']['added_files']}, 'added six suite identity differs')
    check(digest(REPO / plan['source_manifest']) == plan['source_manifest_sha256'], 'historical manifest hash')
    cohorts = {}
    actual = {}
    expected_commands = set(plan['cohorts']) | set(plan['node_repetitions']) | {
        'engine-strict-analysis', 'editor-strict-analysis', 'harper-strict-analysis', 'gector-strict-analysis', 'format', 'python-controls'}
    commands = {c['name']: c for c in receipt['commands']}
    if receipt['status'] == 'running':
        REPORT['pending'].append('Final qualification receipt and after-identity files are still running.')
    else:
        check(set(commands) == expected_commands and len(commands) == len(receipt['commands']), 'command coverage/duplicates')
    all_specs = {**plan['cohorts'], **plan['node_repetitions']}
    for name, command in commands.items():
        if command['status'] == 'running':
            continue
        check(command['exit_code'] == 0 and not command['timed_out'], name + ': exit/timeout failure')
        streams = {}
        for stream in ('stdout', 'stderr'):
            path = QUAL / command[stream]
            data = gzip.decompress(path.read_bytes())
            check(sha(data) == command[stream + '_sha256'], name + ': raw ' + stream + ' hash')
            check(digest(path) == command[stream + '_gzip_sha256'], name + ': gzip ' + stream + ' hash')
            streams[stream] = data
        if name not in all_specs:
            if name.endswith('-strict-analysis'):
                check('No issues found!' in streams['stdout'].decode(), name + ': missing clean analyzer output')
            if name == 'format':
                check(re.search(r'Formatted \d+ files \(0 changed\)', streams['stdout'].decode()) is not None, 'formatter changed source')
            continue
        spec = all_specs[name]
        selected = {str((REPO / 'packages' / PACKAGES[spec['kind']] / t).resolve()) for t in spec['tests']}
        argv_tests = {v for v in command['command'] if v.startswith('test/') and v.endswith('.dart')}
        check(argv_tests == set(spec['tests']), name + ': command omitted/added planned files')
        cases, counts = parse_events(streams['stdout'], command['cwd'], selected, name)
        summary = read_json(QUAL / name / 'test-summary.json')
        check(collections.Counter(tuple(sorted(v.items())) for v in cases) == collections.Counter(tuple(sorted(v.items())) for v in summary['completed_tests']), name + ': recorded case ledger differs from raw events')
        check(counts['raw_outcomes'] == summary['raw_runner_outcomes'], name + ': raw outcome aggregate differs')
        excluded = [c for c in cases if c['name'] in plan['coverage_exclusions_if_private_pdf_absent'] and c['resolved_suite_path'].endswith('/test/pdf_file_test.dart')]
        expected_exclusions = 2 if name == 'engine-integration' else 0
        check(len(excluded) == expected_exclusions and all(c['outcome'] == 'success' for c in excluded), name + ': private PDF exclusions differ')
        skipped = [c for c in cases if c['outcome'] == 'skipped']
        allowed = [c for c in skipped if name == 'gector-contract' and c['name'] == plan['optional_missing_native_fixture_case'] and c['resolved_suite_path'].endswith('/test/native_backend_test.dart')]
        check(skipped == allowed and len(skipped) == (1 if name == 'gector-contract' else 0), name + ': unexpected/missing native skip')
        check(all(c['outcome'] in ('success', 'skipped') for c in cases), name + ': failure/error result')
        counts.update(raw_success=counts['raw_outcomes'].get('success', 0), substantive_success=counts['raw_outcomes'].get('success', 0) - len(excluded),
                      excluded_success_names=[c['name'] for c in excluded], skipped_names=[c['name'] for c in skipped])
        check(counts['raw_success'] == summary['raw_success_count'] and counts['substantive_success'] == summary['substantive_success_count'], name + ': recorded substantive counts differ')
        cohorts[name], actual[name] = counts, cases
    for name, spec in plan['node_repetitions'].items():
        check(len(spec['tests']) == 14 and spec['new_unique_test_cases_claimed'] == 0, 'Node file/repetition scope')
        if name in actual and spec['repeats'] in actual:
            node_identity = collections.Counter((c['resolved_suite_path'], c['name'], c['outcome']) for c in actual[name])
            files = {c['resolved_suite_path'] for c in actual[name]}
            vm_identity = collections.Counter((c['resolved_suite_path'], c['name'], c['outcome']) for c in actual[spec['repeats']] if c['resolved_suite_path'] in files)
            check(node_identity == vm_identity, 'Node and VM per-case identities/outcomes differ')
            cohorts[name]['matches_vm_case_multiset'] = node_identity == vm_identity
        for source, review in spec['selection_review'].items():
            root = REPO / 'packages' / PACKAGES[spec['kind']]
            check(digest(root / source) == review['source_sha256'], 'Node selection source hash ' + source)
            for helper, expected in review['relative_dart_closure_sha256'].items():
                check(digest(root / helper) == expected, 'Node closure hash ' + helper)
    fixture = read_json(QUAL / 'fixture-audit.json')
    check(not fixture['private_pdf_present'] and not Path('/home/mohammed/Desktop/al_tahreer_profile.pdf').exists(), 'private PDF exclusion absent-input condition')
    check(not any(fixture['optional_native_fixture_environment_present'].values()), 'native skip fixture environment condition')
    for path, record in fixture['guarded_source_files'].items():
        check(digest(REPO / path) == record['sha256'], 'fixture-guard source hash ' + path)
    raw_total = sum(cohorts[k]['raw_success'] for k in plan['cohorts'] if k in cohorts)
    substantive_total = sum(cohorts[k]['substantive_success'] for k in plan['cohorts'] if k in cohorts)
    node_total = sum(cohorts[k]['substantive_success'] for k in plan['node_repetitions'] if k in cohorts)
    REPORT['qualification'] = {'status': receipt['status'], 'unique_primary_files': len(primary), 'original_files_retained': len(old),
        'added_files': sorted(set(primary) - old), 'cohorts': cohorts, 'raw_primary_successes': raw_total,
        'substantive_primary_successes': substantive_total, 'node_successful_repetitions': node_total}
    if receipt['status'] != 'running':
        check(receipt['raw_runner_success_total'] == raw_total, 'receipt raw primary total')
        check(receipt['substantive_success_total'] == substantive_total, 'receipt substantive primary total')
        check(receipt['node_substantive_success_total'] == node_total, 'receipt Node total')
        check(receipt['all_runtime_successful_executions'] == substantive_total + node_total, 'receipt combined executions improperly counts repetitions/exclusions')
        check(receipt['working_head_after'] == FROZEN, 'qualification frozen HEAD changed during execution')
        check(receipt['analysis_config_restored'] and receipt['source_matches_frozen_commit'], 'final restoration/source flags')
        check(receipt['status'] == 'passed' and receipt['all_passed'], 'qualification final receipt failed')
        identities = {}
        for family in ('source', 'dependencies', 'runtime', 'workspace', 'system', 'harness'):
            before, after = read_json(QUAL / (family + '-before.json')), read_json(QUAL / (family + '-after.json'))
            check(before == after, family + ': before/after snapshots differ')
            if family == 'source':
                tracked = {}
                for entry in git('ls-tree', '-rz', FROZEN).split(b'\0'):
                    if not entry:
                        continue
                    attrs, name = entry.split(b'\t', 1)
                    mode, kind, blob = attrs.decode().split()
                    name = name.decode()
                    if not name.startswith('docs/'):
                        tracked[name] = (mode, blob)
                check(set(tracked) == set(before['files']), 'source inventory is not all frozen non-doc paths')
                check(before['count'] == len(tracked) and not before['commit_mismatches'] and not before['untracked_non_evidence_paths'], 'source snapshot count/frozen mismatches')
                for name, (mode, blob) in tracked.items():
                    record = before['files'][name]
                    path = REPO / name
                    data = os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
                    actual_blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
                    actual_mode = '120000' if path.is_symlink() else ('100755' if path.stat().st_mode & 0o111 else '100644')
                    check(record == {'git_mode': mode, 'git_blob': blob, 'sha256': sha(data)} and actual_blob == blob and actual_mode == mode, 'source current bytes/frozen blob/mode ' + name)
                identities[family] = len(tracked)
            elif family == 'dependencies':
                check(before['count'] == len(before['sha256_by_path']), 'dependency count')
                identities[family] = compare_hashes(before['sha256_by_path'], family)
            else:
                identities[family] = compare_hashes(before, family, family == 'workspace')
        check(digest(Path(receipt['test_workspace']) / 'pubspec.lock') == receipt['enforced_workspace_lock_sha256'], 'enforced workspace lock hash')
        check(digest(REPO / 'docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock') == receipt['enforced_workspace_lock_sha256'], 'workspace lock differs from preserved committed lock')
        REPORT['qualification']['independently_rehashed_input_counts'] = identities
        REPORT['qualification']['current_head_at_audit'] = git('rev-parse', 'HEAD').decode().strip()
    if (QUAL / 'python-controls-summary.json').exists():
        py = read_json(QUAL / 'python-controls-summary.json')
        log = gzip.decompress((QUAL / 'python-controls/stderr.gz').read_bytes()).decode()
        observed = [(m.group(1), m.group(2)) for m in re.finditer(r'^\S+ \(([^)]+)\) \.\.\. (ok|skipped[^\n]*)$', log, re.M)]
        ok = [name for name, outcome in observed if outcome == 'ok']
        skipped = [name for name, outcome in observed if outcome.startswith('skipped')]
        check(collections.Counter(name for name, _ in observed) == collections.Counter(py['selected_test_ids']), 'Python raw selected-case coverage')
        check(collections.Counter(ok) == collections.Counter(py['successful_test_ids']), 'Python raw success ledger')
        check(skipped == [plan['optional_missing_python_converter_case']], 'Python optional converter skip identity')
        check(len(ok) == py['substantive_success_count'] == 107 and len(observed) == py['tests_run'] == 108, 'Python raw counts')
        check(py['runtime_before'] == py['runtime_after'], 'Python runtime maps changed')
        runtime = py['runtime_before']
        compare_hashes(runtime['numpy_inputs_sha256'], 'Python numpy')
        check(digest(runtime['python_executable']) == runtime['python_executable_sha256'], 'Python executable hash')
        REPORT['python_controls'] = {'selected': len(observed), 'success': len(ok), 'skipped': skipped, 'not_model_inference': True}

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W, 'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing', 'x': 'http://www.w3.org/1999/xhtml'}
def attr(node, name='val'):
    return node.get('{' + W + '}' + name) if node is not None else None

def bbox(path):
    return [{'size': [float(p.get('width')), float(p.get('height'))], 'words': [dict(text=w.text or '', **{k:float(v) for k,v in w.attrib.items()}) for w in p.xpath('.//x:word', namespaces=NS)]}
            for p in E.parse(str(path)).xpath('//x:page', namespaces=NS)]

def resolved(paragraph, styles_root, kind, run=None):
    styles = {attr(s, 'styleId'): s for s in styles_root.findall('w:style', NS)}
    values = {}
    defaults = styles_root.find('w:docDefaults/w:' + kind[0] + 'PrDefault/w:' + kind, NS)
    if defaults is not None:
        values.update({E.QName(c).localname: c for c in defaults})
    chain = []
    sid = attr(paragraph.find('w:pPr/w:pStyle', NS))
    if sid is None:
        sid = next((k for k,s in styles.items() if attr(s, 'type') == 'paragraph' and attr(s, 'default') == '1'), None)
    seen = set()
    while sid in styles and sid not in seen:
        seen.add(sid)
        chain.insert(0, styles[sid])
        sid = attr(styles[sid].find('w:basedOn', NS))
    if run is not None:
        rchain = []
        sid = attr(run.find('w:rPr/w:rStyle', NS))
        while sid in styles and sid not in seen:
            seen.add(sid)
            rchain.insert(0, styles[sid])
            sid = attr(styles[sid].find('w:basedOn', NS))
        chain += rchain
    for element in chain + [run if run is not None else paragraph]:
        props = element.find('w:' + kind, NS)
        if props is not None:
            values.update({E.QName(c).localname: c for c in props})
    return values

def check_consumers():
    receipt = read_json(CONS / 'receipt.json')
    check(receipt['source_head'] == FROZEN and receipt['source_tree'] == TREE, 'consumer frozen source identity')
    before, after = read_json(CONS / 'inputs.json.gz'), read_json(CONS / 'inputs-after.json.gz')
    check(before == after, 'consumer source/runtime input maps differ')
    check(digest(CONS / 'inputs.json.gz') == receipt['inputs_sha256'], 'consumer input file hash')
    for kind in ('source', 'runtime'):
        check(len(before[kind]) == receipt['input_counts'][kind], 'consumer input count ' + kind)
        compare_hashes(before[kind], 'consumer ' + kind)
    compare_hashes(receipt['fixture_inventory'], 'consumer fixture inventory')
    compare_hashes({str(CONS / path): value for path, value in receipt['output_hashes'].items()}, 'consumer outputs')
    check(len(receipt['commands']) == 86 and all(c['exit_code'] == 0 for c in receipt['commands']), 'consumer command failures/coverage')
    specs = read_json(CONS / 'fixtures/fixtures.json')
    recorded = {v['name']:v for v in receipt['fixtures']}
    check(len(specs) == len(recorded) == len(receipt['fixtures']) == 26 and set(recorded) == {s['name'] for s in specs}, 'consumer fixture identity coverage')
    schema_dir = BASE / 'runtime-recovery/consumer-recovery/schemas'
    schemas = {}
    for name, expected in {'OpenDocument-v1.3-schema.rng':'40bad03efdbb02825230d357da0aa6ac679934c5bf56c6281752c0c24d58e4e6',
                           'OpenDocument-v1.3-manifest-schema.rng':'8aee71f03484be112af972d622cc9031280c007b0a454ae8815e8e333c9bdd17'}.items():
        check(digest(schema_dir / name) == expected, 'official consumer schema identity ' + name)
        schemas[name] = E.RelaxNG(E.parse(str(schema_dir / name)))
    parts = ('content.xml','styles.xml','meta.xml','META-INF/manifest.xml')
    measurements, schema_passes = [], 0
    for spec in specs:
        name = spec['name']
        start_failures = len(REPORT['failures'])
        result = recorded[name]
        sem = result['semantics']
        with zipfile.ZipFile(CONS / 'fixtures' / spec['file']) as archive:
            check(archive.testzip() is None, name + ': ODT CRC')
            for part in parts:
                schema = schemas['OpenDocument-v1.3-manifest-schema.rng' if part.startswith('META-INF') else 'OpenDocument-v1.3-schema.rng']
                passed = schema.validate(E.fromstring(archive.read(part)))
                schema_passes += passed
                check(passed, name + ': independently revalidated schema ' + part)
        check(set(result['schema']['passed_parts']) == set(parts) and len(result['schema']['passed_parts']) == 4 and not result['schema']['failures'], name + ': recorded schema claims')
        pages = bbox(CONS / 'converted' / (name + '.bbox.xhtml'))
        check(len(pages) == len(spec['page_sizes_pt']), name + ': page count')
        check([p['size'] for p in pages] == sem['page_sizes_pt'], name + ': recorded page sizes')
        for observed, expected in zip(pages, spec['page_sizes_pt']):
            check(all(abs(a-b) <= .2 for a,b in zip(observed['size'], expected)), name + ': expected page dimensions')
        locations = {}
        for word, target in spec['word_pages'].items():
            matches = [dict(page=i, **v) for i,p in enumerate(pages,1) for v in p['words'] if v['text'] == word]
            check(len(matches) == 1 and matches[0]['page'] == target, name + ': unique expected word/page ' + word)
            if matches:
                locations[word] = matches[0]
        check(locations == sem['word_locations'], name + ': recorded word locations differ from raw bbox')
        for a,b in spec.get('same_x', []):
            check(abs(locations[a]['xMin'] - locations[b]['xMin']) <= .3, name + ': sibling indentation')
        for a,b in spec.get('indented', []):
            check(locations[b]['xMin'] - locations[a]['xMin'] >= 10, name + ': child indentation')
        order = spec.get('vertical_order', [])
        check(all((locations[a]['page'],locations[a]['yMin']) < (locations[b]['page'],locations[b]['yMin']) for a,b in zip(order,order[1:])), name + ': vertical order')
        plain = (CONS / 'converted' / (name + '.txt')).read_text()
        for word, label in spec.get('labels',{}).items():
            check(re.search(r'^\s*' + re.escape(label) + r'\s+' + re.escape(word) + r'\s*$', plain, re.M) is not None, name + ': literal marker ' + word)
        for axis, key in [('left_edge','xMin'),('right_edge','xMax')]:
            if axis in spec:
                check(all(abs(locations[w][key] - spec[axis]['points']) <= .3 for w in spec[axis]['words']), name + ': ' + axis)
        if 'line_step' in spec:
            a,b = spec['line_step']['words']
            check(abs(locations[b]['yMin'] - locations[a]['yMin'] - spec['line_step']['points']) <= .15, name + ': line step')
        if 'same_layout_as' in spec:
            reference = bbox(CONS / 'converted' / (spec['same_layout_as'] + '.bbox.xhtml'))
            for word, pos in locations.items():
                matches = [dict(page=i, **v) for i,p in enumerate(reference,1) for v in p['words'] if v['text'] == word]
                check(len(matches) == 1 and matches[0]['page'] == pos['page'] and all(abs(pos[k]-matches[0][k]) <= .1 for k in ('xMin','xMax','yMin','yMax')), name + ': control layout ' + word)
        footer_locations = []
        with zipfile.ZipFile(CONS / 'converted' / (name + '.docx')) as archive:
            check(archive.testzip() is None, name + ': DOCX CRC')
            document = E.fromstring(archive.read('word/document.xml'))
            types = document.xpath('//w:sectPr/w:type/@w:val', namespaces=NS)
            check(types == sem['reopened_section_types'], name + ': recorded section types')
            if 'reopened_section_type' in spec:
                check(spec['reopened_section_type'] in types, name + ': expected DOCX section type')
            if 'reopened_frame' in spec:
                expected = spec['reopened_frame']
                anchors = document.xpath('//wp:anchor[.//w:t[text()=$text]]', namespaces=NS, text=expected['word'])
                check(len(anchors) == 1, name + ': DOCX frame count')
                if anchors:
                    anchor = anchors[0]
                    h,v,e = (anchor.find('wp:' + tag,NS) for tag in ('positionH','positionV','extent'))
                    check(h.get('relativeFrom') == v.get('relativeFrom') == 'page', name + ': DOCX frame anchoring')
                    values = [float(h.findtext('wp:posOffset',namespaces=NS))/12700, float(v.findtext('wp:posOffset',namespaces=NS))/12700,float(e.get('cx'))/12700,float(e.get('cy'))/12700]
                    check(values == sem['reopened_frame_geometry_pt'] and all(abs(a-b)<=.1 for a,b in zip(values,expected['geometry_pt'])),name + ': DOCX frame geometry')
            if 'paragraph_decorations' in spec or 'styled_footer' in spec:
                styles = E.fromstring(archive.read('word/styles.xml'))
                for word, expected in spec.get('paragraph_decorations',{}).items():
                    candidates = document.xpath('//w:p[.//w:t[text()=$text]]',namespaces=NS,text=word)
                    check(len(candidates)==1,name + ': decorated paragraph identity')
                    props=resolved(candidates[0],styles,'pPr')
                    fill=attr(props.get('shd'),'fill')
                    fill=fill.upper() if fill else None
                    check(fill==expected['fill'] if expected['fill'] else fill in (None,'AUTO','FFFFFF'),name + ': decoration fill ' + word)
                    border=props.get('pBdr')
                    sides={} if border is None else {E.QName(c).localname:c for c in border}
                    if expected['border']:
                        check(all(k in sides and attr(sides[k])=='single' and (attr(sides[k],'color') or '').upper()==expected['border'] and attr(sides[k],'sz')=='4' for k in ('top','bottom','left','right')),name + ': decoration borders ' + word)
                    else:
                        check(all(attr(side) in (None,'none','nil') for side in sides.values()),name + ': plain borders ' + word)
                if 'styled_footer' in spec:
                    expected=spec['styled_footer']
                    check(len(expected['page_numbers'])==len(pages),name + ': footer page cardinality')
                    for number,page in zip(expected['page_numbers'],pages):
                        needle=[str(number)]+expected['suffix'].split()
                        tokens=[v['text']for v in page['words']]
                        positions=[i for i in range(len(tokens)-len(needle)+1)if tokens[i:i+len(needle)]==needle]
                        check(len(positions)==1,name + ': actual PAGE value and full suffix on page '+str(number))
                        if positions:
                            footer_locations.append(page['words'][positions[0]:positions[0]+len(needle)])
                    matched=[]
                    for part in archive.namelist():
                        if re.fullmatch(r'word/footer\d+\.xml',part):
                            for para in E.fromstring(archive.read(part)).xpath('//w:p',namespaces=NS):
                                if expected['suffix'] in ' '.join(''.join(para.xpath('.//w:t/text()',namespaces=NS)).split()):
                                    matched.append(para)
                    check(bool(matched),name + ': reopened suffix exists')
                    for para in matched:
                        instructions=para.xpath('.//w:instrText/text() | .//w:fldSimple/@w:instr',namespaces=NS)
                        check(any(re.search(r'\bPAGE\b',s) for s in instructions),name + ': reopened PAGE instruction')
                        runs=[r for r in para.xpath('.//w:r',namespaces=NS)if ''.join(r.xpath('.//w:t/text()',namespaces=NS)).strip()]
                        check(bool(runs),name + ': visible footer runs')
                        for run in runs:
                            props=resolved(para,styles,'rPr',run)
                            check(('b' in props and attr(props['b'])not in ('0','false','off'))==expected['bold'] and (attr(props.get('color'))or'').upper()==expected['color'] and attr(props.get('sz'))==str(expected['font_size_half_points']),name + ': footer field/suffix run styling')
        raster = CONS / 'rasters' / (name + '.png')
        with Image.open(raster) as source:
            image=source.convert('RGB')
            if 'red_picture' in spec:
                expected=spec['red_picture']
                pixels=[i for i,(r,g,b)in enumerate(image.get_flattened_data())if r>=240 and g<=15 and b<=15]
                check(bool(pixels),name + ': red picture pixels')
                if pixels:
                    xs=[v%image.width for v in pixels];ys=[v//image.width for v in pixels]
                    values={'left_pt':min(xs)*.75,'width_pt':(max(xs)-min(xs)+1)*.75,'height_pt':(max(ys)-min(ys)+1)*.75}
                    check(all(abs(values[k]-expected[k])<=1 for k in values) and len(pixels)>=expected['width_pt']*expected['height_pt']/.75,name + ': red picture geometry/coverage')
            def count_color(bounds,color):
                x1,y1,x2,y2=bounds
                crop=image.crop((max(0,int(x1/.75)),max(0,int(y1/.75)),min(image.width,int(x2/.75)+1),min(image.height,int(y2/.75)+1)))
                return sum(all(abs(a-b)<=20 for a,b in zip(pixel,color))for pixel in crop.get_flattened_data())
            for word,expected in spec.get('paragraph_decorations',{}).items():
                if expected['fill']:
                    pos=locations[word]
                    color=tuple(int(expected['fill'][i:i+2],16)for i in (0,2,4))
                    check(count_color([pos['xMin'],pos['yMin'],min(pos['xMax']+120,364),pos['yMax']],color)>=60,name + ': rendered paragraph fill '+word)
            if footer_locations:
                page_number=min(max(spec['word_pages'].values()),len(pages))
                positions=footer_locations[page_number-1]
                bounds=[min(p['xMin']for p in positions),min(p['yMin']for p in positions),max(p['xMax']for p in positions),max(p['yMax']for p in positions)]
                check(count_color(bounds,(0,0,255))>=30,name + ': rendered blue footer')
        measured_passed=len(REPORT['failures'])==start_failures
        check(result['passed']==measured_passed,name + ': recorded pass disagrees with independent artifact audit')
        measurements.append({'name':name,'passed':measured_passed,'pages':len(pages),'asserted_words':len(locations)})
    summary={'fixtures':len(specs),'passed':sum(v['passed']for v in measurements),'failed':sum(not v['passed']for v in measurements),'schema_parts_passed':schema_passes,'schema_parts_total':len(parts)*len(specs)}
    check(summary==receipt['summary'],'consumer aggregate does not match independently measured fixture outcomes')
    REPORT['consumer']={'summary':summary,'fixtures':measurements,'independently_rehashed_input_counts':{k:len(v)for k,v in before.items()},'verified_output_hashes':len(receipt['output_hashes'])}

def check_archives():
    archives=[]
    root=REPO/'docs/validation/office-recovery-20261117'
    for path in sorted(root.rglob('*index*.json')):
        index=read_json(path)
        if 'archive'not in index or not ('files'in index or 'members'in index):
            continue
        structured=isinstance(index['archive'],dict)
        archive_name=index['archive']['file']if structured else index['archive']
        archive_sha=index['archive']['sha256']if structured else index['archive_sha256']
        archive_size=index['archive']['size']if structured else index.get('archive_bytes')
        archive_path=path.parent/archive_name
        check(digest(archive_path)==archive_sha,'archive hash '+str(path.relative_to(REPO)))
        if archive_size is not None:
            check(archive_path.stat().st_size==archive_size,'archive byte size '+path.name)
        files=index['members']if structured else index['files']
        with tarfile.open(archive_path)as archive:
            members=[m for m in archive.getmembers()if m.isfile()]
            check(len(members)==len({m.name for m in members})==len(files),'archive duplicate/count mismatch '+path.name)
            check({m.name for m in members}==set(files),'archive member identity set '+path.name)
            for member in members:
                check(not member.name.startswith('/')and'..'not in Path(member.name).parts,'unsafe archive name')
                data=archive.extractfile(member).read()
                record=files[member.name]
                expected=record['sha256']if isinstance(record,dict)else record
                check(sha(data)==expected,'archive member hash '+member.name)
                if isinstance(record,dict)and'bytes'in record:
                    check(len(data)==record['bytes'],'archive member length '+member.name)
                if isinstance(record,dict)and'size'in record:
                    check(len(data)==record['size'],'archive member size '+member.name)
                if isinstance(record,dict)and'mode'in record:
                    check(member.mode==int(record['mode'],8),'archive member mode '+member.name)
                if member.name.startswith('run/')and index.get('kind')=='independent-odt-consumer-evidence':
                    supplements = {'run/runner.stdout.log':CONS.parent/'final-966196f3.stdout.log',
                                   'run/runner.stderr.log':CONS.parent/'final-966196f3.stderr.log',
                                   'run/visual-review.json':root/'consumer/visual-review.json'}
                    source = supplements.get(member.name, CONS/member.name[4:])
                    check(digest(source)==sha(data),'consumer archive differs from audited raw evidence/supplement '+member.name)
                if member.name.startswith('qualification/'):
                    check(digest(QUAL/member.name[len('qualification/'):])==sha(data),'qualification archive differs from audited raw evidence '+member.name)
            if any(m.name.startswith('qualification/')for m in members):
                run_members={m.name[len('qualification/'):]for m in members if m.name.startswith('qualification/')}
                raw_files={str(p.relative_to(QUAL))for p in QUAL.rglob('*')if p.is_file()}
                check(run_members==raw_files,'qualification archive omitted/added raw evidence files')
                check(sum(m.size for m in members)==index['archive']['uncompressed_bytes'],'qualification uncompressed archive size')
        archives.append({'index':str(path.relative_to(REPO)),'sha256':archive_sha,'verified_members':len(files)})
    REPORT['archives']=archives
    check(any(v['verified_members']==344 for v in archives),'consumer 344-member archive missing')
    if not any('qualification'in v['index'] for v in archives):
        REPORT['pending'].append('Final qualification archive/index has not yet been published for independent hash verification.')

def main():
    for label, work in [('qualification',check_qualification),('consumers',check_consumers),('archives',check_archives)]:
        try:
            work()
        except Exception as error:
            REPORT['failures'].append(label+': verifier exception '+type(error).__name__+': '+str(error))
    REPORT['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    REPORT['verifier_sha256']=digest(Path(__file__))
    REPORT['passed']=not REPORT['failures']and not REPORT['pending']
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'audit.json').write_text(json.dumps(REPORT,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:v for k,v in REPORT.items()if k in ('checks','failures','pending','passed','finished_utc')},indent=2))
    return 0 if REPORT['passed']else(1 if REPORT['failures']else 3)

if __name__=='__main__':
    raise SystemExit(main())

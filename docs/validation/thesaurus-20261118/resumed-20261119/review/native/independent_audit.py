#!/usr/bin/env python3
"""Read-only independent audit; writes only to this audit directory."""
import ast
import collections
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
from urllib.parse import unquote, urlparse
import zlib

ROOT = Path('/workspace/scratch/786b438f79ef')
REPO = ROOT / 'quds_office_suite'
RUN = ROOT / 'native-final-qualification'
OUT = ROOT / 'final-native-audit'
SOURCE = '39843ed4874c7b56572c7aa8195716e5892aeca2'
FIXREL = 'docs/validation/thesaurus-20261118/continuation/local/fixtures/'
FIX = REPO / FIXREL
WORK = ROOT / 'native-validation-task/zotero-validation'
NOW = datetime.now(timezone.utc).isoformat()

def sha(data):
    return hashlib.sha256(data).hexdigest()

def read_json(path):
    return json.loads(path.read_bytes())

def read_gzip(path):
    return json.loads(gzip.decompress(path.read_bytes()))

def record(path, data):
    return {'path': path, 'bytes': len(data), 'sha256': sha(data)}

def write(name, data):
    data.update(recorded_at_utc=NOW, auditor='independent incoming_audit agent',
                source_commit=SOURCE)
    (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print(name, data.get('status'), flush=True)

receipt = read_json(RUN / 'receipt.json')
assert receipt['base_commit'] == SOURCE
assert receipt['status'] == 'native_passed_web_compiled_browser_not_run'
runs = {r['name']: r for r in receipt['runs']}
assert len(runs) == len(receipt['runs']) == 2
for run in runs.values():
    assert run['exit_code'] == 0
    for stream in ('stdout', 'stderr'):
        assert sha((RUN / run[stream]).read_bytes()) == run[stream + '_sha256']

# Raw JSON-event audit, without importing the producer's audit implementation.
native = runs['native-acceptance']
events = [json.loads(line) for line in (RUN / native['stdout']).read_text().splitlines()]
assert events[-1]['type'] == 'done' and events[-1]['success'] is True
assert sum(e['type'] == 'done' for e in events) == 1
assert not any(e['type'] == 'error' for e in events)
suites = {e['suite']['id']: e['suite'] for e in events if e['type'] == 'suite'}
starts = [e['test'] for e in events if e['type'] == 'testStart']
dones = [e for e in events if e['type'] == 'testDone']
assert len(suites) == sum(e['type'] == 'suite' for e in events) == 14
assert len(starts) == len({s['id'] for s in starts}) == len(dones) == len({d['testID'] for d in dones})
assert {s['id'] for s in starts} == {d['testID'] for d in dones}
by_id = {s['id']: s for s in starts}
assert all(d['result'] == 'success' and not d['skipped'] for d in dones)
assert all(not s['metadata']['skip'] for s in starts)
excluded, substantive = [], []
for done in dones:
    start = by_id[done['testID']]
    case = {'suite': suites[start['suiteID']]['path'], 'name': start['name'], 'test_id': start['id']}
    pseudo = start['name'].startswith('loading ') or start['name'] in ('(setUpAll)', '(tearDownAll)')
    assert done['hidden'] == pseudo
    (excluded if pseudo else substantive).append(case)
assert len(substantive) == 208 and len(excluded) == 26
assert len({(c['suite'], c['name']) for c in substantive}) == 208
selected = native['command'][native['command'].index('json') + 1:]
assert {str((Path(native['cwd']) / p).resolve()) for p in selected} == {
    str(Path(s['path']).resolve()) for s in suites.values()}
messages = [e.get('message', '') for e in events if e['type'] == 'print']
assert not any(re.search(r'overflowed|RenderFlex|EXCEPTION CAUGHT|hit test.*miss|would not hit test', m, re.I) for m in messages)
assert (RUN / native['stderr']).read_bytes() == b''
write('native-events.json', {
    'status': 'passed', 'method': 'Parsed every raw JSON event; independently classified loading/setup/teardown and checked test identity, completion, final success and diagnostics.',
    'raw_stdout_sha256': sha((RUN / native['stdout']).read_bytes()),
    'events': len(events), 'event_types': dict(collections.Counter(e['type'] for e in events)),
    'substantive_passed': len(substantive), 'substantive_failed': 0, 'substantive_skipped': 0,
    'suite_count': len(suites), 'selected_suite_identity_matches': True,
    'test_starts': len(starts), 'test_finishes': len(dones), 'each_start_finished_once': True,
    'unique_suite_and_case_identities': 208, 'excluded_successful_pseudo_events': len(excluded),
    'excluded_loading': sum(c['name'].startswith('loading ') for c in excluded),
    'excluded_setup_teardown': sum(not c['name'].startswith('loading ') for c in excluded),
    'final_success_events': 1, 'error_events': 0, 'layout_or_tap_diagnostics': [],
    'suite_case_counts': dict(sorted(collections.Counter(c['suite'] for c in substantive).items())),
    'cases': substantive, 'scope': 'Native event-stream audit only; no additional runtime tests executed.'})

# SHA-256 receipt equality plus canonical Git blob equality to the fixed source commit.
inputs = read_gzip(RUN / 'source-inputs.json.gz')
assert sha(json.dumps(inputs, sort_keys=True, separators=(',', ':')).encode()) == receipt['input_digest']
tree_raw = subprocess.check_output(['git', 'ls-tree', '-rz', SOURCE], cwd=REPO)
tree = {}
for row in tree_raw.split(b'\0'):
    if row:
        meta, path = row.split(b'\t', 1)
        mode, typ, oid = meta.decode().split()
        tree[path.decode()] = {'mode': mode, 'type': typ, 'oid': oid}
bound = {}
for key, value in inputs.items():
    if not key.startswith('__'):
        bound[key] = value
    elif key.startswith('__fixture__/'):
        bound[FIXREL + key.removeprefix('__fixture__/')] = value
    elif key.startswith('__helper__/'):
        bound[key.removeprefix('__helper__/')] = value
for path, meta in bound.items():
    data = (REPO / path).read_bytes()
    assert sha(data) == meta['sha256'], path
    assert 'bytes' not in meta or len(data) == meta['bytes'], path
    git_hash = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    assert tree[path]['type'] == 'blob' and git_hash == tree[path]['oid'], path
setup = read_json(RUN / 'final-source-setup.json')
binding = inputs['__workspace_binding__']
assert binding == receipt['workspace_binding'] == setup['effective_workspace_binding']
assert setup['source_commit'] == SOURCE
assert setup['source_tree'] == subprocess.check_output(['git', 'rev-parse', SOURCE + '^{tree}'], cwd=REPO, text=True).strip()
for key, path in [('__workspace_lock__', WORK / 'pubspec.lock'), ('__workspace_package_config__', WORK / '.dart_tool/package_config.json')]:
    data = path.read_bytes()
    assert inputs[key] == {'bytes': len(data), 'sha256': sha(data)}
assert (REPO / 'pubspec.lock').read_bytes() == (WORK / 'pubspec.lock').read_bytes()
assert sha((WORK / 'pubspec.lock').read_bytes()) == setup['workspace_lock_sha256'] == setup['source_lock_sha256']
config = read_json(WORK / '.dart_tool/package_config.json')
packages = {p['name']: p for p in config['packages']}
assert len(packages) == len(config['packages'])
def uri_path(base, value):
    uri = urlparse(value)
    assert uri.scheme in ('', 'file') and uri.netloc in ('', 'localhost')
    return (base / unquote(uri.path)).resolve()
for name, roots in binding['package_roots'].items():
    root, source = Path(roots['root']), Path(roots['source'])
    assert root.resolve() == uri_path(WORK / '.dart_tool', packages[name]['rootUri'])
    assert Path(roots['library']).resolve() == uri_path(root, packages[name]['packageUri'])
    assert (root / 'pubspec.yaml').read_bytes() == (source / 'pubspec.yaml').read_bytes()
    assert not (root / 'pubspec_overrides.yaml').exists()
for relative, resolved in binding['source_links'].items():
    assert (WORK / relative).resolve() == (REPO / relative).resolve() == Path(resolved)
before = read_gzip(RUN / 'runtime-inputs-before.json.gz')
after = read_gzip(RUN / 'runtime-inputs-after.json.gz')
assert len(before) == 11953 and before == after
for path, digest in before.items():
    assert sha(Path(path).read_bytes()) == digest, path
supplemental = read_json(RUN / 'supplemental-runtime-receipt.json')
assert supplemental['source_commit'] == SOURCE and supplemental['source_head_after'] == SOURCE
assert supplemental['runtime_input_count'] == len(before)
assert supplemental['status'] == 'passed' and supplemental['exit_code'] == 0
for relative, digest in supplemental['evidence_hashes'].items():
    assert sha((RUN / relative).read_bytes()) == digest, relative
assert receipt['source_unchanged_during_tests'] is True and receipt['source_unchanged_during_build'] is True
write('source-binding.json', {
    'status': 'passed', 'method': 'Hashed all bound current source bytes, checked canonical Git blob IDs at fixed source commit, resolved workspace/package links and copied manifests, independently rehashed all supplemental runtime files.',
    'source_tree': setup['source_tree'], 'input_digest': receipt['input_digest'],
    'ordinary_source_records': sum(not k.startswith('__') for k in inputs),
    'fixture_and_helper_records': sum(k.startswith(('__fixture__/', '__helper__/')) for k in inputs),
    'workspace_binding_records': 3, 'source_inventory_total_records': len(inputs),
    'bound_files_matching_current_bytes_and_exact_git_commit': len(bound),
    'workspace_packages': len(binding['package_roots']), 'source_links_verified': len(binding['source_links']),
    'runtime_files_rehashed': len(before), 'runtime_before_equals_after_and_current': True,
    'producer_source_unchanged_during_tests': True, 'producer_source_unchanged_during_build': True,
    'temporal_limit': 'Before/after temporal equality is recorded by the bound harness; this independent audit also establishes equality to current bytes. It does not observe every instant during execution.',
    'runtime_version': supplemental['runtime'], 'receipt_sha256': sha((RUN / 'receipt.json').read_bytes())})

# Independently reconstruct installed contents from the bound compile inventory and literal overlay.
build = RUN / 'browser-build'
build_binding = receipt['browser_build_binding']
for item in ('source_inputs', 'compiled_files'):
    assert sha((RUN / build_binding[item]['path']).read_bytes()) == build_binding[item]['sha256']
compiled = read_gzip(RUN / build_binding['compiled_files']['path'])
assert len(compiled) == receipt['compiled_browser_files'] == 1155
assert sum(r['bytes'] for r in compiled) == receipt['compiled_browser_bytes'] == 87446576
assert [r['path'] for r in compiled] == sorted({r['path'] for r in compiled})
syntax = ast.parse((FIX / 'install_offline.py').read_text())
literals = {}
for node in syntax.body:
    if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
        try:
            literals[node.targets[0].id] = ast.literal_eval(node.value)
        except (ValueError, TypeError):
            pass
expected = {r['path']: r for r in compiled}
expected['index.html'] = record('index.html', literals['INDEX'].encode())
expected['offline-install.js'] = record('offline-install.js', literals['INSTALL_SCRIPT'].encode())
expected = [expected[k] for k in sorted(expected)]
actual = []
generated = {}
for path in sorted(build.rglob('*')):
    assert not path.is_symlink(), path
    if path.is_file():
        relative = path.relative_to(build).as_posix()
        item = record(relative, path.read_bytes())
        if relative in ('offline-files.json', 'offline-test-worker.js'):
            generated[relative] = item
        else:
            actual.append(item)
assert actual == expected
assert read_json(build / 'offline-files.json') == expected
assert read_gzip(RUN / 'installed-file-inventory.json.gz') == actual
identity = sha(json.dumps(actual, sort_keys=True).encode())
worker_node = next(n for n in syntax.body if isinstance(n, ast.FunctionDef) and n.name == 'worker_script')
worker_return = next(n for n in worker_node.body if isinstance(n, ast.Return))
worker_tail = ast.literal_eval(worker_return.value.right)
worker_expected = ('const CACHE_NAME = ' + json.dumps(literals['CACHE_PREFIX'] + identity) + ';\n' +
                   'const FILES = ' + json.dumps(actual, ensure_ascii=True) + ';\n' + worker_tail)
assert (build / 'offline-test-worker.js').read_bytes() == worker_expected.encode()
assert re.search(r'_flutter\.loader\.load\(\s*\);\s*$', (build / 'flutter_bootstrap.js').read_text())
install = read_json(RUN / 'offline-installation.json')
assert install['cache_identity'] == identity and install['files'] == len(actual)
assert install['bytes'] == sum(r['bytes'] for r in actual)
prov = install['compile_provenance']
assert prov['source_commit'] == SOURCE
assert prov['receipt_sha256'] == sha((RUN / 'receipt.json').read_bytes())
assert prov['source_input_digest'] == receipt['input_digest']
assert prov['source_inventory_sha256'] == build_binding['source_inputs']['sha256']
assert prov['compiled_inventory_sha256'] == build_binding['compiled_files']['sha256']
assert prov['compiled_files'] == len(compiled) and prov['compiled_bytes'] == sum(r['bytes'] for r in compiled)
for name, value in prov['fixture_inputs'].items():
    assert value == inputs['__fixture__/' + name]['sha256']
for name, value in prov['source_verification_helpers'].items():
    assert value == inputs['__helper__/' + name]['sha256']
build_run = runs['browser-build']
assert {'--release', '--csp', '--no-web-resources-cdn', '--no-pub', '--no-wasm-dry-run', '--pwa-strategy=none'} <= set(build_run['command'])
assert '--target=' + str(FIX / 'lib/main.dart') in build_run['command']
assert prov['build_command'] == build_run['command']
assert receipt['browser_execution']['status'] == 'not_run'
write('compile-installation.json', {
    'status': 'passed', 'method': 'Independent byte scanner reconstructed compile inventory plus the two bound literal overlays; checked every installed byte, generated worker text, complete manifest, bootstrap, hashes and provenance.',
    'compile_exit_code': 0, 'compile_command': build_run['command'],
    'compile_stdout_sha256': build_run['stdout_sha256'], 'compile_stderr_sha256': build_run['stderr_sha256'],
    'compiled_inventory_files': len(compiled), 'compiled_inventory_bytes': sum(r['bytes'] for r in compiled),
    'original_compiled_files_rehashed_unchanged': len(compiled) - 1,
    'overlays': ['index.html replaced with exact bound literal', 'offline-install.js added with exact bound literal'],
    'original_index_limit': 'The original compile index is retained as a bound inventory record; its original bytes were replaced during installation, so this audit rehashes its literal replacement rather than claiming to rehash the original index.',
    'installed_inventory_files': len(actual), 'installed_inventory_bytes': sum(r['bytes'] for r in actual),
    'generated_files_outside_cache_inventory': generated,
    'all_on_disk_files': len(actual) + len(generated),
    'all_on_disk_bytes': sum(r['bytes'] for r in actual) + sum(r['bytes'] for r in generated.values()),
    'cache_identity': identity, 'compile_provenance': prov,
    'compiler_warnings': ['Deprecated --pwa-strategy option', 'Wider editor references packages/cupertino_icons/CupertinoIcons without a bundled font'],
    'browser_execution': 'not_run', 'installed_native_desktop': 'not_run',
    'scope': 'Successful release web compilation and test-only offline installation byte integrity; not browser/service-worker execution acceptance.'})

# Independently read compressed shards rather than calling the exporter's make_packet.
packet = read_json(RUN / 'linguistic/linguistic-review.json')
native_report = read_json(RUN / 'native-pack-report.json')
assert native_report['status'] == 'passed'
assert packet['queries'] == native_report['queries']
assert packet['report']['sha256'] == sha((RUN / 'native-pack-report.json').read_bytes())
assert packet['review_status'] == 'not_reviewed'
assert all(packet[k] is None for k in ('reviewer', 'reviewed_at', 'language_expertise', 'release_recommendation'))
assert packet['additional_cases'] == []
panel = [('bank','en-US'),('run','en-US'),('happy','en-GB'),('ice cream','en-US'),('children','en-US'),('dogs','en-US'),('Bank','de-DE'),('Häusern','de-DE'),('Maße','de-DE'),('Masse','de-DE'),('sich freuen','de-DE'),('Straße','de-CH'),('qudsxyzzynotaword','en-US'),('qudsxyzzynotaword','de-DE'),('banque','fr-FR')]
assert [(q['text'],q['language']) for q in packet['queries']] == panel
assert len(packet['decisions']) == 15
for decision, pair in zip(packet['decisions'], panel):
    assert decision == {'text': pair[0], 'language': pair[1], 'decision': None, 'sense_ids': [], 'term_ids': [], 'notes': None}
packs_dir = REPO / 'packages/quds_office_editor/assets/thesaurus'
manifests = {}
def verified_pack(locale, name):
    metadata = manifests[locale]['files'][name]
    compressed = metadata.get('compression') == 'deflate-raw'
    path = packs_dir / locale / (name + '.deflate' if compressed else name)
    raw = path.read_bytes()
    if compressed:
        assert len(raw) == metadata['compressedSize'] and sha(raw) == metadata['compressedSha256']
        decoder = zlib.decompressobj(-15)
        raw = decoder.decompress(raw, metadata['size'] + 1)
        assert decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail
    assert len(raw) == metadata['size'] and sha(raw) == metadata['sha256']
    return raw
notices = []
for locale in ('en', 'de'):
    manifest_bytes = (packs_dir / locale / 'manifest.json').read_bytes()
    manifest = manifests[locale] = json.loads(manifest_bytes)
    pack = packet['packs'][locale]
    assert pack['identity'] == manifest['packId'] + ':' + sha(manifest_bytes)
    assert pack['source'] == manifest['source'] and pack['source_url'] == manifest['sourceUrl']
    assert pack['license'] == manifest['license'] and pack['attribution'] == manifest['attribution']
    assert [n['path'] for n in pack['notices']] == manifest['noticePaths']
    for notice in pack['notices']:
        data = verified_pack(locale, notice['path'])
        assert notice['export_path'] == locale + '/' + notice['path']
        assert notice['bytes'] == len(data) and notice['sha256'] == sha(data)
        assert (RUN / 'linguistic' / notice['export_path']).read_bytes() == data
        notices.append({'locale': locale, **notice})
shards, observed_ids, query_summaries = {}, set(), []
for query in packet['queries']:
    locale = query['language'].split('-')[0]
    query_summaries.append({k: query[k] for k in ('text','language','status') } | {'returned_meanings': len(query['senses'])})
    if locale not in manifests:
        assert query['status'] == 'unsupportedLanguage' and query['pack'] is None and not query['senses']
        continue
    assert query['pack'] == packet['packs'][locale]['identity']
    expected_status = 'noEntry' if query['text'] == 'qudsxyzzynotaword' else 'ready'
    assert query['status'] == expected_status and bool(query['senses']) == (expected_status == 'ready')
    assert len(query['senses']) == len({s['id'] for s in query['senses']})
    for sense in query['senses']:
        sid, value = sense['id'], 0xC5
        for byte in sid.encode():
            value = ((value ^ byte) * 0x93) & 255
        name = f'senses/{value:02x}.json'
        key = (locale, name)
        if key not in shards:
            shards[key] = json.loads(verified_pack(locale, name))
        source = shards[key][sid]
        assert packet['source_records'][sid] == source
        projected = {'id':source['id'], 'source':source['source'], 'pos':source.get('pos'), 'gloss':source.get('gloss'), 'labels':source.get('labels',[]), 'examples':source.get('examples',[]), 'terms':[{'id':t['id'],'text':t['text'],'labels':t.get('labels',[])} for t in source['terms']], 'relations':source.get('relations',[])}
        assert sense == projected
        observed_ids.add(sid)
assert observed_ids == set(packet['source_records']) and len(observed_ids) == 109
assert len(notices) == 10
markdown = (RUN / 'linguistic/linguistic-review.md').read_text()
assert markdown.count('Decision: ______  Sense/term IDs: ______  Notes: ______') == 15
for text in ('Reviewer: ______  Date: ______  Language expertise: ______', 'Release recommendation and its bounded scope: ______', 'Reviewer sign-off: ______', '**Status: not reviewed. All decisions are intentionally blank.**'):
    assert text in markdown
assert all('### ' + sid in markdown for sid in observed_ids)
write('linguistic-packet.json', {
    'status': 'integrity_passed_human_review_not_completed',
    'method': 'Read raw native observations, independently decompressed/hash-verified source shards, compared complete records and observed projection, verified original notice bytes and all blank review fields.',
    'native_report_sha256': sha((RUN / 'native-pack-report.json').read_bytes()),
    'packet_json_sha256': sha((RUN / 'linguistic/linguistic-review.json').read_bytes()),
    'packet_markdown_sha256': sha((RUN / 'linguistic/linguistic-review.md').read_bytes()),
    'ordered_queries': 15, 'distinct_source_records': len(observed_ids),
    'verified_shards': len(shards), 'notices': notices,
    'queries': query_summaries, 'review_status': packet['review_status'],
    'blank_human_identity_fields': True, 'blank_decisions': 15, 'blank_recommendation_and_additions': True,
    'full_source_records_preserved': True, 'source_labels_examples_notes_relations_preserved': True,
    'scope': 'Evidence integrity and preservation only; no independent linguistic approval, vocabulary-wide acceptance, or additional provider run.'})

visuals = []
observations = {
    'english-desktop.png': '1200×900 native rendering. Thesaurus title, financial bank sense and selected multiword alternative, relation rows, notices, Close and Replace are readable. No visible overflow stripes or clipped action labels. Partial cards at the scroll viewport edges reflect the captured scroll position.',
    'german-desktop.png': '1200×900 native rendering. German language note, Bank meaning groups, selected Finanzinstitution and wrapped alternatives fit the modal. Notices, Close and Replace remain readable. The scrolled query area and lower card meet the fixed viewport boundaries without action-label clipping.',
    'german-narrow-large-text.png': '390×844 native rendering. Enlarged German alternatives wrap to multiple rows and footer actions wrap within dialog width. Title, close icon, Sources and licenses, Close and Replace are legible; no visible overflow stripes. List content is partially clipped at deliberate scroll viewport boundaries. Obscured app status labels use ellipses at narrow width.'}
for name, observation in observations.items():
    raw = (RUN / 'visuals' / name).read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n'
    width, height = struct.unpack('>II', raw[16:24])
    visuals.append({'file': name, 'bytes': len(raw), 'sha256': sha(raw), 'width': width, 'height': height, 'independently_opened_and_inspected': True, 'observation': observation})
write('visual-review.json', {'status': 'no_visible_modal_layout_defect_observed', 'screenshots': visuals,
    'scope': 'Actual three PNGs were opened and independently inspected by this agent. They are native widget renderings; they do not establish actual browser execution or an installed native desktop run.'})
write('summary.json', {'status': 'passed_with_explicit_acceptance_limits', 'native_cases': 208, 'native_suites': 14,
    'source_and_runtime_integrity': 'passed', 'compile_and_installed_bytes_integrity': 'passed',
    'linguistic_packet_integrity': 'passed', 'visual_review': 'no_visible_modal_layout_defect_observed',
    'browser_execution': 'not_run', 'installed_native_desktop': 'not_run', 'human_linguistic_review': 'not_completed',
    'no_extra_runtime_tests_executed': True, 'production_or_runtime_files_modified': False,
    'reports': ['native-events.json','source-binding.json','compile-installation.json','linguistic-packet.json','visual-review.json']})

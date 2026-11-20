"""Run a frozen-source, bounded-disk engine acceptance selection.

Usage: python3 run_final_macro_gate.py EXPECTED_FULL_HEAD UNIQUE_LABEL
No repository files or Git state are changed by this driver.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path('/workspace/scratch/f8bca915f70d')
REPO = ROOT / 'quds_office_suite'
ENGINE = REPO / 'packages/quds_office_engine'
WORK = ROOT / 'validation-workspace/packages/quds_office_engine'
SDK = ROOT / 'toolchains/dart-3.13.7/dart-sdk/bin/dart'
CACHE = ROOT / 'toolchains/pub-cache'
CONFIG = ROOT / 'validation-workspace/.dart_tool/package_config.json'
PORTABLE = ROOT / 'toolchains/run_powerpoint_portable.py'
EXAMPLE_CHECK = ROOT / 'toolchains/check_powerpoint_report_example.dart'

BATCHES = [
    ('operations-runtime', ['office_operations', 'office_steps', 'office_macro_runtime', 'office_macro_expansion']),
    ('format-and-word-guards', ['office_macro_word_revision_guard', 'office_macro_slide_format', 'word_step_atomicity', 'word_steps_vocabulary']),
    ('word-structure-and-sheet', ['word_structure_steps', 'table_grid_steps', 'word_table_grid_addressing', 'sheet_macro_preservation']),
    ('word-powerpoint-transactions', ['office_vba_word_integration', 'office_vba_word_format_integration', 'office_vba_powerpoint_integration', 'slide_import_fidelity']),
    ('slide-fidelity-and-variant', ['slide_text_fidelity', 'slide_rich_text_explicit_style', 'office_macro_language', 'office_vba_variant_conversions']),
    ('conformance-and-word-format', ['office_vba_conformance', 'office_vba_word_conformance', 'office_vba_powerpoint_conformance', 'office_vba_word_extensions']),
    ('compiler-host-boundaries', ['office_vba_powerpoint', 'office_vba_word_language', 'office_vba_variant_conformance', 'office_vba_language']),
    ('mcp-cli-bridge', ['office_macro_mcp']),
    ('native-macro-cli', ['office_macro_cli']),
    ('word-vba-cli', ['office_vba_word_cli']),
    ('powerpoint-vba-cli', ['office_vba_powerpoint_cli']),
]
BATCHES = [(name, [f'test/{f}_test.dart' for f in files]) for name, files in BATCHES]
SCOPES = [
    'packages/quds_office_engine/lib',
    'packages/quds_office_engine/test',
    'packages/quds_office_engine/tool',
    'packages/quds_office_engine/example/macros',
    'packages/legacy_doc_parser/lib',
]
EXTRA_INPUTS = [
    'pubspec.yaml', 'pubspec.lock', '.fvmrc', 'analysis_options.yaml',
    'packages/quds_office_engine/pubspec.yaml',
    'packages/quds_office_engine/analysis_options.yaml',
    'packages/legacy_doc_parser/pubspec.yaml',
]

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def manifest():
    files = {p for scope in SCOPES for p in (REPO / scope).rglob('*') if p.is_file()}
    files.update(REPO / p for p in EXTRA_INPUTS if (REPO / p).is_file())
    return {str(p.relative_to(REPO)): sha(p) for p in sorted(files)}

def size(path):
    result = 0
    for root, _, files in os.walk(path):
        for name in files:
            try: result += (Path(root) / name).stat().st_size
            except FileNotFoundError: pass
    return result

def head():
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()

def parse_test_log(path, batch):
    records, nonjson = [], []
    for line in path.read_text(errors='replace').splitlines():
        try: records.append(json.loads(line))
        except json.JSONDecodeError: nonjson.append(line)
    suites = {r['suite']['id']: r['suite'] for r in records if r.get('type') == 'suite'}
    tests = {r['test']['id']: r['test'] for r in records if r.get('type') == 'testStart'}
    errors = [r for r in records if r.get('type') == 'error']
    outcomes = []
    for done in records:
        if done.get('type') != 'testDone' or done.get('hidden'): continue
        test = tests.get(done['testID'], {})
        suite = suites.get(test.get('suiteID'), {})
        source = suite.get('path', test.get('url', 'unknown'))
        if source.startswith('file://'): source = source[7:]
        for prefix in [str(WORK)+'/', str(ENGINE)+'/']:
            if source.startswith(prefix): source = source[len(prefix):]; break
        name = test.get('name', f"test-{done['testID']}")
        outcomes.append({
            'id': source+'::'+name, 'batch': batch, 'runner_test_id': done['testID'],
            'source_file': source, 'name': name, 'outcome': done['result'],
            'skipped': done.get('skipped', False),
            'errors': [e for e in errors if e.get('testID') == done['testID']],
        })
    done = [r for r in records if r.get('type') == 'done']
    return {
        'tests_passed': sum(t['outcome'] == 'success' and not t['skipped'] for t in outcomes),
        'tests_failed': sum(t['outcome'] not in ('success', 'skipped') for t in outcomes),
        'tests_skipped': sum(t['skipped'] for t in outcomes),
        'outcomes': outcomes, 'errors': errors,
        'runner_done': done, 'runner_success': len(done) == 1 and done[0].get('success') is True,
        'non_json_output': nonjson,
    }

def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    expected, label = sys.argv[1:]
    if len(expected) != 40 or any(c not in '0123456789abcdef' for c in expected):
        raise SystemExit('Expected a complete lowercase source SHA')
    if not label or not all(c.isalnum() or c in '-_' for c in label):
        raise SystemExit('Label must be a portable identifier')
    if head() != expected:
        raise SystemExit('Source HEAD changed before gate; obtain a new freeze')
    out = ROOT / 'toolchains/logs' / label
    out.mkdir()
    before = manifest()
    (out / 'inputs-before.json').write_text(json.dumps(before, indent=2)+'\n')
    environment = {
        'DART_SUPPRESS_ANALYTICS': 'true', 'CI': 'true',
        'PUB_CACHE': str(CACHE),
    }
    receipt = {
        'label': label, 'source_head_start': expected,
        'started_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'environment': environment, 'package_config_sha256': sha(CONFIG),
        'validation_script_sha256': {str(p):sha(p) for p in (Path(__file__), PORTABLE, EXAMPLE_CHECK)},
        'resolved_lock_sha256': sha(ROOT/'validation-workspace/pubspec.lock'),
        'source_scope': SCOPES, 'extra_inputs': EXTRA_INPUTS,
        'selected_files': [p for _, files in BATCHES for p in files],
        'test_timeout_factor': '4x', 'max_files_per_batch': 4,
        'transient_limit_bytes': 650*1024*1024,
        'stages': [], 'all_stages_passed': False,
        'retained_evidence_note': 'Earlier source-only array/procedure/control-flow cohorts remain separately attributed; they are not added to this final-source execution count.',
    }
    def checkpoint():
        (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    def changed():
        current = manifest()
        return {k:[before.get(k),current.get(k)] for k in sorted(set(before)|set(current)) if before.get(k)!=current.get(k)}
    def run(stage, cmd, cwd, is_tests=False):
        tmp = out / (stage+'-tmp')
        tmp.mkdir()
        log = out / (stage+'.log')
        env = os.environ.copy()
        env.update(environment)
        env['TMPDIR'] = str(tmp)
        started = time.monotonic()
        peak, stopped = 0, None
        print(json.dumps({'stage':stage,'state':'started','argv':cmd,'cwd':str(cwd)}),flush=True)
        with log.open('w') as stream:
            process = subprocess.Popen(cmd,cwd=cwd,env=env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
            while process.poll() is None:
                peak = max(peak,size(tmp))
                free = shutil.disk_usage(ROOT).free
                if peak > receipt['transient_limit_bytes'] or free < 48*1024*1024:
                    stopped = 'temporary disk budget' if peak > receipt['transient_limit_bytes'] else 'filesystem free space below 48 MiB'
                    os.killpg(process.pid,signal.SIGTERM)
                    try: process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid,signal.SIGKILL); process.wait()
                    break
                time.sleep(0.5)
            exit_code = process.wait()
            # Own process group only: retire any child left by a failed timed-out test.
            try: os.killpg(process.pid,signal.SIGTERM)
            except ProcessLookupError: pass
        final_peak = size(tmp)
        peak = max(peak,final_peak)
        result = {
            'stage':stage,'argv':cmd,'cwd':str(cwd),'environment':{**environment,'TMPDIR':str(tmp)},
            'exit_code':exit_code,'seconds':round(time.monotonic()-started,3),'log':str(log),
            'peak_temporary_bytes':peak,'resource_stop':stopped,
        }
        if is_tests: result.update(parse_test_log(log,stage))
        result['source_changes'] = changed()
        result['passed'] = exit_code == 0 and not stopped and not result['source_changes'] and (not is_tests or (result['runner_success'] and not result['errors'] and result['tests_failed']==0))
        receipt['stages'].append(result)
        shutil.rmtree(tmp)
        checkpoint()
        print(json.dumps({k:result[k] for k in ['stage','exit_code','seconds','peak_temporary_bytes','passed']} | ({k:result[k] for k in ['tests_passed','tests_failed','tests_skipped']} if is_tests else {})),flush=True)
        return result['passed']

    checkpoint()
    for package in ('quds_office_engine','legacy_doc_parser'):
        if sha(REPO/'packages'/package/'pubspec.yaml') != sha(ROOT/'validation-workspace/packages'/package/'pubspec.yaml'):
            raise SystemExit('Harness manifest differs from frozen source: '+package)
    success = run('engine-analysis',[str(SDK),'analyze','--fatal-infos'],ENGINE)
    release_file = os.environ.get('FINAL_GATE_TEST_RELEASE_FILE')
    if success and release_file:
        receipt['test_resource_release_file'] = release_file
        receipt['waiting_for_other_local_tests'] = True
        checkpoint()
        print(json.dumps({'state':'waiting_for_local_resource_release','file':release_file}),flush=True)
        while not Path(release_file).is_file():
            if changed():
                success = False
                break
            time.sleep(1)
        receipt['waiting_for_other_local_tests'] = False
        checkpoint()
    if success:
        for index,(name,files) in enumerate(BATCHES,1):
            if any(not (ENGINE/path).is_file() for path in files):
                raise SystemExit('Missing selected test file in '+name)
            success = run(f'{index:02d}-{name}',[str(SDK),'test','--concurrency=1','--timeout=4x','--reporter=json',*files],WORK,True)
            if not success: break
    if success:
        success = run('powerpoint-report-example',[str(SDK),'--packages='+str(CONFIG),str(EXAMPLE_CHECK),str(ENGINE/'example/macros/powerpoint_report.bas')],WORK)
        if success:
            receipt['example_check'] = json.loads((out/'powerpoint-report-example.log').read_text())
            checkpoint()
    if success:
        for mode in ('conformance','smoke'):
            success = run('portable-'+mode,[sys.executable,str(PORTABLE),mode,label],ROOT)
            portable_receipt = ROOT/'toolchains/logs'/f'{label}-powerpoint-{mode}-receipt.json'
            if portable_receipt.is_file():
                portable = json.loads(portable_receipt.read_text())
                shutil.copy2(portable_receipt,out/f'portable-{mode}-receipt.json')
                success = success and portable['all_commands_passed'] and portable['vm_js_byte_equal'] and not portable['inputs_changed']
            else: success=False
            if not success: break
    after = manifest()
    (out/'inputs-after.json').write_text(json.dumps(after,indent=2)+'\n')
    receipt['source_changes'] = {k:[before.get(k),after.get(k)] for k in sorted(set(before)|set(after)) if before.get(k)!=after.get(k)}
    receipt['source_head_finish'] = head()
    receipt['finished_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    receipt['all_stages_passed'] = success and not receipt['source_changes']
    cases = [case for stage in receipt['stages'] for case in stage.get('outcomes',[])]
    receipt['totals'] = {
        'executed_test_cases':len(cases),
        'passed':sum(x['outcome']=='success' and not x['skipped'] for x in cases),
        'failed':sum(x['outcome'] not in ('success','skipped') for x in cases),
        'skipped':sum(x['skipped'] for x in cases),
        'unique_case_ids':len({x['id'] for x in cases}),
        'peak_batch_temporary_bytes':max((x['peak_temporary_bytes'] for x in receipt['stages']),default=0),
    }
    checkpoint()
    print(json.dumps({'receipt':str(out/'receipt.json'),'all_stages_passed':receipt['all_stages_passed'],'totals':receipt['totals'],'source_changes':receipt['source_changes']},indent=2),flush=True)
    raise SystemExit(0 if receipt['all_stages_passed'] else 1)

if __name__ == '__main__': main()

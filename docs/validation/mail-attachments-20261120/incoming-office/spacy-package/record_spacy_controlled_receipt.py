#!/usr/bin/env python3
"""Audit the complete package run while retaining its declared optional native skip."""
import gzip,hashlib,json
from pathlib import Path
from urllib.parse import urlparse,unquote
ROOT=Path('/workspace/scratch/75dc9d25dfaf')
OUT=ROOT/'final-validation/spacy-package'
raw_path=OUT/'receipt.json'
r=json.loads(raw_path.read_text())
events=[json.loads(x) for x in gzip.decompress((OUT/'events.jsonl.gz').read_bytes()).decode().splitlines() if x.strip()]
starts={x['test']['id']:x['test'] for x in events if x.get('type')=='testStart'}
suites={x['suite']['id']:x['suite'] for x in events if x.get('type')=='suite'}
skips=[]
for x in events:
 if x.get('type')!='testDone':continue
 t=starts[x['testID']]
 if x.get('skipped') or t.get('metadata',{}).get('skip'):
  skips.append({'suite':suites[t['suiteID']]['path'],'name':t['name'],'reason':t.get('metadata',{}).get('skipReason'),'hidden':bool(x.get('hidden')),'result':x['result']})
expected_name='the qualified macOS library has the recorded code digest'
expected_reason='set QUDS_SPACY_MACOS_LIBRARY to the qualified library'
expected_file=ROOT/'quds_office_suite/packages/quds_proofing_spacy/test/macho_code_identity_test.dart'
def resolved_suite(name):
 uri=urlparse(name)
 if uri.scheme=='file':return Path(unquote(uri.path)).resolve()
 path=Path(name)
 return (path if path.is_absolute() else Path(r['cwd'])/path).resolve()
allowed=len(skips)==1 and skips[0]['name']==expected_name and resolved_suite(skips[0]['suite'])==expected_file and skips[0]['reason']==expected_reason and not skips[0]['hidden'] and skips[0]['result']=='success'
checks={
 'exact_predeclared_optional_skip_only':allowed,
 'all_other_inherited_guards_pass':all(v for k,v in r['guards'].items() if k!='no_failures_skips_or_errors'),
 'raw_process_succeeded':r['exit_code']==0 and not r['timed_out'],
 'no_other_failures_errors_or_diagnostics':not any(r['tests'][k] for k in ['failed','error_events','excluded_failures','parse_errors','missing_start_test_ids','layout_or_tap_diagnostics']),
 'raw_audit_reports_exactly_one_skip':r['tests']['skipped']==1,
 'strict_raw_result_retained':r['status']=='failed' and r['guards']['no_failures_skips_or_errors'] is False,
}
result={'status':'passed_controlled_suite_with_declared_optional_native_skip' if all(checks.values()) else 'failed','passed':r['tests']['passed'],'failed':r['tests']['failed'],'skipped':r['tests']['skipped'],'suites':r['tests']['suite_count'],'skipped_cases':skips,'checks':checks,'raw_receipt_sha256':hashlib.sha256(raw_path.read_bytes()).hexdigest(),'source_head_at_start':r['source_head_at_start'],'source_head_at_finish':r['source_head_at_finish'],'source_fingerprints':r['fingerprints'],'acceptance_scope':'All complete-package controlled cases; the optional real qualified macOS dylib digest check was declared skipped because its artifact path was not supplied. No real macOS native model or installed application qualification is claimed. Original test declarations, process environment and application timeouts were unchanged.'}
(OUT/'controlled-suite-receipt.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print(json.dumps({k:result[k] for k in ['status','passed','failed','skipped','suites','checks']}))
raise SystemExit(0 if all(checks.values()) else 1)

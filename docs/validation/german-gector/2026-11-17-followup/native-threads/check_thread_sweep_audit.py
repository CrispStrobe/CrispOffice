#!/usr/bin/env python3
"""Exercise independent sweep checks against retained data and corruptions.

Reads historical JSON only. Does not load model libraries, compile, or run
inference. The original archived receipt is never changed.
"""
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import tarfile


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.source_root.resolve()
    harness_path = Path(__file__).with_name('run_native_thread_sweep.py')
    harness = module(harness_path, 'thread_sweep')
    comparator_path = root / 'tools/proofing/german_model/compare_guarded_provider.py'
    comparator = module(comparator_path, 'guarded_comparison')
    archive = root / 'docs/validation/german-gector/2026-11-17-resume/final-native-evidence.tar.xz'
    with tarfile.open(archive) as stream:
        original_bytes = stream.extractfile('native/segmented.json').read()
    original = json.loads(original_bytes)
    controls = []

    def check(name, condition):
        controls.append({'name':name, 'passed':bool(condition)})

    baseline_audit = harness.audit_arm_evidence(original, comparator)
    check('unaltered retained segmented evidence passes', baseline_audit['short_sample_count'] == 87 and baseline_audit['complete_source_decoder_records_audited'] == 142 and baseline_audit['additional_control_decoder_counters_audited_without_planning_records'] == 5)
    historical = comparator.compare(comparator.DEFAULT_BASELINE.read_bytes(), original_bytes, comparator.DEFAULT_CASES.read_bytes())
    check('unchanged historical two-thread comparator admits segmented schema', historical['passed'])
    check('only three named timing fields are excluded', harness.TIMING_FIELDS == {'elapsed_ms','timing','inference_microseconds'})

    def varied(report):
        return report['varied_segmented_long_complete_check_probes'][1]

    def mutate_and_reject(name, mutate):
        candidate = copy.deepcopy(original)
        mutate(candidate)
        try:
            harness.audit_arm_evidence(candidate, comparator)
        except (ValueError, comparator.EvidenceError):
            check(name, True)
        else:
            check(name, False)

    def broken_aggregate_stat(report):
        report['warm_checks_up_to_64_wordpieces']['p95_ms'] += 1
    mutate_and_reject('reject changed aggregate p95', broken_aggregate_stat)

    def changed_aggregate_sample(report):
        report['warm_checks_up_to_64_wordpieces']['samples_ms'][0] += 0.0001
    mutate_and_reject('reject aggregate samples not present in input rows', changed_aggregate_sample)

    def wrong_budget(report):
        key='p95_at_most_500_ms';report['engineering_budgets'][key]=not report['engineering_budgets'][key]
    mutate_and_reject('reject inconsistent engineering budget', wrong_budget)

    def wrong_counter(report):
        varied(report)['decoder_samples'][1]['forward_count'] += 1
    mutate_and_reject('reject invented actual forward count', wrong_counter)

    def reconcile(decoded):
        decoded['pass_count']=decoded['forward_count']=len(decoded['passes'])
        decoded['forward_tokens']=decoded['decoded_tokens']=sum(p['tokens'] for p in decoded['passes'])

    def missing_tail(report):
        decoded=varied(report)['decoder_samples'][1]
        last=decoded['passes'][-1]['source_start']
        decoded['passes']=[p for p in decoded['passes'] if p['source_start']!=last]
        reconcile(decoded)
    mutate_and_reject('reject absent final source segment despite self-consistent counters', missing_tail)

    def wrong_tokens(report):
        decoded=varied(report)['decoder_samples'][1]
        decoded['passes'][0]['tokens']-=1
        reconcile(decoded)
    mutate_and_reject('reject changed first-pass tokens despite self-consistent counters', wrong_tokens)

    def wrong_start(report):
        varied(report)['decoder_samples'][1]['passes'][0]['source_start']+=1
    mutate_and_reject('reject actual pass outside original source plan', wrong_start)

    def plan_gap(report):
        varied(report)['initial_segments'][1]['start']+=1
    mutate_and_reject('reject a source partition gap', plan_gap)

    def hidden_reuse(report):
        varied(report)['decoder_samples'][1]['passes'][0]['reused_inference']=True
    mutate_and_reject('reject unexpected reuse in uncached sweep', hidden_reuse)

    def wrong_diversity(report):
        varied(report)['initial_distinct_model_inputs']+=1
    mutate_and_reject('reject invented initial-input diversity', wrong_diversity)

    def first_sample_drift(report):
        varied(report)['decoder_samples'][0]['passes'][0]['prediction_input_sha256']='0'*64
    mutate_and_reject('reject first-result and first-sample diagnostic disagreement', first_sample_drift)

    row=copy.deepcopy(varied(original))
    changed=copy.deepcopy(row)
    changed['elapsed_ms']+=123
    changed['timing']['median_ms']+=123
    changed['decoder_samples'][1]['inference_microseconds']+=123
    check('semantic comparison excludes only measured time differences', harness.semantics(row)==harness.semantics(changed))
    for field,value in [('corrected','Different text.'),('status','failed'),('source_coverage_complete',False)]:
        changed=copy.deepcopy(row);changed[field]=value
        check('semantic comparison retains '+field,harness.semantics(row)!=harness.semantics(changed))
    changed=copy.deepcopy(row);changed['decoder_observation_samples'][1]['worker_result_received']=False
    check('semantic comparison retains actual worker observations',harness.semantics(row)!=harness.semantics(changed))
    changed=copy.deepcopy(row);changed['decoder_samples'][1]['forward_tokens']+=1
    check('semantic comparison retains all timed-sample decoder work',harness.semantics(row)!=harness.semantics(changed))
    changed=copy.deepcopy(row);changed['initial_segments'][0]['end']-=1
    check('semantic comparison retains every planned source span',harness.semantics(row)!=harness.semantics(changed))
    with_findings=next(r for r in original['cases'] if r['findings'])
    changed=copy.deepcopy(with_findings);changed['findings'][0]['replacement']='other'
    check('semantic comparison retains linguistic finding replacements',harness.semantics(with_findings)!=harness.semantics(changed))
    check('all retained cohorts participate',set(harness.COHORTS)=={'cases','controls','long_complete_check_probes','segmented_long_complete_check_probes','varied_segmented_long_complete_check_probes','segmentation_controls'})
    report={
        'schema_version':1,'kind':'thread-sweep-independent-audit-controls',
        'observed_utc':datetime.now(timezone.utc).isoformat(),
        'harness_sha256':hashlib.sha256(harness_path.read_bytes()).hexdigest(),
        'comparator_sha256':hashlib.sha256(comparator_path.read_bytes()).hexdigest(),
        'source_archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
        'retained_receipt_sha256':hashlib.sha256(original_bytes).hexdigest(),
        'retained_receipt_audit':baseline_audit,
        'controls':controls,'passed':all(r['passed'] for r in controls),
        'native_inference_or_compilation_executed':False,
        'qualification_scope':'Controls of evidence reconstruction only. Current-source linguistic results remain unmeasured until the actual native sweep.',
    }
    with args.output.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
    print(json.dumps({'passed':report['passed'],'controls':len(controls),'failed':[r['name'] for r in controls if not r['passed']]}))
    return 0 if report['passed'] else 1


if __name__=='__main__':
    raise SystemExit(main())

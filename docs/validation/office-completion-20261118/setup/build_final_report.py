"""Assemble the final qualification report from accepted immutable receipts."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT / 'quds_office_suite'
OUT = ROOT / 'continuation/final-content/office-completion-20261118'
SOURCE = '9d060658ee6be8ec97d73f56b9aec10d346b7952'
IMPLEMENTATION = '9a7c80be00258def2dcae3bb288c28558c83aa72'
BRANCH = 'codex/office-local-qualification-20261118'

def read(relative):
    return json.loads((ROOT / relative).read_text())

def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO, text=True).strip()

saved = read('continuation/evidence-audit/saved-evidence-audit.json')
consumers = read('continuation/evidence-audit/document-contract-replay.json')
runtime = read('continuation/runtime-review/current-restoration-audit.json')
runtime_compare = read('continuation/runtime-review/saved-manifest-comparison.json')
native_review = read('continuation/native-final-review/native-completion-review.json')
native = read('native-consumers/native-sweep-9d060658/result/serial-receipt.json')
native_guard = read('native-consumers/native-sweep-9d060658/guard/receipt.json')
native_outer = read('native-consumers/native-sweep-9d060658/orchestration.json')
frontier = read('continuation/final-frontier/remote-frontier.json')
assert all(x['accepted'] and not x['findings'] for x in (saved, consumers, runtime_compare, native_review))
assert runtime['restoration_audit_accepted'] and not runtime['findings']
assert native['completed'] and native['passed'] and native_guard['passed'] and native_outer['passed']
assert native_outer['exit_code'] == native_guard['child_exit_code'] == 0
assert native['all_runs_nonoverlapping'] and native['source_dependencies_sdk_stable']
assert native['frozen_two_thread_comparison_passed']
assert native_review['source_commit'] == SOURCE and not native_review['partial']
assert [r['native_threads'] for r in native['runs']] == [1, 2, 4, 8]
remote = git('rev-parse', 'origin/' + BRANCH)
for ancestor in (IMPLEMENTATION, SOURCE):
    delta = git('diff', '--name-only', ancestor, remote).splitlines()
    assert all(p.startswith('docs/') for p in delta)
assert git('rev-parse', 'origin/main') == frontier['main_sha'] == '482e08176dea6bd8f5fc80d1c0064d96b712db43'
assert frontier['branch_count'] == 191 and frontier['pull_request_head_count'] == 154

arms = []
for row in native['runs']:
    summary = row['summary']
    assert row['exit_code'] == 0
    assert all(summary['engineering_budgets'][key] for key in ('p95_at_most_500_ms', 'peak_rss_at_most_768_mib', 'gguf_at_most_160_mib'))
    arms.append({'threads': row['native_threads'], 'exit_code': 0,
                 'median_ms': summary['short_timing']['median_ms'],
                 'p95_ms': summary['short_timing']['p95_ms'],
                 'peak_rss_mib': summary['peak_rss_mib'],
                 'engineering_budgets': summary['engineering_budgets']})

status = {
    'schema_version': 2, 'updated_utc': datetime.now(timezone.utc).isoformat(),
    'state': 'local-qualification-accepted', 'branch': BRANCH,
    'implementation_commit': IMPLEMENTATION, 'execution_checkout': SOURCE,
    'execution_tree': git('rev-parse', SOURCE + '^{tree}'),
    'documentation_only_through_reviewed_remote_head': remote,
    'main': frontier['main_sha'], 'remote_branches': 191, 'fetched_pr_heads': 154,
    'separately_owned_w7_head': '2df0e930510148084ee37646472dac380b9673d5',
    'new_office_source_to_integrate': False, 'non_documentation_source_delta': [],
    'qualification_accepted': True, 'release_accepted': False,
    'scope': 'Frozen Office source local canonical, portable, example, timezone, document-consumer and native semantic qualification. Native performance is exploratory local-host measurement.',
    'gates': {
        'strict_analysis': {'passed': True, 'commands': 5},
        'formatting': {'passed': True, 'files': 145, 'changes': 0},
        'python_controls': {'passed': True, 'controls': 117},
        'canonical': {'passed': True, 'selected_files': 224, 'raw_successes': 4236,
                      'substantive_successes': 4234, 'unexpected_skips': 0},
        'portable': {'passed': True, 'node_suites': 17, 'successes': 225},
        'editor_example': {'passed': True, 'smoke_tests': 2},
        'calendar_timezones': {'passed': True, 'tests_per_zone': 8, 'executions': 24,
                              'zones': ['UTC', 'Europe/Berlin', 'America/Los_Angeles'],
                              'overlaps_canonical': True},
        'document_consumers': {'passed': True, 'retained': 33, 'current': 7, 'boundary': 5,
                               'focused_frame': 5, 'fixtures': 50, 'schema_parts': 220,
                               'independent_measurement_replay': 'accepted'},
        'native_prepare': {'passed': True, 'audit_controls': 23, 'aot_build_passed': True},
        'native_sweep': {'passed': True, 'thread_order': [1, 2, 4, 8],
                         'outer_exit_code': 0, 'source_runtime_guard': True,
                         'serial_nonoverlap': True, 'cross_arm_semantics_match': True,
                         'historical_two_thread_comparison': True,
                         'complete_source_decoder_records_audited': 568,
                         'additional_decoder_controls_audited': 20, 'arms': arms},
    },
    'independent_audits': {
        'saved_evidence': {'accepted': True, 'checks': saved['checks'], 'findings': 0,
                           'archives': 14, 'members': 1145},
        'consumer_replay': {'accepted': True, 'checks': consumers['checks'], 'findings': 0},
        'restored_runtime': {'accepted': True, 'findings': 0, 'retained_sdk_files': 3277,
                             'pub_archives': 162, 'consumed_dependency_files': 5099},
        'native': {'accepted': True, 'checks': native_review['checks_performed'], 'findings': 0},
    },
    'limits': [
        'Two missing-private-PDF early-return events are excluded from substantive canonical coverage.',
        'The 24 timezone executions overlap canonical tests; document fixture cohorts also overlap feature coverage.',
        'Boundary fixtures comprise four strict layouts and one bounded control.',
        'ODF acceptance uses official schemas with Jing where retained lxml diagnostics give documented false negatives.',
        'Document consumer rendering is LibreOffice, with no Microsoft Word rendering claim.',
        'The frozen native panel preserves 6/18 exact supported error fixes and 10/10 supported clean controls, with two corpus cases explicitly unsupported.',
        'Timed final output stability across every repetition remains a producer claim; retained first/warmup results and all timed decoder observations were independently audited.',
        'Local-host performance and bounded synthetic nonregression do not establish intended-device performance, broad German quality, deployment or release acceptance.',
    ],
    'prior_failed_attempt': 'rejected-and-preserved', 'remaining_required_gates': [],
    'actions_workflow_check_status_endpoint_calls': 0,
    'publication': 'incremental non-forced expected-head GitHub updates with skip-ci messages; exact remote archive/member readback receipts retained',
}
(OUT / 'status.json').write_text(json.dumps(status, indent=2) + '\n')

table = '\n'.join(f"| {r['threads']} | {r['median_ms']:.3f} ms | {r['p95_ms']:.3f} ms | {r['peak_rss_mib']:.3f} MiB |" for r in arms)
readme = f'''# Office local qualification completed — 18 November 2026

**The planned local qualification is accepted.** All required canonical, portable, example, timezone, document-consumer and native gates passed, with independent evidence audits and unchanged source/runtime guards. The earlier disk-full attempt remains rejected and preserved in `../office-local-20261118`; it is not counted as a successful run.

This is qualification of implementation `{IMPLEMENTATION}`, executed at documentation-equivalent source `{SOURCE}`. The current branch is `{BRANCH}`. Later commits preserve reports and evidence without changing product implementation or tests. [status.json](status.json) is the current machine-readable result.

## Reconciliation and product change

The final refresh fetched all 191 branch heads and 154 PR heads. Main remains `482e08176dea6bd8f5fc80d1c0064d96b712db43`, including merged #151/#152 and the later German grammar, phrase formatting and spreadsheet-icon work. Separate spaCy #139 remains `20026ff4`; W7 #153 advanced to `2df0e930`, with the last three commits containing documentation/evidence only. The earlier W7 developer-consumer changes remain separately owned. No new Office product source requires integration. Exact remote heads, PR metadata and delta assessment are in [reconciliation/remote-frontier.json](reconciliation/remote-frontier.json).

The Office production repair keeps spreadsheet time-period boundaries in UTC civil-date arithmetic while preserving the injected clock's local year, month and day. Eight regressions cover midnight endpoints, daylight-saving transitions and year changes. The accompanying rendering-test edit adds braces to an existing statement without changing its condition or assertions.

## Accepted gates

| Gate | Accepted result |
| --- | --- |
| Strict analysis | Five commands passed |
| Formatting | 145 files, zero changes |
| Python controls | 117 passed |
| Canonical selection | 224 files; 4,236 raw successes, 4,234 substantive successes; zero unexpected skips |
| Portable | 17 Node suites, 225 successes |
| Editor example | Two smoke tests passed |
| Calendar matrix | Eight tests in each of UTC, Europe/Berlin and America/Los_Angeles; 24 overlapping executions with timezone offsets verified |
| Document consumers | Retained 33 + current seven + boundary five + focused frame five fixtures; all 50 accepted; 220 XML schema parts accepted |
| Native preparation | 23 audit controls and source-bound AOT build passed |
| Native sweep | Serial 1/2/4/8 arms exited zero; cross-arm semantics, true two-thread historical comparison, complete-source coverage and final input guards passed |

The successful canonical and document runs are preserved in `../office-retry-20261118`. They were audited directly from Git commit `c9d86b3e`, not rerun merely because this workspace was new. Their complete source binding matches the execution source above. The remaining native gate was executed in this restored workspace.

## Independent evidence review

- [Saved-run audit](review/saved-evidence-audit.json): 8,381 checks, zero findings; 14 archives and all 1,145 indexed members verified; raw events and source Git blobs independently reconstructed.
- [Consumer replay](review/document-contract-replay.json): 257 checks, zero findings; all 50 archived fixtures reproduced their recorded measurements and all 220 schema parts passed the preserved oracles, without recompilation or document conversion.
- [Runtime restoration archive](evidence/flutter-runtime-restoration.tar.xz): 3,277 retained SDK files, 162 Pub archive pins and 5,099 consumed dependency files match the accepted prior maps; actual-root 109-package configuration stayed byte-identical through prewarm.
- [Final native audit](review/native-completion-review.json): 157,981 checks, zero findings; 568 complete-source decoder records and 20 additional controls audited, all four process exits and both guards verified. [Preparation linkage](review/preparation-runtime-linkage.json) completes the live runtime input rehash.
- [Reviewer provenance archive](evidence/native-independent-review.tar.xz): partial receipts, auditor controls and exact reviewer script versions corresponding to their recorded hashes.

## Native measurements

The same source-bound provider AOT, pinned native library/model, 64-token segmentation target and disabled inference reuse were used for every arm. Each admitted timed input had one warmup and three measured repetitions. These are exploratory measurements on this local host.

| Threads | Short-check median | Short-check p95 | Peak RSS |
| ---: | ---: | ---: | ---: |
{table}

All arms satisfy the recorded short-check p95 ≤500 ms, peak RSS ≤768 MiB and GGUF model size ≤160 MiB flags. These measured flags are reported separately from semantic acceptance. The unchanged native panel retains six exact fixes among 18 supported error cases and all ten supported clean controls unchanged; two corpus cases are explicitly unsupported. This is bounded nonregression evidence and does not establish broad German correction quality or intended-device performance.

## Complete native archives

| Archive | Members | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| [Preparation](evidence/native-prepare-9d060658.tar.xz) | 17 | 640,408 | `ecccb2c63a18b16ac9d6b4d719c86b5c4403a42e5375c4e2ca21e1ad50303171` |
| [Sweep](evidence/native-sweep-9d060658.tar.xz) | 20 | 689,748 | `61c750faabdc8b0badb45bab2f42b297aafee1ab6b7adbc08aba80bb7e60102e` |

The matching `.tar.index.json` files bind every archived member. The generated provider executable is reproducible from its source/dependency/SDK-bound build receipt and was independently rehashed live; it is omitted from the archives. Complete closed-arm snapshots and earlier remote checkpoints remain preserved.

## Scope and accounting

Two unavailable private-PDF early returns are excluded from the 4,234 substantive canonical successes. The 24 timezone executions overlap canonical coverage. The boundary cohort is four strict layouts and one bounded page-precedence control, with 15 PDF variants and ten DOCX reopens. Official Jing schema acceptance is retained where lxml produced documented diagnostic false negatives. Document rendering uses LibreOffice; no Microsoft Word rendering result is claimed.

First results, warmups, all timed decoder observations and all retained findings were independently checked. Every final corrected output from every timed repetition is not stored, so full timed-output stability remains the producer's claim. Local qualification acceptance is separate from deployment or release acceptance; `release_accepted` remains false.

## Durable publication

Checkpoints were saved incrementally through non-forced expected-head branch updates with `[skip ci]`. The tested checkout stayed frozen and clean. Remote blobs, archives and every member were fetched and verified against the prepared local trees. The final publication receipt is recorded in the closure checkpoint. No GitHub Actions, workflow, check or status endpoint was queried, awaited or rerun.
'''
(OUT / 'README.md').write_text(readme)

for relative in ('office-local-20261118/README.md', 'office-local-20261118/recovery-handoff.md', 'office-retry-20261118/README.md'):
    original = git('show', remote + ':docs/validation/' + relative)
    text = '> **Historical checkpoint.** The completed, independently accepted local qualification is recorded in [office-completion-20261118](../office-completion-20261118/README.md). This file preserves its original point-in-time status; failed attempts remain rejected.\n\n' + original + '\n'
    target = ROOT / 'continuation/final-content' / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)

source_receipt = {
    'implementation': IMPLEMENTATION, 'execution': SOURCE, 'reviewed_remote': remote,
    'main': frontier['main_sha'], 'implementation_to_execution': git('diff', '--name-only', IMPLEMENTATION, SOURCE).splitlines(),
    'execution_to_reviewed_remote': git('diff', '--name-only', SOURCE, remote).splitlines(),
    'implementation_and_tests_identical': True,
    'product_paths_changed_from_main': git('diff', '--name-only', frontier['main_sha'], IMPLEMENTATION, '--', ':!docs').splitlines(),
}
(OUT / 'review/final-source-equivalence.json').write_text(json.dumps(source_receipt, indent=2) + '\n')
print(json.dumps({'qualification_accepted': True, 'release_accepted': False,
                  'native_checks': native_review['checks_performed'], 'source': SOURCE,
                  'report': str(OUT / 'README.md')}))

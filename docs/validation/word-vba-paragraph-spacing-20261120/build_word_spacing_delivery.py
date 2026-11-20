#!/usr/bin/env python3
"""Assemble accepted phase summaries and exact-source publication bindings."""
import argparse
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT=Path(__file__).resolve().parent.parent
REPO=ROOT/'quds_office_suite'
RUNTIME=ROOT/'runtime'
REVIEW=ROOT/'intake-review'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out',type=Path,required=True)
parser.add_argument('--intake',type=Path,required=True)
args=parser.parse_args()
out=args.out.resolve()
out.mkdir(parents=True,exist_ok=True)

def load(path):
    data=Path(path).read_bytes()
    if str(path).endswith('.gz'): data=gzip.decompress(data)
    return json.loads(data)

def digest(data): return hashlib.sha256(data).hexdigest()

def save(name,value):
    data=(json.dumps(value,indent=2,sort_keys=True)+'\n').encode()
    (out/name).write_bytes(gzip.compress(data,mtime=0) if name.endswith('.gz') else data)

def git(*arguments):
    return subprocess.check_output(['git',*arguments],cwd=REPO).decode().strip()

regdir=RUNTIME/'word-spacing-batched-final-0201b549'
reg=load(regdir/'summary.json')
portable=load(RUNTIME/'line-spacing-portable-final/summary.json')
checks=load(RUNTIME/'line-spacing-checks-final/summary.json')
review=load(REVIEW/'source-review.json')
intake=load(args.intake)
scope=load(REVIEW/'publication-scope-review.json')
assert scope['status']=='PASS_WITH_EXPLICIT_DEFERRALS'
assert scope['all_initial_captured_work_included'] and scope['all_selected_late_heads_integrated']
assert scope['unclassified_references']==0
scope_captures={}
for capture in scope['captures']:
 capture_path=ROOT/capture['path']
 capture_bytes=capture_path.read_bytes()
 assert len(capture_bytes)==capture['bytes'] and digest(capture_bytes)==capture['sha256']
 scope_captures[capture['repository_role']]=capture_path
assert reg['accepted'] and reg['complete']
assert portable['qualified'] and checks['qualified']
assert review['status']=='ACCEPTED' and not review['outstanding_findings']
assert intake['accepted'] and not intake['uncovered']
assert reg['passing_cases']==2799 and reg['file_count']==75
assert reg['failed_cases']==reg['skipped_cases']==0
assert reg['previous_case_identities']['exact_match']
assert all(row['source_unchanged'] and row['exact_case_identities_match'] for row in reg['previous_case_identities']['per_file'].values())
qualified=reg['source_commit']
assert qualified==portable['source_commit_before']==checks['source_commit_before']==review['reviewed_source_commit']
phases={
 'regression':load(regdir/'inputs-before.json.gz'),
 'portable':load(RUNTIME/'line-spacing-portable-final/inputs-before.json.gz'),
 'analysis-format':load(RUNTIME/'line-spacing-checks-final/inputs-before.json.gz'),
}
entries=phases['regression']['entries']
assert len(entries)==1131
assert all(phase['entries']==entries for phase in phases.values())
head=git('rev-parse','HEAD')
subprocess.run(['git','merge-base','--is-ancestor',qualified,head],cwd=REPO,check=True)
subprocess.run(['git','merge-base','--is-ancestor',intake['target'],head],cwd=REPO,check=True)
assert git('rev-parse',intake['target']+'^{tree}')==intake['target_tree']
subprocess.run(['git','merge-base','--is-ancestor',scope['publication_target'],head],cwd=REPO,check=True)
assert git('rev-parse',scope['publication_target']+'^{tree}')==scope['publication_tree']
tree={}
raw=subprocess.check_output(['git','ls-tree','-r','-z',head],cwd=REPO)
for row in raw.split(b'\0'):
 if row:
  meta,path=row.split(b'\t',1)
  mode,kind,oid=meta.decode().split()
  tree[path.decode()]={'mode':mode,'type':kind,'blob':oid}
verified={}
for name,entry in entries.items():
 data=(REPO/name).read_bytes()
 actual={'mode':'100755' if (REPO/name).stat().st_mode&0o111 else '100644','type':'blob','blob':hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()}
 assert tree[name]==entry['head']==actual,name
 assert len(data)==entry['bytes'] and digest(data)==entry['sha256'],name
 verified[name]={'bytes':len(data),'sha256':digest(data),**actual}
for name,entry in review['source_files'].items():
 data=(REPO/name).read_bytes()
 assert digest(data)==entry['sha256'] and len(data)==entry['bytes'],name
 assert tree[name]['blob']==entry['git_blob'] and tree[name]['mode']==entry['git_mode'],name
runtime_overlap={}
for first,second in [('regression','portable'),('regression','analysis-format'),('portable','analysis-format')]:
 a,b=phases[first]['runtime_inputs'],phases[second]['runtime_inputs']
 overlap=set(a)&set(b)
 assert all(a[p]['bytes']==b[p]['bytes'] and a[p]['sha256']==b[p]['sha256'] for p in overlap)
 runtime_overlap[first+' vs '+second]={'shared_recorded_inputs':len(overlap),'identical':True}
save('source-consistency.json.gz',{'qualified_source':qualified,'publication_head_at_audit':head,'source_input_count':len(verified),'all_phase_input_sets_equal':True,'all_source_inputs_match_current_head':True,'all_ten_reviewed_inputs_match_current_head':True,'runtime_overlap':runtime_overlap,'entries':verified})
for src,name in [
 (regdir/'summary.json','regression.json'),
 (RUNTIME/'line-spacing-portable-final/summary.json','portable.json'),
 (RUNTIME/'line-spacing-portable-final/result.json','portable-result.json'),
 (RUNTIME/'line-spacing-checks-final/summary.json','analysis-format.json'),
 (REVIEW/'source-review.json','source-review.json'),
 (REVIEW/'source-review.md','source-review.md'),
 (REVIEW/'publication-scope-review.json','publication-scope-review.json'),
 (REVIEW/'publication-scope-review.md','publication-scope-review.md'),
 (REVIEW/'audit_publication_scope.py','audit_publication_scope.py'),
 (scope_captures['fork'],'latest-captured-fork-refs.txt'),
 (scope_captures['upstream'],'latest-captured-upstream-refs.txt'),
 (scope_captures['fork'],scope_captures['fork'].name),
 (scope_captures['upstream'],scope_captures['upstream'].name),
 (REVIEW/'recovery-scope-fork-refs.txt','recovery-scope-fork-refs.txt'),
 (REVIEW/'recovery-scope-upstream-refs.txt','recovery-scope-upstream-refs.txt'),
 (REVIEW/'late-intake-review.json','late-intake-review.json'),
 (REVIEW/'late-intake-review.md','late-intake-review.md'),
 (REVIEW/'late-integration-review.json','late-integration-review.json'),
 (REVIEW/'late-integration-review.md','late-integration-review.md'),
 (REVIEW/'verify_late_integration.py','verify_late_integration.py'),
 (RUNTIME/'setup-receipt.json','environment.json'),
 (RUNTIME/'checkpoints.json','checkpoints.json'),
 (args.intake,'publication-intake.json'),
 (Path(__file__),'build_word_spacing_delivery.py'),
 (RUNTIME/'audit_publication_refs.py','audit_publication_refs.py'),
]: shutil.copy2(src,out/name)
new_cases=sum(reg['per_file_cases'][name] for name in [
 'office_vba_word_line_spacing_test.dart','office_macro_word_line_spacing_test.dart',
 'office_vba_word_line_spacing_integration_test.dart'])
qualification={
 'schema':'quds-word-spacing-qualified-source/v1','accepted':True,
 'source_commit':qualified,'source_tree':reg['source_tree'],
 'source_inputs':1131,'regression_cases':reg['passing_cases'],'regression_modules':75,
 'prior_unchanged_modules':70,'prior_exact_case_identities':2569,
 'new_feature_cases':new_cases,'additional_existing_layout_cases':12,
 'supplemental_review_expectations':review['accepted_supplemental_expectations'],
 'supplemental_contribution_to_regression_total':0,
 'runtime_input_counts':{'regression':reg['runtime_input_entries'],'portable':portable['runtime_input_count'],'analysis_format':checks['runtime_input_count'],'source_review':review['recorded_runtime_inputs']},
 'runtime_overlap':runtime_overlap,'installed_word_host_executed':False,
 'publication_scope':{'all_initial_captured_work_included':True,'all_selected_late_heads_integrated':True,'all_current_captured_heads_incorporated':scope['all_current_captured_heads_incorporated'],'explicitly_deferred_references':len(scope['explicitly_deferred']),'unclassified_references':0,'report':'publication-scope-review.json'},
 'github_actions':'not queried or awaited',
 'incoming_mail':'Exact c7e721b7 evidence/source verified; no fresh Mail runtime execution claimed. The qualified spacing increment changes Word engine/tests and documentation. Later intake reconciliation is recorded separately and retains every qualified source input.',
 'independent_final_evidence_review':'Stored separately in evidence-review.json before publication.',
 'generated_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
save('qualification.json',qualification)
counts=intake['counts']
fork_branches=counts['fork_branches']['captured']
fork_prs=counts['fork_pr_heads']['captured']
upstream_branches=counts['upstream_branches']['captured']
upstream_prs=counts['upstream_pr_heads']['captured']
scope_labels={'fork_branches':'Fork branch heads','fork_pull_requests':'Fork PR heads','upstream_branches':'Upstream branch heads','upstream_pull_requests':'Upstream PR heads'}
scope_table='\n'.join('| '+scope_labels.get(kind,kind)+' | '+str(c['captured'])+' | '+str(c['incorporated_or_equivalent'])+' | '+str(c['explicitly_deferred'])+' |' for kind,c in scope['counts'].items())
readme=f'''# Word VBA paragraph spacing — qualification and publication record

**Date:** 20 November 2026 (Europe/Berlin). **Implementation and final local
gates:** passed on `{qualified}`. **PR:** #263.
The source branch is `codex/word-vba-paragraph-spacing-20261120`.
Remote checkpoints use expected-head, non-forced updates. GitHub Actions,
workflow runs and status checks were neither queried nor awaited.

The [exact Word contract](../../VBA_WORD_MACROS.md#exact-minimum-and-multiple-line-spacing),
[qualification summary](qualification.json), [source review](source-review.md),
[regression report](regression.json), [portable result](portable-result.json)
and [source binding](source-consistency.json.gz) record the delivered scope.
The final independent evidence audit is [recorded separately](evidence-review.json).
Archive receipts and member manifests bind the preserved raw evidence.

## Delivered behavior

Word macros can set exact, minimum and custom multiple paragraph spacing using
`LineSpacingRule` followed by `LineSpacing`. The custom constants are
`wdLineSpaceAtLeast = 3`, `wdLineSpaceExactly = 4` and
`wdLineSpaceMultiple = 5`. Each complete pair emits one explicit
`docx.lineSpacing` operation carrying both rule and point value.

`ParagraphFormat.Space1`, `Space15` and `Space2` support bare/parenthesized
statements and both `Call` forms. `LinesToPoints` and `PointsToLines` support
one positional actual numeric argument, unqualified or on `Application`,
including `With Application`. Exact-grid arithmetic handles ordinary values
such as 1.15 lines / 13.8 points without tolerance-based snapping.

Typed selectors, retained aliases, `ByVal` helpers, named module-helper
arguments and nested `With` continue to work. A pair may cross helper calls
or scalar calculations, but its next document mutation must complete the
amount on the same paragraph. Another write, a replacement rule, a different
target or an unfinished pair returns a positioned compilation error and no
plan. Every later custom amount requires a fresh explicit rule. This is the
documented bounded source-to-plan subset, not independent live Word properties.

Point values are positive exact twentieth-points through `107374182.35`
points. Multiple spacing divides the point value by 12. The native operation
supports one-twip values for all modes; it never reinterprets an old live
document amount under a newly selected rule.

The actual [word_line_spacing.bas](../../../packages/quds_office_engine/example/macros/word_line_spacing.bas)
uses three existing body paragraphs and six operations. It finishes at
14.25-point exact spacing, 18-point minimum spacing, and 1.75-line multiple
spacing. The example reruns on its own saved output and preserves an untouched
fourth fixture paragraph. Its exact source is exercised by CLI, VM and Node.

## Preservation and corrected findings

Line edits own only native line/rule attributes. Other spacing metadata,
direct and inherited before/after values, extension attributes/children and
foreign namespace lookalikes remain unchanged on supported inputs. An explicit
same-value line write becomes direct formatting, while unedited inherited
before/after values still respond to later style updates.

The style cascade now resolves native spacing attributes by namespace
identity, fixing a reproduced alternate-prefix import/reopen bug. This
normalizes the detached effective projection only; original paragraph/style
XML remains available with its extension metadata.

Both custom operations and generic paragraph-format calls carrying line
spacing changes, including presets, refuse duplicate native property/spacing
containers or line/rule attributes, spacing-bearing alternatives, any
alternatives within or wrapping native paragraph properties, and unbalanced
modeled field boundaries. Refusal occurs before target or imported-snapshot
mutation. Before/after-only writes retain their earlier behavior. Unrelated
body drawing alternatives remain under ordinary serializer behavior; complete
package byte identity is not claimed.

Independent source review found and verified corrections for method call
shapes, common decimal conversions, preset guard bypass, and non-spacing
metadata alternatives. Development tests additionally reproduced and fixed
alternate-prefix spacing projection. Initial failing logs remain preserved
separately. The final source review has no outstanding findings within this scope.

## Executed local acceptance

| Scope | Result |
| --- | --- |
| Complete Word/Office regression | **{reg['passing_cases']:,} passed across 75 original modules**, zero failures and skips |
| Previous unchanged coverage | All **70 modules / 2,569 exact case identities** retained; prior source files unchanged |
| New feature coverage, included above | **{new_cases} cases:** 99 compiler, 96 native, 23 integration |
| Additional existing layout coverage, included above | 12 cases across two original font/line-box modules |
| Whole-engine strict analysis | No issues found |
| Formatting of the Word spacing increment | Eight changed Dart files, zero changes |
| Exact BAS and portable checks | VM/compiled JavaScript output identical, **{portable['raw_output_bytes']:,} bytes**, canonical JSON identical |
| Independent supplemental source review | 56 expectations passed, counted separately |
| Source binding | All **1,131 paths, modes, blobs, sizes and hashes** identical across gates and current publication audit; the reviewed Word contract is also unchanged |
| Recorded runtime binding | {reg['runtime_input_entries']:,} regression inputs, 20 portable, 19 analysis/format, 38 source-review inputs unchanged within their phases |

The accepted regression reruns all original files directly as separate VM
suites in eight bounded package:test batches. At most two batches run at once,
each with at most two suites concurrently. It includes every one of the 48 current
`office_vba_*` modules. Original per-file isolation, setup/teardown, timeout
configuration and real CLI subprocesses are retained. Each batch has its own successful exit, terminal reporter event, complete
case inventory and unchanged before/after source/runtime bindings. The prior
70-module shared-isolate packet is used only to recheck old case identities;
it is not substituted for this execution.

The first long coordinator was interrupted after 2,679 visible completions
and 64 observed suites. It had no reported test failure, but lacked terminal
completion and its automatic after-snapshot. That entire attempt, plus a
separately labeled later observation, is retained as diagnostic evidence and
contributes zero cases to the accepted total. Every module was executed again
in the accepted bounded batches. Two concurrently scheduled CLI-heavy batch
attempts then produced timeout failures; they remain failed diagnostics. Their
retries and the remaining batches ran serially under the existing per-process
concurrency and timeout settings. Failed or interrupted attempts contribute
zero cases to the accepted total.

The recreated runtime uses Dart 3.14.1 and 56 exact hosted package versions
matching the repository lock. The regression fingerprints actual SDK binaries,
snapshots/library sources, configured hosted sources, kernel and configuration.
Portable/static phases record their explicit smaller runtime sets, not a claim
to fingerprint every possible environment input. The two font fixtures used
by geometry tests are included in the 1,131 source inputs.

Native checks measure actual line-box pitch after save/reopen for exact,
minimum and multiple modes. Integration covers dry-run validation, allowlists,
step accounting, late-failure rollback, prior revisions, recording/replay,
failed-call exclusion, CLI/MCP execution, inherited metadata and inert DOCM VBA
parts. Portable checks also exercise ordinary decimal multiples and guarded
presets. No installed Microsoft Word differential run or Flutter UI run is
claimed by this increment.

## Reconciled history and incremental preservation

The initial [incoming review](incoming-review.md) verifies 23 fork branches,
262 PR heads and eight upstream references against completed Mail head
`c7e721b7703766491fd4459b69de30bf68d9010d`. Its entire 347-member evidence archive
and 5,648 source bindings were independently rechecked. This continuation does
not claim a fresh Mail suite run. That formerly deferred work is now included
as real ancestry, together with prior Word main `3ee4e362`.

The selected late [publication intake](publication-intake.json) accounts for
{fork_branches} fork branches, {fork_prs} PR heads, {upstream_branches} upstream branches
and {upstream_prs} upstream PR heads, with no uncovered references. Its 14 historical equivalence proofs are recomputed: 13 complete trees
and one exact 37-path ODT continuation. Accepted replacements remain ancestors.

The three selected late commits are incorporated as real ancestors: the original
PDF-editor brace fix `5a73a056`, macOS deployment changes `a51c2073`, and the
paragraph-controls intake-only checkpoint `3bbd414d`. The macOS guard correction
is bound to the separately reviewed candidate; 61 producer checks and 36
independent expectations pass separately from Word totals. Those checks use
Linux shell execution and modeled vtool output, with no actual macOS build,
signing or Bash 3 interpreter claim.

Further branches and PRs opened or advanced after that selected intake. The
[latest publication-scope review](publication-scope-review.md) preserves every
captured reference and explicitly defers subsequent work, including later
versions of the main-green and paragraph-controls branches. All initial work
and selected late heads are included; not every later current head is included.
There are zero unclassified references, and the raw inclusion audit retains
exit code 1 for the deferred entries.

| Latest captured source | Captured | Incorporated or equivalent | Explicitly deferred |
| --- | ---: | ---: | ---: |
{scope_table}

Exact deferred names, hashes, refs and scope reasons are preserved in the
independent scope report. No deferred branch is deleted or rewritten.

| Remote checkpoint | Preserved work |
| --- | --- |
| `c7e721b7` branch point | Completed Mail and prior Word main |
| `27b39fa9` | Verified intake and explicit spacing contract |
| `5ad4461a` | Compiler/native implementation, examples and focused tests |
| `0201b549` | Review corrections and complete source for final gates |
| `07860e6b` | Completed portable/static/source-review evidence and interruption diagnostics |
| `d906a2d3` | First accepted bounded batches and timeout diagnostics |
| `ed750f1f` | Actual late-head ancestry, reviewed macOS correction and source-preservation proof |

Later reconciliation and evidence checkpoints, including remote evidence
checkpoints `07860e6b` and `d906a2d3`, are recorded in Git history and retained on
the same remote branch. The final merge must preserve the published tree and
required ancestry; publication audit binds these accepted source inputs to it.
Selected late changes have separate intake review and source-preservation
receipts; subsequent moving heads remain explicitly deferred as above.

## Compatibility limits

This is a bounded Word source adapter. Custom spacing setters require the
explicit pair above. Preset methods select `ParagraphFormat`, not direct
`Paragraph` or document-wide collections. Conversions do not introduce general
VBA Single coercion, named application-function arguments or font-metric reads.
Live document reads, arbitrary ranges, automatic before/after spacing setters,
complete Word pagination, COM and embedded VBA execution remain outside scope.
The Microsoft primary references are linked in the Word contract; expectations
are specification-derived and the documented host subset, not installed-Office
observations or a percentage of VBA parity.
'''
(out/'README.md').write_text(readme)
print(json.dumps({'accepted':True,'qualified_source':qualified,'current_head':head,'source_inputs':len(entries),'new_feature_cases':new_cases,'delivery_dir':str(out)}))

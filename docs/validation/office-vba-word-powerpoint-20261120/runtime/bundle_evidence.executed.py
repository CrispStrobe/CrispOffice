"""Bundle successful local qualification into the repository's validation record."""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import shutil
import subprocess

ROOT = Path('/workspace/scratch/f8bca915f70d')
REPO = ROOT / 'quds_office_suite'
LOGS = ROOT / 'toolchains/logs'
GATE = LOGS / 'final-macro-gate-fb09a29b'
DEST = REPO / 'docs/validation/office-vba-word-powerpoint-20261120'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save(src, relative, compressed=False):
    dest = DEST / relative
    dest.parent.mkdir(parents=True, exist_ok=True)
    data = src.read_bytes()
    dest.write_bytes(gzip.compress(data, mtime=0) if compressed else data)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--audit-script', type=Path, required=True)
    parser.add_argument('--checkpoints', type=Path, required=True)
    args = parser.parse_args()
    receipt = json.loads((GATE / 'receipt.json').read_text())
    assert receipt['all_stages_passed'] and not receipt['source_changes']
    assert receipt['totals']['failed'] == receipt['totals']['skipped'] == 0
    before = json.loads((GATE / 'inputs-before.json').read_text())
    after = json.loads((GATE / 'inputs-after.json').read_text())
    assert before == after
    for path, expected in before.items():
        assert digest(REPO / path) == expected, path
    product = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()
    engine_tree = subprocess.check_output(['git', 'rev-parse', 'HEAD:packages/quds_office_engine'], cwd=REPO, text=True).strip()
    frozen_tree = subprocess.check_output(['git', 'rev-parse', receipt['source_head_start']+':packages/quds_office_engine'], cwd=REPO, text=True).strip()
    assert engine_tree == frozen_tree
    for path in sorted(GATE.iterdir()):
        if not path.is_file():
            raise AssertionError('Unexpected unfinished gate directory: '+str(path))
        compressed = path.suffix == '.log' or path.name in ('receipt.json', 'inputs-before.json', 'inputs-after.json', 'case-identifiers.json')
        save(path, 'macro-gate/'+path.name+('.gz' if compressed else ''), compressed)
    summary = {k:v for k,v in receipt.items() if k not in ('stages', 'example_check')}
    summary['stages'] = [{k:v for k,v in s.items() if k not in ('outcomes', 'non_json_output')} for s in receipt['stages']]
    summary['product_commit'] = product
    summary['engine_tree'] = engine_tree
    summary['verified_unchanged_inputs'] = len(before)
    summary['example_check'] = {k:v for k,v in receipt.get('example_check',{}).items() if k != 'nativeOperations'}
    (DEST / 'macro-gate/summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    for name in ('final-pdf-results.json', 'final-pdf-source-snapshot.json'):
        save(LOGS / name, 'pdf-gate/'+name)
    for name in ('final-pdf-incoming-batch1.log','final-pdf-retained-batch2.log','final-pdf-import-batch3.log'):
        save(LOGS / name, 'pdf-gate/'+name+'.gz', True)
    save(args.audit, 'integration/inclusion-receipt.json')
    save(args.audit_script, 'runtime/audit_inclusion.executed.py')
    save(args.checkpoints, 'integration/checkpoints.json')
    save(ROOT / 'final_integration_snapshot.json', 'integration/captured-refs.json')
    save(ROOT / 'toolchains/environment.json', 'runtime/environment.json')
    for name in ('run_final_macro_gate.py','run_powerpoint_portable.py','check_powerpoint_report_example.dart'):
        save(ROOT / 'toolchains' / name, 'runtime/'+name)
    save(Path(__file__), 'runtime/bundle_evidence.executed.py')
    for name in ('vba-same-text-source.json','vba-same-text.patch'):
        save(LOGS / name, 'development/'+name)
    for name in ('vba-same-text-before-fix.log','vba-same-text-native-regression.log','vba-same-text-analysis.log','vba-adapters-shared-regression.log','vba-adapters-word-regression.log','vba-adapters-font-boundary.log'):
        save(LOGS / name, 'development/'+name+'.gz', True)
    for mode in ('conformance','smoke'):
        for suffix in ('vm.log','js.log','compile-js.log'):
            name = f'final-macro-gate-fb09a29b-powerpoint-{mode}-{suffix}'
            path = LOGS / name
            assert path.is_file(), path
            save(path, 'portable/'+f'powerpoint-{mode}-{suffix}.gz', True)
    stages = [s for s in receipt['stages'] if 'tests_passed' in s]
    rows = '\n'.join('| '+s['stage'].split('-',1)[1]+' | '+str(s['tests_passed'])+' | 0 | 0 |' for s in stages)
    old = (DEST / 'README.md').read_text().split('## Final qualification')[0]
    final = f'''## Final source and captured-ref coverage

The final product source is `{product}`. The engine gate began at
`{receipt['source_head_start']}`; the subsequent proofing/UI ancestry merge
left the entire engine tree unchanged: `{engine_tree}`.
All **{len(before):,}** source, test, tool, fixture and manifest inputs were
hashed before and after qualification and checked again while bundling evidence.
The final evidence commit changes only this validation directory.

The captured snapshot contains **24 live branch heads**. The final inclusion
audit accounts for all of them: **15 true ancestors and 9 historical equivalents**.
All three captured open PR heads (#227, #234 and #236) are true ancestors.
Of all 236 fetched PR head refs, 222 are ancestors and 14 older refs have proven
accepted equivalents; those 14 are not described as ancestor commits.
Thirteen of those historical PR equivalents have identical full trees, and the
remaining ODT PR has identical mode/type/blob entries on all 37 changed paths.
See [the complete inclusion receipt](integration/inclusion-receipt.json).

The final captured additions include Zotero `708f2821`, window focus `b8f4a7be`,
Mail `44abcfa1`, presentation controls `1eddb914`, rename/workflow `228d13d9`,
Android `67a4917b`, Variants/Word `1ceae221`, and proofing `604e5f1a`.
Original branch parents are retained by merge commits. Incremental remote
checkpoints and local-to-remote commit mappings are recorded in
[checkpoints.json](integration/checkpoints.json); each published tree was
verified against its local tree before a non-forced expected-head update.
The exact snapshot cutoff is recorded in
[captured-refs.json](integration/captured-refs.json).

See [integration-reconciliation.md](integration-reconciliation.md) for the
PDF/autofit/radial merge decisions. Final review additionally repaired explicit
same-value PowerPoint text replacement, preventing old fields/mixed runs from
being resurrected, and kept existing native-menu callers compatible with the
incoming optional View groups.

## Final local qualification

**Strict analysis of the whole engine passed with `--fatal-infos`.**
The frozen macro selection passed **{receipt['totals']['passed']:,} test cases
across 32 files**, with zero failures and zero skips. Test IDs, exact command
arguments, exit codes, source hashes, durations and local resource limits are
retained in the [summary](macro-gate/summary.json) and
[full raw receipt](macro-gate/receipt.json.gz).

There are 1,221 distinct runner execution IDs and 1,220 display labels because
the empty-group and populated-group guard fixtures share an existing test title.
[Case identifiers](macro-gate/case-identifiers.json.gz) distinguish those inputs.

| Local test batch | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
{rows}

The selection includes all 93 new compiler cases, actual DOCX/PPTX operations,
validation without publication, permissions and work budgets, strict shape
selection, late-failure rollback, exact XML units, explicit false/same-value
formatting, imported fields/hyperlinks, empty/authored rich text, repeated saves,
opaque macro-project preservation, MCP and real CLI subprocesses.

The separate PDF/import reconciliation gate passed **213 tests in 10 files**
across three bounded processes (39 + 119 + 55). Its tested source hashes match
the frozen engine commit. It covers finite/zero autofit, shared paragraph layout,
shape geometry and anchors, scoped picture opacity, alpha resources, radial
guards and ring colors, backgrounds and import preservation.
See [its receipt](pdf-gate/final-pdf-results.json). These selections overlap;
their counts are not added into a claimed unique grand total.

### Portability and runnable example

- The 20-case independently authored PowerPoint conformance corpus passed on
  both Dart VM and compiled JavaScript, with byte-identical canonical receipts
  and unchanged inputs.
- The native PowerPoint transaction smoke passed on both runtimes with
  byte-identical receipts, including real save/readback, MCP, strict selectors,
  read-only refusal, validation without publication and rollback.
- The committed `example/macros/powerpoint_report.bas` compiled through the
  public default `Main` entrypoint into exactly 18 independently specified
  operations. Native PPTX readback verified both formatted shapes, an unchanged
  third shape, and the computed body text `Source records: 3; total units: 14`.

Portable source/command receipts are retained in
[conformance](macro-gate/portable-conformance-receipt.json) and
[native smoke](macro-gate/portable-smoke-receipt.json). Raw VM/JS outputs are in
`portable/`; the runnable example receipt is in the macro summary.

### Reproduction and evidence boundaries

Use the repository's pinned environment and the exact test-file selections and
arguments in `macro-gate/summary.json` and `pdf-gate/final-pdf-results.json`.
All final test commands use `--concurrency=1 --timeout=4x`; CLI-containing suites
run alone. The executed local drivers and runtime receipt are preserved under
`runtime/`. Their absolute workspace paths describe the original run and must
be adjusted when reproducing elsewhere. Raw logs and large JSON manifests use
gzip compression; `evidence-manifest.json` records their SHA-256 hashes.

Earlier source-only shared compiler and Word/Variant regression logs are kept
under `development/` for traceability and are not added to the final-source
execution count. The same-value text regressions were observed failing before
their fix and passing afterward. Earlier disk-exhausted or default-timeout CLI
attempts were development failures, not qualification; the final isolated CLI
batches above supersede them.

No GitHub Actions run, check, status, or queued job was used as an acceptance
gate. No Flutter UI/native application build or Microsoft Office host execution
was performed. The inherited editor/proofing integration received source and
call-site review; its Flutter runtime behavior is not qualified by these engine
tests. No full VBA runtime, COM, live object-property reads, embedded-project
execution, or editor macro ribbon/undo integration is implied.
'''
    (DEST / 'README.md').write_text(old+final)
    manifest = {str(p.relative_to(DEST)):{'sha256':digest(p),'bytes':p.stat().st_size} for p in sorted(DEST.rglob('*')) if p.is_file() and p.name != 'evidence-manifest.json'}
    (DEST / 'evidence-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(json.dumps({'source':product,'engine_tree':engine_tree,'test_cases':receipt['totals']['passed'],'unchanged_inputs':len(before),'evidence_files':len(manifest)+1,'total_bytes':sum(v['bytes'] for v in manifest.values())},indent=2))

if __name__ == '__main__':
    main()

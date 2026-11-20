from pathlib import Path
import gzip
import hashlib
import json
import subprocess

ROOT = Path('/workspace/scratch/f8bca915f70d')
REPO = ROOT / 'quds_office_suite'
DEST = REPO / 'docs/validation/office-vba-word-powerpoint-20261120'
SOURCE = 'a6068b4d46421e8a0c5921ba0b5cc24b4873ca12'
MAIN = '33190e50cae486be362eedb5fa687dd9c82b0c51'

def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO, text=True).strip()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

inputs = json.loads(gzip.decompress((DEST/'macro-gate/inputs-after.json.gz').read_bytes()))
assert all(digest(REPO/path) == sha for path,sha in inputs.items())
assert git('rev-parse', 'HEAD') == SOURCE
for ancestor in (MAIN, '55e52def1b964a85764eb9c4fcf8163fbdcee625'):
    subprocess.run(['git','merge-base','--is-ancestor',ancestor,SOURCE],cwd=REPO,check=True)
audit = json.loads((ROOT/'toolchains/logs/latest-main-integration-audit.json').read_text())
audit['published_commit'] = SOURCE
audit['published_tree'] = git('rev-parse', SOURCE+'^{tree}')
audit['published_parents'] = git('show','-s','--format=%P',SOURCE).split()
audit['qualified_input_count_rechecked'] = len(inputs)
audit['all_qualified_inputs_identical'] = True
audit['original_inclusion_audit_target_is_ancestor'] = True
audit['latest_main_is_ancestor'] = True
audit['qualified_engine_tree'] = git('rev-parse','fb09a29b70e469c2858bde48c8977590791b6ba7:packages/quds_office_engine')
audit['published_engine_tree'] = git('rev-parse',SOURCE+':packages/quds_office_engine')
assert audit['qualified_engine_tree'] == audit['published_engine_tree']
(DEST/'integration/latest-main-reconciliation.json').write_text(json.dumps(audit,indent=2)+'\n')
checkpoints = json.loads((DEST/'integration/checkpoints.json').read_text())
checkpoints['current_product_commit'] = SOURCE
checkpoints['local_to_remote_commits'].update({
 '71cdffc9fe54b59b2b367ad491cfff2f9b54764b':'230b0abdaacda2e178e8740fed5cf0dcb6f7281f',
 'beaf8f4e88054d26a3b31577c25de4f242acd3f8':SOURCE,
})
for local,remote in checkpoints['local_to_remote_commits'].items():
    assert git('rev-parse',local+'^{tree}') == git('rev-parse',remote+'^{tree}')
(DEST/'integration/checkpoints.json').write_text(json.dumps(checkpoints,indent=2)+'\n')
readme = (DEST/'README.md').read_text()
readme = readme.replace('The final product source is `55e52def1b964a85764eb9c4fcf8163fbdcee625`. The engine gate began at\n`fb09a29b70e469c2858bde48c8977590791b6ba7`; the subsequent proofing/UI ancestry merge\nleft the entire engine tree unchanged:', 'The final product source is `'+SOURCE+'`. The engine gate began at\n`fb09a29b70e469c2858bde48c8977590791b6ba7` and finished at `55e52def` before the\nlatest-main reconciliation. Both the proofing/UI and latest-main merges left\nthe entire engine tree unchanged:')
needle = 'The exact snapshot cutoff is recorded in\n[captured-refs.json](integration/captured-refs.json).'
readme = readme.replace(needle,needle+'\n\nRemote main subsequently advanced to `'+MAIN+'`. Its exact head\nwas integrated at `'+SOURCE+'`, retaining the new installed-font\nfixes and evidence. All 1,041 qualified inputs were checked again and remain\nidentical. The original captured-ref audit remains applicable by ancestry.\n[The latest-main receipt](integration/latest-main-reconciliation.json) records\nall seven incoming commits, their merge-resolution inspection, the seven net\nchanged paths, and the retained Mail regression assertions. No additional\nengine test execution was needed because its entire source tree is unchanged.')
(DEST/'README.md').write_text(readme)
pr = ROOT/'word_powerpoint_vba_pr.md'
body = pr.read_text().replace('and final product source `55e52def`.', 'at gate completion `55e52def`, and at the final reconciled product source `a6068b4d`.')
body = body.replace('All 24 captured branch heads are accounted for:', 'Latest remote main `33190e50` was also integrated at `a6068b4d`, retaining its font fixes and evidence; all 1,041 qualified inputs were rechecked unchanged.\n\nAll 24 captured branch heads are accounted for:')
pr.write_text(body)
(DEST/'runtime/record_latest_main_reconciliation.executed.py').write_bytes(Path(__file__).read_bytes())
manifest = {str(p.relative_to(DEST)):{'sha256':digest(p),'bytes':p.stat().st_size} for p in sorted(DEST.rglob('*')) if p.is_file() and p.name != 'evidence-manifest.json'}
(DEST/'evidence-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'published_product':SOURCE,'latest_main':MAIN,'unchanged_inputs':len(inputs),'verified_checkpoints':len(checkpoints['local_to_remote_commits']),'engine_tree':audit['published_engine_tree']},indent=2))

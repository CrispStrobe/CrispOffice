#!/usr/bin/env python3
"""Preserve an accepted Word checkpoint while incorporating newly merged main."""
import copy
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT=Path(__file__).resolve().parent.parent
REPO=ROOT/'quds_office_suite'
DOCS=REPO/'docs/validation/word-vba-paragraph-spacing-20261120'
WORD='8b9be399da380b0b8ab3abf238833eb221996c7d'
MAIN='d1e9cbc0c5dd38f0c8d28e3d76e7fdd59990f3f4'
MAIN_BASE='5ad4461a93c835479bf67acab63623944b3900a3'
ARABIC='be47bed22a88382f016d823e526bae49590bd0eb'
MERGE_TREE='089f8a66e34efb05a3270523b140c4ced2d07950'

def git(*args):return subprocess.check_output(['git',*args],cwd=REPO)
def sha(data):return hashlib.sha256(data).hexdigest()
def ancestor(commit,target):return subprocess.run(['git','merge-base','--is-ancestor',commit,target],cwd=REPO,stdout=subprocess.DEVNULL).returncode==0
def save(name,data):(DOCS/name).write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
def entry(ref,path):
 raw=git('ls-tree',ref,'--',path).decode().strip()
 meta,name=raw.split('\t');mode,kind,blob=meta.split()
 assert name==path and kind=='blob'
 data=git('cat-file','blob',blob)
 return {'mode':mode,'type':kind,'blob':blob,'bytes':len(data),'sha256':sha(data)}

assert git('rev-parse','HEAD').decode().strip()==WORD
assert not git('status','--porcelain').strip(),'Start from clean accepted checkpoint'
assert git('show','-s','--format=%P',MAIN).decode().strip().split()==[MAIN_BASE,ARABIC]
assert ancestor(MAIN_BASE,WORD)
merged=git('merge-tree','--write-tree','--messages',WORD,MAIN).decode().splitlines()
assert merged[0]==MERGE_TREE and not any(line for line in merged[1:])
incoming=git('diff','--name-only',MAIN_BASE,MAIN).decode().splitlines()
assert len(incoming)==9
assert git('diff','--name-only',WORD,MERGE_TREE).decode().splitlines()==incoming
incoming_entries={}
for path in incoming:
 assert path.startswith(('.github/workflows/','packages/quds_arabic_morph/'))
 assert git('ls-tree',MAIN_BASE,'--',path)==git('ls-tree',WORD,'--',path)
 incoming_entries[path]=entry(MAIN,path)
 assert incoming_entries[path]==entry(MERGE_TREE,path)

manifest=json.loads(gzip.decompress((DOCS/'source-consistency.json.gz').read_bytes()))
assert len(manifest['entries'])==1131
for path,expected in manifest['entries'].items():
 assert entry(MERGE_TREE,path)==expected,path
source_review=json.loads((DOCS/'source-review.json').read_text())
for path,expected in source_review['source_files'].items():
 actual=entry(MERGE_TREE,path)
 assert actual['bytes']==expected['bytes'] and actual['sha256']==expected['sha256']
 assert actual['mode']==expected['git_mode'] and actual['blob']==expected['git_blob']

scope_path=DOCS/'publication-scope-review.json'
scope=json.loads(scope_path.read_text())
counts=copy.deepcopy(scope['counts'])
incorporated=[];remaining=[]
for row in scope['explicitly_deferred']:
 if ancestor(row['sha'],WORD) or ancestor(row['sha'],MAIN):
  incorporated.append(row)
  counts[row['kind']]['incorporated_or_equivalent']+=1
  counts[row['kind']]['explicitly_deferred']-=1
 else:remaining.append(row)
assert len(incorporated)==2 and {r['sha'] for r in incorporated}=={ARABIC}
assert len(remaining)==12 and len({r['sha'] for r in remaining})==7
assert counts['fork_branches']['incorporated_or_equivalent']==26
assert counts['fork_pull_requests']['incorporated_or_equivalent']==265
review_path=ROOT/'intake-review/publication-checkpoint-8b9be399.json'
review=json.loads(review_path.read_text())
assert review['status']=='PASS' and review['target']==WORD and not review['outstanding_findings']
receipt={
 'schema':'quds-word-spacing-final-main-reconciliation/v1','accepted':True,
 'prepared_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'word_checkpoint':WORD,'word_checkpoint_tree':git('rev-parse',WORD+'^{tree}').decode().strip(),
 'incoming_main':MAIN,'incoming_main_parents':[MAIN_BASE,ARABIC],
 'incoming_main_tree':git('rev-parse',MAIN+'^{tree}').decode().strip(),
 'expected_parents':[WORD,MAIN],'merge_tree_without_evidence':MERGE_TREE,
 'clean_three_way_merge':True,'incoming_main_paths':incoming_entries,
 'all_nine_incoming_paths_retained_exactly':True,'qualified_source_paths':1131,
 'all_qualified_source_and_ten_reviewed_inputs_unchanged':True,
 'historical_scope':{'path':scope_path.name,'bytes':scope_path.stat().st_size,'sha256':sha(scope_path.read_bytes()),'deferred_references':14},
 'accepted_word_checkpoint_review':{'path':review_path.name,'bytes':review_path.stat().st_size,'sha256':sha(review_path.read_bytes())},
 'incorporated_from_deferred':incorporated,'counts':counts,'remaining_deferred':remaining,
 'remaining_deferred_references':12,'remaining_deferred_unique_heads':7,'unclassified_references':0,
 'all_initial_captured_work_included':True,'all_selected_late_heads_integrated':True,
 'github_actions':'not queried or awaited',
 'limits':['This incorporates existing remote main without reverting its Arabic feature.',
           'The accepted Word gates remain bound to unchanged selected source and runtime inputs.',
           'No new Arabic runtime/native-web parity or workflow execution is claimed.',
           'The original scope capture and classifications remain intact as historical evidence; this addendum reclassifies only the two captured PR267 references.'],
}
subprocess.run(['git','restore','--source',MERGE_TREE,'--staged','--worktree','--',*incoming],cwd=REPO,check=True)
save('main-reconciliation.json',receipt)
shutil.copy2(review_path,DOCS/review_path.name)
shutil.copy2(Path(__file__),DOCS/Path(__file__).name)
labels={'fork_branches':'Fork branch heads','fork_pull_requests':'Fork PR heads','upstream_branches':'Upstream branch heads','upstream_pull_requests':'Upstream PR heads'}
table='\n'.join('| '+labels[k]+' | '+str(v['captured'])+' | '+str(v['incorporated_or_equivalent'])+' | '+str(v['explicitly_deferred'])+' |' for k,v in counts.items())
text=f'''# Final live-main reconciliation

After independent acceptance of Word checkpoint `{WORD}`, remote main advanced
to `{MAIN}` through PR #267. The new merge contains the previously captured
Arabic web-context head `{ARABIC}`. Its nine paths are disjoint from the Word
changes and all qualified inputs. A clean three-way merge retains every incoming
file, Git mode and object exactly. Both heads are actual parents of the final
reconciliation checkpoint. The [receipt](main-reconciliation.json) binds the
source objects, exact bytes, expected parents and scope update.

All 1,131 qualified Word inputs and all ten separately reviewed source/contract
inputs remain unchanged. The [accepted preceding checkpoint review](publication-checkpoint-8b9be399.json)
and original scope report remain exact historical records. No Word tests need
to be rerun for this disjoint merge, and no Arabic runtime/parity validation or
GitHub workflow execution is claimed.

The same captured inventory now has the following disposition. Only the two
references to the newly incorporated Arabic head change classification; the
other 12 deferred references identify seven distinct heads. There are zero
unclassified references. This table supersedes the disposition table in the
historical scope report without replacing its original capture or audit result.

| Captured source | Captured | Incorporated or equivalent | Explicitly deferred |
| --- | ---: | ---: | ---: |
{table}

The complete accepted final reconciliation review and post-merge consistency
proof are preserved in PR #263. All existing checkpoints remain ancestors.
'''
(DOCS/'main-reconciliation.md').write_text(text)
readme_path=DOCS/'README.md'
readme=readme_path.read_text()
assert '## Final live-main reconciliation' not in readme
readme+='\n## Final live-main reconciliation\n\nThe final [main reconciliation addendum](main-reconciliation.md) incorporates PR #267,\nwhich merged to remote main after the captured scope review. All nine incoming\npaths and the accepted Word source are preserved exactly. Its updated table\nsupersedes the historical scope dispositions above: 26 of 33 branch heads and\n265 of 270 PR heads are incorporated or equivalent; 12 references to seven\nlater heads remain deferred, with zero unclassified references. The preceding\nWord checkpoint `8b9be399` and newly observed main `d1e9cbc0` are both retained\nas actual merge parents. No new Arabic runtime validation is claimed.\n'
readme_path.write_text(readme)
print(json.dumps({'accepted':True,'word_checkpoint':WORD,'incoming_main':MAIN,'incoming_paths':len(incoming),'qualified_source_paths':1131,'remaining_deferred_references':12,'remaining_deferred_unique_heads':7}))

#!/usr/bin/env python3
"""Recompute captured-head inclusion without querying CI or rewriting refs."""
import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--target', default='HEAD')
parser.add_argument('--fork', type=Path, required=True)
parser.add_argument('--upstream', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
repo = args.repo.resolve()

def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=repo)

target = git('rev-parse', args.target).decode().strip()

def ancestor(commit):
    result = subprocess.run(['git','merge-base','--is-ancestor',commit,target],cwd=repo,capture_output=True)
    if result.returncode not in (0,1):
        raise RuntimeError(result.stderr.decode())
    return result.returncode == 0

def tree(commit, paths=None):
    return git('ls-tree','-r','-z',commit,'--',*(paths or []))

review_path = repo/'docs/validation/word-vba-paragraph-spacing-20261120/incoming-review.json'
review = json.loads(review_path.read_text())
assert review['status']=='PASS'
assert ancestor(review['target_commit'])
equivalents = {}
proofs = []
for original in review['intake']['recomputed_equivalence_proofs']:
    old = original['historical_head']
    accepted = original['accepted_ancestor']
    assert ancestor(accepted), accepted
    old_tree=git('rev-parse',old+'^{tree}').decode().strip()
    accepted_tree=git('rev-parse',accepted+'^{tree}').decode().strip()
    if original['full_tree_equal']:
        assert old_tree==accepted_tree, old
        proof={'kind':'full_tree','tree':old_tree}
    else:
        paths=git('diff','--name-only','-z',original['comparison_base'],old).decode().split('\0')
        paths=[p for p in paths if p]
        assert sorted(paths)==sorted(original['changed_paths']), old
        assert len(paths)==37, old
        old_entries=tree(old,paths)
        accepted_entries=tree(accepted,paths)
        assert old_entries==accepted_entries, old
        proof={'kind':'changed_paths','count':len(paths),'paths':paths,
               'entries_sha256':hashlib.sha256(old_entries).hexdigest()}
    equivalents[old]=accepted
    proofs.append({'historical_head':old,'accepted_ancestor':accepted,**proof})

refs=[]
counts=collections.defaultdict(collections.Counter)
raw={}
for source,path in [('fork',args.fork),('upstream',args.upstream)]:
    data=path.read_bytes()
    raw[source]={'file':path.name,'sha256':hashlib.sha256(data).hexdigest(),'capture_file_mtime_utc':datetime.datetime.fromtimestamp(path.stat().st_mtime,datetime.timezone.utc).isoformat()}
    seen=set()
    for row in data.decode().splitlines():
        oid,ref=row.split()
        assert ref not in seen
        seen.add(ref)
        kind=source+('_branches' if ref.startswith('refs/heads/') else '_pr_heads')
        assert ref.startswith('refs/heads/') or (ref.startswith('refs/pull/') and ref.endswith('/head'))
        item={'kind':kind,'ref':ref,'sha':oid}
        if oid==target:
            item['disposition']='target'
        elif ancestor(oid):
            item['disposition']='ancestor'
        elif oid in equivalents:
            item.update(disposition='equivalent',accepted_ancestor=equivalents[oid])
        else:
            item['disposition']='uncovered'
        refs.append(item)
        counts[kind]['captured']+=1
        counts[kind][item['disposition']]+=1
uncovered=[r for r in refs if r['disposition']=='uncovered']
result={'schema':'quds-word-spacing-publication-intake/v1',
        'reviewed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'target':target,'target_tree':git('rev-parse',target+'^{tree}').decode().strip(),
        'initial_review_sha256':hashlib.sha256(review_path.read_bytes()).hexdigest(),
        'initial_target_retained':review['target_commit'],
        'raw_captures':raw,'counts':dict(counts),'refs':refs,
        'equivalence_proofs':proofs,'uncovered':uncovered,
        'github_actions':'not queried or awaited','accepted':not uncovered}
args.out.parent.mkdir(parents=True,exist_ok=True)
args.out.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'accepted':not uncovered,'counts':dict(counts),'target':target,'uncovered':uncovered}))
raise SystemExit(bool(uncovered))

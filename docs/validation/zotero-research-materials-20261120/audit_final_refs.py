import argparse
import collections
import datetime
import hashlib
import json
import pathlib
import subprocess

parser = argparse.ArgumentParser(description='Audit captured immutable GitHub heads against one local commit, without network or source mutations.')
parser.add_argument('--repo', type=pathlib.Path, required=True)
parser.add_argument('--evidence', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent)
parser.add_argument('--output', type=pathlib.Path)
parser.add_argument('--head', default='HEAD')
parser.add_argument('--tested-head')
args = parser.parse_args()
REPO = args.repo.resolve()
AUDIT = args.evidence.resolve()
OUTPUT = args.output or (AUDIT / 'final-reconciliation.json')

def git(*argv):
    return subprocess.check_output(['git', '-C', str(REPO), *argv], stderr=subprocess.PIPE).decode().strip()

def ancestor(original, target):
    result = subprocess.run(['git', '-C', str(REPO), 'merge-base', '--is-ancestor', original, target], capture_output=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr.decode())
    return result.returncode == 0

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

head = git('rev-parse', args.head + '^{commit}')
snapshot_path = AUDIT / 'final-remote-snapshot.json'
initial_path = AUDIT / 'initial-reconciliation.json'
snapshot = json.loads(snapshot_path.read_text())
initial = json.loads(initial_path.read_text())
initial_upstream = json.loads((AUDIT / 'upstream-snapshot.json').read_text())
initial_branches = {b['name']: b for b in initial['branches']}
initial_prs = {p['number']: p for p in initial['pullRequests']}
proofs = {}
for initial_proof in initial['historicalEquivalenceProofs']:
    proof = dict(initial_proof)
    proof['reuseBasis'] = 'Exact immutable original/equivalent SHA pair and complete identity proof retained from initial reconciliation.'
    proof['equivalentIsAncestorOfAuditedHead'] = ancestor(proof['equivalent'], head)
    proof['passedForAuditedHead'] = proof['passed'] and proof['equivalentIsAncestorOfAuditedHead']
    proofs[proof['original']] = proof

def disposition(sha):
    is_ancestor = ancestor(sha, head)
    result = {'ancestorOfAuditedHead': is_ancestor}
    if is_ancestor:
        result['disposition'] = 'included by ancestry'
    elif sha in proofs and proofs[sha]['passedForAuditedHead']:
        result.update(disposition='included by retained verified historical equivalence', equivalent=proofs[sha]['equivalent'])
    else:
        result['disposition'] = 'incoming work pending integration'
    return result

def incoming_details(sha):
    commits = []
    for line in git('log', '--format=%H%x09%s', head + '..' + sha).splitlines():
        sha_value, title = line.split('\t', 1)
        commits.append({'sha': sha_value, 'title': title})
    return {
        'mergeBaseCandidates': git('merge-base', '--all', head, sha).splitlines(),
        'commitsNotInAuditedHead': commits,
    }

branches = []
for branch in snapshot['branches']:
    previous = initial_branches.get(branch['name'])
    entry = dict(branch)
    entry.update(disposition(branch['sha']))
    entry['changeSinceInitialCapture'] = 'new branch' if previous is None else ('unchanged' if previous['sha'] == branch['sha'] else 'head advanced or rewritten')
    if previous is not None:
        entry['initialSha'] = previous['sha']
        if previous['sha'] != branch['sha']:
            entry['initialHeadIsAncestorOfCapturedHead'] = ancestor(previous['sha'], branch['sha'])
    ref = 'refs/remotes/origin/' + branch['name']
    entry['fetchedRefShaAtAudit'] = git('rev-parse', ref)
    entry['fetchedRefMatchesCapture'] = entry['fetchedRefShaAtAudit'] == branch['sha']
    if entry['disposition'] == 'incoming work pending integration':
        entry.update(incoming_details(branch['sha']))
    branches.append(entry)

prs = []
for pr in snapshot['pullRequests']:
    previous = initial_prs.get(pr['number'])
    entry = {k:pr[k] for k in ('number','headSha','title','state','mergedAt','url')}
    entry.update(disposition(pr['headSha']))
    entry['changeSinceInitialCapture'] = 'new pull request' if previous is None else ('unchanged head' if previous['headSha'] == pr['headSha'] else 'head advanced or rewritten')
    if previous is not None and previous['headSha'] != pr['headSha']:
        entry['initialHeadSha'] = previous['headSha']
        entry['initialHeadIsAncestorOfCapturedHead'] = ancestor(previous['headSha'], pr['headSha'])
    entry['fetchedRefShaAtAudit'] = git('rev-parse','refs/remotes/pull/'+str(pr['number']))
    entry['fetchedRefMatchesCapture'] = entry['fetchedRefShaAtAudit'] == pr['headSha']
    prs.append(entry)

upstream_branches = []
old_upstream_branches = {b['name']:b['sha'] for b in initial_upstream['branches']}
for branch in snapshot['upstream']['branches']:
    entry = dict(branch)
    entry.update(disposition(branch['sha']))
    entry['unchangedFromInitial'] = old_upstream_branches.get(branch['name']) == branch['sha']
    entry['fetchedRefMatchesCapture'] = git('rev-parse','refs/remotes/upstream/'+branch['name']) == branch['sha']
    upstream_branches.append(entry)
upstream_prs = []
old_upstream_prs = {p['number']:p['sha'] for p in initial_upstream['pullRequests']}
for pr in snapshot['upstream']['pullRequests']:
    entry = {k:pr[k] for k in ('number','headSha','state','mergedAt','url')}
    entry.update(disposition(pr['headSha']))
    entry['unchangedFromInitial'] = old_upstream_prs.get(pr['number']) == pr['headSha']
    entry['fetchedRefMatchesCapture'] = git('rev-parse','refs/remotes/upstream-pull/'+str(pr['number'])) == pr['headSha']
    upstream_prs.append(entry)

incoming = [dict(b) for b in branches if b['disposition'] == 'incoming work pending integration']
for branch in incoming:
    branch['alsoIncludedByIncomingHeads'] = [
        {'name':other['name'],'sha':other['sha']}
        for other in incoming
        if other['sha'] != branch['sha'] and ancestor(branch['sha'],other['sha'])
    ]
minimal_heads = [b for b in incoming if not b['alsoIncludedByIncomingHeads']]
unrepresented_pr_heads = [
    p for p in prs
    if p['disposition'] == 'incoming work pending integration'
    and not any(p['headSha']==b['sha'] or ancestor(p['headSha'],b['sha']) for b in incoming)
]
summary = {
    'branches':dict(collections.Counter(b['disposition'] for b in branches)),
    'pullRequests':dict(collections.Counter(p['disposition'] for p in prs)),
    'historicalProofsRetained':len(proofs),
    'historicalProofsPassedForAuditedHead':sum(p['passedForAuditedHead'] for p in proofs.values()),
    'fetchedRefsMatchCapture':all(x['fetchedRefMatchesCapture'] for x in branches+prs+upstream_branches+upstream_prs),
    'upstreamBranchesIncludedByAncestry':sum(x['ancestorOfAuditedHead'] for x in upstream_branches),
    'upstreamPrHeadsIncludedByAncestry':sum(x['ancestorOfAuditedHead'] for x in upstream_prs),
    'incomingBranchCount':len(incoming),
    'minimalIncomingHeads':[{'name':b['name'],'sha':b['sha']} for b in minimal_heads],
    'incomingPrHeadsWithoutBranchCoverage':[{'number':p['number'],'sha':p['headSha']} for p in unrepresented_pr_heads],
    'allCapturedWorkIncluded':not incoming and not unrepresented_pr_heads and all(p['disposition'] != 'incoming work pending integration' for p in upstream_branches+upstream_prs),
}
out = {
    'repository':snapshot['repository'],
    'captureStartedAt':snapshot['captureStartedAt'],
    'cutoffCapturedAt':snapshot['capturedAt'],
    'captureNote':snapshot['captureNote'],
    'auditedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'auditedHead':head,
    'testedHead':git('rev-parse',args.tested_head+'^{commit}') if args.tested_head else None,
    'testQualificationNote':'This file audits ancestry and historical equivalence only; it does not assert test execution for auditedHead.',
    'initialMain':initial['main'],
    'initialMainIsAncestorOfAuditedHead':ancestor(initial['main'],head),
    'capturedRemoteMain':next(b['sha'] for b in snapshot['branches'] if b['name']=='main'),
    'baselinePr218Merge':initial['baselinePr218Merge'],
    'baselinePr218IsAncestorOfAuditedHead':ancestor(initial['baselinePr218Merge'],head),
    'branchCount':len(branches),
    'pullRequestCount':len(prs),
    'openPullRequestCount':len(snapshot['openPullRequests']),
    'branches':branches,
    'pullRequests':prs,
    'historicalEquivalenceProofs':list(proofs.values()),
    'incoming':incoming,
    'upstream':{'repository':snapshot['upstream']['repository'],'branches':upstream_branches,'pullRequests':upstream_prs},
    'changesSinceInitial':{
        'newBranches':[b['name'] for b in branches if b['changeSinceInitialCapture']=='new branch'],
        'changedBranchHeads':[b['name'] for b in branches if b['changeSinceInitialCapture']=='head advanced or rewritten'],
        'removedBranches':sorted(set(initial_branches)-{b['name'] for b in branches}),
        'newPullRequests':[p['number'] for p in prs if p['changeSinceInitialCapture']=='new pull request'],
        'changedPullRequestHeads':[p['number'] for p in prs if p['changeSinceInitialCapture']=='head advanced or rewritten'],
    },
    'sourceSnapshotSha256':digest(snapshot_path),
    'initialReconciliationSha256':digest(initial_path),
    'policy':{'ciActionsQueried':False,'ciActionsAwaited':False,'sourceTreeMutated':False,'remoteRefsMutated':False,'localRemoteTrackingRefsFetched':True},
    'summary':summary,
}
OUTPUT.write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps({'auditedHead':head,'cutoff':snapshot['capturedAt'],'summary':summary,'changes':out['changesSinceInitial']},indent=2))

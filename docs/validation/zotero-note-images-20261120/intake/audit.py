import collections
import datetime
import hashlib
import json
import pathlib
import subprocess
import tempfile

REPO = pathlib.Path('/workspace/scratch/0faa407ae6ae/quds_office_suite')
OUT = pathlib.Path(__file__).parent
MAIN = 'e06eb3a7e21b71c1d5d4b1d2cc9abde24774eb26'
BASE = '7501b604db23e2df3d765f2ea44f572b2ea43d97'

def git(*args, check=True):
    return subprocess.run(['git', '-C', str(REPO), *args], capture_output=True,
                          text=True, check=check)

def ancestor(sha, target=MAIN):
    return git('merge-base', '--is-ancestor', sha, target, check=False).returncode == 0

def tree_entries(sha):
    result = {}
    for line in git('ls-tree', '-r', sha).stdout.splitlines():
        entry, path = line.split('\t', 1)
        result[path] = entry
    return result

def diff_paths(base, tip):
    return git('diff', '--name-only', base, tip).stdout.splitlines()

prior_path = REPO / 'docs/validation/zotero-research-materials-20261120/continuation/ref-audit.json'
prior = json.loads(prior_path.read_text())
proofs = []
for p in prior['historical_equivalence_proofs']:
    original, equivalent, common = p['original'], p['equivalent'], p['common_base']
    paths = diff_paths(common, original)
    a, b = tree_entries(original), tree_entries(equivalent)
    failures = [path for path in paths if a.get(path) != b.get(path)]
    proof = dict(original=original, equivalent=equivalent, common_base=common,
                 changed_path_count=len(paths), checked_paths=paths,
                 common_base_matches=common in git('merge-base', '--all', original, equivalent).stdout.splitlines(),
                 equivalent_is_ancestor=ancestor(equivalent), identity_failures=failures)
    proof['passed'] = (proof['common_base_matches'] and proof['equivalent_is_ancestor']
                       and not failures)
    proofs.append(proof)
equivalents = {p['original']: p['equivalent'] for p in proofs if p['passed']}

all_refs = []
continuation_refs = []
for line in git('for-each-ref', '--format=%(refname) %(objectname)', 'refs/remotes/origin', 'refs/remotes/pull', 'refs/remotes/upstream', 'refs/remotes/upstream-pull').stdout.splitlines():
    ref, sha = line.split(' ', 1)
    if ref.endswith('/HEAD'):
        continue
    if ref == 'refs/remotes/origin/codex/zotero-parity-20261120':
        continuation_refs.append(dict(ref=ref, sha=sha))
        continue
    kind = 'branch' if ref.startswith(('refs/remotes/origin/', 'refs/remotes/upstream/')) else 'pull_request_head'
    repository = 'upstream' if ref.startswith(('refs/remotes/upstream/', 'refs/remotes/upstream-pull/')) else 'fork'
    state = 'included_by_ancestry' if ancestor(sha) else ('included_by_exact_historical_equivalence' if sha in equivalents else 'new_incoming_head')
    r = dict(ref=ref, sha=sha, kind=kind, repository=repository, disposition=state)
    if sha in equivalents:
        r['equivalent_ancestor'] = equivalents[sha]
    all_refs.append(r)

incoming = []
for r in all_refs:
    if r['kind'] != 'branch' or r['disposition'] != 'new_incoming_head':
        continue
    sha = r['sha']
    bases = git('merge-base', '--all', MAIN, sha).stdout.splitlines()
    chosen = MAIN if MAIN in bases else BASE if BASE in bases else bases[0]
    own_paths, main_paths = set(diff_paths(chosen, sha)), set(diff_paths(chosen, MAIN))
    shared = sorted(own_paths & main_paths)
    overlaps = []
    for path in shared:
        data = []
        missing = []
        for rev in [MAIN, chosen, sha]:
            value = git('show', f'{rev}:{path}', check=False)
            if value.returncode != 0:
                missing.append(rev)
            data.append(value.stdout)
        if missing:
            overlaps.append(dict(path=path, missing_at=missing))
            continue
        if '\x00' in ''.join(data):
            overlaps.append(dict(path=path, binary=True))
            continue
        with tempfile.TemporaryDirectory(dir=OUT) as temp:
            inputs = []
            for i, value in enumerate(data):
                filename = pathlib.Path(temp) / str(i)
                filename.write_text(value)
                inputs.append(str(filename))
            check = git('merge-file', '-p', *inputs, check=False)
            overlaps.append(dict(path=path, identical_tips=data[0] == data[2],
                                 three_way_exit=check.returncode,
                                 conflict_hunks=check.stdout.count('<<<<<<< ')))
    incoming.append(dict(ref=r['ref'], sha=sha, common_bases=bases,
                         explicit_base_for_overlap_review=chosen,
                         changed_paths_from_selected_base=sorted(own_paths),
                         overlapping_changes=overlaps,
                         unique_commits=git('log', '--format=%H %s', f'{MAIN}..{sha}').stdout.splitlines()))

report = dict(schema=1, repository='CrispStrobe/quds_office_suite',
              recorded_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
              audited_main=MAIN, user_checkpoint=BASE,
              policy='Read-only local Git audit of captured origin and PR refs. No Actions, workflow, check or commit-status endpoints queried or awaited. No branches or product sources mutated.',
              prior_proof_source=str(prior_path.relative_to(REPO)),
              prior_proof_source_sha256=hashlib.sha256(prior_path.read_bytes()).hexdigest(),
              historical_equivalence_proofs=proofs, refs=all_refs,
              continuation_refs_separate=continuation_refs,
              summary=dict(fork_branches=sum(r['kind']=='branch' and r['repository']=='fork' for r in all_refs),
                           fork_pull_request_heads=sum(r['kind']=='pull_request_head' and r['repository']=='fork' for r in all_refs),
                           upstream_branches=sum(r['kind']=='branch' and r['repository']=='upstream' for r in all_refs),
                           upstream_pull_request_heads=sum(r['kind']=='pull_request_head' and r['repository']=='upstream' for r in all_refs),
                           dispositions=dict(collections.Counter(r['disposition'] for r in all_refs)),
                           historical_proofs_passed=sum(p['passed'] for p in proofs),
                           original_delta_paths_checked=sum(p['changed_path_count'] for p in proofs)),
              incoming=incoming,
              main_delta_paths=diff_paths(BASE, MAIN),
              limitations=['Three-way text probes use explicit real common bases, not Git recursive virtual-base construction. They predict overlap resolution only and are not performed merges or runtime qualification.'])
(OUT/'intake-audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report['summary'],indent=2))
for i in incoming:
    print(i['ref'],len(i['changed_paths_from_selected_base']),'changed paths')
    print(json.dumps(i['overlapping_changes'],indent=2))
print('Unaccounted PR heads:',[(r['ref'],r['sha']) for r in all_refs if r['kind']=='pull_request_head' and r['disposition']=='new_incoming_head'])

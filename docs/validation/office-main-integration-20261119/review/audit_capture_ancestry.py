#!/usr/bin/env python3
"""Verify captured Git refs and historical source equivalents without mutations.

Captures accept either `ref sha` (for-each-ref) or `sha ref` (ls-remote).
No fetch, checkout, ref update, CI access or application execution occurs.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

BASELINE = '0e84dc951e7a9e923107d7895fa457cf29a7af71'
PROOF_PATH = 'docs/validation/thesaurus-20261118/resume/incoming-audit.json'
HEX = re.compile(r'^[0-9a-f]{40}$')

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--head', required=True)
parser.add_argument('--refs', type=Path, action='append', required=True)
parser.add_argument('--upstream-refs', type=Path, action='append', default=[])
parser.add_argument('--api-capture', type=Path)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()

def raw_git(*argv):
    return subprocess.check_output(['git', '-C', str(args.repo), *argv])

def git(*argv):
    return raw_git(*argv).decode().strip()

def digest(data):
    return hashlib.sha256(data).hexdigest()

def ancestor(older, newer):
    process = subprocess.run(['git', '-C', str(args.repo), 'merge-base', '--is-ancestor', older, newer], capture_output=True)
    if process.returncode not in (0, 1):
        raise RuntimeError(process.stderr.decode())
    return process.returncode == 0

head = git('rev-parse', args.head+'^{commit}')
before = {
    'head': git('rev-parse', 'HEAD'),
    'refs': digest(raw_git('for-each-ref', '--format=%(refname) %(objectname)')),
    'index': digest(raw_git('ls-files', '--stage', '-z')),
}
baseline_ancestor = ancestor(BASELINE, head)
proof_bytes = raw_git('show', BASELINE+':'+PROOF_PATH)
old_proofs = json.loads(proof_bytes)['historical_equivalence']
assert len(old_proofs) == 14
historical = {}
for old in old_proofs:
    row = {k:old[k] for k in ('branch', 'sha', 'disposition')}
    sha = row['sha']
    disposition = row['disposition']
    row['baseline_is_integrated_ancestor'] = baseline_ancestor
    if disposition == 'all_commits_patch_equivalent':
        cherry = git('cherry', BASELINE, sha).splitlines()
        row['fresh_cherry'] = cherry
        row['passed'] = bool(cherry) and all(line.startswith('- ') for line in cherry) and baseline_ancestor
    elif disposition == 'identical_tree_already_integrated':
        equivalent = old['equivalent_commit']
        row.update(equivalent_commit=equivalent,
                   original_tree=git('rev-parse',sha+'^{tree}'),
                   equivalent_tree=git('rev-parse',equivalent+'^{tree}'),
                   equivalent_is_integrated_ancestor=ancestor(equivalent,head))
        row['passed'] = row['original_tree'] == row['equivalent_tree'] and row['equivalent_is_integrated_ancestor']
    elif disposition == 'all_changed_files_identical_in_merged_pr_140':
        equivalent = old['equivalent_commit']
        common = git('merge-base', sha, equivalent)
        paths = git('diff','--name-only',common,sha).splitlines()
        matches = []
        for path in paths:
            original_entry = git('ls-tree',sha,'--',path)
            equivalent_entry = git('ls-tree',equivalent,'--',path)
            matches.append({'path':path,'original_entry':original_entry,
                            'equivalent_entry':equivalent_entry,
                            'identical':original_entry == equivalent_entry})
        row.update(equivalent_commit=equivalent,
                   equivalent_is_integrated_ancestor=ancestor(equivalent,head),
                   recomputed_merge_base=common,
                   recomputed_complete_delta_paths=paths,
                   historical_path_list_matches=set(paths)==set(old['fresh_changed_files']),
                   file_checks=matches,
                   verified_file_count=len(matches))
        row['passed'] = bool(paths) and row['historical_path_list_matches'] and all(m['identical'] for m in matches) and row['equivalent_is_integrated_ancestor']
    else:
        raise ValueError('Unexpected proof disposition '+disposition)
    historical[sha] = row

inputs = []
refs = []
seen = set()
for capture, upstream in [(p,False) for p in args.refs]+[(p,True) for p in args.upstream_refs]:
    data = capture.read_bytes()
    inputs.append({'path':str(capture.resolve()),'sha256':digest(data),'upstream':upstream})
    for line_number,line in enumerate(data.decode().splitlines(),1):
        if not line.strip():
            continue
        fields = line.split()
        if len(fields)!=2:
            raise ValueError(f'{capture}:{line_number}: expected exactly two columns')
        first,second = fields
        if HEX.fullmatch(first):
            sha,ref=first,second
        elif HEX.fullmatch(second):
            ref,sha=first,second
        else:
            raise ValueError(f'{capture}:{line_number}: expected SHA-1')
        namespace = 'upstream' if upstream else 'fork'
        identity=(namespace,ref,sha)
        if identity in seen:
            continue
        seen.add(identity)
        if ref.endswith('^{}'):
            kind='peeled_tag_advertisement'
        elif ref=='HEAD' or ref.endswith('/HEAD'):
            kind='head_alias'
        elif upstream:
            kind='upstream_branch'
        elif ref.startswith('refs/tags/'):
            kind='tag'
        elif ref.startswith(('refs/remotes/pr/','refs/pull/')):
            kind='pull_request_head'
        elif ref.startswith(('refs/remotes/origin/','refs/heads/')):
            kind='fork_branch'
        else:
            kind='unrecognized_ref_kind'
        refs.append({'namespace':namespace,'kind':kind,'ref':ref,'object_sha':sha,'capture':str(capture.resolve())})

cache = {}
for row in refs:
    sha=row['object_sha']
    if sha not in cache:
        process=subprocess.run(['git','-C',str(args.repo),'rev-parse','--verify',sha+'^{commit}'],capture_output=True,text=True)
        if process.returncode:
            state={'classification':'missing_or_noncommit_object','diagnostic':process.stderr.strip()}
        else:
            commit=process.stdout.strip()
            if ancestor(commit,head):
                classification='ancestor'
            elif historical.get(commit,{}).get('passed'):
                classification='historical_equivalent'
            else:
                classification='unaccounted'
            state={'classification':classification,'commit':commit}
        cache[sha]=state
    row.update(cache[sha])

api_check={'provided':False}
if args.api_capture:
    api_bytes=args.api_capture.read_bytes()
    api=json.loads(api_bytes)
    actual={(row['kind'],row['ref']):row['object_sha'] for row in refs if row['namespace']=='fork'}
    differences=[]
    for branch in api['branches']:
        sha=branch.get('sha') or branch['commit']['sha']
        ref='refs/remotes/origin/'+branch['name']
        if actual.get(('fork_branch',ref))!=sha:
            differences.append({'kind':'branch','ref':ref,'api_sha':sha,'capture_sha':actual.get(('fork_branch',ref))})
    prs=api.get('pull_requests',api.get('prs',[]))
    for pr in prs:
        sha=pr['head']['sha'] if isinstance(pr['head'],dict) else pr['head']
        ref='refs/remotes/pr/'+str(pr['number'])
        if actual.get(('pull_request_head',ref))!=sha:
            differences.append({'kind':'pull_request','ref':ref,'api_sha':sha,'capture_sha':actual.get(('pull_request_head',ref))})
    api_check={'provided':True,'path':str(args.api_capture.resolve()),'sha256':digest(api_bytes),
               'branches':len(api['branches']),'pull_requests':len(prs),
               'differences':differences,'passed':not differences}

after={
    'head':git('rev-parse','HEAD'),
    'refs':digest(raw_git('for-each-ref','--format=%(refname) %(objectname)')),
    'index':digest(raw_git('ls-files','--stage','-z')),
}
unknown=[row for row in refs if row['classification'] not in ('ancestor','historical_equivalent') or row['kind']=='unrecognized_ref_kind']
actual_refs=[row for row in refs if row['kind'] not in ('head_alias','peeled_tag_advertisement')]
report={
    'schema':1,
    'checked_at_utc':datetime.now(timezone.utc).isoformat(),
    'integrated_head':head,'integrated_tree':git('rev-parse',head+'^{tree}'),
    'inputs':inputs,'script_sha256':digest(Path(__file__).read_bytes()),
    'counts':dict(Counter(row['kind'] for row in refs)),
    'total_capture_rows':len(refs),'actual_ref_count_excluding_aliases_and_peeled_ads':len(actual_refs),
    'distinct_captured_objects':len(cache),
    'distinct_commit_heads':len({row['commit'] for row in refs if 'commit' in row}),
    'classification':dict(Counter(row['classification'] for row in refs)),
    'actual_ref_classification':dict(Counter(row['classification'] for row in actual_refs)),
    'historical_source_record':{'commit':BASELINE,'path':PROOF_PATH,'sha256':digest(proof_bytes)},
    'historical_equivalence_checks':list(historical.values()),
    'all_14_historical_equivalences_reverified':all(row['passed'] for row in historical.values()),
    'api_capture_crosscheck':api_check,'unaccounted_refs':unknown,'refs':refs,
    'working_copy_observation':{'before':before,'after':after,'unchanged':before==after},
    'scope':'Git ancestry and immutable source equivalence only; historical equivalents remain non-ancestors. No current application/runtime acceptance inferred.',
    'network_calls':0,'github_actions_calls':0,'repository_mutations':0,
    'passed':not unknown and all(row['passed'] for row in historical.values()) and api_check.get('passed',True),
}
args.output.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({key:report[key] for key in ('integrated_head','counts','total_capture_rows','actual_ref_count_excluding_aliases_and_peeled_ads','distinct_commit_heads','classification','actual_ref_classification','all_14_historical_equivalences_reverified','unaccounted_refs','passed')},indent=2))

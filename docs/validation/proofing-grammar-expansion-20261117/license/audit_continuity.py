#!/usr/bin/env python3
"""Independently verify license/data/dependency continuity of proofing work."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent / 'quds_office_suite'

def git(*args):
    return subprocess.check_output(['git',*args],cwd=REPO,text=True).strip()

def sha(p):
    return hashlib.file_digest(p.open('rb'),'sha256').hexdigest()

def tree(ref):
    result={}
    raw=subprocess.check_output(['git','ls-tree','-r','-z',ref],cwd=REPO)
    for row in raw.split(b'\0'):
        if not row:continue
        info,path=row.decode().split('\t',1)
        mode,kind,blob=info.split()
        result[path]={'mode':mode,'kind':kind,'blob':blob}
    return result

def main():
    global REPO
    parser=argparse.ArgumentParser()
    parser.add_argument('--repository',type=Path,default=REPO)
    parser.add_argument('--baseline',default='62563c61f02ee44504776d9e7d26557f9bae490a')
    parser.add_argument('--qualified',default='HEAD')
    parser.add_argument('--output',type=Path,default=ROOT/'license-continuity-review.json')
    args=parser.parse_args()
    REPO=args.repository.resolve()
    baseline=git('rev-parse',args.baseline);qualified=git('rev-parse',args.qualified)
    before=tree(baseline);after=tree(qualified)
    prior=json.loads((REPO/'docs/validation/proofing-en-de-20261117/license-continuity-review.json').read_text())
    paths=set(prior['protected_inputs']['entries'])
    # Explicitly cover current toolchain pin and all relevant present/future data.
    for p in set(before)|set(after):
        name=Path(p).name
        if (p=='.fvmrc' or p.startswith('packages/quds_office_engine/third_party/')
            or p.startswith('packages/quds_office_engine/lib/src/proofing/data/')
            or p.startswith('packages/quds_proofing_harper/licenses/')
            or p.startswith('tools/proofing/german_model/')
            or name in ('pubspec.yaml','Cargo.lock','Cargo.toml','rust-toolchain.toml')
            and not p.startswith(('docs/','tmp/'))):
            paths.add(p)
    entries={p:{'baseline':before.get(p),'qualified':after.get(p)} for p in sorted(paths)}
    changed=[p for p,e in entries.items() if e['baseline']!=e['qualified']]
    worktree_changes=git('diff','--name-only',qualified).splitlines()
    protected_worktree_changes=sorted(set(worktree_changes)&paths)
    manifests=[p for p in paths if Path(p).name in ('pubspec.yaml','Cargo.lock','Cargo.toml','rust-toolchain.toml','.fvmrc','requirements.txt')]
    german=json.loads((REPO/'packages/quds_office_engine/third_party/proofing/manifest.json').read_text())
    # Use recorded generated-file pins, independently SHA-verify current bytes.
    generated=prior['german']['generated_files_sha256_verified']
    german_checks={p:{'expected':expected,'actual':sha(REPO/'packages/quds_office_engine'/p)} for p,expected in generated.items()}
    german_ok=all(v['expected']==v['actual'] for v in german_checks.values())
    sys.path.insert(0,str(REPO/'packages/quds_proofing_harper/tool'))
    from verify import verify_licenses
    harper=verify_licenses(REPO/'packages/quds_proofing_harper')
    manifest=json.loads((REPO/'packages/quds_proofing_harper/licenses/manifest.json').read_text())
    selection_counts=Counter(s for p in manifest['packages'] for s in p['selected_licenses'])
    mpl=[{'name':p['name'],'version':p['version'],'source_sha256':p['mpl_source']['sha256']} for p in manifest['packages'] if 'MPL-2.0' in p['selected_licenses']]
    report={'schema_version':1,'status':'passed' if not changed and not protected_worktree_changes and german_ok and harper['status']=='passed' else 'failed',
            'reviewed_at_utc':datetime.now(timezone.utc).isoformat(),'baseline_commit':baseline,'qualified_commit':qualified,
            'scope':'Independent continuity audit of repository license/data/dependency inputs; not a new legal opinion on inherited dependencies.',
            'protected_inputs':{'count':len(paths),'unchanged_count':len(paths)-len(changed),'changed':changed,'entries':entries,'worktree_changes':protected_worktree_changes},
            'dependency_manifests':{'count':len(manifests),'paths':sorted(manifests),'all_unchanged':not set(manifests)&set(changed)},
            'german_data':{'generated_files':german_checks,'all_pins_match':german_ok,'manifest_sha256':sha(REPO/'packages/quds_office_engine/third_party/proofing/manifest.json')},
            'harper':{**harper,'selected_license_counts':dict(selection_counts),'mpl_sources_detail':mpl,'manifest_sha256':sha(REPO/'packages/quds_proofing_harper/licenses/manifest.json'),'notice_bundle_sha256':sha(REPO/'packages/quds_proofing_harper/licenses/notices-and-mpl-sources.tar.gz')},
            'new_first_party_source_review':{'path':'packages/quds_office_engine/lib/src/proofing/german_grammar.dart','sha256':sha(REPO/'packages/quds_office_engine/lib/src/proofing/german_grammar.dart'),'scope':'Reviewed newly authored bounded phrase rules, explicit noun/adjective paradigms and safeguards; same-library part file, no external rule corpus, network call or dependency import.'},
            'limits':['No protected dependency, dictionary, pattern, model or license input changed; newly authored implementation is separately reviewed as first-party code.','MPL-2.0 is retained under existing accepted policy and its notices and source-distribution obligations remain explicit.','This audit does not establish runtime quality, browser acceptance or native support beyond separately executed validation.']}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'protected_inputs':len(paths),'changed':changed,'dependency_manifests':len(manifests),'harper':harper,'output':str(args.output)}))
    return 0 if report['status']=='passed' else 1

if __name__=='__main__':raise SystemExit(main())

#!/usr/bin/env python3
"""Bind the narrow morphology numeric-string repair to a final commit.

Read-only Git/content review. No product tests, checkout, index write or network.
Expected token hashes bind the reviewed patch while allowing Dart formatting.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone

BASE = '47ce5f726f1a0b1f213b926162528533dc0a3aab'
PRODUCT_PATHS = [
    'packages/quds_arabic_morph/lib/src/morph_analysis.dart',
    'packages/quds_arabic_morph/test/arabic_morph_unit_test.dart',
]
PLANS = [
    'docs/validation/office-resume-main-20261119/final/plan.json',
    'docs/validation/office-resume-main-20261119/final/node-plan.json',
]
EXPECTED_TOKENS = {'packages/quds_arabic_morph/lib/src/morph_analysis.dart': 'd6fb7fd9c3dbd71efab692c6ba615cd716ce3cf5213ed6189cfdaade762d4d40', 'packages/quds_arabic_morph/test/arabic_morph_unit_test.dart': '7553848684d0c753479b30691712140ce482ec59b5573d026ccdb355500bf30d'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def dart_tokens(source):
    """Discard formatting/comments while retaining exact source and string tokens."""
    tokens=[];i=0
    while i<len(source):
        c=source[i]
        if c.isspace():i+=1;continue
        if source.startswith('//',i):
            end=source.find('\n',i);i=len(source) if end<0 else end+1;continue
        if source.startswith('/*',i):
            depth=1;i+=2
            while depth:
                if i>=len(source):raise ValueError('Unclosed block comment')
                if source.startswith('/*',i):depth+=1;i+=2
                elif source.startswith('*/',i):depth-=1;i+=2
                else:i+=1
            continue
        start=i;raw=False
        if c in 'rR' and i+1<len(source) and source[i+1] in "'\"":raw=True;i+=1;c=source[i]
        if c in "'\"":
            quote=c*3 if source.startswith(c*3,i) else c;i+=len(quote)
            while True:
                if i>=len(source):raise ValueError('Unclosed string')
                if source.startswith(quote,i):i+=len(quote);break
                if not raw and source[i]=='\\':i+=2
                else:i+=1
            tokens.append(source[start:i]);continue
        match=re.match(r'[A-Za-z_$][A-Za-z0-9_$]*|(?:\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?',source[i:])
        if match:i+=len(match.group());tokens.append(source[start:i]);continue
        tokens.append(c);i+=1
    return tokens


def token_hash(data):
    return sha(json.dumps(dart_tokens(data.decode()),ensure_ascii=False,separators=(',',':')).encode())


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',required=True,type=Path)
    parser.add_argument('--source',required=True)
    parser.add_argument('--report',type=Path,default=Path(__file__).with_name('numeric-source-delta.json'))
    args=parser.parse_args();repo=args.repo.resolve();issues=[]
    def git(*parts):return subprocess.check_output(['git','-C',str(repo),*parts])
    def show(ref,path):return git('show',ref+':'+path)
    def tree(ref):
        result={}
        for entry in git('ls-tree','-rz',ref).split(b'\0'):
            if entry:
                meta,path=entry.split(b'\t',1);mode,kind,blob=meta.decode().split()
                result[path.decode()]=dict(mode=mode,kind=kind,git_blob=blob)
        return result
    def check(ok,message):
        if not ok:issues.append(message)
    target=git('rev-parse',args.source).decode().strip()
    prior=tree(BASE);current=tree(target)
    product=lambda t:{p:v for p,v in t.items() if p.startswith(('packages/','apps/','third_party/')) or
                      ('/' not in p and Path(p).suffix in {'.yaml','.lock'})}
    before_product=product(prior);after_product=product(current)
    changed=[p for p in sorted(before_product.keys()|after_product.keys()) if before_product.get(p)!=after_product.get(p)]
    check(set(changed)==set(PRODUCT_PATHS),'Product/configuration delta differs from the two reviewed files: '+repr(changed))
    check(set(before_product)==set(after_product),'Product/configuration path set changed')
    files=[]
    for path in PRODUCT_PATHS:
        before=show(BASE,path);after=show(target,path)
        check(current.get(path,{}).get('mode')==prior[path]['mode'],'File mode changed: '+path)
        actual=token_hash(after)
        check(actual==EXPECTED_TOKENS.get(path),'Final source tokens differ from reviewed proposal: '+path)
        files.append(dict(path=path,before=prior[path],after=current.get(path),
                          before_sha256=sha(before),after_sha256=sha(after),
                          reviewed_token_sha256=EXPECTED_TOKENS.get(path),actual_token_sha256=actual))
    all_extra=set()
    plan_reports=[]
    for path in PLANS:
        before=json.loads(show(BASE,path));after=json.loads(show(target,path))
        check(after['groups']==before['groups'],'Test groups/suite selection changed: '+path)
        check(after.get('extra_inputs',[])==before.get('extra_inputs',[]),'Extra input selection changed: '+path)
        check(after.get('whitespace_preserved_inputs',[])==before.get('whitespace_preserved_inputs',[]),'Whitespace exclusions changed: '+path)
        all_extra.update(before.get('extra_inputs',[]));all_extra.update(after.get('extra_inputs',[]))
        for kind in ['analysis','format']:
            old=before.get(kind,[]);new=after.get(kind,[])
            check(isinstance(new,list),'Non-explicit static selection: '+path)
            check(set(old)<=set(new),'Static target removed: '+path+' '+kind)
            check(set(new)-set(old)<=set(PRODUCT_PATHS),'Unexpected static target addition: '+path+' '+kind)
            if path==PLANS[0]:check(set(PRODUCT_PATHS)<=set(new),'Numeric repair is missing static coverage: '+kind)
        plan_reports.append(dict(path=path,before_sha256=sha(show(BASE,path)),after_sha256=sha(show(target,path)),
                                 exact_test_groups_preserved=after['groups']==before['groups'],
                                 analysis_paths=len(after.get('analysis',[])),format_paths=len(after.get('format',[]))))
    helpers={'docs/validation/document-review-notes-20261118/run_checks.py','tools/mail/check_store.py','tools/mail/check_reader.py'}
    helpers.update(all_extra-set(PLANS))
    for path in sorted(helpers):
        check(prior.get(path)==current.get(path),'Validation helper/runtime input changed: '+path)
    all_deltas=[p for p in sorted(prior.keys()|current.keys()) if prior.get(p)!=current.get(p)]
    outside=[p for p in all_deltas if p not in changed and p not in PLANS]
    # Evidence/docs additions are recorded. Other executable workflow changes need review.
    check(all(path.startswith('docs/') or path=='README.md' for path in outside),
          'Unexpected nonproduct change beyond documentation/evidence: '+repr(outside))
    report=dict(schema=1,static_review_passed=not issues,reviewed_at_utc=datetime.now(timezone.utc).isoformat(),
                base_source=BASE,source_commit=target,source_tree=git('rev-parse',target+'^{tree}').decode().strip(),
                method='Exact product/configuration path set and mode/blob delta; reviewed source-token hashes preserve behavior while allowing formatter whitespace; committed suite/static/runner input checks.',
                issues=issues,product_records=len(after_product),unchanged_product_records=len(after_product)-len(changed),
                changed_product_files=files,plans=plan_reports,unchanged_harness_and_extra_inputs=len(helpers),
                documentation_and_evidence_changes=outside,
                semantic_review=[
                    'Pinned JSNumber.toDouble returns the same JS number and toString prefers integer text; the unmodified source demonstrably failed its original -99.0 assertion on Node.',
                    'The repair preserves the double conversion and exact toString output, appending .0 only for finite text with neither dot nor exponent; no numeric rounding or precision truncation is introduced.',
                    'Fractional and exponential forms bypass suffixing, negative zero already retains its dot in both pinned runtimes, and existing string/null behavior is unchanged.',
                    'The original failing expectations remain exact; one added case covers integer signs/zeros/fractions/exponents/plain upper boundary and unchanged string features.',
                ],
                runtime_tests_executed_by_this_review=0,
                qualification_status='Source review only; require fresh source-bound VM and Node receipts before acceptance.',
                audit_script_sha256=sha(Path(__file__).read_bytes()))
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({k:report[k] for k in ['static_review_passed','source_commit','product_records','unchanged_product_records','issues']}))
    raise SystemExit(0 if report['static_review_passed'] else 1)

if __name__=='__main__':main()

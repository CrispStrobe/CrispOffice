from pathlib import Path, PurePosixPath
import collections, datetime, gzip, hashlib, json, os, re, subprocess, tarfile, traceback

ROOT=Path('/workspace/scratch/5c6c66fd3cc3')
REPO=ROOT/'quds_office_suite'
VERIFY=ROOT/'verification'
FINAL=REPO/'docs/validation/mail-m06-resume-20261119/final'
OUTPUT=VERIFY/'final-archive-audit.json'
HEAD='71edec2de364805113d18e0f1d7edbb1f00467e5'
TREE='8b7443bd15be09276764f62934b9d8ce32a6be68'
checks=0
report={'schema':1,'reviewer':'recover_repository','source_commit':HEAD,'source_tree':TREE,'status':'RUNNING','failures':[]}

def check(value, message):
    global checks
    checks+=1
    if not value: raise RuntimeError(message)

def sha(data): return hashlib.sha256(data).hexdigest()
def canonical(value): return json.dumps(value,sort_keys=True,separators=(',',':')).encode()
def strict_object(pairs):
    value={}
    for k,v in pairs:
        if k in value: raise ValueError('Duplicate JSON key '+k)
        value[k]=v
    return value

def decode(data): return json.loads(data,object_pairs_hook=strict_object)
def safe(name):
    return (isinstance(name,str) and bool(name) and not name.startswith('/')
        and '\\' not in name and ':' not in name
        and all(ord(c)>=32 and ord(c)!=127 for c in name)
        and all(p not in ('','.', '..') for p in name.split('/'))
        and str(PurePosixPath(name))==name)

def git(*args,binary=False):
    data=subprocess.check_output(['git','-C',str(REPO),*args],env=dict(os.environ,GIT_NO_LAZY_FETCH='1'))
    return data if binary else data.decode().strip()

def git_tree(commit):
    result={}
    for raw in git('ls-tree','-r','-z','--full-tree',commit,binary=True).split(b'\0'):
        if not raw: continue
        meta,name=raw.split(b'\t',1);mode,kind,oid=meta.decode().split()
        result[name.decode()]={'mode':mode,'type':kind,'git_blob':oid}
    return result

def original_inventory(stem):
    included={};omitted={}
    def directory(root,prefix,omit=False):
        for path in sorted(root.rglob('*')):
            if not path.is_file(): continue
            relative=path.relative_to(root).as_posix()
            if omit and path.name.startswith(('browser-entry.js','browser-worker.js')):
                omitted[relative]=path
            else: included[prefix+'/'+relative]=path
    if stem in ('mail-final','native-final','node-final'):
        directory(VERIFY/stem,stem,omit=True)
        included[stem+'/driver.log']=VERIFY/(stem+'.log')
    elif stem=='preparation':
        directory(VERIFY/'final-preparation','preparation')
        for name in ('final-execution.json','run_final.py','audit_final_mail.py','package_final.py','audit-controls.json','final-evidence-audit.json','runner-controls.log','runtime-controls.log'):
            included['support/'+name]=VERIFY/name
        directory(VERIFY/'test-repair','test-repair')
        directory(VERIFY/'runner-race-repair','runner-race-repair')
    elif stem=='development':
        for path in sorted((ROOT/'transport-dev').iterdir()):
            if path.is_file() and path.suffix in {'.json','.log'}:
                included['transport-development/'+path.name]=path
    elif stem=='first-attempt': directory(VERIFY/'failed-da78c0bb-1','first-attempt',omit=True)
    elif stem=='second-attempt': directory(VERIFY/'failed-e734e3bd-1','second-attempt')
    elif stem=='source-review': directory(VERIFY/'final-source-review','source-review')
    else: raise RuntimeError('Unknown archive '+stem)
    return included,omitted

def normalize_suite(value,cwd):
    p=Path(value)
    if not p.is_absolute(): p=cwd/p
    check('..' not in p.parts,'Suite path traverses parents '+value)
    return p.relative_to(REPO).as_posix()

def parse_stream(raw,cwd,label):
    events=[decode(line) for line in raw.decode().splitlines() if line.strip()]
    check(bool(events) and events[0].get('type')=='start',label+' starts with reporter start')
    check(events[-1].get('type')=='done' and events[-1].get('success') is True,label+' terminal success')
    kinds=collections.Counter(e.get('type') for e in events)
    check(kinds['start']==1 and kinds['done']==1,label+' exactly one start/terminal')
    check(kinds['error']==0,label+' no reporter errors')
    check(set(kinds)<=set(('start','suite','testStart','allSuites','print','testDone','group','done','debug')),label+' known reporter events')
    suites={};started={};done={};suite_totals=[]
    for e in events:
        kind=e['type']
        if kind=='suite':
            s=e['suite'];check(type(s['id']) is int and s['id'] not in suites,label+' unique suite id')
            check(s['platform'] in ('vm','node'),label+' known platform')
            suites[s['id']]={**s,'normalized':normalize_suite(s['path'],cwd)}
        elif kind=='testStart':
            t=e['test'];check(type(t['id']) is int and t['id'] not in started,label+' unique test start')
            check(t['suiteID'] in suites and isinstance(t['name'],str),label+' declared test suite/name')
            started[t['id']]=t
        elif kind=='testDone':
            i=e['testID'];check(i in started and i not in done,label+' unique known completion')
            check(e['result']=='success' and e['skipped'] is False and type(e['hidden']) is bool,label+' no hidden or substantive failure/skip')
            done[i]=e
        elif kind=='allSuites': suite_totals.append(e['count'])
    check(set(started)==set(done),label+' all starts completed')
    check(suite_totals==[len(suites)],label+' suite-count agreement')
    cases=[];excluded=[]
    for i,t in started.items():
        d=done[i];s=suites[t['suiteID']]
        row={'id':i,'name':t['name'],'suite_id':t['suiteID'],'suite':s['normalized'],'platform':s['platform'],'result':d['result'],'skipped':d['skipped'],'hidden':d['hidden']}
        (excluded if d['hidden'] or t['name'].startswith('loading ') else cases).append(row)
    check(cases,label+' substantive cases present')
    check({r['suite'] for r in cases}=={s['normalized'] for s in suites.values()},label+' every declared suite has substantive cases')
    return cases,excluded,kinds

def main():
    check(git('rev-parse',HEAD+'^{tree}')==TREE,'Final immutable local commit/tree')
    tree=git_tree(HEAD)
    stems=['development','first-attempt','mail-final','native-final','node-final','preparation','second-attempt','source-review']
    check(sorted(p.name for p in FINAL.glob('*.tar.xz'))==[s+'.tar.xz' for s in stems],'Exactly eight expected archives')
    check(sorted(p.name for p in FINAL.glob('*.index.json'))==[s+'.tar.index.json' for s in stems],'Exactly eight expected indexes')
    archives={};archive_reports=[]
    source_expectations={'development':None,'source-review':None,'first-attempt':'da78c0bb7bd9e119cc6697a5a476be3b388514c4','second-attempt':'e734e3bd14f6c802a1da1c05969bd51108890ded'}
    for stem in stems:
        ip=FINAL/(stem+'.tar.index.json');iraw=ip.read_bytes();index=decode(iraw)
        ap=FINAL/(stem+'.tar.xz');araw=ap.read_bytes()
        check(index['archive']==ap.name and safe(index['archive']),stem+' exact archive filename')
        check(len(araw)==index['archive_bytes'] and sha(araw)==index['archive_sha256'],stem+' archive size/hash')
        check(index['source_commit']==source_expectations.get(stem,HEAD),stem+' declared source scope')
        indexed=index['members'];names=[m['path'] for m in indexed]
        check(all(safe(n) for n in names),stem+' safe index paths')
        check(len(names)==len(set(names))==len({n.casefold() for n in names}),stem+' unique index paths')
        check(names==sorted(names),stem+' sorted index names')
        originals,omitted=original_inventory(stem)
        check(set(names)==set(originals),stem+' exact original retained inventory')
        data={}
        with tarfile.open(ap,'r:xz') as tar:
            members=tar.getmembers()
            check([m.name for m in members]==names,stem+' exact member names/count/order')
            for member,row in zip(members,indexed):
                check(safe(member.name) and member.isfile() and not member.issym() and not member.islnk(),stem+' safe regular member '+member.name)
                check(member.mode==0o644 and member.mtime==0,stem+' deterministic safe file metadata')
                body=tar.extractfile(member).read()
                check(member.size==row['bytes']==len(body),stem+' member size '+member.name)
                check(sha(body)==row['sha256'],stem+' member hash '+member.name)
                check(body==originals[member.name].read_bytes(),stem+' original bytes '+member.name)
                data[member.name]=body
        omitted_rows=index['omitted_generated_compilation_outputs']
        check(len(omitted_rows)==len({m['path'] for m in omitted_rows}),stem+' unique omitted inventory')
        check({m['path'] for m in omitted_rows}==set(omitted),stem+' complete omitted inventory')
        for row in omitted_rows:
            check(safe(row['path']) and 'Generated browser compilation output' in row['reason'],stem+' declared omission reason')
            b=omitted[row['path']].read_bytes()
            check(len(b)==row['bytes'] and sha(b)==row['sha256'],stem+' omitted output hash')
        archives[stem]=data
        archive_reports.append({'archive':ap.name,'index':ip.name,'archive_sha256':sha(araw),'index_sha256':sha(iraw),'archive_bytes':len(araw),'member_count':len(data),'uncompressed_bytes':sum(map(len,data.values())),'all_members_safe_unique_regular':True,'all_member_names_sizes_hashes_and_original_bytes_match':True,'omitted_generated_outputs_checked':len(omitted_rows),'source_commit_scope':index['source_commit'],'scope':index.get('scope','Final evidence bundle; preparation contains setup/repair provenance with its own original identities.')})
    report['archives']=archive_reports
    report['total_archives']=len(archives);report['total_members_verified']=sum(len(v) for v in archives.values())
    check(report['total_members_verified']==218,'218 original retained archive members')
    copies={
      'mail-final-receipt.json':('mail-final','mail-final/receipt.json'),
      'native-final-verification.json':('native-final','native-final/verification.json'),
      'node-final-verification.json':('node-final','node-final/verification.json'),
      'first-attempt-mail-receipt.json':('first-attempt','first-attempt/mail-final/receipt.json'),
      'second-attempt-mail-receipt.json':('second-attempt','second-attempt/mail-final/receipt.json'),
      'execution.json':('preparation','support/final-execution.json'),
      'evidence-audit.json':('preparation','support/final-evidence-audit.json'),
    }
    for name in ('source-continuity.json','transport-review-binding.json','workspace-and-plan-binding.json','runner-test-review.json','published-readback.json'):
        copies[name]=('source-review','source-review/final-71edec2d/'+name)
    copied=[]
    for name,(archive,member) in copies.items():
        b=(FINAL/name).read_bytes();check(b==archives[archive][member],'Exact standalone copy '+name)
        copied.append({'path':name,'archive':archive+'.tar.xz','member':member,'sha256':sha(b),'bytes':len(b)})
    report['standalone_copies']=copied
    audit=decode((FINAL/'evidence-audit.json').read_bytes());execution=decode((FINAL/'execution.json').read_bytes())
    check(audit['status']=='PASS' and audit['success'] is True and not audit['failures'],'Independent prior evidence audit passed')
    check(audit['auditor_sha256']==sha(archives['preparation']['support/audit_final_mail.py']),'Prior evidence auditor code identity')
    check(audit['source_commit']==execution['head']==HEAD and audit['source_tree']==execution['tree']==TREE,'Final receipt source agreement')
    check(execution['status']=='PASS' and execution['source_unchanged'] is True,'Final execution passed unchanged source')
    check(all(r['exit_code']==0 for r in execution['runs']),'All outer run exit codes zero')
    check({r['name'] for r in execution['runs']}=={'runner-controls','runtime-controls','mail-final','native-final','node-final'},'Complete outer run names')
    for r in execution['runs']:
        if r['name'] in ('mail-final','native-final','node-final'):
            b=archives[r['name']][r['name']+'/driver.log']
        else:b=archives['preparation']['support/'+r['name']+'.log']
        check(sha(b)==r['log_sha256'],'Outer driver log hash '+r['name'])
    historical=[]
    for stem,commit in [('first-attempt','da78c0bb7bd9e119cc6697a5a476be3b388514c4'),('second-attempt','e734e3bd14f6c802a1da1c05969bd51108890ded')]:
        r=decode(archives[stem][stem+'/mail-final/receipt.json']);e=decode(archives[stem][stem+'/final-execution.json'])
        check(r['status']==e['status']=='FAIL' and r['starting_commit']==e['head']==commit,stem+' preserved failed source/status')
        historical.append({'archive':stem+'.tar.xz','source_commit':commit,'status':'FAIL','counted_in_final_acceptance':False})
    report['historical_scopes']=historical+[{'archive':'development.tar.xz','source_commit':None,'status':'mixed historical development','counted_in_final_acceptance':False},{'archive':'source-review.tar.xz','source_commit':None,'status':'per-record source identities, including both failed attempts','counted_in_final_acceptance':False},{'archive':'preparation.tar.xz','source_commit':HEAD,'status':'setup and repair provenance plus final execution/auditor; individual original identities retained','counted_in_final_acceptance':False}]
    final_receipts={}
    final_cases=[];groups=[];source_snapshots=[]
    mail=decode(archives['mail-final']['mail-final/receipt.json']);final_receipts['mail']=mail
    check(mail['status']=='PASS' and mail['starting_commit']==HEAD and mail['source_unchanged'] is True,'Final Mail source and status')
    check(mail['source_before']==mail['source_after'],'Mail before/after input snapshots')
    check(len(mail['checks'])==13 and all(c['status']=='PASS' and c['exit_code']==0 for c in mail['checks']),'All 13 Mail checks passed')
    for name,value in mail['source_before'].items():
        check(name in tree,'Mail source key in final Git tree '+name)
        check(sha(git('show',HEAD+':'+name,binary=True))==value,'Mail source snapshot hash '+name)
    source_snapshots.append({'cohort':'mail','source_commit':HEAD,'source_inputs':len(mail['source_before']),'before_after_equal':True,'source_hashes_against_git':True})
    for c in mail['checks']:
        b=archives['mail-final']['mail-final/'+c['log']]
        check(sha(b)==c['log_sha256'],'Mail log binding '+c['name'])
        if 'tests' not in c:continue
        cwd=Path(c['cwd']);cases,excluded,kinds=parse_stream(b,cwd,'mail/'+c['name'])
        retained=decode(archives['mail-final']['mail-final/'+c['case_list']])
        check(retained['cases']==[{k:r[k] for k in ('name','suite_id','result','skipped','hidden')} for r in cases],c['name']+' exact raw/retained case list')
        check({k:v for k,v in retained.items() if k!='cases'}==c['tests'],c['name']+' retained/receipt test summary')
        check(retained['valid'] is True and retained['passed']==len(cases) and retained['failed']==retained['skipped']==retained['errors']==0,c['name']+' summary result counts')
        actual_suites={r['suite'] for r in cases}
        if c['name'].startswith('core-'):
            expected={p for p in tree if p.startswith('packages/quds_mail_core/test/') and p.endswith('_test.dart')}
        elif c['name']=='store-vm':
            expected={p for p in tree if p.startswith('packages/quds_mail_store/test/') and p.endswith('_test.dart') and p.count('/')==3 and not p.endswith('/browser_problem_test.dart')}
        else:
            expected={'packages/quds_mail_store/'+p for p in ('test/codec_test.dart','test/platform_configuration_test.dart','test/browser_problem_test.dart')}
        check(actual_suites==expected,c['name']+' complete expected suite coverage')
        expected_platform='node' if c['name'].endswith('node') else 'vm'
        check({r['platform'] for r in cases}=={expected_platform},c['name']+' platform')
        row={'cohort':'mail','name':c['name'],'platform':expected_platform,'passed':len(cases),'suites':len(actual_suites),'hidden_loading_events_excluded':len(excluded),'raw_log_sha256':sha(b),'case_list_sha256':sha(archives['mail-final']['mail-final/'+c['case_list']]),'raw_case_list_receipt_agree':True}
        groups.append(row);final_cases.extend({**r,'cohort':'mail','group':c['name']} for r in cases)
    for cohort in ('native','node'):
        stem=cohort+'-final';data=archives[stem];receipt=decode(data[stem+'/verification.json']);final_receipts[cohort]=receipt
        check(receipt['source_commit']==HEAD and receipt['source_tree']==TREE,stem+' final source identity')
        check(receipt['success'] is True and receipt['source_unchanged'] is True and receipt['environment_unchanged'] is True,stem+' passing unchanged snapshots')
        check(receipt['source_head_unchanged'] is True and receipt['source_index_unchanged'] is True and receipt['tracked_worktree_clean_after'] is True,stem+' frozen Git identity')
        for key in ('source_mismatches','environment_mismatches','unexpected_native_mappings_after'):check(not receipt[key],stem+' empty mismatch '+key)
        snapshots={}
        for name,expected_hash in receipt['manifest_sha256'].items():
            b=data[stem+'/'+name];check(sha(b)==expected_hash,stem+' manifest hash '+name);snapshots[name]=decode(b)
        check(snapshots['source-before.json']==snapshots['source-after.json'],stem+' source snapshots equal')
        check(snapshots['environment-before.json']==snapshots['environment-after.json'],stem+' recorded environment snapshots equal')
        source=snapshots['source-before.json'];check(len(source)==receipt['source_input_count'],stem+' source input count')
        for name,row in source.items():
            check(name in tree and row['git_blob']==tree[name]['git_blob'] and row['mode']==tree[name]['mode'],stem+' final Git entry '+name)
        source_snapshots.append({'cohort':cohort,'source_commit':HEAD,'source_tree':TREE,'source_inputs':len(source),'before_after_equal':True,'all_snapshot_git_blobs_and_modes_match_final_tree':True,'environment_snapshot_count':len(snapshots['environment-before.json']),'environment_live_rehash_performed':False})
        plan_raw=git('show',HEAD+':'+receipt['plan'],binary=True);check(sha(plan_raw)==receipt['plan_sha256'],stem+' frozen plan hash')
        plan=decode(plan_raw);planned={g['name']:g for g in plan['groups']};check(len(planned)==len(plan['groups']),stem+' unique groups')
        expected_checks=set(planned)|{'whitespace'}
        if plan.get('analysis'):expected_checks.add('analysis')
        if plan.get('format'):expected_checks.add('format')
        check({r['name'] for r in receipt['runs']}==expected_checks and len(receipt['runs'])==len(expected_checks),stem+' complete unique checks')
        check(receipt['analysis_files']==plan.get('analysis',[]) and receipt['formatted_files']==plan.get('format',[]),stem+' exact analysis/format selection')
        subtotal=0
        for c in receipt['runs']:
            check(c['accepted'] is True and c['exit_code']==0,stem+' accepted '+c['name'])
            b=data[stem+'/'+c['log']];check(sha(b)==c['log_sha256'],stem+' log binding '+c['name'])
            packed=data[stem+'/'+c['compressed_log']];check(sha(packed)==c['compressed_log_sha256'] and gzip.decompress(packed)==b,stem+' gzip/raw equivalence '+c['name'])
            if c['name'] not in planned:continue
            g=planned[c['name']];cwd=REPO/g['cwd'];cases,excluded,kinds=parse_stream(b,cwd,stem+'/'+c['name'])
            case_bytes=data[stem+'/'+c['cases_file']];error_bytes=data[stem+'/'+c['errors_file']]
            check(sha(case_bytes)==c['cases_sha256'] and sha(error_bytes)==c['errors_sha256'],stem+' case/error bindings '+c['name'])
            retained=decode(case_bytes);check(decode(error_bytes)==[],stem+' empty error list '+c['name'])
            normalized=[{'id':x['id'],'name':x['name'],'suite':normalize_suite(x['suite'],cwd),'result':x['result'],'skipped':x['skipped']} for x in retained]
            check(normalized==[{k:r[k] for k in ('id','name','suite','result','skipped')} for r in cases],stem+' exact raw/retained case list '+c['name'])
            expected={str(PurePosixPath(g['cwd'])/p) for p in g['tests']};actual={r['suite'] for r in cases}
            check(actual==expected,stem+' complete requested suite coverage '+c['name'])
            platform=g.get('platform','vm');check({r['platform'] for r in cases}=={platform},stem+' recorded platform '+c['name'])
            check(c['passed']==len(cases) and c['failed']==c['skipped']==0,stem+' receipt counts '+c['name'])
            per_suite=collections.Counter(r['suite'] for r in cases)
            check({normalize_suite(p,cwd):v for p,v in c['per_suite'].items()}=={p:{'passed':n,'failed':0,'skipped':0} for p,n in per_suite.items()},stem+' per-suite counts '+c['name'])
            for key in ('missing_requested_suites','unexpected_suites','empty_requested_suites','unfinished_reporter_events','protocol_anomalies'):check(not c[key],stem+' no '+key)
            check(c['reporter_error_count']==0 and c['reporter_success'] is True and c['strict_event_accounting']['valid'] is True,stem+' strict reporter acceptance')
            subtotal+=len(cases);groups.append({'cohort':cohort,'name':c['name'],'platform':platform,'passed':len(cases),'suites':len(actual),'hidden_loading_events_excluded':len(excluded),'raw_log_sha256':sha(b),'case_list_sha256':sha(case_bytes),'raw_case_list_receipt_agree':True});final_cases.extend({**r,'cohort':cohort,'group':c['name']} for r in cases)
        check(receipt['passed']==subtotal and receipt['failed']==receipt['skipped']==0,stem+' final totals')
    counts=collections.Counter((r['platform'],r['suite'],r['name']) for r in final_cases)
    scenarios={(r['suite'],r['name']) for r in final_cases};multi=collections.defaultdict(set)
    for r in final_cases:multi[(r['suite'],r['name'])].add(r['platform'])
    totals={'raw_successful_test_executions':len(final_cases),'unique_platform_suite_case_executions':len(counts),'repeated_same_platform_executions':sum(n-1 for n in counts.values()),'unique_suite_case_scenarios_across_platforms':len(scenarios),'scenarios_exercised_on_multiple_platforms':sum(len(s)>1 for s in multi.values()),'raw_by_cohort':dict(collections.Counter(r['cohort'] for r in final_cases)),'raw_by_platform':dict(collections.Counter(r['platform'] for r in final_cases)),'unique_by_platform':dict(collections.Counter(k[0] for k in counts)),'unique_suites_across_platforms':len({r['suite'] for r in final_cases})}
    for key,value in totals.items():check(audit['counts'][key]==value,'Summary/recomputed agreement '+key)
    check(not audit['counts']['repeated_same_platform_cases'] and totals['repeated_same_platform_executions']==0,'No duplicate same-platform cases')
    check(totals['raw_successful_test_executions']==631 and totals['unique_suite_case_scenarios_across_platforms']==508 and totals['unique_suites_across_platforms']==48,'631 / 508 / 48 final totals')
    for cohort in ('mail','native','node'):
        reported={g['name']:g for g in audit['cohorts'][cohort]['groups']}
        ours={g['name']:{k:g[k] for k in ('name','platform','passed','suites')} for g in groups if g['cohort']==cohort}
        check(reported==ours,'Cohort group summary agreement '+cohort)
    report['final_coverage']={'counts':totals,'failed':0,'skipped':0,'groups':groups,'raw_reporter_streams':len(groups),'raw_cases_and_retained_lists_and_summaries_agree':True,'coverage_manifest_sha256':sha(canonical(sorted([{'cohort':r['cohort'],'group':r['group'],'platform':r['platform'],'suite':r['suite'],'name':r['name']} for r in final_cases],key=lambda r:(r['platform'],r['suite'],r['name'],r['cohort'],r['group']))))}
    report['final_source_snapshots']=source_snapshots
    # Verify the final reviewed manifest archived inside mixed-history source review.
    prefix='source-review/final-71edec2d/'
    reviewed=decode(archives['source-review'][prefix+'all-reviewed-inputs.json']);binding=decode((FINAL/'transport-review-binding.json').read_bytes())
    check(len(reviewed)==38 and sha(canonical(reviewed))==binding['all_reviewed_inputs_manifest_sha256'],'All 38 reviewed input manifest identity')
    for row in reviewed:
        b=git('show',HEAD+':'+row['path'],binary=True)
        check(row['git_blob_sha1']==tree[row['path']]['git_blob'] and sha(b)==row['sha256'] and len(b)==row['bytes'],'Reviewed source byte binding '+row['path'])
    published=decode((FINAL/'published-readback.json').read_bytes());check(published['commit']==HEAD and published['tree']==TREE and published['remote_tree_matches_expected'] is True,'Copied immutable readback matches final source')
    check(binding['published_commit']==HEAD and binding['published_tree']==TREE,'Copied review binding source')
    continuity=decode((FINAL/'source-continuity.json').read_bytes());check(continuity['published_commit']==HEAD and continuity['published_tree']==TREE and continuity['baseline_commit']=='479e1e038af0467b7f07b35d80bac9e4cc60a198','Office continuity identities retained')
    for name,expected in [('first-attempt-da78c0bb','da78c0bb7bd9e119cc6697a5a476be3b388514c4'),('second-attempt-e734e3bd','e734e3bd14f6c802a1da1c05969bd51108890ded')]:
        d=decode(archives['source-review']['source-review/'+name+'/failed-gate-summary.json']);check(d['status']=='FAIL' and d['source_commit']==expected,'Historical source review identity '+name)
    report['scope']={'archive_extraction_performed':False,'original_evidence_bytes_compared':True,'copied_receipts_compared':True,'final_json_reporter_streams_independently_parsed':True,'full_runtime_rehash_performed':False,'tests_or_builds_executed':False,'github_actions_accessed':False,'fresh_incoming_refs_captured':False,'historical_development_failed_and_preparation_records_excluded_from_final_case_counts':True,'trust_limit':'Integrity, provenance, source identity and internal acceptance consistency of retained artifacts; no independent rerun or external signature claim.'}
    report['status']='PASS';report['success']=True

try:
    main()
except BaseException as error:
    report['status']='FAIL';report['success']=False;report['failures'].append({'error':str(error),'type':type(error).__name__,'traceback':traceback.format_exc()})
finally:
    report['audited_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();report['checks_performed']=checks
    report['auditor_path']='verification/audit_final_archives.py';report['auditor_sha256']=sha(Path(__file__).read_bytes())
    OUTPUT.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'checks':checks,'archives':report.get('total_archives'),'members':report.get('total_members_verified'),'coverage':report.get('final_coverage',{}).get('counts'),'failures':[f['error'] for f in report['failures']]},indent=2))
raise SystemExit(0 if report['status']=='PASS' else 1)

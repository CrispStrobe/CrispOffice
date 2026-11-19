#!/usr/bin/env python3
"""Read-only current Mail preservation review; never executes product tests."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
from datetime import datetime,timezone
BASE='0bd53e3e2b0d75ae48a4d7807dcddd123ab477f9'
UPSTREAM='76fe761f1c97c31ca8d8add405aa54c436a336aa'
EXPECTED_PATCH_TOKENS={'packages/quds_office_editor/example/lib/studio_mail_native.dart': '73c491913834c63d521771c4926ffbd8dd6284361e5a59a5ff005494d8286919', 'packages/quds_office_editor/example/test/studio_mail_test.dart': '038f9fbc75cff0a48b7e1fa9a380dffc4e6c0baa2a4735f2e6af4621f9d7b812'}
MAIL_PACKAGES=['quds_mail_core','quds_mail_store','quds_mail_transport','quds_mail_mime','quds_mail_ui']
PLAN_ROOT='docs/validation/office-resume-main-20261119/main-refresh/'

def sha(data):return hashlib.sha256(data).hexdigest()
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


def token_hash(data):return sha(json.dumps(dart_tokens(data.decode()),ensure_ascii=False,separators=(',',':')).encode())

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--repo',required=True,type=Path);p.add_argument('--target',required=True);p.add_argument('--report',required=True,type=Path);args=p.parse_args()
 repo=args.repo.resolve();issues=[]
 def git(*parts):return subprocess.check_output(['git','-C',str(repo),*parts])
 def show(ref,path):return git('show',ref+':'+path)
 def tree(ref):
  result={}
  for row in git('ls-tree','-rz',ref).split(b'\0'):
   if row:
    meta,path=row.split(b'\t',1);mode,kind,blob=meta.decode().split();result[path.decode()]=dict(mode=mode,kind=kind,git_blob=blob)
  return result
 def check(ok,message):
  if not ok:issues.append(message)
 target=git('rev-parse',args.target).decode().strip();base=tree(BASE);incoming=tree(UPSTREAM);final=tree(target)
 scopes=[]
 for name in MAIL_PACKAGES:
  prefix='packages/'+name+'/'
  a={p:v for p,v in base.items() if p.startswith(prefix)};b={p:v for p,v in incoming.items() if p.startswith(prefix)};c={p:v for p,v in final.items() if p.startswith(prefix)}
  check(a==b==c,'Mail package changed: '+name);scopes.append(dict(package=name,records=len(c),identical_to_base_and_incoming=a==b==c))
 fork=lambda t:{p:v for p,v in t.items() if p.startswith('third_party/enough_mail/')}
 check(fork(final)==fork(incoming),'Incoming vendored send transaction or other fork records were altered')
 fork_changes=[p for p in sorted(fork(base).keys()|fork(final).keys()) if base.get(p)!=final.get(p)]
 expected_fork={'third_party/enough_mail/lib/src/mail/mail_client.dart','third_party/enough_mail/lib/src/mail/mail_exception.dart','third_party/enough_mail/lib/src/private/mail/send_message_transaction.dart','third_party/enough_mail/test/mail/mail_send_transaction_test.dart'}
 check(set(fork_changes)==expected_fork,'Unexpected vendored delta from qualified base')
 def is_studio_mail(path):
  return path.startswith('packages/quds_office_editor/example/') and Path(path).suffix=='.dart' and (Path(path).name.startswith('studio_mail') or Path(path).name.startswith('studio_saved_mail'))
 paths={p for p in incoming if is_studio_mail(p)};check(paths=={p for p in final if is_studio_mail(p)},'Modular Studio Mail pathset changed')
 records=[]
 for path in sorted(paths):
  if path in EXPECTED_PATCH_TOKENS:
   actual=token_hash(show(target,path));check(actual==EXPECTED_PATCH_TOKENS[path],'Confirmed-send correction tokens differ: '+path)
   check(incoming[path]['mode']==final[path]['mode'],'Mail source mode changed: '+path)
   records.append(dict(path=path,review='reviewed correction; formatter whitespace and two optional expect-call trailing commas separately inspected',git_blob=final[path]['git_blob'],content_sha256=sha(show(target,path)),actual_token_sha256=actual,expected_token_sha256=EXPECTED_PATCH_TOKENS[path]))
  else:
   check(final.get(path)==incoming.get(path),'Incoming modular Mail file changed: '+path)
   records.append(dict(path=path,review='exact incoming mode/type/blob preserved',git_blob=final[path]['git_blob']))
 strings='packages/quds_office_editor/example/lib/studio_strings.dart'
 # Reviewed diff removes only two optional trailing commas in localized _t calls.
 strings_equal=token_hash(show(target,strings))=='79d78ac1e98264a083052b1ff87eff95c14fe609b9a33514466d0395fcfec2ba'
 check(strings_equal,'Studio strings differ beyond formatting from incoming main')
 for path in ['pubspec.yaml','pubspec.lock','third_party/enough_mail/pubspec.yaml']:
  check(final[path]==base[path]==incoming[path],'Dependency input changed: '+path)
 studio_pubspec='packages/quds_office_editor/example/pubspec.yaml'
 check(final[studio_pubspec]==incoming[studio_pubspec],'New Studio direct transport dependency was not preserved')
 native=json.loads(show(target,PLAN_ROOT+'native-plan.json'));node=json.loads(show(target,PLAN_ROOT+'node-plan.json'))
 required_native={'studio-mail-modular':('packages/quds_office_editor/example',['test/studio_mail_compose_test.dart','test/studio_mail_discovery_test.dart','test/studio_mail_lifecycle_test.dart','test/studio_mail_message_loader_test.dart','test/studio_mail_operation_test.dart','test/studio_mail_test.dart','test/studio_mail_web_test.dart','test/studio_saved_mail_test.dart']),'mail-send-transaction-vm':('third_party/enough_mail',['test/mail/mail_client_send_test.dart','test/mail/mail_send_transaction_test.dart']),'mail-bounded-reader-vm':('packages/quds_mail_transport',['test/native_provider_test.dart'])}
 required_node={'mail-transport-boundary-node':('packages/quds_mail_transport',['test/unsupported_test.dart']),'mail-mime-entry-node':('packages/quds_mail_mime',['test/portable_import_test.dart']),'mail-fork-mime-entry-node':('third_party/enough_mail',['test/quds_portable_mime_test.dart'])}
 for plan,expected,platform in [(native,required_native,'vm'),(node,required_node,'node')]:
  groups={g['name']:g for g in plan['groups']}
  for name,(cwd,tests) in expected.items():
   g=groups.get(name,{})
   check(g.get('cwd')==cwd and g.get('tests')==tests and g.get('platform','vm')==platform,'Committed Mail suite selection differs: '+name)
  for g in plan['groups']:
   for test in g['tests']:check(g['cwd']+'/'+test in final,'Planned test missing from frozen source: '+test)
 for kind in ['analysis','format']:
  check(paths|{strings}|expected_fork <=set(native[kind]),'A changed Mail static target is absent: '+kind)
 report=dict(schema=1,source_review_passed=not issues,reviewed_at_utc=datetime.now(timezone.utc).isoformat(),source_commit=target,source_tree=git('rev-parse',target+'^{tree}').decode().strip(),qualified_base=BASE,incoming_main=UPSTREAM,issues=issues,mail_package_scopes=scopes,vendored_fork_records=len(fork(final)),vendored_fork_exactly_preserves_incoming=True if fork(final)==fork(incoming) else False,vendored_delta_from_qualified_base=fork_changes,studio_mail_records=records,studio_strings_preserved_except_formatting=strings_equal,formatter_review='Full token diff checked: two optional trailing commas added to expect calls, two removed from localized _t calls; no other changed tokens beyond the reviewed correction. Frozen formatted hashes are pinned, not a general comma-normalization rule.',root_lock_and_manifest_preserved=all(final[p]==base[p]==incoming[p] for p in ['pubspec.yaml','pubspec.lock']),studio_direct_transport_dependency_preserved=final[studio_pubspec]==incoming[studio_pubspec],committed_plans=dict(native=PLAN_ROOT+'native-plan.json',node=PLAN_ROOT+'node-plan.json',total_native_suites=sum(len(g['tests']) for g in native['groups']),total_node_suites=sum(len(g['tests']) for g in node['groups']),required_mail_native_suites=sum(len(v[1]) for v in required_native.values()),required_mail_node_suites=sum(len(v[1]) for v in required_node.values()),analysis_paths=len(native['analysis']),format_paths=len(native['format'])),scope='Source/selection review only. The earlier accepted 0bd execution results and its 395-record historical Mail continuity remain bound to 0bd. This incoming Mail fork has changed; no historical test cases are added to the fresh run.',confirmed_submission='The committed typed catch clears the accepted draft/uncertain state with current-session guard; the new regression checks one send, bounded accepted feedback, and a blank next composer without retry acknowledgement.',runtime_tests_executed=0,qualification_status='Await completed fresh native/Node receipts and independent event audit.',review_script_sha256=sha(Path(__file__).read_bytes()))
 args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
 print(json.dumps({k:report[k] for k in ['source_review_passed','source_commit','source_tree','issues','committed_plans']}))
 raise SystemExit(0 if not issues else 1)
if __name__=='__main__':main()

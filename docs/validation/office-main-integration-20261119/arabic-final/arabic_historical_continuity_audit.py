#!/usr/bin/env python3
"""Read-only source/archived-evidence audit across the final Office integration."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import posixpath
import re
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--head', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
BASE = '39843ed4874c7b56572c7aa8195716e5892aeca2'
EVIDENCE = 'docs/validation/thesaurus-20261118/resumed-20261119/evidence/'
FIXTURE = 'docs/validation/thesaurus-20261118/continuation/local/fixtures/'

def git(*argv):
    return subprocess.check_output(['git', '-C', str(args.repo), *argv])

def sha(data):
    return hashlib.sha256(data).hexdigest()

head = git('rev-parse', args.head+'^{commit}').decode().strip()
def tree(ref):
    entries = {}
    for row in git('ls-tree', '-rz', ref).split(b'\0'):
        if row:
            metadata, path = row.split(b'\t',1)
            entries[path.decode()] = metadata.decode().split()
    return entries

trees = {BASE:tree(BASE),head:tree(head)}
reader = subprocess.Popen(['git','-C',str(args.repo),'cat-file','--batch'],stdin=subprocess.PIPE,stdout=subprocess.PIPE)
cache = {}
def read(ref,path):
    blob = trees[ref][path][2]
    if blob not in cache:
        reader.stdin.write((blob+'\n').encode());reader.stdin.flush()
        observed,kind,size=reader.stdout.readline().decode().split()
        cache[blob]=reader.stdout.read(int(size))
        assert reader.stdout.read(1)==b'\n' and kind=='blob' and observed==blob
    return cache[blob]

def archive(archive_name,index_name):
    index=json.loads(read(head,EVIDENCE+index_name))
    packed=read(head,EVIDENCE+archive_name)
    expected_bytes=index.get('archive_bytes',index.get('bytes'))
    expected_sha=index.get('archive_sha256',index.get('sha256'))
    assert len(packed)==expected_bytes and sha(packed)==expected_sha
    with tarfile.open(fileobj=io.BytesIO(packed),mode='r:xz') as tar:
        members=tar.getmembers()
        assert all(m.isfile() and not m.name.startswith('/') and '..' not in PurePosixPath(m.name).parts for m in members)
        assert len(members)==len({m.name for m in members})
        files={m.name:tar.extractfile(m).read() for m in members}
    expected={row['path']:row for row in index['files']}
    assert set(files)==set(expected)
    for name,data in files.items():
        assert len(data)==expected[name]['bytes'] and sha(data)==expected[name]['sha256'],name
    return files,{'archive':EVIDENCE+archive_name,'bytes':len(packed),'sha256':sha(packed),'members':len(files),'all_members_verified':True}

union,union_archive=archive('combined-final.tar.xz','combined-final-index.json')
native,native_archive=archive('native-final-evidence.tar.xz','native-final-evidence-index.json')
receipt=json.loads(union['receipt.json'])
native_receipt=json.loads(native['receipt.json'])
source=json.loads(union['source-before.json'])
native_source=json.loads(gzip.decompress(native['source-inputs.json.gz']))
assert union['source-before.json']==union['source-after.json']
assert union['environment-before.json']==union['environment-after.json']
assert native['runtime-inputs-before.json.gz']==native['runtime-inputs-after.json.gz']
assert receipt['source_commit']==native_receipt['base_commit']==BASE
assert receipt['success'] and receipt['passed']==2018 and receipt['suite_count']==129
ordinary={p:v for p,v in source.items() if not p.startswith('__')}
ordinary_native={p:v for p,v in native_source.items() if not p.startswith('__')}
assert ordinary==ordinary_native and len(ordinary)==4992
for path,entry in ordinary.items():
    data=read(BASE,path)
    assert sha(data)==entry['sha256'] and len(data)==entry['bytes'],path
changed={p for p in trees[BASE].keys()|trees[head].keys() if trees[BASE].get(p)!=trees[head].get(p)}
inventory_changes=[{'path':p,'qualified_blob':trees[BASE][p][2],'current_blob':trees[head].get(p,[None,None,None])[2]} for p in ordinary if p in changed]
new_product_paths=sorted(p for p in changed if p not in trees[BASE] and not p.startswith('docs/'))
plan=receipt['plan']
plan_path='docs/validation/thesaurus-20261118/reconciled/plan.json'
assert plan==json.loads(read(BASE,plan_path)) and read(BASE,plan_path)==read(head,plan_path)
harness=[]
for path,digest in receipt['harness_sha256'].items():
    assert sha(read(BASE,path))==digest
    harness.append({'path':path,'unchanged':read(BASE,path)==read(head,path),'qualified_sha256':digest,'current_sha256':sha(read(head,path))})

root_old=source['__workspace_binding__']['package_roots']['quds_mail_core']['source'].removesuffix('/packages/quds_mail_core')
package_roots={name:row['source'].removeprefix(root_old+'/') for name,row in source['__workspace_binding__']['package_roots'].items()}
package_roots['quds_mail_transport']='packages/quds_mail_transport'
directives=re.compile(r'''^\s*(?:import|export|part)\s+(["'].*?);''',re.M|re.S)
quoted=re.compile(r'''["']([^"']+)["']''')
dependency_cache={}
def dependencies(ref,path):
    key=(ref,path)
    if key in dependency_cache:return dependency_cache[key]
    local,external,missing=set(),set(),set()
    text=read(ref,path).decode()
    for directive in directives.findall(text):
        for uri in quoted.findall(directive):
            if uri.startswith('dart:'):continue
            if uri.startswith('package:'):
                package,relative=uri[8:].split('/',1)
                if package not in package_roots:
                    external.add(package);continue
                target=package_roots[package]+'/lib/'+relative
            elif ':' in uri:
                missing.add(path+' -> '+uri);continue
            else:
                target=posixpath.normpath(posixpath.join(posixpath.dirname(path),uri))
            if target not in trees[ref]:missing.add(path+' -> '+target)
            else:local.add(target)
    dependency_cache[key]=(local,external,missing)
    return dependency_cache[key]

def closure(ref,start):
    pending=[start];seen=set();external=set();missing=set()
    while pending:
        path=pending.pop()
        if path in seen:continue
        seen.add(path)
        linked,outside,absent=dependencies(ref,path)
        pending.extend(linked-seen);external.update(outside);missing.update(absent)
    return seen,external,missing

def closure_record(path):
    old,external_old,missing_old=closure(BASE,path)
    new,external_new,missing_new=closure(head,path)
    overlapping=sorted((old|new)&changed)
    return {'path':path,'test_or_entrypoint_unchanged':path not in changed,'qualified_tracked_closure_files':len(old),'current_tracked_closure_files':len(new),'closure_added':sorted(new-old),'closure_removed':sorted(old-new),'changed_tracked_closure_inputs':overlapping,'changed_vendor_inputs':[p for p in overlapping if p.startswith('third_party/')],'external_package_names':sorted(external_old|external_new),'unresolved_tracked_directives':sorted(missing_old|missing_new)}

suite_checks=[]
for group in plan['groups']:
    for test in group['tests']:
        entry=closure_record(group['cwd']+'/'+test)
        entry['cohort']=group['name'];suite_checks.append(entry)
assert len(suite_checks)==129
cohorts=[]
for group in plan['groups']:
    checks=[x for x in suite_checks if x['cohort']==group['name']]
    old_run=next(r for r in receipt['runs'] if r['name']==group['name'])
    cohorts.append({'name':group['name'],'suites':len(checks),'historical_cases':old_run['passed'],'suite_sources_identical':all(x['test_or_entrypoint_unchanged'] for x in checks),'suites_with_changed_tracked_closure':sum(bool(x['changed_tracked_closure_inputs']) for x in checks),'changed_closure_paths':sorted({p for x in checks for p in x['changed_tracked_closure_inputs']}),'vendor_overlap':sorted({p for x in checks for p in x['changed_vendor_inputs']})})

fixture_checks=[]
for name,entry in native_source.items():
    if name.startswith('__fixture__/'):
        path=FIXTURE+name.removeprefix('__fixture__/')
    elif name.startswith('__helper__/'):
        path=name.removeprefix('__helper__/')
    else:continue
    assert sha(read(BASE,path))==entry['sha256'],path
    fixture_checks.append({'path':path,'qualified_sha256':entry['sha256'],'current_sha256':sha(read(head,path)),'unchanged':path not in changed})
native_audit=json.loads(native['native-test-audit.json'])
assert native_audit['passed']==208 and native_audit['suite_count']==14
native_suites=[]
for suite in native_audit['suites']:
    absolute=suite['path']
    if '/packages/quds_office_editor/' in absolute:
        path='packages/quds_office_editor/'+absolute.split('/packages/quds_office_editor/',1)[1]
    else:
        path=FIXTURE+absolute.split('/fixtures/',1)[1]
    native_suites.append(closure_record(path))
web_entry=closure_record(FIXTURE+'lib/main.dart')
for run in native_receipt['runs']:
    assert run['exit_code']==0
    for stream in ['stdout','stderr']:
        assert sha(native[run[stream]])==run[stream+'_sha256']
compiled=json.loads(gzip.decompress(native['browser-build-files.json.gz']))
installed=json.loads(gzip.decompress(native['installed-file-inventory.json.gz']))
assert len(compiled)==1155 and sum(x['bytes'] for x in compiled)==87446576
assert len(installed)==1156 and sum(x['bytes'] for x in installed)==87447167
old_files={x['path']:x for x in compiled};new_files={x['path']:x for x in installed}
overlays=sorted(p for p in old_files.keys()|new_files.keys() if old_files.get(p)!=new_files.get(p))
assert overlays==['index.html','offline-install.js']
notes_paths=['packages/quds_office_editor/CHANGELOG.md','packages/quds_office_editor/lib/src/embed/office_editors.dart','packages/quds_office_editor/test/word_notes_proofing_controller_test.dart','packages/quds_office_editor/test/word_notes_proofing_pane_test.dart','packages/quds_office_editor/test/word_zotero_notes_pane_test.dart']
notes=[{'path':p,'qualified_blob':trees[BASE][p][2],'current_blob':trees[head][p][2],'unchanged':p not in changed} for p in notes_paths]
groups={prefix:{'tracked_paths':len([p for p in trees[BASE] if p.startswith(prefix)]),'changed_or_added_paths':sorted(p for p in changed if p.startswith(prefix))} for prefix in ['packages/quds_office_engine/','packages/quds_office_editor/','apps/','packages/quds_mail_ui/','packages/quds_mail_mime/','third_party/']}
suite_files_unchanged=sum(x['test_or_entrypoint_unchanged'] for x in suite_checks)
suite_closures_unchanged=sum(not x['changed_tracked_closure_inputs'] for x in suite_checks)
native_closures_unchanged=sum(not x['changed_tracked_closure_inputs'] for x in native_suites)
closure_scope={
    'original_suite_files_unchanged':suite_files_unchanged,
    'original_suite_files_changed':len(suite_checks)-suite_files_unchanged,
    'original_tracked_closures_unchanged':suite_closures_unchanged,
    'original_tracked_closures_changed':len(suite_checks)-suite_closures_unchanged,
    'native_tracked_closures_unchanged':native_closures_unchanged,
    'native_tracked_closures_changed':len(native_suites)-native_closures_unchanged,
    'web_tracked_closure_unchanged':not web_entry['changed_tracked_closure_inputs'],
    'notes_file_bytes_unchanged':all(x['unchanged'] for x in notes),
    'fixture_helper_file_bytes_unchanged':all(x['unchanged'] for x in fixture_checks),
    'prior_ac1_continuity_is_a_separate_phase':'ac1e4c8c788ea608402c2260488235c0189efcba',
    'static_closure_change_is_not_a_test_failure':True,
}
qualification_wording=(
    'The preserved 129-suite/2,018-case and separate 14-suite/208-case native results and successful web compilation remain attributed to source 39843ed4. '
    f'{suite_files_unchanged} of 129 original suite files remain identical, while {suite_closures_unchanged} original tracked closures remain identical and {129-suite_closures_unchanged} have changed inputs. '
    f'{native_closures_unchanged} of 14 native tracked closures remain identical; web tracked closure unchanged: {not web_entry["changed_tracked_closure_inputs"]}. '
    f'All five original Notes file bytes preserved: {all(x["unchanged"] for x in notes)}. '
    'File identity, transitive tracked-source continuity and runtime acceptance are separate findings. Prior ac1-phase continuity reports retain their original cutoff and must not be presented as continuity of this newer source. '
    'Fresh affected-source qualification must be reported separately without adding overlapping historical counts. No historical application tests were rerun by this audit, and the historical web build is not a build of this integrated source. '
    'Full current workspace/source/configuration or runtime equality is not claimed.'
)
report={
    'schema':1,'audited_at_utc':datetime.now(timezone.utc).isoformat(),'qualified_source':BASE,'frozen_integrated_source':head,
    'archives':[union_archive,native_archive],
    'historical_evidence':{'union_cases':2018,'union_suites':129,'native_cases':208,'native_suites':14,'native_cases_overlap_union':True,'native_cases_not_added_to_union':True,'union_source_before_after_equal':True,'union_environment_before_after_equal':True,'native_runtime_before_after_equal':True,'historical_source_records_git_blob_verified':len(ordinary),'current_source_records_identical':len(ordinary)-len(inventory_changes),'current_source_records_changed':len(inventory_changes),'changed_records':inventory_changes,'new_product_paths_outside_old_inventory':new_product_paths},
    'union_plan_and_harness':{'129_suite_plan_unchanged':True,'all129_suite_source_files_unchanged':suite_files_unchanged==129,'bound_harness_inputs':harness,'cohorts':cohorts,'suite_closure_checks':suite_checks},
    'native_and_web':{'fixture_helper_checks':fixture_checks,'native_suite_closure_checks':native_suites,'web_entrypoint_closure_check':web_entry,'archived_successful_run_log_hashes_verified':True,'compiled_inventory_files':len(compiled),'compiled_inventory_bytes':sum(x['bytes'] for x in compiled),'installed_inventory_files':len(installed),'installed_inventory_bytes':sum(x['bytes'] for x in installed),'exact_inventory_overlays':overlays,'compiled_application_bytes_present':False,'new_build_performed':False,'full_historical_build_binding_matches_current_tree':False},
    'original_notes_preservation':notes,'product_group_continuity':groups,
    'workspace_and_runtime':{'root_workspace_manifest_unchanged':False,'locked_dependency_bytes_unchanged':'pubspec.lock' not in changed,'effective_package_configuration_not_claimed_identical':True,'current_runtime_not_verified_by_this_audit':True},
    'method':'Immutable Git mode/blob comparisons; all archived member sizes/hashes verified; conservative Dart import/export/part closure walks include all conditional local targets. External SDK/hosted imports and dynamic/native/asset runtime behavior are outside the source closure check; source identity is not a new runtime pass.',
    'source_closure_scope':closure_scope,
    'qualification_wording':qualification_wording,
    'no_github_actions':True,'application_tests_executed':False,'repository_mutations':0,
}
reader.stdin.close();assert reader.wait()==0
args.output.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'head':head,'ordinary_source_records_unchanged':len(ordinary)-len(inventory_changes),'ordinary_source_records_changed':len(inventory_changes),'cohorts':cohorts,'native_changed_closures':[x for x in native_suites if x['changed_tracked_closure_inputs']],'web_changed_closure':web_entry['changed_tracked_closure_inputs'],'unresolved_tracked_directives':sorted({p for x in suite_checks+native_suites+[web_entry] for p in x['unresolved_tracked_directives']}),'all_five_notes_preserved':all(x['unchanged'] for x in notes),'fixture_helpers_unchanged':all(x['unchanged'] for x in fixture_checks),'new_product_paths_count':len(new_product_paths)},indent=2))

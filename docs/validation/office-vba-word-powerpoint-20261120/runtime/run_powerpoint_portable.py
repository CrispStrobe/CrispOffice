from pathlib import Path
import base64,hashlib,json,os,subprocess,sys,time
root=Path('/workspace/scratch/f8bca915f70d')
repo=root/'quds_office_suite'
engine=repo/'packages/quds_office_engine'
work=root/'validation-workspace/packages/quds_office_engine'
dart=root/'toolchains/dart-3.13.7/dart-sdk/bin/dart'
env=os.environ.copy()
env.update({'DART_SUPPRESS_ANALYTICS':'true','CI':'true','PUB_CACHE':str(root/'toolchains/pub-cache')})
env.setdefault('TMPDIR',str(root/'toolchains/tmp'))
packages=root/'validation-workspace/.dart_tool/package_config.json'
logs=root/'toolchains/logs'
build=root/'toolchains/build'
mode=sys.argv[1] if len(sys.argv)>1 else 'conformance'
assert mode in ['conformance','smoke']
prefix=(sys.argv[2]+'-') if len(sys.argv)>2 else ''
assert all(c.isalnum() or c in '-_' for c in prefix)
label=prefix+'powerpoint-'+mode
fixture=engine/'test/fixtures/vba_conformance/powerpoint_shapes_v1.json'
entry='tool/macros/web_vba_conformance.dart' if mode=='conformance' else 'tool/macros/web_vba_powerpoint_smoke.dart'
inputs=['lib/src/automation/office_vba_language.dart','lib/src/automation/office_macro_model.dart','lib/src/automation/office_macro_language.dart','lib/src/automation/operations/slide_steps.dart','lib/src/slide/shapes/drawingml.dart','lib/src/slide/model/pml_presentation.dart',entry,'test/support/vba_conformance.dart','test/fixtures/vba_conformance/powerpoint_shapes_v1.json']
def hashes(): return {name:hashlib.sha256((engine/name).read_bytes()).hexdigest() for name in inputs}
before=hashes()
defines=['-DVBA_CONFORMANCE_BASE64='+base64.b64encode(fixture.read_bytes()).decode()] if mode=='conformance' else []
js=build/(label+'.js')
commands=[('vm',[str(dart),'--packages='+str(packages),*defines,entry]),('compile-js',[str(dart),'compile','js','-O1','--packages='+str(packages),*defines,entry,'-o',str(js)]),('js',['node','-e','globalThis.self = globalThis; require(process.argv[1])',str(js)])]
results=[]
for stage,cmd in commands:
 out=logs/(label+'-'+stage+'.log')
 started=time.time()
 with out.open('w') as f: r=subprocess.run(cmd,cwd=work,env=env,stdout=f,stderr=subprocess.STDOUT)
 result={'stage':stage,'argv':[('<fixture base64, sha256 '+before['test/fixtures/vba_conformance/powerpoint_shapes_v1.json']+'>') if arg.startswith('-DVBA_CONFORMANCE_BASE64=') else arg for arg in cmd],'exit_code':r.returncode,'seconds':round(time.time()-started,3),'log':str(out)}
 results.append(result)
 print(json.dumps(result),flush=True)
 if r.returncode: break
vm=logs/(label+'-vm.log')
jso=logs/(label+'-js.log')
passed=len(results)==3 and all(x['exit_code']==0 for x in results)
equal=passed and vm.read_bytes()==jso.read_bytes()
after=hashes()
receipt={'mode':mode,'source_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'runtime':'Dart SDK 3.13.7 (archive SHA256 eb99aed266efbcb615c6ae21c12f52cfe935b9f208bccc5fea7f64c21e867229)','node':subprocess.check_output(['node','--version'],text=True).strip(),'commands':results,'all_commands_passed':passed,'vm_js_byte_equal':equal,'inputs_before':before,'inputs_after':after,'inputs_changed':{k:[v,after[k]] for k,v in before.items() if v!=after[k]}}
if passed: receipt['canonical_output']=json.loads(vm.read_text())
(logs/(label+'-receipt.json')).write_text(json.dumps(receipt,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({'all_commands_passed':passed,'vm_js_byte_equal':equal,'inputs_changed':receipt['inputs_changed']},indent=2),flush=True)
raise SystemExit(0 if equal else 1)

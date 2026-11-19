from pathlib import Path
import collections, hashlib, json, re, yaml
repo=Path('/workspace/scratch/32e3793609d8/quds_office_suite')
lib=repo/'packages/quds_office_engine/lib'
out=Path('/workspace/scratch/32e3793609d8/validation/vba-dynamic-arrays-offline')
cache=Path('/workspace/scratch/32e3793609d8/runtime/pub-cache/hosted/pub.dev')
config=json.loads(Path('/workspace/scratch/32e3793609d8/runtime/core-validation/.dart_tool/package_config.json').read_text())
resolved={p['name'] for p in config['packages']}
results=[];evidence=set()
for root_name in ['src/automation/office_vba_language.dart','quds_office_automation.dart']:
    root=lib/root_name
    queue=collections.deque([(root,[root])]);seen=set();external={};missing={}
    while queue:
        file,chain=queue.popleft();file=file.resolve()
        if file in seen: continue
        seen.add(file)
        if not file.exists():
            missing[str(file)]=[str(x.relative_to(repo)) for x in chain];continue
        source=file.read_text()
        for directive in re.findall(r'^\s*(?:import|export|part)\s+(.+?);',source,re.M|re.S):
            for uri in re.findall(r"['\"]([^'\"]+)['\"]",directive):
                if uri.startswith('dart:'): continue
                if uri.startswith('package:'):
                    pkg,path=uri[8:].split('/',1)
                    local=repo/'packages'/pkg/'lib'/path
                    if local.exists():
                        queue.append((local,chain+[local]));continue
                    external.setdefault(pkg, {'in_existing_resolved_harness':pkg in resolved,'cached_directories':[p.name for p in cache.glob(pkg+'-*')],'chain':[str(x.relative_to(repo)) for x in chain],'uri':uri})
                    evidence.update(chain)
                elif uri.endswith('.dart'):
                    local=(file.parent/uri).resolve();queue.append((local,chain+[local]))
    results.append({'entry':root_name,'local_sources_in_graph':len(seen),'external_dependencies':external,'missing_local_files':missing})
tests=['office_vba_dynamic_arrays_test.dart','office_vba_arrays_boundaries_test.dart','office_vba_language_test.dart','office_vba_dynamic_arrays_integration_test.dart']
evidence.update(repo/'packages/quds_office_engine/test'/name for name in tests)
evidence.update([repo/'packages/quds_office_engine/pubspec.yaml',repo/'packages/legacy_doc_parser/pubspec.yaml'])
receipt={'status':'blocked_before_execution','tests_run':0,'network_attempted':False,'production_modified':False,'reason':'Direct VBA compiler imports still resolve office_operations, Word proofing, the broad engine barrel, PDF image, and legacy DOC dependencies. Missing compatible cached packages prevent legitimate offline execution. Import show clauses cannot remove transitive library resolution. No stubs or substitute implementations were used.','required_constraints':{'characters':'^1.4.1','image':'^4.5.0','archive_from_legacy_doc_parser':'^4.6.0'},'graph':results,'source_hashes':{str(p.relative_to(repo)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(evidence)},'requested_tests':[str(Path('packages/quds_office_engine/test')/name) for name in tests]}
(out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'status':receipt['status'],'tests_run':0,'missing_compatible_packages':['characters','image','archive^4.6.0'],'receipt':str(out/'receipt.json')},indent=2))

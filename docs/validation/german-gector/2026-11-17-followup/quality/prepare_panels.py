#!/usr/bin/env python3
"""Freeze the six existing quality panels; adapt syntax metadata only."""
import argparse,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--repository',type=Path,required=True);p.add_argument('--commit',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
assert not a.output.exists();a.output.mkdir(parents=True)
names=[('original-30','cases.json'),('development-76','prospective_cases_20261117.json'),('syntax-56','syntax_cases_20261117.json'),('context-83','context_cases_20261117.json'),('completion-28','context_completion_cases_20261117.json'),('holdout-104','context_holdout_20261117.json')]
entries=[]
for name,filename in names:
 path='tools/proofing/german_model/'+filename
 source=subprocess.check_output(['git','show',a.commit+':'+path],cwd=a.repository)
 assert(a.repository/path).read_bytes()==source,'Current panel changed: '+filename
 rows=json.loads(source);adapter='none; exact source bytes'
 if name=='syntax-56':
  assert all('area'in row and'category'not in row for row in rows)
  mapped=[{('category'if key=='area'else key):value for key,value in row.items()}for row in rows]
  for before,after in zip(rows,mapped,strict=True):
   assert{key:value for key,value in before.items()if key!='area'}=={key:value for key,value in after.items()if key!='category'}
  output=(json.dumps(mapped,ensure_ascii=False,indent=2)+'\n').encode();adapter='Rename metadata key area to category; all values, case order and other keys unchanged.'
 else:output=source
 (a.output/(name+'.json')).write_bytes(output)
 entries.append({'name':name,'source_path':path,'source_commit':a.commit,'source_sha256':hashlib.sha256(source).hexdigest(),'run_file':name+'.json','run_sha256':hashlib.sha256(output).hexdigest(),'adapter':adapter,'cases':len(rows),'errors':sum(row['kind']=='error'for row in rows),'clean':sum(row['kind']=='clean'for row in rows)})
manifest={'schema_version':1,'panels':entries,'case_count':sum(e['cases']for e in entries),'interpretation':'Reused, previously frozen synthetic panels. These do not establish representative or prospectively independent German accuracy. No input, expected text, locale or case order is altered.'}
(a.output/'panels.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');print(json.dumps(manifest,ensure_ascii=False,indent=2))

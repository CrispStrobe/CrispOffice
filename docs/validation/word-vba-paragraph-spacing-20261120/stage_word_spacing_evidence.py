#!/usr/bin/env python3
"""Copy completed, accepted evidence into its Git-backed validation record."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

root=Path(__file__).resolve().parent.parent
repo=root/'quds_office_suite'
runtime=root/'runtime'
review=root/'intake-review'
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--delivery',type=Path,required=True)
p.add_argument('--fork',type=Path,required=True)
p.add_argument('--upstream',type=Path,required=True)
p.add_argument('--regression-archive',type=Path,required=True)
p.add_argument('--regression-members',type=Path,required=True)
p.add_argument('--regression-receipt',type=Path,required=True)
p.add_argument('--include-final-review',action='store_true')
a=p.parse_args()
out=repo/'docs/validation/word-vba-paragraph-spacing-20261120'
out.mkdir(parents=True,exist_ok=True)
assert json.loads((a.delivery/'qualification.json').read_text())['accepted']
for source in a.delivery.iterdir():
 if source.is_file():shutil.copy2(source,out/source.name)
files=[
 (a.fork,'publication-fork-refs.txt'),
 (a.upstream,'publication-upstream-refs.txt'),
 (a.regression_archive,'regression-evidence.tar.xz'),
 (a.regression_members,'regression-members.json'),
 (a.regression_receipt,'regression-packaging.json'),
 (runtime/'word-spacing-regression-reproduction.md','regression-reproduction.md'),
 (runtime/'line-spacing-portable-static-final.tar.xz','portable-static-evidence.tar.xz'),
 (runtime/'line-spacing-portable-static-members.json','portable-static-members.json'),
 (runtime/'line-spacing-portable-static-packaging.json','portable-static-packaging.json'),
 (runtime/'line-spacing-development-review.tar.xz','development-review-evidence.tar.xz'),
 (runtime/'line-spacing-development-review/members.json','development-review-members.json'),
 (runtime/'line-spacing-development-review/packaging.json','development-review-packaging.json'),
 (runtime/'line-spacing-development-review/attempts.json','development-attempts.json'),
 (runtime/'line-spacing-development-review/README.md','development-review-README.md'),
 (runtime/'verify_word_spacing_publication.py','verify_word_spacing_publication.py'),
 (Path(__file__),'stage_word_spacing_evidence.py'),
]
if a.include_final_review:
 final=json.loads((review/'evidence-review.json').read_text())
 assert final.get('status') in ('ACCEPTED','PASS') or final.get('accepted') is True
 files.extend([(review/'evidence-review.json','evidence-review.json'),(review/'evidence-review.md','evidence-review.md')])
 for name in ['verify_final_evidence.py','audit_batched_regression.py','audit_checkpoint_archives.py','audit_bounded_progress_archive.py','checkpoint-archives-review.json','bounded-progress-archive-review.json','bounded-timeout-diagnostics-review.json']:
  source=review/name
  if source.is_file():files.append((source,name))
for source,name in files:
 assert source.is_file(),source
 shutil.copy2(source,out/name)
index={}
for f in sorted(out.iterdir()):
 if f.is_file() and f.name not in {'publication-files.json'}:
  data=f.read_bytes();index[f.name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
(out/'publication-files.json').write_text(json.dumps({'scope':'Files in this validation directory; excludes this index to avoid recursion. Exact Git tree binding is verified after merge.','files':index},indent=2,sort_keys=True)+'\n')
print(json.dumps({'destination':str(out),'files_indexed':len(index),'bytes_indexed':sum(i['bytes'] for i in index.values()),'independent_final_review_included':a.include_final_review}))

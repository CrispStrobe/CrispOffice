#!/usr/bin/env python3
"""Remove only LF from already SHA-verified Pub cache hash metadata.

Pub's own cache stores exactly 64 hexadecimal bytes, without a trailing LF.
The archives were checked against these exact locked digests before extraction.
This changes neither the verified digest nor any package contents.
"""
from pathlib import Path
import hashlib,json,re
root=Path.cwd()
report=json.loads((root/'evidence/flutter-setup/pub-cache-receipt.json').read_text())
changes=[]
for row in report['packages']:
 assert row['status'] in ('verified-download','verified-cache')
 if row['status']=='verified-download': assert row['actual_sha256']==row['sha256']
 p=root/'runtime/pub-cache/hosted-hashes/pub.dev'/f"{row['name']}-{row['version']}.sha256"
 data=p.read_bytes()
 expected=row['sha256'].encode()
 if data==expected+b'\n':
  assert re.fullmatch(rb'[0-9a-f]{64}\n',data)
  p.write_bytes(expected)
  changes.append({'path':str(p.relative_to(root)),'verified_archive_sha256':row['sha256'],'before_hex':data.hex(),'after_hex':expected.hex()})
 else: assert data==expected,(str(p),data)
(root/'evidence/flutter-setup/cache-metadata-repair.json').write_text(json.dumps({'reason':'Match Pub-owned cache metadata encoding: 64 hex bytes without LF; archive digest values are unchanged.','changes':changes},indent=2)+'\n')
print('Normalized verified metadata files:',len(changes))

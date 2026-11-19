import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

root = Path('/workspace/scratch/9c3338a48b2c')
repo = root / 'crispoffice'
cwd = repo / 'packages/quds_office_editor/example'
out = root / 'validation/layout-theme'
name = sys.argv[1]
command = sys.argv[2:]
sources = sorted(p for p in command if p.endswith('.dart') and (cwd / p).is_file())
before = {p: hashlib.sha256((cwd / p).read_bytes()).hexdigest() for p in sources}
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
started = time.time()
log = out / f'{name}.log'
with log.open('w') as stream:
    result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
after = {p: hashlib.sha256((cwd / p).read_bytes()).hexdigest() for p in sources}
receipt = {
    'head': head, 'cwd': str(cwd), 'command': command, 'exit_code': result.returncode,
    'elapsed_seconds': round(time.time() - started, 3), 'log': str(log),
    'log_sha256': hashlib.sha256(log.read_bytes()).hexdigest(),
    'source_sha256': before, 'source_changed_during_run': [p for p in before if before[p] != after[p]],
}
(out / f'{name}.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2), flush=True)
print(log.read_text()[-24000:], flush=True)
sys.exit(result.returncode)

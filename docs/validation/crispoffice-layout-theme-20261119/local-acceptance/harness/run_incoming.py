import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path('/workspace/scratch/9c3338a48b2c')
repo = root / 'crispoffice'
out = root / 'validation/layout-theme'
audit_path = repo / 'docs/validation/crispoffice-layout-theme-20261119/incoming/audit.json'
audit = json.loads(audit_path.read_text())
gates = audit['qualification']['gates']
selected = set(sys.argv[1:])
if selected:
    known = {gate['id'] for gate in gates}
    assert selected <= known, selected - known
    gates = [gate for gate in gates if gate['id'] in selected]
runtime = out / 'incoming-runtime'
runtime.mkdir(exist_ok=True)
old_output = str(repo / 'docs/validation/crispoffice-layout-theme-20261119/incoming')
plan = []
for gate in gates:
    args = [arg.replace(old_output, str(runtime)) for arg in gate['argv']]
    plan.append({**gate, 'cwd': str((repo / gate['cwd']).resolve()), 'argv': args})
(out / 'incoming-run-plan.json').write_text(json.dumps({
    'audit_sha256': hashlib.sha256(audit_path.read_bytes()).hexdigest(),
    'generated_bundles_destination': str(runtime),
    'gates': plan,
}, indent=2) + '\n')
for gate in plan:
    name = 'incoming-' + gate['id']
    print(json.dumps({'starting': name, 'cwd': gate['cwd']}, sort_keys=True), flush=True)
    result = subprocess.run([
        sys.executable, str(out / 'run_validation.py'), name, gate['cwd'], *gate['argv'],
    ])
    if result.returncode:
        sys.exit(result.returncode)
    if 'required_json_true_fields' not in gate:
        continue
    records = []
    for line in (out / f'{name}.log').read_text().splitlines():
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    matching = [value for value in records if isinstance(value, dict) and value.get('language') == 'vba-excel']
    assert len(matching) == 1, matching
    record = matching[0]
    assertions = {
        field: record.get(field) is True for field in gate['required_json_true_fields']
    }
    for depth in gate['coldDepthStress_contains']:
        assertions[f'coldDepthStress contains {depth}'] = depth in record.get('coldDepthStress', '')
    stem = gate['id'].removesuffix('-node')
    artifacts = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in sorted(runtime.glob(stem + '.js*')) if path.is_file()}
    checked = {'gate': gate['id'], 'emitted_json': record, 'assertions': assertions,
               'all_passed': all(assertions.values()), 'compiled_artifact_sha256': artifacts}
    (out / f'{name}.assertions.json').write_text(json.dumps(checked, indent=2) + '\n')
    print(json.dumps(checked, indent=2), flush=True)
    assert all(assertions.values()), checked

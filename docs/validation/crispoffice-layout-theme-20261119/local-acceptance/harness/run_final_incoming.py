import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path('/workspace/scratch/9c3338a48b2c')
repo = root / 'crispoffice'
out = root / 'validation/layout-theme'
audit_dir = repo / 'docs/validation/crispoffice-layout-theme-20261119/incoming'
plan_index = 1
while (out / ('final-incoming-run-plan' + ('' if plan_index == 1 else '-' + str(plan_index)) + '.json')).exists():
    plan_index += 1
plan_suffix = '' if plan_index == 1 else '-' + str(plan_index)
sources = {}
for stem in ['audit', 'publication-audit']:
    raw = (audit_dir / (stem + '.json')).read_bytes()
    copied = out / (stem + '-for-final-run' + plan_suffix + '.json')
    copied.write_bytes(raw)
    sources[stem] = {'path': str(copied), 'sha256': hashlib.sha256(raw).hexdigest()}
original = json.loads(Path(sources['audit']['path']).read_text())
publication = json.loads(Path(sources['publication-audit']['path']).read_text())
gates = publication['additional_local_acceptance']['gates']
gates += [gate for gate in original['qualification']['gates'] if gate['id'].startswith('web_vba_')]
selected = set(sys.argv[1:])
if selected:
    assert selected <= {gate['id'] for gate in gates}, selected
    gates = [gate for gate in gates if gate['id'] in selected]
runtime = out / 'incoming-runtime'
runtime.mkdir(exist_ok=True)
old_output = str(audit_dir)
plan = []
for gate in gates:
    args = [arg.replace(old_output, str(runtime)) for arg in gate['argv']]
    run_name = 'incoming-' + gate['id']
    run_index = 1
    while (out / (run_name + '.json')).exists() or (out / (run_name + '.log')).exists():
        run_index += 1
        run_name = 'incoming-' + gate['id'] + '-' + str(run_index)
    plan.append({**gate, 'run_name': run_name, 'cwd': str((repo / gate['cwd']).resolve()), 'argv': args})
(out / ('final-incoming-run-plan' + plan_suffix + '.json')).write_text(json.dumps({
    'source_audits': sources,
    'generated_bundles_destination': str(runtime),
    'gates': plan,
}, indent=2) + '\n')
for gate in plan:
    name = gate['run_name']
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
    emitted = matching[0]
    assertions = {field: emitted.get(field) is True for field in gate['required_json_true_fields']}
    for depth in gate['coldDepthStress_contains']:
        assertions[f'coldDepthStress contains {depth}'] = depth in emitted.get('coldDepthStress', '')
    stem = gate['id'].removesuffix('-node')
    artifacts = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in sorted(runtime.glob(stem + '.js*')) if path.is_file()}
    checked = {'gate': gate['id'], 'emitted_json': emitted, 'assertions': assertions,
               'all_passed': all(assertions.values()), 'compiled_artifact_sha256': artifacts}
    (out / f'{name}.assertions.json').write_text(json.dumps(checked, indent=2) + '\n')
    print(json.dumps(checked, indent=2), flush=True)
    assert all(assertions.values()), checked

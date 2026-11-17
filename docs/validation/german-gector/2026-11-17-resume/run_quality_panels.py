import argparse
import json
import os
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--repo', type=Path, required=True)
p.add_argument('--build-dir', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--only')
p.add_argument('--syntax-corpus', type=Path)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
build = json.loads((a.build_dir / 'quality-build.json').read_text())
assert build['passed'], 'A successful source-sealed build is required.'
sdk = Path(os.environ['FLUTTER_ROOT']) / 'bin/cache/dart-sdk/bin'
model = Path(os.environ['GECTOR_TEST_MODEL'])
panels = [('original-30', 'cases.json'), ('development-76', 'prospective_cases_20261117.json'), ('syntax-56', 'syntax_cases_20261117.json')]
for name, corpus in panels:
    if a.only is not None and a.only != name:
        continue
    output = a.out / (name + '.json')
    log = a.out / (name + '.log')
    assert not output.exists() and not log.exists()
    corpus_path = a.syntax_corpus if name == 'syntax-56' and a.syntax_corpus else a.repo / 'tools/proofing/german_model' / corpus
    command = [str(sdk / 'dartaotruntime'), str(a.build_dir / 'quality.aot'), '--source-root', str(a.repo), '--cases', str(corpus_path), '--bundle-dir', str(model.parent), '--model', str(model), '--model-sha256', os.environ['GECTOR_TEST_MODEL_SHA256'], '--library', os.environ['GECTOR_TEST_LIBRARY'], '--library-sha256', os.environ['GECTOR_TEST_LIBRARY_SHA256'], '--output', str(output)]
    with log.open('x') as stream:
        result = subprocess.run(command, cwd=a.repo, env={**os.environ, 'CRISPEMBED_GECTOR': '1'}, stdout=stream, stderr=subprocess.STDOUT, timeout=240)
    if result.returncode:
        print(log.read_text()[-4000:], flush=True)
        raise SystemExit(result.returncode)
    report = json.loads(output.read_text())
    print(json.dumps({'panel':name, 'completed':report['completed'], 'operational_passed':report['operational_passed'], 'source_stable':report['source_stable'], 'summary':report['summary']}, ensure_ascii=False), flush=True)

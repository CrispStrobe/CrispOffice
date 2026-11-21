import hashlib
import json
from pathlib import Path
from urllib.parse import urljoin

runtime = Path(__file__).resolve().parent
repo = runtime.parent / 'quds_office_suite'
harness = runtime / 'engine-harness'
lock = json.loads((harness / 'original-lock.json').read_text())['packages']
closure = json.loads((harness / 'locked-closure.json').read_text())
package_config_path = harness / '.dart_tool/package_config.json'
package_config = json.loads(package_config_path.read_text())
assert len(package_config['packages']) == len(closure) + 1
for package in package_config['packages']:
    package['rootUri'] = urljoin(package_config_path.as_uri(), package['rootUri'])
for name, language in [('legacy_doc_parser', '3.8'), ('quds_office_engine', '3.12')]:
    package_config['packages'].append({
        'name': name,
        'rootUri': (repo / 'packages' / name).as_uri() + '/',
        'packageUri': 'lib/',
        'languageVersion': language,
    })
for name, version in closure.items():
    cached_hash = runtime / 'pub-cache/hosted-hashes/pub.dev' / f'{name}-{version}.sha256'
    expected_hash = lock[name]['description']['sha256']
    assert cached_hash.read_text().strip() == expected_hash, name
manifests = json.loads((harness / 'tracked-manifest-sha256.json').read_text())
for name, expected in manifests.items():
    assert hashlib.sha256((repo / name).read_bytes()).hexdigest() == expected, name
(repo / '.dart_tool').mkdir(exist_ok=True)
(repo / '.dart_tool/package_config.json').write_text(json.dumps(package_config, indent=2) + '\n')
(harness / 'effective-package_config.json').write_text(json.dumps(package_config, indent=2) + '\n')
test_version = closure['test']
wrapper = runtime / 'run-engine-tests.sh'
wrapper.write_text(f'''#!/bin/sh
set -eu
export DART_DISABLE_ANALYTICS=1
export TMPDIR='{runtime}/tmp'
export PUB_CACHE='{runtime}/pub-cache'
export PATH='{runtime}/dart-sdk/bin':"$PATH"
cd '{repo}/packages/quds_office_engine'
exec '{runtime}/dart-sdk/bin/dart' --packages='{repo}/.dart_tool/package_config.json' '{runtime}/pub-cache/hosted/pub.dev/test-{test_version}/bin/test.dart' "$@"
''')
wrapper.chmod(0o755)
print(f'Verified {len(closure)} hosted package hashes against the unchanged repository lock.')
print(f'Verified {len(manifests)} tracked manifests/locks unchanged.')
print(f'Effective package config: {repo}/.dart_tool/package_config.json')
print(f'Test wrapper: {wrapper}')

#!/usr/bin/env python3
"""Static packaging review; never dispatches or queries hosted workflows."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import yaml

parser = argparse.ArgumentParser()
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = args.repo.resolve()
path = repo / '.github/workflows/crispoffice-binaries.yml'
data = path.read_bytes()
workflow = yaml.load(data, Loader=yaml.BaseLoader)
app = 'packages/quds_office_editor/example'
jobs = workflow['jobs']
checks = []

def check(name, ok, **details):
    checks.append({'name': name, 'passed': bool(ok), **details})

check('Existing five jobs retained', set(jobs) == {'macos', 'windows', 'linux', 'android', 'web'})
check('Only manual and release-tag triggers', workflow['on'] == {
    'workflow_dispatch': '', 'push': {'tags': ['crispoffice-v*']}})
check('No elevated repository permission', workflow['permissions'] == {'contents': 'read'})
destinations = {
    'macos': ('--native', '--install-native', f'{app}/build/macos/Build/Products/Release/quds_office_studio.app/Contents/Frameworks'),
    'windows': ('--native', '--install-native', f'{app}/build/windows/x64/runner/Release'),
    'linux': ('--native', '--install-native', f'{app}/build/linux/x64/release/bundle/lib'),
    'android': ('--android', '--install-android', f'{app}/android/app/src/main/jniLibs/arm64-v8a'),
    'web': ('--wasm', '--install-web', f'{app}/web/proofing'),
}
for name, job in jobs.items():
    steps = job['steps']
    builds = [s for s in steps if s.get('run', '').startswith('flutter build ')]
    check(f'{name}: app build directory', len(builds) == 1 and builds[0].get('working-directory') == app)
    check(f'{name}: Python 3.12 selected', any(s.get('uses') == 'actions/setup-python@v5' and s.get('with', {}).get('python-version') == '3.12' for s in steps))
    install = [s for s in steps if 'packages/quds_proofing_hunspell/tool/build.py' in s.get('run', '')]
    mode, flag, destination = destinations[name]
    command = install[0]['run'] if len(install) == 1 else ''
    check(f'{name}: existing verified-output installer and loader path', mode in command and f'{flag} {destination}' in command)
    check(f'{name}: notices and corresponding sources packaged', '--install-licenses' in command or name == 'web' and '--install-web' in command)
    if name in {'android', 'web'}:
        check(f'{name}: engine staged before app compilation', steps.index(install[0]) < steps.index(builds[0]))
    elif install:
        check(f'{name}: native engine staged before archive', steps.index(builds[0]) < steps.index(install[0]) < next(i for i,s in enumerate(steps) if s.get('name') == 'Package'))
    for index, step in enumerate(steps):
        if 'run' not in step or name == 'windows':
            continue
        result = subprocess.run(['bash', '-n'], input=step['run'], text=True, capture_output=True)
        check(f'{name}: shell syntax step {index}', result.returncode == 0, stderr=result.stderr)

android = jobs['android']
check('Android APK and backend both arm64', android['env']['ANDROID_NDK_VERSION'] == '28.2.13676358' and any('--target-platform android-arm64' in s.get('run', '') for s in android['steps']))
mac_command = next(s['run'] for s in jobs['macos']['steps'] if 'tool/build.py' in s.get('run', ''))
check('macOS local signature renewed after adding library', mac_command.index('--install-native') < mac_command.index('codesign --force --sign -') < mac_command.index('codesign --force --deep --sign -'))
web_command = next(s['run'] for s in jobs['web']['steps'] if 'tool/build.py' in s.get('run', ''))
check('Web SDK version fixed and activated in build shell', '--branch 4.0.20' in web_command and 'install 4.0.20' in web_command and 'activate 4.0.20' in web_command and 'source "$RUNNER_TEMP/crispoffice-emsdk/emsdk_env.sh"' in web_command)
for notice in ['COPYING.MPL', 'license.hunspell', 'license.myspell']:
    upstream = repo / 'packages/quds_proofing_hunspell/licenses/upstream' / notice
    copy = repo / app / 'assets/licenses/hunspell' / notice
    check(f'Packaged notice retained exactly: {notice}', upstream.read_bytes() == copy.read_bytes())

receipt = {
    'workflow': str(path.relative_to(repo)),
    'workflow_sha256': hashlib.sha256(data).hexdigest(),
    'checks': checks,
    'passed': all(c['passed'] for c in checks),
    'scope': 'Static YAML, Bash syntax and checked-in build/loader path consistency. The separate Linux native build and receipt-verified installer run are recorded in runtime preparation.',
    'not_run': ['GitHub Actions queries, dispatches or waits', 'macOS/Windows/Android app builds', 'WebAssembly backend build', 'Linux GTK desktop app build'],
    'distribution_limits': ['macOS artifact uses a local ad-hoc signature; no Developer ID signing or notarization', 'Android artifact targets arm64-v8a only', 'No iOS workflow or execution claim'],
    'emscripten_sources': ['https://emscripten.org/docs/getting_started/downloads.html', 'https://github.com/emscripten-core/emsdk/blob/main/emscripten-releases-tags.json'],
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({'passed': receipt['passed'], 'checks': len(checks), 'workflow_sha256': receipt['workflow_sha256']}))
raise SystemExit(0 if receipt['passed'] else 1)

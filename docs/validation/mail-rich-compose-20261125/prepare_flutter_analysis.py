import hashlib
import io
import json
import os
from pathlib import Path
import re
import tarfile
import urllib.request
import yaml

BASE = Path('/workspace/scratch/5be74ff50514')
REPO = BASE / 'crispoffice'
TOOL = BASE / 'toolchain'
ROOT = TOOL / 'ui-analysis'
ROOT.mkdir(exist_ok=True)
LOCK = yaml.safe_load((REPO / 'pubspec.lock').read_text())['packages']
packages = {}
versions = {}
old_config = json.loads((BASE / 'mail-harness/.dart_tool/package_config.json').read_text())
for package in old_config['packages']:
    packages[package['name']] = package

def add(name, path, language='3.12'):
    packages[name] = {
        'name': name,
        'rootUri': path.resolve().as_uri(),
        'packageUri': 'lib/',
        'languageVersion': language,
    }

for pubspec in [*REPO.glob('packages/*/pubspec.yaml'), REPO / 'packages/quds_office_editor/example/pubspec.yaml']:
    manifest = yaml.safe_load(pubspec.read_text())
    add(manifest['name'], pubspec.parent)
for name in ['flutter', 'flutter_test', 'flutter_web_plugins']:
    add(name, TOOL / 'flutter-source/packages' / name, '3.11')
add('sky_engine', TOOL / 'sky_engine', '3.11')
add('enough_mail', REPO / 'third_party/enough_mail', '3.11')

def ensure(name):
    existing = packages.get(name)
    if existing:
        path = Path(existing['rootUri'].removeprefix('file://'))
        if (path / 'lib').is_dir():
            return path
    metadata = LOCK.get(name)
    if not metadata or metadata['source'] != 'hosted':
        raise RuntimeError('Missing non-hosted package: ' + name)
    version = metadata['version']
    dest = TOOL / 'ui-deps' / (name + '-' + version)
    if not dest.exists():
        if os.environ.get('UI_ANALYSIS_OFFLINE') == '1':
            raise RuntimeError('Missing cached source in offline mode: ' + name)
        url = 'https://pub.dev/api/archives/' + name + '-' + version + '.tar.gz'
        with urllib.request.urlopen(url, timeout=30) as response:
            raw = response.read()
        checksum = hashlib.sha256(raw).hexdigest()
        expected = metadata.get('description', {}).get('sha256')
        if expected and checksum != expected:
            raise RuntimeError('Archive checksum mismatch: ' + name)
        archive = tarfile.open(fileobj=io.BytesIO(raw), mode='r:gz')
        count = 0
        for item in archive.getmembers():
            if not item.isfile():
                continue
            member = Path(item.name)
            if member.is_absolute() or '..' in member.parts:
                raise RuntimeError('Unsafe archive member')
            if item.name not in ['pubspec.yaml', 'analysis_options.yaml', 'LICENSE'] and not (item.name.startswith('lib/') and item.name.endswith(('.dart', '.yaml'))):
                continue
            path = dest / member
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(archive.extractfile(item).read())
            count += 1
        versions[name] = {'version': version, 'sha256': checksum, 'source': url}
        print('Fetched actual pinned source:', name, version, count, 'files', flush=True)
    versions[name] = {'version': version, 'sha256': metadata.get('description', {}).get('sha256'), 'source': 'https://pub.dev/api/archives/' + name + '-' + version + '.tar.gz'}
    manifest = yaml.safe_load((dest / 'pubspec.yaml').read_text())
    constraint = str(manifest.get('environment', {}).get('sdk', '3.0'))
    match = re.search(r'(\d+)\.(\d+)', constraint)
    language = '.'.join(match.groups()) if match else '3.0'
    add(name, dest, language)
    return dest

starts = [
    'packages/quds_office_editor/example/lib/studio_mail_compose.dart',
    'packages/quds_office_editor/example/lib/studio_mail_rich_strings.dart',
    'packages/quds_office_editor/example/lib/studio_mail_rich_preview.dart',
    'packages/quds_office_editor/example/lib/studio_mail_outbox_review.dart',
    'packages/quds_office_editor/example/test/studio_mail_rich_compose_test.dart',
    'packages/quds_office_editor/example/test/studio_mail_rich_preview_test.dart',
]
queue = [REPO / path for path in starts]
visited = set()
missing = []
directive = re.compile(r"^\s*(?:import|export|part)\s+['\"][^;]+;", re.MULTILINE)
strings = re.compile(r"['\"]([^'\"]+)['\"]")
while queue:
    path = queue.pop().resolve()
    if path in visited:
        continue
    visited.add(path)
    if not path.is_file():
        missing.append(str(path))
        continue
    source = path.read_text()
    for statement in directive.finditer(source):
        for value in strings.findall(statement.group(0)):
            if value.startswith('dart:'):
                continue
            if value.startswith('package:'):
                name, _, relative = value[8:].partition('/')
                package_root = ensure(name)
                queue.append(package_root / 'lib' / relative)
            elif '://' not in value:
                queue.append(path.parent / value)

ensure('flutter_lints')
config = {'configVersion': 2, 'packages': list(packages.values()), 'generator': 'source-only-pinned-flutter-analysis'}
(ROOT / '.dart_tool').mkdir(exist_ok=True)
(ROOT / '.dart_tool/package_config.json').write_text(json.dumps(config, indent=2) + '\n')
(ROOT / 'source_receipt.json').write_text(json.dumps({
    'flutter_version': '3.47.8',
    'flutter_tag_commit': '737ba8f885dc774b53b442759999a312c9461e4e',
    'engine': 'cf636b1dfb818dd6a3ff16e390e93b1a036969c8',
    'hosted_sources': versions,
    'visited_dart_files': len(visited),
    'missing_paths': missing,
}, indent=2) + '\n')
print('Source graph:', len(visited), 'files;', len(packages), 'package roots;', len(missing), 'missing paths')
if missing:
    print('\n'.join(missing[:30]))

#!/usr/bin/env python3
"""Create an isolated Linux pure-Dart harness; requires Python's PyYAML."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import yaml

parser = argparse.ArgumentParser()
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo, output = args.repo.resolve(), args.output.resolve()
if output.exists():
    raise SystemExit('Use a new output directory; existing output is not replaced.')
output.mkdir(parents=True)
lock = yaml.safe_load((repo / 'pubspec.lock').read_text())
workspace = [
    'packages/quds_mail_core', 'packages/quds_mail_mime',
    'packages/quds_mail_store', 'packages/quds_office_engine',
    'packages/legacy_doc_parser', 'third_party/enough_mail',
]
dependencies = {
    'crypto': lock['packages']['crypto']['version'],
    'drift': lock['packages']['drift']['version'],
    'sqlite3': lock['packages']['sqlite3']['version'],
}
for relative in workspace:
    source, target = repo / relative, output / relative
    target.mkdir(parents=True)
    manifest = yaml.safe_load((source / 'pubspec.yaml').read_text())
    manifest['resolution'] = 'workspace'
    manifest['dev_dependencies'] = {}
    (target / 'pubspec.yaml').write_text(yaml.safe_dump(manifest, sort_keys=False))
    (target / 'lib').symlink_to(source / 'lib', target_is_directory=True)
    dependencies[manifest['name']] = {'path': relative}
studio = output / 'packages/quds_office_studio'
studio.mkdir()
(studio / 'lib').symlink_to(
    repo / 'packages/quds_office_editor/example/lib', target_is_directory=True)
(studio / 'pubspec.yaml').write_text(yaml.safe_dump({
    'name': 'quds_office_studio', 'publish_to': 'none', 'resolution': 'workspace',
    'environment': {'sdk': '^3.12.0'},
    'dependencies': {name: ({'path': '../../' + value['path']}
                          if isinstance(value, dict) else value)
                     for name, value in dependencies.items()},
}, sort_keys=False))
workspace.append('packages/quds_office_studio')
dependencies['quds_office_studio'] = {'path': 'packages/quds_office_studio'}
(output / 'pubspec.yaml').write_text(yaml.safe_dump({
    'name': 'mail_validation', 'publish_to': 'none',
    'environment': {'sdk': '^3.12.0'}, 'workspace': workspace,
    'dependencies': dependencies,
    'dev_dependencies': {name: lock['packages'][name]['version']
                         for name in ['test', 'lints']},
}, sort_keys=False))
shutil.copyfile(repo / 'pubspec.lock', output / 'pubspec.lock')
(output / 'analysis_options.yaml').write_text('include: package:lints/recommended.yaml\n')
(output / 'test').mkdir()
records = []
tests = [('packages/quds_mail_core/test', 'compose_body_test.dart')]
tests += [('packages/quds_office_editor/example/test', name) for name in [
    'studio_mail_rich_body_test.dart', 'studio_mail_rich_preview_data_test.dart',
    'studio_mail_rich_delivery_test.dart', 'studio_mail_rich_store_test.dart',
    'studio_mail_outbox_submission_test.dart', 'studio_mail_outbox_content_test.dart',
]]
focused_tests = list(tests)
tests += [
    ('packages/quds_office_engine/test', 'word_paragraph_mark_formatting_test.dart'),
    ('packages/quds_office_engine/test', 'xml_reader_test.dart'),
    ('packages/quds_mail_core/test', 'outbox_test.dart'),
    ('packages/quds_mail_store/test', 'codec_test.dart'),
    ('packages/quds_mail_store/test', 'cache_cleanup_test.dart'),
]
for parent, name in tests:
    source = repo / parent / name
    original = source.read_text()
    changes = []
    adapted = original
    if "import 'package:flutter_test/flutter_test.dart';" in adapted:
        adapted = adapted.replace("import 'package:flutter_test/flutter_test.dart';",
                                   "import 'package:test/test.dart';")
        changes.append('flutter_test import -> package:test')
    if 'extends Fake' in adapted:
        changes.append('real package:test/fake.dart import')
        adapted = adapted.replace("import 'package:test/test.dart';",
                                  "import 'package:test/test.dart';\nimport 'package:test/fake.dart';")
    if 'expectSync(' in adapted:
        adapted = adapted.replace('expectSync(', 'expect(')
        changes.append('expectSync -> equivalent package:test expect assertion')
    (output / 'test' / name).write_text(adapted)
    records.append({'source': str(source.relative_to(repo)),
                    'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                    'test_sha256': hashlib.sha256(adapted.encode()).hexdigest(),
                    'adaptations': changes or ['none']})
(output / 'test-transforms.json').write_text(json.dumps(records, indent=2))
fixture = Path('packages/quds_office_editor/fonts/LiberationSans-Regular.ttf')
(output / fixture).parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(repo / fixture, output / fixture)
(output / 'fixture-manifest.json').write_text(json.dumps({
    'path': str(fixture),
    'sha256': hashlib.sha256((repo / fixture).read_bytes()).hexdigest(),
    'adaptations': 'none; run tests from the harness engine package directory',
}, indent=2))
analysis = output / 'analysis'
(analysis / 'lib').mkdir(parents=True)
pending = ['studio_mail_compose_tools.dart', 'studio_mail_draft.dart',
           'studio_mail_draft_store.dart', 'studio_mail_outbox_content.dart',
           'studio_mail_submission.dart', 'studio_mail_outbox_strings.dart',
           'studio_mail_rich_body.dart', 'studio_mail_rich_preview_data.dart']
seen = set()
while pending:
    name = pending.pop()
    if name in seen:
        continue
    seen.add(name)
    source = repo / 'packages/quds_office_editor/example/lib' / name
    content = source.read_text()
    target = analysis / 'lib' / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    for match in re.finditer(r"^(?:import|export|part)\s+'([^']+)'", content, re.MULTILINE):
        relative = match.group(1)
        if ':' not in relative:
            pending.append(str(Path(name).parent / relative))
shutil.copyfile(repo / 'packages/quds_mail_core/lib/src/model/compose_body.dart',
                analysis / 'lib/compose_body.dart')
(analysis / 'test').mkdir()
for _, name in focused_tests:
    shutil.copyfile(output / 'test' / name, analysis / 'test' / name)
(output / 'sqlite_smoke.dart').write_text('''import 'package:sqlite3/sqlite3.dart';
void main() {
  print(sqlite3.version);
  final database = sqlite3.openInMemory();
  print(database.select('SELECT sqlite_version() AS version').single);
  database.close();
}
''')
print(output)

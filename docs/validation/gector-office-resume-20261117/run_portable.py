#!/usr/bin/env python3
"""Run retained portable controls plus restored headers and frame styles."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from urllib.parse import unquote, urljoin, urlparse

HERE = Path(__file__).resolve().parent
QUALIFICATION = HERE.parent / 'office-reconciled-20261117/qualification'
sys.path.insert(0, str(QUALIFICATION))
import prior_run_qualification as audit

TESTS = [
    'test/odt_page_field_fidelity_test.dart',
    'test/odt_imported_field_fidelity_test.dart',
    'test/odt_inline_field_fidelity_test.dart',
    'test/odt_inline_column_break_fidelity_test.dart',
    'test/odt_section_fidelity_test.dart',
    'test/word_field_span_test.dart',
    'test/word_zotero_simple_field_test.dart',
    'test/word_toc_test.dart',
    'test/word_revision_validation_test.dart',
    'test/odt_page_marker_column_break_test.dart',
    'test/odt_column_break_style_fidelity_test.dart',
    'test/odt_bookmark_name_ambiguity_test.dart',
    'test/odt_bookmark_range_fidelity_test.dart',
    'test/odt_section_columns_test.dart',
    'test/odt_header_variant_order_test.dart',
    'test/odt_header_variant_comment_fidelity_test.dart',
    'test/odt_frame_common_style_test.dart',
]

NODE_EXCLUSIONS = {
    'test/odt_complex_field_fidelity_test.dart':
        'Its fixture-export helper reads dart:io Platform.environment. '
        'The full VM cohort retains this suite; it is not selected for Node.'
}


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def compressed_json(path, value):
    path.write_bytes(gzip.compress(json.dumps(value, sort_keys=True).encode(), mtime=0))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'workspace', 'flutter-root', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--source-commit', required=True)
    args = parser.parse_args()
    repo, workspace, runtime, output = [
        path.resolve() for path in (args.repo, args.workspace, args.flutter_root, args.output)
    ]
    assert audit.git_text(repo, 'rev-parse', 'HEAD') == args.source_commit
    output.mkdir(parents=True, exist_ok=False)
    config = workspace / '.dart_tool/package_config.json'
    graph = audit.normalized_graph(config, repo)
    test_package = next(row for row in json.loads(config.read_text())['packages'] if row['name'] == 'test')
    test_root = Path(unquote(urlparse(urljoin(config.as_uri(), test_package['rootUri'])).path))
    dart = runtime / 'bin/cache/dart-sdk/bin/dart'
    node = Path(shutil.which('node')).resolve()
    cwd = workspace / 'packages/quds_office_engine'
    command = [str(dart), '--packages=' + str(config), str(test_root / 'bin/test.dart'),
               '--reporter=json', '--concurrency=2', '--platform=node', *TESTS]

    def snapshot():
        return {
            'source': audit.source_snapshot(repo, args.source_commit),
            'dependencies': audit.dependency_snapshot(graph, repo),
            'runtime': audit.runtime_snapshot(runtime),
            'workspace': audit.workspace_snapshot(workspace),
            'node': {str(node): audit.sha(node)},
            'harness': {str(Path(__file__).resolve()): audit.sha(Path(__file__)),
                        str(QUALIFICATION / 'prior_run_qualification.py'):
                            audit.sha(QUALIFICATION / 'prior_run_qualification.py')},
        }

    before = snapshot()
    assert not before['source']['commit_mismatches']
    assert not before['source']['untracked_non_evidence_paths']
    compressed_json(output / 'inputs-before.json.gz', before)
    started = time.monotonic()
    env = dict(os.environ, DASH__SUPPRESS_ANALYTICS='true', PUB_CACHE=str(runtime.parent / 'pub-cache'),
               DART_SUPPRESS_ANALYTICS='true', FLUTTER_SUPPRESS_ANALYTICS='true', CI='true',
               TMPDIR=str(workspace / 'tmp'))
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, timeout=900)
    summary = audit.test_summary(result.stdout, TESTS, False, cwd)
    after = snapshot()
    compressed_json(output / 'inputs-after.json.gz', after)
    outputs = {}
    for name, raw in [('stdout', result.stdout), ('stderr', result.stderr)]:
        data = gzip.compress(raw, mtime=0)
        (output / (name + '.gz')).write_bytes(data)
        outputs[name] = {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
                         'compressed_sha256': hashlib.sha256(data).hexdigest()}
    integrity = {name + '_unchanged': before[name] == after[name] for name in before}
    head_unchanged = audit.git_text(repo, 'rev-parse', 'HEAD') == args.source_commit
    passed = result.returncode == 0 and summary['passed'] and all(integrity.values()) and head_unchanged
    receipt = {'source_commit': args.source_commit,
               'source_tree': audit.git_text(repo, 'rev-parse', args.source_commit + '^{tree}'),
               'command': command, 'cwd': str(cwd), 'selected_files': TESTS,
               'node_exclusions_retained_on_vm': NODE_EXCLUSIONS,
               'duration_seconds': round(time.monotonic() - started, 3),
               'exit_code': result.returncode, 'test_summary': summary,
               'input_integrity': integrity, 'head_unchanged': head_unchanged,
               'outputs': outputs, 'passed': passed, 'historical_results_counted': False,
               'github_actions_queried_or_awaited': False}
    save(output / 'receipt.json', receipt)
    print(json.dumps({'passed': passed, 'exit_code': result.returncode,
                      'outcomes': summary['raw_runner_outcomes'], 'input_integrity': integrity}), flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())

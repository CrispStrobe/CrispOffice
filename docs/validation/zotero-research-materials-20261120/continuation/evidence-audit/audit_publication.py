#!/usr/bin/env python3
"""Bind frozen tests to the exact lint repair and identical publication tree."""
import argparse
from datetime import datetime, timezone
import difflib
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from recheck_saved_evidence import git, read, record, source_records, tree


TARGET = 'packages/quds_proofing_spacy/tool/evaluate_grammar_v2.dart'
OLD = '  if (value is List)\n    return [for (final v in value) _normalizeLibrary(v, library)];\n'
NEW = '  if (value is List) {\n    return [for (final v in value) _normalizeLibrary(v, library)];\n  }\n'
TOKEN_CHECK = r'''import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';

List<String> tokens(String source) {
  final parsed = parseString(content: source,
      featureSet: FeatureSet.latestLanguageVersion(), throwIfDiagnostics: true);
  final result = <String>[];
  var token = parsed.unit.beginToken;
  while (!token.isEof) {
    result.add(token.lexeme);
    token = token.next!;
  }
  return result;
}

void main(List<String> args) {
  File(args[2]).writeAsStringSync(jsonEncode({
    'before': tokens(File(args[0]).readAsStringSync()),
    'after': tokens(File(args[1]).readAsStringSync()),
  }));
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--continuation', type=Path, required=True)
    parser.add_argument('--tested-source', required=True)
    parser.add_argument('--lint-source', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    tested, lint, candidate = [git(repo, 'rev-parse', '--verify', value).decode().strip()
                               for value in (args.tested_source, args.lint_source, args.candidate)]
    tested_tree, lint_tree, candidate_tree = [tree(repo, value) for value in (tested, lint, candidate)]
    delta = sorted(p for p in set(tested_tree) | set(lint_tree) if tested_tree.get(p) != lint_tree.get(p))
    assert delta == [TARGET]
    lint_tree_id = git(repo, 'rev-parse', f'{lint}^{{tree}}').decode().strip()
    candidate_tree_id = git(repo, 'rev-parse', f'{candidate}^{{tree}}').decode().strip()
    assert lint_tree_id == candidate_tree_id and lint_tree == candidate_tree
    parents = git(repo, 'show', '-s', '--format=%P', candidate).decode().split()
    assert lint in parents and len(parents) == 2
    before = git(repo, 'show', f'{tested}:{TARGET}')
    after = git(repo, 'show', f'{lint}:{TARGET}')
    assert before.decode().count(OLD) == 1 and before.decode().replace(OLD, NEW, 1).encode() == after

    sdk = Path(os.environ['FLUTTER_ROOT']).resolve()
    with tempfile.TemporaryDirectory(prefix='publication-tokens-', dir=os.environ['TMPDIR']) as temporary:
        folder = Path(temporary)
        (folder / 'tokens.dart').write_text(TOKEN_CHECK)
        (folder / 'before.dart').write_bytes(before)
        (folder / 'after.dart').write_bytes(after)
        command = [str(sdk / 'bin/cache/dart-sdk/bin/dart'), f'--packages={repo}/.dart_tool/package_config.json',
                   str(folder / 'tokens.dart'), str(folder / 'before.dart'), str(folder / 'after.dart'), str(folder / 'tokens.json')]
        execution = subprocess.run(command, capture_output=True, text=True, check=False)
        assert execution.returncode == 0, execution.stderr
        token_data = read(folder / 'tokens.json')
    operations = []
    matcher = difflib.SequenceMatcher(a=token_data['before'], b=token_data['after'], autojunk=False)
    for tag, first, last, other_first, other_last in matcher.get_opcodes():
        if tag != 'equal':
            operations.append({'operation': tag, 'before_token_index': first,
                               'removed': token_data['before'][first:last],
                               'added': token_data['after'][other_first:other_last]})
    assert len(operations) == 2
    assert [row['operation'] for row in operations] == ['insert', 'insert']
    assert [row['removed'] for row in operations] == [[], []]
    assert [row['added'] for row in operations] == [['{'], ['}']]

    graph_root = args.continuation / 'unused-tool-import-graph'
    graph_receipt = read(graph_root / 'receipt.json')
    compressed = (graph_root / 'graph.json.gz').read_bytes()
    raw_graph = gzip.decompress(compressed)
    assert hashlib.sha256(compressed).hexdigest() == graph_receipt['compressed_graph_sha256']
    assert hashlib.sha256(raw_graph).hexdigest() == graph_receipt['graph_sha256']
    graph = json.loads(raw_graph)
    assert graph_receipt['status'] == 'passed'
    assert graph_receipt['source_head'] == graph_receipt['source_head_after'] == tested
    assert graph_receipt['checker_sha256'] == record((args.continuation / 'check_unused_tool.py').read_bytes())['sha256']
    for key in ['errors', 'source_changes_during_graph', 'target_directive_importers', 'reachable_files_mentioning_target']:
        assert graph[key] == graph_receipt[key] == []
    assert graph['target_reachable'] is False and graph_receipt['target_reachable'] is False
    assert graph['target_sha256'] == record(before)['sha256']
    assert graph['package_config_sha256'] == record((repo / '.dart_tool/package_config.json').read_bytes())['sha256']
    assert graph['package_config_unchanged'] and graph_receipt['package_config_unchanged']
    workspace_records = {}
    external_files_checked = 0
    for row in graph['records']:
        path = Path(row['path'])
        if path.is_relative_to(repo):
            relative = str(path.relative_to(repo))
            workspace_records[relative] = row
            assert tested_tree[relative] == lint_tree[relative] == candidate_tree[relative]
        else:
            data = path.read_bytes()
            assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
            external_files_checked += 1
        assert row['mentions_target_filename'] is False
    assert len(workspace_records) == graph_receipt['workspace_graph_files'] == 974
    assert len(graph['records']) == graph_receipt['graph_files'] == 4115

    fresh_path = args.continuation / 'evidence-audit/fresh-validation.json'
    fresh = read(fresh_path)
    assert fresh['qualified_source'] == tested
    assert fresh['fresh_distinct_passed_cases'] == 3201 and fresh['fresh_distinct_test_files'] == 129
    assert fresh['fresh_successful_application_executions'] == 3209
    assert fresh['primary_receipts_rejected'] == [{'cohort': 'engine-proofing', 'guard': 'unique_application_test_names'}]
    selection = read(graph_root / 'selection.json')
    test_paths = []
    for cohort in fresh['cohorts']:
        selected = [str(Path(path).relative_to(repo)) for path in selection['roots'][cohort['name']]]
        assert sorted(selected) == sorted(cohort['suite_paths'])
        assert graph['cohorts'][cohort['name']]['target_reachable'] is False
        test_paths.extend(selected)
    assert len(test_paths) == len(set(test_paths)) == 129
    assert all(tested_tree[path] == lint_tree[path] == candidate_tree[path] for path in test_paths)

    static_root = args.continuation / 'static'
    static = read(static_root / 'receipt.json')
    assert static['head'] == lint and static['accepted'] and static['inputs_identical']
    assert static['before'] == static['after'] and set(static['paths']) == set(static['before'])
    assert len(static['paths']) == 83 and all(item['exit_code'] == 0 for item in static['checks'].values())
    expected_static = git(repo, 'diff', '--name-only', static['base'], lint, '--', '*.dart').decode().splitlines()
    assert sorted(expected_static) == sorted(static['paths'])
    objects = {tested_tree[p] for p in workspace_records} | {lint_tree[p] for p in static['paths']}
    records = source_records(repo, objects)
    for path, row in workspace_records.items():
        expected = records[tested_tree[path]]
        assert expected['bytes'] == row['bytes'] and expected['sha256'] == row['sha256']
    for path in static['paths']:
        assert records[lint_tree[path]]['sha256'] == static['before'][path]

    recorded_inputs = {}
    for cohort in fresh['cohorts']:
        inputs = read(args.continuation / ('accepted-' + cohort['name']) / 'inputs.json.gz')['before']['source']
        for path, info in inputs.items():
            assert info['git_blob_sha1'] == tested_tree[path]
            recorded_inputs[path] = info
    changed_recorded = sorted(path for path in recorded_inputs if tested_tree[path] != candidate_tree.get(path))
    assert changed_recorded == [TARGET]
    manifest_paths = [p for p in tested_tree if Path(p).name in {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'}]
    library_paths = [p for p in tested_tree if p.startswith(('packages/', 'apps/', 'third_party/')) and '/lib/' in p]
    assert all(tested_tree[p] == candidate_tree[p] for p in manifest_paths + library_paths)
    result = {
        'status': 'verified_final_source_preservation_with_isolated_tool_correction',
        'audited_at_utc': datetime.now(timezone.utc).isoformat(),
        'test_source': tested, 'lint_correction_source': lint, 'publication_source_candidate': candidate,
        'candidate_parents': parents,
        'lint_tree': lint_tree_id, 'publication_candidate_tree': candidate_tree_id,
        'publication_history_merge_has_identical_complete_tree': True,
        'verifier_sha256': record(Path(__file__).read_bytes())['sha256'],
        'only_changed_path_from_tests_to_publication': TARGET,
        'tool_before': record(before), 'tool_after': record(after),
        'exact_approved_if_return_block_text_replacement': True,
        'dart_token_check': {'status': 'passed', 'helper_sha256': hashlib.sha256(TOKEN_CHECK.encode()).hexdigest(),
                             'before_tokens': len(token_data['before']), 'after_tokens': len(token_data['after']),
                             'operations': operations, 'parser_command': command,
                             'scope': 'Only two brace tokens are inserted around one unchanged if-return branch. The condition and return expression are unchanged.'},
        'import_graph': {'receipt_sha256': record((graph_root / 'receipt.json').read_bytes())['sha256'],
                         'compressed_graph_sha256': graph_receipt['compressed_graph_sha256'],
                         'workspace_files_bound_to_both_sources': len(workspace_records),
                         'external_source_files_rehashed': external_files_checked,
                         'target_unreachable_from_every_selected_cohort': True,
                         'reachable_files_with_literal_target_filename': 0,
                         'runtime_boundaries': graph['dart_sdk_boundaries']},
        'selected_test_files_unchanged': len(test_paths),
        'all_tracked_manifests_locks_analysis_settings_unchanged': len(manifest_paths),
        'all_tracked_application_library_paths_unchanged': len(library_paths),
        'recorded_source_inputs': len(recorded_inputs),
        'unchanged_recorded_source_inputs': len(recorded_inputs) - 1,
        'changed_recorded_source_inputs': changed_recorded,
        'all_recorded_source_inputs_unchanged': False,
        'fresh_validation': {'path': 'evidence-audit/fresh-validation.json', 'sha256': record(fresh_path.read_bytes())['sha256'],
                             'successful_executions': 3209, 'distinct_cases': 3201, 'test_files': 129,
                             'proofing_accounting_exception_preserved': True},
        'final_static': {'head': lint, 'target_count': 83, 'accepted': True,
                         'receipt_sha256': record((static_root / 'receipt.json').read_bytes())['sha256'],
                         'analysis_log_sha256': record((static_root / 'analysis.log').read_bytes())['sha256'],
                         'format_log_sha256': record((static_root / 'format.log').read_bytes())['sha256']},
        'limits': ['No application tests are rerun by this audit.',
                   'The standalone evaluator was not executed by the selected tests; static import proof also checks literal filename references, but cannot rule out arbitrary dynamic path construction.',
                   'The primary proofing name-uniqueness rejection remains preserved; eight verified identical fixture repeats are counted once.',
                   'The original 2,886 historical cases retain their earlier source attribution and are not added to the fresh count.',
                   'No native macOS, live-account or Office interoperability acceptance is claimed.'],
    }
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: result[key] for key in ['status', 'publication_source_candidate', 'selected_test_files_unchanged',
                                                'recorded_source_inputs', 'unchanged_recorded_source_inputs']}, indent=2))


if __name__ == '__main__':
    main()

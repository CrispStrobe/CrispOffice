#!/usr/bin/env python3
"""Build a conservative Linux-VM import scope for the accepted host selections.

Uses Dart analyzer ASTs and each package's declared language version. Only the
known VM dart.library.io value is fixed; all other conditional alternatives
remain possible. This proves source reachability, not dynamic call coverage.
No application tests, package resolution, source changes or remote operations.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


CORE_SOURCE = "214c4ed80bef0cb871f74e90c506d508679d3d6e"
COHORTS = (
    "engine-zotero", "editor-zotero", "engine-rendering", "editor-rendering",
    "engine-word-layout", "editor-word-layout", "mail-host", "studio-integration",
)
WEB_VM_ROOTS = [
    "packages/quds_office_editor/example/test/studio_hunspell_web_host_test.dart",
    "packages/quds_office_editor/example/test/studio_hunspell_web_cancellation_test.dart",
    "packages/quds_office_editor/example/test/studio_downloads_manager_test.dart",
]
WEB_LIBRARIES = ["packages/quds_office_editor/example/lib/" + name for name in [
    "studio_hunspell_host_web.dart", "studio_arabic_morph_host_web.dart",
    "studio_web_data_store.dart", "studio_web_data_store_none.dart", "studio_web_data_store_cache.dart",
]]

DART_SOURCE = r'''
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';

void main(List<String> args) {
  final input = jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final configUri = File(input['package_config'] as String).absolute.uri;
  final configBytes = File.fromUri(configUri).readAsBytesSync();
  final config = jsonDecode(utf8.decode(configBytes)) as Map<String, dynamic>;
  final packages = <String, Uri>{};
  final languageVersions = <String, String>{};
  for (final entry in config['packages'] as List) {
    final rootValue = configUri.resolve(entry['rootUri'] as String).toString();
    final root = Uri.parse(rootValue.endsWith('/') ? rootValue : '$rootValue/');
    packages[entry['name'] as String] = root.resolve(entry['packageUri'] as String? ?? '');
    languageVersions[root.toFilePath()] = entry['languageVersion'] as String;
  }
  final packageRoots = languageVersions.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  final records = <String, Map<String, Object?>>{};
  final errors = <Map<String, Object?>>[];
  final sdkLibraries = <String>{};
  final pending = <Uri>[];
  for (final roots in (input['roots'] as Map).values) {
    pending.addAll((roots as List).map((p) => File(p as String).absolute.uri.normalizePath()));
  }
  Uri? resolve(Uri base, String literal) {
    final uri = Uri.parse(literal);
    if (uri.scheme == 'dart') {
      sdkLibraries.add(literal);
      return null;
    }
    if (uri.scheme == 'package') {
      final segments = uri.pathSegments;
      final root = packages[segments.first];
      if (root == null) {
        errors.add({'file': base.toFilePath(), 'unresolved_package': literal});
        return null;
      }
      return root.resolve(segments.skip(1).join('/')).normalizePath();
    }
    if (uri.scheme.isNotEmpty && uri.scheme != 'file') {
      errors.add({'file': base.toFilePath(), 'unresolved_scheme': literal});
      return null;
    }
    return base.resolveUri(uri).normalizePath();
  }
  while (pending.isNotEmpty) {
    final uri = pending.removeLast();
    final path = uri.toFilePath();
    if (records.containsKey(path)) continue;
    final file = File(path);
    if (!file.existsSync()) {
      errors.add({'missing_import': path});
      records[path] = {'path': path, 'missing': true, 'edges': <String>[]};
      continue;
    }
    final bytes = file.readAsBytesSync();
    final owningRoot = packageRoots.where((root) => path.startsWith(root)).firstOrNull;
    if (owningRoot == null) {
      errors.add({'file': path, 'missing_package_language_version': true});
      continue;
    }
    final language = languageVersions[owningRoot]!;
    final features = FeatureSet.fromEnableFlags2(sdkLanguageVersion: Version.parse('$language.0'), flags: const []);
    final parsed = parseString(content: utf8.decode(bytes), path: path, featureSet: features, throwIfDiagnostics: false);
    if (parsed.errors.isNotEmpty) {
      errors.add({'file': path, 'parse_errors': parsed.errors.map((e) => e.toString()).toList()});
    }
    final dependencies = <Uri>{};
    final literals = <String>{};
    final conditionalChoices = <Map<String, Object?>>[];
    for (final directive in parsed.unit.directives) {
      if (directive is! UriBasedDirective) continue;
      final defaultUri = directive.uri.stringValue;
      if (defaultUri == null) {
        errors.add({'file': path, 'nonliteral_uri': directive.toSource()});
        continue;
      }
      if (directive is NamespaceDirective && directive.configurations.isNotEmpty) {
        final possible = <String>{};
        final conditions = <Map<String, Object?>>[];
        var knownMatchReached = false;
        for (final condition in directive.configurations) {
          final name = condition.name.toSource();
          final expectedValue = condition.value?.stringValue ?? 'true';
          final value = condition.uri.stringValue;
          if (value == null) {
            errors.add({'file': path, 'nonliteral_conditional_uri': condition.toSource()});
            continue;
          }
          final bool? matches = name == 'dart.library.io' ? expectedValue == 'true' : null;
          conditions.add({'name': name, 'expected_value': expectedValue, 'matches': matches, 'uri': value});
          if (matches == false) continue;
          possible.add(value);
          if (matches == true) {
            knownMatchReached = true;
            break;
          }
        }
        if (!knownMatchReached) possible.add(defaultUri);
        literals.addAll(possible);
        conditionalChoices.add({'directive': directive.toSource(), 'default_uri': defaultUri,
                                'evaluated_conditions': conditions, 'possible_uris': possible.toList()..sort()});
      } else {
        literals.add(defaultUri);
      }
    }
    for (final literal in literals) {
      final dependency = resolve(uri, literal);
      if (dependency != null) dependencies.add(dependency);
    }
    records[path] = {'path': path, 'sha256': sha256.convert(bytes).toString(), 'bytes': bytes.length,
                     'package_language_version': language,
                     'edges': dependencies.map((d) => d.toFilePath()).toList()..sort(),
                     'conditional_choices': conditionalChoices};
    pending.addAll(dependencies);
  }
  final sourceChanges = <String>[];
  for (final record in records.values) {
    if (record['missing'] == true) continue;
    final path = record['path'] as String;
    if (sha256.convert(File(path).readAsBytesSync()).toString() != record['sha256']) sourceChanges.add(path);
  }
  final targets = Set<String>.from(input['targets'] as List);
  final cohorts = <String, Object?>{};
  for (final entry in (input['roots'] as Map).entries) {
    final reached = <String>{};
    final queue = List<String>.from(entry.value as List);
    while (queue.isNotEmpty) {
      final path = File(queue.removeLast()).absolute.uri.normalizePath().toFilePath();
      if (!reached.add(path)) continue;
      queue.addAll(List<String>.from(records[path]?['edges'] as List? ?? const []));
    }
    cohorts[entry.key as String] = {'test_files': (entry.value as List).length,
                                  'imported_files': reached.length,
                                  'changed_libraries_reachable': reached.intersection(targets).toList()..sort()};
  }
  final result = {
    'cohorts': cohorts,
    'fixed_environment': {'dart.library.io': 'true'},
    'unknown_conditional_variables': 'All possible URI branches retained until a known matching branch ends the alternatives.',
    'package_config_sha256': sha256.convert(configBytes).toString(),
    'package_config_unchanged': sha256.convert(File.fromUri(configUri).readAsBytesSync()).toString() == sha256.convert(configBytes).toString(),
    'dart_sdk_boundaries': sdkLibraries.toList()..sort(),
    'errors': errors, 'source_changes_during_graph': sourceChanges,
    'records': records.values.toList()..sort((a, b) => (a['path'] as String).compareTo(b['path'] as String)),
  };
  File(args[1]).writeAsStringSync(jsonEncode(result));
  if (errors.isNotEmpty || sourceChanges.isNotEmpty || result['package_config_unchanged'] != true) exitCode = 1;
}
'''


def record(path: Path) -> dict:
    data = path.read_bytes()
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=repo, text=True).strip()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.output.resolve()
    assert git(repo, "rev-parse", "HEAD") == args.source
    milestone = repo / "docs/validation/zotero-research-materials-20261120"
    core = milestone / "continuation/host-main-followup"
    roots, receipt_records = {}, {}
    all_roots = []
    for name in COHORTS:
        path = core / ("accepted-" + name) / "receipt.json"
        receipt = json.loads(path.read_text())
        assert receipt["source_head_at_start"] == receipt["source_head_at_finish"] == CORE_SOURCE
        assert receipt["status"] == "passed" and all(receipt["guards"].values())
        roots[name] = [str(repo / path) for path in receipt["selected_repository_paths"]]
        all_roots.extend(roots[name])
        receipt_records[name] = record(path)
    assert len(all_roots) == len(set(all_roots)) == 157
    roots["web-persistence-vm"] = [str(repo / path) for path in WEB_VM_ROOTS]
    changed = git(repo, "diff", "--name-only", CORE_SOURCE, args.source).splitlines()
    targets = [str(repo / path) for path in changed if path.endswith(".dart") and "/lib/" in path]
    out.mkdir(parents=True, exist_ok=False)
    input_data = {"roots": roots, "targets": targets, "package_config": str(repo / ".dart_tool/package_config.json")}
    write_json(out / "selection.json", input_data)
    dart = Path(os.environ["FLUTTER_ROOT"]) / "bin/cache/dart-sdk/bin/dart"
    code_before = {"checker": record(Path(__file__)), "dart_binary": record(dart)}
    with tempfile.TemporaryDirectory(prefix="vm-import-scope-") as work:
        script, output = Path(work) / "directives.dart", Path(work) / "graph.json"
        script.write_text(DART_SOURCE)
        command = [str(dart), "--packages=" + str(repo / ".dart_tool/package_config.json"),
                   str(script), str(out / "selection.json"), str(output)]
        with (out / "execution.log").open("w") as stream:
            process = subprocess.run(command, cwd=repo, stdout=stream, stderr=subprocess.STDOUT)
        if not output.exists():
            print((out / "execution.log").read_text())
            return process.returncode or 1
        raw = output.read_bytes()
    graph = json.loads(raw)
    (out / "graph.json.gz").write_bytes(gzip.compress(raw, mtime=0))
    records = graph.pop("records")
    code_after = {"checker": record(Path(__file__)), "dart_binary": record(dart)}
    final_head = git(repo, "rev-parse", "HEAD")
    web_paths = {str(repo / path) for path in WEB_LIBRARIES}
    unchanged_core_factory_scope = all(
        not set(graph["cohorts"][name]["changed_libraries_reachable"]) & web_paths for name in COHORTS
    )
    passed = (process.returncode == 0 and code_before == code_after and final_head == args.source
              and unchanged_core_factory_scope)
    graph.update({
        "status": "passed" if passed else "failed", "source_head": args.source, "source_head_after": final_head,
        "core_test_source": CORE_SOURCE, "core_test_roots": 157, "additional_web_vm_roots": 3,
        "core_receipt_records": receipt_records, "graph_files": len(records),
        "workspace_graph_files": sum(Path(row["path"]).is_relative_to(repo) for row in records),
        "graph_sha256": hashlib.sha256(raw).hexdigest(), "compressed_graph": record(out / "graph.json.gz"),
        "code_before": code_before, "code_after": code_after, "code_unchanged": code_before == code_after,
        "dart_ast_source_sha256": hashlib.sha256(DART_SOURCE.encode()).hexdigest(), "command": command,
        "changed_web_libraries_excluded_from_all_prior_core_vm_roots": unchanged_core_factory_scope,
        "semantics": "Only dart.library.io is fixed to true for the actually qualified Linux VM. Every other unknown conditional remains conservatively possible. All import/export/part directives are parsed as ASTs with package language versions; dart: libraries are explicit runtime boundaries. This is a static source reachability proof, not a dynamic call-coverage or arbitrary runtime-path proof.",
    })
    write_json(out / "receipt.json", graph)
    print(json.dumps({key: graph[key] for key in ["status", "graph_files", "workspace_graph_files",
                                                  "changed_web_libraries_excluded_from_all_prior_core_vm_roots", "cohorts", "errors"]}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

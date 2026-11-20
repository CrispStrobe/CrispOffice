#!/usr/bin/env python3
"""Prove an isolated grammar CLI is outside all continuation test imports.

Uses the resolved, pinned Dart analyzer AST. Includes import/export/part and
every conditional URI. SDK dart: libraries are treated as runtime boundaries.
The result is a source-dependency proof, not a claim about dynamic execution.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

DART_SOURCE = r'''
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:crypto/crypto.dart';

void main(List<String> args) {
  final input = jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final configUri = File(input['package_config'] as String).absolute.uri;
  final configBytes = File.fromUri(configUri).readAsBytesSync();
  final config = jsonDecode(utf8.decode(configBytes)) as Map<String, dynamic>;
  final packages = <String, Uri>{};
  for (final entry in config['packages'] as List) {
    final rootValue = configUri.resolve(entry['rootUri'] as String).toString();
    final root = Uri.parse(rootValue.endsWith('/') ? rootValue : '$rootValue/');
    packages[entry['name'] as String] = root.resolve(entry['packageUri'] as String? ?? '');
  }
  final records = <String, Map<String, Object?>>{};
  final errors = <Map<String, Object?>>[];
  final sdkLibraries = <String>{};
  final target = File(input['target'] as String).absolute.uri.normalizePath();
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
    final parsed = parseString(content: utf8.decode(bytes), path: path, throwIfDiagnostics: false);
    if (parsed.errors.isNotEmpty) {
      errors.add({'file': path, 'parse_errors': parsed.errors.map((e) => e.toString()).toList()});
    }
    final dependencies = <Uri>{};
    final literals = <String>[];
    for (final directive in parsed.unit.directives) {
      if (directive is UriBasedDirective) {
        final value = directive.uri.stringValue;
        if (value == null) {
          errors.add({'file': path, 'nonliteral_uri': directive.toSource()});
        } else {
          literals.add(value);
        }
      }
      if (directive is NamespaceDirective) {
        for (final condition in directive.configurations) {
          final value = condition.uri.stringValue;
          if (value == null) {
            errors.add({'file': path, 'nonliteral_conditional_uri': condition.toSource()});
          } else {
            literals.add(value);
          }
        }
      }
    }
    for (final literal in literals) {
      final dependency = resolve(uri, literal);
      if (dependency != null) dependencies.add(dependency);
    }
    records[path] = {
      'path': path,
      'sha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
      'edges': dependencies.map((d) => d.toFilePath()).toList()..sort(),
      'mentions_target_filename': utf8.decode(bytes).contains(target.pathSegments.last),
    };
    pending.addAll(dependencies);
  }

  final sourceChanges = <String>[];
  for (final record in records.values) {
    if (record['missing'] == true) continue;
    final path = record['path'] as String;
    if (sha256.convert(File(path).readAsBytesSync()).toString() != record['sha256']) {
      sourceChanges.add(path);
    }
  }
  final cohorts = <String, Object?>{};
  for (final entry in (input['roots'] as Map).entries) {
    final reached = <String>{};
    final queue = List<String>.from(entry.value as List);
    while (queue.isNotEmpty) {
      final path = File(queue.removeLast()).absolute.uri.normalizePath().toFilePath();
      if (!reached.add(path)) continue;
      queue.addAll(List<String>.from(records[path]?['edges'] as List? ?? const []));
    }
    cohorts[entry.key as String] = {
      'test_files': (entry.value as List).length,
      'imported_files': reached.length,
      'target_reachable': reached.contains(target.toFilePath()),
    };
  }
  final targetBytes = File.fromUri(target).readAsBytesSync();
  final result = {
    'cohorts': cohorts,
    'target': target.toFilePath(),
    'target_sha256': sha256.convert(targetBytes).toString(),
    'package_config_sha256': sha256.convert(configBytes).toString(),
    'package_config_unchanged': sha256.convert(File.fromUri(configUri).readAsBytesSync()).toString() == sha256.convert(configBytes).toString(),
    'dart_sdk_boundaries': sdkLibraries.toList()..sort(),
    'errors': errors,
    'source_changes_during_graph': sourceChanges,
    'target_directive_importers': records.values.where((r) => (r['edges'] as List).contains(target.toFilePath())).map((r) => r['path']).toList(),
    'reachable_files_mentioning_target': records.values.where((r) => r['mentions_target_filename'] == true).map((r) => r['path']).toList(),
    'target_reachable': records.containsKey(target.toFilePath()),
    'records': records.values.toList()..sort((a, b) => (a['path'] as String).compareTo(b['path'] as String)),
  };
  File(args[1]).writeAsStringSync(jsonEncode(result));
  if (errors.isNotEmpty || sourceChanges.isNotEmpty || result['target_reachable'] == true || result['package_config_unchanged'] != true) exitCode = 1;
}
'''


def module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    milestone = repo/'docs/validation/zotero-research-materials-20261120'
    primary = module('primary', milestone/'run_validation.py')
    adapter = module('adapter', milestone/'continuation/run_continuation.py')
    primary.COHORTS.update(adapter.CONTINUATION_COHORTS)
    cohorts = ['engine-zotero','editor-zotero','engine-proofing','spacy','studio-integration']
    roots = {name:[str(p) for p in primary.select_tests(repo,name)] for name in cohorts}
    target = repo/'packages/quds_proofing_spacy/tool/evaluate_grammar_v2.dart'
    head = subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
    input_data = {'roots':roots,'target':str(target),'package_config':str(repo/'.dart_tool/package_config.json')}
    (out/'selection.json').write_text(json.dumps(input_data,indent=2)+'\n')
    dart = str(Path(os.environ['FLUTTER_ROOT'])/'bin/cache/dart-sdk/bin/dart')
    with tempfile.TemporaryDirectory(prefix='unused-tool-imports-') as work:
        script = Path(work)/'directives.dart'
        script.write_text(DART_SOURCE)
        output = Path(work)/'graph.json'
        command = [dart,'--packages='+str(repo/'.dart_tool/package_config.json'),str(script),str(out/'selection.json'),str(output)]
        with (out/'execution.log').open('w') as stream:
            result = subprocess.run(command,cwd=repo,stdout=stream,stderr=subprocess.STDOUT)
        if not output.exists():
            print((out/'execution.log').read_text())
            return result.returncode or 1
        raw = output.read_bytes()
    graph = json.loads(raw)
    with (out/'graph.json.gz').open('wb') as stream:
        with gzip.GzipFile(fileobj=stream,mode='wb',mtime=0,filename='') as compressed:
            compressed.write(raw)
    records = graph.pop('records')
    graph.update({
        'status':'passed' if result.returncode==0 else 'failed',
        'source_head':head,
        'source_head_after':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),
        'graph_files':len(records),
        'workspace_graph_files':sum(Path(r['path']).is_relative_to(repo) for r in records),
        'graph_sha256':hashlib.sha256(raw).hexdigest(),
        'compressed_graph_sha256':hashlib.sha256((out/'graph.json.gz').read_bytes()).hexdigest(),
        'checker_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'dart_ast_source_sha256':hashlib.sha256(DART_SOURCE.encode()).hexdigest(),
        'command':command,
        'semantics':'All import/export/part directives and conditional alternatives are traversed. dart: runtime libraries are recorded boundaries. No reachable source references the tool filename; arbitrary dynamic path construction is outside static import proof.',
    })
    (out/'receipt.json').write_text(json.dumps(graph,indent=2)+'\n')
    print(json.dumps({k:graph[k] for k in ['status','graph_files','workspace_graph_files','target_reachable','errors','cohorts']}))
    return result.returncode


if __name__=='__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Independent Dart-AST import graph comparison of two immutable trees."""
from pathlib import Path, PurePosixPath
import collections
import hashlib
import json
import posixpath
import re
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path('/workspace/scratch/a4ce103494d8/quds_office_suite')
OUT = Path('/workspace/scratch/a4ce103494d8/zotero-cell-review')
BASE = 'a6095c304ad2d6935f2ae6f8b74412038d19f142'
TARGET = '5289b90a83ce9042a4f4cfb73ba8115fe501513a'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def tree(ref):
    result = {}
    for row in git('ls-tree', '-rz', ref).split(b'\0'):
        if not row:
            continue
        meta, raw_path = row.split(b'\t', 1)
        mode, kind, blob = meta.decode().split()
        if kind == 'blob':
            result[raw_path.decode()] = (mode, blob)
    return result


AST = {}
for line in (OUT / 'directive-ast.jsonl').read_text().splitlines():
    record = json.loads(line)
    assert record['key'] not in AST
    AST[record['key']] = record


def build(entries):
    packages = {}
    for path, (_, blob) in entries.items():
        if PurePosixPath(path).name != 'pubspec.yaml':
            continue
        if path != 'pubspec.yaml' and not path.startswith(('packages/', 'third_party/')):
            continue
        if 'docs' in PurePosixPath(path).parts:
            continue
        text = git('cat-file', 'blob', blob).decode()
        match = re.search(r'^name:\s*([A-Za-z0-9_]+)\s*(?:#.*)?$', text, re.M)
        if not match:
            raise ValueError(f'Unsupported package declaration: {path}')
        name = match[1]
        assert name not in packages, (name, packages.get(name), path)
        packages[name] = posixpath.dirname(path)
    graph, issues, externals, diagnostics = {}, {}, {}, {}
    for path, (_, blob) in entries.items():
        if not path.endswith('.dart'):
            continue
        parsed = AST[blob]
        dependencies = set()
        diagnostics[path] = parsed['diagnostics']
        for directive in parsed['uris']:
            uri = directive['value']
            if uri is None:
                issues.setdefault(path, []).append({'directive': directive, 'issue': 'nonliteral'})
                continue
            parsed_uri = urlsplit(uri)
            if parsed_uri.scheme == 'dart':
                continue
            if parsed_uri.query or parsed_uri.fragment:
                issues.setdefault(path, []).append({'uri': uri, 'issue': 'query_or_fragment'})
                continue
            if parsed_uri.scheme == 'package':
                package, sep, rel = unquote(parsed_uri.path).partition('/')
                if not sep:
                    issues.setdefault(path, []).append({'uri': uri, 'issue': 'malformed_package'})
                    continue
                if package not in packages:
                    externals.setdefault(path, set()).add(package)
                    continue
                destination = posixpath.join(packages[package], 'lib', rel)
            elif not parsed_uri.scheme and not parsed_uri.netloc and not uri.startswith('/'):
                destination = posixpath.join(posixpath.dirname(path), unquote(parsed_uri.path))
            else:
                issues.setdefault(path, []).append({'uri': uri, 'issue': 'unsupported_scheme'})
                continue
            destination = posixpath.normpath(destination)
            if destination.startswith('../') or destination not in entries or not destination.endswith('.dart'):
                issues.setdefault(path, []).append({'uri': uri, 'destination': destination, 'issue': 'unresolved_local'})
                continue
            dependencies.add(destination)
        graph[path] = dependencies
    return graph, issues, externals, diagnostics, packages


def closure(graph, root):
    result = {root}
    queue = collections.deque([root])
    while queue:
        for dep in graph[queue.popleft()]:
            if dep not in result:
                result.add(dep)
                queue.append(dep)
    return result


trees = {c: tree(c) for c in (BASE, TARGET)}
graphs = {c: build(trees[c]) for c in trees}
qualification = json.loads((ROOT / 'docs/validation/zotero-table-cell-ranges-20261121/qualification.json').read_text())
selected = qualification['selected_test_files']
assert len(selected) == len(set(selected)) == 119
rows, selected_issues, selected_diagnostics, selected_external = [], {}, {}, {}
for path in selected:
    reaches = {c: closure(graphs[c][0], path) for c in trees}
    for c, paths in reaches.items():
        for p in paths:
            if p in graphs[c][1]: selected_issues.setdefault(c, {})[p] = graphs[c][1][p]
            if graphs[c][3][p]: selected_diagnostics.setdefault(c, {})[p] = graphs[c][3][p]
            for pkg in graphs[c][2].get(p, ()):
                selected_external.setdefault(c, set()).add(pkg)
    before = {p: trees[BASE][p] for p in sorted(reaches[BASE])}
    after = {p: trees[TARGET][p] for p in sorted(reaches[TARGET])}
    changed = sorted(p for p in set(before) | set(after) if before.get(p) != after.get(p))
    rows.append({'path': path, 'before_libraries': len(before), 'after_libraries': len(after),
                 'closure_unchanged': before == after, 'changed_dependencies': changed})
report = {
    'method': 'Dart analyzer 13.3.0 parseString AST import/export/part/conditional directives; decoded URI literal values; all alternatives; immutable Git blob inputs',
    'original_commit': BASE, 'reviewed_commit': TARGET,
    'parsed_unique_dart_blobs': len(AST),
    'selected_suites': len(rows),
    'unchanged_closures': sum(r['closure_unchanged'] for r in rows),
    'changed_closures': [r for r in rows if not r['closure_unchanged']],
    'selected_closure_unresolved_or_unsupported_directives': selected_issues,
    'selected_closure_syntax_diagnostics': selected_diagnostics,
    'selected_external_packages': {c: sorted(v) for c, v in selected_external.items()},
    'repository_package_counts': {c: len(graphs[c][4]) for c in trees},
    'all_suite_closures': rows,
    'parser_helper_sha256': hashlib.sha256((OUT / 'parse_directives.dart').read_bytes()).hexdigest(),
    'parsed_input_sha256': hashlib.sha256((OUT / 'directive-ast-input.jsonl').read_bytes()).hexdigest(),
    'parsed_output_sha256': hashlib.sha256((OUT / 'directive-ast.jsonl').read_bytes()).hexdigest(),
}
(OUT / 'impact-ast-review.json').write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ('all_suite_closures', 'selected_external_packages')}, indent=2))

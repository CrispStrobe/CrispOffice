#!/usr/bin/env python3
"""Replay the repository dependency review; this does not execute or accept tests.

The target must be a committed combined tree. Read-only Git plumbing supplies
its bytes, so an unrelated working-tree edit cannot alter the review. The
original qualification archive supplies the frozen map, suite selection and
accepted case records. No Git refs, source files or index entries are changed.
"""

import argparse
from collections import Counter, deque
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile


QUALIFIED = 'a6095c304ad2d6935f2ae6f8b74412038d19f142'
MAIN = '4a1eaa69e7a068e354bdd851ec9b0323b89ae300'
CLOSE_FIX = '9cfad3920f9afb3ca1620df429fa41e33f3db8e6'
NODE_TESTS = [
    'packages/quds_office_engine/test/word_zotero_table_cell_replacement_test.dart',
    'packages/quds_office_engine/test/word_zotero_multiparagraph_test.dart',
]
REPEAT_TESTS = [
    'packages/quds_office_engine/test/word_table_grid_addressing_test.dart',
    'packages/quds_office_engine/test/word_bookmark_fidelity_test.dart',
    'packages/quds_office_editor/example/test/studio_zotero_citing_transport_test.dart',
    'packages/quds_office_editor/example/test/studio_zotero_shortcuts_test.dart',
]
LOADER_DISPOSITIONS = {
    'packages/quds_office_editor/example/lib/credentials/native_system_io.dart': {
        'expected_matches': 1,
        'assessment': 'Comment mentioning Process.run; no executable loader.',
    },
    'packages/quds_office_editor/example/lib/suite_workspace.dart': {
        'expected_matches': 3,
        'assessment': '_openExternalLink delegates a hyperlink to the OS via cmd/start, open or xdg-open; it does not import or execute repository Dart source.',
    },
    'packages/quds_office_editor/lib/src/embed/office_uri_io.dart': {
        'expected_matches': 3,
        'assessment': 'openExternalUri delegates a PDF link to the OS via cmd/start, open or xdg-open; it does not import or execute repository Dart source.',
    },
}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def canonical_digest(value):
    return sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def require(condition, message):
    if not condition:
        raise ValueError(message)


def git(repo, *args):
    return subprocess.check_output(['git', *args], cwd=repo)


def tree(repo, ref):
    result = {}
    for row in git(repo, 'ls-tree', '-rz', ref).split(b'\0'):
        if not row:
            continue
        metadata, path = row.split(b'\t', 1)
        mode, kind, blob = metadata.decode().split()
        if kind == 'blob':
            result[path.decode()] = {'mode': mode, 'git_blob_sha1': blob}
    return result


def captured_path(path):
    """The original broad inventory policy, including rg's hidden-file exclusion."""
    item = PurePosixPath(path)
    if path in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'):
        return True
    if not path.startswith(('packages/', 'third_party/')):
        return False
    if any(p.startswith('.') or p in ('build', 'docs') for p in item.parts):
        return False
    return (item.suffix == '.dart'
            or item.name in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')
            or '/test/fixtures/' in path
            or (path.startswith('packages/quds_office_engine/example/macros/')
                and item.suffix == '.bas'))


def load_blobs(repo, identifiers):
    unique = sorted(set(identifiers))
    raw = subprocess.run(
        ['git', 'cat-file', '--batch'], cwd=repo, check=True,
        input=('\n'.join(unique) + '\n').encode(), stdout=subprocess.PIPE,
    ).stdout
    result = {}
    position = 0
    for requested in unique:
        end = raw.index(b'\n', position)
        actual, kind, size = raw[position:end].decode().split()
        require(actual == requested and kind == 'blob', 'Unexpected Git object')
        position = end + 1
        size = int(size)
        result[requested] = raw[position:position + size]
        position += size + 1
    require(position == len(raw), 'Unexpected cat-file output')
    return result


def source_map(entries, blobs):
    return {
        path: {
            'executable': entry['mode'] == '100755',
            'git_blob_sha1': entry['git_blob_sha1'],
            'sha256': sha256(blobs[entry['git_blob_sha1']]),
            'size': len(blobs[entry['git_blob_sha1']]),
        }
        for path, entry in sorted(entries.items()) if captured_path(path)
    }


def changes(before, after):
    common = set(before) & set(after)
    modified = [p for p in sorted(common) if before[p] != after[p]]
    return {
        'before_count': len(before),
        'after_count': len(after),
        'unchanged_existing_count': len(common) - len(modified),
        'modified_existing_count': len(modified),
        'modified_existing': [
            {'path': p, 'before': before[p], 'after': after[p]} for p in modified
        ],
        'added': [{'path': p, **after[p]} for p in sorted(set(after) - set(before))],
        'removed': [{'path': p, **before[p]} for p in sorted(set(before) - set(after))],
    }


def dependency_graph(entries, blobs):
    texts = {
        p: blobs[v['git_blob_sha1']].decode()
        for p, v in entries.items()
        if p.endswith('.dart') or PurePosixPath(p).name == 'pubspec.yaml'
    }
    packages = {}
    for path, text in texts.items():
        # Evidence directories retain historical pubspec copies with the same
        # package names; only actual repository package roots resolve imports.
        if (PurePosixPath(path).name == 'pubspec.yaml'
                and (path == 'pubspec.yaml'
                     or path.startswith(('packages/', 'third_party/')))):
            match = re.search(r'^name:\s*([^\s#]+)', text, re.M)
            if match:
                require(match[1] not in packages, 'Duplicate package name')
                packages[match[1]] = PurePosixPath(path).parent

    diagnostics = {}

    def issue(source, kind, uri):
        diagnostics.setdefault(source, []).append({'kind': kind, 'value': uri})

    def resolve(source, uri):
        if any(c in uri for c in ('\\', '%', '$', '\n', '\r')):
            issue(source, 'unsupported_uri_escape_or_interpolation', uri)
            return None
        if uri.startswith('dart:'):
            return None
        if uri.startswith('package:'):
            if '/' not in uri[8:]:
                issue(source, 'malformed_package_uri', uri)
                return None
            package, relative = uri[8:].split('/', 1)
            if package not in packages:
                return None
            destination = packages[package] / 'lib' / relative
        else:
            if re.match(r'^[A-Za-z][A-Za-z0-9+.-]*:', uri) or uri.startswith('/'):
                issue(source, 'unsupported_uri_scheme_or_absolute_path', uri)
                return None
            destination = PurePosixPath(source).parent / uri
        normalized = []
        for piece in destination.parts:
            if piece == '..':
                require(bool(normalized), 'Dependency escapes repository')
                normalized.pop()
            elif piece != '.':
                normalized.append(piece)
        result = '/'.join(normalized)
        if result not in texts:
            issue(source, 'unresolved_repository_directive', uri)
            return None
        return result

    graph = {}
    for path, text in texts.items():
        if not path.endswith('.dart'):
            continue
        dependencies = set()
        for number, line in enumerate(text.splitlines(), 1):
            # The directive recognizer is line anchored. Reject any candidate
            # second directive on a physical line instead of silently missing it.
            if re.search(r";[^\n]*\b(?:import|export|part)\s+(?:r)?['\"]", line):
                issue(path, 'possible_same_line_directive', f'{number}: {line.strip()}')
        directive_start = r'^[ \t]*(?:(?:import|export)\s+(?:r)?[\'\"]|part\s+(?:(?:r)?[\'\"]|of\b))'
        for directive in re.findall(directive_start + r'[\s\S]*?;', text, re.M):
            literals = re.findall(r"(?:r)?(['\"])(.*?)\1", directive, re.S)
            if not literals:
                continue  # Named `part of some.library;` has no URI.
            uris = [literals[0][1]]
            for conditional in re.findall(r'\bif\s*\([^)]*\)\s*((?:r)?[\'\"][^\'\"]*[\'\"])', directive):
                uris.append(re.findall(r"(?:r)?(['\"])(.*?)\1", conditional, re.S)[0][1])
            for uri in uris:
                dependency = resolve(path, uri)
                if dependency:
                    dependencies.add(dependency)
        graph[path] = dependencies
    return graph, texts, len(packages), diagnostics


def closure(graph, root):
    parents = {root: None}
    queue = deque([root])
    while queue:
        path = queue.popleft()
        for dependency in sorted(graph.get(path, ())):
            if dependency not in parents:
                parents[dependency] = path
                queue.append(dependency)
    return parents


def identity(entries, paths):
    return {p: entries[p] for p in sorted(paths)}


def path_to(parents, target):
    result = [target]
    while parents[result[-1]] is not None:
        result.append(parents[result[-1]])
    return list(reversed(result))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--target-ref', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    directory = Path(__file__).resolve().parent.parent
    index = json.loads((directory / 'evidence-index.json').read_text())
    archive_path = directory / index['archive']
    require(sha256(archive_path.read_bytes()) == index['archive_sha256'],
            'Original archive checksum mismatch')
    with tarfile.open(archive_path, 'r:xz') as archive:
        def archived(name):
            member = archive.extractfile(name)
            require(member is not None, f'Missing archived member: {name}')
            return member.read()

        frozen_bytes = gzip.decompress(archived(index['qualified_source_member']))
        frozen = json.loads(frozen_bytes)
        node_before = json.loads(archived('portable/source-before.json'))
        case_counts = Counter()
        for cohort in ('engine-owner-fidelity', 'studio-zotero'):
            cases = json.loads(gzip.decompress(archived(
                f'qualification/frozen-remaining/{cohort}/cases.json.gz')))
            for case in cases:
                require(case['result'] == 'success' and not case['skipped'],
                        'Original repeat population contains a non-pass')
                case_counts[PurePosixPath(case['suite']).name] += 1

    qualification = json.loads((directory / 'qualification.json').read_text())
    selection = json.loads((directory / 'selection.json').read_text())
    require(len(frozen) == 2978, 'Unexpected original captured input count')
    require(sha256(frozen_bytes) == index['qualified_source_map_sha256'],
            'Original frozen map checksum mismatch')
    target = git(repo, 'rev-parse', f'{args.target_ref}^{{commit}}').decode().strip()
    ancestry = {}
    for name, commit in [('original_qualification', QUALIFIED), ('main', MAIN),
                         ('saved_mail_close_fix', CLOSE_FIX)]:
        ancestry[name] = subprocess.run(
            ['git', 'merge-base', '--is-ancestor', commit, target], cwd=repo,
        ).returncode == 0
    require(all(ancestry.values()), 'Target does not contain all captured frontiers')
    trees = {ref: tree(repo, ref) for ref in dict.fromkeys((QUALIFIED, MAIN, target))}
    needed = set()
    for entries in trees.values():
        for path, entry in entries.items():
            if (captured_path(path) or path.endswith('.dart')
                    or PurePosixPath(path).name == 'pubspec.yaml'):
                needed.add(entry['git_blob_sha1'])
    blobs = load_blobs(repo, needed)
    maps = {ref: source_map(entries, blobs) for ref, entries in trees.items()}
    require(maps[QUALIFIED] == frozen, 'Original Git source differs from archived map')
    require(all(frozen[p]['sha256'] == value for p, value in node_before.items()),
            'Original Node capture differs from original broad map')
    baseline_graph, baseline_texts, _, baseline_diagnostics = dependency_graph(trees[QUALIFIED], blobs)
    graph, texts, package_count, diagnostics = dependency_graph(trees[target], blobs)
    altered = {p for p in set(trees[QUALIFIED]) | set(trees[target])
               if trees[QUALIFIED].get(p) != trees[target].get(p)}
    changed_production = {p for p in altered if '/lib/' in p and p.endswith('.dart')}
    suites = []
    cohort_rows = []
    dynamic_loaders = []
    all_before_dependencies = set()
    all_after_dependencies = set()
    for cohort in selection['cohorts']:
        rows = []
        for short in cohort['tests']:
            path = f"{cohort['package']}/{short}"
            before = closure(baseline_graph, path)
            after = closure(graph, path)
            all_before_dependencies.update(before)
            all_after_dependencies.update(after)
            changed_dependencies = sorted(set(after) & changed_production)
            row = {
                'path': path,
                'cohort': cohort['name'],
                'test_source_unchanged': trees[QUALIFIED][path] == trees[target][path],
                'repository_dependency_count': len(after),
                'repository_dependency_identity_sha256': canonical_digest(identity(trees[target], after)),
                'repository_dependency_closure_unchanged': identity(trees[QUALIFIED], before) == identity(trees[target], after),
                'changed_production_dependencies': changed_dependencies,
                'dependency_paths': {p: path_to(after, p) for p in changed_dependencies},
            }
            rows.append(row)
            suites.append(row)
        cohort_rows.append({
            'name': cohort['name'], 'suite_count': len(rows),
            'affected_suites': [r['path'] for r in rows if r['changed_production_dependencies']],
        })
    require({r['path'] for r in suites} == set(qualification['selected_test_files']),
            'Original suite selections disagree')
    directive_issues = {
        'original': [{'path': p, **item} for p in sorted(all_before_dependencies)
                     for item in baseline_diagnostics.get(p, ())],
        'combined': [{'path': p, **item} for p in sorted(all_after_dependencies)
                     for item in diagnostics.get(p, ())],
    }
    require(not any(directive_issues.values()),
            'Unresolved/unsupported/unscanned local directives: ' + json.dumps(directive_issues))
    for path in sorted(all_after_dependencies):
        for number, line in enumerate(texts[path].splitlines(), 1):
            if re.search(r'\b(Process\.(?:run|runSync|start)|Isolate\.spawnUri|loadLibrary\(|Platform\.script)', line):
                dynamic_loaders.append({'path': path, 'line': number, 'text': line.strip()})
    loader_counts = Counter(row['path'] for row in dynamic_loaders)
    require(set(loader_counts) == set(LOADER_DISPOSITIONS),
            'Transitive loader source set requires a fresh manual review')
    loader_reviews = []
    for path, disposition in LOADER_DISPOSITIONS.items():
        require(loader_counts[path] == disposition['expected_matches'],
                f'Transitive loader matches require a fresh review: {path}')
        require(trees[QUALIFIED][path] == trees[target][path],
                f'Transitive loader source changed and requires review: {path}')
        loader_reviews.append({
            'path': path, **disposition, 'source_unchanged': True,
            'source_identity': maps[target][path],
        })
    repeat_rows = [{
        'path': path,
        'original_passed_cases': case_counts[PurePosixPath(path).name],
        'reason': ('Shared Studio cohort companion' if path.endswith('studio_zotero_citing_transport_test.dart')
                   else 'Changed production dependency in the selected suite closure'),
    } for path in REPEAT_TESTS]
    node_rows = [r for p in NODE_TESTS for r in suites if r['path'] == p]
    old_node_map = {p: frozen[p] for p in node_before}
    new_node_paths = ({p for p in maps[target] if p.startswith('packages/quds_office_engine/lib/')}
                      | set(NODE_TESTS) | {'packages/quds_office_engine/pubspec.yaml'})
    new_node_map = {p: maps[target][p] for p in new_node_paths}
    report = {
        'schema_version': 1,
        'status': 'applicability-pending-targeted-runs',
        'accepts_combined_main': False,
        'review_kind': 'Read-only static repository dependency review; no test execution',
        'original_qualified_commit': QUALIFIED,
        'original_qualification': {'passed_cases': 2551, 'suites': 119,
                                   'source_inputs': 2978, 'source_map_sha256': sha256(frozen_bytes)},
        'captured_main': MAIN,
        'captured_saved_mail_close_fix': CLOSE_FIX,
        'reviewed_commit': target,
        'reviewed_tree': git(repo, 'rev-parse', f'{target}^{{tree}}').decode().strip(),
        'captured_frontiers_are_ancestors': ancestry,
        'original_archive_sha256': index['archive_sha256'],
        'replay_script_sha256': sha256(Path(__file__).read_bytes()),
        'reviewed_source_identity_sha256': canonical_digest(maps[target]),
        'source_identity_digest_encoding': 'SHA-256 of sorted compact JSON source records',
        'original_to_captured_main': changes(frozen, maps[MAIN]),
        'original_to_reviewed_combination': changes(frozen, maps[target]),
        'captured_main_to_reviewed_combination': changes(maps[MAIN], maps[target]),
        'production_changes': sorted(changed_production),
        'zotero_named_lib_or_test_changes': sorted(p for p in altered if 'zotero' in p and ('/lib/' in p or '/test/' in p)),
        'engine_word_library_changes': sorted(p for p in altered if p.startswith('packages/quds_office_engine/lib/src/word/')),
        'editor_library_changes': sorted(p for p in altered if p.startswith('packages/quds_office_editor/lib/')),
        'dependency_method': 'Lexical import/export/part URI scan, actual repository package resolution and all conditional alternatives; external packages are not traversed. Both original and combined selected transitive closures must have zero unresolved local directives, unsupported URI forms or possible same-line directives. The complete combined transitive closure is scanned for process/library loaders. This is a conservative source review, not a compiler trace or new test result.',
        'tracked_dart_libraries_scanned': len(graph),
        'repository_packages_resolved': package_count,
        'directive_completeness': {'original_closure_inputs': len(all_before_dependencies),
                                   'combined_closure_inputs': len(all_after_dependencies),
                                   'issues': directive_issues},
        'selected_suites': suites,
        'cohorts': cohort_rows,
        'transitive_closure_dynamic_loader_matches': dynamic_loaders,
        'transitive_closure_dynamic_loader_review': loader_reviews,
        'affected_suite_count': sum(bool(r['changed_production_dependencies']) for r in suites),
        'all_119_selected_test_sources_unchanged': all(r['test_source_unchanged'] for r in suites),
        'repeat_plan': {'suites': repeat_rows, 'expected_existing_cases': sum(r['original_passed_cases'] for r in repeat_rows),
                        'result': 'Pending separate execution receipts; repeated cases are not additional unique coverage'},
        'node': {'original_passed_cases': 121, 'original_capture_inputs': len(node_before),
                 'capture_changes': changes(old_node_map, new_node_map),
                 'selected_suites': node_rows,
                 'both_repository_closures_unchanged': len(node_rows) == 2 and all(r['repository_dependency_closure_unchanged'] for r in node_rows),
                 'applicability': 'Original Node test results retain source applicability to the two unchanged test dependency closures; the entire old broad engine capture is not identical.'},
        'additional_close_fix_regression': 'The combined checkpoint includes the added saved-Mail global Close regression in studio_saved_mail_test.dart. Its execution and the targeted Mail suites require separate receipts; they are outside the original 119-suite population.',
        'no_github_ci_used': True,
        'no_source_or_ref_mutations_by_replay': True,
    }
    encoded = json.dumps(report, indent=2, sort_keys=True) + '\n'
    if args.output:
        args.output.write_text(encoded)
    else:
        print(encoded, end='')


if __name__ == '__main__':
    main()

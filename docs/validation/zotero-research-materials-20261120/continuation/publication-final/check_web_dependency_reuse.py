#!/usr/bin/env python3
"""Read-only proof that the new direct web declaration needs no new resolution.

The saved package graph predates the direct Studio-to-web edge. This checker
states that limitation and compares every transitive closure with a virtual
graph containing the new edge. It does not rewrite or claim to regenerate the
package graph, package configuration, lockfile, SDK or package cache.
"""
from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import unquote, urljoin, urlparse

import yaml


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--before', required=True)
    parser.add_argument('--incoming', required=True)
    parser.add_argument('--previous-inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-head')
    parser.add_argument('--require-incoming-manifest', action='store_true')
    args = parser.parse_args()
    repo = args.repo.resolve()

    def git(*arguments):
        return subprocess.check_output(['git', *arguments], cwd=repo)

    def sha(data):
        return hashlib.sha256(data).hexdigest()

    before = git('rev-parse', args.before).decode().strip()
    incoming = git('rev-parse', args.incoming).decode().strip()
    head = git('rev-parse', 'HEAD').decode().strip()
    if args.expected_head:
        assert head == args.expected_head
    manifest = 'packages/quds_office_editor/example/pubspec.yaml'
    old_bytes = git('show', before+':'+manifest)
    new_bytes = git('show', incoming+':'+manifest)
    old = yaml.safe_load(old_bytes)
    new = yaml.safe_load(new_bytes)
    studio = old['name']
    assert studio == new['name']
    assert 'web' not in old['dependencies']
    constraint = new['dependencies']['web']
    virtual_manifest = copy.deepcopy(old)
    virtual_manifest['dependencies']['web'] = constraint
    assert virtual_manifest == new
    old_lock = git('show', before+':pubspec.lock')
    new_lock = git('show', incoming+':pubspec.lock')
    assert old_lock == new_lock
    locked_web = yaml.safe_load(new_lock)['packages']['web']
    assert constraint == '^'+locked_web['version'] == '^1.1.2'
    if args.require_incoming_manifest:
        assert (repo/manifest).read_bytes() == new_bytes
        assert (repo/'pubspec.lock').read_bytes() == new_lock

    config_path = repo/'.dart_tool/package_config.json'
    graph_path = repo/'.dart_tool/package_graph.json'
    config_bytes = config_path.read_bytes()
    graph_bytes = graph_path.read_bytes()
    config = {p['name']:p for p in json.loads(config_bytes)['packages']}
    graph = {p['name']:p for p in json.loads(graph_bytes)['packages']}
    assert 'web' not in graph[studio]['dependencies'], 'Graph no longer predates the direct edge'
    assert graph['web']['version'] == locked_web['version']
    virtual_graph = copy.deepcopy(graph)
    virtual_graph[studio]['dependencies'].append('web')

    def closure(catalog, root):
        reached = set()
        queue = [root, *catalog[root].get('devDependencies', [])]
        while queue:
            name = queue.pop()
            if name in reached:
                continue
            reached.add(name)
            queue.extend(catalog[name].get('dependencies', []))
        return sorted(reached)

    closures = {root:closure(graph, root) for root in graph}
    virtual_closures = {root:closure(virtual_graph, root) for root in graph}
    assert closures == virtual_closures
    assert 'web' in closures[studio]
    queue = [[studio]]
    seen = set()
    route = None
    while queue:
        trail = queue.pop(0)
        name = trail[-1]
        if name == 'web':
            route = trail
            break
        if name in seen:
            continue
        seen.add(name)
        queue.extend(trail+[p] for p in graph[name].get('dependencies', []))
    assert route

    web_root = Path(unquote(urlparse(urljoin(config_path.as_uri(), config['web']['rootUri'])).path))
    installed = yaml.safe_load((web_root/'pubspec.yaml').read_text())
    assert str(installed['version']) == locked_web['version']
    cache_hash = Path(os.environ['PUB_CACHE'])/'hosted-hashes/pub.dev'/f'web-{locked_web["version"]}.sha256'
    assert cache_hash.read_text().strip() == locked_web['description']['sha256']
    previous_path = args.previous_inputs.resolve()
    previous = json.loads(gzip.decompress(previous_path.read_bytes()))['before']
    web_inventory = previous['dependencies']['web']
    assert Path(web_inventory['root']) == web_root
    for name, record in web_inventory['files'].items():
        content = (web_root/name).read_bytes()
        assert len(content) == record['bytes'] and sha(content) == record['sha256'], name
    for name, record in previous['workspace'].items():
        content = (repo/name).read_bytes()
        assert len(content) == record['bytes'] and sha(content) == record['sha256'], name
    assert config_path.read_bytes() == config_bytes
    assert graph_path.read_bytes() == graph_bytes
    assert git('rev-parse', 'HEAD').decode().strip() == head
    result = {
        'status': 'passed',
        'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
        'source_head': head,
        'before_commit': before,
        'incoming_commit': incoming,
        'checkout_matches_incoming_manifest_required': args.require_incoming_manifest,
        'only_manifest_change': { 'package': studio, 'dependency': 'web', 'constraint': constraint },
        'lockfile_unchanged': True,
        'lockfile_sha256': sha(new_lock),
        'locked_web': locked_web,
        'configuration_web_root': str(web_root),
        'existing_studio_transitive_route': route,
        'saved_graph_contains_new_direct_edge': False,
        'saved_graph_attribution': 'Resolved before the new direct edge; reused unchanged. Every package dependency closure equals the graph with that edge added.',
        'compared_package_closures': len(closures),
        'all_virtual_closures_identical': True,
        'studio_closure': closures[studio],
        'all_closures_sha256': sha(json.dumps(closures,sort_keys=True,separators=(',',':')).encode()),
        'package_configuration_sha256': sha(config_bytes),
        'saved_package_graph_sha256': sha(graph_bytes),
        'previous_input_inventory': str(previous_path),
        'previous_input_inventory_sha256': sha(previous_path.read_bytes()),
        'rehashed_web_files': len(web_inventory['files']),
        'web_bytes_and_saved_workspace_metadata_match_previous_qualification': True,
        'resolution_config_sdk_cache_or_head_writes': False,
        'checker_sha256': sha(Path(__file__).read_bytes()),
    }
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    assert not output.exists()
    output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:result[k] for k in ['status','source_head','existing_studio_transitive_route','compared_package_closures','rehashed_web_files','resolution_config_sdk_cache_or_head_writes']}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

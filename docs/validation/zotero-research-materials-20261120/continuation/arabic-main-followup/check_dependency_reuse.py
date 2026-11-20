#!/usr/bin/env python3
"""Reuse exact resolved bytes while disclosing stale local-version metadata."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import unquote, urljoin, urlparse

import yaml

BEFORE = 'a45ee3bf40dbb7e64a04f879fd6d574db7cb60b1'
WEB_BASE = '214c4ed80bef0cb871f74e90c506d508679d3d6e'
WEB_CHECKER_SHA = '36ebcea3bba7a0fb2b27241208c5a873876bd7ac3886df1876baa1696c28f45b'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--expected-head',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    out = args.output.resolve()
    continuation = Path(__file__).resolve().parent.parent

    def git(*arguments):
        return subprocess.check_output(['git',*arguments],cwd=repo)

    def sha(data):
        return hashlib.sha256(data).hexdigest()

    head = git('rev-parse','HEAD').decode().strip()
    assert head == args.expected_head
    manifest = 'packages/quds_arabic_morph/pubspec.yaml'
    old_bytes = git('show',BEFORE+':'+manifest)
    new_bytes = git('show',head+':'+manifest)
    old = yaml.safe_load(old_bytes)
    new = yaml.safe_load(new_bytes)
    old_version = old.pop('version')
    new_version = new.pop('version')
    assert old_version == '0.2.0' and new_version == '0.3.0' and old == new
    assert (repo/manifest).read_bytes() == new_bytes
    old_lock = git('show',BEFORE+':pubspec.lock')
    new_lock = (repo/'pubspec.lock').read_bytes()
    assert old_lock == new_lock == git('show',head+':pubspec.lock')
    lock = yaml.safe_load(new_lock)
    config_path = repo/'.dart_tool/package_config.json'
    config_bytes = config_path.read_bytes()
    graph_path = repo/'.dart_tool/package_graph.json'
    graph_bytes = graph_path.read_bytes()
    config = {p['name']:p for p in json.loads(config_bytes)['packages']}
    graph = {p['name']:p for p in json.loads(graph_bytes)['packages']}
    roots = {name:Path(unquote(urlparse(urljoin(config_path.as_uri(),p['rootUri'])).path)) for name,p in config.items()}
    saved = graph['quds_arabic_morph']
    assert saved['version'] == old_version
    assert roots['quds_arabic_morph'] == repo/'packages/quds_arabic_morph'
    assert set(saved['dependencies']) == set(new['dependencies'])
    assert set(saved['devDependencies']) == set(new['dev_dependencies'])
    consumers = {}
    for name,root in roots.items():
        if not root.is_relative_to(repo):
            continue
        spec = yaml.safe_load((root/'pubspec.yaml').read_text())
        for section in ['dependencies','dev_dependencies','dependency_overrides']:
            if 'quds_arabic_morph' in spec.get(section,{}):
                declaration = spec[section]['quds_arabic_morph']
                assert isinstance(declaration,dict) and 'path' in declaration and 'version' not in declaration
                assert (root/declaration['path']).resolve() == roots['quds_arabic_morph']
                consumers[f'{name}:{section}'] = declaration
    assert consumers
    cache = Path(os.environ['PUB_CACHE'])
    hosted = []
    for name,record in lock['packages'].items():
        if record['source'] != 'hosted':
            continue
        installed = yaml.safe_load((roots[name]/'pubspec.yaml').read_text())
        assert str(installed['version']) == record['version'],name
        checksum = cache/'hosted-hashes/pub.dev'/f'{name}-{record["version"]}.sha256'
        assert checksum.read_text().strip() == record['description']['sha256'],name
        hosted.append(name)
    previous = continuation/'publication-followup/accepted-studio-pin/inputs.json.gz'
    baseline = json.loads(gzip.decompress(previous.read_bytes()))['before']
    counts = {'external_dependency_files':0,'runtime_files':0,'workspace_configuration_files':0}

    def verify(path,record,kind):
        data = path.read_bytes()
        assert len(data) == record['bytes'] and sha(data) == record['sha256'],str(path)
        counts[kind] += 1

    for package in baseline['dependencies'].values():
        for path,record in package['files'].items():
            verify(Path(package['root'])/path,record,'external_dependency_files')
    for path,record in baseline['runtime'].items():
        verify(Path(os.environ['FLUTTER_ROOT'])/path,record,'runtime_files')
    for path,record in baseline['workspace'].items():
        verify(repo/path,record,'workspace_configuration_files')
    web_checker = continuation/'publication-final/check_web_dependency_reuse.py'
    assert sha(web_checker.read_bytes()) == WEB_CHECKER_SHA
    assert not out.exists()
    out.parent.mkdir(parents=True,exist_ok=True)
    web_output = out.parent/'web-dependency-reuse.json'
    command = [sys.executable,str(web_checker),'--repo',str(repo),'--before',WEB_BASE,'--incoming',head,
               '--previous-inputs',str(previous),'--expected-head',head,'--require-incoming-manifest','--output',str(web_output)]
    subprocess.run(command,cwd=repo,check=True)
    web_proof = json.loads(web_output.read_text())
    assert web_proof['status'] == 'passed'
    assert config_path.read_bytes() == config_bytes and graph_path.read_bytes() == graph_bytes
    assert git('rev-parse','HEAD').decode().strip() == head
    result = {
        'status':'passed','recorded_at_utc':datetime.now(timezone.utc).isoformat(),'head':head,'prior_source':BEFORE,
        'manifest_path':manifest,'old_manifest_sha256':sha(old_bytes),'new_manifest_sha256':sha(new_bytes),
        'only_morph_manifest_change':'version','declared_version':new_version,'saved_graph_version':saved['version'],
        'saved_graph_attribution':'The graph was resolved at workspace package version0.2.0 and is reused unchanged. Current source declares0.3.0; the effective dependency edges and path mapping are identical. No graph regeneration is claimed.',
        'unchanged_morph_dependency_edges':saved['dependencies'],'unchanged_morph_dev_dependency_edges':saved['devDependencies'],
        'all_morph_consumers_use_unversioned_local_path':consumers,'lockfile_unchanged':True,'lockfile_sha256':sha(new_lock),
        'hosted_versions_and_archive_hashes_verified':len(hosted),'hosted_package_names':sorted(hosted),
        'prior_studio_web_edge_proof':{'path':str(web_output.relative_to(repo)),'sha256':sha(web_output.read_bytes()),
                                      'compared_closures':web_proof['compared_package_closures'],'saved_graph_contains_direct_edge':False},
        'previous_input_inventory':str(previous.relative_to(repo)),'previous_input_inventory_sha256':sha(previous.read_bytes()),
        'rehashed_unchanged_inputs':counts,'package_configuration_sha256':sha(config_bytes),'saved_package_graph_sha256':sha(graph_bytes),
        'resolution_sdk_package_cache_or_configuration_writes':False,
        'qualification_boundary':'Read-only Dart dependency/runtime reuse. Native ABI3/adapter2 artifacts, disambiguation models and WebAssembly execution are not built, downloaded or qualified by this check.',
        'checker_sha256':sha(Path(__file__).read_bytes()),'web_checker_sha256':WEB_CHECKER_SHA,'web_checker_command':command,
    }
    out.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:result[k] for k in ['status','head','declared_version','saved_graph_version','hosted_versions_and_archive_hashes_verified','rehashed_unchanged_inputs','resolution_sdk_package_cache_or_configuration_writes']}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

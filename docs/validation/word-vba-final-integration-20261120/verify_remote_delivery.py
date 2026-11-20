#!/usr/bin/env python3
"""Read back the delivered Git objects after an authorized remote merge."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument('repo')
    p.add_argument('delivered_head')
    p.add_argument('merge_commit')
    p.add_argument('captured_main')
    p.add_argument('output')
    a = p.parse_args()

    def git(*args):
        return subprocess.check_output(['git', '-C', a.repo, *args])

    def ancestor(older, newer):
        return subprocess.run(['git', '-C', a.repo, 'merge-base', '--is-ancestor', older, newer], check=False).returncode == 0

    heads = {
        'delivered_head': a.delivered_head,
        'captured_main': a.captured_main,
        'word_continuation': 'c12ad8bc9c17f1849acdf92b2245e9198f1005b8',
        'zotero_intake': '835b8019cbb873c72424e63d4df292174edd3c3e',
        'mail_actions': '9109fcc645d0d95fbe7a7568ddf1e0ebc07bc384',
        'mail_flags': 'fcc7bd27f7df6200ac7d3174f6e21097f931cca0',
    }
    remote_main = git('rev-parse', 'origin/main').decode().strip()
    ancestry = {name: {'sha': sha, 'ancestor_of_merge': ancestor(sha, a.merge_commit)} for name, sha in heads.items()}
    delivered_tree = git('rev-parse', a.delivered_head + '^{tree}').decode().strip()
    merged_tree = git('rev-parse', a.merge_commit + '^{tree}').decode().strip()
    compiler = 'packages/quds_office_engine/lib/src/automation/office_vba_language.dart'
    compiler_sha256 = hashlib.sha256(git('show', a.merge_commit + ':' + compiler)).hexdigest()
    expected_compiler = '41de865411b884d18c1097e9a80d68cd6bf1fb245e1844a46f72af05636f5ecd'
    differences = git('diff', '--name-status', a.delivered_head, a.merge_commit).decode().splitlines()
    result = {
        'schema': 1,
        'delivered_head': a.delivered_head,
        'delivered_tree': delivered_tree,
        'merge_commit': a.merge_commit,
        'merge_parents': git('show', '-s', '--format=%P', a.merge_commit).decode().split(),
        'merged_tree': merged_tree,
        'remote_main': remote_main,
        'merge_reachable_from_remote_main': ancestor(a.merge_commit, remote_main),
        'ancestry': ancestry,
        'tree_matches_delivered_head': delivered_tree == merged_tree,
        'differences_from_delivered_head': differences,
        'word_vba_compiler_sha256': compiler_sha256,
        'word_vba_compiler_preserved': compiler_sha256 == expected_compiler,
        'github_actions_queried_or_waited_for': False,
    }
    result['success'] = (all(item['ancestor_of_merge'] for item in ancestry.values())
                         and result['merge_reachable_from_remote_main']
                         and result['tree_matches_delivered_head']
                         and result['word_vba_compiler_preserved'])
    Path(a.output).write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['success'] else 1)


if __name__ == '__main__':
    main()

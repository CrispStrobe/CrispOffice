#!/usr/bin/env python3
"""Account for an immutable fetch snapshot without changing Git state.

Rerun with `python publish-ref-audit/audit.py`. Input is fetch-snapshot.json,
not a fresh network query. If an external head changes, its source/evidence
requires review; this program never reuses a reviewed disposition by name alone.
"""
from __future__ import annotations

import collections
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent
REPO = ROOT / 'quds_office_suite'
BASE = '4970f71f983535d045ce263e86835b499db4fda9'
CHECKPOINT = '81e478ca0ffe249a908362cd233790b8920d439c'
PROOF_COMMIT = '0fe53777c0bb1fe65950401b381cd6e18a6f4bd9'
PROOF_PATH = 'docs/validation/zotero-odt-images-20261121/intake/intake-accounting.json'


def git(*args: str) -> str:
    return subprocess.check_output(['git', *args], cwd=REPO, text=True).strip()


def raw_git(*args: str) -> bytes:
    return subprocess.check_output(['git', *args], cwd=REPO)


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def snapshot_rows(rows: list[str]) -> tuple[list[dict], list[dict]]:
    refs, aliases = [], []
    seen = set()
    for row in rows:
        name, head, *target = row.split()
        assert name not in seen, name
        assert re.fullmatch(r'[0-9a-f]{40}', head), head
        seen.add(name)
        value = {'ref': name, 'head': head}
        if target:
            assert len(target) == 1
            value['target'] = target[0]
            aliases.append(value)
        else:
            refs.append(value)
    return refs, aliases


def changed_paths(start: str, end: str) -> list[dict]:
    return [
        {'status': row.split('\t', 1)[0], 'path': row.split('\t', 1)[1]}
        for row in git('diff', '--no-renames', '--name-status', start, end).splitlines()
    ]


def index_entries(value: bytes) -> list[tuple[str, str, str, str]]:
    entries = []
    for row in value.split(b'\0'):
        if not row:
            continue
        header, path = row.split(b'\t', 1)
        mode, blob, stage = header.decode().split()
        entries.append((mode, blob, stage, path.decode()))
    return sorted(entries)


def tree_entries(tree: str) -> list[tuple[str, str, str, str]]:
    entries = []
    for row in raw_git('ls-tree', '-r', '-z', tree).split(b'\0'):
        if not row:
            continue
        header, path = row.split(b'\t', 1)
        mode, kind, blob = header.decode().split()
        assert kind in ('blob', 'commit')
        entries.append((mode, blob, '0', path.decode()))
    return sorted(entries)


REVIEWED_EXTERNAL = {
    'refs/remotes/origin/codex/word-vba-format-controls-20261121': {
        'reviewed_head': '37afb04e1167fe306e4d124368a08e372638f4ab',
        'record': 'docs/validation/word-vba-format-controls-20261121/README.md',
        'pending_pattern': r'not a completed feature\s+or qualification claim',
        'scope': 'Typed Word VBA paragraph shading, native paragraphShading operation, source-preserving solid/automatic backgrounds, and shared bounded Space/String/ChrW/AscW text construction.',
        'required_current_files': [
            'packages/quds_office_engine/lib/src/automation/operations/word_shading_steps.dart',
            'packages/quds_office_engine/test/office_macro_word_shading_test.dart',
            'packages/quds_office_engine/test/office_vba_word_shading_integration_test.dart',
            'packages/quds_office_engine/tool/macros/web_vba_word_shading_smoke.dart',
        ],
        'finding': 'The former missing-native-operation gap is resolved: 655b2722 adds the native implementation and registration plus shading deserialization/property merging. The latest merge retains concurrent intake without changing its first-parent package source. Product docs and the merge subject describe the implementation, but the exact-head qualification record still explicitly withholds a completed feature/qualification claim and contains no final execution receipt. Source presence is not a new test pass.',
        'readiness': 'Implementation exists; durable final qualification remains pending at this cutoff.',
        'recommendation': 'Preserve this remote branch separately until its final combined-source qualification is recorded. Do not describe it as compiler-only or reintroduce the resolved missing-operation finding.',
    },
    'refs/remotes/origin/codex/zotero-odt-roundtrip-20261121': {
        'reviewed_head': 'bf54a8e7d976670af87dd3d36f3afc26c1821d3b',
        'record': 'docs/validation/zotero-odt-roundtrip-20261121/README.md',
        'pending_pattern': r'Final combined validation and\s+external repeat-cycle checks remain pending',
        'scope': 'Native reopening of actual LibreOffice-saved editable Zotero ODT: inert inherited bibliography sections, validated unused sequence declarations, narrowly recognized LibreOffice zero-based note offsets with exact cached ordinals, bounded table border models, and correct editable-ODT absolute table alignment.',
        'required_current_files': [
            'packages/quds_office_engine/test/fixtures/zotero/odt/libreoffice-bibliography.odt',
            'packages/quds_office_engine/test/odt_libreoffice_bibliography_test.dart',
            'packages/quds_office_engine/test/odt_libreoffice_note_offsets_test.dart',
            'packages/quds_office_engine/test/odt_zotero_table_geometry_test.dart',
        ],
        'finding': 'This is now a source-and-regression checkpoint, not only an intake plan. Its saved record reports targeted development passes and reopening of an untouched prior LibreOffice bibliography artifact, while explicitly leaving final combined validation and external repeat-cycle checks pending. The active footnote separator is still rejected; table-only and endnote-only converter qualifications are separate planned work.',
        'readiness': 'Targeted implementation/development evidence exists; final combined and converter-cycle qualification remains pending.',
        'recommendation': 'Preserve separately at this cutoff. Its three ODT implementation files overlap the image milestone; combine both constructor/style/writer semantics deliberately and run affected tests after this continuation is ready. Do not duplicate or claim these fixes as already delivered by the image milestone.',
    },
    'refs/remotes/origin/work/mail-scheduled-send-20261121': {
        'reviewed_head': 'a4ff3da2feeb9b0b8ed53718c3143ab68c1c6c1b',
        'record': 'docs/validation/mail-scheduled-send-20261121/README.md',
        'pending_pattern': r'Implementation and final combined-source qualification are in progress',
        'scope': 'Durable UTC Outbox deadlines, eligibility and schedule-revision guards, backward-compatible payload-v3 persistence, and foundation regression tests for foreground scheduled sending.',
        'required_current_files': [
            'packages/quds_mail_core/test/outbox_schedule_test.dart',
            'packages/quds_mail_store/test/outbox_schedule_test.dart',
        ],
        'finding': 'The head now contains real Mail core/store work and records 482 core plus 107 store-cohort passing cases, clean analysis and formatting. The Studio workflow and final combined-source checks remain pending. Its inherited octopus checkpoint includes Word compiler 85033b80, but not the latest native Word continuation 655b2722 or 37afb04e; its own record requires that continuation before final main publication.',
        'readiness': 'Locally verified scheduling foundation; Studio and combined-source completion remain pending.',
        'recommendation': 'Preserve separately until the foreground Studio workflow and combined-source qualification are complete. Merging this head now would also import the older incomplete Word compiler snapshot.',
    },
}


def main() -> None:
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    before_head = git('rev-parse', 'HEAD')
    before_index = raw_git('ls-files', '--stage', '-z')
    fetch_bytes = (OUT / 'fetch-snapshot.json').read_bytes()
    pr_bytes = (OUT / 'pr-metadata.json').read_bytes()
    fetch = json.loads(fetch_bytes)
    pulls = json.loads(pr_bytes)
    assert len(fetch['fetches']) == 2
    assert all(row['exit_code'] == 0 for row in fetch['fetches'])
    assert fetch['before_checkout'] == fetch['after_checkout']
    assert fetch['before_index_tree'] == fetch['after_index_tree']

    refs, aliases = snapshot_rows(fetch['refs'])
    captured = {r['ref']: r['head'] for r in refs}
    remote_main = captured['refs/remotes/origin/main']
    assert captured['refs/remotes/origin/codex/zotero-roundtrip-20261121'] == CHECKPOINT
    ancestors_main = set(git('rev-list', remote_main).splitlines())
    ancestors_work = set(git('rev-list', CHECKPOINT).splitlines())
    assert BASE in ancestors_main
    assert PROOF_COMMIT in ancestors_work

    proof_bytes = raw_git('show', PROOF_COMMIT + ':' + PROOF_PATH)
    proof = json.loads(proof_bytes)
    assert proof['baseline'] == BASE
    historical = {
        (r['ref'], r['head']): r for r in proof['refs']
        if r['status'] in ('patch-equivalent', 'squash-merged')
    }
    assert len(historical) == 14
    initial = json.loads((ROOT / 'initial-ref-intake.json').read_text())
    original = {r['ref']: r['sha'] for r in initial['refs']}
    previous = json.loads((ROOT / 'final-ref-audit/ref-accounting.json').read_text())
    prior_heads = {r['ref']: r['head'] for r in previous['refs']}
    current_paths = {r['path'] for r in changed_paths(BASE, CHECKPOINT)}
    external = []

    for entry in refs:
        ref, sha = entry['ref'], entry['head']
        entry['initial_head'] = original.get(ref)
        entry['previous_audit_head'] = prior_heads.get(ref)
        entry['changed_since_initial'] = original.get(ref) != sha
        entry['changed_since_previous_audit'] = prior_heads.get(ref) != sha
        entry['ancestor_of_remote_main'] = sha in ancestors_main
        entry['ancestor_of_working_checkpoint'] = sha in ancestors_work
        if sha in ancestors_main:
            entry['status'] = 'actual-ancestor'
        elif (ref, sha) in historical:
            original_proof = historical[(ref, sha)]
            entry['status'] = 'retained-' + original_proof['status']
            entry['retained_proof'] = {
                'baseline': BASE,
                'exact_ref': ref,
                'exact_head': sha,
                'commit': PROOF_COMMIT,
                'path': PROOF_PATH,
                'file_sha256': digest(proof_bytes),
                'condition': 'Exact historical ref/head unchanged; its verified replacement remains in the remote-main baseline ancestry.',
            }
        elif sha == CHECKPOINT:
            entry['status'] = 'current-working-checkpoint'
        else:
            reviewed = REVIEWED_EXTERNAL.get(ref)
            entry['status'] = 'external-needs-review'
            entry['commits_since_main'] = [
                {'sha': h, 'parents': parents.split(), 'subject': subject}
                for row in git('log', '--format=%H%x09%P%x09%s', remote_main + '..' + sha).splitlines()
                for h, parents, subject in [row.split('\t', 2)]
            ]
            entry['changed_paths'] = changed_paths(BASE, sha)
            entry['changed_runtime_paths'] = [r['path'] for r in entry['changed_paths'] if '/lib/' in r['path']]
            entry['overlapping_working_runtime_paths'] = sorted(set(entry['changed_runtime_paths']) & current_paths)
            if reviewed is not None:
                record_bytes = raw_git('show', sha + ':' + reviewed['record'])
                record_text = record_bytes.decode()
                entry['qualification_record'] = {
                    'path': reviewed['record'],
                    'blob': git('rev-parse', sha + ':' + reviewed['record']),
                    'sha256': digest(record_bytes),
                    'content': record_text,
                }
                pending_match = re.search(reviewed['pending_pattern'], record_text)
                entry['pending_evidence_match'] = pending_match.group(0) if pending_match else None
                entry['reviewed_exact_head'] = reviewed['reviewed_head']
                entry['review_current'] = sha == reviewed['reviewed_head']
                if entry['review_current'] and pending_match:
                    for path in reviewed['required_current_files']:
                        git('cat-file', '-e', sha + ':' + path)
                    entry['status'] = 'external-in-progress'
                    for key in ('scope', 'finding', 'readiness', 'recommendation'):
                        entry[key] = reviewed[key]
            external.append(entry)

    by_ref = {r['ref']: r for r in refs}
    word = by_ref.get('refs/remotes/origin/codex/word-vba-format-controls-20261121')
    mail = by_ref.get('refs/remotes/origin/work/mail-scheduled-send-20261121')
    zotero = by_ref.get('refs/remotes/origin/codex/zotero-odt-roundtrip-20261121')
    if word and mail and zotero:
        mail_ancestors = set(git('rev-list', mail['head']).splitlines())
        word_ancestors = set(git('rev-list', word['head']).splitlines())
        relationships = {
            'mail_contains_word_compiler_85033b80': '85033b80f7e37a6562a4b86b486badc96ba84153' in mail_ancestors,
            'mail_contains_word_native_655b2722': '655b2722e9a11df4da129e2de36016f2f60b9c0b' in mail_ancestors,
            'mail_contains_latest_word_head': word['head'] in mail_ancestors,
            'mail_contains_latest_other_zotero_head': zotero['head'] in mail_ancestors,
            'word_contains_mail_intake_71dc9cc0': '71dc9cc0e3696096248b28b02b276dcc14c97f93' in word_ancestors,
            'word_contains_latest_mail_head': mail['head'] in word_ancestors,
            'word_merge_changed_package_files_from_first_parent': git('diff', '--name-only', word['head'] + '^1', word['head'], '--', 'packages').splitlines(),
        }
    else:
        relationships = {}

    for alias in aliases:
        alias['target_matches'] = captured.get(alias['target']) == alias['head']
        assert alias['target_matches']

    query_open = next(q for q in pulls['queries'] if 'state=open' in q['url'])
    recent = next(q for q in pulls['queries'] if 'state=all' in q['url'])
    recent_results = []
    for pr in recent['records']:
        recent_results.append({
            'number': pr['number'], 'state': pr['state'],
            'head': pr['head']['sha'], 'merge_commit': pr.get('merge_commit_sha'),
            'head_ancestor_of_main': pr['head']['sha'] in ancestors_main,
            'merge_ancestor_of_main': pr.get('merge_commit_sha') in ancestors_main,
            'merged_at': pr.get('merged_at'), 'url': pr['html_url'],
        })

    observed_refs = git('for-each-ref', '--format=%(refname) %(objectname) %(symref)', 'refs/remotes').splitlines()
    observed, observed_aliases = snapshot_rows(observed_refs)
    observed_map = {r['ref']: r['head'] for r in observed}
    live_ref_deltas = [
        {'ref': ref, 'snapshot_head': captured.get(ref), 'later_observed_head': observed_map.get(ref)}
        for ref in sorted(set(captured) | set(observed_map))
        if captured.get(ref) != observed_map.get(ref)
    ]
    before_matches_fetch_tree = index_entries(before_index) == tree_entries(fetch['after_index_tree'])
    after_index = raw_git('ls-files', '--stage', '-z')
    after_head = git('rev-parse', 'HEAD')
    counts = collections.Counter(r['status'] for r in refs)
    unreviewed = [r['ref'] for r in refs if r['status'] == 'external-needs-review']
    record = {
        'repository': 'CrispStrobe/quds_office_suite',
        'audit_started_at_utc': started,
        'audit_completed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'fetch_started_at_utc': fetch['observed_at_utc'],
        'fetch_completed_at_utc': fetch['completed_at_utc'],
        'starting_main': BASE, 'remote_main_at_cutoff': remote_main,
        'working_checkpoint': CHECKPOINT,
        'remote_main_changed_since_start': remote_main != BASE,
        'main_commits_since_start': git('log', '--format=%H %s', BASE + '..' + remote_main).splitlines(),
        'counts': {'nonalias_refs': len(refs), 'symbolic_aliases': len(aliases), **dict(counts)},
        'ref_namespace_counts': dict(collections.Counter(r['ref'].split('/')[2] for r in refs)),
        'all_ref_objects_present': True,
        'historical_proof_policy': 'Retain only exact unchanged ref/head pairs with committed independent patch/squash proof; do not replay those histories.',
        'historical_exception_count': sum(r['status'].startswith('retained-') for r in refs),
        'open_pr_count': len(query_open['records']),
        'recent_pr_count': len(recent_results), 'recent_pr_dispositions': recent_results,
        'changed_since_previous_audit': [r for r in refs if r['changed_since_previous_audit']],
        'external_assessments': external,
        'external_dependency_relationships': relationships,
        'refs': refs, 'symbolic_aliases': aliases,
        'later_live_ref_deltas_from_snapshot': live_ref_deltas,
        'missing_initial_refs': sorted(set(original) - set(captured)),
        'unreviewed_refs': unreviewed,
        'readonly_verification': {
            'both_fetch_commands_succeeded': True,
            'fetch_before_checkout': fetch['before_checkout'],
            'fetch_after_checkout': fetch['after_checkout'],
            'fetch_before_index_tree': fetch['before_index_tree'],
            'fetch_after_index_tree': fetch['after_index_tree'],
            'checkout_unchanged_during_fetch': fetch['before_checkout'] == fetch['after_checkout'],
            'index_tree_unchanged_during_fetch': fetch['before_index_tree'] == fetch['after_index_tree'],
            'audit_before_checkout': before_head, 'audit_after_checkout': after_head,
            'audit_before_index_manifest_sha256': digest(before_index),
            'audit_after_index_manifest_sha256': digest(after_index),
            'audit_start_index_matches_recorded_fetch_tree': before_matches_fetch_tree,
            'checkout_unchanged_during_audit': before_head == after_head,
            'index_unchanged_during_audit': before_index == after_index,
            'current_remote_refs_still_match_fetch_snapshot': observed_map == captured and observed_aliases == [{k: v for k, v in a.items() if k != 'target_matches'} for a in aliases],
            'display_failure': 'The reported TypeError occurred while printing the already-saved snapshot. Both recorded fetch exit codes are zero; before/after checkout and index trees agree. No failed fetch is inferred from the display error.',
            'git_mutations_performed_by_this_audit': [],
        },
        'evidence_sha256': {
            'fetch-snapshot.json': digest(fetch_bytes),
            'pr-metadata.json': digest(pr_bytes),
            'historical-proof-at-' + PROOF_COMMIT: digest(proof_bytes),
        },
        'recommendation': 'No completed external main/PR delta needs integration at this finite cutoff. Preserve all three real implementation continuations separately while their final qualification remains pending; complete the qualified image milestone and recheck the frontier before publication.',
        'limits': 'All origin branches/PR heads and upstream branches/PR heads were refreshed in the supplied successful fetch. This audit reads the immutable snapshot and Git objects only. No source/index/ref/remote mutations, new test executions, or GitHub CI/status/workflow queries were performed. Reported external test counts are saved branch evidence, not freshly executed tests.',
    }
    # Verify all captured heads resolve to local commit objects, including refs
    # not traversed by the main/checkpoint ancestor sets.
    checked = subprocess.run(
        ['git', 'cat-file', '--batch-check=%(objectname) %(objecttype)'],
        cwd=REPO, input='\n'.join(sorted({r['head'] for r in refs})) + '\n',
        text=True, capture_output=True, check=True,
    )
    assert all(line.endswith(' commit') for line in checked.stdout.splitlines())
    assert len(checked.stdout.splitlines()) == len({r['head'] for r in refs})
    (OUT / 'ref-accounting.json').write_text(json.dumps(record, indent=2) + '\n')

    review = [
        '# Publication-cutoff remote ref audit', '',
        f'Fetch cutoff: **{fetch["completed_at_utc"]}**. Both origin and upstream branch/PR-head fetches succeeded. The subsequent snapshot-print TypeError was a display failure; the snapshot is saved and checkout/index trees were unchanged.', '',
        f'Remote main at cutoff: `{remote_main}`; unchanged from starting main. Remote image checkpoint at cutoff: `{CHECKPOINT}`.', '',
        f'**{len(refs)} nonsymbolic refs plus {len(aliases)} symbolic alias are accounted for:** ' + ', '.join(f'{count} {name}' for name, count in counts.items()) + '.', '',
        f'Open PRs: **{len(query_open["records"])}**. All {len(recent_results)} saved recent PR heads and merge commits are already main ancestors. No initial ref is missing; the 14 historical exceptions retain their exact previously verified heads and committed proof.', '',
        '| External continuation | Exact head | Current evidence and disposition |',
        '|---|---|---|',
    ]
    for entry in external:
        review.append(f'| `{entry["ref"]}` | `{entry["head"]}` | {entry.get("finding", "Needs fresh review.")} **{entry.get("readiness", "Unreviewed")}** |')
    review += [
        '', '## Integration decision', '',
        'No external head has completed, durable final qualification at this cutoff. Preserve all three remote continuations; do not merge their unfinished aggregate into the image milestone. This classification is based on the current exact heads and their actual source/evidence, not the older plan-only checkpoints.', '',
        'The separate Zotero continuation overlaps `odt_document_reader.dart`, `odt_document_writer.dart`, and `odt_reader_styles.dart`. Its constructor changes for guarded LibreOffice note numbering must be combined with the image reader constructor, and both inherited-style and output changes must survive eventual integration. Its active footnote-separator refusal remains intentional. Finish its combined/external repeat-cycle checks before integrating that work.', '',
        'The Mail branch already contains the earlier Word compiler checkpoint but not the completed native Word implementation from `655b2722`. Its own record requires the later Word continuation before its final main publication. The latest Word merge incorporates the older Mail intake only, not the new Mail scheduling foundation.', '',
        '## Read-only verification', '',
        f'Fetch checkout remained `{fetch["before_checkout"]}`; index tree remained `{fetch["before_index_tree"]}`. Both before/after values match in the saved fetch receipt. Audit checkout was `{before_head}` before and `{after_head}` after; its index manifest was unchanged: **{before_index == after_index}**.', '',
        ('The audit independently matched the current stage-zero index entries to the fetch index tree.' if before_matches_fetch_tree else 'The checkout/index had advanced after the fetch cutoff before this audit ran. Its current stage-zero entries therefore do not equal the earlier fetch tree; that later state does not invalidate the fetch invariance proof or the immutable ref classification.'), '',
        ('No later live ref changed relative to the saved snapshot.' if not live_ref_deltas else 'Later live refs differ from this immutable snapshot; `later_live_ref_deltas_from_snapshot` records exact old/new heads. They are outside this cutoff and belong to root\'s later frontier check.'), '',
        'The recorded upstream PR heads were refreshed in this cutoff, unlike the preceding pre-qualification audit. No CI, status or workflow endpoint was queried. No source, index, Git ref, or remote state was changed by this audit. Only these scratch accounting files were written.', '',
        'Rerun `python publish-ref-audit/audit.py` to reproduce this snapshot accounting. A changed external head is flagged for fresh review instead of inheriting an old disposition. Root owns any newer frontier check and final integration decision.', '',
    ]
    (OUT / 'review.md').write_text('\n'.join(review))
    print(json.dumps({
        'cutoff': record['fetch_completed_at_utc'],
        'counts': record['counts'],
        'open_pr_count': record['open_pr_count'],
        'missing_initial_refs': record['missing_initial_refs'],
        'unreviewed_refs': unreviewed,
        'readonly_verification': record['readonly_verification'],
        'external_dependency_relationships': relationships,
    }, indent=2))


if __name__ == '__main__':
    main()

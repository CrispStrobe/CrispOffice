#!/usr/bin/env python3
"""Verify the additive PR #176 merge against the audited Mail publication."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

SOURCE = '5569c055a021c893e941fc54d40499ad9d96a5db'
BASE = '199690563b206948871ea0279f5e59f686265f8b'
PRIOR_MAIN = '55e262ef269634a0d618c0b5102dc9be5430a5f3'
MAIN = 'f059065fa622da8cee7824d66d29a2aff414d529'
DOC = 'packages/quds_mail_store/README.md'
PROOFING = {'docs/PROOFING.md', 'docs/roadmaps/arabic-proofing.md',
            'tools/proofing/ayaspell/build_bundle.py'}
HELPER = 'tools/proofing/ayaspell/build_bundle.py'
REPORT = 'docs/validation/office-main-completion-20261119/'
REVIEW = {REPORT + name for name in [
    'README.md', 'release/mail-tail-immutable-readback.json',
    'release/audit_proofing_tail.py', 'release/proofing-tail-review.json',
    'release/check_proofing_output_guard.py', 'release/proofing-output-guard.json']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()

    def git(*words):
        return subprocess.check_output(['git', '--no-replace-objects', *words], cwd=args.repo)

    def entries(ref):
        result = {}
        command = ('ls-files', '--stage', '-z') if ref == 'INDEX' else ('ls-tree', '-r', '-z', ref)
        for row in git(*command).decode().split('\0'):
            if not row:
                continue
            metadata, path = row.split('\t', 1)
            parts = metadata.split(' ')
            if ref == 'INDEX':
                mode, blob, stage = parts
                if stage != '0':
                    raise RuntimeError('Unresolved index path: ' + path)
            else:
                mode, kind, blob = parts
                if kind != 'blob':
                    raise RuntimeError('Unexpected non-blob: ' + path)
            result[path] = {'mode': mode, 'git_blob': blob}
        return result

    def changed(left, right):
        return {p for p in left.keys() | right.keys() if left.get(p) != right.get(p)}

    def digest(data):
        return hashlib.sha256(data).hexdigest()

    def read(path):
        return json.loads(path.read_text())

    baseline, source, incoming = entries(BASE), entries(SOURCE), entries(MAIN)
    target, previous = entries(args.target), entries(PRIOR_MAIN)
    proof = read(args.repo / REPORT / 'release/mail-tail-immutable-readback.json')
    issues = []
    if (not proof['passed'] or proof['issues'] or proof['checked_target']['commit'] != BASE
            or proof['qualified_execution_source'] != SOURCE
            or proof['distinct_bound_input_union'] != 5033
            or proof['unchanged_bound_inputs'] != 5032):
        issues.append('Prior immutable Mail readback identity failed')
    if changed(previous, incoming) != PROOFING:
        issues.append('Incoming main delta differs from the three reviewed proofing paths')
    target_delta = changed(baseline, target)
    if not PROOFING <= target_delta or target_delta - PROOFING - REVIEW:
        issues.append('Candidate delta contains missing or unreviewed paths')
    if any(target.get(path) != incoming[path] for path in PROOFING - {HELPER}):
        issues.append('Incoming proofing documentation is not retained exactly')

    union = set()
    for label in ['native', 'node']:
        union.update(read(args.workspace / ('qualification-release-' + label) / 'source-before.json'))
    union.update(read(args.workspace / 'qualification-release-store/results/receipt.json')['source_before'])
    union.update(read(args.workspace / 'qualification-release-support/receipt.json')['source_before'])
    baseline_bound = {p: baseline[p] for p in sorted(union)}
    fingerprint = digest(json.dumps(baseline_bound, sort_keys=True, separators=(',', ':')).encode())
    if fingerprint != proof['qualified_bound_entry_fingerprint_sha256']:
        issues.append('Prior immutable proof does not bind the reconstructed input union')
    if len(union) != 5033 or any(target.get(p) != baseline[p] for p in union):
        issues.append('Previously audited complete input union changed')
    if {p for p in union if source.get(p) != target.get(p)} != {DOC}:
        issues.append('Qualified source differs beyond the reviewed Store README')
    if union & PROOFING:
        issues.append('New proofing helper/docs overlap the frozen qualification inputs')
    parents = ([git('rev-parse', ref).decode().strip() for ref in ['HEAD', 'MERGE_HEAD']]
               if args.target == 'INDEX' else [git('rev-parse', args.target + '^{commit}').decode().strip()])
    history = {commit: any(subprocess.run(
        ['git', '--no-replace-objects', 'merge-base', '--is-ancestor', commit, parent],
        cwd=args.repo).returncode == 0 for parent in parents) for commit in [SOURCE, BASE, MAIN]}
    if not all(history.values()):
        issues.append('Candidate does not retain qualified source and both incoming histories')
    helper = git('cat-file', 'blob', target[HELPER]['git_blob'])
    compile(helper, HELPER, 'exec')
    guard = json.loads(git('cat-file', 'blob', target[REPORT + 'release/proofing-output-guard.json']['git_blob']))
    check_bytes = git('cat-file', 'blob', target[REPORT + 'release/check_proofing_output_guard.py']['git_blob'])
    if (not guard['passed'] or guard['issues'] or guard['helper_sha256'] != digest(helper)
            or guard['check_script_sha256'] != digest(check_bytes)
            or guard['network_or_publish_performed']
            or guard['added_to_application_or_python_qualification_totals'] != 0):
        issues.append('Standalone output-directory guard evidence does not bind the final helper')
    result = {
        'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'qualified_execution_source': SOURCE, 'previous_audited_publication': BASE,
        'incoming_main': MAIN, 'incoming_main_parent': PRIOR_MAIN,
        'checked_target': {'kind': 'resolved_index' if args.target == 'INDEX' else 'commit',
                           'history_roots': parents},
        'required_history_included': history,
        'proofing_paths': {p: {'incoming': incoming[p], 'final': target[p],
                               'retained_exactly': incoming[p] == target[p]} for p in sorted(PROOFING)},
        'qualification_input_overlap': sorted(union & PROOFING),
        'distinct_bound_input_union': len(union), 'inputs_identical_to_reviewed_mail_publication': len(union),
        'inputs_identical_to_qualified_execution_source': len(union) - 1,
        'reviewed_documentation_exception': DOC, 'bound_entry_fingerprint_sha256': fingerprint,
        'candidate_delta': sorted(target_delta),
        'helper_validation': 'Syntax compilation and isolated output-path checks with stubbed fetch; no download or publication',
        'reviewed_helper_change': 'Require a fresh output directory before any download/publication; reject existing paths',
        'helper_guard_receipt': REPORT + 'release/proofing-output-guard.json',
        'helper_sha256': digest(helper),
        'application_case_executions_preserved': 836, 'separate_python_controls_preserved': 78,
        'new_product_tests_or_ci_executed': False,
        'prior_runtime_verification': 'Inherited unchanged from the immutable Mail readback; no new runtime claim',
        'source_bound_audit_sha256': digest(Path(__file__).read_bytes()),
        'issues': issues, 'passed': not issues,
    }
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in [
        'checked_target', 'distinct_bound_input_union', 'inputs_identical_to_reviewed_mail_publication',
        'inputs_identical_to_qualified_execution_source', 'qualification_input_overlap', 'passed', 'issues']}, indent=2))
    raise SystemExit(0 if not issues else 1)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Review the captured macOS build delta without running native build tools."""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--base', required=True)
    parser.add_argument('--tree', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    here = Path(__file__).resolve().parent

    def git(*command):
        return subprocess.check_output(['git', '-C', str(repo), *command])

    def source(ref, path):
        return git('show', f'{ref}:{path}')

    base = git('rev-parse', args.base + '^{commit}').decode().strip()
    target = git('rev-parse', args.tree + '^{tree}').decode().strip()
    candidate = git('rev-parse', args.candidate + '^{commit}').decode().strip()
    assert git('rev-parse', candidate + '^{tree}').decode().strip() == target
    script_path = 'packages/quds_office_editor/example/tool/build_macos_app.sh'
    distribution = 'packages/quds_proofing_spacy/lib/src/distribution.dart'
    release_doc = 'docs/release/macos-signing.md'
    paths = sorted(filter(None, git(
        'diff', '--name-only', '--no-renames', '-z', base, target
    ).decode().split('\0')))
    assert paths == sorted([script_path, distribution, release_doc]), paths
    patch = git('diff', '--no-ext-diff', '--no-renames', base, target).decode()
    before = source(base, script_path).decode()
    script = source(target, script_path).decode()
    old_distribution = source(base, distribution).decode()
    new_distribution = source(target, distribution).decode()
    non_docs = lambda text: '\n'.join(
        line for line in text.splitlines() if not line.lstrip().startswith('///')
    )
    assert non_docs(old_distribution) == non_docs(new_distribution)
    pins = dict(re.findall(r'^(SPACY_PIN_[A-Z_0-9]+)=([^\s]+)$', script, re.M))
    old_pins = dict(re.findall(r'^(SPACY_PIN_[A-Z_0-9]+)=([^\s]+)$', before, re.M))
    assert pins == old_pins
    syntax = subprocess.run(['bash', '-n'], input=script.encode(), capture_output=True)
    assert syntax.returncode == 0, syntax.stderr.decode()

    input_start = 'if [[ "${QUDS_SKIP_SPACY:-0}" != 1 && "$REBUILD_SPACY" != 1 ]]; then\n'
    input_block = script[script.index(input_start):script.index('\nlog "Sign ($SIGN_MODE)"')]
    loop_start = 'for library in "${LIBRARIES[@]}"; do\n'
    loop_index = script.index(loop_start)
    signing_loop = script[loop_index:script.index('\ndone\n', loop_index) + len('\ndone\n')]
    post_start = 'if [[ "${QUDS_SKIP_SPACY:-0}" != 1 ]]; then\n  # Studio loads'
    post_index = script.index(post_start)
    post_block = script[post_index:script.index('\ncodesign "${SIGN_ARGS[@]}" --entitlements', post_index)]
    # Execute these exact extracted control-flow blocks with declared command
    # stubs. No codesign, Mach-O, signing, download, or native build is run.
    harness = '''set -euo pipefail
code_sha256() {
  if [[ "$PHASE" == before ]]; then printf '%s\n' "$MOCK_CODE_BEFORE";
  else printf '%s\n' "$MOCK_CODE_AFTER"; fi
}
unsigned_sha256() {
  printf 'unsigned|%s\n' "$PHASE" >> "$TRACE"
  if [[ "$PHASE" == before ]]; then printf '%s\n' "$MOCK_UNSIGNED_BEFORE";
  else printf '%s\n' "$MOCK_UNSIGNED_AFTER"; fi
}
shasum() { printf '%s  synthetic-library\n' "$MOCK_FILE_SHA"; }
codesign() {
  printf 'codesign|%s\n' "$*" >> "$TRACE"
  if [[ "${1:-}" == --verify ]]; then return "$MOCK_VERIFY_EXIT"; fi
}
LIBRARIES=(libother.dylib)
if [[ "$QUDS_SKIP_SPACY" != 1 ]]; then LIBRARIES+=(libcrispembed-spacy.dylib); fi
SIGN_ARGS=(--force --sign TEST)
PHASE=before
'''
    harness += input_block + '\n' + signing_loop + '\nPHASE=after\n' + post_block
    harness += '\nprintf "RESULT|%s\\n" "${SPACY_NOTE:-none}"\n'
    known_code = pins['SPACY_PIN_CODE_SHA256']
    known_unsigned = pins['SPACY_PIN_UNSIGNED_SHA256']
    known_file = pins['SPACY_PIN_SHA256']
    defaults = {
        'SIGN_MODE': 'developer-id', 'REBUILD_SPACY': '0', 'QUDS_SKIP_SPACY': '0',
        'MOCK_CODE_BEFORE': known_code, 'MOCK_CODE_AFTER': known_code,
        'MOCK_UNSIGNED_BEFORE': known_unsigned, 'MOCK_UNSIGNED_AFTER': known_unsigned,
        'MOCK_FILE_SHA': 'changed-signature-file', 'MOCK_VERIFY_EXIT': '0',
    }
    cases = [
        ('adhoc pinned bytes verified, not re-signed', {'SIGN_MODE': 'adhoc', 'MOCK_FILE_SHA': known_file}, 0, 'qualified (analysis', 1, 1),
        ('adhoc existing-signature failure stops build', {'SIGN_MODE': 'adhoc', 'MOCK_FILE_SHA': known_file, 'MOCK_VERIFY_EXIT': '7'}, 7, None, 1, 1),
        ('adhoc rebuild remains unqualified and is signed', {'SIGN_MODE': 'adhoc', 'REBUILD_SPACY': '1'}, 0, 'UNQUALIFIED rebuild', 0, 2),
        ('signed known code plus matching normalized bytes', {}, 0, 'qualified code', 0, 2),
        ('signed known code accepts unsupported strip normalization', {'MOCK_UNSIGNED_BEFORE': 'older-tool-input', 'MOCK_UNSIGNED_AFTER': 'older-tool-output'}, 0, 'qualified code', 0, 2),
        ('changed signed code is refused even without strip normalization', {'MOCK_UNSIGNED_BEFORE': 'older-tool-input', 'MOCK_CODE_AFTER': 'wrong-code'}, 1, None, 0, 2),
        ('normalized stripping mismatch is refused', {'MOCK_UNSIGNED_AFTER': 'wrong-stripped-bytes'}, 1, None, 0, 2),
        ('wrong input code fails before signing', {'MOCK_CODE_BEFORE': 'wrong-code'}, 1, None, 0, 0),
        ('signed rebuild cannot reuse code-only qualification', {'REBUILD_SPACY': '1'}, 0, 'UNQUALIFIED rebuild', 0, 2),
        ('explicit spaCy skip bypasses only spaCy work', {'QUDS_SKIP_SPACY': '1'}, 0, 'RESULT|none', 0, 1),
    ]
    import os
    outcomes = []
    with tempfile.TemporaryDirectory(prefix='shell-review-', dir=here) as temp:
        temporary = Path(temp)
        for index, (name, changed, exit_code, note, verifies, signs) in enumerate(cases):
            case_dir = temporary / str(index)
            case_dir.mkdir()
            trace = case_dir / 'trace'
            environment = os.environ.copy()
            environment.update(defaults)
            environment.update(changed)
            environment.update(pins)
            environment.update({'FRAMEWORKS': '/synthetic-frameworks', 'RESOURCES': str(case_dir), 'TRACE': str(trace)})
            result = subprocess.run(['bash'], input=harness.encode(), env=environment, capture_output=True)
            stdout, stderr = result.stdout.decode(), result.stderr.decode()
            calls = trace.read_text().splitlines() if trace.exists() else []
            verify_calls = [c for c in calls if c.startswith('codesign|--verify')]
            sign_calls = [c for c in calls if c.startswith('codesign|--force')]
            assert result.returncode == exit_code, (name, result.returncode, stderr)
            assert note is None or note in stdout, (name, stdout)
            assert len(verify_calls) == verifies, (name, calls)
            assert len(sign_calls) == signs, (name, calls)
            if name == 'signed known code accepts unsupported strip normalization':
                assert 'unsigned|after' not in calls
            outcomes.append({'name': name, 'exit_code': result.returncode, 'expected_exit_code': exit_code, 'stdout': stdout, 'stderr': stderr, 'stub_calls': calls, 'passed': True})

    rows = []
    for path in paths:
        rows.append({'path': path, 'before_blob': git('rev-parse', f'{base}:{path}').decode().strip(), 'after_blob': git('rev-parse', f'{target}:{path}').decode().strip()})
    result = {
        'status': 'passed', 'audited_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'base_candidate': base, 'merged_tree': target, 'candidate_commit': candidate,
        'incoming_commit': 'aeb1f09dfb4b61ca30f8b6f086f0c60cf0607cf9',
        'incoming_main': '3e5f44ae14926b8054b2e5c0558ce71477891a33',
        'delta': rows, 'complete_patch': patch,
        'distribution_all_non_documentation_lines_identical': True,
        'distribution_executable_tokens_unchanged': True,
        'all_script_pins_unchanged': True, 'pins': pins,
        'bash_syntax': {'exit_code': syntax.returncode, 'script_sha256': hashlib.sha256(script.encode()).hexdigest()},
        'shell_control_flow': {'source': 'Exact input gate, signing loop and post-signing qualification blocks extracted from the merged script.', 'command_stubs': ['code_sha256', 'unsigned_sha256', 'shasum', 'codesign'], 'fragment_sha256': hashlib.sha256(harness.encode()).hexdigest(), 'cases': outcomes, 'passed': len(outcomes)},
        'selected_test_read_dependency': {'path': 'packages/quds_office_editor/example/test/studio_spacy_pin_test.dart', 'cases': 1, 'action': 'Rerun on final merged checkout because it reads tool/build_macos_app.sh. Original selected test source and all pins are unchanged.'},
        'required_followup': ['Fresh one-file Studio pin test using the original test runner guards.', 'Fresh final static receipt because distribution.dart documentation bytes changed.'],
        'limitations': ['This review does not execute macOS codesign, native loading, release signing, or a native build.', 'The ten shell cases verify control-flow and gate handling with command stubs; they do not verify Apple tool behavior or cryptographic implementations.', 'Previous source and accepted receipts remain immutable and retain their original source attribution.'],
        'github_actions_queried': False, 'remote_refs_mutated': False,
        'verifier_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    }
    output = args.output or here / 'macos-build-review.json'
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'status': result['status'], 'delta_paths': len(paths), 'shell_cases_passed': len(outcomes), 'merged_tree': target}, indent=2))


if __name__ == '__main__':
    main()
